#!/usr/bin/env bash
# ==============================================================================
# lib/provenance/slsa.sh - Cryptographic SLSA v1.0 provenance attestation engine
#
# Generates in-toto compatible supply chain provenance attestations, recording
# builder parameters, base layer digests, hermetic inputs, and cryptographic hashes.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"
conduit::import "crypto/sha256"

# ------------------------------------------------------------------------------
# conduit::provenance_generate
# Generates an in-toto SLSA v1.0 provenance attestation JSON document.
# Arguments:
#   $1 - Subject name (e.g., image tag or container name)
#   $2 - Subject SHA-256 digest
#   $3 - Builder command / build instruction
#   $4 - Base layer digest
# ------------------------------------------------------------------------------
conduit::provenance_generate() {
    local subject_name="$1"
    local subject_digest="$2"
    local build_cmd="$3"
    local base_digest="${4:-none}"

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    cat <<EOF
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    {
      "name": "${subject_name}",
      "digest": {
        "sha256": "${subject_digest}"
      }
    }
  ],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://conduit.dev/attestation/v1",
      "externalParameters": {
        "entrypoint": "${build_cmd}"
      },
      "internalParameters": {
        "conduit_version": "${CONDUIT_VERSION:-0.9.0-alpha}"
      },
      "resolvedDependencies": [
        {
          "uri": "pkg:conduit/layer@${base_digest}",
          "digest": {
            "sha256": "${base_digest}"
          }
        }
      ]
    },
    "runDetails": {
      "builder": {
        "id": "https://conduit.dev/engine/cli"
      },
      "metadata": {
        "invocationId": "$(conduit::sha256_str "${timestamp}_$$")",
        "startedOn": "${timestamp}",
        "finishedOn": "${timestamp}"
      }
    }
  }
}
EOF
}

# ------------------------------------------------------------------------------
# conduit::provenance_verify
# Verifies that an attestation subject digest matches the target artifact.
# ------------------------------------------------------------------------------
conduit::provenance_verify() {
    local attestation_file="$1"
    local artifact_file="$2"

    if [[ ! -f "${attestation_file}" || ! -f "${artifact_file}" ]]; then
        return 1
    fi

    local actual_digest
    actual_digest="$(conduit::sha256_file "${artifact_file}")" || return 1

    local expected_digest
    expected_digest="$(grep -o '"sha256": *"[^"]*"' "${attestation_file}" | head -n 1 | awk -F'"' '{print $4}')"

    if [[ "${actual_digest}" == "${expected_digest}" ]]; then
        conduit::log_info "Provenance attestation verified: subject digest ${actual_digest:0:16} matches artifact"
        return 0
    else
        conduit::log_error "Provenance attestation mismatch: expected ${expected_digest}, computed ${actual_digest}"
        return 1
    fi
}
