#!/usr/bin/env bash
# ==============================================================================
# tests/regression/test_bug_006_whiteout_opaque_dir.sh
#
# Bug Description:
#   Opaque directory markers (.wh..wh..opq) were being removed before
#   underlying files were completely masked.
#
# Regression Fix:
#   Two-phase directory scanner preserves mask order then purges marker.
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "storage/whiteout"

run_tests() {
    test_plan 2

    local rootfs="${TEST_TMP_DIR}/opaque_rootfs"
    mkdir -p "${rootfs}/opt/myapp"
    touch "${rootfs}/opt/myapp/legacy.txt"
    touch "${rootfs}/opt/myapp/.wh..wh..opq"

    conduit::whiteout_apply "${rootfs}"

    assert_false "[[ -f '${rootfs}/opt/myapp/.wh..wh..opq' ]]" "opaque marker cleanly removed after processing"
    assert_dir_exists "${rootfs}/opt/myapp" "containing directory preserved after opaque scan"

    test_summary
}

run_tests
