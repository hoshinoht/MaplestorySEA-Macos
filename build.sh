#!/bin/bash
# Builds MapleSEA Installer.app from the Swift package and ad-hoc signs it.
# Requires only the Xcode Command Line Tools (no full Xcode).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MapleSEA Installer"
BUNDLE_DIR="build/${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

echo "==> Assembling ${BUNDLE_DIR}"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"
cp ".build/release/MapleSEAInstaller" "$BUNDLE_DIR/Contents/MacOS/MapleSEAInstaller"
cp "Resources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --sign - "$BUNDLE_DIR"

echo "==> Done: $BUNDLE_DIR"
echo "    First launch: right-click the app, or approve it under"
echo "    System Settings > Privacy & Security > 'Open Anyway'."
