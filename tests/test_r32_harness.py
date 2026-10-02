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
import zlib
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


def png_row(width, height, rgba):
    """Synthetic parser fixture only; native codec parity always uses raylib output."""
    def chunk(kind, payload):
        return struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload))
    raster = b''.join(b'\0'+bytes(rgba[y*width*4:(y+1)*width*4]) for y in range(height))
    return list(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+
                chunk(b'IDAT',zlib.compress(raster))+chunk(b'IEND',b''))


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
        self.assertTrue({'float','colors','points','png','code','raw','memory_png','packed_memory_reject','convert_reject','channel_reject','point_reject','independent','float_reject','pixel_reject'} <= {op['kind'] for op in ops})
        self.assertEqual(sum(op['kind'] == 'channel' for op in ops),len(cases)*6)
        self.assertEqual([op['case'] for op in ops if op['kind'] == 'memory_png'],cases)
        self.assertEqual({op['case']['format'] for op in ops if op['kind'] == 'packed_memory_reject'},{3,5,6})
        self.assertEqual(len(self.probe['schemas'](ops)),88)
        words = set(struct.unpack('<'+'I'*(len(cases[2]['bytes'])//4),bytes(cases[2]['bytes'])))
        self.assertEqual(words,set(self.probe['r32_words']()))
        self.assertTrue({0,0x80000000,1,2,0x007fffff,0x00800000,0x3effffff,0x3f000000,0x3f000001,0x3f800000} <= words)
        self.assertTrue(any(c['height'] > 1 for c in cases))
        self.assertTrue(any(c['width'] & (c['width']-1) for c in cases))

    def test_parser_strictly_checks_counts_bytes_headers_and_retained_owner(self):
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63])
        packed = dict(id='packed-3',width=1,height=1,format=3,bytes=[0x31,0xf8])
        ops = [dict(kind='points',case=case),dict(kind='packed_memory_reject',case=packed),dict(kind='float_reject')]
        shapes = self.probe['schemas'](ops)
        owner = self.probe['image_row'](case)
        packed_owner = self.probe['image_row'](packed)
        rows = [[255,0,0,127],owner,packed_owner,list(struct.pack('<6I',1,1,9,0x80000000,0x80000001,0x3f400000))]
        parse = self.probe['parse_rows']
        self.assertEqual(parse(chunks(rows),shapes),rows)
        invalid = [rows[:-1],rows+[rows[-1]],[None,*rows[1:]],[[0],*rows[1:]],
                   [rows[0],owner[:-1],*rows[2:]],[rows[0],owner[:-1]+[0],*rows[2:]],
                   [rows[0],owner,packed_owner[:-1]+[0],rows[-1]],
                   [rows[0],owner,owner,rows[-1]],
                   [rows[0],owner,packed_owner,list(struct.pack('<6I',1,1,9,0,0x80000001,0x3f400000))]]
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
        png = png_row(1,1,[127,0,0,255])
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

    def test_memory_png_success_is_raw_bytes_and_file_png_is_normalized(self):
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63])
        ops = [dict(kind=kind,case=case) for kind in ('memory_png','png')]
        shapes = self.probe['schemas'](ops)
        rows = [png_row(1,1,case['bytes']),case['bytes'],png_row(1,1,[127,0,0,255]),[127,0,0,255]]
        parse = self.probe['parse_rows'];profiles = self.probe['png_observations']
        self.assertEqual(parse(chunks(rows),shapes),rows)
        observed = profiles(ops,rows)['half']
        self.assertEqual(observed['memory_png']['decoded_rgba'],[0,0,0,63])
        self.assertEqual(observed['png']['decoded_rgba'],[127,0,0,255])
        for changed in (rows[:-1],rows+[rows[-1]],[],[rows[2],rows[3],rows[0],rows[1]]):
            with self.subTest(changed=changed),self.assertRaises(ValueError):
                parse(chunks(changed),shapes)
        for decoded in ([0,0,0],[0,0,0,63,0],[0,0,0,0],[127,0,0,255]):
            with self.subTest(decoded=decoded),self.assertRaises(ValueError):
                parse(chunks([rows[0],decoded,*rows[2:]]),shapes)
        for decoded in ([127,0,0],[127,1,0,255],[127,0,0,63],[128,0,0,255]):
            with self.subTest(decoded=decoded),self.assertRaises(ValueError):
                profiles(ops,[*rows[:3],decoded])
        with self.assertRaisesRegex(ValueError,'PNG observation result count'):
            profiles(ops,rows[:-1])
        # Valid PNG containers with a wrong memory/file interpretation still fail
        # the complete native-byte comparison, even if claimed decode rows match.
        wrong_encoded = [rows[2],rows[1],rows[0],rows[3]]
        self.assertEqual(parse(chunks(wrong_encoded),shapes),wrong_encoded)
        self.assertEqual(self.probe['differences'](rows,wrong_encoded),[0,2])

    def test_png_parser_rejects_truncation_extra_chunks_crc_and_wrong_profile(self):
        png = png_row(1,1,[0,0,0,63]);shape = [dict(kind='png',width=1,height=1)]
        parse = self.probe['parse_rows']
        for changed in (png[:33],png[:-1],png+[0],png+png[-12:],png_row(2,1,[0]*8),
                        png[:29]+[png[29]^1]+png[30:],png[:25]+[2]+png[26:]):
            with self.subTest(changed=changed),self.assertRaises(ValueError):
                parse(chunks([changed]),shape)
        for text in ('[]\n"end"',chunks([png])+'\n"end"',chunks([png]).removesuffix('\n"end"')):
            with self.subTest(text=text),self.assertRaises(ValueError):
                parse(text,shape)
        case = self.probe['fixtures']()[2]
        encoded = png_row(case['width'],case['height'],case['bytes'])
        self.assertGreater(len(encoded),256)
        rows = [encoded,case['bytes']]
        self.assertEqual(parse(chunks(rows),self.probe['schemas']([dict(kind='memory_png',case=case)])),rows)

    def test_exports_are_complete_exact_files_and_count_checked(self):
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63])
        ops = [dict(kind=kind,case=case) for kind in ('memory_png','png','code','raw')]
        rows = [[9,8,7],case['bytes'],[1,2,3],[127,0,0,255],[4,5,6],case['bytes']]
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
                    self.assertIn('memory!(',source)
                else:
                    self.assertIn('J.Image.Formatted.write_png(',source)
                    self.assertIn('J.Image.Formatted.load_raw(',source)
                    self.assertIn('raw_load_rejected',source)
                    self.assertNotIn('normalized!(',source)
                self.assertIn('J.UnsupportedPixelFormat{}',source)
                self.assertIn('Out-of-domain FloatRGB to format8 must retain owner',source)
                self.assertIn('case Some{Done{bytes}}: observe_png(width, height, Some{bytes})',source)
                self.assertLess(source.index('def observe_png('),source.index('def observe_memory('))
                self.assertIn('Packed memory PNG must retain UnsupportedPixelFormat owner',source)
        reference = self.probe['reference_program'](ops,Path('/tmp/r32'))
        self.assertEqual(reference.count('ExportImageToMemory(image,".png",&size)'),3)
        self.assertEqual(reference.count('LoadImageFromMemory(".png",png,size)'),3)
        self.assertEqual(reference.count('MemFree(png)'),3)
        self.assertIn('memcmp(decoded.data,image.data,image.width*image.height*4)',reference)
        packed = [op for op in ops if op['kind'] == 'packed_memory_reject']
        self.assertNotIn('ExportImageToMemory(',self.probe['reference_program'](packed,Path('/tmp/r32')))
        self.assertEqual(reference.count('if(!ExportImage(image,'),6)
        self.assertEqual(reference.count('if(!ExportImageAsCode(image,'),3)
        self.assertNotIn('GetPixelColor(',reference)
        self.assertNotIn('LoadImageRaw(',reference)
        self.assertEqual(len(self.probe['io_shapes'](ops)),11)

    def test_batches_preserve_every_operation_file_and_exactly_two_raw_controls(self):
        cases = self.probe['fixtures']();ops = self.probe['operations'](cases)
        batches = self.probe['operation_batches'](ops)
        self.assertEqual([op for batch in batches for op in batch],ops)
        self.assertTrue(all(1 <= len(batch) <= 8 for batch in batches))
        sources = [self.probe['candidate_program'](batch,'cpu',Path('/tmp/r32'),
                   index == len(batches)-1,cases[0]) for index,batch in enumerate(batches)]
        self.assertEqual(sum(source.count('J.Image.Formatted.load_raw(') for source in sources),2)
        self.assertTrue(all('J.Image.Formatted.load_raw(' not in source for source in sources[:-1]))
        self.assertIn('/tmp/r32/present-format9.raw',sources[-1])
        self.assertIn('/tmp/r32/absent-format9.raw',sources[-1])
        self.assertEqual(sources[-1].count(', 1, 1, 9, 0), raw_load_rejected)'),2)
        self.assertNotIn(', 1, 1, 8, 0), raw_load_rejected)',sources[-1])
        self.assertEqual(sum(len(self.probe['io_shapes'](batch,index == len(batches)-1)) for index,batch in enumerate(batches)),11)
        self.assertEqual(sum(len(self.probe['schemas'](batch)) for batch in batches),88)

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
            self.assertEqual(len(result['lanes']['cpu']['batches'][0]['candidate_program_sha256']),64)
            self.assertEqual(len(result['lanes']['cpu']['batches'][0]['candidate_sha256']),64)
            self.assertTrue(all(len(value) == 64 for value in result['harness_sha256'].values()))

    def test_memory_png_report_records_hashes_and_rejects_source_or_harness_drift(self):
        main = self.probe['main']
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63])
        ops = [dict(kind='memory_png',case=case)]
        rows = [png_row(1,1,case['bytes']),case['bytes']]
        for drift in (None,'source','harness'):
            with self.subTest(drift=drift),tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                source_snapshots = iter([{}, {'jonlib.bend':'b'*64} if drift == 'source' else {}])
                harness_snapshots = iter([{'probe':'a'*64},{'probe':('b' if drift == 'harness' else 'a')*64}])
                def fake_run(command,**kwargs):
                    if Path(command[0]).name == 'reference':
                        return chunks(rows)
                    if Path(command[0]).name.startswith('candidate-cpu-') or (command[0] == 'bun' and len(command) == 2):
                        return chunks(rows+[[1],[1]])
                    return ''
                overrides = dict(BUILD=work,checkout=lambda *a:None,source_gate=lambda:next(source_snapshots),
                                 harness_hashes=lambda:next(harness_snapshots),run=fake_run,
                                 fixtures=lambda:[case],operations=lambda c:ops)
                with patch.dict(main.__globals__,overrides),patch('sys.argv',['probe','--bend-source',str(work/'bend'),'--raylib-source',str(work/'raylib')]),patch('subprocess.run',side_effect=AssertionError('Unexpected subprocess')),redirect_stdout(io.StringIO()):
                    if drift:
                        with self.assertRaisesRegex(ValueError,'source/harness changed'):
                            main()
                    else:
                        main()
                report = json.loads((work/'r32-image-probe/results.json').read_text())
                self.assertEqual(report['passed'],drift is None)
                self.assertEqual(report['memory_png_images'],1)
                self.assertEqual(report['png_profiles']['half']['memory_png']['decoded_bytes'],4)
                for lane in ('cpu','javascript'):
                    self.assertEqual(report['lanes'][lane]['result_count'],4)
                    self.assertEqual(len(report['lanes'][lane]['batches'][0]['candidate_program_sha256']),64)
                    self.assertEqual(len(report['lanes'][lane]['candidate_sha256']),64)
                self.assertEqual(len(report['reference_program_sha256']),64)
                self.assertEqual(len(report['reference_sha256']),64)

    def test_bad_batch_count_cannot_be_cancelled_by_another_batch_or_stale_binary(self):
        main = self.probe['main']
        case = dict(id='half',width=1,height=1,bytes=[0,0,0,63])
        ops = [dict(kind='memory_png',case=case)]*2
        rows = [png_row(1,1,case['bytes']),case['bytes']]
        for first_rows in (rows[:-1],rows+[case['bytes']]):
            with self.subTest(count=len(first_rows)),tempfile.TemporaryDirectory() as directory:
                work = Path(directory);probe = work/'r32-image-probe';probe.mkdir()
                stale = probe/'candidate-cpu-0';stale.write_text('stale executable')
                commands = []
                def fake_run(command,**kwargs):
                    commands.append(command)
                    if Path(command[0]).name == 'reference':
                        return chunks(rows*2)
                    if command[0] == 'bun' and '-o' in command:
                        self.assertFalse(stale.exists())
                    if Path(command[0]).name == 'candidate-cpu-0':
                        return chunks(first_rows)
                    return ''
                overrides = dict(BUILD=work,BATCH_OPERATIONS=1,checkout=lambda *a:None,source_gate=lambda:{},
                                 run=fake_run,fixtures=lambda:[case],operations=lambda c:ops)
                with patch.dict(main.__globals__,overrides),patch('sys.argv',['probe','--bend-source',str(work/'bend'),'--raylib-source',str(work/'raylib')]),patch('subprocess.run',side_effect=AssertionError('Unexpected subprocess')):
                    with self.assertRaisesRegex(ValueError,'result count'):
                        main()
                report = json.loads((probe/'results.json').read_text())
                self.assertFalse(report['passed'])
                self.assertEqual(len(report['lanes']['cpu']['batches']),1)
                self.assertFalse(any('candidate-cpu-1' in str(part) for command in commands for part in command))


if __name__ == '__main__':
    unittest.main()
