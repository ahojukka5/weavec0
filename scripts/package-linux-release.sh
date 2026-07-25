#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-linux-release.sh <glibc|musl> <version> [output-dir]

Build a static Linux x86-64 weavec0 SDK and package it as a .tar.gz archive.
Run ./build.sh first so the linked compiler bitcode exists under
build/bootstrap-tests/.
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

LIBC="$1"
VERSION="$2"
OUTPUT_DIR="${3:-dist}"

case "$LIBC" in
  glibc|musl) ;;
  *)
    printf 'unsupported libc: %s\n' "$LIBC" >&2
    usage >&2
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT/build/bootstrap-tests"
FULL_BITCODE="$BUILD_ROOT/weavec0.bc"
RELEASE_BUILD="$ROOT/build/release/$LIBC"
PACKAGE_NAME="weavec0-${VERSION}-linux-x86_64-${LIBC}"
PACKAGE_DIR="$RELEASE_BUILD/$PACKAGE_NAME"
BIN_DIR="$PACKAGE_DIR/bin"
LIB_DIR="$PACKAGE_DIR/lib"
INCLUDE_DIR="$PACKAGE_DIR/include"
ARCHIVE_DIR="$ROOT/$OUTPUT_DIR"
ARCHIVE="$ARCHIVE_DIR/$PACKAGE_NAME.tar.gz"
FULL_OBJECT="$RELEASE_BUILD/weavec0-main.o"
RUNTIME_OBJECT="$RELEASE_BUILD/runtime.o"
BINARY="$BIN_DIR/weavec0"
RUNTIME_LIBRARY="$LIB_DIR/libweavec0-runtime.a"
SMOKE_LL="$RELEASE_BUILD/smoke.ll"
SMOKE_BC="$RELEASE_BUILD/smoke.bc"
SMOKE_OBJECT="$RELEASE_BUILD/smoke.o"
SMOKE_BINARY="$RELEASE_BUILD/smoke"
EXPECTED_FILES="$RELEASE_BUILD/expected-files.txt"
ACTUAL_FILES="$RELEASE_BUILD/actual-files.txt"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

require_tool ar
require_tool clang
require_tool diff
require_tool file
require_tool find
require_tool llvm-as
require_tool llvm-nm
require_tool readelf
require_tool tar

if [[ "$LIBC" == musl ]]; then
  require_tool musl-gcc
fi

if [[ ! -s "$FULL_BITCODE" ]]; then
  printf 'missing compiler bitcode: %s\n' "$FULL_BITCODE" >&2
  printf 'run ./build.sh before packaging a release\n' >&2
  exit 1
fi

rm -rf "$RELEASE_BUILD"
mkdir -p "$BIN_DIR" "$LIB_DIR" "$INCLUDE_DIR" "$ARCHIVE_DIR"

# Stage 0 is a build-time compiler. The SDK intentionally publishes only the
# static compiler, the matching runtime implementation, and ABI metadata. It
# does not export compiler implementation objects or bitcode.
clang -Wno-override-module -O2 -c "$FULL_BITCODE" -o "$FULL_OBJECT"

case "$LIBC" in
  glibc)
    clang -O2 -c "$ROOT/runtime.c" -o "$RUNTIME_OBJECT"
    ar rcs "$RUNTIME_LIBRARY" "$RUNTIME_OBJECT"
    clang -O2 -static "$FULL_OBJECT" "$RUNTIME_LIBRARY" -o "$BINARY"
    ;;
  musl)
    musl-gcc -O2 -c "$ROOT/runtime.c" -o "$RUNTIME_OBJECT"
    ar rcs "$RUNTIME_LIBRARY" "$RUNTIME_OBJECT"
    musl-gcc -O2 -static "$FULL_OBJECT" "$RUNTIME_LIBRARY" -o "$BINARY"
    ;;
esac

# A standalone release must not request a runtime loader.
if readelf -l "$BINARY" | grep -q 'INTERP'; then
  printf 'release binary is dynamically linked: %s\n' "$BINARY" >&2
  readelf -l "$BINARY" >&2
  exit 1
fi

# Verify that the runtime archive exposes the complete documented ABI.
for symbol in \
  weave_rt_fatal \
  weave_rt_read_file \
  weave_rt_write_file \
  weave_rt_stdout \
  weave_rt_stderr
do
  if ! llvm-nm --defined-only "$RUNTIME_LIBRARY" | \
      grep -Eq "[[:space:]]${symbol}$"; then
    printf 'runtime library is missing required symbol: %s\n' "$symbol" >&2
    exit 1
  fi
done

file "$BINARY"
file "$RUNTIME_LIBRARY"

# Exercise the packaged compiler, then assemble, statically link, and execute
# its output. Correctness is checked before the archive is created.
"$BINARY" "$ROOT/test/02_return_42.wir" "$SMOKE_LL"
llvm-as "$SMOKE_LL" -o "$SMOKE_BC"
clang -Wno-override-module -O2 -c "$SMOKE_LL" -o "$SMOKE_OBJECT"
case "$LIBC" in
  glibc) clang -static "$SMOKE_OBJECT" -o "$SMOKE_BINARY" ;;
  musl) musl-gcc -static "$SMOKE_OBJECT" -o "$SMOKE_BINARY" ;;
esac

set +e
"$SMOKE_BINARY"
smoke_status=$?
set -e
if [[ "$smoke_status" != 42 ]]; then
  printf 'packaged compiler smoke test: expected exit 42, got %s\n' \
    "$smoke_status" >&2
  exit 1
fi

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$BINARY"
fi

cp "$ROOT/runtime.h" "$INCLUDE_DIR/runtime.h"
cp "$ROOT/README.md" "$PACKAGE_DIR/README.md"
cp "$ROOT/VERSION" "$PACKAGE_DIR/VERSION"

if [[ -f "$ROOT/LICENSE" ]]; then
  cp "$ROOT/LICENSE" "$PACKAGE_DIR/LICENSE"
elif [[ -f "$ROOT/LICENSE.txt" ]]; then
  cp "$ROOT/LICENSE.txt" "$PACKAGE_DIR/LICENSE"
else
  printf 'missing LICENSE file\n' >&2
  exit 1
fi

if [[ -f "$ROOT/NOTICE" ]]; then
  cp "$ROOT/NOTICE" "$PACKAGE_DIR/NOTICE"
elif [[ -f "$ROOT/NOTICE.txt" ]]; then
  cp "$ROOT/NOTICE.txt" "$PACKAGE_DIR/NOTICE"
else
  printf 'missing NOTICE file\n' >&2
  exit 1
fi

cat > "$PACKAGE_DIR/SDK-MANIFEST" <<EOF
name=weavec0
version=$VERSION
target=linux-x86_64
libc=$LIBC
compiler=bin/weavec0
runtime_library=lib/libweavec0-runtime.a
runtime_header=include/runtime.h
EOF

# Enforce the minimal archive contract exactly. This catches both missing files
# and accidental reintroduction of compiler implementation artifacts.
cat > "$EXPECTED_FILES" <<'EOF'
LICENSE
NOTICE
README.md
SDK-MANIFEST
VERSION
bin/weavec0
include/runtime.h
lib/libweavec0-runtime.a
EOF
find "$PACKAGE_DIR" -type f -printf '%P\n' | LC_ALL=C sort > "$ACTUAL_FILES"
LC_ALL=C sort -o "$EXPECTED_FILES" "$EXPECTED_FILES"
if ! diff -u "$EXPECTED_FILES" "$ACTUAL_FILES"; then
  printf 'SDK archive contents do not match the minimal contract\n' >&2
  exit 1
fi

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
