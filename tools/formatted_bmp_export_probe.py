#!/usr/bin/env python3
"""Exact checked formats 1..8 BMP file bytes, independent decoding and typed IO.

Uses actual pinned ExportImage; never ExportImageToMemory or ImageFormat to
prepare source pixels. CPU-1/CPU-2/JavaScript are separate exact lanes. No GPU
claim. Native error-return parity is deliberately not claimed for short writes.
"""
import random
import struct

import formatted_export
from formatted_export import BPP
from image_format_probe import r32_words
from probekit import ProbeFailure


def fixtures():
    rng = random.Random(0xB481)
    result = []
    def add(name, fmt, width, height, data):
        if len(data) != width*height*BPP[fmt]: raise ValueError('Fixture byte shape')
        result.append(dict(id=name, format=fmt, width=width, height=height, data=list(data)))
    def pattern(fmt, count):
        if fmt == 8:
            values = [0, 0x80000000, 1, 0x007fffff, 0x00800000, 0x3f000000, 0x3f7fffff, 0x3f800000]
            return b''.join(struct.pack('<I', values[i % len(values)]) for i in range(count))
        values = [0, 255, 1, 127, 128, 254, 17, 63, 201, 2, 253, 37, 239]
        return bytes(values[i % len(values)] for i in range(count*BPP[fmt]))
    for fmt in BPP:
        for width in range(1, 5): add(f'format-{fmt}-padding-{width}', fmt, width, 2, pattern(fmt, width*2))
        for name, width, height in [('thin',1,31), ('axis-row',4096,1), ('axis-column',1,4096), ('full-traversal',256,129)]:
            add(f'format-{fmt}-{name}', fmt, width, height, pattern(fmt,width*height))
    for alpha in [0,1,127,128,254,255]:
        add(f'gray-alpha-{alpha}',2,3,2,bytes(v for gray in [0,17,127,128,254,255] for v in [gray,alpha]))
    for fmt in [3,5,6]:
        words = [0,1,2,15,16,31,32,63,64,255,256,1023,1024,2047,2048,32767,32768,65534,65535,0xF801,0x003E]
        add(f'packed-{fmt}-boundaries',fmt,7,3,struct.pack('<'+'H'*len(words),*words))
        words = [rng.randrange(65536) for _ in range(35)]
        add(f'packed-{fmt}-seeded',fmt,7,5,struct.pack('<35H',*words))
    words = r32_words()
    add('r32-truncation-boundaries',8,len(words),1,struct.pack('<'+'I'*len(words),*words))
    add('rgba-alpha-zero',7,3,2,bytes(v for rgb in [(1,2,3),(255,127,0),(17,63,201),(128,254,1),(0,255,0),(255,0,255)] for v in [*rgb,0]))
    if len({c['id'] for c in result}) != len(result): raise ValueError('Duplicate fixture ID')
    return result


def metadata(case):
    return {key:case[key] for key in ('id','format','width','height')}


def decode_bmp(data, case):
    """Independent, strict decoder for the two native-export layouts only."""
    if type(data) is not bytes: raise ValueError('BMP data must be bytes')
    width,height,fmt = (case[k] for k in ('width','height','format'))
    direct = fmt in (1,2,4)
    offset,depth = (54,24) if direct else (122,32)
    stride = (width*3+3)&~3 if direct else width*4
    size = offset+stride*height
    fields = [size,0,offset,40 if direct else 108,width,height,(depth<<16)|1,0 if direct else 3,0,0,0,0,0]
    if not direct: fields += [0xff0000,0xff00,0xff,0xff000000]+[0]*13
    header = b'BM'+struct.pack('<'+'I'*len(fields),*fields)
    if len(data)!=size or len(header)!=offset or data[:offset]!=header: raise ValueError('BMP header/shape differs')
    pixels = bytearray()
    for y in range(height):
        row = data[offset+(height-1-y)*stride:offset+(height-y)*stride]
        if direct and any(row[width*3:]): raise ValueError('Nonzero BMP row padding')
        for x in range(width):
            at = x*(depth//8)
            b,g,r = row[at:at+3]
            pixels.extend((r,g,b,255 if direct else row[at+3]))
    return list(pixels)


def check_reference(cases, rows, work):
    # Gray+alpha is written as 24-bit BMP: every alpha variation encodes identically.
    alpha_rows = [r['encoded'] for r in rows if r['id'].startswith('gray-alpha-')]
    if len(alpha_rows)!=6 or any(r!=alpha_rows[0] for r in alpha_rows): raise ProbeFailure('Native gray-alpha discard differs')


CODEC = formatted_export.Raster('bmp', fixtures, decode_bmp, metadata, check_reference)


def main(argv=None):
    formatted_export.main(CODEC, __doc__, argv)


if __name__ == '__main__':
    main()
