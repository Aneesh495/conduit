# conduit

Deterministic container runtime and process isolation fabric in pure Bash: copy-on-write image layers, cgroup v2 resource accounting, virtual network bridges, DAG-driven service orchestration, and cryptographic provenance receipts.

```
       ___  ___  _  _ ___  _   _ ___ _____ 
      / __|/ _ \| \| |   \| | | |_ _|_   _|
     | (__| (_) | .` | |) | |_| || |  | |  
      \___|\___/|_|\_|___/ \___/|___| |_|  
```

Conduit provides a self-contained container runtime and micro-service orchestrator implemented in modular GNU Bash (4.0+) with an audited POSIX C accelerator shim. It requires no daemon (Docker/Podman/containerd), operates rootless on macOS Darwin and Linux, enforces hardlink Copy-on-Write (CoW) shadow tree immutability, and generates cryptographic SLSA v1.0 supply chain attestations.

---

## Technical Highlights

| Capability | Implementation Mechanism | Invariant Guaranteed |
| :--- | :--- | :--- |
| **Content-Addressable Storage** | SHA-256 indexed blob store with atomic rename ingestion | Bit-exact layer deduplication; tamper detection |
| **Userspace Copy-on-Write** | Hardlink shadow trees with link-breaking write barriers | Base image layers remain strictly immutable |
| **Process Quarantine** | Linux kernel namespaces / macOS Apple Sandbox-exec | Workload writes constrained strictly to container rootfs |
| **Resource Accounting** | Linux cgroups v2 (`cpu.max`, `memory.max`, `pids.max`) | Deterministic quota enforcement; forkbomb immunity |
| **Virtual Networking** | Deterministic IPAM (`10.88.0.0/16`) + userspace TCP proxy | Non-root host port forwarding; synthetic DNS tables |
| **DAG Orchestration** | Kahn topological scheduler with health readiness gates | Deadlock-free startup ordering; automated rollback |
| **Supply Chain Attestation** | In-toto Statement v1 with SLSA v1.0 build predicates | Provable provenance for all materialized container images |

---

## System Architecture

```
+-------------------------------------------------------------------------+
|                               Conduit CLI                               |
|          (build, run, ps, exec, logs, stop, rm, compose, doctor)        |
+-------------------------------------------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                      Orchestration & DAG Scheduler                      |
|       - Kahn Topological Sorter       - Health Check Readiness Gates    |
|       - Blue-Green Rolling Updates    - Service Discovery Synthesizer   |
+-------------------------------------------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                   Process Supervisor & State Machine                    |
|       - Asynchronous Sub-reaper       - Terminal PTY Raw Bridge         |
|       - Append-only Log Streams       - Multi-protocol Health Probes    |
+-------------------------------------------------------------------------+
                   |                                   |
                   v                                   v
+--------------------------------------+   +------------------------------+
|          Virtual Networking          |   |      Storage & CoW Engine    |
|  - IPAM Subnet Leases (10.88.0.0/16) |   |  - CAS Blob Store (SHA-256)  |
|  - Userspace Bidirectional TCP Proxy |   |  - OCI Layer Tarball Unpacker|
|  - Synthetic /etc/hosts Injector     |   |  - Hardlink CoW Shadow Trees |
|  - Linux veth & conduit0 Bridge      |   |  - Whiteout Deletion Masks   |
+--------------------------------------+   +------------------------------+
                   |                                   |
                   +-----------------+-----------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                      Platform Isolation Primitives                      |
|   Linux:                                  macOS Darwin:                 |
|   - Kernel Namespaces (mnt/uts/pid/ipc)   - Apple Sandbox-exec Profiles |
|   - cgroups v2 (cpu.max, memory.max)      - Hermetic Environment Cleanse|
|   - Linux Capabilities Dropping (setpriv) - Synthetic Device Plumbing   |
|   - Native C Shim (clone, pivot_root)     - POSIX Process Group Jails   |
+-------------------------------------------------------------------------+
```

---

## Quickstart

### 1. Host Virtualization Audit
Verify kernel capabilities, isolation drivers, and dependencies:

```bash
./bin/conduit doctor
```

### 2. Build an Immutable Image
Package a rootfs context into an immutable content-addressed image:

```bash
./bin/conduit build -t my-app:v1 ./examples/01_minimal_alpine/context
```

### 3. Launch an Isolated Container
Run a workload in detached background mode with port forwarding:

```bash
./bin/conduit run -d --name web-1 -p 8080:80 my-app:v1 /bin/sleep 60
```

### 4. Query Running Containers and Real-Time Telemetry
Inspect process status, IP assignments, and resource utilization:

```bash
./bin/conduit ps
./bin/conduit stats
./bin/conduit logs web-1
```

### 5. Multi-Service Topology Orchestration
Deploy a multi-tier microservice topology defined in `conduit-compose.yml`:

```bash
cd examples/02_web_stack
../../bin/conduit compose up
../../bin/conduit compose down
```

---

## Performance Benchmarks

Measured on Apple Silicon ARM64 (Darwin 25.6) across 1,000 operations:

| Benchmark Operation | Workload / Dimension | Latency / Throughput |
| :--- | :--- | :--- |
| **CAS Blob Ingestion** | 100 payloads (SHA-256 verified) | 123 µs / blob |
| **CoW Shadow Tree Synthesis** | 500 inode directory tree | 1.2 ms total |
| **Deterministic Layer Packaging** | 500 inodes into sorted tar | 446 ms |
| **Process State Transition** | State machine disk transaction | 18 ms |
| **Kahn DAG Topological Sort** | 10-node complex dependency graph | 12 ms |

---

## Verification Suite

Conduit includes a test harness implementing the Test Anything Protocol (TAP 13):

```bash
make test               # Run all 15 unit, integration, and regression suites
make test-unit          # Run unit tests only
make test-integration   # Run integration tests only
make test-regression    # Run bug reproduction suites only
make benchmark          # Execute latency and throughput benchmarks
```

Audit state integrity with the independent Python verification engine:

```bash
python3 tools/verify_evidence.py
```

---

## Technical Documentation

- [System Architecture & Execution Pipeline](docs/architecture.md)
- [Storage Engine & Userspace Copy-on-Write](docs/storage.md)
- [Process Isolation & Platform Boundaries](docs/isolation.md)
- [Virtual Networking & Service Discovery](docs/networking.md)
- [DAG Scheduling & Rolling Updates](docs/orchestration.md)
- [Supply Chain Provenance & SLSA Attestations](docs/provenance.md)
- [Verification Methodology & Invariants](docs/testing.md)
- [Bug Regression Ledger](docs/bugs.md)
- [Security Model & Containment Boundaries](docs/security.md)
- [Operator Diagnostics & Maintenance](docs/operations.md)

---

## License

MIT License. See [LICENSE](LICENSE) for details.
