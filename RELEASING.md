# Releasing weavec0

`weavec0` publishes versioned Linux x86-64 Stage 0 SDKs for glibc and musl. The
SDK is the supported binary input for `weavec1` and other downstream bootstrap
consumers.

## SDK contents

Each archive contains exactly:

```text
weavec0-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   └── weavec0
├── lib/
│   └── libweavec0-runtime.a
├── include/
│   └── runtime.h
├── SDK-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

`bin/weavec0` is a fully static build-time compiler.
`libweavec0-runtime.a` is the matching libc-specific runtime implementation.
The archive does not contain Stage 0 compiler implementation objects or bitcode.

Consumers must keep the compiler and runtime from one archive together. The
glibc and musl variants implement the same WIR contract but use different libc
implementations.

## Published assets

A normal release contains:

```text
weavec0-vX.Y.Z-linux-x86_64-glibc.tar.gz
weavec0-vX.Y.Z-linux-x86_64-musl.tar.gz
SHA256SUMS
```

The current version is stored in [`VERSION`](VERSION).

## Versioning the archive contract

Removing `weavec0-bootstrap.bc` and `weavec0-bootstrap.o` changes the published
archive layout. The minimal layout therefore begins at `v0.3.0`; existing
`v0.2.1` release assets remain immutable.

A downstream pin may be updated to `v0.3.0` only after the release exists. The
current `weavec1` build already accepts the minimal SDK because it uses Stage 0
only as a build-time compiler and links its own generated modules with the
runtime library.

## Automatic release flow

`.github/workflows/release.yml` runs for pull requests, pushes to `master`,
manual dispatches, and explicit `v*` tags.

Every glibc and musl build:

1. installs LLVM, Clang, binutils, and musl tools;
2. runs the complete `./build.sh` correctness and golden ladder;
3. creates the fully static compiler executable;
4. creates the matching static runtime library;
5. verifies every documented runtime ABI symbol;
6. rejects a compiler executable with an ELF interpreter;
7. runs a packaged-compiler compile–assemble–static-link–execute smoke test;
8. verifies the exact eight-file SDK contract;
9. uploads the versioned `.tar.gz` archive.

For a push to `master`, the publish job reads `VERSION`. When the corresponding
`v<VERSION>` release does not exist, the workflow creates it and uploads both
SDK archives plus `SHA256SUMS`. Existing VERSION releases are left unchanged.

An explicit `v*` tag rebuilds the tag and replaces its assets. This path is
reserved for repairing a broken release workflow or damaged release assets.

## Building archives locally

On Debian or Ubuntu:

```bash
sudo apt-get install -y binutils clang file llvm musl-tools
```

Build and validate the source compiler:

```bash
./build.sh
```

Create either SDK archive:

```bash
bash scripts/package-linux-release.sh glibc v0.3.0 dist
bash scripts/package-linux-release.sh musl v0.3.0 dist
```

The packaging script verifies the exact archive contents, runtime ABI, static
linkage, compiler output, and executable behavior before writing the result
under `dist/`.

## Verifying a downloaded release

Download the selected archive and `SHA256SUMS`, then run:

```bash
sha256sum --check SHA256SUMS
```

Extract and use the compiler:

```bash
tar -xzf weavec0-v0.3.0-linux-x86_64-musl.tar.gz
cd weavec0-v0.3.0-linux-x86_64-musl
bin/weavec0 input.wir output.ll
```

A downstream compiler build compiles its own generated LLVM modules and links
them with:

```text
lib/libweavec0-runtime.a
```

The glibc and musl compiler variants should produce byte-identical LLVM IR for
the same input.

## Release checklist

Before changing `VERSION` or publishing a new SDK:

- confirm the complete source ladder is green;
- review any regenerated LLVM goldens;
- confirm runtime ABI changes are documented;
- confirm the package file list matches the intended versioned contract;
- confirm downstream dependency pins are updated only after publication;
- inspect both archive manifests and `SHA256SUMS`.

See [`docs/BOOTSTRAP_SDK.md`](docs/BOOTSTRAP_SDK.md) for the downstream binary
contract.
