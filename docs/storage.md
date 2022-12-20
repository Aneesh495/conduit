# Storage Engine and Copy-on-Write Architecture

Conduit implements a high-performance content-addressable storage (CAS) engine and userspace Copy-on-Write (CoW) shadow filesystem that operates without root privileges across Linux and macOS Darwin.

## 1. Content-Addressable Storage (CAS)

Every image layer, configuration blob, and file artifact in Conduit is indexed strictly by its cryptographic SHA-256 hexadecimal hash.

### Ingestion Protocol
1. Temporary Buffer: Incoming streams or files are written to a unique ephemeral file: `${CONDUIT_BLOB_DIR}/sha256/stream.tmp.<pid>.<salt>`.
2. Digest Computation: The complete SHA-256 digest is calculated over the committed bytes.
3. Immutability Lockdown: Permissions are set to read-only `0444`.
4. Atomic Rename: The file is renamed to `${CONDUIT_BLOB_DIR}/sha256/<hash>`. If the file already exists, the temporary file is unlinked, achieving instant content deduplication.

## 2. Userspace Copy-on-Write (CoW) Shadow Trees

Traditional container engines rely on Linux kernel union filesystems (OverlayFS, Btrfs, ZFS) which are unavailable to unprivileged users and completely absent on macOS Darwin.

Conduit solves this by synthesizing hardlink shadow trees:

```
Base Layer (Immutable CAS)                 Container Scratch Rootfs
+-------------------------+                +-------------------------+
| /etc/hosts (inode 1001) | <--- hardlink -| /etc/hosts (inode 1001) |
| /bin/sh    (inode 1002) | <--- hardlink -| /bin/sh    (inode 1002) |
| /var/data  (inode 1003) | <--- hardlink -| /var/data  (inode 1003) |
+-------------------------+                +-------------------------+
                                                        |
                                            Workload attempts write
                                                        |
                                                        v
                                           [Break Hardlink Protocol]
                                                        |
                                           +-------------------------+
                                           | Fresh Copy (inode 2050) |
                                           | Unlink old pointer      |
                                           | Mutate private bytes    |
                                           +-------------------------+
```

### Inode Link Breaking Protocol
1. Before a process mutates a target file, Conduit queries the file link count (`stat -f %l` on Darwin, `stat -c %h` on Linux).
2. If `nlink > 1`, the file shares an inode with the underlying base layer.
3. Conduit copies the file bytes to an ephemeral target `file.cow.<pid>.<salt>`.
4. The hardlink is unlinked from the container rootfs, and the private copy is atomically moved into place.
5. The transaction is recorded in `state/cow_journal.log`.
6. Subsequent writes mutate the private inode, guaranteeing zero corruption to the base image.

## 3. OCI Whiteout Markers

When building or stacking layers, file deletions and directory masking follow the Open Container Initiative (OCI) Image Specification:

- File Deletion: When a file `data.txt` is removed in an upper layer, Conduit synthesizes `.wh.data.txt`. During layer unioning, the existence of this marker unlinks `data.txt` from lower layers, and the marker is purged from the active view.
- Opaque Directory: When a directory is completely replaced, Conduit synthesizes `.wh..wh..opq`. During union merging, lower-layer directory contents are ignored, presenting an opaque mask.

## 4. Kernel OverlayFS Driver

When executing as root on modern Linux kernels (`EUID == 0`), Conduit transparently activates the native kernel OverlayFS driver:

```
mount -t overlay overlay \
  -o lowerdir=<base_rootfs>,upperdir=<container_dir>/upper,workdir=<container_dir>/work \
  <container_dir>/rootfs
```

During container teardown, Conduit performs clean lazy unmounting (`umount -l`) to release kernel mount references.
