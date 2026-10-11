import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import iqm_probe


def header(data):
    return dict(zip(iqm_probe.FIELDS, struct.unpack_from('<27I', data, 16)))


def foreign(data):
    """An empty file, another magic or another version: the loaders return before reading on."""
    return not data or (len(data) >= 16 and data[:16] != b'INTERQUAKEMODEL\x00') or (len(data) >= 20 and data[:16] == b'INTERQUAKEMODEL\x00' and struct.unpack_from('<I', data, 16)[0] != 2)


def inside(data, offset, size):
    return offset + size <= len(data)


def terminated(data, offset):
    return inside(data, offset, 32) and 0 in data[offset:offset + 32]


def model_reads_inside(data):
    """Whether LoadIQM reads only the file and its own arrays (and prints only terminated names)."""
    if len(data) < 124:
        return False
    h = header(data)
    if not (inside(data, h['ofs_meshes'], 24 * h['num_meshes']) and inside(data, h['ofs_triangles'], 12 * h['num_triangles'])
            and inside(data, h['ofs_vertexarrays'], 20 * h['num_vertexarrays']) and inside(data, h['ofs_joints'], 48 * h['num_joints'])):
        return False
    read = False
    for index in range(h['num_vertexarrays']):
        kind, _, _, _, offset = struct.unpack_from('<5I', data, h['ofs_vertexarrays'] + 20 * index)
        per = {iqm_probe.POSITION: 12, iqm_probe.NORMAL: 12, iqm_probe.TEXCOORD: 8, iqm_probe.BLENDINDEXES: 4, iqm_probe.BLENDWEIGHTS: 4, iqm_probe.COLOR: 4}.get(kind)
        if per is not None:
            read = True
            if not inside(data, offset, per * h['num_vertexes']):
                return False
    for index in range(h['num_meshes']):
        name, material, first, count, from_triangle, triangles = struct.unpack_from('<6I', data, h['ofs_meshes'] + 24 * index)
        if not (inside(data, h['ofs_text'] + name, 32) and terminated(data, h['ofs_text'] + material) and from_triangle + triangles <= h['num_triangles']):
            return False
        if read and first + count > h['num_vertexes']:
            return False
    return all(terminated(data, h['ofs_text'] + struct.unpack_from('<I', data, h['ofs_joints'] + 48 * index)[0]) for index in range(h['num_joints']))


def animations_read_inside(data):
    """Whether LoadModelAnimationsIQM reads only the file, its frame data and its poses."""
    if len(data) < 124:
        return False
    h = header(data)
    values = h['num_frames'] * h['num_framechannels']
    if not (inside(data, h['ofs_poses'], 88 * h['num_poses']) and inside(data, h['ofs_anims'], 20 * h['num_anims']) and inside(data, h['ofs_frames'], 2 * values)
            and inside(data, h['ofs_joints'], 48 * h['num_joints'])):
        return False
    poses = [struct.unpack_from('<iI', data, h['ofs_poses'] + 88 * index) for index in range(h['num_poses'])]
    masked = sum(bin(mask & 0x3FF).count('1') for _, mask in poses)
    for index in range(h['num_anims']):
        name, first, frames, _, _ = struct.unpack_from('<IIIfI', data, h['ofs_anims'] + 20 * index)
        if not terminated(data, h['ofs_text'] + name):
            return False
        if frames and masked and first * h['num_framechannels'] + frames * masked > values:
            return False
        if frames and any(parent >= len(poses) for parent, _ in poses):
            return False
    return True


# Loads the reference defines and Jonlib leaves out of its profile.
PROFILE = {'model': {'over-2-mib', 'empty-material', 'material-from-root', 'no-vertices', 'no-triangles'}, 'anims': {'over-2-mib'}}


