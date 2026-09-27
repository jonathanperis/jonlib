#!/usr/bin/env python3
"""Compare float rectangles with native extraction/crop and retained owners."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'float-rgb-crop-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    data=list(struct.pack('<'+'f'*72,*[i+c for i in range(24) for c in (0.25,0.5,0.75)]));path=work/'input.raw';path.write_bytes(bytes(data))
    cases=[dict(kind=kind,rect=rect) for kind in ('extract','crop') for rect in ((0,0,6,4),(1,1,3,2),(5,3,1,1),(0,0,1,4),(0,3,6,1))]
    cases += [dict(kind='crop',rect=rect) for rect in ((-2,-1,5,4),(-1,-1,8,6),(4,2,9,9),(7,0,1,1),(0,5,1,1))]
    controls=[dict(kind='extract',rect=rect) for rect in ((-1,0,2,1),(5,0,2,1),(0.5,0,2,1),(0,0,0,1))]
    controls += [dict(kind='crop',rect=rect) for rect in ((6,0,1,1),(-10,0,2,1),(0,0,0,1),(0.5,0,2,1))]
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
           'static void emit(Image image){word(image.width);word(image.height);for(int i=0;i<image.width*image.height*12;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    load=f'LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},6,4,PIXELFORMAT_UNCOMPRESSED_R32G32B32,0)'
    for case in cases:
        rectangle='(Rectangle){'+','.join(str(v) for v in case['rect'])+'}'
        lines.append('{Image image='+load+';if(!image.data)return 2;')
        lines.append('Image region=ImageFromImage(image,'+rectangle+');UnloadImage(image);emit(region);}' if case['kind']=='extract' else 'ImageCrop(&image,'+rectangle+');emit(image);}')
    lines.append('emit('+load+');}')
    source=work/'reference.c';source.write_text('\n'.join(lines)+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);reference=parse_results(text)
    if len(reference)!=len(cases)+1 or reference[-1]!=list(struct.pack('<II',6,4))+data:raise ValueError('Incomplete native rectangle output')
    pixels=0
    for row in reference[:-1]:
        count=int.from_bytes(bytes(row[:4]),'little')*int.from_bytes(bytes(row[4:8]),'little')
        if len(row)!=8+12*count:raise ValueError('Native rectangle metadata/length differs')
        pixels+=count
    wanted=reference[:-1]+[reference[-1] for _ in controls]+[[1]]
    report=dict(passed=False,native_cases=len(cases),pixels=pixels,retained_owner_controls=len(controls),independent_extraction_controls=1,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([data,cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    program='''import Base
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
def emitted(+width: U32, +height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "rectangle sample domain changed")
    case Done{bytes}:
      header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0] : +List<U32>}
      emit_bytes(~&2, List.append(&2, U32, header, bytes))
def observed(result: Maybe<J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "rectangle result/owner differs")
    case Some{J.FloatRGB{+width, +height, pixels}}: emitted(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def extracted(reject: Bool, result: J.Image.FloatRGB & Maybe<J.Image.FloatRGB>) -> Maybe<J.Image.FloatRGB>:
  match reject result:
    case True{} Tuple{source, None{}}: Some{source}
    case False{} Tuple{_, Some{region}}: Some{region}
    case _ _: None{}
def cropped(reject: Bool, result: Result<&1, &1, J.Image.FloatRGB & J.Surface.Error, J.Image.FloatRGB>) -> Maybe<J.Image.FloatRGB>:
  match reject result:
    case True{} Fail{Tuple{source, J.InvalidRectangle{}}}: Some{source}
    case False{} Done{image}: Some{image}
    case _ _: None{}
def apply(crop: Bool, reject: Bool, rect: J.Rectangle, result: Maybe<J.Image.FloatRGB>) -> Maybe<J.Image.FloatRGB>:
  match crop result:
    case _ None{}: None{}
    case True{} Some{image}: cropped(reject, J.Image.FloatRGB.crop(image, rect))
    case False{} Some{image}: extracted(reject, J.Image.FloatRGB.extract(image, rect))
def source_read(result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{x, y, z}}: F32.is_eq(x, 7.25) && F32.is_eq(y, 7.5) && F32.is_eq(z, 7.75)
def region_read(source: Array<M.Vector3>, result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{x, y, z}}:
      F32.is_eq(x, 0.0) && F32.is_eq(y, 0.0) && F32.is_eq(z, 0.0) && source_read(Array.get(M.Vector3, source, 7))
def independent(result: J.Image.FloatRGB & Maybe<J.Image.FloatRGB>) -> Bool:
  match result:
    case Tuple{J.FloatRGB{6, 4, source}, Some{J.FloatRGB{3, 2, region}}}:
      region_read(source, Array.get(M.Vector3, Array.set(M.Vector3, region, 0, M.Vector3{0.0, 0.0, 0.0}), 0))
    case _: False{}
def ownership(result: Maybe<J.Image.FloatRGB>) -> Bool:
  match result:
    case None{}: False{}
    case Some{image}: independent(J.Image.FloatRGB.extract(image, J.Rectangle{1.0, 1.0, 3.0, 2.0}))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    image=f'J.Image.FloatRGB.from_bytes(6, 4, {bend_bytes(data)})'
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for reject,group in ((False,cases),(True,controls)):
            for case in group:
                rectangle='J.Rectangle{'+', '.join(f'F32.neg({abs(v):.1f})' if v<0 else f'{v:.1f}' for v in case['rect'])+'}'
                body+=f'    observed(apply{bang}({"True" if case["kind"]=="crop" else "False"}{{}}, {"True" if reject else "False"}{{}}, {rectangle}, {image}))\n'
        body+=f'    emit_bytes(~&1, [Bool.to_u32(ownership{bang}({image}))])\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: float rectangle differences {different}')
        print(f'{lane}: {len(cases)} native rectangles / {pixels} pixels, {len(controls)} retained owners and independent extraction passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
