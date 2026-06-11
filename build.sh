#!/bin/bash
# Build and package VoxKit.app
# Compiles with swiftc directly so only the Xcode Command Line Tools are required
set -euo pipefail
cd "$(dirname "$0")"

ARCH="$(uname -m)"
echo "▸ Building (release, ${ARCH})…"
mkdir -p .build

swiftc -O -parse-as-library -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -module-name VoxKit \
  Sources/VoxKit/*.swift \
  -o .build/VoxKit

APP="dist/VoxKit.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/VoxKit "$APP/Contents/MacOS/VoxKit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# Localized display names and permission prompts (per-language lproj bundles)
for lproj in Resources/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# Signing: ad-hoc by default; export SIGN_ID to sign properly with a Developer ID
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh --zip
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP"
  echo "▸ Signed with Developer ID: $SIGN_ID"
else
  codesign --force --deep --sign - "$APP"
fi

echo "✅ Done: $PWD/$APP"
echo "   First run: open \"$PWD/$APP\" (macOS will ask for microphone/speech permissions)"

# --zip: build the distribution archive (see DISTRIBUTION.md)
if [[ "${1:-}" == "--zip" ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  ZIP="dist/VoxKit-${VERSION}.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "📦 Distributable: $PWD/$ZIP"
fi
