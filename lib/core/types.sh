#!/usr/bin/env bash
# ==============================================================================
# lib/core/types.sh - Contract assertions, type guards, and semantic parsers
#
# Provides strict runtime type checking and deterministic parsing of resource
# quantities (memory, time durations, CIDR networks, port bindings).
# ==============================================================================

# ------------------------------------------------------------------------------
# Type predicates
# ------------------------------------------------------------------------------

conduit::is_int() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

conduit::is_uint() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

conduit::is_bool() {
    case "$1" in
        true|false|1|0|yes|no) return 0 ;;
        *) return 1 ;;
    esac
}

conduit::to_bool() {
    case "$1" in
        true|1|yes|y) echo "true" ;;
        *) echo "false" ;;
    esac
}

conduit::is_alphanumeric() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

conduit::is_hex() {
    [[ "$1" =~ ^[0-9a-fA-F]+$ ]]
}

conduit::is_valid_id() {
    # Valid container or image ID: 12 to 64 hexadecimal characters
    local id="$1"
    [[ "${#id}" -ge 12 && "${#id}" -le 64 && "${id}" =~ ^[0-9a-fA-F]+$ ]]
}

conduit::is_valid_image_name() {
    # e.g., "alpine", "library/ubuntu", "my-registry.io/app:v1.2.0"
    local name="$1"
    [[ "${name}" =~ ^[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)*(:[a-zA-Z0-9_.-]+)?$ ]]
}

conduit::is_valid_ipv4() {
    local ip="$1"
    local regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
    if [[ "${ip}" =~ ${regex} ]]; then
        local o1="${BASH_REMATCH[1]}"
        local o2="${BASH_REMATCH[2]}"
        local o3="${BASH_REMATCH[3]}"
        local o4="${BASH_REMATCH[4]}"
        if (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 )); then
            return 0
        fi
    fi
    return 1
}

conduit::is_valid_cidr() {
    local cidr="$1"
    if [[ "${cidr}" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/([0-9]{1,2})$ ]]; then
        local ip="${BASH_REMATCH[1]}"
        local prefix="${BASH_REMATCH[2]}"
        if conduit::is_valid_ipv4 "${ip}" && (( prefix >= 0 && prefix <= 32 )); then
            return 0
        fi
    fi
    return 1
}

# ------------------------------------------------------------------------------
# Resource Quantity Parsers
# ------------------------------------------------------------------------------

# Converts memory strings (e.g., 512k, 256m, 2g, 1073741824) to raw bytes
conduit::parse_bytes() {
    local val="$1"
    if [[ -z "${val}" ]]; then
        echo "0"
        return 0
    fi

    # Check for raw integer
    if [[ "${val}" =~ ^[0-9]+$ ]]; then
        echo "${val}"
        return 0
    fi

    local num unit
    if [[ "${val}" =~ ^([0-9]+)([kKmMgGtTpP])([bB])?$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        unit="$(echo "${unit}" | tr '[:upper:]' '[:lower:]')"
        case "${unit}" in
            k) echo "$(( num * 1024 ))" ;;
            m) echo "$(( num * 1024 * 1024 ))" ;;
            g) echo "$(( num * 1024 * 1024 * 1024 ))" ;;
            t) echo "$(( num * 1024 * 1024 * 1024 * 1024 ))" ;;
            *) echo "${val}" ;;
        esac
        return 0
    fi

    echo "conduit: error: invalid byte quantity '${val}'" >&2
    return 1
}

# Formats raw bytes to human-readable string (e.g., 1048576 -> "1.00 MiB")
conduit::format_bytes() {
    local bytes="$1"
    if ! conduit::is_uint "${bytes}"; then
        echo "0 B"
        return 0
    fi

    if (( bytes < 1024 )); then
        echo "${bytes} B"
    elif (( bytes < 1048576 )); then
        local kb=$(( bytes * 100 / 1024 ))
        printf "%d.%02d KiB\n" $(( kb / 100 )) $(( kb % 100 ))
    elif (( bytes < 1073741824 )); then
        local mb=$(( bytes * 100 / 1048576 ))
        printf "%d.%02d MiB\n" $(( mb / 100 )) $(( mb % 100 ))
    else
        local gb=$(( bytes * 100 / 1073741824 ))
        printf "%d.%02d GiB\n" $(( gb / 100 )) $(( gb % 100 ))
    fi
}

