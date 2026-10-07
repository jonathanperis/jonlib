#!/usr/bin/env python3
"""Exact original-format binary PGM/PPM memory decoding against pinned raylib.

Accepted complete native fixtures only; checked-invalid controls are never sent
native. PNM is explicitly enabled in a fresh isolated native build. Actual native
metadata/raw bytes precede normalization. CPU-1/CPU-2/JS; no GPU or file claim.

Shared roles, native recording and lanes: tools/codec_formats.py.
"""
import re
from pnm_probe import fixtures as legacy_fixtures
import codec_formats

BATCH_SIZE = 32
SPACE = b' \t\n\v\f\r'
MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
C_PREFIX = codec_formats.C_PREFIX


def header(width=1, height=1, channels=1, maximum=255, separator=b'\n'):
    return (b'P5' if channels==1 else b'P6')+f'\n{width} {height}\n{maximum}'.encode()+separator


def inspect_header(data):
    """Independent safety parser only: never supplies expected decoded samples."""
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):raise ValueError('Unsafe native byte domain')
    data=bytes(data)
    if data[:2] not in (b'P5',b'P6'):raise ValueError('Unsafe native magic')
    position=2;values=[]
    for _ in range(3):
        while position<len(data):
            if data[position] in SPACE:position+=1
            elif data[position]==35:
                while position<len(data) and data[position] not in (10,13):position+=1
            else:break
        start=position
        while position<len(data) and 48<=data[position]<=57:position+=1
        if position==start or position==len(data):raise ValueError('Unsafe native header')
        token=data[start:position]
        if len(token)>12:raise ValueError('Unsafe native decimal magnitude')
        values.append(int(token))
    if data[position] not in SPACE:raise ValueError('Unsafe native separator')
    w,h,maximum=values
    if not 1<=w<=4096 or not 1<=h<=4096 or w*h>MAX_CASE_PIXELS or not 1<=maximum<=65535:raise ValueError('Unsafe native dimensions/depth')
    return dict(width=w,height=h,channels=1 if data[1]==53 else 3,maximum=maximum,header_bytes=position+1,
                raster_bytes=w*h*(1 if data[1]==53 else 3)*(2 if maximum>255 else 1))


def validate_cases(cases):
    if not cases:raise ValueError('Empty native PNM cases')
    ids=set();total=0
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','width','height','channels','maximum','header_bytes','raster_bytes','extended'}:raise ValueError('Native case schema differs')
        name=case['id']
        if type(name) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',name) is None or name in ids:raise ValueError('Invalid/duplicate native fixture ID')
        ids.add(name)
        if type(case['extended']) is not bool:raise ValueError('Invalid alias selector')
        observed=inspect_header(case['bytes'])
        if any(type(case[k]) is not int or case[k]!=value for k,value in observed.items()):raise ValueError('Native declared metadata/header differs')
        if len(case['bytes'])<case['header_bytes']+case['raster_bytes']:raise ValueError('Incomplete native raster')
        total+=len(case['bytes'])
    if total>MAX_TOTAL_BYTES:raise ValueError('Unsafe native aggregate fixture size')


def fixtures():
    result=[]
    def add(name,w,h,c,maximum,payload,*,prefix=None,tail=b'',extended=False):
        prefix=header(w,h,c,maximum) if prefix is None else prefix
        case=dict(id=name,width=w,height=h,channels=c,maximum=maximum,header_bytes=len(prefix),raster_bytes=w*h*c*(2 if maximum>255 else 1),bytes=list(prefix+bytes(payload)+tail),extended=extended)
        result.append(case)
    # Preserve every historical input verbatim; declarations come from generator
    # identities, and the independent safety parser checks their complete headers.
    for case in legacy_fixtures()[0]:
        name=case['id'];c=3 if name.startswith('P6') else 1
        w,h=(16,16) if name.endswith('-16bit-bytes') else (3,2)
        if name in ('crlf-payload','space-payload','hash-payload','16bit-crlf-payload'):w,h=2,1
        if name=='wide':w,h=4096,1
        if name=='tall':w,h=1,4096
        maximum=int(name.rsplit('-max-',1)[1]) if '-max-' in name else (65535 if '16bit' in name else 255)
        raster=w*h*c*(2 if maximum>255 else 1)
        tail=4 if name.endswith('-16bit-bytes') else 12 if name.endswith(('comments','spaces','leading-zeros','inline-comments')) else 0
        result.append(dict(case,id='legacy-'+name,width=w,height=h,channels=c,maximum=maximum,header_bytes=len(case['bytes'])-raster-tail,raster_bytes=raster,extended=name in ('P5-comments','P6-comments')))
    for c in (1,3):
        for maximum in (255,256):
            prefix=f'c{c}-max{maximum}-'
            def sample(i):
                kept=(i*61+17)&255
                return (kept,) if maximum==255 else ((i*43+128)&255,kept)
            for name,w,h in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63),('channel-ramps',16,16)]:
                values=[v for i in range(w*h*c) for v in sample(i)]
                add(prefix+name,w,h,c,maximum,values,extended=name in ('single','padded'))
            for separator in SPACE:
                add(prefix+f'separator-{separator}',1,1,c,maximum,[v for i in range(c) for v in sample(i)],prefix=header(1,1,c,maximum,bytes([separator])))
        for maximum in (1,15,100,257,1000,65535):
            payload=[v for i in range(5*c) for v in ((255-i,) if maximum<=255 else (i,255-i))]
            add(f'c{c}-unscaled-{maximum}',5,1,c,maximum,payload,tail=b' # ignored\n',extended=maximum==257)
        for varying in ('first','second'):
            payload=[v for i in range(256*c) for v in ((i&255,127) if varying=='first' else (85,i&255))]
            add(f'c{c}-wide-vary-{varying}',16,16,c,65535,payload)
    add('grayscale-exact-ramp',16,16,1,255,range(256),extended=True)
    add('rgb-distinct-boundaries',2,3,3,255,[0,1,127,128,254,255,255,0,128,1,127,254,254,128,1,127,255,0],extended=True)
    validate_cases(result);return result


