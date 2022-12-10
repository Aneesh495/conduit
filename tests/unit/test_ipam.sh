#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_ipam.sh - IP address management unit tests
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "net/ipam"

run_tests() {
    test_plan 4

    # Test sequential IP allocation
    local ip1 ip2
    ip1="$(conduit::ipam_allocate "testnet" "container_1")"
    ip2="$(conduit::ipam_allocate "testnet" "container_2")"

    assert_eq "${ip1}" "10.88.0.2" "first allocated IP is 10.88.0.2"
    assert_eq "${ip2}" "10.88.0.3" "second allocated IP increments sequentially to 10.88.0.3"

    # Test static IP collision
    assert_false "conduit::ipam_allocate 'testnet' 'container_3' '10.88.0.2'" "ipam_allocate rejects duplicate IP"

    # Test IP release and re-allocation
    conduit::ipam_release "testnet" "container_1"
    local ip_reused
    ip_reused="$(conduit::ipam_allocate "testnet" "container_4")"
    assert_eq "${ip_reused}" "10.88.0.2" "released IP is reclaimed by next allocator"

    test_summary
}

run_tests
