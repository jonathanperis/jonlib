"""Offline checks for the export and R32 probes: fixtures, independent decoders and strict parsers."""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import float_rgb_r32_probe
import bmp_export_probe as bmp
import codec_exports
import qoi_export_probe as qoi
import tga_export_probe as tga
import image_export_probe
import image_format_probe
import r32_image_probe
import r32_raw_file_probe


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


def words(data):
    return set(struct.unpack('<' + 'I' * (len(data) // 4), bytes(data)))


class R32InputTests(unittest.TestCase):
    def test_r32_samples_are_in_domain_and_straddle_every_threshold(self):
        samples = image_format_probe.r32_words()
        self.assertEqual(samples, sorted(set(samples)))
        self.assertTrue({0, 0x80000000, 1, 0x007fffff, 0x00800000, 0x3f7fffff, 0x3f800000} <= set(samples))
        self.assertTrue(all(w == 0x80000000 or w <= 0x3f800000 for w in samples))
        for limit, offset in ((255, 0), (31, .5), (63, .5), (15, .5)):
            for level in range(1 if offset == 0 else 0, limit):
                center = struct.unpack('<I', struct.pack('<f', (level + offset) / limit))[0]
                self.assertTrue({center - 1, center, center + 1} <= set(samples))

    def test_image_format_covers_all_64_pairs_and_bad_factories(self):
        cases = image_format_probe.cases()
        pairs = {(c['source'], c['targets'][0]) for c in cases if len(c['targets']) == 1 and c['targets'][0] and not c['bridge']}
        self.assertEqual(pairs, {(a, b) for a in range(1, 9) for b in range(1, 9)})
        large = next(c for c in cases if 'repeat_words' in c)
        self.assertEqual(large['bytes'], image_format_probe.word_bytes(large['repeat_words'] * large['repeat_count']))
        controls = image_format_probe.invalid_cases()
        self.assertTrue({0x80000001, 0x3f800001, 0x7f800000, 0x7fc00000} <= {w for c in controls if len(c['bytes']) == 4 and max(c['bytes']) < 256 for w in words(c['bytes'])})
        self.assertTrue(any(c['width'] == 4097 for c in controls) and any(c['bytes'] == [0, 0, 0, 256] for c in controls))

    def test_image_format_parser_reassembles_chunks_and_guards_noops(self):
        case = dict(width=1, height=1, source=8, bytes=[0, 0, 0, 128], targets=[0, 8], bridge=False)
        head = dict(width=1, height=1, format=8, chunked=True)
        encode = lambda rows: '\n'.join(map(json.dumps, rows))
        self.assertEqual(image_format_probe.parse_rows(encode([head, [0, 0], [0, 128], 'end', dict(rejected=True)]), [case], [{}]),
                         [dict(width=1, height=1, format=8, bytes=[0, 0, 0, 128]), dict(rejected=True)])
        for rows in ([head, [0, 0, 0, 128]], [head, [0, 0, 0, 0], 'end'], [dict(head, format=9), [0, 0, 0, 128], 'end'],
                     [head, [0, 0, 0, 128], 'end', 'end'], [head, [0, 0, 0, 256], 'end']):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                image_format_probe.parse_rows(encode(rows), [case])

    def test_r32_image_png_validation_and_shapes(self):
        def png(width, height, rgba):
            chunk = lambda kind, payload: struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
            raster = b''.join(b'\0' + bytes(rgba[y*width*4:(y+1)*width*4]) for y in range(height))
            return list(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
                        + chunk(b'IDAT', zlib.compress(raster)) + chunk(b'IEND', b''))
        good = png(1, 1, [127, 0, 0, 255])
        self.assertTrue(r32_image_probe.valid_png(good, 1, 1))
        for bad in (good[:-1], good + [0], good[:29] + [good[29] ^ 1] + good[30:], png(2, 1, [0] * 8)):
            self.assertFalse(r32_image_probe.valid_png(bad, 1, 1))
        case = dict(id='half', width=1, height=1, bytes=[0, 0, 0, 63])
        ops = [dict(kind='png', case=case), dict(kind='code', case=case), dict(kind='memory_png', case=case)]
        rows = [good, [127, 0, 0, 255], list(b'#define HALF_FORMAT   8\n'), png(1, 1, case['bytes']), case['bytes']]
        shapes = r32_image_probe.schemas(ops)
        self.assertEqual(r32_image_probe.parse_rows(chunks(rows), shapes), rows)
        self.assertEqual(r32_image_probe.png_observations(ops, rows)['half']['png']['decoded_rgba'], [127, 0, 0, 255])
        for index, changed in ((2, list(b'#define HALF_FORMAT   9\n')), (4, [0, 0, 0, 64]), (1, [127, 0, 0])):
            bad = list(rows); bad[index] = changed
            with self.subTest(index=index), self.assertRaises(ValueError):
                r32_image_probe.png_observations(ops, r32_image_probe.parse_rows(chunks(bad), shapes))

    def test_r32_raw_fixtures_select_payloads_and_place_invalid_words_at_both_ends(self):
        cases, controls = r32_raw_file_probe.fixture_specs()
        for case in cases:
            if not case['error']:
                size = case['width'] * case['height'] * 4
                offset = case['header'] if case['header'] and case['header'] + size <= len(case['data']) else 0
                self.assertEqual(case['selected'], case['data'][offset:offset + size])
        for word in r32_raw_file_probe.INVALID_WORDS:
            first = next(c for c in controls if c['name'] == f'invalid-{word:08x}-first')
            last = next(c for c in controls if c['name'] == f'invalid-{word:08x}-last')
            self.assertEqual((first['data'][:4], last['data'][-4:]), (list(struct.pack('<I', word)),) * 2)
        row = r32_raw_file_probe.image_row(cases[0])
        self.assertEqual(r32_raw_file_probe.parse_rows(chunks([row, None]), [cases[0], cases[-1]], native=True), [row, None])
        with self.assertRaises(ValueError):
            r32_raw_file_probe.parse_rows(chunks([row[:-1], None]), [cases[0], cases[-1]], native=True)

    def test_sparse_raw_input_holds_only_the_selected_word(self):
        _, controls = r32_raw_file_probe.fixture_specs()
        case = next(c for c in controls if c['name'] == 'bounded-sparse-header-tail')
        build = r32_raw_file_probe.ROOT / '.build'
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as directory:
            r32_raw_file_probe.prepare_inputs(Path(directory), [], [case])
            path = r32_raw_file_probe.ROOT / case['path']
            self.assertEqual(path.stat().st_size, case['size'])
            with path.open('rb') as file:
                file.seek(case['header'])
                self.assertEqual(file.read(4), b'\0\0\0\x80')

    def test_float_rgb_r32_controls_and_parser(self):
        controls = float_rgb_r32_probe.controls()
        for word in float_rgb_r32_probe.INVALID_WORDS:
            for component in range(3):
                for position in range(3):
                    c = next(c for c in controls if c['name'] == f'reject-{word:08x}-component{component}-position{position}')
                    self.assertEqual(struct.unpack_from('<I', bytes(c['bytes']), 12*position + 4*component)[0], word)
        case = float_rgb_r32_probe.fixture('one', [(0, 0, 0)])
        shapes = float_rgb_r32_probe.shapes([case])
        row = list(struct.pack('<IIII', 1, 1, 8, 0))
        self.assertEqual(float_rgb_r32_probe.parse_rows(chunks([row]), shapes), [row])
        for bad in ([row[:-1]], [list(struct.pack('<IIII', 1, 1, 8, 0x3f800001))], [row, row]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                float_rgb_r32_probe.parse_rows(chunks(bad), shapes)

    def test_float_rgb_r32_qualification_requires_uncontracted_profile(self):
        case = float_rgb_r32_probe.fixture('one', [(0, 0, 0)])
        good = dict(pixels=1, uncontracted_mismatches=0, fused_differences=1)
        self.assertEqual(float_rgb_r32_probe.qualify(good, [case]), good)
        for bad in (dict(good, pixels=2), dict(good, pixels=True), dict(good, uncontracted_mismatches=1), dict(good, fused_differences=0), {}):
            with self.subTest(bad=bad), self.assertRaises(float_rgb_r32_probe.ProbeFailure):
                float_rgb_r32_probe.qualify(bad, [case])


class RasterExportTests(unittest.TestCase):
    def test_fixture_shapes(self):
        for module, count in ((bmp, 78), (tga, 304)):
            cases = module.fixtures()
            self.assertEqual((len(cases), len({c['id'] for c in cases})), (count, count))
            self.assertTrue(all(len(c['data']) == c['width'] * c['height'] * codec_exports.BPP[c['format']] for c in cases))

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
