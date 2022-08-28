#!/usr/bin/env bash
# ==============================================================================
# lib/crypto/base64.sh - RFC 4648 Base64 encoding and decoding primitives
#
# Provides standard base64 encoding/decoding with padding and newline control,
# utilizing native system binaries with pure Bash fallback algorithms.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::base64_encode
# Encodes stdin or arguments into standard base64 format without line wraps.
# ------------------------------------------------------------------------------
conduit::base64_encode() {
    if (( $# > 0 )); then
        printf "%s" "$*" | conduit::base64_encode
        return 0
    fi

    if command -v base64 >/dev/null 2>&1; then
        # Check if base64 supports -w 0 (GNU) or default no wrap
        base64 | tr -d '\n'
    elif command -v openssl >/dev/null 2>&1; then
        openssl base64 -e -A
    else
        # Pure Bash RFC 4648 Base64 encoder
        local b64_chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local LC_ALL=C
        local byte1 byte2 byte3
        local o1 o2 o3 o4
        local n

        while true; do
            byte1=""
            byte2=""
            byte3=""
            IFS= read -r -d '' -n 1 byte1 || true
            [[ -z "${byte1}" ]] && break
            IFS= read -r -d '' -n 1 byte2 || true
            IFS= read -r -d '' -n 1 byte3 || true

            local b1 b2 b3
            printf -v b1 "%d" "'${byte1}"
            b2=0
            b3=0
            [[ -n "${byte2}" ]] && printf -v b2 "%d" "'${byte2}"
            [[ -n "${byte3}" ]] && printf -v b3 "%d" "'${byte3}"

            o1=$(( (b1 >> 2) & 0x3F ))
            o2=$(( ((b1 & 0x03) << 4) | ((b2 >> 4) & 0x0F) ))
            o3=$(( ((b2 & 0x0F) << 2) | ((b3 >> 6) & 0x03) ))
            o4=$(( b3 & 0x3F ))

            printf "%s%s" "${b64_chars:o1:1}" "${b64_chars:o2:1}"

            if [[ -z "${byte2}" ]]; then
                printf "=="
                break
            elif [[ -z "${byte3}" ]]; then
                printf "%s=" "${b64_chars:o3:1}"
                break
            else
                printf "%s%s" "${b64_chars:o3:1}" "${b64_chars:o4:1}"
            fi
        done
    fi
}

# ------------------------------------------------------------------------------
# conduit::base64_decode
# Decodes base64 stream from stdin or argument to raw bytes.
# ------------------------------------------------------------------------------
conduit::base64_decode() {
    local b64_str
    if (( $# > 0 )); then
        b64_str="$*"
    else
        b64_str="$(cat)"
    fi
    b64_str="${b64_str//[[:space:]]/}"

    if command -v base64 >/dev/null 2>&1; then
        # Try macOS -D then GNU -d
        printf "%s" "${b64_str}" | (base64 -d 2>/dev/null || base64 -D 2>/dev/null)
    elif command -v openssl >/dev/null 2>&1; then
        printf "%s" "${b64_str}" | openssl base64 -d -A
    else
        echo "conduit: error: base64 decoder requires base64 or openssl utility" >&2
        return 1
    fi
}
