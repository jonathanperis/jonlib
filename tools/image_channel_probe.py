#!/usr/bin/env python3
"""Compare native grayscale channel extraction, selector rules and source owners."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import f32
from formatted_float_probe import fixtures as formatted_fixtures
from float_rgb_probe import boundaries
import probekit
from probekit import ROOT, ProbeFailure


def fixtures():
    sources=formatted_fixtures();words=boundaries()
    sources.append(dict(width=len(words)//3,height=1,format=9,bytes=list(struct.pack('<'+'I'*len(words),*words))))
    cases=[dict(source,selected=selected) for source in sources for selected in (-32767,0,1,2,3,32767)]
    controls=[dict(sources[-2],selected=selected) for selected in (0.5,32768)]
    controls.append(dict(sources[-2],bits=0x7f800000))
    controls += [dict(sources[-1],selected=0.5),dict(sources[-1],bits=0x80000001),dict(sources[-1],bits=0x7fc00000)]
    controls.append(dict(width=1,height=1,format=9,bytes=list(struct.pack('<fff',2,0.5,0.75)),selected=1))
    return cases,controls


PROGRAM='''import Base
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
def channel(reject: Bool, result: Maybe<J.Surface>) -> IO(Unit):
  match reject result:
    case True{} None{}: IO.pure(Unit, Unit{})
    case False{} Some{image}: formatted(J.Surface.export(image))
    case _ _: IO.die(Unit, 1, "channel acceptance differs")
def observed(reject: Bool, result: Maybe<(J.Surface & Maybe<J.Surface>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid channel source rejected")
    case Some{Tuple{source, gray}}:
      do IO<Unit>:
        formatted(J.Surface.export(source))
        channel(reject, gray)
def extracted(selected: F32, result: Maybe<J.Surface>) -> Maybe<(J.Surface & Maybe<J.Surface>)>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Surface.from_channel(image, selected)}
def formatted_read(result: Array<U32> & U32) -> Bool:
  (_, value) = result
  U32.is_eq(value, 16909060)
def float_read(result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{r, g, b}}: F32.is_eq(r, 0.25) && F32.is_eq(g, 0.5) && F32.is_eq(b, 0.75)
def gray_read(result: Array<U32> & U32) -> Bool:
  (_, value) = result
  U32.is_eq(value, 0)
def formatted_independent(result: J.Surface & Maybe<J.Surface>) -> Bool:
  match result:
    case Tuple{J.Surface{1, 1, 7, J.Words{source}}, Some{J.Surface{1, 1, 1, J.Words{gray}}}}:
      gray_read(Array.get(U32, Array.set(U32, gray, 0, 0), 0)) && formatted_read(Array.get(U32, source, 0))
    case _: False{}
def float_independent(result: J.Surface & Maybe<J.Surface>) -> Bool:
  match result:
    case Tuple{J.Surface{1, 1, 9, J.Vectors{source}}, Some{J.Surface{1, 1, 1, J.Words{gray}}}}:
      gray_read(Array.get(U32, Array.set(U32, gray, 0, 0), 0)) && float_read(Array.get(M.Vector3, source, 0))
    case _: False{}
def formatted_ownership() -> Bool:
  formatted_independent(J.Surface.from_channel(J.Surface{1, 1, 7, J.Words{Array.new(U32, 0n, 16909060)}}, 2.0))
def float_ownership() -> Bool:
  float_independent(J.Surface.from_channel(J.Surface{1, 1, 9, J.Vectors{Array.new(M.Vector3, 0n, M.Vector3{0.25, 0.5, 0.75})}}, 1.0))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def grouped(rows,sizes):
    """Split flat byte results into one group per action (sizes[i] results each)."""
    if len(rows)!=sum(sizes):raise ProbeFailure(f'image-channel: {len(rows)} byte results for {sum(sizes)} expected')
    groups,at=[],0
    for size in sizes:groups.append(rows[at:at+size]);at+=size
    return groups


def main():
    probe=probekit.Probe('image-channel',probekit.arguments(__doc__));work=probe.work
    cases,controls=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
        'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
        'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
        'static void emit(Image image){if(!image.data)exit(2);word(image.width);word(image.height);word(image.format);',
        'int size=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<size;i++)byte(((unsigned char*)image.data)[i]);end();}',
        'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i,case in enumerate([*cases,*controls]):
        path=work/(str(i)+'.raw');path.write_bytes(bytes(case['bytes']))
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},{case["format"]},0);')
        if i<len(cases):lines.append(f'Image channel=ImageFromChannel(image,{case["selected"]});emit(image);emit(channel);UnloadImage(channel);')
        else:lines.append('emit(image);')
        lines.append('UnloadImage(image);}')
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=parse_results(text)
    if len(expected)!=2*len(cases)+len(controls):raise ProbeFailure('Incomplete native channel output')
    at=0
    for i,case in enumerate([*cases,*controls]):
        if expected[at]!=list(struct.pack('<III',case['width'],case['height'],case['format']))+case['bytes']:raise ProbeFailure('Native channel extraction altered source')
        at+=1
        if i<len(cases):
            if expected[at][:12]!=list(struct.pack('<III',case['width'],case['height'],1)) or len(expected[at])!=12+case['width']*case['height']:raise ProbeFailure('Native grayscale shape differs')
            at+=1
    # Native source+channel results, retained rejected owners, then two independence controls.
    actions=[('case',case) for case in cases]+[('control',case) for case in controls]+[('ownership','formatted'),('ownership','float')]
    sizes=lambda selected:[2 if kind=='case' else 1 for kind,_ in selected]
    wanted=grouped(expected+[[1],[1]],sizes(actions))

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM
        for kind,case in selected:
            if kind=='ownership':
                body+=f'    emit_bytes(~&1, [Bool.to_u32({case}_ownership{bang}())])\n';continue
            selector=f'H.float_bits({case["bits"]})' if 'bits' in case else f32(case['selected'])
            arguments=f'{case["width"]}, {case["height"]}, {case["format"]}, '+bend_bytes(case['bytes'])
            body+=f'    observed({"True" if kind=="control" else "False"}{{}}, extracted{bang}({selector}, J.Surface.from_bytes({arguments})))\n'
        return body

    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:grouped(parse_results(text),sizes(selected))))
    probe.finish(native_cases=len(cases),channel_pixels=sum(c['width']*c['height'] for c in cases),rejected_owner_controls=len(controls),independence_controls=2,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
