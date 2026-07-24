#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-linux-release.sh <glibc|musl> <version> [output-dir]

Build a static Linux x86-64 weavec0 binary and package it as a .tar.gz archive.
The normal ./build.sh must have completed first so that the linked compiler
bitcode exists under build/bootstrap-tests/weavec0.bc.
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
BITCODE="$ROOT/build/bootstrap-tests/weavec0.bc"
RELEASE_BUILD="$ROOT/build/release/$LIBC"
PACKAGE_NAME="weavec0-${VERSION}-linux-x86_64-${LIBC}"
PACKAGE_DIR="$RELEASE_BUILD/$PACKAGE_NAME"
ARCHIVE_DIR="$ROOT/$OUTPUT_DIR"
ARCHIVE="$ARCHIVE_DIR/$PACKAGE_NAME.tar.gz"
OBJECT="$RELEASE_BUILD/weavec0.o"
BINARY="$PACKAGE_DIR/weavec0"
SMOKE_LL="$RELEASE_BUILD/smoke.ll"
SMOKE_BC="$RELEASE_BUILD/smoke.bc"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

require_tool clang
require_tool llvm-as
require_tool readelf
require_tool file
require_tool tar

if [[ "$LIBC" == musl ]]; then
  require_tool musl-gcc
fi

if [[ ! -s "$BITCODE" ]]; then
  printf 'missing compiler bitcode: %s\n' "$BITCODE" >&2
  printf 'run ./build.sh before packaging a release\n' >&2
  exit 1
fi

rm -rf "$RELEASE_BUILD"
mkdir -p "$PACKAGE_DIR" "$ARCHIVE_DIR"

# Convert the linked compiler bitcode to a normal ELF object once. The C runtime
# is then compiled and linked by the selected libc toolchain.
clang -Wno-override-module -O2 -c "$BITCODE" -o "$OBJECT"

case "$LIBC" in
  glibc)
    clang -O2 -static "$OBJECT" "$ROOT/runtime.c" -o "$BINARY"
    ;;
  musl)
    musl-gcc -O2 -static "$OBJECT" "$ROOT/runtime.c" -o "$BINARY"
    ;;
esac

# A standalone release must not request a runtime loader. This is stricter than
# merely checking the output of ldd and works consistently for both libc builds.
if readelf -l "$BINARY" | grep -q 'INTERP'; then
  printf 'release binary is dynamically linked: %s\n' "$BINARY" >&2
  readelf -l "$BINARY" >&2
  exit 1
fi

file "$BINARY"

# Exercise the packaged compiler itself, not only the development binary built
# by build.sh. The generated LLVM must also be accepted by llvm-as.
"$BINARY" "$ROOT/test/02_return_42.wir" "$SMOKE_LL"
llvm-as "$SMOKE_LL" -o "$SMOKE_BC"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$BINARY"
fi

cp "$ROOT/README.md" "$PACKAGE_DIR/"
if [[ -f "$ROOT/LICENSE" ]]; then
  cp "$ROOT/LICENSE" "$PACKAGE_DIR/"
elif [[ -f "$ROOT/LICENSE.txt" ]]; then
  cp "$ROOT/LICENSE.txt" "$PACKAGE_DIR/"
fi

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
