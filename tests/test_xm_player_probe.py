import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import xm_module_probe as xp
import xm_player_probe as pp
from vorbis_codebook_probe import Rng


class BuiltTests(unittest.TestCase):
    def setUp(self):
        self.built = pp.built()

    def test_every_module_loads(self):
        self.assertEqual(len(self.built), 16)
        for name, data in self.built.items():
            self.assertEqual(xp.model(data)[0], 'loaded', name)
        self.assertEqual(pp.built(), self.built)                                      # seeded
        self.assertEqual(sorted(name for name in self.built if name.startswith('tame')), ['tame-0', 'tame-1', 'tame-2', 'tame-3'])
        self.assertEqual(len([name for name in self.built if name.startswith('all')]), 6)

    def test_both_frequency_types_and_many_shapes(self):
        flags = {name: data[74] & 1 for name, data in self.built.items()}
        self.assertTrue(any(flags[name] for name in flags if name.startswith('tame')) and any(not flags[name] for name in flags if name.startswith('tame')))
        self.assertTrue(len({data[68] for data in self.built.values()}) >= 5)          # channels
        self.assertTrue(len({(data[76], data[78]) for data in self.built.values()}) >= 6)   # tempo and BPM

    def test_the_tame_effects_cannot_leave_a_pattern(self):
        # no position jump, pattern break or extended command (loops, delays, retriggers, finetune)
        self.assertFalse({11, 13, 14} & set(pp.TAME))
        self.assertTrue({11, 13, 14} <= set(pp.EVERYTHING))
        self.assertTrue(len(pp.TAME) >= 15)

    def test_the_seeded_slots(self):
        rng = Rng(7)
        packed = pp.soup(rng, 4, 3, pp.TAME)
        self.assertTrue(len(packed) >= 12)                                             # a byte a slot at least
        self.assertEqual(pp.soup(Rng(7), 4, 3, pp.TAME), packed)
        self.assertEqual(xp.model(xp.module([xp.pattern(4, packed)], channels=3))[0], 'loaded')

    def test_the_instruments(self):
        made = pp.instruments(Rng(3))
        self.assertEqual(len(made), 8)
        self.assertEqual(len(made[4]), 29)                                             # one without samples
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], made))[0], 'loaded')


class CasesTests(unittest.TestCase):
    def test_the_modules_and_their_calls(self):
        source = xp.module([xp.pattern(4)], channels=2)
        cases = pp.cases(source)
        self.assertEqual(len(cases), 3 + 16 + 1)
        self.assertEqual(cases['mini'], (source, [pp.OWN, pp.RESET, 400]))             # as raylib: the length, the reset, the song
        for name, (_, calls) in cases.items():
            self.assertTrue(calls and all(op > 0 or op in (pp.REMAINING, pp.RESET, pp.OWN) for op in calls), name)
            # jar_xm's own length only where no row can leave its pattern
            self.assertTrue(pp.OWN not in calls or name.startswith('mini') or name.startswith('tame'), name)
        self.assertIn(pp.REMAINING, cases['flow-length'][1])
        self.assertEqual(cases['flow-length'][0], cases['flow'][0])


class ProgramTests(unittest.TestCase):
    def test_the_reference_plays_each_module_in_its_own_process(self):
        self.assertIn('child = fork();', pp.NATIVE)
        self.assertIn('#define JARXM_MALLOC(sz) guarded(sz)', pp.NATIVE)
        self.assertIn('if (outside(ctx)) { printf("-1]\\n"); free(data); return; }', pp.NATIVE)
        self.assertIn('jar_xm_get_remaining_samples(ctx)', pp.NATIVE)
        self.assertIn('PROT_NONE', pp.NATIVE)
        self.assertEqual(pp.NATIVE.count('@RUNS@'), 1)
        self.assertNotIn('EVERY', pp.NATIVE + pp.PROGRAM)
        self.assertTrue(any('bounds' in flag for flag in pp.FLAGS))

    def test_the_candidate_hashes_what_the_reference_does(self):
        for name in ('mixed.pitch', 'mixed.slot', 'mixed.moving', 'mixed.level', 'mixed.memo', 'mixed.wobble', 'mixed.head', 'mixed.song'):
            self.assertIn(f'def {name}(', pp.PROGRAM)
        self.assertIn('Pl.player.new(M.LIBM{}, module, 48000, 24492)', pp.PROGRAM)


if __name__ == '__main__':
    unittest.main()
