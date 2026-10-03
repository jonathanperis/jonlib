"""Adversarial checks for the native BMP file gate, without native input UB."""
import copy
import io
import json
import struct
from contextlib import ExitStack
import hashlib
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import bmp_file_probe as f
import bmp_format_probe as m


def reference(cases):
    # Protocol/unit-test dummy samples only; runtime expectations come exclusively
    # from actual native observations. Never use this in the differential gate.
    result={}
    for c in cases:
        pixels=c['width']*c['height']
        result[c['id']]=(dict(m.meta(c,'raw'),bytes=[17]*(pixels*c['channels'])),dict(m.meta(c,'normalized'),bytes=[17,17,17,255]*pixels))
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
    return [dict(case=dict(id=f'unit-{i}',width=1,height=1,channels=3,
                          bytes=m.bitmap(1,1,[0x111111ff]),extended=False,
                          filename=f'unit-{i}.bmp',path=f'unit-{i}.bmp',
                          route='LoadImage',regress=False),
                 role='raw',expected=dict(id=f'unit-{i}',role='raw',width=1,
                                         height=1,mipmaps=1,format=4,bytes=[17,17,17]),
                 normalized=[17,17,17,255]) for i in range(count)]


def lanes_for(partitions):
    def receipt(ceiling):
        return dict(passed=True,descriptor_limit=64,maximum_rss_bytes=1,
                    maximum_rss_acceptance_bytes=ceiling,elapsed_seconds=0.01,observations=1,
                    compared_bytes=0,actions_sha256='0'*64,stdout_sha256='1'*64)
    return {lane:dict(passed=False,
                      batches=[dict(entry,bytes=entry['compared_bytes'],passed=True)
                               for entry in partitions],differences=[],
                      boundary=receipt(f.MAX_SPARSE_RSS),
                      sparse=receipt(f.MAX_SPARSE_RSS),
                      exact_cap=receipt(f.MAX_STRESS_RSS)) for lane in f.LANES}


def native_cache():
    fields=dict(PLATFORM='Memory',CMAKE_BUILD_TYPE='Release',CUSTOMIZE_BUILD='ON',
                SUPPORT_MODULE_RAUDIO='OFF',BUILD_EXAMPLES='OFF',USE_EXTERNAL_GLFW='OFF')
    fields.update({'SUPPORT_FILEFORMAT_'+name:'ON' for name in f.ALIAS_MACROS})
    return '\n'.join(k+':STRING='+v for k,v in fields.items())+'\n'


def native_flags():
    return 'C_DEFINES = -DEXTERNAL_CONFIG_FLAGS -DPLATFORM_MEMORY '+\
           ' '.join('-DSUPPORT_FILEFORMAT_'+name for name in f.ALIAS_MACROS)+'\n'


class BmpFileFixtureTests(unittest.TestCase):
    def setUp(self):
        self.cases=f.fixtures();self.invalid=f.controls();self.case=next(c for c in self.cases if c['id']=='c3-single')

    def test_exact_primary_matrix_and_all_memory_inputs_retained(self):
        self.assertEqual(len(self.cases),294);self.assertEqual(sum(c['width']*c['height'] for c in self.cases),39259)
        self.assertEqual(sum(c['route']=='LoadImage' for c in self.cases),272)
        self.assertEqual(sum(c['route']=='explicit-bmp' for c in self.cases),22)
        original=m.fixtures();self.assertEqual(len(original),224)
        by_id={c['id']:c for c in self.cases}
        for c in original:self.assertEqual({k:by_id[c['id']][k] for k in f.BASE_KEYS},c)
        self.assertEqual(sum(c['width']*c['height'] for c in original),39189)
        f.validate_cases(self.cases)

    def test_suffix_matrix_covers_both_native_layouts_and_every_enabled_alias(self):
        for channels in (3,4):
            rows=[c for c in self.cases if c['id'].startswith(f'path-c{channels}-')]
            self.assertEqual(len(rows),35);self.assertTrue(all(c['regress'] for c in rows))
            self.assertEqual(sum(c['route']=='explicit-bmp' for c in rows),11)
            original=next(c for c in self.cases if c['id']==f'c{channels}-single')
            for c in rows:
                self.assertEqual(c['bytes'],original['bytes']);self.assertEqual(c['channels'],channels)
                self.assertEqual(c['route']=='LoadImage',f.extension('fixtures/'+c['filename']) in f.RECOGNIZED)
            observed={f.extension('fixtures/'+c['filename']) for c in rows if c['route']=='LoadImage'}
            self.assertEqual(observed,f.RECOGNIZED)
            text=' '.join(c['filename'] for c in rows)
            for suffix in ('.BmP','.JpEg','.pnm','.PNM','.qoi','.QOI','.dat',' with spaces','.a.b.','/.bmp','.bmp/leaf'):
                self.assertIn(suffix,text)
            self.assertTrue(any(c['filename'].endswith('suffixless') for c in rows))
            self.assertTrue(any(c['filename'].endswith('.') for c in rows))

    def test_native_schema_and_safety_mutations_fail_closed(self):
        changes=[dict(width=0),dict(width=4097),dict(width=True),dict(height=1.0),dict(channels=1),dict(extended=1),dict(regress=1),dict(id='unsafe"id'),dict(bytes=self.case['bytes'][:-1]),dict(bytes=[*self.case['bytes'],256]),dict(bytes=[*self.case['bytes'],True]),dict(bytes=[*self.case['bytes'],17.0]),dict(bytes=bytes(self.case['bytes'])),dict(special='sparse'),dict(native=True),dict(route='explicit-qoi'),dict(route='explicit-bmp'),dict(route=True),dict(filename='image.QoI'),dict(filename='../image.bmp'),dict(filename='/image.bmp'),dict(filename='image\0.bmp'),dict(filename=''),dict(filename=True),dict(path='\0'),dict(path=''),dict(path=True),dict(bytes=[0])]
        for change in changes:
            with self.subTest(change=change),self.assertRaises(ValueError):f.validate_cases([dict(self.case,**change)])
        for cases in ([],(),[self.case,self.case],self.invalid[:1],[dict(self.case,id='different'),self.case]):
            with self.assertRaises(ValueError):f.validate_cases(cases)
        with patch.object(f,'BMP_CAP',1),self.assertRaises(ValueError):f.validate_cases([self.case])
        with patch.object(m,'MAX_TOTAL_BYTES',1),self.assertRaises(ValueError):f.validate_cases([self.case])
        for key in f.BASE_KEYS|{'route','regress','filename'}:
            bad=self.case.copy();del bad[key]
            with self.subTest(missing=key),self.assertRaises(ValueError):f.validate_cases([bad])

    def test_typed_controls_are_file_byte_safe_and_never_native(self):
        self.assertEqual(len(self.invalid),229);by_id={c['id']:c for c in self.invalid}
        for c in self.invalid:
            self.assertTrue(all(type(b) is int and 0<=b<=255 for b in c.get('bytes',[])))
            self.assertNotIn('native',c)
            with self.assertRaises(ValueError):f.reference_program([dict(c,path=c['filename'])])
        safe=[c for c in m.controls() if all(type(b) is int and 0<=b<=255 for b in c['bytes'])]
        self.assertEqual(len(safe),218)
        for c in safe:
            self.assertEqual(by_id[c['id']]['bytes'],c['bytes']);self.assertEqual(by_id[c['id']]['error'],c['error'])
        for ident,error in [('not-bmp-png',0),('not-bmp-qoi',0),('not-bmp-pnm',0),('not-bmp-tga',0),
                            ('missing',5),('missing-parent',5),('directory',5),('cap-plus-one',2),
                            ('cap-misleading',2),('larger-file',2),('host-size-overflow',5),
                            ('bad-header-before-size',0),('bad-size-before-truncated',2)]:
            self.assertEqual(by_id[ident]['error'],error)
        self.assertTrue(all(type(c['error']) is int and 0<=c['error']<=5 for c in self.invalid))

    def test_nonbyte_controls_remain_exact_synthetic_memory_inputs(self):
        synthetic=f.synthetic_controls();expected=[c for c in m.controls() if any(v>255 for v in c['bytes'])]
        self.assertEqual(len(synthetic),379);self.assertEqual(synthetic,expected)
        self.assertFalse({c['id'] for c in synthetic}&{c['id'] for c in self.invalid})
        self.assertEqual(len(synthetic)+218,len(m.controls()))
        for case in synthetic:
            self.assertNotIn('filename',case);self.assertNotIn('path',case)
            with self.assertRaises(ValueError):f.reference_program([case])
            with self.assertRaises(ValueError):f.validate_controls([dict(case,filename=case['id']+'.bmp')])
        actions=f.candidate_actions([dict(self.case,path=self.case['filename'])],[],reference([self.case]),synthetic)
        emitted=[a for a in actions if a['case']['id'] in {c['id'] for c in synthetic}]
        self.assertEqual(len(emitted),379)
        for a,c in zip(emitted,synthetic):
            self.assertEqual(a['case']['bytes'],c['bytes']);self.assertEqual(a['expected']['error'],c['error'])
            self.assertEqual(a['role'],'formatted-error')
        text=f.candidate_program(emitted)
        self.assertIn('J.Image.Formatted.bmp.file.loaded(Done{',text)
        self.assertNotIn('J.Image.Formatted.load_bmp(',text.split('def main()',1)[1])

    def test_native_file_route_and_raw_observation_order(self):
        for channels in (3,4):
            original=next(c for c in self.cases if c['id']==f'c{channels}-single')
            cases=[dict(original,path='native.bmp'),dict(original,id='explicit',filename='explicit.dat',path='explicit.dat',route='explicit-bmp')]
            text=f.reference_program(cases)
            for token in ('if(!little_endian())','Image image=LoadImage("native.bmp")','LoadFileData("explicit.dat",&size)',f'size!={len(original["bytes"])}','LoadImageFromMemory(".bmp",data,size);UnloadFileData(data)','image.mipmaps!=1',f'image.format!={m.FORMATS[channels]}',f'GetPixelDataSize(image.width,image.height,image.format)!={channels}','GetPixelDataSize(image.width,image.height,image.format)!=4'):
                self.assertIn(token,text)
            for block in text.split('Image image=')[1:]:
                self.assertLess(block.index('"raw",image)'),block.index('ImageFormat(&image,7)'))
                self.assertLess(block.index('ImageFormat(&image,7)'),block.index('"normalized",image)'))
            self.assertNotIn('LoadImageColors',text);self.assertNotIn('stbi_load',text)
            self.assertNotIn('decode_bmp',text)
        with self.assertRaises(ValueError):f.reference_program([self.case])

    def test_whole_path_last_dot_rule_distinguishes_literal_and_qualified_dotfile(self):
        for path,want in [('.bmp',''),('fixtures/.bmp','.bmp'),('/.bmp','.bmp'),
                          ('image.BMP','.BMP'),('image.TgA','.TgA'),
                          ('parent.bmp/leaf','.bmp/leaf'),('parent.png/leaf','.png/leaf'),
                          ('parent.dot/leaf.bmp','.bmp'),('file.','.'),('plain','')]:
            with self.subTest(path=path):self.assertEqual(f.extension(path),want)
        for path in (None,True,17,'bad\0.bmp'):
            with self.assertRaises(ValueError):f.extension(path)
        f.validate_cases([dict(self.case,filename='.bmp',path='fixtures/.bmp')])
        f.validate_cases([dict(self.case,filename='.bmp',path='.bmp',route='explicit-bmp')])
        for case in (dict(self.case,path='.bmp'),
                     dict(self.case,path='parent.bmp/leaf'),
                     dict(self.case,path='parent.bmp/leaf.png',route='explicit-bmp')):
            with self.assertRaises(ValueError):f.validate_cases([case])

    def test_only_explicitly_enabled_alias_tokens_are_native(self):
        self.assertEqual(set(f.ALIAS_MACROS),{'BMP','PNG','TGA','JPG','GIF','PIC','PNM','PSD'})
        names=('bmp','png','tga','jpg','jpeg','gif','pic','pgm','ppm','psd')
        self.assertEqual(f.RECOGNIZED,{'.'+n for n in names}|{'.'+n.upper() for n in names})
        for token in sorted(f.RECOGNIZED):
            f.validate_cases([dict(self.case,filename='safe'+token,path='safe'+token)])
        for token in ('.BmP','.JpEg','.PpM','.qoi','.QOI','.pnm','.PNM','.dat','','.'):
            case=dict(self.case,filename='safe'+token,path='safe'+token)
            with self.assertRaises(ValueError):f.validate_cases([case])
            f.validate_cases([dict(case,route='explicit-bmp')])

    def test_independent_safety_parser_runs_before_native_source_emission(self):
        with patch.object(m,'inspect_header',wraps=m.inspect_header) as inspect:
            f.reference_program([dict(self.case,path='safe.bmp')])
        self.assertEqual(inspect.call_args.args[0],self.case['bytes'])
        # Complete header declarations never substitute for a complete raster,
        # every required palette/mask byte, or the pinned native double skip.
        bad=[m.bitmap(4096,4096,[0x123456ff]),self.case['bytes'][:-1],
             m.indexed_bitmap(1,1,[1],[0x010203ff]),
             m.bitfield_bitmap(1,1,[0x1234],dib=40)[:-1]]
        data=m.bitmap(1,1,[0x123456ff]);data[10:14]=list(struct.pack('<I',len(data)))
        bad.append(data)
        for data in bad:
            with self.assertRaises(ValueError):f.reference_program([dict(self.case,path='unsafe.bmp',bytes=data)])
        with patch.object(m,'inspect_header',side_effect=ValueError('incomplete BMP stream')):
            with self.assertRaisesRegex(ValueError,'incomplete BMP stream'):
                f.reference_program([dict(self.case,path='safe.bmp')])

    def test_alias_native_cache_and_actual_compiled_macros_fail_closed(self):
        receipt=f.validate_alias_config(native_cache(),native_flags())
        self.assertEqual(receipt['enabled_macros'],['SUPPORT_FILEFORMAT_'+n for n in f.ALIAS_MACROS])
        self.assertEqual(receipt['recognized_tokens'],sorted(f.RECOGNIZED))
        for name in f.ALIAS_MACROS:
            macro='SUPPORT_FILEFORMAT_'+name
            for value in ('OFF','TRUE','1',''):
                with self.subTest(macro=macro,cache=value),self.assertRaises(ValueError):
                    f.validate_alias_config(native_cache().replace(macro+':STRING=ON',macro+':STRING='+value),native_flags())
            for token in ('','-D'+macro+'=0','-U'+macro,'-D'+macro+' -U'+macro,
                          '-D'+macro+' -D'+macro+'=1','-D '+macro+'=0','-U '+macro):
                with self.subTest(macro=macro,flags=token),self.assertRaises(ValueError):
                    f.validate_alias_config(native_cache(),native_flags().replace('-D'+macro,token))
            for token in ('-D'+macro+'=1','-D '+macro,'-D '+macro+'=1'):
                f.validate_alias_config(native_cache(),native_flags().replace('-D'+macro,token))
        for flags in (native_flags()+' -D',native_flags()+' -U',native_flags()+' -DPLATFORM_DESKTOP'):
            with self.assertRaises(ValueError):f.validate_alias_config(native_cache(),flags)
        with self.assertRaises(ValueError):f.validate_alias_config(native_cache()+'SUPPORT_FILEFORMAT_PNG:BOOL=ON\n',native_flags())

    def test_controls_reject_wrong_types_bytes_schemas_and_native_inputs(self):
        ordinary=next(c for c in self.invalid if 'bytes' in c)
        for change in (dict(error=True),dict(error=3.0),dict(error=6),dict(error=-1),
                       dict(bytes=[256]),dict(bytes=[-1]),dict(bytes=[True]),dict(bytes=[1.0]),
                       dict(bytes=b'\0'),dict(bytes=self.case['bytes']),dict(native=False),
                       dict(filename='../bad.bmp'),dict(filename='/bad.bmp'),
                       dict(filename='bad\0.bmp'),dict(filename=''),dict(path=True)):
            with self.subTest(change=change),self.assertRaises(ValueError):
                f.validate_controls([dict(ordinary,**change)])
        for missing in ('id','filename','error','bytes'):
            bad=ordinary.copy();del bad[missing]
            with self.assertRaises(ValueError):f.validate_controls([bad])
        for cases in (None,(),[None],[ordinary,ordinary]):
            with self.assertRaises(ValueError):f.validate_controls(cases)
        for special,error in [('missing',5),('directory',5),('sparse',2),('large',2),('overflow',5)]:
            case=dict(id='special',filename='special.bmp',special=special,error=error)
            f.validate_controls([case])
            for change in (dict(error=0),dict(error=True),dict(special='unknown'),dict(special=True),dict(bytes=[])):
                with self.assertRaises(ValueError):f.validate_controls([dict(case,**change)])


class BmpFileOwnershipAndBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.cases=[dict(c,path=c['filename']) for c in f.fixtures()];self.invalid=[dict(c,path=c['filename']) for c in f.controls()];self.ref=reference(self.cases)

    def test_wrapper_reuses_closed_bounded_shared_boundary(self):
        source=(f.ROOT/'jonlib.bend').read_text()
        wrapper=source.split('def Image.Formatted.load_bmp(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Image.file.bytes(path, Image.file.limit(RasterFile{}))',wrapper)
        self.assertIn('Image.Formatted.bmp.file.loaded',wrapper)
        for bad in ('Surface','Image.file.kind','QoiFile','decode_image'):self.assertNotIn(bad,wrapper)
        continuation=source.split('def Image.Formatted.bmp.file.loaded(',1)[1].split('\ndef ',1)[0]
        self.assertIn('Fail{error}',continuation);self.assertIn('Image.file.decoded(Image.Formatted, Image.Formatted.decode_bmp(bytes))',continuation)
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
        self.assertIn('law raster_file_limit:',(f.ROOT/'LAWS.bend').read_text())

    def test_primary_and_owner_calls_reopen_real_public_files(self):
        actions=f.candidate_actions(self.cases,self.invalid,self.ref);text=f.candidate_program(actions);main=text.split('def main()',1)[1]
        for call in ('J.Image.Formatted.load_bmp(','J.Surface.load_image(','J.UncontractedDecode{}','J.FusedDecode{}','owner.emitted(','bridge.emitted(','file.failed('):self.assertIn(call,main)
        self.assertNotIn('decode_bmp',main);self.assertNotIn('from_bytes',main)
        for term in ('word <= 16777215','J.Image.Formatted.get','4294967295','J.Image.Formatted.export','surface.bmp.loaded'):self.assertIn(term,text)
        for case in self.cases:
            path=json.dumps(case['path']);self.assertEqual(main.count('J.Image.Formatted.load_bmp('+path+')'),3)
            self.assertEqual(main.count('surface.bmp('+path+')'),1)
        with self.assertRaises(ValueError):f.candidate_program([])
        with self.assertRaises(ValueError):f.candidate_program([dict(actions[0],role='bogus')])

    def test_action_expectations_are_native_and_modes_stay_distinct(self):
        actions=f.candidate_actions(self.cases,self.invalid,self.ref)
        self.assertEqual(len(actions),1805)
        for a in actions:
            c=a['case'];role=a['role']
            if role.endswith('error'):continue
            expected=self.ref[c['id']][0 if role in ('raw','owner') else 1]
            self.assertEqual(a['expected'],dict(expected,role=role))
            if role in ('dispatch-bmp','uncontracted','fused'):self.assertEqual(c['route'],'LoadImage')
        for case in self.cases:
            roles=[a['role'] for a in actions if a['case']['id']==case['id']]
            self.assertEqual(roles[:4],['raw','owner','bridge','surface'])
            self.assertEqual(set(roles[4:]),{'dispatch-bmp','uncontracted','fused'} if case['regress'] and case['route']=='LoadImage' else set())
        self.assertEqual(sum(a['role']=='surface-error' for a in actions),22)
        text=f.candidate_program([next(a for a in actions if a['role']=='surface-error')])
        body=text.split('def surface.failed(',1)[1].split('def require(',1)[0]
        self.assertIn('"surface-error"',body);self.assertNotIn('"formatted-error"',body)

    def test_closure_uses_ten_acquired_handle_paths_and_exact_messages(self):
        text=f.boundary_program(self.cases,self.invalid)
        for token in ('closure_loop(100n)','File.open(','J.Image.file.read(2, (file, Done{[1]}))',
                      'J.Image.file.read(1, (file, Done{[1, 2]}))','stage-read-failure','stage-size-failure',
                      'J.Image.file.sized(1048576','continuation-failure','payload-failure','Done{[256]}',
                      '1048576 <=','1048577 <=','String.eq(message, text)',
                      'def stage.emitted(id: String, +expected: U32,','load.emitted("closure-final", "raw")'):
            self.assertIn(token,text)
        loop=text.split('def closure_loop(',1)[1].split('def main()',1)[0]
        self.assertEqual(loop.count('J.Image.Formatted.load_bmp('),6);self.assertEqual(loop.count('File.open('),4)
        self.assertNotIn('LoadImage(',text)
        actions=f.boundary_actions(self.cases,self.invalid,self.ref)
        self.assertEqual(len(actions),1009);self.assertEqual(f.TERMINAL['paths_per_iteration'],10)
        self.assertEqual(f.TERMINAL['iterations'],100);self.assertEqual(f.TERMINAL['synthetic_checks'],8)
        self.assertEqual([(a['case']['id'],a['expected']['error']) for a in actions[:8]],list(f.SYNTHETIC))
        cycle=actions[8:18]
        self.assertEqual([a['case']['id'] for a in cycle],list(f.BOUNDARY_LOADS)+[s[0] for s in f.STAGES])
        self.assertEqual([a['case']['channels'] for a in cycle[:2]],[3,4])
        self.assertEqual(actions[8:-1],cycle*100)

    def test_complete_boundary_records_and_terminal_are_required(self):
        actions=f.boundary_actions(self.cases,self.invalid,self.ref);text=encode(actions)+json.dumps(f.TERMINAL)+'\n'
        self.assertEqual(f.parse_boundary(text,actions),f.TERMINAL)
        for wrong in ('',encode(actions),text+json.dumps(f.TERMINAL),text.replace('"iterations": 100','"iterations": 99'),text.replace('"records": 1009','"records": true'),text.replace('"synthetic_checks": 8','"synthetic_checks": 8.0'),encode(actions[1:])+json.dumps(f.TERMINAL),encode(actions+[actions[-1]])+json.dumps(f.TERMINAL)):
            with self.subTest(prefix=wrong[:50]),self.assertRaises(ValueError):f.parse_boundary(wrong,actions)
        changed=copy.deepcopy(actions);changed[500]['expected']['error']=99
        with self.assertRaises(ValueError):f.parse_boundary(encode(changed)+json.dumps(f.TERMINAL),actions)
        with self.assertRaises(ValueError):f.parse_boundary(text,actions[:-1])

    def test_format_framing_and_byte_types_cannot_normalize_away_mismatch(self):
        c=next(c for c in self.cases if c['id']=='c3-single');a=dict(case=c,role='raw',expected=self.ref[c['id']][0]);text=encode([a])
        self.assertEqual(m.parse_rows(text,[a]),[a['expected']])
        for key,value in [('width',True),('height',1.0),('format',7),('mipmaps',2),('id','wrong'),('role','normalized'),('extra',1)]:
            bad=copy.deepcopy(a);bad['expected'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):m.parse_rows(encode([bad]),[a])
        for bad in ('',text+'"end"\n',text+text,text.replace('"end"','[]'),text.replace('[17, 17, 17]','[true, 17, 17]'),text.replace('[17, 17, 17]','[256, 17, 17]'),text.replace('[17, 17, 17]','[-1, 17, 17]'),text.replace('[17, 17, 17]','[17.0, 17, 17]'),text.replace('"width": 1','"width": 1, "width": 1')):
            with self.assertRaises(ValueError):m.parse_rows(bad,[a])

    def test_native_reference_coverage_metadata_and_bytes_are_required(self):
        cases=[next(c for c in self.cases if c['id']==f'c{n}-single') for n in (3,4)]
        native=reference(cases);f.candidate_actions(cases,[],native)
        variants=[{},dict(native,extra=native[cases[0]['id']]),dict(native)]
        del variants[-1][cases[-1]['id']]
        for values in variants:
            with self.assertRaises(ValueError):f.candidate_actions(cases,[],values)
        for role in (0,1):
            for key,value in [('width',True),('height',1.0),('mipmaps',2),('format',True),
                              ('role','owner'),('id','other'),('extra',0),('bytes',[]),
                              ('bytes',[17.0]),('bytes',[True]),('bytes',[256]),('bytes',b'\x11')]:
                changed=copy.deepcopy(native);changed[cases[0]['id']][role][key]=value
                with self.subTest(role=role,key=key,value=value),self.assertRaises(ValueError):
                    f.candidate_actions(cases,[],changed)
        for pair in ((),(native[cases[0]['id']][0],),dict(native[cases[0]['id']][0]),[None,None]):
            changed=dict(native);changed[cases[0]['id']]=pair
            with self.assertRaises(ValueError):f.candidate_actions(cases,[],changed)

    def test_byte_differences_survive_equal_rgba_normalization(self):
        cases=[next(c for c in self.cases if c['id']=='c4-single')]
        native=reference(cases);native[cases[0]['id']][0]['bytes']=[23,71,93,127]
        native[cases[0]['id']][1]['bytes']=[91,37,11,5]
        actions=f.candidate_actions(cases,[],native)
        self.assertEqual(actions[0]['expected']['bytes'],[23,71,93,127])
        self.assertEqual(actions[1]['expected']['bytes'],[23,71,93,127])
        self.assertEqual(actions[2]['expected']['bytes'],[91,37,11,5])
        # Unit rows intentionally need not be related by a Python pixel decoder.
        actual=m.parse_rows(encode(actions),actions)
        actual[0]['bytes']=[0,71,93,127]
        delta=m.differences([a['expected'] for a in actions],actual)
        self.assertEqual(len(delta),1);self.assertEqual(delta[0]['byte_differences'][0]['index'],0)

    def test_native_and_bend_qualify_dotfile_and_parent_directory_tokens(self):
        native=f.qualification_program();bend=f.boundary_program(self.cases,self.invalid)
        for token in ('GetFileExtension(".bmp")!=NULL',
                      'strcmp(GetFileExtension("dir/.bmp"),".bmp")',
                      'strcmp(GetFileExtension("dir.bmp/leaf"),".bmp/leaf")'):
            self.assertIn(token,native)
        for token in ('J.Image.file.token(".bmp"), ""',
                      'J.Image.file.token("dir/.bmp"), ".bmp"',
                      'J.Image.file.token("dir.bmp/leaf"), ".bmp/leaf"'):
            self.assertIn(token,bend)
        self.assertIn('LoadImageFromMemory(',native)
        for format in (4,7):self.assertIn(f'image.format!={format}',native)

    def test_source_contract_preserves_function_text_and_hashes(self):
        source=(f.ROOT/'jonlib.bend').read_text();contract=f.boundary_source_contract()
        self.assertEqual(contract['source_sha256'],m.digest(f.ROOT/'jonlib.bend'))
        self.assertIn('not an IO proof',contract['kind'])
        self.assertIn('cannot report OS close failure',contract['close_guarantee'])
        self.assertEqual(len(contract['definitions']),11)
        for name,definition in contract['definitions'].items():
            self.assertTrue(definition['source'].startswith('def '+name+'('))
            self.assertIn(definition['source'],source)
            self.assertEqual(definition['sha256'],hashlib.sha256(definition['source'].encode()).hexdigest())

    def test_source_contract_rejects_pre_read_and_close_order_drift(self):
        source=(f.ROOT/'jonlib.bend').read_text()
        read='    Unit <- File.close(file)\n    IO.pure(Result<&1, &1, Image.LoadError, +List<U32>>, Image.file.payload(size, status))'
        variants=[source.replace('Image.file.bounded((size <= limit : U32), file, size)',
                                 'Image.file.bounded((size < limit : U32), file, size)'),
                  source.replace('File.read_bytes(file, size), Image.file.read(size)',
                                 'File.read_bytes(file, size), File.read_bytes(file, size), Image.file.read(size)'),
                  source.replace(read,read.split('\n')[1]+'\n'+read.split('\n')[0]),
                  source.replace('Image.file.decoded(Image.Formatted, Image.Formatted.decode_bmp(bytes))',
                                 'Image.file.decoded(Image.Formatted, Image.Formatted.decode_tga(bytes))')]
        for changed in variants:
            self.assertNotEqual(changed,source)
            with patch.object(Path,'read_text',return_value=changed),self.assertRaises(ValueError):f.boundary_source_contract()


