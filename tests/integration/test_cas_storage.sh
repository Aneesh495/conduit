#!/usr/bin/env bash
# ==============================================================================
# tests/integration/test_cas_storage.sh - Content-addressable storage integration tests
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "storage/cas"

run_tests() {
    test_plan 5

    # Create sample payload
    local sample_file="${TEST_TMP_DIR}/payload.txt"
    echo "conduit content-addressable storage payload test" > "${sample_file}"

    # Ingest file into CAS
    local digest
    digest="$(conduit::cas_put_file "${sample_file}")"
    assert_eq "${#digest}" "64" "cas_put_file returns 64-char hex digest"

    # Verify blob file existence in CAS hierarchy
    local blob_path
    blob_path="$(conduit::cas_path "${digest}")"
    assert_file_exists "${blob_path}" "blob exists in storage hierarchy at cas_path"

    # Deduplication test: re-ingesting identical content returns same digest
    local digest_dup
    digest_dup="$(conduit::cas_put_file "${sample_file}")"
    assert_eq "${digest_dup}" "${digest}" "cas_put_file deduplicates identical blobs"

    # Verify read retrieval
    local content
    content="$(conduit::cas_get "${digest}")"
    assert_contains "${content}" "conduit content-addressable" "cas_get retrieves original blob content"

    # Integrity verification
    assert_true "conduit::cas_verify_all" "cas_verify_all confirms all stored blobs match their hash"

    test_summary
}

run_tests
