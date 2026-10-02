"""Guardrails for the exact formatted BMP differential harness; no native runs."""
import copy
import json
from pathlib import Path
import runpy
import struct
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
with patch('sys.path',[str(ROOT/'tools'),*sys.path]):
    P=runpy.run_path(str(ROOT/'tools/formatted_bmp_export_probe.py'))


def synthetic(case):
    direct=case['format'] in (1,2,4);w,h=case['width'],case['height']
    offset,depth=(54,24) if direct else (122,32);stride=(w*3+3)&~3 if direct else w*4
    fields=[offset+stride*h,0,offset,40 if direct else 108,w,h,(depth<<16)|1,0 if direct else 3,0,0,0,0,0]
    if not direct:fields += [0xff0000,0xff00,0xff,0xff000000]+[0]*13
    data=b'BM'+struct.pack('<'+'I'*len(fields),*fields)+bytes(stride*h)
    pixels=[v for _ in range(w*h) for v in (0,0,0,255 if direct else 0)]
    return data,pixels


def output(case):
    data,pixels=synthetic(case)
    result=[json.dumps(P['metadata'](case))]
    for values in (list(data),pixels):
        result += [json.dumps(values[i:i+256]) for i in range(0,len(values),256)]+['"end"']
    return '\n'.join(result)+'\n'


