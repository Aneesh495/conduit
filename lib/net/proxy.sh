#!/usr/bin/env bash
# ==============================================================================
# lib/net/proxy.sh - Userspace bidirectional TCP port-forwarding proxy daemon
#
# Multiplexes inbound host TCP connections to container service ports across
# macOS Darwin and rootless Linux without requiring iptables kernel privileges.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::proxy_start
# Launches a background port-forwarding proxy daemon.
# Arguments:
#   $1 - Host binding IP (e.g., "0.0.0.0" or "127.0.0.1")
#   $2 - Host binding TCP port
#   $3 - Target destination IP
#   $4 - Target destination TCP port
#   $5 - File path to store background proxy PID
# ------------------------------------------------------------------------------
conduit::proxy_start() {
    local host_ip="$1"
    local host_port="$2"
    local target_ip="$3"
    local target_port="$4"
    local pid_file="$5"

    mkdir -p "$(dirname "${pid_file}")"

    # Prefer python3 socket forwarder for performance and zero fork overhead
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import socket, sys, threading

src_host, src_port = sys.argv[1], int(sys.argv[2])
dst_host, dst_port = sys.argv[3], int(sys.argv[4])

def forward(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((src_host, src_port))
srv.listen(128)

while True:
    client, _ = srv.accept()
    try:
        remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote.connect((dst_host, dst_port))
        threading.Thread(target=forward, args=(client, remote), daemon=True).start()
        threading.Thread(target=forward, args=(remote, client), daemon=True).start()
    except Exception:
        client.close()
" "${host_ip}" "${host_port}" "${target_ip}" "${target_port}" >/dev/null 2>&1 &

        local p_pid=$!
        echo "${p_pid}" > "${pid_file}"
        conduit::log_debug "Started TCP proxy ${host_ip}:${host_port} -> ${target_ip}:${target_port} (PID ${p_pid})"
        return 0
    fi

    # Fallback using nc and named pipe (FIFO)
    local fifo="/tmp/conduit_proxy_${host_port}_$$.fifo"
    rm -f "${fifo}"
    mkfifo "${fifo}"

    (
        while true; do
            nc -l -p "${host_port}" < "${fifo}" | nc "${target_ip}" "${target_port}" > "${fifo}" 2>/dev/null || break
        done
        rm -f "${fifo}"
    ) &
    local p_pid=$!
    echo "${p_pid}" > "${pid_file}"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::proxy_stop
# Terminates the background port-forwarding proxy.
# ------------------------------------------------------------------------------
conduit::proxy_stop() {
    local pid_file="$1"
    if [[ -f "${pid_file}" ]]; then
        local p_pid
        p_pid="$(cat "${pid_file}" 2>/dev/null || true)"
        if [[ -n "${p_pid}" ]] && kill -0 "${p_pid}" 2>/dev/null; then
            kill -15 "${p_pid}" 2>/dev/null || true
            sleep 0.1
            kill -9 "${p_pid}" 2>/dev/null || true
        fi
        rm -f "${pid_file}"
    fi
}
