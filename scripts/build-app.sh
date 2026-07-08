#!/bin/bash
# Build LokVaani.app without Xcode: swift build → assemble bundle → codesign.
# Usage: ./scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
IDENTITY="LokVaani Dev"
APP="build/LokVaani.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/LokVaani"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LokVaani"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundle any SwiftPM resource bundles produced by dependencies.
BINDIR="$(dirname "$BIN")"
find "$BINDIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

echo "==> Code signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" \
        --identifier com.rahulbhardwaj.lokvaani "$APP"
else
    echo "WARNING: signing identity '$IDENTITY' not found — falling back to ad-hoc."
    echo "         TCC permissions will RESET on every rebuild."
    echo "         Run ./scripts/setup-signing.sh once to fix this."
    codesign --force --deep --sign - "$APP"
fi

echo "==> Built $APP"
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Authority|Signature)' || true
echo "Run with: open $APP"
