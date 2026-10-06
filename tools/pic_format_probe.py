#!/usr/bin/env python3
"""Exact original-format PIC memory decoding against pinned raylib.

Only independently admitted complete PIC fixtures reach native code. Malformed
PIC may free/null its buffer then run a 4-to-3 conversion; controls NEVER go
native. Admission independently walks every descriptor, row control and sample.
PIC shares stb sniffing: a .pic suffix alone proves no PIC content identity.
Raw native metadata and every byte are captured before separate normalization.
CPU-1/CPU-2/JavaScript only; no GPU, formatted-file or generic-formatted claim.

Shared roles, native recording and lanes: tools/formatted_codec.py.
"""
import json
import re
import struct
from bmp_probe import bend_bytes
from pic_probe import fixtures as legacy_fixtures, pic_header, pic, pic_packets
import formatted_codec
from probekit import ROOT

BATCH_SIZE = 32
SOURCE_BYTE_LIMIT = 196_608
FORMATS = {3:4, 4:7}
MAX_CASE_PIXELS = 8192
MAX_TOTAL_BYTES = 2_000_000
C_PREFIX = formatted_codec.C_PREFIX


class AdmissionError(ValueError):
    """Structural checked error, never a decoded-pixel expectation."""
    def __init__(self,message,error):
        super().__init__(message);self.error=error


def inspect_header(data, *, fixture_budget=True):
    """Independently admit actual complete PIC bytes before native execution.

    This is a bounds/format scanner, never a pixel oracle. Empty masks still
    require post-descriptor and post-control bytes. Every zero count consumes
    a control (and its selected sample); pure counts clip, mixed counts reject
    overruns before reading samples. All validated descriptors contribute to
    the sticky native component OR, regardless of order, opacity or overwrites.
    """
    def reject(message,error):raise AdmissionError(message,error)
    if type(data) is not list or any(type(v) is not int or not 0<=v<=255 for v in data):reject('Unsafe native byte domain',1)
    if len(data)>2147483647:reject('Native encoded length exceeds signed int',2)
    if len(data)<104 or data[:4]!=[83,128,246,52] or data[88:92]!=[80,73,67,84]:reject('Incomplete/invalid native PIC header',0)
    width=data[92]*256+data[93];height=data[94]*256+data[95]
    if not 1<=width<=4096 or not 1<=height<=4096:reject('Unsafe native dimensions',2)
    if fixture_budget and width*height>MAX_CASE_PIXELS:reject('Native fixture pixel budget exceeded',2)
    at=104;descriptors=[];effective_mask=0
    while True:
        if len(descriptors)==10:reject('Too many native PIC descriptors',0)
        if at+4>=len(data):reject('Incomplete native PIC descriptor/post-descriptor byte',0)
        chain,depth,kind,mask=data[at:at+4];at+=4
        if depth!=8 or kind not in (0,1,2):reject('Unsafe native PIC descriptor profile',0)
        descriptors.append(dict(kind=kind,mask=mask,channels=(mask&0xf0).bit_count()))
        effective_mask|=mask
        if chain==0:break
    payload=at;zero_counts=clipped_counts=controls_count=0
    for _ in range(height):
        for descriptor in descriptors:
            kind=descriptor['kind'];channels=descriptor['channels'];left=width
            if kind==0:
                count=left*channels
                if at+count>len(data):reject('Incomplete native PIC raw samples',3)
                at+=count;continue
            while left:
                # Native checks EOF immediately after reading each control,
                # including empty masks. Do not synthesize zero bytes at EOF.
                if at+1>=len(data):reject('Incomplete native PIC control/post-control byte',3)
                code=data[at];at+=1;controls_count+=1;literal=False
                if kind==1:
                    count=min(code,left);clipped_counts+=int(code>left)
                elif code==128:
                    if at+2>len(data):reject('Incomplete native PIC extended count',3)
                    count=data[at]*256+data[at+1];at+=2
                elif code<128:count=code+1;literal=True
                else:count=code-127
                if kind==2 and count>left:reject('Unsafe native PIC mixed row overrun',4)
                sample_bytes=channels*(count if literal else 1)
                if at+sample_bytes>len(data):reject('Incomplete native PIC RLE samples',3)
                at+=sample_bytes;left-=count;zero_counts+=int(count==0)
    return dict(width=width,height=height,channels=4 if effective_mask&0x10 else 3,
                descriptors=descriptors,packet_count=len(descriptors),effective_mask=effective_mask,
                payload_offset=payload,payload_bytes=at-payload,tail_bytes=len(data)-at,
                controls=controls_count,zero_counts=zero_counts,clipped_counts=clipped_counts)


