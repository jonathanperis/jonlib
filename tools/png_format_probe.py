#!/usr/bin/env python3
"""Exact original-format PNG memory decoding against pinned raylib.

Only independently admitted complete PNG fixtures reach native code. PNG shares
stb's suffix/content sniffing path: a .png suffix alone proves no PNG identity.
Raw native metadata and every byte are captured before separate normalization.
CPU-1/CPU-2/JavaScript only; no GPU, formatted-file or generic-formatted claim.
"""
import argparse
from functools import partial
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import shlex
import signal
import struct
import subprocess
import sys
import time
import uuid
import zlib

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER
from conformance import BUILD, ROOT, ENV, checkout, source_gate
from png_probe import (fixtures as legacy_fixtures, png, chunk, SIGNATURE, CHANNELS, PASSES)
from reference_environment import ReferenceEnvironment

BATCH_SIZE = 32
SOURCE_BYTE_LIMIT = 196_608
LANES = ('cpu-1', 'cpu-2', 'javascript')
RAW_ROLES = {'raw','factory','owner','raw-roundtrip','alias-PNG'}
IMAGE_ROLES = RAW_ROLES | {'normalized','bridge','surface','dispatch-png','dispatch-PNG','uncontracted','fused'}
FORMATS = {1:1, 2:2, 3:4, 4:7}
MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
ENCODED_LIMIT = 1_048_576
FILTERED_LIMIT = 67_108_864
SEALED = {}

# These source ranges anchor native component selection, palette expansion,
# full-width tRNS, CgBI defaults, and stbi_load's final 16-to-8 high-byte reduction.
SOURCE_RANGES = {
    'src/rtextures.c': [(461,471)],
    'src/external/stb_image.h': [(1190,1203),(1260,1273),(4438,4452),(4910,4994),(5119,5126),(5146,5168),(5210,5234),(5284,5286)],
}
SOURCE_SHA256 = {
    'src/rtextures.c': '90e41879349d58a779c101dbf78e5b5cf8d46241590268a74e6156ad33312e4c',
    'src/external/stb_image.h': '594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3',
}


def validate_reference_sources(root):
    result={}
    for relative,ranges in SOURCE_RANGES.items():
        path=Path(root)/relative;data=path.read_bytes()
        if hashlib.sha256(data).hexdigest()!=SOURCE_SHA256[relative]:raise ValueError('Pinned PNG oracle source differs: '+relative)
        lines=data.splitlines(keepends=True)
        result[relative]=dict(sha256=SOURCE_SHA256[relative],ranges=[dict(first=first,last=last,sha256=hashlib.sha256(b''.join(lines[first-1:last])).hexdigest()) for first,last in ranges])
    return result


