#!/usr/bin/env bash
# ==============================================================================
# tests/integration/test_whiteout.sh - OCI whiteout marker processing integration
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "storage/whiteout"

run_tests() {
    test_plan 4

    local rootfs="${TEST_TMP_DIR}/wh_rootfs"
    mkdir -p "${rootfs}/etc"
    touch "${rootfs}/etc/obsolete.conf"
    touch "${rootfs}/etc/active.conf"

    assert_file_exists "${rootfs}/etc/obsolete.conf" "file exists prior to whiteout"

    # Create whiteout deletion marker
    touch "${rootfs}/etc/.wh.obsolete.conf"
    assert_file_exists "${rootfs}/etc/.wh.obsolete.conf" "whiteout marker created"

    # Apply whiteouts
    conduit::whiteout_apply "${rootfs}"

    assert_false "[[ -f '${rootfs}/etc/obsolete.conf' ]]" "obsolete.conf successfully unlinked by whiteout"
    assert_false "[[ -f '${rootfs}/etc/.wh.obsolete.conf' ]]" "whiteout marker itself cleaned from rootfs"

    test_summary
}

run_tests
