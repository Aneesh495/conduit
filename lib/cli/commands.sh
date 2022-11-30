#!/usr/bin/env bash
# ==============================================================================
# lib/cli/commands.sh - Conduit CLI subcommands and dispatcher engine
#
# Implements unified CLI commands (build, run, ps, exec, logs, stop, rm, images,
# stats, compose, doctor) with strict argument validation and structured output.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "core/platform"
conduit::import "crypto/sha256"
conduit::import "storage/cas"
conduit::import "storage/layer"
conduit::import "storage/cow_tree"
conduit::import "storage/image"
conduit::import "storage/volume"
conduit::import "supervisor/state"
conduit::import "supervisor/process"
conduit::import "supervisor/logs"
conduit::import "supervisor/health"
conduit::import "net/ipam"
conduit::import "net/proxy"
conduit::import "orchestrator/scheduler"
conduit::import "orchestrator/rolling"
conduit::import "provenance/slsa"
conduit::import "cli/table"
conduit::import "cli/progress"

# ------------------------------------------------------------------------------
# cmd: build
# ------------------------------------------------------------------------------
conduit::cmd_build() {
    local tag=""
    local src_path=""

    while (( $# > 0 )); do
        case "$1" in
            -t|--tag)
                tag="$2"
                shift 2
                ;;
            *)
                src_path="$1"
                shift
                ;;
        esac
    done

    if [[ -z "${src_path}" ]]; then
        echo "conduit: error: build requires a context directory or tarball" >&2
        return 1
    fi
    if [[ -z "${tag}" ]]; then
        tag="image_$(date +%s)"
    fi

    conduit::log_info "Building image '${tag}' from context '${src_path}'..."

    local layer_tar
    if [[ -f "${src_path}" ]]; then
        layer_tar="${src_path}"
    elif [[ -d "${src_path}" ]]; then
        layer_tar="/tmp/conduit_build_$$.tar"
        conduit::layer_pack "${src_path}" "${layer_tar}" || return 1
    else
        echo "conduit: error: invalid build context '${src_path}'" >&2
        return 1
    fi

    # Ingest layer into CAS store
    local layer_digest
    layer_digest="$(conduit::cas_put_file "${layer_tar}")" || return 1
    local layer_size
    layer_size="$(wc -c < "${layer_tar}" | tr -d ' ')"

    # Synthesize OCI manifest v2
    local manifest
    manifest="$(cat <<EOF
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.conduit.container.image.v1+json",
  "tag": "${tag}",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "architecture": "${CONDUIT_ARCH}",
  "os": "${CONDUIT_OS}",
  "config": {
    "cmd": ["/bin/sh"],
    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
    "workdir": "/"
  },
  "layers": [
    {
      "mediaType": "application/vnd.conduit.image.rootfs.diff.tar",
      "digest": "sha256:${layer_digest}",
      "size": ${layer_size}
    }
  ]
}
EOF
)"

    local image_id
    image_id="$(conduit::image_register "${tag}" "${manifest}")" || return 1

    # Generate SLSA provenance attestation
    local prov_file="${CONDUIT_IMAGES_DIR}/${image_id}.provenance.json"
    conduit::provenance_generate "${tag}" "${image_id}" "conduit build ${src_path}" "${layer_digest}" > "${prov_file}"

    conduit::log_info "Successfully built image '${tag}' (${image_id:0:12})"
    echo "${image_id}"
    return 0
}