class IqmCasesTests(unittest.TestCase):
    def setUp(self):
        self.items, self.files = iqm_probe.cases(Path('/work'), Path('/raylib'))
        self.data = {Path(path).stem: data for path, data in self.files.items() if Path(path).suffix.lower() == '.iqm'}

    def test_the_examples_files_and_the_texture_are_in_the_corpus(self):
        ids = [item['id'] for item in self.items]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual([item['path'] for item in self.items[:2]], ['/raylib/examples/models/resources/models/iqm/guy.iqm', '/raylib/examples/models/resources/models/iqm/guyanim.iqm'])
        self.assertIn(Path('/work/skin.png'), self.files)
        self.assertEqual(set(self.data), set(ids) - {'guy', 'guyanim', 'missing'})
        self.assertEqual((len(ids), sum(item['model'] + item['anims'] for item in self.items), sum((not item['model']) + (not item['anims']) for item in self.items)), (46, 62, 30))

    def test_a_built_file_has_the_header_the_loaders_read(self):
        data = self.data['animated-model']
        h = header(data)
        self.assertEqual((data[:16], h['version'], h['filesize']), (b'INTERQUAKEMODEL\x00', 2, len(data)))
        self.assertEqual((h['num_meshes'], h['num_vertexes'], h['num_triangles'], h['num_vertexarrays'], h['num_joints'], h['num_poses'], h['num_anims'], h['num_frames'], h['num_framechannels']),
                         (1, 3, 1, 3, 7, 6, 1, 4, iqm_probe.PER_FRAME))
        self.assertEqual(iqm_probe.PER_FRAME, 23)
        text = data[h['ofs_text']:h['ofs_text'] + h['num_text']]
        name, material = struct.unpack_from('<2I', data, h['ofs_meshes'])
        self.assertEqual((text[name:].split(b'\x00')[0], text[material:].split(b'\x00')[0]), (b'mesh', b'none'))

    def test_every_compared_load_stays_inside_what_the_loader_owns(self):
        for item in self.items:
            data = self.data.get(item['id'])
            if data is None or foreign(data):
                continue
            if item['model']:
                self.assertTrue(model_reads_inside(data), item['id'])
            if item['anims']:
                self.assertTrue(animations_read_inside(data), item['id'])

    def test_every_refused_load_reads_outside_or_is_out_of_the_profile(self):
        for item in self.items:
            data = self.data.get(item['id'])
            if data is None:
                continue
            if not item['model'] and item['id'] not in PROFILE['model']:
                self.assertFalse(model_reads_inside(data), item['id'])
            if not item['anims'] and item['id'] not in PROFILE['anims']:
                self.assertFalse(animations_read_inside(data), item['id'])

    def test_the_profile_cases_are_what_they_say(self):
        self.assertGreater(len(self.data['over-2-mib']), 2 * 1024 * 1024)
        for name in ('empty-material', 'material-from-root', 'no-vertices', 'no-triangles'):
            self.assertTrue(model_reads_inside(self.data[name]), name)
        h = header(self.data['no-vertices'])
        self.assertEqual(struct.unpack_from('<6I', self.data['no-vertices'], h['ofs_meshes'])[3], 0)
        self.assertEqual(struct.unpack_from('<6I', self.data['no-triangles'], header(self.data['no-triangles'])['ofs_meshes'])[5], 0)

    def test_the_animated_poses_cover_the_parent_orders(self):
        parents = [pose[0] for pose in iqm_probe.POSES]
        self.assertEqual(parents, [-1, 0, 1, 4, 4, -3])
        self.assertEqual({pose[1] for pose in iqm_probe.POSES} >= {0x3FF, 0}, True)
        joints = [joint[1] for joint in iqm_probe.JOINTS]
        self.assertEqual(joints, [-1, 0, 1, 5, 4, 2, -2])

    def test_the_rows_of_a_case_follow_the_calls_that_run(self):
        items = [dict(id='a', model=True, anims=True), dict(id='b', model=False, anims=True), dict(id='c', model=True, anims=False), dict(id='d', model=False, anims=False)]
        self.assertEqual(iqm_probe.expected_rows(items, ['n1', 'k1', 'a1', 'a2', 'n3', 'k3']), [['n1', 'k1', 'a1'], ['null', 'null', 'a2'], ['n3', 'k3', 'null'], ['null', 'null', 'null']])
        self.assertEqual(iqm_probe.grouped('n1\nk1\n a1\n\nnull\nnull\nnull\n', None), [['n1', 'k1', 'a1'], ['null', 'null', 'null']])


if __name__ == '__main__':
    unittest.main()
