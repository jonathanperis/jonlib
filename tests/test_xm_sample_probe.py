import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import xm_sample_probe as sp


def real(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


class RunsTests(unittest.TestCase):
    def setUp(self):
        self.runs = sp.runs()

    def test_the_runs(self):
        self.assertEqual((len(self.runs), sp.runs()), (111, self.runs))                # seeded
        for head, kept, floats, ops in self.runs:
            self.assertEqual((len(head), len(kept)), (9, 16))
            self.assertTrue(head[4] in (0, 1) and head[5] in (0, 1))                   # jar_xm loads no other loop
            self.assertTrue(ops and all(op in (sp.FRAME, sp.NOTE, sp.UNSAMPLED, sp.SAMPLED) for op in ops))

    def test_what_the_samples_are(self):
        heads = [head for head, _, _, _ in self.runs]
        self.assertTrue(any(head[5] for head in heads) and any(head[4] for head in heads) and any(head[0] == 0 for head in heads))
        # loops that are not inside the data, and data shorter than the length says
        self.assertTrue(any(head[4] and head[3] > head[0] for head in heads) and any(head[4] and head[1] > head[3] for head in heads))
        self.assertTrue(any(len(floats) < head[0] for head, _, floats, _ in self.runs))
        self.assertTrue(any(head[5] and len(floats) == 2 * head[0] + 1 for head, _, floats, _ in self.runs))
        self.assertTrue(all(-1.0 <= real(word) < 1.0 for _, _, floats, _ in self.runs for word in floats))

    def test_the_positions_and_steps(self):
        positions = [real(head[6]) for head, _, _, _ in self.runs]
        steps = [real(head[7]) for head, _, _, _ in self.runs]
        self.assertTrue(any(value < 0.0 for value in positions) and any(value >= 4294967296.0 for value in positions) and any(value != value for value in positions))
        self.assertTrue(any(head[6] == 0x80000000 for head, _, _, _ in self.runs))        # minus zero is not below 0
        self.assertTrue(any(value < 0.0 for value in steps) and any(value != value for value in steps) and 0.0 in steps)
        self.assertTrue(any(head[8] >= 8 for head, _, _, _ in self.runs) and any(0 < head[8] < 8 for head, _, _, _ in self.runs))

    def test_the_scripts(self):
        varied = [ops for _, _, _, ops in self.runs if sp.NOTE in ops]
        self.assertTrue(len(varied) >= 40)
        self.assertTrue(all(sp.UNSAMPLED in ops and sp.SAMPLED in ops for ops in varied))
        self.assertTrue(all(ops.index(sp.UNSAMPLED) < ops.index(sp.SAMPLED) for ops in varied))


class ProgramTests(unittest.TestCase):
    def test_the_reference_faults_past_the_data(self):
        self.assertIn('PROT_NONE', sp.NATIVE)
        self.assertIn('data = (float *)(base + room) - count;', sp.NATIVE)
        self.assertIn('signal(SIGSEGV, on_trap);', sp.NATIVE)
        self.assertIn('jar_xm_next_of_sample(&ctx, &ch, -1); ch.frame_count++;', sp.NATIVE)
        self.assertIn('for (i = 0; i < jar_xm_SAMPLE_RAMPING_POINTS; i++) jar_xm_next_of_sample(&ctx, &ch, i); ch.frame_count = 0;', sp.NATIVE)
        self.assertTrue(any('float-cast-overflow' in flag for flag in sp.FLAGS))
        self.assertEqual(sp.NATIVE.count('@RUNS@'), 1)

    def test_the_candidate_follows_the_same_script(self):
        self.assertIn('case 0: framed.step(Sm.sample.next(sampled, tone, head, 4294967295))', sp.PROGRAM)
        self.assertIn('case 1: noted(8n, True{}, 0, sampled, tone, head)', sp.PROGRAM)


if __name__ == '__main__':
    unittest.main()
