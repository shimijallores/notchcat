#!/bin/bash
# Builds NotchCat.app into ./build (release, ad-hoc signed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/NotchCat.app"
CONTENTS="$APP/Contents"

echo "==> Building (release)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchCat"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/NotchCat"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp brand/zi-mascot.png "$CONTENTS/Resources/mascot.png"

echo "==> Generating icon"
TMP="$(mktemp -d)"
swift scripts/make-icon.swift brand/zi-mascot.png "$TMP/icon-1024.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$TMP/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$TMP"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "Done: $APP"
