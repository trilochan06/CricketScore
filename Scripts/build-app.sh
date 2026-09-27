#!/bin/zsh
# Builds build/CricketScore.app.
#
#   ./Scripts/build-app.sh             # local build (native arch, ad-hoc signed)
#   ./Scripts/build-app.sh --install   # …and copy it to /Applications
#
# Optional environment (used by Scripts/release.sh):
#   VERSION=1.0.0 BUILD_NUMBER=1          version shown in Finder / used for update checks
#   SERVER_URL=https://your-app.vercel.app   baked in as the app's default live server
#   UNIVERSAL=1                           Apple Silicon + Intel (needs full Xcode)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   real signing + hardened runtime
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="CricketScore"
BUNDLE_ID="${BUNDLE_ID:-com.cricketscore.CricketScore}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_MACOS="14.0"
SERVER_URL="${SERVER_URL:-}"
APP="build/$NAME.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ Compiling (release${UNIVERSAL:+, universal})…"
swift build -c release --product "$NAME" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release --show-bin-path "${ARCH_FLAGS[@]}")/$NAME"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
[[ -f CricketScore/Resources/AppIcon.icns ]] || swift Scripts/make-icon.swift
cp CricketScore/Resources/AppIcon.icns "$APP/Contents/Resources/"
sed -e "s/\$(EXECUTABLE_NAME)/$NAME/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$MIN_MACOS/" \
    -e "s#\$(CRICKET_SERVER_URL)#$SERVER_URL#" \
    CricketScore/Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "▸ Signing with: $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=1 "$APP"
else
    echo "▸ Signing (ad-hoc, local use only)…"
    codesign --force --sign - --timestamp=none "$APP"
fi

if [[ "${1:-}" == "--install" ]]; then
    echo "▸ Installing to /Applications"
    pkill -x "$NAME" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" /Applications/
    echo "✓ Installed /Applications/$NAME.app"
else
    echo "✓ Built $APP — open it with: open $APP"
fi
