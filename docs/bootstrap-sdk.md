# weavec0 Stage 0 SDK

The Stage 0 SDK is the versioned binary input consumed by `weavec1`. It lets the
next compiler stage build without cloning or rebuilding `weavec0`.

## Archive contract

Each Linux archive contains exactly:

```text
bin/weavec0
lib/libweavec0-runtime.a
include/runtime.h
SDK-MANIFEST
VERSION
README.md
LICENSE
NOTICE
```

`bin/weavec0` is a fully static build-time compiler that translates WIR to LLVM
IR. `libweavec0-runtime.a` is the matching platform implementation required by
the generated Stage 1 modules, and `runtime.h` documents that ABI.

The SDK deliberately contains no Stage 0 compiler implementation object or
bitcode. `weavec1` compiles its own WIR modules with `bin/weavec0` and links the
resulting Stage 1 implementation with the runtime library. Stage 0 is therefore
not embedded in the Stage 1 binary.

The `v0.2.1` archives included legacy `weavec0-bootstrap.bc` and
`weavec0-bootstrap.o` components. They remain immutable historical release
assets but are not required by current `weavec1`. Version `v0.3.0` removed them
from the supported archive contract.

## Platform variants

Two x86-64 Linux variants are published:

- `glibc`: statically linked against glibc;
- `musl`: statically linked against musl.

The compiler variants implement the same WIR contract and should emit
byte-identical LLVM IR for the same input. The runtime libraries are
libc-specific, so a consumer must keep the compiler and runtime from one archive
together.

## Validation

The packaging script enforces the file list exactly, checks the documented
runtime ABI symbols, rejects dynamically linked compiler executables, and uses
the packaged compiler in a compile–assemble–static-link–run smoke test before
creating the archive.

The release workflow reads `VERSION`. When `master` contains a version for which
no GitHub Release exists, it creates tag `v<VERSION>` and publishes both SDK
archives together with `SHA256SUMS`.

See [architecture](architecture.md) and [releasing](releasing.md).
