"""Strict R32 RAW oracle, domain, framing, fixture and resource guardrails."""
import copy
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from test_r32_harness import chunks, load_probe


class R32RawHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.probe = load_probe('r32_raw_file_probe.py')

    def test_native_cases_cover_exact_storage_headers_thresholds_and_large_input(self):
        cases,controls = self.probe['fixture_specs']()
        self.assertEqual(len(cases),22)
        self.assertEqual(sum(not c['error'] for c in cases),16)
        for case in cases:
            if case['error']:continue
            size = case['width']*case['height']*4
            offset = case['header'] if case['header'] and case['header']+size <= len(case['data']) else 0
            self.assertEqual(case['selected'],case['data'][offset:offset+size])
            self.assertEqual(case['format'],8)
        words = {struct.unpack('<I',bytes(cases[5]['selected'][i:i+4]))[0] for i in range(0,48,4)}
        self.assertTrue({0,0x80000000,1,0x007fffff,0x00800000,0x3f7fffff,0x3f800000} <= words)
        threshold = next(c for c in cases if c['name']=='thresholds-plain')
        self.assertEqual(threshold['selected'],self.probe['word_bytes'](self.probe['r32_words']()))
        large = next(c for c in cases if c['name']=='large-tail-validation')
        self.assertEqual(large['width']*large['height'],33024)
        invalid = next(c for c in controls if c['name']=='invalid-large-last')
        self.assertEqual(invalid['data'][:-4],large['data'][:-4])
        self.assertEqual(invalid['data'][-4:],list(struct.pack('<I',0x3f800001)))

    def test_invalid_samples_reject_both_ends_and_do_not_run_native_casts(self):
        cases,controls = self.probe['fixture_specs']()
        self.assertEqual(sum(c['error']=='samples' for c in controls),31)
        for word in self.probe['INVALID_WORDS']:
            for position in ('first','last'):
                case = next(c for c in controls if c['name']==f'invalid-{word:08x}-{position}')
                self.assertEqual(case['error'],'samples')
                offset = 0 if position=='first' else -4
                self.assertEqual(case['data'][offset:offset+4 if offset==0 else None],list(struct.pack('<I',word)))
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);self.materialize_paths(cases,controls,work)
            with patch.dict(self.probe['reference_program'].__globals__,ROOT=work.parent):
                source=self.probe['reference_program'](cases,work)
            self.assertIn('LoadImageRaw(',source)
            self.assertIn('SaveFileData(',source)
            self.assertNotIn('ExportImage(',source)
            self.assertNotIn('LoadImageColors(',source)
            self.assertNotIn('invalid-',source)
            self.assertIn('image.mipmaps!=1',source)

    @staticmethod
    def materialize_paths(cases,controls,work):
        for case in cases+controls:case['path']=str(work/(case['name']+'.raw'))

    def test_format9_controls_have_valid_present_and_genuinely_absent_inputs(self):
        cases,controls = self.probe['fixture_specs']()
        present = next(c for c in controls if c['name']=='format9-present')
        missing = next(c for c in controls if c['name']=='format9-missing')
        self.assertEqual(present['data'],list(struct.pack('<fff',.25,.5,.75)))
        self.assertEqual(present['error'],missing['error'])
        self.assertEqual(present['error'],'request')
        self.assertIsNone(missing['data'])

    def test_parser_rejects_missing_extra_malformed_and_wrong_typed_failures(self):
        cases,controls=self.probe['fixture_specs']();case=cases[0];control=controls[0]
        row=self.probe['image_row'](case);parse=self.probe['parse_rows']
        self.assertEqual(parse(chunks([row,[5],[1]]),[case,control],closure=True),[row,[5],[1]])
        self.assertEqual(parse(chunks([row,None]),[case,cases[-1]],native=True),[row,None])
        for rows in ([row,[5]],[row,[5],[1],[1]],[row[:-1],[5],[1]],[[*row[:8],9,*row[9:]],[5],[1]],
                     [row,[3],[1]],[row,[5],[0]],[row+[0],[5],[1]],[None,[5],[1]]):
            with self.subTest(rows=rows),self.assertRaises(ValueError):parse(chunks(rows),[case,control],closure=True)
        with self.assertRaises(ValueError):parse('[true]\n"end"',[control])
        with self.assertRaises(ValueError):parse('[5]',[control])

    def test_complete_files_and_failed_outputs_are_checked(self):
        cases,controls=self.probe['fixture_specs']();chosen=[cases[0],controls[0]]
        verify=self.probe['verify_files']
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);path=work/('cpu-'+chosen[0]['name']+'.raw')
            for content in (None,bytes(chosen[0]['selected'])[:-1],bytes(chosen[0]['selected'])+b'!'):
                if content is not None:path.write_bytes(content)
                with self.assertRaises(ValueError):verify(work,chosen,'cpu')
            path.write_bytes(bytes(chosen[0]['selected']));verify(work,chosen,'cpu')
            (work/('cpu-'+chosen[1]['name']+'.raw')).write_bytes(b'')
            with self.assertRaisesRegex(ValueError,'Failed R32 RAW'):verify(work,chosen,'cpu')
            self.probe['clear_outputs'](work,chosen,'cpu')
            self.assertEqual(list(work.iterdir()),[])

    def test_program_serializes_bounded_chunks_and_checks_all_closure_paths(self):
        cases,controls=self.probe['fixture_specs']()
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);self.materialize_paths(cases,controls,work)
            with patch.dict(self.probe['candidate_program'].__globals__,ROOT=work.parent):
                source=self.probe['candidate_program'](cases,controls,work,'cpu')
        self.assertLess(len(source),70000)
        self.assertIn('chunked(~q, bytes, 0',source)
        self.assertIn('closure_loop(100n)',source)
        closure=source[source.index('def closure_loop'):source.index('def main')]
        for code in (0,1,3,4,5):self.assertIn(f'required({code})',closure)
        self.assertEqual(closure.count('J.Image.Formatted.load_raw('),5)
        self.assertEqual(source.count('J.Image.Formatted.load_raw('),len(cases)+len(controls)+6)
        self.assertIn('case J.InvalidRawSamples{}: 5',source)
        self.assertLess(source.index('def reloaded('),source.index('def written('))

    def test_sparse_input_selects_negative_zero_without_materializing_ignored_data(self):
        _,controls=self.probe['fixture_specs']()
        case=copy.deepcopy(next(c for c in controls if c['name']=='bounded-sparse-header-tail'))
        self.assertEqual(case['size'],64*1024*1024)
        self.assertEqual(case['header'],32*1024*1024)
        self.assertEqual(case['selected'],[0,0,0,128])
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);work=root/'inputs';work.mkdir()
            with patch.dict(self.probe['prepare_inputs'].__globals__,ROOT=root):
                self.probe['prepare_inputs'](work,[case],[])
            path=root/case['path']
            self.assertEqual(path.stat().st_size,case['size'])
            with path.open('rb') as file:
                self.assertEqual(file.read(4),b'\0'*4)
                file.seek(case['header']);self.assertEqual(file.read(4),b'\0\0\0\x80')
                file.seek(-4,2);self.assertEqual(file.read(4),b'\0'*4)
        self.assertEqual(self.probe['MAX_RUNTIME_RSS'],256*1024*1024)
        compile(self.probe['RESOURCE_RUNNER'],'resource-runner','exec')
        self.assertIn('resource.RUSAGE_CHILDREN',self.probe['RESOURCE_RUNNER'])
        self.assertIn('subprocess.run(sys.argv[2:],timeout=230)',self.probe['RESOURCE_RUNNER'])

    def test_ci_runs_gate_and_retains_replay_artifacts_without_sparse_raw_files(self):
        workflow=(self.probe['ROOT']/'.github/workflows/conformance.yml').read_text()
        self.assertIn('python3 tools/r32_raw_file_probe.py',workflow)
        self.assertLess(workflow.index('python3 tools/r32_raw_file_probe.py'),workflow.index('python3 tools/conformance.py'))
        for pattern in ('results.json','inputs.json','*.stdout','*-resource.json','*.bend','reference.c'):
            self.assertIn('.build/r32-raw-file-probe/'+pattern,workflow)
        self.assertNotIn('.build/r32-raw-file-probe/*.raw',workflow)
        self.assertNotIn('.build/r32-raw-file-probe/**',workflow)

    def test_stale_success_invalidated_before_source_gate(self):
        main=self.probe['main']
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);report=work/'r32-raw-file-probe/results.json'
            report.parent.mkdir();report.write_text('{"passed":true}')
            with patch.dict(main.__globals__,BUILD=work,checkout=lambda *a:(_ for _ in ()).throw(ValueError('provenance failure'))),patch('sys.argv',['probe','--bend-source',str(work/'bend'),'--raylib-source',str(work/'raylib')]),patch('subprocess.run',side_effect=AssertionError('Unexpected subprocess')):
                with self.assertRaisesRegex(ValueError,'provenance failure'):main()
            self.assertEqual(json.loads(report.read_text()),dict(passed=False))

    def test_missing_native_output_and_stale_binary_cannot_pass(self):
        main=self.probe['main']
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);work=root/'r32-raw-file-probe';work.mkdir()
            binary=work/'reference';binary.write_bytes(b'stale')
            case=dict(name='half',width=1,height=1,format=8,header=0,data=[0,0,0,63],selected=[0,0,0,63],error=None)
            commands=[]
            def fake_run(command,**kwargs):
                commands.append(command)
                if command[0]=='cmake':
                    (root/'raylib/raylib').mkdir(parents=True,exist_ok=True)
                    (root/'raylib/raylib/libraylib.a').write_bytes(b'archive')
                    (root/'raylib/CMakeCache.txt').write_bytes(b'cache')
                else:self.assertFalse(binary.exists())
                return ''
            overrides=dict(ROOT=root,BUILD=root,checkout=lambda *a:None,source_gate=lambda:{},harness_hashes=lambda:{},run=fake_run,fixture_specs=lambda:([copy.deepcopy(case)],[]))
            (root/'toolchain.json').write_text(json.dumps({'bend':{'revision':'x'},'raylib':{'revision':'y'}}))
            with patch.dict(main.__globals__,overrides),patch('sys.argv',['probe','--bend-source',str(root/'bend'),'--raylib-source',str(root/'raylib')]):
                with self.assertRaisesRegex(ValueError,'result count'):main()
            self.assertEqual(len(commands),4)
            self.assertFalse(json.loads((work/'results.json').read_text())['passed'])


if __name__=='__main__':unittest.main()
