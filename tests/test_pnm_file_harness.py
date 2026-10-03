"""Adversarial checks for the reconstructed PNM file gate, without native input UB."""
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pnm_file_probe as p


def reference(cases):
    # Protocol/unit-test dummy samples only; runtime expectations come exclusively
    # from actual native observations. Never use this in the differential gate.
    result={}
    for c in cases:
        pixels=c['width']*c['height']
        result[c['id']]=(dict(p.memory.meta(c,'raw'),bytes=[17]*(pixels*c['channels'])),dict(p.memory.meta(c,'normalized'),bytes=[17,17,17,255]*pixels))
    return result


def encode(actions):
    lines=[]
    for a in actions:
        row=a['expected'].copy();values=row.pop('bytes',None);lines.append(json.dumps(row))
        if values is not None:
            lines += [json.dumps(values[i:i+256]) for i in range(0,len(values),256)]+['"end"']
    return '\n'.join(lines)+'\n'


class PnmFileFixtureTests(unittest.TestCase):
    def setUp(self):
        self.cases=p.fixtures();self.invalid=p.controls();self.case=next(c for c in self.cases if c['id']=='c1-max255-single')

    def test_exact_primary_matrix_and_all_memory_inputs_retained(self):
        self.assertEqual(len(self.cases),156);self.assertEqual(sum(c['width']*c['height'] for c in self.cases),64542)
        self.assertEqual(sum(c['route']=='LoadImage' for c in self.cases),132);self.assertEqual(sum(c['route']=='explicit-pnm' for c in self.cases),24)
        by_id={c['id']:c for c in self.cases}
        for c in p.memory.fixtures():self.assertEqual({k:by_id[c['id']][k] for k in p.BASE_KEYS},c)
        p.validate_cases(self.cases)

    def test_suffix_matrix_covers_both_channels_and_depths(self):
        for channel in (1,3):
            for maximum in (255,256):
                rows=[c for c in self.cases if c['id'].startswith(f'path-c{channel}-max{maximum}-')]
                self.assertEqual(len(rows),15);self.assertTrue(all(c['regress'] for c in rows))
                self.assertEqual(sum(c['route']=='explicit-pnm' for c in rows),6)
                text=' '.join(c['filename'] for c in rows)
                for suffix in ('.PGM','.PPM','.png','.jpg','.gif','.pnm','.PgM','.PpM','.qoi','.dat',' with spaces','.a.b.', '/.pgm'):self.assertIn(suffix,text)
                self.assertTrue(any(c['filename'].endswith('suffixless') for c in rows))

    def test_native_schema_and_safety_mutations_fail_closed(self):
        changes=[dict(width=0),dict(width=4097),dict(width=True),dict(height=1.0),dict(channels=3),dict(maximum=0),dict(header_bytes=0),dict(raster_bytes=0),dict(extended=1),dict(regress=1),dict(id='unsafe"id'),dict(bytes=self.case['bytes'][:-1]),dict(bytes=[*self.case['bytes'],256]),dict(bytes=[*self.case['bytes'],True]),dict(special='sparse'),dict(native=True),dict(route='explicit-qoi'),dict(route='explicit-pnm'),dict(filename='image.QoI'),dict(filename='../image.ppm'),dict(filename='/image.ppm'),dict(filename='image\0.ppm'),dict(filename=''),dict(path='\0'),dict(bytes=[0])]
        for change in changes:
            with self.subTest(change=change),self.assertRaises(ValueError):p.validate_cases([dict(self.case,**change)])
        for cases in ([],[self.case,self.case],self.invalid[:1]):
            with self.assertRaises(ValueError):p.validate_cases(cases)
        with patch.object(p,'PNM_CAP',1),self.assertRaises(ValueError):p.validate_cases([self.case])
        with patch.object(p.memory,'MAX_TOTAL_BYTES',1),self.assertRaises(ValueError):p.validate_cases([self.case])
        for key in p.BASE_KEYS|{'route','regress','filename'}:
            bad=self.case.copy();del bad[key]
            with self.subTest(missing=key),self.assertRaises(ValueError):p.validate_cases([bad])

    def test_typed_controls_are_file_byte_safe_and_never_native(self):
        self.assertEqual(len(self.invalid),74);by_id={c['id']:c for c in self.invalid}
        for c in self.invalid:
            self.assertTrue(all(type(b) is int and 0<=b<=255 for b in c.get('bytes',[])))
            self.assertNotIn('native',c)
            with self.assertRaises(ValueError):p.reference_program([dict(c,path=c['filename'])])
        for ident,error in [('not-pnm-png',0),('not-pnm-qoi',0),('ascii-P3',0),('missing',5),('directory',5),('cap-plus-one',2),('cap-misleading',2),('larger-file',2),('host-size-overflow',5),('complete-header-missing-raster',3),('bad-max-before-bad-size',0),('width-4294967295',0),('height-4097',2)]:self.assertEqual(by_id[ident]['error'],error)
        for c in p.memory.controls():
            if all(0<=b<=255 for b in c['bytes']):self.assertEqual(by_id[c['id']]['bytes'],c['bytes'])

    def test_native_file_route_and_raw_observation_order(self):
        cases=[dict(self.case,path='native.pgm'),dict(self.case,id='explicit',filename='explicit.pnm',path='explicit.pnm',route='explicit-pnm')]
        text=p.reference_program(cases)
        for token in ('if(!little_endian())','Image image=LoadImage("native.pgm")','LoadFileData("explicit.pnm",&size)','size!=12','LoadImageFromMemory(".ppm",data,size);UnloadFileData(data)','image.mipmaps!=1','image.format!=1','GetPixelDataSize(image.width,image.height,image.format)!=1'):self.assertIn(token,text)
        self.assertLess(text.index('"raw",image)'),text.index('ImageFormat(&image,7)'))
        self.assertLess(text.index('ImageFormat(&image,7)'),text.index('"normalized",image)'))
        self.assertNotIn('LoadImageColors',text);self.assertNotIn('stbi_load',text)
        with self.assertRaises(ValueError):p.reference_program([self.case])


class PnmFileOwnershipAndBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.cases=[dict(c,path=c['filename']) for c in p.fixtures()];self.invalid=[dict(c,path=c['filename']) for c in p.controls()];self.ref=reference(self.cases)

    def test_wrapper_reuses_closed_bounded_shared_boundary(self):
        source=(p.ROOT/'jonlib.bend').read_text()
        wrapper=source.split('def Image.Formatted.load_pnm(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Image.file.bytes(path, Image.file.limit(RasterFile{}))',wrapper)
        self.assertIn('Image.Formatted.pnm.file.loaded',wrapper)
        for bad in ('Surface','Image.file.kind','QoiFile','decode_image'):self.assertNotIn(bad,wrapper)
        continuation=source.split('def Image.Formatted.pnm.file.loaded(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Fail{error}',continuation);self.assertIn('Image.file.decoded(Image.Formatted, Image.Formatted.decode_pnm(bytes))',continuation)
        bounded=source.split('def Image.file.bounded(',1)[1].split('\ndef ',1)[0]
        self.assertLess(bounded.index('case False{}:'),bounded.index('File.read_bytes'));self.assertIn('File.close(file)',bounded)
        sized=source.split('def Image.file.sized(',1)[1].split('\ndef ',1)[0];self.assertIn('(size <= limit : U32)',sized)
        read=source.split('def Image.file.read(',1)[1].split('\ndef ',1)[0]
        self.assertLess(read.index('File.close(file)'),read.index('Image.file.payload'))
        self.assertIn('law raster_file_limit:',(p.ROOT/'LAWS.bend').read_text())

    def test_primary_and_owner_calls_reopen_real_public_files(self):
        actions=p.candidate_actions(self.cases,self.invalid,self.ref);text=p.candidate_program(actions);main=text.split('def main()',1)[1]
        for call in ('J.Image.Formatted.load_pnm(','J.Surface.load_image(','J.UncontractedDecode{}','J.FusedDecode{}','owner.emitted(','bridge.emitted(','file.failed('):self.assertIn(call,main)
        self.assertNotIn('decode_pnm',main);self.assertNotIn('from_bytes',main)
        for term in ('word <= 255','word <= 16777215','J.Image.Formatted.get','4294967295','J.Image.Formatted.export','surface.pnm.loaded'):self.assertIn(term,text)
        with self.assertRaises(ValueError):p.candidate_program([])
        with self.assertRaises(ValueError):p.candidate_program([dict(actions[0],role='bogus')])

    def test_action_expectations_are_native_and_modes_stay_distinct(self):
        actions=p.candidate_actions(self.cases,self.invalid,self.ref)
        self.assertGreaterEqual(len(actions),552)
        for a in actions:
            c=a['case'];role=a['role']
            if role.endswith('error'):continue
            expected=self.ref[c['id']][0 if role in ('raw','owner') else 1]
            self.assertEqual(a['expected'],dict(expected,role=role))
            if role in ('dispatch-ppm','uncontracted','fused'):self.assertEqual(c['route'],'LoadImage')
        self.assertEqual(sum(a['role']=='surface-error' for a in actions),24)
        text=p.candidate_program([next(a for a in actions if a['role']=='surface-error')])
        body=text.split('def surface.failed(',1)[1].split('def require(',1)[0]
        self.assertIn('"surface-error"',body);self.assertNotIn('"formatted-error"',body)

    def test_closure_uses_ten_acquired_handle_paths_and_exact_messages(self):
        text=p.boundary_program(self.cases,self.invalid)
        for token in ('closure_loop(100n)','File.open(','J.Image.file.read(2, (file, Done{[1]}))','J.Image.file.read(1, (file, Done{[1, 2]}))','stage-read-failure','stage-size-failure','J.Image.file.sized(1048576','continuation-failure','payload-failure','Done{[256]}','1048576 <=','1048577 <=','String.eq(message, text)','def stage.emitted(id: String, +expected: U32,','load.emitted("closure-final", "raw")'):self.assertIn(token,text)
        loop=text.split('def closure_loop(',1)[1].split('def main()',1)[0]
        self.assertEqual(loop.count('J.Image.Formatted.load_pnm('),6);self.assertEqual(loop.count('File.open('),4)
        self.assertNotIn('LoadImage(',text)
        actions=p.boundary_actions(self.cases,self.invalid,self.ref)
        self.assertEqual(len(actions),1009);self.assertEqual(p.TERMINAL['paths_per_iteration'],10)

    def test_complete_boundary_records_and_terminal_are_required(self):
        actions=p.boundary_actions(self.cases,self.invalid,self.ref);text=encode(actions)+json.dumps(p.TERMINAL)+'\n'
        self.assertEqual(p.parse_boundary(text,actions),p.TERMINAL)
        for wrong in ('',encode(actions),text+json.dumps(p.TERMINAL),text.replace('"iterations": 100','"iterations": 99'),text.replace('"records": 1009','"records": true'),text.replace('"synthetic_checks": 8','"synthetic_checks": 8.0'),encode(actions[1:])+json.dumps(p.TERMINAL),encode(actions+[actions[-1]])+json.dumps(p.TERMINAL)):
            with self.subTest(prefix=wrong[:50]),self.assertRaises(ValueError):p.parse_boundary(wrong,actions)
        changed=copy.deepcopy(actions);changed[500]['expected']['error']=99
        with self.assertRaises(ValueError):p.parse_boundary(encode(changed)+json.dumps(p.TERMINAL),actions)
        with self.assertRaises(ValueError):p.parse_boundary(text,actions[:-1])

    def test_format_framing_and_byte_types_cannot_normalize_away_mismatch(self):
        c=next(c for c in self.cases if c['id']=='c1-max255-single');a=dict(case=c,role='raw',expected=self.ref[c['id']][0]);text=encode([a])
        self.assertEqual(p.memory.parse_rows(text,[a]),[a['expected']])
        for key,value in [('width',True),('height',1.0),('format',7),('mipmaps',2),('id','wrong'),('role','normalized'),('extra',1)]:
            bad=copy.deepcopy(a);bad['expected'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):p.memory.parse_rows(encode([bad]),[a])
        for bad in ('',text+'"end"\n',text+text,text.replace('"end"','[]'),text.replace('[17]','[true]'),text.replace('[17]','[256]'),text.replace('[17]','[-1]'),text.replace('[17]','[17.0]'),text.replace('"width": 1','"width": 1, "width": 1')):
            with self.assertRaises(ValueError):p.memory.parse_rows(bad,[a])


class PnmFileRunGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=p.ROOT);self.work=Path(self.temp.name);p.memory.SEALED.clear()
    def tearDown(self):p.memory.SEALED.clear();self.temp.cleanup()

    def test_files_are_real_exact_cap_and_sparse_are_pre_read_controls(self):
        cases=p.fixtures();invalid=p.controls();stress,stage=p.prepare_inputs(self.work,cases,invalid)
        self.assertEqual(stage['stage'],'read');self.assertEqual(stage['code'],p.errno.EISDIR)
        self.assertEqual(len(stress['bytes']),1048576);self.assertEqual((p.ROOT/stress['path']).stat().st_size,1048576)
        self.assertEqual(stress['bytes'][:12],next(c['bytes'] for c in cases if c['id']=='c1-max255-single'))
        for c in cases:self.assertEqual((p.ROOT/c['path']).read_bytes(),bytes(c['bytes']))
        sparse=[c for c in invalid if c.get('special') in ('sparse','large','overflow')]
        self.assertEqual([c['size'] for c in sparse],[1048577,1048577,268435456,4294967296])
        self.assertLess(sum((p.ROOT/c['path']).stat().st_blocks*512 for c in sparse),100000)
        for c in invalid:
            if c.get('special')=='missing':self.assertFalse((p.ROOT/c['path']).exists())
        p.verify_inputs(cases,invalid,stress)
        c=sparse[0]
        with (p.ROOT/c['path']).open('r+b') as f:f.truncate(c['size']-1)
        with self.assertRaises(ValueError):p.verify_inputs(cases,invalid,stress)

    def test_input_missing_directory_and_sparse_prefix_drift_fail(self):
        for mode in ('missing','directory','prefix'):
            directory=self.work/mode;directory.mkdir();cases=p.fixtures();invalid=p.controls();stress,_=p.prepare_inputs(directory,cases,invalid)
            if mode=='missing':(p.ROOT/next(c['path'] for c in invalid if c['id']=='missing')).write_bytes(b'x')
            elif mode=='directory':(p.ROOT/next(c['path'] for c in invalid if c['id']=='directory')/'entry').write_bytes(b'y')
            else:
                with (p.ROOT/next(c['path'] for c in invalid if c['id']=='cap-plus-one')).open('r+b') as f:f.write(b'bad')
            with self.subTest(mode=mode),self.assertRaises(ValueError):p.verify_inputs(cases,invalid,stress)

    def test_stale_reports_reset_before_invalid_cli_or_timeout(self):
        for flags in (['--bad'],['--timeout','0'],['--reference-env','inherited']):
            dest=self.work/str(len(list(self.work.iterdir())));dest.mkdir();(dest/'results.json').write_text('{"passed":true}')
            with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):p.main(['--build-dir',str(dest),*flags])
            self.assertFalse(json.loads((dest/'results.json').read_text())['passed'])

    def test_duplicate_destinations_reset_and_abbreviations_do_not_select_paths(self):
        a=self.work/'a';b=self.work/'b'
        for dest in (a,b):dest.mkdir();(dest/'results.json').write_text('{"passed":true}')
        self.assertEqual(p.admit_directories(['--build-dir',str(a),'--build-dir='+str(b)]),b.resolve())
        for dest in (a,b):self.assertFalse(json.loads((dest/'results.json').read_text())['passed'])
        self.assertEqual(p.report_directories(['--build-di',str(a)]),[p.BUILD/'pnm-file-probe'])
        self.assertEqual(p.report_directories(['--','--build-dir',str(a)]),[p.BUILD/'pnm-file-probe'])

    def test_resource_receipt_requires_positive_integer_bounded_rss(self):
        for index,value in enumerate((0,-1,True,1.0,p.MAX_SPARSE_RSS+1,None)):
            def record(command,*args,**kwargs):Path(command[2]).write_text(json.dumps({'maximum_rss_bytes':value}));return 'record\n'
            with patch.object(p,'record_resource',side_effect=record),self.subTest(value=value),self.assertRaises(ValueError):p.resource_run(['candidate'],self.work,'bad'+str(index),p.MAX_SPARSE_RSS,{},None,30)
        with patch.object(p,'record_resource',return_value='record\n'),self.assertRaises(ValueError):p.resource_run(['candidate'],self.work,'missing',p.MAX_SPARSE_RSS,{},None,30)
        with self.assertRaises(ValueError):p.resource_run(['candidate'],self.work,'unknown',1,{},None,30)

    def test_real_outer_timeout_kills_candidate_descendants(self):
        started=self.work/'started';sentinel=self.work/'escaped'
        child='import signal,time;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);Path('+repr(str(started))+').write_text("started");time.sleep(0.8);Path('+repr(str(sentinel))+').write_text("escaped")'
        parent='import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",'+repr(child)+']);print("launched",flush=True);time.sleep(10)'
        with self.assertRaisesRegex(ValueError,'process group timed out'):
            p.record_resource([sys.executable,'-c',parent],self.work,'real-timeout',timeout=0.3,environment=os.environ.copy(),receipt=None)
        self.assertTrue(started.exists(), 'negative test did not reach the descendant')
        time.sleep(0.8);self.assertFalse(sentinel.exists(), 'candidate descendant survived timeout')
        row=json.loads((self.work/'real-timeout.command.json').read_text())
        self.assertTrue(row['timed_out']);self.assertTrue(row['process_group_owned']);self.assertNotEqual(row['exit_code'],0)
        self.assertIn('launched',(self.work/'real-timeout.stdout').read_text())

    def test_resource_lifecycle_failure_and_empty_output_keep_receipts(self):
        for label,code in [('failed','import sys;print("partial");sys.exit(7)'),('empty','pass')]:
            with self.assertRaises(ValueError):p.record_resource([sys.executable,'-c',code],self.work,label,timeout=5,environment=os.environ.copy(),receipt=None)
            self.assertTrue((self.work/(label+'.command.json')).exists())

    def test_resource_measurement_is_separate_and_fd_limited(self):
        def record(command,*args,**kwargs):
            self.assertIn('resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))',Path(command[1]).read_text())
            self.assertEqual(command[-1],'candidate');self.assertEqual(kwargs['environment'],{'candidate':'env'})
            Path(command[2]).write_text('{"maximum_rss_bytes":1048576}');return 'ok\n'
        with patch.object(p,'record_resource',side_effect=record):text,usage=p.resource_run(['candidate'],self.work,'good',p.MAX_SPARSE_RSS,{'candidate':'env'},None,30)
        self.assertEqual(text,'ok\n');self.assertEqual(usage['descriptor_limit'],64);self.assertEqual(usage['maximum_rss_bytes'],1048576)
        p.memory.verify_sealed()

    def test_all_three_lanes_require_complete_contiguous_batches_and_resources(self):
        lanes={lane:dict(batches=[dict(start=0,count=1,passed=True)],differences=[],boundary=dict(passed=True,descriptor_limit=64,maximum_rss_bytes=1,maximum_rss_acceptance_bytes=p.MAX_SPARSE_RSS),sparse=dict(passed=True,descriptor_limit=64,maximum_rss_bytes=1,maximum_rss_acceptance_bytes=p.MAX_SPARSE_RSS),exact_cap=dict(passed=True,descriptor_limit=64,maximum_rss_bytes=1,maximum_rss_acceptance_bytes=p.MAX_STRESS_RSS)) for lane in p.LANES}
        good=copy.deepcopy(lanes);p.finish_lanes(good,[{}]);self.assertTrue(all(v['passed'] for v in good.values()))
        variants=[]
        for kind in ('boundary','sparse','exact_cap'):
            bad=copy.deepcopy(lanes);del bad['cpu-1'][kind];variants.append(bad)
            bad=copy.deepcopy(lanes);bad['javascript'][kind]['passed']=False;variants.append(bad)
            bad=copy.deepcopy(lanes);bad['cpu-2'][kind]['descriptor_limit']=65;variants.append(bad)
        for key,value in [('start',True),('count',0),('count',33),('passed',False)]:
            bad=copy.deepcopy(lanes);bad['cpu-2']['batches'][0][key]=value;variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-1']['differences']=[{}];variants.append(bad)
        bad=copy.deepcopy(lanes);del bad['javascript'];variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):p.finish_lanes(bad,[{}])
        with self.assertRaises(ValueError):p.finish_lanes(lanes,[])

    def arguments(self,directory):
        return ['--build-dir',str(directory),'--bend-source',str(self.work/'bend'),'--raylib-source',str(self.work/'raylib')]

    def test_zero_and_negative_timeouts_reach_positive_timeout_guard(self):
        for value in ('0','-1'):
            directory=self.work/('timeout'+value);directory.mkdir();(directory/'results.json').write_text('{"passed":true}')
            with patch.object(p,'checkout') as checkout,patch('sys.stderr',new_callable=io.StringIO) as stderr,self.assertRaises(SystemExit):
                p.main(self.arguments(directory)+['--timeout',value])
            self.assertIn('--timeout must be positive',stderr.getvalue());checkout.assert_not_called()
            self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_reference_policy_cannot_switch_or_abbreviate(self):
        for flags in (['--reference-env','inherited'],['--reference-e','clean-loader'],['--time','1']):
            directory=self.work/str(len(list(self.work.iterdir())));directory.mkdir()
            with patch.object(p,'checkout') as checkout,patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):p.main(self.arguments(directory)+flags)
            checkout.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_default_invalid_cli_resets_only_default_report(self):
        with patch.object(p,'BUILD',self.work):
            default=self.work/'pnm-file-probe';default.mkdir();(default/'results.json').write_text('{"passed":true}')
            with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):p.main(['--unknown'])
            self.assertFalse(json.loads((default/'results.json').read_text())['passed'])

    def test_duplicate_cli_destinations_reset_even_when_parsing_fails(self):
        a=self.work/'a';b=self.work/'b'
        for directory in (a,b):directory.mkdir();(directory/'results.json').write_text('{"passed":true}')
        with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):p.main(self.arguments(a)+['--build-dir='+str(b),'--unknown'])
        for directory in (a,b):self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_checkout_setup_failure_cannot_inherit_success(self):
        directory=self.work/'checkout';directory.mkdir();(directory/'results.json').write_text('{"passed":true}')
        with patch.object(p,'checkout',side_effect=ValueError('wrong revision')),patch.object(p.memory,'native_archive') as archive,self.assertRaisesRegex(ValueError,'wrong revision'):p.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_native_input_safety_failure_precedes_archive_or_decoder(self):
        directory=self.work/'bad-fixture';bad=p.fixtures();bad[0]['bytes']=[0]
        with patch.object(p,'checkout'),patch.object(p,'fixtures',return_value=bad),patch.object(p.memory,'native_archive') as archive,self.assertRaises(ValueError):p.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_missing_tool_setup_failure_cannot_use_stale_archive(self):
        directory=self.work/'missing-tool'
        with patch.object(p,'checkout'),patch.object(p.shutil,'which',return_value=None),patch.object(p.memory,'native_archive') as archive,self.assertRaisesRegex(ValueError,'Required tool missing'):p.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_native_build_failure_preserves_failed_scoped_report(self):
        directory=self.work/'native-failure'
        with patch.object(p,'checkout'),patch.object(p.shutil,'which',return_value=sys.executable),patch.object(p.memory,'native_archive',side_effect=ValueError('PNM compile definition missing')) as archive,self.assertRaisesRegex(ValueError,'PNM compile definition missing'):p.main(self.arguments(directory))
        archive.assert_called_once();report=json.loads((directory/'results.json').read_text())
        self.assertFalse(report['passed']);self.assertEqual(report['cases'],156);self.assertEqual(report['native_rejections'],0)
        self.assertTrue(all(v['passed'] is False for v in report['lanes'].values()))

    def test_bad_native_qualification_cannot_reach_candidate_compile(self):
        directory=self.work/'qualification';commands=[]
        def record(command,*args,**kwargs):
            commands.append(list(map(str,command)))
            if command==['bun','--version']:return '1.3.12\n'
            if command==['clang','--version']:return 'test compiler\n'
            return '{}\n'
        with patch.object(p,'checkout'),patch.object(p.shutil,'which',return_value=sys.executable),patch.object(p.memory,'native_archive',return_value=(self.work/'test.a',{})),patch.object(p,'record_run',side_effect=record),self.assertRaises(ValueError):p.main(self.arguments(directory))
        self.assertFalse(any('candidate-' in ' '.join(c) for c in commands));self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_ordinary_file_and_dependency_drift_cannot_pass_input_verification(self):
        cases=p.fixtures();invalid=p.controls();stress,_=p.prepare_inputs(self.work,cases,invalid)
        file=p.ROOT/cases[0]['path'];p.memory.seal(file);file.write_bytes(file.read_bytes()+b'x')
        with self.assertRaisesRegex(ValueError,'artifact drift'):p.verify_inputs(cases,invalid,stress)
        p.memory.SEALED.clear();dependency=self.work/'dependency.py';dependency.write_text('original');p.memory.seal(dependency);dependency.unlink()
        with self.assertRaisesRegex(ValueError,'artifact drift'):p.verify_inputs(cases,invalid,stress)

    def test_resource_completion_rejects_forged_types_missing_and_excess_receipts(self):
        def receipt(ceiling):return dict(passed=True,descriptor_limit=64,maximum_rss_bytes=1,maximum_rss_acceptance_bytes=ceiling)
        lanes={lane:dict(batches=[dict(start=0,count=1,passed=True)],differences=[],boundary=receipt(p.MAX_SPARSE_RSS),sparse=receipt(p.MAX_SPARSE_RSS),exact_cap=receipt(p.MAX_STRESS_RSS)) for lane in p.LANES}
        for key,value in [('descriptor_limit',64.0),('maximum_rss_bytes',True),('maximum_rss_bytes',0),('maximum_rss_bytes',p.MAX_SPARSE_RSS+1),('maximum_rss_acceptance_bytes',p.MAX_STRESS_RSS),('maximum_rss_acceptance_bytes',float(p.MAX_SPARSE_RSS))]:
            bad=copy.deepcopy(lanes);bad['cpu-1']['sparse'][key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):p.finish_lanes(bad,[{}])
        for key in ('maximum_rss_bytes','maximum_rss_acceptance_bytes'):
            bad=copy.deepcopy(lanes);del bad['cpu-1']['sparse'][key]
            with self.assertRaises(ValueError):p.finish_lanes(bad,[{}])

    def test_resource_stale_missing_extra_and_duplicate_receipts_fail(self):
        for index,content in enumerate(('{"maximum_rss_bytes":1,"extra":true}','{"maximum_rss_bytes":1,"maximum_rss_bytes":1}','{}')):
            def record(command,*args,**kwargs):Path(command[2]).write_text(content);return 'record\n'
            with patch.object(p,'record_resource',side_effect=record),self.assertRaises(ValueError):p.resource_run(['candidate'],self.work,'schema'+str(index),p.MAX_SPARSE_RSS,{},None,30)
        usage=self.work/'stale.resource.json';usage.write_text('{"maximum_rss_bytes":1}')
        with patch.object(p,'record_resource',return_value='record\n'),self.assertRaisesRegex(ValueError,'Missing resource receipt'):p.resource_run(['candidate'],self.work,'stale',p.MAX_SPARSE_RSS,{},None,30)

    def test_compiler_timeout_kills_grandchild_and_removes_stale_output(self):
        output=self.work/'compiled';output.write_text('stale');started=self.work/'compiler-started'
        compiler='import signal,time;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);Path('+repr(str(started))+').write_text("ready");time.sleep(0.8);Path('+repr(str(output))+').write_text("escaped compiler")'
        parent='import subprocess,sys;print("compiler launched",flush=True);subprocess.run([sys.executable,"-c",'+repr(compiler)+'])'
        with self.assertRaisesRegex(ValueError,'process group timed out'):p.record_run([sys.executable,'-c',parent,'-o',output],self.work,'compiler-timeout',timeout=0.3)
        self.assertTrue(started.exists());time.sleep(0.8);self.assertFalse(output.exists())
        row=json.loads((self.work/'compiler-timeout.command.json').read_text())
        self.assertTrue(row['timed_out']);self.assertIsNone(row['descriptor_limit']);self.assertNotEqual(row['exit_code'],0)

    def test_successful_compiler_must_create_nonempty_fresh_outputs(self):
        output=self.work/'output'
        for index,code in enumerate(('pass','from pathlib import Path;Path('+repr(str(output))+').write_bytes(b"")')):
            output.write_bytes(b'stale')
            with self.assertRaisesRegex(ValueError,'Compiler output missing'):p.record_run([sys.executable,'-c',code,'-o',output],self.work,'missing-output'+str(index))
        output.unlink(missing_ok=True)
        code='from pathlib import Path;Path('+repr(str(output))+').write_text("fresh")'
        p.record_run([sys.executable,'-c',code,'-o',output],self.work,'created')
        self.assertEqual(output.read_text(),'fresh');p.memory.verify_sealed();output.write_text('drift')
        with self.assertRaisesRegex(ValueError,'artifact drift'):p.record_run([sys.executable,'-c','pass'],self.work,'after-drift')

    def test_all_command_receipts_preserve_clean_environment_and_actual_limits(self):
        receipt={'policy':'clean-loader'}
        text=p.record_run([sys.executable,'-c','import os;print(os.environ["ONLY"])'],self.work,'environment',environment={'ONLY':'expected'},receipt=receipt,require_output=True)
        self.assertEqual(text,'expected\n');row=json.loads((self.work/'environment.command.json').read_text())
        self.assertEqual(row['reference_environment'],receipt);self.assertIsNone(row['descriptor_limit']);self.assertTrue(row['process_group_owned'])
        self.assertEqual(row['exit_code'],0);self.assertFalse(row['timed_out']);p.memory.verify_sealed()

    def test_child_start_failure_retains_fail_closed_receipt(self):
        with self.assertRaises(OSError):p.record_run([self.work/'missing-command'],self.work,'start-failure')
        row=json.loads((self.work/'start-failure.command.json').read_text())
        self.assertIsNone(row['exit_code']);self.assertIn('interrupted_or_startup_error',row);self.assertFalse(row['timed_out'])

    def test_dependency_archive_loader_and_provenance_sealing_are_required(self):
        source=(p.ROOT/'tools/pnm_file_probe.py').read_text()
        for text in ('reference_env.require_clear()','reference_env.child()','reference_env.receipt()','reference_env.assert_receipt','memory.native_archive(args,work,native_record)','memory.qualification(output)','tool_realpaths','tracked_sources(args)!=report','memory.verify_sealed()','evidence_origin=','NEW reconstruction run','tests/test_pnm_file_harness.py','verify_inputs(cases,invalid,stress)'):self.assertIn(text,source)
        self.assertLess(source.index('memory.QUALIFY'),source.index('candidate_actions(cases,invalid,file_reference)'))
        self.assertIn('SUPPORT_FILEFORMAT_PNM=ON',(p.ROOT/'tools/pnm_format_probe.py').read_text())
        self.assertNotIn('os.environ[',source)


if __name__=='__main__':unittest.main()
