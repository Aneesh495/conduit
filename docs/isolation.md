# Process Isolation and Virtualization Boundaries

Conduit provides strong, multi-layered process containment adapted to the capabilities of the host kernel.

## 1. Linux Kernel Namespaces

On Linux kernels, Conduit utilizes five distinct namespace boundaries to virtualize system resources:

- Mount Namespace (`CLONE_NEWNS`): Provides an isolated virtual filesystem hierarchy. Host mount points are invisible; changes inside the container do not propagate to the host.
- UTS Namespace (`CLONE_NEWUTS`): Isolates hostname and domain name. Containers maintain private hostnames (`conduit_<id>`) without mutating host system identity.
- PID Namespace (`CLONE_NEWPID`): Re-numbers container process IDs starting at PID 1. Host processes are completely invisible to the container.
- IPC Namespace (`CLONE_NEWIPC`): Isolates System V IPC and POSIX message queues, preventing shared memory side channels across tenant workloads.
- Network Namespace (`CLONE_NEWNET`): Isolates network interfaces, IP routing tables, and firewall filter rules.
- User Namespace (`CLONE_NEWUSER`): Maps an unprivileged user UID on the host to UID 0 (root) inside the container, enabling rootless containerization without setuid binaries.

## 2. Linux cgroups v2 Resource Controllers

Resource utilization is constrained via the unified cgroups v2 controller hierarchy at `/sys/fs/cgroup/conduit/<container_id>`:

- CPU Bandwidth (`cpu.max`): Enforces quota limits over a 100ms accounting period (e.g., `50000 100000` restricts the container to 50% of a single CPU core).
- Memory Footprint (`memory.max`): Hard ceiling on resident set size (RSS) and anonymous memory in raw bytes (e.g., `536870912` for 512 MiB). Exceeding this limit triggers out-of-memory (OOM) killer isolation within the slice.
- Thread/Process Limits (`pids.max`): Constrains maximum allowable processes (default: 1024), eliminating forkbomb vulnerabilities.

## 3. macOS Darwin Apple Sandbox-exec Profiles

On macOS Darwin, where Linux namespaces and cgroups do not exist, Conduit compiles dynamic Scheme sandbox profiles (`.sb` format) consumed by Apple's kernel sandbox extension (`sandbox-exec`):

```scheme
;; conduit container sandbox profile v1
(version 1)
(allow default)

;; Quarantine write operations: deny writes outside container rootfs
(deny file-write* (subpath "/Users"))
(deny file-write* (subpath "/System"))
(deny file-write* (subpath "/Library"))
(deny file-write* (subpath "/Applications"))

;; Allow writes STRICTLY inside container rootfs and container state
(allow file-write* (subpath "/Users/operator/.conduit/containers/<id>/rootfs"))
(allow file-write* (subpath "/tmp"))
(allow file-write* (subpath "/var/tmp"))
```

### Sandbox Guarantees
- The process cannot mutate host files in `/Users`, `/Library`, `/Applications`, or system roots.
- When network isolation is requested (`--net none`), the sandbox injects `(deny network*)`, forbidding all raw socket and outbound network connections.
- Processes execute inside the container rootfs with scrubbed environment variables, preventing ambient token leakage.

## 4. Native C Accelerator Shim (`conduit-shim`)

For performance-critical syscalls and raw terminal multiplexing, Conduit compiles an audited C accelerator shim with zero external dependencies:

- Terminal PTY Bridge: Allocates master/slave pseudo-terminals (`openpty`/`forkpty`), captures window resize signals (`SIGWINCH`), configures terminal raw mode (`cfmakeraw`), and pumps bidirectional data using `select()`.
- Syscall Isolation: Executes `unshare()`, `pivot_root()`, `sethostname()`, and registers `prctl(PR_SET_PDEATHSIG, SIGKILL)` so child processes terminate instantly if parent supervisor dies.
