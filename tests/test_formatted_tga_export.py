"""Behavioral guardrails for formatted TGA evidence; no compiler/native builds."""
import argparse
from contextlib import contextmanager, redirect_stderr, redirect_stdout
import copy
import io
import json
import os
from pathlib import Path
import runpy
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
with patch('sys.path', [str(ROOT/'tools'), *sys.path]):
    P = runpy.run_path(str(ROOT/'tools/formatted_tga_export_probe.py'))
G = P['main'].__globals__
BPP = {1: 1, 2: 2, 3: 2, 4: 3, 5: 2, 6: 2, 7: 4, 8: 4}


def components(fmt):
    return {1: 1, 2: 2, 4: 3}.get(fmt, 4)


def header(case):
    comp = components(case['format'])
    return (bytes((0, 0, 11 if comp < 3 else 10)) + bytes(9)
            + struct.pack('<HH', case['width'], case['height'])
            + bytes((comp*8, 8 if comp in (2, 4) else 0)))


def rgba(sample):
    if len(sample) == 1:
        return [sample[0]]*3 + [255]
    if len(sample) == 2:
        return [sample[0]]*3 + [sample[1]]
    return [sample[2], sample[1], sample[0], sample[3] if len(sample) == 4 else 255]


def make_stream(case, rows):
    """Rows in file order; each packet is (repeat?, list of stored samples)."""
    encoded = bytearray(header(case))
    pixels = []
    for packets in rows:
        row = []
        for repeat, samples in packets:
            encoded.append((128 if repeat else 0) + len(samples)-1)
            encoded.extend(b''.join(samples[:1] if repeat else samples))
            row.extend(v for sample in samples for v in rgba(sample))
        pixels.append(row)
    return bytes(encoded), [v for row in reversed(pixels) for v in row]


def simple_stream(case):
    comp = components(case['format'])
    rows = []
    for y in range(case['height']):
        values = [bytes((17+x*13+y*71+i*19) % 256 for i in range(comp))
                  for x in range(case['width'])]
        rows.append([(False, values[i:i+128]) for i in range(0, len(values), 128)])
    return make_stream(case, rows)


def observation(case, stream=None):
    encoded, pixels = stream if stream is not None else simple_stream(case)
    meta = {k: case[k] for k in ('id', 'format', 'width', 'height')}
    meta['decoded_format'] = case['format'] if case['format'] in (1, 2, 4) else 7
    result = [json.dumps(meta)]
    for values in (list(encoded), pixels):
        result.extend(json.dumps(values[i:i+256]) for i in range(0, len(values), 256))
        result.append('"end"')
    return '\n'.join(result)+'\n'


def expanded(case):
    """Independent native checked-format expansion, only for fixture controls."""
    fmt = case['format']
    data = bytes(case['data'])
    colors = []
    for i in range(0, len(data), BPP[fmt]):
        value = data[i:i+BPP[fmt]]
        word = int.from_bytes(value, 'little')
        if fmt == 1: color = (value[0], value[0], value[0], 255)
        elif fmt == 2: color = (value[0], value[0], value[0], value[1])
        elif fmt == 3: color = ((word >> 11)*8, ((word >> 5) & 63)*4, (word & 31)*8, 255)
        elif fmt == 4: color = (*value, 255)
        elif fmt == 5: color = ((word >> 11)*8, ((word >> 6) & 31)*8, ((word >> 1) & 31)*8, (word & 1)*255)
        elif fmt == 6: color = tuple(((word >> shift) & 15)*17 for shift in (12, 8, 4, 0))
        elif fmt == 7: color = tuple(value)
        else:
            product = struct.unpack('<f', struct.pack('<f', struct.unpack('<f', value)[0]*255))[0]
            color = (int(product), 0, 0, 255)
        colors.append(color)
    return colors


@contextmanager
def working_directory(path):
    old = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(old)


class FormattedTgaFixturesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = P['fixtures']()
        cls.by_id = {c['id']: c for c in cls.cases}

    def test_unique_complete_checked_byte_shapes_and_determinism(self):
        self.assertEqual(len(self.cases), len(self.by_id))
        self.assertEqual(self.cases, P['fixtures']())
        self.assertEqual(P['BPP'], BPP)
        for c in self.cases:
            with self.subTest(case=c['id']):
                self.assertTrue(c['id'])
                self.assertIn(c['format'], BPP)
                self.assertTrue(1 <= c['width'] <= 4096 and 1 <= c['height'] <= 4096)
                self.assertEqual(len(c['data']), c['width']*c['height']*BPP[c['format']])
                self.assertTrue(all(type(v) is int and 0 <= v <= 255 for v in c['data']))

    def test_every_format_widths_packet_boundaries_and_patterns(self):
        for fmt in BPP:
            prefix = f'format-{fmt}-'
            for width in range(1, 5):
                c = self.by_id[prefix+f'width-{width}']
                self.assertEqual((c['width'], c['height']), (width, 2))
                self.assertNotEqual(expanded(c)[:width], expanded(c)[width:])
            a, b, c = expanded(self.by_id[prefix+'raw-3'])
            self.assertEqual(len({a, b, c}), 3)
            for length in (1, 2, 3, 127, 128, 129, 130, 255, 256, 257):
                for style in ('repeat', 'raw'):
                    sample = self.by_id[prefix+f'{style}-{length}']
                    self.assertEqual((sample['width'], sample['height']), (length, 1))
                    self.assertEqual(expanded(sample), [a]*length if style == 'repeat' else [[a, b, c][i % 3] for i in range(length)])
            for name, indices in [('aba', [0, 1, 0]), ('abbc', [0, 1, 1, 2]), ('aab', [0, 0, 1]), ('abb', [0, 1, 1]), ('mixed', [0, 1, 2, 2, 2, 0, 1, 0, 1, 1, 2])]:
                self.assertEqual(expanded(self.by_id[prefix+name]), [[a, b, c][i] for i in indices])

    def test_axes_full_traversal_orientation_and_row_reset(self):
        for fmt in BPP:
            prefix = f'format-{fmt}-'
            for name, shape in [('axis-row', (4096, 1)), ('axis-column', (1, 4096)), ('full-traversal', (256, 129)), ('seeded-mixed', (257, 2))]:
                c = self.by_id[prefix+name]
                self.assertEqual((c['width'], c['height']), shape)
                self.assertEqual(len(expanded(c)), shape[0]*shape[1])
            self.assertEqual(len(expanded(self.by_id[prefix+'full-traversal'])), 33024)
            rows = expanded(self.by_id[prefix+'identical-rows'])
            self.assertEqual(rows[:3], rows[3:])
            self.assertEqual(len(set(rows)), 1)
            orient = expanded(self.by_id[prefix+'orientation'])
            self.assertEqual(len({tuple(orient[i:i+3]) for i in (0, 3, 6)}), 3)
            self.assertNotEqual(orient[0], orient[-1])
            self.assertNotEqual(orient[0], orient[2])
            self.assertEqual(orient[2], orient[3])

    def test_alpha_only_hidden_rgb_and_packed_boundaries(self):
        for fmt in (2, 7):
            colors = expanded(self.by_id[f'format-{fmt}-alpha-only'])
            self.assertEqual({c[3] for c in colors}, {0, 1, 127, 128, 254, 255})
            self.assertEqual(len({c[:3] for c in colors}), 1)
            self.assertEqual([c[3] for c in expanded(self.by_id[f'format-{fmt}-alpha-aba'])], [0, 255, 0])
        colors = expanded(self.by_id['rgba-alpha-zero-hidden-rgb'])
        self.assertEqual({c[3] for c in colors}, {0})
        self.assertEqual(len(set(colors)), 6)
        for fmt in (3, 5, 6):
            c = self.by_id[f'packed-{fmt}-boundaries']
            words = struct.unpack('<21H', bytes(c['data']))
            self.assertTrue({0, 1, 15, 16, 31, 32, 63, 64, 65535, 0xF801, 0x3E} <= set(words))
            self.assertEqual(len(set(struct.unpack('<35H', bytes(self.by_id[f'packed-{fmt}-seeded']['data'])))), 35)
        c = self.by_id['packed-3-boundaries']
        words = struct.unpack('<21H', bytes(c['data']))
        self.assertEqual(expanded(c)[words.index(65535)], (248, 252, 248, 255))
        for fmt, count in ((5, 2), (6, 16)):
            colors = expanded(self.by_id[f'packed-{fmt}-alpha-only'])
            self.assertEqual(len({c[:3] for c in colors}), 1)
            self.assertEqual(len({c[3] for c in colors}), count)

    def test_r32_threshold_neighbors_legal_domain_and_expanded_runs(self):
        c = self.by_id['r32-truncation-boundaries']
        words = set(struct.unpack('<'+'I'*(len(c['data'])//4), bytes(c['data'])))
        self.assertTrue({0, 0x80000000, 1, 2, 0x007fffff, 0x00800000, 0x3f000000, 0x3f800000} <= words)
        self.assertTrue(all(w == 0x80000000 or 0 <= w <= 0x3f800000 for w in words))
        for level in range(1, 255):
            word = struct.unpack('<I', struct.pack('<f', level/255))[0]
            self.assertTrue({word-1, word, word+1} <= words)
        collapse = self.by_id['r32-expanded-run-collapse']
        self.assertEqual(len(set(struct.unpack('<9I', bytes(collapse['data'])))), 9)
        self.assertEqual(expanded(collapse), [(0, 0, 0, 255)]*6+[(127, 0, 0, 255)]*3)

    def test_large_raw_case_really_exceeds_generic_cap(self):
        c = self.by_id['rgba-large-raw']
        self.assertEqual((c['width'], c['height']), (513, 513))
        values = expanded(c)
        for y in range(513):
            row = values[y*513:(y+1)*513]
            self.assertTrue(all(row[x] != row[x+1] for x in range(512)))
            self.assertTrue(all(row[x] != row[x+2] for x in range(511)))
        self.assertGreater(18+513*513*4+513*5, 1024*1024)


class FormattedTgaDecoderTests(unittest.TestCase):
    def test_all_native_headers_metadata_and_decoded_channel_order(self):
        for fmt in BPP:
            c = dict(id='sample', format=fmt, width=3, height=2)
            stream = simple_stream(c)
            self.assertEqual(P['decode_tga'](stream[0], c), stream[1])
            self.assertEqual(P['channels'](fmt), components(fmt))
            self.assertEqual(P['metadata'](c)['decoded_format'], fmt if fmt in (1, 2, 4) else 7)
            self.assertEqual(P['parse_rows'](observation(c, stream), [c])[0]['pixels'], stream[1])

    def test_repeat_raw_singletons_and_full_128_packets(self):
        for fmt in BPP:
            comp = components(fmt)
            a = bytes(range(1, comp+1)); b = bytes(range(21, 21+comp))
            for count in (1, 2, 3, 127, 128):
                for repeat in (False, True):
                    c = dict(id='packet', format=fmt, width=count+1, height=2)
                    values = [a]*count if repeat else [a if i % 2 else b for i in range(count)]
                    stream = make_stream(c, [[(repeat, values), (False, [b])], [(False, [a]), (repeat, values)]])
                    self.assertEqual(P['decode_tga'](stream[0], c), stream[1])

    def test_header_mutations_rejected_at_every_byte(self):
        for fmt in BPP:
            c = dict(id='header', format=fmt, width=3, height=2)
            encoded, _ = simple_stream(c)
            for index in range(18):
                altered = bytearray(encoded); altered[index] ^= 1
                with self.subTest(fmt=fmt, byte=index), self.assertRaises(ValueError):
                    P['decode_tga'](bytes(altered), c)
            for descriptor in (16, 32, 40, 128):
                altered = bytearray(encoded); altered[17] = descriptor
                with self.assertRaises(ValueError): P['decode_tga'](bytes(altered), c)

    def test_short_headers_packets_payloads_trailing_bytes_and_row_overrun(self):
        for fmt in BPP:
            c = dict(id='bounds', format=fmt, width=2, height=2)
            encoded, _ = simple_stream(c)
            for end in range(len(encoded)):
                with self.subTest(fmt=fmt, end=end), self.assertRaises(ValueError):
                    P['decode_tga'](encoded[:end], c)
            for suffix in (b'\0', b'TRUEVISION-XFILE.\0', encoded[18:]):
                with self.assertRaises(ValueError): P['decode_tga'](encoded+suffix, c)
            comp = components(fmt)
            for code in (2, 3, 127, 130, 131, 255):
                crossing = header(c)+bytes([code])+bytes(comp*128)
                with self.assertRaisesRegex(ValueError, 'crosses row'): P['decode_tga'](crossing, c)
            for bad_type in (bytearray(encoded), list(encoded), memoryview(encoded), None):
                with self.assertRaises(ValueError): P['decode_tga'](bad_type, c)

    def test_checked_domain_rejects_boolean_noninteger_unknown_and_out_of_range(self):
        base = dict(id='domain', format=7, width=1, height=1)
        encoded, _ = simple_stream(base)
        for key in ('width', 'height', 'format'):
            values = (True, False, 1.0, '1', None, -1, 0, 4097) if key != 'format' else (True, False, 7.0, '7', None, -1, 0, 9)
            for value in values:
                changed = dict(base); changed[key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    P['decode_tga'](encoded, changed)

    def test_parser_checks_entire_33024_pixel_observation_including_last_byte(self):
        c = dict(id='full', format=7, width=256, height=129)
        encoded, pixels = simple_stream(c)
        lines = observation(c, (encoded, pixels)).splitlines()
        row = P['parse_rows']('\n'.join(lines), [c])[0]
        self.assertEqual(row['encoded'], list(encoded))
        self.assertEqual(row['pixels'], pixels)
        self.assertEqual(len(row['pixels']), 33024*4)
        for index in (lines.index('"end"')-1, len(lines)-2):
            changed = lines[:]; values = json.loads(changed[index]); values[-1] ^= 1
            changed[index] = json.dumps(values)
            with self.assertRaises(ValueError): P['parse_rows']('\n'.join(changed), [c])

    def test_parser_rejects_identity_order_missing_duplicates_extra_metadata(self):
        cases = [dict(id='one', format=2, width=1, height=2), dict(id='two', format=7, width=2, height=1)]
        records = [observation(c) for c in cases]
        self.assertEqual(len(P['parse_rows'](''.join(records), cases)), 2)
        for changed in ('', records[0], records[1]+records[0], records[0]*2, ''.join(records)+records[0], '\n'+''.join(records)):
            with self.assertRaises(ValueError): P['parse_rows'](changed, cases)
        lines = records[0].splitlines()
        meta = json.loads(lines[0])
        for key in meta:
            variants = []
            missing = dict(meta); del missing[key]; variants.append(missing)
            for value in (None, True, False, 1.0, [], 'other', 999):
                changed = dict(meta); changed[key] = value; variants.append(changed)
            for changed in variants:
                with self.assertRaises(ValueError): P['parse_rows']('\n'.join([json.dumps(changed), *lines[1:]]), cases[:1])
        for altered in (dict(meta, extra=1), [], None):
            with self.assertRaises(ValueError): P['parse_rows']('\n'.join([json.dumps(altered), *lines[1:]]), cases[:1])
        duplicate = lines[0][:-1]+', "decoded_format": 2}'
        with self.assertRaisesRegex(ValueError, 'Duplicate'): P['parse_rows']('\n'.join([duplicate, *lines[1:]]), cases[:1])

    def test_parser_rejects_bad_chunk_types_bounds_counts_and_pixel_mismatch(self):
        c = dict(id='chunk', format=7, width=65, height=2)
        lines = observation(c).splitlines()
        for index in (1, lines.index('"end"')+1):
            for chunk in ('[]', 'null', 'true', '{}', '[true]', '[256]', '[-1]', '[0.0]', '["1"]', json.dumps([0]*257), '"End"'):
                changed = lines[:]; changed[index] = chunk
                with self.assertRaises(ValueError): P['parse_rows']('\n'.join(changed), [c])
        for index, line in enumerate(lines):
            if line == '"end"':
                with self.assertRaises(ValueError): P['parse_rows']('\n'.join(lines[:index]+lines[index+1:]), [c])
        pixel_start = lines.index('"end"')+1
        for change in ('remove', 'append', 'flip', 'repeat'):
            changed = lines[:]
            values = json.loads(changed[pixel_start])
            if change == 'remove': values.pop()
            elif change == 'append': values.append(0)
            elif change == 'flip': values[-1] ^= 1
            else: changed.insert(pixel_start, changed[pixel_start])
            if change != 'repeat': changed[pixel_start] = json.dumps(values)
            with self.assertRaises(ValueError): P['parse_rows']('\n'.join(changed), [c])
        self.assertEqual(len(P['parse_rows']('\n'.join(lines), [c])[0]['pixels']), 520)


class FormattedTgaGeneratedProgramsTests(unittest.TestCase):
    def test_native_original_typed_owners_full_memcmp_and_preconversion_format(self):
        cases = [dict(id=f'f-{fmt}', format=fmt, width=3, height=2, data=[0]*(6*BPP[fmt])) for fmt in BPP]
        source = P['reference_program'](cases, Path('/tmp/tga-reference'))
        self.assertNotIn('ExportImageToMemory', source)
        self.assertNotIn('ImageFormat(&image', source)
        self.assertIn('unsigned short value;memcpy(&value,data+2*i,sizeof value);samples[i]=value;', source)
        self.assertIn('float value;memcpy(&value,data+4*i,sizeof value);samples[i]=value;', source)
        self.assertIn('memcmp(storage,data,(size_t)size)', source)
        self.assertEqual(source.count('ExportImage(image,'), 8)
        self.assertEqual(source.count('if(image.data!=data)free(image.data)'), 8)
        bodies = source.split('{int n=0;')[1:]
        self.assertEqual(len(bodies), 8)
        for c, body in zip(cases, bodies):
            self.assertIn(f'typed_pixels(data,n,{c["format"]})', body)
            expected = c['format'] if c['format'] in (1, 2, 4) else 7
            check = f'decoded.format!={expected}'
            self.assertLess(body.index('ExportImage(image,'), body.index('LoadImageFromMemory(".tga"'))
            self.assertLess(body.index(check), body.index('ImageFormat(&decoded,7)'))
            self.assertIn('emit(decoded.data,decoded.width*decoded.height*4)', body)

    def test_candidate_actual_api_dat_writer_and_full_compact_observations(self):
        c = dict(id='full', format=7, width=256, height=129, data=[0]*(33024*4))
        source = P['candidate_program']([c], Path('/tmp/tga-candidate'))
        for call in ('J.Image.Formatted.to_tga(image)', 'J.Image.Formatted.write_tga(image, path)', 'J.Surface.decode_tga(bytes)', 'File.close(file)', 'emit_chunks'):
            self.assertIn(call, source)
        self.assertIn('full.dat', source)
        self.assertIn('132097', source)
        self.assertNotIn('to_surface', source)
        self.assertNotIn('Surface.load_image', source)
        self.assertLess(len(source), 10000)

    def test_io_exact_code_message_all_formats_and_qualification_controls(self):
        for failure in (False, True):
            source = P['io_program'](Path('/tmp/tga-io'), failure)
            for text in ('String.eq(message, actual_message)', 'U32.is_eq(code, actual_code)', 'U32.is_gt(code, 0)', 'loop(100n'):
                self.assertIn(text, source)
            for fmt in BPP: self.assertIn(f'from_bytes(1, 1, {fmt},', source)
            self.assertIn('baseline(27,' if failure else 'baseline(2,', source)
        source = P['QUALIFY']
        for text in ('LoadImageColors(image)', 'sizeof(unsigned short)==2', 'fegetround()!=FE_TONEAREST', '0xf8fcf8ff', '0x80000000', 'float sample;memcpy(&sample,&words[i],sizeof sample)', '(void *)&sample : (void *)&packed'):
            self.assertIn(text, source)
        self.assertNotIn('Image image={words+i', source)
        self.assertNotIn('ExportImageToMemory', source)


class FormattedTgaIOAndSealsTests(unittest.TestCase):
    def setUp(self): P['SEALED'].clear()
    def tearDown(self): P['SEALED'].clear()

    def test_io_success_and_failure_require_complete_typed_markers_and_files(self):
        marker = json.dumps(dict(iterations=100, writes=800))+'\n'
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp); (work/'directory').mkdir()
            (work/'directory/sentinel').write_bytes(P['SENTINEL'])
            c = dict(id='last', format=8, width=1, height=1)
            encoded, _ = make_stream(c, [[(False, [bytes((0, 0, 127, 255))])]])
            (work/'repeated.dat').write_bytes(encoded); (work/'post-open.dat').write_bytes(b'')
            for failure in (False, True):
                count = 1 if failure else 3
                self.assertEqual(P['verify_io'](marker*count, work, failure)['writes'], count*800)
                for text in ('', marker*(count+1), marker*(count-1), json.dumps(dict(iterations=100.0, writes=800))+'\n', json.dumps(dict(iterations=100, writes=799))+'\n', '{"iterations":100,"writes":800,"writes":800}'):
                    with self.assertRaises(ValueError): P['verify_io'](text, work, failure)
            (work/'post-open.dat').write_bytes(b'old')
            with self.assertRaises(ValueError): P['verify_io'](marker, work, True)
            (work/'directory/sentinel').write_bytes(b'changed')
            with self.assertRaises(ValueError): P['verify_io'](marker*3, work, False)
            (work/'directory/sentinel').write_bytes(P['SENTINEL']); (work/'missing-parent').mkdir()
            with self.assertRaises(ValueError): P['verify_io'](marker*3, work, False)

    def test_sealed_content_mutation_missing_and_idempotent_seal(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'input'; path.write_bytes(b'input')
            P['seal'](path); P['seal'](path); P['verify_sealed']()
            self.assertEqual(len(P['SEALED']), 1)
            path.write_bytes(b'other')
            with self.assertRaises(ValueError): P['verify_sealed']()
            with self.assertRaises(ValueError): P['seal'](path)
            path.unlink()
            with self.assertRaises(ValueError): P['verify_sealed']()

    def test_compiler_old_output_removed_missing_or_empty_outputs_fail(self):
        for contents in (None, b''):
            with self.subTest(contents=contents), tempfile.TemporaryDirectory() as tmp:
                P['SEALED'].clear()
                work = Path(tmp); output = work/'compiled'; output.write_bytes(b'old')
                def run(command, **kwargs):
                    self.assertFalse(output.exists())
                    if contents is not None: output.write_bytes(contents)
                    return subprocess.CompletedProcess(command, 0, 'output', '')
                with patch('subprocess.run', side_effect=run):
                    with self.assertRaisesRegex(ValueError, 'Compiler output missing'):
                        P['record_run'](['not-run', '-o', output], work, 'compile')
                self.assertEqual((work/'compile.stdout').read_text(), 'output')

    def test_record_run_checks_inputs_first_and_seals_executables_logs_commands(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp); source = work/'source'; source.write_bytes(b'input'); output = work/'compiled'
            def run(command, **kwargs):
                output.write_bytes(b'executable')
                self.assertEqual(kwargs['timeout'], 19)
                return subprocess.CompletedProcess(command, 0, 'stdout', 'stderr')
            with patch('subprocess.run', side_effect=run):
                self.assertEqual(P['record_run'](['not-run', source, '-o', output], work, 'compile', timeout=19), 'stdout')
            for path in (source, output, work/'compile.stdout', work/'compile.stderr', work/'compile.command.json'):
                self.assertIn(str(path.resolve()), P['SEALED'])
            source.write_bytes(b'changed')
            with patch('subprocess.run') as launch:
                with self.assertRaises(ValueError): P['record_run']([output], work, 'execute')
                launch.assert_not_called()

    def test_nonzero_process_retains_diagnostics_but_cannot_succeed(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 9, 'partial', 'failure')):
                with self.assertRaisesRegex(ValueError, 'exited 9'):
                    P['record_run'](['not-run'], work, 'failed')
            self.assertEqual(json.loads((work/'failed.command.json').read_text())['exit_code'], 9)
            self.assertEqual((work/'failed.stderr').read_text(), 'failure')


class FormattedTgaAdmissionTests(unittest.TestCase):
    def test_exact_tokens_duplicates_terminator_and_dash_values_match_argparse(self):
        with tempfile.TemporaryDirectory() as tmp:
            default = Path(tmp)/'default/formatted-tga-export-probe'
            with patch.dict(G, BUILD=Path(tmp)/'default'):
                for args, expected in [([], [default]), (['--build-di', 'x'], [default]), (['--build-dirx=y'], [default]), (['--', '--build-dir', 'ignored'], [default]), (['--build-dir=a', '--build-dir', 'b', '--build-dir=a'], list(map(Path, ['a', 'b', 'a']))), (['--build-dir=a', '--', '--build-dir=b'], [Path('a')]), (['--build-dir', '--bad'], [default])]:
                    self.assertEqual(P['report_directories'](args), expected)
                parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
                parser.add_argument('--build-dir', type=Path)
                for token in ('-1', '-1.25', '-.5', '-dash space', '--dash space', 'plain space', ''):
                    args = ['--build-dir', token]
                    accepted = parser.parse_args(args).build_dir
                    self.assertEqual(P['report_directories'](args), [accepted])

    def test_all_destinations_are_failed_before_late_errors_help_or_unknowns(self):
        for tail in (['--timeout', 'invalid'], ['--timeout', '0'], ['--timeout', '-3'], ['--unknown'], ['--help']):
            with self.subTest(tail=tail), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); a = root/'first'; b = root/'late'
                for path in (a, b): path.mkdir(); (path/'results.json').write_text('{"passed":true}')
                argv = ['--bend-source', tmp, '--raylib-source', tmp, '--build-dir', str(a), *tail, '--build-dir='+str(b), '--build-dir', str(a)]
                with patch.dict(G, checkout=lambda *a: self.fail('checkout before validation')), redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
                    with self.assertRaises(SystemExit): P['main'](argv)
                for path in (a, b): self.assertIs(json.loads((path/'results.json').read_text())['passed'], False)

    def test_negative_and_dash_space_paths_admitted_before_invalid_integer(self):
        with tempfile.TemporaryDirectory() as tmp, working_directory(tmp):
            for token in ('-1', '-1.25', '-.5', '-dash space', '--dash space'):
                path = Path(token); path.mkdir(); (path/'results.json').write_text('{"passed":true}')
                with redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit): P['main'](['--build-dir', token, '--timeout', 'invalid'])
                self.assertIs(json.loads((path/'results.json').read_text())['passed'], False)

    def test_double_dash_and_abbreviations_never_admit_unselected_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); ignored = root/'ignored'; ignored.mkdir()
            (ignored/'results.json').write_text('{"passed":true}')
            with patch.dict(G, BUILD=root/'default'), redirect_stderr(io.StringIO()):
                for argv in (['--', '--build-dir', str(ignored)], ['--build-di', str(ignored)], ['--build-dirx='+str(ignored)]):
                    with self.assertRaises(SystemExit): P['main'](argv)
                    self.assertIs(json.loads((ignored/'results.json').read_text())['passed'], True)
                    self.assertIs(json.loads((root/'default/formatted-tga-export-probe/results.json').read_text())['passed'], False)

    def test_checkout_failure_invalidates_old_success_without_deleting_user_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); work = root/'destination'; work.mkdir()
            (work/'results.json').write_text('{"passed":true}')
            (work/'candidate-0').write_bytes(b'stale executable')
            (work/'important').mkdir(); (work/'important/document').write_bytes(b'keep')
            with patch.dict(G, checkout=lambda *a: (_ for _ in ()).throw(ValueError('bad pin'))):
                with self.assertRaisesRegex(ValueError, 'bad pin'):
                    P['main'](['--bend-source', tmp, '--raylib-source', tmp, '--build-dir', str(work)])
            self.assertIs(json.loads((work/'results.json').read_text())['passed'], False)
            self.assertEqual((work/'candidate-0').read_bytes(), b'stale executable')
            self.assertEqual((work/'important/document').read_bytes(), b'keep')
            self.assertEqual(len(list(work.glob('run-*'))), 1)


