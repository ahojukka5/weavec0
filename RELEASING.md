# Releasing weavec0

`weavec0` publishes versioned Linux x86-64 bootstrap SDKs for glibc and musl.
The SDK is the supported binary input for `weavec1` and other downstream
bootstrap consumers.

## SDK contents

Each archive contains:

```text
weavec0-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   └── weavec0
├── lib/
│   ├── weavec0-bootstrap.bc
│   ├── weavec0-bootstrap.o
│   └── libweavec0-runtime.a
├── include/
│   └── runtime.h
├── SDK-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

`bin/weavec0` is a fully static compiler executable. The bootstrap bitcode and
object contain reusable compiler support code without `main`.
`libweavec0-runtime.a` is the matching libc-specific runtime implementation.

Consumers must keep components from one archive together. The bootstrap object
and bitcode are libc-neutral, but the runtime library and compiler executable
are built for the selected libc.

## Published assets

A normal release contains:

```text
weavec0-vX.Y.Z-linux-x86_64-glibc.tar.gz
weavec0-vX.Y.Z-linux-x86_64-musl.tar.gz
SHA256SUMS
```

The current version is stored in [`VERSION`](VERSION).

## Automatic release flow

`.github/workflows/release.yml` runs for pull requests, pushes to `master`,
manual dispatches, and explicit `v*` tags.

Every glibc and musl build:

1. installs LLVM, Clang, binutils, and musl tools;
2. runs the complete `./build.sh` ladder;
3. creates a fully static compiler executable;
4. creates reusable bootstrap bitcode and object code without `main`;
5. creates the matching static runtime library;
6. rejects a compiler executable with an ELF interpreter;
7. performs a compiler and SDK-only smoke test;
8. uploads the versioned `.tar.gz` archive.

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
bash scripts/package-linux-release.sh glibc v0.2.1 dist
bash scripts/package-linux-release.sh musl v0.2.1 dist
```

The packaging script verifies the archive contents and static linkage before
writing the result under `dist/`.

## Verifying a downloaded release

Download both the selected archive and `SHA256SUMS`, then run:

```bash
sha256sum --check SHA256SUMS
```

Extract and use the compiler:

```bash
tar -xzf weavec0-v0.2.1-linux-x86_64-musl.tar.gz
cd weavec0-v0.2.1-linux-x86_64-musl
bin/weavec0 input.wir output.ll
```

A downstream compiler build may then link generated objects with:

```text
lib/weavec0-bootstrap.o
lib/libweavec0-runtime.a
```

The glibc and musl compiler variants implement the same WIR contract and should
produce byte-identical LLVM IR for the same input.

## Release checklist

Before changing `VERSION` or publishing a new SDK:

- confirm the complete source ladder is green;
- review any regenerated LLVM goldens;
- confirm runtime ABI changes are documented;
- confirm downstream dependency pins are updated only after publication;
- inspect both archive manifests and `SHA256SUMS`.

See [`docs/BOOTSTRAP_SDK.md`](docs/BOOTSTRAP_SDK.md) for the downstream binary
contract.
