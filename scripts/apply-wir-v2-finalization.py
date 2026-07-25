#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
W1_COMMIT = sys.argv[1] if len(sys.argv) > 1 else "agent/wir-v2"


def read(path: str) -> str:
    return (ROOT / path).read_text()


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1, got {count}")
    return text.replace(old, new, 1)


# WIR v2 fixtures. Test 104 intentionally remains v1 to prove rejection.
for path in sorted((ROOT / "test").glob("*.wir")):
    path.write_text(path.read_text().replace("(core-version 1)", "(core-version 2)"))
path = "test/104_unsupported_core_version.wir"
text = read(path)
text = text.replace("claims an unsupported WIR version", "claims the superseded WIR core version 1")
text = text.replace("(core-version 2)", "(core-version 1)")
write(path, text)

for path in sorted((ROOT / "scripts").glob("*.sh")):
    path.write_text(path.read_text().replace("(core-version 1)", "(core-version 2)"))

# Stage 0 contract validator and parser documentation.
path = "src/08_driver.ll"
text = read(path)
text = text.replace("( core-module ( core-version 1 ) ...", "( core-module ( core-version 2 ) ...")
text = replace_once(
    text,
    "%version_ok = icmp eq i64 %version, 1",
    "%version_ok = icmp eq i64 %version, 2",
    "driver version check",
)
write(path, text)

path = "src/06_parser.ll"
text = read(path)
text = text.replace("(core-module (core-version 1) (decls ...))", "(core-module (core-version 2) (decls ...))")
text = text.replace("(core-version 1)", "(core-version 2)")
text = replace_once(
    text,
    """check_store_i8:
  %is_store_i8 = icmp eq i32 %head_kind, 66
  br i1 %is_store_i8, label %store_i8_stmt, label %check_block

check_block:
  %is_block = icmp eq i32 %head_kind, 24
  br i1 %is_block, label %block_stmt, label %check_do
""",
    """check_store_i8:
  %is_store_i8 = icmp eq i32 %head_kind, 66
  br i1 %is_store_i8, label %store_i8_stmt, label %check_do
""",
    "statement block alias",
)
text = replace_once(
    text,
    """read_head:
  %head_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_block = icmp eq i32 %head_kind, 24
  br i1 %is_block, label %consume_head, label %check_do_head

check_do_head:
  %is_do = icmp eq i32 %head_kind, 87
  br i1 %is_do, label %consume_head, label %fail
""",
    """read_head:
  %head_kind = call i32 @weave_parser_current_kind(ptr %parser)
  %is_do = icmp eq i32 %head_kind, 87
  br i1 %is_do, label %consume_head, label %fail
""",
    "block parser alias",
)
write(path, text)

path = "src/07_emit_llvm.ll"
write(path, read(path).replace(
    "every (const_string ...) referenced by the program",
    "every (const_string_ptr ...) referenced by the program",
))

# Documentation contract.
path = "docs/weave-intermediate-representation.md"
text = read(path)
text = text.replace("(core-version 1)", "(core-version 2)")
text = text.replace("### `(const_string TEXT)`", "### `(const_string_ptr TEXT)`")
text = text.replace('(const_string "hello")', '(const_string_ptr "hello")')
text = re.sub(
    r"\n## Builtins\n.*?\n---\n\n## Current Philosophy",
    "\n## Stage 0 bootstrap profile\n\n"
    "`weavec0` implements only the WIR v2 forms required by the pinned `weavec1`\n"
    "source modules. The complete WIR v2 backend lives in `weavec1`; Stage 0 is not\n"
    "expanded merely for feature parity.\n\n---\n\n## Current Philosophy",
    text,
    count=1,
    flags=re.S,
)
write(path, text)

