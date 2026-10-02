"""Portable synthetic parser/JSON tests; these do not attest Darwin runtime code."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DYLD_KEYS = (
    "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH",
    "DYLD_FALLBACK_LIBRARY_PATH", "DYLD_FALLBACK_FRAMEWORK_PATH",
    "DYLD_VERSIONED_LIBRARY_PATH", "DYLD_VERSIONED_FRAMEWORK_PATH",
    "DYLD_ROOT_PATH", "DYLD_IMAGE_SUFFIX", "DYLD_SHARED_REGION",
    "DYLD_SHARED_CACHE_DIR", "DYLD_SHARED_CACHE_DONT_VALIDATE",
    "DYLD_FORCE_FLAT_NAMESPACE", "DYLD_BIND_AT_LAUNCH",
)


class RuntimeImageParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shlex.split(os.environ.get("CC", "cc"))
        if not compiler or not shutil.which(compiler[0]):
            raise unittest.SkipTest("C compiler is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="jonlib-runtime-image-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.exe = Path(cls.temp.name) / "parser"
        subprocess.run(compiler + [
            "-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
            "-I", str(ROOT / "tools/reference"),
            str(ROOT / "tests/runtime_image_parser_test.c"),
            str(ROOT / "tools/reference/runtime_image_macho.c"),
            str(ROOT / "tools/reference/runtime_image.c"), "-o", str(cls.exe),
        ], check=True, capture_output=True, text=True)

    def test_bounded_synthetic_parser(self):
        result = subprocess.run([str(self.exe)], check=True, capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), "Mach-O parser synthetic checks passed")

    def test_exact_loader_keys_values_and_json_escaping(self):
        env = {key: value for key, value in os.environ.items() if key not in DYLD_KEYS}
        # macOS may consume/strip DYLD_* at exec; this exact serialization test
        # uses Linux's portable writer rather than asserting launch behavior.
        if os.uname().sysname == "Darwin":
            self.skipTest("Darwin may consume DYLD environment at process launch")
        env["DYLD_INSERT_LIBRARIES"] = ""
        env["DYLD_FRAMEWORK_PATH"] = "résumé/日本語/🌻"
        env["DYLD_LIBRARY_PATH"] = 'path/with "quotes"\\slash\nand\ttab'
        result = subprocess.run([str(self.exe), "loader"], env=env,
                                check=True, capture_output=True, text=True)
        value = json.loads(result.stdout)
        self.assertEqual(set(value), set(DYLD_KEYS))
        self.assertEqual(value, {key: env.get(key) for key in DYLD_KEYS})

    def test_invalid_utf8_loader_value_fails_without_output(self):
        if os.uname().sysname == "Darwin":
            self.skipTest("Darwin may consume DYLD environment at process launch")
        env = {key: value for key, value in os.environ.items() if key not in DYLD_KEYS}
        env["DYLD_LIBRARY_PATH"] = os.fsdecode(b"bad-\xff")
        result = subprocess.run([str(self.exe), "loader"], env=env,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
