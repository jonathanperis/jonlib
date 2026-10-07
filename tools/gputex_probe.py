#!/usr/bin/env python3
"""Compare raylib's configuration-gated KTX, PKM, PVR and ASTC loaders with Image.Stored.

raylib is built with SUPPORT_FILEFORMAT_KTX/PKM/PVR/ASTC=ON. Single-level
ETC1/ETC2/ETC2 EAC (KTX, PKM), PVR v3 uncompressed and PVRTC, and ASTC 4x4/8x8
files decode to the format, dimensions and GetPixelDataSize bytes native
LoadImageFromMemory returns. Jonlib contracts, asserted natively where raylib's
result is defined: multi-level KTX/PVR files (raylib keeps only the first
level while reporting all) are UnsupportedFormat; unknown formats, which raylib
returns as format 0, InvalidImageHeader; levels whose copied bytes are fewer
than GetPixelDataSize (below one block) UnsupportedImageSize; ASTC blocks other
than 8 or 2 bits per pixel UnsupportedFormat; short files TruncatedImageData.
.ktx/.PVR file loading by suffix is compared too. CPU/JS lanes.
"""
import hashlib
import json
import random
import struct

from byte_probe import C_EMITTER
from stored_probe import PROGRAM, render as stored_render
import probekit
from probekit import ROOT, ProbeFailure

OPTIONS = ('SUPPORT_FILEFORMAT_KTX=ON', 'SUPPORT_FILEFORMAT_PKM=ON', 'SUPPORT_FILEFORMAT_PVR=ON', 'SUPPORT_FILEFORMAT_ASTC=ON')
BITS = {1: 8, 2: 16, 3: 16, 4: 24, 5: 16, 6: 16, 7: 32, 18: 4, 19: 4, 20: 8, 21: 4, 22: 4, 23: 8, 24: 2}


def level_size(width, height, fmt):
    if width < 4 and height < 4 and fmt in (14, 15):
        return 8
    if width < 4 and height < 4 and 16 <= fmt < 24:
        return 16
    return width * height * BITS[fmt] // 8


def pkm(code, width, height, payload, version=b'10'):
    return list(b'PKM ' + version + struct.pack('>HHHHH', code, width, height, width, height) + bytes(payload))


KTX_ID = bytes([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A])


def ktx(internal, width, height, payload, *, image_size=None, mipmaps=1, key_values=b''):
    header = KTX_ID + struct.pack('<13I', 0x04030201, 0, 1, 0, internal, 0, width, height, 0, 0, 1, mipmaps, len(key_values))
    return list(header + key_values + struct.pack('<I', len(payload) if image_size is None else image_size) + bytes(payload))


def pvr(channels, depths, width, height, payload, *, mipmaps=1, metadata=b''):
    header = b'PVR\x03' + struct.pack('<I', 0) + bytes(channels) + bytes(depths)
    header += struct.pack('<8I', 0, 0, height, width, 1, 1, 1, mipmaps) + struct.pack('<I', len(metadata))
    return list(header + metadata + bytes(payload))


def astc(block_x, block_y, width, height, payload):
    size = lambda v: bytes([v & 255, v >> 8 & 255, v >> 16 & 255])
    return list(bytes([0x13, 0xAB, 0xA1, 0x5C, block_x, block_y, 1]) + size(width) + size(height) + size(1) + bytes(payload))


