import copy
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pnm_format_probe as p


def tiny(channels=1,extended=False):
    prefix=p.header(channels=channels)
    return dict(id='tiny',width=1,height=1,channels=channels,maximum=255,header_bytes=len(prefix),raster_bytes=channels,bytes=[*prefix,*range(17,17+channels)],extended=extended)


def encoded(action,values):
    return '\n'.join(json.dumps(v) for v in [p.meta(action['case'],action['role']),*[values[i:i+256] for i in range(0,len(values),256)],'end'])+'\n'


def flags():return 'C_DEFINES = -DEXTERNAL_CONFIG_FLAGS -DPLATFORM_MEMORY -DSUPPORT_FILEFORMAT_PNM\n'


def cache():
    return '\n'.join(k+':STRING='+v for k,v in dict(PLATFORM='Memory',CMAKE_BUILD_TYPE='Release',CUSTOMIZE_BUILD='ON',SUPPORT_FILEFORMAT_PNM='ON',SUPPORT_MODULE_RAUDIO='OFF',BUILD_EXAMPLES='OFF',USE_EXTERNAL_GLFW='OFF').items())+'\n'


class PnmProtocolTests(unittest.TestCase):
    def setUp(self):self.case=tiny();self.action=dict(case=self.case,role='raw');self.row=p.meta(self.case,'raw')

    def text(self,row=None,parts=None):return '\n'.join(json.dumps(v) for v in [self.row if row is None else row,*([[17],'end'] if parts is None else parts)])+'\n'

    def test_complete_raw_gray_rgb_and_normalized(self):
        self.assertEqual(p.parse_rows(self.text(),[self.action]),[dict(self.row,bytes=[17])])
        c=tiny(3)
        for role,values,fmt in [('raw',[17,18,19],4),('normalized',[17,18,19,255],7),('alias-PGM',[17,18,19],4)]:
            a=dict(case=c,role=role);self.assertEqual(p.parse_rows(encoded(a,values),[a])[0]['format'],fmt)

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


