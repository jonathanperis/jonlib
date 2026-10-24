import json
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import gltf_anim_probe


def document(data):
    size = struct.unpack('<I', data[12:16])[0]
    return json.loads(data[20:20 + size])


class GltfAnimCasesTests(unittest.TestCase):
    def cases(self, libm):
        return gltf_anim_probe.cases(Path('/work'), Path('/raylib'), libm)

    def test_the_examples_models_and_the_refusals_are_in_the_corpus(self):
        items, files = self.cases('Glibc239Libm')
        ids = [item['id'] for item in items]
        self.assertEqual(len(ids), len(set(ids)))
        for name in ('greenman', 'robot', 'greenman_hat', 'missing', 'linear', 'steps', 'constant', 'gentle', 'unsorted-bones', 'mixed-interpolation', 'root-joint-without-parent',
                     'between-joints', 'inverse-bind', 'inverse-bind-short'):
            self.assertIn(name, ids)
        self.assertEqual({item['id'] for item in items if item['contract']}, {'cubic-spline', 'short-output', 'integer-times', 'inverse-bind-integers'})
        self.assertEqual({Path(path).stem for path in files}, set(ids) - {'greenman', 'robot', 'greenman_hat', 'missing'})

    def test_another_profile_refuses_the_rotations_that_need_acosf(self):
        refused = {item['id'] for item in self.cases('AppleLibm')[0] if item['contract']}
        self.assertTrue({'robot', 'linear'} <= refused)
        self.assertNotIn('greenman', refused)
        self.assertFalse({'steps', 'gentle', 'constant'} & refused)

    def test_the_linear_case_turns_a_quarter_between_keys(self):
        items, files = self.cases('Glibc239Libm')
        data = next(data for path, data in files.items() if Path(path).stem == 'linear')
        parsed = document(data)
        animation = parsed['animations'][0]
        self.assertEqual([channel['target']['path'] for channel in animation['channels']], ['rotation', 'translation', 'scale'])
        self.assertEqual(parsed['skins'][0]['joints'], [1, 2])
        first, second = gltf_anim_probe.turn(0), gltf_anim_probe.turn(90)
        self.assertLess(sum(a * b for a, b in zip(first, second)), 0.95)
        gentle = sum(a * b for a, b in zip(gltf_anim_probe.turn(0), gltf_anim_probe.turn(10)))
        self.assertGreater(gentle, 0.95)

    def test_the_mixed_case_keeps_each_channels_interpolation(self):
        items, files = self.cases('Glibc239Libm')
        animation = document(next(data for path, data in files.items() if Path(path).stem == 'mixed-interpolation'))['animations'][0]
        bone = [channel['sampler'] for channel in animation['channels'] if channel['target']['node'] == 2]
        self.assertEqual([animation['samplers'][s].get('interpolation', 'LINEAR') for s in bone], ['STEP', 'LINEAR'])

    def test_the_between_case_has_a_joint_under_a_node_that_is_not_a_joint(self):
        items, files = self.cases('Glibc239Libm')
        parsed = document(next(data for path, data in files.items() if Path(path).stem == 'between-joints'))
        joints = parsed['skins'][0]['joints']
        parent = {child: index for index, node in enumerate(parsed['nodes']) for child in node.get('children', [])}
        self.assertNotIn(parent[joints[1]], joints)
        self.assertEqual(parent[parent[joints[1]]], joints[0])

    def test_the_inverse_bind_cases_cover_every_joint_and_fewer(self):
        items, files = self.cases('Glibc239Libm')
        for name, count, component in (('inverse-bind', 2, 5126), ('inverse-bind-short', 1, 5126), ('inverse-bind-integers', 2, 5121)):
            parsed = document(next(data for path, data in files.items() if Path(path).stem == name))
            accessor = parsed['accessors'][parsed['skins'][0]['inverseBindMatrices']]
            self.assertEqual((accessor['type'], accessor['count'], accessor['componentType']), ('MAT4', count, component), name)

    def test_the_rootless_case_has_a_first_joint_without_a_parent(self):
        items, files = self.cases('Glibc239Libm')
        parsed = document(next(data for path, data in files.items() if Path(path).stem == 'root-joint-without-parent'))
        joint = parsed['skins'][0]['joints'][0]
        self.assertFalse(any(joint in node.get('children', []) for node in parsed['nodes']))


if __name__ == '__main__':
    unittest.main()
