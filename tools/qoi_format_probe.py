#!/usr/bin/env python3
"""Exact native QOI format/bytes before normalization, strict errors and owners.

Memory-only, native channel-3 RGB888 / channel-4 RGBA8888, single mip level.
CPU-1, CPU-2 and JavaScript are independent lanes; no GPU or file claim.

Shared roles, native recording and lanes: tools/codec_formats.py.
"""
import json
import random
import struct
import codec_formats
from probekit import ROOT

BATCH_SIZE = 64
MARKER = [0, 0, 0, 0, 0, 0, 0, 1]
C_PREFIX = codec_formats.C_PREFIX


def header(width=1, height=1, channels=4, space=0):
    return list(b'qoif'+struct.pack('>II', width, height)+bytes([channels, space]))


def stream(width, height, channels, space, payload):
    return header(width, height, channels, space)+list(payload)+MARKER


def runs(count):
    return [253]*(count//62)+([191+count%62] if count%62 else [])


def fixtures():
    result = []
    def add(name, width, height, channels, space, payload, extended=False):
        result.append(dict(id=name, width=width, height=height, channels=channels,
                           space=space, bytes=stream(width,height,channels,space,payload), extended=extended))
    for channels in (3,4):
        for space in (0,1):
            prefix=f'c{channels}-s{space}-'
            def core(name, width, height, payload, extended=False):
                add(prefix+name,width,height,channels,space,payload,extended)
            core('initial-run',1,1,[192])
            core('initial-index',1,1,[0])
            core('rgb',1,1,[254,12,34,56])
            for alpha in (0,1,127,254,255): core(f'rgba-{alpha}',1,1,[255,12,34,56,alpha])
            # Full-alpha hashes are 22 and 42. RGB output cannot expose alpha,
            # so the third pixel discriminates against early alpha normalization.
            core('hidden-alpha-cache',3,1,[255,12,34,56,0,255,200,100,50,64,22],True)
            # RGBA(12,34,56,0) -> RGB(10,20,30,0), DIFF(+1,-2,+1),
            # LUMA(+6,-1,-9), INDEX22 restores first RGBA (hash22).
            core('alpha-through-rgb-diff-luma',5,1,[255,12,34,56,0,254,10,20,30,0x73,0x9f,0xf0,22])
            core('empty-index-rgb-alpha',3,1,[63,254,1,2,3,0])
            core('cache-collision',3,1,[254,1,0,0,254,65,0,0,56])
            core('cache-index0-index63',4,1,[255,0,0,0,0,255,21,0,0,0,0,63])
            core('run-inserts-black',3,1,[192,53,0])
            core('cache-after-run',4,1,[255,12,34,56,0,193,22])
            core('noncanonical-repeated-index',3,1,[0,0,0])
            for count in (1,2,61,62,63,64,124): core(f'run-{count}',count,1,runs(count))
            core('row-crossing-run',3,5,[255,17,63,201,127]+runs(13)+[22])
            # Reset near both wrap boundaries before all 64 DIFF encodings.
            diff=[]
            for byte in range(64,128): diff += [254,0 if byte%2 else 255,255 if byte%2 else 0,0,byte]
            core('all-diff',16,8,diff)
            luma=[]
            for anchor in (0,255):
                for dg in (0,1,31,32,62,63):
                    for residual in (0,15,0x70,0x88,0xf0,0xff): luma += [254,anchor,anchor,anchor,128+dg,residual]
            core('luma-boundaries',12,12,luma)
            core('byte-alpha-ramps',16,16,[v for i in range(256) for v in (255,i,255-i,i^85,i)])
    for channels in (3,4):
        add(f'c{channels}-axis-row',4096,1,channels,0,runs(4096))
        add(f'c{channels}-axis-column',1,4096,channels,1,runs(4096))
        # A moderate nonuniform image above 4096 pixels, compact runs/literals.
        payload=[]
        for i in range(82): payload += [255,i,255-i,i^85,i*3%256]+runs(61)
        payload += [254,7,11,13]+runs(18)
        add(f'c{channels}-moderate-nonuniform',81,63,channels,0,payload)
        rng=random.Random(0x514f49)
        payload=[];count=0
        while count<513:
            choice=rng.randrange(6)
            if choice==0: chunk=[rng.randrange(64)];n=1
            elif choice==1: chunk=[64+rng.randrange(64)];n=1
            elif choice==2: chunk=[128+rng.randrange(64),rng.randrange(256)];n=1
            elif choice==3: n=min(513-count,rng.randrange(1,63));chunk=[191+n]
            elif choice==4: chunk=[254,*[rng.randrange(256) for _ in range(3)]];n=1
            else: chunk=[255,*[rng.randrange(256) for _ in range(4)]];n=1
            payload+=chunk;count+=n
        add(f'c{channels}-seeded-mix',27,19,channels,1,payload)
    for case in json.loads((ROOT/'tests/fixtures/images.json').read_text())['cases']:
        if 'qoi' in case:
            data=case['qoi']
            result.append(dict(id='legacy-'+case['id'],width=case['width'],height=case['height'],
                               channels=data[12],space=data[13],bytes=data,extended=False))
    if len({c['id'] for c in result})!=len(result): raise ValueError('Duplicate QOI fixture ID')
    return result


def controls():
    result=[]
    def add(name,data,error,native=False): result.append(dict(id=name,bytes=data,error=error,native=native))
    h=header();valid=stream(1,1,4,0,[192])
    for n in range(14): add(f'header-prefix-{n}',h[:n],0)
    for name,index,value in [('magic',0,0),*[(f'channels-{c}',12,c) for c in (0,1,2,5)],('colorspace',13,2)]:
        data=valid.copy();data[index]=value;add(name,data,0,True)
    for axis in ('width','height'):
        for value in (0,4097,0xffffffff): add(f'{axis}-{value}',header(**{axis:value})+[192]+MARKER,2,value==0)
    for name,index in [('header-byte',0),('payload-byte',14),('tail-byte',22)]:
        data=valid.copy();data[index]=256;add(name,data,1)
    data=valid.copy();data[0]=0;data[-1]=256;add('bad-byte-before-bad-header',data,1)
    data=header(width=0)+[256];add('bad-byte-before-bad-size',data,1)
    add('no-opcode',h,3)
    for tag,need in [(254,3),(255,4),(128,1)]:
        for n in range(need):add(f'truncated-{tag}-{n}',h+[tag]+[1]*n,3)
    add('pixel-underflow',header(width=2)+[192],3)
    add('missing-marker',h+[192],4)
    for n in range(8):
        data=valid.copy();data[-8+n]^=1;add(f'marker-corrupt-{n}',data,4)
        add(f'marker-prefix-{n}',h+[192]+MARKER[:n],4)
    for name,tail in [('zero',[0]),('opcode',[192]),('second-marker',MARKER)]:add('extra-'+name,valid+tail,4)
    add('run-overflow-first',stream(1,1,4,0,[193]),4)
    add('run-overflow-62',stream(61,1,3,0,[253]),4)
    add('run-overflow-late',stream(2,1,4,0,[192,193]),4)
    for tag in (254,255,128):add(f'marker-absorbed-{tag}',h+[tag]+MARKER,4)
    return result


CODEC = codec_formats.Codec(
    name='qoi', token='.qoi', aliases=('.QOI',), contraction_token='.QOI', formats={3: 4, 4: 7}, roles=('raw', 'bridge', 'surface', 'dispatch-qoi'), extended_roles=('dispatch-QOI', 'uncontracted', 'fused', 'factory', 'owner'), batch=64, little_endian=False,
    fixtures=fixtures, controls=controls, describe=__doc__)


def main(argv=None):
    codec_formats.main(CODEC, argv)


if __name__ == '__main__':
    main()
