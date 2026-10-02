#!/usr/bin/env python3
"""Exact original-format binary PGM/PPM memory decoding against pinned raylib.

Accepted complete native fixtures only; checked-invalid controls are never sent
native. PNM is explicitly enabled in a fresh isolated native build. Actual native
metadata/raw bytes precede normalization. CPU-1/CPU-2/JS; no GPU or file claim.
"""
import argparse
from functools import partial
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time
import uuid

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER
from conformance import BUILD, ROOT, ENV, checkout, source_gate
from pnm_probe import fixtures as legacy_fixtures
from reference_environment import ReferenceEnvironment

BATCH_SIZE = 32
LANES = ('cpu-1', 'cpu-2', 'javascript')
IMAGE_ROLES = {'raw','factory','owner','alias-pgm','alias-PPM','alias-PGM','normalized','bridge','surface','dispatch-ppm','dispatch-pgm','dispatch-PPM','dispatch-PGM','uncontracted','fused'}
SPACE = b' \t\n\v\f\r'
MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
SEALED = {}


def header(width=1, height=1, channels=1, maximum=255, separator=b'\n'):
    return (b'P5' if channels==1 else b'P6')+f'\n{width} {height}\n{maximum}'.encode()+separator


def inspect_header(data):
    """Independent safety parser only: never supplies expected decoded samples."""
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):raise ValueError('Unsafe native byte domain')
    data=bytes(data)
    if data[:2] not in (b'P5',b'P6'):raise ValueError('Unsafe native magic')
    position=2;values=[]
    for _ in range(3):
        while position<len(data):
            if data[position] in SPACE:position+=1
            elif data[position]==35:
                while position<len(data) and data[position] not in (10,13):position+=1
            else:break
        start=position
        while position<len(data) and 48<=data[position]<=57:position+=1
        if position==start or position==len(data):raise ValueError('Unsafe native header')
        token=data[start:position]
        if len(token)>12:raise ValueError('Unsafe native decimal magnitude')
        values.append(int(token))
    if data[position] not in SPACE:raise ValueError('Unsafe native separator')
    w,h,maximum=values
    if not 1<=w<=4096 or not 1<=h<=4096 or w*h>MAX_CASE_PIXELS or not 1<=maximum<=65535:raise ValueError('Unsafe native dimensions/depth')
    return dict(width=w,height=h,channels=1 if data[1]==53 else 3,maximum=maximum,header_bytes=position+1,
                raster_bytes=w*h*(1 if data[1]==53 else 3)*(2 if maximum>255 else 1))


def validate_cases(cases):
    if not cases:raise ValueError('Empty native PNM cases')
    ids=set();total=0
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','width','height','channels','maximum','header_bytes','raster_bytes','extended'}:raise ValueError('Native case schema differs')
        name=case['id']
        if type(name) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',name) is None or name in ids:raise ValueError('Invalid/duplicate native fixture ID')
        ids.add(name)
        if type(case['extended']) is not bool:raise ValueError('Invalid alias selector')
        observed=inspect_header(case['bytes'])
        if any(type(case[k]) is not int or case[k]!=value for k,value in observed.items()):raise ValueError('Native declared metadata/header differs')
        if len(case['bytes'])<case['header_bytes']+case['raster_bytes']:raise ValueError('Incomplete native raster')
        total+=len(case['bytes'])
    if total>MAX_TOTAL_BYTES:raise ValueError('Unsafe native aggregate fixture size')