class PnmSafetyAndSourceTests(unittest.TestCase):
    def test_all_legacy_inputs_preserved_and_matrix_discriminators(self):
        cases=p.fixtures();by_id={c['id']:c for c in cases};legacy=p.legacy_fixtures()[0]
        self.assertEqual(len(cases),96);self.assertEqual(len(by_id),len(cases));self.assertEqual(len(legacy),30)
        for c in legacy:self.assertEqual(by_id['legacy-'+c['id']]['bytes'],c['bytes'])
        for channels in (1,3):
            for maximum in (255,256):
                prefix=f'c{channels}-max{maximum}-'
                for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63)]:
                    c=by_id[prefix+name];self.assertEqual((c['width'],c['height']),(w,h))
                for separator in p.SPACE:self.assertEqual(by_id[prefix+f'separator-{separator}']['bytes'][by_id[prefix+f'separator-{separator}']['header_bytes']-1],separator)
            for name in ('first','second'):self.assertIn(f'c{channels}-wide-vary-{name}',by_id)
            for maximum in (1,15,100,257,1000,65535):self.assertIn(f'c{channels}-unscaled-{maximum}',by_id)
        self.assertEqual(by_id['grayscale-exact-ramp']['bytes'][by_id['grayscale-exact-ramp']['header_bytes']:],list(range(256)))
        p.validate_cases(cases)

    def test_native_case_safety_fails_closed(self):
        c=tiny()
        changes=[dict(width=0),dict(width=4097),dict(width=True),dict(height=1.0),dict(channels=3),dict(maximum=0),dict(header_bytes=0),dict(raster_bytes=0),dict(extended=1),dict(id='unsafe"id'),dict(bytes=c['bytes'][:-1]),dict(bytes=[*c['bytes'],256]),dict(bytes=[*c['bytes'],True]),dict(native=True)]
        for change in changes:
            with self.subTest(change=change),self.assertRaises(ValueError):p.validate_cases([dict(c,**change)])
        for cases in ([],[c,c],p.controls()[:1]):
            with self.assertRaises(ValueError):p.validate_cases(cases)
        with patch.object(p,'MAX_TOTAL_BYTES',1),self.assertRaises(ValueError):p.validate_cases([c])
        with self.assertRaises(ValueError):p.inspect_header(list(p.header(4096,4096)+b'\0'))
        for data in (b'P5 9999999999999999 1 255\n\0',b'P5 1 1 255x\0',b'P6 x 1 255\n\0',b'P7 1 1 255\n\0'):
            with self.assertRaises(ValueError):p.inspect_header(list(data))

    def test_controls_are_checked_only_and_precedence_is_explicit(self):
        controls=p.controls();by_id={c['id']:c for c in controls}
        self.assertEqual(len(controls),73);self.assertTrue(all(set(c)=={'id','bytes','error'} for c in controls))
        for c in p.legacy_fixtures()[1]:self.assertEqual(by_id['legacy-'+c['id']]['bytes'],c['bytes'])
        for name,error in [('bad-byte-before-bad-header',1),('bad-byte-before-bad-size',1),('bad-max-before-bad-size',0),('complete-header-missing-raster',3),('width-4294967295',0),('height-4097',2)]:self.assertEqual(by_id[name]['error'],error)
        with self.assertRaises(ValueError):p.reference_program(controls)

    def test_native_actual_raw_precedes_normalization_and_alias_reload(self):
        c=tiny(extended=True);program=p.reference_program([c])
        self.assertLess(program.index('"raw",image)'),program.index('ImageFormat(&image,7)'))
        self.assertLess(program.index('ImageFormat(&image,7)'),program.index('"normalized",image)'))
        for token in ('.ppm','.pgm','.PPM','.PGM'):self.assertIn('LoadImageFromMemory("'+token+'"',program)
        for text in ('if(!little_endian())','image.mipmaps!=1','image.format!=1','GetPixelDataSize(image.width,image.height,image.format)!=1','GetPixelDataSize(image.width,image.height,image.format)!=4'):self.assertIn(text,program)
        self.assertEqual(program.count('Image image=LoadImageFromMemory'),1);self.assertEqual(program.count('image=LoadImageFromMemory'),4)
        self.assertNotIn('LoadImageColors',program);self.assertNotIn('stbi_load',program)
        self.assertEqual([a['role'] for a in p.native_actions([c])],['raw','normalized','alias-pgm','alias-PPM','alias-PGM'])

    def test_native_config_requires_actual_single_enabled_definition(self):
        self.assertEqual(p.validate_native_config(cache(),flags())['SUPPORT_FILEFORMAT_PNM'],'ON')
        # Real CMake caches contain blank lines and // comments between entries.
        commented='// Generated cache\n\n'+'\n// option\n'.join(cache().splitlines())+'\n'
        self.assertEqual(p.validate_native_config(commented,flags())['PLATFORM'],'Memory')
        with self.assertRaises(ValueError):p.validate_native_config(cache()+'PLATFORM:STRING=Memory\n',flags())
        self.assertEqual(p.validate_native_config(cache(),flags().replace('-DSUPPORT_FILEFORMAT_PNM','-DSUPPORT_FILEFORMAT_PNM=1'))['PLATFORM'],'Memory')
        for broken in (flags().replace(' -DSUPPORT_FILEFORMAT_PNM',''),flags()+' -DSUPPORT_FILEFORMAT_PNM',flags()+' -USUPPORT_FILEFORMAT_PNM',flags()+' -U SUPPORT_FILEFORMAT_PNM',flags()+' -D SUPPORT_FILEFORMAT_PNM=0',flags().replace(' -DEXTERNAL_CONFIG_FLAGS',''),flags().replace(' -DPLATFORM_MEMORY',''),flags().replace('-DSUPPORT_FILEFORMAT_PNM','-DSUPPORT_FILEFORMAT_PNM=0')):
            with self.subTest(flags=broken),self.assertRaises(ValueError):p.validate_native_config(cache(),broken)
        for old,new in [('PNM:STRING=ON','PNM:STRING=OFF'),('CUSTOMIZE_BUILD:STRING=ON','CUSTOMIZE_BUILD:STRING=OFF'),('PLATFORM:STRING=Memory','PLATFORM:STRING=Desktop'),('CMAKE_BUILD_TYPE:STRING=Release','CMAKE_BUILD_TYPE:STRING=Debug')]:
            with self.assertRaises(ValueError):p.validate_native_config(cache().replace(old,new),flags())

    def test_native_endian_qualification_exact_and_typed(self):
        row=dict(little_endian=True,pnm_enabled=True,wide_second_byte=True,formats=[1,4]);self.assertEqual(p.qualification(json.dumps(row)),row)
        for key,value in [('little_endian',False),('pnm_enabled',False),('wide_second_byte',1),('formats',[True,4]),('formats',[1,7]),('extra',True)]:
            with self.subTest(key=key),self.assertRaises(ValueError):p.qualification(json.dumps(dict(row,**{key:value})))
        self.assertIn('uint16_t word=1',p.QUALIFY);self.assertIn('if(!little_endian())return 10',p.QUALIFY)
        self.assertIn('a.format!=1',p.QUALIFY);self.assertIn('b.format!=4',p.QUALIFY)

    def test_candidate_ownership_high_bits_factory_and_error_routes(self):
        c=tiny(extended=True);rows=[]
        for a in p.native_actions([c]):rows.append(dict(p.meta(c,a['role']),bytes=[17]*3+[255] if a['role']=='normalized' else [17]))
        actions,_=p.candidate_actions([c],p.controls()[:1],rows);program=p.candidate_program(actions)
        for text in ('word <= 255','word <= 16777215','+format: U32','(pixels, +word)','J.Image.Formatted.decode_pnm','J.Image.Formatted.to_surface','J.Surface.to_formatted','J.Image.Formatted.from_bytes','J.Image.Formatted.get','J.Surface.decode_pnm','J.Surface.decode_image(','J.UncontractedDecode{}','J.FusedDecode{}','J.Image.Formatted.export(image)','owner.read(result, 0, 0, Some{first})','(width - 1 : U32)','4294967295, 0, None{}','0, 4294967295, None{}','formatted.error(J.Image.Formatted.decode_pnm','surface.error(J.Surface.decode_pnm'):
            self.assertIn(text,program)
        self.assertNotIn('Image.Formatted.convert',program)
        rows[-1]['bytes']=[18]
        with self.assertRaises(ValueError):p.candidate_actions([c],[],rows)


