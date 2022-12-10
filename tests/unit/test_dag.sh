#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_dag.sh - DAG topological sorting and cycle detection tests
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "orchestrator/dag"

run_tests() {
    test_plan 4

    # Linear dependency graph: frontend depends on backend, backend depends on db
    local linear_graph="frontend:backend backend:db db:"
    local sorted
    sorted="$(conduit::dag_toposort "${linear_graph}")"
    assert_eq "${sorted}" "db backend frontend" "dag_toposort resolves linear dependency chain"

    # Diamond dependency graph: d depends on b and c; b and c depend on a
    local diamond_graph="d:b,c b:a c:a a:"
    local diamond_sorted
    diamond_sorted="$(conduit::dag_toposort "${diamond_graph}")"
    assert_contains "${diamond_sorted}" "a" "diamond sort contains root node a"
    # Root a must precede b, c, and d
    local -a nodes=(${diamond_sorted})
    assert_eq "${nodes[0]}" "a" "root dependency 'a' is scheduled strictly first"

    # Cyclic dependency detection: a depends on b, b depends on a
    local cyclic_graph="a:b b:a"
    assert_false "conduit::dag_toposort '${cyclic_graph}'" "dag_toposort detects two-node cycle and returns error"

    test_summary
}

run_tests
