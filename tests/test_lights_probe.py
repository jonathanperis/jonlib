import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import lights_probe as lp


class LightsProbeTests(unittest.TestCase):
    def test_corpus_passes_max_lights(self):
        self.assertGreater(len(lp.LIGHTS), 4)
        self.assertEqual({kind for kind, _, _, _ in lp.LIGHTS}, {0, 1})

    def test_programs(self):
        self.assertEqual(lp.c_calls().count('CreateLight('), len(lp.LIGHTS))
        steps = lp.bend_steps()
        self.assertEqual(steps.count('step('), len(lp.LIGHTS))
        self.assertIn('L.Lights.new()', steps)


if __name__ == '__main__':
    unittest.main()
