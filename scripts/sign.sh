#!/bin/sh
# Signs a bundle with hardened runtime (NFR-S5): with the local identity when codesign can use
# it, else ad hoc -- and says which, because an ad hoc designated requirement is the cdhash
# and loses the Accessibility grant at every build (S-B6).
# usage: scripts/sign.sh <bundle or binary> <identifier>
set -eu
target="$1"
identifier="$2"
repository="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
keychain="$(dirname "$repository")/square-control-signing/sc-local.keychain-db"
name="Square Control Local Signing"

mode="adhoc"
if [ -f "$keychain" ]; then
  hash="$(security find-certificate -c "$name" -Z "$keychain" | awk '/SHA-1 hash/ {print $3}')"
  if codesign --force --options runtime --timestamp=none --identifier "$identifier" \
      --keychain "$keychain" --sign "$hash" "$target" 2>/dev/null; then
    mode="local-identity"
  fi
fi
if [ "$mode" = "adhoc" ]; then
  codesign --force --options runtime --timestamp=none --identifier "$identifier" --sign - "$target"
fi
echo "signed mode=$mode identifier=$identifier"
codesign -dv "$target" 2>&1 | grep -E "^(Identifier|CodeDirectory|CDHash|Authority|Signature)="
printf 'designated: '
codesign -d -r- "$target" 2>&1 | grep -E "designated =>" || echo "(none)"
