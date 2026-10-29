#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${1:?usage: verify_bundled_git.sh <runtime-directory>}"
for binary in "$RUNTIME/bin/git" "$RUNTIME/libexec/git-core/git-remote-https"; do
	[[ -x "$binary" ]]
	for architecture in arm64 x86_64; do
		lipo "$binary" -verify_arch "$architecture"
	done
done
while IFS= read -r -d '' binary; do
	if /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
		while IFS= read -r dependency; do
			case "$dependency" in
			/usr/lib/* | /System/Library/*) ;;
			*) printf 'Non-system dependency in %s: %s\n' "$binary" "$dependency" >&2; exit 1 ;;
			esac
		done < <(otool -L "$binary" | awk '/compatibility version/ {print $1}')
	fi
done < <(find "$RUNTIME/bin" "$RUNTIME/libexec" -type f -print0)
[[ -f "$RUNTIME/share/groves-source/Git-COPYING" ]]
[[ -f "$RUNTIME/share/groves-source/git-2.55.0.tar.xz" ]]
"$RUNTIME/bin/git" --version
