# Weave Intermediate Representation (WIR / TIR)

## Overview

This document describes the first stable intermediate representation used by the Weave bootstrap compiler.

At this stage of the project the representation is intentionally:

* small
* explicit
* typed
* easy to lower into LLVM IR
* easy for humans to read and audit
* simple enough to bootstrap with a tiny compiler

Although the name `WIR` (Weave Intermediate Representation) is still used informally, the current representation is technically closer to a typed tree IR (TIR) than a machine-level CFG IR.

The representation is therefore:

```text
structured
recursive
expression-oriented
```

and not yet:

```text
SSA
basic-block based
CFG-oriented
```

That choice is intentional.

---

## Compiler Pipeline

The long-term compiler pipeline is expected to evolve into something like:

```text
Surface Weave
    ↓
Parser
    ↓
AST
    ↓
Lowering
    ↓
TIR / WIR
    ↓
CFG IR (future)
    ↓
LLVM IR
    ↓
clang / lld
    ↓
native executable
```

However, during bootstrap we intentionally skip some stages.

Current bootstrap strategy:

```text
TIR / WIR
    ↓
LLVM IR
```

This keeps the bootstrap compiler small and manageable.

The first self-hosted compiler therefore does not compile the full surface language yet. It compiles the typed IR directly.

---

## Why This Design Exists

The original bootstrap effort became difficult because the compiler source drifted toward a large high-level language before a stable self-hosted core existed.

The project therefore adopts the following rule:

```text
The bootstrap compiler should compile the smallest trustworthy language possible.
```

The current TIR representation was chosen because it:

* removes operator precedence
* removes syntactic ambiguity
* removes parser complexity
* makes lowering nearly mechanical
* resembles LLVM enough to reason about code generation
* remains readable by humans

For example:

Surface language:

```weave
(+ x 1)
```

TIR:

```lisp
(add_i32
  (local_get x)
  (const_i32 1))
```

LLVM IR:

```llvm
%t0 = add i32 %x, 1
```

The transformation becomes explicit and easy to verify.

---

## File Structure

A WIR/TIR file currently has this structure:

```lisp
(core-module
  (core-version 1)

  (decls

    ... declarations ...))
```

Example:

```lisp
(core-module
  (core-version 1)

  (decls

    (fn main
      (params)
      (returns i32)

      (do
        (return
          (const_i32 0))))))
```

---

## Module Forms

### `(core-module ...)`

Top-level container.

Example:

```lisp
(core-module
  ...)
```

---

### `(core-version N)`

Defines the WIR/TIR language version.

Example:

```lisp
(core-version 1)
```

---

### `(decls ...)`

Container for top-level declarations.

Currently supported:

```text
fn
```

Future possibilities:

```text
global
extern
struct
const
```

---

## Functions

### Function Declaration

Syntax:

```lisp
(fn NAME
  (params ...)
  (returns TYPE)
  (do ...))
```

Example:

```lisp
(fn add
  (params
    (a i32)
    (b i32))
  (returns i32)

  (do
    (return
      (add_i32
        (param_get a)
        (param_get b)))))
```

---

## Types

Current primitive types:

```text
i32
i64
bool
ptr
void
```

The naming intentionally follows LLVM conventions.

Example:

```llvm
i32
i64
ptr
void
```

rather than:

```text
Int32
Int64
Pointer
Void
```

This keeps lowering straightforward.

---

## Constants

### `(const_i32 VALUE)`

Example:

```lisp
(const_i32 42)
```

Lowering idea:

```llvm
42
```

---

### `(const_string_ptr TEXT)`

Example:

```lisp
(const_string_ptr "hello")
```

Possible lowering:

```llvm
@.str0 = private unnamed_addr constant [6 x i8] c"hello\00"
```

---

## Arithmetic Operations

### `add_i32`

Syntax:

```lisp
(add_i32 A B)
```

Example:

```lisp
(add_i32
  (const_i32 20)
  (const_i32 22))
```

Lowering idea:

