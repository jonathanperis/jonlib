#!/usr/bin/env python3
"""Compare raylib's JPEG loading (stb_image, SUPPORT_FILEFORMAT_JPG) with Jonlib.

raylib is built with SUPPORT_FILEFORMAT_JPG=ON. The committed fixtures in
tests/fixtures/jpeg (baseline and progressive; grayscale, 4:4:4, 4:2:0, 4:2:2,
4:4:0, 4:1:1, 3:1:1 and mixed sampling; restart intervals; quality 1 with
16-bit tables and 100; optimized and arithmetic coding; RGB and CMYK) and
variants derived here (YCCK, Adobe-RGB, truncated data, junk after EOI, a
missing EOI, fill bytes, a flipped entropy byte, removed Huffman tables, a bad
SOI, lossless and 12-bit frames) are decoded by native LoadImageFromMemory and
by Surface.load_image on .jpg files (the raster dispatch of
Surface.decode_image(".jpg")); format, dimensions and every stored byte match,
and failures fail on both sides. Jonlib contracts: a width above 4096 is
UnsupportedImageSize, and data stb would take from uninitialized planes (a
component without a complete scan, a progressive stream ending before EOI) is
InvalidImageStream. Surface.load_jpeg and .jpg/.JPEG names are compared
too. CPU/JS lanes.
"""
import hashlib
import json

from byte_probe import C_IMAGE, SURFACE_EMITTER
import probekit
from probekit import ROOT, ProbeFailure

FIXTURES = ROOT / 'tests/fixtures/jpeg'


def segments(data):
    """(marker, start, end) of each marker segment before SOS, after SOI."""
    found, at = [], 2
    while at + 4 <= len(data) and data[at] == 0xFF:
        marker = data[at + 1]
        length = data[at + 2] << 8 | data[at + 3]
        found.append((marker, at, at + 2 + length))
        if marker == 0xDA:
            break
        at += 2 + length
    return found


def without(data, marker):
    out, last = bytearray(data[:2]), 2
    for m, start, end in segments(data):
        if m != marker:
            out += data[start:end] if m != 0xDA else data[start:]
        if m == 0xDA:
            return bytes(out)
    return bytes(out)