def controls():
    result=[dict(c,id='legacy-rejected-'+c['id']) for c in legacy_fixtures()[1]]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    h=header()
    for n in range(len(h)):add(f'header-prefix-{n}',h[:n],0)
    for magic in (b'P1',b'P2',b'P4',b'P7',b'p5',b'P0'):add('magic-'+magic.decode(),magic+h[2:]+b'\0',0)
    for axis in ('width','height'):
        for value in (0,4097,2147483647,4294967295):
            # Decimal overflow precedes size validation above signed-32 magnitude.
            add(f'{axis}-{value}',header(**{axis:value})+b'\0',0 if value>2147483647 else 2)
    for maximum in (0,65536,2147483648,4294967295):add(f'maximum-{maximum}',header(maximum=maximum)+b'\0\0',0)
    for text in (b'P5 ',b'P5 1 ',b'P5 1 1 ',b'P5 x 1 255\n',b'P5 1 x 255\n',b'P5 1 1 x\n'):
        add('missing-field-'+str(len(result)),text,0)
    for c in (1,3):
        for maximum in (255,256):
            needed=c*(2 if maximum>255 else 1)
            for n in range(needed):add(f'truncated-c{c}-max{maximum}-{n}',header(channels=c,maximum=maximum)+bytes(n),3)
    for where,data in [('header',[256,*h[1:],0]),('raster',[*h,256]),('tail',[*h,0,256]),('wide-discarded',[*header(maximum=256),256,0]),('wide-kept',[*header(maximum=256),0,256])]:add('invalid-byte-'+where,data,1)
    add('bad-byte-before-bad-header',[0,256],1)
    add('bad-byte-before-bad-size',[*header(width=0),256],1)
    add('bad-max-before-bad-size',header(width=0,maximum=0),0)
    add('bad-separator-before-bad-size',header(width=0,separator=b'x'),0)
    add('complete-header-missing-raster',header(),3)
    if len({c['id'] for c in result})!=len(result):raise ValueError('Duplicate checked control ID')
    return result


QUALIFY=C_PREFIX+r'''int main(void){
  if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);
  const unsigned char gray[]={'P','5','\n','1',' ','1','\n','2','5','6','\n',0x12,0x34};
  const unsigned char rgb[]={'P','6','\n','1',' ','1','\n','2','5','5','\n',1,127,255};
  Image a=LoadImageFromMemory(".ppm",gray,sizeof(gray));
  if(!a.data)return 11;
  if(a.width!=1||a.height!=1||a.mipmaps!=1||a.format!=1||GetPixelDataSize(1,1,a.format)!=1){UnloadImage(a);return 11;}
  if(((unsigned char *)a.data)[0]!=0x34){UnloadImage(a);return 12;}UnloadImage(a);
  Image b=LoadImageFromMemory(".pgm",rgb,sizeof(rgb));
  if(!b.data)return 13;
  if(b.width!=1||b.height!=1||b.mipmaps!=1||b.format!=4||GetPixelDataSize(1,1,b.format)!=3){UnloadImage(b);return 13;}
  const unsigned char *p=b.data;if(p[0]!=1||p[1]!=127||p[2]!=255){UnloadImage(b);return 14;}UnloadImage(b);
  puts("{\"little_endian\":true,\"pnm_enabled\":true,\"wide_second_byte\":true,\"formats\":[1,4]}");return 0;
}
'''


CODEC = codec_formats.Codec(
    name='pnm', token='.ppm', aliases=('.pgm', '.PPM', '.PGM'), contraction_token='.PPM', formats={1: 1, 3: 4}, raylib_options=('SUPPORT_FILEFORMAT_PNM=ON',), batch=32, qualification=(QUALIFY, dict(little_endian=True,pnm_enabled=True,wide_second_byte=True,formats=[1,4])),
    fixtures=fixtures, controls=controls, describe=__doc__)


def main(argv=None):
    codec_formats.main(CODEC, argv)


if __name__ == '__main__':
    main()
