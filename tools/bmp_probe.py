#!/usr/bin/env python3
"""Compare bounded BMP pixels and complete RGBA8 export bytes with pinned raylib."""
import hashlib
import json
import struct

from conformance import image_decode_reference
import probekit
from probekit import ProbeFailure


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


def bitmap16(width,height,words,*,dib=40,top=False,gap=0,alpha_mask=0):
    stride=(width*2+3)&~3;payload=bytearray()
    for y in (range(height) if top else reversed(range(height))):
        for value in words[y*width:(y+1)*width]:payload.extend(struct.pack('<H',value))
        payload.extend(b'\xee'*(stride-width*2))
    header=struct.pack('<2sIHHI',b'BM',14+dib+2*gap+len(payload),0,0,14+dib+gap)
    header+=struct.pack('<IiiHHIIIIII',dib,width,-height if top else height,1,16,0,len(payload),0,0,0,0)
    if dib==108:header+=struct.pack('<IIII',0x123,0x456,0x789,alpha_mask)+bytes(52)
    return list(header+b'\xa5'*2*gap+payload)


def bitfield_bitmap(width,height,words,*,bpp=16,dib=40,masks=(0xf800,0x7e0,0x1f,0),compression=3,top=False,gap=0):
    size=bpp//8;stride=(width*size+3)&~3;payload=bytearray()
    for y in (range(height) if top else reversed(range(height))):
        for value in words[y*width:(y+1)*width]:payload.extend(value.to_bytes(size,'little'))
        payload.extend(b'\xee'*(stride-width*size))
    extra=12 if dib in (40,56) and compression==3 else 0;end=14+dib+extra
    header=struct.pack('<2sIHHI',b'BM',end+2*gap+len(payload),0,0,end+gap)
    header+=struct.pack('<IiiHHIIIIII',dib,width,-height if top else height,1,bpp,compression,len(payload),0,0,0,0)
    if dib==56:header+=struct.pack('<IIII',*[0xffffffff]*4)
    elif dib in (108,124):
        header+=struct.pack('<IIII',*masks)+bytes(52)
        if dib==124:header+=struct.pack('<IIII',4,0xffffffff,0xffffff00,17)
    if extra:header+=struct.pack('<III',*masks[:3])
    return list(header+b'\xa5'*2*gap+payload)


