#!/usr/bin/env python3
"""Compare native extension-token/content dispatch for implemented memory codecs."""
import hashlib
import json

from conformance import image_decode_reference
from image_file_probe import image_streams
from bmp_probe import bend_bytes
import probekit
from probekit import ProbeFailure

PREAMBLE='''import Base
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


def main():
    probe=probekit.Probe('image-memory',probekit.arguments(__doc__))
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
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native memory dispatch results')
    controls=[('.png',[256],1),('.qoi',[256],1),('.unknown',[256],0),('.png',[],0),('.png',[137,80],0)]
    batch_size=64;profile=image_decode_reference()
    actions=[('case',case['token'],case['data']) for case in cases]+[('control',token,data) for token,data,_ in controls]

    def render(selected,gpu):
        bang='!' if gpu else '';body=PREAMBLE
        for kind,token,data in selected:
            call=f'J.Surface.decode_image_for{bang}(J.{profile}{{}}, {json.dumps(token)}, {bend_bytes(data)})'
            body+=f'    observed({call})\n' if kind=='case' else f'    IO.print(U32.show(error_code({call})))\n'
        return body

    wanted=expected+[code for _,_,code in controls]
    probe.compare(wanted,probe.candidates(render,actions,batch=batch_size),describe=lambda i:f'action {i} ({actions[i][0]} {json.dumps(actions[i][1])})')
    probe.finish(native_cases=len(cases),loaded_cases=sum(row['loaded'] for row in expected),invalid_controls=len(controls),batch_size=batch_size,decode_reference=profile,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
