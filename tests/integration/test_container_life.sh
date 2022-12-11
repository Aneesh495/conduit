#!/usr/bin/env bash
# ==============================================================================
# tests/integration/test_container_life.sh - End-to-end container lifecycle tests
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "cli/commands"

run_tests() {
    test_plan 6

    # 1. Prepare minimal rootfs context with executable script
    local ctx_dir="${TEST_TMP_DIR}/test_app_ctx"
    mkdir -p "${ctx_dir}/bin"
    cat <<'EOF' > "${ctx_dir}/bin/app"
#!/bin/sh
echo "hello from conduit container"
sleep 2
EOF
    chmod +x "${ctx_dir}/bin/app"

    # 2. Build image
    local img_id
    img_id="$(conduit::cmd_build -t "test-app:v1" "${ctx_dir}")"
    assert_eq "${#img_id}" "64" "conduit build returns 64-char image ID"

    # 3. Verify image in index
    local resolved_id
    resolved_id="$(conduit::image_resolve "test-app:v1")"
    assert_eq "${resolved_id}" "${img_id}" "image_resolve locates newly built tag"

    # 4. Run detached container
    local cid
    cid="$(conduit::cmd_run -d --name "worker1" "test-app:v1" /bin/sleep 5)"
    assert_eq "${#cid}" "64" "conduit run launches detached container"

    # 5. Verify container running in state
    local status
    status="$(conduit::state_get_status "${cid}")"
    assert_eq "${status}" "running" "container status is running"

    # 6. Stop container
    conduit::cmd_stop "worker1" >/dev/null 2>&1
    status="$(conduit::state_get_status "${cid}")"
    assert_eq "${status}" "stopped" "conduit stop transitions status to stopped"

    # 7. Remove container
    conduit::cmd_rm "worker1" >/dev/null 2>&1
    assert_false "[[ -d '${CONDUIT_CONTAINERS_DIR}/${cid}' ]]" "conduit rm deletes container directory"

    test_summary
}

run_tests