def indexed_bitmap(width,height,indices,palette,*,bpp=4,dib=40,top=False,gap=0,colors_used=0):
    row=(width*bpp+7)//8;stride=(row+3)&~3;payload=bytearray()
    for y in (range(height) if top else reversed(range(height))):
        packed=bytearray([255]*row)
        for x,index in enumerate(indices[y*width:(y+1)*width]):
            shift=8-bpp-(x%(8//bpp))*bpp;at=x*bpp//8;mask=((1<<bpp)-1)<<shift
            packed[at]=(packed[at]&~mask)|(index<<shift)
        payload.extend(packed);payload.extend(b'\xee'*(stride-row))
    offset=14+dib+4*len(palette)+gap
    header=struct.pack('<2sIHHI',b'BM',offset+len(payload),0,0,offset)
    header+=struct.pack('<IiiHHIIIIII',dib,width,-height if top else height,1,bpp,0,len(payload),0,0,colors_used,0)
    header+=bytes(dib-40)
    colors=bytearray()
    for pixel in palette:
        r,g,b,a=pixel.to_bytes(4,'big');colors.extend((b,g,r,a))
    return list(header+colors+b'\xa5'*gap+payload)


def core_bitmap(width,height,pixels,*,gap=0):
    stride=(width*3+3)&~3;payload=bytearray()
    for y in reversed(range(height)):
        for pixel in pixels[y*width:(y+1)*width]:
            r,g,b,_=pixel.to_bytes(4,'big');payload.extend((b,g,r))
        payload.extend(b'\xee'*(stride-width*3))
    header=struct.pack('<2sIHHI',b'BM',26+2*gap+len(payload),0,0,26+gap)
    return list(header+struct.pack('<IHHHH',12,width,height,1,24)+b'\xa5'*2*gap+payload)


def core_indexed_bitmap(width,height,indices,palette,*,bpp=4,remainder=0):
    packed=bytes(indexed_bitmap(width,height,indices,palette,bpp=bpp))
    payload=packed[struct.unpack_from('<I',packed,10)[0]:]
    offset=38+3*len(palette)+remainder
    header=struct.pack('<2sIHHI',b'BM',offset+len(payload),0,0,offset)
    header+=struct.pack('<IHHHH',12,width,height,1,bpp)
    colors=bytearray()
    for pixel in palette:
        r,g,b,_=pixel.to_bytes(4,'big');colors.extend((b,g,r))
    return list(header+colors+b'\xa5'*(12+remainder)+payload)


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
    for bpp in (1,4,8):
        palette=[((i*53+17)&255)<<24|((i*73+31)&255)<<16|((i*97+43)&255)<<8|(i*101&255) for i in range(1<<bpp)]
        for dib in (40,108):
            for top in (False,True):
                width={1:9 if top else 7,4:3 if top else 2,8:4 if top else 3}[bpp]
                indices=[len(palette)-1 if i%3==0 else (i*7)%len(palette) for i in range(width*2)]
                inputs.append(dict(id=f'indexed-{bpp}-{dib}-{top}',bytes=indexed_bitmap(width,2,indices,palette,bpp=bpp,dib=dib,top=top,gap=3 if top else 0,colors_used=1)))
    inputs += [dict(id='indexed-reduced-palette',bytes=indexed_bitmap(3,2,[0,1,2,2,1,0],[0x01020300,0x10203080,0xaabbcc01],gap=2,colors_used=1)),
               dict(id='indexed-wide',bytes=indexed_bitmap(4096,1,[i%2 for i in range(4096)],[0x01020300,0xaabbcc00],bpp=1))]
    words=[(high<<15)|(i<<10)|(((i*5)&31)<<5)|(31-i) for high in (0,1) for i in range(32)]
    for dib in (40,108):
        for top in (False,True):inputs.append(dict(id=f'rgb555-{dib}-{top}',bytes=bitmap16(32,2,words,dib=dib,top=top)))
    inputs.append(dict(id='rgb555-odd-gap',bytes=bitmap16(3,2,[0,0xffff,0x1000,0x9000,0x1234,0x5678],gap=4)))
    layouts=[('rgb565',16,(0xf800,0x7e0,0x1f,0)),
             ('argb1555',16,(0x7c00,0x3e0,0x1f,0x8000)),
             ('rgba4444',16,(0xf000,0xf00,0xf0,0xf)),
             ('widths1234',16,(1,6,0x38,0x3c0)),
             ('widths5678',32,(0x1f,0x7e0,0x3f800,0x3fc0000)),
             ('reordered8888',32,(0xff,0xff00,0xff0000,0xff000000)),
             ('noncontiguous',16,(5,10,0x50,0xa000)),
             ('overlap',32,(0xff,0xf0,0xff00,0xf)),
             ('high-bits',32,(0x80000000,0x60000000,0x1c000000,0x3c00000))]
    for name,bpp,masks in layouts:
        limit=(1<<bpp)-1
        words=[0,limit,1,*[mask&limit for mask in masks],0x1000]+[(i*0x9e3779b9)&limit for i in range(56)]
        for dib in (40,108):
            inputs.append(dict(id=f'bitfields-{name}-{dib}',bytes=bitfield_bitmap(8,8,words,bpp=bpp,dib=dib,masks=masks,top=dib==108)))
    for name,alpha,words in [('mixed',0x8000,[0x1000,0x9000,0xffff]),('zero',0x8000,[0x1000,0x1234,0]),('above-word',0xff000000,[0x1000,0x9000,0xffff])]:
        inputs.append(dict(id=f'v4-rgb16-alpha-{name}',bytes=bitfield_bitmap(3,1,words,dib=108,masks=(0x123,0x456,0x789,alpha),compression=0)))
    inputs += [dict(id='v4-equal-masks',bytes=bitfield_bitmap(3,1,[0,31,17],dib=108,masks=(31,31,31,0))),
               dict(id='info-bitfields-odd-gap',bytes=bitfield_bitmap(3,2,[0,0xffff,0x400,0x2404,0x1234,0x5678],gap=4))]
    profiles=[('rgb24',24,0,[0,0xffffff,0x102030,0x010203,0xfedcba,0x13579b],(0,0,0,0)),
              ('rgb32-zero',32,0,[0,0xffffff,0x102030,0x010203,0xfedcba,0x13579b],(0,0,0,0)),
              ('rgb32-mixed',32,0,[0,0xffffffff,0x80102030,0x010203,0x7ffedcba,0x0113579b],(0,0,0,0)),
              ('rgb16-alpha',16,0,[0x1000,0x9000,0x123,0xffff,0,0x7fff],(0x123,0x456,0x789,0x8000)),
              ('bitfields16',16,3,[0,0xffff,0x400,0x2404,0x1234,0x5678],(0xf800,0x7e0,0x1f,0)),
              ('bitfields32',32,3,[0,0xffffffff,0x80102030,0x010203,0x7ffedcba,0x0113579b],(0xff,0xff00,0xff0000,0xff000000))]
    for dib in (56,124):
        for name,bpp,compression,words,masks in profiles:
            inputs.append(dict(id=f'extended-{dib}-{name}',bytes=bitfield_bitmap(3,2,words,bpp=bpp,dib=dib,masks=masks,compression=compression,top=dib==124,gap=3)))
        inputs.append(dict(id=f'extended-{dib}-indexed',bytes=indexed_bitmap(3,2,[0,1,2,2,1,0],[0x01020300,0x10203080,0xaabbcc01],dib=dib,gap=2,colors_used=1)))
    for width in range(1,5):
        pixels=[((i*53+17)&255)<<24|((i*73+31)&255)<<16|((i*97+43)&255)<<8|(i*101&255) for i in range(width*2)]
        inputs.append(dict(id=f'core24-{width}',bytes=core_bitmap(width,2,pixels)))
    inputs += [dict(id='core24-small',bytes=core_bitmap(1,1,[0x12345600])),
               dict(id='core24-wide',bytes=core_bitmap(4096,1,[(i*65793&0xffffff)<<8 for i in range(4096)])),
               dict(id='core24-maximum-gap',bytes=core_bitmap(1,1,[0x12345678],gap=1024))]
    for bpp in (1,4,8):
        palette=[((i*53+17)&255)<<24|((i*73+31)&255)<<16|((i*97+43)&255)<<8|(i*101&255) for i in range(1<<bpp)]
        width=9 if bpp==1 else 3
        indices=[len(palette)-1 if i%3==0 else (i*7)%len(palette) for i in range(width*2)]
        for remainder in range(3):
            inputs.append(dict(id=f'core-indexed-{bpp}-{remainder}',bytes=core_indexed_bitmap(width,2,indices,palette,bpp=bpp,remainder=remainder)))
    inputs += [dict(id='core-indexed-reduced',bytes=core_indexed_bitmap(3,2,[0,1,2,2,1,0],[0x01020300,0x10203080,0xaabbcc01],remainder=1)),
               dict(id='core-indexed-minimum',bytes=core_indexed_bitmap(1,1,[0],[0x12345678],bpp=8))]
    base = bitmap(1,1,[0x12345678])
    malformed = [dict(id='empty',bytes=[],error=0),dict(id='bad-byte',bytes=[256],error=1),
                 dict(id='short-header',bytes=base[:53],error=0),dict(id='short-padding',bytes=base[:-1],error=3)]
    for name,offset,fmt,value,error in [('signature',0,'H',0,0),('dib',14,'I',16,0),('planes',26,'H',2,0),
                                      ('bpp',28,'H',17,0),('compression',30,'I',1,0),('offset-before-header',10,'I',53,0),
                                      ('offset-too-far',10,'I',1079,0),('width-zero',18,'I',0,2),
                                      ('width-large',18,'I',4097,2),('height-min',22,'I',0x80000000,2)]:
        changed=bytearray(base);struct.pack_into('<'+fmt,changed,offset,value)
        malformed.append(dict(id=name,bytes=list(changed),error=error))
    masked = bitmap(1,1,[0x12345678],bpp=32,dib=108,compression=3)
    masked[54] = 1
    malformed += [dict(id='unsupported-mask',bytes=masked,error=0),
                  dict(id='truncated-v4',bytes=masked[:121],error=0),
                  dict(id='gap-truncated',bytes=bitmap(1,1,[0x12345678],gap=4)[:-4],error=3)]
    indexed=indexed_bitmap(1,1,[0],[0x01020300])
    no_palette=bytearray(indexed);struct.pack_into('<I',no_palette,10,54)
    malformed += [dict(id='indexed-empty-palette',bytes=list(no_palette),error=0),
                  dict(id='indexed-large-palette',bytes=indexed_bitmap(1,1,[0],[0]*257,bpp=8),error=0),
                  dict(id='indexed-truncated-palette',bytes=indexed[:57],error=3),
                  dict(id='indexed-short-padding',bytes=indexed[:-1],error=3),
                  dict(id='indexed-invalid-index',bytes=indexed_bitmap(1,1,[1],[0x01020300]),error=4)]
    packed=bitmap16(1,1,[0x1000])
    malformed += [dict(id='rgb555-short-pixel',bytes=packed[:55],error=3),
                  dict(id='rgb555-short-padding',bytes=packed[:-1],error=3),
                  dict(id='rgb555-alpha-width',bytes=bitmap16(1,1,[0x1000],dib=108,alpha_mask=0x1ff),error=0)]
    info=bitfield_bitmap(1,1,[0x400]);inside=bytearray(info);struct.pack_into('<I',inside,10,65)
    malformed += [dict(id='info-incomplete-masks',bytes=info[:65],error=0),
                  dict(id='info-offset-inside-masks',bytes=list(inside),error=0),
                  dict(id='info-equal-masks',bytes=bitfield_bitmap(1,1,[31],masks=(31,31,31,0)),error=0),
                  dict(id='bitfield-missing-rgb',bytes=bitfield_bitmap(1,1,[0],masks=(0,0x7e0,0x1f,0)),error=0)]
    info56=bitfield_bitmap(1,1,[0x400],dib=56);inside56=bytearray(info56);struct.pack_into('<I',inside56,10,81)
    malformed += [dict(id='info56-short-prefix',bytes=info56[:69],error=0),
                  dict(id='info56-short-masks',bytes=info56[:81],error=0),
                  dict(id='info56-offset-inside-masks',bytes=list(inside56),error=0),
                  dict(id='v5-short-profile',bytes=bitfield_bitmap(1,1,[0x400],dib=124)[:137],error=0)]
    core=core_bitmap(1,1,[0x12345678])
    malformed += [dict(id='core-short-header',bytes=core[:25],error=0),dict(id='core-short-padding',bytes=core[:-1],error=3)]
    for name,offset,fmt,value,error in [('planes',22,'H',2,0),('depth',24,'H',16,0),('zero-width',18,'H',0,2),
                                      ('large-width',18,'H',65535,2),('offset-before-header',10,'I',25,0),('offset-too-far',10,'I',1051,0)]:
        changed=bytearray(core);struct.pack_into('<'+fmt,changed,offset,value)
        malformed.append(dict(id='core-'+name,bytes=list(changed),error=error))
    core_indexed=core_indexed_bitmap(1,1,[0],[0x12345678],bpp=8)
    malformed += [dict(id='core-indexed-empty',bytes=core_indexed_bitmap(1,1,[0],[],bpp=8),error=0),
                  dict(id='core-indexed-large',bytes=core_indexed_bitmap(1,1,[0],[0]*257,bpp=8),error=0),
                  dict(id='core-indexed-short-palette',bytes=core_indexed[:28],error=3),
                  dict(id='core-indexed-short-padding',bytes=core_indexed[:-1],error=3),
                  dict(id='core-indexed-invalid-index',bytes=core_indexed_bitmap(1,1,[1],[0x12345678],bpp=8),error=4)]
    outputs = [dict(id='rgba-mixed',width=3,height=2,pixels=[v | (i*51) for i,v in enumerate(rgba)]),
               dict(id='rgba-zero-alpha',width=2,height=2,pixels=rgba[:4]),
               dict(id='rgba-single',width=1,height=1,pixels=[0xffffffff])]
    return inputs,malformed,outputs


def bend_bytes(values):
    if len(values)<=256:
        return '['+','.join(map(str,values))+']'
    chunks=','.join('['+','.join(map(str,values[start:start+64]))+']' for start in range(0,len(values),64))
    return f'input_bytes([{chunks}], Nil{{}})'


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
'''


def reference_program(codec, extension, inputs, outputs, work):
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'static void emit(Image image){if(!image.data){fputs("valid BMP rejected\\n",stderr);exit(2);} ImageFormat(&image,7);',
           'printf("{\\"width\\":%d,\\"height\\":%d,\\"pixels\\":[",image.width,image.height);',
           'Color *pixels=LoadImageColors(image);for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(pixels[i]));',
           'puts("]}");UnloadImageColors(pixels);UnloadImage(image);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in inputs:
        lines += ['{unsigned char bytes[]={'+','.join(map(str,case['bytes']))+'};emit(LoadImageFromMemory(".'+extension+'",bytes,sizeof(bytes)));}']
    for case in outputs:
        path=work/f'reference-{case["id"]}.{codec}'
        lines += ['{',f'Image image=GenImageColor({case["width"]},{case["height"]},BLANK);',
                  'unsigned pixels[]={'+','.join(str(v)+'u' for v in case['pixels'])+'};',
                  f'for(int i=0;i<{len(case["pixels"])};i++)((Color*)image.data)[i]=GetColor(pixels[i]);',
                  f'if(!ExportImage(image,{json.dumps(str(path))}))return 3;UnloadImage(image);',
                  f'int size=0;unsigned char *bytes=LoadFileData({json.dumps(str(path))},&size);',
                  'if(!bytes)return 4;putchar(\'[\');for(int i=0;i<size;i++)printf("%s%u",i?",":"",bytes[i]);puts("]");UnloadFileData(bytes);','}']
    return '\n'.join(lines+['}'])+'\n'


def main(codec='bmp', fixture_factory=fixtures, native_extension=None):
    probe=probekit.Probe(codec,probekit.arguments(f'Compare {codec.upper()} decoding and RGBA8 export with raylib.'))
    work=probe.work;inputs,malformed,outputs=fixture_factory()
    reference=probe.native(reference_program(codec,native_extension or codec,inputs,outputs,work))
    expected=[json.loads(line) for line in reference.splitlines()]
    if len(expected)!=len(inputs)+len(outputs):raise ProbeFailure(f'Incomplete native {codec.upper()} results')
    # The candidate also writes the 1x1 export to a file; its bytes must equal the native file.
    single,written=work/f'reference-rgba-single.{codec}',work/f'candidate-single.{codec}'
    expected=expected[:len(inputs)]+[c['error'] for c in malformed]+expected[len(inputs):]+([list(single.read_bytes())] if outputs else [])
    actions=[('decode',c) for c in inputs]+[('error',c) for c in malformed]+[('export',c) for c in outputs]+([('file',dict(id='rgba-single'))] if outputs else [])
    program=PROGRAM.replace('OUTPUT',json.dumps(str(written))).replace('BMP',codec.upper()).replace('Surface.to_bmp',f'Surface.to_{codec}').replace('Surface.write_bmp',f'Surface.write_{codec}')
    if not outputs:program=program[:program.index('def fill(')]+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    function=f'decode_{codec}_for' if codec=='psd' else f'decode_{codec}'
    profile=f'M.{image_decode_reference()}{{}}, ' if codec=='psd' else ''

    def render(selected,gpu):
        bang='!' if gpu else '';body=program
        for kind,case in selected:
            if kind=='decode':body+=f'    decoded(J.Surface.{function}{bang}({profile}{bend_bytes(case["bytes"])}))\n'
            elif kind=='error':body+=f'    IO.print(U32.show(error_code(J.Surface.{function}{bang}({profile}{bend_bytes(case["bytes"])}))))\n'
            elif kind=='export':body+=f'    IO.print(List.show(~&2, ~U32, ~U32.show, encoded{bang}({case["width"]}, {bend_bytes(case["pixels"])}, J.Surface.create({case["width"]}, {case["height"]}, 0))))\n'
            else:body+='    saved(J.Surface.create(1, 1, 4294967295))\n    IO.print("\\"file\\"")\n'
        return body

    def parse(text,selected):
        rows=[json.loads(line) for line in text.splitlines()]
        for i,row in enumerate(rows):
            if row=='file':  # Swap the marker for the written bytes; remove the file so each lane rewrites it.
                rows[i]=list(written.read_bytes()) if written.is_file() else None;written.unlink(missing_ok=True)
        return rows

    written.unlink(missing_ok=True)
    probe.compare(expected,probe.candidates(render,actions,batch=len(actions),parse=parse),lambda i:f'{actions[i][0]} {actions[i][1]["id"]}')
    summary=dict(decode_cases=len(inputs),error_cases=len(malformed),export_cases=len(outputs),
                 decoded_pixels=sum(len(row['pixels']) for row in expected[:len(inputs)]),
                 export_bytes=sum(map(len,expected[len(inputs)+len(malformed):len(inputs)+len(malformed)+len(outputs)])),
                 inputs_sha256=hashlib.sha256(json.dumps([inputs,malformed,outputs]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(reference.encode()).hexdigest())
    if codec=='psd':summary['decode_reference']=image_decode_reference()
    probe.finish(**summary)


if __name__=='__main__':
    main()
