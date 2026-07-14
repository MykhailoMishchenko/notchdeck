#!/bin/bash
# inputs {}, does {builds a release NotchDeck.app and packs it into a distributable DMG with an /Applications shortcut}, returns {path to dmg}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DMG="$ROOT/.build/NotchDeck-$VERSION.dmg"
STAGE="$ROOT/.build/dmg-stage"

"$ROOT/scripts/bundle.sh" release >/dev/null

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$ROOT/.build/NotchDeck.app" "$STAGE/NotchDeck.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "NotchDeck $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
