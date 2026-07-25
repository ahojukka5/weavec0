# weavec0 architecture

`weavec0` is the manually written, auditable seed at the bottom of the Weave
compiler chain. It translates the WIR v2 bootstrap profile into deterministic
LLVM IR and exists only to build `weavec1` reproducibly.

```text
WIR v2 bootstrap-profile source
              ↓
           weavec0
              ↓
           LLVM IR
```

It is not a general compiler backend and is not the user-facing compiler.

## Source module graph

The numeric prefixes under `src/` are part of the design. `build.sh` assembles
and links the modules in this dependency order:

| Module | Responsibility |
|---|---|
| `00_prelude.ll` | Shared target, type, token, and ABI declarations used while assembling modules. |
| `01_runtime_bindings.ll` | Fixed runtime ABI declarations. |
| `02_strings.ll` | Source slices, bounded string operations, and formatting helpers. |
| `03_tokens.ll` | Token-stream storage, growth, and accessors. |
| `04_lexer.ll` | Deterministic byte-to-token conversion and fixed keyword dispatch. |
| `05_ast.ll` | Compact AST storage and accessors. |
| `06_parser.ll` | Validation and construction of the admitted WIR bootstrap-profile AST. |
| `07_emit_llvm.ll` | Deterministic LLVM text emission. |
| `08_driver.ll` | File compilation orchestration and failure handling. |
| `09_main.ll` | Command-line entry point. |

`00_prelude.ll` is not linked as an ordinary implementation module. The build
extracts its shared declarations and prepends them to the numbered implementation
modules before independent assembly.

## Compilation data flow

```text
source bytes
    ↓
source slices
    ↓
lexer and token arrays
    ↓
validated AST
    ↓
LLVM text emitter
    ↓
output .ll file
```

The design favors explicit storage layouts and linear dispatch over abstraction.
That repetition is intentional: a reviewer should be able to trace each admitted
form from token recognition through parsing and LLVM emission without hidden
code generation machinery.

## WIR boundary

WIR core version 2 is the versioned language boundary shared by the bootstrap
chain. `weavec0` implements only the strict bootstrap profile needed by the
pinned `weavec1` production sources; `weavec1` owns the complete stable WIR v2
backend.

The distinction is architectural:

- the WIR version identifies the shared contract;
- the Stage 0 profile identifies the smaller implementation subset admitted by
  this seed compiler;
- expanding Stage 0 for feature parity is not a goal.

See [WIR bootstrap profile](wir.md) and [minimization](minimization.md).

## Runtime boundary

`src/01_runtime_bindings.ll` declares the fixed ABI implemented by `runtime.c`
and published in `lib/libweavec0-runtime.a`. The runtime owns only host services
needed by the seed compiler and generated Stage 1 modules, including allocation,
file operations, output, and fatal diagnostics.

Compiler implementation objects and bitcode are not part of the current SDK.
`weavec1` uses `bin/weavec0` at build time and links its own generated modules
with the matching runtime library.

See [bootstrap SDK](bootstrap-sdk.md).

## Deterministic assembly and linking

Each implementation module is assembled independently. `build.sh` derives
cross-module declarations from the actual function definitions rather than
maintaining a second handwritten declaration graph. The generated modules are
then linked into the Stage 0 compiler bitcode and native executable.

The output contract requires the same valid input to produce byte-identical LLVM
IR on supported hosts. Golden fixtures make instruction, label, declaration, and
ordering changes reviewable.

## Verification layers

The repository uses complementary evidence:

1. **Manifest-driven correctness:** positive and negative WIR cases exercise
   compile, assemble, link, execution, diagnostics, and exact LLVM goldens.
2. **CLI coverage:** process-level error paths verify the real command boundary.
3. **LLVM path coverage:** functions, basic blocks, and branch outcomes are
   measured on an instrumented linked compiler.
4. **Pinned Stage 1 corpus:** the exact `WEAVEC1_BOOTSTRAP_COMMIT` modules are
   compiled and inventoried.
5. **Static bootstrap-surface audit:** removed forms, unreachable functions, and
   residual compatibility code are rejected.
6. **SDK validation:** both libc variants are statically linked, ABI-checked, and
   exercised through the installed layout.

See [coverage](coverage.md).

## Change policy

A Stage 0 change is acceptable only when it preserves or improves bootstrap
correctness, auditability, determinism, security, portability, reproducibility,
or packaging. New language and optimizer work belongs in later compiler stages.

A change to accepted WIR, emitted semantics, runtime ABI, or SDK layout is a
versioned contract change and must be released before downstream pins move.
