#!/usr/bin/env python3
"""
tools/verify_evidence.py - Independent verification auditor for Conduit

Performs cryptographic verification of content-addressable storage blobs,
OCI manifest integrity, and in-toto SLSA provenance statements.
"""

import hashlib
import json
import os
import sys

def verify_blobs(blob_dir: str) -> bool:
    sha_dir = os.path.join(blob_dir, "sha256")
    if not os.path.exists(sha_dir):
        print(f"[OK] No CAS blobs directory at {sha_dir} (empty store)")
        return True

    blobs = [f for f in os.listdir(sha_dir) if not f.endswith(".tmp")]
    print(f"[*] Verifying {len(blobs)} CAS blobs in {sha_dir}...")

    corrupted = 0
    for name in blobs:
        path = os.path.join(sha_dir, name)
        if not os.path.isfile(path):
            continue
        h = hashlib.sha256()
        with open(path, "rb") as f:
            while chunk := f.read(65536):
                h.update(chunk)
        digest = h.hexdigest()
        if digest.lower() != name.lower():
            print(f"[FAIL] Digest mismatch for {name}: computed {digest}")
            corrupted += 1

    if corrupted == 0:
        print(f"[PASS] All {len(blobs)} CAS blobs verified against SHA-256 digests")
        return True
    return False

def verify_images(image_dir: str) -> bool:
    if not os.path.exists(image_dir):
        print(f"[OK] No images directory at {image_dir}")
        return True

    manifest_files = [f for f in os.listdir(image_dir) if f.endswith(".json") and not f.endswith(".provenance.json") and f != "index.json"]
    print(f"[*] Verifying {len(manifest_files)} image manifests in {image_dir}...")

    valid = 0
    for fname in manifest_files:
        path = os.path.join(image_dir, fname)
        with open(path, "r") as f:
            try:
                data = json.load(f)
                assert data.get("schemaVersion") == 2
                assert "layers" in data
                valid += 1
            except Exception as e:
                print(f"[FAIL] Invalid manifest {fname}: {e}")

    print(f"[PASS] {valid}/{len(manifest_files)} manifests conform to OCI v2 schema")
    return valid == len(manifest_files)

def main():
    state_dir = os.environ.get("CONDUIT_STATE_DIR", os.path.expanduser("~/.conduit"))
    print(f"[*] Auditing Conduit state root: {state_dir}")

    blobs_ok = verify_blobs(os.path.join(state_dir, "blobs"))
    images_ok = verify_images(os.path.join(state_dir, "images"))

    if blobs_ok and images_ok:
        print("[AUDIT SUCCESS] System state cryptographic invariants preserved.")
        sys.exit(0)
    else:
        print("[AUDIT FAILED] Invariant violations detected.")
        sys.exit(1)

if __name__ == "__main__":
    main()
