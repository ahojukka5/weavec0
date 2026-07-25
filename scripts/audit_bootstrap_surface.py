#!/usr/bin/env python3
"""Compare weavec0's keyword surface with the pinned weavec1 source corpus."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

TOKEN_RE = re.compile(r"^;\s*TOKEN_([A-Z0-9_]+)\s*=", re.MULTILINE)
EXCLUDED = {"EOF", "LPAREN", "RPAREN", "IDENT", "INT", "STRING"}


def keyword_from_token(name: str) -> str | None:
    if name in EXCLUDED or name.startswith("RESERVED_"):
        return None
    if name == "CORE_MODULE":
        return "core-module"
    if name == "CORE_VERSION":
        return "core-version"
    return name.lower()


def tokenize_wir(text: str) -> list[str]:
    tokens: list[str] = []
    index = 0
    while index < len(text):
        char = text[index]
        if char.isspace():
            index += 1
            continue
        if char == ";":
            newline = text.find("\n", index)
            index = len(text) if newline < 0 else newline + 1
            continue
        if char in "()":
            tokens.append(char)
            index += 1
            continue
        if char == '"':
            index += 1
            while index < len(text):
                if text[index] == "\\":
                    index += 2
                elif text[index] == '"':
                    index += 1
                    break
                else:
                    index += 1
            tokens.append("<string>")
            continue
        end = index
        while end < len(text) and not text[end].isspace() and text[end] not in "();":
            end += 1
        tokens.append(text[index:end])
        index = end
    return tokens


def inventory(paths: list[Path]) -> tuple[Counter[str], Counter[str]]:
    symbols: Counter[str] = Counter()
    heads: Counter[str] = Counter()
    for path in paths:
        tokens = tokenize_wir(path.read_text(encoding="utf-8"))
        expect_head = False
        for token in tokens:
            if token == "(":
                expect_head = True
                continue
            if token == ")":
                expect_head = False
                continue
            if token == "<string>":
                expect_head = False
                continue
            if not re.fullmatch(r"-?[0-9]+", token):
                symbols[token] += 1
                if expect_head:
                    heads[token] += 1
            expect_head = False
    return symbols, heads


def parse_sexpressions(tokens: list[str]) -> list[list[object]]:
    roots: list[list[object]] = []
    stack: list[list[object]] = []
    for token in tokens:
        if token == "(":
            node: list[object] = []
            if stack:
                stack[-1].append(node)
            else:
                roots.append(node)
            stack.append(node)
        elif token == ")":
            if not stack:
                raise ValueError("unbalanced closing parenthesis")
            stack.pop()
        elif stack:
            stack[-1].append(token)
    if stack:
        raise ValueError("unclosed parenthesis")
    return roots


def walk_forms(node: object):
    if not isinstance(node, list):
        return
    if node:
        yield node
    for child in node:
        yield from walk_forms(child)


def wir_link_inventory(paths: list[Path]) -> tuple[Counter[str], set[str], set[str]]:
    callees: Counter[str] = Counter()
    definitions: set[str] = set()
    externs: set[str] = set()
    call_heads = {"call_i32", "call_i64", "call_bool", "call_ptr", "call_void"}
    for path in paths:
        forms = parse_sexpressions(tokenize_wir(path.read_text(encoding="utf-8")))
        for root in forms:
            for form in walk_forms(root):
                if not form or not isinstance(form[0], str):
                    continue
                head = form[0]
                if head == "fn" and len(form) > 1 and isinstance(form[1], str):
                    definitions.add(form[1])
                elif head == "extern" and len(form) > 1 and isinstance(form[1], str):
                    externs.add(form[1])
                elif head in call_heads and len(form) > 1 and isinstance(form[1], str):
                    callees[form[1]] += 1
    return callees, definitions, externs


def llvm_call_graph(src_dir: Path) -> tuple[set[str], dict[str, set[str]]]:
    define_re = re.compile(r"^\s*define\b")
    name_re = re.compile(r"@([A-Za-z$._][A-Za-z0-9$._-]*)")
    definitions: set[str] = set()
    bodies: dict[str, list[str]] = {}
    for path in sorted(src_dir.glob("*.ll")):
        lines = path.read_text(encoding="utf-8").splitlines()
        index = 0
        while index < len(lines):
            if not define_re.match(lines[index]):
                index += 1
                continue
            signature = [lines[index]]
            while "{" not in signature[-1]:
                index += 1
                signature.append(lines[index])
            match = name_re.search(" ".join(signature))
            if not match:
                raise ValueError(f"cannot parse function definition in {path}")
            name = match.group(1)
            definitions.add(name)
            body: list[str] = []
            index += 1
            while index < len(lines) and lines[index].strip() != "}":
                body.append(lines[index])
                index += 1
            bodies[name] = body
            index += 1
    graph: dict[str, set[str]] = {name: set() for name in definitions}
    for name, body in bodies.items():
        references = set(name_re.findall("\n".join(body)))
        graph[name] = (references & definitions) - {name}
    return definitions, graph


def reachable_functions(graph: dict[str, set[str]], roots: set[str]) -> set[str]:
    seen: set[str] = set()
    stack = sorted(root for root in roots if root in graph)
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        stack.extend(sorted(graph[name] - seen))
    return seen


def legacy_implementation_residuals(root: Path) -> list[dict[str, str]]:
    checks = {
        "src/04_lexer.ll": {
            "legacy block keyword": r"@weave\.kw\.block\b",
            "legacy const_string keyword": r"@weave\.kw\.const_string\s*=",
            "legacy print keyword": r"@weave\.kw\.print\b",
            "legacy gt_i64 keyword": r"@weave\.kw\.gt_i64\b",
            "legacy ge_i64 keyword": r"@weave\.kw\.ge_i64\b",
        },
        "src/06_parser.ll": {
            "legacy block token branch": r"%is_block\s*=\s*icmp eq i32 %head_kind, 24",
            "legacy print parser branch": r"^check_print:",
        },
        "src/07_emit_llvm.ll": {
            "legacy print lowering": r"@weave\.emit\.(?:print_name|puts_call)",
            "legacy gt_i64 lowering": r"@weave\.emit\.icmp_gt_i64",
            "legacy ge_i64 lowering": r"@weave\.emit\.icmp_ge_i64",
        },
        "docs/wir.md": {
            "legacy print documentation": r"\(print\b",
            "legacy const_string documentation": r"\(const_string\s",
        },
    }
    residuals: list[dict[str, str]] = []
    for relative, patterns in checks.items():
        source = (root / relative).read_text(encoding="utf-8")
        for description, pattern in patterns.items():
            if re.search(pattern, source, re.MULTILINE):
                residuals.append({"path": relative, "description": description})
    return residuals


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--weavec0", type=Path, required=True)
    parser.add_argument("--weavec1", type=Path, required=True)
    parser.add_argument("--json", dest="json_path", type=Path)
    args = parser.parse_args()

    prelude = (args.weavec0 / "src/00_prelude.ll").read_text(encoding="utf-8")
    keywords = sorted(
        keyword for token in TOKEN_RE.findall(prelude)
        if (keyword := keyword_from_token(token)) is not None
    )
    build_text = (args.weavec1 / "build.sh").read_text(encoding="utf-8")
    module_match = re.search(r"^MODULES=\(\n(?P<body>.*?)^\)", build_text, re.MULTILINE | re.DOTALL)
    if not module_match:
        raise SystemExit("cannot locate weavec1 MODULES array in build.sh")
    module_names = []
    for raw_line in module_match.group("body").splitlines():
        line = raw_line.split("#", 1)[0].strip().strip('"')
        if line:
            module_names.append(line)
    weavec1_paths = [args.weavec1 / "src" / f"{name}.wir" for name in module_names]
    missing = [path for path in weavec1_paths if not path.is_file()]
    if missing:
        raise SystemExit("missing weavec1 modules: " + ", ".join(path.as_posix() for path in missing))
    test_paths = sorted((args.weavec0 / "test").glob("*.wir"))
    try:
        weavec1_commit = subprocess.check_output(
            ["git", "-C", str(args.weavec1), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        weavec1_commit = None

    source_symbols, source_heads = inventory(weavec1_paths)
    test_symbols, test_heads = inventory(test_paths)
    call_targets, weavec1_definitions, weavec1_externs = wir_link_inventory(weavec1_paths)
    weavec0_definitions, weavec0_graph = llvm_call_graph(args.weavec0 / "src")
    stage0_dependencies = sorted(set(call_targets) & weavec0_definitions)
    roots = {"main", *stage0_dependencies}
    reachable = reachable_functions(weavec0_graph, roots)
    unreachable = sorted(weavec0_definitions - reachable)
    legacy_residuals = legacy_implementation_residuals(args.weavec0)

    unused = [keyword for keyword in keywords if source_symbols[keyword] == 0]
    test_only = [keyword for keyword in unused if test_symbols[keyword] > 0]
    untested = [keyword for keyword in keywords if test_symbols[keyword] == 0]

    print(f"weavec0 keyword tokens: {len(keywords)}")
    print(f"keywords used by pinned weavec1 sources: {len(keywords) - len(unused)}")
    print("unused by weavec1:")
    for keyword in unused:
        detail = f"tests={test_symbols[keyword]}, heads={test_heads[keyword]}"
        print(f"  {keyword:24s} {detail}")
    if untested:
        print("keywords not present in the weavec0 WIR test corpus:")
        for keyword in untested:
            print(f"  {keyword}")
    print("weavec1 direct dependencies provided by weavec0:")
    for name in stage0_dependencies:
        print(f"  {name:40s} calls={call_targets[name]}")
    print("weavec0 functions unreachable from main or pinned weavec1:")
    for name in unreachable:
        print(f"  {name}")
    print("legacy Stage 0 implementation residuals:")
    for item in legacy_residuals:
        print(f"  {item['path']}: {item['description']}")

    report = {
        "weavec1_commit": weavec1_commit,
        "weavec1_modules": module_names,
        "weavec1_source_files": [path.as_posix() for path in weavec1_paths],
        "weavec0_keywords": keywords,
        "unused_by_weavec1": unused,
        "test_only_keywords": test_only,
        "untested_keywords": untested,
        "weavec1_symbol_counts": dict(sorted(source_symbols.items())),
        "weavec1_head_counts": dict(sorted(source_heads.items())),
        "weavec0_test_symbol_counts": dict(sorted(test_symbols.items())),
        "weavec0_test_head_counts": dict(sorted(test_heads.items())),
        "weavec1_function_definitions": sorted(weavec1_definitions),
        "weavec1_externs": sorted(weavec1_externs),
        "weavec1_call_targets": dict(sorted(call_targets.items())),
        "weavec1_stage0_direct_dependencies": stage0_dependencies,
        "weavec0_reachability_roots": sorted(roots),
        "unreachable_weavec0_functions": unreachable,
        "legacy_implementation_residuals": legacy_residuals,
    }
    if args.json_path:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if unused or unreachable or legacy_residuals:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
