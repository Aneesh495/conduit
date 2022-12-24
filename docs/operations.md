# Operator Manual and Diagnostics

This guide covers operational maintenance, diagnostic procedures, log streaming, and troubleshooting for Conduit clusters and runtime hosts.

## 1. System Diagnostics: `conduit doctor`

Before running production workloads, verify host kernel capabilities and tooling:

```bash
conduit doctor
```

Example diagnostic report:

```
==========================================================
 Conduit Host Virtualization Diagnostics & Health Report  
==========================================================
Platform Diagnostics:
  OS:                darwin
  Architecture:      arm64
  Privilege:         unprivileged (uid 501)
  Linux Namespaces:  false
  cgroups v2:        false
  OverlayFS:         false
  Apple Sandbox:     true
  Native Shim:       true

Required & Optional Tooling:
  bash         [FOUND] (/opt/homebrew/bin/bash)
  tar          [FOUND] (/usr/bin/tar)
  gzip         [FOUND] (/usr/bin/gzip)
  shasum       [FOUND] (/usr/bin/shasum)
  sha256sum    [FOUND] (/sbin/sha256sum)
  openssl      [FOUND] (/opt/homebrew/bin/openssl)
  curl         [FOUND] (/usr/bin/curl)
  nc           [FOUND] (/usr/bin/nc)
  lsof         [FOUND] (/usr/sbin/lsof)
  clang        [FOUND] (/usr/bin/clang)
==========================================================
```

## 2. Real-Time Resource Monitoring: `conduit stats`

Stream live container resource metrics (CPU%, Memory RSS, PID counts):

```bash
conduit stats
```

## 3. Log Inspection and Following: `conduit logs`

Tail or follow container standard output and error:

```bash
conduit logs <container_id_or_name>
conduit logs -f --tail=100 <container_id_or_name>
```

## 4. Recovering Stale Storage and State

If an unexpected host crash occurs while containers were active:
1. Stop running processes: `killall conduit-proxy 2>/dev/null || true`
2. Audit CAS integrity: `python3 tools/verify_evidence.py`
3. Prune dead containers: `rm -rf ~/.conduit/containers/*/pid`
