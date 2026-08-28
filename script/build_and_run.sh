#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Trees"
BUNDLE_ID="io.github.francisswiftbuilder.Trees"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild build \
	-workspace "$ROOT_DIR/Trees.xcworkspace" \
	-scheme App \
	-configuration Debug \
	-destination "platform=macOS"

TARGET_BUILD_DIR="$(
	xcodebuild \
		-workspace "$ROOT_DIR/Trees.xcworkspace" \
		-scheme App \
		-configuration Debug \
		-destination "platform=macOS" \
		-showBuildSettings \
		| awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }'
)"
APP_BUNDLE="$TARGET_BUILD_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

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
