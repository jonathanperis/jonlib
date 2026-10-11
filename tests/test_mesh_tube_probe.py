import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import mesh_tube_probe as probe


class MeshTubeProbeTests(unittest.TestCase):
    def test_both_generators_have_the_same_cases(self):
        items = probe.cases()
        ids = [item['id'] for item in items]
        self.assertEqual(len(ids), len(set(ids)))
        cylinders = [item['id'][len('cylinder'):] for item in items if not item['cone']]
        cones = [item['id'][len('cone'):] for item in items if item['cone']]
        self.assertEqual(cylinders, cones)
        self.assertEqual({item['slices'] for item in items if item['contract'] is None}, set(probe.SLICES) | {6})

    def test_equal_and_unequal_sizes_and_zero_scales_are_compared(self):
        compared = [item for item in probe.cases() if item['contract'] is None]
        self.assertTrue(any(item['radius'] == item['height'] for item in compared))
        self.assertTrue(any(item['radius'] != item['height'] for item in compared))
        zero = probe.bits(0.0)
        self.assertTrue(any(item['radius'] == zero and item['height'] != zero for item in compared))
        self.assertTrue(any(item['radius'] != zero and item['height'] == zero for item in compared))
        self.assertTrue(any(item['radius'] == zero and item['height'] == zero for item in compared))

    def test_the_contracts_name_the_profiles_and_the_empty_mesh(self):
        contracts = [item for item in probe.cases() if item['contract'] is not None]
        self.assertEqual({item['profile'] for item in contracts}, {'host', 'fused', 'AppleLibm', 'Glibc241Libm'})
        empty = [item for item in contracts if item['slices'] < 3]
        self.assertEqual({item['contract'] for item in empty}, {'M0 0 811c9dc5 811c9dc5 811c9dc5'})
        self.assertEqual({item['contract'] for item in contracts if item['slices'] >= 3}, {'null'})

    def test_a_call_names_the_arithmetic_and_the_profile(self):
        items = {item['id']: item for item in probe.cases()}
        self.assertIn('J.Mesh.gen_cone_for(M.Fused{}, M.Glibc239Libm{}', probe.call(items['cone-fused'], 'Glibc239Libm'))
        self.assertIn('J.Mesh.gen_cylinder_for(M.Uncontracted{}, M.AppleLibm{}', probe.call(items['cylinder-apple'], 'Glibc239Libm'))
        self.assertIn(', 40)', probe.call(items['cylinder-40-1.0-2.0'], 'Glibc239Libm'))


if __name__ == '__main__':
    unittest.main()