write("docs/MINIMIZATION.md", """# Stage 0 minimization rule

`weavec0` exists only to produce the pinned `weavec1` compiler.

A WIR form belongs in Stage 0 only when it occurs in the source modules at
`WEAVEC1_BOOTSTRAP_COMMIT`. Stage 0 accepts WIR core version 2 but implements a
strict bootstrap profile rather than the complete Stage 1 language surface.

A compiler helper belongs only when it is reachable from the command-line
compilation path required for those sources. Correctness and hardening code
remain when they protect that path: bounded memory operations, deterministic
output, stable diagnostics, runtime ABI validation, and reproducible SDK
packaging are not optional language features.

The bootstrap-surface audit is the removal gate. It must compile every pinned
Stage 1 module, report no Stage 0-only keyword, report no unreachable Stage 0
function, and find no residual implementation of removed compatibility forms.
""")

path = "docs/COVERAGE.md"
text = read(path)
text = text.replace(
    "Removing an admitted WIR v1 form is a contract",
    "Removing an admitted Stage 0 bootstrap-profile form is a contract",
)
text = text.replace(
    "Such removals must be\nmade through an intentional new bootstrap contract or version, not silently.",
    "Such removals require an intentional bootstrap-profile version transition,\n"
    "not a silent compatibility break.",
)
write(path, text)

path = "RELEASING.md"
text = read(path)
text = text.replace(
    "A downstream pin may be updated to `v0.3.0` only after the release exists.",
    "A downstream pin may be updated to `v0.4.0` only after the release exists.",
)
text = text.replace("scripts/package-linux-release.sh glibc v0.3.0 dist", "scripts/package-linux-release.sh glibc v0.4.0 dist")
text = text.replace("scripts/package-linux-release.sh musl v0.3.0 dist", "scripts/package-linux-release.sh musl v0.4.0 dist")
text = text.replace("weavec0-v0.3.0-linux-x86_64-musl.tar.gz", "weavec0-v0.4.0-linux-x86_64-musl.tar.gz")
text = text.replace("cd weavec0-v0.3.0-linux-x86_64-musl", "cd weavec0-v0.4.0-linux-x86_64-musl")
write(path, text)

path = "README.md"
text = read(path)
text = text.replace(
    "compiles the stable Weave intermediate representation, WIR (`*.wir`),",
    "compiles the WIR core version 2 bootstrap profile (`*.wir`),",
)
text = text.replace(
    "- The WIR and runtime boundaries are versioned bootstrap contracts.",
    "- WIR core version 2 and the runtime ABI are versioned bootstrap contracts.",
)
text = text.replace(
    "- The current release version is stored in [`VERSION`](VERSION).",
    "- The current release is 0.4.0; the authoritative value is stored in [`VERSION`](VERSION).",
)
write(path, text)

write("VERSION", "0.4.0\n")
write("WEAVEC1_BOOTSTRAP_COMMIT", W1_COMMIT + "\n")

# Consolidate prior minimization notes into the 0.4.0 release.
changelog = read("CHANGELOG.md")
start = changelog.index("## [Unreleased]")
next_version = changelog.index("## [0.3.3]")
rest = changelog[next_version:]
new_top = """## [Unreleased]

## [0.4.0] — 2026-07-25

### Changed

- Stage 0 now accepts only WIR core version 2 and pins the corresponding
  `weavec1` source corpus.
- Documented Stage 0 as a strict bootstrap profile of the complete Stage 1 WIR
  backend.

### Removed

- Five forms absent from the pinned Stage 1 source modules: `block`,
  `const_string`, `print`, `gt_i64`, and `ge_i64`.
- The remaining unreachable parser branches for the legacy `block` alias.
- The print-specific LLVM lowering path; required string output uses ordinary
  `call_i32 puts` with `const_string_ptr`.

### Added

- Static audit checks that reject residual implementations of removed Stage 0
  compatibility forms.
- A regression proving the superseded core version 1 contract is rejected.

"""
write("CHANGELOG.md", changelog[:start] + new_top + rest)

