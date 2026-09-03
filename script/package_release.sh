#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
	printf 'usage: %s <version> [output-directory] [build-number]\n' "$0" >&2
	exit 2
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
	printf 'invalid semantic version: %s\n' "$VERSION" >&2
	exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${2:-$ROOT_DIR/dist}"
BUILD_NUMBER="${3:-1}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/groves-release.XXXXXX")"
ARCHIVE_PATH="$WORK_DIR/Groves.xcarchive"
STAGING_DIR="$WORK_DIR/staging"
APP_BUNDLE="$STAGING_DIR/Groves.app"
HELPER_BINARY="$APP_BUNDLE/Contents/Helpers/GrovesAskPass"
DMG_NAME="Groves-$VERSION.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"

cleanup() {
	if [[ -d "$WORK_DIR" ]]; then
		/bin/rm -rf "$WORK_DIR"
	fi
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$STAGING_DIR"

xcodebuild archive \
	-workspace "$ROOT_DIR/Groves.xcworkspace" \
	-scheme App \
	-configuration Release \
	-destination 'generic/platform=macOS' \
	-archivePath "$ARCHIVE_PATH" \
	CODE_SIGNING_ALLOWED=NO \
	ENABLE_USER_SCRIPT_SANDBOXING=NO \
	COMPILER_INDEX_STORE_ENABLE=NO

/usr/bin/ditto "$ARCHIVE_PATH/Products/Applications/Groves.app" "$APP_BUNDLE"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

/usr/bin/codesign --force --sign - "$HELPER_BINARY"
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/hdiutil create \
	-volname Groves \
	-srcfolder "$STAGING_DIR" \
	-format UDZO \
	-ov \
	"$DMG_PATH"

CHECKSUM="$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{ print $1 }')"
printf '%s  %s\n' "$CHECKSUM" "$DMG_NAME" > "$CHECKSUM_PATH"

printf 'Created %s\n' "$DMG_PATH"
printf 'Created %s\n' "$CHECKSUM_PATH"
