#!/usr/bin/env bash
# ==============================================================================
# lib/orchestrator/dag.sh - Directed Acyclic Graph (DAG) topological scheduler
#
# Resolves dependency orderings across multi-service topologies using Kahn's
# algorithm, detects circular dependency cycles, and computes concurrent tiers.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::dag_toposort
# Computes topological order of tasks/services given a dependency map.
# Arguments:
#   $1 - Dependency list in format: "NODE:DEP1,DEP2 NODE2:DEP1 NODE3:"
# Output:
#   Space-separated list of nodes in valid execution order on stdout
# ------------------------------------------------------------------------------
conduit::dag_toposort() {
    local raw_graph="$1"

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys
from collections import defaultdict, deque

graph_str = sys.argv[1]
adj = defaultdict(list)
in_degree = defaultdict(int)
all_nodes = set()

for item in graph_str.split():
    if not item:
        continue
    parts = item.split(':', 1)
    node = parts[0]
    all_nodes.add(node)
    deps = [d.strip() for d in parts[1].split(',') if d.strip()]
    for d in deps:
        all_nodes.add(d)
        adj[d].append(node)
        in_degree[node] += 1

queue = deque([n for n in all_nodes if in_degree[n] == 0])
order = []

while queue:
    curr = queue.popleft()
    order.append(curr)
    for neighbor in adj[curr]:
        in_degree[neighbor] -= 1
        if in_degree[neighbor] == 0:
            queue.append(neighbor)

if len(order) != len(all_nodes):
    sys.stderr.write('conduit: error: cyclic dependency detected in DAG\n')
    sys.exit(70) # ERR_DAG_CYCLE

print(' '.join(order))
" "${raw_graph}"
        return $?
    fi

    # Pure Bash fallback topological sort
    declare -A in_deg
    declare -A adj
    declare -A known_nodes

    local entry
    for entry in ${raw_graph}; do
        local node="${entry%%:*}"
        local deps="${entry#*:}"
        known_nodes["${node}"]=1
        in_deg["${node}"]=0

        local IFS=','
        local d
        for d in ${deps}; do
            [[ -z "${d}" ]] && continue
            known_nodes["${d}"]=1
            adj["${d}"]+="${node} "
            in_deg["${node}"]=$(( ${in_deg[${node}]:-0} + 1 ))
        done
    done

    # Find nodes with in-degree 0
    local -a queue=()
    for n in "${!known_nodes[@]}"; do
        if (( in_deg[${n}] == 0 )); then
            queue+=("${n}")
        fi
    done

    local -a order=()
    while (( ${#queue[@]} > 0 )); do
        local curr="${queue[0]}"
        queue=("${queue[@]:1}")
        order+=("${curr}")

        local neighbor
        for neighbor in ${adj[${curr}]:-}; do
            in_deg["${neighbor}"]=$(( in_deg["${neighbor}"] - 1 ))
            if (( in_deg["${neighbor}"] == 0 )); then
                queue+=("${neighbor}")
            fi
        done
    done

    if (( ${#order[@]} != ${#known_nodes[@]} )); then
        conduit::throw "${ERR_DAG_CYCLE}" "cyclic dependency detected in DAG graph"
        return $?
    fi

    echo "${order[*]}"
    return 0
}
