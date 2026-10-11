import struct
import sys
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import m3d_probe


def chunks(model):
    """The chunks of a model (HEAD on) up to its end mark: (name, content)."""
    at, out = struct.unpack_from('<I', model, 4)[0], []
    while model[at:at + 4] != b'OMD3':
        size = struct.unpack_from('<I', model, at + 4)[0]
        out.append((model[at:at + 4], model[at + 8:at + size]))
        at += size
    return out, at


class M3dCasesTests(unittest.TestCase):
    def setUp(self):
        self.items, self.files = m3d_probe.cases(Path('/work'), Path('/raylib'))
        self.data = {Path(path).stem: data for path, data in self.files.items()}

    def test_the_examples_files_and_the_refusals_are_in_the_corpus(self):
        ids = [item['id'] for item in self.items]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual([Path(item['path']).name for item in self.items[:4]], ['cesium_man.m3d', 'suzanne.m3d', 'seagull.m3d', 'missing.m3d'])
        self.assertEqual((self.items[2]['model'], self.items[2]['anims']), (False, False))
        self.assertEqual(set(self.data), set(ids) - {'cesium_man', 'suzanne', 'seagull', 'missing'})
        self.assertEqual((len(ids), sum(item['model'] + item['anims'] for item in self.items), sum((not item['model']) + (not item['anims']) for item in self.items)), (65, 80, 50))
        self.assertEqual({item['id'] for item in self.items if item['model'] and not item['anims']}, {'transform-bone-past', 'transform-vertex-past', 'action-without-a-name'})
        self.assertEqual({item['id'] for item in self.items if item['anims'] and not item['model']}, {'vertex-past', 'normal-past', 'texcoord-past', 'texcoord-without-map', 'bone-without-a-name'})

    def test_a_written_file_has_the_container_and_header_the_importer_reads(self):
        data = self.data['animated']
        self.assertEqual((data[:4], struct.unpack_from('<I', data, 4)[0]), (b'3DMO', len(data)))
        model = data[8:]
        self.assertEqual((model[:4], model[-4:]), (b'HEAD', b'OMD3'))
        length, scale, types = struct.unpack_from('<IfI', model, 4)
        self.assertEqual(scale, 1.0)
        sizes = [1 << ((types >> shift) & 3) for shift in range(0, 18, 2)]
        self.assertEqual(sizes, [4, 2, 2, 8, 2, 1, 1, 1, 1])
        self.assertEqual(model[16:length].split(b'\x00')[:4], [b'model', b'license', b'author', b''])
        found, end = chunks(model)
        self.assertEqual([name for name, _ in found], [b'VRTS', b'BONE', b'MESH', b'ACTN'])
        self.assertEqual(end, len(model) - 4)

    def test_the_compressed_container_inflates_to_the_plain_model(self):
        plain, packed = self.data['animated'], self.data['animated-compressed']
        self.assertEqual(struct.unpack_from('<I', packed, 4)[0], len(packed))
        self.assertEqual(zlib.decompress(packed[8:]), plain[8:])

    def test_the_rig_has_the_parent_orders_and_every_vertex_it_names(self):
        self.assertEqual([bone[0] for bone in m3d_probe.BONES], [-1, 0, 1, 4, 4, 2])
        count = len(m3d_probe.RIG_VERTICES)
        self.assertTrue(all(bone[2] < count and bone[3] < count for bone in m3d_probe.BONES))
        self.assertTrue(all(pos < count and ori < count and bone < len(m3d_probe.BONES) for _, moves in m3d_probe.ACTION for bone, pos, ori in moves))
        self.assertTrue(all(bone < 3 for skin in m3d_probe.SKINS3 for _, bone in skin))
        times = [msec for msec, _ in m3d_probe.ACTION]
        self.assertEqual(times, sorted(times))
        self.assertTrue(any(msec % 17 for msec in times) and times[-1] < 170)

    def test_the_runs_case_has_four_runs_of_three_materials(self):
        found, _ = chunks(self.data['runs'][8:])
        self.assertEqual([name for name, _ in found].count(b'MTRL'), 3)
        mesh = next(content for name, content in found if name == b'MESH')
        self.assertEqual(sum(1 for byte in mesh[::1] if byte == 0x32), 5)

    def test_the_profile_and_cut_cases_are_what_they_say(self):
        self.assertGreater(len(self.data['over-2-mib']), 2 * 1024 * 1024)
        self.assertEqual(self.data['magic-cut'], b'3DM')
        self.assertEqual(len(self.data['header-cut']), 20)
        self.assertGreater(struct.unpack_from('<I', self.data['length-past-the-file'], 4)[0], len(self.data['length-past-the-file']))
        with self.assertRaises(zlib.error):
            zlib.decompress(self.data['stream-cut'][8:])
        self.assertEqual((struct.unpack_from('<I', self.data['doubles'], 20)[0]) & 3, 3)
        found, _ = chunks(self.data['map-names-a-file'][8:])
        material = next(content for name, content in found if name == b'MTRL')
        self.assertEqual(material[-3], 128)


if __name__ == '__main__':
    unittest.main()
