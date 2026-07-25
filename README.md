# weavec0 — Weave Stage 0 Bootstrap Compiler

[![ci](https://github.com/ahojukka5/weavec0/actions/workflows/ci.yml/badge.svg)](https://github.com/ahojukka5/weavec0/actions/workflows/ci.yml)

> A small, hand-written LLVM-IR compiler that provides the reproducible seed for
> the Weave compiler chain.

## Role

`weavec0` compiles the WIR core version 2 bootstrap profile (`*.wir`),
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
- The combined test and pinned-`weavec1` corpus covers 98.17% of functions,
  90.16% of basic blocks, and 72.15% of conditional branch outcomes.
- The static audit reports no Stage 0 function unreachable from both the command
  line compiler and the pinned Stage 1 corpus.
- CI enforces conservative coverage non-regression floors and publishes a
  machine-readable bootstrap-surface report.
- Minimal Linux x86-64 SDKs are published for glibc and musl.
- `weavec1` uses `weavec0` only as a build-time compiler and does not embed the
  Stage 0 implementation in Stage 1 binaries.
- WIR core version 2 and the runtime ABI are versioned bootstrap contracts.
- The current release is 0.4.0; the authoritative value is stored in [`VERSION`](VERSION).

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

## Published Stage 0 SDK

Downstream stages should consume the published SDK instead of cloning and
rebuilding Stage 0.

```text
weavec0-vX.Y.Z-linux-x86_64-<libc>/
├── bin/
│   └── weavec0
├── lib/
│   └── libweavec0-runtime.a
├── include/
│   └── runtime.h
├── SDK-MANIFEST
├── VERSION
├── README.md
├── LICENSE
└── NOTICE
```

- `bin/weavec0` is the static WIR-to-LLVM build-time compiler.
- `libweavec0-runtime.a` is the matching libc-specific runtime implementation.
- `runtime.h` documents the runtime ABI.
- `SDK-MANIFEST` records the exact required components and target variant.

Stage 0 compiler implementation objects and bitcode are deliberately not part
of the SDK. The generated Stage 1 compiler is linked from its own generated
modules and the matching runtime; it does not embed Stage 0.

The glibc and musl archives implement the same compiler contract but contain
different runtime implementations. A consumer must verify the archive against
`SHA256SUMS` and keep the compiler and runtime from the selected variant
together.

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
5. assembles, links, and executes every generated positive program;
6. verifies expected exit codes and all expected-failure cases;
7. only after correctness passes, compares every generated LLVM file with its
   checked-in golden.

Use `--regen-goldens` only after an intentional emitter change and review the
resulting diff. Correctness is always checked before any fixture is regenerated.

## Coverage and minimisation audit

The audit measures function, basic-block, and branch-outcome coverage on a
temporary instrumented copy of the linked compiler. It runs both the Stage 0
test corpus and the exact `weavec1` source modules pinned in
[`WEAVEC1_BOOTSTRAP_COMMIT`](WEAVEC1_BOOTSTRAP_COMMIT).

```sh
bash scripts/run-coverage.sh
bash scripts/run-coverage.sh --weavec1-dir ../weavec1
```

It also inventories the WIR forms used by the pinned Stage 1 sources and computes
which Stage 0 functions are unreachable from either the command-line compiler or
any direct Stage 1 dependency. This evidence is used to add focused tests and to
identify code that can be removed safely.

See [`docs/COVERAGE.md`](docs/COVERAGE.md) for the metrics, reports, current
baseline, and compatibility rules for removal candidates.

## Repository layout

```text
weavec0/
├── build.sh
├── runtime.c
├── runtime.h
├── VERSION
├── WEAVEC1_BOOTSTRAP_COMMIT
├── src/                 hand-written LLVM compiler modules
├── test/                WIR fixtures and LLVM goldens
├── scripts/             release, audit, and coverage tools
└── docs/                SDK, coverage, and source-style documentation
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
| `weavec0` | **this repository** | Hand-written Stage 0 seed and minimal build SDK. |
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
- Version every externally visible WIR, runtime ABI, or SDK-layout change.
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
the exact minimal archive layout and static linkage, performs compile-link-run
smoke tests, creates checksums, and publishes `.tar.gz` archives.

A push to `master` creates `v<VERSION>` when that release does not already
exist. Existing version releases remain immutable.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing the WIR contract,
runtime ABI, emitter output, or release packaging.
