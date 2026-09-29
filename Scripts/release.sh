#!/bin/zsh
# Public release: universal build → DMG → GitHub Release (CricketScore.dmg) → version.json
# on the website. Requires the GitHub CLI (`gh auth login`). Two modes:
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
command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || { echo "✗ GitHub CLI not logged in (brew install gh && gh auth login)"; exit 1; }
gh release view "v$VERSION" >/dev/null 2>&1 && { echo "✗ Release v$VERSION already exists"; exit 1; }
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

echo "▸ Publishing to GitHub Releases"
REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
ASSET_DIR="$(mktemp -d)"
cp "$DMG" "$ASSET_DIR/$NAME.dmg"   # stable asset name → /releases/latest/download/CricketScore.dmg always works
gh release create "v$VERSION" "$ASSET_DIR/$NAME.dmg#$NAME.dmg (macOS, universal)" \
    --repo "$REPO" --title "Cricket Score $VERSION" --latest \
    --notes "${NOTES:-Cricket Score $VERSION}

**Install:** download \`$NAME.dmg\`, drag the app to Applications, open it once$([[ -z "$SIGN_IDENTITY" ]] && echo ', then approve it in **System Settings → Privacy & Security → Open Anyway** (one time)').

Requires macOS 14 or later · Apple Silicon & Intel."
rm -rf "$ASSET_DIR"

echo "▸ Updating version.json (website download button + in-app update check)"
python3 - "$VERSION" "$NOTES" "$([[ -n "$SIGN_IDENTITY" ]] && echo true || echo false)" "$REPO" <<'PY'
import json, sys
version, notes, notarized, repo = sys.argv[1], sys.argv[2], sys.argv[3] == "true", sys.argv[4]
json.dump({"version": version,
           "url": f"https://github.com/{repo}/releases/latest/download/CricketScore.dmg",
           "releaseNotes": f"https://github.com/{repo}/releases/tag/v{version}",
           "minimumSystemVersion": "14.0", "notes": notes, "notarized": notarized},
          open("server/public/version.json", "w"), indent=2)
PY

echo
echo "✓ Released $VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
echo "  Now publish the version bump:  git add server/public/version.json && git commit -m \"Release $VERSION\" && git push"
echo "  (Vercel redeploys the site; installed apps see the update within a day.)"
