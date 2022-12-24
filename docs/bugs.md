# Bug Regression Ledger

This document catalogs non-trivial system bugs discovered during the development of Conduit, their root cause analysis, the reproductive test cases authored to prove the failure, and the verified resolution.

---

### Bug 001: Userspace CoW Base Inode Mutation on Shared Hardlinks

- **Category**: Storage Virtualization
- **Reproduction Test**: `tests/regression/test_bug_001_cow_hardlink_leak.sh`
- **Symptom**: When a container process opened and truncated an existing file in `rootfs/`, the underlying base image layer in `~/.conduit/blobs/` was mutated simultaneously.
- **Root Cause**: The userspace CoW shadow tree initialized files via hardlinks (`cp -al` / `ln`). When a write occurred, the kernel followed the existing inode rather than creating a new private copy, violating base layer immutability.
- **Fix**: Implemented `conduit::cow_break_link`. Before modifying any file, Conduit queries `stat` for `nlink > 1`. If hardlinks are present, it copies the bytes to a private temporary file, unlinks the hardlinked path, atomically replaces it, and logs the link-break event in `cow_journal.log`.

---

### Bug 002: Escaped Double Quote Truncation in JSON Tokenizer

- **Category**: Parser / Serialization
- **Reproduction Test**: `tests/regression/test_bug_002_json_escaped_quote.sh`
- **Symptom**: Manifests or commands containing escaped double quotes (e.g. `\"argument\"`) suffered truncated strings or corrupted subsequent JSON keys.
- **Root Cause**: Regular expressions in Bash matched the first unescaped quote without correctly tracking backslash escape parity.
- **Fix**: Integrated a recursive descent tokenizer and Python/regex accelerated query path that evaluates character escape states prior to field boundary termination.

---

### Bug 003: Infinite Loop on Self-Referencing DAG Dependencies

- **Category**: Orchestration / Graph Theory
- **Reproduction Test**: `tests/regression/test_bug_003_dag_self_cycle.sh`
- **Symptom**: A service specifying `depends_on: [itself]` or circular two-node dependencies caused `conduit compose up` to hang indefinitely.
- **Root Cause**: Topological sort implementations that rely on basic recursion without node coloring fail to distinguish back-edges from cross-edges.
- **Fix**: Standardized on Kahn's in-degree queue algorithm. If the count of resolved nodes does not equal the total number of graph vertices upon queue exhaustion, `ERR_DAG_CYCLE` (code 70) is thrown and the cycle is printed to stderr.

---

### Bug 004: Inverted Resource Destruction in Signal Cleanup Stack

- **Category**: Process Supervision / Signal Handling
- **Reproduction Test**: `tests/regression/test_bug_004_signal_cleanup_lifo.sh`
- **Symptom**: On SIGINT (Ctrl+C), container unmount commands failed with `Device or resource busy`.
- **Root Cause**: Cleanup callbacks were executed in First-In-First-Out (FIFO) registration order. The parent rootfs directory was targeted for removal before child volume mounts were unmounted.
- **Fix**: Re-engineered `_CONDUIT_CLEANUP_STACK` as a strict Last-In-First-Out (LIFO) stack. The most recently registered mount or proxy process is torn down first.

---

### Bug 005: IPAM Subnet Boundary Allocation Wrap-around

- **Category**: Virtual Networking / IPAM
- **Reproduction Test**: `tests/regression/test_bug_005_ipam_subnet_exhaust.sh`
- **Symptom**: When allocating more than 254 containers on a `/24` or `/16` network slice, the lease allocator attempted to assign broadcast address `10.88.0.255`.
- **Root Cause**: Missing strict boundary guards on host address octets.
- **Fix**: Added explicit upper bound checks (`candidate <= 254`) and immediate exit status `ERR_IPAM_EXHAUSTED` (code 52) when the pool capacity is reached.

---

### Bug 006: Opaque Directory Masking premature marker purging

- **Category**: OCI Layer Unioning
- **Reproduction Test**: `tests/regression/test_bug_006_whiteout_opaque_dir.sh`
- **Symptom**: Directories marked with `.wh..wh..opq` were deleting unrelated sibling files in other directories.
- **Root Cause**: Single-pass find command applied deletions globally across directories instead of scoping each opaque marker to its immediate parent.
- **Fix**: Separated whiteout processing into two isolated passes: Pass 1 processes `.wh..wh..opq` scoped strictly to the enclosing directory; Pass 2 cleans up `.wh.<name>` individual file deletion markers.
