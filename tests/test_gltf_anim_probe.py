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
        for name in ('greenman', 'robot', 'greenman_hat', 'missing', 'linear', 'steps', 'constant', 'gentle', 'unsorted-bones'):
            self.assertIn(name, ids)
        self.assertEqual({item['id'] for item in items if item['contract']}, {'cubic-spline', 'short-output', 'integer-times', 'root-joint-without-parent'})
        self.assertEqual({Path(path).stem for path in files}, set(ids) - {'greenman', 'robot', 'greenman_hat', 'missing'})

    def test_another_profile_refuses_the_rotations_that_need_acosf(self):
        refused = {item['id'] for item in self.cases('AppleLibm')[0] if item['contract']}
        self.assertTrue({'greenman', 'robot', 'linear'} <= refused)
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

    def test_the_rootless_case_has_a_first_joint_without_a_parent(self):
        items, files = self.cases('Glibc239Libm')
        parsed = document(next(data for path, data in files.items() if Path(path).stem == 'root-joint-without-parent'))
        joint = parsed['skins'][0]['joints'][0]
        self.assertFalse(any(joint in node.get('children', []) for node in parsed['nodes']))


if __name__ == '__main__':
    unittest.main()
