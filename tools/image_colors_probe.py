#!/usr/bin/env python3
"""Compare native bulk/point colors from formatted and RGB float images."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, run, source_gate
from formatted_float_probe import fixtures as formatted_fixtures
from float_rgb_probe import boundaries


def fixtures():
    cases=formatted_fixtures();words=boundaries()
    cases.append(dict(width=len(words)//3,height=1,format=9,bytes=list(struct.pack('<'+'I'*len(words),*words))))
    invalid=dict(width=2,height=1,format=9,bytes=list(struct.pack('<6f',2,0.5,0.75,0.25,0.5,0.75)))
    controls=[dict(cases[4],x=x,y=y,found=False) for x,y in ((16,0),(0,16),(4294967295,0))]
    controls += [dict(cases[-1],x=769,y=0,found=False),dict(invalid,x=0,y=0,found=False),dict(invalid,x=1,y=0,found=True)]
    return cases,controls,invalid


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'image-colors-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases,controls,invalid=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(Image image){if(!image.data)exit(2);word(image.width);word(image.height);word(image.format);',
        'int size=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<size;i++)byte(((unsigned char*)image.data)[i]);end();}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate([*cases,*controls,invalid]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},{case["format"]},0);if(!image.data)return 3;')
        if i<len(cases):
            lines+=['Color *colors=LoadImageColors(image);if(!colors)return 4;int n=image.width*image.height;',
                    'for(int j=0;j<n;j++)word(ColorToInt(colors[j]));end();',
                    'for(int j=0;j<n;j++){unsigned c=ColorToInt(GetImageColor(image,j%image.width,j/image.width));if(c!=ColorToInt(colors[j]))return 5;word(c);}end();UnloadImageColors(colors);']
        elif i<len(cases)+len(controls):
            lines.append(f'byte(1);word(ColorToInt(GetImageColor(image,{case["x"]},{case["y"]})));end();' if case['found'] else 'byte(0);end();')
        lines.append('emit(image);UnloadImage(image);}')
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=parse_results(text)
    if len(expected)!=3*len(cases)+2*len(controls)+1:raise ValueError('Incomplete native color observations')
    at=0
    for i,case in enumerate([*cases,*controls,invalid]):
        if i<len(cases):
            if len(expected[at])!=case['width']*case['height']*4 or expected[at]!=expected[at+1]:raise ValueError('Native bulk/point colors differ')
            at+=2
        elif i<len(cases)+len(controls):at+=1
        if expected[at]!=list(struct.pack('<III',case['width'],case['height'],case['format']))+case['bytes']:raise ValueError('Native color observation changed source')
        at+=1
    report=dict(passed=False,source_formats=len(cases),pixels=sum(c['width']*c['height'] for c in cases),point_controls=len(controls),bulk_rejected_owners=1,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps([cases,controls,invalid]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),lanes={})
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
def word_bytes(~q: Quant, n: Nat, +word: U32, values: List<q, U32>) -> List<q, U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(~q, rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def colors(values: List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: List.reverse(&1, U32, bytes)
    case Con{word, rest}: colors(rest, word_bytes(~&1, 4n, word, bytes))
'''+BEND_EMITTER+'''
def emitted(~q: Quant, width: U32, height: U32, format: U32, bytes: List<q, U32>) -> IO(Unit):
  header = List.reverse(q, U32, word_bytes(~q, 4n, format, word_bytes(~q, 4n, height, word_bytes(~q, 4n, width, Nil{}))))
  emit_bytes(~q, List.append(q, U32, header, bytes))
def formatted(result: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = result
  emitted(~&1, width, height, format, bytes)
def float_bytes(width: U32, height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "retained float source changed")
    case Done{bytes}: emitted(~&2, width, height, 9, bytes)
def float_image(image: J.Image.FloatRGB) -> IO(Unit):
  J.FloatRGB{+width, +height, pixels} = image
  float_bytes(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def formatted_bulk(result: Maybe<J.Image.Formatted>) -> Maybe<List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.colors(image)}
def float_bulk(result: Maybe<J.Image.FloatRGB>) -> Maybe<Result<&1, &1, J.Image.FloatRGB, List<U32>>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.FloatRGB.colors(image)}
def emit_bulk(result: Maybe<List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid bulk colors rejected")
    case Some{values}: emit_bytes(~&1, colors(values, Nil{}))
def emit_float_bulk(reject: Bool, result: Maybe<Result<&1, &1, J.Image.FloatRGB, List<U32>>>) -> IO(Unit):
  match reject result:
    case False{} Some{Done{values}}: emit_bytes(~&1, colors(values, Nil{}))
    case True{} Some{Fail{image}}: float_image(image)
    case _ _: IO.die(Unit, 1, "float bulk domain/owner differs")
def formatted_read(values: List<U32>, result: J.Image.Formatted & Maybe<&2, U32>) -> Maybe<(J.Image.Formatted & List<U32>)>:
  match result:
    case Tuple{source, Some{color}}: Some{(source, Con{color, values})}
    case _: None{}
def float_read(values: List<U32>, result: J.Image.FloatRGB & Maybe<&2, U32>) -> Maybe<(J.Image.FloatRGB & List<U32>)>:
  match result:
    case Tuple{source, Some{color}}: Some{(source, Con{color, values})}
    case _: None{}
def formatted_points(n: Nat, +index: U32, +width: U32, state: Maybe<(J.Image.Formatted & List<U32>)>) -> Maybe<(J.Image.Formatted & List<U32>)>:
  match n state:
    case _ None{}: None{}
    case 0n _: state
    case 1n+rest Some{Tuple{source, values}}:
      formatted_points(rest, (index + 1 : U32), width, formatted_read(values, J.Image.Formatted.get(source, (index % width : U32), (index / width : U32))))
def float_points(n: Nat, +index: U32, +width: U32, state: Maybe<(J.Image.FloatRGB & List<U32>)>) -> Maybe<(J.Image.FloatRGB & List<U32>)>:
  match n state:
    case _ None{}: None{}
    case 0n _: state
    case 1n+rest Some{Tuple{source, values}}:
      float_points(rest, (index + 1 : U32), width, float_read(values, J.Image.FloatRGB.get(source, (index % width : U32), (index / width : U32))))
def formatted_walk(result: Maybe<J.Image.Formatted>) -> Maybe<(J.Image.Formatted & List<U32>)>:
  match result:
    case None{}: None{}
    case Some{J.FormattedImage{+width, +height, format, pixels}}:
      formatted_points(U32.to_nat((width * height : U32)), 0, width, Some{(J.FormattedImage{width, height, format, pixels}, Nil{})})
def float_walk(result: Maybe<J.Image.FloatRGB>) -> Maybe<(J.Image.FloatRGB & List<U32>)>:
  match result:
    case None{}: None{}
    case Some{J.FloatRGB{+width, +height, pixels}}:
      float_points(U32.to_nat((width * height : U32)), 0, width, Some{(J.FloatRGB{width, height, pixels}, Nil{})})
def emit_formatted_points(result: Maybe<(J.Image.Formatted & List<U32>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid formatted point rejected")
    case Some{Tuple{source, values}}:
      do IO<Unit>:
        emit_bytes(~&1, colors(List.reverse(&1, U32, values), Nil{}))
        formatted(J.Image.Formatted.export(source))
def emit_float_points(result: Maybe<(J.Image.FloatRGB & List<U32>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid float point rejected")
    case Some{Tuple{source, values}}:
      do IO<Unit>:
        emit_bytes(~&1, colors(List.reverse(&1, U32, values), Nil{}))
        float_image(source)
def point(value: Maybe<&2, U32>) -> IO(Unit):
  match value:
    case None{}: emit_bytes(~&1, [0])
    case Some{color}: emit_bytes(~&1, Con{1, colors([color], Nil{})})
def formatted_get(x: U32, y: U32, source: Maybe<J.Image.Formatted>) -> Maybe<(J.Image.Formatted & Maybe<&2, U32>)>:
  match source:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.get(image, x, y)}
def float_get(x: U32, y: U32, source: Maybe<J.Image.FloatRGB>) -> Maybe<(J.Image.FloatRGB & Maybe<&2, U32>)>:
  match source:
    case None{}: None{}
    case Some{image}: Some{J.Image.FloatRGB.get(image, x, y)}
def emit_formatted_get(result: Maybe<(J.Image.Formatted & Maybe<&2, U32>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "formatted control source rejected")
    case Some{Tuple{source, value}}:
      do IO<Unit>:
        point(value)
        formatted(J.Image.Formatted.export(source))
def emit_float_get(result: Maybe<(J.Image.FloatRGB & Maybe<&2, U32>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "float control source rejected")
    case Some{Tuple{source, value}}:
      do IO<Unit>:
        point(value)
        float_image(source)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    def image(case):
        floating=case['format']==9;owner='FloatRGB' if floating else 'Formatted'
        return f'J.Image.{owner}.from_bytes({case["width"]}, {case["height"]}, '+('' if floating else f'{case["format"]}, ')+bend_bytes(case['bytes'])+')'
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        bang='!' if lane=='metal' else '';body=program
        for case in cases:
            kind='float' if case['format']==9 else 'formatted';created=image(case)
            body+=f'    emit_float_bulk(False{{}}, float_bulk{bang}({created}))\n' if kind=='float' else f'    emit_bulk(formatted_bulk{bang}({created}))\n'
            body+=f'    emit_{kind}_points({kind}_walk{bang}({created}))\n'
        for case in controls:
            kind='float' if case['format']==9 else 'formatted'
            body+=f'    emit_{kind}_get({kind}_get{bang}({case["x"]}, {case["y"]}, {image(case)}))\n'
        body+=f'    emit_float_bulk(True{{}}, float_bulk{bang}({image(invalid)}))\n'
        source=work/f'{lane}.bend';source.write_text(body);binary=work/('candidate.js' if lane=='javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual=parse_results(run(command));different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane]=dict(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: image color differences {different}')
        print(f'{lane}: 8 formats / {report["pixels"]} native bulk/point colors, 6 point controls and retained rejected bulk owner passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
