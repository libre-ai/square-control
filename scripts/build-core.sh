#!/bin/sh
# Builds the Rust core bridge, regenerates the UniFFI Swift bindings and packs the static
# library into a local xcframework consumed by the SwiftPM package (never committed).
set -eu
cd "$(git rev-parse --show-toplevel)"
# Machine paths never end up in the artefact (NFR-S7).
RUSTFLAGS="--remap-path-prefix=$(pwd)=. --remap-path-prefix=$HOME/.cargo=cargo --remap-path-prefix=$HOME/.rustup=rustup"
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
