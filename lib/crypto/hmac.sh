#!/usr/bin/env bash
# ==============================================================================
# lib/crypto/hmac.sh - HMAC-SHA256 message authentication codes
#
# Generates cryptographic message authentication codes (RFC 2104) for image
# signature verification, provenance attestations, and tamper detection.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::hmac_sha256
# Computes HMAC-SHA256 digest of input data using secret key.
# Arguments:
#   $1 - Secret key string
#   $2 - (Optional) Message string; if omitted, reads message from stdin
# ------------------------------------------------------------------------------
conduit::hmac_sha256() {
    local key="$1"
    local message="${2:-}"

    if command -v openssl >/dev/null 2>&1; then
        if (( $# >= 2 )); then
            printf "%s" "${message}" | openssl dgst -sha256 -hmac "${key}" | awk '{print $NF}'
        else
            openssl dgst -sha256 -hmac "${key}" | awk '{print $NF}'
        fi
        return 0
    elif command -v python3 >/dev/null 2>&1; then
        if (( $# >= 2 )); then
            python3 -c "import hmac, hashlib, sys; print(hmac.new(sys.argv[1].encode('utf-8'), sys.argv[2].encode('utf-8'), hashlib.sha256).hexdigest())" "${key}" "${message}"
        else
            python3 -c "import hmac, hashlib, sys; print(hmac.new(sys.argv[1].encode('utf-8'), sys.stdin.buffer.read(), hashlib.sha256).hexdigest())" "${key}"
        fi
        return 0
    else
        echo "conduit: error: hmac_sha256 requires openssl or python3" >&2
        return 1
    fi
}
