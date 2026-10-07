#!/usr/bin/env python3
"""Compare raylib's compressed and multi-level DDS images with Image.Stored.

Fixtures are DDS files with DXT1 (RGB and RGBA), DXT3 and DXT5 blocks and
uncompressed mipmap chains, including sizes below one 4x4 block and
non-square chains. The expected Image.Stored (format, dimensions, level
count and the complete level chain, with raylib's channel reordering) is
derived from the file; native raylib must agree on the metadata and on every
byte of its own data buffer, which holds only pitch (+pitch/3) or size
(+size/3) bytes of a chain. Files without every level are TruncatedImageData,
other FourCC codes (raylib: format 0) InvalidImageHeader and chains of more
than 64 levels UnsupportedImageSize: Jonlib contracts, asserted natively where
raylib's result is defined. ImageCopy, ExportImage(.raw) and
ExportImageAsCode on a compressed image, the uncompressed levels as Surfaces,
a QOI file (one Surface level) and file loading by suffix are compared too. CPU/JS lanes.
"""
import hashlib
import json
import random
import struct

from byte_probe import C_EMITTER
from loaders_probe import PIXELS, qoi
import probekit
from probekit import ROOT, ProbeFailure

DXT1, DXT3, DXT5, DX10 = 0x31545844, 0x33545844, 0x35545844, 0x30315844
UNCOMPRESSED = {  # format: (bits, flags, alpha mask)
    3: (16, 0x40, 0), 5: (16, 0x41, 0x8000), 6: (16, 0x41, 0xF000), 4: (24, 0x40, 0), 7: (32, 0x41, 0xFF000000)}
BITS = {3: 16, 5: 16, 6: 16, 4: 24, 7: 32, 14: 4, 15: 4, 16: 8, 17: 8}


def level_size(width, height, fmt):
    if width < 4 and height < 4 and fmt in (14, 15):
        return 8
    if width < 4 and height < 4 and fmt in (16, 17):
        return 16
    return width * height * BITS[fmt] // 8


