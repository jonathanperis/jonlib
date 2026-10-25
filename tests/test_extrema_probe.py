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

    def test_the_candidate_uses_the_selected_profile(self):
        text = probe.render([('v2_min', (0, 0, 0, 0x80000000))], False, 'M.AppleLibm{}')
        self.assertIn('M.Vector2.min_for(M.AppleLibm{}, ', text)
        self.assertNotIn('Glibc239Libm', text)
