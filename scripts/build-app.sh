#!/bin/bash
set -euo pipefail
VIGGO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$VIGGO_ROOT" --scratch-path "$VIGGO_ROOT/.build" -c release
VIGGO_BIN="$(swift build --package-path "$VIGGO_ROOT" --scratch-path "$VIGGO_ROOT/.build" -c release --show-bin-path)"
VIGGO_APP="$VIGGO_ROOT/build/ViggoClean.app"
mkdir -p "$VIGGO_APP/Contents/MacOS" "$VIGGO_APP/Contents/Resources"
cp "$VIGGO_BIN/ViggoClean" "$VIGGO_APP/Contents/MacOS/ViggoClean"
cp "$VIGGO_ROOT/Info.plist" "$VIGGO_APP/Contents/Info.plist"
if [ -f "$VIGGO_ROOT/Resources/AppIcon.icns" ]; then
    cp "$VIGGO_ROOT/Resources/AppIcon.icns" "$VIGGO_APP/Contents/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --sign - --options runtime "$VIGGO_APP"
printf 'Built %s\n' "$VIGGO_APP"