def fixtures():
    result=[]
    def add(name,w,h,c,maximum,payload,*,prefix=None,tail=b'',extended=False):
        prefix=header(w,h,c,maximum) if prefix is None else prefix
        case=dict(id=name,width=w,height=h,channels=c,maximum=maximum,header_bytes=len(prefix),raster_bytes=w*h*c*(2 if maximum>255 else 1),bytes=list(prefix+bytes(payload)+tail),extended=extended)
        result.append(case)
    # Preserve every historical input verbatim; declarations come from generator
    # identities, and the independent safety parser checks their complete headers.
    for case in legacy_fixtures()[0]:
        name=case['id'];c=3 if name.startswith('P6') else 1
        w,h=(16,16) if name.endswith('-16bit-bytes') else (3,2)
        if name in ('crlf-payload','space-payload','hash-payload','16bit-crlf-payload'):w,h=2,1
        if name=='wide':w,h=4096,1
        if name=='tall':w,h=1,4096
        maximum=int(name.rsplit('-max-',1)[1]) if '-max-' in name else (65535 if '16bit' in name else 255)
        raster=w*h*c*(2 if maximum>255 else 1)
        tail=4 if name.endswith('-16bit-bytes') else 12 if name.endswith(('comments','spaces','leading-zeros','inline-comments')) else 0
        result.append(dict(case,id='legacy-'+name,width=w,height=h,channels=c,maximum=maximum,header_bytes=len(case['bytes'])-raster-tail,raster_bytes=raster,extended=name in ('P5-comments','P6-comments')))
    for c in (1,3):
        for maximum in (255,256):
            prefix=f'c{c}-max{maximum}-'
            def sample(i):
                kept=(i*61+17)&255
                return (kept,) if maximum==255 else ((i*43+128)&255,kept)
            for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63),('channel-ramps',16,16)]:
                values=[v for i in range(w*h*c) for v in sample(i)]
                add(prefix+name,w,h,c,maximum,values,extended=name in ('single','padded'))
            for separator in SPACE:
                add(prefix+f'separator-{separator}',1,1,c,maximum,[v for i in range(c) for v in sample(i)],prefix=header(1,1,c,maximum,bytes([separator])))
        for maximum in (1,15,100,257,1000,65535):
            payload=[v for i in range(5*c) for v in ((255-i,) if maximum<=255 else (i,255-i))]
            add(f'c{c}-unscaled-{maximum}',5,1,c,maximum,payload,tail=b' # ignored\n',extended=maximum==257)
        for varying in ('first','second'):
            payload=[v for i in range(256*c) for v in ((i&255,127) if varying=='first' else (85,i&255))]
            add(f'c{c}-wide-vary-{varying}',16,16,c,65535,payload)
    add('grayscale-exact-ramp',16,16,1,255,range(256),extended=True)
    add('rgb-distinct-boundaries',2,3,3,255,[0,1,127,128,254,255,255,0,128,1,127,254,254,128,1,127,255,0],extended=True)
    validate_cases(result);return result


def controls():
    result=[dict(c,id='legacy-'+c['id']) for c in legacy_fixtures()[1]]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    h=header()
    for n in range(len(h)):add(f'header-prefix-{n}',h[:n],0)
    for magic in (b'P1',b'P2',b'P4',b'P7',b'p5',b'P0'):add('magic-'+magic.decode(),magic+h[2:]+b'\0',0)
    for axis in ('width','height'):
        for value in (0,4097,2147483647,4294967295):
            # Decimal overflow precedes size validation above signed-32 magnitude.
            add(f'{axis}-{value}',header(**{axis:value})+b'\0',0 if value>2147483647 else 2)
    for maximum in (0,65536,2147483648,4294967295):add(f'maximum-{maximum}',header(maximum=maximum)+b'\0\0',0)
    for text in (b'P5 ',b'P5 1 ',b'P5 1 1 ',b'P5 x 1 255\n',b'P5 1 x 255\n',b'P5 1 1 x\n'):
        add('missing-field-'+str(len(result)),text,0)
    for c in (1,3):
        for maximum in (255,256):
            needed=c*(2 if maximum>255 else 1)
            for n in range(needed):add(f'truncated-c{c}-max{maximum}-{n}',header(channels=c,maximum=maximum)+bytes(n),3)
    for where,data in [('header',[256,*h[1:],0]),('raster',[*h,256]),('tail',[*h,0,256]),('wide-discarded',[*header(maximum=256),256,0]),('wide-kept',[*header(maximum=256),0,256])]:add('invalid-byte-'+where,data,1)
    add('bad-byte-before-bad-header',[0,256],1)
    add('bad-byte-before-bad-size',[*header(width=0),256],1)
    add('bad-max-before-bad-size',header(width=0,maximum=0),0)
    add('bad-separator-before-bad-size',header(width=0,separator=b'x'),0)
    add('complete-header-missing-raster',header(),3)
    if len({c['id'] for c in result})!=len(result):raise ValueError('Duplicate checked control ID')
    return result


def strict_json(text):
    def unique(pairs):
        out={}
        for key,value in pairs:
            if key in out:raise ValueError('Duplicate JSON key')
            out[key]=value
        return out
    return json.loads(text,object_pairs_hook=unique)


def meta(case,role):
    if role not in IMAGE_ROLES:raise ValueError('Unknown PNM image role')
    return dict(id=case['id'],role=role,width=case['width'],height=case['height'],mipmaps=1,
                format=(1 if case['channels']==1 else 4) if role in ('raw','factory','owner','alias-pgm','alias-PPM','alias-PGM') else 7)


