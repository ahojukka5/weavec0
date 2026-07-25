# weavec0 — Weave Stage 0 Bootstrap Compiler

[![ci](https://github.com/ahojukka5/weavec0/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec0/actions/workflows/ci.yml)

> A small, hand-written LLVM-IR compiler that provides the reproducible seed for
> the Weave compiler chain.

## Role

`weavec0` compiles the stable Weave intermediate representation, WIR (`*.wir`),
to LLVM IR (`*.ll`). The compiler is written directly in LLVM IR and uses a
small C runtime for file I/O, allocation, output, and fatal diagnostics.

```text
WIR source
    ↓
 weavec0
    ↓
 LLVM IR
```

Stage 0 is deliberately not the user-facing compiler. Its job is to remain
small, auditable, deterministic, and capable of building `weavec1`.

## Current status

- The source test ladder contains 104 cases: 93 positive cases and 11 expected failures.
- Linux x86-64 bootstrap SDKs are published for glibc and musl.
- `weavec1` builds from the published Stage 0 SDK without rebuilding this
  repository on Linux.
- The WIR and runtime boundaries are versioned bootstrap contracts.
- The current release version is stored in [`VERSION`](VERSION).

## Build from source

Requirements:

- LLVM and Clang 14 or newer;
- Bash 4 or newer.

```sh
git clone https://github.com/ahojukka5/weavec0.git
cd weavec0
./build.sh
```

Compile a WIR file:

```sh
./weavec0 input.wir output.ll
llvm-as output.ll -o output.bc
clang output.ll -o output
```

The source build assembles the numbered LLVM modules, links them with
`runtime.c`, creates `./weavec0`, and runs every case in
[`test/manifest.txt`](test/manifest.txt).

## Published bootstrap SDK

Downstream stages should consume the published SDK instead of cloning and
rebuilding Stage 0.

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

- `bin/weavec0` compiles WIR to LLVM IR.
- `weavec0-bootstrap.bc` and `weavec0-bootstrap.o` contain reusable compiler
  support code without `main`.
- `libweavec0-runtime.a` is the libc-specific runtime implementation.
- `runtime.h` documents the runtime ABI.

The glibc and musl archives contain the same compiler contract but different
runtime implementations. A consumer must verify the archive against
`SHA256SUMS` and keep all components from the selected variant together.

See [`docs/BOOTSTRAP_SDK.md`](docs/BOOTSTRAP_SDK.md) and
[`RELEASING.md`](RELEASING.md).

## Build and test ladder

```sh
./build.sh
./build.sh --regen-goldens
```

The build:

1. assembles `src/NN_*.ll` modules with `llvm-as`;
2. links compiler bitcode with `llvm-link`;
3. links the source compiler with `runtime.c`;
4. compiles every positive WIR fixture;
5. compares generated LLVM IR with checked-in goldens;
6. assembles, links, and runs generated programs;
7. verifies expected exit codes;
8. verifies negative cases fail without producing LLVM IR.

Use `--regen-goldens` only after an intentional emitter change and review the
resulting diff.

## Repository layout

```text
weavec0/
├── build.sh
├── runtime.c
├── runtime.h
├── VERSION
├── src/                 hand-written LLVM compiler modules
├── test/                WIR fixtures and LLVM goldens
├── scripts/             release packaging
└── docs/                SDK and source-style documentation
```

The numeric source prefixes expose the dependency order explicitly:

```text
source bytes → lexer → tokens → parser → AST → LLVM emitter → LLVM IR
```

## Runtime boundary

`src/01_runtime_bindings.ll` declares the small ABI implemented by the runtime.
The source build compiles `runtime.c`; SDK consumers link the matching
`libweavec0-runtime.a`. Downstream Linux builds do not need to carry
`runtime.c` as source.

## Compiler chain

| Component | Repository | Role |
|---|---|---|
| `weavec0` | **this repository** | Hand-written Stage 0 seed and bootstrap SDK. |
| `weavec1` | [`ahojukka5/weavec1`](https://github.com/ahojukka5/weavec1) | WIR-written compiler and Stage 1 SDK. |
| `weavec-bootstrap` | [`ahojukka5/weavec-bootstrap`](https://github.com/ahojukka5/weavec-bootstrap) | Frozen surface-Weave-to-WIR bootstrap frontend, formerly `weavefront`. |
| `weavec` | [`ahojukka5/weavec`](https://github.com/ahojukka5/weavec) | User-facing self-hosted compiler written in surface Weave, formerly `weavec2`. |

```text
hand-written LLVM IR
        ↓
     weavec0
        ↓
 WIR-written weavec1
        ↓
weavec-bootstrap
        ↓
      weavec
```

Normal users should install and use `weavec`. The three lower repositories form
the reproducible bootstrap chain and should change conservatively.

## Design rules

- No feature without an end-to-end test.
- Keep the parser and emitter explicit and auditable.
- Preserve deterministic LLVM output.
- Avoid production-compiler features in Stage 0.
- Version every externally visible WIR or runtime ABI change.
- Publish a new SDK before updating downstream dependency pins.

Source style is documented in [`docs/source-style.md`](docs/source-style.md).

## Known limitations

- WIR is intentionally small and explicit.
- Diagnostics are compact and mostly lack precise source ranges.
- The admitted extern set is fixed and versioned.
- Published SDKs currently target Linux x86-64 only.
- `const_string_ptr` is supported only in the direct call-argument shape covered
  by `test/29_const_string_ptr.wir`.

## Releases

The release workflow builds glibc and musl SDKs, runs the full ladder, verifies
static linkage, performs SDK-only smoke tests, creates checksums, and publishes
`.tar.gz` archives.

A push to `master` creates `v<VERSION>` when that release does not already
exist. Existing version releases remain immutable.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing the WIR contract,
runtime ABI, emitter output, or release packaging.
