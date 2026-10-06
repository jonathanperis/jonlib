"""Offline checks for the export probes: fixtures, independent decoders and strict parsers."""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import formatted_bmp_export_probe as bmp
import formatted_export
import formatted_qoi_export_probe as qoi
import formatted_tga_export_probe as tga
import image_export_probe


def chunks(rows):
    """parse_results transport: 256-byte chunks closed by "end"; None as null."""
    lines = []
    for row in rows:
        if row is None:
            lines.append('null')
            continue
        lines += [json.dumps(row[i:i+256]) for i in range(0, len(row), 256)] + ['"end"']
    return '\n'.join(lines)


def observation(meta, *values):
    return '\n'.join([json.dumps(meta), *(chunks([list(v)]) for v in values)]) + '\n'


class RasterExportTests(unittest.TestCase):
    def test_fixture_shapes(self):
        for module, count in ((bmp, 78), (tga, 304)):
            cases = module.fixtures()
            self.assertEqual((len(cases), len({c['id'] for c in cases})), (count, count))
            self.assertTrue(all(len(c['data']) == c['width'] * c['height'] * formatted_export.BPP[c['format']] for c in cases))

    def test_bmp_decoder_reads_both_layouts_bottom_up_and_rejects_mutations(self):
        for fmt, offset in ((1, 54), (7, 122)):
            case = dict(id='x', format=fmt, width=1, height=2)
            fields = [offset + (4 if fmt == 1 else 4) * 2, 0, offset, 40 if fmt == 1 else 108, 1, 2, ((24 if fmt == 1 else 32) << 16) | 1, 0 if fmt == 1 else 3, 0, 0, 0, 0, 0]
            if fmt == 7:
                fields += [0xff0000, 0xff00, 0xff, 0xff000000] + [0] * 13
            pixels = bytes([3, 2, 1, 0, 7, 6, 5, 0]) if fmt == 1 else bytes([3, 2, 1, 4, 7, 6, 5, 8])
            data = b'BM' + struct.pack('<' + 'I' * len(fields), *fields) + pixels
            alpha = (255, 255) if fmt == 1 else (8, 4)
            self.assertEqual(bmp.decode_bmp(data, case), [5, 6, 7, alpha[0], 1, 2, 3, alpha[1]])
            for changed in (data[:-1], data + b'\0', data[:2] + b'\1' + data[3:]):
                with self.assertRaises(ValueError):
                    bmp.decode_bmp(changed, case)
            if fmt == 1:
                with self.assertRaisesRegex(ValueError, 'padding'):
                    bmp.decode_bmp(data[:57] + b'\1' + data[58:], case)

    def test_tga_decoder_expands_packets_and_rejects_bad_streams(self):
        case = dict(id='x', format=4, width=3, height=2)
        head = bytes([0, 0, 10]) + bytes(9) + struct.pack('<HH', 3, 2) + bytes([24, 0])
        a, b = bytes([1, 2, 3]), bytes([4, 5, 6])
        # File rows are bottom-up: a 3-pixel repeat packet, then a 3-pixel raw packet; BGR -> RGBA.
        data = head + bytes([0x82]) + a + bytes([0x02]) + b + a + b
        self.assertEqual(tga.decode_tga(data, case), [6, 5, 4, 255, 3, 2, 1, 255, 6, 5, 4, 255] + [3, 2, 1, 255] * 3)
        for changed in (data[:-1], data + b'\0', head + bytes([0x83]) + a, data[:2] + b'\x0b' + data[3:]):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                tga.decode_tga(changed, case)

    def test_strict_parser_requires_identity_types_and_independent_decode(self):
        codec, case = tga.CODEC, dict(id='x', format=1, width=1, height=1)
        data = bytes([0, 0, 11]) + bytes(9) + struct.pack('<HH', 1, 1) + bytes([8, 0]) + bytes([0, 9])
        text = observation(tga.metadata(case), data, [9, 9, 9, 255])
        self.assertEqual(codec.parse_rows(text, [case])[0]['pixels'], [9, 9, 9, 255])
        for changed in (text.replace('"x"', '"y"'), text.replace('"width": 1', '"width": true'), text + text,
                        text.replace('"format": 1', '"format": 1, "format": 1'), observation(tga.metadata(case), data, [9, 9, 9, 254])):
            with self.assertRaises(ValueError):
                codec.parse_rows(changed, [case])

    def test_codec_templates_are_fully_substituted(self):
        work = Path('/work')
        case = tga.fixtures()[0]
        for program in (tga.CODEC.candidate_program([case], work), tga.CODEC.io_program(work, False)):
            self.assertNotIn('bmp', program.lower())
        self.assertIn('decoded.format!=1', tga.CODEC.reference_program([case], work))
        self.assertNotIn('decoded.format', bmp.CODEC.reference_program([bmp.fixtures()[0]], work))


