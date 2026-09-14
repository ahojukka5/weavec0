# Historical trusted-surface study

This repository contains a bounded research audit for the Stage 0 minimization
studied by `ahojukka5/research#331` and implemented under `weavec0#35`.

The experiment compares two immutable Stage 0 revisions against the same pinned
Stage 1 source corpus:

- broader seed: `c720014d35d21ba0ed1a38c9645e566b37b4dfbe`;
- minimized seed: `a0aeb3919cdeec1e47a931fdfa7dc660a78567ff`.

Both revisions pin Stage 1 commit
`963bd99a62b2db0482817ba49bcdbc02e624a20a`.

The minimized revision removed the WIR forms `block`, `const_string`, `print`,
`gt_i64`, and `ge_i64` because they were absent from that frozen Stage 1
production corpus. The study measures that historical intervention; it does not
modify either revision or authorize further minimization.

## Metrics

`scripts/trust_surface_metrics.py` reports independent surface measures rather
than one weighted trust score:

- hand-written LLVM source bytes;
- non-comment LLVM source lines;
- LLVM function definitions;
- explicit LLVM basic-block labels;
- admitted non-lexical WIR token/keyword forms;
- C runtime source bytes;
- runtime ABI function count;
- built compiler binary bytes;
- build-time host tools named by `build.sh`;
- source/runtime hashes and the pinned Stage 1 commit.

Source bytes are the exact UTF-8 bytes under `src/*.ll`. Non-comment lines omit
blank lines and LLVM `;` comments. Basic blocks count explicit labels in the
hand-written LLVM source; this is a structural surface measure, not dynamic
coverage. Runtime and host-tool measures remain separate so compiler logic is
not credited as removed when it merely moves across the trust boundary.

## Reconstruction check

`scripts/run_trust_surface_study.py` creates detached worktrees for both Stage 0
revisions and two copies of the exact pinned Stage 1 revision. It:

1. builds and tests each historical Stage 0 checkout;
2. records the same trust-surface metrics for both;
3. builds the same Stage 1 source corpus using each historical Stage 0 source
   fallback;
4. records hashes of Stage 1, self-host, generated source LLVM, self-host LLVM,
   and test LLVM artifacts;
5. compares those outputs without treating binary equality as the only valid
   correctness signal.

The historical Stage 1 build prefers a published SDK on Linux before consulting
its documented `WEAVEC0` source override. The research runner therefore prepends
a private `uname` shim that reports an unsupported host only to that build
process. This selects Stage 1's existing source-fallback branch without changing
Stage 0 or Stage 1 source. The result records this harness adaptation explicitly.

## Running the study

Use a local `weavec1` clone that contains the pinned commit:

```bash
git clone https://github.com/ahojukka5/weavec1.git ../weavec1
python3 scripts/test_trust_surface_metrics.py
python3 scripts/run_trust_surface_study.py \
  --weavec1-repo ../weavec1 \
  --output build/trust-surface-study/result.json
```

The runner needs Git, Python 3, Bash, Clang and LLVM tools required by the two
historical builds. It writes the aggregate JSON plus per-arm Stage 0 and Stage 1
build logs under `build/trust-surface-study/`.

A manual GitHub Actions workflow, `trust-surface-study.yml`, performs the same
bounded run and uploads its evidence artifact. The workflow is intentionally not
part of routine compiler CI because this historical reconstruction is research
evidence rather than a product regression gate.

## Interpretation boundary

The owning `research` report decides what the measured differences mean. This
repository preserves executable protocol and raw evidence only. In particular:

- a lower source byte count is not by itself a security proof;
- dynamic coverage is supporting evidence, not a trusted-surface metric;
- unchanged runtime code is evidence against moving this particular reduction
  into the C runtime, but says nothing about the trustworthiness of host LLVM,
  Clang, libc, or the operating system;
- one compiler chain is a bounded case study, not a universal bootstrap result.
