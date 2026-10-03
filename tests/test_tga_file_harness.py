"""Adversarial checks for the native TGA file gate, without native input UB."""
import copy
import io
import json
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import tga_file_probe as p


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


def unit_actions(count=1):
    # Synthetic protocol data only, never a replacement for native file bytes.
    return [dict(case=dict(id=f'unit-{i}',width=1,height=1,channels=1,
                          bytes=p.memory.targa(1,1,1,[17]),extended=False,
                          filename=f'unit-{i}.tga',path=f'unit-{i}.tga',
                          route='LoadImage',regress=False),
                 role='raw',expected=dict(id=f'unit-{i}',role='raw',width=1,
                                         height=1,mipmaps=1,format=1,bytes=[17]),
                 normalized=[17,17,17,255]) for i in range(count)]


def lanes_for(partitions):
    def receipt(ceiling):
        return dict(passed=True,descriptor_limit=64,maximum_rss_bytes=1,
                    maximum_rss_acceptance_bytes=ceiling)
    return {lane:dict(passed=False,
                      batches=[dict(entry,bytes=entry['compared_bytes'],passed=True)
                               for entry in partitions],differences=[],
                      boundary=receipt(p.MAX_SPARSE_RSS),
                      sparse=receipt(p.MAX_SPARSE_RSS),
                      exact_cap=receipt(p.MAX_STRESS_RSS)) for lane in p.LANES}


def native_cache():
    fields=dict(PLATFORM='Memory',CMAKE_BUILD_TYPE='Release',CUSTOMIZE_BUILD='ON',
                SUPPORT_MODULE_RAUDIO='OFF',BUILD_EXAMPLES='OFF',USE_EXTERNAL_GLFW='OFF')
    fields.update({'SUPPORT_FILEFORMAT_'+name:'ON' for name in p.ALIAS_MACROS})
    return '\n'.join(k+':STRING='+v for k,v in fields.items())+'\n'


def native_flags():
    return 'C_DEFINES = -DEXTERNAL_CONFIG_FLAGS -DPLATFORM_MEMORY '+\
           ' '.join('-DSUPPORT_FILEFORMAT_'+name for name in p.ALIAS_MACROS)+'\n'


