"""Offline checks for the shared formatted-image probe drivers and every codec spec."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import formatted_codec
from formatted_codec import bend_bytes, bend_input, c_input, compact_segments, parse_rows
import formatted_file
from probekit import ProbeFailure

CODECS = ('bmp', 'tga', 'png', 'pic', 'pnm', 'qoi')
FILES = ('bmp', 'tga', 'png', 'pic', 'pnm')


class EncodingTests(unittest.TestCase):
    def test_compact_segments_are_lossless(self):
        data = [1, 2] + [7] * 300 + [3] * 255 + [9] * 256
        expanded = []
        for kind, value in compact_segments(data):
            expanded += value if kind == 'literal' else [value[0]] * value[1]
        self.assertEqual(expanded, data)
        self.assertEqual([k for k, _ in compact_segments(data)], ['literal', 'repeat', 'literal', 'repeat'])

    def test_short_inputs_stay_plain_literals(self):
        self.assertEqual(bend_input([1, 2, 3]), '[1,2,3]')
        self.assertEqual(c_input([1, 2]), ('const unsigned char data[]={1,2};', ''))

    def test_long_literals_are_chunked(self):
        text = bend_bytes(list(range(256)) * 2)
        self.assertTrue(text.startswith('input_bytes([[0,1,'))
        self.assertEqual(text.count('],['), 7)

    def test_runs_use_repeat_and_heap_copy(self):
        self.assertIn('repeat_input(300n, 7, Nil{})', bend_input([7] * 300))
        declaration, cleanup = c_input([1] + [7] * 300)
        self.assertIn('memset(data+1,7,300);', declaration)
        self.assertEqual(cleanup, 'free(data);')


class FramingTests(unittest.TestCase):
    def test_image_records_collect_chunks_until_end(self):
        text = '\n'.join([json.dumps(dict(id='a', role='raw', width=1, height=1, mipmaps=1, format=4)), '[1,2]', '[3]', '"end"',
                          json.dumps(dict(id='b', role='formatted-error', error=2))])
        rows = parse_rows(text, [dict(id='a'), dict(id='b')])
        self.assertEqual(rows[0]['bytes'], [1, 2, 3])
        self.assertEqual(rows[1], dict(id='b', role='formatted-error', error=2))

    def test_missing_unterminated_and_trailing_records_fail(self):
        head = json.dumps(dict(id='a', role='raw', width=1, height=1, mipmaps=1, format=4))
        for text, heads in [('', [dict(id='a')]), (head + '\n[1]', [dict(id='a')]), (head + '\n"end"\n7', [dict(id='a')])]:
            with self.assertRaises(ProbeFailure):
                parse_rows(text, heads)


class CodecSpecTests(unittest.TestCase):
    def test_every_codec_spec_is_consistent(self):
        for name in CODECS:
            with self.subTest(codec=name):
                codec = __import__(f'{name}_format_probe').CODEC
                cases, controls = codec.fixtures(), codec.controls()
                formatted_codec.validate(codec, cases, controls)
                self.assertTrue(any(c['extended'] for c in cases))
                program = formatted_codec.reference_program(codec, cases[:3])
                self.assertIn(f'LoadImageFromMemory("{codec.token}"', program)

    def test_native_expectations_drive_every_role(self):
        codec = __import__('bmp_format_probe').CODEC
        case = next(c for c in codec.fixtures() if c['extended'])
        fmt = codec.formats[case['channels']]
        raw = dict(id=case['id'], role='raw', width=case['width'], height=case['height'], mipmaps=1, format=fmt,
                   bytes=[0] * (case['width'] * case['height'] * formatted_codec.CHANNEL_BYTES[fmt]))
        normal = dict(raw, role='normalized', format=7, bytes=[0] * (case['width'] * case['height'] * 4))
        rows = [raw, normal] + [dict(raw, role='alias-' + t[1:]) for t in codec.aliases]
        actions, _ = formatted_codec.expectations(codec, [case], [], rows)
        roles = [a['role'] for a in actions]
        self.assertEqual(roles, list(codec.roles) + list(codec.dispatch_roles) + ['uncontracted', 'fused'])
        program = formatted_codec.candidate_program(codec, actions)
        self.assertIn('J.Surface.decode_image_for(M.Fused{}, ".BMP"', program)
        with self.assertRaises(ProbeFailure):
            formatted_codec.expectations(codec, [case], [], [raw, normal] + [dict(raw, role='alias-BMP', format=7)])

    def test_file_specs_route_by_whole_path_extension(self):
        self.assertEqual(formatted_file.extension('dir.bmp/leaf'), '.bmp/leaf')
        self.assertEqual(formatted_file.extension('.bmp'), '')
        for name in FILES:
            with self.subTest(codec=name):
                codec = __import__(f'{name}_file_probe').CODEC
                cases, controls = formatted_file.fixtures(codec), formatted_file.controls(codec)
                self.assertEqual(len({c['id'] for c in cases + controls}), len(cases) + len(controls))
                for c in cases:
                    routed = formatted_file.extension('fixtures/' + c['filename']) in formatted_file.RECOGNIZED
                    self.assertEqual(c['route'] == 'LoadImage', routed, c['id'])
                self.assertEqual({c['special'] for c in controls if 'special' in c} >= {'missing', 'directory', 'sparse', 'overflow'}, True)


if __name__ == '__main__':
    unittest.main()
