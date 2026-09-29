#!/bin/zsh
# Public release: universal build → DMG → publish the DMG + version.json to the website
# (server/public). Two modes:
#
#   FREE (default, no Apple Developer account):
#     SERVER_URL="https://your-site.vercel.app" ./Scripts/release.sh 1.0.0 "What's new"
#     The app is ad-hoc signed; on first launch users approve it once in
#     System Settings → Privacy & Security → "Open Anyway" (explained on the website).
#
#   SIGNED + NOTARIZED (Apple Developer Program, $99/yr) — opens with no warning:
#   1. Apple Developer Program membership + full Xcode installed
#   2. A "Developer ID Application" certificate in your login keychain
#   3. xcrun notarytool store-credentials CricketScoreNotary \
#        --apple-id you@example.com --team-id ABCDE12345 --password <app-specific-password>
#
#   then add SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" to the command above.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> [notes]}"
NOTES="${2:-}"
: "${SERVER_URL:?Set SERVER_URL to your public website, e.g. https://your-site.vercel.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-CricketScoreNotary}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
NAME="CricketScore"
DMG="build/$NAME-$VERSION.dmg"

# Preflight
[[ "$SERVER_URL" == https://* ]] || { echo "✗ SERVER_URL must be https://"; exit 1; }
curl -fsS -m 15 -o /dev/null "$SERVER_URL/" || { echo "✗ $SERVER_URL is not responding"; exit 1; }
if [[ -n "$SIGN_IDENTITY" ]]; then
    security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" || { echo "✗ Certificate not found in keychain: $SIGN_IDENTITY"; exit 1; }
    xcrun --find notarytool >/dev/null 2>&1 || { echo "✗ notarytool not found — install Xcode"; exit 1; }
else
    echo "ℹ︎ Free release: ad-hoc signed, not notarized. Users approve it once on first launch."
fi

echo "▸ Building $NAME $VERSION ($BUILD_NUMBER) for $SERVER_URL"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" SERVER_URL="$SERVER_URL" UNIVERSAL=1 \
    SIGN_IDENTITY="$SIGN_IDENTITY" ./Scripts/build-app.sh
lipo -archs "build/$NAME.app/Contents/MacOS/$NAME"

echo "▸ Creating DMG"
STAGING="$(mktemp -d)"
cp -R "build/$NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
if [[ -z "$SIGN_IDENTITY" ]]; then
    cat > "$STAGING/How to open.txt" <<'TXT'
Cricket Score — first launch

1. Drag CricketScore into the Applications folder.
2. Open it. macOS will say it can't verify the developer — click "Done".
   (The app is free and open, but not paid-signed with Apple.)
3. Open System Settings → Privacy & Security, scroll down, and click "Open Anyway"
   next to "CricketScore". Confirm with your password.

You only do this once. After that it opens normally, and it will show
"Update available" in its menu when a new version is out.
TXT
fi
rm -f "$DMG"
hdiutil create -volname "Cricket Score" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    echo "▸ Notarizing (usually 1–5 minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "▸ Publishing to the website"
mkdir -p server/public/downloads
cp "$DMG" "server/public/downloads/$NAME.dmg"
python3 - "$VERSION" "$NOTES" "$([[ -n "$SIGN_IDENTITY" ]] && echo true || echo false)" <<'PY'
import json, sys
json.dump({"version": sys.argv[1], "url": "/downloads/CricketScore.dmg", "minimumSystemVersion": "14.0", "notes": sys.argv[2],
           "notarized": sys.argv[3] == "true"},
          open("server/public/version.json", "w"), indent=2)
PY

echo
echo "✓ Release $VERSION ready: $DMG ($([[ -n "$SIGN_IDENTITY" ]] && echo notarized || echo free, ad-hoc signed))."
echo "  Publish it with:  git add server/public/downloads server/public/version.json && git commit -m \"Release $VERSION\" && git push"
echo "  Vercel redeploys automatically; installed apps will see the update within a day."