class TgaFileFixtureTests(unittest.TestCase):
    def setUp(self):
        self.cases=p.fixtures();self.invalid=p.controls();self.case=next(c for c in self.cases if c['id']=='c1-single')

    def test_exact_primary_matrix_and_all_memory_inputs_retained(self):
        self.assertEqual(len(self.cases),225);self.assertEqual(sum(c['width']*c['height'] for c in self.cases),61913)
        self.assertEqual(sum(c['route']=='LoadImage' for c in self.cases),197);self.assertEqual(sum(c['route']=='explicit-tga' for c in self.cases),28)
        by_id={c['id']:c for c in self.cases}
        for c in p.memory.fixtures():self.assertEqual({k:by_id[c['id']][k] for k in p.BASE_KEYS},c)
        p.validate_cases(self.cases)

    def test_suffix_matrix_covers_all_four_native_layouts(self):
        for channel in (1,2,3,4):
            rows=[c for c in self.cases if c['id'].startswith(f'path-c{channel}-')]
            self.assertEqual(len(rows),14);self.assertTrue(all(c['regress'] for c in rows))
            self.assertEqual(sum(c['route']=='explicit-tga' for c in rows),7)
            original=next(c for c in self.cases if c['id']==f'c{channel}-single')
            for c in rows:
                self.assertEqual(c['bytes'],original['bytes'])
                self.assertEqual(c['channels'],channel)
                self.assertEqual(c['route']=='LoadImage',p.extension('fixtures/'+c['filename']) in p.RECOGNIZED)
            text=' '.join(c['filename'] for c in rows)
            for suffix in ('.TGA','.png','.BMP','.gif','.TgA','.qoi','.QOI','.dat',
                           ' with spaces','.a.b.', '/.tga','.tga/leaf'):
                self.assertIn(suffix,text)
            self.assertTrue(any(c['filename'].endswith('suffixless') for c in rows))
            self.assertTrue(any(c['filename'].endswith('.') for c in rows))

    def test_native_schema_and_safety_mutations_fail_closed(self):
        changes=[dict(width=0),dict(width=4097),dict(width=True),dict(height=1.0),dict(channels=3),dict(extended=1),dict(regress=1),dict(id='unsafe"id'),dict(bytes=self.case['bytes'][:-1]),dict(bytes=[*self.case['bytes'],256]),dict(bytes=[*self.case['bytes'],True]),dict(bytes=[*self.case['bytes'],17.0]),dict(bytes=bytes(self.case['bytes'])),dict(special='sparse'),dict(native=True),dict(route='explicit-qoi'),dict(route='explicit-tga'),dict(route=True),dict(filename='image.QoI'),dict(filename='../image.tga'),dict(filename='/image.tga'),dict(filename='image\0.tga'),dict(filename=''),dict(filename=True),dict(path='\0'),dict(path=''),dict(path=True),dict(bytes=[0])]
        for change in changes:
            with self.subTest(change=change),self.assertRaises(ValueError):p.validate_cases([dict(self.case,**change)])
        for cases in ([],(),[self.case,self.case],self.invalid[:1],[dict(self.case,id='different'),self.case]):
            with self.assertRaises(ValueError):p.validate_cases(cases)
        with patch.object(p,'TGA_CAP',1),self.assertRaises(ValueError):p.validate_cases([self.case])
        with patch.object(p.memory,'MAX_TOTAL_BYTES',1),self.assertRaises(ValueError):p.validate_cases([self.case])
        for key in p.BASE_KEYS|{'route','regress','filename'}:
            bad=self.case.copy();del bad[key]
            with self.subTest(missing=key),self.assertRaises(ValueError):p.validate_cases([bad])

    def test_typed_controls_are_file_byte_safe_and_never_native(self):
        self.assertEqual(len(self.invalid),154);by_id={c['id']:c for c in self.invalid}
        for c in self.invalid:
            self.assertTrue(all(type(b) is int and 0<=b<=255 for b in c.get('bytes',[])))
            self.assertNotIn('native',c)
            with self.assertRaises(ValueError):p.reference_program([dict(c,path=c['filename'])])
        for ident,error in [('not-tga-png',0),('not-tga-qoi',0),('not-tga-pnm',0),('missing',5),('directory',5),('cap-plus-one',2),('cap-misleading',2),('larger-file',2),('host-size-overflow',5),('palette-skip-truncated',3),('bad-header-before-bad-size',0),('bad-size-before-truncated',2),('overrun-before-truncated',4),('height-4097',2)]:self.assertEqual(by_id[ident]['error'],error)
        safe=[c for c in p.memory.controls() if all(type(b) is int and 0<=b<=255 for b in c['bytes'])]
        self.assertEqual(len(safe),144)
        for c in safe:
            self.assertEqual(by_id[c['id']]['bytes'],c['bytes']);self.assertEqual(by_id[c['id']]['error'],c['error'])
        self.assertTrue(all(type(c['error']) is int and 0<=c['error']<=5 for c in self.invalid))

    def test_native_file_route_and_raw_observation_order(self):
        for channels in (1,2,3,4):
            original=next(c for c in self.cases if c['id']==f'c{channels}-single')
            cases=[dict(original,path='native.tga'),dict(original,id='explicit',filename='explicit.dat',path='explicit.dat',route='explicit-tga')]
            text=p.reference_program(cases)
            for token in ('if(!little_endian())','Image image=LoadImage("native.tga")','LoadFileData("explicit.dat",&size)',f'size!={len(original["bytes"])}','LoadImageFromMemory(".tga",data,size);UnloadFileData(data)','image.mipmaps!=1',f'image.format!={p.memory.FORMATS[channels]}',f'GetPixelDataSize(image.width,image.height,image.format)!={channels}','GetPixelDataSize(image.width,image.height,image.format)!=4'):
                self.assertIn(token,text)
            for block in text.split('Image image=')[1:]:
                self.assertLess(block.index('"raw",image)'),block.index('ImageFormat(&image,7)'))
                self.assertLess(block.index('ImageFormat(&image,7)'),block.index('"normalized",image)'))
            self.assertNotIn('LoadImageColors',text);self.assertNotIn('stbi_load',text)
            self.assertNotIn('decode_tga',text)
        with self.assertRaises(ValueError):p.reference_program([self.case])

    def test_whole_path_last_dot_rule_distinguishes_literal_and_qualified_dotfile(self):
        for path,want in [('.tga',''),('fixtures/.tga','.tga'),('/.tga','.tga'),
                          ('image.TGA','.TGA'),('image.TgA','.TgA'),
                          ('parent.tga/leaf','.tga/leaf'),('parent.png/leaf','.png/leaf'),
                          ('parent.dot/leaf.tga','.tga'),('file.','.'),('plain','')]:
            with self.subTest(path=path):self.assertEqual(p.extension(path),want)
        for path in (None,True,17,'bad\0.tga'):
            with self.assertRaises(ValueError):p.extension(path)
        p.validate_cases([dict(self.case,filename='.tga',path='fixtures/.tga')])
        p.validate_cases([dict(self.case,filename='.tga',path='.tga',route='explicit-tga')])
        for case in (dict(self.case,path='.tga'),
                     dict(self.case,path='parent.tga/leaf'),
                     dict(self.case,path='parent.tga/leaf.png',route='explicit-tga')):
            with self.assertRaises(ValueError):p.validate_cases([case])

    def test_only_explicitly_enabled_alias_tokens_are_native(self):
        self.assertEqual(p.ALIAS_MACROS,('TGA','PNG','BMP','GIF'))
        self.assertEqual(p.RECOGNIZED,{'.tga','.TGA','.png','.PNG','.bmp','.BMP','.gif','.GIF'})
        for token in sorted(p.RECOGNIZED):
            p.validate_cases([dict(self.case,filename='safe'+token,path='safe'+token)])
        for token in ('.TgA','.qoi','.QOI','.jpg','.JPG','.jpeg','.pgm','.ppm','.psd','.pic','.dat',''):
            case=dict(self.case,filename='safe'+token,path='safe'+token)
            with self.assertRaises(ValueError):p.validate_cases([case])
            p.validate_cases([dict(case,route='explicit-tga')])

    def test_independent_safety_parser_runs_before_native_source_emission(self):
        with patch.object(p.memory,'inspect_header',wraps=p.memory.inspect_header) as inspect:
            p.reference_program([dict(self.case,path='safe.tga')])
        self.assertEqual(inspect.call_args.args[0],self.case['bytes'])
        for data in (p.memory.targa(4096,4096,1,[17]),
                     p.memory.targa(1,1,1,[129,17],rle=True),
                     p.memory.indexed_targa(1,1,[b'\x01\x02\x03'],8,24,[])):
            with self.assertRaises(ValueError):p.reference_program([dict(self.case,path='unsafe.tga',bytes=data)])
        with patch.object(p.memory,'inspect_header',side_effect=ValueError('incomplete stream')):
            with self.assertRaisesRegex(ValueError,'incomplete stream'):
                p.reference_program([dict(self.case,path='safe.tga')])

    def test_alias_native_cache_and_actual_compiled_macros_fail_closed(self):
        receipt=p.validate_alias_config(native_cache(),native_flags())
        self.assertEqual(receipt['enabled_macros'],['SUPPORT_FILEFORMAT_'+n for n in p.ALIAS_MACROS])
        self.assertEqual(receipt['recognized_tokens'],sorted(p.RECOGNIZED))
        for name in p.ALIAS_MACROS:
            macro='SUPPORT_FILEFORMAT_'+name
            for value in ('OFF','TRUE','1',''):
                with self.subTest(macro=macro,cache=value),self.assertRaises(ValueError):
                    p.validate_alias_config(native_cache().replace(macro+':STRING=ON',macro+':STRING='+value),native_flags())
            for token in ('','-D'+macro+'=0','-U'+macro,'-D'+macro+' -U'+macro,
                          '-D'+macro+' -D'+macro+'=1','-D '+macro+'=0','-U '+macro):
                with self.subTest(macro=macro,flags=token),self.assertRaises(ValueError):
                    p.validate_alias_config(native_cache(),native_flags().replace('-D'+macro,token))
            for token in ('-D'+macro+'=1','-D '+macro,'-D '+macro+'=1'):
                p.validate_alias_config(native_cache(),native_flags().replace('-D'+macro,token))
        for flags in (native_flags()+' -D',native_flags()+' -U',native_flags()+' -DPLATFORM_DESKTOP'):
            with self.assertRaises(ValueError):p.validate_alias_config(native_cache(),flags)
        with self.assertRaises(ValueError):p.validate_alias_config(native_cache()+'SUPPORT_FILEFORMAT_PNG:BOOL=ON\n',native_flags())

    def test_controls_reject_wrong_types_bytes_schemas_and_native_inputs(self):
        ordinary=next(c for c in self.invalid if 'bytes' in c)
        for change in (dict(error=True),dict(error=3.0),dict(error=6),dict(error=-1),
                       dict(bytes=[256]),dict(bytes=[-1]),dict(bytes=[True]),dict(bytes=[1.0]),
                       dict(bytes=b'\0'),dict(bytes=self.case['bytes']),dict(native=False),
                       dict(filename='../bad.tga'),dict(filename='/bad.tga'),
                       dict(filename='bad\0.tga'),dict(filename=''),dict(path=True)):
            with self.subTest(change=change),self.assertRaises(ValueError):
                p.validate_controls([dict(ordinary,**change)])
        for missing in ('id','filename','error','bytes'):
            bad=ordinary.copy();del bad[missing]
            with self.assertRaises(ValueError):p.validate_controls([bad])
        for cases in (None,(),[None],[ordinary,ordinary]):
            with self.assertRaises(ValueError):p.validate_controls(cases)
        for special,error in [('missing',5),('directory',5),('sparse',2),('large',2),('overflow',5)]:
            case=dict(id='special',filename='special.tga',special=special,error=error)
            p.validate_controls([case])
            for change in (dict(error=0),dict(error=True),dict(special='unknown'),dict(special=True),dict(bytes=[])):
                with self.assertRaises(ValueError):p.validate_controls([dict(case,**change)])


class TgaFileOwnershipAndBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.cases=[dict(c,path=c['filename']) for c in p.fixtures()];self.invalid=[dict(c,path=c['filename']) for c in p.controls()];self.ref=reference(self.cases)

    def test_wrapper_reuses_closed_bounded_shared_boundary(self):
        source=(p.ROOT/'jonlib.bend').read_text()
        wrapper=source.split('def Image.Formatted.load_tga(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Image.file.bytes(path, Image.file.limit(RasterFile{}))',wrapper)
        self.assertIn('Image.Formatted.tga.file.loaded',wrapper)
        for bad in ('Surface','Image.file.kind','QoiFile','decode_image'):self.assertNotIn(bad,wrapper)
        continuation=source.split('def Image.Formatted.tga.file.loaded(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Fail{error}',continuation);self.assertIn('Image.file.decoded(Image.Formatted, Image.Formatted.decode_tga(bytes))',continuation)
        bounded=source.split('def Image.file.bounded(',1)[1].split('\ndef ',1)[0]
        self.assertLess(bounded.index('case False{}:'),bounded.index('File.read_bytes'));self.assertIn('File.close(file)',bounded)
        rejected=bounded.split('case False{}:',1)[1].split('case True{}:',1)[0]
        self.assertIn('File.close(file)',rejected);self.assertNotIn('File.read_bytes',rejected)
        self.assertIn('UnsupportedImageSize{}',rejected)
        sized=source.split('def Image.file.sized(',1)[1].split('\ndef ',1)[0];self.assertIn('(size <= limit : U32)',sized)
        self.assertIn('case Tuple{file, Fail{error}}: Image.file.read(0, (file, Fail{error}))',sized)
        read=source.split('def Image.file.read(',1)[1].split('\ndef ',1)[0]
        self.assertLess(read.index('File.close(file)'),read.index('Image.file.payload'))
        self.assertNotIn('decode',read)
        token=source.split('def Image.file.token(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Image.file.last_dot(path, 0n, 0n)',token)
        self.assertIn('Nat.is_lt(0n, position)',token)
        self.assertIn('law raster_file_limit:',(p.ROOT/'LAWS.bend').read_text())

    def test_primary_and_owner_calls_reopen_real_public_files(self):
        actions=p.candidate_actions(self.cases,self.invalid,self.ref);text=p.candidate_program(actions);main=text.split('def main()',1)[1]
        for call in ('J.Image.Formatted.load_tga(','J.Surface.load_image(','J.UncontractedDecode{}','J.FusedDecode{}','owner.emitted(','bridge.emitted(','file.failed('):self.assertIn(call,main)
        self.assertNotIn('decode_tga',main);self.assertNotIn('from_bytes',main)
        for term in ('word <= 255','word <= 65535','word <= 16777215','J.Image.Formatted.get','4294967295','J.Image.Formatted.export','surface.tga.loaded'):self.assertIn(term,text)
        for case in self.cases:
            path=json.dumps(case['path']);self.assertEqual(main.count('J.Image.Formatted.load_tga('+path+')'),3)
            self.assertEqual(main.count('surface.tga('+path+')'),1)
        with self.assertRaises(ValueError):p.candidate_program([])
        with self.assertRaises(ValueError):p.candidate_program([dict(actions[0],role='bogus')])

    def test_action_expectations_are_native_and_modes_stay_distinct(self):
        actions=p.candidate_actions(self.cases,self.invalid,self.ref)
        self.assertEqual(len(actions),1283)
        for a in actions:
            c=a['case'];role=a['role']
            if role.endswith('error'):continue
            expected=self.ref[c['id']][0 if role in ('raw','owner') else 1]
            self.assertEqual(a['expected'],dict(expected,role=role))
            if role in ('dispatch-tga','uncontracted','fused'):self.assertEqual(c['route'],'LoadImage')
        for case in self.cases:
            roles=[a['role'] for a in actions if a['case']['id']==case['id']]
            self.assertEqual(roles[:4],['raw','owner','bridge','surface'])
            self.assertEqual(set(roles[4:]),{'dispatch-tga','uncontracted','fused'} if case['regress'] and case['route']=='LoadImage' else set())
        self.assertEqual(sum(a['role']=='surface-error' for a in actions),28)
        text=p.candidate_program([next(a for a in actions if a['role']=='surface-error')])
        body=text.split('def surface.failed(',1)[1].split('def require(',1)[0]
        self.assertIn('"surface-error"',body);self.assertNotIn('"formatted-error"',body)

    def test_closure_uses_twelve_acquired_handle_paths_and_exact_messages(self):
        text=p.boundary_program(self.cases,self.invalid)
        for token in ('closure_loop(100n)','File.open(','J.Image.file.read(2, (file, Done{[1]}))','J.Image.file.read(1, (file, Done{[1, 2]}))','stage-read-failure','stage-size-failure','J.Image.file.sized(1048576','continuation-failure','payload-failure','Done{[256]}','1048576 <=','1048577 <=','String.eq(message, text)','def stage.emitted(id: String, +expected: U32,','load.emitted("closure-final", "raw")'):self.assertIn(token,text)
        loop=text.split('def closure_loop(',1)[1].split('def main()',1)[0]
        self.assertEqual(loop.count('J.Image.Formatted.load_tga('),8);self.assertEqual(loop.count('File.open('),4)
        self.assertNotIn('LoadImage(',text)
        actions=p.boundary_actions(self.cases,self.invalid,self.ref)
        self.assertEqual(len(actions),1209);self.assertEqual(p.TERMINAL['paths_per_iteration'],12)
        self.assertEqual([(a['case']['id'],a['expected']['error']) for a in actions[:8]],list(p.SYNTHETIC))
        cycle=actions[8:20]
        self.assertEqual([a['case']['id'] for a in cycle],list(p.BOUNDARY_LOADS)+[s[0] for s in p.STAGES])
        self.assertEqual([a['case']['channels'] for a in cycle[:4]],[1,2,3,4])
        self.assertEqual(actions[8:-1],cycle*100)

    def test_complete_boundary_records_and_terminal_are_required(self):
        actions=p.boundary_actions(self.cases,self.invalid,self.ref);text=encode(actions)+json.dumps(p.TERMINAL)+'\n'
        self.assertEqual(p.parse_boundary(text,actions),p.TERMINAL)
        for wrong in ('',encode(actions),text+json.dumps(p.TERMINAL),text.replace('"iterations": 100','"iterations": 99'),text.replace('"records": 1209','"records": true'),text.replace('"synthetic_checks": 8','"synthetic_checks": 8.0'),encode(actions[1:])+json.dumps(p.TERMINAL),encode(actions+[actions[-1]])+json.dumps(p.TERMINAL)):
            with self.subTest(prefix=wrong[:50]),self.assertRaises(ValueError):p.parse_boundary(wrong,actions)
        changed=copy.deepcopy(actions);changed[500]['expected']['error']=99
        with self.assertRaises(ValueError):p.parse_boundary(encode(changed)+json.dumps(p.TERMINAL),actions)
        with self.assertRaises(ValueError):p.parse_boundary(text,actions[:-1])

    def test_format_framing_and_byte_types_cannot_normalize_away_mismatch(self):
        c=next(c for c in self.cases if c['id']=='c1-single');a=dict(case=c,role='raw',expected=self.ref[c['id']][0]);text=encode([a])
        self.assertEqual(p.memory.parse_rows(text,[a]),[a['expected']])
        for key,value in [('width',True),('height',1.0),('format',7),('mipmaps',2),('id','wrong'),('role','normalized'),('extra',1)]:
            bad=copy.deepcopy(a);bad['expected'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):p.memory.parse_rows(encode([bad]),[a])
        for bad in ('',text+'"end"\n',text+text,text.replace('"end"','[]'),text.replace('[17]','[true]'),text.replace('[17]','[256]'),text.replace('[17]','[-1]'),text.replace('[17]','[17.0]'),text.replace('"width": 1','"width": 1, "width": 1')):
            with self.assertRaises(ValueError):p.memory.parse_rows(bad,[a])

    def test_native_reference_coverage_metadata_and_bytes_are_required(self):
        cases=[next(c for c in self.cases if c['id']==f'c{n}-single') for n in (1,2,3,4)]
        native=reference(cases);p.candidate_actions(cases,[],native)
        variants=[{},dict(native,extra=native[cases[0]['id']]),dict(native)]
        del variants[-1][cases[-1]['id']]
        for values in variants:
            with self.assertRaises(ValueError):p.candidate_actions(cases,[],values)
        for role in (0,1):
            for key,value in [('width',True),('height',1.0),('mipmaps',2),('format',True),
                              ('role','owner'),('id','other'),('extra',0),('bytes',[]),
                              ('bytes',[17.0]),('bytes',[True]),('bytes',[256]),('bytes',b'\x11')]:
                changed=copy.deepcopy(native);changed[cases[0]['id']][role][key]=value
                with self.subTest(role=role,key=key,value=value),self.assertRaises(ValueError):
                    p.candidate_actions(cases,[],changed)
        for pair in ((),(native[cases[0]['id']][0],),dict(native[cases[0]['id']][0]),[None,None]):
            changed=dict(native);changed[cases[0]['id']]=pair
            with self.assertRaises(ValueError):p.candidate_actions(cases,[],changed)

    def test_byte_differences_survive_equal_rgba_normalization(self):
        cases=[next(c for c in self.cases if c['id']=='c2-single')]
        native=reference(cases);native[cases[0]['id']][0]['bytes']=[23,71]
        native[cases[0]['id']][1]['bytes']=[91,37,11,5]
        actions=p.candidate_actions(cases,[],native)
        self.assertEqual(actions[0]['expected']['bytes'],[23,71])
        self.assertEqual(actions[1]['expected']['bytes'],[23,71])
        self.assertEqual(actions[2]['expected']['bytes'],[91,37,11,5])
        # Unit rows intentionally need not be related by a Python pixel decoder.
        actual=p.memory.parse_rows(encode(actions),actions)
        actual[0]['bytes']=[0,71]
        delta=p.memory.differences([a['expected'] for a in actions],actual)
        self.assertEqual(len(delta),1);self.assertEqual(delta[0]['byte_differences'][0]['index'],0)

    def test_native_and_bend_qualify_dotfile_and_parent_directory_tokens(self):
        native=p.qualification_program();bend=p.boundary_program(self.cases,self.invalid)
        for token in ('GetFileExtension(".tga")!=NULL',
                      'strcmp(GetFileExtension("dir/.tga"),".tga")',
                      'strcmp(GetFileExtension("dir.tga/leaf"),".tga/leaf")'):
            self.assertIn(token,native)
        for token in ('J.Image.file.token(".tga"), ""',
                      'J.Image.file.token("dir/.tga"), ".tga"',
                      'J.Image.file.token("dir.tga/leaf"), ".tga/leaf"'):
            self.assertIn(token,bend)
        self.assertIn('LoadImageFromMemory(',native)
        for format in (1,2,4,7):self.assertIn(f'image.format!={format}',native)

    def test_source_contract_preserves_function_text_and_hashes(self):
        source=(p.ROOT/'jonlib.bend').read_text();contract=p.boundary_source_contract()
        self.assertEqual(contract['source_sha256'],p.memory.digest(p.ROOT/'jonlib.bend'))
        self.assertIn('not an IO proof',contract['kind'])
        self.assertIn('cannot report OS close failure',contract['close_guarantee'])
        self.assertEqual(len(contract['definitions']),11)
        for name,definition in contract['definitions'].items():
            self.assertTrue(definition['source'].startswith('def '+name+'('))
            self.assertIn(definition['source'],source)
            self.assertEqual(definition['sha256'],hashlib.sha256(definition['source'].encode()).hexdigest())

    def test_source_contract_rejects_pre_read_and_close_order_drift(self):
        source=(p.ROOT/'jonlib.bend').read_text()
        read='    Unit <- File.close(file)\n    IO.pure(Result<&1, &1, Image.LoadError, +List<U32>>, Image.file.payload(size, status))'
        variants=[source.replace('Image.file.bounded((size <= limit : U32), file, size)',
                                 'Image.file.bounded((size < limit : U32), file, size)'),
                  source.replace('File.read_bytes(file, size), Image.file.read(size)',
                                 'File.read_bytes(file, size), File.read_bytes(file, size), Image.file.read(size)'),
                  source.replace(read,read.split('\n')[1]+'\n'+read.split('\n')[0]),
                  source.replace('Image.file.decoded(Image.Formatted, Image.Formatted.decode_tga(bytes))',
                                 'Image.file.decoded(Image.Formatted, Image.Formatted.decode_bmp(bytes))')]
        for changed in variants:
            self.assertNotEqual(changed,source)
            with patch.object(Path,'read_text',return_value=changed),self.assertRaises(ValueError):p.boundary_source_contract()


