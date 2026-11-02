#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT_DIR/Groves.xcworkspace"
"$ROOT_DIR/script/build_bundled_git.sh"

BUILD_SETTINGS="$(
	xcodebuild \
		-workspace "$WORKSPACE" \
		-scheme App \
		-configuration Debug \
		-destination "platform=macOS" \
		-showBuildSettings
)"
CODE_SIGN_IDENTITY="$(
	printf '%s\n' "$BUILD_SETTINGS" \
		| awk -F ' = ' '/^[[:space:]]*CODE_SIGN_IDENTITY = / { print $2; exit }'
)"
DEVELOPMENT_TEAM="$(
	printf '%s\n' "$BUILD_SETTINGS" \
		| awk -F ' = ' '/^[[:space:]]*DEVELOPMENT_TEAM = / { print $2; exit }'
)"

SIGNING_ARGUMENTS=(-allowProvisioningUpdates)
USE_ADHOC_SIGNING=false
if [[ -z "$CODE_SIGN_IDENTITY" || "$CODE_SIGN_IDENTITY" == "-" || -z "$DEVELOPMENT_TEAM" ]]; then
	SIGNING_ARGUMENTS=(CODE_SIGNING_ALLOWED=NO)
	USE_ADHOC_SIGNING=true
fi

xcodebuild build \
	-workspace "$WORKSPACE" \
	-scheme App \
	-configuration Debug \
	-destination "platform=macOS" \
	"${SIGNING_ARGUMENTS[@]}"

TARGET_BUILD_DIR="$(
	printf '%s\n' "$BUILD_SETTINGS" \
		| awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }'
)"
APP_NAME="$(
	printf '%s\n' "$BUILD_SETTINGS" \
		| awk -F ' = ' '/^[[:space:]]*EXECUTABLE_NAME = / { print $2; exit }'
)"
FULL_PRODUCT_NAME="$(
	printf '%s\n' "$BUILD_SETTINGS" \
		| awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }'
)"
BUNDLE_ID="$(
	printf '%s\n' "$BUILD_SETTINGS" \
		| awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }'
)"
APP_BUNDLE="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
HELPER_BINARY="$APP_BUNDLE/Contents/Helpers/GrovesAskPass.app/Contents/MacOS/GrovesAskPass"

team_identifier() {
	/usr/bin/codesign -dv "$1" 2>&1 \
		| awk -F= '/^TeamIdentifier=/ { print $2; exit }'
}

if [[ "$USE_ADHOC_SIGNING" == true ]]; then
	/usr/bin/codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/GrovesAskPass.app"
	/usr/bin/codesign --force --sign - "$APP_BUNDLE"
fi

/usr/bin/codesign --verify --strict "$HELPER_BINARY"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
if [[ "$USE_ADHOC_SIGNING" == false ]]; then
	APP_TEAM="$(team_identifier "$APP_BINARY")"
	HELPER_TEAM="$(team_identifier "$HELPER_BINARY")"
	if [[ -z "$APP_TEAM" || "$APP_TEAM" != "$DEVELOPMENT_TEAM" || "$HELPER_TEAM" != "$APP_TEAM" ]]; then
		printf 'Signing team mismatch: configured=%s app=%s helper=%s\n' \
			"$DEVELOPMENT_TEAM" "${APP_TEAM:-missing}" "${HELPER_TEAM:-missing}" >&2
		exit 1
	fi
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

open_app() {
	/usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
run)
	open_app
	;;
--debug | debug)
	xcrun lldb -- "$APP_BINARY"
	;;
--logs | logs)
	open_app
	/usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
	;;
--telemetry | telemetry)
	open_app
	/usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
	;;
--verify | verify)
	open_app
	sleep 1
	pgrep -x "$APP_NAME" >/dev/null
	;;
*)
	printf 'usage: %s [run|--debug|--logs|--telemetry|--verify]\n' "$0" >&2
	exit 2
	;;
esac
