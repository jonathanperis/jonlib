#!/usr/bin/env python3
"""Compare src/msf_gif.bend with msf_gif.h, the GIF encoder raylib ships
beside its examples (examples/core/msf_gif.h, 2.2).

Reference. A C program includes the pinned msf_gif.h unmodified and, for
each case, calls msf_gif_begin, msf_gif_frame for every frame (the pitch
is width*4) and msf_gif_end; it prints the file's length and bytes. It is
built twice, as the header builds itself on the host (four pixels at a time
with SSE2 where the compiler has it) and with MSF_GIF_NO_SSE2 (the scalar
loop): both must print the same files, which is what lets the port follow
the scalar loop alone. The frames' pixels are made here and read by the C
program from a file. This probe also reads each reference file back with a
decoder of its own (LZW included) and requires every frame to hold
width*height pixels; what the decoder sees (table resets, sub-blocks, frames
written entirely as transparent pixels, a stream that ends on a sub-block's
last byte) is the coverage the cases must keep.

msf_compress_frame clears 260 bytes ahead of every sub-block it begins, in
a buffer of 800 + width*height*3/2 bytes after its header: a small frame of
many colors (128 or more in under 165 pixels, and more pixels where the
codes fill further sub-blocks) is written past the buffer. The reference is
therefore built with the header's own allocator hooks giving 4096 bytes
more than asked, so that it writes those files too without leaving its
memory; from the codes read back the probe computes which frames the
unhooked library would write past its buffer, and those cases are expected
refused.

Candidate. src/msf_gif.bend's begin, frame and finish on the same frames,
which the Bend program makes with the same integer generators (the FNV-1a
of the pixels it made is compared too): per case whether a file was
answered, its length and the FNV-1a of its bytes.

The cases: single pixels, widths that are not multiples of four, flat
frames, frames equal to the one before, moving shapes on a flat ground,
gradients (the dither), noise of 2^24 colors (the depth is lowered until
fewer than 256 are left, and LZW's table fills and is cleared), noise of 64
colors, depths asked from 1 to 16 and outside (0, 20, a negative int),
delays of one and two bytes, above 65535 and negative, and frames on both
sides of the buffer's limit. Refused, and not run natively (the C code
would read pixels that are not there): a frame with one pixel too few or
too many, and a recording begun with a side of 0 or above 4096. CPU-1,
CPU-2 and JavaScript lanes.
"""
import json
import struct

import probekit
from probekit import ProbeFailure

HEADER = 'examples/core/msf_gif.h'
RAYWHITE, RED, MAROON = 0xF5F5F5FF, 0xE62937FF, 0xBE2137FF
# the two high bits of each color channel: noise of 64 colors
SIXTYFOUR = 0xC0C0C000

