#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
DIST="dist"
APP_NAME="Claude KeepAwake"
BINARY="$DIST/$APP_NAME.app/Contents/MacOS/ClaudeKeepAwake"
ASSET="$DIST/claude-keepawake.tar.gz"

rm -rf "$DIST"
mkdir -p "$DIST/$APP_NAME.app/Contents/MacOS"

cat > "$DIST/$APP_NAME.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>ClaudeKeepAwake</string>
    <key>CFBundleIdentifier</key><string>com.claude-keepawake.menu</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Claude KeepAwake</string>
    <key>CFBundleDisplayName</key><string>Claude KeepAwake</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

swiftc -O -target arm64-apple-macosx13.0 -o "$BINARY.arm64" main.swift
swiftc -O -target x86_64-apple-macosx13.0 -o "$BINARY.x86_64" main.swift
lipo -create -output "$BINARY" "$BINARY.arm64" "$BINARY.x86_64"
rm -f "$BINARY.arm64" "$BINARY.x86_64"

cp scripts/claude-keepawake-agent.sh "$DIST/claude-keepawake-agent"
chmod +x "$DIST/claude-keepawake-agent"

tar -czf "$ASSET" -C "$DIST" "$APP_NAME.app" claude-keepawake-agent

echo "Built $ASSET (version $VERSION, universal arm64 + x86_64)"
