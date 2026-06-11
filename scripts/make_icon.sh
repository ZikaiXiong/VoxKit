#!/bin/bash
# Regenerate Resources/AppIcon.icns from Resources/icon.svg
# Uses only built-in system tools: qlmanage (SVG rendering), sips (resizing), iconutil (packaging)
set -euo pipefail
cd "$(dirname "$0")/../Resources"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

qlmanage -t -s 1024 -o "$TMP" icon.svg >/dev/null
PNG="$TMP/icon.svg.png"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"

sips -z 16 16     "$PNG" --out "$SET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$PNG" --out "$SET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$PNG" --out "$SET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$PNG" --out "$SET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$PNG" --out "$SET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$PNG" --out "$SET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$PNG" --out "$SET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$PNG" --out "$SET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$PNG" --out "$SET/icon_512x512.png"    >/dev/null
cp "$PNG" "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o AppIcon.icns
echo "✅ AppIcon.icns 已更新"
