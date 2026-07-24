# weavec0 — Weave Stage 0 Bootstrap Compiler

[![ci](https://github.com/ahojukka5/weavec0/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec0/actions/workflows/ci.yml)

> A small, hand-written LLVM-IR compiler that bootstraps the first
> compiler written in Weave.

## Overview

`weavec0` compiles the stable Weave intermediate representation, WIR
(`*.wir`), to human-readable LLVM IR (`*.ll`). The compiler itself is written
in LLVM IR and uses a deliberately small C runtime for file I/O, allocation,
output, and fatal diagnostics.

Its role is narrow:

```text
WIR source
    ↓
weavec0
    ↓
LLVM IR
```

Stage 0 is not intended to become the production compiler. It exists to remain
small, auditable, deterministic, and capable of building the next compiler
stage.

## Current status

- The source build passes a 101-case ladder: 91 positive cases and 10 expected
  failures.
- `weavec1` is successfully bootstrapped from the published Stage 0 SDK.
- Linux x86-64 SDKs are published for glibc and musl.
- The current release version is stored in [`VERSION`](VERSION).
- The WIR boundary is treated as stable; new language work belongs primarily in
  later compiler stages.

## Quick start from source

Prerequisites:

- LLVM and Clang 14 or newer;
- Bash 4 or newer.

On Debian or Ubuntu:

```sh
sudo apt-get install -y clang llvm
```

On macOS with Homebrew:

```sh
brew install llvm
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

Build the compiler and run the full ladder:

```sh
git clone https://github.com/ahojukka5/weavec0.git
cd weavec0
./build.sh
```

Compile a WIR program:

```sh
./weavec0 input.wir output.ll
llvm-as output.ll -o output.bc
clang output.ll -o output
```

The source build assembles the numbered LLVM modules, links them with
`runtime.c`, produces `./weavec0`, and executes every entry in
[`test/manifest.txt`](test/manifest.txt).

## Published bootstrap SDK

Downstream stages should normally consume the published SDK rather than clone
and rebuild Stage 0.

Release `v0.2.1` introduced the SDK layout:

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

The components have distinct purposes:

- `bin/weavec0` compiles WIR to LLVM IR;
- `weavec0-bootstrap.bc` and `weavec0-bootstrap.o` contain reusable compiler
  support code without `main`;
- `libweavec0-runtime.a` provides the libc-specific runtime implementation;
- `runtime.h` documents the runtime ABI.

Two static Linux x86-64 variants are published:

- `glibc` for conventional GNU/Linux systems;
- `musl` for a smaller broadly portable Linux binary.

The compiler, bootstrap object, and runtime library from one archive form a
matched SDK. Consumers must verify the archive against `SHA256SUMS` and use the
runtime library from the selected libc variant.

See [`docs/BOOTSTRAP_SDK.md`](docs/BOOTSTRAP_SDK.md) and
[`RELEASING.md`](RELEASING.md) for the binary contract and publication flow.

## Build and test ladder

```sh
./build.sh
./build.sh --regen-goldens
```

The build performs these steps:

1. assemble `src/NN_*.ll` modules with `llvm-as`;
2. link compiler bitcode with `llvm-link`;
3. link the compiler executable with `runtime.c`;
4. compile every positive WIR fixture;
5. compare generated LLVM IR with checked-in goldens;
6. assemble and link each generated program;
7. execute it and verify the expected exit code;
8. verify negative cases fail without producing LLVM IR.

`--regen-goldens` updates `*.expected.ll` files after an intentional emitter
change. Review the resulting diff before committing it.

## Repository layout

```text
weavec0/
├── build.sh
├── runtime.c
├── runtime.h
├── VERSION
├── src/
│   ├── 00_prelude.ll
│   ├── 01_runtime_bindings.ll
│   ├── 02_strings.ll
│   ├── 03_tokens.ll
│   ├── 04_lexer.ll
│   ├── 05_ast.ll
│   ├── 06_parser.ll
│   ├── 07_emit_llvm.ll
│   ├── 08_driver.ll
│   └── 09_main.ll
├── test/
│   ├── manifest.txt
│   ├── NN_<name>.wir
│   └── NN_<name>.expected.ll
├── scripts/
│   └── package-linux-release.sh
└── docs/
    ├── BOOTSTRAP_SDK.md
    └── source-style.md
```

Numeric module prefixes make dependency order explicit and keep the bootstrap
pipeline easy to audit:

```text
source bytes
    ↓
lexer
    ↓
tokens
    ↓
parser
    ↓
AST
    ↓
LLVM emitter
    ↓
LLVM IR
```

## Runtime boundary

`src/01_runtime_bindings.ll` declares the small ABI implemented by the runtime.
The admitted extern set is intentionally limited to the functions needed by the
compiler chain, including allocation, memory helpers, string operations, file
I/O, output, and fatal diagnostics.

The source build compiles `runtime.c`. Published SDK consumers link the matching
`libweavec0-runtime.a` instead. Downstream builds do not need to carry
`runtime.c` as source.

## Compiler chain

| Stage | Repository | Role |
|---|---|---|
| `weavec0` | **this repository** | Hand-written LLVM-IR seed and published bootstrap SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-written compiler built from the Stage 0 SDK. |
| `weavefront` | [`ahojukka5/weavefront`](https://github.com/ahojukka5/weavefront) | Surface Weave to WIR frontend built from the Stage 1 SDK. |
| `weavec2` | [`ahojukka5/weavec2`](https://github.com/ahojukka5/weavec2) | Self-hosted compiler written in surface Weave. |

The completed bootstrap progression is:

```text
hand-written LLVM IR
        ↓
     weavec0
        ↓
WIR-written weavec1
        ↓
surface-written weavec2
```

Future compiler development belongs in the upper stages. Stage 0 should change
only when the stable bootstrap contract genuinely requires it.

## Design rules

- No feature without an end-to-end test.
- Keep the parser and emitter explicit and auditable.
- Preserve deterministic LLVM output.
- Avoid speculative abstractions and production-compiler features.
- Version every externally visible WIR or runtime ABI change.
- Publish a new SDK before updating downstream dependency pins.

Source style is documented in
[`docs/source-style.md`](docs/source-style.md).

## Known limitations

- WIR is intentionally small and explicit.
- Diagnostics are compact and mostly lack precise source ranges.
- The admitted extern set is fixed and versioned.
- Linux SDKs currently target x86-64 only.
- The source prelude contains a Linux x86-64 target triple; the published SDK
  is therefore explicitly a Linux x86-64 product.
- `const_string_ptr` is supported only in the direct call-argument shape covered
  by `test/29_const_string_ptr.wir`.

## Releases

The release workflow builds both libc variants, runs the complete ladder,
verifies static linkage, performs SDK-only smoke tests, creates checksums, and
publishes `.tar.gz` archives.

A push to `master` creates `v<VERSION>` when that release does not yet exist.
Existing version releases remain immutable. An explicit `v*` tag may be used to
rebuild and replace damaged assets for that tag.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing the WIR contract,
runtime ABI, emitter output, or release packaging.
