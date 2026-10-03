#!/usr/bin/env python3
"""Exact original-format BMP memory decoding against pinned raylib.

Accepted complete native fixtures only; checked-invalid controls are never sent
native. BMP is explicitly enabled in a fresh isolated native build. Actual native
metadata/raw bytes precede normalization. CPU-1/CPU-2/JS; no GPU or file claim.
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

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER
from conformance import BUILD, ROOT, ENV, checkout, source_gate
from bmp_probe import (fixtures as legacy_fixtures, bitmap, bitmap16, bitfield_bitmap,
                       indexed_bitmap, core_bitmap, core_indexed_bitmap)
from reference_environment import ReferenceEnvironment

BATCH_SIZE = 32
SOURCE_BYTE_LIMIT = 196_608
LANES = ('cpu-1', 'cpu-2', 'javascript')
RAW_ROLES = {'raw','factory','owner','raw-roundtrip','alias-BMP'}
IMAGE_ROLES = RAW_ROLES | {'normalized','bridge','surface','dispatch-bmp','dispatch-BMP','uncontracted','fused'}
FORMATS = {3:4, 4:7}
MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
SEALED = {}


# These are execution-fixture resource budgets, not BMP API restrictions.
# In particular checked BMP memory input has NO 1 MiB encoded-byte cap.
SOURCE_RANGES = {
    'src/rtextures.c': [(461,471)],
    'src/external/stb_image.h': [(5422,5443),(5482,5515),(5584,5591),(5707,5710),(5728,5730)],
}
SOURCE_SHA256 = {
    'src/rtextures.c': '90e41879349d58a779c101dbf78e5b5cf8d46241590268a74e6156ad33312e4c',
    'src/external/stb_image.h': '594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3',
}


def validate_reference_sources(root):
    result={}
    for relative,ranges in SOURCE_RANGES.items():
        path=Path(root)/relative;data=path.read_bytes()
        if hashlib.sha256(data).hexdigest()!=SOURCE_SHA256[relative]:raise ValueError('Pinned BMP oracle source differs: '+relative)
        lines=data.splitlines(keepends=True)
        result[relative]=dict(sha256=SOURCE_SHA256[relative],ranges=[dict(first=first,last=last,sha256=hashlib.sha256(b''.join(lines[first-1:last])).hexdigest()) for first,last in ranges])
    return result


def inspect_header(data, *, fixture_budget=True):
    """Independent native safety admission; it does not decode output pixels.

    Re-parse every byte, supported header, effective mask, palette index, row
    and double skip before invoking native code. The finite fixture budget is
    deliberately separate from the larger checked API's 1..4096 dimensions.
    Metadata channels derive from the effective alpha MASK, not opacity/bpp.
    """
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):raise ValueError('Unsafe native byte domain')
    if len(data)<18 or data[:2]!=[66,77]:raise ValueError('Incomplete/invalid native BMP prefix')
    if len(data)>2147483647:raise ValueError('Native encoded length exceeds signed int')
    raw=bytes(data);offset,dib=struct.unpack_from('<II',raw,10)
    if dib not in (12,40,56,108,124):raise ValueError('Unsafe native DIB header')
    if len(data)<14+dib:raise ValueError('Incomplete native DIB header')
    if dib==12:
        w,h,planes,bits=struct.unpack_from('<HHHH',raw,18);compression=0;top=False
        if planes!=1 or bits not in (1,4,8,24):raise ValueError('Unsafe native CORE profile')
    else:
        w,signed_height,planes,bits,compression=struct.unpack_from('<IiHHI',raw,18)
        h=abs(signed_height);top=signed_height<0
        if planes!=1 or bits not in (1,4,8,16,24,32) or compression not in (0,3) or (compression==3 and bits not in (16,32)):raise ValueError('Unsafe native INFO profile')
    end=14+dib+(12 if dib in (40,56) and compression==3 else 0)
    if len(data)<end:raise ValueError('Incomplete native external masks')
    indexed=bits<16;gap=offset-end
    if indexed:
        entry=3 if dib==12 else 4;bias=12 if dib==12 else 0
        count=(gap-bias)//entry
        if not 1<=count<=256 or gap<bias+entry or gap>bias+entry*256+entry-1:raise ValueError('Unsafe native palette count/offset')
        palette_end=end+count*entry;skip=offset-palette_end
        if palette_end>len(data) or skip<0:raise ValueError('Incomplete native palette')
        payload=offset
    else:
        entry=count=skip=0
        if not 0<=gap<=1024:raise ValueError('Unsafe native true-color offset')
        payload=end+2*gap
    if not 1<=w<=4096 or not 1<=h<=4096:raise ValueError('Unsafe native dimensions')
    if fixture_budget and w*h>MAX_CASE_PIXELS:raise ValueError('Native fixture pixel budget exceeded')
    masks=[0,0,0,0]
    if dib in (108,124):masks=list(struct.unpack_from('<IIII',raw,54))
    if compression==3 and dib in (40,56):
        masks=list(struct.unpack_from('<III',raw,14+dib))+[0]
        if masks[0]==masks[1]==masks[2]:raise ValueError('Unsafe native identical INFO masks')
    if compression==0:
        if bits==16:masks=[0x7c00,0x3e0,0x1f,masks[3]]
        elif bits==32:masks=[0xff0000,0xff00,0xff,0xff000000]
        else:masks=[0,0,0,0]
    if bits in (16,32):
        if any(not m or m.bit_count()>8 for m in masks[:3]) or masks[3].bit_count()>8:raise ValueError('Unsafe native channel masks')
    # Native's bpp24/ma==ff000000 special case cannot be reached by this
    # checked domain: BI_RGB24 resets masks and BI_BITFIELDS24 is rejected.
    channels=4 if masks[3] else 3
    row=(w*bits+7)//8;stride=(row+3)&~3;raster=stride*h
    if payload+raster>len(data):raise ValueError('Incomplete native raster/padding/double skip')
    if indexed:
        for y in range(h):
            for x in range(w):
                value=data[payload+y*stride+x*bits//8]
                index=(value>>(8-bits-(x%(8//bits))*bits))&((1<<bits)-1)
                if index>=count:raise ValueError('Unsafe native undefined palette index')
    return dict(width=w,height=h,channels=channels,dib=dib,bits=bits,compression=compression,top=top,offset=offset,
                header_bytes=end,payload_offset=payload,row_bytes=row,stride=stride,padding=stride-row,
                palette_count=count,palette_entry_bytes=entry,palette_skip=skip,gap=gap,effective_masks=masks,
                repair_zero_alpha=bits==32 and compression==0,raster_bytes=raster,tail_bytes=len(data)-payload-raster)


def validate_cases(cases):
    if type(cases) is not list or not cases:raise ValueError('Empty native BMP cases')
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
        data=list(data);header=inspect_header(data)
        result.append(dict(id=name,bytes=data,width=header['width'],height=header['height'],channels=header['channels'],extended=extended))
    # Historical encoded inputs are copied byte-for-byte; no reconstructed pixel
    # expectations are inherited from the older normalized-only probe.
    for case in legacy_fixtures()[0]:add('legacy-'+case['id'],case['bytes'])
    for channels in (3,4):
        for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63)]:
            pixels=[sum(((i*61+j*79+(i//w)*17+13)&255)<<(24-8*j) for j in range(4)) for i in range(w*h)]
            add(f'c{channels}-{name}',bitmap(w,h,pixels,bpp=channels*8,top=True),extended=name in ('single','padded'))
        for name in ('ramp','alpha-ramp'):
            pixels=[sum(((i+j*71)&255 if name=='ramp' else (i if j==3 else 37+j*53))<<(24-8*j) for j in range(4)) for i in range(256)]
            add(f'c{channels}-{name}',bitmap(16,16,pixels,bpp=channels*8,top=name=='ramp'),extended=True)
    for dib in (40,56,108,124):
        for name,alpha in [('zero',0),('opaque',255),('mixed',None)]:
            words=[((i*39071+0x123456)&0xffffff)|((i*17 if alpha is None else alpha)<<24) for i in range(15)]
            add(f'rgb32-{dib}-alpha-{name}',bitfield_bitmap(3,5,words,bpp=32,dib=dib,compression=0,masks=(0,0,0,0),top=name=='mixed'),extended=True)
        for bits in (16,32):
            limit=(1<<bits)-1;words=[(i*0x9e3779b9)&limit for i in range(15)]
            for alpha in (0,0x8000,0xff000000):
                add(f'bitfields-{dib}-{bits}-alpha-{alpha}',bitfield_bitmap(3,5,words,bpp=bits,dib=dib,masks=(0x7c00,0x3e0,0x1f,alpha),top=bool(alpha)),extended=True)
        # Stored masks in RGB24 and the 56-byte embedded prefix are ignored.
        words=[0x123456,0xabcdef,0x070b13,0x192b3f,0x456789,0xcdefff]
        data=bitfield_bitmap(3,2,words,bpp=24,dib=dib,compression=0,masks=(0xffffffff,0xffffffff,0xffffffff,0xff000000),gap=3)
        add(f'ignored-rgb24-masks-{dib}',data,extended=True)
    for dib in (108,124):
        for name,alpha,words in [('absent',0,[0,0x7fff,0x1234]),('zero',0x8000,[0,0x1234,0x7fff]),('opaque',0x8000,[0x8000,0x9234,0xffff]),('mixed',0x8000,[0,0x9234,0x7fff]),('above-word',0xff000000,[0,0x9234,0xffff])]:
            add(f'rgb16-{dib}-alpha-{name}',bitfield_bitmap(3,1,words,dib=dib,compression=0,masks=(0xffffffff,0xffffffff,0xffffffff,alpha)),extended=True)
        for name,words in [('zero',[0x010203,0x112233,0xabcdef]),('opaque',[0xff010203,0xff112233,0xffabcdef])]:
            add(f'explicit32-{dib}-alpha-{name}',bitfield_bitmap(3,1,words,bpp=32,dib=dib,masks=(0xff0000,0xff00,0xff,0xff000000)),extended=True)
    for dib in (40,56,108,124):
        for bits in (1,4,8):
            palette=[0x01020300,0x719bc1ff] if bits==1 else [0x01020300,0x719bc180,0xe7f1fbff]
            for remainder in range(4):
                indices=[i%len(palette) for i in range(15)]
                add(f'palette-{dib}-{bits}-remainder-{remainder}',indexed_bitmap(3,5,indices,palette,bpp=bits,dib=dib,top=bool(remainder&1),gap=remainder,colors_used=0xffffffff),extended=remainder==3)
    for bits in (1,4,8):
        for remainder in range(3):
            add(f'core-palette-{bits}-remainder-{remainder}',core_indexed_bitmap(3,5,[i%2 for i in range(15)],[0x01020300,0xfbd591ff],bpp=bits,remainder=remainder),extended=remainder==2)
    # Mutate every native-ignored metadata category while preserving the raster.
    data=bitfield_bitmap(3,2,[0x12345678+i*0x10203 for i in range(6)],bpp=32,dib=124,compression=0,gap=5,top=True)
    for start,end in ((2,10),(34,54),(70,138)):
        data[start:end]=[(i*37+19)&255 for i in range(start,end)]
    data+=list(b'BMP ignored complete trailer\0')
    add('ignored-metadata-gap-tail',data,extended=True)
    validate_cases(result);return result


def validate_controls(cases):
    if type(cases) is not list:raise ValueError('Invalid checked BMP controls')
    ids=set()
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','error'}:raise ValueError('Checked control schema differs')
        if type(case['id']) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',case['id']) is None or case['id'] in ids:raise ValueError('Invalid/duplicate control ID')
        ids.add(case['id'])
        if type(case['error']) is not int or case['error'] not in range(5):raise ValueError('Invalid checked error')
        if type(case['bytes']) is not list or any(type(v) is not int or not 0<=v<=4294967295 for v in case['bytes']):raise ValueError('Invalid checked byte domain')
        # Fixture resource limits cannot turn a valid API input into an error
        # control. Only actual checked-domain structural rejection qualifies.
        try:inspect_header(case['bytes'],fixture_budget=False)
        except ValueError:pass
        else:raise ValueError('Accepted native input mislabeled as control')


def controls():
    result=[dict(c,id='legacy-'+c['id']) for c in legacy_fixtures()[1]]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    def changed(data,at,fmt,value):
        result=bytearray(data);struct.pack_into('<'+fmt,result,at,value);return list(result)
    base=bitmap(1,1,[0x12345678]);v5=bitfield_bitmap(1,1,[0x1234],dib=124)
    # Every byte of the largest header, word payload and padding is covered.
    # Further specimens cover CORE/palettes, 56-byte discarded and external
    # masks, both true-color skips, and ignored complete trailers.
    specimens=[('v5',v5),('core',core_bitmap(1,1,[0x12345678])),
               ('palette',indexed_bitmap(1,1,[0],[0x12345678],gap=3)),
               ('core-palette',core_indexed_bitmap(1,1,[0],[0x12345678],bpp=8,remainder=2)),
               ('info56',bitfield_bitmap(1,1,[0x1234],dib=56,gap=2)+[17])]
    for name,data in specimens:
        for at in range(len(data)):
            values=data.copy();values[at]=256;add(f'invalid-byte-{name}-{at}',values,1)
    for n in range(26):add(f'core-prefix-{n}',core_bitmap(1,1,[0x12345678])[:n],0)
    for dib in (40,56,108,124):
        data=bitfield_bitmap(1,1,[0x1234],dib=dib)
        end=14+dib+(12 if dib in (40,56) else 0)
        for n in sorted({26,53,14+dib-1,end-1}):add(f'dib-{dib}-prefix-{n}',data[:n],0)
        for n in range(4):add(f'dib-{dib}-short-raster-{n}',data[:end+n],3)
    for axis,at in (('width',18),('height',22)):
        for value in (0,4097,0x7fffffff,0x80000000,0xffffffff):
            if axis=='height' and value==0xffffffff:continue  # -1 is accepted.
            add(f'{axis}-{value}',changed(base,at,'I',value),2)
    for name,at,fmt,values in [('planes',26,'H',(0,2,65535)),('dib',14,'I',(0,13,39,41,55,57,107,109,123,125,0xffffffff)),('depth',28,'H',(0,2,15,17,23,25,31,33,65535)),('compression',30,'I',(1,2,3,4,5,6,0xffffffff)),('offset',10,'I',(0,53,1079,0x7fffffff,0x80000000,0xffffffff))]:
        for value in values:add(f'{name}-{value}',changed(base,at,fmt,value),0)
    for dib in (40,56,108,124):
        for bits in (16,32):
            for channel in range(4 if dib in (108,124) else 3):
                for value in ((0,0x1ff) if channel<3 else (0x1ff,)):
                    masks=[0x7c00,0x3e0,0x1f,0x8000];masks[channel]=value
                    add(f'mask-{dib}-{bits}-{channel}-{value}',bitfield_bitmap(1,1,[0x1234],bpp=bits,dib=dib,masks=tuple(masks)),0)
    for bits in (1,4,8):
        for dib in (40,56,108,124):
            data=indexed_bitmap(1,1,[1],[0x12345678],bpp=bits,dib=dib)
            add(f'index-undefined-{dib}-{bits}',data,4)
        add(f'core-index-undefined-{bits}',core_indexed_bitmap(1,1,[1],[0x12345678],bpp=bits),4)
    # Typed precedence belongs to the checked APIs; controls never run native.
    add('bad-byte-before-header',[0,4294967295],1)
    add('bad-byte-before-size',changed(base,18,'I',0)+[256],1)
    add('bad-byte-before-padding',base[:-1]+[256],1)
    add('bad-header-before-size',changed(changed(base,18,'I',0),26,'H',0),0)
    add('bad-offset-before-size',changed(changed(base,18,'I',0),10,'I',53),0)
    add('bad-size-before-truncated',changed(base,18,'I',0)[:54],2)
    add('bad-size-before-incomplete-masks',changed(v5,18,'I',0)[:54],2)
    add('bad-size-before-invalid-mask',changed(changed(v5,18,'I',0),54,'I',0),2)
    data=indexed_bitmap(1,1,[1],[0x12345678])
    add('truncated-before-invalid-index',data[:-1],3)
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
    if role not in IMAGE_ROLES:raise ValueError('Unknown BMP image role')
    return dict(id=case['id'],role=role,width=case['width'],height=case['height'],mipmaps=1,
                format=FORMATS[case['channels']] if role in RAW_ROLES else 7)


def parse_rows(text, actions):
    if not actions:raise ValueError('Empty BMP observation batch')
    lines=text.splitlines();cursor=0;rows=[]
    for action in actions:
        case,role=action['case'],action['role']
        if cursor>=len(lines):raise ValueError('Missing BMP record')
        row=strict_json(lines[cursor]);cursor+=1
        if role in ('formatted-error','surface-error'):
            expected=dict(id=case['id'],role=role,error=case['error'])
        else:expected=meta(case,role)
        if type(row) is not dict or row!=expected or any(type(row.get(k)) is not type(v) for k,v in expected.items()):
            raise ValueError(f'BMP metadata/order/type differs: {case["id"]}/{role}: {row!r}')
        if role not in ('formatted-error','surface-error'):
            output=[];short=False
            while cursor<len(lines):
                chunk=strict_json(lines[cursor]);cursor+=1
                if chunk=='end':break
                if type(chunk) is not list or not 1<=len(chunk)<=256 or short or any(type(v) is not int or not 0<=v<=255 for v in chunk):raise ValueError('Malformed BMP byte chunk')
                short=len(chunk)<256;output.extend(chunk)
            else:raise ValueError('Unterminated BMP bytes')
            if len(output)!=case['width']*case['height']*{1:1,2:2,4:3,7:4}[row['format']]:raise ValueError('BMP byte count differs')
            row=dict(row,bytes=output)
        rows.append(row)
    if cursor!=len(lines):raise ValueError('Extra BMP records')
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
  (pixels, (U32.is_eq(format, 4) && (word <= 16777215 : U32)) || U32.is_eq(format, 7))
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
    case None{}: IO.die(Unit, 1, "valid BMP or owner invariant rejected")
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
def qualification_program():
    # Deliberately tiny fixed vectors qualify native routing. This is not a
    # Python decoder: broad expected pixels only come from native raw captures.
    vectors=[('rgb24',bitmap(1,1,[0x01020380]),4,[1,2,3]),
             ('rgb32-repaired',bitmap(1,1,[0x01020300],bpp=32),7,[1,2,3,255]),
             ('rgb32-alpha',bitmap(1,1,[0x01020380],bpp=32),7,[1,2,3,128]),
             ('info16-rgb565',bitfield_bitmap(1,1,[0xf800]),4,[255,0,0]),
             ('rgb555-bit-replication',bitmap16(1,1,[4]),4,[0,0,33]),
             ('info32-ignored-alpha',bitfield_bitmap(1,1,[0x80112233],bpp=32,masks=(0xff0000,0xff00,0xff,0xff000000)),4,[17,34,51]),
             ('info56-ignored-alpha',bitfield_bitmap(1,1,[0x80112233],bpp=32,dib=56,masks=(0xff0000,0xff00,0xff,0xff000000)),4,[17,34,51]),
             ('v4-explicit-zero-alpha',bitfield_bitmap(1,1,[0x00112233],bpp=32,dib=108,masks=(0xff0000,0xff00,0xff,0xff000000)),7,[17,34,51,0]),
             ('v5-rgb32-repaired',bitfield_bitmap(1,1,[0x00112233],bpp=32,dib=124,compression=0),7,[17,34,51,255]),
             ('v4-rgb16-alpha',bitfield_bitmap(1,1,[0x001f],dib=108,compression=0,masks=(0,0,0,0x8000)),7,[0,0,255,0]),
             ('v5-rgb16-above-word-alpha',bitfield_bitmap(1,1,[0x001f],dib=124,compression=0,masks=(0,0,0,0xff000000)),7,[0,0,255,0]),
             ('palette-reserved-ignored',indexed_bitmap(1,1,[0],[0x01020300]),4,[1,2,3])]
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for name,data,fmt,expected in vectors:
        inspect_header(data)
        lines+=['/* '+name+' */ {const unsigned char data[]={'+','.join(map(str,data))+'};',
                'Image image=LoadImageFromMemory(".bmp",data,sizeof(data));if(!image.data)return 11;',
                f'if(image.width!=1||image.height!=1||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(1,1,image.format)!={len(expected)}){{UnloadImage(image);return 12;}}',
                'const unsigned char *p=image.data;if('+ '||'.join(f'p[{i}]!={v}' for i,v in enumerate(expected))+'){UnloadImage(image);return 13;}UnloadImage(image);}' ]
    row=json.dumps(dict(little_endian=True,bmp_enabled=True,effective_alpha_routing=True,formats=[4,7]),separators=(',',':'))
    return '\n'.join(lines+['puts('+json.dumps(row)+');return 0;}'])+'\n'


QUALIFY=qualification_program()


def qualification(text):
    expected=dict(little_endian=True,bmp_enabled=True,effective_alpha_routing=True,formats=[4,7])
    result=strict_json(text)
    if type(result) is not dict or result!=expected or any(type(result[k]) is not type(v) for k,v in expected.items()) or any(type(v) is not int for v in result['formats']):raise ValueError('Native BMP qualification differs')
    return result


def native_actions(cases):
    return [dict(case=c,role=role) for c in cases for role in ('raw','normalized',*(('alias-BMP',) if c['extended'] else ()))]


def reference_program(cases):
    validate_cases(cases)
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        fmt=FORMATS[c['channels']];raw_size=c['width']*c['height']*c['channels']
        lines+=['{const unsigned char data[]={'+','.join(map(str,c['bytes']))+'};',
                'Image image=LoadImageFromMemory(".bmp",data,sizeof(data));if(!image.data)return 2;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 3;}}',
                f'observed({json.dumps(c["id"])},"raw",image);',
                'ImageFormat(&image,7);if(!image.data)return 4;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!=7||GetPixelDataSize(image.width,image.height,image.format)!={c["width"]*c["height"]*4}){{UnloadImage(image);return 5;}}',
                f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);']
        if c['extended']:
            lines+=['image=LoadImageFromMemory(".BMP",data,sizeof(data));if(!image.data)return 6;',
                    f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 7;}}',
                    f'observed({json.dumps(c["id"])},"alias-BMP",image);UnloadImage(image);']
        lines+=['}']
    return '\n'.join(lines+['return 0;}'])+'\n'


def candidate_actions(cases,invalid,rows):
    validate_cases(cases);validate_controls(invalid)
    if {c['id'] for c in cases}&{c['id'] for c in invalid}:raise ValueError('BMP accepted/control IDs overlap')
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
            if rows[cursor]!=dict(raw,role='alias-BMP'):raise ValueError('Native BMP alias bytes differ')
            cursor+=1
        reference[c['id']]=(raw,normal)
    if cursor!=len(rows):raise ValueError('Native BMP reference count differs')
    actions=[]
    for c in cases:
        raw,normal=reference[c['id']]
        for role in ('raw','bridge','surface','factory','owner','raw-roundtrip',*(('dispatch-bmp','dispatch-BMP','uncontracted','fused') if c['extended'] else ())):
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
        if action.get('role') not in ('raw','bridge','surface','factory','owner','raw-roundtrip','dispatch-bmp','dispatch-BMP','uncontracted','fused','formatted-error','surface-error'):raise ValueError('Unknown BMP candidate role')
        c=action['case']
        if c['id'] in bound_cases and c!=bound_cases[c['id']]:raise ValueError('BMP action case identity differs')
        bound_cases[c['id']]=c
        if c['id'] not in bindings:
            name='input'+str(len(bindings));bindings[c['id']]=name
            lines.append(f'  +{name} = {{{bend_bytes(c["bytes"])} : +List<U32>}}')
    lines.append('  do IO<Unit>:')
    for action in actions:
        c=action['case'];role=action['role'];data=bindings[c['id']];ident=json.dumps(c['id'])
        decode=f'decoded(J.Image.Formatted.decode_bmp({data}))'
        if role.endswith('-error'):
            mode=role.split('-')[0];call='J.Image.Formatted' if mode=='formatted' else 'J.Surface'
            lines.append(f'    emit.error({ident}, {json.dumps(role)}, {mode}.error({call}.decode_bmp({data})))');continue
        if role=='raw':image=decode
        elif role=='bridge':image=f'bridge({decode})'
        elif role=='raw-roundtrip':image=f'roundtrip({decode})'
        elif role=='surface':image=f'surface(J.Surface.decode_bmp({data}))'
        elif role.startswith('dispatch-'):image=f'surface(J.Surface.decode_image({json.dumps("."+role.split("-")[1])}, {data}))'
        elif role in ('uncontracted','fused'):image=f'surface(J.Surface.decode_image_for(J.{"UncontractedDecode" if role=="uncontracted" else "FusedDecode"}{{}}, ".BMP", {data}))'
        elif role=='factory':image=f'J.Image.Formatted.from_bytes({c["width"]}, {c["height"]}, {FORMATS[c["channels"]]}, {bend_bytes(action["expected"]["bytes"])})'
        elif role=='owner':
            normal=action['normalized'];first=int.from_bytes(bytes(normal[:4]),'big');last=int.from_bytes(bytes(normal[-4:]),'big')
            image=f'owner({decode}, {c["width"]}, {c["height"]}, {first}, {last})'
        else:raise ValueError('Unknown BMP observation')
        lines.append(f'    observed({ident}, {json.dumps(role)}, {image})')
    return '\n'.join(lines)+'\n'


def differences(expected,actual):
    if len(expected)!=len(actual):raise ValueError('BMP comparison count differs')
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
    if path in SEALED and SEALED[path]!=observed:raise ValueError('Sealed BMP artifact drift: '+path)
    SEALED[path]=observed


def verify_sealed():
    for path,expected in SEALED.items():
        if not Path(path).is_file() or digest(path)!=expected:raise ValueError('Sealed BMP artifact drift: '+path)


PROCESS_CLEANUP_SECONDS = 5


def run_process_group(command, *, cwd, env, timeout):
    """Bound the spawned POSIX group, then reap its direct child.

    Only this new session's PGID is signalled. Grandchildren that keep inherited
    pipes open cannot turn timeout cleanup into an unbounded communicate().
    The cleanup budget is separate from, and never extends, the work timeout.
    """
    if os.name!='posix':raise OSError('BMP process-group profile requires POSIX')
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
        raise ValueError('BMP child '+('timed out' if isinstance(failed,subprocess.TimeoutExpired) else 'could not start or communicate')+': '+label) from failed
    if proc.returncode:raise ValueError(f'{label} exited {proc.returncode}: {proc.stdout[-1000:]}{proc.stderr[-2500:]}')
    if require_output and not proc.stdout.strip():raise ValueError('Process output missing: '+label)
    if any(not p.is_file() or p.stat().st_size==0 for p in outputs):raise ValueError('Compiler output missing')
    return proc.stdout


def tracked_sources(args):
    paths=[ROOT/p for p in ('tools/bmp_format_probe.py','tests/test_bmp_format_harness.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','toolchain.json','LAWS.bend','PROOF.bend')]
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
    return result or [BUILD/'bmp-format-probe']


def admit_directories(argv):
    paths=report_directories(argv)
    for path in dict.fromkeys(p.resolve() for p in paths):
        path.mkdir(parents=True,exist_ok=True);(path/'results.json').write_text('{"passed":false,"phase":"argument-validation"}\n')
    return paths[-1].resolve()


def validate_native_config(cache,flags):
    required={'PLATFORM':'Memory','CMAKE_BUILD_TYPE':'Release','CUSTOMIZE_BUILD':'ON','SUPPORT_FILEFORMAT_BMP':'ON','SUPPORT_MODULE_RAUDIO':'OFF','BUILD_EXAMPLES':'OFF','USE_EXTERNAL_GLFW':'OFF'}
    pairs=re.findall(r'^([A-Za-z_][A-Za-z0-9_]*):[^=\n]+=(.*)$',cache,re.M)
    fields=dict(pairs)
    if len(fields)!=len(pairs):raise ValueError('Duplicate native CMake cache field')
    if any(fields.get(k)!=v for k,v in required.items()):raise ValueError('Native BMP cache configuration differs')
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
    for macro in ('SUPPORT_FILEFORMAT_BMP','EXTERNAL_CONFIG_FLAGS','PLATFORM_MEMORY'):
        selected=[t for t in definitions if t[2:].split('=')[0]==macro]
        if len(selected)!=1 or selected[0] not in ('-D'+macro,'-D'+macro+'=1'):raise ValueError('Actual native macro missing/disabled/ambiguous: '+macro)
    if any(t[2:].split('=')[0].startswith('PLATFORM_') and t[2:].split('=')[0]!='PLATFORM_MEMORY' for t in definitions):raise ValueError('Conflicting native platform macro')
    return required


def native_archive(args,work,record):
    cmake=work/'raylib-build'
    if cmake.exists():raise ValueError('Native build directory must be fresh')
    record(['cmake','-S',args.raylib_source,'-B',cmake,'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DSUPPORT_FILEFORMAT_BMP=ON','-DUSE_EXTERNAL_GLFW=OFF'],work,'configure')
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
    if type(actions) is not list or not actions:raise ValueError('Empty BMP action sequence')
    identities=set()
    for action in actions:
        if type(action) is not dict or type(action.get('case')) is not dict or type(action.get('role')) is not str or type(action.get('expected')) is not dict:raise ValueError('Malformed BMP action')
        identity=(action['case'].get('id'),action['role'])
        if type(identity[0]) is not str or identity in identities:raise ValueError('Invalid/duplicate BMP action identity')
        identities.add(identity)
        if (action['expected'].get('id'),action['expected'].get('role'))!=identity:raise ValueError('BMP action/reference identity differs')
        values=action['expected'].get('bytes',[])
        if type(values) is not list or any(type(v) is not int or not 0<=v<=255 for v in values):raise ValueError('Invalid BMP action reference bytes')


def action_digest(actions):
    return hashlib.sha256(json.dumps(actions,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


def partition_entry(actions,start,count,program):
    selected=actions[start:start+count]
    return dict(start=start,count=count,source_bytes=len(program),source_sha256=hashlib.sha256(program).hexdigest(),
                actions_sha256=action_digest(selected),compared_bytes=sum(len(a['expected'].get('bytes',[])) for a in selected))


def validate_partitions(actions,partitions,source_limit=SOURCE_BYTE_LIMIT):
    """Require an exact ordered, exhaustive plan against regenerated sources."""
    validate_action_sequence(actions)
    if type(source_limit) is not int or not 0<source_limit<=SOURCE_BYTE_LIMIT:raise ValueError('Invalid BMP partition source budget')
    if type(partitions) is not list or not partitions:raise ValueError('Empty BMP partition plan')
    cursor=0
    for entry in partitions:
        if type(entry) is not dict or set(entry)!={'start','count','source_bytes','source_sha256','actions_sha256','compared_bytes'}:raise ValueError('BMP partition schema differs')
        if any(type(entry[k]) is not int for k in ('start','count','source_bytes','compared_bytes')):raise ValueError('BMP partition integer type differs')
        if entry['start']!=cursor or not 1<=entry['count']<=BATCH_SIZE or cursor+entry['count']>len(actions):raise ValueError('Noncontiguous/incomplete BMP partition')
        if not 0<entry['source_bytes']<=source_limit or entry['compared_bytes']<0:raise ValueError('BMP partition budget differs')
        selected=actions[cursor:cursor+entry['count']];program=candidate_program(selected).encode('utf-8')
        expected=partition_entry(actions,cursor,entry['count'],program)
        if entry!=expected or any(type(entry[k]) is not type(v) for k,v in expected.items()):raise ValueError('BMP partition source/action identity differs')
        cursor+=entry['count']
    if cursor!=len(actions):raise ValueError('Incomplete BMP partition coverage')


def plan_partitions(actions,source_limit=SOURCE_BYTE_LIMIT):
    """Greedy complete ordered partitions; only compilation grouping changes.

    Both the 32-action maximum and the exact generated UTF-8 byte budget apply.
    No fixture, role, reference byte, runtime limit or oracle is changed.
    """
    validate_action_sequence(actions)
    if type(source_limit) is not int or not 0<source_limit<=SOURCE_BYTE_LIMIT:raise ValueError('Invalid BMP partition source budget')
    plan=[];start=0
    while start<len(actions):
        selected=None
        for count in range(1,min(BATCH_SIZE,len(actions)-start)+1):
            program=candidate_program(actions[start:start+count]).encode('utf-8')
            if not program:raise ValueError('Empty generated BMP source')
            if len(program)>source_limit:
                if count==1:raise ValueError('BMP singleton exceeds source budget: '+str(start))
                break
            selected=partition_entry(actions,start,count,program)
        if selected is None:raise ValueError('Empty BMP partition')
        plan.append(selected);start+=selected['count']
    validate_partitions(actions,plan,source_limit)
    return plan


def finish_lanes(lanes,actions,partitions):
    validate_partitions(actions,partitions)
    if set(lanes)!=set(LANES):raise ValueError('Missing mandatory BMP lanes/cases')
    expected_bytes=sum(len(a['expected'].get('bytes',[])) for a in actions)
    for lane in LANES:
        if type(lanes[lane]) is not dict or type(lanes[lane].get('batches')) is not list or type(lanes[lane].get('differences')) is not list:raise ValueError('Malformed BMP lane')
        batches=lanes[lane]['batches']
        if len(batches)!=len(partitions):raise ValueError('Incomplete BMP lane partition count')
        observations=compared_bytes=0
        for batch,planned in zip(batches,partitions):
            if type(batch) is not dict or set(batch)!={*planned,'bytes','passed'}:raise ValueError('BMP lane batch schema differs')
            if any(type(batch[k]) is not type(v) or batch[k]!=v for k,v in planned.items()) or batch['passed'] is not True:raise ValueError('BMP lane differs from exact partition plan')
            if type(batch['bytes']) is not int or batch['bytes']!=planned['compared_bytes']:raise ValueError('BMP lane byte coverage differs')
            observations+=batch['count'];compared_bytes+=batch['bytes']
        if observations!=len(actions) or compared_bytes!=expected_bytes or lanes[lane]['differences']:raise ValueError('Incomplete or differing BMP lane: '+lane)
    for lane in LANES:lanes[lane]['passed']=True


def run_probe(argv):
    SEALED.clear();admitted=admit_directories(argv)
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--build-dir',type=Path,default=BUILD/'bmp-format-probe')
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
    if sys.byteorder!='little':raise ValueError('BMP profile requires little endian')
    cases,invalid=fixtures(),controls();validate_cases(cases)
    inputs=work/'inputs.json';inputs.write_text(json.dumps(dict(cases=cases,controls=invalid),sort_keys=True)+'\n');seal(inputs)
    tool_paths={}
    for tool in ('bun','clang','cmake'):
        path=shutil.which(tool)
        if path is None:raise ValueError('Required tool missing: '+tool)
        tool_paths[tool]=str(Path(path).absolute());seal(path)
    tool_realpaths={k:str(Path(p).resolve()) for k,p in tool_paths.items()}
    report=dict(passed=False,oracle_source_ranges=validate_reference_sources(args.raylib_source),profile='native-bmp-formatted-memory-v1',reconstruction='fresh implementation; no previous runtime evidence reused',run_directory=str(work),toolchain=lock,base_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),host=dict(system=platform.system(),machine=platform.machine()),tool_paths=tool_paths,tool_realpaths=tool_realpaths,sources=tracked_sources(args),reference_environment=reference_env.receipt(),inputs_sha256=digest(inputs),cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(invalid),native_rejections=0,batch_size=BATCH_SIZE,source_byte_limit=SOURCE_BYTE_LIMIT,partition_strategy='ordered-greedy-generated-source-v1',lanes={lane:dict(passed=False,batches=[],differences=[]) for lane in LANES},candidate_mipmaps='implicit single-mip type contract, not stored/measured',unrun=['GPU/Metal','Windows/browser','big-endian','exact-commit hosted CI','4096x4096 allocation/resource limits','representative performance','formatted file IO','generic formatted/float dispatch','native malformed recovery'])
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
        save()
    actions,reference=candidate_actions(cases,invalid,native_rows)
    report.update(native_observations=len(native_rows),native_raw_bytes=sum(len(raw['bytes']) for raw,_ in reference.values()),native_normalized_bytes=sum(len(normal['bytes']) for _,normal in reference.values()),native_all_observed_bytes=sum(len(r['bytes']) for r in native_rows),observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions),raw_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] in ('raw','factory','owner','raw-roundtrip')),normalized_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] not in ('raw','factory','owner','raw-roundtrip')));save()
    partitions=plan_partitions(actions);report.update(partition_plan=partitions,planned_batches=len(partitions));save()
    for index,partition in enumerate(partitions):
        start=partition['start'];selected=actions[start:start+partition['count']]
        program=candidate_program(selected).encode('utf-8')
        if partition_entry(actions,start,len(selected),program)!=partition:raise ValueError('BMP generated partition drift before compilation')
        source=work/f'candidate-{index}.bend';source.write_bytes(program);seal(source)
        binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,f'compile-{index}')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual=parse_rows(record(command,work,f'{lane}-{index}',require_output=True),selected)
            delta=differences([a['expected'] for a in selected],actual)
            report['lanes'][lane]['differences'].extend(delta)
            report['lanes'][lane]['batches'].append(dict(partition,bytes=sum(len(r.get('bytes',[])) for r in actual),passed=not delta));save()
        print(f'BMP batch {index+1}: {len(selected)} observations compared on CPU-1/CPU-2/JavaScript',flush=True)
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    reference_env.assert_receipt(report['reference_environment'])
    if any(shutil.which(k) is None or str(Path(shutil.which(k)).absolute())!=p or str(Path(shutil.which(k)).resolve())!=tool_realpaths[k] for k,p in tool_paths.items()):raise ValueError('Tool executable resolution drift')
    if tracked_sources(args)!=report['sources']:raise ValueError('Source/toolchain/native input drift')
    finish_lanes(report['lanes'],actions,partitions);verify_sealed()
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3),sealed_artifacts=dict(SEALED));save()
    print(f'PASS: {len(cases)} native BMP images, {len(invalid)} checked-only typed controls, {report["compared_bytes_per_lane"]} bytes per lane',flush=True)


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
            if hasattr(error,'add_note'):error.add_note('Could not save failed BMP report: '+str(report_error))
        raise


if __name__=='__main__':main()
