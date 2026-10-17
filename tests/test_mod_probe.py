import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import mod_probe as mp


class ModProbeTests(unittest.TestCase):
    def test_note_bytes(self):
        # sample 0x1F, period 428, effect 0xC40: sample's high nibble and period's high bits share byte 0
        self.assertEqual(mp.note(0x1F, 428, 0xC40), bytes([0x11, 0xAC, 0xFC, 0x40]))

    def test_module_layout(self):
        sample = dict(data=[0] * 64, finetune=0, volume=64, reppnt=0, replen=2)
        data = mp.module([sample], [mp.empty_pattern(4)], [0])
        self.assertEqual(data[1080:1084], b'M.K.')
        self.assertEqual(len(data), 1084 + 1024 + 64)
        self.assertEqual(data[950], 1)
        fifteen = mp.module([sample], [mp.empty_pattern(4)], [0], fifteen=True)
        self.assertEqual(len(fifteen), 600 + 1024 + 64)
        self.assertEqual(fifteen[470], 1)

    def test_one_break_a_row(self):
        for name, data, contract in mp.cases():
            if contract is not None or not name.startswith('song-'):
                continue
            channels = {b'M.K.': 4, b'6CHN': 6, b'8CHN': 8}[data[1080:1084]]
            for p in range(data[950]):
                for row in range(64):
                    at = 1084 + (p * 64 + row) * channels * 4
                    breaks = [c for c in range(channels) if data[at + c * 4 + 2] & 15 == 0xD]
                    self.assertLessEqual(len(breaks), 1, (name, p, row))

    def test_cases(self):
        names = [name for name, _, _ in mp.cases()]
        self.assertEqual(len(names), len(set(names)))
        self.assertIn('jump-back', names)


if __name__ == '__main__':
    unittest.main()
