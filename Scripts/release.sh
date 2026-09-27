#!/bin/zsh
# Public release: universal build → Developer ID signing → DMG → Apple notarization →
# staple → publish the DMG + version.json to the website (server/public).
#
# One-time setup (see README → "Shipping"):
#   1. Apple Developer Program membership + full Xcode installed
#   2. A "Developer ID Application" certificate in your login keychain
#   3. xcrun notarytool store-credentials CricketScoreNotary \
#        --apple-id you@example.com --team-id ABCDE12345 --password <app-specific-password>
#
# Each release:
#   SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" \
#   SERVER_URL="https://your-app.vercel.app" \
#   ./Scripts/release.sh 1.0.0 "What's new in this version"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> [notes]}"
NOTES="${2:-}"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your \"Developer ID Application: …\" certificate name}"
: "${SERVER_URL:?Set SERVER_URL to your public server, e.g. https://your-app.vercel.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-CricketScoreNotary}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
NAME="CricketScore"
DMG="build/$NAME-$VERSION.dmg"

# Preflight
xcode-select -p | grep -q "Xcode.app" || { echo "✗ Full Xcode is required (xcode-select -s /Applications/Xcode.app)"; exit 1; }
security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" || { echo "✗ Certificate not found in keychain: $SIGN_IDENTITY"; exit 1; }
[[ "$SERVER_URL" == https://* ]] || { echo "✗ SERVER_URL must be https://"; exit 1; }
curl -fsS -m 15 "$SERVER_URL/api/health" >/dev/null || { echo "✗ $SERVER_URL/api/health is not responding"; exit 1; }

echo "▸ Building $NAME $VERSION ($BUILD_NUMBER) for $SERVER_URL"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" SERVER_URL="$SERVER_URL" UNIVERSAL=1 \
    SIGN_IDENTITY="$SIGN_IDENTITY" ./Scripts/build-app.sh
lipo -archs "build/$NAME.app/Contents/MacOS/$NAME"

echo "▸ Creating DMG"
STAGING="$(mktemp -d)"
cp -R "build/$NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Cricket Score" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

echo "▸ Notarizing (usually 1–5 minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "▸ Publishing to the website"
mkdir -p server/public/downloads
cp "$DMG" "server/public/downloads/$NAME.dmg"
python3 - "$VERSION" "$NOTES" <<'PY'
import json, sys
json.dump({"version": sys.argv[1], "url": "/downloads/CricketScore.dmg", "minimumSystemVersion": "14.0", "notes": sys.argv[2]},
          open("server/public/version.json", "w"), indent=2)
PY

echo
echo "✓ Release $VERSION ready: $DMG (notarized)."
echo "  Publish it with:  git add server/public/downloads server/public/version.json && git commit -m \"Release $VERSION\" && git push"
echo "  Vercel redeploys automatically; installed apps will see the update within a day."
