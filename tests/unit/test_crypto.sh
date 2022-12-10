#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_crypto.sh - Cryptographic primitives test suite
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "crypto/sha256"
conduit::import "crypto/hmac"
conduit::import "crypto/hex"
conduit::import "crypto/base64"

run_tests() {
    test_plan 8

    # NIST SHA-256 test vectors
    assert_eq "$(conduit::sha256_str "")" \
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" \
        "sha256 empty string matches NIST vector"

    assert_eq "$(conduit::sha256_str "abc")" \
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" \
        "sha256 'abc' matches NIST vector"

    # HMAC-SHA256 test vector (key: "secret", data: "conduit")
    local hmac_out
    hmac_out="$(conduit::hmac_sha256 "secret" "conduit")"
    assert_eq "${#hmac_out}" "64" "hmac-sha256 produces 64-char hex digest"

    # Hex encoding & decoding roundtrip
    local raw="conduit-engine"
    local hex
    hex="$(echo -n "${raw}" | conduit::hex_encode)"
    assert_eq "${hex}" "636f6e647569742d656e67696e65" "hex encode matches expected"
    local decoded
    decoded="$(echo -n "${hex}" | conduit::hex_decode)"
    assert_eq "${decoded}" "${raw}" "hex decode roundtrip preserved string"

    # Base64 encoding & decoding roundtrip
    local b64
    b64="$(echo -n "${raw}" | conduit::base64_encode)"
    assert_eq "${b64}" "Y29uZHVpdC1lbmdpbmU=" "base64 encode matches standard RFC 4648"
    local b64_decoded
    b64_decoded="$(echo -n "${b64}" | conduit::base64_decode)"
    assert_eq "${b64_decoded}" "${raw}" "base64 decode roundtrip preserved string"

    # File hashing verification
    local tmp_file="${TEST_TMP_DIR}/test_hash.txt"
    echo -n "conduit" > "${tmp_file}"
    assert_true "conduit::sha256_verify '${tmp_file}' '$(conduit::sha256_str "conduit")'" "sha256_verify validates matching file digest"

    test_summary
}

run_tests