def control_cases():
    selected = []
    streams = {}
    for case in P['fixtures']():
        name = case['id']
        if not (name.endswith(('-aba', '-abbc', '-identical-rows')) and name.startswith('format-') and '-alpha-' not in name) and name != 'r32-expanded-run-collapse':
            continue
        selected.append(case)
        comp = components(case['format'])
        def stored(color):
            r, g, b, a = color
            return bytes([r] if comp == 1 else [r, a] if comp == 2 else [b, g, r] if comp == 3 else [b, g, r, a])
        samples = [stored(color) for color in expanded(case)]
        if name.endswith('-aba'): rows = [[(False, samples[:1]), (False, samples[1:])]]
        elif name.endswith('-abbc'): rows = [[(False, samples)]]
        elif name.endswith('-identical-rows'): rows = [[(True, samples[:3])], [(True, samples[3:])]]
        else: rows = [[(True, samples[:6]), (True, samples[6:])]]
        streams[name] = make_stream(case, rows)
    return selected, streams


class FormattedTgaPipelineTests(unittest.TestCase):
    """Exercise the actual main/report/record_run path with only processes mocked."""
    @classmethod
    def setUpClass(cls):
        cls.cases, cls.streams = control_cases()

    def setUp(self):
        P['SEALED'].clear()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(P['SEALED'].clear)
        self.base = Path(self.temp.name)
        self.root = self.base/'repo'; self.root.mkdir()
        self.build = self.root/'.build'
        self.destination = self.base/'outside-repository'
        self.destination.mkdir()
        self.report_path = self.destination/'results.json'
        self.report_path.write_text('{"passed":true}')
        (self.destination/'candidate-0').write_text('stale executable')
        (self.root/'toolchain.json').write_text(json.dumps(dict(bend=dict(revision='bend-pin', patch={'declared': True}), raylib=dict(revision='ray-pin'), bun=dict(version='mock-bun'))))
        self.library = self.root/'jonlib.bend'; self.library.write_text('library source')
        self.dependency = self.root/'dependency.py'; self.dependency.write_text('probe dependency')
        self.compiler = self.root/'bend/bend2/main.ts'; self.compiler.parent.mkdir(parents=True); self.compiler.write_text('compiler source')
        self.tool_paths = {}
        for tool in ('bun', 'clang', 'cmake'):
            path = self.base/('mock-'+tool); path.write_bytes(b'mock tool')
            self.tool_paths[tool] = str(path)
        self.alternate = self.base/'other-tool'; self.alternate.write_bytes(b'mock tool')
        self.commands = []
        self.checkouts = []
        self.snapshots = 0
        self.fault = None
        self.work = None

    def sources(self, args):
        self.snapshots += 1
        return dict(library={'jonlib.bend': P['digest'](self.library)}, dependencies={str(p): P['digest'](p) for p in (self.dependency, self.compiler)})

    def checkout(self, *args):
        self.checkouts.append(args)
        if len(self.checkouts) != 4:
            return
        targets = {'library': self.library, 'dependency': self.dependency, 'compiler': self.compiler,
                   'archive': self.build/'raylib/raylib/libraylib.a',
                   'cache': self.build/'raylib/CMakeCache.txt', 'flags': self.build/'raylib/raylib/CMakeFiles/raylib.dir/flags.make',
                   'inputs': self.work/'inputs.json', 'raw-input': self.work/(self.cases[0]['id']+'.raw'),
                   'generated': self.work/'candidate-0.bend', 'executable': self.work/'candidate-0',
                   'stdout': self.work/'cpu-1-0.stdout', 'command': self.work/'cpu-1-0.command.json',
                   'reference-file': self.work/('reference-'+self.cases[0]['id']+'.tga'),
                   'retained': self.work/('cpu-1-'+self.cases[0]['id']+'.dat'),
                   'io-retained': self.work/'javascript-failure-final.dat', 'tool-content': Path(self.tool_paths['clang'])}
        if self.fault in targets:
            targets[self.fault].write_bytes(b'mutated')
        if self.fault == 'missing-sealed':
            (self.work/'candidate-0.bend').unlink()
        if self.fault == 'final-pin':
            raise ValueError('Final checkout pin differs')

    def which(self, tool):
        if self.fault == 'tool-resolution' and len(self.checkouts) == 4:
            return str(self.alternate)
        return self.tool_paths[tool]

    def process(self, command, **kwargs):
        command = list(map(str, command))
        self.commands.append((command, kwargs))
        self.work = next(self.destination.glob('run-*'))
        output = ''
        if command[0] == 'cmake':
            for relative in ('raylib/libraylib.a', 'CMakeCache.txt', 'raylib/CMakeFiles/raylib.dir/flags.make'):
                path = self.build/'raylib'/relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'native build')
        elif command[:2] == ['bun', '--version']:
            output = 'wrong-bun' if self.fault == 'bun-version' else 'mock-bun\n'
        elif command[:2] == ['clang', '--version']:
            output = 'mock clang\n'
        elif '-o' in command:
            for i, arg in enumerate(command[:-1]):
                if arg == '-o':
                    path = Path(command[i+1])
                    if self.fault != 'missing-output': path.write_bytes(b'mock executable')
        else:
            executable = Path(command[1] if command[0] == 'bun' else command[0])
            name = executable.stem
            if name == 'qualification':
                qualification = dict(controls=9, little_endian=True, round_to_nearest=True)
                if self.fault == 'qualification-type': qualification['controls'] = 9.0
                if self.fault == 'qualification-value': qualification['round_to_nearest'] = False
                output = json.dumps(qualification)
            elif name == 'reference':
                for case in self.cases:
                    stream = self.streams[case['id']]
                    if self.fault == 'native-packet' and case['id'] == 'format-1-aba':
                        stream = make_stream(case, [[(False, [b'\0', b'\x7f', b'\0'])]])
                    (self.work/('reference-'+case['id']+'.tga')).write_bytes(stream[0])
                    output += observation(case, stream)
            elif name.startswith('candidate-'):
                index = int(name.partition('-')[2])
                batch = self.cases[index*P['BATCH_SIZE']:(index+1)*P['BATCH_SIZE']]
                for case in batch:
                    path = self.work/(case['id']+'.dat')
                    if path.read_bytes() != P['SENTINEL']: raise AssertionError('Missing pre-write sentinel')
                    stream = self.streams[case['id']]
                    if self.fault == 'lane-bytes' and case['id'] == 'format-1-aba':
                        stream = make_stream(case, [[(False, [b'\0', b'\x7f', b'\0'])]])
                    path.write_bytes(stream[0]+(b'wrong' if self.fault == 'real-file' else b''))
                    output += observation(case, stream)
                if self.fault == 'missing-record': output = ''
                if self.fault == 'duplicate-record': output += output
            elif name in ('ordinary', 'failure'):
                marker = json.dumps(dict(iterations=100, writes=800))+'\n'
                if name == 'failure':
                    (self.work/'post-open.dat').write_bytes(b'' if self.fault != 'nontruncation' else b'old')
                    output = marker
                else:
                    last = dict(format=8, width=1, height=1)
                    data, _ = make_stream(last, [[(False, [bytes((0, 0, 127, 255))])]])
                    (self.work/'repeated.dat').write_bytes(data)
                    output = marker*3
                if self.fault == 'io-marker': output = output.replace('800', '799')
            else:
                raise AssertionError('Unexpected mocked command: '+str(command))
        return subprocess.CompletedProcess(command, 0, output, '')

    def execute(self, fault=None):
        self.fault = fault
        with patch.dict(G, ROOT=self.root, BUILD=self.build, fixtures=lambda: copy.deepcopy(self.cases), tracked_sources=self.sources, checkout=self.checkout), patch('shutil.which', side_effect=self.which), patch('subprocess.run', side_effect=self.process), redirect_stdout(io.StringIO()):
            P['main'](['--bend-source', str(self.root/'bend'), '--raylib-source', str(self.root/'raylib'), '--build-dir', str(self.destination), '--timeout', '23'])
        return json.loads(self.report_path.read_text())

    def test_complete_mocked_pipeline_preserves_distinct_lanes_timeout_and_provenance(self):
        report = self.execute()
        self.assertIs(report['passed'], True)
        self.assertEqual(report['images'], 25)
        self.assertEqual(self.snapshots, 2)
        self.assertEqual(len(self.checkouts), 4)
        self.assertEqual(self.checkouts[0][1:], ('bend-pin', {'declared': True}))
        self.assertEqual(report['tool_paths'], self.tool_paths)
        self.assertEqual(report['clang_version'], 'mock clang')
        self.assertEqual(report['bun_version'], 'mock-bun')
        self.assertEqual(set(report['lanes']), {'cpu-1', 'cpu-2', 'javascript'})
        self.assertEqual((self.destination/'candidate-0').read_text(), 'stale executable')
        self.assertEqual(Path(report['run_directory']), self.work)
        self.assertTrue(all(Path(path).is_absolute() for path in report['artifacts']))
        for command, kwargs in self.commands:
            self.assertEqual(kwargs['timeout'], 23)
            self.assertNotIn(str(self.destination/'candidate-0'), command)
        for lane, details in report['lanes'].items():
            self.assertIs(details['passed'], True)
            self.assertEqual(sum(batch['images'] for batch in details['batches']), 25)
            self.assertEqual(details['ordinary']['writes']+details['failure']['writes'], 3200)
            for name in ('ordinary', 'failure'):
                self.assertIn(details[name]['retained_file'], report['sealed_artifacts'])
        native = [command for command, _ in self.commands if '--threads' in command]
        self.assertEqual({command[-1] for command in native}, {'1', '2'})
        self.assertTrue(all(command[1:3] == ['--gpu', 'off'] for command in native))
        self.assertTrue(any(command[0] == 'bun' and command[1].endswith('candidate-0.js') for command, _ in self.commands))
        for name in ('qualification.c', 'reference.c', 'candidate-0.bend', 'inputs.json', 'cpu-1-0.stdout', 'cpu-1-0.command.json', 'directory/sentinel'):
            self.assertIn(str(self.work/name), report['sealed_artifacts'])
        for command, kwargs in self.commands:
            if command[0].endswith('/failure') or (command[0] == 'bun' and command[1].endswith('/failure.js')):
                self.assertIs(kwargs['preexec_fn'], P['limit_write_failures'])
            elif '--threads' in command or (command[0] == 'bun' and command[1].endswith('.js')):
                self.assertIs(kwargs['preexec_fn'], P['limit_handles'])

    def test_invalid_native_qualification_and_versions_cannot_certify(self):
        for fault, message in [('qualification-type', 'qualification differs'), ('qualification-value', 'qualification differs'), ('bun-version', 'Bun version differs'), ('missing-output', 'Compiler output missing'), ('native-packet', 'ABA packet rule differs')]:
            with self.subTest(fault=fault):
                self.setUp()
                with self.assertRaisesRegex(ValueError, message): self.execute(fault)
                self.assertIs(json.loads(self.report_path.read_text())['passed'], False)

    def test_exact_lane_bytes_actual_files_full_records_and_io_are_mandatory(self):
        for fault in ('lane-bytes', 'real-file', 'missing-record', 'duplicate-record', 'io-marker', 'nontruncation'):
            with self.subTest(fault=fault):
                self.setUp()
                with self.assertRaises(ValueError): self.execute(fault)
                self.assertIs(json.loads(self.report_path.read_text())['passed'], False)

    def test_final_sources_native_outputs_tools_and_all_sealed_evidence_fail_closed(self):
        for fault in ('library', 'dependency', 'compiler', 'archive', 'cache', 'flags', 'inputs', 'raw-input', 'generated', 'executable', 'stdout', 'command', 'reference-file', 'retained', 'io-retained', 'tool-content', 'missing-sealed', 'final-pin', 'tool-resolution'):
            with self.subTest(fault=fault):
                self.setUp()
                with self.assertRaises(ValueError): self.execute(fault)
                self.assertIs(json.loads(self.report_path.read_text())['passed'], False)


