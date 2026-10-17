#!/bin/bash
# Build ClipHaven.app into build/ and sign it.
# Signs with this Mac's Developer ID Application identity, so Accessibility (auto-paste) and
# Keychain grants survive rebuilds; falls back to ad-hoc ("-") when there is none.
# SIGN_IDENTITY overrides the choice.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64
app=build/ClipHaven.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$(swift build -c release --arch arm64 --show-bin-path)/ClipHaven" "$app/Contents/MacOS/ClipHaven"
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
codesign --force --sign "${identity:--}" "$app"
echo "built $app (signed: ${identity:-ad-hoc})"
