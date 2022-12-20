# Supply Chain Provenance and SLSA Attestations

Conduit generates cryptographic supply chain attestations conforming to the in-toto Statement v1 specification and the SLSA (Supply-chain Levels for Software Artifacts) v1.0 standard.

## 1. Provenance Attestation Schema

Every image build (`conduit build`) and container commit (`conduit commit`) produces an immutable provenance document saved alongside the manifest at `${CONDUIT_IMAGES_DIR}/<image_id>.provenance.json`:

```json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    {
      "name": "conduit-base:latest",
      "digest": {
        "sha256": "ca6b58e2b6e01edba87423bd6739df6c524784069d5514bd66400c094a8a4437"
      }
    }
  ],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://conduit.dev/attestation/v1",
      "externalParameters": {
        "entrypoint": "conduit build ./context"
      },
      "internalParameters": {
        "conduit_version": "0.9.0-alpha"
      },
      "resolvedDependencies": [
        {
          "uri": "pkg:conduit/layer@c61c1354f1bbe24e...",
          "digest": {
            "sha256": "c61c1354f1bbe24e..."
          }
        }
      ]
    },
    "runDetails": {
      "builder": {
        "id": "https://conduit.dev/engine/cli"
      },
      "metadata": {
        "invocationId": "73f918e...",
        "startedOn": "2026-10-18T00:20:00Z",
        "finishedOn": "2026-10-18T00:20:02Z"
      }
    }
  }
}
```

## 2. Invariant Verification

The Python auditor (`tools/verify_evidence.py`) validates that:
1. Every manifest subject digest mathematically equals the SHA-256 hash of the generated image layers.
2. Every resolved dependency layer exists in the CAS blob store and passes digest verification.
3. Timestamps and build parameters are cryptographically anchored.