def parse_rows(text, actions):
    if not actions:raise ValueError('Empty PNM observation batch')
    lines=text.splitlines();cursor=0;rows=[]
    for action in actions:
        case,role=action['case'],action['role']
        if cursor>=len(lines):raise ValueError('Missing PNM record')
        row=strict_json(lines[cursor]);cursor+=1
        if role in ('formatted-error','surface-error'):
            expected=dict(id=case['id'],role=role,error=case['error'])
        else:expected=meta(case,role)
        if type(row) is not dict or row!=expected or any(type(row.get(k)) is not type(v) for k,v in expected.items()):
            raise ValueError(f'PNM metadata/order/type differs: {case["id"]}/{role}: {row!r}')
        if role not in ('formatted-error','surface-error'):
            output=[];short=False
            while cursor<len(lines):
                chunk=strict_json(lines[cursor]);cursor+=1
                if chunk=='end':break
                if type(chunk) is not list or not 1<=len(chunk)<=256 or short or any(type(v) is not int or not 0<=v<=255 for v in chunk):raise ValueError('Malformed PNM byte chunk')
                short=len(chunk)<256;output.extend(chunk)
            else:raise ValueError('Unterminated PNM bytes')
            if len(output)!=case['width']*case['height']*{1:1,4:3,7:4}[row['format']]:raise ValueError('PNM byte count differs')
            row=dict(row,bytes=output)
        rows.append(row)
    if cursor!=len(lines):raise ValueError('Extra PNM records')
    return rows


BEND_PREFIX=r'''import Base
import ../../../jonlib.bend as J
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def words.read(+format: U32, state: Array<U32> & U32) -> Array<U32> & Bool:
  (pixels, +word) = state
  (pixels, (U32.is_eq(format, 1) && (word <= 255 : U32)) || (U32.is_eq(format, 4) && (word <= 16777215 : U32)))
def words(n: Nat, +index: U32, +format: U32, state: Array<U32> & Bool) -> Array<U32> & Bool:
  match n state:
    case _ Tuple{pixels, False{}}: (pixels, False{})
    case 0n Tuple{pixels, True{}}: (pixels, True{})
    case 1n+rest Tuple{pixels, True{}}: words(rest, (index + 1 : U32), format, words.read(format, Array.get(U32, pixels, index)))
def checked.words(width: U32, height: U32, format: U32, state: Array<U32> & Bool) -> Maybe<J.Image.Formatted>:
  match state:
    case Tuple{pixels, True{}}: Some{J.FormattedImage{width, height, format, pixels}}
    case _: None{}
def checked(image: J.Image.Formatted) -> Maybe<J.Image.Formatted>:
  J.FormattedImage{+width, +height, +format, pixels} = image
  checked.words(width, height, format, words(U32.to_nat((width * height : U32)), 0, format, (pixels, True{})))
def decoded(result: Result<&1, &1, J.Image.DecodeError, J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: checked(image)
def surface(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{J.Surface.to_formatted(image)}
def bridge(result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Surface.to_formatted(J.Image.Formatted.to_surface(image))}
def owner.got(expected: Maybe<&2, U32>, result: J.Image.Formatted & Maybe<&2, U32>) -> Maybe<J.Image.Formatted>:
  match expected result:
    case None{} Tuple{image, None{}}: Some{image}
    case Some{wanted} Tuple{image, Some{value}}: Bool.pick(Maybe<J.Image.Formatted>, U32.is_eq(wanted, value), Some{image}, None{})
    case _ _: None{}
def owner.read(result: Maybe<J.Image.Formatted>, x: U32, y: U32, expected: Maybe<&2, U32>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: owner.got(expected, J.Image.Formatted.get(image, x, y))
def owner(result: Maybe<J.Image.Formatted>, +width: U32, +height: U32, first: U32, last: U32) -> Maybe<J.Image.Formatted>:
  image = owner.read(result, 0, 0, Some{first})
  image = owner.read(image, (width - 1 : U32), (height - 1 : U32), Some{last})
  image = owner.read(image, width, 0, None{})
  image = owner.read(image, 0, height, None{})
  image = owner.read(image, 4294967295, 0, None{})
  owner.read(image, 0, 4294967295, None{})
def emit(id: String, role: String, data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  do IO<Unit>:
    # Formatted owners are single-mip by contract; there is no mipmaps field.
    IO.print("{\"id\":\"" ++ id ++ "\",\"role\":\"" ++ role ++ "\",\"width\":" ++ U32.show(width) ++ ",\"height\":" ++ U32.show(height) ++ ",\"mipmaps\":1,\"format\":" ++ U32.show(format) ++ "}")
    emit_bytes(~&1, bytes)
def observed(id: String, role: String, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid PNM or owner invariant rejected")
    case Some{image}: emit(id, role, J.Image.Formatted.export(image))
def error.code(error: J.Image.DecodeError) -> U32:
  match error:
    case J.InvalidImageHeader{}: 0
    case J.InvalidImageByte{}: 1
    case J.UnsupportedImageSize{}: 2
    case J.TruncatedImageData{}: 3
    case J.InvalidImageStream{}: 4
def formatted.error(result: Result<&1, &1, J.Image.DecodeError, J.Image.Formatted>) -> U32:
  match result:
    case Fail{error}: error.code(error)
    case Done{_}: 99
def surface.error(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> U32:
  match result:
    case Fail{error}: error.code(error)
    case Done{_}: 99
def emit.error(id: String, role: String, code: U32) -> IO(Unit):
  IO.print("{\"id\":\"" ++ id ++ "\",\"role\":\"" ++ role ++ "\",\"error\":" ++ U32.show(code) ++ "}")
'''

