#!/usr/bin/env bash
# ==============================================================================
# tests/integration/test_cow_tree.sh - Copy-on-Write shadow tree integration tests
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "storage/cow_tree"

run_tests() {
    test_plan 4

    # Setup immutable base layer directory
    local base_dir="${TEST_TMP_DIR}/base_layer"
    mkdir -p "${base_dir}/etc"
    echo "VERSION=1.0" > "${base_dir}/etc/version"
    echo "ORIGINAL" > "${base_dir}/data.txt"

    # Synthesize CoW shadow tree
    local container_rootfs="${TEST_TMP_DIR}/cnt_rootfs"
    local container_state="${TEST_TMP_DIR}/cnt_state"
    conduit::cow_init_tree "${base_dir}" "${container_rootfs}" "${container_state}"

    assert_file_exists "${container_rootfs}/data.txt" "shadow tree materialized data.txt"
    assert_file_exists "${container_rootfs}/etc/version" "shadow tree materialized nested directory"

    # Execute CoW link breaking
    local target_file="${container_rootfs}/data.txt"
    conduit::cow_break_link "${target_file}" "${container_state}/cow_journal.log"

    # Mutate container file
    echo "MUTATED_INSIDE_CONTAINER" > "${target_file}"

    assert_eq "$(cat "${target_file}")" "MUTATED_INSIDE_CONTAINER" "container file mutated successfully"
    assert_eq "$(cat "${base_dir}/data.txt")" "ORIGINAL" "base layer file remains strictly immutable"

    test_summary
}

run_tests
