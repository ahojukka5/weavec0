# Stage 0 coverage and bootstrap-surface audit

`weavec0` is deliberately small, but source size alone does not establish that
its implementation is tested or required. The repository therefore measures two
independent properties:

1. **Execution coverage:** which handwritten LLVM functions, basic blocks, and
   conditional branch outcomes run while compiling the complete Stage 0 test
   corpus and the pinned `weavec1` production corpus.
2. **Bootstrap surface:** which admitted WIR keywords and which Stage 0 functions
   the pinned `weavec1` sources actually require.

These properties must remain separate. A reachable error path may be necessary
but difficult to exercise. Conversely, a fully covered legacy feature can still
be unnecessary for bootstrapping `weavec1`.

## Why not LLVM line coverage?

LLVM IR is structured into functions and basic blocks. Every instruction in an
entered basic block executes in sequence until its terminator. Comments, type
declarations, target metadata, global constants, and external declarations are
not executable lines. Counting source lines would therefore mix executable and
non-executable material and would not distinguish the two outcomes of a branch.

The audit uses:

- **function coverage** to identify entirely unentered routines;
- **basic-block coverage** as the closest meaningful analogue to statement or
  executable-line coverage;
- **branch-outcome coverage** to require both true and false outcomes of each
  conditional branch.

## Running the audit

First run the normal correctness and golden ladder:

```sh
./build.sh
```

Measure the Stage 0 test corpus alone:

```sh
bash scripts/run-coverage.sh
```

Measure it together with a checkout of the pinned `weavec1` corpus:

```sh
bash scripts/run-coverage.sh --weavec1-dir ../weavec1
```

The `weavec1` checkout must contain the commit recorded in
`WEAVEC1_BOOTSTRAP_COMMIT` when reproducing the CI result.

The runner writes:

```text
build/coverage/coverage-map.tsv
build/coverage/coverage-report.json
build/coverage/bootstrap-surface.json
```

The map connects instrumented identifiers back to the original LLVM function,
basic-block label, source file, and source line. The JSON reports list every
uncovered function, basic block, branch outcome, WIR keyword unused by
`weavec1`, and Stage 0 function unreachable from both the command-line compiler
and the pinned Stage 1 sources.

## Instrumentation boundary

The audit disassembles the already-linked `build/bootstrap-tests/weavec0.bc` and
instruments a temporary copy. It does not modify the checked-in LLVM modules,
the released compiler, or the runtime ABI. The ordinary `./build.sh` ladder must
pass before instrumentation begins.

## Current baseline

After the WIR v2 bootstrap-profile finalization, the combined Stage 0,
command-line, and pinned Stage 1 workload measures:

| Metric | Covered | Total | Coverage |
|---|---:|---:|---:|
| Functions | 230 | 230 | 100.00% |
| Basic blocks | 1,352 | 1,461 | 92.54% |
| Branch outcomes | 1,174 | 1,490 | 78.79% |

The static report contains no function unreachable from both Stage 0 `main` and
the pinned Stage 1 dependency roots.

CI currently enforces conservative non-regression floors of 95% function, 87%
basic-block, and 70% branch-outcome coverage. These floors prevent accidental
loss while leaving room to add focused tests and delete unnecessary code. They
are not a claim that Stage 0 is completely tested.

## Interpreting removal candidates

A feature or function is a strong removal candidate only when several forms of
evidence agree:

- absent from the pinned `weavec1` source corpus;
- absent from any direct Stage 1 call into Stage 0;
- unreachable in the static Stage 0 call graph from the command-line root;
- dynamically uncovered by both the tests and the Stage 1 compilation corpus;
- not required by the published WIR or runtime compatibility contract.

The final condition is essential. Removing an admitted Stage 0
bootstrap-profile form is a contract change even when current `weavec1` sources
do not use it. Such removals require an intentional bootstrap-profile version
transition, not a silent compatibility break.

See [architecture](architecture.md) and [minimization](minimization.md).
