#!/bin/zsh
# Builds build/CricketScore.app with only the Xcode Command Line Tools.
#   ./Scripts/build-app.sh            # release build
#   ./Scripts/build-app.sh --install  # also copy to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="CricketScore"
BUNDLE_ID="${BUNDLE_ID:-com.cricketscore.CricketScore}"
VERSION="1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"
APP="build/$NAME.app"

echo "▸ Compiling (release)…"
swift build -c release --product "$NAME"
BIN="$(swift build -c release --show-bin-path)/$NAME"

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
    CricketScore/Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - --timestamp=none "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "▸ Installing to /Applications"
    pkill -x "$NAME" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" /Applications/
    echo "✓ Installed /Applications/$NAME.app"
else
    echo "✓ Built $APP — open it with: open $APP"
fi
