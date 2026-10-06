#!/usr/bin/env python3
"""Compare supported image-file dispatch with native raylib and check closure."""
import hashlib
import json
import resource
import struct

from conformance import image_decode_reference
from png_probe import png
from bmp_probe import bitmap, bitmap16, bitfield_bitmap, core_bitmap, core_indexed_bitmap, indexed_bitmap
from tga_probe import indexed_targa, targa
from psd_probe import alpha_planes, psd, rle_psd
from pic_probe import pic, pic_packets
from gif_probe import gif
import probekit
from probekit import ROOT, ProbeFailure

FILE_DESCRIPTOR_LIMIT=64


def limit_handles():
    resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))


def image_streams():
    rgba=bytes([1,2,3,0, 17,63,201,128, 255,127,128,255, 254,253,252,1, 0,255,0,127, 255,0,255,255])
    pixels=[int.from_bytes(rgba[i:i+4],'big') for i in range(0,len(rgba),4)]
    bgra=bytes(v for i in range(0,len(rgba),4) for v in (rgba[i+2],rgba[i+1],rgba[i],rgba[i+3]))
    cross=targa(3,2,4,[5,*bgra],rle=True,top=True);cross[2]=11
    return {'png':png(3,2,6,rgba,interlaced=True),
            'bmp':bytes(bitmap(3,2,pixels,top=True)),
            'tga':bytes(targa(3,2,4,[5,*bgra],rle=True,top=True)),
            'pgm':b'P5\n# gray\n3 2\n255\n'+bytes([0,1,127,128,254,255]),
            'ppm':b'P6\n3 2\n255\n'+bytes(v for i in range(0,len(rgba),4) for v in rgba[i:i+3]),
            'qoi':b'qoif'+struct.pack('>II',3,2)+b'\4\0'+b''.join(b'\xff'+rgba[i:i+4] for i in range(0,len(rgba),4))+b'\0'*7+b'\1',
            'ppm16':b'P6\n3 2\n65535\n'+bytes(value for i in range(18) for value in ((i*43+128)&255,(i*61+17)&255)),
            'tga16':bytes(targa(3,2,3,b''.join(struct.pack('<H',value) for value in (0,1,31,1023,0x7fff,0xffff)),bits=16,top=True)),
            'tga-indexed':bytes(indexed_targa(3,2,[b'\3\2\1\0',b'\30\20\10\xff'],8,32,[0,1,1,0,2,255],skip=3,top=True)),
            'bmp-indexed':bytes(indexed_bitmap(3,2,[0,1,2,2,1,0],[0x01020300,0x10203080,0xaabbcc01],gap=2,colors_used=1)),
            'bmp16':bytes(bitmap16(3,2,[0,0xffff,0x1000,0x9000,0x1234,0x5678],gap=4)),
            'bmp-bitfields':bytes(bitfield_bitmap(3,2,[0,0xffff,0x400,0x2404,0x1234,0x5678],gap=4)),
            'bmp56':bytes(bitfield_bitmap(3,2,[0,0xffff,0x400,0x2404,0x1234,0x5678],dib=56,gap=3)),
            'bmp-v5':bytes(bitfield_bitmap(3,2,[0x1000,0x9000,0x123,0xffff,0,0x7fff],dib=124,masks=(0x123,0x456,0x789,0x8000),compression=0)),
            'bmp-core':bytes(core_bitmap(3,2,pixels,gap=4)),
            'bmp-core-indexed':bytes(core_indexed_bitmap(3,2,[0,1,2,2,1,0],[0x01020300,0x10203080,0xaabbcc01],remainder=2)),
            'tga-cross':bytes(cross),
            'psd':bytes(psd(3,2,[[1,4,7,10,13,16],[2,5,8,11,14,17],[3,6,9,12,15,18]])),
            'psd-rle':bytes(rle_psd(3,2,[[128,1,1,4,253,7],[255,2,253,5],[5,3,6,9,12,15,18]],depth=16)),
            'psd-alpha':bytes(psd(3,2,alpha_planes())),
            'pic':bytes(pic(3,2,[(0xe0,pixels),(0x90,[0x07000000,0x08000080,0x090000ff,0x0a00007f,0x0b000001,0x0c0000fe])])),
            'pic-rle':bytes(pic_packets(3,2,[(2,0xf0,[[2,*rgba[:12]],[2,*rgba[12:]]])])),
            'gif':bytes(gif(3,2,[0,1,2,3,2,1],[0x010203ff,0x112233ff,0xaabbccff,0xfedcbaff],transparent=1)),
            'gif-interlaced':bytes(gif(5,4,[0,1,2,3,2,1],[0x010203ff,0x112233ff,0xaabbccff,0xfedcbaff],
                transparent=1,background=2,frame=(1,1,3,2),interlaced=True))}