def variants(fixtures):
    cases = []
    cmyk = bytearray(fixtures['k16-cmyk'])
    for m, start, _ in segments(cmyk):
        if m == 0xEE and cmyk[start + 4:start + 9] == b'Adobe':
            cmyk[start + 15] = 2
    cases.append(('k16-ycck', bytes(cmyk)))
    plain = without(fixtures['c16-444'], 0xE0)
    adobe = bytes([0xFF, 0xEE, 0, 14]) + b'Adobe' + bytes([0, 100, 0, 0, 0, 0, 0])
    cases.append(('c16-adobe-rgb', plain[:2] + adobe + plain[2:]))
    big, prog, gray = fixtures['c64x48-420'], fixtures['pc64x48-420'], fixtures['g64x48']
    cases += [('c64x48-truncated', big[:len(big) * 6 // 10]), ('pc64x48-truncated', prog[:len(prog) // 2]),
              ('g64x48-truncated', gray[:len(gray) * 7 // 10]), ('c16-junk-after-eoi', fixtures['c16-420'] + b'junk\xff\x00\xff\xd9'),
              ('c16-no-eoi', fixtures['c16-444'][:-2])]
    flipped = bytearray(fixtures['c16-420'])
    flipped[len(flipped) - 40] ^= 0x55
    cases.append(('c16-flipped', bytes(flipped)))
    cases.append(('c16-no-huffman', without(fixtures['c16-420'], 0xC4)))
    sos = next(start for m, start, _ in segments(fixtures['c16-444']) if m == 0xDA)
    filled = fixtures['c16-444']
    cases.append(('c16-fill-bytes', filled[:sos] + b'\xff\xff\xff' + filled[sos:]))
    cases.append(('bad-soi', b'\xff\xd9' + fixtures['g8'][2:]))
    sof = next(start for m, start, _ in segments(fixtures['g8']) if m == 0xC0)
    lossless = bytearray(fixtures['g8'])
    lossless[sof + 1] = 0xC3
    cases.append(('g8-lossless', bytes(lossless)))
    twelve = bytearray(fixtures['g8'])
    twelve[sof + 4] = 12
    cases.append(('g8-12bit', bytes(twelve)))
    cases.append(('soi-only', b'\xff\xd8'))
    wide = bytearray(fixtures['g8'])
    wide[sof + 7:sof + 9] = (5000).to_bytes(2, 'big')
    cases.append(('g8-width-5000', bytes(wide)))
    return cases


# Jonlib contracts, not native comparisons: dimensions above 4096, and a
# progressive stream ending before EOI, whose planes stb leaves uninitialized
# (it skips stbi__jpeg_finish).
NATIVE_ONLY_CONTRACTS = {'g8-width-5000': ['error', 'size'], 'pc64x48-truncated': ['error', 'stream']}
FILES = {'.build/jpeg-probe/file.jpg': 'c16-420', '.build/jpeg-probe/FILE2.JPEG': 'pg17x9'}


def native(probe, cases):
    lines = ['#include "raylib.h"', '#include <stdio.h>', C_IMAGE,
             'static void loaded(Image im){if(!im.data){puts("null");return;}image(im);UnloadImage(im);}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for name, data in cases:
        if name not in NATIVE_ONLY_CONTRACTS:
            lines.append(f'{{static const unsigned char d[]={{{",".join(map(str, data))}}};loaded(LoadImageFromMemory(".jpg",d,sizeof d));}}')
    for path in FILES:
        lines.append(f'loaded(LoadImage("{path}"));')
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n')


PROGRAM = '''import Base
import ../../jonlib.bend as J
''' + SURFACE_EMITTER + '''def error.name(error: J.Surface.Error) -> String:
  match error:
    case J.UnsupportedImageSize{}: "size"
    case _: "other"
def decoded(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{J.UnsupportedImageSize{}}: IO.print("[\\"error\\", \\"size\\"]")
    case Fail{_}: IO.print("null")
    case Done{surface}: exported(J.Surface.export(surface))
def file_decoded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{J.DataError{J.UnsupportedImageSize{}}}: IO.print("[\\"error\\", \\"size\\"]")
    case Fail{J.DataError{J.InvalidImageStream{}}}: IO.print("[\\"error\\", \\"stream\\"]")
    case Fail{_}: IO.print("null")
    case Done{surface}: exported(J.Surface.export(surface))
def main() -> IO(Unit):
  do IO<Unit>:
'''


# Inputs are files: Bun cannot evaluate list literals of several thousand
# bytes. Surface.load_image on a .jpg name takes the same raster dispatch as
# Surface.decode_image(".jpg", bytes).
def render(selected, gpu):
    body = PROGRAM
    for kind, path in selected:
        loader = 'load_jpeg' if kind == 'explicit' else 'load_image'
        body += f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.{loader}({json.dumps(path)}), file_decoded)\n'
    return body + '    IO.print("\\"done\\"")\n'


def rows(text):
    """One row per result: stored bytes, None or an error marker."""
    found, chunk = [], []
    for line in text.splitlines():
        value = json.loads(line)
        if value is None or (isinstance(value, list) and value[:1] == ['error']):
            found.append(value)
        elif value == 'end':
            found.append(chunk)
            chunk = []
        elif value == 'done':
            continue
        else:
            chunk.extend(value)
    return found


def main():
    probe = probekit.Probe('jpeg', probekit.arguments(__doc__), raylib_options=('SUPPORT_FILEFORMAT_JPG=ON',))
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())
    fixtures = {entry['name']: (FIXTURES / f'{entry["name"]}.jpg').read_bytes() for entry in manifest['fixtures']}
    cases = list(fixtures.items()) + variants(fixtures)
    for path, name in FILES.items():
        (ROOT / path).parent.mkdir(parents=True, exist_ok=True)
        (ROOT / path).write_bytes(fixtures[name])
    observed = iter(rows(native(probe, cases)))
    expected = [NATIVE_ONLY_CONTRACTS[name] if name in NATIVE_ONLY_CONTRACTS else next(observed) for name, _ in cases]
    expected += [next(observed) for _ in FILES]
    if sum(row is None for row in expected) < 4 or sum(isinstance(row, list) and row[:1] != ['error'] for row in expected) < 30:
        raise ProbeFailure('jpeg: unexpected native decode outcomes')
    inputs = ROOT / '.build/jpeg-probe/cases'
    inputs.mkdir(parents=True, exist_ok=True)
    paths = []
    for index, (_, data) in enumerate(cases):
        (inputs / f'{index:03}.jpg').write_bytes(data)
        paths.append(f'.build/jpeg-probe/cases/{index:03}.jpg')
    actions = [('decode', path) for path in paths] + [('file', path) for path in FILES]
    names = [name for name, _ in cases] + list(FILES)
    actions.append(('explicit', paths[names.index('pc16-420')]))
    names.append('decode_jpeg pc16-420')
    expected.append(expected[names.index('pc16-420')])
    lanes = probe.candidates(render, actions, batch=12, parse=lambda text, selected: rows(text))
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: names[i])
    probe.finish(fixtures=len(fixtures), variants=len(cases) - len(fixtures), files=len(FILES),
                 decoded=sum(isinstance(row, list) and row[:1] != ['error'] for row in expected), failed=sum(row is None for row in expected),
                 encoder=manifest['encoder'], inputs_sha256=hashlib.sha256(b''.join(data for _, data in cases)).hexdigest())


if __name__ == '__main__':
    main()