class BmpFilePartitionTests(unittest.TestCase):
    def test_fixed32_order_source_bytes_actions_and_coverage_are_sealed(self):
        actions=unit_actions(65);plan=f.plan_partitions(actions)
        self.assertEqual(plan,f.plan_partitions(copy.deepcopy(actions)))
        self.assertEqual([(b['start'],b['count']) for b in plan],[(0,32),(32,32),(64,1)])
        for entry in plan:
            selected=actions[entry['start']:entry['start']+entry['count']]
            source=f.candidate_program(selected).encode()
            self.assertEqual(entry['source_bytes'],len(source))
            self.assertEqual(entry['source_sha256'],hashlib.sha256(source).hexdigest())
            self.assertEqual(entry['actions_sha256'],m.action_digest(selected))
            self.assertEqual(entry['compared_bytes'],3*len(selected))
        lanes=lanes_for(plan);f.finish_lanes(lanes,actions,plan)
        self.assertTrue(all(row['passed'] for row in lanes.values()))

    def test_empty_actions_duplicates_malformed_and_byte_types_reject(self):
        for actions in ([],(),[None],unit_actions()*2):
            with self.assertRaises(ValueError):f.plan_partitions(actions)
        for key,value in [('bytes',[True]),('bytes',[17.0]),('bytes',[256]),('role','owner'),('id','wrong')]:
            actions=unit_actions();actions[0]['expected'][key]=value
            with self.assertRaises(ValueError):f.plan_partitions(actions)
        for source in ('','x'*(f.SOURCE_BYTE_LIMIT+1)):
            with patch.object(f,'candidate_program',return_value=source),self.assertRaises(ValueError):f.plan_partitions(unit_actions())
        with patch.object(f,'candidate_program',return_value='é'*(f.SOURCE_BYTE_LIMIT//2)):
            self.assertEqual(f.plan_partitions(unit_actions())[0]['source_bytes'],f.SOURCE_BYTE_LIMIT)

    def test_plan_missing_extra_reordered_gap_overlap_schema_and_types_reject(self):
        actions=unit_actions(33);plan=f.plan_partitions(actions)
        variants=[None,(),[],plan[:-1],plan+plan,plan[::-1]]
        for key,value in [('start',True),('start',1),('count',True),('count',0),('count',33),
                          ('source_bytes',True),('source_bytes',0),('source_bytes',f.SOURCE_BYTE_LIMIT+1),
                          ('source_sha256','0'*64),('actions_sha256','0'*64),
                          ('compared_bytes',True),('compared_bytes',0),('extra',1)]:
            bad=copy.deepcopy(plan);bad[0][key]=value;variants.append(bad)
        for start in (31,33):
            bad=copy.deepcopy(plan);bad[1]['start']=start;variants.append(bad)
        for key in plan[0]:
            bad=copy.deepcopy(plan);del bad[0][key];variants.append(bad)
        for bad in variants:
            with self.subTest(plan=bad),self.assertRaises(ValueError):f.finish_lanes(lanes_for(plan),actions,bad)

    def test_same_program_cannot_hide_changed_native_bytes_or_input_identity(self):
        actions=unit_actions(3);plan=f.plan_partitions(actions)
        variants=[actions[::-1],actions[:2]]
        for target,key,value in [('case','bytes',[0]),('case','path','different.bmp'),
                                 ('case','id','different'),('expected','bytes',[18])]:
            changed=copy.deepcopy(actions);changed[0][target][key]=value;variants.append(changed)
        changed=copy.deepcopy(actions);changed[0]['normalized']=[0,0,0,0];variants.append(changed)
        for changed in variants:
            with self.assertRaises(ValueError):f.finish_lanes(lanes_for(plan),changed,plan)
        changed=copy.deepcopy(actions);changed[0]['expected']['bytes']=[18,17,17]
        self.assertEqual(f.candidate_program(actions),f.candidate_program(changed))
        self.assertNotEqual(m.action_digest(actions),m.action_digest(changed))

    def test_every_lane_batch_must_match_exact_plan_and_full_byte_count(self):
        actions=unit_actions(33);plan=f.plan_partitions(actions)
        for key,value in [('start',False),('count',32.0),('source_bytes',1),
                          ('source_sha256','0'*64),('actions_sha256','0'*64),
                          ('compared_bytes',0),('bytes',0),('bytes',True),('passed',1),('extra',0)]:
            lanes=lanes_for(plan);lanes['javascript']['batches'][0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):f.finish_lanes(lanes,actions,plan)
            self.assertTrue(all(row['passed'] is False for row in lanes.values()))
        for batch in ([],plan,lanes_for(plan)['cpu-1']['batches'][::-1],
                      lanes_for(plan)['cpu-1']['batches']*2):
            lanes=lanes_for(plan);lanes['cpu-2']['batches']=batch
            with self.assertRaises(ValueError):f.finish_lanes(lanes,actions,plan)

    def test_complete_real_corpus_plan_preserves_all_file_roles_and_bytes(self):
        cases=[dict(c,path=c['filename']) for c in f.fixtures()]
        invalid=[dict(c,path=c['filename']) for c in f.controls()]
        actions=f.candidate_actions(cases,invalid,reference(cases));plan=f.plan_partitions(actions)
        self.assertEqual((len(actions),len(plan)),(1805,57))
        self.assertEqual(sum(b['compared_bytes'] for b in plan),sum(2*c['width']*c['height']*(c['channels']+4)+(12*c['width']*c['height'] if c['regress'] and c['route']=='LoadImage' else 0) for c in cases))
        self.assertEqual(sum(b['count'] for b in plan),1805)
        self.assertTrue(all(0<b['source_bytes']<=f.SOURCE_BYTE_LIMIT for b in plan))
        self.assertEqual([a for b in plan for a in actions[b['start']:b['start']+b['count']]],actions)
        lanes=lanes_for(plan);f.finish_lanes(lanes,actions,plan)
        self.assertTrue(all(row['passed'] for row in lanes.values()))


class BmpFileRunGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=f.ROOT);self.work=Path(self.temp.name);m.SEALED.clear()
    def tearDown(self):m.SEALED.clear();self.temp.cleanup()

    def test_files_are_real_exact_cap_and_sparse_are_pre_read_controls(self):
        cases=f.fixtures();invalid=f.controls();stress,stage=f.prepare_inputs(self.work,cases,invalid)
        self.assertEqual(stage['stage'],'read');self.assertEqual(stage['code'],f.errno.EISDIR)
        self.assertEqual(len(stress['bytes']),1048576);self.assertEqual((f.ROOT/stress['path']).stat().st_size,1048576)
        original=next(c['bytes'] for c in cases if c['id']=='c3-single');self.assertEqual(stress['bytes'][:len(original)],original)
        for c in cases:self.assertEqual((f.ROOT/c['path']).read_bytes(),bytes(c['bytes']))
        sparse=[c for c in invalid if c.get('special') in ('sparse','large','overflow')]
        self.assertEqual([c['size'] for c in sparse],[1048577,1048577,268435456,4294967296])
        self.assertLess(sum((f.ROOT/c['path']).stat().st_blocks*512 for c in sparse),100000)
        for c in invalid:
            if c.get('special')=='missing':self.assertFalse((f.ROOT/c['path']).exists())
        f.verify_inputs(cases,invalid,stress)
        c=sparse[0]
        with (f.ROOT/c['path']).open('r+b') as handle:handle.truncate(c['size']-1)
        with self.assertRaises(ValueError):f.verify_inputs(cases,invalid,stress)

    def test_input_missing_directory_and_sparse_prefix_drift_fail(self):
        for mode in ('missing','directory','prefix'):
            directory=self.work/mode;directory.mkdir();cases=f.fixtures();invalid=f.controls();stress,_=f.prepare_inputs(directory,cases,invalid)
            if mode=='missing':(f.ROOT/next(c['path'] for c in invalid if c['id']=='missing')).write_bytes(b'x')
            elif mode=='directory':(f.ROOT/next(c['path'] for c in invalid if c['id']=='directory')/'entry').write_bytes(b'y')
            else:
                with (f.ROOT/next(c['path'] for c in invalid if c['id']=='cap-plus-one')).open('r+b') as handle:handle.write(b'bad')
            with self.subTest(mode=mode),self.assertRaises(ValueError):f.verify_inputs(cases,invalid,stress)

    def test_stale_reports_reset_before_invalid_cli_or_timeout(self):
        for flags in (['--bad'],['--timeout','0'],['--reference-env','inherited']):
            dest=self.work/str(len(list(self.work.iterdir())));dest.mkdir();(dest/'results.json').write_text('{"passed":true}')
            with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):f.main(['--build-dir',str(dest),*flags])
            self.assertFalse(json.loads((dest/'results.json').read_text())['passed'])

    def test_duplicate_destinations_reset_and_abbreviations_do_not_select_paths(self):
        a=self.work/'a';b=self.work/'b'
        for dest in (a,b):dest.mkdir();(dest/'results.json').write_text('{"passed":true}')
        self.assertEqual(f.admit_directories(['--build-dir',str(a),'--build-dir='+str(b)]),b.resolve())
        for dest in (a,b):self.assertFalse(json.loads((dest/'results.json').read_text())['passed'])
        self.assertEqual(f.report_directories(['--build-di',str(a)]),[f.BUILD/'bmp-file-probe'])
        self.assertEqual(f.report_directories(['--','--build-dir',str(a)]),[f.BUILD/'bmp-file-probe'])

    def test_resource_receipt_requires_positive_integer_bounded_rss(self):
        for index,value in enumerate((0,-1,True,1.0,f.MAX_SPARSE_RSS+1,None)):
            def record(command,*args,**kwargs):Path(command[2]).write_text(json.dumps({'maximum_rss_bytes':value}));return 'record\n'
            with patch.object(f,'record_resource',side_effect=record),self.subTest(value=value),self.assertRaises(ValueError):f.resource_run(['candidate'],self.work,'bad'+str(index),f.MAX_SPARSE_RSS,{},None,30)
        with patch.object(f,'record_resource',return_value='record\n'),self.assertRaises(ValueError):f.resource_run(['candidate'],self.work,'missing',f.MAX_SPARSE_RSS,{},None,30)
        with self.assertRaises(ValueError):f.resource_run(['candidate'],self.work,'unknown',1,{},None,30)

    def test_real_outer_timeout_kills_candidate_descendants(self):
        started=self.work/'started';sentinel=self.work/'escaped'
        child='import signal,time;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);Path('+repr(str(started))+').write_text("started");time.sleep(0.8);Path('+repr(str(sentinel))+').write_text("escaped")'
        parent='import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",'+repr(child)+']);print("launched",flush=True);time.sleep(10)'
        with self.assertRaisesRegex(ValueError,'timed out'):
            f.record_resource([sys.executable,'-c',parent],self.work,'real-timeout',timeout=0.3,environment=os.environ.copy(),receipt=None)
        self.assertTrue(started.exists(), 'negative test did not reach the descendant')
        time.sleep(0.8);self.assertFalse(sentinel.exists(), 'candidate descendant survived timeout')
        row=json.loads((self.work/'real-timeout.command.json').read_text())
        self.assertTrue(row['timed_out']);self.assertTrue(row['process_group_owned']);self.assertNotEqual(row['exit_code'],0)
        self.assertIn('launched',(self.work/'real-timeout.stdout').read_text())

    def test_resource_lifecycle_failure_and_empty_output_keep_receipts(self):
        for label,code in [('failed','import sys;print("partial");sys.exit(7)'),('empty','pass')]:
            with self.assertRaises(ValueError):f.record_resource([sys.executable,'-c',code],self.work,label,timeout=5,environment=os.environ.copy(),receipt=None)
            self.assertTrue((self.work/(label+'.command.json')).exists())

    def test_resource_measurement_is_separate_and_fd_limited(self):
        def record(command,*args,**kwargs):
            self.assertIn('resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))',Path(command[1]).read_text())
            self.assertEqual(command[-1],'candidate');self.assertEqual(kwargs['environment'],{'candidate':'env'})
            Path(command[2]).write_text('{"maximum_rss_bytes":1048576}');return 'ok\n'
        with patch.object(f,'record_resource',side_effect=record):text,usage=f.resource_run(['candidate'],self.work,'good',f.MAX_SPARSE_RSS,{'candidate':'env'},None,30)
        self.assertEqual(text,'ok\n');self.assertEqual(usage['descriptor_limit'],64);self.assertEqual(usage['maximum_rss_bytes'],1048576)
        m.verify_sealed()

    def test_all_three_lanes_require_complete_contiguous_batches_and_resources(self):
        actions=unit_actions();partitions=f.plan_partitions(actions);lanes=lanes_for(partitions)
        good=copy.deepcopy(lanes);f.finish_lanes(good,actions,partitions);self.assertTrue(all(v['passed'] for v in good.values()))
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
            with self.assertRaises(ValueError):f.finish_lanes(bad,actions,partitions)
            self.assertFalse(any(row.get('passed') for row in bad.values()))
        with self.assertRaises(ValueError):f.finish_lanes(lanes,[],[])

    def arguments(self,directory):
        return ['--build-dir',str(directory),'--bend-source',str(self.work/'bend'),'--raylib-source',str(self.work/'raylib')]

    def test_zero_and_negative_timeouts_reach_positive_timeout_guard(self):
        for value in ('0','-1'):
            directory=self.work/('timeout'+value);directory.mkdir();(directory/'results.json').write_text('{"passed":true}')
            with patch.object(f,'checkout') as checkout,patch('sys.stderr',new_callable=io.StringIO) as stderr,self.assertRaises(SystemExit):
                f.main(self.arguments(directory)+['--timeout',value])
            self.assertIn('--timeout must be positive',stderr.getvalue());checkout.assert_not_called()
            self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_reference_policy_cannot_switch_or_abbreviate(self):
        for flags in (['--reference-env','inherited'],['--reference-e','clean-loader'],['--time','1']):
            directory=self.work/str(len(list(self.work.iterdir())));directory.mkdir()
            with patch.object(f,'checkout') as checkout,patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):f.main(self.arguments(directory)+flags)
            checkout.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_default_invalid_cli_resets_only_default_report(self):
        with patch.object(f,'BUILD',self.work):
            default=self.work/'bmp-file-probe';default.mkdir();(default/'results.json').write_text('{"passed":true}')
            with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):f.main(['--unknown'])
            self.assertFalse(json.loads((default/'results.json').read_text())['passed'])

    def test_duplicate_cli_destinations_reset_even_when_parsing_fails(self):
        a=self.work/'a';b=self.work/'b'
        for directory in (a,b):directory.mkdir();(directory/'results.json').write_text('{"passed":true}')
        with patch('sys.stderr',new_callable=io.StringIO),self.assertRaises(SystemExit):f.main(self.arguments(a)+['--build-dir='+str(b),'--unknown'])
        for directory in (a,b):self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_checkout_setup_failure_cannot_inherit_success(self):
        directory=self.work/'checkout';directory.mkdir();(directory/'results.json').write_text('{"passed":true}')
        with patch.object(f,'checkout',side_effect=ValueError('wrong revision')),patch.object(f,'native_archive') as archive,self.assertRaisesRegex(ValueError,'wrong revision'):f.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_native_input_safety_failure_precedes_archive_or_decoder(self):
        directory=self.work/'bad-fixture';bad=f.fixtures();bad[0]['bytes']=[0]
        with patch.object(f,'checkout'),patch.object(f,'fixtures',return_value=bad),patch.object(f,'native_archive') as archive,self.assertRaises(ValueError):f.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_missing_tool_setup_failure_cannot_use_stale_archive(self):
        directory=self.work/'missing-tool'
        with patch.object(f,'checkout'),patch.object(f.shutil,'which',return_value=None),patch.object(f,'native_archive') as archive,self.assertRaisesRegex(ValueError,'Required tool missing'):f.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_native_build_failure_preserves_failed_scoped_report(self):
        directory=self.work/'native-failure'
        with patch.object(f,'checkout'),patch.object(f.shutil,'which',return_value=sys.executable),patch.object(m,'validate_reference_sources',return_value={}),patch.object(f,'native_archive',side_effect=ValueError('BMP compile definition missing')) as archive,self.assertRaisesRegex(ValueError,'BMP compile definition missing'):f.main(self.arguments(directory))
        archive.assert_called_once();report=json.loads((directory/'results.json').read_text())
        self.assertFalse(report['passed']);self.assertEqual(report['cases'],len(f.fixtures()));self.assertEqual(report['native_rejections'],0)
        self.assertTrue(all(v['passed'] is False for v in report['lanes'].values()))

    def test_bad_native_qualification_cannot_reach_candidate_compile(self):
        directory=self.work/'qualification';commands=[]
        def record(command,*args,**kwargs):
            commands.append(list(map(str,command)))
            if command==['bun','--version']:return '1.3.12\n'
            if command==['clang','--version']:return 'test compiler\n'
            return '{}\n'
        with patch.object(f,'checkout'),patch.object(f.shutil,'which',return_value=sys.executable),patch.object(m,'validate_reference_sources',return_value={}),patch.object(f,'native_archive',return_value=(self.work/'test.a',{})),patch.object(f,'record_run',side_effect=record),self.assertRaises(ValueError):f.main(self.arguments(directory))
        self.assertFalse(any('candidate-' in ' '.join(c) for c in commands));self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_ordinary_file_and_dependency_drift_cannot_pass_input_verification(self):
        cases=f.fixtures();invalid=f.controls();stress,_=f.prepare_inputs(self.work,cases,invalid)
        file=f.ROOT/cases[0]['path'];original=file.read_bytes();m.seal(file);file.write_bytes(original+b'x')
        with self.assertRaisesRegex(ValueError,'identity drift'):f.verify_inputs(cases,invalid,stress)
        file.write_bytes(original)
        m.SEALED.clear();dependency=self.work/'dependency.py';dependency.write_text('original');m.seal(dependency);dependency.unlink()
        with self.assertRaisesRegex(ValueError,'artifact drift'):f.verify_inputs(cases,invalid,stress)

    def test_unsealed_accepted_file_and_exact_cap_identity_are_checked(self):
        cases=f.fixtures();invalid=f.controls();stress,_=f.prepare_inputs(self.work,cases,invalid)
        self.assertEqual(m.SEALED,{})
        for case in (cases[0],stress):
            path=f.ROOT/case['path'];original=path.read_bytes()
            path.write_bytes(original[:-1]+bytes([original[-1]^1]))
            with self.assertRaisesRegex(ValueError,'identity drift'):f.verify_inputs(cases,invalid,stress)
            path.write_bytes(original)
        f.verify_inputs(cases,invalid,stress)

    def test_special_file_recipe_type_size_and_prefix_are_required(self):
        cases=f.fixtures();invalid=f.controls();stress,_=f.prepare_inputs(self.work,cases,invalid)
        sparse=next(c for c in invalid if c.get('special')=='sparse')
        for change in (dict(size=True),dict(size=float(sparse['size'])),dict(size=sparse['size']-1),
                       dict(prefix=[]),dict(prefix=[True]+sparse['prefix'][1:]),
                       dict(sparse_recipe='unverified')):
            with self.subTest(change=change),self.assertRaises(ValueError):
                f.validate_controls([dict(sparse,**change)])

    def test_invalid_control_schema_rejects_before_native_build(self):
        directory=self.work/'bad-control';invalid=f.controls();invalid[0]['bytes']=[256]
        with patch.object(f,'checkout'),patch.object(f,'controls',return_value=invalid),\
             patch.object(f,'native_archive') as archive,self.assertRaises(ValueError):
            f.main(self.arguments(directory))
        archive.assert_not_called();self.assertFalse(json.loads((directory/'results.json').read_text())['passed'])

    def test_native_alias_definitions_are_explicit_and_checked_before_build(self):
        args=type('Args',(),dict(raylib_source=self.work/'source'))()
        for alias in f.ALIAS_MACROS:
            work=self.work/alias;work.mkdir();commands=[]
            def record(command,work,label,**kwargs):
                commands.append(list(map(str,command)))
                self.assertEqual(label,'configure')
                directory=work/'raylib-build';(directory/'raylib/CMakeFiles/raylib.dir').mkdir(parents=True)
                (directory/'CMakeCache.txt').write_text(native_cache())
                (directory/'raylib/CMakeFiles/raylib.dir/flags.make').write_text(native_flags().replace('-DSUPPORT_FILEFORMAT_'+alias,''))
            with self.subTest(alias=alias),self.assertRaises(ValueError):f.native_archive(args,work,record)
            self.assertEqual(len(commands),1)
            for name in f.ALIAS_MACROS:self.assertIn('-DSUPPORT_FILEFORMAT_'+name+'=ON',commands[0])
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
                    self.assertIn(str(path.resolve()),m.SEALED)
                (directory/'raylib/libraylib.a').write_bytes(b'unit-test archive')
            return 'unit-test compiler version 1\n'
        archive,receipt=f.native_archive(args,self.work,record)
        self.assertEqual(labels,['configure','archive-compiler-version','native-build'])
        self.assertEqual(receipt['mode'],'fresh-isolated-build')
        self.assertEqual(receipt['artifacts'][str(archive)],m.digest(archive))
        self.assertEqual(receipt['file_aliases']['recognized_tokens'],sorted(f.RECOGNIZED))
        m.verify_sealed()
        with self.assertRaisesRegex(ValueError,'fresh'):
            f.native_archive(args,self.work,lambda *a,**kw:self.fail('stale archive reused'))
        archive.write_bytes(b'drift')
        with self.assertRaisesRegex(ValueError,'artifact drift'):m.verify_sealed()

    def test_tracked_source_manifest_includes_file_gate_tests_and_upstream_dependencies(self):
        bend=self.work/'bend/bend2';bend.mkdir(parents=True)
        raylib=self.work/'raylib';raylib.mkdir()
        compiler=bend/'compiler.ts';compiler.write_text('unit compiler')
        native=raylib/'rtextures.c';native.write_text('unit native source')
        args=type('Args',(),dict(bend_source=bend.parent,raylib_source=raylib))()
        before=f.tracked_sources(args)
        for path in (f.ROOT/'tools/bmp_file_probe.py',f.ROOT/'tests/test_bmp_file_harness.py',
                     f.ROOT/'tools/bmp_format_probe.py',f.ROOT/'tests/test_bmp_format_harness.py',
                     f.ROOT/'tools/raw_file_probe.py',f.ROOT/'tools/r32_raw_file_probe.py',
                     f.ROOT/'toolchain.json',compiler,native):
            self.assertEqual(before['dependencies'][str(path)],m.digest(path))
        self.assertIn('jonlib.bend',before['library'])
        compiler.write_text('changed compiler');self.assertNotEqual(f.tracked_sources(args),before)

    def test_real_resource_child_observes_fd_limit_and_sealed_usage(self):
        output,usage=f.resource_run([sys.executable,'-c','import resource;print(resource.getrlimit(resource.RLIMIT_NOFILE))'],
                                    self.work,'actual-resource',f.MAX_SPARSE_RSS,os.environ.copy(),None,5)
        self.assertEqual(output.strip(),'(64, 64)')
        self.assertEqual(usage['descriptor_limit'],64)
        self.assertGreater(usage['maximum_rss_bytes'],0)
        self.assertLessEqual(usage['maximum_rss_bytes'],f.MAX_SPARSE_RSS)
        for name in ('actual-resource.resource-runner.py','actual-resource.resource.json',
                     'actual-resource.command.json','actual-resource.stdout','actual-resource.stderr'):
            self.assertIn(str((self.work/name).resolve()),m.SEALED)
        m.verify_sealed()

    def test_resource_completion_rejects_forged_types_missing_and_excess_receipts(self):
        actions=unit_actions();partitions=f.plan_partitions(actions);lanes=lanes_for(partitions)
        for key,value in [('descriptor_limit',64.0),('maximum_rss_bytes',True),('maximum_rss_bytes',0),('maximum_rss_bytes',f.MAX_SPARSE_RSS+1),('maximum_rss_acceptance_bytes',f.MAX_STRESS_RSS),('maximum_rss_acceptance_bytes',float(f.MAX_SPARSE_RSS))]:
            bad=copy.deepcopy(lanes);bad['cpu-1']['sparse'][key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):f.finish_lanes(bad,actions,partitions)
        for key in ('maximum_rss_bytes','maximum_rss_acceptance_bytes'):
            bad=copy.deepcopy(lanes);del bad['cpu-1']['sparse'][key]
            with self.assertRaises(ValueError):f.finish_lanes(bad,actions,partitions)

    def test_resource_stale_missing_extra_and_duplicate_receipts_fail(self):
        for index,content in enumerate(('{"maximum_rss_bytes":1,"extra":true}','{"maximum_rss_bytes":1,"maximum_rss_bytes":1}','{}')):
            def record(command,*args,**kwargs):Path(command[2]).write_text(content);return 'record\n'
            with patch.object(f,'record_resource',side_effect=record),self.assertRaises(ValueError):f.resource_run(['candidate'],self.work,'schema'+str(index),f.MAX_SPARSE_RSS,{},None,30)
        usage=self.work/'stale.resource.json';usage.write_text('{"maximum_rss_bytes":1}')
        with patch.object(f,'record_resource',return_value='record\n'),self.assertRaisesRegex(ValueError,'Missing resource receipt'):f.resource_run(['candidate'],self.work,'stale',f.MAX_SPARSE_RSS,{},None,30)

    def test_compiler_timeout_kills_grandchild_and_removes_stale_output(self):
        output=self.work/'compiled';output.write_text('stale');started=self.work/'compiler-started'
        compiler='import signal,time;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);Path('+repr(str(started))+').write_text("ready");time.sleep(0.8);Path('+repr(str(output))+').write_text("escaped compiler")'
        parent='import subprocess,sys;print("compiler launched",flush=True);subprocess.run([sys.executable,"-c",'+repr(compiler)+'])'
        with self.assertRaisesRegex(ValueError,'timed out'):f.record_run([sys.executable,'-c',parent,'-o',output],self.work,'compiler-timeout',timeout=0.3)
        self.assertTrue(started.exists());time.sleep(0.8);self.assertFalse(output.exists())
        row=json.loads((self.work/'compiler-timeout.command.json').read_text())
        self.assertTrue(row['timed_out']);self.assertNotIn('descriptor_limit',row);self.assertNotEqual(row['exit_code'],0)

    def test_successful_compiler_must_create_nonempty_fresh_outputs(self):
        output=self.work/'output'
        for index,code in enumerate(('pass','from pathlib import Path;Path('+repr(str(output))+').write_bytes(b"")')):
            m.SEALED.clear()
            output.write_bytes(b'stale')
            with self.assertRaisesRegex(ValueError,'Compiler output missing'):f.record_run([sys.executable,'-c',code,'-o',output],self.work,'missing-output'+str(index))
        m.SEALED.clear()
        output.unlink(missing_ok=True)
        code='from pathlib import Path;Path('+repr(str(output))+').write_text("fresh")'
        f.record_run([sys.executable,'-c',code,'-o',output],self.work,'created')
        self.assertEqual(output.read_text(),'fresh');m.verify_sealed();output.write_text('drift')
        with self.assertRaisesRegex(ValueError,'artifact drift'):f.record_run([sys.executable,'-c','pass'],self.work,'after-drift')

    def test_all_command_receipts_preserve_clean_environment_and_actual_limits(self):
        receipt={'policy':'clean-loader'}
        text=f.record_run([sys.executable,'-c','import os;print(os.environ["ONLY"])'],self.work,'environment',environment={'ONLY':'expected'},receipt=receipt,require_output=True)
        self.assertEqual(text,'expected\n');row=json.loads((self.work/'environment.command.json').read_text())
        self.assertEqual(row['reference_environment'],receipt);self.assertNotIn('descriptor_limit',row);self.assertTrue(row['process_group_owned'])
        self.assertEqual(row['exit_code'],0);self.assertFalse(row.get('timed_out',False));m.verify_sealed()

    def test_child_start_failure_retains_fail_closed_receipt(self):
        with self.assertRaisesRegex(ValueError,'could not start'):f.record_run([self.work/'missing-command'],self.work,'start-failure')
        row=json.loads((self.work/'start-failure.command.json').read_text())
        self.assertIsNone(row['exit_code']);self.assertEqual(row['startup_error'],'FileNotFoundError');self.assertFalse(row.get('timed_out',False))

    def test_dependency_archive_loader_and_provenance_sealing_are_required(self):
        source=(f.ROOT/'tools/bmp_file_probe.py').read_text()
        for text in ('reference_env.require_clear()','reference_env.child()','reference_env.receipt()','reference_env.assert_receipt','native_archive(args,work,native_record)','memory.native_archive(args,work,explicit_record)','memory.qualification(output)','tool_realpaths','tracked_sources(args)!=report','memory.verify_sealed()','evidence_origin=','NEW source-scoped file run','tests/test_bmp_file_harness.py','verify_inputs(cases,invalid,stress)','boundary_source_contract()'):self.assertIn(text,source)
        self.assertLess(source.index("('qualification',qualification_program())"),source.index('candidate_actions(cases,invalid,file_reference,synthetic)'))
        self.assertIn('SUPPORT_FILEFORMAT_BMP=ON',(f.ROOT/'tools/bmp_format_probe.py').read_text())
        self.assertNotIn('os.environ[',source)


class BmpFileStrictEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=f.ROOT);self.work=Path(self.temp.name);m.SEALED.clear()
    def tearDown(self):m.SEALED.clear();self.temp.cleanup()

    def test_dynamic_qualification_retains_all_twelve_alpha_discriminators(self):
        native=f.qualification_program()
        markers=('rgb24','rgb32-repaired','rgb32-alpha','info16-rgb565','rgb555-bit-replication',
                 'info32-ignored-alpha','info56-ignored-alpha','v4-explicit-zero-alpha',
                 'v5-rgb32-repaired','v4-rgb16-alpha','v5-rgb16-above-word-alpha','palette-reserved-ignored')
        for marker in markers:self.assertIn('/* '+marker+' */',native)
        self.assertEqual(native.count('LoadImageFromMemory(".bmp",data,sizeof(data))'),12)
        with patch.object(m,'qualification_program',return_value='SetTraceLogLevel(LOG_NONE); /* current */') as build:
            text=f.qualification_program()
        build.assert_called_once_with();self.assertIn('/* current */',text)
        self.assertIn('GetFileExtension(".bmp")',text)
        expected=dict(little_endian=True,bmp_enabled=True,effective_alpha_routing=True,formats=[4,7])
        self.assertEqual(m.qualification(json.dumps(expected)),expected)
        for key,value in [('little_endian',1),('bmp_enabled',False),('effective_alpha_routing',1),
                          ('formats',[4.0,7]),('formats',[7,4]),('extra',True)]:
            bad=dict(expected,**{key:value})
            with self.assertRaises(ValueError):m.qualification(json.dumps(bad))

    def test_exact_host_messages_are_checked_for_each_acquired_file_failure(self):
        cases=[dict(c,path=c['filename']) for c in f.fixtures()]
        invalid=[dict(c,path=c['filename']) for c in f.controls()]
        text=f.candidate_program(f.candidate_actions(cases,invalid,reference(cases)))
        for ident,code in [('missing',f.errno.ENOENT),('missing-parent',f.errno.ENOENT),
                           ('directory',f.errno.EISDIR),('host-size-overflow',f.errno.EOVERFLOW)]:
            self.assertIn(f'file.failed({json.dumps(ident)}, {code}, {json.dumps(os.strerror(code))})',text)
        definition=text.split('def file.failed(',1)[1].split('\ndef ',1)[0]
        self.assertIn('exact.error(',definition)
        self.assertIn('String.eq(message, text)',text)

    def test_candidate_identities_and_synthetic_domain_cannot_overlap_or_coerce(self):
        case=dict(next(c for c in f.fixtures() if c['id']=='c3-single'),path='safe.bmp')
        control=dict(next(c for c in f.controls() if 'bytes' in c),path='bad.bmp')
        synthetic=f.synthetic_controls()[0];native=reference([case])
        for controls,synthetics in [([dict(control,id=case['id'])],[]),
                                    ([control],[dict(synthetic,id=control['id'])]),
                                    ([],[dict(synthetic,id=case['id'])]),
                                    ([],[synthetic,synthetic]),([], [dict(synthetic,bytes=[256.0])]),
                                    ([],[dict(synthetic,bytes=[True])]),([],[dict(synthetic,bytes=[])]),
                                    ([],[dict(synthetic,error=True)])]:
            with self.subTest(controls=controls,synthetics=synthetics),self.assertRaises(ValueError):
                f.candidate_actions([case],controls,native,synthetics)
        actions=f.candidate_actions([case],[],native,[synthetic])
        candidate=actions[-1]
        for changes in ({'synthetic':1},{'role':'raw'},{'synthetic':False}):
            with self.assertRaises((ValueError,KeyError)):
                f.candidate_program([dict(candidate,**changes)])

    def test_full_corpus_includes_every_synthetic_observation_without_native_input(self):
        cases=[dict(c,path=c['filename']) for c in f.fixtures()]
        controls=[dict(c,path=c['filename']) for c in f.controls()]
        actions=f.candidate_actions(cases,controls,reference(cases),f.synthetic_controls())
        plan=f.plan_partitions(actions)
        self.assertEqual(len(actions),2184);self.assertEqual(len(plan),69)
        self.assertEqual(sum(p['count'] for p in plan),2184)
        self.assertEqual(sum(a.get('synthetic') is True for a in actions),379)
        self.assertEqual(sum(a['role']=='formatted-error' for a in actions),608)
        self.assertEqual([a for p in plan for a in actions[p['start']:p['start']+p['count']]],actions)
        self.assertTrue(all(0<p['count']<=32 and 0<p['source_bytes']<=196608 for p in plan))
        self.assertEqual(sum(p['compared_bytes'] for p in plan),602588)
        self.assertNotIn('invalid-byte-',f.reference_program(cases))

    def test_ordered_greedy_partitions_enforce_utf8_source_cap_and_max32(self):
        actions=unit_actions(5)
        def program(selected):return 'é'*(2*len(selected))
        with patch.object(f,'candidate_program',side_effect=program):
            plan=f.plan_partitions(actions,source_limit=8)
            self.assertEqual([(p['start'],p['count'],p['source_bytes']) for p in plan],[(0,2,8),(2,2,8),(4,1,4)])
            f.validate_partitions(actions,plan,source_limit=8)
            for value in (True,0,-1,8.0,f.SOURCE_BYTE_LIMIT+1):
                with self.assertRaises(ValueError):f.plan_partitions(actions,source_limit=value)
        with patch.object(f,'candidate_program',return_value='x'*9),self.assertRaises(ValueError):
            f.plan_partitions(actions,source_limit=8)
        self.assertEqual([(p['start'],p['count']) for p in f.plan_partitions(unit_actions(65))],[(0,32),(32,32),(64,1)])

    def test_protocol_rejects_chunk_loss_reordering_short_early_and_untyped_errors(self):
        case=dict(id='chunks',width=100,height=1,channels=3)
        a=dict(case=case,role='raw',expected=dict(m.meta(case,'raw'),bytes=list(range(256))+list(range(44))))
        good=encode([a]);self.assertEqual(m.parse_rows(good,[a]),[a['expected']])
        lines=good.splitlines()
        variants=['\n'.join(lines[:1]+lines[2:]),'\n'.join([lines[0],lines[2],lines[1],lines[3]]),
                  '\n'.join([lines[0],json.dumps(a['expected']['bytes'][:128]),json.dumps(a['expected']['bytes'][128:]),lines[3]]),
                  good+'\n',good.replace('"raw"','"owner"',1),good.replace('"width": 100','"width": 100, "width": 100')]
        for value in variants:
            with self.assertRaises(ValueError):m.parse_rows(value,[a])
        error=dict(case={'id':'bad','error':3},role='formatted-error',expected=dict(id='bad',role='formatted-error',error=3))
        for value in (True,3.0,'3',None):
            bad=copy.deepcopy(error);bad['expected']['error']=value
            with self.assertRaises(ValueError):m.parse_rows(encode([bad]),[error])
        with self.assertRaises(ValueError):m.parse_rows(encode([error])+'"end"\n',[error])

    def test_runtime_failure_keeps_partial_report_and_all_durable_seals(self):
        target=self.work/'report';target.mkdir();report=target/'results.json'
        def failed(argv):
            report.write_text(json.dumps(dict(passed=False,phase='native',lanes={lane:dict(passed=False) for lane in f.LANES})))
            artifact=self.work/'partial.stdout';artifact.write_text('observed bytes');m.seal(artifact)
            raise ValueError('native file failed')
        with patch.object(f,'run_probe',side_effect=failed),self.assertRaisesRegex(ValueError,'native file failed'):
            f.main(['--build-dir',str(target)])
        saved=json.loads(report.read_text());self.assertIs(saved['passed'],False);self.assertEqual(saved['phase'],'native')
        self.assertEqual(saved['failure'],dict(type='ValueError',message='native file failed'))
        self.assertEqual(saved['sealed_artifacts'][str((self.work/'partial.stdout').resolve())],m.digest(self.work/'partial.stdout'))

    def test_malformed_missing_or_duplicate_failed_report_cannot_restore_success(self):
        target=self.work/'report';target.mkdir();report=target/'results.json'
        for content in ('','{"passed":true','{"passed":true,"passed":true}','[]','null','true',None):
            def failed(argv):
                if content is None:report.unlink(missing_ok=True)
                else:report.write_text(content)
                raise ValueError('original failure')
            report.write_text('{"passed":true}')
            with patch.object(f,'run_probe',side_effect=failed),self.assertRaisesRegex(ValueError,'original failure'):
                f.main(['--build-dir',str(target)])
            saved=json.loads(report.read_text());self.assertIs(saved['passed'],False)
            self.assertEqual(saved['failure'],dict(type='ValueError',message='original failure'))
            self.assertEqual(saved['sealed_artifacts'],m.SEALED)

    def test_failed_compiler_output_and_interrupted_group_are_retained_and_sealed(self):
        output=self.work/'compiled'
        code='from pathlib import Path;import sys;Path('+repr(str(output))+').write_text("partial compiler output");sys.exit(3)'
        with self.assertRaises(ValueError):f.record_run([sys.executable,'-c',code,'-o',output],self.work,'failed-compile')
        for path in (output,self.work/'failed-compile.command.json',self.work/'failed-compile.stdout',self.work/'failed-compile.stderr'):
            self.assertEqual(m.SEALED[str(path.resolve())],m.digest(path))
        row=json.loads((self.work/'failed-compile.command.json').read_text())
        self.assertEqual(row['exit_code'],3);self.assertTrue(row['process_group_owned'])


    def test_interrupt_cleans_only_owned_group_and_seals_partial_streams(self):
        process=MagicMock(pid=123457,returncode=-signal.SIGKILL)
        process.communicate.side_effect=[KeyboardInterrupt(),('partial','diagnostic')]
        with patch.object(m.subprocess,'Popen',return_value=process),patch.object(m.os,'killpg') as kill:
            with self.assertRaises(KeyboardInterrupt):f.record_run(['unit-tool'],self.work,'interrupt',timeout=600)
        kill.assert_called_once_with(process.pid,signal.SIGKILL)
        row=json.loads((self.work/'interrupt.command.json').read_text())
        self.assertEqual(row['communication_error'],'KeyboardInterrupt');self.assertTrue(row['leader_reaped'])
        self.assertTrue(row['process_group_owned']);self.assertEqual(row['process_group_id'],process.pid)
        self.assertEqual((self.work/'interrupt.stdout').read_text(),'partial')
        self.assertEqual((self.work/'interrupt.stderr').read_text(),'diagnostic');m.verify_sealed()

    def test_resource_receipts_require_exact_schema_plan_identity_counts_and_digests(self):
        actions=unit_actions(2);partitions=f.plan_partitions(actions)
        resources={'boundary':unit_actions(3),'sparse':[dict(case={'id':'oversized','error':2},role='formatted-error',
                   expected=dict(id='oversized',role='formatted-error',error=2))],'exact_cap':unit_actions(4)}
        lanes=lanes_for(partitions)
        for lane in f.LANES:
            for kind,selected in resources.items():
                lanes[lane][kind].update(observations=len(selected),
                    compared_bytes=sum(len(a['expected'].get('bytes',[])) for a in selected),
                    actions_sha256=m.action_digest(selected),stdout_sha256=hashlib.sha256(encode(selected).encode()).hexdigest())
        f.finish_lanes(lanes,actions,partitions,resources)
        self.assertTrue(all(row['passed'] is True for row in lanes.values()))
        for kind in resources:
            for key,value in [('observations',True),('observations',1.0),('observations',0),('observations',99),
                              ('compared_bytes',True),('compared_bytes',-1),('compared_bytes',999),
                              ('actions_sha256','0'*64),('actions_sha256','A'*64),('actions_sha256',True),
                              ('stdout_sha256','bad'),('stdout_sha256',17),('stdout_sha256','A'*64),
                              ('elapsed_seconds',True),('elapsed_seconds',float('nan')),('elapsed_seconds',float('inf')),
                              ('elapsed_seconds',-1),('extra',0)]:
                changed=copy.deepcopy(lanes);changed['javascript'][kind][key]=value
                with self.subTest(kind=kind,key=key,value=value),self.assertRaises(ValueError):
                    f.finish_lanes(changed,actions,partitions,resources)
                self.assertTrue(all(row['passed'] is False for row in changed.values()))
            for key in lanes['cpu-1'][kind]:
                changed=copy.deepcopy(lanes);del changed['cpu-1'][kind][key]
                with self.assertRaises(ValueError):f.finish_lanes(changed,actions,partitions,resources)
        for altered in ({},[],dict(resources,extra=unit_actions()),{k:v for k,v in resources.items() if k!='sparse'},
                        dict(resources,exact_cap=resources['exact_cap'][::-1]),dict(resources,boundary=resources['boundary'][:-1])):
            changed=copy.deepcopy(lanes)
            with self.assertRaises(ValueError):f.finish_lanes(changed,actions,partitions,altered)
            self.assertTrue(all(row['passed'] is False for row in changed.values()))
        for key in ('bytes','path','id'):
            changed=copy.deepcopy(resources)
            changed['exact_cap'][0]['case'][key]={'bytes':[0],'path':'other.bmp','id':'changed'}[key]
            with self.assertRaises(ValueError):f.finish_lanes(copy.deepcopy(lanes),actions,partitions,changed)

    def test_previously_passed_lanes_reset_before_any_invalid_replay(self):
        actions=unit_actions();plan=f.plan_partitions(actions)
        for changed in ([],plan+plan,tuple(plan)):
            lanes=lanes_for(plan)
            for value in lanes.values():value['passed']=True
            with self.assertRaises(ValueError):f.finish_lanes(lanes,actions,changed)
            self.assertTrue(all(row['passed'] is False for row in lanes.values()))

    def test_file_memory_admission_is_independent_for_every_complete_alpha_layout(self):
        cases=f.fixtures()
        for case in cases:
            header=m.inspect_header(case['bytes'])
            self.assertEqual(case['channels'],4 if header['effective_masks'][3] else 3)
        by_id={c['id']:c for c in cases}
        for name in ('rgb32-40-alpha-zero','rgb32-124-alpha-opaque','rgb16-108-alpha-zero',
                     'rgb16-124-alpha-above-word','explicit32-108-alpha-zero'):
            self.assertEqual(by_id[name]['channels'],4)
        for name in ('ignored-rgb24-masks-108','bitfields-56-32-alpha-4278190080','rgb16-108-alpha-absent'):
            self.assertEqual(by_id[name]['channels'],3)
        original=by_id['c3-single']
        with patch.object(m,'inspect_header',side_effect=ValueError('safety parser denied')):
            with self.assertRaisesRegex(ValueError,'safety parser denied'):
                f.reference_program([dict(original,path='file.bmp')])