NATIVE = r'''
#include <stdio.h>
#include <stdlib.h>
// The header's allocator hooks: every block gets 4096 bytes more than asked.
#define MSF_GIF_MALLOC(context, size) malloc((size) + 4096)
#define MSF_GIF_REALLOC(context, old, oldSize, newSize) realloc(old, (newSize) + 4096)
#define MSF_GIF_FREE(context, old, oldSize) free(old)
#define MSF_GIF_IMPL
#include "msf_gif.h"

static unsigned int word(FILE *file) {
    unsigned char b[4];
    if (fread(b, 1, 4, file) != 4) exit(3);
    return b[0] | b[1] << 8 | b[2] << 16 | (unsigned int)b[3] << 24;
}

int main(int argc, char **argv) {
    FILE *file = fopen(argv[1], "rb");
    if (!file) return 2;
    unsigned int cases = word(file);
    for (unsigned int c = 0; c < cases; c++) {
        int width = (int)word(file), height = (int)word(file);
        unsigned int frames = word(file);
        MsfGifState state = { 0 };
        if (!msf_gif_begin(&state, width, height)) return 4;
        unsigned char *pixels = malloc((size_t)width*height*4);
        for (unsigned int f = 0; f < frames; f++) {
            int centiseconds = (int)word(file), depth = (int)word(file);
            // the words are 0xRRGGBBAA; msf_gif reads the bytes R, G, B, A
            for (int i = 0; i < width*height; i++) {
                unsigned int w = word(file);
                pixels[i*4] = w >> 24; pixels[i*4 + 1] = w >> 16; pixels[i*4 + 2] = w >> 8; pixels[i*4 + 3] = w;
            }
            if (!msf_gif_frame(&state, pixels, centiseconds, depth, width*4)) return 5;
        }
        MsfGifResult result = msf_gif_end(&state);
        if (!result.data) return 6;
        printf("%zu", result.dataSize);
        for (size_t i = 0; i < result.dataSize; i++) printf(" %u", ((unsigned char *)result.data)[i]);
        printf("\n");
        msf_gif_free(result);
        free(pixels);
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../src/msf_gif.bend as G

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, ((h .^. x) * 16777619 : U32))

def count(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def lcg(+s: U32) -> U32:
  ((s * 1664525) + 1013904223 : U32)

def hashed(+i: U32) -> U32:
  (((i * 2654435761) + 40503) .|. 255 : U32)

def shape(+seed: U32, +w: U32, +h: U32, +t: U32, +x: U32, +y: U32) -> U32:
  +left = ((t * 3) + 4 : U32)
  +inside = (x >= left : U32) && (x < (left + (w / 4)) : U32) && (y >= (h / 4) : U32) && (y < (h / 2) : U32)
  Bool.pick(U32, inside, RED, Bool.pick(U32, U32.is_eq(((x + (y * 3) + seed) % 17 : U32), 0), MAROON, RAYWHITE))

# kinds: 0 flat, 1 noise, 2 gradient, 3 shapes on a ground, 4 a few colors in bands, 5 noise of 64 colors.
def pixel(kind: U32, +seed: U32, +w: U32, +h: U32, +t: U32, +x: U32, +y: U32, +s: U32) -> U32:
  match kind:
    case 0: hashed(seed)
    case 1: s
    case 2: ((((x * 255) / U32.max(1, (w - 1 : U32))) << 24n) .|. ((((y * 255) / U32.max(1, (h - 1 : U32))) << 16n)) .|. (((x + y + (t * 8)) .&. 255) << 8n) .|. 255 : U32)
    case 3: shape(seed, w, h, t, x, y)
    case 4: hashed(((((x / 3) + (y / 2) + t) % ((seed % 7) + 1)) + seed : U32))
    case _: ((s .&. SIXTYFOUR) .|. 255 : U32)

def image(n: Nat, +kind: U32, +seed: U32, +w: U32, +h: U32, +t: U32, +x: U32, +y: U32, +s: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k:
      +next = lcg(s)
      +wrap = U32.is_eq((x + 1 : U32), w)
      image(k, kind, seed, w, h, t, Bool.pick(U32, wrap, 0, (x + 1 : U32)), Bool.pick(U32, wrap, (y + 1 : U32), y), next, Con{pixel(kind, seed, w, h, t, x, y, next), acc})

# extra: 0 the frame's pixels, 1 one fewer, 2 one more.
def pixels(extra: U32, +kind: U32, +seed: U32, +w: U32, +h: U32, +t: U32) -> +List<U32>:
  match extra:
    case 0: image(U32.to_nat((w * h : U32)), kind, seed, w, h, t, 0, 0, (seed + (t * 7919) : U32), Nil{})
    case 1: image(U32.to_nat(((w * h) - 1 : U32)), kind, seed, w, h, t, 0, 0, (seed + (t * 7919) : U32), Nil{})
    case _: image(U32.to_nat(((w * h) + 1 : U32)), kind, seed, w, h, t, 0, 0, (seed + (t * 7919) : U32), Nil{})

def row(gif: Maybe<G.Gif>, +sum: U32) -> String:
  match gif:
    case None{}: "[0, 0, 0, 0]"
    case Some{+g}:
      +bytes = G.finish(g)
      "[1, " ++ U32.show(sum) ++ ", " ++ U32.show(count(bytes, 0)) ++ ", " ++ U32.show(fnv(bytes, 2166136261)) ++ "]"

def framed(gif: Maybe<G.Gif>, +made: +List<U32>, +centiseconds: U32, +depth: U32) -> Maybe<G.Gif>:
  match gif:
    case None{}: None{}
    case Some{+g}: G.frame(g, made, centiseconds, depth)

# frames: t, centiseconds and depth for each.
def run(frames: +List<U32>, +extra: U32, +kind: U32, +seed: U32, +w: U32, +h: U32, +sum: U32, gif: Maybe<G.Gif>) -> String:
  match frames:
    case Con{+t, Con{+centiseconds, Con{+depth, +rest}}}:
      +made = pixels(extra, kind, seed, w, h, t)
      run(rest, extra, kind, seed, w, h, fnv(made, sum), framed(gif, made, centiseconds, depth))
    case _: row(gif, sum)

def main() -> IO(Unit):
  do IO<Unit>:
'''


def lcg(s):
    return (s * 1664525 + 1013904223) & 0xFFFFFFFF


def hashed(i):
    return ((i * 2654435761 + 40503) | 255) & 0xFFFFFFFF


