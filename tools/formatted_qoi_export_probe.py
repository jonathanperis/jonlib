#!/usr/bin/env python3
"""Exact checked RGB/RGBA QOI export, retained rejections, decoding and typed IO.

Uses actual pinned ExportImage; never ExportImageToMemory or ImageFormat to
prepare source pixels. CPU-1/CPU-2/JavaScript are separate exact lanes. No GPU
claim. Native error-return parity is deliberately not claimed for short writes.
"""
import json
from pathlib import Path
import random
import re
import shutil
import struct

import formatted_export
from formatted_export import BPP, COLOR_CONTROLS, SENTINEL, TYPED_PIXELS, strict_json
from byte_probe import BEND_EMITTER
from image_format_probe import r32_words
from probekit import ProbeFailure

MARKER = b'\0\0\0\0\0\0\0\1'
ACCEPTED = (4, 7)
REJECTED = (1, 2, 3, 5, 6, 8)


def channels(fmt):
    return {4: 3, 7: 4}.get(fmt, 0)


def header(width, height, channels, space=0):
    return b'qoif'+struct.pack('>II', width, height)+bytes((channels, space))


def validate_case(case):
    w,h,f=(case[k] for k in ('width','height','format'))
    if (any(type(v) is not int for v in (w,h,f)) or not 1<=w<=4096 or
            not 1<=h<=4096 or f not in BPP or type(case['data']) is not list or
            len(case['data'])!=w*h*BPP[f] or any(type(v) is not int or not 0<=v<=255 for v in case['data'])):
        raise ValueError('Unsafe native checked source shape/bytes')
    if f==8:
        words=struct.unpack('<'+'I'*(w*h),bytes(case['data']))
        if any(word!=0x80000000 and not 0<=word<=0x3f800000 for word in words):
            raise ValueError('Unsafe native R32 source domain')


