#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="2.55.0"
SHA256="457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357"
CACHE_DIR="$ROOT_DIR/.build/bundled-git"
ARCHIVE="$CACHE_DIR/downloads/git-$VERSION.tar.xz"
RUNTIME="$CACHE_DIR/runtime"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD_KEY="$VERSION-$(shasum -a 256 "$ROOT_DIR/script/build_bundled_git.sh" "$ROOT_DIR/script/verify_bundled_git.sh" "$ROOT_DIR/script/embed_bundled_git.sh" "$ROOT_DIR/THIRD_PARTY_NOTICES.md" | shasum -a 256 | awk '{print $1}')-$(xcrun --sdk macosx --show-sdk-version)"

if [[ -f "$RUNTIME/build-key" && "$(< "$RUNTIME/build-key")" == "$BUILD_KEY" && -x "$RUNTIME/bin/git" && -x "$RUNTIME/libexec/git-core/git-remote-https" ]]; then
	"$RUNTIME/bin/git" --version
	exit 0
fi

mkdir -p "$CACHE_DIR/downloads"
if [[ ! -f "$ARCHIVE" ]]; then
	curl --fail --location --retry 3 "https://www.kernel.org/pub/software/scm/git/git-$VERSION.tar.xz" -o "$ARCHIVE.partial"
	mv "$ARCHIVE.partial" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 -c -
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/groves-git-build.XXXXXX")"
trap 'printf "Build workspace: %s\n" "$WORK_DIR"' EXIT
tar -xf "$ARCHIVE" -C "$WORK_DIR"

BUILD_OPTIONS=(
	"prefix=/groves-git"
	"CC=$(xcrun --find clang)"
	"CFLAGS=-O2 -arch arm64 -arch x86_64 -isysroot $SDK -mmacosx-version-min=26.0"
	"LDFLAGS=-arch arm64 -arch x86_64 -isysroot $SDK -mmacosx-version-min=26.0"
	"CURL_CONFIG=/usr/bin/curl-config"
	"CURL_LDFLAGS=-lcurl"
	"NO_GETTEXT=YesPlease"
	"NO_TCLTK=YesPlease"
	"NO_PERL=YesPlease"
	"NO_PYTHON=YesPlease"
	"NO_EXPAT=YesPlease"
	"NO_OPENSSL=YesPlease"
	"NO_RUST=YesPlease"
	"NO_INSTALL_HARDLINKS=YesPlease"
	"RUNTIME_PREFIX=YesPlease"
)

env -u CPATH -u LIBRARY_PATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
	PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/make -C "$WORK_DIR/git-$VERSION" \
	-j 8 "${BUILD_OPTIONS[@]}" all
env -u CPATH -u LIBRARY_PATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
	PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/make -C "$WORK_DIR/git-$VERSION" \
	"${BUILD_OPTIONS[@]}" "DESTDIR=$WORK_DIR/stage" install

STAGED_RUNTIME="$WORK_DIR/stage/groves-git"
mkdir -p "$STAGED_RUNTIME/share/groves-source"
cp "$ARCHIVE" "$STAGED_RUNTIME/share/groves-source/"
cp "$0" "$STAGED_RUNTIME/share/groves-source/build_bundled_git.sh"
cp "$ROOT_DIR/script/verify_bundled_git.sh" "$STAGED_RUNTIME/share/groves-source/"
cp "$ROOT_DIR/script/embed_bundled_git.sh" "$STAGED_RUNTIME/share/groves-source/"
cp "$WORK_DIR/git-$VERSION/COPYING" "$STAGED_RUNTIME/share/groves-source/Git-COPYING"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$STAGED_RUNTIME/share/groves-source/"
"$ROOT_DIR/script/verify_bundled_git.sh" "$STAGED_RUNTIME"
printf '%s\n' "$BUILD_KEY" > "$STAGED_RUNTIME/build-key"
if [[ -e "$RUNTIME" ]]; then
	mv "$RUNTIME" "$WORK_DIR/previous-runtime"
fi
mv "$STAGED_RUNTIME" "$RUNTIME"
"$RUNTIME/bin/git" --version
