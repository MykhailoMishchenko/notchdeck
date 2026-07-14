#!/bin/bash
# inputs {-c debug|release}, does {builds SPM binary and wraps it into NotchDeck.app bundle}, returns {path to .app}
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/NotchDeck.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

swift build -c "$CONFIG" --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/$CONFIG/NotchDeck" "$APP/Contents/MacOS/NotchDeck"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NotchDeck</string>
    <key>CFBundleIdentifier</key>
    <string>dev.notchdeck.app</string>
    <key>CFBundleName</key>
    <string>NotchDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>NotchDeck shows your next calendar event in the notch panel.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>NotchDeck shows your next calendar event in the notch panel.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotchDeck controls playback in Spotify and Music.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
