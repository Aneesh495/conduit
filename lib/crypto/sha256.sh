#!/usr/bin/env bash
# ==============================================================================
# lib/crypto/sha256.sh - Cryptographic SHA-256 digest computation and validation
#
# Computes cryptographic SHA-256 digests for arbitrary file paths, memory
# streams, and strings, with cross-platform acceleration and integrity guards.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::sha256_stream
# Computes SHA-256 hexadecimal hash of stdin stream.
# ------------------------------------------------------------------------------
conduit::sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 | awk '{print $NF}'
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())"
    else
        echo "conduit: error: sha256 requires sha256sum, shasum, openssl, or python3" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# conduit::sha256_file
# Computes SHA-256 hexadecimal digest of target file.
# Arguments:
#   $1 - Path to regular file
# ------------------------------------------------------------------------------
conduit::sha256_file() {
    local file_path="$1"
    if [[ ! -f "${file_path}" ]]; then
        echo "conduit: error: file not found '${file_path}'" >&2
        return 1
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file_path}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file_path}" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "${file_path}" | awk '{print $NF}'
    else
        conduit::sha256_stream < "${file_path}"
    fi
}

# ------------------------------------------------------------------------------
# conduit::sha256_str
# Computes SHA-256 digest of argument string without trailing newline.
# ------------------------------------------------------------------------------
conduit::sha256_str() {
    printf "%s" "$*" | conduit::sha256_stream
}

# ------------------------------------------------------------------------------
# conduit::sha256_verify
# Verifies if file matches expected SHA-256 digest.
# Arguments:
#   $1 - Path to file
#   $2 - Expected 64-char hex digest
# Returns:
#   0 if matches, 1 if mismatch or error
# ------------------------------------------------------------------------------
conduit::sha256_verify() {
    local file_path="$1"
    local expected_hash="$2"

    local actual_hash
    actual_hash="$(conduit::sha256_file "${file_path}")" || return 1

    actual_hash="$(echo "${actual_hash}" | tr '[:upper:]' '[:lower:]')"
    expected_hash="$(echo "${expected_hash}" | tr '[:upper:]' '[:lower:]')"

    if [[ "${actual_hash}" == "${expected_hash}" ]]; then
        return 0
    else
        echo "conduit: integrity failure: digest mismatch for '${file_path}'" >&2
        echo "  expected: ${expected_hash}" >&2
        echo "  actual:   ${actual_hash}" >&2
        return 1
    fi
}
