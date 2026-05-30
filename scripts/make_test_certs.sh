#!/usr/bin/env bash
#
# Generates a *development/testing* ES256 (NIST P-256) signing credential for
# C2PA, written to Sources/Resources/ so it gets bundled into the app.
#
# This produces a proper two-link chain — a root CA that issues an end-entity
# (leaf) signing certificate — because the C2PA certificate profile / RFC 5280
# path validation rejects a lone self-signed leaf (a cert with CA:FALSE cannot
# be its own issuer, which surfaces in the app as
# "Signature: the certificate is invalid").
#
#   root CA  : CA:TRUE,  keyUsage = keyCertSign, cRLSign        (self-signed)
#   leaf     : CA:FALSE, keyUsage = digitalSignature (critical),
#              extendedKeyUsage = emailProtection                (signed by root)
#
# Output:
#   es256_certs.pem    leaf certificate followed by the root (full chain, PEM)
#   es256_private.key  the leaf's private key (unencrypted PKCS#8 PEM)
#
# Because the root is not on the C2PA trust list, verifiers (c2patool,
# https://contentcredentials.org/verify, etc.) will report the signer as
# "untrusted" / "unknown" — that is expected for test credentials. The signature
# itself is cryptographically valid and the manifest is well-formed. For a
# trusted credential, obtain a certificate from a CA on the C2PA trust list.
#
# Usage:  ./scripts/make_test_certs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/../Sources/Resources"
mkdir -p "${OUT_DIR}"

KEY="${OUT_DIR}/es256_private.key"
CERT="${OUT_DIR}/es256_certs.pem"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ---------------------------------------------------------------------------
# Leaf extension config (applied by `openssl x509 -req` via -extfile)
# ---------------------------------------------------------------------------
cat > "${WORK}/leaf.cnf" <<'EOF'
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = emailProtection
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
EOF

# ---------------------------------------------------------------------------
# 1. Root CA: EC P-256 key + self-signed CA certificate.
# ---------------------------------------------------------------------------
openssl ecparam -name prime256v1 -genkey -noout -out "${WORK}/root.key" 2>/dev/null
openssl req -new -x509 -sha256 -days 3650 \
  -key "${WORK}/root.key" \
  -out "${WORK}/root.crt" \
  -subj "/CN=C2PA Camera Test Root CA/O=Content Authenticity Example/C=US" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"

# ---------------------------------------------------------------------------
# 2. Leaf signing cert: EC P-256 key + CSR, signed by the root CA.
# ---------------------------------------------------------------------------
openssl ecparam -name prime256v1 -genkey -noout -out "${WORK}/leaf.key" 2>/dev/null
openssl req -new -sha256 \
  -key "${WORK}/leaf.key" \
  -out "${WORK}/leaf.csr" \
  -subj "/CN=C2PA Camera Test Signer/O=Content Authenticity Example/C=US"

openssl x509 -req -sha256 -days 3650 \
  -in "${WORK}/leaf.csr" \
  -CA "${WORK}/root.crt" -CAkey "${WORK}/root.key" -CAcreateserial \
  -out "${WORK}/leaf.crt" \
  -extfile "${WORK}/leaf.cnf"

# ---------------------------------------------------------------------------
# 3. Assemble outputs: full chain (leaf first) + leaf key as PKCS#8.
# ---------------------------------------------------------------------------
cat "${WORK}/leaf.crt" "${WORK}/root.crt" > "${CERT}"
openssl pkcs8 -topk8 -nocrypt -in "${WORK}/leaf.key" -out "${KEY}"

# Sanity check: the chain must verify.
openssl verify -CAfile "${WORK}/root.crt" "${WORK}/leaf.crt" >/dev/null

echo "Wrote:"
echo "  ${CERT}    (leaf + root chain)"
echo "  ${KEY}    (leaf private key)"
echo
echo "These are TEST credentials. Verifiers will mark the signer as untrusted."