C_PREFIX=r'''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
static int little_endian(void){uint16_t word=1;return *(unsigned char *)&word==1;}
static void emit(const unsigned char *p,int n){for(int start=0;start<n;start+=256){putchar('[');for(int i=start;i<n&&i<start+256;i++)printf("%s%u",i==start?"":",",p[i]);puts("]");}puts("\"end\"");}
static void observed(const char *id,const char *role,Image image){
  printf("{\"id\":\"%s\",\"role\":\"%s\",\"width\":%d,\"height\":%d,\"mipmaps\":%d,\"format\":%d}\n",id,role,image.width,image.height,image.mipmaps,image.format);
  emit(image.data,GetPixelDataSize(image.width,image.height,image.format));
}
'''
QUALIFY=C_PREFIX+r'''int main(void){
  if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);
  const unsigned char gray[]={'P','5','\n','1',' ','1','\n','2','5','6','\n',0x12,0x34};
  const unsigned char rgb[]={'P','6','\n','1',' ','1','\n','2','5','5','\n',1,127,255};
  Image a=LoadImageFromMemory(".ppm",gray,sizeof(gray));
  if(!a.data)return 11;
  if(a.width!=1||a.height!=1||a.mipmaps!=1||a.format!=1||GetPixelDataSize(1,1,a.format)!=1){UnloadImage(a);return 11;}
  if(((unsigned char *)a.data)[0]!=0x34){UnloadImage(a);return 12;}UnloadImage(a);
  Image b=LoadImageFromMemory(".pgm",rgb,sizeof(rgb));
  if(!b.data)return 13;
  if(b.width!=1||b.height!=1||b.mipmaps!=1||b.format!=4||GetPixelDataSize(1,1,b.format)!=3){UnloadImage(b);return 13;}
  const unsigned char *p=b.data;if(p[0]!=1||p[1]!=127||p[2]!=255){UnloadImage(b);return 14;}UnloadImage(b);
  puts("{\"little_endian\":true,\"pnm_enabled\":true,\"wide_second_byte\":true,\"formats\":[1,4]}");return 0;
}
'''


def qualification(text):
    expected=dict(little_endian=True,pnm_enabled=True,wide_second_byte=True,formats=[1,4])
    result=strict_json(text)
    if type(result) is not dict or result!=expected or any(type(result[k]) is not type(v) for k,v in expected.items()) or any(type(v) is not int for v in result['formats']):raise ValueError('Native PNM/endian qualification differs')
    return result


def native_actions(cases):
    return [dict(case=c,role=role) for c in cases for role in ('raw','normalized',*(('alias-pgm','alias-PPM','alias-PGM') if c['extended'] else ()))]


def reference_program(cases):
    validate_cases(cases)
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        fmt=1 if c['channels']==1 else 4;raw_size=c['width']*c['height']*c['channels']
        lines+=['{const unsigned char data[]={'+','.join(map(str,c['bytes']))+'};',
                'Image image=LoadImageFromMemory(".ppm",data,sizeof(data));if(!image.data)return 2;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 3;}}',
                f'observed({json.dumps(c["id"])},"raw",image);',
                'ImageFormat(&image,7);if(!image.data)return 4;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!=7||GetPixelDataSize(image.width,image.height,image.format)!={c["width"]*c["height"]*4}){{UnloadImage(image);return 5;}}',
                f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);']
        if c['extended']:
            for token in ('pgm','PPM','PGM'):
                lines+=[f'image=LoadImageFromMemory(".{token}",data,sizeof(data));if(!image.data)return 6;',
                        f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 7;}}',
                        f'observed({json.dumps(c["id"])},"alias-{token}",image);UnloadImage(image);']
        lines+=['}']
    return '\n'.join(lines+['return 0;}'])+'\n'


