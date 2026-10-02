"""Python-only guardrails for R32 parity probes; no compiler or native execution."""
import copy
import io
import json
from pathlib import Path
import random
import runpy
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from tools.conformance import ROOT


def load_probe(name):
    with patch('sys.path',[str(ROOT/'tools'),*sys.path]):
        return runpy.run_path(str(ROOT/'tools'/name))


def chunks(rows):
    lines = []
    for row in rows:
        if row is None:
            lines.append('null')
            continue
        lines.extend(json.dumps(row[i:i+256]) for i in range(0,len(row),256))
        lines.append('"end"')
    return '\n'.join(lines)


class ImageFormatR32HarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.probe = load_probe('image_format_probe.py')

    def test_all_64_pairs_and_historical_seven_format_cases_survive(self):
        cases = self.probe['cases']()
        pairs = {(c['source'],c['targets'][0]) for c in cases if len(c['targets']) == 1 and c['targets'][0] and not c['bridge']}
        self.assertEqual(pairs,{(a,b) for a in range(1,9) for b in range(1,9)})
        rng = random.Random(0xF07A7)
        for source,bpp in list(self.probe['BYTES_PER_PIXEL'].items())[:7]:
            data = [rng.randrange(256) for _ in range(12*bpp)]
            data[:bpp] = [0]*bpp
            data[bpp:2*bpp] = [255]*bpp
            data[2*bpp:3*bpp] = [1]+[0]*(bpp-1)
            if source == 7:
                data[12:24] = [127,128,129,49,17,63,201,50,17,63,201,51]
            old = [dict(width=4,height=3,source=source,bytes=data,targets=[target],bridge=False) for target in range(8)]
            old += [dict(old[0],targets=[3,1,2,5,6,4,7][:count]) for count in range(2,8)]
            old.append(dict(old[0],bridge=True))
            if source in (6,7):
                old += [dict(old[0],targets=[6,5,7][:count]) for count in range(2,4)]
            for case in old:
                with self.subTest(source=source,targets=case['targets'],bridge=case['bridge']):
                    self.assertIn(case,cases)

    def test_r32_samples_cover_domain_and_both_sides_of_every_threshold(self):
        words = self.probe['r32_words']()
        self.assertEqual(words,sorted(set(words)))
        self.assertLessEqual(len(words),4096)
        self.assertTrue({0,0x80000000,1,0x007fffff,0x00800000,0x3f7fffff,0x3f800000} <= set(words))
        self.assertTrue(all(word == 0x80000000 or 0 <= word <= 0x3f800000 for word in words))
        for limit,offset in ((255,0),(31,.5),(63,.5),(15,.5)):
            for level in range(1 if offset == 0 else 0,limit):
                center = struct.unpack('<I',struct.pack('<f',(level+offset)/limit))[0]
                self.assertTrue({center-1,center,center+1} <= set(words))

    def test_large_import_is_compact_generated_source_and_exact_noop(self):
        case = next(c for c in self.probe['cases']() if 'repeat_words' in c)
        self.assertGreaterEqual(case['width']*case['height'],33024)
        self.assertLessEqual(max(case['width'],case['height']),4096)
        self.assertEqual(len(case['bytes']),4*case['width']*case['height'])
        self.assertEqual(case['targets'],[0,8])
        self.assertEqual(case['bytes'],self.probe['word_bytes'](case['repeat_words']*case['repeat_count']))
        self.assertLess(len(self.probe['input_expression'](case)),160)
        self.assertLess(len(self.probe['reference_program']([case])),1600)
        self.assertIn('repeat_bytes(8256n',self.probe['candidate_program']([case],[],'cpu'))

    def test_luminance_discriminator_uses_native_oracle_without_modelled_bits(self):
        cases = self.probe['cases']()
        discriminator = dict(width=1,height=1,source=4,bytes=[0,17,51],targets=[8],bridge=False)
        self.assertIn(discriminator,cases)
        source = self.probe['reference_program']([discriminator])
        self.assertIn('ImageFormat(&image,8)',source)
        self.assertNotIn('0x3d7dadd0',source)
        self.assertNotIn('fmaf',source)

    def test_invalid_factories_cover_bad_samples_bytes_shape_and_bounds(self):
        controls = self.probe['invalid_cases']()
        invalid = {struct.unpack('<I',bytes(c['bytes']))[0] for c in controls if len(c['bytes']) == 4 and max(c['bytes']) <= 255 and c['source'] == 8 and c['width'] == c['height'] == 1}
        self.assertTrue({0x80000001,0x3f800001,0x7f800000,0xff800000,0x7fc00000,0x7f800001} <= invalid)
        self.assertTrue(any(c['source'] == 9 and c['bytes'] == list(struct.pack('<3I',*[0x3f000000]*3)) for c in controls))
        self.assertTrue(any(c['bytes'] == [0,0,0,256] for c in controls))
        self.assertTrue(any(c['width'] == 4097 for c in controls))
        self.assertTrue(any(c['height'] == 4097 for c in controls))
        self.assertTrue(any(c['width'] == 3 and c['bytes'][-4:] == [1,0,128,63] for c in controls))

    def test_format_parser_rejects_missing_extra_and_malformed_rows(self):
        case = dict(width=1,height=1,source=8,bytes=[0,0,0,128],targets=[0,8],bridge=False)
        row = dict(width=1,height=1,format=8,bytes=case['bytes'])
        reject = dict(rejected=True)
        parse = self.probe['parse_rows']
        encode = lambda rows:'\n'.join(map(json.dumps,rows))
        self.assertEqual(parse(encode([row,reject]),[case],[{}]),[row,reject])
        invalid = [[],[row],[row,reject,reject],[dict(row,width=True),reject],
                   [dict(row,format=9),reject],[dict(row,bytes=[0,0,0]),reject],
                   [dict(row,bytes=[0,0,0,256]),reject],[dict(row,bytes=[0,0,0,False]),reject],
                   [dict(row,bytes=[0,0,0,128.0]),reject],[dict(row,bytes=[0,0,0,0]),reject],
                   [dict(row,extra=True),reject],[row,dict(rejected=1)],[row,dict(rejected=False)],
                   [row,dict(rejected=True,extra=True)]]
        for rows in invalid:
            with self.subTest(rows=rows),self.assertRaises(ValueError):
                parse(encode(rows),[case],[{}])
        with self.assertRaisesRegex(ValueError,'comparison result count'):
            self.probe['differences']([row],[row,row])

    def test_chunked_transport_reassembles_exact_bytes_and_rejects_broken_framing(self):
        case = dict(width=1,height=1,source=8,bytes=[0,0,0,128],targets=[0,8],bridge=False)
        header = dict(width=1,height=1,format=8,chunked=True)
        row = dict(width=1,height=1,format=8,bytes=case['bytes'])
        encode = lambda rows:'\n'.join(map(json.dumps,rows))
        parse = self.probe['parse_rows']
        valid = [header,[0,0],[0,128],'end']
        self.assertEqual(parse(encode(valid),[case]),[row])
        for values in ([header,[0,0,0,128]], [header,[],[0,0,0,128],'end'],
                       [header,[0,0,0,True],'end'], [header,[0,0,0,128],row,'end'],
                       [dict(header,chunked=1),[0,0,0,128],'end'],valid+['end'],
                       [header,[0,0,0,128,1],'end']):
            with self.subTest(values=values),self.assertRaises(ValueError):
                parse(encode(values),[case])

    def test_format_reference_shape_tracks_chains_and_bridge(self):
        case = dict(width=1,height=1,source=8,bytes=[0,0,0,63],targets=[0,3,8,0],bridge=False)
        self.assertEqual(self.probe['output_format'](case),8)
        self.assertEqual(self.probe['output_format'](dict(case,bridge=True)),7)
        self.assertEqual(self.probe['differences']([[1]],[[2]]),[dict(case=0,reference=[1],candidate=[2])])

    def test_format_incomplete_candidate_cannot_pass_and_stale_report_is_cleared(self):
        main = self.probe['main']
        case = dict(width=1,height=1,source=8,bytes=[0,0,0,63],targets=[0],bridge=False)
        row = dict(width=1,height=1,format=8,bytes=case['bytes'])
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory);report = work/'image-format-probe/results.json'
            report.parent.mkdir();report.write_text('{"passed":true}')
            def fake_run(command,**kwargs):
                if Path(command[0]).name == 'reference':
                    return json.dumps(row)
                return ''
            overrides = dict(BUILD=work,checkout=lambda *a:None,source_gate=lambda:{},run=fake_run,cases=lambda:[case],invalid_cases=lambda:[])
            with patch.dict(main.__globals__,overrides),patch('sys.argv',['probe','--bend-source',str(work/'bend'),'--raylib-source',str(work/'raylib')]),patch('subprocess.run',side_effect=AssertionError('Unexpected subprocess')):
                with self.assertRaisesRegex(ValueError,'result count'):
                    main()
            result = json.loads(report.read_text())
            self.assertFalse(result['passed'])
            self.assertEqual(len(result['reference_program_sha256']),64)
            self.assertEqual(len(result['lanes']['cpu']['candidate_program_sha256']),64)
            self.assertTrue(all(len(value) == 64 for value in result['harness_sha256'].values()))


