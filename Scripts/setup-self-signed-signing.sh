#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

identity="${LOCAL_CODE_SIGN_IDENTITY:-ClipboardApp Local Code Signing}"
keychain="${CODE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/clipboard-signing.keychain-db}"
password="${CLIPBOARD_SIGNING_KEYCHAIN_PASSWORD:-clipboard-local-signing}"
days="${CLIPBOARD_SIGNING_DAYS:-3650}"

if [[ -f "$keychain" ]]; then
  echo "using existing keychain: $keychain" >&2
else
  echo "creating keychain: $keychain" >&2
  security create-keychain -p "$password" "$keychain"
fi

security unlock-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"

trust_identity() {
  local certificate_path="$1"
  security add-trusted-cert \
    -d \
    -r trustRoot \
    -k "$keychain" \
    "$certificate_path" >/dev/null
}

if security find-identity -v -p codesigning "$keychain" | grep -Fq "\"$identity\""; then
  echo "signing identity already exists: $identity" >&2
else
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  cat > "$tmp_dir/codesign.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = codesign_ext

[ dn ]
CN = $identity

[ codesign_ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
EOF

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -nodes \
    -days "$days" \
    -keyout "$tmp_dir/signing.key" \
    -out "$tmp_dir/signing.crt" \
    -config "$tmp_dir/codesign.cnf" >/dev/null 2>&1

  openssl pkcs12 \
    -export \
    -inkey "$tmp_dir/signing.key" \
    -in "$tmp_dir/signing.crt" \
    -name "$identity" \
    -passout "pass:$password" \
    -out "$tmp_dir/signing.p12" >/dev/null 2>&1

  security import "$tmp_dir/signing.p12" \
    -k "$keychain" \
    -P "$password" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
  trust_identity "$tmp_dir/signing.crt"

  security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$password" \
    "$keychain" >/dev/null

  echo "created signing identity: $identity" >&2
fi

if ! security find-identity -v -p codesigning "$keychain" | grep -Fq "\"$identity\""; then
  tmp_cert="$(mktemp)"
  security find-certificate -c "$identity" -p "$keychain" > "$tmp_cert"
  trust_identity "$tmp_cert"
  rm -f "$tmp_cert"
fi

probe="$PWD/.build/signing-probe"
mkdir -p "$(dirname "$probe")"
cp /usr/bin/true "$probe"
codesign --force --sign "$identity" --keychain "$keychain" "$probe" >/dev/null
rm -f "$probe"

cat <<EOF
Self-signed signing is ready.

Use:
  CODE_SIGN_KEYCHAIN="$keychain" \\
  LOCAL_CODE_SIGN_IDENTITY="$identity" \\
  REQUIRE_STABLE_CODE_SIGNING=1 \\
  Scripts/build-app-bundle.sh
EOF
