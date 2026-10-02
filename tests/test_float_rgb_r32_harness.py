"""Failure-detection tests for the bounded FloatRGB/R32 native gate."""
import copy
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from test_r32_harness import chunks, load_probe


class FloatRGBR32HarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.probe = load_probe('float_rgb_r32_probe.py')

    def test_fixtures_preserve_domains_shapes_and_complete_large_traversal(self):
        cases = self.probe['fixtures']()
        self.assertEqual(len(cases),17)
        names = {c['name']:c for c in cases}
        self.assertEqual(len(names['signed-zero-corners']['bytes']),8*12)
        large = names['large-full-traversal']
        self.assertEqual((large['width'],large['height']),(256,129))
        self.assertEqual(large['bytes'],self.probe['word_bytes'](large['repeat_words']*large['repeat_count']))
        self.assertLess(len(self.probe['candidate_program']([large])),15000)
        for case in cases:
            bpp = 12 if case['source']==9 else 4
            self.assertEqual(len(case['bytes']),case['width']*case['height']*bpp)
            words = struct.unpack('<'+'I'*(len(case['bytes'])//4),bytes(case['bytes']))
            self.assertTrue(all(word<=0x3f800000 or word==0x80000000 for word in words))
        self.assertEqual(names['8-9-8']['targets'],[9,8])
        self.assertEqual(sum(c['targets']==[8,9] for c in cases),4)

    def test_controls_cover_each_component_and_early_middle_final_without_nan_bridge(self):
        controls = self.probe['controls']()
        regular = [c for c in controls if c.get('reject')]
        self.assertEqual(len(regular),len(self.probe['INVALID_WORDS'])*9+3)
        self.assertEqual({c['targets'][0] for c in regular},{0,8,9,0xffffffff})
        for word in self.probe['INVALID_WORDS']:
            for component in range(3):
                for position in range(3):
                    c = next(c for c in regular if c['name']==f'reject-{word:08x}-component{component}-position{position}')
                    self.assertEqual(struct.unpack_from('<I',bytes(c['bytes']),12*position+4*component)[0],word)
        nans = [c for c in controls if 'nan' in c]
        self.assertEqual(len(nans),27)
        source = self.probe['candidate_program'](nans)
        self.assertNotIn('J.Image.FloatRGB.from_bytes(3,',source)
        self.assertIn('nan_control(',source)
        self.assertIn('F32.bits(a)',source)
        self.assertIn('J.Image.FloatRGB.copy(image)',source)

    def test_strict_counts_framing_types_dimensions_format_payload_and_owners(self):
        case = self.probe['fixture']('one',[(0,0,0)])
        row = list(struct.pack('<IIII',1,1,8,0))
        shapes = self.probe['shapes']([case]);parse = self.probe['parse_rows']
        self.assertEqual(parse(chunks([row]),shapes),[row])
        for rows in ([],[row,row],[None],[row[:-1]],[row+[0]],[[True]+row[1:]],
                     [list(struct.pack('<IIII',2,1,8,0))],[list(struct.pack('<IIII',1,1,9,0))],[list(struct.pack('<IIII',1,1,8,0x3f800001))]):
            with self.subTest(rows=rows),self.assertRaises(ValueError):parse(chunks(rows),shapes)
        for text in ('[]\n"end"',chunks([row])+'\n"end"',chunks([row]).removesuffix('\n"end"'),'null\n"end"'):
            with self.subTest(text=text),self.assertRaises(ValueError):parse(text,shapes)
        control = self.probe['controls']()[0];owner_shapes = self.probe['shapes']([control]);rows = [s['exact'] for s in owner_shapes]
        self.assertEqual(parse(chunks(rows),owner_shapes),rows)
        for index in (0,1):
            bad = copy.deepcopy(rows);bad[index][-1]^=1
            with self.assertRaises(ValueError):parse(chunks(bad),owner_shapes)
        with self.assertRaisesRegex(ValueError,'comparison count'):self.probe['differences']([row],[])
        self.assertEqual(self.probe['differences']([row],[row[:-1]]),[0])

    def test_batches_preserve_every_operation_and_observation(self):
        ops = self.probe['fixtures']()+self.probe['controls']()
        batches = self.probe['batches'](ops)
        self.assertEqual([op for batch in batches for op in batch],ops)
        self.assertTrue(all(1<=len(batch)<=8 for batch in batches))
        self.assertEqual(sum(len(self.probe['shapes'](batch)) for batch in batches),len(self.probe['shapes'](ops)))
        reference = self.probe['reference_program'](self.probe['fixtures']())
        self.assertIn('ImageFormat(&image,8);',reference)
        self.assertIn('ImageFormat(&image,9);',reference)
        self.assertNotIn('fmaf(',reference)

    def test_stale_success_invalidated_before_source_provenance(self):
        main = self.probe['main']
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory);report = work/'float-rgb-r32-probe/results.json';report.parent.mkdir();report.write_text('{"passed":true}')
            with patch.dict(main.__globals__,BUILD=work,checkout=lambda *a:(_ for _ in ()).throw(ValueError('bad provenance'))),patch('sys.argv',['probe','--bend-source',directory,'--raylib-source',directory]):
                with self.assertRaisesRegex(ValueError,'bad provenance'):main()
            self.assertEqual(json.loads(report.read_text()),{'passed':False})

    def test_qualification_fails_closed_on_wrong_or_incomplete_native_profiles(self):
        qualify = self.probe['qualify_native'];case = self.probe['fixture']('one',[(0,0,0)])
        good = dict(pixels=1,uncontracted_mismatches=0,fused_differences=1)
        for result in (good,dict(good,pixels=0),dict(good,pixels=True),dict(good,fused_differences=0),dict(good,uncontracted_mismatches=1),{}):
            with tempfile.TemporaryDirectory() as directory:
                work = Path(directory);(work/'qualification').write_text('stale');(work/'qualification.stdout').write_text('stale')
                def fake_run(command,**kwargs):
                    if command[0]=='clang':
                        self.assertFalse((work/'qualification').exists());self.assertFalse((work/'qualification.stdout').exists());return ''
                    return json.dumps(result)
                with patch.dict(qualify.__globals__,run=fake_run):
                    if result is good:
                        observed = qualify([case],work,work,work/'archive');self.assertEqual(observed['pixels'],1)
                    else:
                        with self.assertRaises(ValueError):qualify([case],work,work,work/'archive')

    def test_batch_count_failure_cannot_cancel_or_reuse_stale_executables(self):
        main = self.probe['main'];case = self.probe['fixture']('one',[(0,0,0)]);row = list(struct.pack('<IIII',1,1,8,0))
        for bad in ([],[row,row]):
            with tempfile.TemporaryDirectory() as directory:
                work = Path(directory);probe = work/'float-rgb-r32-probe';probe.mkdir();stale = probe/'candidate-cpu-0';stale.write_text('stale')
                archive = work/'archive';archive.write_bytes(b'archive');commands=[]
                def fake_run(command,**kwargs):
                    commands.append(command)
                    if Path(command[0]).name=='reference':return chunks([row,row])
                    if command[0]=='bun' and '-o' in command:self.assertFalse(stale.exists())
                    if Path(command[0]).name=='candidate-cpu-0':return chunks(bad)
                    return ''
                overrides = dict(BUILD=work,BATCH_OPERATIONS=1,checkout=lambda *a:None,source_gate=lambda:{},run=fake_run,
                                 fixtures=lambda:[case,case],controls=lambda:[],qualify_native=lambda *a:{},
                                 native_build=lambda *a:(archive,{'archive_sha256':self.probe['digest'](b'archive')}))
                with patch.dict(main.__globals__,overrides),patch('sys.argv',['probe','--bend-source',directory,'--raylib-source',directory]):
                    with self.assertRaisesRegex(ValueError,'result count'):main()
                self.assertFalse(json.loads((probe/'results.json').read_text())['passed'])
                self.assertTrue((probe/'cpu-0.stdout').is_file())
                self.assertFalse(any('candidate-cpu-1' in str(part) for command in commands for part in command))

    def test_old_probes_keep_existing_scope_and_use_genuine_out_of_domain_control(self):
        previous = load_probe('float_rgb_formats_probe.py');cases,controls = previous['fixtures']()
        self.assertEqual(len(cases),10);self.assertEqual(len(controls),3)
        self.assertEqual([c['target'] for c in cases[:7]],list(range(1,8)))
        self.assertEqual([c['target'] for c in controls],[0,9,3])
        self.assertEqual(cases[-1]['target'],8)
        consumer = load_probe('r32_image_probe.py');op = [dict(kind='float_reject')]
        row = consumer['schemas'](op)[0]['value']
        self.assertEqual(struct.unpack('<6I',bytes(row)),(1,1,9,0x80000000,0x80000001,0x3f400000))
        self.assertIn('H.float_bits(2147483649)',consumer['candidate_program'](op,'cpu',Path('/tmp/test')))
        self.assertIn('0x80000001',consumer['reference_program'](op,Path('/tmp/test')))


if __name__=='__main__':
    unittest.main()