def candidate_actions(cases,invalid,rows):
    reference={};cursor=0
    for c in cases:
        raw,normal=rows[cursor:cursor+2];cursor+=2
        if c['extended']:
            for token in ('pgm','PPM','PGM'):
                if rows[cursor]!=dict(raw,role='alias-'+token):raise ValueError('Native PNM alias bytes differ')
                cursor+=1
        reference[c['id']]=(raw,normal)
    if cursor!=len(rows):raise ValueError('Native PNM reference count differs')
    actions=[]
    for c in cases:
        raw,normal=reference[c['id']]
        for role in ('raw','bridge','surface','factory','owner',*(('dispatch-ppm','dispatch-pgm','dispatch-PPM','dispatch-PGM','uncontracted','fused') if c['extended'] else ())):
            expected=dict(raw if role in ('raw','factory','owner') else normal,role=role)
            actions.append(dict(case=c,role=role,expected=expected,normalized=normal['bytes']))
    for c in invalid:
        for mode in ('formatted','surface'):
            role=mode+'-error';actions.append(dict(case=c,role=role,expected=dict(id=c['id'],role=role,error=c['error'])))
    return actions,reference


def candidate_program(actions):
    lines=[BEND_PREFIX.replace('import ../../../jonlib.bend as J','import '+str(ROOT/'jonlib.bend')+' as J').replace('def reverse_into(',BEND_EMITTER+'def reverse_into(',1),'def main() -> IO(Unit):']
    bindings={}
    for action in actions:
        c=action['case']
        if c['id'] not in bindings:
            name='input'+str(len(bindings));bindings[c['id']]=name
            lines.append(f'  +{name} = {{{bend_bytes(c["bytes"])} : +List<U32>}}')
    lines.append('  do IO<Unit>:')
    for action in actions:
        c=action['case'];role=action['role'];data=bindings[c['id']];ident=json.dumps(c['id'])
        decode=f'decoded(J.Image.Formatted.decode_pnm({data}))'
        if role.endswith('-error'):
            mode=role.split('-')[0];call='J.Image.Formatted' if mode=='formatted' else 'J.Surface'
            lines.append(f'    emit.error({ident}, {json.dumps(role)}, {mode}.error({call}.decode_pnm({data})))');continue
        if role=='raw':image=decode
        elif role=='bridge':image=f'bridge({decode})'
        elif role=='surface':image=f'surface(J.Surface.decode_pnm({data}))'
        elif role.startswith('dispatch-'):image=f'surface(J.Surface.decode_image({json.dumps("."+role.split("-")[1])}, {data}))'
        elif role in ('uncontracted','fused'):image=f'surface(J.Surface.decode_image_for(J.{"UncontractedDecode" if role=="uncontracted" else "FusedDecode"}{{}}, ".PPM", {data}))'
        elif role=='factory':image=f'J.Image.Formatted.from_bytes({c["width"]}, {c["height"]}, {1 if c["channels"]==1 else 4}, {bend_bytes(action["expected"]["bytes"])})'
        elif role=='owner':
            normal=action['normalized'];first=int.from_bytes(bytes(normal[:4]),'big');last=int.from_bytes(bytes(normal[-4:]),'big')
            image=f'owner({decode}, {c["width"]}, {c["height"]}, {first}, {last})'
        else:raise ValueError('Unknown PNM observation')
        lines.append(f'    observed({ident}, {json.dumps(role)}, {image})')
    return '\n'.join(lines)+'\n'


def differences(expected,actual):
    if len(expected)!=len(actual):raise ValueError('PNM comparison count differs')
    result=[]
    for wanted,got in zip(expected,actual):
        if wanted!=got:
            item=dict(id=wanted['id'],role=wanted['role'])
            if 'bytes' in wanted and 'bytes' in got:
                item['byte_differences']=[dict(index=i,expected=a,actual=b) for i,(a,b) in enumerate(zip(wanted['bytes'],got['bytes'])) if a!=b]
                item['expected_length']=len(wanted['bytes']);item['actual_length']=len(got['bytes'])
            item['metadata_differences']={k:dict(expected=wanted.get(k),actual=got.get(k)) for k in set(wanted)|set(got) if k!='bytes' and wanted.get(k)!=got.get(k)}
            result.append(item)
    return result


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def seal(path):
    path=str(Path(path).resolve());observed=digest(path)
    if path in SEALED and SEALED[path]!=observed:raise ValueError('Sealed PNM artifact drift: '+path)
    SEALED[path]=observed


