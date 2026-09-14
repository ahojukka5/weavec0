#!/usr/bin/env python3
"""Unit tests for the trust-surface metric extractor."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from trust_surface_metrics import measure


class TrustSurfaceMetricsTests(unittest.TestCase):
    def test_measure_synthetic_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "src").mkdir()
            (root / "src/00_prelude.ll").write_text(
                "; TOKEN_EOF = 0\n"
                "; TOKEN_FOO = 1\n"
                "; TOKEN_RESERVED_2 = 2\n"
                "define i32 @main() {\n"
                "entry:\n"
                "  br label %done\n"
                "done:\n"
                "  ret i32 0\n"
                "}\n",
                encoding="utf-8",
            )
            (root / "src/01_runtime_bindings.ll").write_text(
                "define i32 @helper() {\n"
                "entry:\n"
                "  ret i32 1\n"
                "}\n",
                encoding="utf-8",
            )
            (root / "runtime.c").write_text("int runtime_value = 1;\n", encoding="utf-8")
            (root / "runtime.h").write_text(
                "void weave_rt_one(void);\nint weave_rt_two(int x);\n",
                encoding="utf-8",
            )
            (root / "build.sh").write_text(
                "require_tool llvm-as\nrequire_tool clang\nrequire_tool llvm-as\n",
                encoding="utf-8",
            )
            (root / "WEAVEC1_BOOTSTRAP_COMMIT").write_text("abc123\n", encoding="utf-8")
            binary = root / "weavec0"
            binary.write_bytes(b"0123456789")

            report = measure(root, binary)

            self.assertEqual(report["pinned_weavec1_commit"], "abc123")
            self.assertEqual(report["wir_surface"]["keywords"], ["foo"])
            self.assertEqual(report["wir_surface"]["keyword_count"], 1)
            self.assertEqual(report["llvm_source"]["function_count"], 2)
            self.assertEqual(report["llvm_source"]["basic_block_count"], 3)
            self.assertEqual(report["runtime"]["abi_function_count"], 2)
            self.assertEqual(
                report["runtime"]["abi_functions"],
                ["weave_rt_one", "weave_rt_two"],
            )
            self.assertEqual(report["build"]["required_tools"], ["clang", "llvm-as"])
            self.assertEqual(report["build"]["compiler_binary"]["bytes"], 10)


if __name__ == "__main__":
    unittest.main()
