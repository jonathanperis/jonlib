#!/usr/bin/env python3
"""Compare native bulk/point colors from formatted and RGB float images."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from formatted_float_probe import fixtures as formatted_fixtures
from float_rgb_probe import boundaries
import probekit
from probekit import ROOT, ProbeFailure


def fixtures():
    cases=formatted_fixtures();words=boundaries()
    cases.append(dict(width=len(words)//3,height=1,format=9,bytes=list(struct.pack('<'+'I'*len(words),*words))))
    invalid=dict(width=2,height=1,format=9,bytes=list(struct.pack('<6f',2,0.5,0.75,0.25,0.5,0.75)))
    controls=[dict(cases[4],x=x,y=y,found=False) for x,y in ((16,0),(0,16),(4294967295,0))]
    controls += [dict(cases[-1],x=769,y=0,found=False),dict(invalid,x=0,y=0,found=False),dict(invalid,x=1,y=0,found=True)]
    return cases,controls,invalid


PROGRAM='''import Base
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
def bulk(result: Maybe<J.Surface>) -> Maybe<Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Surface.colors(image)}
def emit_bulk(reject: Bool, result: Maybe<Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>>) -> IO(Unit):
  match reject result:
    case False{} Some{Done{values}}: emit_bytes(~&1, colors(values, Nil{}))
    case True{} Some{Fail{Tuple{image, J.OutOfDomain{}}}}: formatted(J.Surface.export(image))
    case _ _: IO.die(Unit, 1, "bulk colors domain/owner differs")
def point_read(values: List<U32>, result: J.Surface & Maybe<&2, U32>) -> Maybe<(J.Surface & List<U32>)>:
  match result:
    case Tuple{source, Some{color}}: Some{(source, Con{color, values})}
    case _: None{}
def points(n: Nat, +index: U32, +width: U32, state: Maybe<(J.Surface & List<U32>)>) -> Maybe<(J.Surface & List<U32>)>:
  match n state:
    case _ None{}: None{}
    case 0n _: state
    case 1n+rest Some{Tuple{source, values}}:
      points(rest, (index + 1 : U32), width, point_read(values, J.Surface.get(source, (index % width : U32), (index / width : U32))))
def walk(result: Maybe<J.Surface>) -> Maybe<(J.Surface & List<U32>)>:
  match result:
    case None{}: None{}
    case Some{J.Surface{+width, +height, format, pixels}}:
      points(U32.to_nat((width * height : U32)), 0, width, Some{(J.Surface{width, height, format, pixels}, Nil{})})
def emit_points(result: Maybe<(J.Surface & List<U32>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid point rejected")
    case Some{Tuple{source, values}}:
      do IO<Unit>:
        emit_bytes(~&1, colors(List.reverse(&1, U32, values), Nil{}))
        formatted(J.Surface.export(source))
def point(value: Maybe<&2, U32>) -> IO(Unit):
  match value:
    case None{}: emit_bytes(~&1, [0])
    case Some{color}: emit_bytes(~&1, Con{1, colors([color], Nil{})})
def point_get(x: U32, y: U32, source: Maybe<J.Surface>) -> Maybe<(J.Surface & Maybe<&2, U32>)>:
  match source:
    case None{}: None{}
    case Some{image}: Some{J.Surface.get(image, x, y)}
def emit_get(result: Maybe<(J.Surface & Maybe<&2, U32>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "control source rejected")
    case Some{Tuple{source, value}}:
      do IO<Unit>:
        point(value)
        formatted(J.Surface.export(source))
def main() -> IO(Unit):
  do IO<Unit>:
'''
ROWS={'case':3,'control':2,'invalid':1}


def grouped(rows,selected):
    """Split flat byte results into one group per action (bulk/points/source, point/source or owner)."""
    sizes=[ROWS[kind] for kind,_ in selected]
    if len(rows)!=sum(sizes):raise ProbeFailure(f'image-colors: {len(rows)} byte results for {sum(sizes)} expected')
    groups,at=[],0
    for size in sizes:groups.append(rows[at:at+size]);at+=size
    return groups


def image(case):
    return f'J.Surface.from_bytes({case["width"]}, {case["height"]}, {case["format"]}, '+bend_bytes(case['bytes'])+')'


def render(selected,gpu):
    bang='!' if gpu else '';body=PROGRAM
    for kind,case in selected:
        if kind=='case':
            created=image(case)
            body+=f'    emit_bulk(False{{}}, bulk{bang}({created}))\n'
            body+=f'    emit_points(walk{bang}({created}))\n'
        elif kind=='control':body+=f'    emit_get(point_get{bang}({case["x"]}, {case["y"]}, {image(case)}))\n'
        else:body+=f'    emit_bulk(True{{}}, bulk{bang}({image(case)}))\n'
    return body


def main():
    probe=probekit.Probe('image-colors',probekit.arguments(__doc__));work=probe.work
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
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=parse_results(text)
    if len(expected)!=3*len(cases)+2*len(controls)+1:raise ProbeFailure('Incomplete native color observations')
    at=0
    for i,case in enumerate([*cases,*controls,invalid]):
        if i<len(cases):
            if len(expected[at])!=case['width']*case['height']*4 or expected[at]!=expected[at+1]:raise ProbeFailure('Native bulk/point colors differ')
            at+=2
        elif i<len(cases)+len(controls):at+=1
        if expected[at]!=list(struct.pack('<III',case['width'],case['height'],case['format']))+case['bytes']:raise ProbeFailure('Native color observation changed source')
        at+=1
    actions=[('case',case) for case in cases]+[('control',case) for case in controls]+[('invalid',invalid)]
    probe.compare(grouped(expected,actions),probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:grouped(parse_results(text),selected)))
    probe.finish(source_formats=len(cases),pixels=sum(c['width']*c['height'] for c in cases),point_controls=len(controls),bulk_rejected_owners=1,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls,invalid]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
