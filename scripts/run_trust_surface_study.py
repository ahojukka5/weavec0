#!/usr/bin/env python3
"""Run the frozen historical Stage 0 trusted-surface comparison."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

from trust_surface_metrics import measure

BROADER = "c720014d35d21ba0ed1a38c9645e566b37b4dfbe"
MINIMIZED = "a0aeb3919cdeec1e47a931fdfa7dc660a78567ff"


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    log_path: Path | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(completed.stdout, encoding="utf-8")
    if check and completed.returncode != 0:
        sys.stderr.write(completed.stdout)
        raise subprocess.CalledProcessError(completed.returncode, command, completed.stdout)
    return completed


def git_output(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), *args],
        text=True,
    ).strip()


def sha256_file(path: Path) -> str | None:
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_manifest(paths: list[Path], root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): sha256_file(path) or ""
        for path in sorted(paths)
        if path.is_file()
    }


def worktree_add(repo: Path, destination: Path, revision: str) -> None:
    run(["git", "-C", str(repo), "worktree", "add", "--detach", str(destination), revision])


def worktree_remove(repo: Path, destination: Path) -> None:
    if destination.exists():
        run(
            ["git", "-C", str(repo), "worktree", "remove", "--force", str(destination)],
            check=False,
        )


def pinned_stage1(repo: Path, revision: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), "show", f"{revision}:WEAVEC1_BOOTSTRAP_COMMIT"],
        text=True,
    ).strip()


def make_source_fallback_path(work_root: Path) -> Path:
    tools = work_root / "forced-source-tools"
    tools.mkdir(parents=True, exist_ok=True)
    uname = tools / "uname"
    uname.write_text(
        "#!/usr/bin/env bash\n"
        "case \"${1:-}\" in\n"
        "  -s) printf 'ResearchHost\\n' ;;\n"
        "  -m) printf 'x86_64\\n' ;;\n"
        "  *) printf 'ResearchHost\\n' ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    uname.chmod(uname.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return tools


def stage1_record(stage1_root: Path, build_result: subprocess.CompletedProcess[str]) -> dict[str, object]:
    src_ll = list((stage1_root / "build" / "src-ll").glob("*.ll"))
    selfhost_src_ll = list((stage1_root / "build" / "src2-ll").glob("*.ll"))
    test_ll = list((stage1_root / "build" / "test-ll").glob("*.ll"))
    return {
        "exit_code": build_result.returncode,
        "success": build_result.returncode == 0,
        "weavec1_sha256": sha256_file(stage1_root / "build" / "weavec1"),
        "weavec1_selfhost_sha256": sha256_file(stage1_root / "build" / "weavec1-selfhost"),
        "source_llvm": tree_manifest(src_ll, stage1_root),
        "selfhost_source_llvm": tree_manifest(selfhost_src_ll, stage1_root),
        "test_llvm": tree_manifest(test_ll, stage1_root),
    }


def compare_stage1(a: dict[str, object], b: dict[str, object]) -> dict[str, object]:
    return {
        "both_builds_succeeded": bool(a["success"] and b["success"]),
        "weavec1_binary_equal": a["weavec1_sha256"] is not None
        and a["weavec1_sha256"] == b["weavec1_sha256"],
        "weavec1_selfhost_binary_equal": a["weavec1_selfhost_sha256"] is not None
        and a["weavec1_selfhost_sha256"] == b["weavec1_selfhost_sha256"],
        "source_llvm_equal": a["source_llvm"] == b["source_llvm"],
        "selfhost_source_llvm_equal": a["selfhost_source_llvm"] == b["selfhost_source_llvm"],
        "test_llvm_equal": a["test_llvm"] == b["test_llvm"],
    }


def numeric_delta(before: object, after: object) -> dict[str, object]:
    before_value = int(before)
    after_value = int(after)
    delta = after_value - before_value
    fraction = None if before_value == 0 else delta / before_value
    return {
        "broader": before_value,
        "minimized": after_value,
        "delta": delta,
        "fractional_change": fraction,
    }


def metric_deltas(broader: dict[str, object], minimized: dict[str, object]) -> dict[str, object]:
    broad_llvm = broader["llvm_source"]
    min_llvm = minimized["llvm_source"]
    broad_wir = broader["wir_surface"]
    min_wir = minimized["wir_surface"]
    broad_runtime = broader["runtime"]
    min_runtime = minimized["runtime"]
    broad_build = broader["build"]
    min_build = minimized["build"]
    return {
        "llvm_source_bytes": numeric_delta(broad_llvm["source_bytes"], min_llvm["source_bytes"]),
        "llvm_noncomment_loc": numeric_delta(broad_llvm["noncomment_loc"], min_llvm["noncomment_loc"]),
        "llvm_function_count": numeric_delta(broad_llvm["function_count"], min_llvm["function_count"]),
        "llvm_basic_block_count": numeric_delta(broad_llvm["basic_block_count"], min_llvm["basic_block_count"]),
        "wir_keyword_count": numeric_delta(broad_wir["keyword_count"], min_wir["keyword_count"]),
        "runtime_source_bytes": numeric_delta(
            broad_runtime["source"]["bytes"], min_runtime["source"]["bytes"]
        ),
        "runtime_abi_function_count": numeric_delta(
            broad_runtime["abi_function_count"], min_runtime["abi_function_count"]
        ),
        "compiler_binary_bytes": numeric_delta(
            broad_build["compiler_binary"]["bytes"], min_build["compiler_binary"]["bytes"]
        ),
        "removed_wir_keywords": sorted(
            set(broad_wir["keywords"]) - set(min_wir["keywords"])
        ),
        "added_wir_keywords": sorted(
            set(min_wir["keywords"]) - set(broad_wir["keywords"])
        ),
        "runtime_source_unchanged": broad_runtime["source"]["sha256"]
        == min_runtime["source"]["sha256"],
        "runtime_header_unchanged": broad_runtime["header"]["sha256"]
        == min_runtime["header"]["sha256"],
        "required_host_tools_unchanged": broad_build["required_tools"]
        == min_build["required_tools"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--weavec1-repo", type=Path, required=True)
    parser.add_argument("--broader", default=BROADER)
    parser.add_argument("--minimized", default=MINIMIZED)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/trust-surface-study/result.json"),
    )
    parser.add_argument("--keep-worktrees", action="store_true")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    weavec1_repo = args.weavec1_repo.resolve()
    if not (weavec1_repo / ".git").exists():
        raise SystemExit(f"weavec1 repository is not a git checkout: {weavec1_repo}")

    broad_pin = pinned_stage1(repo, args.broader)
    minimized_pin = pinned_stage1(repo, args.minimized)
    if broad_pin != minimized_pin:
        raise SystemExit(
            "frozen Stage 0 revisions pin different Stage 1 commits: "
            f"{broad_pin} != {minimized_pin}"
        )

    try:
        git_output(weavec1_repo, "cat-file", "-e", f"{broad_pin}^{{commit}}")
    except subprocess.CalledProcessError as exc:
        raise SystemExit(
            f"weavec1 checkout does not contain pinned commit {broad_pin}; fetch it first"
        ) from exc

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    work_root = Path(tempfile.mkdtemp(prefix="weavec0-trust-surface-"))
    tools = make_source_fallback_path(work_root)

    arms = {
        "broader": args.broader,
        "minimized": args.minimized,
    }
    records: dict[str, dict[str, object]] = {}
    created: list[tuple[Path, Path]] = []

    try:
        for label, revision in arms.items():
            stage0 = work_root / f"weavec0-{label}"
            stage1 = work_root / f"weavec1-{label}"
            worktree_add(repo, stage0, revision)
            created.append((repo, stage0))
            worktree_add(weavec1_repo, stage1, broad_pin)
            created.append((weavec1_repo, stage1))

            stage0_log = output.parent / f"{label}-stage0-build.log"
            run(["bash", "build.sh"], cwd=stage0, log_path=stage0_log)
            metrics = measure(stage0, stage0 / "weavec0")

            env = os.environ.copy()
            env["PATH"] = f"{tools}{os.pathsep}{env.get('PATH', '')}"
            env["WEAVEC0"] = str(stage0)
            stage1_log = output.parent / f"{label}-stage1-build.log"
            stage1_build = run(
                ["bash", "build.sh"],
                cwd=stage1,
                env=env,
                log_path=stage1_log,
                check=False,
            )
            stage1_result = stage1_record(stage1, stage1_build)
            records[label] = {
                "stage0_revision": revision,
                "stage0": metrics,
                "stage1": stage1_result,
            }

        broader = records["broader"]["stage0"]
        minimized = records["minimized"]["stage0"]
        result = {
            "schema": "weavec0-trust-surface-study-v1",
            "protocol": {
                "broader_revision": args.broader,
                "minimized_revision": args.minimized,
                "pinned_weavec1_commit": broad_pin,
                "stage1_source_fallback_forced": True,
                "stage1_source_fallback_method": (
                    "PATH-local uname reports an unsupported host so the historical "
                    "build uses its documented WEAVEC0 source-tree fallback"
                ),
            },
            "arms": records,
            "surface_deltas": metric_deltas(broader, minimized),
            "stage1_comparison": compare_stage1(
                records["broader"]["stage1"], records["minimized"]["stage1"]
            ),
        }
        output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result["surface_deltas"], indent=2, sort_keys=True))
        print(json.dumps(result["stage1_comparison"], indent=2, sort_keys=True))

        return 0 if result["stage1_comparison"]["both_builds_succeeded"] else 1
    finally:
        if args.keep_worktrees:
            print(f"kept worktrees under {work_root}", file=sys.stderr)
        else:
            for owner, path in reversed(created):
                worktree_remove(owner, path)
            shutil.rmtree(work_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
