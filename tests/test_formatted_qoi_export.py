"""Behavioral guardrails for formatted QOI evidence; no compiler/native builds."""
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

ROOT=Path(__file__).resolve().parents[1]
with patch('sys.path',[str(ROOT/'tools'),*sys.path]):P=runpy.run_path(str(ROOT/'tools/formatted_qoi_export_probe.py'))
G=P['main'].__globals__


def case(fmt=7,data=(12,34,56,0),width=1,height=1,name='sample'):
    return dict(id=name,format=fmt,width=width,height=height,data=list(data))


def stream(c,payload,space=0):
    return P['header'](c['width'],c['height'],P['channels'](c['format']),space)+bytes(payload)+P['MARKER']


def literal_stream(c):
    # Deliberately unoptimized streams for decoder tests, not an encoding oracle.
    comp=P['channels'](c['format']);data=c['data'];payload=[]
    for offset in range(0,len(data),comp):payload.extend([254 if comp==3 else 255,*data[offset:offset+comp]])
    return stream(c,payload)


def observation(c,encoded=None):
    values=dict(source=c['data'])
    if c['format'] in P['ACCEPTED']:
        encoded=encoded or literal_stream(c);decoded=P['decode_qoi'](encoded,c)
        values.update(encoded=list(encoded),decoded=decoded['raw'],surface=decoded['pixels'],loaded=decoded['raw'])
    else:values['retained']=c['data']
    lines=[]
    for role in P['roles'](c):
        lines.append(json.dumps(P['metadata'](c,role)))
        data=values[role]
        lines.extend(json.dumps(data[i:i+256]) for i in range(0,len(data),256));lines.append('"end"')
    return '\n'.join(lines)+'\n'


@contextmanager
def working_directory(path):
    old=Path.cwd();os.chdir(path)
    try:yield
    finally:os.chdir(old)


class FixturesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases=P['fixtures']();cls.by_id={c['id']:c for c in cls.cases}

    def test_deterministic_complete_safe_inputs_all_eight_formats(self):
        self.assertEqual(self.cases,P['fixtures']());self.assertEqual(len(self.cases),len(self.by_id))
        self.assertEqual({c['format'] for c in self.cases},set(range(1,9)))
        for c in self.cases:P['validate_case'](c)
        self.assertEqual(len([c for c in self.cases if c['format'] in (4,7)]),273)
        self.assertEqual(len([c for c in self.cases if c['format'] not in (4,7)]),22)

    def test_runs_axes_padding_orientation_and_diff_boundaries(self):
        for fmt in (4,7):
            for n in (1,2,61,62,63,64,123,124,125):
                for start in ('initial','literal'):
                    for suffix in ('','-change'):
                        c=self.by_id[f'format-{fmt}-run-{n}-{start}{suffix}']
                        self.assertEqual(c['width'],n+bool(suffix))
            for name,shape in [('axis-row',(4096,1)),('axis-column',(1,4096)),('full-traversal',(256,129)),('seeded-mixed',(257,2))]:
                c=self.by_id[f'format-{fmt}-{name}'];self.assertEqual((c['width'],c['height']),shape)
            self.assertEqual(len([c for c in self.cases if c['id'].startswith(f'format-{fmt}-diff-')]),64)
            self.assertEqual(self.by_id[f'format-{fmt}-diff-42']['data'][:3],[0,0,0])
            self.assertEqual(self.by_id[f'format-{fmt}-diff-0'+'0']['data'][:3],[254]*3)
            self.assertEqual({int(c['id'].split('-luma-')[1]) for c in self.cases if c['id'].startswith(f'format-{fmt}-luma-')},{-33,-32,-31,30,31,32})

    def test_ingress_noncanonical_alpha_colorspace_and_large_exact_bound(self):
        for c in self.cases:
            if 'input' in c:
                self.assertEqual(c['input'][13],1)
                self.assertEqual(P['decode_qoi'](bytes(c['input']),c,canonical=False)['raw'],c['data'])
                with self.assertRaises(ValueError):P['decode_qoi'](bytes(c['input']),c)
        self.assertEqual({c.get('origin') for c in self.cases},{None,'bridge','decode','load'})
        c=self.by_id['rgba-large-raw'];self.assertEqual((c['width'],c['height']),(513,513))
        values=[tuple(c['data'][i:i+4]) for i in range(0,len(c['data']),4)]
        self.assertEqual(len(set(p[:3] for p in values)),513*513)
        self.assertTrue(all(a[3]!=b[3] for a,b in zip(values,values[1:])))
        self.assertEqual(22+5*len(values),1315867)

    def test_each_just_outside_diff_edge_is_isolated_and_decodes_as_luma(self):
        payloads={'0-minus3':[160,88],'0-plus2':[160,168],
                  '1-minus3':[157,187],'1-plus2':[162,102],
                  '2-minus3':[160,133],'2-plus2':[160,138]}
        controls=[c for c in self.cases if '-outside-diff-' in c['id']]
        self.assertEqual(len(controls),12)
        for c in controls:
            edge=c['id'].split('-outside-diff-')[1];axis,label=edge.split('-')
            expected=[0,0,0];expected[int(axis)]=253 if label=='minus3' else 2
            self.assertEqual(c['data'][:3],expected)
            result=P['decode_qoi'](stream(c,payloads[edge]),c)
            self.assertEqual(result['raw'],c['data']);self.assertEqual(len(result['opcodes']),1)
            self.assertEqual(result['opcodes'][0]['kind'],'LUMA')

    def test_rejected_safe_r32_words_and_invalid_native_inputs_guard(self):
        words=set(struct.unpack('<'+'I'*(len(self.by_id['rejected-r32-boundaries']['data'])//4),bytes(self.by_id['rejected-r32-boundaries']['data'])))
        self.assertTrue({0,0x80000000,1,0x007fffff,0x00800000,0x3f000000,0x3f800000}<=words)
        for word in (0x7f800000,0xff800000,0x7fc00000,0xbf800000,0x3f800001):
            c=case(8,list(struct.pack('<I',word)))
            with self.assertRaisesRegex(ValueError,'R32'):P['reference_program']([c],Path('/tmp/never-executed'))
        for key,value in [('format',True),('width',True),('height',0),('width',4097),('data',[12,34,56]),('data',[True,34,56,0]),('data',[256,34,56,0])]:
            c=case();c[key]=value
            with self.assertRaises(ValueError):P['validate_case'](c)


class DecoderTests(unittest.TestCase):
    def test_exact_initial_controls_and_all_diff_opcodes(self):
        for fmt in (4,7):
            for rgb,payload in [([0,0,0],[192]),([255,255,255],[85]),([12,34,56],[254,12,34,56])]:
                c=case(fmt,rgb+([255] if fmt==7 else []));self.assertEqual(P['decode_qoi'](stream(c,payload),c)['raw'],c['data'])
            for code in range(64):
                rgb=[((code>>4)-2)&255,(((code>>2)&3)-2)&255,((code&3)-2)&255]
                c=case(fmt,rgb+([255] if fmt==7 else []));self.assertEqual(P['decode_qoi'](stream(c,[64+code]),c)['raw'],c['data'])
        c=case(7,[0]*4);self.assertEqual(P['decode_qoi'](stream(c,[0]),c)['raw'],[0]*4)

    def test_luma_wrapping_index_collision_and_run_crossing_rows(self):
        c=case(7,[0]*24,3,2)
        s=stream(c,[255,12,34,56,0,192,22,254,0,255,0,0x80,0,22])
        result=P['decode_qoi'](s,c)
        self.assertEqual(result['raw'][:12],[12,34,56,0]*3)
        self.assertEqual(result['raw'][-4:],[12,34,56,0])
        self.assertEqual(result['raw'][16:20],[216,223,216,0])
        c=case(4,[0]*18,3,2);result=P['decode_qoi'](stream(c,[197]),c)
        self.assertEqual(result['raw'],[0]*18);self.assertEqual(result['opcodes'][0]['count'],6)

    def test_header_each_byte_marker_every_byte_truncation_and_eof(self):
        c=case();valid=literal_stream(c)
        for i in range(14):
            altered=bytearray(valid);altered[i]^=1
            with self.subTest(index=i),self.assertRaises(ValueError):P['decode_qoi'](bytes(altered),c)
        for i in range(8):
            altered=bytearray(valid);altered[-8+i]^=1
            with self.assertRaises(ValueError):P['decode_qoi'](bytes(altered),c)
        for end in range(len(valid)):
            with self.assertRaises(ValueError):P['decode_qoi'](valid[:end],c)
        for suffix in (b'\0',P['MARKER'],b'\xc0'):
            with self.assertRaises(ValueError):P['decode_qoi'](valid+suffix,c)
        for payload in ([],[255],[255,1,2,3],[254,1,2],[128],[193],[192,192]):
            with self.assertRaises(ValueError):P['decode_qoi'](stream(c,payload),c)
        with self.assertRaises(ValueError):P['decode_qoi'](list(valid),c)

    def test_channel_three_alpha_and_noncanonical_colorspace(self):
        c=case(4,[12,34,56]);s=stream(c,[255,12,34,56,0],1)
        self.assertEqual(P['decode_qoi'](s,c,canonical=False)['pixels'],[12,34,56,255])
        with self.assertRaises(ValueError):P['decode_qoi'](s,c)
        with self.assertRaises(ValueError):P['decode_qoi'](stream(c,[255,12,34,56,0]),c)
        with self.assertRaises(ValueError):P['decode_qoi'](stream(c,[0]),c)


class FramingTests(unittest.TestCase):
    def test_complete_accepted_and_retained_observations(self):
        cases=[case(),case(4,[0,0,0],name='rgb'),case(8,[0,0,0,128],name='r32')]
        rows=P['parse_rows'](''.join(observation(c) for c in cases),cases)
        self.assertEqual(len(rows),3);self.assertEqual(rows[-1]['retained'],cases[-1]['data'])

    def test_missing_extra_reordered_duplicate_metadata_wrong_types(self):
        c=case();text=observation(c);lines=text.splitlines()
        for bad in ('',text+text,'\n'.join(lines[1:]),text.replace('"source"','"loaded"',1),text.replace('"width": 1','"width": true',1),text.replace('"width": 1','"width": 1.0',1),text.replace('"mipmaps": 1','"mipmaps": 2',1),text.replace('"width": 1','"width": 1, "width": 1',1),text.replace('[12, 34, 56, 0]','[12, 34, 56, 1]',1)):
            with self.assertRaises(ValueError):P['parse_rows'](bad,[c])

    def test_bad_chunks_partial_chunks_and_wrong_retained_owner(self):
        c=case();text=observation(c)
        for value in ('[]','[true,34,56,0]','[12,34,56,256]','[12.0,34,56,0]','[12]\n[34,56,0]','null'):
            with self.assertRaises(ValueError):P['parse_rows'](text.replace('[12, 34, 56, 0]',value,1),[c])
        c=case(1,[17]);text=observation(c)
        with self.assertRaises(ValueError):P['parse_rows'](text[:-9]+'[18]\n"end"\n',[c])
        c=case(7,[17]*260,65,1);text=observation(c)
        self.assertEqual(P['parse_rows'](text,[c])[0]['source'],c['data'])
        lines=text.splitlines();first=json.loads(lines[1]);lines[1]=json.dumps(first[:128])+'\n'+json.dumps(first[128:])
        with self.assertRaises(ValueError):P['parse_rows']('\n'.join(lines)+'\n',[c])


class SourceTests(unittest.TestCase):
    def test_native_actual_export_typed_safety_snapshot_and_raw_before_normalize(self):
        c=[case(),case(3,[255,255],name='packed'),case(8,[0,0,0,128],name='float')]
        source=P['reference_program'](c,Path('/tmp/qoi-test'))
        for text in ('ExportImage(image,','typed_pixels(data,n,','unsigned short *samples=malloc','float *samples=malloc','samples[i]=value','memcpy(snapshot,data,','memcmp(image.data,snapshot,','free(snapshot)','if(image.data!=data)free(image.data)','n<22','expected_header','decoded.mipmaps!=1'):
            self.assertIn(text,source)
        self.assertNotIn('ExportImageToMemory',source)
        self.assertLess(source.index('"decoded",decoded)'),source.index('ImageFormat(&decoded,7)'))
        self.assertIn('signed char)255!=-1',P['QUALIFY']);self.assertIn('CHAR_BIT==8',P['QUALIFY'])

    def test_candidate_explicit_qoi_raw_first_all_ingress_retained_errors(self):
        source=P['candidate_program'](P['fixtures'](),Path('/tmp/qoi-test'))
        for text in ('J.Image.Formatted.to_qoi','J.Image.Formatted.write_qoi','J.Image.Formatted.load_qoi','J.Image.Formatted.decode_qoi','J.Surface.to_formatted','J.Image.Formatted.export','J.QoiSourceError{image}','J.UnsupportedPixelFormat{}','rejected.twice(rejected.twice','File.close(file)'):
            self.assertIn(text,source)
        self.assertNotIn('Surface.load_image',source);self.assertNotIn('Surface.write_image',source)
        for suffix in ('.dat','.png','.QoI'):self.assertIn(suffix,source)

    def test_exact_typed_file_errors_rejection_priority_and_final_success(self):
        for failure in (False,True):
            source=P['io_program'](Path('/tmp/qoi-test'),failure)
            for text in ('J.QoiFileError{actual_code, actual_message}','U32.is_eq(code, actual_code)','String.eq(message, actual_message)','U32.is_gt(code, 0)','loop(100n','J.QoiSourceError{image}','retained.exported','missing-parent','rejected-sentinel.dat'):
                self.assertIn(text,source)
            self.assertIn('baseline(27,' if failure else 'baseline(2,',source)
            self.assertIn('baseline(21,',source) if not failure else None
            if not failure:self.assertLess(source.rindex('baseline(21,'),source.rindex('write(0, "",'))
        self.assertNotIn('baseline(24,',P['io_program'](Path('/tmp/qoi-test'),True))


class IOAndSealTests(unittest.TestCase):
    def setUp(self):P['SEALED'].clear()
    def tearDown(self):P['SEALED'].clear()

    def test_complete_io_markers_sentinels_and_post_open_truncation(self):
        marker=json.dumps(dict(iterations=100,accepted_writes=200,rejected_writes=1800))+'\n'
        with tempfile.TemporaryDirectory() as tmp:
            work=Path(tmp);(work/'directory').mkdir();(work/'directory/sentinel').write_bytes(P['SENTINEL']);(work/'rejected-sentinel.dat').write_bytes(P['SENTINEL']);(work/'post-open.dat').write_bytes(b'');(work/'repeated.dat').write_bytes(literal_stream(case(7,[17]*4)))
            for failure in (False,True):
                good=marker if failure else marker*3+'{"final_success":true}\n'
                self.assertEqual(P['verify_io'](good,work,failure)['accepted_writes'],200 if failure else 601)
                for bad in ('',good+marker,good.replace('200','199'),good.replace('100','100.0'),good.replace('1800','true')):
                    with self.assertRaises(ValueError):P['verify_io'](bad,work,failure)
            with self.assertRaises(ValueError):P['verify_io'](marker*3,work,False)
            with self.assertRaises(ValueError):P['verify_io'](marker*3+'{"final_success":1}\n',work,False)
            (work/'post-open.dat').write_bytes(b'old')
            with self.assertRaises(ValueError):P['verify_io'](marker,work,True)
            (work/'post-open.dat').write_bytes(b'');(work/'rejected-sentinel.dat').write_bytes(b'changed')
            with self.assertRaises(ValueError):P['verify_io'](marker,work,True)

    def test_seals_detect_missing_and_changed_source_or_generated_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'source';path.write_bytes(b'good');P['seal'](path);P['seal'](path);P['verify_sealed']()
            path.write_bytes(b'bad')
            with self.assertRaises(ValueError):P['verify_sealed']()
            with self.assertRaises(ValueError):P['seal'](path)
            path.unlink()
            with self.assertRaises(ValueError):P['verify_sealed']()

    def test_stale_outputs_deleted_and_missing_empty_outputs_or_process_fail(self):
        for fault in ('missing','empty','nonzero','blank-runtime'):
            with self.subTest(fault=fault),tempfile.TemporaryDirectory() as tmp:
                P['SEALED'].clear();work=Path(tmp);output=work/'program';output.write_bytes(b'stale')
                def launch(command,**kw):
                    self.assertFalse(output.exists())
                    if fault!='missing':output.write_bytes(b'' if fault=='empty' else b'new')
                    return subprocess.CompletedProcess(command,1 if fault=='nonzero' else 0,'' if fault=='blank-runtime' else 'ok','diagnostic')
                with patch('subprocess.run',side_effect=launch),self.assertRaises(ValueError):P['record_run'](['tool','-o',output],work,'run',require_output=True)
                self.assertTrue((work/'run.command.json').is_file())

    def test_receipt_environment_timeout_and_generated_outputs_sealed(self):
        with tempfile.TemporaryDirectory() as tmp:
            work=Path(tmp);source=work/'source';source.write_bytes(b'input');output=work/'program'
            def launch(command,**kw):
                self.assertEqual(kw['env'],{'PATH':'verified'});self.assertEqual(kw['timeout'],23);output.write_bytes(b'new')
                return subprocess.CompletedProcess(command,0,'observation','')
            with patch('subprocess.run',side_effect=launch):P['record_run'](['tool',source,'-o',output],work,'run',environment={'PATH':'verified'},receipt={'policy':'clean-loader'},timeout=23,require_output=True)
            self.assertEqual(json.loads((work/'run.command.json').read_text())['reference_environment'],{'policy':'clean-loader'})
            for path in (source,output,work/'run.stdout',work/'run.stderr',work/'run.command.json'):self.assertIn(str(path),P['SEALED'])
            source.write_bytes(b'changed')
            with patch('subprocess.run') as launch,self.assertRaises(ValueError):P['record_run']([output],work,'again')
            launch.assert_not_called()

    def test_fresh_archive_records_actual_compiler_config_and_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            work=Path(tmp);cmake=work/'raylib-build';archive=cmake/'raylib/libraylib.a';archive.parent.mkdir(parents=True);archive.write_bytes(b'archive')
            compiler=work/'gcc';compiler.write_bytes(b'compiler')
            paths=[cmake/'CMakeCache.txt',cmake/'raylib/CMakeFiles/raylib.dir/flags.make',cmake/'CMakeFiles/3.2/CMakeCCompiler.cmake']
            for path in paths:path.parent.mkdir(parents=True,exist_ok=True);path.write_text('config')
            paths[-1].write_text(f'set(CMAKE_C_COMPILER "{compiler}")\nset(CMAKE_C_COMPILER_ID "GNU")\nset(CMAKE_C_COMPILER_VERSION "14.2.0")\n')
            args=argparse.Namespace(raylib_source=work/'raylib');commands=[]
            output,receipt=P['native_archive'](args,work,lambda *a,**k:commands.append(a[0]))
            self.assertEqual(output,archive);self.assertEqual(receipt['compiler']['CMAKE_C_COMPILER_ID'],'GNU');self.assertIn(str(compiler),receipt['artifacts'])
            self.assertEqual(len(commands),2);self.assertIn('--clean-first',commands[1]);self.assertEqual(receipt['mode'],'fresh-isolated-build')
            paths[-1].unlink()
            with self.assertRaises(ValueError):P['native_archive'](args,work,lambda *a,**k:None)


class FormattedQoiAdmissionTests(unittest.TestCase):
    def test_exact_tokens_duplicates_terminator_and_dash_values_match_argparse(self):
        with tempfile.TemporaryDirectory() as tmp:
            default = Path(tmp)/'default/formatted-qoi-export-probe'
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
                    self.assertIs(json.loads((root/'default/formatted-qoi-export-probe/results.json').read_text())['passed'], False)

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


class PipelineTests(unittest.TestCase):
    """Run real framing/report/sealing orchestration with only processes mocked."""
    def setUp(self):
        P['SEALED'].clear();self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.addCleanup(P['SEALED'].clear)
        self.base=Path(self.temp.name);self.root=self.base/'repo';self.root.mkdir();self.destination=self.base/'result';self.destination.mkdir()
        self.report=self.destination/'results.json';self.report.write_text('{"passed":true}')
        (self.destination/'old').write_bytes(b'not reused')
        (self.root/'toolchain.json').write_text(json.dumps(dict(bend=dict(revision='bend-pin'),raylib=dict(revision='ray-pin'),bun=dict(version='mock-bun'))))
        self.library=self.root/'jonlib.bend';self.library.write_bytes(b'library');self.dependency=self.root/'probe.py';self.dependency.write_bytes(b'probe')
        self.compiler=self.root/'bend/bend2/main.ts';self.compiler.parent.mkdir(parents=True);self.compiler.write_bytes(b'compiler')
        self.tools={}
        for tool in ('bun','clang','cmake','cc'):
            path=self.base/tool;path.write_bytes(tool.encode());self.tools[tool]=str(path)
        self.cases=[case(4,[0,0,0],name='rgb'),case(7,[12,34,56,0],name='rgba'),case(1,[17],name='gray'),case(8,[0,0,0,128],name='r32')]
        self.commands=[];self.checkouts=[];self.fault=None;self.work=None

    def sources(self,args):
        return dict(library={'jonlib.bend':P['digest'](self.library)},dependencies={str(p):P['digest'](p) for p in (self.dependency,self.compiler)})

    def checkout(self,*args):
        self.checkouts.append(args)
        if len(self.checkouts)==4:
            targets={'library':self.library,'dependency':self.dependency,'compiler':self.compiler,'archive':self.work/'raylib-build/raylib/libraylib.a','inputs':self.work/'inputs.json','generated':self.work/'candidate-0.bend','binary':self.work/'candidate-0','stdout':self.work/'cpu-1-0.stdout','command':self.work/'cpu-1-0.command.json','retained':self.work/'javascript-rgb.dat','native-file':self.work/'reference-rgb.qoi','io-file':self.work/'javascript-failure-final.dat','tool':Path(self.tools['clang'])}
            if self.fault in targets:targets[self.fault].write_bytes(b'changed')
            if self.fault=='deleted':(self.work/'candidate-0.bend').unlink()
            if self.fault=='pin':raise ValueError('pin differs')

    def process(self,command,**kw):
        self.commands.append((command,kw));self.work=next(self.destination.glob('run-*'));out=''
        if command[0]=='cmake':
            cmake=self.work/'raylib-build'
            for rel in ('raylib/libraylib.a','CMakeCache.txt','raylib/CMakeFiles/raylib.dir/flags.make','CMakeFiles/3.2/CMakeCCompiler.cmake'):
                path=cmake/rel;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'build')
            (cmake/'CMakeFiles/3.2/CMakeCCompiler.cmake').write_text(f'set(CMAKE_C_COMPILER "{self.tools["cc"]}")\nset(CMAKE_C_COMPILER_ID "GNU")\nset(CMAKE_C_COMPILER_VERSION "14.2.0")\n')
        elif command[:2]==['bun','--version']:out='wrong' if self.fault=='version' else 'mock-bun\n'
        elif command[:2]==['clang','--version']:out='mock clang\n'
        elif '-o' in command:
            for i,arg in enumerate(command[:-1]):
                if arg=='-o' and self.fault!='missing-output':Path(command[i+1]).write_bytes(b'program')
        else:
            executable=Path(command[1] if command[0]=='bun' else command[0]);name=executable.stem
            if name=='qualification':
                q=dict(controls=9,little_endian=True,round_to_nearest=True,signed_char_wrap=True)
                if self.fault=='qualification':q['controls']=9.0
                out=json.dumps(q)
            elif name in ('reference','candidate-0'):
                native=name=='reference'
                for c in self.cases:
                    encoded=literal_stream(c) if c['format'] in P['ACCEPTED'] else None
                    path=self.work/('reference-'+c['id']+'.qoi') if native else P['output_path'](self.work,c)
                    if encoded:path.write_bytes(encoded+(b'bad' if self.fault=='real-file' and not native else b''))
                    if self.fault=='rejection-touch' and not native and c['format'] in P['REJECTED']:path.write_bytes(b'bad')
                    if self.fault=='absent-touch' and not native and c['format'] in P['REJECTED']:Path(str(path)+'.qoi.absent.qoi').write_bytes(b'bad')
                    out+=observation(c,encoded)
                if not native:
                    if self.fault=='missing-record':out=''
                    if self.fault=='extra-record':out+=out
                    if self.fault=='metadata':out=out.replace('"format": 4','"format": 7',1)
            elif name in ('ordinary','failure'):
                marker=json.dumps(dict(iterations=100,accepted_writes=200,rejected_writes=1800))+'\n'
                if name=='failure':(self.work/'post-open.dat').write_bytes(b'' if self.fault!='truncation' else b'old');out=marker
                else:(self.work/'repeated.dat').write_bytes(literal_stream(case(7,[17]*4)));out=marker*3+'{"final_success":true}\n'
                if self.fault=='io-count':out=out.replace('1800','1799')
                if self.fault=='io-final-type':out=out.replace('true','1')
            else:raise AssertionError(command)
        return subprocess.CompletedProcess(command,0,out,'')

    def execute(self,fault=None):
        self.fault=fault
        with patch.dict(G,ROOT=self.root,BUILD=self.root/'.build',fixtures=lambda:copy.deepcopy(self.cases),tracked_sources=self.sources,checkout=self.checkout,coverage=lambda *a:dict(mocked=True)),patch('shutil.which',side_effect=lambda tool:self.tools[tool]),patch('subprocess.run',side_effect=self.process),redirect_stdout(io.StringIO()):
            P['main'](['--bend-source',str(self.root/'bend'),'--raylib-source',str(self.root/'raylib'),'--build-dir',str(self.destination),'--timeout','23'])
        return json.loads(self.report.read_text())

    def test_complete_pipeline_records_distinct_lanes_fresh_archive_environment(self):
        result=self.execute();self.assertIs(result['passed'],True);self.assertEqual(result['images'],4);self.assertEqual(result['accepted'],2);self.assertEqual(result['rejected'],2)
        self.assertEqual(set(result['lanes']),{'cpu-1','cpu-2','javascript'});self.assertEqual(result['native_build']['mode'],'fresh-isolated-build')
        self.assertEqual(result['native_build']['compiler']['CMAKE_C_COMPILER_ID'],'GNU');self.assertEqual(result['native_build']['sources'],result['sources'])
        self.assertEqual((self.destination/'old').read_bytes(),b'not reused');self.assertEqual(len(self.checkouts),4)
        for command,kw in self.commands:
            self.assertEqual(kw['timeout'],23)
            if command[0] in ('clang','cmake') or command[0].endswith(('/reference','/qualification')):
                self.assertNotIn('LD_PRELOAD',kw['env'])
        for lane,r in result['lanes'].items():
            self.assertIs(r['passed'],True);self.assertEqual(sum(b['images'] for b in r['batches']),4)
            self.assertEqual(r['ordinary']['accepted_writes']+r['failure']['accepted_writes'],801)
            self.assertEqual(r['ordinary']['rejected_writes']+r['failure']['rejected_writes'],7200)
            self.assertIn(r['failure']['retained_file'],result['sealed_artifacts'])
        for name in ('qualification.c','reference.c','candidate-0.bend','candidate-0','candidate-0.js','inputs.json','cpu-1-0.stdout','cpu-1-0.command.json','directory/sentinel'):
            self.assertIn(str(self.work/name),result['sealed_artifacts'])

    def test_wrong_files_owners_metadata_process_output_and_io_cannot_pass(self):
        for fault in ('version','qualification','missing-output','real-file','rejection-touch','absent-touch','missing-record','extra-record','metadata','truncation','io-count','io-final-type'):
            with self.subTest(fault=fault):
                self.setUp()
                with self.assertRaises(ValueError):self.execute(fault)
                self.assertIs(json.loads(self.report.read_text())['passed'],False)

    def test_final_source_and_all_evidence_drift_cannot_pass(self):
        for fault in ('library','dependency','compiler','archive','inputs','generated','binary','stdout','command','retained','native-file','io-file','tool','deleted','pin'):
            with self.subTest(fault=fault):
                self.setUp()
                with self.assertRaises(ValueError):self.execute(fault)
                self.assertIs(json.loads(self.report.read_text())['passed'],False)


class SourceInventoryTests(unittest.TestCase):
    def test_required_native_library_compiler_and_proof_dependencies(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);bend=root/'bend';ray=root/'raylib'
            paths=[root/p for p in ('tools/formatted_qoi_export_probe.py','tools/byte_probe.py','tools/image_export_probe.py','tools/image_format_probe.py','tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','tests/test_formatted_qoi_export.py','toolchain.json','LAWS.bend','PROOF.bend')]
            paths += [ray/'src'/p for p in ('rtextures.c','rcore.c','raylib.h','config.h','external/qoi.h')]
            paths += [bend/'bend2'/('compiler'+suffix) for suffix in ('.ts','.bend','.c','.js','.h')]
            for path in paths:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'source')
            args=argparse.Namespace(bend_source=bend,raylib_source=ray)
            with patch.dict(G,ROOT=root,source_gate=lambda:dict(library='hash')):
                before=P['tracked_sources'](args);self.assertEqual(set(before['dependencies']),set(map(str,paths)))
                for path in paths:
                    path.write_bytes(b'changed');self.assertNotEqual(P['tracked_sources'](args),before);path.write_bytes(b'source')


if __name__=='__main__':unittest.main()
