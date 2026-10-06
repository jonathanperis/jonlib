#!/usr/bin/env python3
"""Strict native format-9 -> bounded R32 differential gate, with owner controls.

Expected conversion bytes come exclusively from the pinned ImageFormat. The
volatile C arithmetic control only qualifies the archive's uncontracted profile;
Python arithmetic generates inputs, never expected conversion outputs.
"""
import hashlib
import itertools
import json
import random
import struct
import sys

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from float_rgb_formats_probe import fixtures as previous_fixtures
from image_format_probe import r32_words, word_bytes
import probekit
from probekit import ProbeFailure

BATCH_OPERATIONS = 8
INVALID_WORDS = (0x80000001,0x807fffff,0x80800000,0xbf000000,0x3f800001,
                 0x7f7fffff,0x7f800000,0xff800000)
NAN_WORDS = (0x7fc00000,0x7f800001,0xffc12345)


def fixture(name, pixels, width=None, source=9, targets=None, **extra):
    width = len(pixels) if width is None else width
    return dict(name=name,width=width,height=len(pixels)//width,source=source,
                bytes=word_bytes([word for pixel in pixels for word in pixel]),
                targets=[8] if targets is None else targets,**extra)


def fixtures():
    cases = [fixture('signed-zero-corners',list(itertools.product((0,0x80000000),repeat=3))),
             fixture('unit-corners',list(itertools.product((0,0x3f800000),repeat=3))),
             fixture('one-predecessors',list(itertools.product((0x3f7ffffe,0x3f7fffff,0x3f800000),repeat=3)),width=3)]
    boundary = (0,0x80000000,1,2,0x007ffffe,0x007fffff,0x00800000,0x00800001)
    pixels = list(itertools.product(boundary,repeat=3))
    for word in boundary:
        for component in range(3):
            pixel = [0x3e800000,0x3f000000,0x3f400000];pixel[component] = word;pixels.append(pixel)
    cases.append(fixture('subnormal-normal-equal-mixed',pixels,width=8))
    previous,_ = previous_fixtures()
    for name,case in (('packed-boundaries',previous[0]),('gray-boundaries',previous[7])):
        cases.append(dict(case,name=name,source=9,targets=[8]));cases[-1].pop('target')
    # Native normalized [0,17,51] is a discriminator against contracted luminance.
    words = [struct.unpack('<I',struct.pack('<f',v/255))[0] for v in (0,17,51)]
    cases.append(fixture('contraction-discriminator',[words]))
    rng = random.Random(0x9328)
    pixels = [tuple((rng.randrange(127)<<23)|rng.randrange(1<<23) for _ in range(3)) for _ in range(1024)]
    cases.append(fixture('seeded-exponent-spread',pixels,width=32))
    thin = pixels[:31]
    cases += [fixture('thin-row',thin),fixture('thin-column',thin,width=1),fixture('rectangle',pixels[:35],width=7)]
    pattern = [0,0x80000000,1, 0x007fffff,0x00800000,0x00800001,
               0x3f7fffff,0x3f800000,0x3f000000, 0x3d088888,0x3c020820,0x3f400000]
    cases.append(dict(name='large-full-traversal',width=256,height=129,source=9,
                      bytes=word_bytes(pattern*8256),repeat_words=pattern,repeat_count=8256,targets=[8]))
    for selected in (cases[0],cases[2],cases[5],cases[7]):
        cases.append(dict(selected,name=selected['name']+'-9-8-9',targets=[8,9]))
    words = r32_words()
    cases.append(fixture('8-9-8',[(word,) for word in words],source=8,targets=[9,8]))
    return cases


def controls():
    result = []
    base = [[0x80000000,1,0x3f400000],[0x3e800000,0x3f000000,0x3f800000],[2,0x007fffff,0x00800000]]
    for word,component,position in itertools.product(INVALID_WORDS,range(3),range(3)):
        pixels = [p[:] for p in base];pixels[position][component] = word
        result.append(fixture(f'reject-{word:08x}-component{component}-position{position}',pixels,
                              reject=True,targets=[8]))
    for target in (0,9,0xffffffff):
        result.append(fixture(f'unsupported-target-{target}',base,reject=True,targets=[target]))
    # NaNs are constructed directly and compared against same-backend owner bits;
    # they never pass through a raw-byte bridge or claim NaN payload interoperability.
    for word,component,position in itertools.product(NAN_WORDS,range(3),range(3)):
        result.append(dict(name=f'direct-nan-{word:08x}-{component}-{position}',nan=word,
                           component=component,position=position))
    return result


