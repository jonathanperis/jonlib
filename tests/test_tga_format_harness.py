import copy
import io
import json
import os
import signal
import time
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import tga_format_probe as p


def tiny(channels=1,extended=False):
    return dict(id='tiny',width=1,height=1,channels=channels,bytes=p.targa(1,1,channels,range(17,17+channels)),extended=extended)


def unit_actions(count=1):
    result=[]
    for index in range(count):
        case=dict(tiny(),id='unit-'+str(index))
        result.append(dict(case=case,role='raw',expected=dict(p.meta(case,'raw'),bytes=[17]),normalized=[17,17,17,255]))
    return result


def lanes_for(partitions):
    return {lane:dict(passed=False,batches=[dict(entry,bytes=entry['compared_bytes'],passed=True) for entry in partitions],differences=[]) for lane in p.LANES}


def encoded(action,values):
    return '\n'.join(json.dumps(v) for v in [p.meta(action['case'],action['role']),*[values[i:i+256] for i in range(0,len(values),256)],'end'])+'\n'


def flags():return 'C_DEFINES = -DEXTERNAL_CONFIG_FLAGS -DPLATFORM_MEMORY -DSUPPORT_FILEFORMAT_TGA\n'


def cache():
    return '\n'.join(k+':STRING='+v for k,v in dict(PLATFORM='Memory',CMAKE_BUILD_TYPE='Release',CUSTOMIZE_BUILD='ON',SUPPORT_FILEFORMAT_TGA='ON',SUPPORT_MODULE_RAUDIO='OFF',BUILD_EXAMPLES='OFF',USE_EXTERNAL_GLFW='OFF').items())+'\n'


class TgaProtocolTests(unittest.TestCase):
    def setUp(self):self.case=tiny();self.action=dict(case=self.case,role='raw');self.row=p.meta(self.case,'raw')

    def text(self,row=None,parts=None):return '\n'.join(json.dumps(v) for v in [self.row if row is None else row,*([[17],'end'] if parts is None else parts)])+'\n'

    def test_complete_raw_gray_rgb_and_normalized(self):
        self.assertEqual(p.parse_rows(self.text(),[self.action]),[dict(self.row,bytes=[17])])
        c=tiny(3)
        for role,values,fmt in [('raw',[17,18,19],4),('normalized',[17,18,19,255],7),('alias-TGA',[17,18,19],4)]:
            a=dict(case=c,role=role);self.assertEqual(p.parse_rows(encoded(a,values),[a])[0]['format'],fmt)

    def test_gray_alpha_and_rgba_complete_raw_payload(self):
        for channels in (2,4):
            c=tiny(channels);a=dict(case=c,role='raw');values=list(range(channels))
            row=p.parse_rows(encoded(a,values),[a])[0]
            self.assertEqual(row['format'],p.FORMATS[channels]);self.assertEqual(row['bytes'],values)

    def test_nonfinite_json_rejected_recursively(self):
        for text in ('NaN','Infinity','-Infinity','[NaN]','{"ignored":Infinity}','1e999','[-1e999]'):
            with self.assertRaises(ValueError):p.strict_json(text)
        for value in ('NaN','Infinity','-Infinity'):
            with self.assertRaises(ValueError):p.parse_rows(self.text().replace('[17]','['+value+']'),[self.action])

    def test_exact_metadata_fields_types_and_order(self):
        for key,value in [('id','other'),('role','bridge'),('width',2),('height',2),('format',4),('mipmaps',2),('width',True),('height',1.0),('mipmaps',True),('format',1.0),('extra',0)]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):p.parse_rows(self.text(dict(self.row,**{key:value})),[self.action])
        for key in self.row:
            row=self.row.copy();del row[key]
            with self.subTest(missing=key),self.assertRaises(ValueError):p.parse_rows(self.text(row),[self.action])
        with self.assertRaises(ValueError):p.parse_rows(self.text()+encoded(dict(case=self.case,role='bridge'),[17]*4),[dict(case=self.case,role='bridge'),self.action])
        with self.assertRaises(ValueError):p.meta(self.case,'rejected')

    def test_bad_framing_empty_missing_extra_and_byte_types(self):
        variants=['',self.text().replace('"end"\n',''),self.text()+self.text(),self.text()+'"end"\n']
        variants += [self.text(parts=parts) for parts in (['end'],[[],'end'],[[17,18],'end'],[[0]*257,'end'],[None],[[True],'end'],[[17.0],'end'],[[256],'end'],[[-1],'end'],[[17],False],[[17],'END'])]
        for text in variants:
            with self.subTest(text=text[:70]),self.assertRaises(ValueError):p.parse_rows(text,[self.action])
        with self.assertRaises(ValueError):p.parse_rows('',[])

    def test_chunk_boundaries_and_partial_chunk_rejection(self):
        c=dict(self.case,width=257);a=dict(case=c,role='raw');data=[i%256 for i in range(257)]
        self.assertEqual(p.parse_rows(encoded(a,data),[a])[0]['bytes'],data)
        text='\n'.join(json.dumps(v) for v in [p.meta(c,'raw'),[1],[0]*256,'end'])
        with self.assertRaises(ValueError):p.parse_rows(text,[a])

    def test_duplicate_json_fields_reject(self):
        with self.assertRaises(ValueError):p.strict_json('{"format":1,"format":4}')
        with self.assertRaises(ValueError):p.parse_rows(self.text().replace('"width": 1','"width": 1,"width": 1'),[self.action])

    def test_typed_errors_have_distinct_entrypoint_roles(self):
        c=p.controls()[0]
        for role in ('formatted-error','surface-error'):
            action=dict(case=c,role=role);row=dict(id=c['id'],role=role,error=c['error'])
            self.assertEqual(p.parse_rows(json.dumps(row),[action]),[row])
            for value in (99,True,0.0):
                with self.assertRaises(ValueError):p.parse_rows(json.dumps(dict(row,error=value)),[action])
            with self.assertRaises(ValueError):p.parse_rows(json.dumps(row)+'\n"end"',[action])
            with self.assertRaises(ValueError):p.parse_rows(json.dumps(dict(row,role='surface-error' if role=='formatted-error' else 'formatted-error')),[action])

    def test_all_byte_differences_are_retained(self):
        rows=[dict(self.row,bytes=[1,2,3]),dict(self.row,bytes=[4,5,6])]
        actual=[dict(self.row,bytes=[9,2,8]),dict(self.row,bytes=[4,0,6])]
        delta=p.differences(rows,actual)
        self.assertEqual([[d['index'] for d in r['byte_differences']] for r in delta],[[0,2],[1]])
        with self.assertRaises(ValueError):p.differences(rows,actual[:1])