# Converts duration strings (e.g., 500ms, 10s, 5m, 2h) to integer seconds
conduit::parse_duration_seconds() {
    local dur="$1"
    if [[ -z "${dur}" ]]; then
        echo "0"
        return 0
    fi

    if [[ "${dur}" =~ ^[0-9]+$ ]]; then
        echo "${dur}"
        return 0
    fi

    if [[ "${dur}" =~ ^([0-9]+)(s|m|h|d)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "${unit}" in
            s) echo "${num}" ;;
            m) echo "$(( num * 60 ))" ;;
            h) echo "$(( num * 3600 ))" ;;
            d) echo "$(( num * 86400 ))" ;;
        esac
        return 0
    fi

    echo "conduit: error: invalid duration format '${dur}'" >&2
    return 1
}

# ------------------------------------------------------------------------------
# Port Binding Parser
# Formats: "8080:80", "127.0.0.1:8080:80", "8080:80/tcp", "53:53/udp"
# Output on stdout: HOST_IP HOST_PORT CONTAINER_PORT PROTOCOL
# ------------------------------------------------------------------------------
conduit::parse_port_binding() {
    local spec="$1"
    local proto="tcp"

    # Extract protocol if specified
    if [[ "${spec}" =~ /([a-zA-Z0-9]+)$ ]]; then
        proto="${BASH_REMATCH[1]}"
        spec="${spec%/*}"
    fi

    local host_ip="0.0.0.0"
    local host_port=""
    local container_port=""

    local colons
    colons="${spec//[^:]/}"
    local count="${#colons}"

    if [[ "${count}" -eq 0 ]]; then
        # Just container port: e.g. "80" -> host port ephemeral (0)
        host_port="0"
        container_port="${spec}"
    elif [[ "${count}" -eq 1 ]]; then
        # Host:Container: e.g. "8080:80"
        host_port="${spec%%:*}"
        container_port="${spec##*:}"
    elif [[ "${count}" -eq 2 ]]; then
        # HostIP:HostPort:ContainerPort: e.g. "127.0.0.1:8080:80"
        host_ip="${spec%%:*}"
        local rest="${spec#*:}"
        host_port="${rest%%:*}"
        container_port="${rest##*:}"
    else
        echo "conduit: error: invalid port specification '${spec}'" >&2
        return 1
    fi

    if ! conduit::is_uint "${host_port}" || ! conduit::is_uint "${container_port}"; then
        echo "conduit: error: ports must be unsigned integers in '${spec}'" >&2
        return 1
    fi

    if (( host_port > 65535 || container_port > 65535 || container_port == 0 )); then
        echo "conduit: error: port numbers out of valid range (1-65535) in '${spec}'" >&2
        return 1
    fi

    echo "${host_ip} ${host_port} ${container_port} ${proto}"
    return 0
}

# ------------------------------------------------------------------------------
# Strict Contract Assertions
# ------------------------------------------------------------------------------

conduit::assert_str() {
    local val="$1"
    local msg="${2:-assertion failed: expected non-empty string}"
    if [[ -z "${val}" ]]; then
        echo "conduit: contract violation: ${msg}" >&2
        return 1
    fi
    return 0
}

conduit::assert_int() {
    local val="$1"
    local msg="${2:-assertion failed: expected integer, got '${val}'}"
    if ! conduit::is_int "${val}"; then
        echo "conduit: contract violation: ${msg}" >&2
        return 1
    fi
    return 0
}

conduit::assert_file() {
    local path="$1"
    local msg="${2:-assertion failed: expected regular file at '${path}'}"
    if [[ ! -f "${path}" ]]; then
        echo "conduit: contract violation: ${msg}" >&2
        return 1
    fi
    return 0
}

conduit::assert_dir() {
    local path="$1"
    local msg="${2:-assertion failed: expected directory at '${path}'}"
    if [[ ! -d "${path}" ]]; then
        echo "conduit: contract violation: ${msg}" >&2
        return 1
    fi
    return 0
}