# Extend the machine-readable audit with source-level residual checks.
path = "scripts/audit_bootstrap_surface.py"
text = read(path)
helper = '''

def legacy_implementation_residuals(root: Path) -> list[dict[str, str]]:
    checks = {
        "src/04_lexer.ll": {
            "legacy block keyword": r"@weave\\.kw\\.block\\b",
            "legacy const_string keyword": r"@weave\\.kw\\.const_string\\s*=",
            "legacy print keyword": r"@weave\\.kw\\.print\\b",
            "legacy gt_i64 keyword": r"@weave\\.kw\\.gt_i64\\b",
            "legacy ge_i64 keyword": r"@weave\\.kw\\.ge_i64\\b",
        },
        "src/06_parser.ll": {
            "legacy block token branch": r"%is_block\\s*=\\s*icmp eq i32 %head_kind, 24",
            "legacy print parser branch": r"^check_print:",
        },
        "src/07_emit_llvm.ll": {
            "legacy print lowering": r"@weave\\.emit\\.(?:print_name|puts_call)",
            "legacy gt_i64 lowering": r"@weave\\.emit\\.icmp_gt_i64",
            "legacy ge_i64 lowering": r"@weave\\.emit\\.icmp_ge_i64",
        },
        "docs/weave-intermediate-representation.md": {
            "legacy print documentation": r"\\(print\\b",
            "legacy const_string documentation": r"\\(const_string\\s",
        },
    }
    residuals: list[dict[str, str]] = []
    for relative, patterns in checks.items():
        source = (root / relative).read_text(encoding="utf-8")
        for description, pattern in patterns.items():
            if re.search(pattern, source, re.MULTILINE):
                residuals.append({"path": relative, "description": description})
    return residuals
'''
text = replace_once(text, "def main() -> int:\n", helper + "\ndef main() -> int:\n", "audit residual helper")
text = replace_once(
    text,
    "    unreachable = sorted(weavec0_definitions - reachable)\n",
    "    unreachable = sorted(weavec0_definitions - reachable)\n"
    "    legacy_residuals = legacy_implementation_residuals(args.weavec0)\n",
    "audit residual compute",
)
text = replace_once(
    text,
    '    print("weavec0 functions unreachable from main or pinned weavec1:")\n'
    '    for name in unreachable:\n'
    '        print(f"  {name}")\n',
    '    print("weavec0 functions unreachable from main or pinned weavec1:")\n'
    '    for name in unreachable:\n'
    '        print(f"  {name}")\n'
    '    print("legacy Stage 0 implementation residuals:")\n'
    '    for item in legacy_residuals:\n'
    '        print(f"  {item[\'path\']}: {item[\'description\']}")\n',
    "audit residual print",
)
text = replace_once(
    text,
    '        "unreachable_weavec0_functions": unreachable,\n',
    '        "unreachable_weavec0_functions": unreachable,\n'
    '        "legacy_implementation_residuals": legacy_residuals,\n',
    "audit residual report",
)
text = replace_once(
    text,
    "    return 0\n\n\nif __name__ == \"__main__\":",
    "    if unused or unreachable or legacy_residuals:\n"
    "        return 1\n"
    "    return 0\n\n\nif __name__ == \"__main__\":",
    "audit failure gate",
)
write(path, text)

path = "scripts/run-structural-negative-matrix.sh"
write(path, read(path).replace("run_case block-truncated", "run_case do-truncated"))

# Contract assertions.
for path in sorted((ROOT / "test").glob("*.wir")):
    source = path.read_text()
    if path.name == "104_unsupported_core_version.wir":
        if "(core-version 1)" not in source:
            raise SystemExit("test 104 must reject v1")
    elif "(core-version 1)" in source:
        raise SystemExit(f"v1 remains in fixture: {path}")
for path in sorted((ROOT / "scripts").glob("*.sh")):
    if "(core-version 1)" in path.read_text():
        raise SystemExit(f"v1 remains in generated workload: {path}")

print("migrated weavec0 to WIR v2 release contract")
