#!/bin/bash
# Builds, signs, notarizes, and packages Inkdown into dist/Inkdown-<version>.dmg.
#
# Full pipeline requires two one-time setups by the account owner:
#   1. A "Developer ID Application" certificate in the keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + )
#   2. Notary credentials stored as profile "inkdown":
#      xcrun notarytool store-credentials inkdown \
#        --apple-id <apple-id> --team-id <team-id>
#      (password: app-specific password from appleid.apple.com)
#
# Without them the script still produces a DMG, but Gatekeeper will block
# it on other people's Macs.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=MarkReaderMac
VERSION=$(awk '/MARKETING_VERSION/{gsub(/"/, "", $2); print $2; exit}' project.yml)
DMG="dist/Inkdown-$VERSION.dmg"

IDENTITY=$(security find-identity -v -p codesigning \
    | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"' || true)

echo "== Building Inkdown $VERSION (Release) =="
if [ -n "$IDENTITY" ]; then
    echo "Signing with: $IDENTITY"
    xcodebuild -project MarkReader.xcodeproj -scheme "$SCHEME" \
        -destination 'platform=macOS,arch=arm64' -configuration Release \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$IDENTITY" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        clean build | tail -2
else
    echo "No Developer ID certificate found; building with default signing."
    xcodebuild -project MarkReader.xcodeproj -scheme "$SCHEME" \
        -destination 'platform=macOS,arch=arm64' -configuration Release \
        clean build | tail -2
fi

PRODUCTS=$(xcodebuild -project MarkReader.xcodeproj -scheme "$SCHEME" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk '/ BUILT_PRODUCTS_DIR/{print $3}' | head -1)
APP="$PRODUCTS/Inkdown.app"
codesign --verify --deep --strict "$APP"

echo "== Packaging $DMG =="
mkdir -p dist
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Inkdown.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Inkdown" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    if xcrun notarytool history --keychain-profile inkdown >/dev/null 2>&1; then
        echo "== Notarizing (this waits for Apple) =="
        xcrun notarytool submit "$DMG" --keychain-profile inkdown --wait
        xcrun stapler staple "$DMG"
        echo "Notarized and stapled."
    else
        echo "WARNING: no notary profile; DMG is signed but NOT notarized."
    fi
else
    echo "WARNING: DMG is not Developer ID signed; other Macs will block it."
fi

echo "Done: $DMG"
ls -lh "$DMG"
