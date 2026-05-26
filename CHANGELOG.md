# Changelog

All notable changes to `weavec0` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning is
[SemVer](https://semver.org/) with the caveat that `0.x` is the
bootstrap phase: minor versions may break things until `weavec0` reaches
its goal of compiling `weavec1` reliably, at which point the contract
freezes.

## [Unreleased]

### Added
- Ten more admitted externs in `weave_emit_extern_decl`
  (`realloc`, `memcpy`, `strlen`, `strcmp`, `strncmp`, `atoi`,
  `putchar`, `weave_rt_read_file`, `weave_rt_write_file`,
  `weave_rt_fatal`). This is the C-runtime subset that `weavec1`'s
  `runtime_bindings.wir` needs, so `weavec1` can now self-compile
  against published `weavec0`. New positive test
  `test/101_extern_runtime_subset.wir` declares the full subset.

### Changed
- `test/54_unknown_extern.wir` now declares a truly unknown name
  (`frobnicate`) rather than `strlen`, which is admitted now.

## [0.1.0]

The first public release.

### Added
- Apache-2.0 licensing (`LICENSE`, `NOTICE`, SPDX headers on every owned
  source file).
- `CONTRIBUTING.md` describing the very narrow merge bar.
- GitHub Actions CI matrix (`ubuntu-latest`, `macos-latest`) running the
  full test ladder via `./build.sh`.
- Regression test `test/86_const_i64_call_arg.wir` locking in the new
  i64 call-arg behaviour.

### Changed
- Emitter now distinguishes `const_i32` and `const_i64` literals end to
  end: a new AST kind (`AST_INTEGER_LITERAL_I64 = 36`) flows from the
  parser through the type-classification path so call arguments use the
  correct LLVM type prefix.
- Token-stream value channel widened from `i32` to `i64` (lexer uses
  `atoll` instead of `atoi`). Large `(const_i64 N)` literals no longer
  silently truncate.
- README reframed for standalone publication: `weavec1` / `weavec2` are
  now described as separate downstream projects, not in-tree siblings.
- `docs/source-style.md` is now the canonical source-style document for
  this repository (previously a summary pointing at a sibling repo).

### Fixed
- `(call_ptr malloc (const_i64 N))` previously emitted `call ptr @malloc(i32 N)`
  — wrong type for the declared signature. The output now correctly
  emits `(i64 N)`. `llvm-as` accepted both forms on x86_64, but the
  fix removes a latent portability bug.
- Large `(const_i64 N)` literals (those that did not round-trip through
  `i32`) previously had their high bits silently dropped by the lexer.
  Such values are now preserved end to end and materialised in the IR
  via `%tN = add i64 0, <N>`.

## [0.0.0] — pre-publication polish

Internal milestones not previously tagged. Summarised for context:

- Layout rename: `ll/` → `src/`, `tests/` → `test/`.
- `build.sh` refactored into named helpers; new `--regen-goldens` flag;
  test ladder driven by `test/manifest.txt`.
- Documentation pass on every `src/*.ll` file: `Responsibilities:` block
  on every module header, `Parameters:` / `Returns:` / `Notes:` blocks
  on every cross-module entry point.
- Test ladder grew from 49 to 75 admitted cases, all inside the existing
  language subset.
- Indentation bug fixed (`%tN = …` lines now correctly 2-space indented
  to match `store`/`br`/`ret`/`call void` lines).
- Extern declarations filtered: `weavec0` now emits only the `declare`
  lines that the input WIR actually declares (previously a fixed block
  of four declares was emitted on every output).
