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
    }
    if args.json_path:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
