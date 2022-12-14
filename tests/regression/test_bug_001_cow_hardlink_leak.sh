#!/usr/bin/env bash
# ==============================================================================
# tests/regression/test_bug_001_cow_hardlink_leak.sh
#
# Bug Description:
#   In userspace copy-on-write trees, modifying a container file without
#   breaking hardlinks directly mutates the immutable base image layer.
#
# Regression Fix:
#   conduit::cow_break_link checks inode link count and replaces the hardlinked
#   target with an unlinked private copy before any mutation occurs.
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "storage/cow_tree"

run_tests() {
    test_plan 3

    local base_layer="${TEST_TMP_DIR}/bug1_base"
    local cnt_rootfs="${TEST_TMP_DIR}/bug1_cnt"
    local cnt_state="${TEST_TMP_DIR}/bug1_state"

    mkdir -p "${base_layer}"
    echo "PRISTINE_BASE_DATA" > "${base_layer}/config.env"

    # Initialize shadow tree
    conduit::cow_init_tree "${base_layer}" "${cnt_rootfs}" "${cnt_state}"

    # Target file
    local target="${cnt_rootfs}/config.env"

    # Execute link break
    conduit::cow_break_link "${target}" "${cnt_state}/journal.log"

    # Mutate container file
    echo "CONTAMINATED_DATA" > "${target}"

    assert_eq "$(cat "${target}")" "CONTAMINATED_DATA" "container file successfully updated"
    assert_eq "$(cat "${base_layer}/config.env")" "PRISTINE_BASE_DATA" "base layer data is completely untouched and preserved"
    assert_file_exists "${cnt_state}/journal.log" "CoW link break logged in transaction journal"

    test_summary
}

run_tests
