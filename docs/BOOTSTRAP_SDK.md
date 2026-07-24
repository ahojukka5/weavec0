# weavec0 bootstrap SDK

The bootstrap SDK is the versioned binary interface consumed by `weavec1`.
It lets the next compiler stage build without cloning or rebuilding `weavec0`.

Each Linux archive contains:

```text
bin/weavec0
lib/weavec0-bootstrap.bc
lib/weavec0-bootstrap.o
lib/libweavec0-runtime.a
include/runtime.h
README.md
LICENSE
```

The executable compiles WIR to LLVM IR. The bootstrap bitcode and object contain
the reusable compiler support modules but deliberately omit `main`. The static
runtime library provides the platform functions required by generated compiler
code.

Two x86-64 Linux variants are published:

- `glibc`: statically linked against glibc;
- `musl`: statically linked against musl.

A consumer must use the runtime library matching the selected archive. The
bootstrap object and bitcode are libc-neutral, while the runtime library is not.

The release workflow reads `VERSION`. When `master` contains a version for which
no GitHub Release exists, it creates tag `v<VERSION>` and publishes both SDK
archives together with `SHA256SUMS`.