class R32ImageHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.probe = load_probe('r32_image_probe.py')

    def test_fixture_and_operation_scope(self):
        cases = self.probe['fixtures']();ops = self.probe['operations'](cases)
        self.assertTrue(all(len(c['bytes']) == c['width']*c['height']*4 and max(c['width'],c['height']) <= 4096 for c in cases))
        self.assertEqual({op['selected'] for op in ops if op['kind'] == 'channel'},{-32767,0,1,2,3,32767})
        self.assertTrue({'float','colors','points','png','code','raw','memory_reject','convert_reject','channel_reject','point_reject','independent','float_reject','pixel_reject'} <= {op['kind'] for op in ops})
        self.assertEqual(sum(op['kind'] == 'channel' for op in ops),len(cases)*6)

    def test_parser_strictly_checks_counts_bytes_headers_and_retained_owner(self):
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63])
        ops = [dict(kind='points',case=case),dict(kind='memory_reject',case=case),dict(kind='float_reject')]
        shapes = self.probe['schemas'](ops)
        owner = self.probe['image_row'](case)
        rows = [[255,0,0,127],owner,owner,list(struct.pack('<6I',1,1,9,0x80000000,1,0x3f400000))]
        parse = self.probe['parse_rows']
        self.assertEqual(parse(chunks(rows),shapes),rows)
        invalid = [rows[:-1],rows+[rows[-1]],[None,*rows[1:]],[[0],*rows[1:]],
                   [rows[0],owner[:-1],*rows[2:]],[rows[0],owner[:-1]+[0],*rows[2:]],
                   [rows[0],owner,owner,list(struct.pack('<6I',1,1,9,0,1,0x3f400000))]]
        for values in invalid:
            with self.subTest(values=values),self.assertRaises(ValueError):
                parse(chunks(values),shapes)
        for bad in ('[true]\n"end"','[256]\n"end"','[0.0]\n"end"','[1]'):
            with self.subTest(bad=bad),self.assertRaises(ValueError):
                parse(bad,[dict(kind='exact',value=[1])])
        with self.assertRaisesRegex(ValueError,'comparison result count'):
            self.probe['differences']([[1]],[[1],[1]])

    def test_normalized_png_code_and_gray_shapes_are_checked(self):
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63])
        ops = [dict(kind='float',case=case),dict(kind='channel',case=case,selected=3),dict(kind='png',case=case),dict(kind='code',case=case)]
        shapes = self.probe['schemas'](ops)
        png = list(b'\x89PNG\r\n\x1a\n'+struct.pack('>I4sII',13,b'IHDR',1,1)+bytes(9))
        rows = [list(struct.pack('<6I',1,1,9,0x3f000000,0,0)),self.probe['image_row'](case),
                list(struct.pack('<III',1,1,1))+[127],png,[127,0,0,255],list(b'#define HALF_FORMAT   8\n')]
        parse = self.probe['parse_rows']
        self.assertEqual(parse(chunks(rows),shapes),rows)
        for index,changed in [(0,rows[0][:-1]),(2,list(struct.pack('<III',1,1,8))+[127]),
                              (3,png[:16]+list(struct.pack('>II',2,1))+png[24:]),
                              (4,[127,0,0]),(5,list(b'#define HALF_FORMAT   9\n'))]:
            bad = copy.deepcopy(rows);bad[index] = changed
            with self.subTest(index=index),self.assertRaises(ValueError):
                parse(chunks(bad),shapes)

    def test_exports_are_complete_exact_files_and_count_checked(self):
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63])
        ops = [dict(kind=kind,case=case) for kind in ('png','code','raw')]
        rows = [[1,2,3],[127,0,0,255],[4,5,6],case['bytes']]
        files = self.probe['file_expectations'](ops,rows)
        self.assertEqual(files,{'half.png':bytes([1,2,3]),'half.h':bytes([4,5,6]),'half.raw':bytes(case['bytes'])})
        with self.assertRaisesRegex(ValueError,'file reference result count'):
            self.probe['file_expectations'](ops,rows[:-1])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for name,data in files.items():
                (path/name).write_bytes(data)
            self.probe['verify_files'](path,files)
            for name,data in files.items():
                for changed in (data[:-1],data+b'extra'):
                    (path/name).write_bytes(changed)
                    with self.subTest(name=name,changed=changed),self.assertRaisesRegex(ValueError,'Complete R32 exported file differs'):
                        self.probe['verify_files'](path,files)
                (path/name).write_bytes(data)
            self.probe['prepare_files'](path,files)
            self.assertTrue(all(not (path/name).exists() for name in files))
            with self.assertRaises(ValueError):
                self.probe['verify_files'](path,files)

    def test_metal_has_only_pure_operations_cpu_js_have_requested_file_io(self):
        ops = self.probe['operations'](self.probe['fixtures']())
        for lane in ('cpu','javascript','metal'):
            source = self.probe['candidate_program'](ops,lane,Path('/tmp/r32'))
            with self.subTest(lane=lane):
                if lane == 'metal':
                    self.assertNotIn('write_png(',source)
                    self.assertNotIn('write_raw(',source)
                    self.assertNotIn('write_code(',source)
                    self.assertNotIn('load_raw(',source)
                    self.assertIn('normalized!(',source)
                    self.assertIn('independent!(',source)
                else:
                    self.assertIn('J.Image.Formatted.write_png(',source)
                    self.assertIn('J.Image.Formatted.load_raw(',source)
                    self.assertIn('raw_load_rejected',source)
                    self.assertNotIn('normalized!(',source)
                self.assertIn('J.UnsupportedPixelFormat{}',source)
                self.assertIn('FloatRGB to format8 expanded beyond this slice',source)
        reference = self.probe['reference_program'](ops,Path('/tmp/r32'))
        self.assertNotIn('ExportImageToMemory(',reference)
        self.assertNotIn('GetPixelColor(',reference)
        self.assertNotIn('LoadImageRaw(',reference)
        self.assertEqual(len(self.probe['io_shapes'](ops)),11)

    def test_stale_success_is_invalidated_before_provenance_for_both_probes(self):
        for name,directory_name in (('image_format_probe.py','image-format-probe'),('r32_image_probe.py','r32-image-probe')):
            main = load_probe(name)['main']
            with tempfile.TemporaryDirectory() as directory:
                work = Path(directory);report = work/directory_name/'results.json'
                report.parent.mkdir();report.write_text('{"passed":true}')
                with patch.dict(main.__globals__,BUILD=work,checkout=lambda *a:(_ for _ in ()).throw(ValueError('forced provenance failure'))),patch('sys.argv',['probe','--bend-source',str(work/'bend'),'--raylib-source',str(work/'raylib')]),patch('subprocess.run',side_effect=AssertionError('Unexpected subprocess')):
                    with self.assertRaisesRegex(ValueError,'forced provenance failure'):
                        main()
                self.assertEqual(json.loads(report.read_text()),dict(passed=False))

    def test_incomplete_r32_candidate_cannot_pass_after_native_output(self):
        main = self.probe['main']
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63]);ops = [dict(kind='raw',case=case)]
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            def fake_run(command,**kwargs):
                if Path(command[0]).name == 'reference':
                    (work/'r32-image-probe/reference-files/half.raw').write_bytes(bytes(case['bytes']))
                    return chunks([case['bytes']])
                return ''
            overrides = dict(BUILD=work,checkout=lambda *a:None,source_gate=lambda:{},run=fake_run,fixtures=lambda:[case],operations=lambda c:ops)
            with patch.dict(main.__globals__,overrides),patch('sys.argv',['probe','--bend-source',str(work/'bend'),'--raylib-source',str(work/'raylib')]),patch('subprocess.run',side_effect=AssertionError('Unexpected subprocess')):
                with self.assertRaisesRegex(ValueError,'result count'):
                    main()
            result = json.loads((work/'r32-image-probe/results.json').read_text())
            self.assertFalse(result['passed'])
            self.assertEqual(len(result['reference_program_sha256']),64)
            self.assertEqual(len(result['lanes']['cpu']['candidate_program_sha256']),64)
            self.assertTrue(all(len(value) == 64 for value in result['harness_sha256'].values()))


if __name__ == '__main__':
    unittest.main()