class FormattedTgaSourceInventoryTests(unittest.TestCase):
    def test_dependency_inventory_covers_sources_compilers_and_test_and_detects_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); bend = root/'bend'; ray = root/'raylib'
            required = [root/path for path in ('tools/formatted_tga_export_probe.py', 'tools/byte_probe.py', 'tools/image_export_probe.py', 'tools/image_format_probe.py', 'tools/conformance.py', 'tests/test_formatted_tga_export.py', 'toolchain.json')]
            required += [ray/'src'/path for path in ('rtextures.c', 'raylib.h', 'config.h', 'external/stb_image_write.h', 'external/stb_image.h')]
            required += [bend/'bend2'/('compiler'+suffix) for suffix in ('.ts', '.bend', '.c', '.js', '.h')]
            for path in required: path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'source')
            args = argparse.Namespace(bend_source=bend, raylib_source=ray)
            with patch.dict(G, ROOT=root, source_gate=lambda: {'jonlib.bend': 'library-hash'}):
                before = P['tracked_sources'](args)
                self.assertEqual(set(before['dependencies']), set(map(str, required)))
                self.assertEqual(before['library'], {'jonlib.bend': 'library-hash'})
                for path in required:
                    path.write_bytes(b'changed')
                    self.assertNotEqual(P['tracked_sources'](args), before)
                    path.write_bytes(b'source')
                required[0].unlink()
                with self.assertRaises(FileNotFoundError): P['tracked_sources'](args)


if __name__ == '__main__':
    unittest.main()
