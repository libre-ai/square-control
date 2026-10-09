#!/bin/sh
# Creates (once) the local self-signed code-signing identity used for dogfooding builds
# (spec v2 S-B6, NFR-S5): a stable designated requirement keeps the Accessibility grant
# across rebuilds, unlike an ad hoc signature whose requirement is the cdhash.
#
# The identity lives in a dedicated keychain file OUTSIDE the repository; it is never added to
# the keychain search list and never marked trusted (no trust-settings change). Its protection
# is the user account's file permissions: see the residual risk in the E0 report.
set -eu
repository="$(git rev-parse --show-toplevel)"
directory="$(dirname "$repository")/square-control-signing"
keychain="$directory/sc-local.keychain-db"
name="Square Control Local Signing"

if [ -f "$keychain" ]; then
  security find-certificate -c "$name" -Z "$keychain" | awk '/SHA-1 hash/ {print $3}'
  exit 0
fi

umask 077
mkdir -p "$directory"
work="$(mktemp -d "$directory/tmp.XXXXXX")"
trap 'rm -rf "$work"' EXIT

cat > "$work/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
# `security` resolves a relative keychain name under ~/Library/Keychains: always pass the
# absolute path held in $keychain.

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -config "$work/req.cnf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
# The PKCS#12 container needs a transport password; it is random and lives only in $work.
transport="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" \
  -out "$work/identity.p12" -passout "pass:$transport"

# Empty keychain password on purpose: a password stored next to the keychain would protect
# nothing more against a same-user process, and claiming otherwise would be false.
security create-keychain -p "" "$keychain"
security set-keychain-settings "$keychain"
security unlock-keychain -p "" "$keychain"
security import "$work/identity.p12" -k "$keychain" -P "$transport" -f pkcs12 -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$keychain" >/dev/null
security find-certificate -c "$name" -Z "$keychain" | awk '/SHA-1 hash/ {print $3}'
