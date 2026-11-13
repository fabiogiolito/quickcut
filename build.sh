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
codesign -s - -f "$APP/Contents/MacOS/QuickCut" 2>/dev/null
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>QuickCut</string>
  <key>CFBundleIdentifier</key><string>com.fabiogiolito.QuickCut</string>
  <key>CFBundleExecutable</key><string>QuickCut</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "$PWD/$APP"
