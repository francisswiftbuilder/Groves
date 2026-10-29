#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:?usage: embed_bundled_git.sh <app-bundle>}"
RUNTIME="$ROOT_DIR/.build/bundled-git/runtime"
DESTINATION="$APP_BUNDLE/Contents/Resources/Git"
if [[ "$APP_BUNDLE" != *.app || ! -d "$APP_BUNDLE/Contents" ]]; then
	printf 'Expected an existing app bundle.\n' >&2
	exit 1
fi
if [[ ! -x "$RUNTIME/bin/git" ]]; then
	printf 'Bundled Git is missing. Run make bundled-git before building Groves.\n' >&2
	exit 1
fi
for previous in "$DESTINATION" "$APP_BUNDLE/Contents/Helpers/Git"; do
	if [[ -e "$previous" ]]; then
		/bin/rm -rf "$previous"
	fi
done
mkdir -p "$DESTINATION"
/usr/bin/ditto "$RUNTIME" "$DESTINATION"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == NO || -z "$IDENTITY" ]]; then
	IDENTITY=-
fi
while IFS= read -r -d '' binary; do
	if /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
		/usr/bin/codesign --force --sign "$IDENTITY" "$binary"
	fi
done < <(find "$DESTINATION/bin" "$DESTINATION/libexec" -type f -print0)
