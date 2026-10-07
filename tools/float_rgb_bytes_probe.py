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
def header(+width: U32, +height: U32) -> List<U32>:
  List.reverse(&1, U32, word_bytes(4n, height, word_bytes(4n, width, Nil{})))
'''+BEND_EMITTER+'''
def emit_values(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: emit_bytes(~&1, List.append(&1, U32, header(width, height), bytes))
    case _: IO.die(Unit, 1, "raw float export format changed")
def raw_bytes(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{_, Tuple{9, bytes}}: emit_bytes(~&1, bytes)
    case _: IO.die(Unit, 1, "raw float export format changed")
def emit_image(result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid raw float import rejected")
    case Some{image}: emit_values(J.Surface.export(image))
def emit_export(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid float conversion rejected")
    case Done{image}: raw_bytes(J.Surface.export(image))
def emit_roundtrip(result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid raw float round trip rejected")
    case Some{image}: raw_bytes(J.Surface.export(image))
def rejected(result: Maybe<J.Surface>) -> U32:
  match result:
    case None{}: 1
    case Some{_}: 0
def byte_pixels(n: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match n:
    case 0n: pixels
    case 1n+rest: byte_pixels(rest, (index + 1 : U32), Array.set(U32, pixels, index, J.Color.rgba(index, (255 - index : U32), (index .^. 85 : U32), index)))
def native_export() -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  J.Surface.format(J.Surface{256, 1, 7, J.Words{byte_pixels(256n, 0, Array.new(U32, 8n, 0))}}, 9)
# Checked writers reject NaN R32G32B32 samples before opening the file; the owner
# comes back intact (compared with same-backend bits: payloads are not portable).
def nan_owner() -> J.Surface:
  pixels = Array.set(M.Vector3, Array.new(M.Vector3, 1n, M.Vector3{0.25, 0.5, 0.75}), 1, M.Vector3{H.float_bits(2143294004), 0.5, 0.75})
  J.Surface{2, 1, 9, J.Vectors{pixels}}
def vector_is.bits(+r: U32, +g: U32, +b: U32, value: M.Vector3) -> Bool:
  M.Vector3{x, y, z} = value
  U32.is_eq(F32.bits(x), r) && U32.is_eq(F32.bits(y), g) && U32.is_eq(F32.bits(z), b)
def vector_is(+r: U32, +g: U32, +b: U32, result: Array<M.Vector3> & M.Vector3) -> Array<M.Vector3> & Bool:
  (values, value) = result
  (values, vector_is.bits(r, g, b, value))
def owner.second(first: Bool, result: Array<M.Vector3> & Bool) -> Bool:
  (_, second) = result
  first && second
def owner.first(result: Array<M.Vector3> & Bool) -> Bool:
  (values, first) = result
  owner.second(first, vector_is(F32.bits(H.float_bits(2143294004)), 1056964608, 1061158912, Array.get(M.Vector3, values, 1)))
def owner_intact(image: J.Surface) -> Bool:
  match image:
    case J.Surface{2, 1, 9, J.Vectors{values}}: owner.first(vector_is(1048576000, 1056964608, 1061158912, Array.get(M.Vector3, values, 0)))
    case _: False{}
def nan_rejected(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.OutOfDomain{}}}: emit_bytes(~&1, [Bool.to_u32(owner_intact(image))])
    case _: IO.die(Unit, 1, "NaN raw write was not rejected with its owner")
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
    nan_target=probe.work/'rejected-nan.raw';nan_target.unlink(missing_ok=True)
    actions=[]
    for case in cases:
        arguments=f'{case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])}'
        actions+=[f'emit_image(J.Surface.from_bytesBANG({arguments}))',f'emit_roundtrip(J.Surface.from_bytesBANG({arguments}))']
    actions.append('emit_export(native_exportBANG())')
    actions+=[f'emit_bytes(~&1, [rejected(J.Surface.from_bytesBANG({case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])}))])' for case in invalid]
    actions.append(f'IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_raw(nan_ownerBANG(), {json.dumps(str(nan_target.relative_to(ROOT)))}), nan_rejected)')
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    if nan_target.exists():raise ProbeFailure('Rejected NaN raw write created its target file')
    probe.finish(native_images=len(cases),pixels=sum(c['width']*c['height'] for c in cases),export_bytes=3072,invalid_controls=len(invalid),owner_controls=1,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,invalid]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