def verify_sealed():
    for path,expected in SEALED.items():
        if not Path(path).is_file() or digest(path)!=expected:raise ValueError('Sealed PNM artifact drift: '+path)


def record_run(command,work,label,*,timeout=600,environment=None,receipt=None,require_output=False):
    verify_sealed();command=list(map(str,command))
    outputs=[Path(command[i+1]) for i,arg in enumerate(command[:-1]) if arg=='-o']
    for arg in command:
        path=Path(arg)
        if path.is_file() and path not in outputs:seal(path)
    for path in outputs:path.unlink(missing_ok=True)
    for ext in ('stdout','stderr','command.json'):(work/(label+'.'+ext)).unlink(missing_ok=True)
    try:
        proc=subprocess.run(command,cwd=ROOT,env=ENV if environment is None else environment,text=True,capture_output=True,timeout=timeout)
    except subprocess.TimeoutExpired as error:
        for ext,value in [('stdout',error.stdout or ''),('stderr',error.stderr or ''),('command.json',json.dumps(dict(command=command,exit_code=None,timed_out=True,timeout=timeout,reference_environment=receipt))+'\n')]:
            path=work/(label+'.'+ext);path.write_text(value.decode(errors='replace') if isinstance(value,bytes) else value);seal(path)
        raise ValueError('PNM child timed out: '+label) from error
    for ext,value in [('stdout',proc.stdout),('stderr',proc.stderr),('command.json',json.dumps(dict(command=command,exit_code=proc.returncode,reference_environment=receipt),indent=2)+'\n')]:
        path=work/(label+'.'+ext);path.write_text(value);seal(path)
    if proc.returncode:raise ValueError(f'{label} exited {proc.returncode}: {proc.stdout[-1000:]}{proc.stderr[-2500:]}')
    if require_output and not proc.stdout.strip():raise ValueError('Process output missing: '+label)
    if any(not p.is_file() or p.stat().st_size==0 for p in outputs):raise ValueError('Compiler output missing')
    for path in outputs:seal(path)
    return proc.stdout


def tracked_sources(args):
    paths=[ROOT/p for p in ('tools/pnm_format_probe.py','tests/test_pnm_format_harness.py','tools/pnm_probe.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','toolchain.json','LAWS.bend','PROOF.bend')]
    paths += [p for p in args.raylib_source.rglob('*') if p.is_file() and (p.suffix in ('.c','.h','.cmake','.in') or p.name in ('CMakeLists.txt','CMakeOptions.txt')) and '.git' not in p.parts]
    paths += [p for p in (args.bend_source/'bend2').rglob('*') if p.is_file() and p.suffix in ('.ts','.bend','.c','.js','.h')]
    return dict(library=source_gate(),dependencies={str(p):digest(p) for p in paths})


def report_directories(argv):
    result=[];index=0;rules=argparse.ArgumentParser(add_help=False,allow_abbrev=False)
    while index<len(argv):
        token=argv[index]
        if token=='--':break
        if token.startswith('--build-dir='):result.append(Path(token.partition('=')[2]))
        elif token=='--build-dir' and index+1<len(argv) and rules._parse_optional(argv[index+1]) is None:index+=1;result.append(Path(argv[index]))
        index+=1
    return result or [BUILD/'pnm-format-probe']


def admit_directories(argv):
    paths=report_directories(argv)
    for path in dict.fromkeys(p.resolve() for p in paths):
        path.mkdir(parents=True,exist_ok=True);(path/'results.json').write_text('{"passed":false,"phase":"argument-validation"}\n')
    return paths[-1].resolve()


