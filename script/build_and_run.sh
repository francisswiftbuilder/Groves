#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Trees"
BUNDLE_ID="io.github.francisswiftbuilder.Trees"
ACCESS_GROUP_SUFFIX="io.github.francisswiftbuilder.Trees.GitCredential"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT_DIR/Trees.xcworkspace"

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

if [[ -z "$CODE_SIGN_IDENTITY" || "$CODE_SIGN_IDENTITY" == "-" || -z "$DEVELOPMENT_TEAM" ]]; then
	printf '%s\n' \
		'Trees requires a development-signed app and helper for shared Keychain access.' \
		'Set TUIST_CODE_SIGN_IDENTITY and TUIST_DEVELOPMENT_TEAM in .env.local,' \
		'then run make generate before using this script.' >&2
	exit 1
fi

xcodebuild build \
	-workspace "$WORKSPACE" \
	-scheme App \
	-configuration Debug \
	-destination "platform=macOS" \
	-allowProvisioningUpdates

TARGET_BUILD_DIR="$(
	printf '%s\n' "$BUILD_SETTINGS" \
		| awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }'
)"
APP_BUNDLE="$TARGET_BUILD_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
HELPER_BINARY="$APP_BUNDLE/Contents/Helpers/TreesAskPass"

team_identifier() {
	/usr/bin/codesign -dv "$1" 2>&1 \
		| awk -F= '/^TeamIdentifier=/ { print $2; exit }'
}

access_group() {
	local binary="$1"
	local entitlements
	entitlements="$(/usr/bin/mktemp -t trees-entitlements)"
	/usr/bin/codesign -d --entitlements :- "$binary" > "$entitlements" 2>/dev/null
	/usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:0' "$entitlements"
	/bin/rm -f "$entitlements"
}

/usr/bin/codesign --verify --strict "$HELPER_BINARY"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
APP_TEAM="$(team_identifier "$APP_BINARY")"
HELPER_TEAM="$(team_identifier "$HELPER_BINARY")"
APP_GROUP="$(access_group "$APP_BINARY")"
HELPER_GROUP="$(access_group "$HELPER_BINARY")"

if [[ -z "$APP_TEAM" || "$APP_TEAM" != "$DEVELOPMENT_TEAM" || "$HELPER_TEAM" != "$APP_TEAM" ]]; then
	printf 'Signing team mismatch: configured=%s app=%s helper=%s\n' \
		"$DEVELOPMENT_TEAM" "${APP_TEAM:-missing}" "${HELPER_TEAM:-missing}" >&2
	exit 1
fi
if [[ "$APP_GROUP" != "$HELPER_GROUP" || "$APP_GROUP" != *.$ACCESS_GROUP_SUFFIX ]]; then
	printf 'Keychain access group mismatch: app=%s helper=%s\n' \
		"${APP_GROUP:-missing}" "${HELPER_GROUP:-missing}" >&2
	exit 1
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
