import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import easings_probe as ep


class EasingsProbeTests(unittest.TestCase):
    def test_names(self):
        self.assertEqual(len(ep.NAMES), 28)
        self.assertEqual(ep.bend_name('LinearNone'), 'Ease.linear_none')
        self.assertEqual(ep.bend_name('SineInOut'), 'Ease.sine_in_out_for')
        self.assertEqual(ep.bend_name('BounceOut'), 'Ease.bounce_out')
        source = (ROOT / 'joneasings.bend').read_text()
        for name in ep.NAMES:
            self.assertIn(f'def {ep.bend_name(name)}(', source)

    def test_refusals(self):
        # glibc profiles verify every finite normal argument and powf(2, y) below 126 in magnitude.
        self.assertTrue(ep.accepted('Glibc239Libm', 'SineIn', 0.5, 0.0, 1.0, 1.0))
        self.assertTrue(ep.accepted('Glibc239Libm', 'ExpoIn', 0.0, 0.0, 1.0, 0.001))
        self.assertFalse(ep.accepted('Glibc239Libm', 'ExpoIn', -1.0, 0.0, 1.0, 0.001))
        self.assertTrue(ep.accepted('Glibc239Libm', 'ElasticOut', 1.0, 0.0, 1.0, 1.0))
        self.assertFalse(ep.accepted('AppleLibm', 'ExpoOut', 0.5, 0.0, 1.0, 1.0))
        self.assertTrue(ep.accepted('AppleLibm', 'BounceOut', 0.5, 0.0, 1.0, 1.0))

    def test_corpus(self):
        items = ep.corpus()
        self.assertGreater(len(items), 300)
        self.assertEqual(items, ep.corpus())
        self.assertIn((ep.f32(2.5 / 2.75), 0.0, 1.0, 1.0), items)


if __name__ == '__main__':
    unittest.main()
