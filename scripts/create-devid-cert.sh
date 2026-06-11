#!/usr/bin/env bash
set -euo pipefail

# Creates a Developer ID Application certificate via the App Store Connect API,
# generating the private key locally and importing the resulting identity into
# the login keychain so `codesign` can use it.
#
# Requires: the App Store Connect API key (.p8), key id, and issuer id below,
# plus an Admin / Account Holder role on that key.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID to your App Store Connect API key id}"
ISSUER="${ASC_ISSUER:-}"   # team keys only; leave empty and set ASC_SUB=user for individual keys
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"

WORK="$ROOT_DIR/Build/signing"
PRIV="$WORK/scope_devid.key"
CSR="$WORK/scope_devid.csr"
CER="$WORK/scope_devid.cer"
CERTPEM="$WORK/scope_devid.pem"
P12="$WORK/scope_devid.p12"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

mkdir -p "$WORK"
chmod 700 "$WORK"

echo "==> Generating RSA 2048 private key + CSR"
[[ -f "$PRIV" ]] || openssl genrsa -out "$PRIV" 2048
chmod 600 "$PRIV"
openssl req -new -key "$PRIV" -out "$CSR" -subj "/CN=Scope Developer ID/C=US"

echo "==> Building App Store Connect JWT"
# Team keys authenticate with the issuer id; individual keys with ASC_SUB=user
# (the JWT helper prefers ASC_SUB when both are set).
TOKEN="$(ASC_KEY_PATH="$KEY_PATH" ASC_KEY_ID="$KEY_ID" \
  ASC_ISSUER="$ISSUER" ASC_SUB="${ASC_SUB:-}" \
  swift "$ROOT_DIR/scripts/make-asc-jwt.swift")"

echo "==> Requesting Developer ID Application certificate"
BODY="$(python3 -c '
import json, sys
csr = open(sys.argv[1]).read()
print(json.dumps({"data": {"type": "certificates", "attributes": {
    "certificateType": "DEVELOPER_ID_APPLICATION", "csrContent": csr}}}))
' "$CSR")"

RESP="$(curl -gsS -X POST "https://api.appstoreconnect.apple.com/v1/certificates" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY")"

python3 -c '
import json, sys, base64
d = json.load(sys.stdin)
if "errors" in d:
    sys.stderr.write("API error:\n" + json.dumps(d["errors"], indent=2) + "\n")
    sys.exit(1)
content = d["data"]["attributes"]["certificateContent"]
open(sys.argv[1], "wb").write(base64.b64decode(content))
print("Issued:", d["data"]["attributes"].get("name"),
      "exp", d["data"]["attributes"].get("expirationDate"))
' "$CER" <<<"$RESP"

echo "==> Converting + bundling into PKCS#12"
openssl x509 -inform DER -in "$CER" -out "$CERTPEM"
rm -f "$P12"
openssl pkcs12 -export -inkey "$PRIV" -in "$CERTPEM" \
  -out "$P12" -passout pass: -name "Scope Developer ID"

echo "==> Importing identity into login keychain"
security import "$P12" -k "$LOGIN_KEYCHAIN" -P "" \
  -T /usr/bin/codesign -T /usr/bin/security

echo "==> Verifying"
security find-identity -v -p codesigning | grep -i "developer id application" \
  || { echo "ERROR: identity not found after import" >&2; exit 1; }

echo
echo "Done. Developer ID Application identity is installed."
echo "Private key + cert live in: $WORK (gitignored). Keep them safe; do not commit."
