import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import spectrum_probe as sp


class FramesTests(unittest.TestCase):
    def test_the_frames(self):
        items = sp.frames()
        self.assertEqual((len(items), len({name for name, _ in items})), (50, 11))
        self.assertTrue(all(len(samples) == 2048 and all(-32768 <= v <= 32767 for v in samples) for _, samples in items))
        # the history has 45 rows: the frames go round it
        self.assertGreater(len(items), 45)
        names = [name for name, _ in items]
        self.assertEqual((names[0], names[2], names[5], names.count('silence')), ('silence', 'tone', 'square', 35))
        self.assertEqual(sp.frames(), items)

    def test_a_tone_has_its_cycles(self):
        tone = dict(sp.frames())['tone']
        # 37 cycles over the 2048 samples: the pairs the example averages hold 37 cycles in 1024
        crossings = sum((a < 0) != (b < 0) for a, b in zip(tone, tone[1:]))
        self.assertIn(crossings, (73, 74))
        self.assertEqual(max(tone), 12000)

    def test_the_file(self):
        data = sp.packed([('a', [1, -2] + [0] * 2046), ('b', [32767] * 2048)])
        self.assertEqual((len(data), struct.unpack('<hh', data[:4]), struct.unpack('<h', data[4096:4098])), (8192, (1, -2), (32767,)))


class ProgramTests(unittest.TestCase):
    def test_the_reference_is_the_example_itself(self):
        for text in ('#define main example_main', '#include "audio_spectrum_visualizer.c"', 'CaptureFrame(&fft, audioSamples);', 'RenderFrame(&fft, &fftImage);',
                     'audioSamples[i] = (chunk[i*2] + chunk[i*2 + 1])*0.5f/32767.0f;', '.tapbackPos = 0.01f'):
            self.assertIn(text, sp.NATIVE)

    def test_the_candidate_is_the_port(self):
        for text in ('import ../../examples/audio_spectrum_visualizer.bend as Ex', 'Ex.capture(libm, tables, Ex.averaged(', 'Ex.render(fft, image)', 'Ex.tables.for(libm)', 'M.LIBM{}'):
            self.assertIn(text, sp.PROGRAM)


if __name__ == '__main__':
    unittest.main()
