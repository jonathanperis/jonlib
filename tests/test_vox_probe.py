import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vox_probe


def padded(size):
    return size + ((16 - size % 16) % 16)


def faces(data):
    """The visible faces vox_loader builds from a file every read of which stays inside it (the RGBA chunk's
    255 colors included: the reading goes on four bytes before the chunk's end)."""
    assert data[:4] == b'VOX ' and struct.unpack_from('<I', data, 4)[0] in (150, 200)
    at, sizes, voxels = 8, (0, 0, 0), {}
    while at < len(data):
        name = data[at:at + 4]
        length = struct.unpack_from('<I', data, at + 4)[0]
        at += 12
        if name == b'SIZE':
            x, y, z = struct.unpack_from('<III', data, at)
            at += 12
            sizes, voxels = (padded(x), padded(z), padded(y)), {}
        elif name == b'XYZI':
            count = struct.unpack_from('<I', data, at)[0]
            at += 4
            for _ in range(count):
                x, y, z, index = data[at:at + 4]
                at += 4
                assert x < sizes[0] and z < sizes[1] and y < sizes[2]
                voxels[(x, z, sizes[2] - y - 1)] = index
        elif name == b'RGBA':
            assert at + 1020 <= len(data)
            at += 1020
        else:
            at += length
    return sum(1 for (x, y, z), index in voxels.items() if index
               for dx, dy, dz in ((-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1)) if not voxels.get((x + dx, y + dy, z + dz), 0))


class VoxCasesTests(unittest.TestCase):
    def setUp(self):
        self.items, self.files = vox_probe.cases(Path('/work'), Path('/raylib'))
        self.data = {Path(path).stem: data for path, data in self.files.items()}

    def test_the_examples_models_and_the_refusals_are_in_the_corpus(self):
        ids = [item['id'] for item in self.items]
        self.assertEqual(len(ids), len(set(ids)))
        for name in vox_probe.EXAMPLE_MODELS:
            self.assertIn(f'/raylib/examples/models/resources/models/vox/{name}.vox', [item['path'] for item in self.items])
        self.assertEqual({item['id'] for item in self.items if item['contract']},
                         {'magic-cut', 'version-cut', 'header-cut', 'size-cut', 'count-cut', 'voxels-cut', 'palette-cut', 'palette-last', 'palette-first', 'voxel-before-size', 'voxel-past-x',
                          'voxel-past-y', 'voxel-past-z', 'no-voxels', 'header-only', 'zero-ids', 'zero-size', 'size-over-1024', 'array-over-2-21', 'over-2-mib'})
        self.assertEqual(set(self.data), set(ids) - set(vox_probe.EXAMPLE_MODELS) - {'missing'})
        self.assertEqual(sum(1 for item in self.items if not item['contract']), 33)

    def test_the_faces_the_cases_are_built_for(self):
        expected = {'one': 6, 'pair-x': 10, 'pair-y': 10, 'pair-z': 10, 'block': 54, 'corners': 48, 'padding': 24, 'twice': 6, 'erased': 6, 'two-lists': 16, 'no-palette': 12,
                    'after-palette': 6, 'palette-spells-xyzi': 6, 'two-sizes': 6, 'version-200': 12, 'unknown-chunks': 6, 'no-main': 6, 'past-the-end': 6, 'header-then-skip': 6}
        for name, count in expected.items():
            self.assertEqual(faces(self.data[name]), count, name)

    def test_the_split_cases_have_the_vertices_that_split_as_documented(self):
        seven = faces(self.data['seven-meshes']) * 4
        self.assertEqual(seven, 393216)
        self.assertEqual((1 + seven // 65536, seven - 6 * 65532), (7, 24))
        lost = faces(self.data['four-lost']) * 4
        self.assertEqual(lost, 196600)
        self.assertEqual((1 + lost // 65536, lost - 3 * 65532), (3, 4))

    def test_every_compared_file_is_read_inside_its_bytes(self):
        for item in self.items:
            name = item['id']
            if item['contract'] or name not in self.data or name in ('empty-file', 'other-magic', 'short-other-magic', 'other-version'):
                continue
            self.assertGreater(faces(self.data[name]), 0, name)

    def test_a_file_that_ends_with_its_palette_is_read_past_its_end(self):
        with self.assertRaises(struct.error):
            faces(self.data['palette-last'])

    def test_the_voxels_without_a_visible_face_are_refusals(self):
        for name in ('no-voxels', 'zero-ids', 'palette-first'):
            self.assertEqual(faces(self.data[name]), 0, name)

    def test_the_profile_limits_are_crossed_by_their_cases(self):
        self.assertGreater(len(self.data['over-2-mib']), 2 * 1024 * 1024)
        self.assertLess(max(len(data) for name, data in self.data.items() if name != 'over-2-mib'), 2 * 1024 * 1024)
        x, y, z = struct.unpack_from('<III', self.data['array-over-2-21'], 8 + 12 + 12)
        self.assertGreater(padded(x) * padded(y) * padded(z), 1 << 21)
        self.assertEqual(struct.unpack_from('<I', self.data['size-over-1024'], 8 + 12 + 12)[0], 1025)

    def test_a_palette_keeps_255_colors_and_the_reading_stands_four_bytes_early(self):
        chunk = vox_probe.palette(last=tuple(b'XYZI'))
        self.assertEqual((chunk[:4], struct.unpack_from('<I', chunk, 4)[0], chunk[-4:]), (b'RGBA', 1024, b'XYZI'))
        data = self.data['palette-spells-xyzi']
        at = data.index(b'RGBA') + 12 + 1020
        self.assertEqual((data[at:at + 4], data[at + 4:at + 8]), (b'XYZI', b'PACK'))


if __name__ == '__main__':
    unittest.main()
