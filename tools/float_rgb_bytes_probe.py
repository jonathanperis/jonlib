#!/usr/bin/env python3
"""Check exact non-NaN format-9 raw words, byte round trips and owned failures."""
import hashlib
import json
import random
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(const char *path,int w,int h){Image image=LoadImageRaw(path,w,h,PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);if(!image.data)exit(2);',
           'word(image.width);word(image.height);for(int i=0;i<w*h*12;i++)byte(((unsigned char*)image.data)[i]);end();',
           'for(int i=0;i<w*h*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/hdr.bend as H
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def samples(pixels: List<M.Vector3>, values: List<U32>) -> List<U32>:
  match pixels:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{M.Vector3{r, g, b}, rest}: samples(rest, word_bytes(4n, F32.bits(b), word_bytes(4n, F32.bits(g), word_bytes(4n, F32.bits(r), values))))
'''+BEND_EMITTER+'''
def emit_values(result: U32 & U32 & List<M.Vector3>) -> IO(Unit):
  (width, height, pixels) = result
  emit_bytes(~&1, samples(pixels, word_bytes(4n, height, word_bytes(4n, width, Nil{}))))
def emit_image(result: Maybe<J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid raw float import rejected")
    case Some{image}: emit_values(J.Image.FloatRGB.entries(image))
def emit_export(result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid raw float export rejected")
    case Done{bytes}: emit_bytes(~&2, bytes)
def exported(result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match result:
    case Fail{_}: None{}
    case Done{bytes}: Some{bytes}
def export_checked(result: Maybe<J.Image.FloatRGB>) -> Maybe<&2, +List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: exported(J.Image.FloatRGB.to_bytes(image))
def roundtrip(width: U32, height: U32, bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  export_checked(J.Image.FloatRGB.from_bytes(width, height, bytes))
def emit_roundtrip(result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid raw float round trip rejected")
    case Some{bytes}: emit_bytes(~&2, bytes)
def rejected(result: Maybe<J.Image.FloatRGB>) -> U32:
  match result:
    case None{}: 1
    case Some{_}: 0
def byte_pixels(n: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: byte_pixels(rest, (index + 1 : U32), Array.set(U32, pixels, index, J.Color.rgba(index, (255 - index : U32), (index .^. 85 : U32), index)))
def native_export() -> Result<&1, &1, J.Image.FloatRGB, +List<U32>>:
  J.Image.FloatRGB.to_bytes(J.Surface.to_float_rgb(J.Surface{256, 1, byte_pixels(256n, 0, Array.new(U32, 8n, 0))}))
def owner_values(values: List<M.Vector3>) -> Bool:
  match values:
    case Con{M.Vector3{a, b, c}, Con{M.Vector3{x, y, z}, Nil{}}}:
      F32.is_eq(a, 0.25) && F32.is_eq(b, 0.5) && F32.is_eq(c, 0.75)
        && U32.is_eq(F32.bits(x), F32.bits(H.float_bits(2143294004))) && F32.is_eq(y, 0.5) && F32.is_eq(z, 0.75)
    case _: False{}
def owner_entries(result: U32 & U32 & List<M.Vector3>) -> Bool:
  (width, height, values) = result
  U32.is_eq(width, 2) && U32.is_eq(height, 1) && owner_values(values)
def owner(result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> Bool:
  match result:
    case Done{_}: False{}
    case Fail{image}: owner_entries(J.Image.FloatRGB.entries(image))
def rejected_owner() -> Bool:
  pixels = Array.set(M.Vector3, Array.new(M.Vector3, 1n, M.Vector3{0.25, 0.5, 0.75}), 1, M.Vector3{H.float_bits(2143294004), 0.5, 0.75})
  owner(J.Image.FloatRGB.to_bytes(J.FloatRGB{2, 1, pixels}))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    classes=[0,0x80000000,1,0x80000001,0x007fffff,0x807fffff,0x00800000,0x80800000,
             0x3f800000,0xbf800000,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x3f000000]
    exponents=[(sign<<31)|(exponent<<23)|mantissa for sign in (0,1) for exponent in range(255) for mantissa in (0,1,0x7fffff)]
    rng=random.Random(0x32b17);random_words=[]
    while len(random_words)<3072:
        word=rng.getrandbits(32)
        if word&0x7fffffff<=0x7f800000:random_words.append(word)
    cases=[]
    for name,width,height,words in [('classes',5,1,classes),('exponents',255,2,exponents),('random',64,16,random_words)]:
        cases.append(dict(id=name,width=width,height=height,bytes=list(b''.join(struct.pack('<I',word) for word in words))))
    valid=cases[0]['bytes'][:12]
    invalid=[dict(id='zero-width',width=0,height=1,bytes=valid),dict(id='large-height',width=1,height=4097,bytes=valid),
             dict(id='short',width=1,height=1,bytes=valid[:-1]),dict(id='excess',width=1,height=1,bytes=valid+[0]),
             dict(id='byte',width=1,height=1,bytes=[256,*valid[1:]])]
    for index,bits in enumerate((0x7f800001,0x7fc01234,0xffc00001)):
        words=[0x3e800000,0x3f000000,0x3f400000];words[index]=bits
        invalid.append(dict(id=f'nan-{index}',width=1,height=1,bytes=list(struct.pack('<III',*words))))
    return cases,invalid


def reference_program(cases,work):
    lines=list(PRELUDE)
    for case in cases:
        path=work/(case['id']+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'emit({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]});')
    exported=work/'native-normalized.raw'
    lines += ['Image image=GenImageColor(256,1,BLANK);for(int i=0;i<256;i++)((Color*)image.data)[i]=(Color){i,255-i,i^0x55,i};',
              'ImageFormat(&image,PIXELFORMAT_UNCOMPRESSED_R32G32B32);',
              f'if(!ExportImage(image,{json.dumps(str(exported.relative_to(ROOT)))}))return 3;UnloadImage(image);',
              f'int size=0;unsigned char *data=LoadFileData({json.dumps(str(exported.relative_to(ROOT)))},&size);if(size!=3072)return 4;',
              'for(int i=0;i<size;i++)byte(data[i]);end();UnloadFileData(data);return 0;}']
    return '\n'.join(lines)+'\n'


def main():
    probe=probekit.Probe('float-rgb-bytes',probekit.arguments(__doc__))
    cases,invalid=fixtures();text=probe.native(reference_program(cases,probe.work));expected=parse_results(text)
    if len(expected)!=2*len(cases)+1:raise ProbeFailure('Incomplete native raw float results')
    for i,case in enumerate(cases):
        if expected[2*i]!=list(struct.pack('<II',case['width'],case['height']))+case['bytes'] or expected[2*i+1]!=case['bytes']:raise ProbeFailure('Native raw layout differs')
    wanted=expected+[[1] for _ in invalid]+[[1]];probe.report['sources']=source_gate()
    actions=[]
    for case in cases:
        arguments=f'{case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])}'
        actions+=[f'emit_image(J.Image.FloatRGB.from_bytesBANG({arguments}))',f'emit_roundtrip(roundtripBANG({arguments}))']
    actions.append('emit_export(native_exportBANG())')
    actions+=[f'emit_bytes(~&1, [rejected(J.Image.FloatRGB.from_bytesBANG({case["width"]}, {case["height"]}, {bend_bytes(case["bytes"])}))])' for case in invalid]
    actions.append('emit_bytes(~&1, [Bool.to_u32(rejected_ownerBANG())])')
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(native_images=len(cases),pixels=sum(c['width']*c['height'] for c in cases),export_bytes=3072,invalid_controls=len(invalid),owner_controls=1,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,invalid]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
