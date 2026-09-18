#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PRODUCT="${1:-$ROOT/.build/arm64-apple-macosx/release/TrackerTrapperMenuBar}"
OUT="${2:-$ROOT/dist/TrackerTrapper.app}"

[ -x "$PRODUCT" ] || { echo "Build the menu-bar product first: swift build -c release --product TrackerTrapperMenuBar" >&2; exit 1; }
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/tracker-trapper-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK"' EXIT HUP INT TERM
ICONSET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/Assets/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$ROOT/Assets/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"
cp "$PRODUCT" "$OUT/Contents/MacOS/TrackerTrapper"
cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TrackerTrapper</string>
<key>CFBundleIdentifier</key><string>com.shelbyklein.trackertrapper</string>
<key>CFBundleName</key><string>Tracker Trapper</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "$OUT"
