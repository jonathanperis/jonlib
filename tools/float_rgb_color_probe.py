#!/usr/bin/env python3
"""Compare native format-9 color transforms and owner-preserving rejection."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import ROOT, f32, source_gate
from float_rgb_probe import boundaries
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(Image image){if(!image.data||image.format!=PIXELFORMAT_UNCOMPRESSED_R32G32B32)exit(2);word(image.width);word(image.height);',
           'for(int i=0;i<image.width*image.height*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/hdr.bend as H
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
'''+BEND_EMITTER+'''
type Op is Data:
  Tint{color: U32}
  Invert{}
  Contrast{amount: F32}
  Brightness{amount: F32}
  Replace{original: U32, replacement: U32}
def operation(op: Op, image: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match op:
    case Tint{color}: J.Surface.color_tint(image, color)
    case Invert{}: J.Surface.color_invert(image)
    case Contrast{amount}: J.Surface.color_contrast(image, amount)
    case Brightness{amount}: J.Surface.color_brightness(image, amount)
    case Replace{original, replacement}: J.Surface.color_replace(image, original, replacement)
def operations(ops: +List<Op>, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match ops result:
    case _ Fail{failure}: Fail{failure}
    case Nil{} _: result
    case Con{op, rest} Done{image}: operations(rest, operation(op, image))
def apply(ops: +List<Op>, result: Maybe<J.Surface>) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{operations(ops, Done{image})}
def emitted.sized(+width: U32, +height: U32, bytes: List<U32>) -> IO(Unit):
  header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : List<U32>}
  emit_bytes(~&1, List.append(&1, U32, header, bytes))
def emitted(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: emitted.sized(width, height, bytes)
    case _: IO.die(Unit, 1, "color transform changed the pixel format")
def image(image: J.Surface) -> IO(Unit):
  emitted(J.Surface.export(image))
# expected: 99 accepted, 1 InvalidRequest, 2 OutOfDomain (owner returned unchanged).
def observed(expected: U32, result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>>) -> IO(Unit):
  match expected result:
    case 99 Some{Done{value}}: image(value)
    case 1 Some{Fail{Tuple{value, J.InvalidRequest{}}}}: image(value)
    case 2 Some{Fail{Tuple{value, J.OutOfDomain{}}}}: image(value)
    case _ _: IO.die(Unit, 1, "color transform acceptance/error/owner differs")
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    values=[0.5,0.25,0.75,0,0,0,1,1,1,0.49999997,0.249999985,0.74999994,0,-0.0,1,17/255,34/255,51/255]
    small=dict(width=3,height=2,bytes=list(struct.pack('<18f',*values)))
    words=boundaries();wide=dict(width=len(words)//3,height=1,bytes=list(struct.pack('<'+'I'*len(words),*words)))
    operations=[[dict(op='tint',color=color)] for color in (0x7fabcc00,0xffffffff)]
    operations += [[dict(op='invert')]]
    operations += [[dict(op='contrast',amount=amount)] for amount in (-300,-100,-50,0,12.5,50,100,300)]
    operations += [[dict(op='brightness',amount=amount)] for amount in (-300,-255,-1,0,1,64,255,300)]
    operations += [[dict(op='replace',original=original,replacement=0x11223300)] for original in (0x7f3fbfff,0x7f3fbf00)]
    operations.append([dict(op='contrast',amount=23.5),dict(op='brightness',amount=-20),dict(op='invert'),dict(op='tint',color=0xabcdef80)])
    cases=[dict(source,operations=ops) for source in (small,wide) for ops in operations]
    # ImageColorBrightness takes int: finite amounts below 2^31 in magnitude truncate.
    cases += [dict(small,operations=[op]) for op in (dict(op='brightness',amount=0.5),dict(op='brightness',bits=0x80000001))]
    controls=[dict(small,operations=[op],error=1) for op in (dict(op='contrast',bits=0x7f800000),dict(op='contrast',bits=0x7fc00000),
                dict(op='brightness',bits=0x7f800000))]
    controls.append(dict(width=1,height=1,bytes=list(struct.pack('<fff',2,0.5,0.75)),operations=[dict(op='invert')],error=2))
    return cases,controls


def reference_program(cases,controls,work):
    lines=list(PRELUDE)
    for i,case in enumerate([*cases,*controls]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},PIXELFORMAT_UNCOMPRESSED_R32G32B32,0);')
        if i<len(cases):
            for op in case['operations']:
                if op['op']=='tint':lines.append(f'ImageColorTint(&image,GetColor({op["color"]}u));')
                elif op['op']=='invert':lines.append('ImageColorInvert(&image);')
                elif op['op']=='contrast':lines.append(f'ImageColorContrast(&image,{float(op["amount"])}f);')
                elif op['op']=='brightness' and 'bits' in op:lines.append(f'{{unsigned b={op["bits"]}u;float f;memcpy(&f,&b,4);ImageColorBrightness(&image,(int)f);}}')
                elif op['op']=='brightness' and op['amount']!=int(op['amount']):lines.append(f'ImageColorBrightness(&image,(int){float(op["amount"])}f);')
                elif op['op']=='brightness':lines.append(f'ImageColorBrightness(&image,{op["amount"]});')
                else:lines.append(f'ImageColorReplace(&image,GetColor({op["original"]}u),GetColor({op["replacement"]}u));')
        lines.append('emit(image);}')
    return '\n'.join(lines+['}'])+'\n'


def bend_op(op):
    if op['op']=='tint':return f'Tint{{{op["color"]}}}'
    if op['op']=='invert':return 'Invert{}'
    if op['op']=='replace':return f'Replace{{{op["original"]}, {op["replacement"]}}}'
    value=f'H.float_bits({op["bits"]})' if 'bits' in op else f32(op['amount'])
    return ('Contrast' if op['op']=='contrast' else 'Brightness')+'{'+value+'}'


def main():
    probe=probekit.Probe('float-rgb-color',probekit.arguments(__doc__))
    cases,controls=fixtures();text=probe.native(reference_program(cases,controls,probe.work));expected=parse_results(text)
    if len(expected)!=len(cases)+len(controls):raise ProbeFailure('Incomplete native float color output')
    for case,row in zip([*cases,*controls],expected):
        if row[:8]!=list(struct.pack('<II',case['width'],case['height'])) or len(row)!=8+case['width']*case['height']*12:raise ProbeFailure('Native float color shape differs')
    probe.report['sources']=source_gate()
    actions=[f'observed({case.get("error",99)}, applyBANG([{",".join(bend_op(op) for op in case["operations"])}], '
             f'J.Surface.from_bytes({case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])})))' for case in [*cases,*controls]]
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(native_cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),retained_owner_controls=len(controls),
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
