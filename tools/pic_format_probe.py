#!/usr/bin/env python3
"""Exact original-format PIC memory decoding against pinned raylib.

Only independently admitted complete PIC fixtures reach native code. Malformed
PIC may free/null its buffer then run a 4-to-3 conversion; controls NEVER go
native. Admission independently walks every descriptor, row control and sample.
PIC shares stb sniffing: a .pic suffix alone proves no PIC content identity.
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

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER
from conformance import BUILD, ROOT, ENV, checkout, source_gate
from pic_probe import fixtures as legacy_fixtures, pic_header, pic, pic_packets
from reference_environment import ReferenceEnvironment

BATCH_SIZE = 32
SOURCE_BYTE_LIMIT = 196_608
LANES = ('cpu-1', 'cpu-2', 'javascript')
RAW_ROLES = {'raw','factory','owner','raw-roundtrip','alias-PIC'}
IMAGE_ROLES = RAW_ROLES | {'normalized','bridge','surface','dispatch-pic','dispatch-PIC','uncontracted','fused'}
FORMATS = {3:4, 4:7}
MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
SEALED = {}

# Fixture budgets are deliberately separate from the checked API. PIC has no
# encoded-byte cap; native LoadImageFromMemory still accepts a signed int size.
# Anchor native signature/descriptor/RLE walks, all-descriptor channel OR,
# default-white initialization, and conversion after an unsafe malformed load.
SOURCE_RANGES = {
    'src/rtextures.c': [(443,446),(461,471)],
    'src/external/stb_image.h': [(6346,6546)],
}
SOURCE_SHA256 = {
    'src/rtextures.c': '90e41879349d58a779c101dbf78e5b5cf8d46241590268a74e6156ad33312e4c',
    'src/external/stb_image.h': '594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3',
}


def validate_reference_sources(root):
    result={}
    for relative,ranges in SOURCE_RANGES.items():
        path=Path(root)/relative;data=path.read_bytes()
        if hashlib.sha256(data).hexdigest()!=SOURCE_SHA256[relative]:raise ValueError('Pinned PIC oracle source differs: '+relative)
        lines=data.splitlines(keepends=True)
        result[relative]=dict(sha256=SOURCE_SHA256[relative],ranges=[dict(first=first,last=last,sha256=hashlib.sha256(b''.join(lines[first-1:last])).hexdigest()) for first,last in ranges])
    return result


class AdmissionError(ValueError):
    """Structural checked error, never a decoded-pixel expectation."""
    def __init__(self,message,error):
        super().__init__(message);self.error=error


def inspect_header(data, *, fixture_budget=True):
    """Independently admit actual complete PIC bytes before native execution.

    This is a bounds/format scanner, never a pixel oracle. Empty masks still
    require post-descriptor and post-control bytes. Every zero count consumes
    a control (and its selected sample); pure counts clip, mixed counts reject
    overruns before reading samples. All validated descriptors contribute to
    the sticky native component OR, regardless of order, opacity or overwrites.
    """
    def reject(message,error):raise AdmissionError(message,error)
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):reject('Unsafe native byte domain',1)
    if len(data)>2147483647:reject('Native encoded length exceeds signed int',2)
    if len(data)<104 or data[:4]!=[83,128,246,52] or data[88:92]!=[80,73,67,84]:reject('Incomplete/invalid native PIC header',0)
    width=data[92]*256+data[93];height=data[94]*256+data[95]
    if not 1<=width<=4096 or not 1<=height<=4096:reject('Unsafe native dimensions',2)
    if fixture_budget and width*height>MAX_CASE_PIXELS:reject('Native fixture pixel budget exceeded',2)
    at=104;descriptors=[];effective_mask=0
    while True:
        if len(descriptors)==10:reject('Too many native PIC descriptors',0)
        if at+4>=len(data):reject('Incomplete native PIC descriptor/post-descriptor byte',0)
        chain,depth,kind,mask=data[at:at+4];at+=4
        if depth!=8 or kind not in (0,1,2):reject('Unsafe native PIC descriptor profile',0)
        descriptors.append(dict(kind=kind,mask=mask,channels=(mask&0xf0).bit_count()))
        effective_mask|=mask
        if chain==0:break
    payload=at;zero_counts=clipped_counts=controls_count=0
    for _ in range(height):
        for descriptor in descriptors:
            kind=descriptor['kind'];channels=descriptor['channels'];left=width
            if kind==0:
                count=left*channels
                if at+count>len(data):reject('Incomplete native PIC raw samples',3)
                at+=count;continue
            while left:
                # Native checks EOF immediately after reading each control,
                # including empty masks. Do not synthesize zero bytes at EOF.
                if at+1>=len(data):reject('Incomplete native PIC control/post-control byte',3)
                code=data[at];at+=1;controls_count+=1;literal=False
                if kind==1:
                    count=min(code,left);clipped_counts+=int(code>left)
                elif code==128:
                    if at+2>len(data):reject('Incomplete native PIC extended count',3)
                    count=data[at]*256+data[at+1];at+=2
                elif code<128:count=code+1;literal=True
                else:count=code-127
                if kind==2 and count>left:reject('Unsafe native PIC mixed row overrun',4)
                sample_bytes=channels*(count if literal else 1)
                if at+sample_bytes>len(data):reject('Incomplete native PIC RLE samples',3)
                at+=sample_bytes;left-=count;zero_counts+=int(count==0)
    return dict(width=width,height=height,channels=4 if effective_mask&0x10 else 3,
                descriptors=descriptors,packet_count=len(descriptors),effective_mask=effective_mask,
                payload_offset=payload,payload_bytes=at-payload,tail_bytes=len(data)-at,
                controls=controls_count,zero_counts=zero_counts,clipped_counts=clipped_counts)


def checked_error(data):
    """Return only the independently scanned checked scalar error, or None."""
    try:inspect_header(data,fixture_budget=False)
    except AdmissionError as error:return error.error
    return None


def validate_cases(cases):
    if type(cases) is not list or not cases:raise ValueError('Empty native PIC cases')
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
    # Only immutable historical streams are reused, never a normalized oracle.
    legacy=legacy_fixtures()[0]
    if len(legacy)!=33 or sum(inspect_header(c['bytes'])['width']*inspect_header(c['bytes'])['height'] for c in legacy)!=8867:raise ValueError('Legacy PIC fixture inventory differs')
    for case in legacy:add('legacy-'+case['id'],case['bytes'])
    for channels in (3,4):
        for name,width,height in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63)]:
            colors=[sum(((i*61+j*79+(i//width)*17+13)&255)<<(24-8*j) for j in range(4)) for i in range(width*height)]
            add(f'c{channels}-{name}',pic(width,height,[(0xe0 if channels==3 else 0xf0,colors)]),name in ('single','padded'))
    for name,colors in [('alpha-ramp',[0x25354700|i for i in range(256)]),('all-opaque',[((i*65793&0xffffff)<<8)|255 for i in range(256)]),('all-zero-alpha',[(i*65793&0xffffff)<<8 for i in range(256)])]:
        add(name,pic(16,16,[(0xf0,colors)]),True)
    colors=[0x01020300,0x11223380,0xaabbccff,0x00ff007f,0xff00ff01,0xfefdfcfe]
    replacement=[0x071727ff,0x081828ff,0x091929ff,0x0a1a2aff,0x0b1b2bff,0x0c1c2cff]
    for name,packets in [('early-alpha-followed-rgb',[(0x10,colors),(0xe0,replacement)]),
                         ('middle-alpha-followed-rgb',[(0x80,replacement),(0x10,colors),(0xe0,colors)]),
                         ('opaque-alpha-followed-rgb',[(0x10,replacement),(0xe0,colors)]),
                         ('alpha-overwrites-final-opaque',[(0xf0,colors),(0x10,list(reversed(colors))),(0x10,replacement),(0xe0,colors)]),
                         ('overlap-alpha-zero',[(0xf0,replacement),(0x90,colors),(0x40,replacement)]),
                         ('lowbits-all-channels',[(0xff,colors)]),
                         ('lowbits-empty-masks',[(0x0f,colors),(0x01,replacement)]),
                         ('alpha-then-empty-mask',[(0x10,colors),(0x0f,replacement)]),
                         ('ten-packets-alpha-first',[(0x10,colors)]+[(0x80,replacement)]*8+[(0x00,colors)])]:
        add(name,pic(3,2,packets),True)
    def sample(color,mask):return [value for i,value in enumerate(color.to_bytes(4,'big')) if mask&(128>>i)]
    # Both RLE families exercise all 16 high-bit masks, low-bit indifference,
    # zero counts and exact/oversize runs. The final sentinel is deliberate:
    # empty masks still need one byte after their last control.
    for kind in (1,2):
        for mask in range(0,256,16):
            rows=[]
            for y in range(2):
                samples=[sample(c,mask) for c in colors[y*3:(y+1)*3]]
                rows.append([0,*samples[0],1,*samples[0],255,*samples[1]] if kind==1 else
                            [128,0,0,*samples[0],1,*samples[0],*samples[1],128,0,1,*samples[2]])
            add(f'all-masks-rle-{kind}-{mask:02x}',pic_packets(3,2,[(kind,mask,rows)])+[0],True)
        add(f'rle-lowbits-{kind}',pic_packets(3,1,[(kind,0x9f,[[3,17,128] if kind==1 else [130,17,128]])])+[0],True)
    add('pure-clip-rgba',pic_packets(1,1,[(1,0xf0,[[255,1,2,3,0]])]),True)
    add('pure-zero-progress-then-one',pic_packets(1,1,[(1,0x10,[[0,99]*64+[1,0]])]),True)
    add('mixed-zero-progress-then-one',pic_packets(1,1,[(2,0x10,[[128,0,0,99]*64+[0,0]])]),True)
    add('mixed-extended-255-256',pic_packets(511,1,[(2,0xf0,[[128,0,255,1,2,3,0,128,1,0,4,5,6,255]])]),True)
    add('mixed-raw128-repeat128-one',pic_packets(257,1,[(2,0x90,[[127,*sum(([i,255-i] for i in range(128)),[]),255,17,0,0,37,255]])]),True)
    add('mixed-raw-pure-alpha-order',pic_packets(3,2,[
        (2,0x10,[[2,0,128,255],[2,255,128,0]]),
        (0,0xe0,[[1,2,3,4,5,6,7,8,9],[11,12,13,14,15,16,17,18,19]]),
        (1,0x80,[[0,99,1,21,255,22],[0,99,1,31,255,32]])]),True)
    for kind in (1,2):
        add(f'empty-mask-progress-{kind}',pic_packets(4,2,[(kind,0x0f,[[0,2,2],[0,2,2]] if kind==1 else [[128,0,0,3],[128,0,0,3]])])+[0],True)
    base=pic(1,1,[(0xe0,[0x12345678])])
    for value in (0,255):
        data=base.copy();data[4:88]=[value]*84;data[96:104]=[value]*8
        add(f'ignored-header-{value}',data,True)
    add('ignored-trailer',base+[83,128,246,52,80,73,67,84,0,255,17],True)
    add('encoded-over-one-mib',base+[0]*(1048577-len(base)))
    validate_cases(result);return result


def validate_controls(cases):
    if type(cases) is not list:raise ValueError('Invalid checked PIC controls')
    ids=set()
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','error'}:raise ValueError('Checked control schema differs')
        if type(case['id']) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',case['id']) is None or case['id'] in ids:raise ValueError('Invalid/duplicate control ID')
        ids.add(case['id'])
        if type(case['error']) is not int or case['error'] not in range(5):raise ValueError('Invalid checked error')
        if type(case['bytes']) is not list or any(type(v) is not int or not 0<=v<=4294967295 for v in case['bytes']):raise ValueError('Invalid checked byte domain')
        observed=checked_error(case['bytes'])
        if observed is None:raise ValueError('Accepted native input mislabeled as control')
        if observed!=case['error']:raise ValueError('Checked PIC scalar error differs')


def controls():
    legacy=legacy_fixtures()[1]
    if len(legacy)!=24:raise ValueError('Legacy PIC control inventory differs')
    result=[dict(c,id='legacy-'+c['id']) for c in legacy]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    base=pic(1,1,[(0xf0,[0x12345678])])
    for n in range(len(base)):add('prefix-'+str(n),base[:n],0 if n<=108 else 3)
    for n in range(len(base)):
        data=base.copy();data[n]=256;add('invalid-byte-'+str(n),data,1)
    for name,data in [('qoi',b'qoif'+bytes(30)),('bmp',b'BM'+bytes(60)),('png',b'\x89PNG\r\n\x1a\n'+bytes(50)),('pnm',b'P6\n1 1\n255\n\1\2\3'),('tga',bytes(30)),('gif',b'GIF89a'+bytes(40))]:add('non-pic-'+name,data,0)
    for offset in (92,94):
        for value in (0,4097,65535):
            data=base.copy();data[offset:offset+2]=[value>>8,value&255]
            add(f'axis-{offset}-{value}',data,2)
            add(f'byte-before-axis-{offset}-{value}',data+[256],1)
    for offset,values in ((105,(0,1,7,16,255)),(106,(3,4,127,255))):
        for value in values:
            data=base.copy();data[offset]=value;add(f'descriptor-{offset}-{value}',data,0)
            add(f'byte-before-descriptor-{offset}-{value}',data+[256],1)
    for offset in (0,88):
        data=base.copy();data[offset]=0;data[92:94]=[0,0];add(f'header-before-axis-{offset}',data,0)
    for value in (256,65536,4294967295):
        add('invalid-trailer-'+str(value),base+[value],1)
        add('invalid-short-header-'+str(value),[83,value],1)
        data=base.copy();data[40]=value;add('invalid-ignored-header-'+str(value),data,1)
    add('raw-empty-mask-descriptor-eof',pic(1,1,[(0,[0])])[:108],0)
    for count in (10,11):
        data=pic(1,1,[(0x10,[0])]*count)
        if count==10:data[104+4*(count-1)]=255
        add('unclosed-chain-'+str(count),data,0)
    for kind in (1,2):
        for mask in (0x00,0x0f,0x80,0xf0):
            add(f'post-control-eof-{kind}-{mask}',pic_packets(1,1,[(kind,mask,[[1 if kind==1 else 0]])]),3)
        for missing in (1,2,3):
            payload=[1,*([17]*(4-missing))] if kind==1 else [0,*([17]*(4-missing))]
            add(f'short-rgba-{kind}-{missing}',pic_packets(1,1,[(kind,0xf0,[payload])]),3)
    for name,width,mask,payload,error in [
        ('empty-extended-count-eof',1,0,[128],3),
        ('empty-extended-count-short',1,0,[128,0],3),
        ('empty-zero-extended-eof',1,0,[128,0,0],3),
        ('pure-zero-empty-eof',1,0,[0]*257,3),
        ('mixed-zero-empty-eof',1,0,[128,0,0]*257,3),
        ('literal-overrun-before-sample',1,0xf0,[1,17],4),
        ('repeat-overrun-before-sample',1,0xf0,[129,17],4),
        ('extended-overrun-before-sample',1,0xf0,[128,255,255],4),
        ('literal-overrun-empty-mask',1,0,[1,0],4),
        ('repeat-overrun-empty-mask',1,0,[129,0],4),
        ('extended-overrun-empty-mask',1,0,[128,0,2],4),
        ('extended-short-sample',1,0xf0,[128,0,1,1,2,3],3),
        ('raw128-short-sample',128,0x80,[127,*range(127)],3),
        ('repeat128-short-sample',128,0xf0,[255,1,2,3],3),
        ('zero-repeat-short-sample',1,0xf0,[128,0,0,1,2,3],3)]:
        kind=1 if name.startswith('pure-') else 2
        data=pic_packets(width,1,[(kind,mask,[payload])]);add(name,data,error)
        add('byte-before-'+name,data+[256],1)
    # Malformed later descriptors win before any earlier packet raster is read.
    data=pic(1,1,[(0x10,[0]),(0xe0,[0])]);data[109]=16
    add('late-descriptor-before-stream',data[:113],0)
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
    if role not in IMAGE_ROLES:raise ValueError('Unknown PIC image role')
    return dict(id=case['id'],role=role,width=case['width'],height=case['height'],mipmaps=1,
                format=FORMATS[case['channels']] if role in RAW_ROLES else 7)


def parse_rows(text, actions):
    if not actions:raise ValueError('Empty PIC observation batch')
    lines=text.splitlines();cursor=0;rows=[]
    for action in actions:
        case,role=action['case'],action['role']
        if cursor>=len(lines):raise ValueError('Missing PIC record')
        row=strict_json(lines[cursor]);cursor+=1
        if role in ('formatted-error','surface-error'):
            expected=dict(id=case['id'],role=role,error=case['error'])
        else:expected=meta(case,role)
        if type(row) is not dict or row!=expected or any(type(row.get(k)) is not type(v) for k,v in expected.items()):
            raise ValueError(f'PIC metadata/order/type differs: {case["id"]}/{role}: {row!r}')
        if role not in ('formatted-error','surface-error'):
            output=[];short=False
            while cursor<len(lines):
                chunk=strict_json(lines[cursor]);cursor+=1
                if chunk=='end':break
                if type(chunk) is not list or not 1<=len(chunk)<=256 or short or any(type(v) is not int or not 0<=v<=255 for v in chunk):raise ValueError('Malformed PIC byte chunk')
                short=len(chunk)<256;output.extend(chunk)
            else:raise ValueError('Unterminated PIC bytes')
            if len(output)!=case['width']*case['height']*{1:1,2:2,4:3,7:4}[row['format']]:raise ValueError('PIC byte count differs')
            row=dict(row,bytes=output)
        rows.append(row)
    if cursor!=len(lines):raise ValueError('Extra PIC records')
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
    case None{}: IO.die(Unit, 1, "valid PIC or owner invariant rejected")
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
    # Tiny independent known vectors qualify original 3/4-channel selection,
    # defaults, sticky descriptor OR and overwrite/RLE routing. Broad expected
    # pixels are always captured from native output, never decoded in Python.
    vectors=[('rgb',pic(1,1,[(0xe0,[0x01020380])]),4,[1,2,3]),
             ('rgba',pic(1,1,[(0xf0,[0x01020380])]),7,[1,2,3,128]),
             ('opaque-alpha',pic(1,1,[(0xf0,[0x010203ff])]),7,[1,2,3,255]),
             ('alpha-first',pic(1,1,[(0x10,[0x00000000]),(0xe0,[0x010203ff])]),7,[1,2,3,0]),
             ('alpha-middle',pic(1,1,[(0x80,[0x01000000]),(0x10,[0x00000080]),(0x60,[0x000203ff])]),7,[1,2,3,128]),
             ('empty-low-mask',pic(1,1,[(0x0f,[0])]),4,[255,255,255]),
             ('overlap',pic(1,1,[(0xf0,[0x010203ff]),(0x90,[0x09000000])]),7,[9,2,3,0]),
             ('pure-zero-clip',pic_packets(1,1,[(1,0xf0,[[0,9,8,7,6,255,1,2,3,0]])]),7,[1,2,3,0]),
             ('mixed-zero-extended',pic_packets(1,1,[(2,0xf0,[[128,0,0,9,8,7,6,128,0,1,1,2,3,128]])]),7,[1,2,3,128])]
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for name,data,fmt,expected in vectors:
        inspect_header(list(data))
        lines+=['/* '+name+' */ {const unsigned char data[]={'+','.join(map(str,data))+'};',
                'Image image=LoadImageFromMemory(".pic",data,sizeof(data));if(!image.data)return 11;',
                f'if(image.width!=1||image.height!=1||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(1,1,image.format)!={len(expected)}){{UnloadImage(image);return 12;}}',
                'const unsigned char *p=image.data;if('+ '||'.join(f'p[{i}]!={v}' for i,v in enumerate(expected))+'){UnloadImage(image);return 13;}UnloadImage(image);}' ]
    row=json.dumps(QUALIFICATION,separators=(',',':'))
    return '\n'.join(lines+['puts('+json.dumps(row)+');return 0;}'])+'\n'


QUALIFICATION=dict(little_endian=True,pic_enabled=True,all_descriptor_channels=True,
                   default_white=True,packet_overwrite=True,rle_rules=True,formats=[4,7])
QUALIFY=qualification_program()


def qualification(text):
    result=strict_json(text)
    if type(result) is not dict or result!=QUALIFICATION or any(type(result[k]) is not type(v) for k,v in QUALIFICATION.items()) or any(type(v) is not int for v in result['formats']):raise ValueError('Native PIC qualification differs')
    return result


def compact_segments(data):
    """Lossless runs keep large-trailer sources small; bytes stay in inputs.json."""
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
    return [dict(case=c,role=role) for c in cases for role in ('raw','normalized',*(('alias-PIC',) if c['extended'] else ()))]


def reference_program(cases):
    validate_cases(cases)
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        fmt=FORMATS[c['channels']];raw_size=c['width']*c['height']*c['channels']
        declaration,cleanup=native_input(c['bytes'])
        lines+=['{'+declaration,
                f'Image image=LoadImageFromMemory(".pic",data,{len(c["bytes"])});if(!image.data)return 2;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 3;}}',
                f'observed({json.dumps(c["id"])},"raw",image);',
                'ImageFormat(&image,7);if(!image.data)return 4;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!=7||GetPixelDataSize(image.width,image.height,image.format)!={c["width"]*c["height"]*4}){{UnloadImage(image);return 5;}}',
                f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);']
        if c['extended']:
            lines+=[f'image=LoadImageFromMemory(".PIC",data,{len(c["bytes"])});if(!image.data)return 6;',
                    f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 7;}}',
                    f'observed({json.dumps(c["id"])},"alias-PIC",image);UnloadImage(image);']
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
    if type(partitions) is not list or not partitions:raise ValueError('Empty native PIC partition plan')
    cursor=0
    for part in partitions:
        if type(part) is not dict or set(part)!={'start','count','observations','source_bytes','source_sha256','cases_sha256','compared_bytes'}:raise ValueError('Native PIC partition schema differs')
        if any(type(part[k]) is not int for k in ('start','count','observations','source_bytes','compared_bytes')):raise ValueError('Native PIC partition integer types differ')
        if part['start']!=cursor or part['count']<1 or cursor+part['count']>len(cases) or not 1<=part['observations']<=BATCH_SIZE or not 0<part['source_bytes']<=SOURCE_BYTE_LIMIT:raise ValueError('Native PIC partition order or budget differs')
        program=reference_program(cases[cursor:cursor+part['count']]).encode()
        if part!=native_partition_entry(cases,cursor,part['count'],program):raise ValueError('Native PIC partition source/input identity differs')
        cursor+=part['count']
    if cursor!=len(cases):raise ValueError('Incomplete native PIC partition coverage')


def plan_native_partitions(cases):
    validate_cases(cases);plan=[];start=0
    while start<len(cases):
        chosen=None
        for count in range(1,min(BATCH_SIZE,len(cases)-start)+1):
            selected=cases[start:start+count]
            if len(native_actions(selected))>BATCH_SIZE:break
            program=reference_program(selected).encode()
            if not program or len(program)>SOURCE_BYTE_LIMIT:
                if count==1:raise ValueError('Native PIC singleton source budget exceeded')
                break
            chosen=native_partition_entry(cases,start,count,program)
        if chosen is None:raise ValueError('Empty native PIC partition')
        plan.append(chosen);start+=chosen['count']
    validate_native_partitions(cases,plan);return plan


def finish_native(cases,partitions,batches):
    validate_native_partitions(cases,partitions)
    if type(batches) is not list or len(batches)!=len(partitions):raise ValueError('Native PIC batch count differs')
    for batch,part in zip(batches,partitions):
        if type(batch) is not dict or set(batch)!={*part,'bytes','passed','output_sha256'}:raise ValueError('Native PIC batch schema differs')
        if any(type(batch[k]) is not type(v) or batch[k]!=v for k,v in part.items()) or batch['passed'] is not True:raise ValueError('Native PIC batch partition differs')
        if type(batch['bytes']) is not int or batch['bytes']!=part['compared_bytes'] or type(batch['output_sha256']) is not str or re.fullmatch('[0-9a-f]{64}',batch['output_sha256']) is None:raise ValueError('Native PIC byte coverage/output digest differs')


def candidate_actions(cases,invalid,rows):
    validate_cases(cases);validate_controls(invalid)
    if {c['id'] for c in cases}&{c['id'] for c in invalid}:raise ValueError('PIC accepted/control IDs overlap')
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
            if rows[cursor]!=dict(raw,role='alias-PIC'):raise ValueError('Native PIC alias bytes differ')
            cursor+=1
        reference[c['id']]=(raw,normal)
    if cursor!=len(rows):raise ValueError('Native PIC reference count differs')
    actions=[]
    for c in cases:
        raw,normal=reference[c['id']]
        for role in ('raw','bridge','surface','factory','owner','raw-roundtrip',*(('dispatch-pic','dispatch-PIC','uncontracted','fused') if c['extended'] else ())):
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
        if action.get('role') not in ('raw','bridge','surface','factory','owner','raw-roundtrip','dispatch-pic','dispatch-PIC','uncontracted','fused','formatted-error','surface-error'):raise ValueError('Unknown PIC candidate role')
        c=action['case']
        if c['id'] in bound_cases and c!=bound_cases[c['id']]:raise ValueError('PIC action case identity differs')
        bound_cases[c['id']]=c
        if c['id'] not in bindings:
            name='input'+str(len(bindings));bindings[c['id']]=name
            lines.append(f'  +{name} = {{{input_expression(c["bytes"])} : +List<U32>}}')
    lines.append('  do IO<Unit>:')
    for action in actions:
        c=action['case'];role=action['role'];data=bindings[c['id']];ident=json.dumps(c['id'])
        decode=f'decoded(J.Image.Formatted.decode_pic({data}))'
        if role.endswith('-error'):
            mode=role.split('-')[0];call='J.Image.Formatted' if mode=='formatted' else 'J.Surface'
            lines.append(f'    emit.error({ident}, {json.dumps(role)}, {mode}.error({call}.decode_pic({data})))');continue
        if role=='raw':image=decode
        elif role=='bridge':image=f'bridge({decode})'
        elif role=='raw-roundtrip':image=f'roundtrip({decode})'
        elif role=='surface':image=f'surface(J.Surface.decode_pic({data}))'
        elif role.startswith('dispatch-'):image=f'surface(J.Surface.decode_image({json.dumps("."+role.split("-")[1])}, {data}))'
        elif role in ('uncontracted','fused'):image=f'surface(J.Surface.decode_image_for(J.{"UncontractedDecode" if role=="uncontracted" else "FusedDecode"}{{}}, ".PIC", {data}))'
        elif role=='factory':image=f'J.Image.Formatted.from_bytes({c["width"]}, {c["height"]}, {FORMATS[c["channels"]]}, {bend_bytes(action["expected"]["bytes"])})'
        elif role=='owner':
            normal=action['normalized'];first=int.from_bytes(bytes(normal[:4]),'big');last=int.from_bytes(bytes(normal[-4:]),'big')
            image=f'owner({decode}, {c["width"]}, {c["height"]}, {first}, {last})'
        else:raise ValueError('Unknown PIC observation')
        lines.append(f'    observed({ident}, {json.dumps(role)}, {image})')
    return '\n'.join(lines)+'\n'


def differences(expected,actual):
    if len(expected)!=len(actual):raise ValueError('PIC comparison count differs')
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
    if path in SEALED and SEALED[path]!=observed:raise ValueError('Sealed PIC artifact drift: '+path)
    SEALED[path]=observed


def verify_sealed():
    for path,expected in SEALED.items():
        if not Path(path).is_file() or digest(path)!=expected:raise ValueError('Sealed PIC artifact drift: '+path)


PROCESS_CLEANUP_SECONDS = 5


def run_process_group(command, *, cwd, env, timeout):
    """Bound the spawned POSIX group, then reap its direct child.

    Only this new session's PGID is signalled. Grandchildren that keep inherited
    pipes open cannot turn timeout cleanup into an unbounded communicate().
    The cleanup budget is separate from, and never extends, the work timeout.
    """
    if os.name!='posix':raise OSError('PIC process-group profile requires POSIX')
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
        raise ValueError('PIC child '+('timed out' if isinstance(failed,subprocess.TimeoutExpired) else 'could not start or communicate')+': '+label) from failed
    if proc.returncode:raise ValueError(f'{label} exited {proc.returncode}: {proc.stdout[-1000:]}{proc.stderr[-2500:]}')
    if require_output and not proc.stdout.strip():raise ValueError('Process output missing: '+label)
    if any(not p.is_file() or p.stat().st_size==0 for p in outputs):raise ValueError('Compiler output missing')
    return proc.stdout


def tracked_sources(args):
    paths=[ROOT/p for p in ('tools/pic_format_probe.py','tools/pic_format_audit.py','tests/test_pic_format_harness.py','tools/pic_probe.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','toolchain.json','LAWS.bend','PROOF.bend')]
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
    return result or [BUILD/'pic-format-probe']


def admit_directories(argv):
    paths=report_directories(argv)
    for path in dict.fromkeys(p.resolve() for p in paths):
        path.mkdir(parents=True,exist_ok=True);(path/'results.json').write_text('{"passed":false,"phase":"argument-validation"}\n')
    return paths[-1].resolve()


def validate_native_config(cache,flags):
    required={'PLATFORM':'Memory','CMAKE_BUILD_TYPE':'Release','CUSTOMIZE_BUILD':'ON','SUPPORT_FILEFORMAT_PIC':'ON','SUPPORT_MODULE_RAUDIO':'OFF','BUILD_EXAMPLES':'OFF','USE_EXTERNAL_GLFW':'OFF'}
    if type(cache) is not str or type(flags) is not str:raise ValueError('Native configuration text type differs')
    fields={}
    for line in cache.splitlines():
        if not line or line.startswith(('#','//')):continue
        entry=re.fullmatch(r'([^:=]+):[^=]+=(.*)',line)
        if entry is None:raise ValueError('Malformed native CMake cache field')
        key,value=entry.groups()
        if key in fields:raise ValueError('Duplicate native CMake cache field')
        fields[key]=value
    if any(fields.get(k)!=v for k,v in required.items()):raise ValueError('Native PIC cache configuration differs')
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
    for macro in ('SUPPORT_FILEFORMAT_PIC','EXTERNAL_CONFIG_FLAGS','PLATFORM_MEMORY'):
        selected=[t for t in definitions if t[2:].split('=')[0]==macro]
        if len(selected)!=1 or selected[0] not in ('-D'+macro,'-D'+macro+'=1'):raise ValueError('Actual native macro missing/disabled/ambiguous: '+macro)
    if any(t[2:].split('=')[0].startswith('PLATFORM_') and t[2:].split('=')[0]!='PLATFORM_MEMORY' for t in definitions):raise ValueError('Conflicting native platform macro')
    return required


def native_archive(args,work,record):
    cmake=work/'raylib-build'
    if cmake.exists():raise ValueError('Native build directory must be fresh')
    record(['cmake','-S',args.raylib_source,'-B',cmake,'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DSUPPORT_FILEFORMAT_PIC=ON','-DUSE_EXTERNAL_GLFW=OFF'],work,'configure')
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
    if type(actions) is not list or not actions:raise ValueError('Empty PIC action sequence')
    identities=set()
    for action in actions:
        if type(action) is not dict or type(action.get('case')) is not dict or type(action.get('role')) is not str or type(action.get('expected')) is not dict:raise ValueError('Malformed PIC action')
        identity=(action['case'].get('id'),action['role'])
        if type(identity[0]) is not str or identity in identities:raise ValueError('Invalid/duplicate PIC action identity')
        identities.add(identity)
        if (action['expected'].get('id'),action['expected'].get('role'))!=identity:raise ValueError('PIC action/reference identity differs')
        values=action['expected'].get('bytes',[])
        if type(values) is not list or any(type(v) is not int or not 0<=v<=255 for v in values):raise ValueError('Invalid PIC action reference bytes')


def action_digest(actions):
    return hashlib.sha256(json.dumps(actions,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


def partition_entry(actions,start,count,program):
    selected=actions[start:start+count]
    return dict(start=start,count=count,source_bytes=len(program),source_sha256=hashlib.sha256(program).hexdigest(),
                actions_sha256=action_digest(selected),compared_bytes=sum(len(a['expected'].get('bytes',[])) for a in selected))


def validate_partitions(actions,partitions,source_limit=SOURCE_BYTE_LIMIT):
    """Require an exact ordered, exhaustive plan against regenerated sources."""
    validate_action_sequence(actions)
    if type(source_limit) is not int or not 0<source_limit<=SOURCE_BYTE_LIMIT:raise ValueError('Invalid PIC partition source budget')
    if type(partitions) is not list or not partitions:raise ValueError('Empty PIC partition plan')
    cursor=0
    for entry in partitions:
        if type(entry) is not dict or set(entry)!={'start','count','source_bytes','source_sha256','actions_sha256','compared_bytes'}:raise ValueError('PIC partition schema differs')
        if any(type(entry[k]) is not int for k in ('start','count','source_bytes','compared_bytes')):raise ValueError('PIC partition integer type differs')
        if entry['start']!=cursor or not 1<=entry['count']<=BATCH_SIZE or cursor+entry['count']>len(actions):raise ValueError('Noncontiguous/incomplete PIC partition')
        if not 0<entry['source_bytes']<=source_limit or entry['compared_bytes']<0:raise ValueError('PIC partition budget differs')
        selected=actions[cursor:cursor+entry['count']];program=candidate_program(selected).encode('utf-8')
        expected=partition_entry(actions,cursor,entry['count'],program)
        if entry!=expected or any(type(entry[k]) is not type(v) for k,v in expected.items()):raise ValueError('PIC partition source/action identity differs')
        cursor+=entry['count']
    if cursor!=len(actions):raise ValueError('Incomplete PIC partition coverage')


def plan_partitions(actions,source_limit=SOURCE_BYTE_LIMIT):
    """Greedy complete ordered partitions; only compilation grouping changes.

    Both the 32-action maximum and the exact generated UTF-8 byte budget apply.
    No fixture, role, reference byte, runtime limit or oracle is changed.
    """
    validate_action_sequence(actions)
    if type(source_limit) is not int or not 0<source_limit<=SOURCE_BYTE_LIMIT:raise ValueError('Invalid PIC partition source budget')
    plan=[];start=0
    while start<len(actions):
        selected=None
        for count in range(1,min(BATCH_SIZE,len(actions)-start)+1):
            program=candidate_program(actions[start:start+count]).encode('utf-8')
            if not program:raise ValueError('Empty generated PIC source')
            if len(program)>source_limit:
                if count==1:raise ValueError('PIC singleton exceeds source budget: '+str(start))
                break
            selected=partition_entry(actions,start,count,program)
        if selected is None:raise ValueError('Empty PIC partition')
        plan.append(selected);start+=selected['count']
    validate_partitions(actions,plan,source_limit)
    return plan


def finish_lanes(lanes,actions,partitions):
    validate_partitions(actions,partitions)
    if set(lanes)!=set(LANES):raise ValueError('Missing mandatory PIC lanes/cases')
    expected_bytes=sum(len(a['expected'].get('bytes',[])) for a in actions)
    for lane in LANES:
        if type(lanes[lane]) is not dict or type(lanes[lane].get('batches')) is not list or type(lanes[lane].get('differences')) is not list:raise ValueError('Malformed PIC lane')
        batches=lanes[lane]['batches']
        if len(batches)!=len(partitions):raise ValueError('Incomplete PIC lane partition count')
        observations=compared_bytes=0
        for batch,planned in zip(batches,partitions):
            if type(batch) is not dict or set(batch)!={*planned,'bytes','passed'}:raise ValueError('PIC lane batch schema differs')
            if any(type(batch[k]) is not type(v) or batch[k]!=v for k,v in planned.items()) or batch['passed'] is not True:raise ValueError('PIC lane differs from exact partition plan')
            if type(batch['bytes']) is not int or batch['bytes']!=planned['compared_bytes']:raise ValueError('PIC lane byte coverage differs')
            observations+=batch['count'];compared_bytes+=batch['bytes']
        if observations!=len(actions) or compared_bytes!=expected_bytes or lanes[lane]['differences']:raise ValueError('Incomplete or differing PIC lane: '+lane)
    for lane in LANES:lanes[lane]['passed']=True


def inventory(actions):
    """Persist every ordered observation identity, separate from batch counts."""
    result=[];seen=set()
    for action in actions:
        if type(action) is not dict or type(action.get('case')) is not dict:raise ValueError('Malformed PIC inventory action')
        name=action['case'].get('id');role=action.get('role')
        if type(name) is not str or type(role) is not str or (name,role) in seen:raise ValueError('Invalid/duplicate PIC inventory identity')
        seen.add((name,role));result.append(dict(id=name,role=role))
    if not result:raise ValueError('Empty PIC action inventory')
    return result


def validate_inventory(observed,actions):
    expected=inventory(actions)
    if type(observed) is not list or len(observed)!=len(expected):raise ValueError('Incomplete PIC action inventory')
    for actual,wanted in zip(observed,expected):
        if type(actual) is not dict or set(actual)!=set(wanted) or any(type(actual[k]) is not str or actual[k]!=v for k,v in wanted.items()):raise ValueError('PIC action inventory order/identity differs')


def run_probe(argv):
    SEALED.clear();admitted=admit_directories(argv)
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--build-dir',type=Path,default=BUILD/'pic-format-probe')
    parser.add_argument('--reference-env',choices=('clean-loader',),default='clean-loader')
    parser.add_argument('--timeout',type=int,default=600)
    args=parser.parse_args(argv);destination=args.build_dir.resolve()
    args.bend_source=args.bend_source.resolve();args.raylib_source=args.raylib_source.resolve()
    if destination!=admitted:parser.error('Destination admission differs')
    if args.timeout<=0:parser.error('--timeout must be positive')
    reference_env=ReferenceEnvironment(args.reference_env)
    record=partial(record_run,timeout=args.timeout)
    native_record=partial(record,environment=reference_env.child(),receipt=reference_env.receipt())
    report_path=destination/'results.json';work=destination/('run-'+uuid.uuid4().hex);work.mkdir()
    started=time.monotonic();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if sys.byteorder!='little':raise ValueError('PIC profile requires little endian')
    cases,invalid=fixtures(),controls();validate_cases(cases)
    inputs=work/'inputs.json';inputs.write_text(json.dumps(dict(cases=cases,controls=invalid),sort_keys=True)+'\n');seal(inputs)
    tool_paths={}
    for tool in ('bun','clang','cmake'):
        path=shutil.which(tool)
        if path is None:raise ValueError('Required tool missing: '+tool)
        tool_paths[tool]=str(Path(path).absolute());seal(path)
    tool_realpaths={k:str(Path(p).resolve()) for k,p in tool_paths.items()}
    report=dict(passed=False,oracle_source_ranges=validate_reference_sources(args.raylib_source),profile='native-pic-formatted-memory-v1',reconstruction='fresh implementation; no previous runtime evidence reused',run_directory=str(work),toolchain=lock,base_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),host=dict(system=platform.system(),machine=platform.machine()),tool_paths=tool_paths,tool_realpaths=tool_realpaths,sources=tracked_sources(args),reference_environment=reference_env.receipt(),inputs_sha256=digest(inputs),legacy_cases=33,legacy_pixels=8867,legacy_controls=24,native_content_admission='strict global byte domain; actual PIC signature/header/all descriptors/all row packet controls and samples; malformed controls never native',cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(invalid),native_rejections=0,batch_size=BATCH_SIZE,source_byte_limit=SOURCE_BYTE_LIMIT,partition_strategy='ordered-greedy-generated-source-v1',lanes={lane:dict(passed=False,batches=[],differences=[]) for lane in LANES},candidate_mipmaps='implicit single-mip type contract, not stored/measured',unrun=['GPU/Metal','Windows/browser','big-endian','exact-commit hosted CI','4096x4096 allocation/resource limits','representative performance','formatted file IO','generic formatted/float dispatch','native malformed recovery'])
    report['native_action_inventory']=inventory(native_actions(cases))
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
        if native_partition_entry(cases,part['start'],part['count'],program)!=part:raise ValueError('Native PIC source drift before compilation')
        source=work/f'reference-{index}.c';source.write_bytes(program);seal(source);binary=work/f'reference-{index}'
        native_record(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,f'reference-{index}-compile')
        output=native_record([binary],work,f'reference-{index}',require_output=True)
        rows=parse_rows(output,native_actions(selected));native_rows.extend(rows);native_outputs.append(output)
        report['native_batches'].append(dict(part,bytes=sum(len(row['bytes']) for row in rows),passed=True,output_sha256=hashlib.sha256(output.encode()).hexdigest()));save()
    finish_native(cases,native_plan,report['native_batches'])
    report['reference_sha256']=hashlib.sha256(''.join(native_outputs).encode()).hexdigest();save()
    actions,reference=candidate_actions(cases,invalid,native_rows)
    report['action_inventory']=inventory(actions)
    report.update(native_observations=len(native_rows),native_raw_bytes=sum(len(raw['bytes']) for raw,_ in reference.values()),native_normalized_bytes=sum(len(normal['bytes']) for _,normal in reference.values()),native_all_observed_bytes=sum(len(r['bytes']) for r in native_rows),observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions),raw_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] in ('raw','factory','owner','raw-roundtrip')),normalized_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] not in ('raw','factory','owner','raw-roundtrip')));save()
    partitions=plan_partitions(actions);report.update(partition_plan=partitions,planned_batches=len(partitions));save()
    for index,partition in enumerate(partitions):
        start=partition['start'];selected=actions[start:start+partition['count']]
        program=candidate_program(selected).encode('utf-8')
        if partition_entry(actions,start,len(selected),program)!=partition:raise ValueError('PIC generated partition drift before compilation')
        source=work/f'candidate-{index}.bend';source.write_bytes(program);seal(source)
        binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,f'compile-{index}')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual=parse_rows(record(command,work,f'{lane}-{index}',require_output=True),selected)
            delta=differences([a['expected'] for a in selected],actual)
            report['lanes'][lane]['differences'].extend(delta)
            report['lanes'][lane]['batches'].append(dict(partition,bytes=sum(len(r.get('bytes',[])) for r in actual),passed=not delta));save()
        print(f'PIC batch {index+1}: {len(selected)} observations compared on CPU-1/CPU-2/JavaScript',flush=True)
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    reference_env.assert_receipt(report['reference_environment'])
    if any(shutil.which(k) is None or str(Path(shutil.which(k)).absolute())!=p or str(Path(shutil.which(k)).resolve())!=tool_realpaths[k] for k,p in tool_paths.items()):raise ValueError('Tool executable resolution drift')
    if tracked_sources(args)!=report['sources']:raise ValueError('Source/toolchain/native input drift')
    validate_inventory(report['native_action_inventory'],native_actions(cases));validate_inventory(report['action_inventory'],actions)
    finish_native(cases,native_plan,report['native_batches']);finish_lanes(report['lanes'],actions,partitions);verify_sealed()
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3),sealed_artifacts=dict(SEALED));save()
    print(f'PASS: {len(cases)} native PIC images, {len(invalid)} checked-only typed controls, {report["compared_bytes_per_lane"]} bytes per lane',flush=True)


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
            if hasattr(error,'add_note'):error.add_note('Could not save failed PIC report: '+str(report_error))
        raise


if __name__=='__main__':main()
