#!/usr/bin/env python3
"""Exact original-format BMP memory decoding against pinned raylib (BMP enabled).

Accepted fixtures are admitted by an independent header parse before any native
call; checked-invalid controls only exercise Jonlib's typed errors. Shared roles
and lanes: tools/codec_formats.py.
"""
import json
import re
import struct

from bmp_probe import (fixtures as legacy_fixtures, bitmap, bitmap16, bitfield_bitmap,
                       indexed_bitmap, core_bitmap, core_indexed_bitmap)
import codec_formats

MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
C_PREFIX = codec_formats.C_PREFIX


def inspect_header(data, *, fixture_budget=True):
    """Independent native safety admission; it does not decode output pixels.

    Re-parse every byte, supported header, effective mask, palette index, row
    and double skip before invoking native code. The finite fixture budget is
    deliberately separate from the larger checked API's 1..4096 dimensions.
    Metadata channels derive from the effective alpha MASK, not opacity/bpp.
    """
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):raise ValueError('Unsafe native byte domain')
    if len(data)<18 or data[:2]!=[66,77]:raise ValueError('Incomplete/invalid native BMP prefix')
    if len(data)>2147483647:raise ValueError('Native encoded length exceeds signed int')
    raw=bytes(data);offset,dib=struct.unpack_from('<II',raw,10)
    if dib not in (12,40,56,108,124):raise ValueError('Unsafe native DIB header')
    if len(data)<14+dib:raise ValueError('Incomplete native DIB header')
    if dib==12:
        w,h,planes,bits=struct.unpack_from('<HHHH',raw,18);compression=0;top=False
        if planes!=1 or bits not in (1,4,8,24):raise ValueError('Unsafe native CORE profile')
    else:
        w,signed_height,planes,bits,compression=struct.unpack_from('<IiHHI',raw,18)
        h=abs(signed_height);top=signed_height<0
        if planes!=1 or bits not in (1,4,8,16,24,32) or compression not in (0,3) or (compression==3 and bits not in (16,32)):raise ValueError('Unsafe native INFO profile')
    end=14+dib+(12 if dib in (40,56) and compression==3 else 0)
    if len(data)<end:raise ValueError('Incomplete native external masks')
    indexed=bits<16;gap=offset-end
    if indexed:
        entry=3 if dib==12 else 4;bias=12 if dib==12 else 0
        count=(gap-bias)//entry
        if not 1<=count<=256 or gap<bias+entry or gap>bias+entry*256+entry-1:raise ValueError('Unsafe native palette count/offset')
        palette_end=end+count*entry;skip=offset-palette_end
        if palette_end>len(data) or skip<0:raise ValueError('Incomplete native palette')
        payload=offset
    else:
        entry=count=skip=0
        if not 0<=gap<=1024:raise ValueError('Unsafe native true-color offset')
        payload=end+2*gap
    if not 1<=w<=4096 or not 1<=h<=4096:raise ValueError('Unsafe native dimensions')
    if fixture_budget and w*h>MAX_CASE_PIXELS:raise ValueError('Native fixture pixel budget exceeded')
    masks=[0,0,0,0]
    if dib in (108,124):masks=list(struct.unpack_from('<IIII',raw,54))
    if compression==3 and dib in (40,56):
        masks=list(struct.unpack_from('<III',raw,14+dib))+[0]
        if masks[0]==masks[1]==masks[2]:raise ValueError('Unsafe native identical INFO masks')
    if compression==0:
        if bits==16:masks=[0x7c00,0x3e0,0x1f,masks[3]]
        elif bits==32:masks=[0xff0000,0xff00,0xff,0xff000000]
        else:masks=[0,0,0,0]
    if bits in (16,32):
        if any(not m or m.bit_count()>8 for m in masks[:3]) or masks[3].bit_count()>8:raise ValueError('Unsafe native channel masks')
    # Native's bpp24/ma==ff000000 special case cannot be reached by this
    # checked domain: BI_RGB24 resets masks and BI_BITFIELDS24 is rejected.
    channels=4 if masks[3] else 3
    row=(w*bits+7)//8;stride=(row+3)&~3;raster=stride*h
    if payload+raster>len(data):raise ValueError('Incomplete native raster/padding/double skip')
    if indexed:
        for y in range(h):
            for x in range(w):
                value=data[payload+y*stride+x*bits//8]
                index=(value>>(8-bits-(x%(8//bits))*bits))&((1<<bits)-1)
                if index>=count:raise ValueError('Unsafe native undefined palette index')
    return dict(width=w,height=h,channels=channels,dib=dib,bits=bits,compression=compression,top=top,offset=offset,
                header_bytes=end,payload_offset=payload,row_bytes=row,stride=stride,padding=stride-row,
                palette_count=count,palette_entry_bytes=entry,palette_skip=skip,gap=gap,effective_masks=masks,
                repair_zero_alpha=bits==32 and compression==0,raster_bytes=raster,tail_bytes=len(data)-payload-raster)


def validate_cases(cases):
    if type(cases) is not list or not cases:raise ValueError('Empty native BMP cases')
    ids=set();total=0
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','width','height','channels','extended'}:raise ValueError('Native case schema differs')
        name=case['id']
        if type(name) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',name) is None or name in ids:raise ValueError('Invalid/duplicate native fixture ID')
        ids.add(name)
        if type(case['extended']) is not bool:raise ValueError('Invalid alias selector')
        observed=inspect_header(case['bytes'])
        if any(type(case[k]) is not int or case[k]!=observed[k] for k in ('width','height','channels')):raise ValueError('Native declared metadata/header differs')
        total+=len(case['bytes'])
    if total>MAX_TOTAL_BYTES:raise ValueError('Unsafe native aggregate fixture size')


def fixtures():
    result=[]
    def add(name,data,extended=False):
        data=list(data);header=inspect_header(data)
        result.append(dict(id=name,bytes=data,width=header['width'],height=header['height'],channels=header['channels'],extended=extended))
    # Historical encoded inputs are copied byte-for-byte; no reconstructed pixel
    # expectations are inherited from the older normalized-only probe.
    for case in legacy_fixtures()[0]:add('legacy-'+case['id'],case['bytes'])
    for channels in (3,4):
        for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63)]:
            pixels=[sum(((i*61+j*79+(i//w)*17+13)&255)<<(24-8*j) for j in range(4)) for i in range(w*h)]
            add(f'c{channels}-{name}',bitmap(w,h,pixels,bpp=channels*8,top=True),extended=name in ('single','padded'))
        for name in ('ramp','alpha-ramp'):
            pixels=[sum(((i+j*71)&255 if name=='ramp' else (i if j==3 else 37+j*53))<<(24-8*j) for j in range(4)) for i in range(256)]
            add(f'c{channels}-{name}',bitmap(16,16,pixels,bpp=channels*8,top=name=='ramp'),extended=True)
    for dib in (40,56,108,124):
        for name,alpha in [('zero',0),('opaque',255),('mixed',None)]:
            words=[((i*39071+0x123456)&0xffffff)|((i*17 if alpha is None else alpha)<<24) for i in range(15)]
            add(f'rgb32-{dib}-alpha-{name}',bitfield_bitmap(3,5,words,bpp=32,dib=dib,compression=0,masks=(0,0,0,0),top=name=='mixed'),extended=True)
        for bits in (16,32):
            limit=(1<<bits)-1;words=[(i*0x9e3779b9)&limit for i in range(15)]
            for alpha in (0,0x8000,0xff000000):
                add(f'bitfields-{dib}-{bits}-alpha-{alpha}',bitfield_bitmap(3,5,words,bpp=bits,dib=dib,masks=(0x7c00,0x3e0,0x1f,alpha),top=bool(alpha)),extended=True)
        # Stored masks in RGB24 and the 56-byte embedded prefix are ignored.
        words=[0x123456,0xabcdef,0x070b13,0x192b3f,0x456789,0xcdefff]
        data=bitfield_bitmap(3,2,words,bpp=24,dib=dib,compression=0,masks=(0xffffffff,0xffffffff,0xffffffff,0xff000000),gap=3)
        add(f'ignored-rgb24-masks-{dib}',data,extended=True)
    for dib in (108,124):
        for name,alpha,words in [('absent',0,[0,0x7fff,0x1234]),('zero',0x8000,[0,0x1234,0x7fff]),('opaque',0x8000,[0x8000,0x9234,0xffff]),('mixed',0x8000,[0,0x9234,0x7fff]),('above-word',0xff000000,[0,0x9234,0xffff])]:
            add(f'rgb16-{dib}-alpha-{name}',bitfield_bitmap(3,1,words,dib=dib,compression=0,masks=(0xffffffff,0xffffffff,0xffffffff,alpha)),extended=True)
        for name,words in [('zero',[0x010203,0x112233,0xabcdef]),('opaque',[0xff010203,0xff112233,0xffabcdef])]:
            add(f'explicit32-{dib}-alpha-{name}',bitfield_bitmap(3,1,words,bpp=32,dib=dib,masks=(0xff0000,0xff00,0xff,0xff000000)),extended=True)
    for dib in (40,56,108,124):
        for bits in (1,4,8):
            palette=[0x01020300,0x719bc1ff] if bits==1 else [0x01020300,0x719bc180,0xe7f1fbff]
            for remainder in range(4):
                indices=[i%len(palette) for i in range(15)]
                add(f'palette-{dib}-{bits}-remainder-{remainder}',indexed_bitmap(3,5,indices,palette,bpp=bits,dib=dib,top=bool(remainder&1),gap=remainder,colors_used=0xffffffff),extended=remainder==3)
    for bits in (1,4,8):
        for remainder in range(3):
            add(f'core-palette-{bits}-remainder-{remainder}',core_indexed_bitmap(3,5,[i%2 for i in range(15)],[0x01020300,0xfbd591ff],bpp=bits,remainder=remainder),extended=remainder==2)
    # Mutate every native-ignored metadata category while preserving the raster.
    data=bitfield_bitmap(3,2,[0x12345678+i*0x10203 for i in range(6)],bpp=32,dib=124,compression=0,gap=5,top=True)
    for start,end in ((2,10),(34,54),(70,138)):
        data[start:end]=[(i*37+19)&255 for i in range(start,end)]
    data+=list(b'BMP ignored complete trailer\0')
    add('ignored-metadata-gap-tail',data,extended=True)
    validate_cases(result);return result


def validate_controls(cases):
    if type(cases) is not list:raise ValueError('Invalid checked BMP controls')
    ids=set()
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','error'}:raise ValueError('Checked control schema differs')
        if type(case['id']) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',case['id']) is None or case['id'] in ids:raise ValueError('Invalid/duplicate control ID')
        ids.add(case['id'])
        if type(case['error']) is not int or case['error'] not in range(5):raise ValueError('Invalid checked error')
        if type(case['bytes']) is not list or any(type(v) is not int or not 0<=v<=4294967295 for v in case['bytes']):raise ValueError('Invalid checked byte domain')
        # Fixture resource limits cannot turn a valid API input into an error
        # control. Only actual checked-domain structural rejection qualifies.
        try:inspect_header(case['bytes'],fixture_budget=False)
        except ValueError:pass
        else:raise ValueError('Accepted native input mislabeled as control')


def controls():
    result=[dict(c,id='legacy-'+c['id']) for c in legacy_fixtures()[1]]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    def changed(data,at,fmt,value):
        result=bytearray(data);struct.pack_into('<'+fmt,result,at,value);return list(result)
    base=bitmap(1,1,[0x12345678]);v5=bitfield_bitmap(1,1,[0x1234],dib=124)
    # Every byte of the largest header, word payload and padding is covered.
    # Further specimens cover CORE/palettes, 56-byte discarded and external
    # masks, both true-color skips, and ignored complete trailers.
    specimens=[('v5',v5),('core',core_bitmap(1,1,[0x12345678])),
               ('palette',indexed_bitmap(1,1,[0],[0x12345678],gap=3)),
               ('core-palette',core_indexed_bitmap(1,1,[0],[0x12345678],bpp=8,remainder=2)),
               ('info56',bitfield_bitmap(1,1,[0x1234],dib=56,gap=2)+[17])]
    for name,data in specimens:
        for at in range(len(data)):
            values=data.copy();values[at]=256;add(f'invalid-byte-{name}-{at}',values,1)
    for n in range(26):add(f'core-prefix-{n}',core_bitmap(1,1,[0x12345678])[:n],0)
    for dib in (40,56,108,124):
        data=bitfield_bitmap(1,1,[0x1234],dib=dib)
        end=14+dib+(12 if dib in (40,56) else 0)
        for n in sorted({26,53,14+dib-1,end-1}):add(f'dib-{dib}-prefix-{n}',data[:n],0)
        for n in range(4):add(f'dib-{dib}-short-raster-{n}',data[:end+n],3)
    for axis,at in (('width',18),('height',22)):
        for value in (0,4097,0x7fffffff,0x80000000,0xffffffff):
            if axis=='height' and value==0xffffffff:continue  # -1 is accepted.
            add(f'{axis}-{value}',changed(base,at,'I',value),2)
    for name,at,fmt,values in [('planes',26,'H',(0,2,65535)),('dib',14,'I',(0,13,39,41,55,57,107,109,123,125,0xffffffff)),('depth',28,'H',(0,2,15,17,23,25,31,33,65535)),('compression',30,'I',(1,2,3,4,5,6,0xffffffff)),('offset',10,'I',(0,53,1079,0x7fffffff,0x80000000,0xffffffff))]:
        for value in values:add(f'{name}-{value}',changed(base,at,fmt,value),0)
    for dib in (40,56,108,124):
        for bits in (16,32):
            for channel in range(4 if dib in (108,124) else 3):
                for value in ((0,0x1ff) if channel<3 else (0x1ff,)):
                    masks=[0x7c00,0x3e0,0x1f,0x8000];masks[channel]=value
                    add(f'mask-{dib}-{bits}-{channel}-{value}',bitfield_bitmap(1,1,[0x1234],bpp=bits,dib=dib,masks=tuple(masks)),0)
    for bits in (1,4,8):
        for dib in (40,56,108,124):
            data=indexed_bitmap(1,1,[1],[0x12345678],bpp=bits,dib=dib)
            add(f'index-undefined-{dib}-{bits}',data,4)
        add(f'core-index-undefined-{bits}',core_indexed_bitmap(1,1,[1],[0x12345678],bpp=bits),4)
    # Typed precedence belongs to the checked APIs; controls never run native.
    add('bad-byte-before-header',[0,4294967295],1)
    add('bad-byte-before-size',changed(base,18,'I',0)+[256],1)
    add('bad-byte-before-padding',base[:-1]+[256],1)
    add('bad-header-before-size',changed(changed(base,18,'I',0),26,'H',0),0)
    add('bad-offset-before-size',changed(changed(base,18,'I',0),10,'I',53),0)
    add('bad-size-before-truncated',changed(base,18,'I',0)[:54],2)
    add('bad-size-before-incomplete-masks',changed(v5,18,'I',0)[:54],2)
    add('bad-size-before-invalid-mask',changed(changed(v5,18,'I',0),54,'I',0),2)
    data=indexed_bitmap(1,1,[1],[0x12345678])
    add('truncated-before-invalid-index',data[:-1],3)
    validate_controls(result);return result


def qualification_program():
    # Deliberately tiny fixed vectors qualify native routing. This is not a
    # Python decoder: broad expected pixels only come from native raw captures.
    vectors=[('rgb24',bitmap(1,1,[0x01020380]),4,[1,2,3]),
             ('rgb32-repaired',bitmap(1,1,[0x01020300],bpp=32),7,[1,2,3,255]),
             ('rgb32-alpha',bitmap(1,1,[0x01020380],bpp=32),7,[1,2,3,128]),
             ('info16-rgb565',bitfield_bitmap(1,1,[0xf800]),4,[255,0,0]),
             ('rgb555-bit-replication',bitmap16(1,1,[4]),4,[0,0,33]),
             ('info32-ignored-alpha',bitfield_bitmap(1,1,[0x80112233],bpp=32,masks=(0xff0000,0xff00,0xff,0xff000000)),4,[17,34,51]),
             ('info56-ignored-alpha',bitfield_bitmap(1,1,[0x80112233],bpp=32,dib=56,masks=(0xff0000,0xff00,0xff,0xff000000)),4,[17,34,51]),
             ('v4-explicit-zero-alpha',bitfield_bitmap(1,1,[0x00112233],bpp=32,dib=108,masks=(0xff0000,0xff00,0xff,0xff000000)),7,[17,34,51,0]),
             ('v5-rgb32-repaired',bitfield_bitmap(1,1,[0x00112233],bpp=32,dib=124,compression=0),7,[17,34,51,255]),
             ('v4-rgb16-alpha',bitfield_bitmap(1,1,[0x001f],dib=108,compression=0,masks=(0,0,0,0x8000)),7,[0,0,255,0]),
             ('v5-rgb16-above-word-alpha',bitfield_bitmap(1,1,[0x001f],dib=124,compression=0,masks=(0,0,0,0xff000000)),7,[0,0,255,0]),
             ('palette-reserved-ignored',indexed_bitmap(1,1,[0],[0x01020300]),4,[1,2,3])]
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for name,data,fmt,expected in vectors:
        inspect_header(data)
        lines+=['/* '+name+' */ {const unsigned char data[]={'+','.join(map(str,data))+'};',
                'Image image=LoadImageFromMemory(".bmp",data,sizeof(data));if(!image.data)return 11;',
                f'if(image.width!=1||image.height!=1||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(1,1,image.format)!={len(expected)}){{UnloadImage(image);return 12;}}',
                'const unsigned char *p=image.data;if('+ '||'.join(f'p[{i}]!={v}' for i,v in enumerate(expected))+'){UnloadImage(image);return 13;}UnloadImage(image);}' ]
    row=json.dumps(dict(little_endian=True,bmp_enabled=True,effective_alpha_routing=True,formats=[4,7]),separators=(',',':'))
    return '\n'.join(lines+['puts('+json.dumps(row)+');return 0;}'])+'\n'



QUALIFIED = dict(little_endian=True, bmp_enabled=True, effective_alpha_routing=True, formats=[4, 7])

CODEC = codec_formats.Codec(
    name='bmp', token='.bmp', aliases=('.BMP',), contraction_token='.BMP', formats={3: 4, 4: 7},
    fixtures=fixtures, controls=controls, roles=('raw', 'bridge', 'surface', 'factory', 'owner', 'raw-roundtrip'),
    raylib_options=('SUPPORT_FILEFORMAT_BMP=ON',), batch=32, qualification=(qualification_program(), QUALIFIED),
    describe=__doc__)


def main(argv=None):
    codec_formats.main(CODEC, argv)


if __name__ == '__main__':
    main()
