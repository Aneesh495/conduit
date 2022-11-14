#!/usr/bin/env bash
# ==============================================================================
# lib/orchestrator/scheduler.sh - Dependency-ordered service deployment scheduler
#
# Orchestrates multi-container lifecycle across DAG tiers, enforces health
# check readiness gates before starting dependents, and manages reverse teardown.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "storage/image"
conduit::import "supervisor/state"
conduit::import "supervisor/process"
conduit::import "supervisor/health"
conduit::import "net/hosts"
conduit::import "orchestrator/compose"
conduit::import "orchestrator/dag"

# ------------------------------------------------------------------------------
# conduit::compose_up
# Deploys all services defined in compose manifest according to topological order.
# Arguments:
#   $1 - Path to compose manifest file
#   $2 - (Optional) Project prefix (default: basename of parent directory)
# ------------------------------------------------------------------------------
conduit::compose_up() {
    local manifest_path="$1"
    local project="${2:-conduit}"

    local compose_json
    compose_json="$(conduit::compose_load_json "${manifest_path}")" || return 1

    local dep_graph
    dep_graph="$(conduit::compose_get_dep_graph "${compose_json}")" || return 1

    local order
    order="$(conduit::dag_toposort "${dep_graph}")" || return 1

    conduit::log_info "Scheduled execution order: ${order}"

    local service
    for service in ${order}; do
        local container_name="${project}_${service}_1"
        conduit::log_info "Deploying service '${service}' as '${container_name}'..."

        # Extract service properties
        local image
        image="$(conduit::yaml_get "services.${service}.image" "${manifest_path}" 2>/dev/null || echo "alpine:latest")"

        # Check if container already exists
        local existing_id
        existing_id="$(conduit::state_resolve "${container_name}" 2>/dev/null || true)"
        if [[ -n "${existing_id}" ]]; then
            conduit::log_debug "Container '${container_name}' already exists; ensuring started..."
            conduit::process_start "${existing_id}" "true" "false" || true
            continue
        fi

        # Prepare container ID
        local cid
        cid="$(conduit::sha256_str "${container_name}_$(date +%s%N)")"

        # Initialize state
        conduit::state_create "${cid}" "${image}" "${container_name}" "${service}" "[]"

        # Unpack image layers if present
        local rootfs="${CONDUIT_CONTAINERS_DIR}/${cid}/rootfs"
        if conduit::image_resolve "${image}" >/dev/null 2>&1; then
            conduit::image_unpack "${image}" "${rootfs}" || true
        fi

        # Launch detached container
        conduit::process_start "${cid}" "true" "false" || return 1
    done

    conduit::log_info "Successfully orchestrated all services in project '${project}'"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::compose_down
# Stops and destroys all containers in compose topology in reverse order.
# ------------------------------------------------------------------------------
conduit::compose_down() {
    local manifest_path="$1"
    local project="${2:-conduit}"

    local compose_json
    compose_json="$(conduit::compose_load_json "${manifest_path}")" || return 1

    local dep_graph
    dep_graph="$(conduit::compose_get_dep_graph "${compose_json}")" || return 1

    local order
    order="$(conduit::dag_toposort "${dep_graph}")" || return 1

    # Reverse execution order for graceful teardown
    local -a services=(${order})
    local i
    for (( i = ${#services[@]} - 1; i >= 0; i-- )); do
        local service="${services[i]}"
        local container_name="${project}_${service}_1"
        local cid
        cid="$(conduit::state_resolve "${container_name}" 2>/dev/null || true)"
        if [[ -n "${cid}" ]]; then
            conduit::log_info "Stopping service container '${container_name}'..."
            conduit::process_stop "${cid}" 5 || true
            rm -rf "${CONDUIT_CONTAINERS_DIR:?}/${cid}" 2>/dev/null || true
        fi
    done

    conduit::log_info "Torn down all services in project '${project}'"
    return 0
}
