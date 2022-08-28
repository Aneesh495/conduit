#!/usr/bin/env bash
# ==============================================================================
# lib/crypto/hex.sh - Hexadecimal encoding and decoding utilities
#
# Provides deterministic conversion between raw binary streams, ASCII strings,
# and lowercase hexadecimal representations with optional host tool acceleration.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::hex_encode
# Encodes standard input or given string to lowercase hexadecimal.
# ------------------------------------------------------------------------------
conduit::hex_encode() {
    if (( $# > 0 )); then
        printf "%s" "$*" | conduit::hex_encode
        return 0
    fi

    if command -v xxd >/dev/null 2>&1; then
        xxd -p -c 256 | tr -d '\n'
    elif command -v hexdump >/dev/null 2>&1; then
        hexdump -ve '1/1 "%02x"'
    elif command -v od >/dev/null 2>&1; then
        od -An -tx1 -v | tr -d ' \n'
    else
        # Pure Bash fallback character-by-character conversion
        local LC_ALL=C
        local byte
        while IFS= read -r -d '' -n 1 byte; do
            printf "%02x" "'${byte}"
        done
    fi
}

# ------------------------------------------------------------------------------
# conduit::hex_decode
# Decodes hexadecimal string from standard input to raw bytes.
# ------------------------------------------------------------------------------
conduit::hex_decode() {
    local hex_data
    if (( $# > 0 )); then
        hex_data="$*"
    else
        hex_data="$(cat)"
    fi
    # Strip whitespace
    hex_data="${hex_data//[[:space:]]/}"

    if command -v xxd >/dev/null 2>&1; then
        printf "%s" "${hex_data}" | xxd -r -p
    else
        # Pure Bash fallback using octal/hex escape printing
        local i len="${#hex_data}"
        for (( i = 0; i < len; i += 2 )); do
            printf "\\x${hex_data:i:2}"
        done
    fi
}
