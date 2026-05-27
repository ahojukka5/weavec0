# weavec0 — Weave Stage 0 Bootstrap Compiler

[![ci](https://github.com/ahojukka5/weavec0/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec0/actions/workflows/ci.yml)

> A tiny, hand-written LLVM-IR compiler whose only job is to compile the
> first Weave compiler — written in Weave itself. After that, it
> mostly freezes.

## Overview

`weavec0` reads a small s-expression-style intermediate representation
called **WIR** (`*.wir`) and emits human-readable **LLVM IR** (`*.ll`).
The compiler itself is written directly in `.ll`, paired with a ~130-line
C runtime. It compiles in well under a second and ships 75+ end-to-end
test cases under [`test/`](test).

This is *not* the final architecture of the Weave compiler. The purpose
of this codebase is much narrower:

```text
Create the smallest trustworthy bridge capable of compiling
an early Weave compiler written in Weave itself.
```

This project values **simplicity**, **auditability**, **explicit
structure**, **minimal moving parts**, **deterministic behaviour**, and
**tiny incremental milestones**. It deliberately avoids premature
abstractions, optimisation, advanced typing, packages, beautiful
diagnostics, and production compiler architecture — those belong to
later compiler generations.

---

## Prerequisites

`weavec0` builds with a standard LLVM toolchain:

- `clang`, `llvm-as`, `llvm-link` — LLVM 14 or newer (opaque pointers).
- `bash` 4 or newer.

Installation hints:

```sh
# Debian / Ubuntu
sudo apt-get install -y llvm clang

# macOS (Homebrew)
brew install llvm
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

CI runs on `ubuntu-latest` and `macos-latest` against the package-manager
LLVMs; both should track recent stable releases.

---

## Quick start

```sh
git clone https://github.com/ahojukka5/weavec0.git
cd weavec0
./build.sh

# Inspect a tiny example and its emitted LLVM IR:
cat test/02_return_42.wir
cat test/02_return_42.expected.ll

# Compile a WIR file of your own:
./weavec0 path/to/program.wir path/to/program.ll
```

The first run builds the `weavec0` binary from `src/*.ll` + `runtime.c`,
then runs every case listed in [`test/manifest.txt`](test/manifest.txt).
Each test compiles, assembles with `llvm-as`, builds with `clang`, runs,
and is compared byte-for-byte against a checked-in golden `.ll` file.

---

# Philosophy

A common bootstrap failure mode is attempting to build the "real
compiler" too early. This repository intentionally avoids that trap.

The goal is not:

```text
Build a sophisticated compiler immediately.
```

The goal is:

```text
Build the smallest compiler capable of building the next compiler.
```

The Stage 0 compiler is a bridge. It is not the destination.

---

# Repository Structure

```text
weavec0/
  build.sh
  runtime.c
  runtime.h

  src/
    00_prelude.ll
    01_runtime_bindings.ll
    02_strings.ll
    03_tokens.ll
    04_lexer.ll
    05_ast.ll
    06_parser.ll
    07_emit_llvm.ll
    08_driver.ll
    09_main.ll

  test/
    NN_<name>.wir              positive case: WIR input
    NN_<name>.expected.ll      positive case: golden LLVM output
    NN_<name>.wir              negative case: WIR-only (compile must fail)
```

The numeric prefixes are intentional.

They make the dependency order explicit and preserve a stable mental model for the bootstrap compiler.

The structure mirrors the conceptual compiler pipeline:

```text
source text
  -> lexer
  -> tokens
  -> parser
  -> AST
  -> LLVM emitter
  -> LLVM IR
```

---

# File Responsibilities

## `00_prelude.ll`

Global LLVM module setup.

Contains:

- target triple
- common declarations
- global conventions

This file should remain extremely small.

---

## `01_runtime_bindings.ll`

LLVM declarations for runtime functions implemented in `runtime.c`.

Examples:

- file IO
- memory allocation
- string output
- fatal error handling

This layer forms the ABI boundary between LLVM IR and C.

---

## `02_strings.ll`

String and buffer utilities.

Examples:

- append byte
- append string
- append integer
- compare strings
- dynamic buffer growth

This file intentionally contains low-level utilities only.

---

## `03_tokens.ll`

Token storage and token helpers.

Contains:

- token stream representation
- token append operations
- token field accessors
- token kinds

The lexer depends on this module.

---

## `04_lexer.ll`

Converts source text into tokens.

Responsibilities:

```text
source bytes -> token stream
```

The lexer should remain deterministic and simple.

No semantic analysis belongs here.

---

## `05_ast.ll`

AST storage and AST helper routines.

Contains:

- AST node representation
- AST append operations
- node accessors
- minimal constructors

Stage 0 intentionally uses a primitive AST representation.

Compactness and clarity are preferred over abstraction.

---

## `06_parser.ll`

Recursive descent parser.

Responsibilities:

```text
tokens -> AST
```

The parser intentionally supports only a tiny bootstrap subset of the language.

The subset grows incrementally through tests.

---

## `07_emit_llvm.ll`

LLVM IR text emitter.

Responsibilities:

```text
AST -> LLVM IR text
```

The emitter is intentionally extremely small.

At Stage 0:

- all values are effectively `i32`
- optimization is ignored
- readability matters more than efficiency

The emitted LLVM IR should ideally remain inspectable by humans.

---

## `08_driver.ll`

Compiler pipeline orchestration.

Responsibilities:

```text
read source
  -> lex
  -> parse
  -> emit LLVM
  -> write output
```

This file should contain orchestration logic only.

---

## `09_main.ll`

Program entry point.

Responsibilities:

- argument parsing
- invoking the driver
- returning process exit code

This file should remain tiny.

---

# Runtime

The runtime layer is intentionally tiny.

Files:

```text
runtime.c
runtime.h
```

The runtime exists only to provide:

- file IO
- memory allocation
- simple output
- fatal errors

The runtime is not intended to become a general-purpose runtime system.

---

# Build

The compiler is built and tested with one command:

```bash
./build.sh
```

The script:

1. assembles each `src/NN_*.ll` module with `llvm-as`,
2. links the bitcodes with `llvm-link`,
3. produces the `weavec0` executable by clang-linking the linked bitcode
   with `runtime.c`,
4. runs every case listed in `test/manifest.txt` (the test ladder).

The ladder enumeration lives in `test/manifest.txt`, one case per line:

```text
pass <name> <expected_exit>           # positive: compiles & runs successfully
fail <name> <expected_diagnostic>     # negative: weavec0 must error out cleanly
```

Flags:

- `--regen-goldens` — when a `.expected.ll` differs from the generated
  output (or is missing), overwrite it instead of failing. Useful after
  intentional output-format changes; review the resulting `git diff`
  before committing.

The script is intentionally bash, not CMake, matching the convention used
by the rest of the Weave compiler chain.

---

# Conventions

Source style for the `.ll` modules follows a small, consistent set of
documentation rules described in [`docs/source-style.md`](docs/source-style.md).

In short: every module file opens with a `Responsibilities:` block, every
cross-module entry-point function carries a `Parameters:` / `Returns:`
docstring, and `Notes:` blocks capture non-obvious design tradeoffs.

---

# Where weavec0 fits in the chain

`weavec0` is the **seed** at the bottom of a four-repository Weave
compiler chain. Each stage lives in its own repository and is
independently buildable.

| Stage | Repo | Role |
|-------|------|------|
| `weavec0` | **this repo** | Hand-written LLVM-IR seed compiler. Compiles WIR → LLVM IR. Tiny, frozen. Bootstraps everything above it. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-written compiler. Compiled by `weavec0`. Same WIR → LLVM IR contract, self-hosted implementation. |
| `weavefront` | [`ahojukka5/weavefront`](https://github.com/ahojukka5/weavefront) | Surface (`.weave`) → WIR (`.wir`) frontend. Written in WIR, compiled by `weavec1`. |
| `weavec2` | [`ahojukka5/weavec2`](https://github.com/ahojukka5/weavec2) | Self-hosted Weave compiler. Written in surface Weave; bootstrapped via `weavefront + weavec1`. |

Characteristics of `weavec0`:

- implemented manually in LLVM IR
- tiny bootstrap subset (WIR → LLVM IR)
- intentionally primitive
- bridge compiler only

As long as the compiler is hand-written LLVM IR, it is still
`weavec0`, even if features are added. Once `weavec2` is fully
self-sustaining for surface inputs, `weavec0`'s job is to stay
small and frozen.

---

# Bootstrap Strategy

The repository follows a strict incremental strategy.

## Rule 1

Never add a feature without a test.

---

## Rule 2

Only fix bugs exposed by the current test ladder.

Avoid speculative architecture work.

---

## Rule 3

The bootstrap subset must remain intentionally small.

The goal is not to support the full language immediately.

The goal is to support:

```text
just enough language
for the next compiler stage
```

---

## Rule 4

Do not turn Stage 0 into the production compiler.

This is one of the most dangerous bootstrap failure modes.

Stage 0 should eventually stabilize and mostly freeze.

---

# Test Ladder

The bootstrap compiler evolves through a curated test ladder enumerated by
[`test/manifest.txt`](test/manifest.txt). At time of writing the ladder
runs **100 cases** (90 positive + 10 negative).

Each positive case has two fixtures:

- `test/<name>.wir` — the WIR input,
- `test/<name>.expected.ll` — the golden LLVM IR.

A `.expected.ll` is a checked-in *golden* — the exact LLVM IR `weavec0`
produces today for the corresponding `.wir`. Goldens are not written by
hand; they are regenerated with `./build.sh --regen-goldens` and
reviewed via `git diff` before commit.

Per case the ladder checks, in this order:

1. `weavec0` compiles `.wir` → `.ll` without error,
2. the generated LLVM matches the golden fixture verbatim,
3. `llvm-as` accepts the generated LLVM,
4. `clang` builds an executable from it,
5. the executable's exit code matches the declared value.

Negative cases (`fail` rows in the manifest) instead check that `weavec0`
exits non-zero, writes no `.ll`, and emits a diagnostic that contains a
specified substring.

Numeric prefixes are conventional:

- `01`–`49` — original ladder (constants, arithmetic, control flow, calls,
  pointers, externs, strings).
- `50`–`59` — compile-fail cases (parse errors, unknown operators, arity,
  unknown extern).
- `60`+ — later additions slotted into theme gaps (no-arg paren shape,
  i64 chaining, nested control flow, edge-value constants, mixed-type
  locals, ...).

Each new test must exercise behaviour the parser and emitter already admit.
Do not extend the language to make a test pass — admit a feature only when
a deliberate bootstrap milestone calls for it (see `Bootstrap Strategy`).

---

# Examples

There is no separate `examples/` directory: every file under [`test/`](test)
is a runnable, end-to-end example. Suggested entry points if you are
reading the code for the first time:

- [`test/01_return_constant.wir`](test/01_return_constant.wir) — the
  smallest possible WIR program.
- [`test/07_if.wir`](test/07_if.wir) — branching, with the matching
  [`test/07_if.expected.ll`](test/07_if.expected.ll) showing how `if`
  lowers to `br`.
- [`test/08_while.wir`](test/08_while.wir) — loops and mutable locals.
- [`test/16_extern_malloc_free.wir`](test/16_extern_malloc_free.wir) —
  declaring and calling C externs.
- [`test/86_const_i64_call_arg.wir`](test/86_const_i64_call_arg.wir) —
  the regression test for the i64 call-argument bug; the easiest way to
  see how a typed literal flows through the pipeline.

Run `./weavec0 test/<name>.wir /tmp/out.ll` to produce the LLVM IR
yourself, then `clang /tmp/out.ll -o /tmp/run && /tmp/run; echo $?` to
see it execute.

---

# Self-Hosting Roadmap

## Phase 0

Make `weavec0` build reliably.

---

## Phase 1

Pass the tiny bootstrap test ladder.

---

## Phase 2

Add the minimal language required for a small compiler.

Examples:

- locals
- functions
- conditionals
- loops
- strings

---

## Phase 3

Write the first Weave compiler (`weavec1`) in Weave itself. This work
happens in a separate repository — `weavec0`'s job is only to compile
it once.

---

## Phase 4

Compile `weavec1` using `weavec0`.

---

## Phase 5

Use `weavec1` to compile the same bootstrap tests.

---

## Phase 6

First self-host smoke test.

---

## Phase 7

Freeze `weavec0`.

Future compiler development should happen in Weave itself.

---

# Important Non-Goals

This repository is NOT currently trying to solve:

- optimization
- advanced typing
- packages/modules
- borrow checking
- generics
- macro systems
- advanced diagnostics
- IDE tooling
- incremental compilation
- parallel compilation
- production performance

Those belong to later compiler generations.

The only question Stage 0 must answer is:

```text
Can the language compile itself?
```

---

# Final Note

The Stage 0 compiler is intentionally primitive.

That is not a weakness.

A bootstrap compiler succeeds not by being impressive,

but by being:

```text
small
predictable
understandable
stable
```

The real compiler comes later.

---

# Known Limitations

These are intentional scope choices and one rough edge — not bugs.
Documented so users are not surprised.

- **i32-default surface.** The language `weavec0` admits is essentially
  i32. `main` always returns i32. i64 only exists through explicit
  operators (`const_i64`, `add_i64`, `cast_i64_to_i32`, ...). Anything
  outside this is out of scope for Stage 0.

- **Fixed extern subset.** Only the C-runtime names the Weave chain
  itself needs are recognised: `puts`, `malloc`, `free`, `realloc`,
  `memcpy`, `strlen`, `strcmp`, `strncmp`, `atoi`, `putchar`,
  `weave_rt_read_file`, `weave_rt_write_file`, `weave_rt_fatal`.
  Declaring any other extern in WIR is a hard error
  (`weavec0: extern not supported`). Expanding the set is a
  versioned change to `weavec0` — add a name+signature entry to
  `weave_emit_extern_decl` in
  [`src/07_emit_llvm.ll`](src/07_emit_llvm.ll), bump the tag, and
  point downstream stages at the new tag.

- **Blunt diagnostics.** Errors are one of `parsing failed`,
  `unknown operator`, `invalid arity`, or `extern not supported`,
  with no source location. A real diagnostics framework belongs in a
  later compiler stage.

- **Large i64 literals materialise through a temp.** Values that do
  not round-trip through i32 emit `%tN = add i64 0, <literal>` and
  use the resulting temp as the operand. LLVM's instcombine folds the
  add-zero at `-O1` and above; at `-O0` the extra instruction stays.
  See the `integer_i64` label in
  [`src/07_emit_llvm.ll`](src/07_emit_llvm.ll).

- **Hardcoded target triple in the prelude.** `src/00_prelude.ll`
  carries `target triple = "x86_64-unknown-linux-gnu"`. Emitted
  `.ll` files for user programs carry no triple at all; the
  `-Wno-override-module` flag in `build.sh` silences the resulting
  clang warning. Works on any host the LLVM toolchain supports.

- **`const_string_ptr` only works as a direct call argument.** Using
  it as the initialiser of a `let` (for example
  `(let g ptr (const_string_ptr "hi"))`) fails with `error: LLVM
  emit failed` because the emitter only has a special-cased path for
  the call-argument position. Test
  [`test/29_const_string_ptr.wir`](test/29_const_string_ptr.wir)
  shows the supported shape.

---

# License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE)
and [`NOTICE`](NOTICE).

# Contributing

Pull requests and issues are welcome. The merge bar is intentionally
narrow — please read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the
**Bootstrap Strategy** section above before opening a PR.
