#!/usr/bin/env bash
# ==============================================================================
# tools/benchmark.sh - Performance benchmarks for layer unpacking and CoW latency
#
# Measures latency and throughput for CAS blob ingestion, reproducible layer
# packing, userspace copy-on-write shadow tree synthesis, and process spawning.
# ==============================================================================

set -o pipefail

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CONDUIT_ROOT="${_ROOT}"
export CONDUIT_LIB="${CONDUIT_ROOT}/lib"
source "${CONDUIT_LIB}/conduit.sh"

conduit::import "core/types"
conduit::import "crypto/sha256"
conduit::import "storage/cas"
conduit::import "storage/cow_tree"
conduit::import "storage/layer"

BENCH_TMP="/tmp/conduit_bench_$$"
mkdir -p "${BENCH_TMP}"
export CONDUIT_STATE_DIR="${BENCH_TMP}/state"
conduit::init_environment

cleanup() {
    rm -rf "${BENCH_TMP}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "=========================================================="
echo " Conduit Systems Performance Benchmark Suite             "
echo "=========================================================="

# Benchmark 1: CAS Ingestion Throughput
echo -n "==> Benchmarking CAS Ingestion (100 files)... "
PAYLOAD_DIR="${BENCH_TMP}/payloads"
mkdir -p "${PAYLOAD_DIR}"
for i in {1..100}; do
    echo "Payload data block number $i with random salt $RANDOM" > "${PAYLOAD_DIR}/file_$i.dat"
done

START_NS="$(date +%s%N 2>/dev/null || date +%s)"
for i in {1..100}; do
    conduit::cas_put_file "${PAYLOAD_DIR}/file_$i.dat" >/dev/null
done
END_NS="$(date +%s%N 2>/dev/null || date +%s)"
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
echo "${ELAPSED_MS} ms (avg $(( ELAPSED_MS * 10 / 100 )) µs/file)"

# Benchmark 2: CoW Shadow Tree Synthesis
echo -n "==> Benchmarking Userspace CoW Tree Synthesis (500 inodes)... "
MOCK_ROOTFS="${BENCH_TMP}/mock_rootfs"
mkdir -p "${MOCK_ROOTFS}/bin" "${MOCK_ROOTFS}/etc" "${MOCK_ROOTFS}/lib"
for i in {1..500}; do
    touch "${MOCK_ROOTFS}/lib/module_$i.so"
done

TARGET_ROOTFS="${BENCH_TMP}/target_rootfs"
STATE_DIR="${BENCH_TMP}/target_state"

START_NS="$(date +%s%N 2>/dev/null || date +%s)"
conduit::cow_init_tree "${MOCK_ROOTFS}" "${TARGET_ROOTFS}" "${STATE_DIR}" >/dev/null
END_NS="$(date +%s%N 2>/dev/null || date +%s)"
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
echo "${ELAPSED_MS} ms"

# Benchmark 3: Deterministic Layer Packing & SHA-256 Hashing
echo -n "==> Benchmarking Layer Packaging & Verification... "
TAR_OUT="${BENCH_TMP}/layer.tar"
START_NS="$(date +%s%N 2>/dev/null || date +%s)"
conduit::layer_pack "${MOCK_ROOTFS}" "${TAR_OUT}" >/dev/null
DIGEST="$(conduit::sha256_file "${TAR_OUT}")"
END_NS="$(date +%s%N 2>/dev/null || date +%s)"
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
echo "${ELAPSED_MS} ms (SHA-256: ${DIGEST:0:16}...)"

echo "=========================================================="
echo " Benchmark suite completed successfully."
echo "=========================================================="
