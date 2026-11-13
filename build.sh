#!/bin/sh
# Builds QuickCut.app next to this script and prints its path. Usage: ./build.sh [--release]
# --release builds the Release configuration, the one that checks for updates (see docs/RELEASING.md).
# Without it, a debug build that never does.
set -e
cd "$(dirname "$0")"
# scripts/release.sh bumps these.
MARKETING_VERSION=1.0.0
CURRENT_PROJECT_VERSION=0
CONFIG=debug
[ "$1" = --release ] && CONFIG=release
swift build -c $CONFIG >&2
BIN=$(swift build -c $CONFIG --show-bin-path)
APP=QuickCut.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
# SwiftPM stamps the binary with sdk = deployment target (15.0), which makes AppKit draw
# the window in the old compatibility style (misaligned sidebar/toolbar). Stamp the real SDK.
xcrun vtool -set-build-version macos 15.0 "$(xcrun --show-sdk-version)" -replace \
  -output "$APP/Contents/MacOS/QuickCut" "$BIN/QuickCut"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
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
  <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$CURRENT_PROJECT_VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>${QUICKCUT_FEED_URL:-https://raw.githubusercontent.com/fabiogiolito/quickcut/main/appcast.xml}</string>
  <key>SUPublicEDKey</key><string>CiOG7GD4UzfXgCyXUwujMg/9QBYxouIgEMot+wgM2Tk=</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict></plist>
PLIST
# Ad-hoc; scripts/release.sh re-signs with the Developer ID.
codesign -s - -f --deep "$APP" 2>/dev/null
echo "$PWD/$APP"