def fixtures():
    result=[]; rng=random.Random(0x514f49)
    def add(name,fmt,w,h,data,**extra):
        case=dict(id=name,format=fmt,width=w,height=h,data=list(data),**extra)
        validate_case(case);result.append(case)
    def colors(name,fmt,values,w=None,**extra):
        values=list(values);w=w or len(values)
        add(name,fmt,w,len(values)//w,bytes(v for p in values for v in p[:channels(fmt)]),**extra)
    for fmt in ACCEPTED:
        prefix=f'format-{fmt}-'
        a=(12,34,56,255);b=(127,128,129,255);black=(0,0,0,255)
        for name,value in [('black',black),('white',(255,255,255,255)),('rgb',a)]:
            colors(prefix+name,fmt,[value])
        for width in range(1,5):colors(prefix+f'width-{width}',fmt,[a,b,black,b,a,black,a,b][:width*2],width)
        for n in (1,2,61,62,63,64,123,124,125):
            for initial in (True,False):
                values=[black if initial else a]*n
                for changed in (False,True):
                    colors(prefix+f'run-{n}-'+('initial' if initial else 'literal')+('-change' if changed else ''),fmt,values+([b] if changed else []))
        colors(prefix+'row-crossing-run',fmt,[a]+[black]*7+[b],3)
        colors(prefix+'initial-run-black-reuse',fmt,[black,a,black])
        colors(prefix+'orientation',fmt,[a,b,black,black,b,a,b,black,a],3)
        for name,w,h in [('axis-row',4096,1),('axis-column',1,4096),('full-traversal',256,129),('seeded-mixed',257,2)]:
            colors(prefix+name,fmt,([a,b,black][i%3] for i in range(w*h)) if name!='seeded-mixed' else (tuple(rng.randrange(256) for _ in range(3))+(255,) for _ in range(w*h)),w)
        for code in range(64):
            delta=((code>>4)-2,((code>>2)&3)-2,(code&3)-2)
            colors(prefix+f'diff-{code:02d}',fmt,[tuple(x&255 for x in delta)+(255,)])
        # Isolate each just-outside DIFF edge with untouched other channels;
        # initial cache state cannot preempt the required LUMA fallback.
        for axis in range(3):
            for delta,label in ((-3,'minus3'),(2,'plus2')):
                rgb=[0,0,0];rgb[axis]=delta&255
                colors(prefix+f'outside-diff-{axis}-{label}',fmt,[tuple(rgb)+(255,)])
        for dg in (-33,-32,-31,30,31,32):
            values=[]
            for drg in (-9,-8,-7,6,7,8):
                for dbg in (-9,-8,-7,6,7,8):values.extend([black,((dg+drg)&255,dg&255,(dg+dbg)&255,255)])
            colors(prefix+f'luma-{dg}',fmt,values)
        values=[]
        for r in range(64):values.extend([(r,31,65,255),(r,31,64,255),(r,31,65,255)])
        colors(prefix+'all-index-slots',fmt,values)
        colors(prefix+'cache-collision',fmt,[(1,0,0,255),(65,0,0,255),(1,0,0,255)])
        colors(prefix+'byte-ramp',fmt,[(i,255-i,i^85,255) for i in range(256)],16)
    for name,values in [('transparent-black',[(0,0,0,0)]),('rgba-literal',[(12,34,56,0)]),('alpha-aba',[(17,63,201,a) for a in (0,255,0)]),('alpha-boundaries',[(17,63,201,a) for a in (0,1,127,128,254,255)]),('alpha-ramp',[(17,63,201,a) for a in range(256)]),('hidden-rgb',[(i,255-i,i^85,0) for i in range(256)]),('alpha-hash-collision',[(1,2,3,a) for a in (0,64,0,255,191,255)])]:
        colors('rgba-'+name,7,values)
    for fmt in ACCEPTED:
        colors(f'paired-{fmt}',fmt,[(i,255-i,i^85,255) for i in range(256)],16)
    colors('surface-bridge',7,[(12,34,56,0),(127,128,129,255),(0,0,0,0)],origin='bridge')
    # Noncanonical input alpha/cache state is discarded only for channel 3.
    for fmt in ACCEPTED:
        for origin in ('decode','load'):
            stream=header(3,1,channels(fmt),1)+bytes([255,12,34,56,0,255,200,100,50,64,22])+MARKER
            values=[(12,34,56,0),(200,100,50,64),(12,34,56,0)]
            colors(f'{origin}-c{channels(fmt)}-hidden-alpha-space1',fmt,values,origin=origin,input=list(stream))
    colors('rgba-large-raw',7,((i&255,(i>>8)&255,(i>>16)&255,(i+1)&255) for i in range(513*513)),513)
    samples={1:bytes([0,127,255]),2:bytes([17,0,127,127,255,255]),3:struct.pack('<3H',0,0xf801,0xffff),5:struct.pack('<3H',0,0xf800,0xf801),6:struct.pack('<3H',0,0xa127,0xa12f),8:struct.pack('<3I',0,0x80000000,0x3f800000)}
    for fmt in REJECTED:
        values=[samples[fmt][i*BPP[fmt]:(i+1)*BPP[fmt]] for i in range(3)]
        for name,w,h in [('single',1,1),('padded',3,3),('full-traversal',65,67)]:
            add(f'rejected-{fmt}-{name}',fmt,w,h,b''.join(values[i%3] for i in range(w*h)))
    for fmt in (3,5,6):
        words=[0,1,15,16,31,32,63,64,255,256,1023,1024,32767,32768,65534,65535,0xf801,0x003e]
        add(f'rejected-packed-{fmt}',fmt,6,3,struct.pack('<18H',*words))
    words=r32_words();add('rejected-r32-boundaries',8,len(words),1,struct.pack('<'+'I'*len(words),*words))
    if len({c['id'] for c in result})!=len(result):raise ValueError('Duplicate fixture ID')
    return result


def decode_qoi(data, case, *, canonical=True):
    """Strict independent decoder, with opcode observations, never an encoder."""
    if type(data) is not bytes:raise ValueError('QOI data must be bytes')
    w,h,f=(case[k] for k in ('width','height','format'))
    if any(type(v) is not int for v in (w,h,f)) or not 1<=w<=4096 or not 1<=h<=4096 or f not in ACCEPTED:raise ValueError('Invalid checked QOI shape')
    if len(data)<22 or data[:13]!=header(w,h,channels(f))[:13] or data[13] not in ((0,) if canonical else (0,1)):
        raise ValueError('QOI header/shape differs')
    end=len(data)-8
    if data[end:]!=MARKER:raise ValueError('QOI marker differs')
    position=14;pixels=[];previous=(0,0,0,255);index=[(0,0,0,0)]*64;ops=[]
    while len(pixels)<w*h:
        if position>=end:raise ValueError('QOI pixel underflow')
        code=data[position];position+=1;count=1;before=previous
        def take(n):
            nonlocal position
            if position+n>end:raise ValueError('Short QOI opcode operand')
            result=data[position:position+n];position+=n;return result
        if code==254:previous=(*take(3),previous[3]);kind='RGB'
        elif code==255:previous=tuple(take(4));kind='RGBA'
        elif code<64:previous=index[code];kind='INDEX'
        elif code<128:
            previous=tuple((previous[i]+((code>>(4-2*i))&3)-2)&255 for i in range(3))+(previous[3],);kind='DIFF'
        elif code<192:
            residual=take(1)[0];dg=(code&63)-32
            previous=((previous[0]+dg+(residual>>4)-8)&255,(previous[1]+dg)&255,(previous[2]+dg+(residual&15)-8)&255,previous[3]);kind='LUMA'
        else:count=(code&63)+1;kind='RUN'
        if len(pixels)+count>w*h:raise ValueError('QOI run exceeds pixel count')
        if canonical and f==4 and (kind=='RGBA' or previous[3]!=255):raise ValueError('RGB export changed implicit alpha')
        ops.append(dict(kind=kind,code=code,pixel=len(pixels),count=count,before=before,after=previous))
        for _ in range(count):
            pixels.append(previous);index[(previous[0]*3+previous[1]*5+previous[2]*7+previous[3]*11)&63]=previous
    if position!=end:raise ValueError('Extra QOI payload/EOF bytes')
    raw=[v for p in pixels for v in p[:channels(f)]]
    rgba=[v for p in pixels for v in ((*p[:3],255) if f==4 else p)]
    return dict(raw=raw,pixels=rgba,opcodes=ops)


def metadata(case,role):
    fmt=7 if role=='surface' else case['format']
    return dict(id=case['id'],role=role,width=case['width'],height=case['height'],format=fmt,mipmaps=1)


def roles(case):
    return ('source','encoded','decoded','surface','loaded') if case['format'] in ACCEPTED else ('source','retained')


def parse_rows(text,cases):
    lines=text.splitlines();cursor=0;rows=[]
    for case in cases:
        values={}
        for role in roles(case):
            if cursor>=len(lines):raise ValueError('Missing QOI metadata')
            row=strict_json(lines[cursor]);cursor+=1;expected=metadata(case,role)
            if type(row) is not dict or row!=expected or any(type(row.get(k)) is not type(v) for k,v in expected.items()):raise ValueError('QOI metadata identity/order/type differs')
            output=[];short=False
            while cursor<len(lines):
                part=strict_json(lines[cursor]);cursor+=1
                if part=='end':break
                if (type(part) is not list or not 1<=len(part)<=256 or short or any(type(v) is not int or not 0<=v<=255 for v in part)):raise ValueError('Malformed or partial QOI byte chunk')
                short=len(part)<256;output.extend(part)
            else:raise ValueError('Unterminated QOI bytes')
            values[role]=output
        if values['source']!=case['data']:raise ValueError('Raw source owner bytes differ')
        if case['format'] in ACCEPTED:
            decoded=decode_qoi(bytes(values['encoded']),case)
            if any(values[role]!=case['data'] for role in ('decoded','loaded')) or decoded['raw']!=case['data'] or decoded['pixels']!=values['surface']:raise ValueError('QOI decoded raw/Surface observations differ')
        elif values['retained']!=case['data']:raise ValueError('Rejected QOI owner changed')
        rows.append(dict(id=case['id'],**values))
    if cursor!=len(lines):raise ValueError('Extra QOI records')
    return rows


def coverage(cases,rows):
    by_id={r['id']:r for r in rows};kinds=set();diff=set();slots=set()
    for case in cases:
        if case['format'] not in ACCEPTED:continue
        ops=decode_qoi(bytes(by_id[case['id']]['encoded']),case)['opcodes']
        kinds.update(op['kind'] for op in ops);diff.update(op['code'] for op in ops if op['kind']=='DIFF');slots.update(op['code'] for op in ops if op['kind']=='INDEX')
        name=case['id']
        if re.fullmatch(r'format-[47]-diff-[0-9]{2}',name):
            code=int(name.rsplit('-',1)[1]);expected=bytes([192 if code==42 else 64+code])
            if bytes(by_id[name]['encoded'])[14:-8]!=expected:raise ValueError('Native wrapped DIFF control differs')
        if '-outside-diff-' in name:
            edge=name.split('-outside-diff-')[1]
            payload={'0-minus3':b'\xa0\x58','0-plus2':b'\xa0\xa8',
                     '1-minus3':b'\x9d\xbb','1-plus2':b'\xa2\x66',
                     '2-minus3':b'\xa0\x85','2-plus2':b'\xa0\x8a'}[edge]
            if len(ops)!=1 or ops[0]['kind']!='LUMA' or bytes(by_id[name]['encoded'])[14:-8]!=payload:
                raise ValueError('Native just-outside DIFF LUMA fallback differs')
        if '-luma-' in name:
            dg=int(name.split('-luma-')[1])
            for op in ops:
                if op['pixel']%2:
                    delta=lambda v:(v+128)%256-128
                    drg=delta(op['after'][0])-dg;dbg=delta(op['after'][2])-dg
                    expected='LUMA' if -32<=dg<=31 and -8<=drg<=7 and -8<=dbg<=7 else 'RGB'
                    if op['kind']!=expected:raise ValueError('Native LUMA boundary/fallback differs')
    for fmt in ACCEPTED:
        for name,payload in [('black',b'\xc0'),('white',b'\x55'),('rgb',b'\xfe\x0c\x22\x38'),('run-62-initial',b'\xfd'),('run-63-initial',b'\xfd\xc0'),('run-124-initial',b'\xfd\xfd')]:
            if bytes(by_id[f'format-{fmt}-{name}']['encoded'])[14:-8]!=payload:raise ValueError('Native exact payload control differs')
    if bytes(by_id['rgba-transparent-black']['encoded'])[14:-8]!=b'\0' or bytes(by_id['rgba-rgba-literal']['encoded'])[14:-8]!=b'\xff\x0c\x22\x38\0':raise ValueError('Native transparent exact payload differs')
    a=bytes(by_id['paired-4']['encoded']);b=bytes(by_id['paired-7']['encoded'])
    if a[:12]!=b[:12] or a[13:]!=b[13:] or a[12]!=3 or b[12]!=4:raise ValueError('RGB/opaque RGBA paired payload differs')
    if len(by_id['rgba-large-raw']['encoded'])!=1315867:raise ValueError('Large RGBA exact byte count differs')
    if kinds!={'RGB','RGBA','RUN','INDEX','DIFF','LUMA'} or diff!=set(range(64,128))-{106} or slots!=set(range(64)):raise ValueError('Incomplete actual QOI opcode coverage')
    return dict(opcodes=sorted(kinds),diff_opcodes=sorted(diff),index_slots=sorted(slots),zero_diff_uses_run=True,outside_diff_luma_controls=sum('-outside-diff-' in c['id'] for c in cases),large_encoded_bytes=1315867)


C_PREFIX = r'''#include "raylib.h"
#include <float.h>
#include <fenv.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
_Static_assert(CHAR_BIT==8 && sizeof(float)==4 && sizeof(unsigned)==4 && sizeof(unsigned short)==2 && FLT_RADIX==2 && FLT_MANT_DIG==24 && FLT_MAX_EXP==128, "8-bit bytes, 16-bit shorts and binary32 required");
'''+TYPED_PIXELS+r'''    if(memcmp(storage,data,(size_t)size))exit(7);
    return storage;
}
static void emit(const unsigned char *p,int n){for(int start=0;start<n;start+=256){putchar('[');for(int i=start;i<n&&i<start+256;i++)printf("%s%u",i==start?"":",",p[i]);puts("]");}puts("\"end\"");}
static void meta(const char *id,const char *role,Image image){
    printf("{\"id\":\"%s\",\"role\":\"%s\",\"width\":%d,\"height\":%d,\"format\":%d,\"mipmaps\":%d}\n",id,role,image.width,image.height,image.format,image.mipmaps);
}
static void observed(const char *id,const char *role,Image image){meta(id,role,image);emit(image.data,GetPixelDataSize(image.width,image.height,image.format));}
'''
QUALIFY = C_PREFIX+r'''int main(void){SetTraceLogLevel(LOG_NONE);unsigned little=1;if(*(unsigned char*)&little!=1||fegetround()!=FE_TONEAREST||(signed char)255!=-1||(signed char)-255!=1||(signed char)128!=-128)return 2;
'''+COLOR_CONTROLS+r'''puts("{\"controls\":9,\"little_endian\":true,\"round_to_nearest\":true,\"signed_char_wrap\":true}");return 0;}
'''


def reference_program(cases,work):
    body=[C_PREFIX,'int main(void){SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        validate_case(c)
        ident=json.dumps(c['id']);path=json.dumps(str(work/(c['id']+'.raw')));output=json.dumps(str(work/('reference-'+c['id']+'.qoi')))
        body += ['{int n=0;unsigned char *data=LoadFileData('+path+',&n);',f'if(!data||n!={len(c["data"])})return 2;Image image={{typed_pixels(data,n,{c["format"]}),{c["width"]},{c["height"]},1,{c["format"]}}};',f'unsigned char *snapshot=malloc({len(c["data"])});if(!snapshot)return 10;memcpy(snapshot,data,{len(c["data"])});observed({ident},"source",image);']
        if c['format'] in ACCEPTED:
            body += [f'if(!ExportImage(image,{output}))return 3;',f'if(memcmp(image.data,snapshot,{len(c["data"])}))return 7;',f'unsigned char *file=LoadFileData({output},&n);if(!file||n<22)return 4;',
                     'const unsigned char expected_header[]={'+','.join(map(str,header(c['width'],c['height'],channels(c['format']))))+'};if(memcmp(file,expected_header,14))return 8;',
                     f'meta({ident},"encoded",image);emit(file,n);','Image decoded=LoadImageFromMemory(".qoi",file,n);',
                     f'if(!decoded.data||decoded.width!={c["width"]}||decoded.height!={c["height"]}||decoded.mipmaps!=1||decoded.format!={c["format"]})return 5;',
                     f'observed({ident},"decoded",decoded);','ImageFormat(&decoded,7);if(!decoded.data)return 5;',f'observed({ident},"surface",decoded);UnloadImage(decoded);',
                     f'Image loaded=LoadImage({output});if(!loaded.data)return 9;observed({ident},"loaded",loaded);UnloadImage(loaded);UnloadFileData(file);']
        else:
            absent=json.dumps(str(work/('reference-absent-'+c['id']+'.qoi')))
            body += [f'if(ExportImage(image,{output})||ExportImage(image,{absent}))return 3;',f'if(memcmp(image.data,snapshot,{len(c["data"])}))return 7;',f'observed({ident},"retained",image);']
        body+=['free(snapshot);if(image.data!=data)free(image.data);UnloadFileData(data);}']
    return '\n'.join(body+['return 0;}'])+'\n'


BEND_PREFIX = '''import Base
import ../../jonlib.bend as J
'''+BEND_EMITTER+r'''
def checked(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "QOI contract differs")
def meta(id: String, role: String, width: U32, height: U32, format: U32) -> IO(Unit):
  IO.print("{\"id\":\"" ++ id ++ "\",\"role\":\"" ++ role ++ "\",\"width\":" ++ U32.show(width) ++ ",\"height\":" ++ U32.show(height) ++ ",\"format\":" ++ U32.show(format) ++ ",\"mipmaps\":1}")
def emit(id: String, role: String, value: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = value
  do IO<Unit>:
    meta(id, role, width, height, format)
    emit_bytes(~&1, bytes)
def observed(id: String, role: String, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "QOI fixture source rejected")
    case Some{image}: emit(id, role, J.Surface.export(image))
def decoded(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}
def rgba.bytes(values: List<U32>, bytes: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: List.reverse(&2, U32, bytes)
    case Con{+v, rest}: rgba.bytes(rest, Con{J.Color.alpha(v), Con{J.Color.blue(v), Con{J.Color.green(v), Con{J.Color.red(v), bytes}}}})
def rgba.colors(+width: U32, +height: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{values}: J.Surface.from_bytes(width, height, 7, rgba.bytes(values, Nil{}))
def rgba(image: J.Surface) -> Maybe<J.Surface>:
  J.Surface{+width, +height, format, pixels} = image
  rgba.colors(width, height, J.Surface.colors(J.Surface{width, height, format, pixels}))
def surface(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: rgba(image)
def bridge.formatted(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}
def bridge(result: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match result:
    case None{}: None{}
    case Some{image}: bridge.formatted(J.Surface.format(image, 7))
def owner(mode: U32, width: U32, height: U32, format: U32, bytes: +List<U32>) -> Maybe<J.Surface>:
  match mode:
    case 1: decoded(J.Surface.decode_qoi(bytes))
    case 2: bridge(J.Surface.from_bytes(width, height, format, bytes))
    case _: J.Surface.from_bytes(width, height, format, bytes)
def encoded(+id: String, width: U32, height: U32, format: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "Accepted QOI export rejected")
    case Done{+bytes}:
      do IO<Unit>:
        meta(id, "encoded", width, height, format)
        emit_bytes(~&2, bytes)
        observed(id, "decoded", decoded(J.Surface.decode_qoi(bytes)))
        observed(id, "surface", surface(J.Surface.decode_qoi(bytes)))
def pure(id: String, width: U32, height: U32, format: U32, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "QOI source rejected")
    case Some{image}: encoded(id, width, height, format, J.Surface.to_qoi(image))
def loaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}
def loaded.emit(id: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  observed(id, "loaded", loaded(result))
def saved(id: String, path: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "Accepted QOI write rejected")
    case Done{_}: IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_qoi(path), loaded.emit(id))
def save(id: String, +path: String, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "QOI write source rejected")
    case Some{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_qoi(image, path), saved(id, path))
def rejected.pure(result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Maybe<J.Surface>:
  match result:
    case Fail{Tuple{image, J.UnsupportedFormat{}}}: Some{image}
    case _: None{}
def rejected.twice(result: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match result:
    case None{}: None{}
    case Some{image}: rejected.pure(J.Surface.to_qoi(image))
def rejected.last(id: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.UnsupportedFormat{}}}: observed(id, "retained", rejected.pure(J.Surface.to_qoi(image)))
    case _: IO.die(Unit, 1, "QOI wrong source error")
def rejected.absent(id: String, absent: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.UnsupportedFormat{}}}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_qoi(image, absent), rejected.last(id))
    case _: IO.die(Unit, 1, "QOI wrong source error")
def rejected.directory(id: String, absent: String, directory: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.UnsupportedFormat{}}}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_qoi(image, directory), rejected.absent(id, absent))
    case _: IO.die(Unit, 1, "QOI wrong source error")
def rejected.missing(id: String, absent: String, missing: String, directory: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.UnsupportedFormat{}}}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_qoi(image, missing), rejected.directory(id, absent, directory))
    case _: IO.die(Unit, 1, "QOI wrong source error")
def rejected.second(id: String, +path: String, missing: String, directory: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.UnsupportedFormat{}}}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_qoi(image, path), rejected.missing(id, path ++ ".absent.qoi", missing, directory))
    case _: IO.die(Unit, 1, "QOI wrong source error")
def reject(id: String, +path: String, missing: String, directory: String, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "QOI rejected owner lost")
    case Some{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_qoi(image, path), rejected.second(id, path ++ ".qoi", missing, directory))
def process.selected(accepted: Bool, +id: String, +width: U32, +height: U32, +format: U32, +mode: U32, path: String, missing: String, directory: String, +bytes: +List<U32>) -> IO(Unit):
  match accepted:
    case True{}:
      do IO<Unit>:
        pure(id, width, height, format, owner(mode, width, height, format, bytes))
        save(id, path, owner(mode, width, height, format, bytes))
    case False{}: reject(id, path, missing, directory, rejected.twice(rejected.twice(owner(mode, width, height, format, bytes))))
def process(+id: String, +width: U32, +height: U32, +format: U32, +mode: U32, path: String, missing: String, directory: String, +bytes: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    observed(id, "source", owner(mode, width, height, format, bytes))
    process.selected(U32.is_eq(format, 4) || U32.is_eq(format, 7), id, width, height, format, mode, path, missing, directory, bytes)
def payload(id: String, width: U32, height: U32, format: U32, mode: U32, path: String, missing: String, directory: String, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "QOI input read failed")
    case Done{bytes}: process(id, width, height, format, mode, path, missing, directory, bytes)
def received(id: String, width: U32, height: U32, format: U32, mode: U32, path: String, missing: String, directory: String, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(id, width, height, format, mode, path, missing, directory, status)
def opened(id: String, width: U32, height: U32, format: U32, mode: U32, size: U32, path: String, missing: String, directory: String, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "QOI input open failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(id, width, height, format, mode, path, missing, directory))
def source.loaded(id: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  observed(id, "source", loaded(result))
def pure.loaded(id: String, width: U32, height: U32, format: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  pure(id, width, height, format, loaded(result))
def save.loaded(id: String, path: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  save(id, path, loaded(result))
'''


def output_path(work,case):
    suffix={0:'.dat',1:'.png',2:'.QoI',3:''}[sum(case['id'].encode())%4] if case['format'] in ACCEPTED else '.dat'
    return work/('candidate-'+case['id']+suffix)


def candidate_program(cases,work):
    body=BEND_PREFIX+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    for c in cases:
        ident=json.dumps(c['id']);origin=c.get('origin');data=c.get('input',c['data']);source=work/(c['id']+('.input.qoi' if 'input' in c else '.raw'));target=output_path(work,c)
        if origin=='load':
            call='J.Surface.load_qoi('+json.dumps(str(source))+')'
            for continuation in (f'source.loaded({ident})',f'pure.loaded({ident}, {c["width"]}, {c["height"]}, {c["format"]})',f'save.loaded({ident}, {json.dumps(str(target))})'):
                body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, {call}, {continuation})\n'
        else:
            mode={'decode':1,'bridge':2}.get(origin,0)
            continuation=f'opened({ident}, {c["width"]}, {c["height"]}, {c["format"]}, {mode}, {len(data)+1}, {json.dumps(str(target))}, {json.dumps(str(work/"missing-parent"/"rejected.dat"))}, {json.dumps(str(work/"directory"))})'
            body+=f'    IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({json.dumps(str(source))}, "r"), {continuation})\n'
    return body


def io_program(work,failure):
    body=BEND_PREFIX+r'''
def direct(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), J.Image.file.write.opened([1]))
def status(+code: U32, message: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FileError{actual_code, actual_message}}: checked(U32.is_gt(code, 0) && U32.is_eq(code, actual_code) && String.eq(message, actual_message))
    case Done{_}: checked(U32.is_eq(code, 0))
    case _: checked(False{})
def write(code: U32, message: String, path: String, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: checked(False{})
    case Some{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_qoi(image, path), status(code, message))
def bytes.eq(actual: List<U32>, expected: +List<U32>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case Con{a, rest} Con{b, tail}: U32.is_eq(a, b) && bytes.eq(rest, tail)
    case _ _: False{}
def retained.exported(format: U32, bytes: +List<U32>, result: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match result:
    case Tuple{Tuple{1, 1}, Tuple{actual, values}}: checked(U32.is_eq(format, actual) && bytes.eq(values, bytes))
    case _: checked(False{})
def retained(format: U32, bytes: +List<U32>, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.UnsupportedFormat{}}}: retained.exported(format, bytes, J.Surface.export(image))
    case _: checked(False{})
def reject.write(+format: U32, +bytes: +List<U32>, path: String, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: checked(False{})
    case Some{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_qoi(image, path), retained(format, bytes))
def loop(n: Nat, +code: U32, +message: String, +path: String) -> IO(Unit):
  match n:
    case 0n: IO.print("{\"iterations\":100,\"accepted_writes\":200,\"rejected_writes\":1800}")
    case 1n+rest:
      do IO<Unit>:
'''
    for fmt in ACCEPTED:body+=f'        write(code, message, path, J.Surface.from_bytes(1, 1, {fmt}, [{", ".join(["17"]*BPP[fmt])}]))\n'
    for fmt in REJECTED:
        values=[0,0,0,128] if fmt==8 else [17]*BPP[fmt];data='['+', '.join(map(str,values))+']'
        for path in (work/'rejected-sentinel.dat',work/'missing-parent'/'rejected.dat',work/'directory'):
            body+=f'        reject.write({fmt}, {data}, {json.dumps(str(path))}, J.Surface.from_bytes(1, 1, {fmt}, {data}))\n'
    body+=r'''        loop(rest, code, message, path)
def baseline(expected: U32, path: String, result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Done{_}:
      do IO<Unit>:
        checked(U32.is_eq(expected, 0))
        loop(100n, 0, "", path)
    case Fail{Tuple{+code, +message}}:
      do IO<Unit>:
        checked(U32.is_eq(code, expected) && Bool.not(String.eq(message, "")))
        loop(100n, code, message, path)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    paths=formatted_export.io_targets(work,failure)
    for path,code in paths:body+=f'    IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, direct({json.dumps(str(path))}), baseline({code}, {json.dumps(str(path))}))\n'
    if not failure:
        body+=f'    write(0, "", {json.dumps(str(work/"repeated.dat"))}, J.Surface.from_bytes(1, 1, 7, [17, 17, 17, 17]))\n'
        body+='    IO.print("{\\\"final_success\\\":true}")\n'
    return body


def verify_io(text,work,failure):
    rows=[strict_json(line) for line in text.splitlines()];count=1 if failure else 3
    marker=dict(iterations=100,accepted_writes=200,rejected_writes=1800)
    if not failure:
        if not rows:raise ValueError('Missing final accepted IO write')
        final=rows.pop()
        if type(final) is not dict or final!=dict(final_success=True) or type(final.get('final_success')) is not bool:raise ValueError('Missing final accepted IO write')
    if len(rows)!=count or any(type(r) is not dict or r!=marker or any(type(v) is not int for v in r.values()) for r in rows):raise ValueError('Incomplete QOI IO controls')
    if (work/'directory'/'sentinel').read_bytes()!=SENTINEL or (work/'rejected-sentinel.dat').read_bytes()!=SENTINEL or (work/'missing-parent').exists():raise ValueError('Rejected/open-error targets changed')
    if failure:
        if (work/'post-open.dat').read_bytes()!=b'':raise ValueError('Post-open failure did not truncate')
    elif decode_qoi((work/'repeated.dat').read_bytes(),dict(width=1,height=1,format=7))['raw']!=[17]*4:raise ValueError('Repeated final write differs')
    return dict(iterations=100,accepted_writes=200*count+(0 if failure else 1),rejected_writes=1800*count,file_descriptor_limit=64,exact_base_code_and_message=True,post_open=failure)


def verify_reference_files(work,cases,rows):
    """Native files: accepted exports equal the emitted bytes; rejected sources leave the sentinel and create nothing."""
    for c,row in zip(cases,rows):
        path=work/('reference-'+c['id']+'.qoi')
        if c['format'] in ACCEPTED:
            if path.read_bytes()!=bytes(row['encoded']):raise ValueError('Real QOI file differs: '+c['id'])
        else:
            if path.read_bytes()!=SENTINEL:raise ValueError('Rejected source touched existing file')
            if (work/('reference-absent-'+c['id']+'.qoi')).exists():raise ValueError('Rejected native source created absent file')


class Qoi:
    """Accepted RGB/RGBA: source, complete file, decoded raw, Surface and reloaded owner; others: retained owner."""
    name, batch = 'qoi', 16
    qualification = (QUALIFY, dict(controls=9, little_endian=True, round_to_nearest=True, signed_char_wrap=True))
    fixtures, reference_program, candidate_program = staticmethod(fixtures), staticmethod(reference_program), staticmethod(candidate_program)
    parse_rows, io_program, verify_io = staticmethod(parse_rows), staticmethod(io_program), staticmethod(verify_io)

    def prepare(self, work, cases):
        shutil.rmtree(work/'missing-parent', ignore_errors=True)
        (work/'directory').mkdir(exist_ok=True);(work/'directory'/'sentinel').write_bytes(SENTINEL)
        (work/'rejected-sentinel.dat').write_bytes(SENTINEL)
        for c in cases:
            (work/(c['id']+'.raw')).write_bytes(bytes(c['data']))
            if 'input' in c:
                if decode_qoi(bytes(c['input']),c,canonical=False)['raw']!=c['data']:raise ProbeFailure('Noncanonical input raw owner differs')
                (work/(c['id']+'.input.qoi')).write_bytes(bytes(c['input']))
            if c['format'] in REJECTED:
                (work/('reference-'+c['id']+'.qoi')).write_bytes(SENTINEL);(work/('reference-absent-'+c['id']+'.qoi')).unlink(missing_ok=True)

    def check_reference(self, cases, rows, work):
        verify_reference_files(work,cases,rows)
        return dict(coverage=coverage(cases,rows))

    def expected_file(self, case, row):
        return row['encoded'] if case['format'] in ACCEPTED else [list(SENTINEL),list(SENTINEL),False]

    def reset(self, work, cases):
        for c in cases:
            path=output_path(work,c);path.write_bytes(SENTINEL)
            if c['format'] in REJECTED:Path(str(path)+'.qoi').write_bytes(SENTINEL);Path(str(path)+'.qoi.absent.qoi').unlink(missing_ok=True)

    def observed(self, work, cases):
        """Accepted: the complete file this lane wrote over the sentinel. Rejected: both sentinels untouched, no absent file."""
        if (work/'missing-parent').exists() or (work/'directory'/'sentinel').read_bytes()!=SENTINEL:raise ProbeFailure('Rejected source touched invalid path')
        read=lambda path:list(path.read_bytes()) if path.is_file() else None
        files=[read(output_path(work,c)) if c['format'] in ACCEPTED else
               [read(output_path(work,c)),read(Path(str(output_path(work,c))+'.qoi')),Path(str(output_path(work,c))+'.qoi.absent.qoi').exists()]
               for c in cases]
        self.reset(work,cases)
        return files

    def reset_io(self, work):
        (work/'post-open.dat').write_bytes(SENTINEL);(work/'repeated.dat').write_bytes(SENTINEL)

    def summary(self, cases, rows):
        return dict(accepted=sum(c['format'] in ACCEPTED for c in cases),rejected=sum(c['format'] in REJECTED for c in cases),
                    encoded_bytes=sum(len(r.get('encoded',[])) for r in rows),decoded_bytes=sum(len(r.get('decoded',[])) for r in rows))


CODEC = Qoi()


def main(argv=None):
    formatted_export.main(CODEC, __doc__, argv)


if __name__=='__main__':main()