PROGRAM='''import Base
import ../../jonlib.bend as J
def error_name(error: J.Image.LoadError) -> String:
  match error:
    case J.ImageFileError{_, _}: "file"
    case J.ImageDecodeError{J.UnsupportedImageSize{}}: "size"
    case _: "decode"
def observed(result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("{\\"loaded\\":false,\\"error\\":\\"" ++ error_name(error) ++ "\\"}")
    case Done{J.Surface{+w, +h, pixels}}:
      IO.print("{\\"loaded\\":true,\\"width\\":" ++ U32.show(w) ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"pixels\\":" ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{w, h, pixels})) ++ "}")
def checked(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "image-file outcome or closure differs")
def required(expected: String, result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  match result:
    case Done{_}: checked(String.eq(expected, "success"))
    case Fail{error}: checked(String.eq(expected, error_name(error)))
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"closure_checks\\":true}")
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_image_for(REFERENCE, VALID), required("success"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_image_for(REFERENCE, INVALID), required("decode"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_image_for(REFERENCE, DIRECTORY), required("file"))
        IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_image_for(REFERENCE, LARGE), required("size"))
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def main():
    probe=probekit.Probe('image-file',probekit.arguments(__doc__));work=probe.work
    streams=image_streams()
    cases=[]
    def add(name,data,error=None,legacy=False):
        path=work/name
        path.parent.mkdir(parents=True,exist_ok=True)
        if data is not None:path.write_bytes(data)
        elif path.exists():raise ProbeFailure('Task-owned missing-file fixture unexpectedly exists')
        cases.append(dict(path=str(path.relative_to(ROOT)),data=list(data) if data is not None else None,error=error,legacy=legacy))
    for extension in ('png','bmp','tga','pgm','ppm','qoi','psd','pic','gif'):
        add(f'normal.{extension}',streams[extension]);add(f'upper.{extension.upper()}',streams[extension])
    add('wide-samples.ppm',streams['ppm16'])
    add('packed.tga',streams['tga16'])
    add('indexed.tga',streams['tga-indexed'])
    add('indexed.bmp',streams['bmp-indexed'])
    add('packed.bmp',streams['bmp16'])
    add('bitfields.bmp',streams['bmp-bitfields'])
    add('header56.bmp',streams['bmp56']);add('header-v5.bmp',streams['bmp-v5'])
    add('header-core.bmp',streams['bmp-core'])
    add('core-indexed.bmp',streams['bmp-core-indexed'])
    add('cross-type.tga',streams['tga-cross'])
    add('rle.psd',streams['psd-rle'])
    add('alpha.psd',streams['psd-alpha'])
    add('rle.pic',streams['pic-rle'])
    add('offset-interlaced.gif',streams['gif-interlaced'])
    for name,kind in [('png-data.bmp','png'),('bmp-data.png','bmp'),('pnm-data.tga','ppm'),('tga-data.ppm','tga')]:add(name,streams[kind])
    add('mixed.PnG',streams['png'],'decode');add('unsupported.data',streams['png'],'decode')
    add('qoi-data.png',streams['qoi'],'decode');add('png-data.qoi',streams['png'],'decode')
    add('malformed.png',b'invalid','decode');add('empty.png',b'','decode');add('missing.png',None,'file')
    add('explicit-qoi.data',streams['qoi'],legacy=True)
    for extension in ('jpg','jpeg','gif','pic','psd'):
        add(f'alias.{extension}',streams['png']);add(f'alias.{extension.upper()}',streams['png'])
    add('many.parts.JPEG',streams['png']);add('.png',streams['png'])
    add('mixed.JpEg',streams['png'],'decode');add('folder.png/no-extension',streams['png'],'decode')
    controls=[]
    for name,size in [('large.png',1048577),('large.qoi',83886103)]:
        path=work/name
        with path.open('wb') as file:file.truncate(size)
        controls.append(dict(path=str(path.relative_to(ROOT)),size=size,error='size',legacy=False))
    directory=work/'directory.png';directory.mkdir(exist_ok=True);(directory/'entry').write_bytes(b'x')
    controls.append(dict(path=str(directory.relative_to(ROOT)),error='file',legacy=False))
    lines=['#include "raylib.h"','#include <stdio.h>',
           'static void emit(Image image){if(!image.data){puts("{\\"loaded\\":false}");return;}ImageFormat(&image,7);',
           'printf("{\\"loaded\\":true,\\"width\\":%d,\\"height\\":%d,\\"pixels\\":[",image.width,image.height);',
           'Color *pixels=LoadImageColors(image);for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(pixels[i]));',
           'puts("]}");UnloadImageColors(pixels);UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path=json.dumps(case['path'])
        if case['legacy']:
            lines+=['{int size=0;',f'unsigned char *data=LoadFileData({path},&size);',
                    'emit(LoadImageFromMemory(".qoi",data,size));UnloadFileData(data);}']
        else:lines += [f'emit(LoadImage({path}));']
    text=probe.native('\n'.join(lines+['}'])+'\n');expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native image-file results')
    if any(row['loaded']!=(case['error'] is None) for case,row in zip(cases,expected)):raise ProbeFailure('Native image-file acceptance differs from fixture profile')
    profile=image_decode_reference()
    preamble=PROGRAM.replace('REFERENCE',f'J.{profile}{{}}')
    for key,path in [('INVALID',work/'malformed.png'),('VALID',work/'alpha.psd'),('DIRECTORY',directory),('LARGE',work/'large.png')]:
        preamble=preamble.replace(key,json.dumps(str(path.relative_to(ROOT))))
    # Native pixels/dispatch plus the fixture's error kind; boundaries and closure have no native row.
    actions=[('case',case) for case in cases]+[('control',case) for case in controls]+[('closure',None)]
    wanted=[dict(row,error=case['error']) if case['error'] else row for case,row in zip(cases,expected)]
    wanted+=[dict(loaded=False,error=case['error']) for case in controls]+[dict(closure_checks=True)]

    def render(selected,gpu):
        body=preamble
        for kind,case in selected:
            if kind=='closure':body+='    closure_loop(100n)\n';continue
            function='load_qoi' if case['legacy'] else 'load_image_for'
            reference='' if case['legacy'] else f'J.{profile}{{}}, '
            body+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.{function}({reference}{json.dumps(case["path"])}), observed)\n'
        return body

    def parse(text,selected):
        rows=[json.loads(line) for line in text.splitlines() if line.strip()]
        # Error kinds are compared only where the fixture profile names one.
        return [{k:v for k,v in row.items() if k!='error'} if kind=='case' and not case['error'] else row
                for (kind,case),row in zip(selected,rows)]+rows[len(selected):]

    probe.compare(wanted,probe.candidates(render,actions,batch=len(actions),fd_limit=FILE_DESCRIPTOR_LIMIT,parse=parse),
                  describe=lambda i:f'action {i} ({actions[i][1]["path"] if actions[i][1] else "closure"})')
    probe.finish(reference_cases=len(cases),boundary_controls=len(controls),closure_iterations=100,file_descriptor_limit=FILE_DESCRIPTOR_LIMIT,decode_reference=profile,
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
