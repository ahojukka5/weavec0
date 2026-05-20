# Weave Stage 0 Bootstrap Compiler

## Overview

This directory contains the first bootstrap compiler for the Weave programming language.

The compiler is intentionally written directly in LLVM IR (`.ll`) together with a very small C runtime.

This is not intended to become the final architecture of the Weave compiler.

The purpose of this codebase is much narrower:

```text
Create the smallest trustworthy bridge capable of compiling
an early Weave compiler written in Weave itself.
```

In other words:

```text
hand-written LLVM IR -> first Weave compiler -> self-hosting
```

This project values:

- simplicity
- auditability
- explicit structure
- minimal moving parts
- deterministic behavior
- tiny incremental milestones

It deliberately avoids:

- premature abstractions
- large framework design
- complicated optimization
- rich type systems
- modules/packages
- advanced diagnostics
- production compiler architecture

The Stage 0 compiler exists only to make the first self-hosted compiler possible.

Once the first Weave-written compiler becomes stable, this Stage 0 compiler should largely freeze.

---

# Philosophy

A common bootstrap failure mode is attempting to build the “real compiler” too early.

This repository intentionally avoids that trap.

The goal is not:

```text
Build a sophisticated compiler immediately.
```

The goal is:

```text
Build the smallest compiler capable of building the next compiler.
```

This distinction matters.

The Stage 0 compiler is a bridge.
It is not the destination.

---

# Repository Structure

```text
bootstrap/
  build.sh
  runtime.c
  runtime.h

  ll/
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

The compiler is built using:

```bash
./build.sh
```

Internally this invokes `clang` on:

- linked bootstrap bitcode
- `runtime.c`

Result:

```text
weavec0
```

---

# Stage Naming

The naming convention is important.

## `weavec0`

The hand-written LLVM IR bootstrap compiler.

Characteristics:

- implemented manually in LLVM IR
- tiny bootstrap subset
- intentionally primitive
- bridge compiler only

As long as the compiler is hand-written LLVM IR:

```text
it is still weavec0
```

Even if features are added.

---

## `weavec1`

The first compiler written in the Weave language itself.

Produced by:

```text
weavec0 -> compiles src-bootstrap/*.weave -> weavec1
```

This is the first true self-hosting milestone.

---

## `weavec2`

A compiler compiled by `weavec1`.

At this point the bootstrap chain becomes self-sustaining.

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

The bootstrap compiler evolves through a curated test ladder.

Each test has two fixtures:

- `tests/<name>.wir`
- `tests/<name>.expected.ll`

The ladder compiles each positive `.wir` file with `weavec0` and checks the
result in several small steps:

1. generated LLVM matches golden fixtures
2. generated LLVM is accepted by `llvm-as`
3. generated LLVM can be compiled by `clang`
4. executable exit code matches expected behavior
5. selected invalid WIR inputs fail cleanly

Example progression:

```text
01_return_constant
02_return_42
03_add
04_one_arg_function
05_let_local
06_set_local
07_if
08_while
09_two_arg_function
10_string_literal
```

Each new feature is admitted only after:

- a minimal test exists
- the previous ladder remains green

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

Write the first Weave compiler:

```text
src-bootstrap/
```

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
