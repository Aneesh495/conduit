# Verification Methodology and Invariant Preservation

Conduit employs a rigorous, multi-tiered verification framework implementing the Test Anything Protocol (TAP version 13).

## 1. Test Architecture

The test suite is structured into three discrete layers:

```
tests/
├── unit/           # Micro-benchmarks for core algorithms (parsers, codecs, math)
├── integration/    # Subsystem integration (CAS storage, CoW trees, lifecycle)
└── regression/     # Bug reproduction suites and verified fixes
```

### Running Tests

```bash
make test               # Run all test suites
make test-unit          # Run unit tests only
make test-integration   # Run integration tests only
make test-regression    # Run bug regression tests only
```

## 2. Invariant Verification

The verification framework continuously asserts five core system invariants:

1. Base Layer Immutability: Mutating a file inside a container rootfs must never alter the inode or content of underlying base layers.
2. Inode Isolation: Breaking hardlinks on modified container files must correctly decrease link counts and allocate private inodes.
3. Hermetic State Isolation: Tests run with overridden `$CONDUIT_STATE_DIR` pointing to unique `/tmp/conduit_test_<pid>` directories, ensuring zero interference with live user containers.
4. Process Reaping: Background container workloads and child subshells must be cleanly terminated upon test exit without leaving zombie processes.
5. Deterministic Digesting: SHA-256 digests and HMAC-SHA256 tokens must strictly match standard NIST test vectors.
