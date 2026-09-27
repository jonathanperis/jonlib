#!/usr/bin/env python3
"""Compare exact PNG memory/file exports and complete candidate decode round trips."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct
import zlib

from conformance import BUILD, ROOT, checkout, run, source_gate
from byte_probe import BEND_EMITTER, parse_results


def fixtures():
    rng=random.Random(0x906e)
    cases=[dict(id='zero',width=1,height=1,data=bytes(4)),
           dict(id='white',width=1,height=1,data=b'\xff'*4),
           dict(id='mixed',width=3,height=2,data=bytes([1,2,3,0, 255,127,128,255, 17,63,201,128, 254,253,252,1, 0,255,0,127, 255,0,255,255])),
           dict(id='solid',width=16,height=9,data=bytes([17,34,51,68])*144)]
    for name,width,height in [('thin',1,129),('wide',129,1),('gradient',17,13)]:
        data=bytes(v for y in range(height) for x in range(width) for v in ((x*17)&255,(y*31)&255,(x*73+y*19)&255,255))
        cases.append(dict(id=name,width=width,height=height,data=data))
    for name,width,height in [('noise-filters',8,32),('stored32766',32,254),('stored32767',54,151),('stored-two',128,64),('stored-three',128,128)]:
        cases.append(dict(id=name,width=width,height=height,data=bytes(rng.randrange(256) for _ in range(width*height*4))))
    for format,channels in ((1,1),(2,2),(4,3),(7,4)):
        for width,height in ((1,1),(3,2),(1,33),(8,32)):
            data=bytearray(rng.randrange(256) for _ in range(width*height*channels))
            if channels in (2,4):
                for i,alpha in enumerate((0,1,127,128,254,255)):
                    if i<width*height:data[i*channels+channels-1]=alpha
            cases.append(dict(id=f'format-{format}-{width}-{height}',format=format,width=width,height=height,data=bytes(data)))
    boundaries=[0,1,2,31,32,63,64,255,256,1023,1024,2047,2048,32767,65534,65535]
    for format in (3,5,6):
        for name,width,height,words in [('maximum',1,1,[65535]),('boundaries',4,4,boundaries),('seeded',7,5,[rng.randrange(65536) for _ in range(35)])]:
            cases.append(dict(id=f'packed-{format}-{name}',format=format,file_only=True,width=width,height=height,data=struct.pack('<'+'H'*len(words),*words)))
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'png-export-probe';work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures()
    lines=['#include "raylib.h"','#include <stdio.h>','#include <string.h>',
           'static void emit(unsigned char *bytes,int size){putchar(\'[\');for(int i=0;i<size;i++)printf("%s%u",i?",":"",bytes[i]);puts("]");}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path=work/f'{case["id"]}.rgba';path.write_bytes(case['data'])
        output=work/f'reference-{case["id"]}.png'
        file_only=case.get('file_only',False)
        lines += ['{int size=0,n=0,file_size=0;',f'unsigned char *data=LoadFileData({json.dumps(str(path))},&size);if(!data||size!={len(case["data"])})return 1;',
                  f'Image image={{data,{case["width"]},{case["height"]},1,{case.get("format",7)}}};',
                  'unsigned char *encoded=NULL;' if file_only else 'unsigned char *encoded=ExportImageToMemory(image,".png",&n);if(!encoded)return 2;',
                  f'if(!ExportImage(image,{json.dumps(str(output))}))return 3;',
                  f'unsigned char *file=LoadFileData({json.dumps(str(output))},&file_size);if(!file)return 4;',
                  'encoded=file;n=file_size;' if file_only else 'if(file_size!=n||memcmp(file,encoded,n))return 4;',
                  'Image decoded=LoadImageFromMemory(".png",encoded,n);if(!decoded.data||decoded.width!=image.width||decoded.height!=image.height)return 5;',
                  'ImageFormat(&decoded,7);Color *colors=LoadImageColors(image);int rgba_size=image.width*image.height*4;if(!colors||memcmp(decoded.data,colors,rgba_size))return 6;emit(encoded,n);emit(decoded.data,rgba_size);',
                  'UnloadImageColors(colors);UnloadImage(decoded);'+('' if file_only else 'MemFree(encoded);')+'UnloadFileData(file);UnloadFileData(data);','}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n')
    binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text=run([binary]);expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=2*len(cases):raise ValueError('Incomplete native PNG exports')
    filters=set();blocks=set()
    for case,encoded in zip(cases,expected[::2]):
        data=bytes(encoded);offset=8;idat=bytearray()
        while offset<len(data):
            size=struct.unpack('>I',data[offset:offset+4])[0];kind=data[offset+4:offset+8]
            if kind==b'IDAT':idat.extend(data[offset+8:offset+8+size])
            offset+=12+size
        format=case.get('format',7);channels=4 if case.get('file_only') else {1:1,2:2,4:3,7:4}[format]
        color_type=6 if case.get('file_only') else {1:0,2:4,4:2,7:6}[format]
        if data[25]!=color_type:raise ValueError('Native PNG color type differs')
        raster=zlib.decompress(idat);stride=case['width']*channels+1
        if len(raster)!=stride*case['height']:raise ValueError('Native filtered raster size differs')
        filters.update(raster[::stride]);blocks.add((idat[2]>>1)&3)
    if filters!=set(range(5)) or blocks!={0,1}:raise ValueError(f'Incomplete filter/block coverage: {filters}, {blocks}')
    report=dict(passed=False,images=len(cases),encoded_bytes=sum(map(len,expected[::2])),roundtrip_bytes=sum(map(len,expected[1::2])),
                filters=sorted(filters),block_types=sorted(blocks),sources=source_gate(),
                inputs_sha256=hashlib.sha256(b''.join(struct.pack('>IIII',c['width'],c['height'],c.get('format',7),int(c.get('file_only',False)))+c['data'] for c in cases)).hexdigest(),
                reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program='''import Base
import ../../jonlib.bend as J
'''+BEND_EMITTER+'''def encoded.formatted(result: Result<&1, &1, J.Image.Formatted & J.Pixel.Error, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match result:
    case Fail{_}: None{}
    case Done{bytes}: Some{bytes}
def encoded(formatted: Bool, file_only: Bool, result: Maybe<J.Image.Formatted>) -> Maybe<&2, +List<U32>>:
  match formatted file_only result:
    case _ _ None{}: None{}
    case False{} _ Some{image}: Some{J.Surface.to_png(J.Image.Formatted.to_surface(image))}
    case True{} False{} Some{image}: encoded.formatted(J.Image.Formatted.to_png(image))
    case True{} True{} Some{image}: Some{J.Image.Formatted.png.file_bytes(image)}
def encode(formatted: Bool, file_only: Bool, width: U32, height: U32, format: U32, bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  encoded(formatted, file_only, J.Image.Formatted.from_bytes(width, height, format, bytes))
def expanded(bytes: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (pixels, +value) = read
  (pixels, Con{(value .&. 255 : U32), Con{((value >> 8n) .&. 255 : U32), Con{((value >> 16n) .&. 255 : U32), Con{(value >> 24n : U32), bytes}}}})
def raw_bytes(n: Nat, +index: U32, state: Array<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{_, bytes}: List.reverse(&2, U32, bytes)
    case 1n+rest Tuple{pixels, bytes}: raw_bytes(rest, (index + 1 : U32), expanded(bytes, Array.get(U32, pixels, index)))
def dimensions(valid: Bool, count: U32, pixels: Array<U32>) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit, 1, "PNG round-trip dimensions differ")
    case True{}: emit_bytes(~&2, raw_bytes(U32.to_nat(count), 0, (pixels, Nil{})))
def decoded(width: U32, height: U32, result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "PNG candidate round trip failed")
    case Done{J.Surface{+w, +h, pixels}}: dimensions(U32.is_eq(width, w) && U32.is_eq(height, h), (w * h : U32), pixels)
def observed(width: U32, height: U32, result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "invalid PNG export fixture")
    case Some{+bytes}:
      do IO<Unit>:
        emit_bytes(~&2, bytes)
        decoded(width, height, J.Surface.decode_pngBANG(bytes))
def saved(formatted: Bool, path: String, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match formatted result:
    case _ None{}: IO.die(Unit, 1, "invalid PNG file fixture")
    case False{} Some{image}: IO.try(Unit, J.Surface.write_png(J.Image.Formatted.to_surface(image), path))
    case True{} Some{image}: IO.try(Unit, J.Image.Formatted.write_png(image, path))
def save_file(enabled: Bool, formatted: Bool, path: String, width: U32, height: U32, format: U32, bytes: +List<U32>) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: saved(formatted, path, J.Image.Formatted.from_bytes(width, height, format, bytes))
def payload(+formatted: Bool, file_only: Bool, +width: U32, +height: U32, +format: U32, save: Bool, path: String, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "PNG fixture read failed")
    case Done{+bytes}:
      do IO<Unit>:
        observed(width, height, encodeBANG(formatted, file_only, width, height, format, bytes))
        save_file(save, formatted, path, width, height, format, bytes)
def received(formatted: Bool, file_only: Bool, width: U32, height: U32, format: U32, save: Bool, path: String, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(formatted, file_only, width, height, format, save, path, status)
def opened(formatted: Bool, file_only: Bool, width: U32, height: U32, format: U32, size: U32, save: Bool, path: String, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "PNG fixture open failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(formatted, file_only, width, height, format, save, path))
def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('BANG','!' if lane=='metal' else '')
        saved_cases=[]
        for case in cases:
            save=lane!='metal' and ('format' in case or case['id'] in ('mixed','noise-filters'))
            if save:saved_cases.append(case['id'])
            path=work/f'{case["id"]}.rgba';output=work/f'{lane}-{case["id"]}.png'
            program+=f'    IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({json.dumps(str(path))}, "r"), opened({"True{}" if "format" in case else "False{}"}, {"True{}" if case.get("file_only") else "False{}"}, {case["width"]}, {case["height"]}, {case.get("format",7)}, {len(case["data"])}, {"True{}" if save else "False{}"}, {json.dumps(str(output))}))\n'
        source=work/f'{lane}.bend';source.write_text(program)
        binary=work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command))
        differences=[dict(index=i,case=cases[i//2]['id'],kind='encoded' if i%2==0 else 'pixels') for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        files_match=all((work/f'{lane}-{name}.png').read_bytes()==(work/f'reference-{name}.png').read_bytes() for name in saved_cases)
        report['lanes'][lane]=dict(passed=actual==expected and files_match,differences=differences,file_exports=len(saved_cases))
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected or not files_match:raise ValueError(f'{lane}: PNG export differences: {differences[:4]}')
        print(f'{lane}: {len(cases)} PNGs / {report["encoded_bytes"]} exact bytes and {report["roundtrip_bytes"]} round-trip bytes passed',flush=True)
    report['passed']=True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
