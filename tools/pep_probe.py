#!/usr/bin/env python3
"""PEP serialize and decompress bytes against pinned pep.h.

The corpus is the images the Bend codec has been compared with: RGBA and
ABGR, 8/4/1-bit channels, bitmaps, first-color transparency and
premultiplication. Each row is width, height, pixel count, decompressed
words, byte count and file bytes. Images above 4096 pixels are outside this
probe; a 16x16 image is not included.
"""
import json
import math

import probekit
from probekit import ProbeFailure

# (id, width, height, format, bits, dst, transparent, premultiply, pixels or None, raw or None)
# pixels is the pep little-endian word list. raw is a decode-only file.
CASES = (
    ('red-plain', 1, 1, 0, 3, 0, 0, 0, (0xFF0000FF,), None),
    ('red-load', 1, 1, 0, 3, 0, 1, 1, (0xFF0000FF,), None),
    ('red-bgra', 1, 1, 0, 3, 1, 0, 0, (0xFF0000FF,), None),
    ('red-argb', 1, 1, 0, 3, 3, 0, 0, (0xFF0000FF,), None),
    ('magenta-pre', 1, 1, 0, 3, 0, 0, 1, (0x80FF00FF,), None),
    ('magenta-load', 1, 1, 0, 3, 0, 1, 1, (0x80FF00FF,), None),
    ('quad', 2, 2, 0, 3, 0, 0, 0, (0xFF0000FF, 0xFF00FF00, 0xFFFF0000, 0xFFFFFFFF), None),
    ('quad-load', 2, 2, 0, 3, 0, 1, 1, (0xFF0000FF, 0xFF00FF00, 0xFFFF0000, 0xFFFFFFFF), None),
    ('checker', 4, 4, 0, 3, 0, 0, 0, (0xFF000000, 0xFFFFFFFF) * 8, None),
    ('bitmap', 3, 2, 0, 3, 0, 0, 0, (0xFF000000, 0xFFFFFFFF) * 3, None),
    ('abgr-bitmap', 3, 2, 2, 3, 2, 0, 0, (0x000000FF, 0xFFFFFFFF) * 3, None),
    ('grey-1bit', 1, 1, 0, 0, 0, 0, 0, (0x80808080,), None),
    ('argb-pair', 2, 1, 2, 3, 2, 0, 0, (0x80FF00FF, 0xFF00FF00), None),
    ('abgr-clear', 1, 1, 2, 3, 2, 1, 0, (0x80FF00FF,), None),
    ('narrow', 5, 3, 1, 2, 1, 0, 0, (0xFF0000FF, 0xFF00FF00, 0xFFFF0000, 0xFFFFFFFF, 0x80FF00FF) * 3, None),
    ('ramp', 8, 1, 0, 3, 0, 0, 0, tuple(0xFF000000 + i for i in range(8)), None),
    ('empty', 0, 0, 0, 0, 0, 1, 1, None, ()),
    ('truncated', 0, 0, 0, 0, 0, 1, 1, None, (60,)),
)


def depth(count):
    if count <= 1:
        return '0n'
    return f'{1 + int(math.log2(count - 1))}n'


def array_expr(pixels):
    expr = f'Array.new(U32, {depth(len(pixels))}, 0)'
    for index, word in enumerate(pixels):
        expr = f'Array.set(U32, {expr}, {index}, {word})'
    return expr


def bend_case(index, case):
    _, width, height, fmt, bits, dst, transparent, premultiply, pixels, raw = case
    if raw is None:
        produced = f'Pep.bytes({width}, {height}, {fmt}, {bits}, {array_expr(pixels)})'
    else:
        produced = 'Nil{}' if not raw else 'Con{' + ', Con{'.join(str(byte) for byte in raw) + ', Nil{}' + '}' * len(raw)
    return (
        f'def case{index}.open(read: +List<U32> & +List<U32>) -> +List<U32>:\n'
        f'  (file, kept) = read\n'
        f'  pack(Pep.picture({dst}, {transparent}, {premultiply}, file), kept)\n'
        f'def case{index}() -> +List<U32>:\n'
        f'  case{index}.open(dup({produced}))\n'
    )


