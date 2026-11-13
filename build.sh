#!/bin/sh
# Builds QuickCut.app next to this script.
set -e
cd "$(dirname "$0")"
swift build -c release >&2
APP=QuickCut.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp .build/release/QuickCut "$APP/Contents/MacOS/"
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
