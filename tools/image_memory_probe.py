#!/usr/bin/env python3
"""Compare native extension-token/content dispatch for implemented memory codecs."""
import argparse
import hashlib
import json
from pathlib import Path

from conformance import BUILD, ROOT, checkout, run, source_gate
from image_file_probe import image_streams
from bmp_probe import bend_bytes


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'image-memory-probe';work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    streams=image_streams();cases=[]
    for extension in ('png','bmp','tga','pgm','ppm','jpg','jpeg','gif','pic','psd','qoi'):
        for token in ('.'+extension,'.'+extension.upper()):
            for kind,data in streams.items():cases.append(dict(token=token,kind=kind,data=list(data)))
    for token in ('.PnG','.pnm','','PNG','.png-tail','image.png'):
        cases.append(dict(token=token,kind='unsupported',data=list(streams['png'])))
    lines=['#include "raylib.h"','#include <stdio.h>',
           'static void emit(Image image){if(!image.data){puts("{\\"loaded\\":false}");return;}ImageFormat(&image,7);',
           'printf("{\\"loaded\\":true,\\"width\\":%d,\\"height\\":%d,\\"pixels\\":[",image.width,image.height);',
           'Color *pixels=LoadImageColors(image);for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(pixels[i]));',
           'puts("]}");UnloadImageColors(pixels);UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        lines+=['{unsigned char data[]={'+','.join(map(str,case['data']))+'};',f'emit(LoadImageFromMemory({json.dumps(case["token"])},data,sizeof(data)));','}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n')
    binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases):raise ValueError('Incomplete native memory dispatch results')
    controls=[('.png',[256],1),('.qoi',[256],1),('.unknown',[256],0),('.png',[],0),('.png',[137,80],0)]
    report=dict(passed=False,native_cases=len(cases),loaded_cases=sum(row['loaded'] for row in expected),invalid_controls=len(controls),
                sources=source_gate(),inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),
                reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program='''import Base
import ../../jonlib.bend as J
def observed(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("{\\"loaded\\":false}")
    case Done{J.Surface{+w, +h, pixels}}:
      IO.print("{\\"loaded\\":true,\\"width\\":" ++ U32.show(w) ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"pixels\\":" ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{w, h, pixels})) ++ "}")
def error_code(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> U32:
  match result:
    case Done{_}: 99
    case Fail{error}:
      match error:
        case J.InvalidImageHeader{}: 0
        case J.InvalidImageByte{}: 1
        case J.UnsupportedImageSize{}: 2
        case J.TruncatedImageData{}: 3
        case J.InvalidImageStream{}: 4
def main() -> IO(Unit):
  do IO<Unit>:
'''
        bang='!' if lane=='metal' else ''
        for case in cases:program+=f'    observed(J.Surface.decode_image{bang}({json.dumps(case["token"])}, {bend_bytes(case["data"])}))\n'
        for token,data,_ in controls:program+=f'    IO.print(U32.show(error_code(J.Surface.decode_image{bang}({json.dumps(token)}, {bend_bytes(data)}))))\n'
        source=work/f'{lane}.bend';source.write_text(program)
        binary=work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=[json.loads(line) for line in run(command).splitlines()]
        wanted=expected+[code for _,_,code in controls]
        differences=[i for i,(a,b) in enumerate(zip(wanted,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==wanted,different_cases=differences)
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=wanted:raise ValueError(f'{lane}: memory dispatch differs: {differences[:8]}')
        print(f'{lane}: {len(cases)} native token/content pairs and {len(controls)} typed controls passed',flush=True)
    report['passed']=True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
