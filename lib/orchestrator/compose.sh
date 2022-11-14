#!/usr/bin/env bash
# ==============================================================================
# lib/orchestrator/compose.sh - Multi-service compose specification loader
#
# Parses multi-container service topology manifests, extracts service dependency
# graphs, validates volume/port bindings, and constructs execution plans.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "json/parser"
conduit::import "yaml/parser"
conduit::import "orchestrator/dag"

# ------------------------------------------------------------------------------
# conduit::compose_load_json
# Loads compose manifest (YAML or JSON) into canonical JSON.
# ------------------------------------------------------------------------------
conduit::compose_load_json() {
    local manifest_path="$1"
    if [[ ! -f "${manifest_path}" ]]; then
        conduit::throw "${ERR_FILE_NOT_FOUND}" "compose file not found '${manifest_path}'"
        return $?
    fi

    if [[ "${manifest_path}" == *.json ]]; then
        cat "${manifest_path}"
    else
        conduit::yaml_to_json "${manifest_path}"
    fi
}

# ------------------------------------------------------------------------------
# conduit::compose_get_services
# Returns space-separated list of service names defined in manifest.
# ------------------------------------------------------------------------------
conduit::compose_get_services() {
    local compose_json="$1"

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, json
data = json.loads(sys.argv[1])
services = list(data.get('services', {}).keys())
print(' '.join(services))
" "${compose_json}"
    fi
}

# ------------------------------------------------------------------------------
# conduit::compose_get_dep_graph
# Generates "SERVICE:DEP1,DEP2 ..." graph string for topological sort.
# ------------------------------------------------------------------------------
conduit::compose_get_dep_graph() {
    local compose_json="$1"

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, json
data = json.loads(sys.argv[1])
entries = []
for name, srv in data.get('services', {}).items():
    deps = srv.get('depends_on', [])
    if isinstance(deps, list):
        entries.append(f\"{name}:{','.join(deps)}\")
    elif isinstance(deps, dict):
        entries.append(f\"{name}:{','.join(deps.keys())}\")
    else:
        entries.append(f\"{name}:\")
print(' '.join(entries))
" "${compose_json}"
    fi
}
