import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import model_pose_probe as probe


class ModelPoseProbeTests(unittest.TestCase):
    def cases(self, libm):
        return probe.cases(Path('/work'), Path('/raylib'), libm)[0]

    def test_every_case_is_compared_under_the_glibc_profile(self):
        items = self.cases('Glibc239Libm')
        ids = [item['id'] for item in items]
        self.assertEqual(len(ids), len(set(ids)))
        for name in ('greenman', 'linear', 'steps', 'unsorted-bones', 'boneless', 'more-bones', *probe.LIBM_FREE):
            self.assertIn(name, ids)
        self.assertEqual([item['id'] for item in items if item['contract']], ['undefined-calls'])

    def test_another_profile_compares_only_the_cases_without_acosf(self):
        items = self.cases('AppleLibm')
        self.assertEqual({item['id'] for item in items if not item['contract']}, set(probe.LIBM_FREE))
        self.assertEqual([item['id'] for item in items if item['contract']], ['undefined-calls'])

    def test_the_boneless_and_the_larger_animation_cases_mix_two_files(self):
        items = {item['id']: item for item in self.cases('Glibc239Libm')}
        self.assertTrue(items['boneless']['model'].endswith('greenman_hat.glb'))
        self.assertTrue(items['boneless']['animations'].endswith('gentle.glb'))
        self.assertTrue(items['more-bones']['model'].endswith('linear.glb'))
        self.assertTrue(items['more-bones']['animations'].endswith('greenman.glb'))
        self.assertTrue(items['undefined-calls']['animations'].endswith('greenman.glb'))

    def test_both_sequences_make_the_same_calls(self):
        native, candidate = probe.c_ops().splitlines(), probe.bend_ops().splitlines()
        self.assertEqual(len(native), len(probe.OPS))
        self.assertEqual(len(candidate), len(probe.OPS) + 1)
        self.assertIn('flagged(s14, skeleton, pick(items, 0, count))', candidate[-1])
        for op, c_line, bend_line in zip(probe.OPS, native, candidate):
            self.assertEqual('UpdateModelAnimationEx(' in c_line, op[0] == 'x')
            self.assertEqual(' x(' in bend_line, op[0] == 'x')
        self.assertEqual(probe.OPS[probe.UNCHANGED][-1], '1.5')
        self.assertIn('-(float)a[0%count].keyframeCount', probe.c_ops())
        self.assertIn('F32.neg(frames(pick(items, 0, count)))', probe.bend_ops())

    def test_the_loaded_entry_hashes_zeroed_transforms_and_identities(self):
        self.assertEqual(probe.loaded(0), '811c9dc5:811c9dc5')
        self.assertEqual(len(probe.loaded(2)), 17)
        self.assertNotEqual(probe.loaded(1), probe.loaded(2))

    def test_the_reference_rows_are_checked(self):
        entry = probe.loaded(2)
        good = ' '.join(['p2', entry] + [f'{index:08x}:00000000' for index in range(probe.UNCHANGED)] + ['bbbbbbbb:00000000'] + ['aaaaaaaa:00000000'] * 3 + ['v1'])
        with self.assertRaises(probe.ProbeFailure):
            probe.check_reference({'linear': good}, 'AppleLibm')
        fixed = good.split()
        fixed[2 + probe.UNCHANGED] = fixed[1 + probe.UNCHANGED]
        probe.check_reference({'linear': ' '.join(fixed)}, 'AppleLibm')
        with self.assertRaises(probe.ProbeFailure):
            probe.check_reference({'more-bones': ' '.join(fixed)}, 'AppleLibm')
        with self.assertRaises(probe.ProbeFailure):
            probe.check_reference({'no-animations': ' '.join(fixed)}, 'AppleLibm')


if __name__ == '__main__':
    unittest.main()
