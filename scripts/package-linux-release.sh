#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-linux-release.sh <glibc|musl> <version> [output-dir]

Build a static Linux x86-64 weavec0 bootstrap SDK and package it as a .tar.gz
archive. Run ./build.sh first so the compiler and module bitcode exist under
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
BITCODE_DIR="$BUILD_ROOT/bc"
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
BOOTSTRAP_BITCODE="$LIB_DIR/weavec0-bootstrap.bc"
BOOTSTRAP_OBJECT="$LIB_DIR/weavec0-bootstrap.o"
RUNTIME_LIBRARY="$LIB_DIR/libweavec0-runtime.a"
SMOKE_LL="$RELEASE_BUILD/smoke.ll"
SMOKE_BC="$RELEASE_BUILD/smoke.bc"

BOOTSTRAP_MODULES=(
  01_runtime_bindings
  02_strings
  03_tokens
  04_lexer
  05_ast
  06_parser
  07_emit_llvm
  08_driver
)

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

require_tool ar
require_tool clang
require_tool file
require_tool llvm-as
require_tool llvm-link
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

bootstrap_inputs=()
for module in "${BOOTSTRAP_MODULES[@]}"; do
  input="$BITCODE_DIR/$module.bc"
  if [[ ! -s "$input" ]]; then
    printf 'missing bootstrap module bitcode: %s\n' "$input" >&2
    exit 1
  fi
  bootstrap_inputs+=("$input")
done

rm -rf "$RELEASE_BUILD"
mkdir -p "$BIN_DIR" "$LIB_DIR" "$INCLUDE_DIR" "$ARCHIVE_DIR"

# The executable contains the Stage 0 entry point. The reusable bootstrap
# component deliberately links only modules 01-08 and therefore has no main.
clang -Wno-override-module -O2 -c "$FULL_BITCODE" -o "$FULL_OBJECT"
llvm-link "${bootstrap_inputs[@]}" -o "$BOOTSTRAP_BITCODE"
clang -Wno-override-module -O2 -c "$BOOTSTRAP_BITCODE" -o "$BOOTSTRAP_OBJECT"

if llvm-nm "$BOOTSTRAP_BITCODE" | grep -Eq '[[:space:]][Tt][[:space:]]+main$'; then
  printf 'bootstrap support unexpectedly defines main\n' >&2
  exit 1
fi

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

file "$BINARY"
file "$BOOTSTRAP_OBJECT"

# Exercise the packaged compiler itself, not only the development binary.
"$BINARY" "$ROOT/test/02_return_42.wir" "$SMOKE_LL"
llvm-as "$SMOKE_LL" -o "$SMOKE_BC"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$BINARY"
  strip --strip-unneeded "$BOOTSTRAP_OBJECT"
fi

cp "$ROOT/runtime.h" "$INCLUDE_DIR/"
cp "$ROOT/README.md" "$PACKAGE_DIR/"
cp "$ROOT/VERSION" "$PACKAGE_DIR/"
if [[ -f "$ROOT/LICENSE" ]]; then
  cp "$ROOT/LICENSE" "$PACKAGE_DIR/"
elif [[ -f "$ROOT/LICENSE.txt" ]]; then
  cp "$ROOT/LICENSE.txt" "$PACKAGE_DIR/"
fi

cat > "$PACKAGE_DIR/SDK-MANIFEST.txt" <<EOF
name=weavec0
version=$VERSION
target=linux-x86_64
libc=$LIBC
compiler=bin/weavec0
bootstrap_bitcode=lib/weavec0-bootstrap.bc
bootstrap_object=lib/weavec0-bootstrap.o
runtime_library=lib/libweavec0-runtime.a
runtime_header=include/runtime.h
EOF

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
