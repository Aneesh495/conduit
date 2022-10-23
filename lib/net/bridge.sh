#!/usr/bin/env bash
# ==============================================================================
# lib/net/bridge.sh - Linux virtual bridge and veth pair network synthesis
#
# Creates kernel virtual ethernet (veth) pairs, attaches host interfaces to
# the conduit bridge, configures IP addresses, and enables NAT masquerading.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"
conduit::import "core/platform"

export CONDUIT_BRIDGE_NAME="conduit0"

# ------------------------------------------------------------------------------
# conduit::bridge_ensure
# Initializes the host bridge device and assigns default gateway IP.
# ------------------------------------------------------------------------------
conduit::bridge_ensure() {
    if ! conduit::is_linux || [[ "${CONDUIT_IS_ROOT}" != "true" ]]; then
        return 0
    fi

    if ! ip link show "${CONDUIT_BRIDGE_NAME}" >/dev/null 2>&1; then
        ip link add "${CONDUIT_BRIDGE_NAME}" type bridge || return 1
        ip addr add 10.88.0.1/16 dev "${CONDUIT_BRIDGE_NAME}" || return 1
        ip link set "${CONDUIT_BRIDGE_NAME}" up || return 1

        # Enable IPv4 forwarding and NAT masquerade
        sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
        iptables -t nat -A POSTROUTING -s 10.88.0.0/16 ! -o "${CONDUIT_BRIDGE_NAME}" -j MASQUERADE 2>/dev/null || true
        conduit::log_info "Initialized Linux bridge '${CONDUIT_BRIDGE_NAME}' with gateway 10.88.0.1/16"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# conduit::bridge_attach_veth
# Synthesizes veth pair and attaches container end into target network namespace.
# ------------------------------------------------------------------------------
conduit::bridge_attach_veth() {
    local container_id="$1"
    local pid="$2"
    local ip_addr="$3"

    if ! conduit::is_linux || [[ "${CONDUIT_IS_ROOT}" != "true" ]]; then
        return 0
    fi

    conduit::bridge_ensure || return 1

    local short_id="${container_id:0:8}"
    local host_veth="veth${short_id}"
    local peer_veth="peer${short_id}"

    # Create veth pair
    ip link add "${host_veth}" type veth peer name "${peer_veth}" || return 1
    ip link set "${host_veth}" master "${CONDUIT_BRIDGE_NAME}" || return 1
    ip link set "${host_veth}" up || return 1

    # Move peer veth into container namespace
    ip link set "${peer_veth}" netns "${pid}" name eth0 || return 1

    # Configure interface inside container namespace
    nsenter -t "${pid}" -n ip addr add "${ip_addr}/16" dev eth0 || return 1
    nsenter -t "${pid}" -n ip link set eth0 up || return 1
    nsenter -t "${pid}" -n ip link set lo up || return 1
    nsenter -t "${pid}" -n ip route add default via 10.88.0.1 dev eth0 || return 1

    conduit::log_debug "Plumbed veth pair '${host_veth}' -> eth0 (${ip_addr}) in netns PID ${pid}"
    return 0
}
