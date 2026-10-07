#!/usr/bin/env python3
"""Compare float rectangles with native extraction/crop and retained owners."""
import hashlib
import json
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
           'static void emit(Image image){word(image.width);word(image.height);for(int i=0;i<image.width*image.height*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
'''+BEND_EMITTER+'''
def emitted.sized(+width: U32, +height: U32, bytes: List<U32>) -> IO(Unit):
  header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : List<U32>}
  emit_bytes(~&1, List.append(&1, U32, header, bytes))
def emitted(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{width, height}, Tuple{9, bytes}}: emitted.sized(width, height, bytes)
    case _: IO.die(Unit, 1, "rectangle pixel format changed")
def observed(result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "rectangle result/owner differs")
    case Some{image}: emitted(J.Surface.export(image))
def extracted(reject: Bool, result: J.Surface & Maybe<J.Surface>) -> Maybe<J.Surface>:
  match reject result:
    case True{} Tuple{source, None{}}: Some{source}
    case False{} Tuple{_, Some{region}}: Some{region}
    case _ _: None{}
def cropped(reject: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match reject result:
    case True{} Fail{Tuple{source, J.InvalidRectangle{}}}: Some{source}
    case False{} Done{image}: Some{image}
    case _ _: None{}
def apply(crop: Bool, reject: Bool, rect: J.Rectangle, result: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match crop result:
    case _ None{}: None{}
    case True{} Some{image}: cropped(reject, J.Surface.crop(image, rect))
    case False{} Some{image}: extracted(reject, J.Surface.extract(image, rect))
def source_read(result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{x, y, z}}: F32.is_eq(x, 7.25) && F32.is_eq(y, 7.5) && F32.is_eq(z, 7.75)
def region_read(source: Array<M.Vector3>, result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{x, y, z}}:
      F32.is_eq(x, 0.0) && F32.is_eq(y, 0.0) && F32.is_eq(z, 0.0) && source_read(Array.get(M.Vector3, source, 7))
def independent(result: J.Surface & Maybe<J.Surface>) -> Bool:
  match result:
    case Tuple{J.Surface{6, 4, 9, J.Vectors{source}}, Some{J.Surface{3, 2, 9, J.Vectors{region}}}}:
      region_read(source, Array.get(M.Vector3, Array.set(M.Vector3, region, 0, M.Vector3{0.0, 0.0, 0.0}), 0))
    case _: False{}
def ownership(result: Maybe<J.Surface>) -> Bool:
  match result:
    case None{}: False{}
    case Some{image}: independent(J.Surface.extract(image, J.Rectangle{1.0, 1.0, 3.0, 2.0}))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    data=list(struct.pack('<'+'f'*72,*[i+c for i in range(24) for c in (0.25,0.5,0.75)]))
    cases=[dict(kind=kind,rect=rect) for kind in ('extract','crop') for rect in ((0,0,6,4),(1,1,3,2),(5,3,1,1),(0,0,1,4),(0,3,6,1))]
    cases += [dict(kind='crop',rect=rect) for rect in ((-2,-1,5,4),(-1,-1,8,6),(4,2,9,9),(7,0,1,1),(0,5,1,1))]
    controls=[dict(kind='extract',rect=rect) for rect in ((-1,0,2,1),(5,0,2,1),(0.5,0,2,1),(0,0,0,1))]
    controls += [dict(kind='crop',rect=rect) for rect in ((6,0,1,1),(-10,0,2,1),(0,0,0,1),(0.5,0,2,1))]
    return data,cases,controls


def reference_program(path,cases):
    lines=list(PRELUDE);load=f'LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},6,4,PIXELFORMAT_UNCOMPRESSED_R32G32B32,0)'
    for case in cases:
        rectangle='(Rectangle){'+','.join(str(v) for v in case['rect'])+'}'
        lines.append('{Image image='+load+';if(!image.data)return 2;')
        lines.append('Image region=ImageFromImage(image,'+rectangle+');UnloadImage(image);emit(region);}' if case['kind']=='extract' else 'ImageCrop(&image,'+rectangle+');emit(image);}')
    lines.append('emit('+load+');}')
    return '\n'.join(lines)+'\n'


def main():
    probe=probekit.Probe('float-rgb-crop',probekit.arguments(__doc__))
    data,cases,controls=fixtures();path=probe.work/'input.raw';path.write_bytes(bytes(data))
    text=probe.native(reference_program(path,cases));reference=parse_results(text)
    if len(reference)!=len(cases)+1 or reference[-1]!=list(struct.pack('<II',6,4))+data:raise ProbeFailure('Incomplete native rectangle output')
    pixels=0
    for row in reference[:-1]:
        count=int.from_bytes(bytes(row[:4]),'little')*int.from_bytes(bytes(row[4:8]),'little')
        if len(row)!=8+12*count:raise ProbeFailure('Native rectangle metadata/length differs')
        pixels+=count
    wanted=reference[:-1]+[reference[-1] for _ in controls]+[[1]];probe.report['sources']=source_gate()
    image=f'J.Surface.from_bytes(6, 4, 9, {bend_bytes(data)})';actions=[]
    for reject,group in ((False,cases),(True,controls)):
        for case in group:
            rectangle='J.Rectangle{'+', '.join(f'F32.neg({abs(v):.1f})' if v<0 else f'{v:.1f}' for v in case['rect'])+'}'
            actions.append(f'observed(applyBANG({"True" if case["kind"]=="crop" else "False"}{{}}, {"True" if reject else "False"}{{}}, {rectangle}, {image}))')
    actions.append(f'emit_bytes(~&1, [Bool.to_u32(ownershipBANG({image}))])')
    render=lambda selected,gpu:PROGRAM+''.join('    '+line.replace('BANG','!' if gpu else '')+'\n' for line in selected)
    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:parse_results(text)))
    probe.finish(native_cases=len(cases),pixels=pixels,retained_owner_controls=len(controls),independent_extraction_controls=1,
                 inputs_sha256=hashlib.sha256(json.dumps([data,cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
