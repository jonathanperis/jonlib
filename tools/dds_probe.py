#!/usr/bin/env python3
"""Compare LoadImageFromMemory(".dds") with Surface.decode_image on DDS files.

Uncompressed single-level files (R5G6B5, A1R5G5B5, A4R4G4B4, 24-bit and
32-bit) must match raylib's format, dimensions and stored bytes exactly.
Headers raylib rejects must be InvalidImageHeader. Files raylib loads as
compressed DXT data or mipmap chains are UnsupportedFormat in Jonlib (asserted
natively first), and files shorter than their payload, which raylib reads past,
are TruncatedImageData: explicit Jonlib contracts, not native equivalence.
File cases compare LoadImage with Surface.load_image on .dds/.DDS names and the
explicit Surface.load_dds on another suffix (CPU and JavaScript lanes).
"""
import hashlib
import json
import random
import struct

from byte_probe import C_IMAGE, SURFACE_EMITTER
import probekit
from probekit import ROOT, ProbeFailure

DDPF_RGB, DDPF_RGBA = 0x40, 0x41
LAYOUTS = {  # name: (bits, flags, alpha mask, bytes per pixel, raylib format)
    'r5g6b5': (16, DDPF_RGB, 0, 2, 3),
    'a1r5g5b5': (16, DDPF_RGBA, 0x8000, 2, 5),
    'a4r4g4b4': (16, DDPF_RGBA, 0xF000, 2, 6),
    'rgb24': (24, DDPF_RGB, 0, 3, 4),
    'bgra32': (32, DDPF_RGBA, 0xFF000000, 4, 7),
}
SIZES = ((1, 1), (3, 2), (4, 4), (5, 3), (16, 1), (2, 9))


def dds(width, height, bits, flags, alpha, payload, mipmaps=0, fourcc=0, magic=b'DDS '):
    words = [124, 0x1007, height, width, 0, 0, mipmaps] + [0] * 11
    words += [32, flags, fourcc, bits, 0, 0, 0, alpha, 0x1000, 0, 0, 0, 0]
    return list(magic + struct.pack('<31I', *words) + bytes(payload))


def fixtures():
    rng = random.Random(0xDD5)
    cases = []
    for name, (bits, flags, alpha, bpp, fmt) in LAYOUTS.items():
        for width, height in SIZES:
            data = [rng.randrange(256) for _ in range(width * height * bpp)]
            cases.append(dict(id=f'{name}-{width}x{height}', kind='decoded', format=fmt,
                              bytes=dds(width, height, bits, flags, alpha, data)))
        # Trailing bytes after the payload are ignored.
        cases.append(dict(id=f'{name}-trailing', kind='decoded', format=fmt,
                          bytes=dds(2, 2, bits, flags, alpha, [rng.randrange(256) for _ in range(4 * bpp + 7)])))
    payload = [rng.randrange(256) for _ in range(64)]
    for name, args in (
        ('bad-magic', dict(bits=32, flags=DDPF_RGBA, alpha=0, magic=b'DDS!')),
        ('rgba-mask-00ff', dict(bits=16, flags=DDPF_RGBA, alpha=0x00FF)),
        ('rgb-flags-for-32bit', dict(bits=32, flags=DDPF_RGB, alpha=0)),
        ('rgba-flags-for-24bit', dict(bits=24, flags=DDPF_RGBA, alpha=0)),
        ('bit-count-8', dict(bits=8, flags=DDPF_RGB, alpha=0)),
        ('fourcc-with-16bit', dict(bits=16, flags=0x04, alpha=0, fourcc=0x31545844)),
    ):
        cases.append(dict(id=name, kind='invalid', bytes=dds(2, 2, payload=payload, **args)))
    cases.append(dict(id='dxt1-rgb', kind='compressed', bytes=dds(4, 4, 0, 0x04, 0, payload[:8], fourcc=0x31545844)))
    cases.append(dict(id='dxt5', kind='compressed', bytes=dds(4, 4, 0, 0x05, 0, payload[:16], fourcc=0x35545844)))
    cases.append(dict(id='mipmapped-rgba', kind='mipmapped', bytes=dds(4, 4, 32, DDPF_RGBA, 0xFF000000, payload, mipmaps=3)))
    for name, (bits, flags, alpha, bpp, _) in LAYOUTS.items():
        cases.append(dict(id=f'{name}-truncated', kind='truncated', native=False,
                          bytes=dds(3, 3, bits, flags, alpha, [7] * (9 * bpp - 1))))
    cases.append(dict(id='short-header', kind='truncated', native=False, bytes=list(b'DDS ') + [0] * 40))
    for name, suffix, loader in (('file-lower', '.dds', 'load_image'), ('file-upper', '.DDS', 'load_image'), ('file-explicit', '.bin', 'load_dds')):
        bits, flags, alpha, bpp, fmt = LAYOUTS['bgra32']
        cases.append(dict(id=name, kind='decoded', format=fmt, suffix=suffix, loader=loader,
                          bytes=dds(3, 2, bits, flags, alpha, [rng.randrange(256) for _ in range(6 * bpp)])))
    return cases