def bend_source(selected):
    lines = [
        'import Base',
        'import ../../src/pep.bend as Pep',
        'def dup.pair(+head: U32, read: +List<U32> & +List<U32>) -> +List<U32> & +List<U32>:',
        '  (left, right) = read',
        '  (Con{head, left}, Con{head, right})',
        'def dup(xs: +List<U32>) -> +List<U32> & +List<U32>:',
        '  match xs:',
        '    case Nil{}: (Nil{}, Nil{})',
        '    case Con{+head, rest}: dup.pair(head, dup(rest))',
        'def count(xs: +List<U32>, +n: U32) -> U32:',
        '  match xs:',
        '    case Nil{}: n',
        '    case Con{_, rest}: count(rest, (n + 1 : U32))',
        'def join(xs: +List<U32>, ys: +List<U32>) -> +List<U32>:',
        '  match xs:',
        '    case Nil{}: ys',
        '    case Con{+head, rest}: Con{head, join(rest, ys)}',
        'def pack.file(+width: U32, +height: U32, +plen: U32, pixels: +List<U32>, read: +List<U32> & +List<U32>) -> +List<U32>:',
        '  (f1, f2) = read',
        '  join(Con{width, Con{height, Con{plen, pixels}}}, Con{count(f1, 0), f2})',
        'def pack.pix(+width: U32, +height: U32, read: +List<U32> & +List<U32>, file: +List<U32>) -> +List<U32>:',
        '  (p1, p2) = read',
        '  pack.file(width, height, count(p1, 0), p2, dup(file))',
        'def pack(shot: Pep.Shot, file: +List<U32>) -> +List<U32>:',
        '  Pep.Shot{width, height, pixels} = shot',
        '  pack.pix(width, height, dup(pixels), file)',
    ]
    names = []
    for index, case in enumerate(selected):
        lines.append(bend_case(index, case))
        names.append(f'case{index}()')
    lines.append('def main() -> IO(Unit):')
    lines.append('  do IO<Unit>:')
    for name in names:
        lines.append(f'    IO.print(List.show(~&2, ~U32, ~U32.show, {name}))')
    return '\n'.join(lines) + '\n'


def c_source(cases):
    parts = [
        '#define PEP_IMPLEMENTATION',
        '#include "external/pep.h"',
        '#include <stdint.h>',
        '#include <stdio.h>',
        '#include <stdlib.h>',
        'static void emit(unsigned w, unsigned h, const uint32_t *pix, unsigned np,',
        '                  const unsigned char *bytes, unsigned nb) {',
        '  printf("[%u,%u,%u", w, h, np);',
        '  for (unsigned i = 0; i < np; i++) printf(",%u", pix ? pix[i] : 0);',
        '  printf(",%u", nb);',
        '  for (unsigned i = 0; i < nb; i++) printf(",%u", bytes ? bytes[i] : 0);',
        '  printf("]\\n");',
        '}',
        'int main(void) {',
    ]
    for case in cases:
        _, width, height, fmt, bits, dst, transparent, premultiply, pixels, raw = case
        if raw is None:
            words = ', '.join(str(word) for word in pixels)
            parts.append(
                '  { uint32_t pix[] = {' + words + '};'
                f' pep compressed = pep_compress(pix, {width}, {height}, {fmt}, {bits});'
                ' uint32_t size = 0; uint8_t *bytes = pep_serialize(&compressed, &size);'
                ' pep loaded = pep_deserialize(bytes, size);'
                f' uint32_t *out = (bytes && loaded.bytes) ? pep_decompress(&loaded, {dst}, {transparent}, {premultiply}) : NULL;'
                f' emit({width}, {height}, out, out ? {width * height} : 0, bytes, size);'
                ' pep_free(&compressed); pep_free(&loaded); free(bytes); free(out); }'
            )
        elif not raw:
            parts.append('  emit(0, 0, NULL, 0, NULL, 0);')
        else:
            raws = ', '.join(str(byte) for byte in raw)
            parts.append(
                '  { unsigned char raw[] = {' + raws + '};'
                f' pep loaded = pep_deserialize(raw, {len(raw)});'
                ' if (!loaded.bytes || !loaded.width || !loaded.height) emit(0, 0, NULL, 0, raw, sizeof raw);'
                ' else { uint32_t *out = pep_decompress(&loaded, 0, 1, 1);'
                ' emit(loaded.width, loaded.height, out, (unsigned)loaded.width * loaded.height, raw, sizeof raw);'
                ' free(out); } pep_free(&loaded); }'
            )
    parts.append('  return 0;')
    parts.append('}')
    return '\n'.join(parts) + '\n'


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('pep', args)
    if len(CASES) != len({case[0] for case in CASES}):
        raise ProbeFailure('pep: duplicate case id')
    expected = [json.loads(line) for line in probe.native(c_source(CASES), link_raylib=False).splitlines() if line.strip()]
    if len(expected) != len(CASES):
        raise ProbeFailure(f'pep: oracle produced {len(expected)} rows for {len(CASES)} cases')
    lanes = probe.candidates(lambda selected, gpu: bend_source(selected), list(CASES), batch=len(CASES), timeout=600)
    probe.compare(expected, lanes, lambda index: CASES[index][0])
    probe.finish(cases=len(CASES))


if __name__ == '__main__':
    main()
