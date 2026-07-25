#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check documentation names and local Markdown links."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
DOC_NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\.md\Z")
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
REQUIRED = {"index.md", "architecture.md", "releasing.md"}
ROOT_DOCS = {"README.md", "CONTRIBUTING.md", "CHANGELOG.md"}


def markdown_files() -> list[Path]:
    files = [ROOT / name for name in sorted(ROOT_DOCS)]
    files.extend(sorted(DOCS.glob("*.md")))
    return [path for path in files if path.is_file()]


def local_target(source: Path, raw: str) -> Path | None:
    target = raw.strip().split(maxsplit=1)[0].strip("<>")
    if not target or target.startswith(("#", "http://", "https://", "mailto:")):
        return None
    target = unquote(target.split("#", 1)[0])
    if not target:
        return None
    return (source.parent / target).resolve()


def main() -> int:
    errors: list[str] = []
    docs = sorted(DOCS.glob("*.md"))
    names = {path.name for path in docs}

    for path in docs:
        if DOC_NAME.fullmatch(path.name) is None:
            errors.append(
                f"{path.relative_to(ROOT)}: documentation filenames must use "
                "lowercase kebab-case"
            )

    for name in sorted(REQUIRED - names):
        errors.append(f"docs/{name}: required documentation file is missing")

    root_resolved = ROOT.resolve()
    for source in markdown_files():
        text = source.read_text(encoding="utf-8")
        for raw in LINK.findall(text):
            target = local_target(source, raw)
            if target is None:
                continue
            try:
                target.relative_to(root_resolved)
            except ValueError:
                errors.append(
                    f"{source.relative_to(ROOT)}: local link escapes repository: {raw}"
                )
                continue
            if not target.exists():
                errors.append(
                    f"{source.relative_to(ROOT)}: broken local link: {raw}"
                )

    if errors:
        for error in errors:
            print(f"documentation audit: {error}", file=sys.stderr)
        return 1

    print(f"documentation audit: {len(docs)} docs files, all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
