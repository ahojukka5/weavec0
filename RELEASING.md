# Releasing weavec0

`weavec0` publishes standalone Linux x86-64 compiler binaries in two variants:

- **glibc** — statically linked with glibc for conventional GNU/Linux systems;
- **musl** — statically linked with musl for a smaller and broadly portable
  Linux binary.

Both variants are single-file executables. They do not require LLVM, Clang, or a
C compiler at runtime. LLVM is only required when building `weavec0` or when
assembling the LLVM IR produced by it.

## GitHub Actions workflow

The `.github/workflows/release.yml` workflow runs on pull requests, pushes to
`master`, manual dispatches, and tags matching `v*`.

Every build:

1. installs LLVM, Clang, binutils, and musl tools;
2. runs the complete `./build.sh` test ladder;
3. creates static glibc and musl binaries;
4. rejects binaries that contain an ELF interpreter;
5. uses the packaged binary to compile `test/02_return_42.wir`;
6. verifies the resulting LLVM IR with `llvm-as`;
7. uploads each `.tar.gz` archive as a workflow artifact.

A pushed `v*` tag additionally creates or updates a GitHub Release containing:

```text
weavec0-<tag>-linux-x86_64-glibc.tar.gz
weavec0-<tag>-linux-x86_64-musl.tar.gz
SHA256SUMS
```

## Creating a release

Create and push a version tag from the release commit:

```bash
git switch master
git pull --ff-only
git tag -a v0.1.0 -m "weavec0 v0.1.0"
git push origin v0.1.0
```

The release workflow builds both archives and publishes them after all build and
smoke-test jobs succeed.

## Building archives locally

Install the required build tools first. On Debian or Ubuntu:

```bash
sudo apt-get install -y binutils clang file llvm musl-tools
```

Build and test the normal compiler:

```bash
./build.sh
```

Then create either archive:

```bash
bash scripts/package-linux-release.sh glibc v0.1.0 dist
bash scripts/package-linux-release.sh musl v0.1.0 dist
```

The archives are written under `dist/`.

## Verifying a downloaded release

Verify checksums:

```bash
sha256sum --check SHA256SUMS
```

Extract one archive and run the compiler:

```bash
tar -xzf weavec0-v0.1.0-linux-x86_64-musl.tar.gz
cd weavec0-v0.1.0-linux-x86_64-musl
./weavec0 input.wir output.ll
```

The musl and glibc builds implement the same compiler and should produce
byte-identical LLVM IR for the same input.