class QoiExportTests(unittest.TestCase):
    @staticmethod
    def stream(case, payload, space=0):
        return qoi.header(case['width'], case['height'], qoi.channels(case['format']), space) + bytes(payload) + qoi.MARKER

    def test_decoder_covers_every_opcode(self):
        case = dict(id='x', format=7, width=7, height=1)
        payload = [255, 12, 34, 56, 0, 254, 200, 100, 50, 0x40 + 0x15, 0x80 + 40, 0x88, 0xc1, 22]
        result = qoi.decode_qoi(self.stream(case, payload), case)
        self.assertEqual([op['kind'] for op in result['opcodes']], ['RGBA', 'RGB', 'DIFF', 'LUMA', 'RUN', 'INDEX'])
        self.assertEqual(result['raw'][:8], [12, 34, 56, 0, 200, 100, 50, 0])
        self.assertEqual(result['raw'][-4:], [12, 34, 56, 0])

    def test_decoder_rejects_framing_and_rgb_alpha_changes(self):
        case = dict(id='x', format=4, width=1, height=1)
        valid = self.stream(case, [254, 1, 2, 3])
        self.assertEqual(qoi.decode_qoi(valid, case)['pixels'], [1, 2, 3, 255])
        for changed in (valid[:-1], valid + b'\0', valid[:4] + b'\1' + valid[5:], self.stream(case, [255, 1, 2, 3, 0]),
                        self.stream(case, [254, 1, 2, 3], space=1), self.stream(case, [193])):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                qoi.decode_qoi(changed, case)
        self.assertEqual(qoi.decode_qoi(self.stream(case, [254, 1, 2, 3], 1), case, canonical=False)['raw'], [1, 2, 3])

    def test_fixtures_are_safe_and_noncanonical_inputs_decode_to_their_owner(self):
        cases = qoi.fixtures()
        for case in cases:
            qoi.validate_case(case)
            if 'input' in case:
                self.assertEqual(qoi.decode_qoi(bytes(case['input']), case, canonical=False)['raw'], case['data'])
        self.assertEqual({c['format'] for c in cases}, set(range(1, 9)))

    def test_parser_checks_roles_and_retained_owners(self):
        accepted = dict(id='a', format=7, width=1, height=1, data=[12, 34, 56, 0])
        rejected = dict(id='r', format=8, width=1, height=1, data=[0, 0, 0, 128])
        encoded = self.stream(accepted, [255, 12, 34, 56, 0])
        text = ''.join(observation(qoi.metadata(accepted, role), value) for role, value in
                       (('source', accepted['data']), ('encoded', encoded), ('decoded', accepted['data']),
                        ('surface', accepted['data']), ('loaded', accepted['data'])))
        retained = ''.join(observation(qoi.metadata(rejected, role), rejected['data']) for role in ('source', 'retained'))
        rows = qoi.parse_rows(text + retained, [accepted, rejected])
        self.assertEqual((rows[0]['encoded'], rows[1]['retained']), (list(encoded), rejected['data']))
        for changed in (text.replace('"surface"', '"loaded"', 1) + retained, text + retained.replace('[0, 0, 0, 128]', '[0, 0, 0, 0]')):
            with self.assertRaises(ValueError):
                qoi.parse_rows(changed, [accepted, rejected])