def pass_layout(width,height,components,depth,interlace):
    """Independent exact filtered lengths; empty Adam7 passes consume nothing."""
    result=[]
    for x,y,dx,dy in PASSES if interlace else ((0,0,1,1),):
        w=max(0,(width-x+dx-1)//dx);h=max(0,(height-y+dy-1)//dy)
        if w and h:
            row=(w*components*depth+7)//8
            result.append(dict(width=w,height=h,row_bytes=row,filtered_bytes=(row+1)*h))
    return result


def bounded_inflate(stream,raw,expected):
    """Validate native framing while deliberately not validating Adler-32.

    zlib.decompress(stream) would incorrectly reject two preserved native cases:
    missing Adler and wrong Adler. Validate CM/FCHECK/FDICT then feed raw DEFLATE
    to an independent bounded inflater. Stop after expected+1 bytes; no flush()
    or unbounded decompression can allocate a hostile expansion.
    """
    if not raw:
        if len(stream)<2 or stream[0]&15!=8 or (stream[0]*256+stream[1])%31 or stream[1]&32:
            raise ValueError('Unsafe native zlib framing')
        stream=stream[2:]
    try:
        decoder=zlib.decompressobj(-15)
        data=decoder.decompress(stream,expected+1)
    except zlib.error as error:raise ValueError('Unsafe native DEFLATE stream') from error
    if len(data)!=expected or not decoder.eof or decoder.unconsumed_tail:
        raise ValueError('Unsafe native filtered raster length or incomplete DEFLATE')
    return data


def inspect_header(data, *, fixture_budget=True):
    """Independently parse actual bytes before any native invocation.

    No pixel oracle is implemented here. Reconstructed scanline bytes are used
    only to check filter validity and every actual palette index, because stb's
    palette expander ignores its palette-count argument. Native output remains
    the sole broad byte expectation, including transparency and 16-bit narrowing.
    """
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):raise ValueError('Unsafe native byte domain')
    if len(data)>ENCODED_LIMIT:raise ValueError('Unsafe native encoded input size')
    if bytes(data[:8])!=SIGNATURE:raise ValueError('Unsafe native PNG signature')
    values=bytes(data);cursor=8;header=None;palette=0;seen=False;trns=False;raw=False;streams=[];chunks=[]
    while True:
        if cursor+12>len(values):raise ValueError('Incomplete native PNG chunk')
        size=struct.unpack_from('>I',values,cursor)[0];kind=values[cursor+4:cursor+8]
        if size>ENCODED_LIMIT or cursor+12+size>len(values):raise ValueError('Incomplete/oversized native PNG payload')
        payload=values[cursor+8:cursor+8+size];cursor+=12+size;chunks.append(kind.decode('latin1'))
        if kind==b'CgBI':raw=True;continue
        if header is None:
            if kind!=b'IHDR' or size!=13:raise ValueError('Unsafe native first/unique PNG header')
            w,h,depth,color,method,filter_method,interlace=struct.unpack('>IIBBBBB',payload)
            if color not in CHANNELS or depth not in ((1,2,4,8) if color==3 else (1,2,4,8,16) if color==0 else (8,16)) or method or filter_method or interlace not in (0,1):raise ValueError('Unsafe native PNG profile')
            if not 1<=w<=4096 or not 1<=h<=4096:raise ValueError('Unsafe native dimensions')
            if fixture_budget and w*h>MAX_CASE_PIXELS:raise ValueError('Native fixture pixel budget exceeded')
            header=(w,h,depth,color,interlace);continue
        if kind==b'IHDR':raise ValueError('Duplicate native PNG header')
        if kind==b'PLTE':
            if seen or not 0<size<=768 or size%3:raise ValueError('Unsafe native PNG palette')
            palette=size//3
        elif kind==b'tRNS':
            if seen or color not in (0,2,3) or (color==3 and (not palette or size>palette)) or (color!=3 and size!=2*CHANNELS[color]):raise ValueError('Unsafe native PNG transparency')
            trns=True  # Structural and sticky, even empty or followed by PLTE.
        elif kind==b'IDAT':
            if color==3 and not palette:raise ValueError('Missing native PNG palette')
            streams.append(payload);seen=True
        elif kind==b'IEND':
            if size or not seen:raise ValueError('Unsafe native PNG terminator')
            break
        elif not kind[0]&32:raise ValueError('Unknown native critical PNG chunk')
    passes=pass_layout(w,h,CHANNELS[color],depth,interlace)
    expected=sum(p['filtered_bytes'] for p in passes)
    if expected>FILTERED_LIMIT:raise ValueError('Unsafe native filtered capacity')
    raster=bounded_inflate(b''.join(streams),raw,expected)
    at=0;distance=max(1,(CHANNELS[color]*depth+7)//8);maximum_index=None
    for shape in passes:
        stride=shape['row_bytes'];previous=bytearray(stride)
        for _ in range(shape['height']):
            mode=raster[at];at+=1
            if mode>4:raise ValueError('Unsafe native PNG filter')
            row=bytearray(stride)
            for x in range(stride):
                left=row[x-distance] if x>=distance else 0
                up=previous[x];corner=previous[x-distance] if x>=distance else 0
                if mode==0:predict=0
                elif mode==1:predict=left
                elif mode==2:predict=up
                elif mode==3:predict=(left+up)//2
                else:
                    base=left+up-corner;distances=(abs(base-left),abs(base-up),abs(base-corner))
                    predict=(left,up,corner)[distances.index(min(distances))]
                row[x]=(raster[at]+predict)&255;at+=1
            if color==3:
                for x in range(shape['width']):
                    index=(row[x*depth//8]>>(8-depth-(x*depth%8)))&((1<<depth)-1)
                    if index>=palette:raise ValueError('Unsafe native undefined PNG palette index')
                    maximum_index=index if maximum_index is None else max(maximum_index,index)
            previous=row
    if at!=expected:raise ValueError('Incomplete native pass consumption')
    channels=(4 if trns else 3) if color==3 else CHANNELS[color]+int(trns)
    return dict(width=w,height=h,channels=channels,depth=depth,color=color,interlace=interlace,
                palette_count=palette,has_transparency=trns,cgbi=raw,filtered_bytes=expected,
                passes=passes,maximum_index=maximum_index,tail_bytes=len(values)-cursor,chunks=chunks)


def validate_cases(cases):
    if type(cases) is not list or not cases:raise ValueError('Empty native PNG cases')
    ids=set();total=0
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','width','height','channels','extended'}:raise ValueError('Native case schema differs')
        name=case['id']
        if type(name) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',name) is None or name in ids:raise ValueError('Invalid/duplicate native fixture ID')
        ids.add(name)
        if type(case['extended']) is not bool:raise ValueError('Invalid alias selector')
        observed=inspect_header(case['bytes'])
        if any(type(case[k]) is not int or case[k]!=observed[k] for k in ('width','height','channels')):raise ValueError('Native declared metadata/header differs')
        total+=len(case['bytes'])
    if total>MAX_TOTAL_BYTES:raise ValueError('Unsafe native aggregate fixture size')


def fixtures():
    result=[]
    def add(name,data,extended=False):
        data=list(data);observed=inspect_header(data)
        result.append(dict(id=name,bytes=data,width=observed['width'],height=observed['height'],channels=observed['channels'],extended=extended))
    for case in legacy_fixtures()[0]:add('legacy-'+case['id'],case['bytes'])
    palette=bytes([17,63,201,71,113,159,227,239,251])
    for name,alpha in [('empty',b''),('opaque',b'\xff\xff\xff'),('unused-transparent',b'\xff\xff\0')]:
        add('palette-trns-'+name,png(2,1,3,b'\0\1',palette=palette,transparency=alpha),True)
    add('palette-trns-repeated',png(3,1,3,b'\0\1\2',palette=palette,transparency=b'\0\x80',extra=[(b'tRNS',b'\xff')]),True)
    for name,alpha in [('empty',b''),('transparent',b'\0\x80')]:
        add('palette-trns-plte-sticky-'+name,png(3,1,3,b'\0\1\2',palette=palette,transparency=alpha,extra=[(b'PLTE',palette[::-1])]),True)
    add('palette-plte-trns-plte-trns',png(3,1,3,b'\0\1\2',palette=palette,transparency=b'\0',extra=[(b'PLTE',palette[::-1]),(b'tRNS',b'\xff\x7f')]),True)
    for color in (0,2):
        channels=CHANNELS[color]
        add('trns-no-match-'+str(color),png(3,1,color,bytes([7,11,13][:channels])*3,transparency=b'\0\x7f'*channels),True)
        samples=[0x1234,0x1235,0x12ff] if color==0 else [0x1234,0x5678,0x9abc,0x1234,0x5678,0x9abd,0x1235,0x5678,0x9abc]
        key=samples[:channels]
        add('trns-full16-'+str(color),png(3,1,color,struct.pack('>'+'H'*len(samples),*samples),depth=16,transparency=struct.pack('>'+'H'*channels,*key)),True)
    for color in (0,4,2,6):
        channels=CHANNELS[color]
        for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63),('byte-ramp',16,16)]:
            raw=bytes((i*61+(i//channels)*17+13)&255 for i in range(w*h*channels))
            add(f'c{channels}-{name}',png(w,h,color,raw,(4,3,2,1,0)),name in ('single','padded','byte-ramp'))
    add('cgbi-default-bgr-premultiplied',png(3,1,6,bytes([3,8,12,16,11,22,33,0,55,30,10,127]),cgbi=True),True)
    base=list(png(1,1,0,b'\x7f'))
    add('encoded-exact-cap',base+[0]*(ENCODED_LIMIT-len(base)),True)
    validate_cases(result);return result


def validate_controls(cases):
    if type(cases) is not list:raise ValueError('Invalid checked PNG controls')
    ids=set()
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','error'}:raise ValueError('Checked control schema differs')
        if type(case['id']) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',case['id']) is None or case['id'] in ids:raise ValueError('Invalid/duplicate control ID')
        ids.add(case['id'])
        if type(case['error']) is not int or case['error'] not in range(5):raise ValueError('Invalid checked error')
        if type(case['bytes']) is not list or any(type(v) is not int or not 0<=v<=4294967295 for v in case['bytes']):raise ValueError('Invalid checked byte domain')
        try:inspect_header(case['bytes'],fixture_budget=False)
        except ValueError:pass
        else:raise ValueError('Accepted native input mislabeled as control')


def controls():
    result=[dict(c,id='legacy-'+c['id']) for c in legacy_fixtures()[1]]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    base=png(1,1,6,b'\1\2\3\4')
    for n in range(len(base)):add('prefix-'+str(n),base[:n],0)
    for n in range(len(base)):
        values=list(base);values[n]=256;add('invalid-byte-'+str(n),values,1)
    for name,data in [('qoi',b'qoif'+bytes(30)),('bmp',b'BM'+bytes(60)),('pnm',b'P6\n1 1\n255\n\1\2\3'),('tga',bytes(30)),('gif',b'GIF89a'+bytes(40))]:add('non-png-'+name,data,0)
    for color,depth,width,height,error in [(6,8,4095,4096,4),(6,8,4096,4096,2),(6,16,2047,4096,4),(6,16,2048,4096,2)]:
        for interlace in (0,1):
            header=struct.pack('>IIBBBBB',width,height,depth,color,0,0,interlace)
            expected=sum(p['filtered_bytes'] for p in pass_layout(width,height,CHANNELS[color],depth,interlace))
            add(f'filtered-boundary-{depth}-{width}-{interlace}',SIGNATURE+chunk(b'IHDR',header)+chunk(b'IDAT',b'bad')+chunk(b'IEND',b''),2 if expected>FILTERED_LIMIT else 4)
    palette=b'\1\2\3'
    for depth in (1,2,4,8):
        for interlace in (False,True):add(f'undefined-index-{depth}-{interlace}',png(9,9,3,bytes([1])*81,depth=depth,interlaced=interlace,palette=palette),4)
    add('bad-byte-before-header',[0,256],1)
    add('bad-byte-before-size',list(SIGNATURE+chunk(b'IHDR',struct.pack('>IIBBBBB',0,1,8,6,0,0,0)))+[256],1)
    add('bad-header-before-size',SIGNATURE+chunk(b'IHDR',struct.pack('>IIBBBBB',0,1,3,6,0,0,0))+base[33:],0)
    add('size-before-stream',SIGNATURE+chunk(b'IHDR',struct.pack('>IIBBBBB',0,1,8,6,0,0,0))+base[33:],2)
    # input.count stops at its first byte/size error. A bad byte at cap+1
    # wins that byte's size check; later bad bytes cannot replace an earlier cap.
    padded=list(base)+[0]*(ENCODED_LIMIT-len(base))
    add('encoded-cap-plus-one',padded+[0],2)
    add('invalid-byte-at-cap-plus-one',padded+[256],1)
    add('size-before-later-invalid-byte',padded+[0,256],2)
    add('invalid-byte-before-cap',[256]+[0]*ENCODED_LIMIT,1)
    validate_controls(result);return result


def strict_json(text):
    def unique(pairs):
        out={}
        for key,value in pairs:
            if key in out:raise ValueError('Duplicate JSON key')
            out[key]=value
        return out
    def nonfinite(value):raise ValueError('Nonfinite JSON number: '+value)
    def finite(value):
        result=float(value)
        if not math.isfinite(result):raise ValueError('Nonfinite JSON number: '+value)
        return result
    return json.loads(text,object_pairs_hook=unique,parse_constant=nonfinite,parse_float=finite)


def meta(case,role):
    if role not in IMAGE_ROLES:raise ValueError('Unknown PNG image role')
    return dict(id=case['id'],role=role,width=case['width'],height=case['height'],mipmaps=1,
                format=FORMATS[case['channels']] if role in RAW_ROLES else 7)


def parse_rows(text, actions):
    if not actions:raise ValueError('Empty PNG observation batch')
    lines=text.splitlines();cursor=0;rows=[]
    for action in actions:
        case,role=action['case'],action['role']
        if cursor>=len(lines):raise ValueError('Missing PNG record')
        row=strict_json(lines[cursor]);cursor+=1
        if role in ('formatted-error','surface-error'):
            expected=dict(id=case['id'],role=role,error=case['error'])
        else:expected=meta(case,role)
        if type(row) is not dict or row!=expected or any(type(row.get(k)) is not type(v) for k,v in expected.items()):
            raise ValueError(f'PNG metadata/order/type differs: {case["id"]}/{role}: {row!r}')
        if role not in ('formatted-error','surface-error'):
            output=[];short=False
            while cursor<len(lines):
                chunk=strict_json(lines[cursor]);cursor+=1
                if chunk=='end':break
                if type(chunk) is not list or not 1<=len(chunk)<=256 or short or any(type(v) is not int or not 0<=v<=255 for v in chunk):raise ValueError('Malformed PNG byte chunk')
                short=len(chunk)<256;output.extend(chunk)
            else:raise ValueError('Unterminated PNG bytes')
            if len(output)!=case['width']*case['height']*{1:1,2:2,4:3,7:4}[row['format']]:raise ValueError('PNG byte count differs')
            row=dict(row,bytes=output)
        rows.append(row)
    if cursor!=len(lines):raise ValueError('Extra PNG records')
    return rows


BEND_PREFIX=r'''import Base
import ../../../jonlib.bend as J
def repeat_input(n: Nat, +value: U32, values: +List<U32>) -> +List<U32>:
  match n:
    case 0n: values
    case 1n+rest: repeat_input(rest, value, Con{value, values})
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
  (pixels, (U32.is_eq(format, 1) && (word <= 255 : U32)) || (U32.is_eq(format, 2) && (word <= 65535 : U32)) || (U32.is_eq(format, 4) && (word <= 16777215 : U32)) || U32.is_eq(format, 7))
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
def roundtrip.bytes(values: List<U32>, bytes: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: List.reverse(&2, U32, bytes)
    case Con{head, tail}: roundtrip.bytes(tail, Con{head, bytes})
def roundtrip.exported(data: (U32 & U32) & (U32 & List<U32>)) -> Maybe<J.Image.Formatted>:
  ((width, height), (format, bytes)) = data
  J.Image.Formatted.from_bytes(width, height, format, roundtrip.bytes(bytes, Nil{}))
def roundtrip(result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: roundtrip.exported(J.Image.Formatted.export(image))
def emit(id: String, role: String, data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  do IO<Unit>:
    # Formatted owners are single-mip by contract; there is no mipmaps field.
    IO.print("{\"id\":\"" ++ id ++ "\",\"role\":\"" ++ role ++ "\",\"width\":" ++ U32.show(width) ++ ",\"height\":" ++ U32.show(height) ++ ",\"mipmaps\":1,\"format\":" ++ U32.show(format) ++ "}")
    emit_bytes(~&1, bytes)
def observed(id: String, role: String, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid PNG or owner invariant rejected")
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
#include <string.h>
static int little_endian(void){uint16_t word=1;return *(unsigned char *)&word==1;}
static void emit(const unsigned char *p,int n){for(int start=0;start<n;start+=256){putchar('[');for(int i=start;i<n&&i<start+256;i++)printf("%s%u",i==start?"":",",p[i]);puts("]");}puts("\"end\"");}
static void observed(const char *id,const char *role,Image image){
  printf("{\"id\":\"%s\",\"role\":\"%s\",\"width\":%d,\"height\":%d,\"mipmaps\":%d,\"format\":%d}\n",id,role,image.width,image.height,image.mipmaps,image.format);
  emit(image.data,GetPixelDataSize(image.width,image.height,image.format));
}
'''
def qualification_program():
    # Tiny fixed vectors qualify all four native formats and decisive routing.
    # Broad fixture output is never derived from Python expected pixels.
    palette=b'\x11\x3f\xc9\x47\x71\x9f'
    vectors=[('gray',png(1,1,0,b'\x7f'),1,[127]),
             ('gray-alpha',png(1,1,4,b'\x11\x80'),2,[17,128]),
             ('rgb',png(1,1,2,b'\1\2\3'),4,[1,2,3]),
             ('rgba',png(1,1,6,b'\1\2\3\x80'),7,[1,2,3,128]),
             ('palette-opaque',png(1,1,3,b'\0',palette=palette),4,[17,63,201]),
             ('palette-empty-trns',png(1,1,3,b'\0',palette=palette,transparency=b''),7,[17,63,201,255]),
             ('palette-allopaque-trns',png(1,1,3,b'\0',palette=palette,transparency=b'\xff\xff'),7,[17,63,201,255]),
             ('palette-plte-sticky',png(1,1,3,b'\0',palette=palette,transparency=b'\0',extra=[(b'PLTE',palette)]),7,[17,63,201,255]),
             ('gray-trns-no-match',png(1,1,0,b'\x11',transparency=b'\0\x7f'),2,[17,255]),
             ('gray-full16-key',png(1,1,0,b'\x12\x35',depth=16,transparency=b'\x12\x34'),2,[18,255]),
             ('alpha-high16',png(1,1,4,b'\x12\x34\0\xff',depth=16),2,[18,0]),
             ('cgbi-default',png(1,1,6,b'\3\x08\x0c\x10',cgbi=True),7,[3,8,12,16])]
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for name,data,fmt,expected in vectors:
        inspect_header(list(data))
        lines+=['/* '+name+' */ {const unsigned char data[]={'+','.join(map(str,data))+'};',
                'Image image=LoadImageFromMemory(".png",data,sizeof(data));if(!image.data)return 11;',
                f'if(image.width!=1||image.height!=1||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(1,1,image.format)!={len(expected)}){{UnloadImage(image);return 12;}}',
                'const unsigned char *p=image.data;if('+ '||'.join(f'p[{i}]!={v}' for i,v in enumerate(expected))+'){UnloadImage(image);return 13;}UnloadImage(image);}' ]
    row=json.dumps(QUALIFICATION,separators=(',',':'))
    return '\n'.join(lines+['puts('+json.dumps(row)+');return 0;}'])+'\n'


QUALIFICATION=dict(little_endian=True,png_enabled=True,structural_channels=True,
                   full_width_transparency=True,cgbi_defaults=True,formats=[1,2,4,7])
QUALIFY=qualification_program()


def qualification(text):
    result=strict_json(text)
    if type(result) is not dict or result!=QUALIFICATION or any(type(result[k]) is not type(v) for k,v in QUALIFICATION.items()) or any(type(v) is not int for v in result['formats']):raise ValueError('Native PNG qualification differs')
    return result


def compact_segments(data):
    """Lossless runs keep exact-cap fixture source small; bytes stay in inputs.json."""
    result=[];literal=[];at=0
    while at<len(data):
        end=at+1
        while end<len(data) and data[end]==data[at]:end+=1
        if end-at>=256:
            if literal:result.append(('literal',literal));literal=[]
            result.append(('repeat',(data[at],end-at)))
        else:literal.extend(data[at:end])
        at=end
    if literal:result.append(('literal',literal))
    return result


def input_expression(data):
    segments=compact_segments(data)
    if not any(kind=='repeat' for kind,_ in segments):return bend_bytes(data)
    expressions=[bend_bytes(values) if kind=='literal' else f'repeat_input({values[1]}n, {values[0]}, Nil{{}})' for kind,values in segments]
    return 'input_bytes(['+','.join(expressions)+'], Nil{})'


def native_input(data):
    segments=compact_segments(data)
    if not any(kind=='repeat' for kind,_ in segments):return 'const unsigned char data[]={'+','.join(map(str,data))+'};',''
    lines=[f'unsigned char *data=malloc({len(data)});if(!data)return 20;'];at=0
    for index,(kind,values) in enumerate(segments):
        if kind=='repeat':
            value,count=values;lines.append(f'memset(data+{at},{value},{count});');at+=count
        else:
            lines.append('const unsigned char part'+str(index)+'[]={'+','.join(map(str,values))+'};')
            lines.append(f'memcpy(data+{at},part{index},sizeof(part{index}));');at+=len(values)
    if at!=len(data):raise ValueError('Compact native input length differs')
    return '\n'.join(lines),'free(data);'


def native_actions(cases):
    return [dict(case=c,role=role) for c in cases for role in ('raw','normalized',*(('alias-PNG',) if c['extended'] else ()))]


def reference_program(cases):
    validate_cases(cases)
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        fmt=FORMATS[c['channels']];raw_size=c['width']*c['height']*c['channels']
        declaration,cleanup=native_input(c['bytes'])
        lines+=['{'+declaration,
                f'Image image=LoadImageFromMemory(".png",data,{len(c["bytes"])});if(!image.data)return 2;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 3;}}',
                f'observed({json.dumps(c["id"])},"raw",image);',
                'ImageFormat(&image,7);if(!image.data)return 4;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!=7||GetPixelDataSize(image.width,image.height,image.format)!={c["width"]*c["height"]*4}){{UnloadImage(image);return 5;}}',
                f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);']
        if c['extended']:
            lines+=[f'image=LoadImageFromMemory(".PNG",data,{len(c["bytes"])});if(!image.data)return 6;',
                    f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 7;}}',
                    f'observed({json.dumps(c["id"])},"alias-PNG",image);UnloadImage(image);']
        lines+=[cleanup+'}']
    return '\n'.join(lines+['return 0;}'])+'\n'


def native_partition_entry(cases,start,count,program):
    selected=cases[start:start+count];actions=native_actions(selected)
    return dict(start=start,count=count,observations=len(actions),source_bytes=len(program),
                source_sha256=hashlib.sha256(program).hexdigest(),
                cases_sha256=hashlib.sha256(json.dumps(selected,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
                compared_bytes=sum(a['case']['width']*a['case']['height']*(a['case']['channels'] if a['role'] in RAW_ROLES else 4) for a in actions))


def validate_native_partitions(cases,partitions):
    validate_cases(cases)
    if type(partitions) is not list or not partitions:raise ValueError('Empty native PNG partition plan')
    cursor=0
    for part in partitions:
        if type(part) is not dict or set(part)!={'start','count','observations','source_bytes','source_sha256','cases_sha256','compared_bytes'}:raise ValueError('Native PNG partition schema differs')
        if any(type(part[k]) is not int for k in ('start','count','observations','source_bytes','compared_bytes')):raise ValueError('Native PNG partition integer types differ')
        if part['start']!=cursor or part['count']<1 or cursor+part['count']>len(cases) or not 1<=part['observations']<=BATCH_SIZE or not 0<part['source_bytes']<=SOURCE_BYTE_LIMIT:raise ValueError('Native PNG partition order or budget differs')
        program=reference_program(cases[cursor:cursor+part['count']]).encode()
        if part!=native_partition_entry(cases,cursor,part['count'],program):raise ValueError('Native PNG partition source/input identity differs')
        cursor+=part['count']
    if cursor!=len(cases):raise ValueError('Incomplete native PNG partition coverage')


def plan_native_partitions(cases):
    validate_cases(cases);plan=[];start=0
    while start<len(cases):
        chosen=None
        for count in range(1,min(BATCH_SIZE,len(cases)-start)+1):
            selected=cases[start:start+count]
            if len(native_actions(selected))>BATCH_SIZE:break
            program=reference_program(selected).encode()
            if not program or len(program)>SOURCE_BYTE_LIMIT:
                if count==1:raise ValueError('Native PNG singleton source budget exceeded')
                break
            chosen=native_partition_entry(cases,start,count,program)
        if chosen is None:raise ValueError('Empty native PNG partition')
        plan.append(chosen);start+=chosen['count']
    validate_native_partitions(cases,plan);return plan


def finish_native(cases,partitions,batches):
    validate_native_partitions(cases,partitions)
    if type(batches) is not list or len(batches)!=len(partitions):raise ValueError('Native PNG batch count differs')
    for batch,part in zip(batches,partitions):
        if type(batch) is not dict or set(batch)!={*part,'bytes','passed','output_sha256'}:raise ValueError('Native PNG batch schema differs')
        if any(type(batch[k]) is not type(v) or batch[k]!=v for k,v in part.items()) or batch['passed'] is not True:raise ValueError('Native PNG batch partition differs')
        if type(batch['bytes']) is not int or batch['bytes']!=part['compared_bytes'] or type(batch['output_sha256']) is not str or re.fullmatch('[0-9a-f]{64}',batch['output_sha256']) is None:raise ValueError('Native PNG byte coverage/output digest differs')


def candidate_actions(cases,invalid,rows):
    validate_cases(cases);validate_controls(invalid)
    if {c['id'] for c in cases}&{c['id'] for c in invalid}:raise ValueError('PNG accepted/control IDs overlap')
    # Revalidate full native rows even when called outside the CLI parser.
    framed=[]
    for row in rows:
        if type(row) is not dict or 'bytes' not in row or type(row['bytes']) is not list:raise ValueError('Incomplete native observation')
        framed.append(json.dumps({k:v for k,v in row.items() if k!='bytes'}))
        framed.extend(json.dumps(row['bytes'][i:i+256]) for i in range(0,len(row['bytes']),256));framed.append('"end"')
    rows=parse_rows('\n'.join(framed),native_actions(cases))
    reference={};cursor=0
    for c in cases:
        raw,normal=rows[cursor:cursor+2];cursor+=2
        if c['extended']:
            if rows[cursor]!=dict(raw,role='alias-PNG'):raise ValueError('Native PNG alias bytes differ')
            cursor+=1
        reference[c['id']]=(raw,normal)
    if cursor!=len(rows):raise ValueError('Native PNG reference count differs')
    actions=[]
    for c in cases:
        raw,normal=reference[c['id']]
        for role in ('raw','bridge','surface','factory','owner','raw-roundtrip',*(('dispatch-png','dispatch-PNG','uncontracted','fused') if c['extended'] else ())):
            expected=dict(raw if role in RAW_ROLES else normal,role=role)
            actions.append(dict(case=c,role=role,expected=expected,normalized=normal['bytes']))
    for c in invalid:
        for mode in ('formatted','surface'):
            role=mode+'-error';actions.append(dict(case=c,role=role,expected=dict(id=c['id'],role=role,error=c['error'])))
    return actions,reference


def candidate_program(actions):
    lines=[BEND_PREFIX.replace('import ../../../jonlib.bend as J','import '+str(ROOT/'jonlib.bend')+' as J').replace('def reverse_into(',BEND_EMITTER+'def reverse_into(',1),'def main() -> IO(Unit):']
    bindings={};bound_cases={}
    for action in actions:
        if action.get('role') not in ('raw','bridge','surface','factory','owner','raw-roundtrip','dispatch-png','dispatch-PNG','uncontracted','fused','formatted-error','surface-error'):raise ValueError('Unknown PNG candidate role')
        c=action['case']
        if c['id'] in bound_cases and c!=bound_cases[c['id']]:raise ValueError('PNG action case identity differs')
        bound_cases[c['id']]=c
        if c['id'] not in bindings:
            name='input'+str(len(bindings));bindings[c['id']]=name
            lines.append(f'  +{name} = {{{input_expression(c["bytes"])} : +List<U32>}}')
    lines.append('  do IO<Unit>:')
    for action in actions:
        c=action['case'];role=action['role'];data=bindings[c['id']];ident=json.dumps(c['id'])
        decode=f'decoded(J.Image.Formatted.decode_png({data}))'
        if role.endswith('-error'):
            mode=role.split('-')[0];call='J.Image.Formatted' if mode=='formatted' else 'J.Surface'
            lines.append(f'    emit.error({ident}, {json.dumps(role)}, {mode}.error({call}.decode_png({data})))');continue
        if role=='raw':image=decode
        elif role=='bridge':image=f'bridge({decode})'
        elif role=='raw-roundtrip':image=f'roundtrip({decode})'
        elif role=='surface':image=f'surface(J.Surface.decode_png({data}))'
        elif role.startswith('dispatch-'):image=f'surface(J.Surface.decode_image({json.dumps("."+role.split("-")[1])}, {data}))'
        elif role in ('uncontracted','fused'):image=f'surface(J.Surface.decode_image_for(J.{"UncontractedDecode" if role=="uncontracted" else "FusedDecode"}{{}}, ".PNG", {data}))'
        elif role=='factory':image=f'J.Image.Formatted.from_bytes({c["width"]}, {c["height"]}, {FORMATS[c["channels"]]}, {bend_bytes(action["expected"]["bytes"])})'
        elif role=='owner':
            normal=action['normalized'];first=int.from_bytes(bytes(normal[:4]),'big');last=int.from_bytes(bytes(normal[-4:]),'big')
            image=f'owner({decode}, {c["width"]}, {c["height"]}, {first}, {last})'
        else:raise ValueError('Unknown PNG observation')
        lines.append(f'    observed({ident}, {json.dumps(role)}, {image})')
    return '\n'.join(lines)+'\n'


def differences(expected,actual):
    if len(expected)!=len(actual):raise ValueError('PNG comparison count differs')
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
    if path in SEALED and SEALED[path]!=observed:raise ValueError('Sealed PNG artifact drift: '+path)
    SEALED[path]=observed


def verify_sealed():
    for path,expected in SEALED.items():
        if not Path(path).is_file() or digest(path)!=expected:raise ValueError('Sealed PNG artifact drift: '+path)


PROCESS_CLEANUP_SECONDS = 5


def run_process_group(command, *, cwd, env, timeout):
    """Bound the spawned POSIX group, then reap its direct child.

    Only this new session's PGID is signalled. Grandchildren that keep inherited
    pipes open cannot turn timeout cleanup into an unbounded communicate().
    The cleanup budget is separate from, and never extends, the work timeout.
    """
    if os.name!='posix':raise OSError('PNG process-group profile requires POSIX')
    process=subprocess.Popen(command,cwd=cwd,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    stdout=stderr='';failed=None
    receipt=dict(process_group_owned=True,process_group_id=process.pid,cleanup_timeout_seconds=PROCESS_CLEANUP_SECONDS)
    try:
        stdout,stderr=process.communicate(timeout=timeout)
    except BaseException as error:
        failed=error
        if isinstance(error,subprocess.TimeoutExpired):stdout,stderr=error.stdout or '',error.stderr or ''
    cleanup_started=time.monotonic();deadline=cleanup_started+PROCESS_CLEANUP_SECONDS
    try:
        try:
            os.killpg(process.pid,signal.SIGKILL);receipt['process_group_cleanup']='SIGKILL'
        except ProcessLookupError:receipt['process_group_cleanup']='already-exited'
        stdout,stderr=process.communicate(timeout=max(0,deadline-time.monotonic()))
    except BaseException as error:
        receipt['cleanup_error']=type(error).__name__+': '+str(error)
        if isinstance(error,subprocess.TimeoutExpired):stdout,stderr=error.stdout or stdout,error.stderr or stderr
        if failed is None:failed=error
        # Closing our pipe readers cannot signal or wait on an unrelated group.
        for pipe in (process.stdout,process.stderr):
            if pipe is not None:pipe.close()
        try:process.wait(timeout=max(0,deadline-time.monotonic()))
        except BaseException as reap_error:
            receipt['reap_error']=type(reap_error).__name__+': '+str(reap_error)
            if failed is None:failed=reap_error
    receipt.update(leader_reaped=process.returncode is not None,cleanup_elapsed_seconds=round(time.monotonic()-cleanup_started,3))
    if failed is not None:
        failed.process_group_receipt=receipt;failed.process_returncode=process.returncode
        failed.process_stdout=stdout;failed.process_stderr=stderr
        raise failed
    result=subprocess.CompletedProcess(command,process.returncode,stdout,stderr);result.process_group_receipt=receipt
    return result


def record_run(command,work,label,*,timeout=600,environment=None,receipt=None,require_output=False):
    verify_sealed();command=list(map(str,command))
    outputs=[Path(command[i+1]) for i,arg in enumerate(command[:-1]) if arg=='-o']
    for arg in command:
        path=Path(arg)
        if path.is_file() and path not in outputs:seal(path)
    for path in outputs:path.unlink(missing_ok=True)
    for ext in ('stdout','stderr','command.json'):(work/(label+'.'+ext)).unlink(missing_ok=True)
    failed=None;started=time.monotonic();run_receipt=dict(command=command,reference_environment=receipt,timeout_seconds=timeout)
    try:
        proc=run_process_group(command,cwd=ROOT,env=ENV if environment is None else environment,timeout=timeout)
        stdout,stderr=proc.stdout,proc.stderr;run_receipt.update(exit_code=proc.returncode,**getattr(proc,'process_group_receipt',{}))
    except BaseException as error:
        failed=error
        stdout=getattr(error,'process_stdout',getattr(error,'stdout','')) or ''
        stderr=getattr(error,'process_stderr',getattr(error,'stderr',str(error))) or ''
        run_receipt.update(exit_code=getattr(error,'process_returncode',None),**getattr(error,'process_group_receipt',dict(process_group_owned=False)))
        if isinstance(error,subprocess.TimeoutExpired):run_receipt.update(timed_out=True,timeout=timeout)
        else:run_receipt['communication_error' if run_receipt.get('process_group_owned') else 'startup_error']=type(error).__name__
    run_receipt['elapsed_seconds']=round(time.monotonic()-started,6)
    artifacts={}
    for ext,value in [('stdout',stdout),('stderr',stderr)]:
        path=work/(label+'.'+ext);path.write_text(value.decode(errors='replace') if isinstance(value,bytes) else value);seal(path);artifacts[str(path)]=digest(path)
    # Retain partial/empty compiler output hashes even on a failure or timeout.
    for path in outputs:
        if path.is_file():seal(path);artifacts[str(path)]=digest(path)
    run_receipt['artifacts']=artifacts
    path=work/(label+'.command.json');path.write_text(json.dumps(run_receipt,indent=2)+'\n');seal(path)
    if failed is not None:
        if not isinstance(failed,(subprocess.TimeoutExpired,OSError)):raise failed
        raise ValueError('PNG child '+('timed out' if isinstance(failed,subprocess.TimeoutExpired) else 'could not start or communicate')+': '+label) from failed
    if proc.returncode:raise ValueError(f'{label} exited {proc.returncode}: {proc.stdout[-1000:]}{proc.stderr[-2500:]}')
    if require_output and not proc.stdout.strip():raise ValueError('Process output missing: '+label)
    if any(not p.is_file() or p.stat().st_size==0 for p in outputs):raise ValueError('Compiler output missing')
    return proc.stdout


def tracked_sources(args):
    paths=[ROOT/p for p in ('tools/png_format_probe.py','tests/test_png_format_harness.py','tools/png_probe.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','toolchain.json','LAWS.bend','PROOF.bend')]
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
    return result or [BUILD/'png-format-probe']


def admit_directories(argv):
    paths=report_directories(argv)
    for path in dict.fromkeys(p.resolve() for p in paths):
        path.mkdir(parents=True,exist_ok=True);(path/'results.json').write_text('{"passed":false,"phase":"argument-validation"}\n')
    return paths[-1].resolve()


def validate_native_config(cache,flags):
    required={'PLATFORM':'Memory','CMAKE_BUILD_TYPE':'Release','CUSTOMIZE_BUILD':'ON','SUPPORT_FILEFORMAT_PNG':'ON','SUPPORT_MODULE_RAUDIO':'OFF','BUILD_EXAMPLES':'OFF','USE_EXTERNAL_GLFW':'OFF'}
    pairs=re.findall(r'^([A-Za-z_][A-Za-z0-9_]*):[^=\n]+=(.*)$',cache,re.M)
    fields=dict(pairs)
    if len(fields)!=len(pairs):raise ValueError('Duplicate native CMake cache field')
    if any(fields.get(k)!=v for k,v in required.items()):raise ValueError('Native PNG cache configuration differs')
    # Ignore makefile comments: a macro spelled only in a comment is not
    # an enabled compiler flag. Reject repeated definitions below, including
    # conflicting -U options and flags injected through C_FLAGS.
    tokens=shlex.split(flags,comments=True)
    definitions=[];index=0
    while index<len(tokens):
        token=tokens[index]
        if token in ('-D','-U'):
            if index+1>=len(tokens):raise ValueError('Incomplete native macro option')
            index+=1;token+=tokens[index]
        if token.startswith(('-D','-U')):definitions.append(token)
        index+=1
    for macro in ('SUPPORT_FILEFORMAT_PNG','EXTERNAL_CONFIG_FLAGS','PLATFORM_MEMORY'):
        selected=[t for t in definitions if t[2:].split('=')[0]==macro]
        if len(selected)!=1 or selected[0] not in ('-D'+macro,'-D'+macro+'=1'):raise ValueError('Actual native macro missing/disabled/ambiguous: '+macro)
    if any(t[2:].split('=')[0].startswith('PLATFORM_') and t[2:].split('=')[0]!='PLATFORM_MEMORY' for t in definitions):raise ValueError('Conflicting native platform macro')
    return required


def native_archive(args,work,record):
    cmake=work/'raylib-build'
    if cmake.exists():raise ValueError('Native build directory must be fresh')
    record(['cmake','-S',args.raylib_source,'-B',cmake,'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DSUPPORT_FILEFORMAT_PNG=ON','-DUSE_EXTERNAL_GLFW=OFF'],work,'configure')
    cache=cmake/'CMakeCache.txt';flags=cmake/'raylib/CMakeFiles/raylib.dir/flags.make'
    config=validate_native_config(cache.read_text(),flags.read_text())
    compilers=list((cmake/'CMakeFiles').glob('*/CMakeCCompiler.cmake'))
    if len(compilers)!=1:raise ValueError('Missing/ambiguous native compiler provenance')
    text=compilers[0].read_text()
    fields={k:re.search(r'set\('+k+r' "([^"\n]+)"\)',text) for k in ('CMAKE_C_COMPILER','CMAKE_C_COMPILER_ID','CMAKE_C_COMPILER_VERSION')}
    if any(v is None for v in fields.values()):raise ValueError('Incomplete native compiler provenance')
    compiler={k:v.group(1) for k,v in fields.items()};compiler_path=Path(compiler['CMAKE_C_COMPILER'])
    if not compiler_path.is_file():raise ValueError('Native archive compiler missing')
    files=[cache,flags,*compilers,compiler_path]
    for path in files:seal(path)
    version=record([compiler_path,'--version'],work,'archive-compiler-version',require_output=True)
    record(['cmake','--build',cmake,'--clean-first','--parallel','4'],work,'native-build')
    validate_native_config(cache.read_text(),flags.read_text());verify_sealed()
    archive=cmake/'raylib/libraylib.a'
    if not archive.is_file() or not archive.stat().st_size:raise ValueError('Native archive missing/empty')
    files.append(archive);seal(archive)
    return archive,dict(mode='fresh-isolated-build',configuration=config,compiler=compiler,compiler_version=version,artifacts={str(p):digest(p) for p in files})


def validate_action_sequence(actions):
    if type(actions) is not list or not actions:raise ValueError('Empty PNG action sequence')
    identities=set()
    for action in actions:
        if type(action) is not dict or type(action.get('case')) is not dict or type(action.get('role')) is not str or type(action.get('expected')) is not dict:raise ValueError('Malformed PNG action')
        identity=(action['case'].get('id'),action['role'])
        if type(identity[0]) is not str or identity in identities:raise ValueError('Invalid/duplicate PNG action identity')
        identities.add(identity)
        if (action['expected'].get('id'),action['expected'].get('role'))!=identity:raise ValueError('PNG action/reference identity differs')
        values=action['expected'].get('bytes',[])
        if type(values) is not list or any(type(v) is not int or not 0<=v<=255 for v in values):raise ValueError('Invalid PNG action reference bytes')


def action_digest(actions):
    return hashlib.sha256(json.dumps(actions,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


def partition_entry(actions,start,count,program):
    selected=actions[start:start+count]
    return dict(start=start,count=count,source_bytes=len(program),source_sha256=hashlib.sha256(program).hexdigest(),
                actions_sha256=action_digest(selected),compared_bytes=sum(len(a['expected'].get('bytes',[])) for a in selected))


def validate_partitions(actions,partitions,source_limit=SOURCE_BYTE_LIMIT):
    """Require an exact ordered, exhaustive plan against regenerated sources."""
    validate_action_sequence(actions)
    if type(source_limit) is not int or not 0<source_limit<=SOURCE_BYTE_LIMIT:raise ValueError('Invalid PNG partition source budget')
    if type(partitions) is not list or not partitions:raise ValueError('Empty PNG partition plan')
    cursor=0
    for entry in partitions:
        if type(entry) is not dict or set(entry)!={'start','count','source_bytes','source_sha256','actions_sha256','compared_bytes'}:raise ValueError('PNG partition schema differs')
        if any(type(entry[k]) is not int for k in ('start','count','source_bytes','compared_bytes')):raise ValueError('PNG partition integer type differs')
        if entry['start']!=cursor or not 1<=entry['count']<=BATCH_SIZE or cursor+entry['count']>len(actions):raise ValueError('Noncontiguous/incomplete PNG partition')
        if not 0<entry['source_bytes']<=source_limit or entry['compared_bytes']<0:raise ValueError('PNG partition budget differs')
        selected=actions[cursor:cursor+entry['count']];program=candidate_program(selected).encode('utf-8')
        expected=partition_entry(actions,cursor,entry['count'],program)
        if entry!=expected or any(type(entry[k]) is not type(v) for k,v in expected.items()):raise ValueError('PNG partition source/action identity differs')
        cursor+=entry['count']
    if cursor!=len(actions):raise ValueError('Incomplete PNG partition coverage')


def plan_partitions(actions,source_limit=SOURCE_BYTE_LIMIT):
    """Greedy complete ordered partitions; only compilation grouping changes.

    Both the 32-action maximum and the exact generated UTF-8 byte budget apply.
    No fixture, role, reference byte, runtime limit or oracle is changed.
    """
    validate_action_sequence(actions)
    if type(source_limit) is not int or not 0<source_limit<=SOURCE_BYTE_LIMIT:raise ValueError('Invalid PNG partition source budget')
    plan=[];start=0
    while start<len(actions):
        selected=None
        for count in range(1,min(BATCH_SIZE,len(actions)-start)+1):
            program=candidate_program(actions[start:start+count]).encode('utf-8')
            if not program:raise ValueError('Empty generated PNG source')
            if len(program)>source_limit:
                if count==1:raise ValueError('PNG singleton exceeds source budget: '+str(start))
                break
            selected=partition_entry(actions,start,count,program)
        if selected is None:raise ValueError('Empty PNG partition')
        plan.append(selected);start+=selected['count']
    validate_partitions(actions,plan,source_limit)
    return plan


def finish_lanes(lanes,actions,partitions):
    validate_partitions(actions,partitions)
    if set(lanes)!=set(LANES):raise ValueError('Missing mandatory PNG lanes/cases')
    expected_bytes=sum(len(a['expected'].get('bytes',[])) for a in actions)
    for lane in LANES:
        if type(lanes[lane]) is not dict or type(lanes[lane].get('batches')) is not list or type(lanes[lane].get('differences')) is not list:raise ValueError('Malformed PNG lane')
        batches=lanes[lane]['batches']
        if len(batches)!=len(partitions):raise ValueError('Incomplete PNG lane partition count')
        observations=compared_bytes=0
        for batch,planned in zip(batches,partitions):
            if type(batch) is not dict or set(batch)!={*planned,'bytes','passed'}:raise ValueError('PNG lane batch schema differs')
            if any(type(batch[k]) is not type(v) or batch[k]!=v for k,v in planned.items()) or batch['passed'] is not True:raise ValueError('PNG lane differs from exact partition plan')
            if type(batch['bytes']) is not int or batch['bytes']!=planned['compared_bytes']:raise ValueError('PNG lane byte coverage differs')
            observations+=batch['count'];compared_bytes+=batch['bytes']
        if observations!=len(actions) or compared_bytes!=expected_bytes or lanes[lane]['differences']:raise ValueError('Incomplete or differing PNG lane: '+lane)
    for lane in LANES:lanes[lane]['passed']=True


def run_probe(argv):
    SEALED.clear();admitted=admit_directories(argv)
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--build-dir',type=Path,default=BUILD/'png-format-probe')
    parser.add_argument('--reference-env',choices=('clean-loader',),default='clean-loader')
    parser.add_argument('--timeout',type=int,default=600)
    args=parser.parse_args(argv);destination=args.build_dir.resolve()
    if destination!=admitted:parser.error('Destination admission differs')
    if args.timeout<=0:parser.error('--timeout must be positive')
    reference_env=ReferenceEnvironment(args.reference_env)
    record=partial(record_run,timeout=args.timeout)
    native_record=partial(record,environment=reference_env.child(),receipt=reference_env.receipt())
    report_path=destination/'results.json';work=destination/('run-'+uuid.uuid4().hex);work.mkdir()
    started=time.monotonic();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if sys.byteorder!='little':raise ValueError('PNG profile requires little endian')
    cases,invalid=fixtures(),controls();validate_cases(cases)
    inputs=work/'inputs.json';inputs.write_text(json.dumps(dict(cases=cases,controls=invalid),sort_keys=True)+'\n');seal(inputs)
    tool_paths={}
    for tool in ('bun','clang','cmake'):
        path=shutil.which(tool)
        if path is None:raise ValueError('Required tool missing: '+tool)
        tool_paths[tool]=str(Path(path).absolute());seal(path)
    tool_realpaths={k:str(Path(p).resolve()) for k,p in tool_paths.items()}
    report=dict(passed=False,oracle_source_ranges=validate_reference_sources(args.raylib_source),profile='native-png-formatted-memory-v1',reconstruction='fresh implementation; no previous runtime evidence reused',run_directory=str(work),toolchain=lock,base_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),host=dict(system=platform.system(),machine=platform.machine()),tool_paths=tool_paths,tool_realpaths=tool_realpaths,sources=tracked_sources(args),reference_environment=reference_env.receipt(),inputs_sha256=digest(inputs),legacy_cases=193,legacy_pixels=31677,legacy_controls=39,native_content_admission='actual PNG signature/chunks/bounded raw-DEFLATE/filter/index scan; .png shares stb sniffing',cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(invalid),native_rejections=0,batch_size=BATCH_SIZE,source_byte_limit=SOURCE_BYTE_LIMIT,partition_strategy='ordered-greedy-generated-source-v1',lanes={lane:dict(passed=False,batches=[],differences=[]) for lane in LANES},candidate_mipmaps='implicit single-mip type contract, not stored/measured',unrun=['GPU/Metal','Windows/browser','big-endian','exact-commit hosted CI','4096x4096 allocation/resource limits','representative performance','formatted file IO','generic formatted/float dispatch','native malformed recovery'])
    for path in [*(ROOT/p for p in report['sources']['library']),*(Path(p) for p in report['sources']['dependencies'])]:seal(path)
    def save():report_path.write_text(json.dumps(report,indent=2)+'\n')
    save();archive,report['native_build']=native_archive(args,work,native_record);save()
    report['bun_version']=record(['bun','--version'],work,'bun-version',require_output=True).strip()
    if report['bun_version']!=lock['bun']['version']:raise ValueError('Bun version differs')
    report['clang_version']=native_record(['clang','--version'],work,'clang-version',require_output=True).strip()
    source=work/'qualification.c';source.write_text(QUALIFY);seal(source);binary=work/'qualification'
    if not 0<len(QUALIFY.encode())<=SOURCE_BYTE_LIMIT:raise ValueError('Qualification source budget differs')
    native_record(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,'qualification-compile')
    report['qualification']=qualification(native_record([binary],work,'qualification',require_output=True));save()
    native_plan=plan_native_partitions(cases);report.update(native_partition_plan=native_plan,native_batches=[]);save()
    native_rows=[];native_outputs=[]
    for index,part in enumerate(native_plan):
        selected=cases[part['start']:part['start']+part['count']]
        program=reference_program(selected).encode()
        if native_partition_entry(cases,part['start'],part['count'],program)!=part:raise ValueError('Native PNG source drift before compilation')
        source=work/f'reference-{index}.c';source.write_bytes(program);seal(source);binary=work/f'reference-{index}'
        native_record(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,f'reference-{index}-compile')
        output=native_record([binary],work,f'reference-{index}',require_output=True)
        rows=parse_rows(output,native_actions(selected));native_rows.extend(rows);native_outputs.append(output)
        report['native_batches'].append(dict(part,bytes=sum(len(row['bytes']) for row in rows),passed=True,output_sha256=hashlib.sha256(output.encode()).hexdigest()));save()
    finish_native(cases,native_plan,report['native_batches'])
    report['reference_sha256']=hashlib.sha256(''.join(native_outputs).encode()).hexdigest();save()
    actions,reference=candidate_actions(cases,invalid,native_rows)
    report.update(native_observations=len(native_rows),native_raw_bytes=sum(len(raw['bytes']) for raw,_ in reference.values()),native_normalized_bytes=sum(len(normal['bytes']) for _,normal in reference.values()),native_all_observed_bytes=sum(len(r['bytes']) for r in native_rows),observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions),raw_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] in ('raw','factory','owner','raw-roundtrip')),normalized_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] not in ('raw','factory','owner','raw-roundtrip')));save()
    partitions=plan_partitions(actions);report.update(partition_plan=partitions,planned_batches=len(partitions));save()
    for index,partition in enumerate(partitions):
        start=partition['start'];selected=actions[start:start+partition['count']]
        program=candidate_program(selected).encode('utf-8')
        if partition_entry(actions,start,len(selected),program)!=partition:raise ValueError('PNG generated partition drift before compilation')
        source=work/f'candidate-{index}.bend';source.write_bytes(program);seal(source)
        binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,f'compile-{index}')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual=parse_rows(record(command,work,f'{lane}-{index}',require_output=True),selected)
            delta=differences([a['expected'] for a in selected],actual)
            report['lanes'][lane]['differences'].extend(delta)
            report['lanes'][lane]['batches'].append(dict(partition,bytes=sum(len(r.get('bytes',[])) for r in actual),passed=not delta));save()
        print(f'PNG batch {index+1}: {len(selected)} observations compared on CPU-1/CPU-2/JavaScript',flush=True)
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    reference_env.assert_receipt(report['reference_environment'])
    if any(shutil.which(k) is None or str(Path(shutil.which(k)).absolute())!=p or str(Path(shutil.which(k)).resolve())!=tool_realpaths[k] for k,p in tool_paths.items()):raise ValueError('Tool executable resolution drift')
    if tracked_sources(args)!=report['sources']:raise ValueError('Source/toolchain/native input drift')
    finish_native(cases,native_plan,report['native_batches']);finish_lanes(report['lanes'],actions,partitions);verify_sealed()
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3),sealed_artifacts=dict(SEALED));save()
    print(f'PASS: {len(cases)} native PNG images, {len(invalid)} checked-only typed controls, {report["compared_bytes_per_lane"]} bytes per lane',flush=True)


def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv)
    try:run_probe(argv)
    except Exception as error:
        # Argument failures already reset every named destination; runtime
        # failures also retain the last partial report and durable seal list.
        path=report_directories(argv)[-1].resolve()/'results.json'
        report=dict(passed=False,phase='runtime-failure')
        try:
            previous=strict_json(path.read_text())
            if type(previous) is dict:report=previous
        except (OSError,ValueError):pass
        report.update(passed=False,failure=dict(type=type(error).__name__,message=str(error)),sealed_artifacts=dict(SEALED))
        try:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
        except OSError as report_error:
            # Keep the original failure even when its receipt cannot be saved.
            if hasattr(error,'add_note'):error.add_note('Could not save failed PNG report: '+str(report_error))
        raise


if __name__=='__main__':main()