def checked_error(data):
    """Return only the independently scanned checked scalar error, or None."""
    try:inspect_header(data,fixture_budget=False)
    except AdmissionError as error:return error.error
    return None


def validate_cases(cases):
    if type(cases) is not list or not cases:raise ValueError('Empty native PIC cases')
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
    # Only immutable historical streams are reused, never a normalized oracle.
    legacy=legacy_fixtures()[0]
    if len(legacy)!=33 or sum(inspect_header(c['bytes'])['width']*inspect_header(c['bytes'])['height'] for c in legacy)!=8867:raise ValueError('Legacy PIC fixture inventory differs')
    for case in legacy:add('legacy-'+case['id'],case['bytes'])
    for channels in (3,4):
        for name,width,height in [('single',1,1),('padded',3,5),('axis-row',4096,1),('axis-column',1,4096),('moderate',81,63)]:
            colors=[sum(((i*61+j*79+(i//width)*17+13)&255)<<(24-8*j) for j in range(4)) for i in range(width*height)]
            add(f'c{channels}-{name}',pic(width,height,[(0xe0 if channels==3 else 0xf0,colors)]),name in ('single','padded'))
    for name,colors in [('alpha-ramp',[0x25354700|i for i in range(256)]),('all-opaque',[((i*65793&0xffffff)<<8)|255 for i in range(256)]),('all-zero-alpha',[(i*65793&0xffffff)<<8 for i in range(256)])]:
        add(name,pic(16,16,[(0xf0,colors)]),True)
    colors=[0x01020300,0x11223380,0xaabbccff,0x00ff007f,0xff00ff01,0xfefdfcfe]
    replacement=[0x071727ff,0x081828ff,0x091929ff,0x0a1a2aff,0x0b1b2bff,0x0c1c2cff]
    for name,packets in [('early-alpha-followed-rgb',[(0x10,colors),(0xe0,replacement)]),
                         ('middle-alpha-followed-rgb',[(0x80,replacement),(0x10,colors),(0xe0,colors)]),
                         ('opaque-alpha-followed-rgb',[(0x10,replacement),(0xe0,colors)]),
                         ('alpha-overwrites-final-opaque',[(0xf0,colors),(0x10,list(reversed(colors))),(0x10,replacement),(0xe0,colors)]),
                         ('overlap-alpha-zero',[(0xf0,replacement),(0x90,colors),(0x40,replacement)]),
                         ('lowbits-all-channels',[(0xff,colors)]),
                         ('lowbits-empty-masks',[(0x0f,colors),(0x01,replacement)]),
                         ('alpha-then-empty-mask',[(0x10,colors),(0x0f,replacement)]),
                         ('ten-packets-alpha-first',[(0x10,colors)]+[(0x80,replacement)]*8+[(0x00,colors)])]:
        add(name,pic(3,2,packets),True)
    def sample(color,mask):return [value for i,value in enumerate(color.to_bytes(4,'big')) if mask&(128>>i)]
    # Both RLE families exercise all 16 high-bit masks, low-bit indifference,
    # zero counts and exact/oversize runs. The final sentinel is deliberate:
    # empty masks still need one byte after their last control.
    for kind in (1,2):
        for mask in range(0,256,16):
            rows=[]
            for y in range(2):
                samples=[sample(c,mask) for c in colors[y*3:(y+1)*3]]
                rows.append([0,*samples[0],1,*samples[0],255,*samples[1]] if kind==1 else
                            [128,0,0,*samples[0],1,*samples[0],*samples[1],128,0,1,*samples[2]])
            add(f'all-masks-rle-{kind}-{mask:02x}',pic_packets(3,2,[(kind,mask,rows)])+[0],True)
        add(f'rle-lowbits-{kind}',pic_packets(3,1,[(kind,0x9f,[[3,17,128] if kind==1 else [130,17,128]])])+[0],True)
    add('pure-clip-rgba',pic_packets(1,1,[(1,0xf0,[[255,1,2,3,0]])]),True)
    add('pure-zero-progress-then-one',pic_packets(1,1,[(1,0x10,[[0,99]*64+[1,0]])]),True)
    add('mixed-zero-progress-then-one',pic_packets(1,1,[(2,0x10,[[128,0,0,99]*64+[0,0]])]),True)
    add('mixed-extended-255-256',pic_packets(511,1,[(2,0xf0,[[128,0,255,1,2,3,0,128,1,0,4,5,6,255]])]),True)
    add('mixed-raw128-repeat128-one',pic_packets(257,1,[(2,0x90,[[127,*sum(([i,255-i] for i in range(128)),[]),255,17,0,0,37,255]])]),True)
    add('mixed-raw-pure-alpha-order',pic_packets(3,2,[
        (2,0x10,[[2,0,128,255],[2,255,128,0]]),
        (0,0xe0,[[1,2,3,4,5,6,7,8,9],[11,12,13,14,15,16,17,18,19]]),
        (1,0x80,[[0,99,1,21,255,22],[0,99,1,31,255,32]])]),True)
    for kind in (1,2):
        add(f'empty-mask-progress-{kind}',pic_packets(4,2,[(kind,0x0f,[[0,2,2],[0,2,2]] if kind==1 else [[128,0,0,3],[128,0,0,3]])])+[0],True)
    base=pic(1,1,[(0xe0,[0x12345678])])
    for value in (0,255):
        data=base.copy();data[4:88]=[value]*84;data[96:104]=[value]*8
        add(f'ignored-header-{value}',data,True)
    add('ignored-trailer',base+[83,128,246,52,80,73,67,84,0,255,17],True)
    add('encoded-over-one-mib',base+[0]*(1048577-len(base)))
    validate_cases(result);return result


def validate_controls(cases):
    if type(cases) is not list:raise ValueError('Invalid checked PIC controls')
    ids=set()
    for case in cases:
        if type(case) is not dict or set(case)!={'id','bytes','error'}:raise ValueError('Checked control schema differs')
        if type(case['id']) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',case['id']) is None or case['id'] in ids:raise ValueError('Invalid/duplicate control ID')
        ids.add(case['id'])
        if type(case['error']) is not int or case['error'] not in range(5):raise ValueError('Invalid checked error')
        if type(case['bytes']) is not list or any(type(v) is not int or not 0<=v<=4294967295 for v in case['bytes']):raise ValueError('Invalid checked byte domain')
        observed=checked_error(case['bytes'])
        if observed is None:raise ValueError('Accepted native input mislabeled as control')
        if observed!=case['error']:raise ValueError('Checked PIC scalar error differs')


def controls():
    legacy=legacy_fixtures()[1]
    if len(legacy)!=24:raise ValueError('Legacy PIC control inventory differs')
    result=[dict(c,id='legacy-'+c['id']) for c in legacy]
    def add(name,data,error):result.append(dict(id=name,bytes=list(data),error=error))
    base=pic(1,1,[(0xf0,[0x12345678])])
    for n in range(len(base)):add('prefix-'+str(n),base[:n],0 if n<=108 else 3)
    for n in range(len(base)):
        data=base.copy();data[n]=256;add('invalid-byte-'+str(n),data,1)
    for name,data in [('qoi',b'qoif'+bytes(30)),('bmp',b'BM'+bytes(60)),('png',b'\x89PNG\r\n\x1a\n'+bytes(50)),('pnm',b'P6\n1 1\n255\n\1\2\3'),('tga',bytes(30)),('gif',b'GIF89a'+bytes(40))]:add('non-pic-'+name,data,0)
    for offset in (92,94):
        for value in (0,4097,65535):
            data=base.copy();data[offset:offset+2]=[value>>8,value&255]
            add(f'axis-{offset}-{value}',data,2)
            add(f'byte-before-axis-{offset}-{value}',data+[256],1)
    for offset,values in ((105,(0,1,7,16,255)),(106,(3,4,127,255))):
        for value in values:
            data=base.copy();data[offset]=value;add(f'descriptor-{offset}-{value}',data,0)
            add(f'byte-before-descriptor-{offset}-{value}',data+[256],1)
    for offset in (0,88):
        data=base.copy();data[offset]=0;data[92:94]=[0,0];add(f'header-before-axis-{offset}',data,0)
    for value in (256,65536,4294967295):
        add('invalid-trailer-'+str(value),base+[value],1)
        add('invalid-short-header-'+str(value),[83,value],1)
        data=base.copy();data[40]=value;add('invalid-ignored-header-'+str(value),data,1)
    add('raw-empty-mask-descriptor-eof',pic(1,1,[(0,[0])])[:108],0)
    for count in (10,11):
        data=pic(1,1,[(0x10,[0])]*count)
        if count==10:data[104+4*(count-1)]=255
        add('unclosed-chain-'+str(count),data,0)
    for kind in (1,2):
        for mask in (0x00,0x0f,0x80,0xf0):
            add(f'post-control-eof-{kind}-{mask}',pic_packets(1,1,[(kind,mask,[[1 if kind==1 else 0]])]),3)
        for missing in (1,2,3):
            payload=[1,*([17]*(4-missing))] if kind==1 else [0,*([17]*(4-missing))]
            add(f'short-rgba-{kind}-{missing}',pic_packets(1,1,[(kind,0xf0,[payload])]),3)
    for name,width,mask,payload,error in [
        ('empty-extended-count-eof',1,0,[128],3),
        ('empty-extended-count-short',1,0,[128,0],3),
        ('empty-zero-extended-eof',1,0,[128,0,0],3),
        ('pure-zero-empty-eof',1,0,[0]*257,3),
        ('mixed-zero-empty-eof',1,0,[128,0,0]*257,3),
        ('literal-overrun-before-sample',1,0xf0,[1,17],4),
        ('repeat-overrun-before-sample',1,0xf0,[129,17],4),
        ('extended-overrun-before-sample',1,0xf0,[128,255,255],4),
        ('literal-overrun-empty-mask',1,0,[1,0],4),
        ('repeat-overrun-empty-mask',1,0,[129,0],4),
        ('extended-overrun-empty-mask',1,0,[128,0,2],4),
        ('extended-short-sample',1,0xf0,[128,0,1,1,2,3],3),
        ('raw128-short-sample',128,0x80,[127,*range(127)],3),
        ('repeat128-short-sample',128,0xf0,[255,1,2,3],3),
        ('zero-repeat-short-sample',1,0xf0,[128,0,0,1,2,3],3)]:
        kind=1 if name.startswith('pure-') else 2
        data=pic_packets(width,1,[(kind,mask,[payload])]);add(name,data,error)
        add('byte-before-'+name,data+[256],1)
    # Malformed later descriptors win before any earlier packet raster is read.
    data=pic(1,1,[(0x10,[0]),(0xe0,[0])]);data[109]=16
    add('late-descriptor-before-stream',data[:113],0)
    validate_controls(result);return result


def qualification_program():
    # Tiny independent known vectors qualify original 3/4-channel selection,
    # defaults, sticky descriptor OR and overwrite/RLE routing. Broad expected
    # pixels are always captured from native output, never decoded in Python.
    vectors=[('rgb',pic(1,1,[(0xe0,[0x01020380])]),4,[1,2,3]),
             ('rgba',pic(1,1,[(0xf0,[0x01020380])]),7,[1,2,3,128]),
             ('opaque-alpha',pic(1,1,[(0xf0,[0x010203ff])]),7,[1,2,3,255]),
             ('alpha-first',pic(1,1,[(0x10,[0x00000000]),(0xe0,[0x010203ff])]),7,[1,2,3,0]),
             ('alpha-middle',pic(1,1,[(0x80,[0x01000000]),(0x10,[0x00000080]),(0x60,[0x000203ff])]),7,[1,2,3,128]),
             ('empty-low-mask',pic(1,1,[(0x0f,[0])]),4,[255,255,255]),
             ('overlap',pic(1,1,[(0xf0,[0x010203ff]),(0x90,[0x09000000])]),7,[9,2,3,0]),
             ('pure-zero-clip',pic_packets(1,1,[(1,0xf0,[[0,9,8,7,6,255,1,2,3,0]])]),7,[1,2,3,0]),
             ('mixed-zero-extended',pic_packets(1,1,[(2,0xf0,[[128,0,0,9,8,7,6,128,0,1,1,2,3,128]])]),7,[1,2,3,128])]
    lines=[C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for name,data,fmt,expected in vectors:
        inspect_header(list(data))
        lines+=['/* '+name+' */ {const unsigned char data[]={'+','.join(map(str,data))+'};',
                'Image image=LoadImageFromMemory(".pic",data,sizeof(data));if(!image.data)return 11;',
                f'if(image.width!=1||image.height!=1||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(1,1,image.format)!={len(expected)}){{UnloadImage(image);return 12;}}',
                'const unsigned char *p=image.data;if('+ '||'.join(f'p[{i}]!={v}' for i,v in enumerate(expected))+'){UnloadImage(image);return 13;}UnloadImage(image);}' ]
    row=json.dumps(QUALIFICATION,separators=(',',':'))
    return '\n'.join(lines+['puts('+json.dumps(row)+');return 0;}'])+'\n'


QUALIFICATION=dict(little_endian=True,pic_enabled=True,all_descriptor_channels=True,
                   default_white=True,packet_overwrite=True,rle_rules=True,formats=[4,7])


CODEC = formatted_codec.Codec(
    name='pic', token='.pic', aliases=('.PIC',), contraction_token='.PIC', formats={3: 4, 4: 7}, roles=('raw', 'bridge', 'surface', 'factory', 'owner', 'raw-roundtrip'), raylib_options=('SUPPORT_FILEFORMAT_PIC=ON',), batch=32, native_batch=32, qualification=(qualification_program(), QUALIFICATION),
    fixtures=fixtures, controls=controls, describe=__doc__)


def main(argv=None):
    formatted_codec.main(CODEC, argv)


if __name__ == '__main__':
    main()
