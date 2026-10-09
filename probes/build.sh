#!/bin/sh
# Builds the probe bundles (TapProbe, HotkeyProbe, SCHelper) and the injector, signed with
# hardened runtime. Output: probes/build/ (not versioned).
set -eu
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
out=probes/build
mkdir -p "$out"
SWIFTFLAGS="-O -swift-version 6 -warnings-as-errors"

bundle() {
  name="$1"; identifier="$2"; source="$3"; shift 3
  app="$out/$name.app"
  mkdir -p "$app/Contents/MacOS"
  # shellcheck disable=SC2086
  swiftc $SWIFTFLAGS -o "$app/Contents/MacOS/$name" "$source" "$@"
  cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$identifier</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
EOF
  scripts/sign.sh "$app" "$identifier"
}

bundle TapProbe org.libre-ai.square-control.probe.tap probes/src/TapProbe.swift
bundle HotkeyProbe org.libre-ai.square-control.probe.hotkey probes/src/HotkeyProbe.swift -framework Carbon
bundle SCHelper org.libre-ai.square-control.helper probes/src/Helper.swift
# shellcheck disable=SC2086
swiftc $SWIFTFLAGS -o "$out/injector" probes/src/Injector.swift
echo "probes built in $out"
