#!/bin/bash
# Build ClipHaven.app into build/ and sign it.
# SIGN_IDENTITY defaults to "-" (ad-hoc); set it to a stable identity for Keychain work.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64
app=build/ClipHaven.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$(swift build -c release --arch arm64 --show-bin-path)/ClipHaven" "$app/Contents/MacOS/ClipHaven"
codesign --force --sign "${SIGN_IDENTITY:--}" "$app"
echo "built $app"
