import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import verify_bend


class UnsafeVerdictTests(unittest.TestCase):
    def test_an_unsafe_file_may_fail_only_the_reliance_verdict(self):
        text = '@unsafe\ndef fill() -> U32:\n  0\n'
        output = ('SOME PROOFS FAIL\nError: 1 def relies on unsafe or foreign code:\n'
                  'defs that depend on @unsafe: fill\n')
        self.assertTrue(verify_bend.unsafe_verdict(text, output))

    def test_a_type_error_on_an_unsafe_file_is_not_that_verdict(self):
        text = '@unsafe\ndef fill() -> U32:\n  0\n'
        self.assertFalse(verify_bend.unsafe_verdict(text, 'SOME PROOFS FAIL\nError: duplicate declaration: fill\n'))

    def test_a_safe_file_does_not_accept_the_reliance_verdict(self):
        output = 'SOME PROOFS FAIL\nError: 1 def relies on unsafe or foreign code:\n'
        self.assertFalse(verify_bend.unsafe_verdict('def main() -> U32:\n  0\n', output))
