# Security Model and Containment Boundaries

Conduit is designed with a defense-in-depth security model that minimizes privilege requirements while strictly enforcing filesystem and process isolation.

## 1. Threat Model

Conduit defends against the following primary threat vectors:

1. Ambient Host File Tampering: Unprivileged container workloads must not be capable of modifying host files in home directories, system libraries, or operational configuration files.
2. Inode Contamination: Workloads modifying files shared with the base image must not corrupt the underlying image layers stored in CAS.
3. Network Egress Leakage: Workloads launched with `--net none` must be completely prevented from establishing raw sockets or outbound TCP/UDP connections.
4. Process Privilege Escalation: On Linux, workloads running as container root must not gain raw block device access or kernel module loading capabilities on the host.

## 2. Privilege Boundaries

### Linux Containment
- Drops `CAP_SYS_ADMIN`, `CAP_SYS_RAWIO`, `CAP_SYS_PTRACE`, `CAP_SYS_MODULE`, `CAP_SYS_BOOT`, and `CAP_MAC_ADMIN` via `setpriv --no-new-privs`.
- Isolates PID, Mount, UTS, IPC, and Network namespaces via `unshare`.
- Prevents forkbomb attacks via cgroups v2 `pids.max` ceilings.

### macOS Darwin Containment
- Compiles dynamic Apple Sandbox-exec profiles (`.sb` format) denying file writes outside the container scratch rootfs.
- Sanitizes environment variables using `conduit::env_cleanse`, preventing token or credential leakage.

## 3. Storage Security
- CAS blobs are committed with read-only permissions `0444`.
- Tar layer extraction enforces strict Zip Slip path guards, rejecting tarballs containing relative path traversal (`../`) or absolute path prefixes (`/`).