def fixtures():
    rng = random.Random(0x6E7)
    noise = lambda n: [rng.randrange(256) for _ in range(n)]
    cases = []

    def loaded(name, token, data, fmt, width, height, payload, copied, native=True):
        size = level_size(width, height, fmt)
        cases.append(dict(id=name, token=token, bytes=data, kind='loaded', native=native,
                          expected=[fmt, width, height, 1, payload[:size]], prefix=size))

    def refused(name, token, data, error, check=None):
        cases.append(dict(id=name, token=token, bytes=data, kind='refused', expected=['error', error], check=check))

    for code, fmt in ((0, 18), (1, 19), (3, 20)):
        for width, height in ((4, 4), (8, 4), (16, 8)):
            copied = width * height * (8 if code == 3 else 4) // 8
            payload = noise(copied + 5)
            loaded(f'pkm-{fmt}-{width}x{height}', '.pkm', pkm(code, width, height, payload), fmt, width, height, payload, copied)
    payload = noise(32)
    loaded('pkm-v20', '.PKM', pkm(1, 8, 8, payload, b'20'), 19, 8, 8, payload, 32)
    refused('pkm-small', '.pkm', pkm(0, 2, 2, noise(8)), 'size', check='loaded')
    refused('pkm-format-2', '.pkm', pkm(2, 4, 4, noise(8)), 'header', check='format0')
    refused('pkm-truncated', '.pkm', pkm(0, 8, 8, noise(31)), 'truncated')
    for internal, fmt in ((0x8D64, 18), (0x9274, 19), (0x9278, 20)):
        for width, height in ((4, 4), (8, 8)):
            payload = noise(level_size(width, height, fmt))
            loaded(f'ktx-{fmt}-{width}x{height}', '.ktx', ktx(internal, width, height, payload), fmt, width, height, payload, len(payload))
    payload = noise(48)
    loaded('ktx-key-values', '.KTX', ktx(0x8D64, 8, 8, payload, key_values=bytes(noise(8))), 18, 8, 8, payload, 48)
    loaded('ktx-larger-image', '.ktx', ktx(0x9278, 4, 4, payload), 20, 4, 4, payload, 48)
    refused('ktx-chain', '.ktx', ktx(0x8D64, 8, 8, noise(32), mipmaps=2), 'unsupported', check='loaded')
    refused('ktx-internal', '.ktx', ktx(0x1908, 4, 4, noise(16)), 'header', check='format0')
    refused('ktx-short-image', '.ktx', ktx(0x9278, 4, 4, noise(8)), 'size', check='loaded')
    refused('ktx-truncated', '.ktx', ktx(0x8D64, 8, 8, noise(20), image_size=32), 'truncated')
    for channels, depths, fmt in ((b'l\0\0\0', b'\x08\0\0\0', 1), (b'la\0\0', b'\x08\x08\0\0', 2), (b'rgba', b'\x05\x05\x05\x01', 5),
                                  (b'rgba', b'\x04\x04\x04\x04', 6), (b'rgba', b'\x08\x08\x08\x08', 7), (b'rgb\0', b'\x05\x06\x05\0', 3),
                                  (b'rgb\0', b'\x08\x08\x08\0', 4), (b'\x02\0\0\0', b'\0\0\0\0', 21), (b'\x03\0\0\0', b'\0\0\0\0', 22)):
        for width, height in ((4, 4), (6, 4)):
            payload = noise(level_size(width, height, fmt) + 3)
            loaded(f'pvr-{fmt}-{width}x{height}', '.pvr', pvr(channels, depths, width, height, payload), fmt, width, height, payload,
                   width * height * BITS[fmt] // 8)
    payload = noise(64)
    loaded('pvr-metadata', '.PVR', pvr(b'rgba', b'\x08\x08\x08\x08', 4, 4, payload, metadata=bytes(noise(12))), 7, 4, 4, payload, 64)
    refused('pvr-chain', '.pvr', pvr(b'rgba', b'\x08\x08\x08\x08', 4, 4, noise(84), mipmaps=3), 'unsupported', check='loaded')
    refused('pvr-pvrtc-small', '.pvr', pvr(b'\x02\0\0\0', b'\0\0\0\0', 2, 2, noise(16)), 'size', check='loaded')
    refused('pvr-channels', '.pvr', pvr(b'rgba', b'\x06\x06\x06\x06', 4, 4, noise(64)), 'header')
    refused('pvr-v2', '.pvr', [52] + noise(60), 'header', check='null')
    for (bx, by), fmt in (((4, 4), 23), ((8, 8), 24), ((2, 8), 23)):
        for width, height in ((8, 8), (12, 12)):
            copied = width * height * BITS[fmt] // 8
            payload = noise(copied + 2)
            loaded(f'astc-{bx}x{by}-{width}x{height}', '.astc', astc(bx, by, width, height, payload), fmt, width, height, payload, copied)
    refused('astc-5x5', '.ASTC', astc(5, 5, 10, 10, noise(64)), 'unsupported', check='null')
    refused('astc-small', '.astc', astc(4, 4, 3, 3, noise(16)), 'size', check='loaded')
    refused('astc-zero-block', '.astc', astc(0, 4, 8, 8, noise(64)), 'header')
    refused('astc-magic', '.astc', [0x13, 0xAB, 0xA1, 0x5D] + noise(40), 'header', check='null')
    return cases


FILES = {'.build/gputex-probe/file.ktx': 'ktx-18-8x8', '.build/gputex-probe/FILE.PVR': 'pvr-7-4x4'}


def native(probe, cases):
    lines = ['#include "raylib.h"', '#include <stdio.h>', C_EMITTER,
             'static void loaded(Image im,int prefix){if(!im.data){puts("null");return;}'
             'printf("[%d,%d,%d,%d]\\n",im.format,im.width,im.height,im.mipmaps);unsigned char *p=im.data;'
             'for(int i=0;i<prefix;i++)byte(p[i]);end();UnloadImage(im);}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        data = f'static unsigned char d[]={{{",".join(map(str, case["bytes"]))}}};'  # writable: the PKM loader swaps its header in place
        if case['kind'] == 'loaded' and case['native']:
            lines.append(f'{{{data}loaded(LoadImageFromMemory("{case["token"]}",d,sizeof d),{case["prefix"]});}}')
        elif case['kind'] == 'refused' and case['check']:
            lines.append(f'{{{data}Image im=LoadImageFromMemory("{case["token"]}",d,sizeof d);'
                         'printf("[%d,%d,%d]\\n",im.data!=NULL,im.format,im.mipmaps);if(im.data)UnloadImage(im);}')
    for path, name in FILES.items():
        (ROOT / path).parent.mkdir(parents=True, exist_ok=True)
        (ROOT / path).write_bytes(bytes(next(c for c in cases if c['id'] == name)['bytes']))
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n')


def check_native(cases, text):
    rows = iter(text.splitlines())
    for case in cases:
        if case['kind'] == 'loaded' and case['native']:
            meta = json.loads(next(rows))
            values = []
            for line in rows:
                value = json.loads(line)
                if value == 'end':
                    break
                values += value
            if meta != case['expected'][:4] or values != case['expected'][4]:
                raise ProbeFailure(f'gputex: native {case["id"]} differs: {meta}')
        elif case['kind'] == 'refused' and case['check']:
            has_data, fmt, mipmaps = json.loads(next(rows))
            check = case['check']
            if (check == 'null' and has_data) or (check == 'format0' and (not has_data or fmt != 0)) or (check == 'loaded' and not has_data):
                raise ProbeFailure(f'gputex: native {case["id"]} does not show the documented behavior: {has_data, fmt, mipmaps}')


def render(selected, gpu):
    body = PROGRAM
    for case in selected:
        if 'path' in case:
            body += f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Stored>, Unit, J.Image.Stored.load_image({json.dumps(case["path"])}), file_stored)\n'
        else:
            body += f'    Unit <- stored(J.Image.Stored.decode_image("{case["token"]}", [{",".join(map(str, case["bytes"]))}]))\n'
    return body + '    IO.print("\\"done\\"")\n'


def parse(text, selected):
    rows = [json.loads(line) for line in text.splitlines()]
    if rows[-1:] != ['done']:
        raise ValueError('gputex: candidate output did not finish')
    return rows[:-1]


def main():
    probe = probekit.Probe('gputex', probekit.arguments(__doc__), raylib_options=OPTIONS)
    cases = fixtures()
    check_native(cases, native(probe, cases))
    actions = cases + [dict(id=path, path=path) for path in FILES]
    expected = [case['expected'] for case in cases] + [next(c for c in cases if c['id'] == name)['expected'] for name in FILES.values()]
    lanes = probe.candidates(render, actions, batch=48, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: actions[i]['id'])
    probe.finish(cases=len(cases), loaded=sum(c['kind'] == 'loaded' for c in cases), refused=sum(c['kind'] == 'refused' for c in cases),
                 files=len(FILES), inputs_sha256=hashlib.sha256(json.dumps([c['bytes'] for c in cases]).encode()).hexdigest())


if __name__ == '__main__':
    main()