class TgaFilePartitionTests(unittest.TestCase):
    def test_fixed32_order_source_bytes_actions_and_coverage_are_sealed(self):
        actions=unit_actions(65);plan=p.plan_partitions(actions)
        self.assertEqual(plan,p.plan_partitions(copy.deepcopy(actions)))
        self.assertEqual([(b['start'],b['count']) for b in plan],[(0,32),(32,32),(64,1)])
        for entry in plan:
            selected=actions[entry['start']:entry['start']+entry['count']]
            source=p.candidate_program(selected).encode()
            self.assertEqual(entry['source_bytes'],len(source))
            self.assertEqual(entry['source_sha256'],hashlib.sha256(source).hexdigest())
            self.assertEqual(entry['actions_sha256'],p.memory.action_digest(selected))
            self.assertEqual(entry['compared_bytes'],len(selected))
        lanes=lanes_for(plan);p.finish_lanes(lanes,actions,plan)
        self.assertTrue(all(row['passed'] for row in lanes.values()))

    def test_empty_actions_duplicates_malformed_and_byte_types_reject(self):
        for actions in ([],(),[None],unit_actions()*2):
            with self.assertRaises(ValueError):p.plan_partitions(actions)
        for key,value in [('bytes',[True]),('bytes',[17.0]),('bytes',[256]),('role','owner'),('id','wrong')]:
            actions=unit_actions();actions[0]['expected'][key]=value
            with self.assertRaises(ValueError):p.plan_partitions(actions)
        for source in ('','x'*(p.SOURCE_BYTE_LIMIT+1)):
            with patch.object(p,'candidate_program',return_value=source),self.assertRaises(ValueError):p.plan_partitions(unit_actions())
        with patch.object(p,'candidate_program',return_value='é'*(p.SOURCE_BYTE_LIMIT//2)):
            self.assertEqual(p.plan_partitions(unit_actions())[0]['source_bytes'],p.SOURCE_BYTE_LIMIT)

    def test_plan_missing_extra_reordered_gap_overlap_schema_and_types_reject(self):
        actions=unit_actions(33);plan=p.plan_partitions(actions)
        variants=[None,(),[],plan[:-1],plan+plan,plan[::-1]]
        for key,value in [('start',True),('start',1),('count',True),('count',0),('count',33),
                          ('source_bytes',True),('source_bytes',0),('source_bytes',p.SOURCE_BYTE_LIMIT+1),
                          ('source_sha256','0'*64),('actions_sha256','0'*64),
                          ('compared_bytes',True),('compared_bytes',0),('extra',1)]:
            bad=copy.deepcopy(plan);bad[0][key]=value;variants.append(bad)
        for start in (31,33):
            bad=copy.deepcopy(plan);bad[1]['start']=start;variants.append(bad)
        for key in plan[0]:
            bad=copy.deepcopy(plan);del bad[0][key];variants.append(bad)
        for bad in variants:
            with self.subTest(plan=bad),self.assertRaises(ValueError):p.finish_lanes(lanes_for(plan),actions,bad)

    def test_same_program_cannot_hide_changed_native_bytes_or_input_identity(self):
        actions=unit_actions(3);plan=p.plan_partitions(actions)
        variants=[actions[::-1],actions[:2]]
        for target,key,value in [('case','bytes',[0]),('case','path','different.tga'),
                                 ('case','id','different'),('expected','bytes',[18])]:
            changed=copy.deepcopy(actions);changed[0][target][key]=value;variants.append(changed)
        changed=copy.deepcopy(actions);changed[0]['normalized']=[0,0,0,0];variants.append(changed)
        for changed in variants:
            with self.assertRaises(ValueError):p.finish_lanes(lanes_for(plan),changed,plan)
        changed=copy.deepcopy(actions);changed[0]['expected']['bytes']=[18]
        self.assertEqual(p.candidate_program(actions),p.candidate_program(changed))
        self.assertNotEqual(p.memory.action_digest(actions),p.memory.action_digest(changed))

    def test_every_lane_batch_must_match_exact_plan_and_full_byte_count(self):
        actions=unit_actions(33);plan=p.plan_partitions(actions)
        for key,value in [('start',False),('count',32.0),('source_bytes',1),
                          ('source_sha256','0'*64),('actions_sha256','0'*64),
                          ('compared_bytes',0),('bytes',0),('bytes',True),('passed',1),('extra',0)]:
            lanes=lanes_for(plan);lanes['javascript']['batches'][0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):p.finish_lanes(lanes,actions,plan)
            self.assertTrue(all(row['passed'] is False for row in lanes.values()))
        for batch in ([],plan,lanes_for(plan)['cpu-1']['batches'][::-1],
                      lanes_for(plan)['cpu-1']['batches']*2):
            lanes=lanes_for(plan);lanes['cpu-2']['batches']=batch
            with self.assertRaises(ValueError):p.finish_lanes(lanes,actions,plan)

    def test_complete_real_corpus_plan_preserves_all_file_roles_and_bytes(self):
        cases=[dict(c,path=c['filename']) for c in p.fixtures()]
        invalid=[dict(c,path=c['filename']) for c in p.controls()]
        actions=p.candidate_actions(cases,invalid,reference(cases));plan=p.plan_partitions(actions)
        self.assertEqual((len(actions),len(plan)),(1283,41))
        self.assertEqual(sum(b['compared_bytes'] for b in plan),854352)
        self.assertEqual(sum(b['count'] for b in plan),1283)
        self.assertTrue(all(0<b['source_bytes']<=p.SOURCE_BYTE_LIMIT for b in plan))
        self.assertEqual([a for b in plan for a in actions[b['start']:b['start']+b['count']]],actions)
        lanes=lanes_for(plan);p.finish_lanes(lanes,actions,plan)
        self.assertTrue(all(row['passed'] for row in lanes.values()))


class TgaFileRunGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=p.ROOT);self.work=Path(self.temp.name);p.memory.SEALED.clear()
    def tearDown(self):p.memory.SEALED.clear();self.temp.cleanup()

    def test_files_are_real_exact_cap_and_sparse_are_pre_read_controls(self):
        cases=p.fixtures();invalid=p.controls();stress,stage=p.prepare_inputs(self.work,cases,invalid)
        self.assertEqual(stage['stage'],'read');self.assertEqual(stage['code'],p.errno.EISDIR)
        self.assertEqual(len(stress['bytes']),1048576);self.assertEqual((p.ROOT/stress['path']).stat().st_size,1048576)
        self.assertEqual(stress['bytes'][:19],next(c['bytes'] for c in cases if c['id']=='c1-single'))
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
        self.assertEqual(p.report_directories(['--build-di',str(a)]),[p.BUILD/'tga-file-probe'])
        self.assertEqual(p.report_directories(['--','--build-dir',str(a)]),[p.BUILD/'tga-file-probe'])

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
        with self.assertRaisesRegex(ValueError,'timed out'):
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
        actions=unit_actions();partitions=p.plan_partitions(actions);lanes=lanes_for(partitions)
        good=copy.deepcopy(lanes);p.finish_lanes(good,actions,partitions);self.assertTrue(all(v['passed'] for v in good.values()))
        variants=[]
        for kind in ('boundary','sparse','exact_cap'):
            bad=copy.deepcopy(lanes);del bad['cpu-1'][kind];variants.append(bad)
            bad=copy.deepcopy(lanes);bad['javascript'][kind]['passed']=False;variants.append(bad)
            bad=copy.deepcopy(lanes);bad['cpu-2'][kind]['descriptor_limit']=65;variants.append(bad)
        for key,value in [('start',True),('count',0),('count',33),('passed',False)]:
            bad=copy.deepcopy(lanes);bad['cpu-2']['batches'][0][key]=value;variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-1']['differences']=[{}];variants.append(bad)
        bad=copy.deepcopy(lanes);del bad['javascript'];variants.append(bad)
        bad=copy.deepcopy(lanes);bad['gpu']=copy.deepcopy(bad['cpu-1']);variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-2']['batches']=[];variants.append(bad)
        bad=copy.deepcopy(lanes);bad['cpu-1']['differences']=();variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):p.finish_lanes(bad,actions,partitions)
            self.assertFalse(any(row.get('passed') for row in bad.values()))
        with self.assertRaises(ValueError):p.finish_lanes(lanes,[],[])

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
            default=self.work/'tga-file-probe';default.mkdir();(default/'results.json').write_text('{"passed":true}')
            with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):p.main(['--unknown'])
            self.assertFalse(json.loads((default/'results.json').read_text())['passed'])

    def test_duplicate_cli_destinations_reset_even_when_parsing_fails(self):
        a=self.work/'a';b=self.work/'b'
        for directory in (a,b):directory.mkdir();(directory/'results.json').write_text('{"passed":true}')
        with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):p.main(self.arguments(a)+['--build-dir='+str(b),'--unknown'])
        for directory in (a,b):self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_checkout_setup_failure_cannot_inherit_success(self):
        directory=self.work/'checkout';directory.mkdir();(directory/'results.json').write_text('{"passed":true}')
        with patch.object(p,'checkout',side_effect=ValueError('wrong revision')),patch.object(p,'native_archive') as archive,self.assertRaisesRegex(ValueError,'wrong revision'):p.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_native_input_safety_failure_precedes_archive_or_decoder(self):
        directory=self.work/'bad-fixture';bad=p.fixtures();bad[0]['bytes']=[0]
        with patch.object(p,'checkout'),patch.object(p,'fixtures',return_value=bad),patch.object(p,'native_archive') as archive,self.assertRaises(ValueError):p.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_missing_tool_setup_failure_cannot_use_stale_archive(self):
        directory=self.work/'missing-tool'
        with patch.object(p,'checkout'),patch.object(p.shutil,'which',return_value=None),patch.object(p,'native_archive') as archive,self.assertRaisesRegex(ValueError,'Required tool missing'):p.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_native_build_failure_preserves_failed_scoped_report(self):
        directory=self.work/'native-failure'
        with patch.object(p,'checkout'),patch.object(p.shutil,'which',return_value=sys.executable),patch.object(p,'native_archive',side_effect=ValueError('TGA compile definition missing')) as archive,self.assertRaisesRegex(ValueError,'TGA compile definition missing'):p.main(self.arguments(directory))
        archive.assert_called_once();report=json.loads((directory/'results.json').read_text())
        self.assertFalse(report['passed']);self.assertEqual(report['cases'],225);self.assertEqual(report['native_rejections'],0)
        self.assertTrue(all(v['passed'] is False for v in report['lanes'].values()))

    def test_bad_native_qualification_cannot_reach_candidate_compile(self):
        directory=self.work/'qualification';commands=[]
        def record(command,*args,**kwargs):
            commands.append(list(map(str,command)))
            if command==['bun','--version']:return '1.3.12\n'
            if command==['clang','--version']:return 'test compiler\n'
            return '{}\n'
        with patch.object(p,'checkout'),patch.object(p.shutil,'which',return_value=sys.executable),patch.object(p,'native_archive',return_value=(self.work/'test.a',{})),patch.object(p,'record_run',side_effect=record),self.assertRaises(ValueError):p.main(self.arguments(directory))
        self.assertFalse(any('candidate-' in ' '.join(c) for c in commands));self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_ordinary_file_and_dependency_drift_cannot_pass_input_verification(self):
        cases=p.fixtures();invalid=p.controls();stress,_=p.prepare_inputs(self.work,cases,invalid)
        file=p.ROOT/cases[0]['path'];original=file.read_bytes();p.memory.seal(file);file.write_bytes(original+b'x')
        with self.assertRaisesRegex(ValueError,'identity drift'):p.verify_inputs(cases,invalid,stress)
        file.write_bytes(original)
        p.memory.SEALED.clear();dependency=self.work/'dependency.py';dependency.write_text('original');p.memory.seal(dependency);dependency.unlink()
        with self.assertRaisesRegex(ValueError,'artifact drift'):p.verify_inputs(cases,invalid,stress)

    def test_unsealed_accepted_file_and_exact_cap_identity_are_checked(self):
        cases=p.fixtures();invalid=p.controls();stress,_=p.prepare_inputs(self.work,cases,invalid)
        self.assertEqual(p.memory.SEALED,{})
        for case in (cases[0],stress):
            path=p.ROOT/case['path'];original=path.read_bytes()
            path.write_bytes(original[:-1]+bytes([original[-1]^1]))
            with self.assertRaisesRegex(ValueError,'identity drift'):p.verify_inputs(cases,invalid,stress)
            path.write_bytes(original)
        p.verify_inputs(cases,invalid,stress)

    def test_special_file_recipe_type_size_and_prefix_are_required(self):
        cases=p.fixtures();invalid=p.controls();stress,_=p.prepare_inputs(self.work,cases,invalid)
        sparse=next(c for c in invalid if c.get('special')=='sparse')
        for change in (dict(size=True),dict(size=float(sparse['size'])),dict(size=sparse['size']-1),
                       dict(prefix=[]),dict(prefix=[True]+sparse['prefix'][1:]),
                       dict(sparse_recipe='unverified')):
            with self.subTest(change=change),self.assertRaises(ValueError):
                p.validate_controls([dict(sparse,**change)])

    def test_invalid_control_schema_rejects_before_native_build(self):
        directory=self.work/'bad-control';invalid=p.controls();invalid[0]['bytes']=[256]
        with patch.object(p,'checkout'),patch.object(p,'controls',return_value=invalid),\
             patch.object(p,'native_archive') as archive,self.assertRaises(ValueError):
            p.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_native_alias_definitions_are_explicit_and_checked_before_build(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))()
        for alias in p.ALIAS_MACROS:
            work=self.work/alias;work.mkdir();commands=[]
            def record(command,work,label,**kwargs):
                commands.append(list(map(str,command)))
                self.assertEqual(label,'configure')
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(native_cache())
                (directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(native_flags().replace('-DSUPPORT_FILEFORMAT_'+alias,''))
            with self.subTest(alias=alias),self.assertRaises(ValueError):p.native_archive(args,work,record)
            self.assertEqual(len(commands),1)
            for name in p.ALIAS_MACROS:self.assertIn('-DSUPPORT_FILEFORMAT_'+name+'=ON',commands[0])
            self.assertIn('-DCUSTOMIZE_BUILD=ON',commands[0])

    def test_fresh_native_archive_seals_alias_config_compiler_and_archive(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))();labels=[]
        compiler=self.work/'compiler';compiler.write_text('unit-test compiler')
        def record(command,work,label,**kwargs):
            labels.append(label)
            directory=work/'raylib-build'
            if label=='configure':
                (directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeFiles/version').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(native_cache())
                (directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(native_flags())
                (directory/'CMakeFiles/version/CMakeCCompiler.cmake').write_text(
                    'set(CMAKE_C_COMPILER "'+str(compiler)+'")\nset(CMAKE_C_COMPILER_ID "Clang")\nset(CMAKE_C_COMPILER_VERSION "1")\n')
            elif label=='native-build':
                for path in (compiler,directory/'CMakeCache.txt',directory/'raylib/CMakeFiles/raylib.dir/flags.make'):
                    self.assertIn(str(path.resolve()),p.memory.SEALED)
                (directory/'raylib/libraylib.a').write_bytes(b'unit-test archive')
            return 'unit-test compiler version 1\n'
        archive,receipt=p.native_archive(args,self.work,record)
        self.assertEqual(labels,['configure','archive-compiler-version','native-build'])
        self.assertEqual(receipt['mode'],'fresh-isolated-build')
        self.assertEqual(receipt['artifacts'][str(archive)],p.memory.digest(archive))
        self.assertEqual(receipt['file_aliases']['recognized_tokens'],sorted(p.RECOGNIZED))
        p.memory.verify_sealed()
        with self.assertRaisesRegex(ValueError,'fresh'):
            p.native_archive(args,self.work,lambda *a,**kw:self.fail('stale archive reused'))
        archive.write_bytes(b'drift')
        with self.assertRaisesRegex(ValueError,'artifact drift'):p.memory.verify_sealed()

    def test_tracked_source_manifest_includes_file_gate_tests_and_upstream_dependencies(self):
        bend=self.work/'bend/bend2';bend.mkdir(parents=True)
        raylib=self.work/'raylib';raylib.mkdir()
        compiler=bend/'compiler.ts';compiler.write_text('unit compiler')
        native=raylib/'rtextures.c';native.write_text('unit native source')
        args=type('Args',(),dict(bend_source=bend.parent,raylib_source=raylib))()
        before=p.tracked_sources(args)
        for path in (p.ROOT/'tools/tga_file_probe.py',p.ROOT/'tests/test_tga_file_harness.py',
                     p.ROOT/'tools/tga_format_probe.py',p.ROOT/'tests/test_tga_format_harness.py',
                     p.ROOT/'tools/raw_file_probe.py',p.ROOT/'tools/r32_raw_file_probe.py',
                     p.ROOT/'toolchain.json',compiler,native):
            self.assertEqual(before['dependencies'][str(path)],p.memory.digest(path))
        self.assertIn('jonlib.bend',before['library'])
        compiler.write_text('changed compiler');self.assertNotEqual(p.tracked_sources(args),before)

    def test_real_resource_child_observes_fd_limit_and_sealed_usage(self):
        output,usage=p.resource_run([sys.executable,'-c','import resource;print(resource.getrlimit(resource.RLIMIT_NOFILE))'],
                                    self.work,'actual-resource',p.MAX_SPARSE_RSS,os.environ.copy(),None,5)
        self.assertEqual(output.strip(),'(64, 64)')
        self.assertEqual(usage['descriptor_limit'],64)
        self.assertGreater(usage['maximum_rss_bytes'],0)
        self.assertLessEqual(usage['maximum_rss_bytes'],p.MAX_SPARSE_RSS)
        for name in ('actual-resource.resource-runner.py','actual-resource.resource.json',
                     'actual-resource.command.json','actual-resource.stdout','actual-resource.stderr'):
            self.assertIn(str((self.work/name).resolve()),p.memory.SEALED)
        p.memory.verify_sealed()

    def test_resource_completion_rejects_forged_types_missing_and_excess_receipts(self):
        actions=unit_actions();partitions=p.plan_partitions(actions);lanes=lanes_for(partitions)
        for key,value in [('descriptor_limit',64.0),('maximum_rss_bytes',True),('maximum_rss_bytes',0),('maximum_rss_bytes',p.MAX_SPARSE_RSS+1),('maximum_rss_acceptance_bytes',p.MAX_STRESS_RSS),('maximum_rss_acceptance_bytes',float(p.MAX_SPARSE_RSS))]:
            bad=copy.deepcopy(lanes);bad['cpu-1']['sparse'][key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):p.finish_lanes(bad,actions,partitions)
        for key in ('maximum_rss_bytes','maximum_rss_acceptance_bytes'):
            bad=copy.deepcopy(lanes);del bad['cpu-1']['sparse'][key]
            with self.assertRaises(ValueError):p.finish_lanes(bad,actions,partitions)

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
        with self.assertRaisesRegex(ValueError,'timed out'):p.record_run([sys.executable,'-c',parent,'-o',output],self.work,'compiler-timeout',timeout=0.3)
        self.assertTrue(started.exists());time.sleep(0.8);self.assertFalse(output.exists())
        row=json.loads((self.work/'compiler-timeout.command.json').read_text())
        self.assertTrue(row['timed_out']);self.assertNotIn('descriptor_limit',row);self.assertNotEqual(row['exit_code'],0)

    def test_successful_compiler_must_create_nonempty_fresh_outputs(self):
        output=self.work/'output'
        for index,code in enumerate(('pass','from pathlib import Path;Path('+repr(str(output))+').write_bytes(b"")')):
            p.memory.SEALED.clear()
            output.write_bytes(b'stale')
            with self.assertRaisesRegex(ValueError,'Compiler output missing'):p.record_run([sys.executable,'-c',code,'-o',output],self.work,'missing-output'+str(index))
        p.memory.SEALED.clear()
        output.unlink(missing_ok=True)
        code='from pathlib import Path;Path('+repr(str(output))+').write_text("fresh")'
        p.record_run([sys.executable,'-c',code,'-o',output],self.work,'created')
        self.assertEqual(output.read_text(),'fresh');p.memory.verify_sealed();output.write_text('drift')
        with self.assertRaisesRegex(ValueError,'artifact drift'):p.record_run([sys.executable,'-c','pass'],self.work,'after-drift')

    def test_all_command_receipts_preserve_clean_environment_and_actual_limits(self):
        receipt={'policy':'clean-loader'}
        text=p.record_run([sys.executable,'-c','import os;print(os.environ["ONLY"])'],self.work,'environment',environment={'ONLY':'expected'},receipt=receipt,require_output=True)
        self.assertEqual(text,'expected\n');row=json.loads((self.work/'environment.command.json').read_text())
        self.assertEqual(row['reference_environment'],receipt);self.assertNotIn('descriptor_limit',row);self.assertTrue(row['process_group_owned'])
        self.assertEqual(row['exit_code'],0);self.assertFalse(row.get('timed_out',False));p.memory.verify_sealed()

    def test_child_start_failure_retains_fail_closed_receipt(self):
        with self.assertRaisesRegex(ValueError,'could not start'):p.record_run([self.work/'missing-command'],self.work,'start-failure')
        row=json.loads((self.work/'start-failure.command.json').read_text())
        self.assertIsNone(row['exit_code']);self.assertEqual(row['startup_error'],'FileNotFoundError');self.assertFalse(row.get('timed_out',False))

    def test_dependency_archive_loader_and_provenance_sealing_are_required(self):
        source=(p.ROOT/'tools/tga_file_probe.py').read_text()
        for text in ('reference_env.require_clear()','reference_env.child()','reference_env.receipt()','reference_env.assert_receipt','native_archive(args,work,native_record)','memory.native_archive(args,work,explicit_record)','memory.qualification(output)','tool_realpaths','tracked_sources(args)!=report','memory.verify_sealed()','evidence_origin=','NEW source-scoped file run','tests/test_tga_file_harness.py','verify_inputs(cases,invalid,stress)','boundary_source_contract()'):self.assertIn(text,source)
        self.assertLess(source.index("('qualification',qualification_program())"),source.index('candidate_actions(cases,invalid,file_reference)'))
        self.assertIn('SUPPORT_FILEFORMAT_TGA=ON',(p.ROOT/'tools/tga_format_probe.py').read_text())
        self.assertNotIn('os.environ[',source)


if __name__=='__main__':unittest.main()
