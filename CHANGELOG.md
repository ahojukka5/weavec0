# Changelog

All notable changes to `weavec0` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[SemVer](https://semver.org/). The project remains pre-1.0, but its Stage 0 WIR
and runtime contracts are maintained conservatively because downstream compiler
stages consume published SDKs.

## [Unreleased]

### Added

- A generated 99-case parser-negative matrix covering too-few and too-many
  operands across fixed-arity operators, malformed unary and constant forms,
  missing call targets, and malformed statements.
- The same generated matrix is included in both the normal test ladder and the
  instrumented LLVM coverage workload.

## [0.3.0] — 2026-07-25

### Added

- Regression coverage for exact `INT64_MIN` emission.
- A token-growth case that crosses the initial parallel-array capacity.
- A negative case for unsupported WIR core versions.
- Machine-readable function, basic-block, and branch-outcome coverage for the
  linked handwritten LLVM implementation.
- A pinned `weavec1` production corpus and bootstrap-surface inventory that
  reports unused WIR keywords and statically unreachable Stage 0 functions.
- CI coverage non-regression floors and uploaded JSON/TSV audit reports.
- Exact SDK file-list validation, runtime ABI symbol checks, and a packaged
  compiler compile–assemble–static-link–execute smoke test.

### Changed

- The Stage 0 SDK is now a minimal build boundary containing only the static
  compiler, the matching runtime library, `runtime.h`, and release metadata.
- The SDK manifest is now consistently named `SDK-MANIFEST`, and `NOTICE` is
  included as documented.
- `weavec1` uses Stage 0 strictly as a build-time compiler and no longer embeds
  Stage 0 implementation objects or bitcode in Stage 1 binaries.

### Removed

- `weavec0-bootstrap.bc` and `weavec0-bootstrap.o` from the published SDK
  contract. The immutable `v0.2.1` archives retain those legacy components.
- Five implementation helpers proven unreachable from both the command-line
  compiler and the pinned Stage 1 corpus: `weave_slice_starts_with_cstr`,
  `weave_emit_type_after_name`, `weave_emit_expr_operand`,
  `weave_source_init_copy`, and `weave_compile_buffer_to_buffer`.
- The unused in-memory compilation path and its private source-copy helper.

### Fixed

- Signed decimal formatting now emits `INT32_MIN` and `INT64_MIN` exactly instead
  of overflowing while computing their magnitudes.
- Token-stream growth now allocates and copies all replacement arrays before
  committing them, so a partial allocation failure cannot leave dangling
  pointers or partially updated storage.
- Buffer and token growth paths now reject size arithmetic overflow.
- Token accessors now return EOF or zero for out-of-range lookahead instead of
  reading uninitialised capacity slack.
- Stage 0 now rejects `(core-version N)` values other than version 1.
- Corrected the token layout documentation to describe the i64 literal-value
  channel accurately.

### Documentation

- Updated the compiler-chain terminology after `weavefront` was renamed to
  `weavec-bootstrap` and `weavec2` was renamed to `weavec`.
- Clarified that normal users consume `weavec`, while `weavec0`, `weavec1`, and
  `weavec-bootstrap` form the reproducible bootstrap chain.
- Documented why LLVM basic-block and branch-outcome coverage are used instead
  of textual line coverage and how coverage evidence guides minimisation.
- Documented the narrower Stage 0 compile-time boundary and the versioned
  `v0.3.0` archive contract.

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

- Renamed `tests/` to `test/`.
- Removed the sibling-directory assumption. The initial release fetched and
  built the pinned `weavec0 v0.2.0` source tree when `WEAVEC0` was unset.
- Expanded the README into standalone build, test, architecture, and
  contribution documentation.

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
