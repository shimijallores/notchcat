#!/bin/bash
# Builds NotchCat.app and packages it into build/NotchCat.dmg (unsigned).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build-app.sh"

STAGE="$ROOT/build/dmg"
DMG="$ROOT/build/NotchCat.dmg"

echo "==> Staging disk image contents"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$ROOT/build/NotchCat.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create -volname "NotchCat" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Done: $DMG"
