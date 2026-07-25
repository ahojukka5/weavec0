#!/usr/bin/env python3
"""Instrument linked handwritten LLVM IR for block and branch coverage."""
from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

DEFINE_RE = re.compile(r"^\s*define\b")
FUNC_NAME_RE = re.compile(r"@([A-Za-z$._][A-Za-z0-9$._-]*)\s*\(")
LABEL_RE = re.compile(r"^\s*([A-Za-z$._][A-Za-z0-9$._-]*):(?:\s*;.*)?$")
PHI_RE = re.compile(r"^\s*%[^=]+?=\s*phi\b")
COND_BR_RE = re.compile(
    r"^(?P<indent>\s*)br\s+i1\s+(?P<cond>[^,]+),\s*label\s+%[^,]+,\s*label\s+%\S+\s*(?:;.*)?$"
)


@dataclass(frozen=True)
class SourceLocation:
    path: str
    line: int


@dataclass(frozen=True)
class BlockRecord:
    ident: int
    function: str
    label: str
    source: str
    line: int


@dataclass(frozen=True)
class BranchRecord:
    ident: int
    function: str
    label: str
    source: str
    line: int


def extract_function_name(signature: str) -> str:
    match = FUNC_NAME_RE.search(signature)
    if not match:
        raise ValueError(f"cannot parse LLVM function name from: {signature!r}")
    return match.group(1)


def scan_source_locations(src_dir: Path) -> tuple[dict[tuple[str, str], SourceLocation], dict[str, str]]:
    blocks: dict[tuple[str, str], SourceLocation] = {}
    function_files: dict[str, str] = {}
    for path in sorted(src_dir.glob("*.ll")):
        lines = path.read_text(encoding="utf-8").splitlines()
        current_function: str | None = None
        signature_parts: list[str] = []
        in_signature = False
        for line_no, line in enumerate(lines, 1):
            if current_function is None and not in_signature and DEFINE_RE.match(line):
                in_signature = True
                signature_parts = [line]
                if "{" in line:
                    current_function = extract_function_name(" ".join(signature_parts))
                    function_files[current_function] = path.relative_to(src_dir.parent).as_posix()
                    in_signature = False
                continue
            if in_signature:
                signature_parts.append(line)
                if "{" in line:
                    current_function = extract_function_name(" ".join(signature_parts))
                    function_files[current_function] = path.relative_to(src_dir.parent).as_posix()
                    in_signature = False
                continue
            if current_function is not None:
                if line.strip() == "}":
                    current_function = None
                    continue
                label = LABEL_RE.match(line)
                if label:
                    blocks[(current_function, label.group(1))] = SourceLocation(
                        path.relative_to(src_dir.parent).as_posix(), line_no
                    )
    return blocks, function_files


