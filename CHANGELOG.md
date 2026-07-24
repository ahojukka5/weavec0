# Changelog

All notable changes to `weavec0` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[SemVer](https://semver.org/). The project remains pre-1.0, but its Stage 0 WIR
and runtime contracts are now maintained conservatively because downstream
compiler stages consume published SDKs.

## [Unreleased]

## [0.2.1] — 2026-07-24

### Added

- Versioned Linux x86-64 bootstrap SDKs for glibc and musl.
- A fully static `bin/weavec0` compiler in each archive.
- Reusable `weavec0-bootstrap.bc` and `weavec0-bootstrap.o` components that omit
  `main` and can be linked into the next compiler stage.
- A libc-specific `libweavec0-runtime.a` and the matching `runtime.h` ABI header.
- `SDK-MANIFEST`, `VERSION`, release documentation, and SHA-256 checksums.
- GitHub Actions packaging and SDK-only smoke tests for both libc variants.

### Changed

- Pushes to `master` now create `v<VERSION>` when that release does not yet
  exist. Existing VERSION releases remain immutable.
- `weavec1` now consumes the published Stage 0 SDK on Linux instead of cloning
  and rebuilding `weavec0`.
- Release archives are bootstrap SDKs rather than single-executable bundles.

## [0.2.0] — 2026-05-26

### Added

- Ten more admitted externs in `weave_emit_extern_decl`: `realloc`, `memcpy`,
  `strlen`, `strcmp`, `strncmp`, `atoi`, `putchar`, `weave_rt_read_file`,
  `weave_rt_write_file`, and `weave_rt_fatal`.
- Positive test `test/101_extern_runtime_subset.wir`, which declares the full
  runtime subset required by `weavec1`.
- README documentation for the expanded admitted extern set.

### Changed

- `test/54_unknown_extern.wir` now declares the genuinely unknown
  `frobnicate` symbol rather than `strlen`.

## [0.1.0] — 2026-05-26

The first public release.

### Added

- Apache-2.0 licensing, notices, and SPDX headers.
- `CONTRIBUTING.md` and this changelog.
- GitHub Actions CI on Linux and macOS.
- Regression test `test/86_const_i64_call_arg.wir`.

### Changed

- The emitter distinguishes `const_i32` and `const_i64` literals end to end.
- The token-stream value channel widened from `i32` to `i64`.
- The README was reframed for standalone publication and separate downstream
  repositories.
- `docs/source-style.md` became the canonical source-style document.

### Fixed

- Pointer-returning calls such as `malloc` now emit i64 arguments with the
  declared LLVM type.
- Large `const_i64` literals no longer lose their high bits in the lexer.

## [0.0.0] — pre-publication polish

Internal milestones before the first public tag:

- Renamed `ll/` to `src/` and `tests/` to `test/`.
- Refactored `build.sh`, added `--regen-goldens`, and moved ladder enumeration
  to `test/manifest.txt`.
- Added structured documentation to every LLVM module and cross-module entry
  point.
- Expanded the original ladder and fixed deterministic LLVM indentation.
- Limited emitted extern declarations to symbols actually present in the WIR
  input.
