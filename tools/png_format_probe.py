#!/usr/bin/env python3
"""Exact original-format PNG memory decoding against pinned raylib.

Only independently admitted complete PNG fixtures reach native code. PNG shares
stb's suffix/content sniffing path: a .png suffix alone proves no PNG identity.
Raw native metadata and every byte are captured before separate normalization.
CPU-1/CPU-2/JavaScript only; no GPU, formatted-file or generic-formatted claim.

Shared roles, native recording and lanes: tools/formatted_codec.py.
"""
import json
import re
import struct
import zlib
from bmp_probe import bend_bytes
from png_probe import (fixtures as legacy_fixtures, png, chunk, SIGNATURE, CHANNELS, PASSES)
import formatted_codec
from probekit import ROOT

BATCH_SIZE = 32
SOURCE_BYTE_LIMIT = 196_608
FORMATS = {1:1, 2:2, 3:4, 4:7}
MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
ENCODED_LIMIT = 1_048_576
FILTERED_LIMIT = 67_108_864
C_PREFIX = formatted_codec.C_PREFIX


def pass_layout(width,height,components,depth,interlace):
    """Independent exact filtered lengths; empty Adam7 passes consume nothing."""
    result=[]
    for x,y,dx,dy in PASSES if interlace else ((0,0,1,1),):
        w=max(0,(width-x+dx-1)//dx);h=max(0,(height-y+dy-1)//dy)
        if w and h:
            row=(w*components*depth+7)//8
            result.append(dict(width=w,height=h,row_bytes=row,filtered_bytes=(row+1)*h))
    return result


def bounded_inflate(stream,raw,expected):
    """Validate native framing while deliberately not validating Adler-32.

    zlib.decompress(stream) would incorrectly reject two preserved native cases:
    missing Adler and wrong Adler. Validate CM/FCHECK/FDICT then feed raw DEFLATE
    to an independent bounded inflater. Stop after expected+1 bytes; no flush()
    or unbounded decompression can allocate a hostile expansion.
    """
    if not raw:
        if len(stream)<2 or stream[0]&15!=8 or (stream[0]*256+stream[1])%31 or stream[1]&32:
            raise ValueError('Unsafe native zlib framing')
        stream=stream[2:]
    try:
        decoder=zlib.decompressobj(-15)
        data=decoder.decompress(stream,expected+1)
    except zlib.error as error:raise ValueError('Unsafe native DEFLATE stream') from error
    if len(data)!=expected or not decoder.eof or decoder.unconsumed_tail:
        raise ValueError('Unsafe native filtered raster length or incomplete DEFLATE')
    return data


def inspect_header(data, *, fixture_budget=True):
    """Independently parse actual bytes before any native invocation.

    No pixel oracle is implemented here. Reconstructed scanline bytes are used
    only to check filter validity and every actual palette index, because stb's
    palette expander ignores its palette-count argument. Native output remains
    the sole broad byte expectation, including transparency and 16-bit narrowing.
    """
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):raise ValueError('Unsafe native byte domain')
    if len(data)>ENCODED_LIMIT:raise ValueError('Unsafe native encoded input size')
    if bytes(data[:8])!=SIGNATURE:raise ValueError('Unsafe native PNG signature')
    values=bytes(data);cursor=8;header=None;palette=0;seen=False;trns=False;raw=False;streams=[];chunks=[]
    while True:
        if cursor+12>len(values):raise ValueError('Incomplete native PNG chunk')
        size=struct.unpack_from('>I',values,cursor)[0];kind=values[cursor+4:cursor+8]
        if size>ENCODED_LIMIT or cursor+12+size>len(values):raise ValueError('Incomplete/oversized native PNG payload')
        payload=values[cursor+8:cursor+8+size];cursor+=12+size;chunks.append(kind.decode('latin1'))
        if kind==b'CgBI':raw=True;continue
        if header is None:
            if kind!=b'IHDR' or size!=13:raise ValueError('Unsafe native first/unique PNG header')
            w,h,depth,color,method,filter_method,interlace=struct.unpack('>IIBBBBB',payload)
            if color not in CHANNELS or depth not in ((1,2,4,8) if color==3 else (1,2,4,8,16) if color==0 else (8,16)) or method or filter_method or interlace not in (0,1):raise ValueError('Unsafe native PNG profile')
            if not 1<=w<=4096 or not 1<=h<=4096:raise ValueError('Unsafe native dimensions')
            if fixture_budget and w*h>MAX_CASE_PIXELS:raise ValueError('Native fixture pixel budget exceeded')
            header=(w,h,depth,color,interlace);continue
        if kind==b'IHDR':raise ValueError('Duplicate native PNG header')
        if kind==b'PLTE':
            if seen or not 0<size<=768 or size%3:raise ValueError('Unsafe native PNG palette')
            palette=size//3
        elif kind==b'tRNS':
            if seen or color not in (0,2,3) or (color==3 and (not palette or size>palette)) or (color!=3 and size!=2*CHANNELS[color]):raise ValueError('Unsafe native PNG transparency')
            trns=True  # Structural and sticky, even empty or followed by PLTE.
        elif kind==b'IDAT':
            if color==3 and not palette:raise ValueError('Missing native PNG palette')
            streams.append(payload);seen=True
        elif kind==b'IEND':
            if size or not seen:raise ValueError('Unsafe native PNG terminator')
            break
        elif not kind[0]&32:raise ValueError('Unknown native critical PNG chunk')
    passes=pass_layout(w,h,CHANNELS[color],depth,interlace)
    expected=sum(p['filtered_bytes'] for p in passes)
    if expected>FILTERED_LIMIT:raise ValueError('Unsafe native filtered capacity')
    raster=bounded_inflate(b''.join(streams),raw,expected)
    at=0;distance=max(1,(CHANNELS[color]*depth+7)//8);maximum_index=None
    for shape in passes:
        stride=shape['row_bytes'];previous=bytearray(stride)
        for _ in range(shape['height']):
            mode=raster[at];at+=1
            if mode>4:raise ValueError('Unsafe native PNG filter')
            row=bytearray(stride)
            for x in range(stride):
                left=row[x-distance] if x>=distance else 0
                up=previous[x];corner=previous[x-distance] if x>=distance else 0
                if mode==0:predict=0
                elif mode==1:predict=left
                elif mode==2:predict=up
                elif mode==3:predict=(left+up)//2
                else:
                    base=left+up-corner;distances=(abs(base-left),abs(base-up),abs(base-corner))
                    predict=(left,up,corner)[distances.index(min(distances))]
                row[x]=(raster[at]+predict)&255;at+=1
            if color==3:
                for x in range(shape['width']):
                    index=(row[x*depth//8]>>(8-depth-(x*depth%8)))&((1<<depth)-1)
                    if index>=palette:raise ValueError('Unsafe native undefined PNG palette index')
                    maximum_index=index if maximum_index is None else max(maximum_index,index)
            previous=row
    if at!=expected:raise ValueError('Incomplete native pass consumption')
    channels=(4 if trns else 3) if color==3 else CHANNELS[color]+int(trns)
    return dict(width=w,height=h,channels=channels,depth=depth,color=color,interlace=interlace,
                palette_count=palette,has_transparency=trns,cgbi=raw,filtered_bytes=expected,
                passes=passes,maximum_index=maximum_index,tail_bytes=len(values)-cursor,chunks=chunks)


def validate_cases(cases):
    if type(cases) is not list or not cases:raise ValueError('Empty native PNG cases')
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
        data=list(data);observed=inspect_header(data)
        result.append(dict(id=name,bytes=data,width=observed['width'],height=observed['height'],channels=observed['channels'],extended=extended))
    for case in legacy_fixtures()[0]:add('legacy-'+case['id'],case['bytes'])
    palette=bytes([17,63,201,71,113,159,227,239,251])
    for name,alpha in [('empty',b''),('opaque',b'\xff\xff\xff'),('unused-transparent',b'\xff\xff\0')]:
        add('palette-trns-'+name,png(2,1,3,b'\0\1',palette=palette,transparency=alpha),True)
    add('palette-trns-repeated',png(3,1,3,b'\0\1\2',palette=palette,transparency=b'\0\x80',extra=[(b'tRNS',b'\xff')]),True)
    for name,alpha in [('empty',b''),('transparent',b'\0\x80')]:
        add('palette-trns-plte-sticky-'+name,png(3,1,3,b'\0\1\2',palette=palette,transparency=alpha,extra=[(b'PLTE',palette[::-1])]),True)
    add('palette-plte-trns-plte-trns',png(3,1,3,b'\0\1\2',palette=palette,transparency=b'\0',extra=[(b'PLTE',palette[::-1]),(b'tRNS',b'\xff\x7f')]),True)
    for color in (0,2):
        channels=CHANNELS[color]
        add('trns-no-match-'+str(color),png(3,1,color,bytes([7,11,13][:channels])*3,transparency=b'\0\x7f'*channels),True)
        samples=[0x1234,0x1235,0x12ff] if color==0 else [0x1234,0x5678,0x9abc,0x1234,0x5678,0x9abd,0x1235,0x5678,0x9abc]
        key=samples[:channels]
        add('trns-full16-'+str(color),png(3,1,color,struct.pack('>'+'H'*len(samples),*samples),depth=16,transparency=struct.pack('>'+'H'*channels,*key)),True)
    for color in (0,4,2,6):
        channels=CHANNELS[color]
        for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63),('byte-ramp',16,16)]:
            raw=bytes((i*61+(i//channels)*17+13)&255 for i in range(w*h*channels))
            add(f'c{channels}-{name}',png(w,h,color,raw,(4,3,2,1,0)),name in ('single','padded','byte-ramp'))
    add('cgbi-default-bgr-premultiplied',png(3,1,6,bytes([3,8,12,16,11,22,33,0,55,30,10,127]),cgbi=True),True)
    base=list(png(1,1,0,b'\x7f'))
    add('encoded-exact-cap',base+[0]*(ENCODED_LIMIT-len(base)),True)
    validate_cases(result);return result


def validate_controls(cases):
    if type(cases) is not list:raise ValueError('Invalid checked PNG controls')
    ids=set()
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','error'}:raise ValueError('Checked control schema differs')
        if type(case['id']) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',case['id']) is None or case['id'] in ids:raise ValueError('Invalid/duplicate control ID')
        ids.add(case['id'])
        if type(case['error']) is not int or case['error'] not in range(5):raise ValueError('Invalid checked error')
        if type(case['bytes']) is not list or any(type(v) is not int or not 0<=v<=4294967295 for v in case['bytes']):raise ValueError('Invalid checked byte domain')
        try:inspect_header(case['bytes'],fixture_budget=False)
        except ValueError:pass
        else:raise ValueError('Accepted native input mislabeled as control')


def controls():
    result=[dict(c,id='legacy-'+c['id']) for c in legacy_fixtures()[1]]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    base=png(1,1,6,b'\1\2\3\4')
    for n in range(len(base)):add('prefix-'+str(n),base[:n],0)
    for n in range(len(base)):
        values=list(base);values[n]=256;add('invalid-byte-'+str(n),values,1)
    for name,data in [('qoi',b'qoif'+bytes(30)),('bmp',b'BM'+bytes(60)),('pnm',b'P6\n1 1\n255\n\1\2\3'),('tga',bytes(30)),('gif',b'GIF89a'+bytes(40))]:add('non-png-'+name,data,0)
    for color,depth,width,height,error in [(6,8,4095,4096,4),(6,8,4096,4096,2),(6,16,2047,4096,4),(6,16,2048,4096,2)]:
        for interlace in (0,1):
            header=struct.pack('>IIBBBBB',width,height,depth,color,0,0,interlace)
            expected=sum(p['filtered_bytes'] for p in pass_layout(width,height,CHANNELS[color],depth,interlace))
            add(f'filtered-boundary-{depth}-{width}-{interlace}',SIGNATURE+chunk(b'IHDR',header)+chunk(b'IDAT',b'bad')+chunk(b'IEND',b''),2 if expected>FILTERED_LIMIT else 4)
    palette=b'\1\2\3'
    for depth in (1,2,4,8):
        for interlace in (False,True):add(f'undefined-index-{depth}-{interlace}',png(9,9,3,bytes([1])*81,depth=depth,interlaced=interlace,palette=palette),4)
    add('bad-byte-before-header',[0,256],1)
    add('bad-byte-before-size',list(SIGNATURE+chunk(b'IHDR',struct.pack('>IIBBBBB',0,1,8,6,0,0,0)))+[256],1)
    add('bad-header-before-size',SIGNATURE+chunk(b'IHDR',struct.pack('>IIBBBBB',0,1,3,6,0,0,0))+base[33:],0)
    add('size-before-stream',SIGNATURE+chunk(b'IHDR',struct.pack('>IIBBBBB',0,1,8,6,0,0,0))+base[33:],2)
    # input.count stops at its first byte/size error. A bad byte at cap+1
    # wins that byte's size check; later bad bytes cannot replace an earlier cap.
    padded=list(base)+[0]*(ENCODED_LIMIT-len(base))
    add('encoded-cap-plus-one',padded+[0],2)
    add('invalid-byte-at-cap-plus-one',padded+[256],1)
    add('size-before-later-invalid-byte',padded+[0,256],2)
    add('invalid-byte-before-cap',[256]+[0]*ENCODED_LIMIT,1)
    validate_controls(result);return result


def qualification_program():
    # Tiny fixed vectors qualify all four native formats and decisive routing.
    # Broad fixture output is never derived from Python expected pixels.
    palette=b'\x11\x3f\xc9\x47\x71\x9f'
    vectors=[('gray',png(1,1,0,b'\x7f'),1,[127]),
             ('gray-alpha',png(1,1,4,b'\x11\x80'),2,[17,128]),
             ('rgb',png(1,1,2,b'\1\2\3'),4,[1,2,3]),
             ('rgba',png(1,1,6,b'\1\2\3\x80'),7,[1,2,3,128]),
             ('palette-opaque',png(1,1,3,b'\0',palette=palette),4,[17,63,201]),
             ('palette-empty-trns',png(1,1,3,b'\0',palette=palette,transparency=b''),7,[17,63,201,255]),
             ('palette-allopaque-trns',png(1,1,3,b'\0',palette=palette,transparency=b'\xff\xff'),7,[17,63,201,255]),
             ('palette-plte-sticky',png(1,1,3,b'\0',palette=palette,transparency=b'\0',extra=[(b'PLTE',palette)]),7,[17,63,201,255]),
             ('gray-trns-no-match',png(1,1,0,b'\x11',transparency=b'\0\x7f'),2,[17,255]),
             ('gray-full16-key',png(1,1,0,b'\x12\x35',depth=16,transparency=b'\x12\x34'),2,[18,255]),
             ('alpha-high16',png(1,1,4,b'\x12\x34\0\xff',depth=16),2,[18,0]),
             ('cgbi-default',png(1,1,6,b'\3\x08\x0c\x10',cgbi=True),7,[3,8,12,16])]
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for name,data,fmt,expected in vectors:
        inspect_header(list(data))
        lines+=['/* '+name+' */ {const unsigned char data[]={'+','.join(map(str,data))+'};',
                'Image image=LoadImageFromMemory(".png",data,sizeof(data));if(!image.data)return 11;',
                f'if(image.width!=1||image.height!=1||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(1,1,image.format)!={len(expected)}){{UnloadImage(image);return 12;}}',
                'const unsigned char *p=image.data;if('+ '||'.join(f'p[{i}]!={v}' for i,v in enumerate(expected))+'){UnloadImage(image);return 13;}UnloadImage(image);}' ]
    row=json.dumps(QUALIFICATION,separators=(',',':'))
    return '\n'.join(lines+['puts('+json.dumps(row)+');return 0;}'])+'\n'


QUALIFICATION=dict(little_endian=True,png_enabled=True,structural_channels=True,
                   full_width_transparency=True,cgbi_defaults=True,formats=[1,2,4,7])


CODEC = formatted_codec.Codec(
    name='png', token='.png', aliases=('.PNG',), contraction_token='.PNG', formats={1: 1, 2: 2, 3: 4, 4: 7}, roles=('raw', 'bridge', 'surface', 'factory', 'owner', 'raw-roundtrip'), raylib_options=('SUPPORT_FILEFORMAT_PNG=ON',), batch=32, native_batch=32, qualification=(qualification_program(), QUALIFICATION),
    fixtures=fixtures, controls=controls, describe=__doc__)


def main(argv=None):
    formatted_codec.main(CODEC, argv)


if __name__ == '__main__':
    main()