# ------------------------------------------------------------------------------
# cmd: run
# ------------------------------------------------------------------------------
conduit::cmd_run() {
    local detach="false"
    local interactive="false"
    local container_name=""
    local hostname=""
    local mem_limit="0"
    local cpu_limit="0"
    local -a ports=()
    local -a volumes=()
    local -a env_vars=()
    local image=""

    while (( $# > 0 )); do
        case "$1" in
            -d|--detach) detach="true"; shift ;;
            -i|--interactive) interactive="true"; shift ;;
            -t|--tty) interactive="true"; shift ;;
            -it|-ti) interactive="true"; shift ;;
            --name) container_name="$2"; shift 2 ;;
            -h|--hostname) hostname="$2"; shift 2 ;;
            -m|--memory) mem_limit="$(conduit::parse_bytes "$2")"; shift 2 ;;
            --cpus) cpu_limit="$2"; shift 2 ;;
            -p|--publish) ports+=("$2"); shift 2 ;;
            -v|--volume) volumes+=("$2"); shift 2 ;;
            -e|--env) env_vars+=("$2"); shift 2 ;;
            *)
                if [[ -z "${image}" ]]; then
                    image="$1"
                    shift
                    break
                fi
                ;;
        esac
    done

    local -a cmd=("$@")

    if [[ -z "${image}" ]]; then
        echo "conduit: error: 'run' requires an image name or ID" >&2
        return 1
    fi

    # Resolve image ID
    local image_id
    image_id="$(conduit::image_resolve "${image}")" || {
        echo "conduit: error: image '${image}' not found" >&2
        return 1
    }

    # Generate container name and ID
    local cid
    cid="$(conduit::sha256_str "${image_id}_$(date +%s%N)_${RANDOM}")"
    if [[ -z "${container_name}" ]]; then
        container_name="conduit_${cid:0:12}"
    fi
    if [[ -z "${hostname}" ]]; then
        hostname="${container_name}"
    fi

    # Build command JSON array
    local cmd_json="[]"
    if (( ${#cmd[@]} > 0 )); then
        cmd_json="$(conduit::json_array_from_list "${cmd[@]}")"
    fi

    # Initialize container state
    conduit::state_create "${cid}" "${image_id}" "${container_name}" "${hostname}" "${cmd_json}" || return 1

    local container_dir="${CONDUIT_CONTAINERS_DIR}/${cid}"
    local rootfs="${container_dir}/rootfs"

    # Unpack base image layers into container rootfs
    conduit::image_unpack "${image_id}" "${rootfs}" || return 1

    # Setup volumes
    local v
    for v in "${volumes[@]}"; do
        read -r v_src v_dst v_ro < <(conduit::parse_mount_spec "${v}")
        local target_mnt="${rootfs}/${v_dst#/}"
        mkdir -p "${target_mnt}"
        # Hardlink or bind mount directory
        cp -al "${v_src}/." "${target_mnt}/" 2>/dev/null || cp -a "${v_src}/." "${target_mnt}/" 2>/dev/null || true
    done

    # Setup port forwarding proxies if detached
    local p
    for p in "${ports[@]}"; do
        read -r h_ip h_port c_port proto < <(conduit::parse_port_binding "${p}")
        if [[ "${h_port}" == "0" ]]; then
            h_port="$(conduit::port_allocate_ephemeral)"
        fi
        local proxy_pid_file="${container_dir}/state/proxy_${h_port}.pid"
        conduit::proxy_start "${h_ip}" "${h_port}" "127.0.0.1" "${c_port}" "${proxy_pid_file}"
    done

    # Configure resource cgroups
    conduit::cgroup_create "${cid}" "${mem_limit}" "${cpu_limit}" 1024

    # Execute container
    conduit::process_start "${cid}" "${detach}" "${interactive}"
}

# ------------------------------------------------------------------------------
# cmd: ps
# ------------------------------------------------------------------------------
conduit::cmd_ps() {
    local show_all="false"
    while (( $# > 0 )); do
        case "$1" in
            -a|--all) show_all="true"; shift ;;
            *) shift ;;
        esac
    done

    {
        echo "CONTAINER_ID IMAGE COMMAND CREATED STATUS PORTS NAMES"
        local c_dir
        for c_dir in "${CONDUIT_CONTAINERS_DIR}"/*; do
            [[ ! -d "${c_dir}" ]] && continue
            local s_file="${c_dir}/state.json"
            [[ ! -f "${s_file}" ]] && continue

            local cid cimage cstatus cname ccreated
            cid="$(conduit::json_get "id" "${s_file}")"
            cimage="$(conduit::json_get "image" "${s_file}")"
            cstatus="$(conduit::json_get "status" "${s_file}")"
            cname="$(conduit::json_get "name" "${s_file}")"
            ccreated="$(conduit::json_get "created" "${s_file}")"

            if [[ "${show_all}" != "true" && "${cstatus}" != "${STATE_RUNNING}" ]]; then
                continue
            fi

            echo "${cid:0:12} ${cimage:0:12} sh ${ccreated:0:10} ${cstatus} 0.0.0.0 ${cname}"
        done
    } | conduit::table_render
}

# ------------------------------------------------------------------------------
# cmd: exec
# ------------------------------------------------------------------------------
conduit::cmd_exec() {
    local interactive="false"
    while (( $# > 0 )); do
        case "$1" in
            -i|-t|-it|-ti) interactive="true"; shift ;;
            *) break ;;
        esac
    done

    local query="$1"
    shift

    local cid
    cid="$(conduit::state_resolve "${query}")" || {
        echo "conduit: error: container '${query}' not found" >&2
        return 1
    }

    local rootfs="${CONDUIT_CONTAINERS_DIR}/${cid}/rootfs"
    local hostname
    hostname="$(conduit::json_get "hostname" "${CONDUIT_CONTAINERS_DIR}/${cid}/state.json")"

    if [[ "${interactive}" == "true" ]]; then
        conduit::pty_run conduit::sandbox_spawn "${cid}" "${rootfs}" "${hostname}" "/" "bridge" "${CONDUIT_CONTAINERS_DIR}/${cid}/state" "$@"
    else
        conduit::sandbox_spawn "${cid}" "${rootfs}" "${hostname}" "/" "bridge" "${CONDUIT_CONTAINERS_DIR}/${cid}/state" "$@"
    fi
}

# ------------------------------------------------------------------------------
# cmd: logs
# ------------------------------------------------------------------------------
conduit::cmd_logs() {
    local follow="false"
    local tail_n="50"
    local query=""

    while (( $# > 0 )); do
        case "$1" in
            -f|--follow) follow="true"; shift ;;
            -n|--tail) tail_n="$2"; shift 2 ;;
            *) query="$1"; shift ;;
        esac
    done

    if [[ -z "${query}" ]]; then
        echo "conduit: error: 'logs' requires a container name or ID" >&2
        return 1
    fi

    if [[ "${follow}" == "true" ]]; then
        conduit::logs_follow "${query}" "${tail_n}"
    else
        conduit::logs_cat "${query}" "${tail_n}"
    fi
}

# ------------------------------------------------------------------------------
# cmd: stop
# ------------------------------------------------------------------------------
conduit::cmd_stop() {
    local query="$1"
    if [[ -z "${query}" ]]; then
        echo "conduit: error: 'stop' requires a container name or ID" >&2
        return 1
    fi
    conduit::process_stop "${query}" 10
}

# ------------------------------------------------------------------------------
# cmd: rm
# ------------------------------------------------------------------------------
conduit::cmd_rm() {
    local force="false"
    while (( $# > 0 )); do
        case "$1" in
            -f|--force) force="true"; shift ;;
            *) break ;;
        esac
    done

    local query="$1"
    local cid
    cid="$(conduit::state_resolve "${query}")" || {
        echo "conduit: error: container '${query}' not found" >&2
        return 1
    }

    local status
    status="$(conduit::state_get_status "${cid}")"
    if [[ "${status}" == "${STATE_RUNNING}" ]]; then
        if [[ "${force}" != "true" ]]; then
            echo "conduit: error: cannot remove running container '${query}'; stop it first or use -f" >&2
            return 1
        fi
        conduit::process_stop "${cid}" 2
    fi

    rm -rf "${CONDUIT_CONTAINERS_DIR:?}/${cid}"
    conduit::log_info "Removed container '${query}' (${cid:0:12})"
    echo "${cid:0:12}"
    return 0
}

# ------------------------------------------------------------------------------
# cmd: images
# ------------------------------------------------------------------------------
conduit::cmd_images() {
    conduit::image_list | conduit::table_render
}

# ------------------------------------------------------------------------------
# cmd: inspect
# ------------------------------------------------------------------------------
conduit::cmd_inspect() {
    local query="$1"
    # Check container first
    if local cid="$(conduit::state_resolve "${query}" 2>/dev/null)"; then
        cat "${CONDUIT_CONTAINERS_DIR}/${cid}/state.json"
        return 0
    fi
    # Check image
    if local iid="$(conduit::image_resolve "${query}" 2>/dev/null)"; then
        cat "${CONDUIT_IMAGES_DIR}/${iid}.json"
        return 0
    fi
    echo "conduit: error: no such container or image '${query}'" >&2
    return 1
}

# ------------------------------------------------------------------------------
# cmd: commit
# ------------------------------------------------------------------------------
conduit::cmd_commit() {
    local query="$1"
    local new_tag="$2"

    local cid
    cid="$(conduit::state_resolve "${query}")" || return 1

    local rootfs="${CONDUIT_CONTAINERS_DIR}/${cid}/rootfs"
    local delta_tar="/tmp/conduit_commit_$$.tar"

    conduit::layer_pack "${rootfs}" "${delta_tar}" || return 1
    local layer_hash
    layer_hash="$(conduit::cas_put_file "${delta_tar}")" || return 1
    local layer_size
    layer_size="$(wc -c < "${delta_tar}" | tr -d ' ')"

    local manifest
    manifest="$(cat <<EOF
{
  "schemaVersion": 2,
  "tag": "${new_tag}",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "layers": [
    {
      "mediaType": "application/vnd.conduit.image.rootfs.diff.tar",
      "digest": "sha256:${layer_hash}",
      "size": ${layer_size}
    }
  ]
}
EOF
)"

    local image_id
    image_id="$(conduit::image_register "${new_tag}" "${manifest}")"
    echo "${image_id}"
    return 0
}

# ------------------------------------------------------------------------------
# cmd: stats
# ------------------------------------------------------------------------------
conduit::cmd_stats() {
    {
        echo "CONTAINER_ID NAME CPU% MEM_USAGE PIDS"
        local c_dir
        for c_dir in "${CONDUIT_CONTAINERS_DIR}"/*; do
            [[ ! -d "${c_dir}" ]] && continue
            local s_file="${c_dir}/state.json"
            [[ ! -f "${s_file}" ]] && continue

            local cid cname cstatus cpid
            cid="$(conduit::json_get "id" "${s_file}")"
            cname="$(conduit::json_get "name" "${s_file}")"
            cstatus="$(conduit::json_get "status" "${s_file}")"
            cpid="$(conduit::json_get "pid" "${s_file}")"

            if [[ "${cstatus}" == "${STATE_RUNNING}" && -n "${cpid}" && "${cpid}" != "0" ]]; then
                # Query host process metrics via ps
                local cpu="0.0%"
                local mem="0.0 MiB"
                if ps -p "${cpid}" -o %cpu,rss >/dev/null 2>&1; then
                    read -r cpu mem_kb < <(ps -p "${cpid}" -o %cpu,rss | tail -n 1)
                    cpu="${cpu}%"
                    mem="$(conduit::format_bytes $(( mem_kb * 1024 )))"
                fi
                echo "${cid:0:12} ${cname} ${cpu} ${mem} 1"
            fi
        done
    } | conduit::table_render
}

# ------------------------------------------------------------------------------
# cmd: compose
# ------------------------------------------------------------------------------
conduit::cmd_compose() {
    local action="${1:-up}"
    local file="conduit-compose.yml"
    [[ ! -f "${file}" && -f "conduit-compose.yaml" ]] && file="conduit-compose.yaml"
    [[ ! -f "${file}" && -f "conduit-compose.json" ]] && file="conduit-compose.json"

    case "${action}" in
        up)
            conduit::compose_up "${file}"
            ;;
        down)
            conduit::compose_down "${file}"
            ;;
        *)
            echo "conduit: error: unknown compose action '${action}' (expected up, down)" >&2
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# cmd: doctor
# ------------------------------------------------------------------------------
conduit::cmd_doctor() {
    echo "=========================================================="
    echo " Conduit Host Virtualization Diagnostics & Health Report  "
    echo "=========================================================="
    conduit::platform_info
    echo ""
    echo "Required & Optional Tooling:"
    local tool
    for tool in bash tar gzip shasum sha256sum openssl curl nc lsof clang cc python3; do
        if command -v "${tool}" >/dev/null 2>&1; then
            printf "  %-12s [FOUND] (%s)\n" "${tool}" "$(command -v "${tool}")"
        else
            printf "  %-12s [OPTIONAL MISSING]\n" "${tool}"
        fi
    done
    echo ""
    echo "Runtime Storage Hierarchy:"
    echo "  State Root:        ${CONDUIT_STATE_DIR}"
    echo "  Images Store:      ${CONDUIT_IMAGES_DIR}"
    echo "  Containers:        ${CONDUIT_CONTAINERS_DIR}"
    echo "  CAS Blobs:         ${CONDUIT_BLOB_DIR}"
    echo "=========================================================="
}