def pixel(kind, seed, w, h, t, x, y, s):
    if kind == 0:
        return hashed(seed)
    if kind == 1:
        return s
    if kind == 2:
        return (x * 255 // max(1, w - 1)) << 24 | (y * 255 // max(1, h - 1)) << 16 | ((x + y + t * 8) & 255) << 8 | 255
    if kind == 3:
        left = t * 3 + 4
        if left <= x < left + w // 4 and h // 4 <= y < h // 2:
            return RED
        return MAROON if (x + y * 3 + seed) % 17 == 0 else RAYWHITE
    if kind == 4:
        return hashed(((x // 3 + y // 2 + t) % (seed % 7 + 1) + seed) & 0xFFFFFFFF)
    return (s & SIXTYFOUR) | 255


def image(count, kind, seed, w, h, t):
    """The words the Bend program makes for a frame (`count` of them, in row order)."""
    out, s, x, y = [], (seed + t * 7919) & 0xFFFFFFFF, 0, 0
    for _ in range(count):
        s = lcg(s)
        out.append(pixel(kind, seed, w, h, t, x, y, s))
        x += 1
        if x == w:
            x, y = 0, y + 1
    return out


def fnv(values, h=2166136261):
    for v in values:
        h = ((h ^ v) * 16777619) & 0xFFFFFFFF
    return h


def case(kind, seed, w, h, frames, extra=0):
    return dict(kind=kind, seed=seed, w=w, h=h, frames=frames, extra=extra)


def cases():
    """frames are (t, the centiseconds' word, the depth's word)."""
    neg = lambda v: v & 0xFFFFFFFF
    out = [case(0, 1, 1, 1, [(0, 0, 16)]),
           case(0, 2, 1, 1, [(0, 5, 16), (0, 5, 16), (0, 5, 16)]),
           case(1, 3, 1, 1, [(0, 1, 16), (1, 2, 16)]),
           case(1, 4, 2, 2, [(0, 3, 16)]),
           case(1, 5, 3, 5, [(0, 300, 16), (1, 70000, 16)]),
           case(1, 6, 5, 3, [(0, neg(-1), 16), (1, 0, 16)]),
           case(1, 7, 7, 1, [(0, 0, 16)]),
           case(1, 8, 1, 9, [(0, 0, 16)]),
           case(0, 9, 64, 48, [(0, 0, 16), (0, 0, 16), (0, 0, 16)]),
           case(0, 10, 300, 40, [(0, 4, 16)]),
           case(3, 11, 160, 90, [(0, 0, 16), (1, 0, 16), (2, 0, 16), (2, 0, 16)]),
           case(3, 12, 43, 37, [(0, 2, 16), (3, 2, 16), (9, 2, 16)]),
           case(2, 13, 64, 64, [(0, 0, 16), (1, 0, 16), (2, 0, 16)]),
           case(2, 14, 97, 31, [(0, 0, 16), (0, 0, 16)]),
           case(2, 15, 256, 16, [(0, 0, 16)]),
           case(1, 16, 96, 96, [(0, 0, 16), (1, 0, 16)]),
           case(1, 17, 33, 29, [(0, 0, 16), (0, 0, 16), (1, 0, 16)]),
           case(5, 18, 96, 80, [(0, 0, 16), (1, 0, 16)]),
           case(5, 19, 50, 50, [(0, 0, 16), (0, 0, 16)]),
           case(4, 20, 80, 60, [(0, 0, 16), (1, 0, 16), (2, 0, 16)]),
           case(4, 27, 80, 60, [(0, 0, 16), (5, 0, 16)]),
           case(4, 6, 31, 17, [(0, 0, 16)])]
    # the depths asked, on a gradient and on noise, alone and after a frame of another depth
    for depth in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0, 20, neg(-3)):
        out.append(case(2, 30 + (depth & 31), 24, 20, [(0, 0, depth), (1, 0, depth)]))
    for depth in (1, 3, 6, 8, 9, 12):
        out.append(case(1, 60 + depth, 40, 30, [(0, 0, depth), (1, 0, 16), (2, 0, depth)]))
    # a frame of few colors lets the next start deeper; one of many holds it down
    out += [case(2, 70, 48, 48, [(0, 0, 6), (1, 0, 16), (2, 0, 16), (3, 0, 16)]),
            case(4, 71, 48, 48, [(0, 0, 3), (1, 0, 16), (2, 0, 16)])]
    out += BOUNDARY
    # the buffer's limit: 165 pixels of 128 colors or more fit and 164 do not; 256 pixels fill a second sub-block
    out += [case(1, 90, 11, 15, [(0, 0, 16)]), case(1, 91, 15, 11, [(0, 0, 16)]), case(1, 92, 4, 41, [(0, 0, 16)]), case(1, 93, 41, 4, [(0, 0, 16)]),
            case(1, 94, 16, 16, [(0, 0, 16)]), case(1, 95, 20, 20, [(0, 0, 16)]), case(1, 96, 12, 14, [(0, 0, 16), (1, 0, 16)]),
            case(0, 97, 12, 12, [(0, 0, 16)]), case(1, 98, 12, 12, [(0, 0, 16)]), case(1, 99, 9, 14, [(0, 0, 16)]),
            case(0, 100, 13, 12, [(0, 0, 16), (0, 0, 16)])]
    # refused
    out += [case(1, 80, 6, 4, [(0, 0, 16)], extra=1), case(1, 81, 6, 4, [(0, 0, 16)], extra=2),
            case(1, 82, 6, 4, [(0, 0, 16), (1, 0, 16)], extra=1), case(0, 83, 0, 4, []), case(0, 84, 4, 0, []),
            case(0, 85, 4097, 1, []), case(0, 86, 1, 4097, []), case(0, 87, 0, 0, [(0, 0, 16)])]
    # a recording without frames is a file
    out += [case(0, 88, 4096, 4096, []), case(0, 89, 300, 2, [])]
    return out


# Streams that end on a sub-block's 255th byte (found by search: the terminator follows a full block).
BOUNDARY = [case(2, 302, 22, 22, [(0, 0, 16)]), case(1, 944, 20, 32, [(0, 0, 16)]), case(2, 1010, 40, 19, [(0, 0, 16)])]


def refused(item):
    return not (1 <= item['w'] <= 4096 and 1 <= item['h'] <= 4096) or (item['extra'] != 0 and bool(item['frames']))


def read_back(data, item):
    """Decode a reference file: {frames, resets, blocks, transparent, boundary}."""
    w, h = item['w'], item['h']
    if data[:6] != b'GIF89a' or struct.unpack_from('<HH', data, 6) != (w & 0xFFFF, h & 0xFFFF) or data[-1] != 0x3B:
        raise ProbeFailure('msf-gif: the reference file has no header or trailer')
    at, seen = 32, dict(frames=0, resets=0, blocks=0, transparent=0, boundary=0, overflows=0)
    while data[at] == 0x21:
        if data[at:at + 4] != b'\x21\xF9\x04\x05' or data[at + 8] != 0x2C:
            raise ProbeFailure('msf-gif: the reference frame has another header')
        if struct.unpack_from('<HH', data, at + 13) != (w, h):
            raise ProbeFailure('msf-gif: the reference frame has another size')
        size = 1 << ((data[at + 17] & 7) + 1)
        at += 18 + size * 3
        minimum = data[at]
        at += 1
        stream = bytearray()
        while data[at]:
            seen['blocks'] += 1
            stream += data[at + 1:at + 1 + data[at]]
            last = data[at]
            at += 1 + data[at]
        at += 1
        seen['boundary'] += last == 255
        # a code's entry: (length, first index, whether every index is 0)
        clear, bits, value, width, limit, pixels, clears, zero, previous, table = 1 << minimum, 0, 0, minimum + 1, 0, 0, 0, 0, None, {}
        read, ended = 0, False
        for byte in stream:
            if ended:
                raise ProbeFailure('msf-gif: the reference stream has bytes after its end code')
            value |= byte << bits
            bits += 8
            while bits >= width:
                code = value & ((1 << width) - 1)
                value >>= width
                bits -= width
                read += width
                if code == clear:
                    clears += 1
                    table, limit, width, previous = {}, clear + 2, minimum + 1, None
                    continue
                if code == clear + 1:
                    ended = True
                    break
                if code < clear:
                    entry = (1, code, code == 0)
                elif code in table:
                    entry = table[code]
                elif code == limit and previous is not None:
                    entry = (previous[0] + 1, previous[1], previous[2] and previous[1] == 0)
                else:
                    raise ProbeFailure('msf-gif: the reference stream has a code its table lacks')
                if previous is not None and limit < 4096:
                    table[limit] = (previous[0] + 1, previous[1], previous[2] and entry[1] == 0)
                    limit += 1
                    if limit == 1 << width and width < 12:
                        width += 1
                pixels += entry[0]
                zero += entry[0] if entry[2] else 0
                previous = entry
        if not ended:
            raise ProbeFailure('msf-gif: the reference stream has no end code')
        if pixels != w * h:
            raise ProbeFailure(f'msf-gif: a reference frame decodes to {pixels} pixels of {w * h}')
        seen['frames'] += 1
        # the bytes the C code has written or cleared: header, table, size byte, 260 for the first sub-block, 256 for each one begun after
        seen['overflows'] += 279 + size * 3 + 256 * (read // 8 // 255) > 800 + w * h * 3 // 2
        seen['resets'] += clears - 1
        seen['transparent'] += zero == pixels
    if at != len(data) - 1:
        raise ProbeFailure('msf-gif: the reference file has bytes after its frames')
    return seen


def packed(items):
    out = [struct.pack('<I', len(items))]
    for item in items:
        out.append(struct.pack('<III', item['w'], item['h'], len(item['frames'])))
        for t, centiseconds, depth in item['frames']:
            words = image(item['w'] * item['h'], item['kind'], item['seed'], item['w'], item['h'], t)
            out.append(struct.pack(f'<II{len(words)}I', centiseconds, depth, *words))
    return b''.join(out)


def reference(probe, items):
    """The files of the cases that are run natively, from both builds of the header."""
    path = probe.work / 'cases.bin'
    path.write_bytes(packed(items))
    include = '-I' + str(probe.args.raylib_source / 'examples/core')
    outputs = []
    for name, flags in (('reference', []), ('reference-scalar', ['-DMSF_GIF_NO_SSE2'])):
        source, binary = probe.work / f'{name}.c', probe.work / name
        source.write_text(NATIVE)
        probekit.run(['clang', '-std=c11', '-O2', '-Wno-everything', *flags, include, source, '-o', binary])
        outputs.append(probekit.run([binary, path]).splitlines())
    if outputs[0] != outputs[1]:
        raise ProbeFailure('msf-gif: the header\'s SSE2 and scalar builds write different files')
    files = []
    for line in outputs[0]:
        values = [int(v) for v in line.split()]
        if values[0] != len(values) - 1:
            raise ProbeFailure('msf-gif: incomplete native output')
        files.append(bytes(values[1:]))
    if len(files) != len(items):
        raise ProbeFailure('msf-gif: incomplete native output')
    return files


def bend_case(item):
    frames = ', '.join(str(v) for frame in item['frames'] for v in frame)
    return (f'    IO.print(run([{frames}], {item["extra"]}, {item["kind"]}, {item["seed"]}, {item["w"]}, {item["h"]}, 2166136261, '
            f'G.begin({item["w"]}, {item["h"]})))')


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('msf-gif', args)
    if not (args.raylib_source / HEADER).is_file():
        raise ProbeFailure(f'msf-gif: {HEADER} is not in the raylib checkout')
    chosen = cases()
    native = [item for item in chosen if not refused(item)]
    files = iter(reference(probe, native))
    expected, coverage, size, past = [], dict(frames=0, resets=0, blocks=0, transparent=0, boundary=0, overflows=0), 0, 0
    for item in chosen:
        if refused(item):
            expected.append([0, 0, 0, 0])
            continue
        data = next(files)
        seen = read_back(data, item)
        for key, value in seen.items():
            coverage[key] += value
        if seen['overflows']:
            past += 1
            expected.append([0, 0, 0, 0])
            continue
        size += len(data)
        total = 2166136261
        for t, _, _ in item['frames']:
            total = fnv(image(item['w'] * item['h'], item['kind'], item['seed'], item['w'], item['h'], t), total)
        expected.append([1, total, len(data), fnv(data)])
    lacking = [key for key, least in dict(resets=4, blocks=200, transparent=3, boundary=1, overflows=3).items() if coverage[key] < least]
    if lacking:
        raise ProbeFailure(f'msf-gif: the cases lost coverage of {", ".join(lacking)} ({coverage})')

    def render(items, gpu):
        text = PROGRAM
        for name, value in (('RAYWHITE', RAYWHITE), ('MAROON', MAROON), ('RED', RED), ('SIXTYFOUR', SIXTYFOUR)):
            text = text.replace(name, str(value))
        return text + '\n'.join(bend_case(item) for item in items) + '\n'

    probe.compare(expected, probe.candidates(render, chosen, batch=len(chosen), timeout=1500),
                  describe=lambda i: f'case {i} {chosen[i]["kind"]}/{chosen[i]["seed"]} {chosen[i]["w"]}x{chosen[i]["h"]} frames={chosen[i]["frames"]}')
    probe.finish(cases=len(chosen), refused=len(chosen) - len(native) + past, past_buffer=past, bytes=size, **coverage)


if __name__ == '__main__':
    main()
