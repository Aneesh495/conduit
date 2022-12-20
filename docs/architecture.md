# Conduit System Architecture and Execution Fabric

Conduit is a deterministic, hermetic container runtime, userspace copy-on-write storage engine, virtual network switch, and process supervisor implemented in modular GNU Bash 4.0+ with an audited POSIX C accelerator shim.

## 1. High-Level System Architecture

Conduit decouples container virtualization into six discrete, modular layers:

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

## 2. Container Lifecycle State Machine

A container transitions deterministically through well-defined lifecycle states:

```
  [Non-existent]
        |
        | conduit run / state_create
        v
    [CREATED] ----------> [DEAD] (init failed)
        |
        | process_start
        v
    [RUNNING] <=========> [PAUSED]
        |
        | SIGTERM / SIGKILL / workload exit
        v
    [STOPPED]
        |
        | conduit rm
        v
  [Non-existent]
```

### State Definitions

- `creating`: The storage engine is allocating the scratch container directory, unpacking base image layers, and synthesizing device files.
- `created`: The container rootfs and configuration are finalized, IP address is leased from IPAM, but PID 1 workload has not yet been spawned.
- `running`: The workload process is actively running under kernel namespace isolation (Linux) or Apple Sandbox-exec profile containment (macOS).
- `paused`: The cgroups v2 freezer controller has suspended all threads in the container slice.
- `stopped`: Workload process terminated naturally or via SIGTERM/SIGKILL; exit status and termination timestamp are persisted in `state.json`.
- `dead`: Container suffered an unrecoverable initialization error during storage or namespace setup.

## 3. Storage Hierarchy and Content Addressability

All images, layers, and configuration state reside within `~/.conduit` (or `$CONDUIT_STATE_DIR`):

```
~/.conduit/
├── blobs/
│   └── sha256/
│       ├── ba7816bf8f01cfea... (immutable layer tarball)
│       └── e3b0c44298fc1c14... (immutable configuration blob)
├── images/
│   ├── index.json          (tag to manifest digest mapping)
│   ├── <image_id>.json     (OCI v2 manifest descriptor)
│   └── <image_id>.prov.json(SLSA v1.0 supply-chain attestation)
├── containers/
│   └── <container_id>/
│       ├── state.json      (execution metadata and status)
│       ├── pid             (active host PID of container workload)
│       ├── combined.log    (multiplexed stdout and stderr)
│       ├── rootfs/         (active userspace CoW container filesystem)
│       └── state/
│           ├── cow_journal.log (append-only link break audit trail)
│           └── sandbox.sb      (compiled Darwin sandbox profile)
├── networks/
│   └── conduit/
│       ├── config.json     (subnet definition: 10.88.0.0/16)
│       └── leases.txt      (active IPv4 address lease table)
└── volumes/
    └── <volume_name>/
        ├── metadata.json
        └── _data/          (persistent host storage mount)
```

## 4. Execution Flow: `conduit run`

1. **Tag Resolution**: The image tag is queried against `images/index.json` to resolve the immutable manifest digest.
2. **Layer Materialization**: If the container uses userspace CoW (macOS or rootless Linux), Conduit creates a hardlink shadow tree of the base layer inside `rootfs/`. On privileged Linux, it mounts an OverlayFS union mount.
3. **Whiteout Resolution**: Any `.wh.<filename>` and `.wh..wh..opq` markers are scanned and applied to ensure underlying deletions are masked.
4. **Network Plumbing**: IPAM allocates an IPv4 address from `10.88.0.0/16`. If port bindings are requested, background TCP proxy daemons are initialized.
5. **Environment Cleansing**: Host environment variables are scrubbed. Clean paths, hostname, and user-defined `-e` variables are materialized.
6. **Isolation Dispatch**:
   - On Linux: child is spawned via `unshare` or `conduit-shim isolate` with private namespaces and cgroups v2 quotas.
   - On macOS: a dynamic Scheme quarantine profile is compiled, and child is executed via `sandbox-exec` with filesystem write locks outside `rootfs/`.
7. **Supervisor Attachment**: Detached workloads are detached from parent subshell file descriptors to prevent command substitution hangs; an asynchronous reaper monitors child death and updates `state.json`.
