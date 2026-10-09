#!/bin/sh
# AT-27 + AT-34 static gate on a built bundle (PROTOCOL.txt P6).
# usage: scripts/check-binary.sh <bundle.app> [--write-allowlist]
# Prints the volume it examined; an unreadable input is a failure, never a zero.
set -u
bundle="${1:?bundle}"
mode="${2:-check}"
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
allowlist="$root/scripts/symbols.allowlist"
executable="$bundle/Contents/MacOS/SquareControl"
plist="$bundle/Contents/Info.plist"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
violations=0
fail() { echo "VIOLATION: $*"; violations=$((violations + 1)); }

[ -r "$executable" ] || { echo "UNREADABLE: $executable"; exit 2; }
[ -r "$plist" ] || { echo "UNREADABLE: $plist"; exit 2; }

# 1. Imported symbols, with the library each one comes from.
nm -u -m "$executable" > "$work/nm.txt" 2>"$work/nm.err" || { echo "UNREADABLE: nm failed"; cat "$work/nm.err"; exit 2; }
sed -n 's/^ *(undefined) [a-z-]* *external \([^ ]*\) (from \([^)]*\)).*$/\2 \1/p' "$work/nm.txt" | sort -u > "$work/imports.txt"
symbols=$(wc -l < "$work/imports.txt" | tr -d ' ')
[ "$symbols" -gt 0 ] || { echo "UNREADABLE: 0 imported symbol parsed"; exit 2; }
if [ "$mode" = "--write-allowlist" ]; then
  cp "$work/imports.txt" "$allowlist"
  echo "allowlist written: $symbols symbols"
fi
[ -r "$allowlist" ] || { echo "UNREADABLE: $allowlist"; exit 2; }
comm -23 "$work/imports.txt" "$allowlist" > "$work/new.txt"
while read -r line; do fail "symbol outside the closed list: $line"; done < "$work/new.txt"

admitted='^(AppKit|ApplicationServices|HIServices|Carbon|HIToolbox|CoreGraphics|CoreFoundation|Foundation|libSystem|libobjc|libswiftCore|libswift_Concurrency|libswiftDarwin|libswiftDispatch|libswiftObjectiveC|libswiftFoundation|libswiftCoreFoundation|libswift_StringProcessing|libswiftSynchronization|libswiftos|libswiftOSLog|libswiftXPC|libswiftIOKit|libswiftCoreGraphics|libswiftAppKit|libswiftCoreImage|libswiftQuartzCore|libswiftMetal|libswiftUniformTypeIdentifiers|libswiftCoreData|libswift_errno|libswift_math|libswift_signal|libswift_stdio|libswift_time|libswiftsys_time|libswiftunistd|libswift_Builtin_float|libswiftSpatial|libswiftsimd|libswift_DarwinFoundation[0-9]*|libiconv|libresolv|libc\+\+|os|FoundationEssentials|FoundationInternationalization)$'
cut -d' ' -f1 "$work/imports.txt" | sort -u > "$work/libraries.txt"
libraries=$(wc -l < "$work/libraries.txt" | tr -d ' ')
while read -r library; do
  echo "$library" | grep -Eq "$admitted" || fail "symbol from a library outside the admitted set: $library"
done < "$work/libraries.txt"

denied='NSURLSession|_nw_|_socket$|_connect$|_getaddrinfo|_dlopen|_dlsym|_objc_getClass$|NSClassFromString|_AXUIElementGetWindow|_SLS|_CGS|_CGEventPost|CGEventKeyboardGetUnicodeString|CGWindowListCreateImage|CGRequestListenEventAccess|CGPreflightListenEventAccess|CGRequestScreenCaptureAccess|_task_for_pid|_ptrace'
grep -E "$denied" "$work/imports.txt" | while read -r line; do echo "VIOLATION: denied symbol: $line"; done > "$work/denied.txt"
[ -s "$work/denied.txt" ] && { cat "$work/denied.txt"; violations=$((violations + $(wc -l < "$work/denied.txt"))); }

