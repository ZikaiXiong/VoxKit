#!/bin/bash
# Build and package VoxNote.app
# Compiles with swiftc directly (this machine's CLT has a broken SwiftPM manifest library; switch back to swift build once full Xcode is installed)
set -euo pipefail
cd "$(dirname "$0")"

ARCH="$(uname -m)"
echo "▸ 编译 (release, ${ARCH})…"
mkdir -p .build

swiftc -O -parse-as-library -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -module-name VoxNote \
  Sources/VoxNote/*.swift \
  -o .build/VoxNote

APP="dist/VoxNote.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/VoxNote "$APP/Contents/MacOS/VoxNote"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# Localized display name & permission prompts (Finder shows 声记 on Chinese systems)
for lproj in Resources/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# Signing: ad-hoc by default; export SIGN_ID to sign properly with a Developer ID
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh --zip
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP"
  echo "▸ 已用 Developer ID 签名：$SIGN_ID"
else
  codesign --force --deep --sign - "$APP"
fi

echo "✅ 完成：$PWD/$APP"
echo "   首次运行：open \"$PWD/$APP\"（系统会请求麦克风/语音识别权限）"

# --zip: build the distribution archive (see DISTRIBUTION.md)
if [[ "${1:-}" == "--zip" ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  ZIP="dist/VoxNote-${VERSION}.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "📦 分发包：$PWD/$ZIP"
fi
