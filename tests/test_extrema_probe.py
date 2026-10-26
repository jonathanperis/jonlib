"""The extrema gate selects the profile its volatile fminf/fmaxf control implements."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import extrema_probe as probe
import native_profiles


class ExtremaTieTests(unittest.TestCase):
    def test_each_declared_table_selects_itself(self):
        for name in native_profiles.EXTREMA_PROFILES:
            self.assertEqual(probe.selected_profile(probe.tie_words(name)), name)

    def test_a_mixed_table_matches_no_declared_profile(self):
        words = probe.tie_words('AppleLibm')
        words[5] ^= 0x80000000
        with self.assertRaisesRegex(probe.ProbeFailure, 'no declared profile'):
            probe.selected_profile(words)

    def test_corpus_rows_select_the_profile_they_implement(self):
        bits = native_profiles.CONTROL_BITS
        for name in native_profiles.EXTREMA_PROFILES:
            words = probe.tie_words(name)
            rows, expected, cursor = [], [], 0
            for op, function in (('v2_min', 'min'), ('v2_max', 'max')):
                table = native_profiles.TABLES[name][function]
                for i, left in enumerate(bits):
                    for j, right in enumerate(bits):
                        rows.append((op, (left, 0x3f800000, right, 0x3f800000)))
                        expected.append([bits[table[i][j]], 0x3f800000])
                        self.assertEqual(words[cursor], bits[table[i][j]])
                        cursor += 1
            self.assertEqual(probe.profile_from_corpus(rows, expected), name)

    def test_a_second_operand_tie_matches_no_declared_profile(self):
        zeros = {0x00000000, 0x80000000}
        rows, expected = [], []
        for op in ('v2_min', 'v2_max'):
            for left in zeros:
                for right in zeros:
                    rows.append((op, (left, 0x3f800000, right, 0x3f800000)))
                    expected.append([right, 0x3f800000])
        with self.assertRaisesRegex(probe.ProbeFailure, 'no declared profile'):
            probe.profile_from_corpus(rows, expected)

    def test_the_candidate_uses_the_selected_profile(self):
        text = probe.render([('v2_min', (0, 0, 0, 0x80000000))], False, 'M.AppleLibm{}')
        self.assertIn('M.Vector2.min_for(M.AppleLibm{}, ', text)
        self.assertNotIn('Glibc239Libm', text)