```llvm
%t0 = add i32 %a, %b
```

---

### Other arithmetic operations

```text
sub_i32
mul_i32
div_i32
```

Example:

```lisp
(sub_i32
  (const_i32 10)
  (const_i32 3))
```

---

## Comparison Operations

### Supported comparisons

```text
eq_i32
ne_i32
lt_i32
le_i32
gt_i32
ge_i32
```

Example:

```lisp
(lt_i32
  (const_i32 1)
  (const_i32 2))
```

Possible lowering:

```llvm
%t0 = icmp slt i32 %a, %b
```

---

## Local Variables

### `(let NAME TYPE VALUE)`

Creates a local variable.

Example:

```lisp
(let x i32
  (const_i32 40))
```

This is still a structured high-level operation.

The emitter may later lower this into:

```llvm
%x = alloca i32
store i32 40, ptr %x
```

---

### `(set NAME VALUE)`

Updates an existing local variable.

Example:

```lisp
(set x
  (add_i32
    (local_get x)
    (const_i32 2)))
```

---

### `(local_get NAME)`

Reads a local variable.

Example:

```lisp
(local_get x)
```

---

### `(param_get NAME)`

Reads a function parameter.

Example:

```lisp
(param_get a)
```

This remains higher-level than explicit memory operations.

We intentionally do NOT use:

```text
load_i32
store_i32
```

for normal local variables yet.

Those belong more naturally to a future machine-oriented IR.

---

## Function Calls

### `(call_i32 NAME ARG...)`

Calls a function returning `i32`.

Example:

```lisp
(call_i32 add
  (const_i32 20)
  (const_i32 22))
```

Possible lowering:

```llvm
%t0 = call i32 @add(i32 20, i32 22)
```

---

## Control Flow

### `(if (condition ...) (then ...) (else ...))`

Structured conditional.

Example:

```lisp
(if
  (condition
    (lt_i32
      (const_i32 1)
      (const_i32 2)))

  (then
    (do
      (return
        (const_i32 42))))

  (else
    (do
      (return
        (const_i32 0)))))
```

This is NOT yet a CFG.

The LLVM emitter creates blocks automatically.

Possible lowering:

```llvm
entry:
  br i1 %cond, label %then, label %else

then:
  ret i32 42

else:
  ret i32 0
```

---

### `(while (condition ...) (do ...))`

Structured loop.

Example:

```lisp
(while
  (condition
    (lt_i32
      (local_get i)
      (const_i32 7)))

  (do
    ...))
```

The emitter lowers this into CFG blocks.

---

### `(do ...)`

Groups an ordered statement sequence. Function bodies, loop bodies, and
conditional branches use `do` for statement sequencing.

Example:

```lisp
(do
  (set x ...)
  (set y ...))
```

---

## Return

### `(return VALUE)`

Returns a value from a function.

Example:

```lisp
(return
  (const_i32 42))
```

Possible lowering:

```llvm
ret i32 42
```

---

## Builtins

### `(print VALUE)`

Bootstrap builtin.

Example:

```lisp
(print
  (const_string "hello from weave"))
```

Current intended lowering:

```llvm
call i32 @puts(ptr @.str0)
```

This may later become:

```text
runtime function
intrinsic
external symbol
```

---

## Current Philosophy

The current IR intentionally remains:

```text
structured
typed
human-readable
recursive
```

It is NOT yet:

```text
SSA
CFG-oriented
machine-level
```

That decision keeps the bootstrap compiler small.

The current strategy is:

```text
First achieve stable self-hosting.
Then introduce lower-level IR stages later.
```

---

## Future Evolution

Expected future stages:

```text
Surface Weave
    ↓
TIR (current stage)
    ↓
CFG IR
    ↓
LLVM IR
```

Possible future CFG IR operations:

```text
br
cond_br
phi
load_i32
store_i32
alloca_i32
label
```

At that stage the representation becomes much closer to LLVM.

But that is intentionally postponed until after bootstrap stability.
