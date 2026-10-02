import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import qoi_file_probe as probe


class QoiFileHarnessTests(unittest.TestCase):
    def setUp(self):
        self.case=dict(probe.fixtures()[8],path='test.qoi')
        self.action=dict(case=self.case,role='raw')
        self.row=probe.memory.meta(self.case,'raw')

    def test_wrapper_reuses_explicit_shared_boundary(self):
        source=(probe.ROOT/'jonlib.bend').read_text()
        wrapper=source.split('def Image.Formatted.load_qoi(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Image.file.bytes(path, Image.file.limit(QoiFile{}))',wrapper)
        self.assertIn('Image.Formatted.qoi.file.loaded',wrapper)
        self.assertNotIn('Surface',wrapper);self.assertNotIn('Image.file.kind',wrapper)
        continuation=source.split('def Image.Formatted.qoi.file.loaded(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Fail{error}',continuation)
        self.assertIn('Image.file.decoded(Image.Formatted, Image.Formatted.decode_qoi(bytes))',continuation)
        bounded=source.split('def Image.file.bounded(',1)[1].split('\ndef ',1)[0]
        self.assertLess(bounded.index('case False{}:'),bounded.index('File.read_bytes'))
        self.assertIn('File.close(file)',bounded)
        sized=source.split('def Image.file.sized(',1)[1].split('\ndef ',1)[0]
        self.assertIn('(size <= limit : U32)',sized)
        read=source.split('def Image.file.read(',1)[1].split('\ndef ',1)[0]
        self.assertLess(read.index('File.close(file)'),read.index('Image.file.payload'))

    def test_native_file_routes_and_raw_first(self):
        explicit=dict(self.case,id='explicit',path='image.png',route='explicit-qoi')
        text=probe.reference_program([self.case,explicit],[])
        self.assertIn('Image image=LoadImage("test.qoi")',text)
        self.assertIn('LoadFileData("image.png",&size)',text)
        self.assertIn('if(!data||size!=',text);self.assertIn('size<22',text)
        self.assertIn('LoadImageFromMemory(".qoi",data,size);UnloadFileData(data)',text)
        self.assertLess(text.index('"raw",image)'),text.index('ImageFormat(&image,7)'))
        self.assertIn('image.mipmaps!=1',text);self.assertIn('image.format!=4',text)
        self.assertIn('GetPixelDataSize(image.width,image.height,image.format)!=9',text)
        self.assertNotIn('LoadImageColors',text)

    def test_native_never_receives_sparse_or_short_files(self):
        for bad in (dict(self.case,bytes=[1]),dict(self.case,special='sparse')):
            with self.assertRaises(ValueError):probe.reference_program([bad],[])
        for bad in (dict(self.case,bytes=[1],native=True),dict(self.case,special='overflow',native=True),dict(self.case,native=False)):
            with self.assertRaises(ValueError):probe.reference_program([],[bad])
        rejected=[c for c in probe.controls() if c.get('native')]
        self.assertEqual(len(rejected),8)
        for c in rejected:
            self.assertGreaterEqual(len(c['bytes']),22)
            self.assertLessEqual(int.from_bytes(bytes(c['bytes'][4:8]),'big'),1)
            self.assertLessEqual(int.from_bytes(bytes(c['bytes'][8:12]),'big'),1)

    def test_accepted_fixture_reuse_and_suffix_matrix(self):
        cases=probe.fixtures();by_id={c['id']:c for c in cases}
        self.assertEqual(len(cases),135);self.assertEqual(len(by_id),len(cases))
        self.assertEqual(sum(c['route']=='explicit-qoi' for c in cases),6)
        self.assertEqual(sum(c['route']=='LoadImage' for c in cases),129)
        for original in probe.memory.fixtures():
            actual=by_id[original['id']]
            self.assertEqual(actual['bytes'],original['bytes'])
        for channels in (3,4):
            for space in (0,1):self.assertTrue(by_id[f'c{channels}-s{space}-hidden-alpha-cache']['regress'])
            for name in ('upper','mixed','without-extension','misnamed','spaces','many.parts','directory-dotfile'):
                self.assertTrue(by_id[f'path-c{channels}-{name}']['regress'])
        self.assertTrue(by_id['c3-seeded-mix']['regress'])

    def test_controls_keep_exact_decoder_codes_and_file_domains(self):
        controls={c['id']:c for c in probe.controls()}
        for n in range(14):self.assertEqual(controls[f'header-prefix-{n}']['error'],0)
        for name,code in [('marker-absorbed-255',4),('run-overflow-first',4),('missing-marker',4),('pixel-underflow',3),('width-4097',2),('missing',5),('missing-parent',5),('cap-plus-one',2),('cap-misleading',2),('host-size-overflow',5),('directory',5),('not-qoi-raster',0)]:
            self.assertEqual(controls[name]['error'],code)
        for c in controls.values():self.assertTrue(all(0<=b<=255 for b in c.get('bytes',[])))

    def test_candidate_primary_is_public_file_call(self):
        actions=[dict(case=self.case,role=role) for role in ('raw','bridge','surface','dispatch','uncontracted','fused')]
        actions += [dict(case=dict(self.case,error=0),role='error',mode=mode) for mode in ('formatted','dispatch')]
        text=probe.candidate_program(actions);main=text.split('def main()',1)[1]
        for call in ('J.Image.Formatted.load_qoi','J.Surface.load_qoi','J.Surface.load_image(','J.UncontractedDecode{}','J.FusedDecode{}'):self.assertIn(call,main)
        self.assertNotIn('decode_qoi',main)
        self.assertIn('J.Image.Formatted.export(image)',text)
        self.assertIn('word <= 16777215',text)

    def test_boundary_requires_closed_real_handles_and_exact_errors(self):
        cases=[dict(c,path=c['filename']) for c in probe.fixtures()]
        invalid=[dict(c,path=c['filename']) for c in probe.controls()]
        text=probe.boundary_program(cases,invalid)
        for part in ('closure_loop(100n)','File.open(','J.Image.file.read(2, (file, Done{[1]}))','stage-read-failure','continuation-failure','payload-failure','Done{[256]}','J.Image.file.complete(0n, Nil{})','J.Image.file.complete(1n, [1, 2])','83886102 <=','83886103 <='):
            self.assertIn(part,text)
        self.assertIn('String.eq(message, text)',text)
        self.assertIn('load.emitted("closure-final", "raw")',text)
        self.assertIn('host-size-overflow.qoi',text)

    def test_metadata_and_framing_stay_strict(self):
        values=[self.row,[0]*9,'end'];encoded=lambda vs:'\n'.join(map(json.dumps,vs))+'\n'
        self.assertEqual(probe.memory.parse_rows(encoded(values),[self.action])[0]['format'],4)
        for wrong in (dict(self.row,width=True),dict(self.row,format=7),dict(self.row,mipmaps=2),dict(self.row,id='wrong')):
            with self.assertRaises(ValueError):probe.memory.parse_rows(encoded([wrong,*values[1:]]),[self.action])
        for wrong in (values[:-1],values+values,[self.row,[0]*8,'end'],[self.row,[True]*9,'end'],[self.row,[0]*257,'end']):
            with self.assertRaises(ValueError):probe.memory.parse_rows(encoded(wrong),[self.action])

    def test_closure_terminal_cannot_hide_extra_records(self):
        case=dict(self.case,id='closure-final');raw=dict(probe.memory.meta(case,'raw'),bytes=[0]*9)
        terminal=dict(closure_checks=True,iterations=100,paths_per_iteration=8,synthetic_checks=7)
        lines=[probe.memory.meta(case,'raw'),[0]*9,'end',terminal]
        text='\n'.join(map(json.dumps,lines));self.assertEqual(probe.parse_boundary(text,self.case,dict(raw,id=self.case['id'])),terminal)
        for wrong in (lines[:-1],lines+[terminal],lines[:-1]+[dict(terminal,iterations=99)]):
            with self.assertRaises(ValueError):probe.parse_boundary('\n'.join(map(json.dumps,wrong)),self.case,dict(raw,id=self.case['id']))

    def test_fresh_receipts_resource_and_failure_gates(self):
        text=(probe.ROOT/'tools/qoi_file_probe.py').read_text()
        self.assertLess(text.index('report_path.write_text'),text.index('args=parser.parse_args()'))
        for part in ('uuid.uuid4().hex','ReferenceEnvironment(\'clean-loader\')',"'rcore.c'",'resource_ceiling=ceiling','preexec_fn=limit_handles','except subprocess.TimeoutExpired','if proc.returncode:raise',"kind+'.bend'",'source_gate()!=sources','checkout(args.bend_source'):
            self.assertIn(part,text)
        self.assertEqual(probe.LANES,('cpu-1','cpu-2','javascript'))
        self.assertEqual(probe.BATCH_SIZE,64);self.assertEqual(probe.MAX_SPARSE_RSS,256*1024*1024)
        self.assertIn('RESOURCE_RUNNER',text)

    def test_ci_keeps_sparse_artifacts_out(self):
        text=(probe.ROOT/'.github/workflows/conformance.yml').read_text()
        self.assertIn('python3 tools/qoi_file_probe.py',text)
        self.assertIn('.build/qoi-file-probe/results.json',text)
        self.assertNotIn('.build/qoi-file-probe/\n',text)
        self.assertNotIn('.build/qoi-file-probe/**',text)
        self.assertNotIn('.build/qoi-file-probe/run-*/fixtures',text)


if __name__=='__main__':unittest.main()
