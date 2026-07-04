#!/bin/bash
# One-time setup: create a self-signed code-signing certificate ("rbFlow Dev")
# in the login keychain. Signing every build with this stable identity makes
# macOS TCC permissions (Microphone / Accessibility / Input Monitoring)
# persist across rebuilds. Re-running this script and creating a NEW identity
# resets those permissions.
set -euo pipefail

IDENTITY="rbFlow Dev"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Generating self-signed code-signing certificate '$IDENTITY'…"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -days 3650 -subj "/CN=$IDENTITY" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE"

# -legacy: OpenSSL 3 defaults to AES/SHA256 PKCS12 encoding, which
# `security import` cannot parse ("MAC verification failed").
openssl pkcs12 -export -legacy \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" \
    -out "$WORKDIR/rbflow.p12" -passout pass:rbflow

echo "Importing into login keychain…"
security import "$WORKDIR/rbflow.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P rbflow -T /usr/bin/codesign

echo "Trusting certificate for code signing (macOS will show an authorization dialog)…"
security add-trusted-cert -r trustRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$WORKDIR/cert.pem"

echo
echo "Done. Verify with: security find-identity -v -p codesigning"
echo "Note: the first codesign may show a keychain prompt — click 'Always Allow'."
