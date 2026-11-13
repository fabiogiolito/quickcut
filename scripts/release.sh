#!/bin/sh
# Builds, signs, notarizes and (with --publish) releases QuickCut on GitHub with an appcast.xml item for Sparkle.
# See docs/RELEASING.md.
# Usage: scripts/release.sh [version] [release-notes.md] [--publish]
# Without a version: the patch number after the last v* tag (1.0.0 -> 1.0.1), or MARKETING_VERSION if there's no tag.
# Without notes: the commit subjects since the last tag.
# Without --publish nothing goes online (except notarization): the build bump and appcast item are left in the
# working tree and the publish commands are printed.
# Env: DEVELOPER_ID  signing identity. Defaults to the Developer ID Application certificate in the keychain.
#      ASC_ENV       App Store Connect API key for notarytool (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).
#                    Defaults to ~/.appstoreconnect/shift.env (the key is for the whole developer account).
set -e
cd "$(dirname "$0")/.."
die() { echo "release: $*" >&2; exit 1; }

PUBLISH=0 VERSION= NOTES=
for a do
  case $a in
    --publish) PUBLISH=1 ;;
    -*) die "unknown option $a" ;;
    *) if [ -z "$VERSION" ]; then VERSION=$a; else NOTES=$a; fi ;;
  esac
done

: "${DEVELOPER_ID:=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
[ -n "$DEVELOPER_ID" ] || die "no Developer ID Application certificate in the keychain"
ASC_ENV=${ASC_ENV:-$HOME/.appstoreconnect/shift.env}
[ -f "$ASC_ENV" ] || die "no App Store Connect API key file at $ASC_ENV"
. "$ASC_ENV"
[ -f "$ASC_KEY_PATH" ] || die "no API key at $ASC_KEY_PATH (from $ASC_ENV)"
[ -z "$NOTES" ] || [ -f "$NOTES" ] || die "no such file: $NOTES"
[ -z "$(git status --porcelain)" ] || die "uncommitted changes; commit or stash them first"
[ "$PUBLISH" = 0 ] || [ "$(git branch --show-current)" = main ] || die "not on main"

# 1. Version and build number.
LAST=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
if [ -z "$VERSION" ]; then
  if [ -n "$LAST" ]; then VERSION=$(echo "${LAST#v}" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }')
  else VERSION=$(sed -n 's/^MARKETING_VERSION=//p' build.sh); fi
fi
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || die "tag v$VERSION already exists"
! grep -qs "<sparkle:shortVersionString>$VERSION<" appcast.xml || die "appcast.xml already has $VERSION"
# Sparkle compares the build number, so every release gets the next one.
BUILD=$(( $(sed -n 's/^CURRENT_PROJECT_VERSION=//p' build.sh) + 1 ))
sed -i '' -e "s/^MARKETING_VERSION=.*/MARKETING_VERSION=$VERSION/" \
  -e "s/^CURRENT_PROJECT_VERSION=.*/CURRENT_PROJECT_VERSION=$BUILD/" build.sh
trap '[ -n "$DONE" ] || git checkout -q build.sh appcast.xml' EXIT
echo "release: QuickCut $VERSION (build $BUILD), signing with $DEVELOPER_ID" >&2

mkdir -p dist
if [ -z "$NOTES" ]; then
  NOTES=dist/notes-$VERSION.md
  git log --no-merges --format='- %s' ${LAST:+$LAST..}HEAD > "$NOTES"
fi

# 2. Release build.
./build.sh --release >/dev/null
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
APP=dist/QuickCut.app
rm -rf "$APP"
ditto QuickCut.app "$APP"

# 3. Developer ID signature, inside out: Sparkle's helpers, the framework, then the app (Sparkle's documented order).
sign() { codesign -f -s "$DEVELOPER_ID" -o runtime --timestamp "$@"; }
S=$APP/Contents/Frameworks/Sparkle.framework
sign "$S/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$S/Versions/B/XPCServices/Downloader.xpc"
sign "$S/Versions/B/Autoupdate"
sign "$S/Versions/B/Updater.app"
sign "$S"
sign "$APP"
codesign --verify --deep --strict "$APP"

# 4. Notarize and staple.
ditto -c -k --keepParent "$APP" dist/notarize.zip
xcrun notarytool submit dist/notarize.zip --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait >&2
rm dist/notarize.zip
xcrun stapler staple "$APP" >&2
spctl -a -t exec "$APP"

# 5. Zip.
ZIP=dist/QuickCut-$VERSION.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 6–7. Sign the zip for Sparkle and add the appcast item.
SIGNATURE=$("$SPARKLE_BIN/sign_update" --account QuickCut "$ZIP")
ITEM=$(mktemp)
cat > "$ITEM" <<ITEM
    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[$(cat "$NOTES")]]></description>
      <enclosure url="https://github.com/fabiogiolito/quickcut/releases/download/v$VERSION/QuickCut-$VERSION.zip" $SIGNATURE type="application/octet-stream"/>
    </item>
ITEM
awk -v item="$ITEM" '/<\/channel>/ { while ((getline l < item) > 0) print l } { print }' appcast.xml > appcast.xml.new
mv appcast.xml.new appcast.xml
rm "$ITEM"
DONE=1

# 8–9. Commit, tag, push, GitHub release. main is pushed last, so no copy sees the appcast item before its zip
# is downloadable.
CMDS="git commit -m 'Release $VERSION' build.sh appcast.xml
git tag v$VERSION
git push origin v$VERSION
gh release create v$VERSION $ZIP --title 'QuickCut $VERSION' --notes-file $NOTES
git push origin main"

echo "Built $ZIP (build $BUILD, Developer ID, notarized); appcast.xml updated."
if [ "$PUBLISH" = 1 ]; then
  echo "$CMDS" | sh -ex
else
  echo "To publish, run (or discard with: git checkout build.sh appcast.xml):"
  echo "$CMDS" | sed 's/^/  /'
fi