class PnmRunnerTests(unittest.TestCase):
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
        with patch.object(p.subprocess,'run',return_value=fake) as run:
            self.assertEqual(p.record_run(['tool'],self.work,'success',environment=env,receipt=receipt,require_output=True),'ok\n')
        self.assertEqual(run.call_args.kwargs['env'],env)
        row=json.loads((self.work/'success.command.json').read_text());self.assertEqual(row['reference_environment'],receipt);self.assertEqual(row['exit_code'],0)
        self.assertEqual((self.work/'success.stderr').read_text(),'warning\n');p.verify_sealed()

    def test_failed_native_exit_empty_output_and_missing_compiler_output(self):
        for name,result,command,require in [('failed',subprocess.CompletedProcess([],9,'partial','bad'),['tool'],False),('empty',subprocess.CompletedProcess([],0,'',''),['tool'],True),('compiler',subprocess.CompletedProcess([],0,'ok',''),['tool','-o',str(self.work/'out')],False)]:
            with self.subTest(name=name),patch.object(p.subprocess,'run',return_value=result),self.assertRaises(ValueError):p.record_run(command,self.work,name,require_output=require)
            self.assertTrue((self.work/(name+'.command.json')).is_file())

    def test_stale_compiler_output_cannot_be_reused(self):
        path=self.work/'out';path.write_text('stale')
        with patch.object(p.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'','')),self.assertRaises(ValueError):p.record_run(['compiler','-o',path],self.work,'stale')
        self.assertFalse(path.exists())

    def test_timeout_retains_failed_receipt_and_partial_streams(self):
        error=subprocess.TimeoutExpired(['tool'],1,output=b'partial',stderr=b'waiting')
        with patch.object(p.subprocess,'run',side_effect=error),self.assertRaises(ValueError):p.record_run(['tool'],self.work,'timeout',timeout=1)
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
        self.assertEqual(p.report_directories(['--build-di',str(a)]),[p.BUILD/'pnm-format-probe'])
        self.assertEqual(p.report_directories(['--','--build-dir',str(a)]),[p.BUILD/'pnm-format-probe'])

    def test_mandatory_lanes_complete_contiguous_typed_and_nonempty(self):
        lanes={lane:dict(batches=[dict(start=0,count=1,passed=True)],differences=[]) for lane in p.LANES}
        good=copy.deepcopy(lanes);p.finish_lanes(good,[{}]);self.assertTrue(all(v['passed'] for v in good.values()))
        variants=[]
        for key,value in [('start',False),('start',1),('count',True),('count',0),('count',33),('passed',False)]:
            bad=copy.deepcopy(lanes);bad['cpu-1']['batches'][0][key]=value;variants.append(bad)
        bad=copy.deepcopy(lanes);del bad['javascript'];variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-2']['differences']=[{}];variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-2']['batches']=[];variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):p.finish_lanes(bad,[{}])
        with self.assertRaises(ValueError):p.finish_lanes(lanes,[])

    def test_native_build_explicit_pnm_and_configuration_checked_before_execution(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))();commands=[]
        def record(command,work,label,**kwargs):
            commands.append(list(map(str,command)))
            if label=='configure':
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(cache());(directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(flags().replace(' -DSUPPORT_FILEFORMAT_PNM',''))
        with self.assertRaises(ValueError):p.native_archive(args,self.work,record)
        self.assertEqual(len(commands),1);self.assertIn('-DSUPPORT_FILEFORMAT_PNM=ON',commands[0]);self.assertIn('-DCUSTOMIZE_BUILD=ON',commands[0])


if __name__=='__main__':unittest.main()
