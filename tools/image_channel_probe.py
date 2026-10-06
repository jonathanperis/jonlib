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
def float_bytes(width: U32, height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "retained float channel source changed")
    case Done{bytes}: emitted(~&2, width, height, 9, bytes)
def float_image(image: J.Image.FloatRGB) -> IO(Unit):
  J.FloatRGB{+width, +height, pixels} = image
  float_bytes(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def channel(reject: Bool, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match reject result:
    case True{} None{}: IO.pure(Unit, Unit{})
    case False{} Some{image}: formatted(J.Image.Formatted.export(image))
    case _ _: IO.die(Unit, 1, "channel acceptance differs")
def formatted_result(reject: Bool, result: Maybe<(J.Image.Formatted & Maybe<J.Image.Formatted>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid formatted source rejected")
    case Some{Tuple{source, gray}}:
      do IO<Unit>:
        formatted(J.Image.Formatted.export(source))
        channel(reject, gray)
def float_result(reject: Bool, result: Maybe<(J.Image.FloatRGB & Maybe<J.Image.Formatted>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid float source rejected")
    case Some{Tuple{source, gray}}:
      do IO<Unit>:
        float_image(source)
        channel(reject, gray)
def formatted_channel(selected: F32, result: Maybe<J.Image.Formatted>) -> Maybe<(J.Image.Formatted & Maybe<J.Image.Formatted>)>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.from_channel(image, selected)}
def float_channel(selected: F32, result: Maybe<J.Image.FloatRGB>) -> Maybe<(J.Image.FloatRGB & Maybe<J.Image.Formatted>)>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.FloatRGB.from_channel(image, selected)}
def formatted_read(result: Array<U32> & U32) -> Bool:
  (_, value) = result
  U32.is_eq(value, 67305985)
def float_read(result: Array<M.Vector3> & M.Vector3) -> Bool:
  match result:
    case Tuple{_, M.Vector3{r, g, b}}: F32.is_eq(r, 0.25) && F32.is_eq(g, 0.5) && F32.is_eq(b, 0.75)
def gray_read(result: Array<U32> & U32) -> Bool:
  (_, value) = result
  U32.is_eq(value, 0)
def formatted_independent(result: J.Image.Formatted & Maybe<J.Image.Formatted>) -> Bool:
  match result:
    case Tuple{J.FormattedImage{1, 1, 7, source}, Some{J.FormattedImage{1, 1, 1, gray}}}:
      gray_read(Array.get(U32, Array.set(U32, gray, 0, 0), 0)) && formatted_read(Array.get(U32, source, 0))
    case _: False{}
def float_independent(result: J.Image.FloatRGB & Maybe<J.Image.Formatted>) -> Bool:
  match result:
    case Tuple{J.FloatRGB{1, 1, source}, Some{J.FormattedImage{1, 1, 1, gray}}}:
      gray_read(Array.get(U32, Array.set(U32, gray, 0, 0), 0)) && float_read(Array.get(M.Vector3, source, 0))
    case _: False{}
def formatted_ownership() -> Bool:
  formatted_independent(J.Image.Formatted.from_channel(J.FormattedImage{1, 1, 7, Array.new(U32, 0n, 67305985)}, 2.0))
def float_ownership() -> Bool:
  float_independent(J.Image.FloatRGB.from_channel(J.FloatRGB{1, 1, Array.new(M.Vector3, 0n, M.Vector3{0.25, 0.5, 0.75})}, 1.0))
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
            floating=case['format']==9;family='float' if floating else 'formatted';owner='FloatRGB' if floating else 'Formatted'
            arguments=f'{case["width"]}, {case["height"]}, '+('' if floating else f'{case["format"]}, ')+bend_bytes(case['bytes'])
            body+=f'    {family}_result({"True" if kind=="control" else "False"}{{}}, {family}_channel{bang}({selector}, J.Image.{owner}.from_bytes({arguments})))\n'
        return body

    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),parse=lambda text,selected:grouped(parse_results(text),sizes(selected))))
    probe.finish(native_cases=len(cases),channel_pixels=sum(c['width']*c['height'] for c in cases),rejected_owner_controls=len(controls),independence_controls=2,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