class FormattedBmpExportTests(unittest.TestCase):
    def test_unique_nonempty_cases_and_shapes(self):
        cases=P['fixtures']();self.assertEqual(len(cases),78)
        self.assertEqual(len({c['id'] for c in cases}),78)
        for c in cases:
            self.assertEqual(len(c['data']),c['width']*c['height']*P['BPP'][c['format']])
            self.assertTrue(all(type(v) is int and 0<=v<=255 for v in c['data']))

    def test_all_formats_padding_orientation_axes_and_full_traversal(self):
        cases=P['fixtures']()
        for fmt in range(1,9):
            selected=[c for c in cases if c['format']==fmt]
            for width in range(1,5):self.assertTrue(any(c['width']==width and c['height']==2 for c in selected))
            for w,h in [(1,31),(4096,1),(1,4096),(256,129)]:self.assertTrue(any((c['width'],c['height'])==(w,h) for c in selected))
            for c in selected:
                if c['height']==2:
                    n=c['width']*P['BPP'][fmt]
                    self.assertNotEqual(c['data'][:n],c['data'][n:])

    def test_alpha_discard_variations_identical_gray(self):
        cases=[c for c in P['fixtures']() if c['id'].startswith('gray-alpha-')]
        self.assertEqual({c['data'][1] for c in cases},{0,1,127,128,254,255})
        self.assertTrue(all(c['data'][::2]==cases[0]['data'][::2] for c in cases))

    def test_packed_boundaries_seeded_and_alpha_only(self):
        cases=P['fixtures']()
        for fmt in (3,5,6):
            c=next(c for c in cases if c['id']==f'packed-{fmt}-boundaries')
            words=struct.unpack('<21H',bytes(c['data']))
            self.assertTrue({0,1,15,31,32,63,64,0xF801,0x3E,65535}<=set(words))
            self.assertTrue(any(c['id']==f'packed-{fmt}-seeded' for c in cases))

    def test_r32_domain_thresholds_signedzero_subnormal(self):
        c=next(c for c in P['fixtures']() if c['id']=='r32-truncation-boundaries')
        words=set(struct.unpack('<'+'I'*(len(c['data'])//4),bytes(c['data'])))
        self.assertTrue({0,0x80000000,1,0x007fffff,0x3f000000,0x3f800000}<=words)
        self.assertTrue(all(v==0x80000000 or 0<=v<=0x3f800000 for v in words))
        for level in range(1,255):
            word=struct.unpack('<I',struct.pack('<f',level/255))[0]
            self.assertTrue({word-1,word,word+1}<=words)

    def test_independent_two_layouts_decode_and_headers(self):
        for fmt in range(1,9):
            for w in range(1,5):
                c=dict(id='fixture',format=fmt,width=w,height=2)
                data,pixels=synthetic(c)
                self.assertEqual(P['decode_bmp'](data,c),pixels)
                self.assertEqual(P['parse_rows'](output(c),[c])[0]['pixels'],pixels)

    def test_independent_decode_channel_order_bottomup_and_alpha(self):
        for fmt in (1,7):
            c=dict(id='fixture',format=fmt,width=1,height=2)
            data,_=synthetic(c);data=bytearray(data);off=54 if fmt==1 else 122
            data[off:]=bytes([3,2,1,0 if fmt==1 else 4,7,6,5,0 if fmt==1 else 8])
            self.assertEqual(P['decode_bmp'](bytes(data),c),[5,6,7,255 if fmt==1 else 8,1,2,3,255 if fmt==1 else 4])

    def test_decode_rejects_header_size_padding_and_trailing_mutations(self):
        for fmt in (1,7):
            c=dict(id='fixture',format=fmt,width=1,height=2);data,_=synthetic(c)
            changes=[data[:-1],data+b'\0']
            for index in (0,2,10,14,18,22,26,28,30,34,38,42,46,50):
                altered=bytearray(data);altered[index]^=1;changes.append(bytes(altered))
            if fmt==1:
                altered=bytearray(data);altered[57]=1;changes.append(bytes(altered))
            for changed in changes:
                with self.assertRaises(ValueError):P['decode_bmp'](changed,c)

    def test_parser_rejects_missing_extra_reordered_duplicate_and_wrong_type(self):
        c=dict(id='fixture',format=7,width=1,height=2);valid=output(c);lines=valid.splitlines()
        changes=['',valid+valid,'\n'.join(lines[:-1]),'\n'.join(lines[1:]),valid.replace('"fixture"','"other"'),valid.replace('"width": 1','"width": true'),valid.replace('"format": 7','"format": 7, "format": 7')]
        for changed in changes:
            with self.assertRaises(ValueError):P['parse_rows'](changed,[c])

    def test_parser_rejects_invalid_chunks_pixels_and_incomplete_metadata(self):
        c=dict(id='fixture',format=7,width=1,height=2);lines=output(c).splitlines()
        for part in ('[]','null','[true]','[256]','[-1]','[0.0]',json.dumps([0]*257)):
            changed=lines[:];changed[1]=part
            with self.assertRaises(ValueError):P['parse_rows']('\n'.join(changed),[c])
        changed=lines[:];changed[3]='[1,0,0,0,0,0,0,0]'
        with self.assertRaises(ValueError):P['parse_rows']('\n'.join(changed),[c])

    def test_native_uses_actual_export_before_decode_normalization(self):
        c=P['fixtures']()[0];source=P['reference_program']([c],Path('/tmp/fixture'))
        self.assertIn('ExportImage(image,',source);self.assertNotIn('ExportImageToMemory',source)
        self.assertLess(source.index('ExportImage(image,'),source.index('ImageFormat(&decoded,7)'))
        self.assertNotIn('ImageFormat(&image',source)
        self.assertIn('typed_pixels(data,n,',source)
        self.assertIn('unsigned short value;memcpy(&value,data+2*i,sizeof value);samples[i]=value;',source)
        self.assertIn('float value;memcpy(&value,data+4*i,sizeof value);samples[i]=value;',source)
        self.assertIn('memcmp(storage,data,(size_t)size)',source)
        self.assertIn('if(image.data!=data)free(image.data)',source)

    def test_candidate_calls_public_pure_and_explicit_dat_file_writer(self):
        source=P['candidate_program'](P['fixtures']()[:2],Path('/tmp/fixture'))
        self.assertIn('J.Image.Formatted.to_bmp(image)',source)
        self.assertIn('J.Image.Formatted.write_bmp(image, path)',source)
        self.assertIn('.dat',source);self.assertNotIn('to_surface',source)
        self.assertIn('File.close(file)',source);self.assertIn('emit_chunks',source)
        self.assertLess(len(P['candidate_program']([P['fixtures']()[7]],Path('/tmp/fixture'))),10000)

    def test_io_exact_code_and_message_and_all_formats(self):
        source=P['io_program'](Path('/tmp/fixture'),True)
        self.assertIn('String.eq(message, actual_message)',source)
        self.assertIn('U32.is_eq(code, actual_code)',source)
        self.assertIn('U32.is_gt(code, 0)',source)
        self.assertIn('baseline(27,',source)
        for fmt in range(1,9):self.assertIn(f'from_bytes(1, 1, {fmt},',source)
        self.assertIn('loop(100n',source)

    def test_io_parser_rejects_false_success_type_and_nontruncation(self):
        marker=json.dumps(dict(iterations=100,writes=800))
        with tempfile.TemporaryDirectory() as tmp:
            work=Path(tmp);(work/'post-open.dat').write_bytes(b'')
            self.assertTrue(P['verify_io'](marker,work,True)['exact_base_code_and_message'])
            for text in ('',marker+'\n'+marker,json.dumps(dict(iterations=100.0,writes=800)),json.dumps(dict(iterations=100,writes=799))):
                with self.assertRaises(ValueError):P['verify_io'](text,work,True)
            (work/'post-open.dat').write_bytes(b'old')
            with self.assertRaises(ValueError):P['verify_io'](marker,work,True)

    def test_source_implementation_retains_legacy_encoder_and_native_route(self):
        source=(ROOT/'jonlib.bend').read_text()
        start=source.index('def Image.Formatted.bmp.routed');end=source.index('def Image.FloatRGB.png.word',start)
        new=source[start:end]
        self.assertIn('Formats.packed_colors',new);self.assertIn('Bmp.encode24',new)
        self.assertNotIn('to_surface',new);self.assertNotIn('Formats.convert',new)
        writer=source[source.index('def Image.Formatted.write_bmp'):source.index('# Called only after checked request')]
        self.assertIn('U32 & String, Unit',writer);self.assertIn('Surface.qoi.opened(Image.Formatted.to_bmp(image))',writer)

    def test_sealed_artifacts_reject_mutation_and_missing_input(self):
        P['SEALED'].clear()
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'input.raw';path.write_bytes(b'input')
            P['seal'](path);P['verify_sealed']()
            path.write_bytes(b'other')
            with self.assertRaises(ValueError):P['verify_sealed']()
            with self.assertRaises(ValueError):P['seal'](path)
            path.unlink()
            with self.assertRaises(ValueError):P['verify_sealed']()
        P['SEALED'].clear()

    def test_stale_success_and_outputs_cleared_before_checkout_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            work=Path(tmp)/'formatted-bmp-export-probe';work.mkdir()
            (work/'results.json').write_text('{"passed":true}')
            (work/'candidate-0').write_text('stale executable')
            with patch.dict(P['main'].__globals__,BUILD=Path(tmp),checkout=lambda *args: (_ for _ in ()).throw(ValueError('bad pin'))):
                with patch('sys.argv',['probe','--bend-source',tmp,'--raylib-source',tmp]):
                    with self.assertRaisesRegex(ValueError,'bad pin'):P['main']()
            self.assertIs(json.loads((work/'results.json').read_text())['passed'],False)
            self.assertFalse((work/'candidate-0').exists())

    def test_missing_compiler_output_rejected_after_old_output_removed(self):
        P['SEALED'].clear()
        with tempfile.TemporaryDirectory() as tmp:
            work=Path(tmp);output=work/'compiled';output.write_text('old')
            with patch('subprocess.run',return_value=subprocess.CompletedProcess([],0,'','')):
                with self.assertRaisesRegex(ValueError,'Compiler output missing'):
                    P['record_run'](['unexecuted-compiler','-o',output],work,'test')
            self.assertFalse(output.exists())
        P['SEALED'].clear()

    def test_qualification_is_separate_fixed_native_controls(self):
        source=P['QUALIFY']
        self.assertIn('LoadImageColors(image)',source)
        self.assertIn('sizeof(unsigned short)==2',source)
        self.assertIn('float sample;memcpy(&sample,&words[i],sizeof sample)',source)
        self.assertIn('(void *)&sample : (void *)&packed',source)
        self.assertNotIn('Image image={words+i',source)
        self.assertIn('fegetround()!=FE_TONEAREST',source)
        self.assertIn('0xf8fcf8ff',source);self.assertIn('0x80000000',source)
        self.assertNotIn('ExportImageToMemory',source)


if __name__=='__main__':unittest.main()