def shapes(ops):
    result = []
    for op in ops:
        if 'nan' in op:
            result.append(dict(exact=[1]));continue
        if op.get('reject'):
            row = list(struct.pack('<III',op['width'],op['height'],9))+op['bytes']
            # The retained owner is exported and independently copied/used.
            result.extend([dict(exact=row),dict(exact=row)])
        else:
            target = op['targets'][-1]
            result.append(dict(width=op['width'],height=op['height'],format=target,
                               size=(12 if target==9 else 4)*op['width']*op['height']))
    return result


def parse_rows(text, expected_shapes):
    rows = parse_results(text)
    if len(rows) != len(expected_shapes):
        raise ValueError(f'FloatRGB/R32 result count differs: {len(rows)} != {len(expected_shapes)}')
    for index,(row,shape) in enumerate(zip(rows,expected_shapes)):
        if type(row) is not list or any(type(v) is not int or not 0 <= v <= 255 for v in row):
            raise ValueError(f'Malformed FloatRGB/R32 byte row {index}')
        if 'exact' in shape:
            valid = row == shape['exact']
        else:
            valid = (len(row)==12+shape['size'] and row[:12]==list(struct.pack('<III',shape['width'],shape['height'],shape['format'])))
        if valid and shape.get('format')==8:
            words = struct.unpack('<'+'I'*(shape['size']//4),bytes(row[12:]))
            valid = all(word<=0x3f800000 or word==0x80000000 for word in words)
        if not valid:
            raise ValueError(f'FloatRGB/R32 metadata, owner or byte length differs at {index}')
    return rows


C_PREAMBLE = r'''#include "raylib.h"
#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
_Static_assert(sizeof(float)==4 && sizeof(unsigned)==4 && FLT_RADIX==2 && FLT_MANT_DIG==24 && FLT_MAX_EXP==128, "binary32 and 32-bit words required");
static int used=0;
static void byte(unsigned v){if(!used)putchar('[');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}
static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}
static void end(void){if(used){puts("]");used=0;}puts("\"end\"");}
static void emit(Image image){if(!image.data||image.mipmaps!=1)exit(2);word(image.width);word(image.height);word(image.format);
int n=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<n;i++)byte(((unsigned char*)image.data)[i]);end();}
'''


def c_image(op):
    if 'repeat_words' in op:
        lines = ['unsigned pattern[]={'+','.join(map(str,op['repeat_words']))+'};',
                 f'unsigned char data[{len(op["bytes"])}];for(unsigned i=0;i<sizeof(data)/4;i++)memcpy(data+4*i,pattern+i%{len(op["repeat_words"])},4);']
    else:
        lines = ['unsigned char data[]={'+','.join(map(str,op['bytes']))+'};']
    return '\n'.join(lines+[f'Image image={{malloc(sizeof(data)),{op["width"]},{op["height"]},1,{op["source"]}}};',
                            'if(!image.data)exit(3);memcpy(image.data,data,sizeof(data));'])


def reference_program(ops):
    lines = [C_PREAMBLE,'int main(void){SetTraceLogLevel(LOG_NONE);']
    for op in ops:
        if 'nan' in op:
            lines.append('byte(1);end();');continue
        lines += ['{',c_image(op)]
        if op.get('reject'):
            # Native original words only; rejection is Jonlib's bounded adaptation.
            lines.append('emit(image);emit(image);')
        else:
            lines.extend(f'ImageFormat(&image,{target});' for target in op['targets'])
            lines.append('emit(image);')
        lines.append('UnloadImage(image);}')
    return '\n'.join(lines+['}'])+'\n'


def qualification_program(cases):
    """A native-only profile check, separate from differential expected results."""
    lines = [C_PREAMBLE,r'''static unsigned bits(float f){unsigned u;memcpy(&u,&f,4);return u;}
int main(void){SetTraceLogLevel(LOG_NONE);unsigned n=0,bad=0,fused_diff=0;
''']
    for case in cases:
        if case['source'] != 9 or case['targets'] != [8]:continue
        lines += ['{',c_image(case),'ImageFormat(&image,8);',
                  'for(unsigned i=0;i<sizeof(data)/12;i++){float in[3],out;memcpy(in,data+12*i,12);memcpy(&out,(unsigned char*)image.data+4*i,4);volatile float r=in[0]*0.299f,g=in[1]*0.587f,b=in[2]*0.114f;volatile float rg=r+g;float u=rg+b;float f=fmaf(in[2],0.114f,fmaf(in[1],0.587f,r));n++;bad+=bits(out)!=bits(u);fused_diff+=bits(out)!=bits(f);}',
                  'UnloadImage(image);}']
    return '\n'.join(lines+['printf("{\\"pixels\\":%u,\\"uncontracted_mismatches\\":%u,\\"fused_differences\\":%u}\\n",n,bad,fused_diff);return 0;}'])+'\n'


BEND_PREAMBLE = '''import Base
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
def repeat_bytes(n: Nat, +chunk: +List<U32>, values: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, values)
    case 1n+rest: repeat_bytes(rest, chunk, reverse_into(chunk, values))
def word_bytes(~q: Quant, n: Nat, +word: U32, values: List<q, U32>) -> List<q, U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(~q, rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
'''+BEND_EMITTER+'''
def emitted(~q: Quant, width: U32, height: U32, format: U32, bytes: List<q, U32>) -> IO(Unit):
  header = List.reverse(q, U32, word_bytes(~q, 4n, format, word_bytes(~q, 4n, height, word_bytes(~q, 4n, width, Nil{}))))
  emit_bytes(~q, List.append(q, U32, header, bytes))
def formatted(result: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = result
  emitted(~&1, width, height, format, bytes)
def float_bytes(width: U32, height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: emitted(~&2, width, height, 9, bytes)
    case _: IO.die(Unit, 1, "float owner byte export rejected")
def float_image(image: J.Image.FloatRGB) -> IO(Unit):
  J.FloatRGB{+width, +height, pixels} = image
  float_bytes(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def retained_copies(result: J.Image.FloatRGB & J.Image.FloatRGB) -> IO(Unit):
  (original, copy) = result
  do IO<Unit>:
    float_image(original)
    float_image(J.Image.FloatRGB.flip_horizontal(J.Image.FloatRGB.flip_horizontal(copy)))
def selected(reject: Bool, targets: +List<U32>, result: Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>) -> IO(Unit):
  match reject targets result:
    case True{} _ Fail{image}: retained_copies(J.Image.FloatRGB.copy(image))
    case False{} Nil{} Done{image}: formatted(J.Image.Formatted.export(image))
    case False{} Con{9, Nil{}} Done{image}: float_image(J.Image.Formatted.to_float_rgb(image))
    case _ _ _: IO.die(Unit, 1, "FloatRGB/R32 conversion or ownership differs")
def converted(reject: Bool, targets: +List<U32>, result: Maybe<J.Image.FloatRGB>) -> IO(Unit):
  match targets result:
    case Con{target, rest} Some{image}: selected(reject, rest, J.Image.FloatRGB.to_formatted(image, target))
    case _ _: IO.die(Unit, 1, "FloatRGB/R32 source rejected")
def from_r32(result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case Some{image}: selected(False{}, Nil{}, J.Image.FloatRGB.to_formatted(J.Image.Formatted.to_float_rgb(image), 8))
    case _: IO.die(Unit, 1, "R32 round-trip source rejected")
def invalid_pixel(component: U32, value: F32) -> M.Vector3:
  match component:
    case 0: M.Vector3{value, 0.5, 0.75}
    case 1: M.Vector3{0.25, value, 0.75}
    case _: M.Vector3{0.25, 0.5, value}
def vector_bits(left: M.Vector3, right: M.Vector3) -> Bool:
  M.Vector3{a, b, c} = left
  M.Vector3{x, y, z} = right
  U32.is_eq(F32.bits(a), F32.bits(x)) && U32.is_eq(F32.bits(b), F32.bits(y)) && U32.is_eq(F32.bits(c), F32.bits(z))
def expected_nan_pixel(selected: Bool, wanted: M.Vector3) -> M.Vector3:
  match selected:
    case True{}: wanted
    case False{}: M.Vector3{0.25, 0.5, 0.75}
def nan_entries(n: Nat, +index: U32, +position: U32, +wanted: M.Vector3, entries: List<M.Vector3>) -> Bool:
  match n entries:
    case 0n Nil{}: True{}
    case 1n+rest Con{pixel, tail}:
      expected = expected_nan_pixel(U32.is_eq(index, position), wanted)
      vector_bits(pixel, expected) && nan_entries(rest, (index + 1 : U32), position, wanted, tail)
    case _ _: False{}
def nan_owner_entries(position: U32, wanted: M.Vector3, result: U32 & U32 & List<M.Vector3>) -> Bool:
  (width, height, entries) = result
  U32.is_eq(width, 3) && U32.is_eq(height, 1) && nan_entries(3n, 0, position, wanted, entries)
def nan_owner(position: U32, wanted: M.Vector3, result: Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>) -> Bool:
  match result:
    case Done{_}: False{}
    case Fail{image}: nan_owner_entries(position, wanted, J.Image.FloatRGB.entries(image))
def nan_control(word: U32, component: U32, +position: U32) -> IO(Unit):
  +wanted = invalid_pixel(component, H.float_bits(word))
  pixels = Array.set(M.Vector3, Array.new(M.Vector3, 2n, M.Vector3{0.25, 0.5, 0.75}), position, wanted)
  emit_bytes(~&1, [Bool.to_u32(nan_owner(position, wanted, J.Image.FloatRGB.to_formatted(J.FloatRGB{3, 1, pixels}, 8)))])
'''


def candidate_program(ops):
    body = BEND_PREAMBLE+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    for op in ops:
        if 'nan' in op:
            expression = f'nan_control({op["nan"]}, {op["component"]}, {op["position"]})'
        else:
            data = (f'repeat_bytes({op["repeat_count"]}n, {bend_bytes(word_bytes(op["repeat_words"]))}, Nil{{}})'
                    if 'repeat_words' in op else bend_bytes(op['bytes']))
            if op['source']==8:
                expression = f'from_r32(J.Image.Formatted.from_bytes({op["width"]}, {op["height"]}, 8, {data}))'
            else:
                expression = f'converted({"True" if op.get("reject") else "False"}{{}}, [{", ".join(map(str,op["targets"]))}], J.Image.FloatRGB.from_bytes({op["width"]}, {op["height"]}, {data}))'
        body += '    '+expression+'\n'
    return body


def qualify(observed, cases):
    """The archive must match left-associated uncontracted F32 and differ from fused luminance."""
    if (type(observed) is not dict or set(observed)!={'pixels','uncontracted_mismatches','fused_differences'} or
        any(type(v) is not int for v in observed.values()) or
        observed['pixels']!=sum(c['width']*c['height'] for c in cases if c['source']==9 and c['targets']==[8]) or
        observed['uncontracted_mismatches']!=0 or observed['fused_differences']<=0):
        raise ProbeFailure('Native R32 archive does not qualify for the uncontracted profile')
    return observed


def main():
    args = probekit.arguments(__doc__)
    if args.gpu:raise SystemExit('float_rgb_r32_probe has no forced-GPU variant (no GPU evidence claimed)')
    probe = probekit.Probe('float-rgb-r32',args)
    if sys.byteorder!='little':raise ProbeFailure('FloatRGB/R32 profile requires little-endian storage')
    cases,invalid = fixtures(),controls();ops = cases+invalid
    qualification = qualify(json.loads(probe.native(qualification_program(cases),'qualification',extra_flags=('-ffp-contract=off',))),cases)
    text = probe.native(reference_program(ops));rows = iter(parse_rows(text,shapes(ops)))
    expected = [[next(rows) for _ in shapes([op])] for op in ops]

    def parse(text,selected):
        rows = iter(parse_rows(text,shapes(selected)))
        return [[next(rows) for _ in shapes([op])] for op in selected]

    lanes = probe.candidates(lambda selected,gpu:candidate_program(selected),ops,batch=BATCH_OPERATIONS,parse=parse)
    probe.compare(expected,lanes,lambda i:ops[i].get('name',''))
    probe.finish(native_cases=len(cases),native_pixels=sum(c['width']*c['height'] for c in cases),
                 retained_owner_controls=sum(bool(c.get('reject')) for c in invalid),direct_nan_controls=sum('nan' in c for c in invalid),
                 expected_results=len(shapes(ops)),compared_bytes=sum(len(r) for op in expected for r in op),qualification=qualification,
                 inputs_sha256=hashlib.sha256((json.dumps(ops,sort_keys=True)+'\n').encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
