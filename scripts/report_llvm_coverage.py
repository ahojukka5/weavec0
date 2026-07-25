#!/usr/bin/env python3
"""Aggregate and report weavec0 LLVM basic-block and branch coverage."""
from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def percentage(hit: int, total: int) -> float:
    return 100.0 if total == 0 else 100.0 * hit / total


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", dest="map_path", type=Path, required=True)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--json", dest="json_path", type=Path)
    parser.add_argument("--fail-under-functions", type=float, default=0.0)
    parser.add_argument("--fail-under-blocks", type=float, default=0.0)
    parser.add_argument("--fail-under-branch-outcomes", type=float, default=0.0)
    args = parser.parse_args()

    blocks: dict[int, dict[str, str]] = {}
    branches: dict[int, dict[str, str]] = {}
    with args.map_path.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            ident = int(row["id"])
            (blocks if row["kind"] == "block" else branches)[ident] = row

    block_counts: defaultdict[int, int] = defaultdict(int)
    branch_counts: defaultdict[int, list[int]] = defaultdict(lambda: [0, 0])
    if args.raw.exists():
        for line in args.raw.read_text(encoding="utf-8").splitlines():
            fields = line.split("\t")
            if not fields:
                continue
            if fields[0] == "B" and len(fields) == 3:
                block_counts[int(fields[1])] += int(fields[2])
            elif fields[0] == "R" and len(fields) == 4:
                counts = branch_counts[int(fields[1])]
                counts[0] += int(fields[2])
                counts[1] += int(fields[3])

    functions = sorted({row["function"] for row in blocks.values()})
    covered_functions = {
        row["function"] for ident, row in blocks.items() if block_counts[ident] > 0
    }
    covered_blocks = {ident for ident in blocks if block_counts[ident] > 0}
    covered_branch_outcomes = sum(
        int(branch_counts[ident][0] > 0) + int(branch_counts[ident][1] > 0)
        for ident in branches
    )
    total_branch_outcomes = 2 * len(branches)

    function_pct = percentage(len(covered_functions), len(functions))
    block_pct = percentage(len(covered_blocks), len(blocks))
    branch_pct = percentage(covered_branch_outcomes, total_branch_outcomes)

    print(f"functions: {len(covered_functions)}/{len(functions)} ({function_pct:.2f}%)")
    print(f"basic blocks: {len(covered_blocks)}/{len(blocks)} ({block_pct:.2f}%)")
    print(
        f"branch outcomes: {covered_branch_outcomes}/{total_branch_outcomes} "
        f"({branch_pct:.2f}%)"
    )

    uncovered_functions = sorted(set(functions) - covered_functions)
    uncovered_blocks = [blocks[ident] for ident in sorted(blocks) if ident not in covered_blocks]
    uncovered_outcomes: list[dict[str, str | int]] = []
    for ident in sorted(branches):
        counts = branch_counts[ident]
        for outcome, count in (("false", counts[0]), ("true", counts[1])):
            if count == 0:
                row = dict(branches[ident])
                row["outcome"] = outcome
                uncovered_outcomes.append(row)

    if uncovered_functions:
        print("\nuncovered functions:")
        for name in uncovered_functions:
            print(f"  {name}")
    if uncovered_blocks:
        print("\nuncovered basic blocks:")
        for row in uncovered_blocks:
            print(
                f"  {row['source']}:{row['line']} {row['function']}::{row['label']}"
            )
    if uncovered_outcomes:
        print("\nuncovered branch outcomes:")
        for row in uncovered_outcomes:
            print(
                f"  {row['source']}:{row['line']} {row['function']}::{row['label']} "
                f"outcome={row['outcome']}"
            )

    report = {
        "summary": {
            "functions": {
                "covered": len(covered_functions),
                "total": len(functions),
                "percent": function_pct,
            },
            "blocks": {
                "covered": len(covered_blocks),
                "total": len(blocks),
                "percent": block_pct,
            },
            "branch_outcomes": {
                "covered": covered_branch_outcomes,
                "total": total_branch_outcomes,
                "percent": branch_pct,
            },
        },
        "uncovered_functions": uncovered_functions,
        "uncovered_blocks": uncovered_blocks,
        "uncovered_branch_outcomes": uncovered_outcomes,
    }
    if args.json_path:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    failed = (
        function_pct < args.fail_under_functions
        or block_pct < args.fail_under_blocks
        or branch_pct < args.fail_under_branch_outcomes
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