class TgaSafetyAndSourceTests(unittest.TestCase):
    def test_all_legacy_inputs_preserved_and_new_counts_derived(self):
        cases=p.fixtures();by_id={c['id']:c for c in cases};legacy=p.legacy_fixtures()[0]
        self.assertEqual(len(legacy),64);self.assertEqual(len(cases),169)
        self.assertEqual(sum(c['width']*c['height'] for c in cases),61857)
        self.assertEqual(len(by_id),len(cases));self.assertEqual({c['channels'] for c in cases},{1,2,3,4})
        for c in legacy:self.assertEqual(by_id['legacy-'+c['id']]['bytes'],c['bytes'])
        p.validate_cases(cases)
        c=by_id['ignored-direct-palette-metadata'];self.assertEqual(c['bytes'][1],0);self.assertEqual(c['bytes'][3:8],[255]*5)
        self.assertEqual(p.inspect_header(c['bytes'])['channels'],2);self.assertEqual(p.meta(c,'raw')['format'],2)

    def test_four_layouts_all_allocation_shapes_nonuniform(self):
        by_id={c['id']:c for c in p.fixtures()}
        for channels in (1,2,3,4):
            for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63)]:
                c=by_id[f'c{channels}-{name}'];self.assertEqual((c['width'],c['height'],c['channels']),(w,h,channels))
                self.assertEqual(p.meta(c,'raw')['format'],p.FORMATS[channels])
                if w*h>1:self.assertGreater(len(set(c['bytes'][18:])),10)

    def test_gray_alpha_ramps_and_identical16_semantic_discriminators(self):
        by_id={c['id']:c for c in p.fixtures()}
        self.assertEqual(by_id['c1-ramp']['bytes'][18:],list(range(256)))
        self.assertEqual(by_id['c2-alpha-ramp']['bytes'][19::2],list(range(256)))
        self.assertEqual(set(by_id['c2-alpha-ramp']['bytes'][18::2]),{37})
        for top in (False,True):
            for rle in (False,True):
                a=by_id[f'identical16-kind2-{top}-{rle}'];b=by_id[f'identical16-kind3-{top}-{rle}']
                self.assertEqual(a['bytes'][:2]+a['bytes'][3:],b['bytes'][:2]+b['bytes'][3:])
                self.assertEqual((p.inspect_header(a['bytes'])['channels'],p.inspect_header(b['bytes'])['channels']),(3,2))

    def test_palette_depth_independent_of_index_width_and_orientation(self):
        by_id={c['id']:c for c in p.fixtures()}
        for depth in (8,15,16,24,32):
            for index_bits in (8,16):
                for top in (False,True):
                    for rle in (False,True):
                        c=by_id[f'palette-{depth}-{index_bits}-{top}-{rle}'];observed=p.inspect_header(c['bytes'])
                        self.assertEqual(observed['channels'],1 if depth==8 else 4 if depth==32 else 3)
                        self.assertEqual(observed['palette_bits'],depth);self.assertEqual(observed['bits'],index_bits)
                        self.assertEqual(observed['palette_skip'],3 if index_bits==8 else 5)
                        self.assertEqual(bool(c['bytes'][17]&32),top);self.assertEqual(observed['kind'],9 if rle else 1)
        # Byte skips are deliberately not palette-entry multiples.
        self.assertEqual(p.inspect_header(by_id['palette-32-8-True-True']['bytes'])['header_bytes'],18+6+3+12)

    def test_packet_limits_cross_rows_and_complete_tails(self):
        by_id={c['id']:c for c in p.fixtures()}
        for c in (1,2,3,4):
            for n in (127,128,129):
                for repeat in (False,True):
                    case=by_id[f'c{c}-packet-{n}-{repeat}'];info=p.inspect_header(case['bytes'])
                    self.assertEqual(case['width']*case['height'],n);self.assertGreater(case['height'],1)
                    self.assertEqual(case['bytes'][18],(128 if repeat else 0)+min(n,128)-1)
                    self.assertEqual(info['tail_bytes'],0)
            case=by_id[f'c{c}-max-id-tail'];info=p.inspect_header(case['bytes'])
            self.assertEqual(case['bytes'][0],255);self.assertEqual(case['bytes'][18:273],list(range(255)))
            self.assertEqual(info['header_bytes'],273);self.assertEqual(info['tail_bytes'],18)
            self.assertTrue(case['bytes'][17]&16)

    def test_native_case_safety_fails_closed_and_checks_declarations(self):
        c=tiny()
        changes=[dict(width=0),dict(width=4097),dict(width=True),dict(height=1.0),dict(channels=2),dict(extended=1),dict(id='unsafe"id'),dict(bytes=c['bytes'][:-1]),dict(bytes=[*c['bytes'],256]),dict(bytes=[*c['bytes'],True]),dict(native=True)]
        for change in changes:
            with self.subTest(change=change),self.assertRaises(ValueError):p.validate_cases([dict(c,**change)])
        for cases in ([],[c,c],p.controls()[:1]):
            with self.assertRaises(ValueError):p.validate_cases(cases)
        with patch.object(p,'MAX_TOTAL_BYTES',1),self.assertRaises(ValueError):p.validate_cases([c])
        with self.assertRaises(ValueError):p.inspect_header(p.targa(4096,4096,1,[0]))
        for field in c:
            bad=c.copy();del bad[field]
            with self.assertRaises(ValueError):p.validate_cases([bad])

    def test_complete_stream_safety_checks_every_header_palette_and_packet(self):
        # No malformed control reaches the native C program or oracle.
        for control in p.controls():
            with self.subTest(control=control['id']),self.assertRaises(ValueError):p.inspect_header(control['bytes'])
        for data in (p.indexed_targa(1,1,[b'\1\2'],8,16,[]),p.targa(2,1,4,[1,0,0,0],rle=True)):
            with self.assertRaises(ValueError):p.inspect_header(data)
        # Direct streams ignore unused palette metadata, as the pinned reader does.
        direct=p.targa(1,1,1,[17]);direct[3:8]=[255]*5
        self.assertEqual(p.inspect_header(direct)['channels'],1)

    def test_controls_checked_only_and_explicit_error_precedence(self):
        controls=p.controls();by_id={c['id']:c for c in controls}
        self.assertEqual(len(controls),155);self.assertEqual(len(p.legacy_fixtures()[1]),23)
        for c in p.legacy_fixtures()[1]:self.assertEqual(by_id['legacy-'+c['id']]['bytes'],c['bytes']);self.assertEqual(by_id['legacy-'+c['id']]['error'],c['error'])
        for name,error in [('bad-byte-before-bad-header',1),('bad-byte-before-bad-size',1),('bad-header-before-bad-size',0),('bad-size-before-truncated',2),('overrun-before-truncated',4),('palette-skip-truncated',3),('invalid-byte-palette-skip',1),('invalid-byte-palette-index',1)]:self.assertEqual(by_id[name]['error'],error)
        with self.assertRaises(ValueError):p.reference_program(controls)
        for change in (dict(error=True),dict(error=5),dict(bytes=[-1]),dict(bytes=[True]),dict(extra=1)):
            with self.assertRaises(ValueError):p.validate_controls([dict(controls[0],**change)])
        with self.assertRaises(ValueError):p.validate_controls([dict(id='accepted',bytes=tiny()['bytes'],error=3)])
        with self.assertRaises(ValueError):p.validate_controls([controls[0],controls[0]])

    def test_native_actual_raw_precedes_normalization_and_alias_reload(self):
        for channels in (1,2,3,4):
            c=tiny(channels,extended=True);program=p.reference_program([c])
            self.assertLess(program.index('"raw",image)'),program.index('ImageFormat(&image,7)'))
            self.assertLess(program.index('ImageFormat(&image,7)'),program.index('"normalized",image)'))
            for token in ('.tga','.TGA'):self.assertIn('LoadImageFromMemory("'+token+'"',program)
            for text in ('if(!little_endian())','image.mipmaps!=1',f'image.format!={p.FORMATS[channels]}',f'GetPixelDataSize(image.width,image.height,image.format)!={channels}','GetPixelDataSize(image.width,image.height,image.format)!=4'):self.assertIn(text,program)
            self.assertEqual(program.count('Image image=LoadImageFromMemory'),1);self.assertEqual(program.count('image=LoadImageFromMemory'),2)
            self.assertNotIn('LoadImageColors',program);self.assertNotIn('stbi_load',program)
            self.assertEqual([a['role'] for a in p.native_actions([c])],['raw','normalized','alias-TGA'])

    def test_native_config_requires_single_enabled_definition_for_every_macro(self):
        self.assertEqual(p.validate_native_config(cache(),flags())['SUPPORT_FILEFORMAT_TGA'],'ON')
        commented='// Generated cache\n\n'+'\n// option\n'.join(cache().splitlines())+'\n'
        self.assertEqual(p.validate_native_config(commented,flags())['PLATFORM'],'Memory')
        with self.assertRaises(ValueError):p.validate_native_config(cache()+'PLATFORM:STRING=Memory\n',flags())
        for macro in ('SUPPORT_FILEFORMAT_TGA','EXTERNAL_CONFIG_FLAGS','PLATFORM_MEMORY'):
            self.assertEqual(p.validate_native_config(cache(),flags().replace('-D'+macro,'-D '+macro+'=1'))['PLATFORM'],'Memory')
            for broken in (flags().replace(' -D'+macro,''),flags()+' -D'+macro,flags()+' -U'+macro,flags()+' -U '+macro,flags()+' -D '+macro+'=0',flags().replace('-D'+macro,'-D'+macro+'=0')):
                with self.subTest(macro=macro,flags=broken),self.assertRaises(ValueError):p.validate_native_config(cache(),broken)
        with self.assertRaises(ValueError):p.validate_native_config(cache(),flags()+' -DPLATFORM_DESKTOP')
        for old,new in [('TGA:STRING=ON','TGA:STRING=OFF'),('CUSTOMIZE_BUILD:STRING=ON','CUSTOMIZE_BUILD:STRING=OFF'),('PLATFORM:STRING=Memory','PLATFORM:STRING=Desktop'),('CMAKE_BUILD_TYPE:STRING=Release','CMAKE_BUILD_TYPE:STRING=Debug')]:
            with self.assertRaises(ValueError):p.validate_native_config(cache().replace(old,new),flags())

    def test_native_qualification_exact_typed_four_formats_direct16_palette_width(self):
        row=dict(little_endian=True,tga_enabled=True,direct16_distinct=True,palette_index_widths=[8,16],formats=[1,2,4,7]);self.assertEqual(p.qualification(json.dumps(row)),row)
        for key,value in [('little_endian',False),('tga_enabled',False),('direct16_distinct',1),('palette_index_widths',[8,16.0]),('formats',[True,2,4,7]),('formats',[1,2,4]),('extra',True)]:
            with self.subTest(key=key),self.assertRaises(ValueError):p.qualification(json.dumps(dict(row,**{key:value})))
        self.assertIn('uint16_t word=1',p.QUALIFY);self.assertIn('if(!little_endian())return 10',p.QUALIFY)
        for text in ('gray-alpha','packed16','image.format!=1','image.format!=2','image.format!=4','image.format!=7'):self.assertIn(text,p.QUALIFY)
        for depth in (8,15,16,24,32):
            for width in (8,16):self.assertIn(f'palette-{depth}-{width}',p.QUALIFY)

    def test_candidate_ownership_high_bits_factory_error_routes_and_no_pixel_oracle(self):
        for channels in (1,2,3,4):
            c=tiny(channels,extended=True);rows=[]
            for a in p.native_actions([c]):rows.append(dict(p.meta(c,a['role']),bytes=[17]*4 if a['role']=='normalized' else [17]*channels))
            actions,_=p.candidate_actions([c],p.controls()[:1],rows);program=p.candidate_program(actions)
            for text in ('word <= 255','word <= 65535','word <= 16777215','U32.is_eq(format, 7)','+format: U32','(pixels, +word)','J.Image.Formatted.decode_tga','J.Image.Formatted.to_surface','J.Surface.to_formatted','J.Image.Formatted.from_bytes','J.Image.Formatted.get','J.Surface.decode_tga','J.Surface.decode_image(','J.UncontractedDecode{}','J.FusedDecode{}','J.Image.Formatted.export(image)','owner.read(result, 0, 0, Some{first})','(width - 1 : U32)','4294967295, 0, None{}','0, 4294967295, None{}','formatted.error(J.Image.Formatted.decode_tga','surface.error(J.Surface.decode_tga'):
                self.assertIn(text,program)
            self.assertIn(f'J.Image.Formatted.from_bytes(1, 1, {p.FORMATS[channels]},',program)
            self.assertNotIn('Image.Formatted.convert',program)
            rows[-1]['bytes']=[18]*channels
            with self.assertRaises(ValueError):p.candidate_actions([c],[],rows)

    def test_candidate_reference_rejects_order_metadata_missing_and_extra(self):
        c=tiny();rows=[dict(p.meta(c,'raw'),bytes=[17]),dict(p.meta(c,'normalized'),bytes=[17]*3+[255])]
        for bad in (rows[::-1],rows[:1],rows+rows, [dict(rows[0],bytes=[True]),rows[1]],[dict(rows[0],mipmaps=2),rows[1]],[dict(rows[0],width=True),rows[1]]):
            with self.assertRaises(ValueError):p.candidate_actions([c],[],bad)