def validate_native_config(cache,flags):
    required={'PLATFORM':'Memory','CMAKE_BUILD_TYPE':'Release','CUSTOMIZE_BUILD':'ON','SUPPORT_FILEFORMAT_PNM':'ON','SUPPORT_MODULE_RAUDIO':'OFF','BUILD_EXAMPLES':'OFF','USE_EXTERNAL_GLFW':'OFF'}
    pairs=re.findall(r'^([A-Za-z_][A-Za-z0-9_]*):[^=\n]+=(.*)$',cache,re.M)
    fields=dict(pairs)
    if len(fields)!=len(pairs):raise ValueError('Duplicate native CMake cache field')
    if any(fields.get(k)!=v for k,v in required.items()):raise ValueError('Native PNM cache configuration differs')
    tokens=flags.split()
    definitions=[t for t in tokens if t.startswith(('-DSUPPORT_FILEFORMAT_PNM','-USUPPORT_FILEFORMAT_PNM'))]
    definitions += [t+tokens[i+1] for i,t in enumerate(tokens[:-1]) if t in ('-D','-U') and tokens[i+1].startswith('SUPPORT_FILEFORMAT_PNM')]
    if len(definitions)!=1 or definitions[0] not in ('-DSUPPORT_FILEFORMAT_PNM','-DSUPPORT_FILEFORMAT_PNM=1') or '-DEXTERNAL_CONFIG_FLAGS' not in tokens or '-DPLATFORM_MEMORY' not in tokens:raise ValueError('Actual PNM compile definition missing/disabled/ambiguous')
    return required


def native_archive(args,work,record):
    cmake=work/'raylib-build'
    record(['cmake','-S',args.raylib_source,'-B',cmake,'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DSUPPORT_FILEFORMAT_PNM=ON','-DUSE_EXTERNAL_GLFW=OFF'],work,'configure')
    config=validate_native_config((cmake/'CMakeCache.txt').read_text(),(cmake/'raylib/CMakeFiles/raylib.dir/flags.make').read_text())
    record(['cmake','--build',cmake,'--clean-first','--parallel','4'],work,'native-build')
    validate_native_config((cmake/'CMakeCache.txt').read_text(),(cmake/'raylib/CMakeFiles/raylib.dir/flags.make').read_text())
    archive=cmake/'raylib/libraylib.a';files=[archive,cmake/'CMakeCache.txt',cmake/'raylib/CMakeFiles/raylib.dir/flags.make']
    compilers=list((cmake/'CMakeFiles').glob('*/CMakeCCompiler.cmake'))
    if len(compilers)!=1:raise ValueError('Missing/ambiguous native compiler provenance')
    files+=compilers;text=compilers[0].read_text()
    fields={k:re.search(r'set\('+k+r' "([^"\n]+)"\)',text) for k in ('CMAKE_C_COMPILER','CMAKE_C_COMPILER_ID','CMAKE_C_COMPILER_VERSION')}
    if any(v is None for v in fields.values()):raise ValueError('Incomplete native compiler provenance')
    compiler={k:v.group(1) for k,v in fields.items()};compiler_path=Path(compiler['CMAKE_C_COMPILER'])
    if not compiler_path.is_file():raise ValueError('Native archive compiler missing')
    files.append(compiler_path)
    version=record([compiler_path,'--version'],work,'archive-compiler-version',require_output=True)
    for path in files:seal(path)
    return archive,dict(mode='fresh-isolated-build',configuration=config,compiler=compiler,compiler_version=version,artifacts={str(p):digest(p) for p in files})


def finish_lanes(lanes,actions):
    if not actions or set(lanes)!=set(LANES):raise ValueError('Missing mandatory PNM lanes/cases')
    for lane in LANES:
        batches=lanes[lane]['batches'];cursor=0
        for batch in batches:
            if type(batch['start']) is not int or batch['start']!=cursor or type(batch['count']) is not int or not 1<=batch['count']<=BATCH_SIZE or batch['passed'] is not True:raise ValueError('Incomplete/noncontiguous/failed PNM batch')
            cursor+=batch['count']
        if cursor!=len(actions) or lanes[lane]['differences']:raise ValueError('Incomplete or differing PNM lane: '+lane)
        lanes[lane]['passed']=True