def chain(width, height, fmt, count):
    sizes = []
    for _ in range(count):
        sizes.append((width, height, level_size(width, height, fmt)))
        width, height = max(width // 2, 1), max(height // 2, 1)
    return sizes


def reorder(fmt, data):
    data = list(data)
    if fmt == 7:
        for i in range(0, len(data) - 3, 4):
            data[i], data[i + 2] = data[i + 2], data[i]
    elif fmt in (5, 6):
        shift = 1 if fmt == 5 else 4
        for i in range(0, len(data) - 1, 2):
            value = data[i] | data[i + 1] << 8
            value = ((value << shift) & 0xFFFF) + (value >> (16 - shift))
            data[i], data[i + 1] = value & 0xFF, value >> 8
    return data


def dds(width, height, *, fmt=None, fourcc=0, flags=0x04, mipmaps=0, pitch=0, payload=()):
    if fmt in UNCOMPRESSED:
        bits, flags, alpha = UNCOMPRESSED[fmt]
    else:
        bits, alpha = 0, 0
    words = [124, 0x1007, height, width, pitch, 0, mipmaps] + [0] * 11
    words += [32, flags, fourcc, bits, 0, 0, 0, alpha, 0x1000, 0, 0, 0, 0]
    return list(b'DDS ' + struct.pack('<31I', *words) + bytes(payload))


def raylib_size(width, height, fmt, mipmaps, pitch):
    size = pitch if fmt >= 14 else width * height * BITS[fmt] // 8
    return size + size // 3 if mipmaps > 1 else size


def fixtures():
    rng = random.Random(0x5704ED)
    noise = lambda n: [rng.randrange(256) for _ in range(n)]
    cases = []

    def stored(name, width, height, fmt, count, *, fourcc=0, flags=0x04, pitch=None, extra=7, native=True):
        sizes = chain(width, height, fmt, max(count, 1))
        total = sum(size for *_, size in sizes)
        pitch = level_size(width, height, fmt) if pitch is None else pitch
        payload = noise(total + extra)
        cases.append(dict(id=name, kind='stored', bytes=dds(width, height, fmt=fmt, fourcc=fourcc, flags=flags, mipmaps=count, pitch=pitch, payload=payload),
                          expected=[fmt, width, height, max(count, 1), reorder(fmt, payload[:total])],
                          raylib=raylib_size(width, height, fmt, count, pitch), native=native))

    for fourcc, flags, fmt in ((DXT1, 0x04, 14), (DXT1, 0x05, 15), (DXT3, 0x04, 16), (DXT5, 0x05, 17)):
        for width, height in ((4, 4), (8, 4), (2, 2), (1, 1), (6, 5), (12, 8)):
            stored(f'{fmt}-{width}x{height}', width, height, fmt, 1, fourcc=fourcc, flags=flags)
        stored(f'{fmt}-pitch-larger', 8, 8, fmt, 1, fourcc=fourcc, flags=flags, pitch=level_size(8, 8, fmt) + 16)
        stored(f'{fmt}-chain-8x8', 8, 8, fmt, 4, fourcc=fourcc, flags=flags, pitch=level_size(8, 8, fmt))
        stored(f'{fmt}-chain-16x4', 16, 4, fmt, 5, fourcc=fourcc, flags=flags, pitch=level_size(16, 4, fmt))
    # raylib's buffer is shorter than the level: its later use reads past it.
    stored('14-pitch-smaller', 8, 8, 14, 1, fourcc=DXT1, pitch=8)
    for fmt in UNCOMPRESSED:
        stored(f'u{fmt}-chain-4x4', 4, 4, fmt, 3)
        stored(f'u{fmt}-chain-8x2', 8, 2, fmt, 4)
        stored(f'u{fmt}-chain-2-levels', 6, 3, fmt, 2)
    stored('u7-mipmaps-one', 4, 2, 7, 1)

    def refused(name, data, error, native_check=None):
        cases.append(dict(id=name, kind='refused', bytes=data, expected=['error', error], check=native_check))

    level = level_size(8, 8, 14)
    refused('dxt1-truncated', dds(8, 8, fourcc=DXT1, pitch=level, payload=noise(level - 1)), 'truncated')
    sizes = chain(8, 8, 17, 4)
    refused('dxt5-chain-truncated', dds(8, 8, fourcc=DXT5, flags=0x05, mipmaps=4, pitch=64, payload=noise(sum(s for *_, s in sizes) - 1)), 'truncated',
            native_check='loaded')
    refused('dx10-fourcc', dds(4, 4, fourcc=DX10, pitch=16, payload=noise(16)), 'header', native_check='format0')
    refused('chain-65-levels', dds(1, 1, fmt=7, mipmaps=65, payload=noise(400)), 'size')
    return cases


def c_bytes(data):
    return '(const unsigned char[]){' + ','.join(map(str, data)) + '}'


OPS_CASE = '17-chain-8x8'  # compressed chain for copy/raw/code
LEVELS_CASE = 'u7-chain-8x2'
CODE_PATH = '.build/stored-probe/stored.h'
RAW_PATH = '.build/stored-probe/stored.raw'
FILES = {'.build/stored-probe/lower.dds': '17-chain-8x8', '.build/stored-probe/UPPER.DDS': 'u5-chain-4x4'}


def native(probe, cases):
    by_id = {case['id']: case for case in cases}
    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <stdlib.h>', C_EMITTER,
             'static void stored(Image im,int prefix){if(!im.data){puts("null");return;}'
             'printf("[%d,%d,%d,%d]\\n",im.format,im.width,im.height,im.mipmaps);unsigned char *p=im.data;'
             'for(int i=0;i<prefix;i++)byte(p[i]);end();}',
             'static void file(const char *path){FILE *f=fopen(path,"rb");int c;while((c=fgetc(f))!=EOF)byte(c);fclose(f);end();}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        if case['kind'] == 'stored' and case['native']:
            fmt, width, height, count, data = case['expected']
            unit = {7: 4, 5: 2, 6: 2}.get(fmt, 1)
            prefix = min(len(data), case['raylib'] - case['raylib'] % unit)
            case['prefix'] = prefix
            lines.append(f'{{static const unsigned char d[]={{{",".join(map(str, case["bytes"]))}}};stored(LoadImageFromMemory(".dds",d,sizeof d),{prefix});}}')
        elif case['kind'] == 'refused' and case['check']:
            lines.append(f'{{static const unsigned char d[]={{{",".join(map(str, case["bytes"]))}}};Image im=LoadImageFromMemory(".dds",d,sizeof d);'
                         'printf("[%d,%d]\\n",im.data!=NULL,im.format);UnloadImage(im);}')
    ops = by_id[OPS_CASE]
    lines.append(f'{{static const unsigned char d[]={{{",".join(map(str, ops["bytes"]))}}};Image im=LoadImageFromMemory(".dds",d,sizeof d);'
                 f'Image copy=ImageCopy(im);stored(copy,{ops["prefix"]});UnloadImage(copy);'
                 f'ExportImage(im,"{RAW_PATH}");file("{RAW_PATH}");ExportImageAsCode(im,"{CODE_PATH}");file("{CODE_PATH}");UnloadImage(im);}}')
    for path in FILES:
        (ROOT / path).write_bytes(bytes(by_id[FILES[path]]['bytes']))
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n')


def check_native(cases, text):
    rows = iter(text.splitlines())

    def chunked():
        values = []
        for line in rows:
            value = json.loads(line)
            if value == 'end':
                return values
            values += value
        raise ProbeFailure('stored: unterminated native bytes')
    for case in cases:
        if case['kind'] == 'stored' and case['native']:
            meta = json.loads(next(rows))
            fmt, width, height, count, data = case['expected']
            if meta != [fmt, width, height, count] or chunked() != data[:case['prefix']]:
                raise ProbeFailure(f'stored: native {case["id"]} differs from the file-derived chain: {meta}')
        elif case['kind'] == 'refused' and case['check']:
            loaded, fmt = json.loads(next(rows))
            if case['check'] == 'format0' and (loaded, fmt) != (1, 0):
                raise ProbeFailure(f'stored: native {case["id"]} was expected to return data with format 0')
            if case['check'] == 'loaded' and not loaded:
                raise ProbeFailure(f'stored: native {case["id"]} was expected to load its buffer')
    ops = next(case for case in cases if case['id'] == OPS_CASE)
    meta = json.loads(next(rows))
    # ImageCopy copies the whole chain from raylib's shorter buffer: only its
    # defined prefix is comparable.
    if meta != ops['expected'][:4] or chunked() != ops['expected'][4][:ops['prefix']]:
        raise ProbeFailure('stored: native ImageCopy differs')
    raw, code = chunked(), chunked()
    return raw, code


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def bytes(values: +List<U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, values)
def codes(text: String) -> +List<U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{c, rest}: Con{Char.to_u32(c), codes(rest)}
def error.name(error: J.Surface.Error) -> String:
  match error:
    case J.InvalidImageHeader{}: "header"
    case J.UnsupportedFormat{}: "unsupported"
    case J.TruncatedImageData{}: "truncated"
    case J.UnsupportedImageSize{}: "size"
    case _: "other"
def entries(e: (U32 & U32) & ((U32 & U32) & +List<U32>)) -> IO(Unit):
  ((w, h), ((f, m), data)) = e
  IO.print("[" ++ U32.show(f) ++ ", " ++ U32.show(w) ++ ", " ++ U32.show(h) ++ ", " ++ U32.show(m) ++ ", " ++ bytes(data) ++ "]")
def stored(result: Result<&1, &1, J.Surface.Error, J.Image.Stored>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("[\\"error\\", \\"" ++ error.name(error) ++ "\\"]")
    case Done{image}: entries(J.Image.Stored.entries(image))
def file_stored(result: Result<&1, &1, J.Surface.IOError, J.Image.Stored>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{image}: entries(J.Image.Stored.entries(image))
def copied(pair: J.Image.Stored & J.Image.Stored) -> IO(Unit):
  (a, b) = pair
  do IO<Unit>:
    Unit <- entries(J.Image.Stored.entries(a))
    entries(J.Image.Stored.entries(b))
def copy(result: Result<&1, &1, J.Surface.Error, J.Image.Stored>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{image}: copied(J.Image.Stored.copy(image))
def raw(result: Result<&1, &1, J.Surface.Error, J.Image.Stored>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{image}: IO.print(bytes(J.Image.Stored.raw(image)))
def code.text(result: Result<&1, &1, J.Image.Stored & J.Surface.Error, String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{text}: IO.print(bytes(codes(text)))
def code(result: Result<&1, &1, J.Surface.Error, J.Image.Stored>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{image}: code.text(J.Image.Stored.to_code(image, "''' + CODE_PATH + '''"))
def level.one(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((w, h), (f, values)) = data
  IO.print("[" ++ U32.show(f) ++ ", " ++ U32.show(w) ++ ", " ++ U32.show(h) ++ ", " ++ List.show(~&1, ~U32, ~U32.show, values) ++ "]")
def level.list(levels: List<J.Surface>) -> IO(Unit):
  match levels:
    case Nil{}: IO.print("\\"end\\"")
    case Con{surface, rest}:
      do IO<Unit>:
        Unit <- level.one(J.Surface.export(surface))
        level.list(rest)
def level.chain(result: Result<&1, &1, J.Image.Stored & J.Surface.Error, J.Image.Mipmaps>) -> IO(Unit):
  match result:
    case Fail{Tuple{_, error}}: IO.print("[\\"error\\", \\"" ++ error.name(error) ++ "\\"]")
    case Done{J.Mipmaps{_, levels}}: level.list(levels)
def levels(result: Result<&1, &1, J.Surface.Error, J.Image.Stored>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{image}: level.chain(J.Image.Stored.levels(image))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for action in selected:
        kind, payload = action
        if kind == 'qoi':
            body += f'    Unit <- stored(J.Image.Stored.decode_image(".qoi", [{",".join(map(str, payload))}]))\n'
        elif kind == 'decode':
            body += f'    Unit <- stored(J.Image.Stored.decode_image(".dds", [{",".join(map(str, payload))}]))\n'
        elif kind == 'file':
            body += f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Image.Stored>, Unit, J.Image.Stored.load_image({json.dumps(payload)}), file_stored)\n'
        else:
            body += f'    Unit <- {kind}(J.Image.Stored.decode_image(".dds", [{",".join(map(str, payload))}]))\n'
    return body + '    IO.print("\\"done\\"")\n'


def parse(text, selected):
    """One row per action: decode/file/raw/code print one line, copy two, levels until "end"."""
    lines = iter(json.loads(line) for line in text.splitlines())
    rows = []
    for kind, _ in selected:
        if kind == 'copy':
            rows.append([next(lines), next(lines)])
        elif kind == 'levels':
            first = next(lines)
            if isinstance(first, list) and first[:1] == ['error']:
                rows.append(first)
                continue
            levels = []
            while first != 'end':
                levels.append(first)
                first = next(lines)
            rows.append(levels)
        else:
            rows.append(next(lines))
    if next(lines) != 'done':
        raise ValueError('stored: candidate output did not finish')
    return rows


def main():
    probe = probekit.Probe('stored', probekit.arguments(__doc__))
    cases = fixtures()
    raw, code = check_native(cases, native(probe, cases))
    by_id = {case['id']: case for case in cases}
    actions = [('decode', case['bytes']) for case in cases]
    expected = [case['expected'] for case in cases]
    ops = by_id[OPS_CASE]
    actions += [('copy', ops['bytes']), ('raw', ops['bytes']), ('code', ops['bytes'])]
    expected += [[ops['expected'], ops['expected']], raw, code]
    fmt, width, height, count, data = by_id[LEVELS_CASE]['expected']
    split, at = [], 0
    for w, h, size in chain(width, height, fmt, count):
        split.append([fmt, w, h, data[at:at + size]])
        at += size
    actions += [('levels', by_id[LEVELS_CASE]['bytes']), ('levels', ops['bytes'])]
    expected += [split, ['error', 'unsupported']]
    actions.append(('qoi', list(qoi(3, 2, PIXELS))))
    expected.append([7, 3, 2, 1, [v for pixel in PIXELS for v in pixel]])
    for path, name in FILES.items():
        actions.append(('file', path))
        expected.append(by_id[name]['expected'])
    lanes = probe.candidates(render, actions, batch=40, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: cases[i]['id'] if i < len(cases) else actions[i][0])
    probe.finish(cases=len(cases), stored=sum(case['kind'] == 'stored' for case in cases),
                 refused=sum(case['kind'] == 'refused' for case in cases), operations=len(actions) - len(cases),
                 inputs_sha256=hashlib.sha256(json.dumps([case['bytes'] for case in cases]).encode()).hexdigest())


if __name__ == '__main__':
    main()