class TgaRunnerTests(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.work=Path(self.tmp.name);p.SEALED.clear()
    def tearDown(self):p.SEALED.clear();self.tmp.cleanup()

    def test_seal_rejects_changed_missing_and_resealing(self):
        path=self.work/'source';path.write_text('one');p.seal(path);p.verify_sealed();path.write_text('two')
        with self.assertRaises(ValueError):p.verify_sealed()
        with self.assertRaises(ValueError):p.seal(path)
        path.unlink()
        with self.assertRaises(ValueError):p.verify_sealed()

    def test_record_success_retains_environment_command_and_streams(self):
        fake=subprocess.CompletedProcess(['tool'],0,'ok\n','warning\n');env={'ONLY':'native'};receipt={'policy':'clean-loader'}
        with patch.object(p,'run_process_group',return_value=fake) as run:
            self.assertEqual(p.record_run(['tool'],self.work,'success',environment=env,receipt=receipt,require_output=True),'ok\n')
        self.assertEqual(run.call_args.kwargs['env'],env)
        row=json.loads((self.work/'success.command.json').read_text());self.assertEqual(row['reference_environment'],receipt);self.assertEqual(row['exit_code'],0)
        self.assertEqual((self.work/'success.stderr').read_text(),'warning\n');p.verify_sealed()

    def test_failed_native_exit_empty_output_and_missing_compiler_output(self):
        for name,result,command,require in [('failed',subprocess.CompletedProcess([],9,'partial','bad'),['tool'],False),('empty',subprocess.CompletedProcess([],0,'',''),['tool'],True),('compiler',subprocess.CompletedProcess([],0,'ok',''),['tool','-o',str(self.work/'out')],False)]:
            with self.subTest(name=name),patch.object(p,'run_process_group',return_value=result),self.assertRaises(ValueError):p.record_run(command,self.work,name,require_output=require)
            self.assertTrue((self.work/(name+'.command.json')).is_file())

    def test_stale_compiler_output_cannot_be_reused(self):
        path=self.work/'out';path.write_text('stale')
        with patch.object(p,'run_process_group',return_value=subprocess.CompletedProcess([],0,'','')),self.assertRaises(ValueError):p.record_run(['compiler','-o',path],self.work,'stale')
        self.assertFalse(path.exists())

    def test_timeout_retains_failed_receipt_and_partial_streams(self):
        error=subprocess.TimeoutExpired(['tool'],1,output=b'partial',stderr=b'waiting')
        with patch.object(p,'run_process_group',side_effect=error),self.assertRaises(ValueError):p.record_run(['tool'],self.work,'timeout',timeout=1)
        row=json.loads((self.work/'timeout.command.json').read_text());self.assertTrue(row['timed_out']);self.assertIsNone(row['exit_code'])
        self.assertEqual((self.work/'timeout.stdout').read_text(),'partial');self.assertEqual((self.work/'timeout.stderr').read_text(),'waiting')

    def test_stale_report_reset_before_invalid_arguments(self):
        target=self.work/'report';target.mkdir();path=target/'results.json';path.write_text('{"passed":true}')
        with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):p.main(['--build-dir',str(target),'--bad'])
        self.assertFalse(json.loads(path.read_text())['passed'])

    def test_all_duplicate_destinations_reset_and_exact_token_classification(self):
        a=self.work/'a';b=self.work/'b'
        for dest in (a,b):dest.mkdir();(dest/'results.json').write_text('{"passed":true}')
        self.assertEqual(p.admit_directories(['--build-dir',str(a),'--build-dir='+str(b)]),b.resolve())
        self.assertFalse(json.loads((a/'results.json').read_text())['passed']);self.assertFalse(json.loads((b/'results.json').read_text())['passed'])
        self.assertEqual(p.report_directories(['--build-di',str(a)]),[p.BUILD/'tga-format-probe'])
        self.assertEqual(p.report_directories(['--','--build-dir',str(a)]),[p.BUILD/'tga-format-probe'])

    def test_mandatory_lanes_complete_contiguous_typed_and_nonempty(self):
        actions=unit_actions();partitions=p.plan_partitions(actions);lanes=lanes_for(partitions)
        good=copy.deepcopy(lanes);p.finish_lanes(good,actions,partitions);self.assertTrue(all(v['passed'] for v in good.values()))
        variants=[]
        for key,value in [('start',False),('start',1),('count',True),('count',0),('count',33),('passed',False)]:
            bad=copy.deepcopy(lanes);bad['cpu-1']['batches'][0][key]=value;variants.append(bad)
        bad=copy.deepcopy(lanes);del bad['javascript'];variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-2']['differences']=[{}];variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-2']['batches']=[];variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):p.finish_lanes(bad,actions,partitions)
        with self.assertRaises(ValueError):p.finish_lanes(lanes,[],[])

    def test_native_build_explicit_tga_and_configuration_checked_before_execution(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))();commands=[]
        def record(command,work,label,**kwargs):
            commands.append(list(map(str,command)))
            if label=='configure':
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(cache());(directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(flags().replace(' -DSUPPORT_FILEFORMAT_TGA',''))
        with self.assertRaises(ValueError):p.native_archive(args,self.work,record)
        self.assertEqual(len(commands),1);self.assertIn('-DSUPPORT_FILEFORMAT_TGA=ON',commands[0]);self.assertIn('-DCUSTOMIZE_BUILD=ON',commands[0])


class TgaFailureEvidenceTests(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.work=Path(self.tmp.name);p.SEALED.clear()
    def tearDown(self):p.SEALED.clear();self.tmp.cleanup()

    def test_failed_and_timedout_compiler_outputs_are_sealed(self):
        for timeout in (False,True):
            p.SEALED.clear();output=self.work/('timedout' if timeout else 'failed')
            def run(*args,**kwargs):
                output.write_bytes(b'partial compiler bytes')
                if timeout:raise subprocess.TimeoutExpired(['compiler'],1,output='partial',stderr='timeout')
                return subprocess.CompletedProcess([],9,'partial','error')
            with patch.object(p,'run_process_group',side_effect=run),self.assertRaises(ValueError):p.record_run(['compiler','-o',output],self.work,output.name)
            self.assertIn(str(output.resolve()),p.SEALED);p.verify_sealed()
            receipt=json.loads((self.work/(output.name+'.command.json')).read_text())
            self.assertEqual(receipt['artifacts'][str(output)],p.digest(output))
            output.write_bytes(b'drift')
            with self.assertRaises(ValueError):p.verify_sealed()

    def test_native_build_refuses_preexisting_directory(self):
        (self.work/'raylib-build').mkdir();args=type('Args',(),dict(raylib_source=self.work/'source'))()
        with self.assertRaises(ValueError):p.native_archive(args,self.work,lambda *a,**k:self.fail('Stale native build attempted'))

    def test_loader_clean_children_parent_unchanged_and_receipt_checked(self):
        import os
        from reference_environment import LOADER_NAMES
        with patch.dict(os.environ,{name:'qualification-parent' for name in LOADER_NAMES}):
            before=dict(os.environ);environment=p.ReferenceEnvironment('clean-loader')
            child=environment.child();self.assertTrue(all(name not in child for name in LOADER_NAMES))
            self.assertEqual(dict(os.environ),before);environment.assert_receipt(environment.receipt())
            receipt=environment.receipt();receipt['policy']='inherited'
            with self.assertRaises(ValueError):environment.assert_receipt(receipt)
            os.environ[LOADER_NAMES[0]]='changed'
            with self.assertRaises(ValueError):environment.assert_unchanged()

    def test_startup_failure_retains_sealed_receipt_and_streams(self):
        with patch.object(p,'run_process_group',side_effect=FileNotFoundError('tool absent')),self.assertRaises(ValueError):p.record_run(['missing'],self.work,'startup')
        receipt=json.loads((self.work/'startup.command.json').read_text())
        self.assertEqual(receipt['startup_error'],'FileNotFoundError');self.assertIsNone(receipt['exit_code'])
        self.assertIn('tool absent',(self.work/'startup.stderr').read_text());p.verify_sealed()

    def test_runtime_failure_retains_partial_report_and_durable_seals(self):
        target=self.work/'report';target.mkdir();report=target/'results.json'
        def failing(argv):
            report.write_text(json.dumps(dict(passed=False,lanes={'cpu-1':{'passed':False}},phase='native')))
            path=self.work/'partial';path.write_text('observed bytes');p.seal(path)
            raise ValueError('native failed')
        with patch.object(p,'run_probe',side_effect=failing),self.assertRaises(ValueError):p.main(['--build-dir',str(target)])
        result=json.loads(report.read_text());self.assertFalse(result['passed']);self.assertEqual(result['phase'],'native')
        self.assertEqual(result['failure'],dict(type='ValueError',message='native failed'))
        self.assertEqual(result['sealed_artifacts'][str((self.work/'partial').resolve())],p.digest(self.work/'partial'))
        self.assertIn('cpu-1',result['lanes'])

    def test_native_archive_success_seals_config_and_compiler_before_build(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))();labels=[];compiler=self.work/'compiler';compiler.write_text('compiler')
        def record(command,work,label,**kwargs):
            labels.append(label)
            if label=='configure':
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeFiles/version').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(cache());(directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(flags())
                (directory/'CMakeFiles/version/CMakeCCompiler.cmake').write_text('set(CMAKE_C_COMPILER "'+str(compiler)+'")\nset(CMAKE_C_COMPILER_ID "Clang")\nset(CMAKE_C_COMPILER_VERSION "1")\n')
            elif label=='native-build':
                self.assertIn(str(compiler.resolve()),p.SEALED)
                self.assertIn(str((work/'raylib-build/CMakeCache.txt').resolve()),p.SEALED)
                (work/'raylib-build/raylib/libraylib.a').write_bytes(b'archive')
            return 'compiler version 1'
        archive,receipt=p.native_archive(args,self.work,record)
        self.assertEqual(labels,['configure','archive-compiler-version','native-build'])
        self.assertEqual(receipt['mode'],'fresh-isolated-build');self.assertEqual(receipt['artifacts'][str(archive)],p.digest(archive));p.verify_sealed()

    def test_finish_lanes_does_not_mark_partial_success(self):
        actions=unit_actions();partitions=p.plan_partitions(actions);lanes=lanes_for(partitions)
        lanes['javascript']['batches']=[]
        with self.assertRaises(ValueError):p.finish_lanes(lanes,actions,partitions)
        self.assertTrue(all(row['passed'] is False for row in lanes.values()))


class TgaPartitionTests(unittest.TestCase):
    def test_empty_actions_invalid_budget_empty_program_and_oversized_singleton_reject(self):
        with self.assertRaises(ValueError):p.plan_partitions([])
        for budget in (0,-1,True,1.0,p.SOURCE_BYTE_LIMIT+1):
            with self.subTest(budget=budget),self.assertRaises(ValueError):p.plan_partitions(unit_actions(),budget)
        with patch.object(p,'candidate_program',return_value=''),self.assertRaises(ValueError):p.plan_partitions(unit_actions())
        with patch.object(p,'candidate_program',side_effect=lambda actions:'x'*(10 if actions[0]['case']['id']=='unit-0' else p.SOURCE_BYTE_LIMIT+1)),self.assertRaises(ValueError):p.plan_partitions(unit_actions(33))
        with patch.object(p,'candidate_program',return_value='x'*(p.SOURCE_BYTE_LIMIT+1)),self.assertRaisesRegex(ValueError,'singleton'):p.plan_partitions(unit_actions())

    def test_max32_is_preserved_and_planning_is_deterministic(self):
        actions=unit_actions(65);first=p.plan_partitions(actions);self.assertEqual(first,p.plan_partitions(copy.deepcopy(actions)))
        self.assertEqual([(b['start'],b['count']) for b in first],[(0,32),(32,32),(64,1)])
        p.validate_partitions(actions,first)
        self.assertEqual(sum(b['compared_bytes'] for b in first),65)

    def test_utf8_source_cap_exact_boundary_and_greedy_order(self):
        actions=unit_actions(5)
        with patch.object(p,'candidate_program',side_effect=lambda selected:'é'*len(selected)):
            plan=p.plan_partitions(actions,4)
            self.assertEqual([(b['start'],b['count'],b['source_bytes']) for b in plan],[(0,2,4),(2,2,4),(4,1,2)])
            p.validate_partitions(actions,plan,4)
            with self.assertRaises(ValueError):p.plan_partitions(actions,1)
        with patch.object(p,'candidate_program',return_value='x'*p.SOURCE_BYTE_LIMIT):
            plan=p.plan_partitions(unit_actions());self.assertEqual(plan[0]['source_bytes'],p.SOURCE_BYTE_LIMIT)

    def test_plan_rejects_empty_missing_extra_gap_overlap_type_hash_and_budget_drift(self):
        actions=unit_actions(33);plan=p.plan_partitions(actions);variants=[[],plan[:-1],plan+plan,plan[::-1]]
        for key,value in [('start',True),('start',1),('count',False),('count',0),('count',33),('source_bytes',True),('source_bytes',0),('source_bytes',p.SOURCE_BYTE_LIMIT+1),('source_sha256','0'*64),('actions_sha256','0'*64),('compared_bytes',True),('compared_bytes',0),('extra',1)]:
            bad=copy.deepcopy(plan);bad[0][key]=value;variants.append(bad)
        for start in (31,33):
            bad=copy.deepcopy(plan);bad[1]['start']=start;variants.append(bad)
        for bad in variants:
            with self.subTest(plan=bad[:1]),self.assertRaises(ValueError):p.validate_partitions(actions,bad)

    def test_action_order_identity_and_full_content_preserved(self):
        actions=unit_actions(3);plan=p.plan_partitions(actions)
        variants=[actions[::-1],actions[:2],actions+[actions[0]]]
        for target,key,value in [('case','id','different'),('case','bytes',[0]),('expected','bytes',[18])]:
            changed=copy.deepcopy(actions);changed[0][target][key]=value;variants.append(changed)
        changed=copy.deepcopy(actions);changed[0]['normalized']=[0,0,0,0];variants.append(changed)
        for changed in variants:
            with self.assertRaises(ValueError):p.validate_partitions(changed,plan)
        # A role that does not render its expected bytes still seals those bytes.
        changed=copy.deepcopy(actions);changed[0]['expected']['bytes']=[18]
        self.assertEqual(p.candidate_program(actions),p.candidate_program(changed))
        self.assertNotEqual(p.action_digest(actions),p.action_digest(changed))
        with self.assertRaises(ValueError):p.validate_partitions(changed,plan)

    def test_lane_receipts_must_match_every_planned_batch_and_full_byte_totals(self):
        actions=unit_actions(33);plan=p.plan_partitions(actions);lanes=lanes_for(plan)
        p.finish_lanes(lanes,actions,plan);self.assertTrue(all(row['passed'] for row in lanes.values()))
        for key,value in [('source_bytes',1),('source_sha256','0'*64),('actions_sha256','0'*64),('compared_bytes',0),('bytes',0),('bytes',True),('passed',1)]:
            changed=lanes_for(plan);changed['javascript']['batches'][0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):p.finish_lanes(changed,actions,plan)
            self.assertTrue(all(row['passed'] is False for row in changed.values()))
        changed=lanes_for(plan);changed['cpu-1']['batches'].reverse()
        with self.assertRaises(ValueError):p.finish_lanes(changed,actions,plan)
        changed=lanes_for(plan);changed['cpu-2']['batches'].append(changed['cpu-2']['batches'][0])
        with self.assertRaises(ValueError):p.finish_lanes(changed,actions,plan)

    def test_complete_real_fixture_corpus_keeps_all_roles_bytes_and_control_observations(self):
        cases=p.fixtures();invalid=p.controls();rows=[]
        # Structural planning only: these synthetic protocol rows are not a
        # pixel oracle and never feed a differential acceptance run.
        for action in p.native_actions(cases):
            c=action['case'];channels=4 if action['role']=='normalized' else c['channels']
            rows.append(dict(p.meta(c,action['role']),bytes=[17]*(c['width']*c['height']*channels)))
        actions,_=p.candidate_actions(cases,invalid,rows);plan=p.plan_partitions(actions)
        self.assertEqual((len(cases),len(invalid),len(actions)),(169,155,1311))
        self.assertEqual(sum(len(a['expected'].get('bytes',[])) for a in actions),1024632)
        self.assertEqual(sum(b['count'] for b in plan),1311);self.assertEqual(sum(b['compared_bytes'] for b in plan),1024632)
        self.assertTrue(all(1<=b['count']<=32 and 0<b['source_bytes']<=196608 for b in plan))
        flattened=[a for b in plan for a in actions[b['start']:b['start']+b['count']]]
        self.assertEqual(flattened,actions);self.assertEqual(p.action_digest(flattened),p.action_digest(actions))
        lanes=lanes_for(plan);p.finish_lanes(lanes,actions,plan);self.assertTrue(all(row['passed'] for row in lanes.values()))


@unittest.skipUnless(os.name=='posix','owned process-group profile requires POSIX')
class TgaProcessGroupTests(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.work=Path(self.tmp.name);p.SEALED.clear()
    def tearDown(self):p.SEALED.clear();self.tmp.cleanup()

    def test_real_timeout_kills_grandchildren_preserves_partial_outputs_and_unrelated_child(self):
        started=self.work/'started';escaped=self.work/'escaped';unrelated_marker=self.work/'unrelated';output=self.work/'output'
        sleeper='import os,signal,time;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);Path('+repr(str(started))+').write_text(str(os.getpgrp()));time.sleep(1.2);Path('+repr(str(escaped))+').write_text("escaped")'
        worker='import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",'+repr(sleeper)+']);time.sleep(10)'
        launcher='import subprocess,sys,time;from pathlib import Path;Path(sys.argv[-1]).write_bytes(b"partial compiler output");subprocess.Popen([sys.executable,"-c",'+repr(worker)+']);print("launched",flush=True);print("diagnostic",file=sys.stderr,flush=True);time.sleep(10)'
        launcher_path=self.work/'launcher.py';launcher_path.write_text(launcher)
        other='import time;from pathlib import Path;time.sleep(1);Path('+repr(str(unrelated_marker))+').write_text("alive")'
        unrelated=subprocess.Popen([sys.executable,'-c',other],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            before=dict(os.environ);began=time.monotonic()
            with self.assertRaisesRegex(ValueError,'timed out'):p.record_run([sys.executable,launcher_path,'-o',output],self.work,'timeout-group',timeout=0.5)
            self.assertLess(time.monotonic()-began,2);self.assertEqual(dict(os.environ),before)
            self.assertTrue(started.is_file(),'negative test never reached the grandchild')
            row=json.loads((self.work/'timeout-group.command.json').read_text())
            self.assertTrue(row['timed_out']);self.assertTrue(row['process_group_owned']);self.assertTrue(row['leader_reaped'])
            self.assertEqual(int(started.read_text()),row['process_group_id']);self.assertNotEqual(row['process_group_id'],os.getpgrp())
            self.assertEqual(row['process_group_cleanup'],'SIGKILL');self.assertEqual(row['cleanup_timeout_seconds'],p.PROCESS_CLEANUP_SECONDS)
            self.assertEqual(row['exit_code'],-signal.SIGKILL);self.assertIn('launched',(self.work/'timeout-group.stdout').read_text())
            self.assertIn('diagnostic',(self.work/'timeout-group.stderr').read_text());self.assertEqual(row['artifacts'][str(output)],p.digest(output))
            time.sleep(1.1);self.assertFalse(escaped.exists(),'owned grandchild survived timeout')
            unrelated.wait(timeout=2);self.assertEqual(unrelated.returncode,0);self.assertTrue(unrelated_marker.exists(),'cleanup touched an unrelated process')
            p.verify_sealed()
        finally:
            if unrelated.poll() is None:unrelated.terminate();unrelated.wait(timeout=2)

    def test_real_success_and_nonzero_cleanup_stray_descendants_without_pipe_inheritance(self):
        for code in (0,7):
            with self.subTest(code=code):
                started=self.work/f'started-{code}';escaped=self.work/f'escaped-{code}'
                child='import os,time;from pathlib import Path;Path('+repr(str(started))+').write_text(str(os.getpgrp()));time.sleep(0.5);Path('+repr(str(escaped))+').write_text("escaped")'
                parent='import subprocess,sys,time;from pathlib import Path;subprocess.Popen([sys.executable,"-c",'+repr(child)+'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);started=Path('+repr(str(started))+')\nwhile not started.exists():time.sleep(0.01)\nprint("complete",flush=True)\nsys.exit('+str(code)+')'
                parent_path=self.work/f'parent-{code}.py';parent_path.write_text(parent)
                if code:
                    with self.assertRaisesRegex(ValueError,'exited 7'):p.record_run([sys.executable,parent_path],self.work,f'exit-{code}',timeout=2)
                else:self.assertEqual(p.record_run([sys.executable,parent_path],self.work,f'exit-{code}',timeout=2),'complete\n')
                row=json.loads((self.work/f'exit-{code}.command.json').read_text())
                self.assertEqual(row['exit_code'],code);self.assertTrue(row['leader_reaped']);self.assertEqual(row['process_group_cleanup'],'SIGKILL')
                self.assertEqual(int(started.read_text()),row['process_group_id'])
                time.sleep(0.7);self.assertFalse(escaped.exists(),'owned descendant survived ordinary completion');p.verify_sealed()

    def test_cleanup_drain_timeout_is_bounded_closes_pipes_and_reaps_only_owned_leader(self):
        process=MagicMock(pid=123456,returncode=None)
        process.communicate.side_effect=[subprocess.TimeoutExpired(['tool'],600,output=b'first',stderr=b'warning'),subprocess.TimeoutExpired(['tool'],5,output=b'complete partial',stderr=b'warning')]
        def reaped(*args,**kwargs):process.returncode=-signal.SIGKILL;return process.returncode
        process.wait.side_effect=reaped
        with patch.object(p.subprocess,'Popen',return_value=process) as launch,patch.object(p.os,'killpg') as kill,patch.object(p.time,'monotonic',side_effect=[10,10.2,15.1,15.2]):
            with self.assertRaises(subprocess.TimeoutExpired) as failure:p.run_process_group(['tool'],cwd=self.work,env={'ONLY':'child'},timeout=600)
        self.assertTrue(launch.call_args.kwargs['start_new_session']);self.assertEqual(launch.call_args.kwargs['env'],{'ONLY':'child'})
        kill.assert_called_once_with(process.pid,signal.SIGKILL)
        self.assertEqual(process.communicate.call_args_list[0].kwargs['timeout'],600)
        self.assertLessEqual(process.communicate.call_args_list[1].kwargs['timeout'],p.PROCESS_CLEANUP_SECONDS)
        self.assertEqual(process.wait.call_args.kwargs['timeout'],0)
        process.stdout.close.assert_called_once();process.stderr.close.assert_called_once()
        self.assertEqual(failure.exception.process_stdout,b'complete partial');self.assertTrue(failure.exception.process_group_receipt['leader_reaped'])
        self.assertIn('TimeoutExpired',failure.exception.process_group_receipt['cleanup_error'])

    def test_interruption_cleans_owned_group_and_keeps_durable_receipts(self):
        process=MagicMock(pid=123457,returncode=-signal.SIGKILL)
        process.communicate.side_effect=[KeyboardInterrupt(),('partial','diagnostic')]
        with patch.object(p.subprocess,'Popen',return_value=process),patch.object(p.os,'killpg') as kill:
            with self.assertRaises(KeyboardInterrupt):p.record_run(['tool'],self.work,'interrupt',timeout=600)
        kill.assert_called_once_with(process.pid,signal.SIGKILL)
        row=json.loads((self.work/'interrupt.command.json').read_text())
        self.assertEqual(row['communication_error'],'KeyboardInterrupt');self.assertTrue(row['leader_reaped'])
        self.assertEqual((self.work/'interrupt.stdout').read_text(),'partial');self.assertEqual((self.work/'interrupt.stderr').read_text(),'diagnostic');p.verify_sealed()


if __name__=='__main__':unittest.main()