def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv);admitted=admit_directories(argv)
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--build-dir',type=Path,default=BUILD/'pnm-format-probe')
    parser.add_argument('--reference-env',choices=('clean-loader',),default='clean-loader')
    parser.add_argument('--timeout',type=int,default=600)
    args=parser.parse_args(argv);destination=args.build_dir.resolve()
    if destination!=admitted:parser.error('Destination admission differs')
    if args.timeout<=0:parser.error('--timeout must be positive')
    SEALED.clear();reference_env=ReferenceEnvironment(args.reference_env)
    record=partial(record_run,timeout=args.timeout)
    native_record=partial(record,environment=reference_env.child(),receipt=reference_env.receipt())
    report_path=destination/'results.json';work=destination/('run-'+uuid.uuid4().hex);work.mkdir()
    started=time.monotonic();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if sys.byteorder!='little':raise ValueError('PNM profile requires little endian')
    cases,invalid=fixtures(),controls();validate_cases(cases)
    inputs=work/'inputs.json';inputs.write_text(json.dumps(dict(cases=cases,controls=invalid),sort_keys=True)+'\n');seal(inputs)
    tool_paths={}
    for tool in ('bun','clang','cmake'):
        path=shutil.which(tool)
        if path is None:raise ValueError('Required tool missing: '+tool)
        tool_paths[tool]=str(Path(path).absolute());seal(path)
    tool_realpaths={k:str(Path(p).resolve()) for k,p in tool_paths.items()}
    report=dict(passed=False,profile='native-pnm-formatted-memory-v1',run_directory=str(work),toolchain=lock,base_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),host=dict(system=platform.system(),machine=platform.machine()),tool_paths=tool_paths,tool_realpaths=tool_realpaths,sources=tracked_sources(args),reference_environment=reference_env.receipt(),inputs_sha256=digest(inputs),cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(invalid),native_rejections=0,batch_size=BATCH_SIZE,lanes={lane:dict(passed=False,batches=[],differences=[]) for lane in LANES},candidate_mipmaps='implicit single-mip type contract, not stored/measured',unrun=['GPU/Metal','Windows/browser','big-endian','exact-commit hosted CI','4096x4096 allocation/resource limits','representative performance','formatted file IO','generic formatted/float dispatch','native malformed recovery'])
    for path in [*(ROOT/p for p in report['sources']['library']),*(Path(p) for p in report['sources']['dependencies'])]:seal(path)
    def save():report_path.write_text(json.dumps(report,indent=2)+'\n')
    save();archive,report['native_build']=native_archive(args,work,native_record);save()
    report['bun_version']=record(['bun','--version'],work,'bun-version',require_output=True).strip()
    if report['bun_version']!=lock['bun']['version']:raise ValueError('Bun version differs')
    report['clang_version']=native_record(['clang','--version'],work,'clang-version',require_output=True).strip()
    for name,program in [('qualification',QUALIFY),('reference',reference_program(cases))]:
        source=work/(name+'.c');source.write_text(program);seal(source);binary=work/name
        native_record(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,name+'-compile')
        output=native_record([binary],work,name,require_output=True)
        if name=='qualification':report['qualification']=qualification(output)
        else:
            native_rows=parse_rows(output,native_actions(cases));report['reference_sha256']=hashlib.sha256(output.encode()).hexdigest()
    actions,reference=candidate_actions(cases,invalid,native_rows)
    report.update(native_observations=len(native_rows),native_raw_bytes=sum(len(raw['bytes']) for raw,_ in reference.values()),native_normalized_bytes=sum(len(normal['bytes']) for _,normal in reference.values()),native_all_observed_bytes=sum(len(r['bytes']) for r in native_rows),observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions),raw_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] in ('raw','factory','owner')),normalized_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] not in ('raw','factory','owner')));save()
    for start in range(0,len(actions),BATCH_SIZE):
        selected=actions[start:start+BATCH_SIZE];index=start//BATCH_SIZE
        source=work/f'candidate-{index}.bend';source.write_text(candidate_program(selected));seal(source)
        binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,f'compile-{index}')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual=parse_rows(record(command,work,f'{lane}-{index}',require_output=True),selected)
            delta=differences([a['expected'] for a in selected],actual)
            report['lanes'][lane]['differences'].extend(delta)
            report['lanes'][lane]['batches'].append(dict(start=start,count=len(selected),bytes=sum(len(r.get('bytes',[])) for r in actual),passed=not delta));save()
        print(f'PNM batch {index+1}: {len(selected)} observations compared on CPU-1/CPU-2/JavaScript',flush=True)
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    reference_env.assert_receipt(report['reference_environment'])
    if any(shutil.which(k) is None or str(Path(shutil.which(k)).absolute())!=p or str(Path(shutil.which(k)).resolve())!=tool_realpaths[k] for k,p in tool_paths.items()):raise ValueError('Tool executable resolution drift')
    if tracked_sources(args)!=report['sources']:raise ValueError('Source/toolchain/native input drift')
    finish_lanes(report['lanes'],actions);verify_sealed()
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3),sealed_artifacts=dict(SEALED));save()
    print(f'PASS: {len(cases)} native PNM images, {len(invalid)} checked-only typed controls, {report["compared_bytes_per_lane"]} bytes per lane',flush=True)


if __name__=='__main__':main()
