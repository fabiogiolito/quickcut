#!/bin/sh
# Builds QuickCut.app next to this script.
set -e
cd "$(dirname "$0")"
swift build -c release >&2
APP=QuickCut.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
# SwiftPM stamps the binary with sdk = deployment target (15.0), which makes AppKit draw
# the window in the old compatibility style (misaligned sidebar/toolbar). Stamp the real SDK.
xcrun vtool -set-build-version macos 15.0 "$(xcrun --show-sdk-version)" -replace \
  -output "$APP/Contents/MacOS/QuickCut" .build/release/QuickCut
mkdir -p "$APP/Contents/Resources"
# Compile the Icon Composer icon into Assets.car (macOS 26 Liquid Glass) + QuickCut.icns (older macOS).
xcrun actool QuickCut.icon --compile "$APP/Contents/Resources" --app-icon QuickCut \
  --platform macosx --minimum-deployment-target 15.0 \
  --output-partial-info-plist /dev/null >/dev/null
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>QuickCut</string>
  <key>CFBundleIdentifier</key><string>com.fabiogiolito.QuickCut</string>
  <key>CFBundleExecutable</key><string>QuickCut</string>
  <key>CFBundleIconFile</key><string>QuickCut</string>
  <key>CFBundleIconName</key><string>QuickCut</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign -s - -f "$APP" 2>/dev/null
echo "$PWD/$APP"
