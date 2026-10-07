#!/usr/bin/env python3
"""Exact checked formats 1..8 TGA file bytes, independent decoding and typed IO.

Uses actual pinned ExportImage; never ExportImageToMemory or ImageFormat to
prepare source pixels. CPU-1/CPU-2/JavaScript are separate exact lanes. No GPU
claim. Native error-return parity is deliberately not claimed for short writes.
"""
import random
import struct

import codec_exports
from codec_exports import BPP
from image_format_probe import r32_words
from probekit import ProbeFailure


def fixtures():
    rng = random.Random(0x7A481)
    result = []
    def add(name, fmt, width, height, data):
        if len(data) != width*height*BPP[fmt]: raise ValueError('Fixture byte shape')
        result.append(dict(id=name, format=fmt, width=width, height=height, data=list(data)))
    samples = {1:[b'\x00',b'\x7f',b'\xff'], 2:[b'\x11\x00',b'\x11\x7f',b'\x11\xff'],
               3:[struct.pack('<H',v) for v in (0,0xF801,0xFFFF)],
               4:[bytes(v) for v in ((0,1,2),(127,128,129),(255,254,253))],
               5:[struct.pack('<H',v) for v in (0,0xF800,0xF801)],
               6:[struct.pack('<H',v) for v in (0,0xA127,0xA12F)],
               7:[bytes(v) for v in ((17,63,201,0),(17,63,201,127),(17,63,201,255))],
               8:[struct.pack('<I',v) for v in (0,0x3F000000,0x3F800000)]}
    for fmt in BPP:
        def pattern(values): return b''.join(samples[fmt][v] for v in values)
        add(f'format-{fmt}-single',fmt,1,1,pattern([2]))
        for width in range(1,5):
            add(f'format-{fmt}-width-{width}',fmt,width,2,pattern([i%3 for i in range(width)]+[(i+1)%3 for i in range(width)]))
        for length in (1,2,3,127,128,129,130,255,256,257):
            add(f'format-{fmt}-repeat-{length}',fmt,length,1,pattern([0]*length))
            add(f'format-{fmt}-raw-{length}',fmt,length,1,pattern([i%3 for i in range(length)]))
        for name,values in [('aba',[0,1,0]),('abbc',[0,1,1,2]),('aab',[0,0,1]),('abb',[0,1,1]),('mixed',[0,1,2,2,2,0,1,0,1,1,2])]:
            add(f'format-{fmt}-{name}',fmt,len(values),1,pattern(values))
        add(f'format-{fmt}-identical-rows',fmt,3,2,pattern([0]*6))
        add(f'format-{fmt}-orientation',fmt,3,3,pattern([0,1,2,2,2,0,0,0,1]))
        for name,width,height in [('axis-row',4096,1),('axis-column',1,4096),('full-traversal',256,129)]:
            add(f'format-{fmt}-{name}',fmt,width,height,pattern([i%3 for i in range(width*height)]))
        mixed=[]
        while len(mixed)<514:
            length=rng.randrange(1,141)
            mixed.extend([rng.randrange(3)]*length if rng.randrange(2) else [rng.randrange(3) for _ in range(length)])
        add(f'format-{fmt}-seeded-mixed',fmt,257,2,pattern(mixed[:514]))
    for fmt in (2,7):
        values=[0,1,127,128,254,255,255,254,128,127,1,0]
        add(f'format-{fmt}-alpha-only',fmt,6,2,b''.join(bytes([17,a] if fmt==2 else [17,63,201,a]) for a in values))
        add(f'format-{fmt}-alpha-aba',fmt,3,1,b''.join(bytes([17,a] if fmt==2 else [17,63,201,a]) for a in [0,255,0]))
    for fmt in (3,5,6):
        words=[0,1,2,15,16,31,32,63,64,255,256,1023,1024,2047,2048,32767,32768,65534,65535,0xF801,0x003E]
        add(f'packed-{fmt}-boundaries',fmt,7,3,struct.pack('<21H',*words))
        add(f'packed-{fmt}-seeded',fmt,7,5,struct.pack('<35H',*[rng.randrange(65536) for _ in range(35)]))
    add('packed-5-alpha-only',5,6,1,struct.pack('<6H',*[0x8420|a for a in (0,1,0,0,1,1)]))
    add('packed-6-alpha-only',6,16,1,struct.pack('<16H',*[0x8420|a for a in range(16)]))
    words=r32_words()
    add('r32-truncation-boundaries',8,len(words),1,struct.pack('<'+'I'*len(words),*words))
    words=[0,0x80000000,1,2,0x007FFFFF,0x00800000,0x3F000000,0x3F000001,0x3F000002]
    add('r32-expanded-run-collapse',8,len(words),1,struct.pack('<9I',*words))
    add('rgba-alpha-zero-hidden-rgb',7,3,2,bytes(v for rgb in [(1,2,3),(255,127,0),(17,63,201),(128,254,1),(0,255,0),(255,0,255)] for v in [*rgb,0]))
    # Encoded file exceeds the generic raster loader's independent 1 MiB cap.
    add('rgba-large-raw',7,513,513,b''.join(bytes((i%251,(i//251)%251,(i//63001)%251,255)) for i in range(513*513)))
    if len({c['id'] for c in result})!=len(result): raise ValueError('Duplicate fixture ID')
    return result


def metadata(case):
    return dict({key:case[key] for key in ('id','format','width','height')}, decoded_format=decoded_format(case['format']))


def channels(fmt):
    return {1:1,2:2,4:3}.get(fmt,4)


def decoded_format(fmt):
    return fmt if fmt in (1,2,4) else 7


def decode_tga(data, case):
    """Strict independent export-layout decoder; no packet-selection algorithm."""
    if type(data) is not bytes: raise ValueError('TGA data must be bytes')
    width,height,fmt=(case[k] for k in ('width','height','format'))
    if any(type(v) is not int for v in (width,height,fmt)) or not 1<=width<=4096 or not 1<=height<=4096 or fmt not in BPP: raise ValueError('Invalid checked TGA dimensions/format')
    comp=channels(fmt)
    header=bytes([0,0,11 if comp<3 else 10,0,0,0,0,0,0,0,0,0])+struct.pack('<HH',width,height)+bytes([comp*8,8 if comp in (2,4) else 0])
    if data[:18]!=header: raise ValueError('TGA header/shape differs')
    position=18;rows=[]
    for _ in range(height):
        row=[]
        while len(row)<width:
            if position>=len(data): raise ValueError('Missing TGA packet')
            code=data[position];position+=1;count=(code&127)+1
            if len(row)+count>width: raise ValueError('TGA packet crosses row')
            samples=1 if code&128 else count
            needed=samples*comp
            if position+needed>len(data): raise ValueError('Short TGA packet payload')
            values=[]
            for _ in range(samples):
                value=data[position:position+comp];position+=comp
                if comp==1: rgba=(*value,*value,*value,255)
                elif comp==2: rgba=(value[0],value[0],value[0],value[1])
                else: rgba=(value[2],value[1],value[0],value[3] if comp==4 else 255)
                values.append(rgba)
            row.extend(values*count if code&128 else values)
        rows.append(row)
    if position!=len(data): raise ValueError('Extra TGA bytes after pixels')
    return [v for row in reversed(rows) for pixel in row for v in pixel]


def check_reference(cases, rows, work):
    """Exact packet controls independently pin the surprising native raw scan."""
    by_id={r['id']:bytes(r['encoded']) for r in rows}
    for fmt in BPP:
        comp=channels(fmt)
        if by_id[f'format-{fmt}-aba'][18]!=0 or by_id[f'format-{fmt}-aba'][19+comp]!=1: raise ProbeFailure('Native ABA packet rule differs')
        if by_id[f'format-{fmt}-abbc'][18]!=3: raise ProbeFailure('Native ABBC packet rule differs')
        if by_id[f'format-{fmt}-identical-rows'][18]!=130 or by_id[f'format-{fmt}-identical-rows'][19+comp]!=130: raise ProbeFailure('Native row reset differs')
    collapse=by_id['r32-expanded-run-collapse']
    if len(collapse)!=28 or collapse[18]!=133 or collapse[23]!=130: raise ProbeFailure('Native expanded R32 run collapse differs')


CODEC = codec_exports.Raster('tga', fixtures, decode_tga, metadata, check_reference)


def main(argv=None):
    codec_exports.main(CODEC, __doc__, argv)


if __name__ == '__main__':
    main()
