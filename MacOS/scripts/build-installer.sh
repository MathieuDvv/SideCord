#!/bin/bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$MACOS_DIRECTORY/.build/ReleaseDerivedData}"
OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY:-$MACOS_DIRECTORY/dist}"
VERSION="${SIDECORD_VERSION:-2.5.0}"
PRODUCT="$DERIVED_DATA_PATH/Build/Products/Release/SideCord.app"
DMG_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/sidecord-dmg.XXXXXX")"
DISK_IMAGE="$OUTPUT_DIRECTORY/SideCord-macOS-universal-$VERSION.dmg"

cleanup() {
  rm -rf "$DMG_STAGING"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIRECTORY"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcodebuild \
    -project "$MACOS_DIRECTORY/SideCord.xcodeproj" \
    -scheme SideCord \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

test -d "$PRODUCT"
lipo "$PRODUCT/Contents/MacOS/SideCord" -verify_arch arm64
lipo "$PRODUCT/Contents/MacOS/SideCord" -verify_arch x86_64

ditto "$PRODUCT" "$DMG_STAGING/SideCord.app"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname SideCord \
  -srcfolder "$DMG_STAGING" \
  -format UDZO \
  -ov \
  "$DISK_IMAGE"

hdiutil verify "$DISK_IMAGE"
echo "$DISK_IMAGE"
