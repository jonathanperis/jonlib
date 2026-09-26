#!/usr/bin/env python3
"""Compare bounded BMP pixels and complete RGBA8 export bytes with pinned raylib."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from conformance import BUILD, ROOT, checkout, run, source_gate


def bitmap(width, height, pixels, *, bpp=24, dib=40, compression=0, top=False, gap=0):
    stride = (width*(bpp//8)+3)&~3
    payload = bytearray()
    for y in (range(height) if top else reversed(range(height))):
        for pixel in pixels[y*width:(y+1)*width]:
            r,g,b,a = pixel.to_bytes(4,'big')
            payload.extend((b,g,r) if bpp==24 else (b,g,r,a))
        payload.extend(bytes(stride-width*(bpp//8)))
    header = struct.pack('<2sIHHI',b'BM',14+dib+2*gap+len(payload),0,0,14+dib+gap)
    header += struct.pack('<IiiHHIIIIII',dib,width,-height if top else height,1,bpp,compression,len(payload),0,0,0,0)
    if dib==108:
        header += struct.pack('<IIII',0xff0000,0xff00,0xff,0xff000000)+bytes(52)
    # The pinned stb reader skips these extra bytes twice for true-color files.
    return list(header+bytes([0xa5])*2*gap+payload)


def fixtures():
    inputs = []
    for width in range(1,5):
        pixels = [((i*53+17)&255)<<24 | ((i*73+31)&255)<<16 | ((i*97+43)&255)<<8 | (i*101&255) for i in range(width*2)]
        for top in (False,True):
            inputs.append(dict(id=f'rgb24-{width}-{top}',bytes=bitmap(width,2,pixels,top=top)))
    rgba = [0x01020300,0x11223300,0xabcdef00,0xfedcba00,0xff001100,0x07ff8000]
    for dib,compression in ((40,0),(108,0),(108,3)):
        for top in (False,True):
            for mixed in (False,True):
                pixels = [value | ((i*51)&255 if mixed else 0) for i,value in enumerate(rgba)]
                inputs.append(dict(id=f'rgba32-{dib}-{compression}-{top}-{mixed}',bytes=bitmap(3,2,pixels,bpp=32,dib=dib,compression=compression,top=top)))
    inputs += [dict(id='v4-rgb24',bytes=bitmap(3,2,rgba,dib=108,top=True)),
               dict(id='double-gap',bytes=bitmap(3,2,rgba,gap=4)),
               dict(id='maximum-gap',bytes=bitmap(1,1,[0x12345678],gap=1024))]
    v4 = bitmap(3,2,rgba,bpp=32,dib=108)
    v4[54:70] = [0]*16
    inputs.append(dict(id='rgb-masks-ignored',bytes=v4))
    base = bitmap(1,1,[0x12345678])
    malformed = [dict(id='empty',bytes=[],error=0),dict(id='bad-byte',bytes=[256],error=1),
                 dict(id='short-header',bytes=base[:53],error=0),dict(id='short-padding',bytes=base[:-1],error=3)]
    for name,offset,fmt,value,error in [('signature',0,'H',0,0),('dib',14,'I',12,0),('planes',26,'H',2,0),
                                      ('bpp',28,'H',16,0),('compression',30,'I',1,0),('offset-before-header',10,'I',53,0),
                                      ('offset-too-far',10,'I',1079,0),('width-zero',18,'I',0,2),
                                      ('width-large',18,'I',4097,2),('height-min',22,'I',0x80000000,2)]:
        changed=bytearray(base);struct.pack_into('<'+fmt,changed,offset,value)
        malformed.append(dict(id=name,bytes=list(changed),error=error))
    masked = bitmap(1,1,[0x12345678],bpp=32,dib=108,compression=3)
    masked[54] = 1
    malformed += [dict(id='unsupported-mask',bytes=masked,error=0),
                  dict(id='truncated-v4',bytes=masked[:121],error=0),
                  dict(id='gap-truncated',bytes=bitmap(1,1,[0x12345678],gap=4)[:-4],error=3)]
    outputs = [dict(id='rgba-mixed',width=3,height=2,pixels=[v | (i*51) for i,v in enumerate(rgba)]),
               dict(id='rgba-zero-alpha',width=2,height=2,pixels=rgba[:4]),
               dict(id='rgba-single',width=1,height=1,pixels=[0xffffffff])]
    return inputs,malformed,outputs


def bend_bytes(values):
    if len(values)<=256:
        return '['+','.join(map(str,values))+']'
    chunks=','.join('['+','.join(map(str,values[start:start+64]))+']' for start in range(0,len(values),64))
    return f'input_bytes([{chunks}], Nil{{}})'


def main(codec='bmp', fixture_factory=fixtures):
    parser=argparse.ArgumentParser(description=f'Compare {codec.upper()} decoding and RGBA8 export with raylib.')
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/f'{codec}-probe';work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    inputs,malformed,outputs=fixture_factory()
    lines=['#include "raylib.h"','#include <stdio.h>',
           'static void emit(Image image){if(!image.data){fputs("valid BMP rejected\\n",stderr);exit(2);} ImageFormat(&image,7);',
           'printf("{\\"width\\":%d,\\"height\\":%d,\\"pixels\\":[",image.width,image.height);',
           'Color *pixels=LoadImageColors(image);for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(pixels[i]));',
           'puts("]}");UnloadImageColors(pixels);UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    lines.insert(2,'#include <stdlib.h>')
    for case in inputs:
        lines += ['{unsigned char bytes[]={'+','.join(map(str,case['bytes']))+'};emit(LoadImageFromMemory(".'+codec+'",bytes,sizeof(bytes)));}']
    for case in outputs:
        path=work/f'reference-{case["id"]}.{codec}'
        lines += ['{',f'Image image=GenImageColor({case["width"]},{case["height"]},BLANK);',
                  'unsigned pixels[]={'+','.join(str(v)+'u' for v in case['pixels'])+'};',
                  f'for(int i=0;i<{len(case["pixels"])};i++)((Color*)image.data)[i]=GetColor(pixels[i]);',
                  f'if(!ExportImage(image,{json.dumps(str(path))}))return 3;UnloadImage(image);',
                  f'int size=0;unsigned char *bytes=LoadFileData({json.dumps(str(path))},&size);',
                  'if(!bytes)return 4;putchar(\'[\');for(int i=0;i<size;i++)printf("%s%u",i?",":"",bytes[i]);puts("]");UnloadFileData(bytes);','}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n')
    binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    reference=run([binary]);expected=[json.loads(line) for line in reference.splitlines()]
    if len(expected)!=len(inputs)+len(outputs):raise ValueError(f'Incomplete native {codec.upper()} results')
    expected = expected[:len(inputs)]+[c['error'] for c in malformed]+expected[len(inputs):]
    report=dict(passed=False,decode_cases=len(inputs),error_cases=len(malformed),export_cases=len(outputs),
                decoded_pixels=sum(len(row['pixels']) for row in expected[:len(inputs)]),export_bytes=sum(len(row) for row in expected[-len(outputs):]),
                inputs_sha256=hashlib.sha256(json.dumps([inputs,malformed,outputs]).encode()).hexdigest(),
                reference_sha256=hashlib.sha256(reference.encode()).hexdigest(),sources=source_gate(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program='''import Base
import ../../jonlib.bend as J
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def decoded(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid BMP rejected")
    case Done{J.Surface{+w, +h, pixels}}:
      IO.print("{\\"width\\":" ++ U32.show(w) ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"pixels\\":" ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{w, h, pixels})) ++ "}")
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
def fill(values: +List<U32>, +index: U32, +width: U32, surface: J.Surface) -> J.Surface:
  match values:
    case Nil{}: surface
    case Con{color, rest}: fill(rest, (index + 1 : U32), width, J.Surface.draw_pixel(surface, U32.to_f32((index % width : U32)), U32.to_f32((index / width : U32)), color))
def encoded(width: U32, values: +List<U32>, result: Maybe<J.Surface>) -> +List<U32>:
  match result:
    case None{}: Nil{}
    case Some{surface}: J.Surface.to_bmp(fill(values, 0, width, surface))
def saved(result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "BMP export input rejected")
    case Some{surface}: IO.try(Unit, J.Surface.write_bmp(surface, OUTPUT))
def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('OUTPUT',json.dumps(str(work/f'{lane}-single.{codec}'))).replace('BMP',codec.upper()).replace('Surface.to_bmp',f'Surface.to_{codec}').replace('Surface.write_bmp',f'Surface.write_{codec}')
        bang='!' if lane=='metal' else ''
        for case in inputs:program+=f'    decoded(J.Surface.decode_{codec}{bang}({bend_bytes(case["bytes"])}))\n'
        for case in malformed:program+=f'    IO.print(U32.show(error_code(J.Surface.decode_{codec}{bang}({bend_bytes(case["bytes"])}))))\n'
        for case in outputs:program+=f'    IO.print(List.show(~&2, ~U32, ~U32.show, encoded{bang}({case["width"]}, {bend_bytes(case["pixels"])}, J.Surface.create({case["width"]}, {case["height"]}, 0))))\n'
        if lane!='metal':program+='    saved(J.Surface.create(1, 1, 4294967295))\n'
        source=work/f'{lane}.bend';source.write_text(program)
        binary=work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=[json.loads(line) for line in run(command).splitlines()]
        differences=[dict(index=i,reference=a,candidate=b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        file_match=lane=='metal' or (work/f'{lane}-single.{codec}').read_bytes()==(work/f'reference-rgba-single.{codec}').read_bytes()
        report['lanes'][lane]=dict(passed=actual==expected and file_match,differences=differences[:2])
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected or not file_match:raise ValueError(f'{lane}: {codec.upper()} results differ: {differences[:1]}')
        print(f'{lane}: {len(inputs)} {codec.upper()} images, {len(malformed)} typed errors and {len(outputs)} exact exports passed',flush=True)
    report['passed']=True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