class BmpFileMockedRunTests(unittest.TestCase):
    """Replay the complete orchestration without compiling or running native code."""
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=f.ROOT);self.work=Path(self.temp.name);m.SEALED.clear()
        self.lock=json.loads((f.ROOT/'toolchain.json').read_text())
        wanted={'c3-single','c4-single','path-c3-mixed'}
        self.cases=[copy.deepcopy(c) for c in f.fixtures() if c['id'] in wanted]
        needed=set(f.BOUNDARY_LOADS)-{'c3-single','c4-single'}
        self.controls=[copy.deepcopy(c) for c in f.controls() if c['id'] in needed]
        self.synthetic=[copy.deepcopy(f.synthetic_controls()[0])]
        self.native=reference(self.cases);self.calls=[];self.pin_calls=[];self.source_calls=[];self.oracle_calls=[]
        self.tools={name:self.work/name for name in ('bun','clang','cmake')}
        for name,path in self.tools.items():path.write_text('unit tool '+name)
        self.archive=self.work/'test.a';self.archive.write_bytes(b'unit native archive')
    def tearDown(self):m.SEALED.clear();self.temp.cleanup()

    def run_mock(self,mode=None):
        target=self.work/('report-'+str(len(list(self.work.iterdir()))));target.mkdir()
        (target/'results.json').write_text('{"passed":true,"stale":"must disappear"}')
        prepare=f.prepare_inputs
        def prepared(work,cases,controls):
            self.stress,stage=prepare(work,cases,controls)
            self.actions=f.candidate_actions(cases,controls,self.native,self.synthetic)
            self.plan=f.plan_partitions(self.actions)
            self.boundary=f.boundary_actions(cases,controls,self.native)
            self.stress_actions=f.candidate_actions([self.stress],[],reference([self.stress]))
            self.sparse=[dict(case=c,role='formatted-error',expected=dict(id=c['id'],role='formatted-error',error=c['error']))
                         for c in controls if c.get('special') in ('sparse','large','overflow')]
            return self.stress,stage
        def tracked(args):
            self.source_calls.append(1)
            return dict(library={},dependencies={},**({'drift':True} if mode=='sources' and len(self.source_calls)>1 else {}))
        def pinned(root):
            self.oracle_calls.append(1)
            return {'pinned':False if mode=='oracle' and len(self.oracle_calls)>1 else True}
        def checkout(*args):
            self.pin_calls.append(args)
            if mode=='pins' and len(self.pin_calls)==3:raise ValueError('pinned source changed')
        def native_output(cases):
            return encode([dict(expected=row) for c in cases for row in reference([c])[c['id']]])
        def record(command,work,label,**kwargs):
            self.calls.append((label,list(map(str,command)),kwargs))
            if label=='bun-version':return 'wrong' if mode=='bun' else self.lock['bun']['version']
            if label=='clang-version':return 'unit clang'
            if label=='qualification':return '{}' if mode=='qualification' else json.dumps(dict(little_endian=True,bmp_enabled=True,effective_alpha_routing=True,formats=[4,7]))
            if label in ('reference','exact-cap-reference'):
                result=native_output(self.cases if label=='reference' else [self.stress])
                if label=='reference' and mode=='reference-empty':return ''
                if label=='reference' and mode=='reference-extra':return result+result
                if label=='reference' and mode=='reference-order':return native_output(list(reversed(self.cases)))
                return result
            if any(label.startswith(lane+'-') for lane in f.LANES):
                part=self.plan[int(label.rsplit('-',1)[1])];selected=self.actions[part['start']:part['start']+part['count']]
                result=encode(selected)
                if label.startswith('javascript-'):
                    if mode=='candidate-empty':return ''
                    if mode=='candidate-missing':return encode(selected[:-1])
                    if mode=='candidate-extra':return result+result
                    if mode=='candidate-order':return encode(list(reversed(selected)))
                    if mode=='candidate-bytes':return result.replace('[17, 17, 17]','[18, 17, 17]',1)
                    if mode=='sealed':(work/'candidate-0.bend').write_text('source drift')
                    if mode=='loader':os.environ['LD_LIBRARY_PATH']='changed'
                    if mode=='tool':self.tools['bun']=self.work/'replacement'
                return result
            return ''
        def resource(command,work,label,ceiling,environment,receipt,timeout):
            self.calls.append((label,list(map(str,command)),dict(environment=environment,receipt=receipt,timeout=timeout)))
            kind=label.split('-',2)[-1] if label.startswith('cpu-') else label.split('-',1)[1]
            selected={'boundary':self.boundary,'sparse':self.sparse,'exact_cap':self.stress_actions}[kind]
            result=encode(selected)+(json.dumps(f.TERMINAL)+'\n' if kind=='boundary' else '')
            if label.startswith('javascript-'):
                if mode==kind+'-missing':result=encode(selected[:-1])+(json.dumps(f.TERMINAL)+'\n' if kind=='boundary' else '')
                if mode==kind+'-extra':result+=encode(selected[-1:])
                if mode==kind+'-order':result=encode(list(reversed(selected)))+(json.dumps(f.TERMINAL)+'\n' if kind=='boundary' else '')
                if mode==kind+'-bytes':result=result.replace('[17, 17, 17]','[18, 17, 17]',1)
                if mode=='boundary-terminal':result=json.dumps(f.TERMINAL)+'\n'
            usage=dict(maximum_rss_bytes=1,elapsed_seconds=0.01,descriptor_limit=64,maximum_rss_acceptance_bytes=ceiling)
            return result,usage
        with ExitStack() as stack:
            stack.enter_context(patch.dict(os.environ,{},clear=False))
            for owner,name,value in [(f,'fixtures',self.cases),(f,'controls',self.controls),(f,'synthetic_controls',self.synthetic)]:
                stack.enter_context(patch.object(owner,name,return_value=copy.deepcopy(value)))
            stack.enter_context(patch.object(f,'prepare_inputs',side_effect=prepared))
            stack.enter_context(patch.object(f,'checkout',side_effect=checkout))
            stack.enter_context(patch.object(f,'tracked_sources',side_effect=tracked))
            stack.enter_context(patch.object(m,'validate_reference_sources',side_effect=pinned))
            stack.enter_context(patch.object(f,'native_archive',return_value=(self.archive,dict(mode='unit-only'))))
            stack.enter_context(patch.object(f.shutil,'which',side_effect=lambda name:str(self.tools[name])))
            stack.enter_context(patch.object(f.subprocess,'check_output',return_value='unit-revision\n'))
            stack.enter_context(patch.object(f,'record_run',side_effect=record))
            stack.enter_context(patch.object(f,'resource_run',side_effect=resource))
            stack.enter_context(patch('sys.stdout',new_callable=io.StringIO))
            args=['--bend-source',str(self.work/'bend'),'--raylib-source',str(self.work/'raylib'),'--build-dir',str(target)]
            if mode:
                with self.assertRaises(ValueError):f.main(args)
            else:f.main(args)
        return json.loads((target/'results.json').read_text())

    def reset_observations(self):
        self.calls=[];self.pin_calls=[];self.source_calls=[];self.oracle_calls=[];self.tools['bun']=self.work/'bun'

    def test_success_replays_every_file_owner_bridge_resource_and_pin(self):
        before=dict(os.environ);report=self.run_mock()
        self.assertIs(report['passed'],True);self.assertNotIn('stale',report);self.assertEqual(dict(os.environ),before)
        self.assertEqual(self.pin_calls,[(self.work/'bend',self.lock['bend']['revision'],self.lock['bend']['patch']),
                                        (self.work/'raylib',self.lock['raylib']['revision']),
                                        (self.work/'bend',self.lock['bend']['revision'],self.lock['bend']['patch']),
                                        (self.work/'raylib',self.lock['raylib']['revision'])])
        self.assertGreater(len(self.oracle_calls),1);self.assertEqual(report['native_rejections'],0)
        self.assertEqual(report['cases'],3);self.assertEqual(report['typed_controls'],5)
        self.assertEqual(report['observations_per_lane'],len(self.actions))
        self.assertEqual(report['compared_bytes_per_lane'],sum(len(a['expected'].get('bytes',[])) for a in self.actions))
        self.assertEqual(report['file_descriptor_limit'],64);self.assertEqual(report['closure']['iterations'],100)
        self.assertTrue(all(row['passed'] is True for row in report['lanes'].values()))
        from reference_environment import LOADER_NAMES
        for label,command,kwargs in self.calls:
            if label in ('clang-version','qualification-compile','qualification','reference-compile','reference','exact-cap-reference-compile','exact-cap-reference'):
                self.assertEqual(kwargs['receipt']['policy'],'clean-loader')
                self.assertTrue(all(name not in kwargs['environment'] for name in LOADER_NAMES))
            if label.startswith(('cpu-1-','cpu-2-')):self.assertIn('--gpu',command);self.assertIn('off',command)
        labels=[label for label,_,_ in self.calls]
        for lane in f.LANES:
            for kind in ('boundary','sparse','exact_cap'):self.assertIn(lane+'-'+kind,labels)
        self.assertIn('candidate-0.bend',' '.join(report['sealed_artifacts']))
        self.assertEqual([a['role'] for a in self.stress_actions],['raw','owner','bridge','surface'])

    def test_setup_or_native_protocol_failures_never_inherit_success(self):
        for mode in ('bun','qualification','reference-empty','reference-extra','reference-order'):
            with self.subTest(mode=mode):
                self.reset_observations();report=self.run_mock(mode)
                self.assertIs(report['passed'],False);self.assertIn('failure',report);self.assertNotIn('stale',report)
                self.assertFalse(any(label.startswith('compile-') for label,_,_ in self.calls))

    def test_missing_extra_reordered_or_changed_candidate_records_fail(self):
        for mode in ('candidate-empty','candidate-missing','candidate-extra','candidate-order','candidate-bytes'):
            with self.subTest(mode=mode):
                self.reset_observations();report=self.run_mock(mode)
                self.assertIs(report['passed'],False);self.assertIn('failure',report)
                self.assertTrue(all(row['passed'] is False for row in report['lanes'].values()))

    def test_exact_cap_and_sparse_controls_require_full_replay_not_terminal_claims(self):
        for mode in ('boundary-missing','boundary-extra','boundary-order','boundary-bytes','boundary-terminal',
                     'sparse-missing','sparse-extra','sparse-order','exact_cap-missing','exact_cap-extra','exact_cap-order','exact_cap-bytes'):
            with self.subTest(mode=mode):
                self.reset_observations();report=self.run_mock(mode)
                self.assertIs(report['passed'],False);self.assertIn('failure',report)
                self.assertTrue(all(row['passed'] is False for row in report['lanes'].values()))

    def test_late_pin_oracle_loader_tool_source_and_input_seals_fail_closed(self):
        for mode in ('pins','oracle','sources','loader','tool','sealed'):
            with self.subTest(mode=mode):
                self.reset_observations();report=self.run_mock(mode)
                self.assertIs(report['passed'],False);self.assertIn('failure',report);self.assertNotIn('stale',report)


if __name__=='__main__':unittest.main()