# 2. Linked libraries.
otool -L "$executable" > "$work/otool.txt" || { echo "UNREADABLE: otool failed"; exit 2; }
linked=$(($(wc -l < "$work/otool.txt") - 1))
grep -E 'PrivateFrameworks|ScreenCaptureKit|CFNetwork|/Network.framework' "$work/otool.txt" | while read -r line; do echo "VIOLATION: linked: $line"; done > "$work/linked.txt"
[ -s "$work/linked.txt" ] && { cat "$work/linked.txt"; violations=$((violations + $(wc -l < "$work/linked.txt"))); }

# 3. Signature flags and entitlements.
codesign -dv "$bundle" > "$work/codesign.txt" 2>&1 || { echo "UNREADABLE: codesign -dv"; exit 2; }
grep -q 'flags=.*runtime' "$work/codesign.txt" || fail "hardened runtime absent"
codesign --verify --strict "$bundle" 2>"$work/verify.txt" || fail "signature does not verify: $(head -1 "$work/verify.txt")"
codesign -d --entitlements - --xml "$bundle" > "$work/entitlements.xml" 2>/dev/null || true
entitlements=$(grep -c '<key>' "$work/entitlements.xml" 2>/dev/null || true)
for key in get-task-allow disable-library-validation allow-dyld-environment-variables allow-unsigned-executable-memory allow-jit; do
  grep -q "$key" "$work/entitlements.xml" 2>/dev/null && fail "entitlement $key"
done

# 4. No URL scheme, no E2E channel, no machine path (AT-27, NFR-S7).
plutil -extract CFBundleURLTypes raw "$plist" >/dev/null 2>&1 && fail "Info.plist declares CFBundleURLTypes"
plist_keys=$(plutil -convert xml1 -o - "$plist" | grep -c '<key>')
strings -a "$executable" > "$work/strings.txt" || { echo "UNREADABLE: strings"; exit 2; }
string_count=$(wc -l < "$work/strings.txt" | tr -d ' ')
grep -q 'sc-e2e' "$work/strings.txt" && fail "E2E channel string present (sc-e2e)"
grep -Eq 'CFBundleURLSchemes|square-control://' "$work/strings.txt" && fail "URL scheme string present"
# Machine-path needles (owner decision Y40): generic prefixes plus this machine's own.
# Counted on raw bytes with rg -a, not on `strings`, which drops short runs.
cargo_home="${CARGO_HOME:-$HOME/.cargo}"
rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
count_in() { rg -a -o -F -- "$2" "$1" | wc -l | tr -d ' '; }
scan_paths() { # <file> <label> <generic: yes|no>
  [ -r "$1" ] && [ -s "$1" ] || { echo "UNREADABLE: $2"; exit 2; }
  scanned_files=$((scanned_files + 1))
  scanned_bytes=$((scanned_bytes + $(wc -c < "$1" | tr -d ' ')))
  if [ "$3" = yes ]; then set -- "$1" "$2" "/Us""ers/" '/home/' '.cargo/registry' '.rustup'; else set -- "$1" "$2"; fi
  file="$1"; label="$2"; shift 2
  for needle in "$@" "$HOME" "$cargo_home" "$rustup_home" "$root"; do
    hits=$(count_in "$file" "$needle")
    # Only the generic needles are printed verbatim; machine values are labelled.
    case "$needle" in "$HOME") name=HOME ;; "$cargo_home") name=CARGO_HOME ;; "$rustup_home") name=RUSTUP_HOME ;; "$root") name="repository root" ;; *) name="$needle" ;; esac
    [ "$hits" -gt 0 ] && fail "$label: $hits x $name"
  done
}
command -v rg >/dev/null || { echo "UNREADABLE: rg is required for the machine-path scan"; exit 2; }
scanned_files=0; scanned_bytes=0
scan_paths "$executable" "executable" yes
# The static core library linked into the executable. Its prebuilt std and
# compiler-builtins objects carry the Rust project's own CI path, which is not a
# path of this machine, so only this machine's prefixes are counted there.
scan_paths "$root/target/release/libsc_ffi.a" "libsc_ffi.a" no

echo "examined: imported_symbols=$symbols libraries=$libraries linked=$linked entitlements=$entitlements plist_keys=$plist_keys strings=$string_count path_scan_files=$scanned_files path_scan_bytes=$scanned_bytes"
echo "violations=$violations"
[ "$violations" -eq 0 ]
