#!/bin/zsh
set -euo pipefail

# One-time local code signing identity. A self-signed certificate keeps the
# app's code identity stable across rebuilds, so macOS TCC grants (Desktop /
# Documents / Downloads / Full Disk Access) survive every build. ad-hoc
# signatures only pin a cdhash, which changes on every build.

identity="Zmole Local Signing"
login_keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -qF "$identity"; then
    printf '%s\n' "signing identity already present: $identity"
    exit 0
fi

work="$(mktemp -d)"
trap 'command rm -rf "$work"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$work/key.pem" -out "$work/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=$identity" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE"

password="$(openssl rand -hex 16)"
openssl pkcs12 -export -legacy -out "$work/id.p12" \
    -inkey "$work/key.pem" -in "$work/cert.pem" -passout "pass:$password"

security import "$work/id.p12" -k "$login_keychain" -P "$password" \
    -A -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign "$work/cert.pem"

printf '%s\n' "signing identity created: $identity"
security find-identity -v -p codesigning