class ImageExportTests(unittest.TestCase):
    def test_fixtures_cover_every_codec_and_unsupported_dispatch(self):
        cases = image_export_probe.fixtures()
        self.assertEqual(len({c['id'] for c in cases}), len(cases))
        self.assertEqual({c['codec'] for c in cases if c['status'] == 'ok'}, set(image_export_probe.CODECS))
        self.assertTrue(all(not c['native'] for c in cases if c['path'].endswith(('.jpg', '.jpeg', '.ktx'))))

    def test_candidate_parser_checks_raw_bytes_owners_and_io_errors(self):
        raw = dict(id='raw', status='ok', width=1, height=1, pixels=[0x01020300], codec='raw')
        owner = dict(raw, id='owner', status='unsupported', codec=None)
        error = dict(raw, id='file', status='file')
        rows = [dict(id='raw', status='ok', bytes=[1, 2, 3, 0]), dict(id='owner', status='unsupported', width=1, height=1, pixels=[0x01020300]),
                dict(id='file', status='file', code=2, message_empty=0), dict(closure_checks=True, iterations=100)]
        encode = lambda rows: '\n'.join(map(json.dumps, rows))
        parsed = image_export_probe.parse_rows(encode(rows), [raw, owner, error], candidate=True)
        self.assertEqual(image_export_probe.comparable(parsed), [rows[0], rows[1], dict(id='file', status='file')])
        for index, bad in ((0, dict(rows[0], bytes=[1, 2, 3, 255])), (1, dict(rows[1], pixels=[0x010203ff])),
                           (2, dict(rows[2], code=0)), (2, dict(rows[2], message_empty=1)), (3, dict(rows[3], iterations=99))):
            changed = list(rows); changed[index] = bad
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                image_export_probe.parse_rows(encode(changed), [raw, owner, error], candidate=True)

    def test_files_must_be_complete_and_rejections_must_leave_sentinels(self):
        cases = [dict(id='ok', status='ok', path='out.raw'), dict(id='reject', status='unsupported', path='rejected.data'),
                 dict(id='missing', status='file', path='missing-parent/output.png'), dict(id='directory', status='file', path='directory.png')]
        rows = [dict(bytes=[1, 2, 3, 0]), {}, {}, {}]
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            image_export_probe.prepare_paths(work, cases)
            (work / 'out.raw').write_bytes(bytes([1, 2, 3, 0]))
            image_export_probe.verify_files(work, cases, rows)
            for path, error in (('out.raw', 'Complete'), ('rejected.data', 'sentinel'), ('directory.png/entry', 'directory'), ('closure.data', 'closure')):
                original = (work / path).read_bytes()
                (work / path).write_bytes(b'')
                with self.subTest(path=path), self.assertRaisesRegex(ValueError, error):
                    image_export_probe.verify_files(work, cases, rows)
                (work / path).write_bytes(original)
            (work / 'missing-parent').mkdir()
            with self.assertRaisesRegex(ValueError, 'missing parent'):
                image_export_probe.verify_files(work, cases, rows)

    def test_write_failure_evidence_requires_truncation_and_untouched_sentinel(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            image_export_probe.prepare_write_failure_paths(work)
            text = json.dumps(image_export_probe.write_failure_marker())
            with self.assertRaisesRegex(ValueError, 'not truncated'):
                image_export_probe.verify_write_failures(work, text)
            for codec in image_export_probe.CODECS:
                (work / ('write-failure.' + codec)).write_bytes(b'')
            image_export_probe.verify_write_failures(work, text)
            with self.assertRaisesRegex(ValueError, 'Incomplete'):
                image_export_probe.verify_write_failures(work, json.dumps(dict(image_export_probe.write_failure_marker(), error_code=24)))
            (work / 'write-failure.data').write_bytes(b'')
            with self.assertRaisesRegex(ValueError, 'sentinel changed'):
                image_export_probe.verify_write_failures(work, text)


if __name__ == '__main__':
    unittest.main()
