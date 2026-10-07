#!/usr/bin/env python3
"""Exact original-format TGA memory decoding against pinned raylib.

Accepted complete native fixtures only; checked-invalid controls are never sent
native. TGA is explicitly enabled in a fresh isolated native build. Actual native
metadata/raw bytes precede normalization. CPU-1/CPU-2/JS; no GPU or file claim.

Shared roles, native recording and lanes: tools/codec_formats.py.
"""
import json
import re
import struct
from tga_probe import fixtures as legacy_fixtures, targa, indexed_targa
import codec_formats

BATCH_SIZE = 32
SOURCE_BYTE_LIMIT = 196_608
FORMATS = {1:1, 2:2, 3:4, 4:7}
MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
C_PREFIX = codec_formats.C_PREFIX


def inspect_header(data):
    """Independent safety parser, including full packet framing, never pixels.

    It only proves the finite complete stream is safe for the native oracle.
    Expected decoded bytes are always obtained from that oracle, never Python.
    Native palette-start skips bytes, while out-of-range indices are permitted.
    """
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):raise ValueError('Unsafe native byte domain')
    if len(data)<18:raise ValueError('Incomplete native header')
    ident,mapped,kind,skip,count,entry_bits,_,_,w,h,bits,_=struct.unpack('<BBBHHBHHHHBB',bytes(data[:18]))
    depths=(8,15,16,24,32)
    if mapped==1:
        if kind not in (1,9) or not count or entry_bits not in depths or bits not in (8,16):raise ValueError('Unsafe native palette header')
        channels=1 if entry_bits==8 else 4 if entry_bits==32 else 3
        palette_bytes=skip+count*((entry_bits+7)//8)
    elif mapped==0:
        if kind not in (2,3,10,11) or bits not in depths:raise ValueError('Unsafe native direct header')
        channels=1 if bits==8 else 2 if bits==16 and kind in (3,11) else 4 if bits==32 else 3
        palette_bytes=0
    else:raise ValueError('Unsafe native map selector')
    if not 1<=w<=4096 or not 1<=h<=4096 or w*h>MAX_CASE_PIXELS:raise ValueError('Unsafe native dimensions')
    position=18+ident+palette_bytes;header_bytes=position
    if position>len(data):raise ValueError('Incomplete native ID/palette')
    source_bytes=(bits+7)//8;remaining=w*h
    if kind<8:
        position+=remaining*source_bytes
        if position>len(data):raise ValueError('Incomplete native raster')
    else:
        while remaining:
            if position>=len(data):raise ValueError('Missing native packet')
            code=data[position];position+=1;run=(code&127)+1
            if run>remaining:raise ValueError('Overrunning native packet')
            position+=(1 if code&128 else run)*source_bytes
            if position>len(data):raise ValueError('Incomplete native packet')
            remaining-=run
    return dict(width=w,height=h,channels=channels,header_bytes=header_bytes,
                raster_bytes=position-header_bytes,tail_bytes=len(data)-position,
                kind=kind,bits=bits,palette_bits=entry_bits if mapped else 0,
                palette_count=count if mapped else 0,palette_skip=skip if mapped else 0)


def validate_cases(cases):
    if type(cases) is not list or not cases:raise ValueError('Empty native TGA cases')
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


def packets(samples,repeat=False):
    """Encode complete raw/repeat packets, splitting at the 128-pixel limit."""
    result=[]
    for start in range(0,len(samples),128):
        selected=samples[start:start+128]
        result.append((128 if repeat else 0)+len(selected)-1)
        result.extend(v for sample in (selected[:1] if repeat else selected) for v in sample)
    return result


def fixtures():
    result=[]
    def add(name,data,w,h,c,extended=False):
        result.append(dict(id=name,bytes=list(data),width=w,height=h,channels=c,extended=extended))
    # Preserve historical streams exactly. The independent safety parser checks
    # all headers, complete palette bytes and raw/RLE packet boundaries again.
    for case in legacy_fixtures()[0]:
        data=case['bytes'];w=data[12]+256*data[13];h=data[14]+256*data[15]
        bits=data[7] if data[1] else data[16]
        channels=1 if bits==8 else 2 if not data[1] and bits==16 and data[2] in (3,11) else 4 if bits==32 else 3
        add('legacy-'+case['id'],data,w,h,channels)
    for c in (1,2,3,4):
        for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63)]:
            payload=[(i*61+j*79+(i//w)*17+13)&255 for i in range(w*h) for j in range(c)]
            add(f'c{c}-{name}',targa(w,h,c,payload,top=True),w,h,c,extended=name in ('single','padded'))
        # Full gray and alpha ramps, with independent channel permutations.
        for name in ('ramp','alpha-ramp'):
            samples=[[(i+j*71)&255 if name=='ramp' else (i if j==c-1 else (37+j*53)) for j in range(c)] for i in range(256)]
            data=targa(16,16,c,[v for sample in samples for v in sample],top=name=='ramp',descriptor=0xcf)
            add(f'c{c}-{name}',data,16,16,c,extended=True)
        # 127/128/129 logical pixels, with packet boundaries crossing rows.
        for n,w,h in ((127,1,127),(128,8,16),(129,43,3)):
            for repeat in (False,True):
                samples=[[(i*37+j*71+19)&255 for j in range(c)] for i in range(n)]
                add(f'c{c}-packet-{n}-{repeat}',targa(w,h,c,packets(samples,repeat),rle=True,top=repeat),w,h,c)
        # Maximal ID, ignored horizontal/attribute bits and complete valid tails.
        payload=[(i*19+j*83)&255 for i in range(17*17) for j in range(c)]
        add(f'c{c}-max-id-tail',targa(17,17,c,payload,identifier=bytes(range(255)),descriptor=0xdf)+list(b'TRUEVISION-XFILE.\0'),17,17,c,extended=True)
    samples=[list(struct.pack('<H',(i*1031+0x801f)&65535)) for i in range(64)]
    for kind,c in ((2,3),(3,2)):
        for top in (False,True):
            for rle in (False,True):
                payload=packets(samples) if rle else [v for sample in samples for v in sample]
                data=targa(8,8,2,payload,rle=rle,top=top,bits=16,descriptor=17);data[2]=kind+(8 if rle else 0)
                add(f'identical16-kind{kind}-{top}-{rle}',data,8,8,c,extended=True)
    palettes={8:[bytes([v]) for v in (3,127,251)],
              15:[struct.pack('<H',v) for v in (0x001f,0x4210,0xffff)],
              16:[struct.pack('<H',v) for v in (0x801f,0x4210,0x7fff)],
              24:[bytes(v) for v in ((3,2,1),(101,63,29),(251,197,151))],
              32:[bytes(v) for v in ((3,2,1,0),(101,63,29,128),(251,197,151,255))]}
    for depth,entries in palettes.items():
        for index_bits in (8,16):
            samples=[list(v.to_bytes(index_bits//8,'little')) for v in ([0,1,2,3,(1<<index_bits)-1]*3)]
            for top in (False,True):
                for rle in (False,True):
                    payload=packets(samples) if rle else [v for sample in samples for v in sample]
                    data=indexed_targa(3,5,entries,index_bits,depth,payload,rle=rle,top=top,skip=3 if index_bits==8 else 5,identifier=b'index\0')
                    add(f'palette-{depth}-{index_bits}-{top}-{rle}',data,3,5,1 if depth==8 else 4 if depth==32 else 3,extended=top and rle)
    # Map selector zero makes these deliberately nonsensical palette fields
    # irrelevant, including the palette depth used by indexed channel routing.
    data=targa(3,2,2,[3,0,71,127,255,255,41,19,103,211,7,251],top=True)
    data[3:8]=[255]*5
    add('ignored-direct-palette-metadata',data,3,2,2,extended=True)
    validate_cases(result);return result


def validate_controls(cases):
    ids=set()
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','error'}:raise ValueError('Checked control schema differs')
        if type(case['id']) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',case['id']) is None or case['id'] in ids:raise ValueError('Invalid/duplicate control ID')
        ids.add(case['id'])
        if type(case['error']) is not int or case['error'] not in range(5):raise ValueError('Invalid checked error')
        if type(case['bytes']) is not list or any(type(v) is not int or not 0<=v<=4294967295 for v in case['bytes']):raise ValueError('Invalid checked byte domain')
        try:inspect_header(case['bytes'])
        except ValueError:pass
        else:raise ValueError('Accepted native input mislabeled as control')


def controls():
    result=[dict(c,id='legacy-'+c['id']) for c in legacy_fixtures()[1]]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    base=targa(1,1,4,[3,2,1,0])
    for n in range(18):add(f'header-prefix-{n}',base[:n],0)
    for offset,name,values in [(1,'map',(2,255)),(2,'kind',(0,1,4,5,7,8,9,12,255)),(16,'depth',(0,1,7,9,14,17,23,25,31,33,255))]:
        for value in values:
            data=base.copy();data[offset]=value;add(f'{name}-{value}',data,0)
    for axis,offset in (('width',12),('height',14)):
        for value in (0,4097,65535):
            data=base.copy();data[offset:offset+2]=value.to_bytes(2,'little');add(f'{axis}-{value}',data,2)
    for kind in (2,3):
        for bits in (8,15,16,24,32):
            needed=(bits+7)//8
            for n in range(needed):
                data=targa(1,1,needed,bytes(n),bits=bits);data[2]=kind;add(f'truncated-kind{kind}-bits{bits}-{n}',data,3)
    for n in (0,1,254):
        data=base[:18];data[0]=255;add(f'truncated-id-{n}',data+[17]*n,3)
    for depth in (8,15,16,24,32):
        entry=bytes((depth+7)//8)
        for index_bits in (8,16):
            data=indexed_targa(1,1,[entry],index_bits,depth,bytes(index_bits//8))
            add(f'truncated-palette-{depth}-{index_bits}',data[:18+len(entry)-1],3)
            for n in range(index_bits//8):add(f'truncated-index-{depth}-{index_bits}-{n}',data[:18+len(entry)+n],3)
    for c in (1,2,3,4):
        for name,payload,w,error in [('no-command',[],1,3),('short-repeat',[128,*bytes(c-1)],1,3),('short-raw',[1,*bytes(2*c-1)],2,3),('raw-overrun',[1,*bytes(2*c)],1,4),('repeat-overrun',[129,*bytes(c)],1,4)]:
            add(f'c{c}-{name}',targa(w,1,c,payload,rle=True),error)
    gray=targa(1,1,1,[17],identifier=b'id')
    palette=indexed_targa(1,1,[b'\x11'],8,8,[0])
    for name,data,at in [('header',base,0),('id',gray,18),('palette',palette,18),('raster',base,18),('rle',targa(1,1,1,[128,17],rle=True),18),('tail',base+[0],len(base))]:
        data=data.copy();data[at]=256;add('invalid-byte-'+name,data,1)
    data=indexed_targa(1,1,[b'\3\2\1'],8,24,[0],skip=3);data[18]=256
    add('invalid-byte-palette-skip',data,1)
    data=indexed_targa(1,1,[b'\3\2\1'],16,24,[0,0]);data[-1]=256
    add('invalid-byte-palette-index',data,1)
    add('bad-byte-before-bad-header',[0,256],1)
    data=base.copy();data[12]=0;data[-1]=256;add('bad-byte-before-bad-size',data,1)
    data=base.copy();data[2]=0;data[12]=0;add('bad-header-before-bad-size',data,0)
    data=base[:18];data[12]=0;add('bad-size-before-truncated',data,2)
    add('overrun-before-truncated',targa(1,1,4,[129],rle=True),4)
    data=indexed_targa(1,1,[b'\x11'],8,8,[0],skip=255);add('palette-skip-truncated',data[:19],3)
    validate_controls(result);return result


def qualification_program():
    # Deliberately tiny fixed vectors qualify native routing. This is not a
    # Python decoder: broad expected pixels only come from native raw captures.
    vectors=[('gray',targa(1,1,1,[17]),1,[17]),
             ('gray-alpha',targa(1,1,2,[31,128]),2,[31,128]),
             ('rgb',targa(1,1,3,[3,2,1]),4,[1,2,3]),
             ('rgba',targa(1,1,4,[3,2,1,0]),7,[1,2,3,0]),
             ('packed16',targa(1,1,3,[31,128],bits=16),4,[0,0,255])]
    palette_vectors=[(8,[b'\x11',b'\x7f'],1,[127]),
                     (15,[b'\0\0',b'\x1f\x80'],4,[0,0,255]),
                     (16,[b'\0\0',b'\x1f\x80'],4,[0,0,255]),
                     (24,[b'\0\0\0',b'\3\2\1'],4,[1,2,3]),
                     (32,[b'\0\0\0\0',b'\3\2\1\x80'],7,[1,2,3,128])]
    for depth,entries,fmt,expected in palette_vectors:
        for width in (8,16):vectors.append((f'palette-{depth}-{width}',indexed_targa(1,1,entries,width,depth,(1).to_bytes(width//8,'little'),skip=3),fmt,expected))
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for name,data,fmt,expected in vectors:
        inspect_header(data)
        lines+=['/* '+name+' */ {const unsigned char data[]={'+','.join(map(str,data))+'};',
                'Image image=LoadImageFromMemory(".tga",data,sizeof(data));if(!image.data)return 11;',
                f'if(image.width!=1||image.height!=1||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(1,1,image.format)!={len(expected)}){{UnloadImage(image);return 12;}}',
                'const unsigned char *p=image.data;if('+ '||'.join(f'p[{i}]!={v}' for i,v in enumerate(expected))+'){UnloadImage(image);return 13;}UnloadImage(image);}' ]
    row=json.dumps(dict(little_endian=True,tga_enabled=True,direct16_distinct=True,palette_index_widths=[8,16],formats=[1,2,4,7]),separators=(',',':'))
    return '\n'.join(lines+['puts('+json.dumps(row)+');return 0;}'])+'\n'


CODEC = codec_formats.Codec(
    name='tga', token='.tga', aliases=('.TGA',), contraction_token='.TGA', formats={1: 1, 2: 2, 3: 4, 4: 7}, raylib_options=('SUPPORT_FILEFORMAT_TGA=ON',), batch=32, qualification=(qualification_program(), dict(little_endian=True,tga_enabled=True,direct16_distinct=True,palette_index_widths=[8,16],formats=[1,2,4,7])),
    fixtures=fixtures, controls=controls, describe=__doc__)


def main(argv=None):
    codec_formats.main(CODEC, argv)


if __name__ == '__main__':
    main()
