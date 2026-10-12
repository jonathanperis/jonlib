import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vr_probe as vp


class VrCasesTests(unittest.TestCase):
    def test_the_example_device_and_the_refusals_are_in_the_corpus(self):
        items = vp.cases()
        ids = [item['id'] for item in items]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual((len(items), sum(not item['contract'] for item in items), ids[0]), (50, 40, 'example'))
        self.assertEqual(items[0]['device'], vp.EXAMPLE)
        self.assertEqual({item['id'] for item in items if item['contract']},
                         {'zero-height-resolution', 'zero-width-resolution', 'zero-screen-width', 'zero-screen-height', 'zero-distortion-scale', 'nan-width', 'nan-distortion',
                          'infinite-ipd', 'infinite-eye', 'nan-eye'})
        self.assertEqual(vp.cases(), items)     # the seeded devices do not change between runs

    def test_a_device_is_fifteen_words_in_struct_order(self):
        words = vp.fields(dict(vp.EXAMPLE, h=-2160))
        self.assertEqual((len(words), words[0], words[1]), (15, 0xFFFFF790, 1200))
        self.assertEqual(words[2:7], [vp.bits(v) for v in (0.133793, 0.0669, 0.041, 0.07, 0.07)])
        self.assertEqual(words[7:], [vp.bits(v) for v in (1.0, 0.22, 0.24, 0.0, 0.996, -0.004, 1.014, 0.0)])
        self.assertEqual(vp.fields(dict(vp.EXAMPLE, width=math.inf))[2], 0x7F800000)

    def test_the_program_asks_the_profile_for_each_device(self):
        text = vp.render_for('Glibc239Libm')([(0, vp.cases()[0]), (1, vp.cases()[1])], False)
        self.assertEqual(text.count('J.Vr.load_stereo_config_for(M.Glibc239Libm{}, device(['), 2)
        self.assertIn('def at(xs: +List<U32>, +i: U32) -> U32:', text)
        self.assertLess(text.index('def at('), text.index('def device('))
        self.assertIn('device([2160, 1200, ', text)
        self.assertIn('M.AppleLibm{}', vp.render_for('AppleLibm')([(0, vp.cases()[0])], False))


if __name__ == '__main__':
    unittest.main()
