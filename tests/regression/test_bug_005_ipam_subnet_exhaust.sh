#!/usr/bin/env bash
# ==============================================================================
# tests/regression/test_bug_005_ipam_subnet_exhaust.sh
#
# Bug Description:
#   When IP lease pools are exhausted, allocation loop wraps around or stalls.
#
# Regression Fix:
#   Explicit upper boundary checks return ERR_IPAM_EXHAUSTED immediately.
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "net/ipam"

run_tests() {
    test_plan 1

    conduit::ipam_init "exhaust_net"
    local leases="${CONDUIT_NETWORKS_DIR}/exhaust_net/leases.txt"

    # Simulate full subnet leases
    local i
    for (( i = 2; i < 254; i++ )); do
        echo "10.88.0.${i} mock_cid 0" >> "${leases}"
    done

    # Allocation should fail with error
    assert_false "conduit::ipam_allocate 'exhaust_net' 'new_container'" "ipam_allocate cleanly fails when subnet is full"

    test_summary
}

run_tests