def is_comment_or_blank(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith(";")


def instrument_function(
    lines: list[str],
    function: str,
    linked_start_line: int,
    source_blocks: dict[tuple[str, str], SourceLocation],
    function_files: dict[str, str],
    next_block_id: int,
    next_branch_id: int,
) -> tuple[list[str], list[BlockRecord], list[BranchRecord], int, int]:
    label_indices: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = LABEL_RE.match(line)
        if match:
            label_indices.append((index, match.group(1)))

    if not label_indices:
        brace_index = next((i for i, line in enumerate(lines) if "{" in line), 0)
        insert_at = brace_index + 1
        while insert_at < len(lines) and is_comment_or_blank(lines[insert_at]):
            insert_at += 1
        label_indices = [(brace_index, "<entry>")]
    else:
        insert_at = -1

    insertions: dict[int, list[str]] = {}
    block_records: list[BlockRecord] = []
    branch_records: list[BranchRecord] = []

    for label_index, label in label_indices:
        if label == "<entry>":
            block_insert = insert_at
            source = function_files.get(function, "<linked>")
            source_line = linked_start_line + block_insert
        else:
            block_insert = label_index + 1
            while block_insert < len(lines):
                candidate = lines[block_insert]
                if is_comment_or_blank(candidate) or PHI_RE.match(candidate):
                    block_insert += 1
                    continue
                break
            location = source_blocks.get((function, label))
            source = location.path if location else function_files.get(function, "<linked>")
            source_line = location.line if location else linked_start_line + label_index
        insertions.setdefault(block_insert, []).append(
            f"  call void @weavec0_cov_hit(i32 {next_block_id})"
        )
        block_records.append(BlockRecord(next_block_id, function, label, source, source_line))
        next_block_id += 1

    labels_by_index = {index: label for index, label in label_indices}
    active_label = "<entry>"
    for index, line in enumerate(lines):
        if index in labels_by_index:
            active_label = labels_by_index[index]
        match = COND_BR_RE.match(line)
        if not match:
            continue
        cond = match.group("cond").strip()
        indent = match.group("indent") or "  "
        value_name = f"%weavec0_cov_branch_{next_branch_id}"
        insertions.setdefault(index, []).extend(
            [
                f"{indent}{value_name} = zext i1 {cond} to i32",
                f"{indent}call void @weavec0_cov_branch(i32 {next_branch_id}, i32 {value_name})",
            ]
        )
        location = source_blocks.get((function, active_label))
        source = location.path if location else function_files.get(function, "<linked>")
        source_line = location.line if location else linked_start_line + index
        branch_records.append(
            BranchRecord(next_branch_id, function, active_label, source, source_line)
        )
        next_branch_id += 1

    output: list[str] = []
    for index, line in enumerate(lines):
        output.extend(insertions.get(index, []))
        output.append(line)
    output.extend(insertions.get(len(lines), []))
    return output, block_records, branch_records, next_block_id, next_branch_id


def instrument_module(text: str, src_dir: Path) -> tuple[str, list[BlockRecord], list[BranchRecord]]:
    source_blocks, function_files = scan_source_locations(src_dir)
    lines = text.splitlines()
    output: list[str] = []
    blocks: list[BlockRecord] = []
    branches: list[BranchRecord] = []
    block_id = 0
    branch_id = 0
    declarations_added = False
    index = 0

    while index < len(lines):
        line = lines[index]
        if DEFINE_RE.match(line):
            if not declarations_added:
                output.extend(
                    [
                        "declare void @weavec0_cov_hit(i32)",
                        "declare void @weavec0_cov_branch(i32, i32)",
                        "",
                    ]
                )
                declarations_added = True
            function_start = index
            signature = [line]
            while "{" not in signature[-1]:
                index += 1
                signature.append(lines[index])
            function = extract_function_name(" ".join(signature))
            function_lines = list(signature)
            index += 1
            while index < len(lines):
                function_lines.append(lines[index])
                if lines[index].strip() == "}":
                    break
                index += 1
            instrumented, new_blocks, new_branches, block_id, branch_id = instrument_function(
                function_lines,
                function,
                function_start + 1,
                source_blocks,
                function_files,
                block_id,
                branch_id,
            )
            output.extend(instrumented)
            blocks.extend(new_blocks)
            branches.extend(new_branches)
        else:
            output.append(line)
        index += 1

    if not declarations_added:
        raise ValueError("input LLVM module contains no function definitions")
    return "\n".join(output) + "\n", blocks, branches


def write_map(path: Path, blocks: Iterable[BlockRecord], branches: Iterable[BranchRecord]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["kind", "id", "function", "label", "source", "line"])
        for item in blocks:
            writer.writerow(["block", item.ident, item.function, item.label, item.source, item.line])
        for item in branches:
            writer.writerow(["branch", item.ident, item.function, item.label, item.source, item.line])


def write_runtime(path: Path, block_count: int, branch_count: int) -> None:
    path.write_text(
        f'''/* SPDX-License-Identifier: Apache-2.0 */
#include <stdio.h>
#include <stdlib.h>

static unsigned long long block_counts[{max(block_count, 1)}];
static unsigned long long branch_counts[{max(branch_count, 1)}][2];

void weavec0_cov_hit(int id) {{
    if (id >= 0 && id < {block_count}) block_counts[id]++;
}}

void weavec0_cov_branch(int id, int outcome) {{
    if (id >= 0 && id < {branch_count}) branch_counts[id][outcome ? 1 : 0]++;
}}

__attribute__((destructor)) static void weavec0_cov_flush(void) {{
    const char *path = getenv("WEAVEC0_COVERAGE_OUT");
    if (!path || !*path) return;
    FILE *out = fopen(path, "a");
    if (!out) return;
    for (int i = 0; i < {block_count}; ++i) {{
        if (block_counts[i]) fprintf(out, "B\\t%d\\t%llu\\n", i, block_counts[i]);
    }}
    for (int i = 0; i < {branch_count}; ++i) {{
        if (branch_counts[i][0] || branch_counts[i][1]) {{
            fprintf(out, "R\\t%d\\t%llu\\t%llu\\n", i,
                    branch_counts[i][0], branch_counts[i][1]);
        }}
    }}
    fclose(out);
}}
''',
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--src-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--map", dest="map_path", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    args = parser.parse_args()

    text = args.input.read_text(encoding="utf-8")
    instrumented, blocks, branches = instrument_module(text, args.src_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(instrumented, encoding="utf-8")
    write_map(args.map_path, blocks, branches)
    write_runtime(args.runtime, len(blocks), len(branches))
    print(f"instrumented {len(blocks)} basic blocks and {len(branches)} conditional branches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
