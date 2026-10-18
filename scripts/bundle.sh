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
mkdir -p "$app/Contents/Resources"
cp -R Resources/script "$app/Contents/Resources/script"
cp -R Resources/StatusIcons "$app/Contents/Resources/StatusIcons"
cp -R Resources/Help "$app/Contents/Resources/Help"
cp "$(swift build -c release --arch arm64 --show-bin-path)/ClipHaven" "$app/Contents/MacOS/ClipHaven"
# The app icon is ClipMenu's own clipboard (MIT-licensed, see Resources/script/LICENSE-ClipMenu.txt) with a red
# "CH" added: Resources/AppIcon.icon holds the artwork. Xcode's actool turns it into the layered icon macOS Tahoe expects, so it is not boxed in a grey tile.
# Without Xcode, a plain .icns made from the same drawing is used instead.
icon_work="$(mktemp -d)"
icon_src="$icon_work/AppIcon.icon"
mkdir -p "$icon_work/out"
cp -R Resources/AppIcon.icon "$icon_src"
if xcrun --find actool >/dev/null 2>&1 && xcrun actool "$icon_src" --compile "$icon_work/out" --platform macosx \
        --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$icon_work/partial.plist" >/dev/null 2>&1; then
    cp "$icon_work/out/Assets.car" "$icon_work/out/AppIcon.icns" "$app/Contents/Resources/"
else
    echo "actool unavailable: using a plain .icns"
    iconset="$icon_work/AppIcon.iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$icon_src/Assets/layer.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" "$icon_src/Assets/layer.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
fi
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
# The Keychain features that need an entitlement (iCloud-synchronizable items, Keychain-enforced
# Touch ID) work only with a provisioning profile for com.shavenconsulting.ClipHaven. Point
# PROVISION_PROFILE at it (default ~/.cliphaven/ClipHaven.provisionprofile); without one the app is
# signed with no entitlements, because a restricted entitlement with no profile will not launch.
profile="${PROVISION_PROFILE:-$HOME/.cliphaven/ClipHaven.provisionprofile}"
if [ -f "$profile" ] && [ -n "$identity" ]; then
    cp "$profile" "$app/Contents/embedded.provisionprofile"
    codesign --force --sign "$identity" --entitlements Resources/ClipHaven.entitlements --options runtime "$app"
    echo "entitlements: embedded $profile"
else
    codesign --force --sign "${identity:--}" "$app"
fi
echo "built $app (signed: ${identity:-ad-hoc})"
