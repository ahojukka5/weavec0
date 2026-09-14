#!/usr/bin/env python3
"""Measure the compiler-specific trusted surface of one weavec0 checkout."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

TOKEN_RE = re.compile(r"^;\s*TOKEN_([A-Z0-9_]+)\s*=", re.MULTILINE)
DEFINE_RE = re.compile(r"^\s*define\b")
BLOCK_LABEL_RE = re.compile(r'^\s*(?:[A-Za-z$._][A-Za-z0-9$._-]*|[0-9]+):(?:\s*;.*)?$')
RUNTIME_ABI_RE = re.compile(r"\b(weave_rt_[A-Za-z0-9_]+)\s*\(")
REQUIRE_TOOL_RE = re.compile(r"^\s*require_tool\s+([A-Za-z0-9_.+-]+)\s*$", re.MULTILINE)
EXCLUDED_TOKENS = {"EOF", "LPAREN", "RPAREN", "IDENT", "INT", "STRING"}


def git_head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def noncomment_llvm_loc(text: str) -> int:
    return sum(1 for line in text.splitlines() if line.strip() and not line.lstrip().startswith(";"))


def llvm_metrics(paths: list[Path], root: Path) -> dict[str, object]:
    function_count = 0
    basic_block_count = 0
    source_bytes = 0
    source_loc = 0
    source_hash = hashlib.sha256()
    per_file: list[dict[str, object]] = []

    for path in paths:
        data = path.read_bytes()
        text = data.decode("utf-8")
        size = len(data)
        loc = noncomment_llvm_loc(text)
        functions = sum(1 for line in text.splitlines() if DEFINE_RE.match(line))
        blocks = sum(1 for line in text.splitlines() if BLOCK_LABEL_RE.match(line))
        source_bytes += size
        source_loc += loc
        function_count += functions
        basic_block_count += blocks
        relative = path.relative_to(root).as_posix()
        source_hash.update(relative.encode("utf-8"))
        source_hash.update(b"\0")
        source_hash.update(data)
        source_hash.update(b"\0")
        per_file.append(
            {
                "path": relative,
                "bytes": size,
                "noncomment_loc": loc,
                "functions": functions,
                "basic_blocks": blocks,
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        )

    return {
        "source_bytes": source_bytes,
        "noncomment_loc": source_loc,
        "function_count": function_count,
        "basic_block_count": basic_block_count,
        "source_tree_sha256": source_hash.hexdigest(),
        "files": per_file,
    }


def keyword_inventory(prelude: str) -> list[str]:
    keywords: list[str] = []
    for token in TOKEN_RE.findall(prelude):
        if token in EXCLUDED_TOKENS or token.startswith("RESERVED_"):
            continue
        if token == "CORE_MODULE":
            keywords.append("core-module")
        elif token == "CORE_VERSION":
            keywords.append("core-version")
        else:
            keywords.append(token.lower())
    return sorted(keywords)


def file_record(path: Path, root: Path) -> dict[str, object] | None:
    if not path.is_file():
        return None
    data = path.read_bytes()
    return {
        "path": path.relative_to(root).as_posix(),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def measure(root: Path, binary: Path | None = None) -> dict[str, object]:
    root = root.resolve()
    src_dir = root / "src"
    sources = sorted(src_dir.glob("*.ll"))
    if not sources:
        raise ValueError(f"no Stage 0 LLVM sources under {src_dir}")

    prelude_path = src_dir / "00_prelude.ll"
    runtime_c = root / "runtime.c"
    runtime_h = root / "runtime.h"
    build_sh = root / "build.sh"
    pin_path = root / "WEAVEC1_BOOTSTRAP_COMMIT"
    for required in (prelude_path, runtime_c, runtime_h, build_sh, pin_path):
        if not required.is_file():
            raise ValueError(f"required Stage 0 file missing: {required}")

    source = llvm_metrics(sources, root)
    keywords = keyword_inventory(prelude_path.read_text(encoding="utf-8"))
    runtime_header = runtime_h.read_text(encoding="utf-8")
    runtime_abi = sorted(set(RUNTIME_ABI_RE.findall(runtime_header)))
    build_text = build_sh.read_text(encoding="utf-8")
    required_tools = sorted(set(REQUIRE_TOOL_RE.findall(build_text)))
    pinned_stage1 = pin_path.read_text(encoding="utf-8").strip()

    if binary is None:
        default_binary = root / "weavec0"
        binary = default_binary if default_binary.is_file() else None
    elif not binary.is_absolute():
        binary = root / binary
    binary = binary.resolve() if binary is not None else None

    return {
        "schema": "weavec0-trust-surface-v1",
        "git_commit": git_head(root),
        "pinned_weavec1_commit": pinned_stage1,
        "llvm_source": source,
        "wir_surface": {
            "keyword_count": len(keywords),
            "keywords": keywords,
        },
        "runtime": {
            "source": file_record(runtime_c, root),
            "header": file_record(runtime_h, root),
            "abi_function_count": len(runtime_abi),
            "abi_functions": runtime_abi,
        },
        "build": {
            "required_tools": required_tools,
            "compiler_binary": file_record(binary, root) if binary is not None else None,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--json", dest="json_path", type=Path)
    args = parser.parse_args()

    report = measure(args.root, args.binary)
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.json_path:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
