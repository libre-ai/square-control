#!/bin/sh
# Builds the Rust core bridge, regenerates the UniFFI Swift bindings and packs the static
# library into a local xcframework consumed by the SwiftPM package (never committed).
set -eu
cd "$(git rev-parse --show-toplevel)"
# Machine paths never end up in the artefact (NFR-S7, owner decision Y40).
# Fixed targets, so two machines produce the same bytes; rustc applies the last
# matching prefix, so the most specific prefixes come last. CARGO_HOME and
# RUSTUP_HOME follow the environment, as cargo does.
for variable in CARGO_ENCODED_RUSTFLAGS CARGO_BUILD_RUSTFLAGS; do
  # Either one silently replaces RUSTFLAGS and would drop the remap.
  if [ -n "$(printenv "$variable" || true)" ]; then echo "refusing $variable: it would drop the path remap" >&2; exit 2; fi
done
if env | cut -d= -f1 | grep -Eq '^CARGO_TARGET_[A-Z0-9_]+_RUSTFLAGS$'; then
  echo "refusing CARGO_TARGET_*_RUSTFLAGS: it would drop the path remap" >&2; exit 2
fi
case "$HOME" in /|"") echo "refusing a root home directory" >&2; exit 2 ;; esac
cargo_home="${CARGO_HOME:-$HOME/.cargo}"
rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
for prefix in "$HOME" "$(pwd)" "$rustup_home" "$cargo_home"; do
  # RUSTFLAGS splits on spaces and rustc splits FROM=TO on the last '='.
  case "$prefix" in *" "*|*=*) echo "refusing a remap prefix holding a space or '='" >&2; exit 2 ;; esac
done
RUSTFLAGS="--remap-path-prefix=$HOME=~ --remap-path-prefix=$(pwd)=. --remap-path-prefix=$rustup_home=/rustup --remap-path-prefix=$cargo_home=/cargo"
export RUSTFLAGS
cargo build --locked --release -p sc_ffi -p uniffi-bindgen
rm -rf gen xcframework
./target/release/uniffi-bindgen generate --library target/release/libsc_ffi.a --language swift --out-dir gen
mkdir -p gen/headers
cp gen/sc_ffiFFI.h gen/headers/
cp gen/sc_ffiFFI.modulemap gen/headers/module.modulemap
xcodebuild -create-xcframework -library target/release/libsc_ffi.a -headers gen/headers \
  -output xcframework/SCCoreFFI.xcframework >/dev/null
mkdir -p shell/Sources/SCCore
cp gen/sc_ffi.swift shell/Sources/SCCore/sc_ffi.swift
echo "core bridge built: $(ls xcframework/SCCoreFFI.xcframework)"
