# WIR v2 bootstrap profile

WIR is the typed, deterministic tree representation shared by the Weave
bootstrap compiler chain. A module has the versioned shape:

```lisp
(core-module
  (core-version 2)
  (decls
    (fn main
      (params)
      (returns i32)
      (do
        (return (const_i32 42))))))
```

WIR v2 is explicit, structured, expression-oriented, human-readable, and close
enough to LLVM semantics for deterministic lowering. It is not an SSA or
basic-block IR.

## Complete contract and Stage 0 profile

`weavec1` is the authoritative complete WIR v2 backend. `weavec0` accepts the
same core version but deliberately implements a strict bootstrap profile: the
forms required to compile the production `weavec1` modules pinned by
`WEAVEC1_BOOTSTRAP_COMMIT`.

This distinction does not create a second WIR language version:

- `(core-version 2)` identifies the shared representation contract;
- the Stage 0 bootstrap profile identifies the smaller implementation subset in
  the hand-written seed;
- downstream code that needs the complete WIR v2 backend uses `weavec1`.

## Admitted shape categories

The Stage 0 profile covers the categories exercised by the pinned Stage 1
compiler:

- module, declaration, function, parameter, return, and extern forms;
- explicit scalar, boolean, pointer, and void types;
- typed integer, boolean, pointer, and string-pointer constants;
- arithmetic, comparison, bitwise, shift, cast, and boolean expressions;
- locals, parameters, loads, stores, allocation, and pointer operations;
- typed direct calls and the fixed admitted runtime extern ABI;
- structured `do`, `if`, `while`, `let`, `set`, and `return` statements.

The implementation and executable fixtures are authoritative. This document
intentionally avoids duplicating every operator spelling and arity because a
second handwritten grammar inventory would drift from the lexer, parser, and
manifest. The current surface is derived and checked by
`scripts/audit_bootstrap_surface.py`.

## Authoritative evidence

A form belongs to the current Stage 0 profile only when all relevant repository
contracts agree:

1. the lexer recognizes its fixed keyword;
2. the parser validates its exact shape and type requirements;
3. the emitter implements deterministic LLVM semantics;
4. `test/manifest.txt` contains appropriate positive or negative coverage;
5. the pinned `weavec1` production corpus requires the form;
6. the bootstrap-surface audit reports no unused Stage 0 keyword or residual
   removed implementation path.

The audit report is written to:

```text
build/coverage/bootstrap-surface.json
```

## Deterministic LLVM lowering

WIR preserves structured control flow and named local/parameter access. Stage 0
creates LLVM blocks, temporaries, storage, declarations, and string constants in
stable source-driven order. Checked-in `.expected.ll` fixtures make every output
change reviewable.

The same valid WIR input must produce byte-identical LLVM IR on supported hosts.
Host-specific behavior belongs behind the fixed runtime ABI, not in emitted text.

## Compatibility and versioning

Without a coordinated contract transition, Stage 0 may receive correctness,
security, portability, diagnostics, test, audit, and packaging improvements that
preserve admitted WIR semantics.

The following require intentional versioning and downstream release order:

- adding or removing an admitted form;
- changing a form's shape, typing, or semantics;
- changing emitted observable behavior;
- changing the runtime ABI incompatibly;
- changing the required SDK layout.

Removed compatibility forms must not reappear as undocumented aliases. The
static audit checks source and documentation for known residual implementations.

See [architecture](architecture.md), [minimization](minimization.md), and
[coverage](coverage.md). The complete stable backend contract is documented in
[`weavec1`](https://github.com/ahojukka5/weavec1/blob/master/docs/architecture.md).
