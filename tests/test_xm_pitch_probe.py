import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import xm_pitch_probe as pp


def real(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


class ArgumentsTests(unittest.TestCase):
    def test_the_notes(self):
        notes = pp.notes()
        self.assertEqual((len(notes), pp.notes()), (197, notes))                       # seeded
        values = [real(word) for word in notes]
        # both sides of each end of the Amiga period's domain, NaNs and infinities
        self.assertTrue(any(-1.0 < value < 0.0 for value in values) and -1.0 in values and 407.0 in values and 408.0 in values)
        self.assertTrue(0x7FC00000 in notes and 0xFFC00000 in notes and 0x7F800000 in notes and 0xFF800000 in notes)
        self.assertTrue(sum(1 for value in values if 0.0 <= value <= 120.0) >= 40)       # a module's notes

    def test_the_linear_periods_are_inside_what_powf_is_given_for(self):
        pairs = pp.linear_pairs()
        self.assertEqual(len(pairs), 198)
        for period, offset in pairs:
            self.assertTrue(abs((4608.0 - (real(period) - 64.0 * real(offset))) / 768.0) < 126.0)
        self.assertTrue(sum(1 for _, offset in pairs if real(offset) == 0.0) >= 20)

    def test_the_amiga_periods(self):
        pairs = pp.amiga_pairs()
        self.assertEqual(len(pairs), 54 + 12 + 260)
        periods = [real(period) for period, _ in pairs]
        self.assertTrue(any(value < 0.0 for value in periods) and 0.0 in periods and 1795162112.0 in periods and any(value > 1795162112.0 for value in periods if value == value))
        self.assertTrue(sum(1 for _, offset in pairs if real(offset) == 0.0) >= 40)       # the plain division
        self.assertTrue(any(real(offset) != real(offset) for _, offset in pairs))        # an offset that is no number

    def test_the_waveforms(self):
        pairs = pp.wave_pairs()
        self.assertEqual({kind for kind, _ in pairs}, {0, 1, 2, 3, 4, 5, 9})
        self.assertTrue(all((kind, step) in pairs for kind in (0, 1, 2, 4) for step in range(64)))
        self.assertTrue(any(step > 63 for _, step in pairs))                             # a step past the 64 is taken modulo
        self.assertEqual(sum(1 for kind, _ in pairs if kind == 3), 42)                   # the random one's state moves each time

    def test_the_envelopes(self):
        rows = pp.envelope_rows()
        self.assertEqual((len(rows), {len(row) for row in rows}), (26, {30}))
        self.assertEqual(rows[0][24], 0)
        self.assertEqual(rows[3][:10], [0, 0, 4, 64, 10, 32, 20, 48, 30, 0])
        # the ones read past their points: a loop's or a sustain's point number past the 12th, with the flag that reads it
        past = [k for k, row in enumerate(rows) if (row[28] & 4 and (row[26] > 11 or row[27] > 11)) or (row[28] & 2 and row[29] and row[25] > 11)]
        self.assertEqual(past, [20, 21, 22, 25])
        self.assertTrue(any(row[28] & 2 and not row[29] and row[25] > 11 for row in rows))    # a sustain point that is not read


class ProgramTests(unittest.TestCase):
    def test_the_reference_traps_what_is_undefined(self):
        self.assertTrue(any(flag.startswith('-fsanitize-trap=') for flag in pp.FLAGS))
        for kind in ('float-cast-overflow', 'shift', 'signed-integer-overflow', 'bounds'):
            self.assertTrue(all(kind in flag for flag in pp.FLAGS if flag.startswith('-fsanitize')))
        self.assertIn('if (sigsetjmp(trapped, 1) == 0) { out = jar_xm_amiga_period(real(notes[i]));', pp.NATIVE)
        self.assertIn('jar_xm_envelope_tick(&ch, &env, &c, &v);', pp.NATIVE)
        self.assertIn('return x != x? 0x7FC00000u : w;', pp.NATIVE)
        self.assertNotIn('TICKS', pp.NATIVE + pp.PROGRAM)
        self.assertEqual(pp.NATIVE.count('@'), 10)                                       # five places to fill

    def test_the_candidate_prints_a_nan_as_one(self):
        self.assertIn('2143289344', pp.PROGRAM)
        self.assertIn('ticks(40n, True{}', pp.PROGRAM)


if __name__ == '__main__':
    unittest.main()
