#!/bin/bash
# inputs {-c debug|release}, does {builds SPM binary and wraps it into NotchDeck.app bundle}, returns {path to .app}
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/NotchDeck.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

swift build -c "$CONFIG" --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons"
cp "$ROOT/.build/$CONFIG/NotchDeck" "$APP/Contents/MacOS/NotchDeck"
cp "$ROOT/.build/$CONFIG/NotchDeckFanHelper" "$APP/Contents/MacOS/NotchDeckFanHelper"

cat > "$APP/Contents/Library/LaunchDaemons/dev.notchdeck.fanhelperd.plist" <<'DAEMON'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.notchdeck.fanhelperd</string>
    <key>BundleProgram</key>
    <string>Contents/MacOS/NotchDeckFanHelper</string>
    <key>MachServices</key>
    <dict>
        <key>dev.notchdeck.fanhelperd</key>
        <true/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>dev.notchdeck.app</string>
    </array>
</dict>
</plist>
DAEMON

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

# CODESIGN_IDENTITY: set to a stable identity (e.g. "Apple Development: ...") so TCC grants
# survive rebuilds; ad-hoc ("-") re-signs every build and macOS re-prompts for calendar access.
# The nested daemon is signed first, then the bundle.
codesign --force --sign "${CODESIGN_IDENTITY:--}" --identifier dev.notchdeck.fanhelperd \
    "$APP/Contents/MacOS/NotchDeckFanHelper" >/dev/null 2>&1 || true
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP" >/dev/null 2>&1 || true
echo "$APP"
