#!/usr/bin/env python3
"""Compare owned GIF animation frames with native LoadImageAnimFromMemory."""
import hashlib
import json

from bmp_probe import bend_bytes
from conformance import image_decode_reference
from gif_probe import animation
from image_file_probe import image_streams
import probekit
from probekit import ProbeFailure
from psd_probe import psd


def fixtures():
    colors=[0x010203ff,0x112233ff,0xaabbccff,0xfedcbaff]
    cases=[]
    def add(name,width,height,frames,background=0):
        cases.append(dict(id=name,token='.gif',width=width,height=height,frames=len(frames),bytes=animation(width,height,colors,frames,background=background)))
    add('single',3,2,[dict(indices=[0,1,2,3,2,1])])
    for disposal in (0,1,2):
        add(f'full-disposal-{disposal}',3,2,[dict(indices=[1]*6,disposal=disposal),
            dict(indices=[0,2,0,3,0,2],transparent=0,disposal=1),dict(indices=[0,3,0,2,0,3])])
    add('offset-restore',4,3,[dict(indices=[1]*12,disposal=0),
        dict(indices=[0,2,0,2],frame=(1,1,2,2),transparent=0,disposal=2),
        dict(indices=[3],frame=(3,2,1,1),disposal=0)])
    add('palette-background-persistence',4,2,[dict(indices=[1],frame=(1,0,1,1),transparent=1,disposal=0),
        dict(indices=[1]*8),dict(indices=[1]*8,local=list(reversed(colors)))],background=1)
    add('local-global-controls',3,2,[dict(indices=[0,1,2,3,2,1],transparent=1,disposal=1),
        dict(indices=[1,2,3,0,1,2],local=list(reversed(colors))),dict(indices=[1]*6,disposal=0)])
    add('offset-interlaced',8,10,[dict(indices=[i%4 for i in range(80)],disposal=1),
        dict(indices=[(i*3+i//5)%4 for i in range(45)],frame=(1,1,5,9),interlaced=True,transparent=1,disposal=2),
        dict(indices=[3],frame=(7,9,1,1),disposal=0)])
    add('delay-ignored',2,1,[dict(indices=[0,1],disposal=1,delay=65535),dict(indices=[1,0],disposal=0,delay=0)])
    cases += [dict(cases[1],id='uppercase-gif',token='.GIF'),dict(cases[1],id='gif-under-png',token='.png',frames=1)]
    streams=image_streams()
    for kind,token in [('png','.png'),('bmp','.bmp'),('tga','.tga'),('pgm','.pgm'),('ppm','.ppm'),('qoi','.qoi'),('psd-alpha','.psd'),('pic','.pic')]:
        cases.append(dict(id='single-'+kind,token=token,width=3,height=2,frames=1,bytes=list(streams[kind])))
    cases.append(dict(id='png-under-jpg',token='.jpg',width=3,height=2,frames=1,bytes=list(streams['png'])))
    base=cases[1]['bytes'];width=cases[1]['width'];height=cases[1]['height'];count=cases[1]['frames']
    controls=[dict(id='zero-frames',bytes=base,maximum_frames=0,maximum_pixels=100,error=2),
              dict(id='zero-pixels',bytes=base,maximum_frames=10,maximum_pixels=0,error=2),
              dict(id='oversize-pixel-budget',bytes=base,maximum_frames=10,maximum_pixels=16777217,error=2),
              dict(id='frame-budget',bytes=base,maximum_frames=count-1,maximum_pixels=width*height*count,error=2),
              dict(id='pixel-budget',bytes=base,maximum_frames=count,maximum_pixels=width*height*count-1,error=2),
              dict(id='unsupported-disposal',bytes=animation(1,1,colors,[dict(indices=[0],disposal=3)]),maximum_frames=2,maximum_pixels=2,error=0),
              dict(id='missing-terminator',bytes=base[:-1],maximum_frames=10,maximum_pixels=100,error=0),
              dict(id='no-frame',bytes=animation(1,1,colors,[]),maximum_frames=2,maximum_pixels=2,error=0),
              dict(id='bad-later-frame',bytes=animation(2,1,colors,[dict(indices=[0,1]),dict(indices=[2],frame=(2,0,1,1))]),maximum_frames=2,maximum_pixels=4,error=0),
              dict(id='bad-byte',bytes=[*base,256],maximum_frames=10,maximum_pixels=100,error=1)]
    for case in controls:case['token']='.gif'
    controls += [dict(id='mixed-gif-token',token='.GiF',bytes=base,maximum_frames=10,maximum_pixels=100,error=0),
                 dict(id='wrong-gif-payload',token='.gif',bytes=list(streams['png']),maximum_frames=10,maximum_pixels=100,error=0),
                 dict(id='unsupported-token',token='.unknown',bytes=list(streams['png']),maximum_frames=10,maximum_pixels=100,error=0),
                 dict(id='single-pixel-budget',token='.png',bytes=list(streams['png']),maximum_frames=1,maximum_pixels=5,error=2),
                 dict(id='single-frame-budget',token='.png',bytes=list(streams['png']),maximum_frames=0,maximum_pixels=6,error=2)]
    return cases,controls


def reference_program(cases):
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static void emit(const char *token,const unsigned char *data,int size){int frames=0;Image image=LoadImageAnimFromMemory(token,data,size,&frames);if(!image.data)exit(2);ImageFormat(&image,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);',
           'printf("{\\"width\\":%d,\\"height\\":%d,\\"count\\":%d}\\n",image.width,image.height,frames);',
           'for(int f=0;f<frames;f++){putchar(\'[\');for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(((Color*)image.data)[f*image.width*image.height+i]));puts("]");}UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:lines+=['{unsigned char data[]={'+','.join(map(str,case['bytes']))+'};emit('+json.dumps(case['token'])+',data,sizeof(data));}']
    return '\n'.join(lines+['}'])+'\n'


def grouped(lines, actions):
    """One row per action: an animation is its header line plus one line per frame; leftovers form an extra row."""
    rows,at=[],0
    for kind,case in actions:
        if at>=len(lines):break
        size=1+case['frames'] if kind=='animation' else 1
        rows.append(lines[at:at+size] if kind=='animation' else lines[at]);at+=size
    return rows+([lines[at:]] if at<len(lines) else [])


PROGRAM='''import Base
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
def emit_colors(result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "animation frame colors unavailable")
    case Done{colors}: IO.print(List.show(~&1, ~U32, ~U32.show, colors))
def emit_frames(frames: List<J.Surface>) -> IO(Unit):
  match frames:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{surface, rest}:
      do IO<Unit>:
        emit_colors(J.Surface.colors(surface))
        emit_frames(rest)
def emit_animation(result: U32 & U32 & U32 & List<J.Surface>) -> IO(Unit):
  (width, height, count, frames) = result
  do IO<Unit>:
    IO.print("{\\"width\\":" ++ U32.show(width) ++ ",\\"height\\":" ++ U32.show(height) ++ ",\\"count\\":" ++ U32.show(count) ++ "}")
    emit_frames(frames)
def observed(result: Result<&1, &1, J.Surface.Error, J.Image.Animation>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid animation rejected")
    case Done{animation}: emit_animation(J.Image.Animation.entries(animation))
def error_code(result: Result<&1, &1, J.Surface.Error, J.Image.Animation>) -> U32:
  match result:
    case Done{_}: 99
    case Fail{error}:
      match error:
        case J.InvalidImageHeader{}: 0
        case J.InvalidImageByte{}: 1
        case J.UnsupportedImageSize{}: 2
        case J.TruncatedImageData{}: 3
        case J.InvalidImageStream{}: 4
        case _: 98
def second_kept(result: J.Surface & Maybe<&2, U32>) -> Bool:
  match result:
    case Tuple{_, Some{color}}: U32.is_eq(color, J.Color.rgba(17, 34, 51, 255))
    case _: False{}
def first_changed(second: J.Surface, result: J.Surface & Maybe<&2, U32>) -> Bool:
  match result:
    case Tuple{_, Some{0}}: second_kept(J.Surface.get(second, 0, 0))
    case _: False{}
def independent(frames: List<J.Surface>) -> Bool:
  match frames:
    case Con{first, Con{second, _}}: first_changed(second, J.Surface.get(J.Surface.draw_pixel(first, 0.0, 0.0, 0), 0, 0))
    case _: False{}
def owned_entries(result: U32 & U32 & U32 & List<J.Surface>) -> Bool:
  (width, height, count, frames) = result
  U32.is_eq(width, 3) && U32.is_eq(height, 2) && U32.is_eq(count, 3) && independent(frames)
def owned(result: Result<&1, &1, J.Surface.Error, J.Image.Animation>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{animation}: owned_entries(J.Image.Animation.entries(animation))
def unit_seen(value: Unit) -> Bool:
  True{}
def disposed(result: Result<&1, &1, J.Surface.Error, J.Image.Animation>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{animation}: unit_seen(J.Image.Animation.unload(animation))
def default_pixel(result: J.Surface & Maybe<&2, U32>) -> Bool:
  match result:
    case Tuple{_, Some{color}}: U32.is_eq(color, J.Color.rgba(255, 255, 255, 11))
    case _: False{}
def default_frames(frames: List<J.Surface>) -> Bool:
  match frames:
    case Con{surface, Nil{}}: default_pixel(J.Surface.get(surface, 0, 0))
    case _: False{}
def default_entries(result: U32 & U32 & U32 & List<J.Surface>) -> Bool:
  (width, height, count, frames) = result
  U32.is_eq(width, 1) && U32.is_eq(height, 1) && U32.is_eq(count, 1) && default_frames(frames)
def default_checked(result: Result<&1, &1, J.Surface.Error, J.Image.Animation>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{animation}: default_entries(J.Image.Animation.entries(animation))
def default_reference(bytes: +List<U32>) -> Bool:
  default_checked(J.Image.Animation.decode_image(".psd", bytes, 1, 1))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe=probekit.Probe('gif-animation',probekit.arguments(__doc__))
    cases,controls=fixtures()
    text=probe.native(reference_program(cases));native=[json.loads(line) for line in text.splitlines()]
    at=0
    for case in cases:
        if native[at]!={key:case[key] for key in ('width','height')}|{'count':case['frames']}:raise ProbeFailure('Native animation geometry/count differs')
        at+=1+case['frames']
    if at!=len(native):raise ProbeFailure('Incomplete native animation output')
    profile=image_decode_reference()
    actions=[('animation',c) for c in cases]+[('control',c) for c in controls]+[(name,dict(id=name)) for name in ('owned','disposed','default_reference')]
    expected=grouped(native,actions[:len(cases)])+[c['error'] for c in controls]+[1,1,1]

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM
        for kind,case in selected:
            if kind=='animation':body+=f'    observed(J.Image.Animation.decode_image_for{bang}(M.{profile}{{}}, {json.dumps(case["token"])}, {bend_bytes(case["bytes"])}, {case["frames"]}, {case["frames"]*case["width"]*case["height"]}))\n'
            elif kind=='control':body+=f'    IO.print(U32.show(error_code(J.Image.Animation.decode_image_for{bang}(M.{profile}{{}}, {json.dumps(case["token"])}, {bend_bytes(case["bytes"])}, {case["maximum_frames"]}, {case["maximum_pixels"]}))))\n'
            elif kind=='default_reference':body+=f'    IO.print(U32.show(Bool.to_u32(default_reference{bang}({bend_bytes(psd(1,1,[[255],[255],[255],[11]]))}))))\n'
            else:body+=f'    IO.print(U32.show(Bool.to_u32({kind}{bang}(J.Image.Animation.decode_gif({bend_bytes(cases[1]["bytes"])}, 3, 18)))))\n'
        return body

    parse=lambda text,selected:grouped([json.loads(line) for line in text.splitlines()],selected)
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=parse),lambda i:f'{actions[i][0]} {actions[i][1]["id"]}')
    probe.finish(animations=len(cases),frames=sum(c['frames'] for c in cases),decode_reference=profile,
                 pixels=sum(c['frames']*c['width']*c['height'] for c in cases),error_controls=len(controls),ownership_controls=2,default_reference_controls=1,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