EXPECTED_ERROR = {'invalid': 'header', 'compressed': 'unsupported', 'mipmapped': 'unsupported', 'truncated': 'truncated'}


def file_path(probe, case, suffix):
    path = probe.work / (case['id'] + suffix)
    path.write_bytes(bytes(case['bytes']))
    return json.dumps(str(path.relative_to(ROOT)))


def native(probe, cases):
    lines = ['#include "raylib.h"', '#include <stdio.h>', C_IMAGE,
             'static void loaded(Image im){if(!im.data){puts("null");return;}'
             'if(im.mipmaps!=1||im.format>=PIXELFORMAT_COMPRESSED_DXT1_RGB){printf("{\\"format\\":%d,\\"mipmaps\\":%d}\\n",im.format,im.mipmaps);UnloadImage(im);return;}'
             'image(im);UnloadImage(im);}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for i, case in enumerate(cases):
        if 'suffix' in case:
            # raylib loads DDS files by suffix: the explicit Jonlib loader's
            # .bin file is compared with LoadImage on a .dds copy.
            file_path(probe, case, case['suffix'])
            lines.append(f'loaded(LoadImage({file_path(probe, case, ".dds" if case["loader"] == "load_dds" else case["suffix"])}));')
        elif case.get('native', True):
            lines.append(f'{{static const unsigned char d[]={{{",".join(map(str, case["bytes"]))}}};loaded(LoadImageFromMemory(".dds",d,sizeof d));}}')
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n')


PROGRAM = '''import Base
import ../../jonlib.bend as J
''' + SURFACE_EMITTER + '''def error.name(error: J.Surface.Error) -> String:
  match error:
    case J.InvalidImageHeader{}: "header"
    case J.UnsupportedFormat{}: "unsupported"
    case J.TruncatedImageData{}: "truncated"
    case J.UnsupportedImageSize{}: "size"
    case _: "other"
def decoded(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("[\\"error\\", \\"" ++ error.name(error) ++ "\\"]")
    case Done{surface}: exported(J.Surface.export(surface))
def file_decoded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("[\\"error\\", \\"file\\"]")
    case Done{surface}: exported(J.Surface.export(surface))
'''


def render(work):
    def emit(selected, gpu):
        body = PROGRAM + 'def main() -> IO(Unit):\n  do IO<Unit>:\n'
        for case in selected:
            if 'suffix' in case:
                path = json.dumps(str((work / (case['id'] + case['suffix'])).relative_to(ROOT)))
                body += (f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.{case["loader"]}({path}), file_decoded)\n')
            else:
                body += f'    decoded(J.Surface.decode_image(".dds", [{",".join(map(str, case["bytes"]))}]))\n'
        return body
    return emit


def parse(text):
    """Byte results as lists; error markers as ['error', kind]."""
    rows, chunk = [], []
    for line in text.splitlines():
        value = json.loads(line)
        if isinstance(value, list) and value[:1] == ['error']:
            rows.append(value)
        elif value == 'end':
            rows.append(chunk)
            chunk = []
        elif isinstance(value, list):
            chunk.extend(value)
        else:
            raise ValueError(f'unexpected candidate line {line!r}')
    return rows


def native_rows(text):
    """One row per native call: decoded bytes, None for no data, or a dict
    describing compressed/multi-level data."""
    rows, chunk = [], []
    for line in text.splitlines():
        value = json.loads(line)
        if value is None or isinstance(value, dict):
            rows.append(value)
        elif value == 'end':
            rows.append(chunk)
            chunk = []
        else:
            chunk.extend(value)
    return rows


def main():
    probe = probekit.Probe('dds', probekit.arguments(__doc__))
    cases = fixtures()
    observed = iter(native_rows(native(probe, cases)))
    expected = []
    for case in cases:
        row = next(observed) if case.get('native', True) else None
        kind = case['kind']
        if kind == 'decoded':
            if not isinstance(row, list) or row[0] != case['format']:
                raise ProbeFailure(f'{case["id"]}: native did not decode format {case["format"]}: {str(row)[:80]}')
            expected.append(row)
            continue
        if kind == 'invalid' and row is not None:
            raise ProbeFailure(f'{case["id"]}: native loaded a header the profile treats as invalid')
        if kind == 'compressed' and not (isinstance(row, dict) and row['format'] >= 14):
            raise ProbeFailure(f'{case["id"]}: native did not load compressed data')
        if kind == 'mipmapped' and not (isinstance(row, dict) and row['mipmaps'] > 1):
            raise ProbeFailure(f'{case["id"]}: native did not load a mipmap chain')
        expected.append(['error', EXPECTED_ERROR[kind]])
    lanes = probe.candidates(render(probe.work), cases, batch=64, parse=lambda text, selected: parse(text))
    probe.compare(expected, lanes, describe=lambda i: cases[i]['id'])
    probe.finish(cases=len(cases), decoded=sum(c['kind'] == 'decoded' for c in cases),
                 rejections=sum(c['kind'] != 'decoded' for c in cases),
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest())


if __name__ == '__main__':
    main()
