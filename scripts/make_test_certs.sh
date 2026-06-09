#!/usr/bin/env bash
#
# Generates *development/testing* ES256 (NIST P-256) credentials for C2PA,
# written to Sources/Resources/ so they get bundled into the app.
#
# Two distinct end-entity certificates are issued from a single test root CA:
#
#   1. Claim signer  -> es256_certs.pem    / es256_private.key
#        Signs the C2PA manifest/claim.
#   2. Creator identity -> identity_certs.pem / identity_private.key
#        Signs the CAWG identity assertion (cawg.identity) that binds a creator
#        identity to the author assertion. A SEPARATE key from the claim signer.
#
# Each leaf is a proper two-link chain (leaf + root). A lone self-signed leaf is
# rejected by C2PA path validation ("the certificate is invalid"), so we always
# chain to the root.
#
#   root CA : CA:TRUE,  keyUsage = keyCertSign, cRLSign        (self-signed)
#   leaf    : CA:FALSE, keyUsage = digitalSignature (critical),
#             extendedKeyUsage = emailProtection                (signed by root)
#
# Because the root is not on the C2PA trust list, verifiers (c2patool,
# https://contentcredentials.org/verify, etc.) will report the signers as
# "untrusted" / "unknown" — expected for test credentials. The signatures are
# cryptographically valid and the manifest is well-formed. For trusted
# credentials, obtain certificates from a CA on the C2PA trust list. In a real
# deployment the creator identity certificate would be issued to the actual
# creator (its subject would identify them), not minted locally.
#
# Usage:  ./scripts/make_test_certs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/../Sources/Resources"
mkdir -p "${OUT_DIR}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Leaf extension config (applied by `openssl x509 -req` via -extfile).
cat > "${WORK}/leaf.cnf" <<'EOF'
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = emailProtection
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
EOF

# ---------------------------------------------------------------------------
# Root CA: EC P-256 key + self-signed CA certificate.
# ---------------------------------------------------------------------------
openssl ecparam -name prime256v1 -genkey -noout -out "${WORK}/root.key" 2>/dev/null
openssl req -new -x509 -sha256 -days 3650 \
  -key "${WORK}/root.key" \
  -out "${WORK}/root.crt" \
  -subj "/CN=Sigillo Test Root CA/O=Content Authenticity Example/C=US" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"

# ---------------------------------------------------------------------------
# issue_leaf <name> <subjectCN> <cert-out> <key-out>
#   Mints an EC P-256 leaf signed by the root CA and writes the full chain
#   (leaf + root) and the PKCS#8 private key.
# ---------------------------------------------------------------------------
issue_leaf() {
  local name="$1" cn="$2" cert_out="$3" key_out="$4"
  openssl ecparam -name prime256v1 -genkey -noout -out "${WORK}/${name}.key" 2>/dev/null
  openssl req -new -sha256 \
    -key "${WORK}/${name}.key" \
    -out "${WORK}/${name}.csr" \
    -subj "/CN=${cn}/O=Content Authenticity Example/C=US"
  openssl x509 -req -sha256 -days 3650 \
    -in "${WORK}/${name}.csr" \
    -CA "${WORK}/root.crt" -CAkey "${WORK}/root.key" -CAcreateserial \
    -out "${WORK}/${name}.crt" \
    -extfile "${WORK}/leaf.cnf"
  openssl verify -CAfile "${WORK}/root.crt" "${WORK}/${name}.crt" >/dev/null
  cat "${WORK}/${name}.crt" "${WORK}/root.crt" > "${cert_out}"
  openssl pkcs8 -topk8 -nocrypt -in "${WORK}/${name}.key" -out "${key_out}"
}

# ---------------------------------------------------------------------------
# Two distinct leaves from the same root.
# ---------------------------------------------------------------------------
issue_leaf "claim" "Sigillo Test Signer" \
  "${OUT_DIR}/es256_certs.pem" "${OUT_DIR}/es256_private.key"

issue_leaf "identity" "Sigillo Creator Identity" \
  "${OUT_DIR}/identity_certs.pem" "${OUT_DIR}/identity_private.key"

echo "Wrote:"
echo "  ${OUT_DIR}/es256_certs.pem      + es256_private.key      (claim signer)"
echo "  ${OUT_DIR}/identity_certs.pem   + identity_private.key   (creator identity)"
echo
echo "These are TEST credentials. Verifiers will mark the signers as untrusted."
