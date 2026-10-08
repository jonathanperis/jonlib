#!/usr/bin/env python3
"""Compare Jonlib's fonts, text measurement, text drawing and image text with
raylib 6.0's rtext.c and rtextures.c.

Same reference as tools/frame_probe.py and tools/texture_probe.py: pinned
raylib on PLATFORM=Memory (rlgl.h's OpenGL 1.1 path into rlsw.h) built with
CMAKE_C_FLAGS=-ffp-contract=off and checked free of fused multiply-adds;
framebuffers are read back with rlCopyFramebuffer (top-down BGRA, swapped
to RGBA). Each scene runs InitWindow (which loads the default font as
texture 1), SetTextLineSpacing(2), then a list of operations, and prints one
row: the log of every logging operation followed by the framebuffer.

Logged: GetFontDefault's fields and its whole glyph table (values, offsets,
advance, recs bits and every glyph image's bytes), IsFontValid,
GetGlyphIndex/GetGlyphInfo/GetGlyphAtlasRec for ASCII, Latin-1, unknown,
negative and huge codepoints, MeasureText ints and MeasureTextEx /
MeasureTextCodepoints bits over ASCII, UTF-8 multi-byte, invalid and
truncated UTF-8, unknown codepoints (drawn and measured as '?'), tabs,
newlines, embedded NULs, empty texts and integral, fractional, zero,
negative, tiny, huge and nonfinite sizes and spacings under several
SetTextLineSpacing values; ImageText/ImageTextEx images and
ImageDrawText/ImageDrawTextEx results on images of several formats (bytes).
Fonts built by LoadFontFromImage from generated XNA-style images (opaque and
translucent glyphs, R8G8B8A8, R8G8B8, R5G5B5A1 and GRAY_ALPHA sources,
several first characters, exactly 256 glyphs, images that return the
default font) are logged, measured, drawn (POINT and BILINEAR) and turned
into image text; UnloadFont returns their texture ids.

Drawn: DrawText, DrawTextEx, DrawTextPro (rotations in the host M.Libm
profile's verified set, origins), DrawTextCodepoint(s), DrawFPS (GetFPS is 0
in this build, which defines SUPPORT_CUSTOM_FRAME_CONTROL; other values go
through DrawFPS's body extracted from the pinned rtext.c with GetFPS()
replaced by the value) with integral and fractional positions and sizes,
tints, translucency, overlapping and clipped text, text in a 2D camera and
a scissor, line spacings, and the default font's texture filtered
BILINEAR through a Font value (reset to POINT before DrawText or shapes,
which Jonlib keeps NEAREST; see docs/FONTS.md).

Contracts: operations marked refused are not run natively; Jonlib must
answer "R" (None or Fail) for logging ones, and contract scenes (C int
conversions out of range, unverified rotation arguments) must leave the
frame undefined ("null"). LoadFontFromImage refusals (reads past the image,
no glyph, more than 256 glyphs) come from a model of its scan here.
CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import math
import random

from conformance import gradient_reference
import frame_probe as fp
import texture_probe as tp
import probekit
from probekit import ROOT, ProbeFailure

C = fp.C
f32 = fp.f32
cf = fp.cf
bf = fp.bf
NAN = float('nan')
INF = float('inf')

WHITE, BLACK, RED, GREEN, BLUE = C(255, 255, 255), C(0, 0, 0), C(230, 41, 55), C(0, 228, 48), C(0, 121, 241)
MAGENTA, KEY = C(255, 0, 255), C(0, 0, 0)


def T(text):
    return list(text.encode('utf-8')) if isinstance(text, str) else list(text)


def u32(value):
    return value & 0xFFFFFFFF


# -----------------------------------------------------------------------------
# XNA-style font images (both sides draw the same boxes over the key color)

def font_image(width, height, key, cs, ls, ch, rows, seed=1, alpha=False, fmt=7, extra=()):
    boxes = []
    for r, widths in enumerate(rows):
        y, x = ls + r * (ch + ls), cs
        for w in widths:
            boxes.append((x, y, w, ch))
            x += w + cs
    boxes += list(extra)
    for x, y, w, h in boxes:
        if x < 0 or y < 0 or x + w > width or y + h > height:
            raise ProbeFailure(f'font: box {(x, y, w, h)} outside a {width}x{height} font image')
    return dict(width=width, height=height, key=key, seed=seed, alpha=alpha, boxes=boxes, format=fmt)


def glyph_color(x, y, seed, alpha, key):
    v = u32(x * 73856093) ^ u32(y * 19349663) ^ u32(seed * 83492791)
    v |= 0x40404000
    c = (v & 0xFFFFFF00) | (128 + (v & 127)) if alpha else v | 255
    return c ^ 0x100 if c == key else c


def font_pixels(spec):
    w, h = spec['width'], spec['height']
    p = [spec['key']] * (w * h)
    for x0, y0, bw, bh in spec['boxes']:
        for y in range(y0, y0 + bh):
            for x in range(x0, x0 + bw):
                p[y * w + x] = glyph_color(x, y, spec['seed'], spec['alpha'], spec['key'])
    return p


def scan_font(spec, first):
    """LoadFontFromImage's scan: 'refused' (undefined), 'default' or the glyph count."""
    if spec['format'] != 7:
        spec = dict(spec, format=7)  # the generated colors survive the probe's conversions
    w, h, key, p = spec['width'], spec['height'], spec['key'], font_pixels(spec)
    x = y = 0
    for y in range(h):
        x = next((i for i in range(w) if p[y * w + i] != key), w)
        if x < w:
            break
        if y == h - 1:
            return 'refused'
        if p[(y + 1) * w] != key:
            break
    if x == 0 or y == 0:
        return 'default'
    j = 0
    while y + j < h:
        if (y + j) * w + x >= w * h:
            return 'refused'
        if p[(y + j) * w + x] == key:
            break
        j += 1
    count, line = 0, 0
    while y + line * (j + y) < h:
        row, xp = y + line * (j + y), x
        while xp < w and p[row * w + xp] != key:
            if count >= 256:
                return 'refused'
            cw = 0
            while xp + cw < w and p[row * w + xp + cw] != key:
                cw += 1
            count, xp = count + 1, xp + cw + x
        line += 1
    signed_first = first - (1 << 32) if first >= 1 << 31 else first
    if count == 0 or signed_first + count - 1 > 2**31 - 1:
        return 'refused'
    return count


# -----------------------------------------------------------------------------
# Scenes

def scenes(libm):
    out = []

    def add(name, width, height, ops, contract=False):
        out.append(dict(id=name, width=width, height=height, ops=ops, contract=contract))

    half = [C(255, 0, 0, 128), C(0, 255, 0, 64), C(0, 0, 255, 200), C(255, 255, 0, 1), C(17, 34, 51, 254)]
    trans_bg = C(255, 128, 128, 100)

    # The default font: fields, glyph table and glyph queries.
    add('default-table', 4, 4, [('default', 0), ('info', 0), ('table', 0)])
    cps = [u32(-1), 0, 9, 10, 31, 32, 33, 48, 63, 64, 65, 90, 97, 122, 126, 127, 128, 159, 160, 161, 191, 192, 200, 223, 224, 254, 255,
           256, 0x3A9, 0x20AC, 0xFFFD, 0x10FFFF, 0x1FFFFF, 0x7FFFFFFF, 0x80000000]
    add('default-glyphs', 4, 4, [('default', 0)] + [('glyph', 0, cp) for cp in cps])

    # Measurement with the default font.
    texts = [b'', 'A', 'Hello, World!', 'Line one\nLine 2', '\n', '\n\n', 'a\n', '\nabc', 'tab\there', 'multi  spaces ', ' ',
             'Olá ñandú', '€ 5', 'こんにちは', '\U0001F600!', b'\xff\xfeAB', b'ab\xe2\x82', b'ab\x00cd',
             ''.join(chr(c) for c in range(32, 127)), ''.join(chr(c) for c in range(160, 256)), 'raylib ' * 40, '\t\t\n x \n\n yy',
             'iiiii\nWWWWW\nmm', b'\xc0\xaf\xed\xa0\x80\xf8\x88\x80\x80\x80', '?', '~\x7f\x01']
    sizes = [10.0, 20.0, 1.0, 0.0, -5.0, 7.5, 13.37, 100.0, 1e-3, 1e6, INF, NAN, -0.0]
    spacings = [0.0, 1.0, 2.0, -1.0, 0.5, -3.25, 1e10, NAN]
    rng = random.Random(0xF0A7)
    measure_ops = []
    for k, text in enumerate(texts):
        measure_ops.append(('measure', 0, T(text), sizes[k % len(sizes)], spacings[k % len(spacings)]))
        measure_ops.append(('measure', 0, T(text), f32(rng.uniform(0.0, 40.0)), f32(rng.uniform(-3.0, 6.0))))
        measure_ops.append(('measure_text', T(text), (10.0, 20.0, 0.0, 5.0, 11.0, 19.0, 25.0, 99.0, 1000.0, -3.0, 7.9)[k % 11]))
        measure_ops.append(('measure_cp', 0, [ord(c) for c in text] if isinstance(text, str) else list(text),
                            sizes[(k + 3) % len(sizes)], spacings[(k + 5) % len(spacings)]))
    for k in range(0, len(measure_ops), 36):
        spacing = (2, 0, u32(-5), 7, 100)[(k // 36) % 5]
        add(f'measure-{k // 36}', 4, 4, [('default', 0), ('spacing', spacing)] + measure_ops[k:k + 36])
    add('measure-text-refused', 4, 4, [('measure_text', T('Hello'), NAN, 'R'), ('measure_text', T('Hello'), 3e9, 'R'),
                                       ('measure_text', T('Hello'), 1e9, 'R'), ('measure_text', T('Hello'), 2e8),
                                       ('measure_text', T(''), 1e9), ('measure_text', T('\n'), 20.0)])
    add('measure-codepoints', 4, 4, [('default', 0), ('spacing', 4)] + [
        ('measure_cp', 0, list(c), s, sp) for c, s, sp in (
            ((), 10.0, 1.0), ((72, 105), 20.0, 2.0), ((10,), 10.0, 1.0), ((10, 10, 65), 30.0, 3.0), ((0x20AC, 0x1FFFFF, u32(-7)), 12.5, 0.25),
            ((65, 10, 66, 67, 10), 15.0, -1.0), ((9, 32, 32), 10.0, 1.0), ((0, 65), 10.0, 1.0))])

    # Frames: DrawText and friends with the default font.
    hello = T('Hello, raylib!')
    add('draw-text-basic', 96, 32, [('begin',), ('clear', C(245, 245, 245)), ('text', hello, 2.0, 2.0, 10.0, BLACK),
                                    ('text', T('Size 20'), 4.0, 12.0, 20.0, RED), ('end',)])
    add('draw-text-sizes', 96, 48, [('begin',), ('clear', BLACK), ('text', T('ab'), 1.0, 1.0, 8.0, WHITE), ('text', T('cd'), 20.0, 1.0, 15.0, GREEN),
                                    ('text', T('ef'), 50.0, 1.0, 19.0, BLUE), ('text', T('Wg'), 1.0, 20.0, 25.0, C(255, 200, 0)),
                                    ('text', T('Q'), 60.0, 18.0, 30.0, half[0]), ('text', T('x'), 80.0, 30.0, -4.0, WHITE), ('end',)])
    add('draw-text-fractional', 64, 32, [('begin',), ('clear', C(20, 30, 40)), ('text', T('12.9'), 1.9, 2.7, 10.9, WHITE),
                                         ('text', T('neg'), -3.5, -1.2, 12.0, GREEN), ('text', T('edge'), 50.0, 25.0, 10.0, half[2]), ('end',)])
    add('draw-text-multiline', 80, 48, [('begin',), ('clear', BLACK), ('text', T('one\ntwo\n\nfour'), 2.0, 1.0, 10.0, WHITE),
                                        ('spacing', 6), ('text', T('a\nb\nc'), 40.0, 1.0, 10.0, GREEN), ('spacing', u32(-4)),
                                        ('text', T('x\ny'), 60.0, 20.0, 10.0, RED), ('end',)])
    add('draw-text-utf8', 96, 24, [('begin',), ('clear', C(250, 250, 250)), ('text', T('Olá ção €こÿ'), 1.0, 1.0, 10.0, BLACK),
                                   ('text', T(b'\xff\xe2\x82 \xc3\xa9\x00zz'), 1.0, 12.0, 10.0, BLUE), ('end',)])
    add('draw-text-tabs', 64, 16, [('begin',), ('clear', BLACK), ('text', T('a\tb  c\t\td'), 0.0, 3.0, 10.0, WHITE), ('end',)])
    add('draw-text-alpha', 64, 32, [('begin',), ('clear', trans_bg), ('text', T('ALPHA'), 2.0, 2.0, 20.0, half[0]),
                                    ('text', T('alpha'), 6.0, 8.0, 20.0, half[2]), ('text', T('###'), 0.0, 0.0, 10.0, half[3]),
                                    ('text', T('Mm'), 30.0, 14.0, 20.0, half[4]), ('end',)])
    add('draw-text-shapes', 64, 32, [('begin',), ('clear', BLACK), ('rect', 2.0, 2.0, 20.0, 10.0, BLUE), ('text', T('OVER'), 3.0, 3.0, 10.0, WHITE),
                                     ('rect', 10.0, 5.0, 6.0, 6.0, half[0]), ('text', T('x'), 40.0, 10.0, 40.0, half[1]), ('end',)])
    add('draw-text-camera', 64, 48, [('begin',), ('clear', BLACK), ('mode2d', 32.0, 24.0, 10.0, 5.0, 0.0, 2.0), ('text', T('Zoom'), 0.0, 0.0, 10.0, WHITE),
                                     ('end2d',), ('mode2d', 32.0, 24.0, 0.0, 0.0, 90.0, 1.0), ('text', T('Turn'), 0.0, 0.0, 10.0, GREEN), ('end2d',),
                                     ('text', T('flat'), 1.0, 38.0, 10.0, RED), ('end',)])
    add('draw-text-scissor', 64, 32, [('begin',), ('clear', C(30, 30, 30)), ('scissor', 5.0, 4.0, 30.0, 10.0),
                                      ('text', T('Scissored text'), 0.0, 2.0, 20.0, WHITE), ('end_scissor',), ('text', T('free'), 40.0, 20.0, 10.0, GREEN), ('end',)])
    fps_ops = [('begin',), ('clear', BLACK)]
    for k, fps in enumerate((0, 7, 14, 15, 29, 30, 60, 144, 1000, u32(-5))):
        fps_ops.append(('fps', float(2 + 52 * (k % 2)), float(1 + 20 * (k // 2)), fps))
    add('draw-fps', 112, 104, fps_ops + [('end',)])

    # Fonts as values: DrawTextEx, DrawTextPro, DrawTextCodepoint(s).
    add('draw-ex-default', 96, 48, [('begin',), ('clear', BLACK), ('default', 0),
                                    ('text_ex', 0, T('Ex 10'), 1.0, 1.0, 10.0, 1.0, WHITE), ('text_ex', 0, T('frac'), 2.5, 12.25, 13.7, 0.75, GREEN),
                                    ('text_ex', 0, T('tight'), 50.0, 1.0, 10.0, -1.5, half[2]), ('text_ex', 0, T('small'), 50.0, 14.0, 6.5, 0.0, WHITE),
                                    ('text_ex', 0, T('two\nlines'), 1.0, 26.0, 9.0, 2.0, RED), ('text_ex', 0, T('BIG'), 40.0, 24.0, 23.0, 3.0, half[0]),
                                    ('text_ex', 0, T('neg'), 90.0, 40.0, -10.0, 1.0, WHITE), ('end',)])
    for k, rot in enumerate((0.0, 90.0, 45.0, -30.0, 180.0, 270.0, 359.0, 1.0)):
        add(f'draw-pro-{k}', 64, 48, [('begin',), ('clear', (C(10, 30, 50), trans_bg)[k % 2]), ('default', 0),
                                      ('text_pro', 0, T('Pro text'), 32.0, 24.0, 20.0, 5.0, rot, 10.0, 1.0, WHITE),
                                      ('text_pro', 0, T('o\nk'), 10.0, 10.0, 0.0, 0.0, rot, 15.5, 2.0, half[0]),
                                      ('text', T('ref'), 1.0, 38.0, 10.0, GREEN), ('end',)])
    add('draw-codepoints', 96, 40, [('begin',), ('clear', C(240, 240, 240)), ('default', 0),
                                    ('codepoint', 0, 65, 1.0, 1.0, 10.0, BLACK), ('codepoint', 0, 0x20AC, 10.0, 1.0, 20.0, RED),
                                    ('codepoint', 0, 233, 30.5, 2.5, 12.5, BLUE), ('codepoint', 0, 32, 40.0, 1.0, 10.0, BLACK),
                                    ('codepoints', 0, [72, 105, 10, 0x3A9, 9, 255, 33], 50.0, 1.0, 10.0, 1.0, BLACK),
                                    ('codepoints', 0, [87, 87, 87], 1.0, 24.0, 15.0, -2.0, half[2]), ('spacing', 9),
                                    ('codepoints', 0, [65, 10, 66], 70.0, 1.0, 10.0, 1.0, RED), ('end',)])
    add('draw-default-bilinear', 96, 40, [('begin',), ('clear', BLACK), ('default', 0), ('filter', 0, 1),
                                          ('text_ex', 0, T('Smooth'), 1.5, 1.25, 23.0, 2.0, WHITE), ('text_ex', 0, T('soft'), 60.0, 22.0, 12.5, 0.5, GREEN),
                                          ('filter', 0, 0), ('text', T('point'), 1.0, 28.0, 10.0, RED), ('rect', 60.0, 2.0, 8.0, 8.0, BLUE),
                                          ('text_ex', 0, T('pt'), 70.0, 2.0, 15.0, 1.0, WHITE), ('end',)])

    # Fonts from images.
    std = font_image(64, 40, KEY, 1, 2, 9, [[3, 5, 1, 7, 4, 2, 6, 5, 3], [6, 6, 2, 8, 4, 5], [1, 1, 9, 3]], seed=7)
    tra = font_image(48, 30, MAGENTA, 2, 1, 6, [[4, 3, 5, 2, 6], [7, 1, 5, 4]], seed=3, alpha=True)
    rgb = dict(font_image(40, 24, KEY, 1, 1, 7, [[3, 4, 5, 2, 6], [4, 4, 4]], seed=11), format=4)
    rgba5551 = dict(font_image(40, 24, KEY, 2, 2, 5, [[3, 4, 2, 5], [6, 1]], seed=13), format=5)
    gray = dict(font_image(32, 20, KEY, 1, 2, 6, [[2, 3, 4, 2], [5, 3]], seed=17), format=2)
    many = font_image(130, 17, KEY, 1, 1, 3, [[1] * 64] * 4, seed=19)
    over = font_image(130, 21, KEY, 1, 1, 3, [[1] * 64] * 5, seed=19)
    corner = font_image(16, 8, KEY, 0, 0, 3, [[2, 3]], seed=23)
    lead_row = font_image(16, 8, KEY, 1, 1, 3, [[2]], seed=29, extra=[(0, 0, 1, 1)])
    all_key = font_image(8, 6, KEY, 1, 1, 2, [], seed=1)
    edge = font_image(8, 6, KEY, 1, 1, 2, [], seed=1, extra=[(0, 2, 1, 4)])
    irregular = font_image(40, 16, KEY, 2, 2, 5, [[3, 4]], seed=31, extra=[(18, 2, 3, 5), (24, 2, 2, 5)])
    fonts = [('std', std, KEY, 32), ('tra', tra, MAGENTA, 65), ('rgb', rgb, KEY, 48), ('rgba5551', rgba5551, KEY, 97), ('gray', gray, KEY, 33),
             ('irregular', irregular, KEY, 32)]
    for name, spec, key, first in fonts:
        n = scan_font(spec, first)
        if not isinstance(n, int):
            raise ProbeFailure(f'font: generated font {name} scans as {n}')
        add(f'font-{name}', 96, 48, [('begin',), ('clear', C(40, 40, 40)), ('load', 0, spec, key, first), ('info', 0), ('table', 0),
                                     ('glyph', 0, first), ('glyph', 0, first + n - 1), ('glyph', 0, first + n), ('glyph', 0, 63),
                                     ('measure', 0, T('ABCDEFGHIJ'), 9.0, 1.0), ('measure', 0, [first, first + 1, 10, first + 2], 20.0, 0.5),
                                     ('measure_cp', 0, [first + 3, first + 3, 10, 10], 4.5, 2.0),
                                     ('text_ex', 0, bytes(range(first, first + min(n, 12))) if first < 128 else T('?'), 1.0, 1.0, 9.0, 1.0, WHITE),
                                     ('text_ex', 0, T('!"#$%&'), 2.5, 14.5, 18.0, 2.0, half[0]), ('filter', 0, 1),
                                     ('text_ex', 0, T('!"#$%&ABab'), 1.0, 30.0, 13.5, 0.0, WHITE),
                                     ('text_pro', 0, T('#$%'), 80.0, 20.0, 3.0, 3.0, 90.0, 12.0, 1.0, GREEN), ('end',)])
    add('font-many', 32, 16, [('load', 0, many, KEY, 0), ('info', 0), ('glyph', 0, 255), ('glyph', 0, 63), ('glyph', 0, 256)])
    add('font-security', 16, 8, [('load', 0, corner, KEY, 32), ('info', 0), ('load', 1, lead_row, KEY, 32), ('info', 1)])
    add('font-refused', 16, 8, [('load', 0, all_key, KEY, 32), ('load', 1, edge, KEY, 32), ('load', 2, over, KEY, 32),
                                ('load', 0, std, KEY, u32(2**31 - 3))])
    add('font-unload', 32, 16, [('load', 0, std, KEY, 32), ('info', 0), ('load', 1, tra, MAGENTA, 32), ('info', 1), ('unload', 0),
                                ('load', 2, gray, KEY, 32), ('info', 2), ('default', 0), ('info', 0), ('unload', 0), ('load', 0, rgb, KEY, 32),
                                ('info', 0)])

    # Image text with the default font.
    img_ops = [('image_text', T('Hello'), 10.0, BLACK), ('image_text', T('Hello'), 20.0, RED), ('image_text', T('Ab'), 5.0, WHITE),
               ('image_text', T('xyz'), 13.0, half[0]), ('image_text', T('two\nlines'), 10.0, BLUE), ('image_text', T(''), 10.0, WHITE),
               ('image_text', T('\n'), 10.0, WHITE, 'R'), ('image_text', T('é€?'), 25.0, GREEN), ('image_text', T('tab\tx'), 11.0, half[2]),
               ('image_text', T('W'), 40.0, C(10, 20, 30, 0)), ('image_text', T('a\n\nb'), 15.0, half[4]), ('image_text', T('nan'), NAN, WHITE, 'R')]
    add('image-text', 4, 4, img_ops)
    add('image-text-spacing', 4, 4, [('spacing', 10)] + img_ops[4:5] + [('image_text', T('l\ni\nn'), 12.0, WHITE), ('spacing', u32(-30)),
                                                                        ('image_text', T('a\nb'), 10.0, WHITE, 'R')])
    add('image-text-ex', 4, 4, [('default', 0)] + [
        ('image_text_ex', 0, T(t), s, sp, c) for t, s, sp, c in (
            ('Ex', 10.0, 1.0, WHITE), ('Ex', 10.5, 1.0, RED), ('frac', 17.3, 0.5, BLUE), ('neg sp', 10.0, -2.0, WHITE),
            ('wide', 20.0, 4.75, half[0]), ('mm', 7.0, 0.0, GREEN), ('x', 1.0, 1.0, WHITE), ('o\nk', 12.0, 1.0, half[1]))] + [
        ('image_text_ex', 0, T('bad'), 10.0, NAN, WHITE, 'R'), ('image_text_ex', 0, T('bad'), 0.0, 1.0, WHITE, 'R'),
        ('image_text_ex', 0, T('big'), 1e6, 1.0, WHITE, 'R')])

    # ImageDrawText(Ex) onto images of several formats.
    targets = [tp.image(24, 14, 7, 41), tp.image(20, 12, 1, 42), tp.image(20, 12, 2, 43), tp.image(18, 10, 3, 44), tp.image(18, 10, 4, 45),
               tp.image(18, 10, 6, 46), tp.image(16, 10, 7, 47, True), tp.image(12, 8, 5, 48)]
    draws = []
    for k, target in enumerate(targets):
        draws.append(('image_draw_text', target, T('Hi!'), float((k % 3) - 1), float((k % 4) - 1), (10.0, 20.0, 5.0, 13.0)[k % 4],
                      (RED, WHITE, half[0], half[2])[k % 4]))
    draws += [('image_draw_text', targets[0], T('far'), 30.0, 2.0, 10.0, WHITE), ('image_draw_text', targets[0], T('up'), 2.0, -20.0, 10.0, WHITE),
              ('image_draw_text', targets[0], T(''), 2.0, 2.0, 10.0, WHITE), ('image_draw_text', targets[0], T('zero'), 2.0, 2.0, 0.0, WHITE, 'R'),
              ('image_draw_text', targets[0], T('neg'), 2.0, 2.0, -10.0, WHITE, 'R'), ('image_draw_text', targets[0], T('x'), NAN, 2.0, 10.0, WHITE, 'R')]
    add('image-draw-text', 4, 4, draws)
    add('image-draw-text-ex', 4, 4, [('default', 0)] + [
        ('image_draw_text_ex', 0, targets[k % len(targets)], T(t), x, y, s, sp, c) for k, (t, x, y, s, sp, c) in enumerate((
            ('Ex', 1.5, 2.75, 10.0, 1.0, WHITE), ('Ex', -2.5, -1.5, 12.5, 0.5, RED), ('frac', 0.9, 0.1, 10.0, 2.0, half[2]),
            ('a\nb', 3.0, -4.0, 10.0, 1.0, GREEN), ('wide', 12.25, 4.0, 15.0, 1.5, WHITE), ('Q', 5.0, 5.0, 30.0, 1.0, half[0])))] + [
        ('image_draw_text_ex', 0, targets[0], T('far'), 40000.0, 2.0, 10.0, 1.0, WHITE, 'R')])

    # Image text with image fonts (ImageResize, not NN).
    add('image-text-font', 4, 4, [('load', 1, std, KEY, 32), ('load', 2, tra, MAGENTA, 65)] + [
        ('image_text_ex', s, T(t), size, sp, c) for s, t, size, sp, c in (
            (1, '!"#$', 9.0, 1.0, WHITE), (1, '!"#$', 18.0, 1.0, WHITE), (1, '&\'()\n*+', 13.0, 0.0, RED), (2, 'ABCD', 6.0, 1.0, WHITE),
            (2, 'ABCD', 15.5, 2.0, half[2]), (2, 'A\nB', 6.0, 1.0, WHITE))] + [
        ('image_draw_text_ex', 1, targets[0], T('!"#'), 1.0, 1.0, 12.0, 1.0, WHITE), ('image_draw_text_ex', 2, targets[1], T('ABC'), 0.5, -1.0, 9.0, 0.0, RED)])

    # Random scenes (seeded): texts mixing ASCII, newlines, tabs, multi-byte
    # and invalid UTF-8; measurement with any finite size and spacing; draws
    # at fractional positions with tints and verified rotations; image text
    # with sizes and spacings that keep raylib's image sizes defined.
    alphabet = [T(c) for c in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,;:!?-+=/()[]{}<>@#$%^&*_~|'] + \
        [T('\n'), T('\t'), T('é'), T('ß'), T('€'), T('こ'), T('\U0001F600'), [0xFF], [0xC3], [0x80]]

    def rtext(low, high, newlines=True):
        pool = alphabet if newlines else [a for a in alphabet if a != T('\n')]
        return [b for _ in range(rng.randrange(low, high + 1)) for b in rng.choice(pool)]

    def rcolor():
        return C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, rng.randrange(256))))

    for k in range(4):
        ops = [('default', 0), ('spacing', u32(rng.randrange(-6, 12)))]
        for _ in range(32):
            text = rtext(0, 30)
            kind = rng.randrange(3)
            if kind == 0:
                ops.append(('measure', 0, text, f32(rng.uniform(-20.0, 80.0)), f32(rng.uniform(-8.0, 12.0))))
            elif kind == 1:
                ops.append(('measure_text', text, float(rng.randrange(-5, 120))))
            else:
                ops.append(('measure_cp', 0, [rng.choice((10, 32, 63, 65, 97, 233, 0x20AC, 0x1F600, rng.randrange(0, 300))) for _ in range(rng.randrange(0, 20))],
                            f32(rng.uniform(0.0, 50.0)), f32(rng.uniform(-3.0, 6.0))))
        add(f'random-measure-{k}', 4, 4, ops)
    rotations = [d for d in range(-360, 361, 15)]
    for k in range(8):
        w, h = rng.choice(((64, 40), (80, 32), (48, 48)))
        ops = [('begin',), ('clear', rcolor()), ('default', 0), ('spacing', u32(rng.randrange(-3, 8)))]
        for _ in range(7):
            kind = rng.randrange(4)
            if kind == 0:
                ops.append(('text', rtext(1, 10), float(rng.randrange(-10, w)), float(rng.randrange(-8, h)), float(rng.randrange(1, 32)), rcolor()))
            elif kind == 1:
                ops.append(('text_ex', 0, rtext(1, 10), f32(rng.uniform(-10, w)), f32(rng.uniform(-8, h)), f32(rng.uniform(4, 30)),
                            f32(rng.uniform(-2, 5)), rcolor()))
            elif kind == 2:
                ops.append(('text_pro', 0, rtext(1, 8), f32(rng.uniform(0, w)), f32(rng.uniform(0, h)), f32(rng.uniform(-10, 10)),
                            f32(rng.uniform(-10, 10)), float(rng.choice(rotations)), f32(rng.uniform(6, 24)), f32(rng.uniform(-1, 4)), rcolor()))
            else:
                ops.append(('codepoints', 0, [rng.choice((10, 32, 63, 65, 87, 105, 233, 0x20AC, rng.randrange(0, 300))) for _ in range(rng.randrange(1, 8))],
                            f32(rng.uniform(-5, w)), f32(rng.uniform(-5, h)), f32(rng.uniform(5, 25)), f32(rng.uniform(-1, 3)), rcolor()))
        if k % 4 == 3:
            ops += [('filter', 0, rng.choice((1, 2))), ('text_ex', 0, rtext(1, 6, False), f32(rng.uniform(0, 20)), f32(rng.uniform(0, 20)),
                                                       f32(rng.uniform(11, 30)), 1.0, rcolor()), ('filter', 0, 0)]
        add(f'random-draw-{k}', w, h, ops + [('end',)])
    for k in range(3):
        ops = [('default', 0), ('spacing', u32(rng.randrange(0, 8)))]
        for _ in range(10):
            kind = rng.randrange(4)
            text = rtext(1, 12) if rng.random() < 0.3 else rtext(1, 12, False)
            if text.count(10) == len(text):
                text = text + T('x')
            if kind == 0:
                ops.append(('image_text', text, float(rng.randrange(10, 41)), rcolor()))
            elif kind == 1:
                ops.append(('image_text_ex', 0, text, f32(rng.uniform(10.0, 40.0)), f32(rng.uniform(0.0, 4.0)), rcolor()))
            elif kind == 2:
                ops.append(('image_draw_text', tp.image(rng.randrange(8, 40), rng.randrange(6, 30), rng.choice((1, 2, 3, 4, 6, 7)), rng.randrange(1000)),
                            text, float(rng.randrange(-20, 30)), float(rng.randrange(-10, 20)), float(rng.randrange(10, 30)), rcolor()))
            else:
                ops.append(('image_draw_text_ex', 0, tp.image(rng.randrange(8, 40), rng.randrange(6, 30), rng.choice((2, 4, 7)), rng.randrange(1000)),
                            text, f32(rng.uniform(-20.0, 30.0)), f32(rng.uniform(-10.0, 20.0)), f32(rng.uniform(10.0, 30.0)), f32(rng.uniform(0.0, 3.0)), rcolor()))
        add(f'random-image-{k}', 4, 4, ops)
    for k in range(4):
        cs, ls, ch = rng.randrange(1, 4), rng.randrange(1, 4), rng.randrange(3, 11)
        rows = [[rng.randrange(1, 9) for _ in range(rng.randrange(1, 9))] for _ in range(rng.randrange(1, 4))]
        width = max(cs + sum(w + cs for w in row) for row in rows) + rng.randrange(0, 5)
        height = ls + len(rows) * (ch + ls) + rng.randrange(0, 3)
        spec = font_image(width, height, rng.choice((KEY, MAGENTA)), cs, ls, ch, rows, seed=rng.randrange(1000), alpha=rng.random() < 0.5,
                          fmt=rng.choice((7, 7, 4, 5)))
        first = rng.choice((32, 33, 48, 65))
        n = scan_font(spec, first)
        if not isinstance(n, int):
            raise ProbeFailure(f'font: random font {k} scans as {n}')
        text = bytes(rng.randrange(first, first + n) for _ in range(rng.randrange(1, 9)))
        add(f'random-font-{k}', 64, 40, [('begin',), ('clear', rcolor()), ('load', 0, spec, spec['key'], first), ('info', 0), ('table', 0),
                                         ('measure', 0, list(text) + [10] + list(text[:2]), f32(rng.uniform(1.0, 30.0)), f32(rng.uniform(-2.0, 4.0))),
                                         ('text_ex', 0, text, f32(rng.uniform(0, 30)), f32(rng.uniform(0, 20)), f32(rng.uniform(4.0, 24.0)),
                                          f32(rng.uniform(-1.0, 3.0)), rcolor()), ('filter', 0, rng.choice((1, 2, 3))),
                                         ('text_ex', 0, text, f32(rng.uniform(0, 30)), f32(rng.uniform(15, 35)), f32(rng.uniform(4.0, 24.0)),
                                          f32(rng.uniform(-1.0, 3.0)), rcolor()),
                                         ('image_text_ex', 0, text, f32(rng.uniform(float(ch), 3.0 * ch)), f32(rng.uniform(0.0, 3.0)), rcolor()),
                                         ('end',)])

    # Contracts: the frame becomes undefined.
    add('draw-text-nan', 16, 12, [('text', T('x'), NAN, 1.0, 10.0, WHITE)], contract=True)
    add('draw-text-huge', 16, 12, [('text', T('x'), 1.0, 3e9, 10.0, WHITE)], contract=True)
    add('draw-text-size-nan', 16, 12, [('text', T('x'), 1.0, 1.0, NAN, WHITE)], contract=True)
    add('draw-pro-unverified', 16, 12, [('default', 0), ('text_pro', 0, T('x'), 8.0, 6.0, 0.0, 0.0, 13.0, 10.0, 1.0, WHITE)])
    add('draw-pro-nan', 16, 12, [('default', 0), ('text_pro', 0, T('x'), 8.0, 6.0, 0.0, 0.0, NAN, 10.0, 1.0, WHITE)])
    return out


def rotation_arguments(op):
    if op[0] == 'text_pro':
        return [f32(op[7] * fp.DEG2RAD)]
    if op[0] == 'mode2d':
        return [f32(op[5] * fp.DEG2RAD)]
    return []


def refused_scene(scene, libm):
    """A scene whose frame Jonlib leaves undefined: declared contracts and
    rotations outside the host profile's verified sinf/cosf arguments."""
    if scene['contract']:
        return True
    return not all(fp.accepted(libm, x) for op in scene['ops'] for x in rotation_arguments(op))


def declared(op):
    return op[-1] == 'R'


def load_refused(op):
    return op[0] == 'load' and scan_font(op[2], op[4]) == 'refused'


# -----------------------------------------------------------------------------
# Native reference

C_PREFIX = r'''#include "raylib.h"
#include "rlgl.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static float bf(unsigned u) { float f; memcpy(&f, &u, 4); return f; }
static unsigned fb(float f) { unsigned u; memcpy(&u, &f, 4); return u; }
static void hexbytes(const unsigned char *p, int n) { for (int i = 0; i < n; i++) printf("%02x", p[i]); }
static void dump(int w, int h)
{
    unsigned char *p = malloc(w*h*4);
    rlCopyFramebuffer(0, 0, w, h, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, p);
    for (int i = 0; i < w*h; i++) { unsigned char t = p[4*i]; p[4*i] = p[4*i + 2]; p[4*i + 2] = t; }
    printf(" F ");
    hexbytes(p, w*h*4);
    printf("\n");
    free(p);
}
static void image_out(Image im)
{
    if ((im.data == NULL) || (im.width <= 0) || (im.height <= 0)) { printf(" i-"); return; }
    printf(" i%d,%d,%d,", im.width, im.height, im.format);
    hexbytes(im.data, GetPixelDataSize(im.width, im.height, im.format));
}
static void vec(Vector2 v) { printf(" v%u,%u", fb(v.x), fb(v.y)); }
static void font_info(Font f) { printf(" f%d,%d,%d,%u,%d", f.baseSize, f.glyphCount, f.glyphPadding, f.texture.id, (int)IsFontValid(f)); }
static void glyph_row(GlyphInfo g, Rectangle r)
{
    printf(",%d,%d,%d,%d,%u,%u,%u,%u", g.value, g.offsetX, g.offsetY, g.advanceX, fb(r.x), fb(r.y), fb(r.width), fb(r.height));
    image_out(g.image);
}
static void table(Font f)
{
    printf(" T");
    for (int i = 0; i < f.glyphCount; i++) { printf(" "); glyph_row(f.glyphs[i], f.recs[i]); }
}
static void glyph(Font f, int cp)
{
    printf(" g%d", GetGlyphIndex(f, cp));
    glyph_row(GetGlyphInfo(f, cp), GetGlyphAtlasRec(f, cp));
}
static Image img_from(int w, int h, int format, const unsigned char *bytes, int n)
{
    Image img = { 0 };
    img.data = malloc(n); memcpy(img.data, bytes, n);
    img.width = w; img.height = h; img.mipmaps = 1; img.format = format;
    return img;
}
static Image font_image(int w, int h, unsigned key, unsigned seed, int alpha, const int *boxes, int n, int format)
{
    Image img = GenImageColor(w, h, GetColor(key));
    Color *p = img.data;
    for (int b = 0; b < n; b++)
        for (int y = boxes[4*b + 1]; y < boxes[4*b + 1] + boxes[4*b + 3]; y++)
            for (int x = boxes[4*b]; x < boxes[4*b] + boxes[4*b + 2]; x++)
            {
                unsigned v = ((unsigned)x*73856093u) ^ ((unsigned)y*19349663u) ^ (seed*83492791u);
                v |= 0x40404000u;
                unsigned c = alpha ? ((v & 0xFFFFFF00u) | (128u + (v & 127u))) : (v | 255u);
                if (c == key) c ^= 0x100u;
                p[y*w + x] = GetColor(c);
            }
    if (format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) ImageFormat(&img, format);
    return img;
}
'''


def drawfps_source(raylib_source):
    """DrawFPS's body from the pinned rtext.c with GetFPS() replaced by a parameter."""
    source = (raylib_source / 'src/rtext.c').read_text()
    start = source.index('void DrawFPS(int posX, int posY)')
    body = source[start:source.index('\n}\n', start) + 3]
    if body.count('GetFPS()') != 1:
        raise ProbeFailure('font: the pinned DrawFPS no longer calls GetFPS() once')
    return body.replace('void DrawFPS(int posX, int posY)', 'static void DrawFPSWith(int fpsValue, int posX, int posY)').replace('GetFPS()', 'fpsValue')


def ctext(data):
    return '"' + ''.join(f'\\{c:03o}' for c in data) + '"'


def cints(values):
    return '(int[]){ ' + ''.join(f'{v - (1 << 32) if v >= 1 << 31 else v}, ' for v in values) + '0 }'


def cint(value):
    return str(value - (1 << 32) if value >= 1 << 31 else value)


def cimg(spec):
    data = tp.image_bytes(spec)
    return f'img_from({spec["width"]}, {spec["height"]}, {spec["format"]}, (const unsigned char[]){{{",".join(map(str, data))}}}, {len(data)})'


def cfont_image(spec):
    boxes = [v for box in spec['boxes'] for v in box] or [0]
    return (f'font_image({spec["width"]}, {spec["height"]}, {spec["key"]}u, {spec["seed"]}u, {int(spec["alpha"])}, (const int[]){{{",".join(map(str, boxes))}}}, '
            f'{len(spec["boxes"])}, {spec["format"]})')


def c_op(op):
    name, a = op[0], op[1:]
    if declared(op) or load_refused(op):
        return {'measure_text': '    printf(" R");', 'image_text': '    printf(" i-");', 'image_text_ex': '    printf(" i-");',
                'image_draw_text': '    printf(" R");', 'image_draw_text_ex': '    printf(" R");', 'load': '    printf(" L-");'}[name]
    calls = {
        'begin': lambda: 'BeginDrawing();', 'end': lambda: 'EndDrawing();', 'clear': lambda: f'ClearBackground({fp.cc(a[0])});',
        'rect': lambda: f'DrawRectangle({fp.ci(a[0])}, {fp.ci(a[1])}, {fp.ci(a[2])}, {fp.ci(a[3])}, {fp.cc(a[4])});',
        'mode2d': lambda: f'BeginMode2D((Camera2D){{ {fp.cv(a[0], a[1])}, {fp.cv(a[2], a[3])}, {cf(a[4])}, {cf(a[5])} }});', 'end2d': lambda: 'EndMode2D();',
        'scissor': lambda: f'BeginScissorMode({fp.ci(a[0])}, {fp.ci(a[1])}, {fp.ci(a[2])}, {fp.ci(a[3])});', 'end_scissor': lambda: 'EndScissorMode();',
        'spacing': lambda: f'SetTextLineSpacing({cint(a[0])});',
        'text': lambda: f'DrawText({ctext(a[0])}, {fp.ci(a[1])}, {fp.ci(a[2])}, {fp.ci(a[3])}, {fp.cc(a[4])});',
        'fps': lambda: (f'printf(" P%d", GetFPS()); DrawFPS({fp.ci(a[0])}, {fp.ci(a[1])});' if a[2] == 0 else
                        f'printf(" P{cint(a[2])}"); DrawFPSWith({cint(a[2])}, {fp.ci(a[0])}, {fp.ci(a[1])});'),
        'measure_text': lambda: f'printf(" t%d", MeasureText({ctext(a[0])}, {fp.ci(a[1])}));',
        'image_text': lambda: f'{{ Image im = ImageText({ctext(a[0])}, {fp.ci(a[1])}, {fp.cc(a[2])}); image_out(im); UnloadImage(im); }}',
        'image_draw_text': lambda: (f'{{ Image im = {cimg(a[0])}; ImageDrawText(&im, {ctext(a[1])}, {fp.ci(a[2])}, {fp.ci(a[3])}, {fp.ci(a[4])}, '
                                    f'{fp.cc(a[5])}); image_out(im); UnloadImage(im); }}'),
        'default': lambda: f'f[{a[0]}] = GetFontDefault();',
        'load': lambda: (f'{{ Image src = {cfont_image(a[1])}; f[{a[0]}] = LoadFontFromImage(src, GetColor({a[2]}u), {cint(a[3])}); UnloadImage(src); '
                         f'printf(" L"); font_info(f[{a[0]}]); }}'),
        'unload': lambda: f'UnloadFont(f[{a[0]}]); f[{a[0]}] = (Font){{ 0 }};',
        'filter': lambda: f'SetTextureFilter(f[{a[0]}].texture, {a[1]});',
        'info': lambda: f'font_info(f[{a[0]}]);', 'table': lambda: f'table(f[{a[0]}]);', 'glyph': lambda: f'glyph(f[{a[0]}], {cint(a[1])});',
        'measure': lambda: f'vec(MeasureTextEx(f[{a[0]}], {ctext(a[1])}, {cf(a[2])}, {cf(a[3])}));',
        'measure_cp': lambda: f'vec(MeasureTextCodepoints(f[{a[0]}], {cints(a[1])}, {len(a[1])}, {cf(a[2])}, {cf(a[3])}));',
        'text_ex': lambda: f'DrawTextEx(f[{a[0]}], {ctext(a[1])}, {fp.cv(a[2], a[3])}, {cf(a[4])}, {cf(a[5])}, {fp.cc(a[6])});',
        'text_pro': lambda: (f'DrawTextPro(f[{a[0]}], {ctext(a[1])}, {fp.cv(a[2], a[3])}, {fp.cv(a[4], a[5])}, {cf(a[6])}, {cf(a[7])}, {cf(a[8])}, '
                             f'{fp.cc(a[9])});'),
        'codepoint': lambda: f'DrawTextCodepoint(f[{a[0]}], {cint(a[1])}, {fp.cv(a[2], a[3])}, {cf(a[4])}, {fp.cc(a[5])});',
        'codepoints': lambda: f'DrawTextCodepoints(f[{a[0]}], {cints(a[1])}, {len(a[1])}, {fp.cv(a[2], a[3])}, {cf(a[4])}, {cf(a[5])}, {fp.cc(a[6])});',
        'image_text_ex': lambda: f'{{ Image im = ImageTextEx(f[{a[0]}], {ctext(a[1])}, {cf(a[2])}, {cf(a[3])}, {fp.cc(a[4])}); image_out(im); UnloadImage(im); }}',
        'image_draw_text_ex': lambda: (f'{{ Image im = {cimg(a[1])}; ImageDrawTextEx(&im, f[{a[0]}], {ctext(a[2])}, {fp.cv(a[3], a[4])}, {cf(a[5])}, '
                                       f'{cf(a[6])}, {fp.cc(a[7])}); image_out(im); UnloadImage(im); }}'),
    }
    return '    ' + calls[name]()


def c_scene(scene):
    lines = [f'    {{ Font f[3] = {{ 0 }}; (void)f;', f'    InitWindow({scene["width"]}, {scene["height"]}, "");', '    SetTextLineSpacing(2);', '    printf("S");']
    lines += [c_op(op) for op in scene['ops']]
    lines += [f'    dump({scene["width"]}, {scene["height"]});', '    CloseWindow(); }']
    return '\n'.join(lines)


# -----------------------------------------------------------------------------
# Bend candidate

PROGRAM = fp.PROGRAM.replace('import ../../src/trig.bend as Trig\n', 'import ../../src/trig.bend as Trig\nimport ../../src/text.bend as TC\n'
                             'import ../../src/fonts.bend as FontCore\n') + '''
def hex.byte(+b: U32, rest: String) -> String:
  SCon{hex.digit(((b >> 4n) .&. 15 : U32)), SCon{hex.digit((b .&. 15 : U32)), rest}}

def hex.bytes.go(reversed: List<U32>, acc: String) -> String:
  match reversed:
    case Nil{}: acc
    case Con{+b, rest}: hex.bytes.go(rest, hex.byte(b, acc))

def hex.bytes(bytes: List<U32>) -> String:
  hex.bytes.go(List.reverse(&1, U32, bytes), "")

def sint(+v: U32) -> String:
  Bool.pick(String, (v >= 2147483648 : U32), "-" ++ U32.show((0 - v : U32)), U32.show(v))

def fbits(+x: F32) -> String:
  U32.show(F32.bits(x))

def image.out(s: J.Surface) -> String:
  J.Surface{+w, +h, +format, pixels} = s
  " i" ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(format) ++ "," ++ hex.bytes(J.Surface.raw(~&1, J.Surface{w, h, format, pixels}))

def image.maybe(s: Maybe<J.Surface>) -> String:
  match s:
    case None{}: " i-"
    case Some{surface}: image.out(surface)

def pattern.byte(+i: U32, +seed: U32, +mask: U32, +period: U32) -> U32:
  ((((i * 2654435761 + seed * 40503 : U32) >> 13n) .&. 255) .|. ((mask >> U32.to_nat((8 * (i % period) : U32))) .&. 255) : U32)

def pattern(n: Nat, +i: U32, +seed: U32, +mask: U32, +period: U32, +zero: Bool) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+rest: Con{Bool.pick(U32, zero, 0, pattern.byte(i, seed, mask, period)), pattern(rest, (i + 1 : U32), seed, mask, period, zero)}

type Img is Data:
  Img{width: U32, height: U32, format: U32, bpp: U32, seed: U32, mask: U32, period: U32, zero: Bool}

def Img.surface(+i: Img) -> Maybe<J.Surface>:
  Img{width, height, format, bpp, seed, mask, period, zero} = i
  J.Surface.from_bytes(width, height, format, pattern(U32.to_nat((width * height * bpp : U32)), 0, seed, mask, period, zero))

# XNA-style font images: boxes (x, y, w, h) of hashed colors over the key.
type FontImg is Data:
  FontImg{width: U32, height: U32, key: U32, seed: U32, alpha: Bool, boxes: +List<U32>, format: U32}

def fimg.color(+x: U32, +y: U32, +seed: U32, +alpha: Bool, +key: U32) -> U32:
  +v = (((x * 73856093) .^. (y * 19349663) .^. (seed * 83492791)) .|. 1077952512 : U32)
  +c = Bool.pick(U32, alpha, ((v .&. 4294967040) .|. (128 + (v .&. 127)) : U32), (v .|. 255 : U32))
  Bool.pick(U32, U32.is_eq(c, key), (c .^. 256 : U32), c)

def fimg.row(n: Nat, +x: U32, +y: U32, +w: U32, +seed: U32, +alpha: Bool, +key: U32, out: Array<U32>) -> Array<U32>:
  match n:
    case 0n: out
    case 1n+k: fimg.row(k, (x + 1 : U32), y, w, seed, alpha, key, Array.set(U32, out, (y * w + x : U32), fimg.color(x, y, seed, alpha, key)))

def fimg.rows(n: Nat, +x: U32, +y: U32, +bw: Nat, +w: U32, +seed: U32, +alpha: Bool, +key: U32, out: Array<U32>) -> Array<U32>:
  match n:
    case 0n: out
    case 1n+k: fimg.rows(k, x, (y + 1 : U32), bw, w, seed, alpha, key, fimg.row(bw, x, y, w, seed, alpha, key, out))

def fimg.boxes(boxes: +List<U32>, +w: U32, +seed: U32, +alpha: Bool, +key: U32, out: Array<U32>) -> Array<U32>:
  match boxes:
    case Con{+x, Con{+y, Con{+bw, Con{+bh, rest}}}}:
      fimg.boxes(rest, w, seed, alpha, key, fimg.rows(U32.to_nat(bh), x, y, U32.to_nat(bw), w, seed, alpha, key, out))
    case _: out

def fimg.result(r: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match r:
    case Done{s}: Some{s}
    case Fail{_}: None{}

def fimg.formatted(+format: U32, made: J.Surface) -> Maybe<J.Surface>:
  fimg.result(J.Surface.format(made, format))

def FontImg.surface(+i: FontImg) -> Maybe<J.Surface>:
  FontImg{w, h, key, seed, alpha, boxes, format} = i
  fimg.formatted(format, J.Surface{w, h, 7, J.Words{fimg.boxes(boxes, w, seed, alpha, key, Array.new(U32, J.Storage.depth((w * h : U32)), key))}})

type FontOp is Data:
  FFilter{filter: U32}
  FInfo{}
  FTable{}
  FGlyph{cp: U32}
  FMeasure{text: +List<U32>, size: F32, spacing: F32}
  FMeasureCp{cps: +List<U32>, size: F32, spacing: F32}
  FTextEx{text: +List<U32>, x: F32, y: F32, size: F32, spacing: F32, tint: U32}
  FTextPro{text: +List<U32>, x: F32, y: F32, ox: F32, oy: F32, rotation: F32, size: F32, spacing: F32, tint: U32}
  FCodepoint{cp: U32, x: F32, y: F32, size: F32, tint: U32}
  FCodepoints{cps: +List<U32>, x: F32, y: F32, size: F32, spacing: F32, tint: U32}
  FImageTextEx{text: +List<U32>, size: F32, spacing: F32, tint: U32}
  FImageDrawTextEx{image: Img, text: +List<U32>, x: F32, y: F32, size: F32, spacing: F32, tint: U32}

type Op is Data:
  OBegin{}
  OEnd{}
  OClear{color: U32}
  ORect{x: F32, y: F32, w: F32, h: F32, color: U32}
  OMode2D{camera: J.Camera2D}
  OEnd2D{}
  OScissor{x: F32, y: F32, w: F32, h: F32}
  OEndScissor{}
  OSpacing{value: U32}
  OText{text: +List<U32>, x: F32, y: F32, size: F32, color: U32}
  OFps{x: F32, y: F32, fps: U32}
  OMeasureText{text: +List<U32>, size: F32}
  OImageText{text: +List<U32>, size: F32, color: U32}
  OImageDrawText{image: Img, text: +List<U32>, x: F32, y: F32, size: F32, color: U32}
  ODefault{slot: U32}
  OLoad{slot: U32, image: FontImg, key: U32, first: U32}
  OUnload{slot: U32}
  OFont{slot: U32, call: FontOp}

type St is Type:
  St{frame: J.Frame, f0: Maybe<J.Font>, f1: Maybe<J.Font>, f2: Maybe<J.Font>, line: U32, log: +List<String>}

def info.text(+valid: Bool, info: J.FontInfo) -> String:
  J.FontInfo{base, count, padding, texture} = info
  " f" ++ sint(base) ++ "," ++ sint(count) ++ "," ++ sint(padding) ++ "," ++ U32.show(texture) ++ "," ++ Bool.pick(String, valid, "1", "0")

def info.with(+valid: Bool, r: J.Font & J.FontInfo) -> (J.Font & String):
  (font, info) = r
  (font, info.text(valid, info))

def info.font(r: J.Font & Bool) -> (J.Font & String):
  (font, +valid) = r
  info.with(valid, J.Font.info(font))

def glyph.row(+value: U32, +ox: U32, +oy: U32, +adv: U32, +rec: J.Rectangle, image: String) -> String:
  J.Rectangle{x, y, w, h} = rec
  "," ++ sint(value) ++ "," ++ sint(ox) ++ "," ++ sint(oy) ++ "," ++ sint(adv) ++ "," ++ fbits(x) ++ "," ++ fbits(y) ++ "," ++ fbits(w) ++ "," ++ fbits(h) ++ image

def table.glyph(+g: FontCore.Glyph, +rec: J.Rectangle, r: J.Surface & Maybe<J.Surface>) -> J.Surface & String:
  (atlas, image) = r
  (atlas, " " ++ glyph.row(FontCore.Glyph.value(g), FontCore.Glyph.offset_x(g), FontCore.Glyph.offset_y(g), FontCore.Glyph.advance_x(g), rec, image.maybe(image)))

# Each glyph's row; the pair is the previous glyph's (atlas, text).
def table.go(glyphs: +List<FontCore.Glyph>, acc: +List<String>, r: J.Surface & String) -> J.Surface & +List<String>:
  match glyphs r:
    case Nil{} Tuple{atlas, text}: (atlas, Con{text, acc})
    case Con{+g, rest} Tuple{atlas, text}: table.go(rest, Con{text, acc}, table.glyph(g, J.Font.glyph.rec(g), J.Surface.extract(atlas, J.Font.glyph.rec(g))))
'''

NEW_BEND = '''def table.done(+base: U32, +padding: U32, +glyphs: +List<FontCore.Glyph>, texture: J.Texture, r: J.Surface & +List<String>) -> J.Font & String:
  (atlas, texts) = r
  (J.Font{base, padding, glyphs, texture, atlas}, " T" ++ String.concat(List.reverse(&2, String, texts)))

def table(font: J.Font) -> J.Font & String:
  J.Font{+base, +padding, +glyphs, texture, atlas} = font
  table.done(base, padding, glyphs, texture, table.go(glyphs, Nil{}, (atlas, "")))

def glyph.info.some(+index: U32, +rec: J.Rectangle, g: J.GlyphInfo) -> String:
  J.GlyphInfo{value, ox, oy, adv, image} = g
  " g" ++ U32.show(index) ++ glyph.row(value, ox, oy, adv, rec, image.out(image))

def glyph.info(+index: U32, +rec: J.Rectangle, info: Maybe<J.GlyphInfo>) -> String:
  match info:
    case None{}: " g" ++ U32.show(index) ++ ",-"
    case Some{g}: glyph.info.some(index, rec, g)

def glyph.rec(+index: U32, info: Maybe<J.GlyphInfo>, r: J.Font & J.Rectangle) -> J.Font & String:
  (font, +rec) = r
  (font, glyph.info(index, rec, info))

def glyph.got(+cp: U32, +index: U32, r: J.Font & Maybe<J.GlyphInfo>) -> J.Font & String:
  (font, info) = r
  glyph.rec(index, info, J.Font.glyph_atlas_rec(font, cp))

def glyph.indexed(+cp: U32, r: J.Font & U32) -> J.Font & String:
  (font, +index) = r
  glyph.got(cp, index, J.Font.glyph_info(font, cp))

def vec(r: J.Font & M.Vector2) -> J.Font & String:
  (font, v) = r
  M.Vector2{x, y} = v
  (font, " v" ++ fbits(x) ++ "," ++ fbits(y))

def drawn(r: J.Frame & J.Font) -> (J.Frame & J.Font) & String:
  (r, "")

def keep(frame: J.Frame, r: J.Font & String) -> (J.Frame & J.Font) & String:
  (font, text) = r
  ((frame, font), text)

def image.font(frame: J.Frame, r: J.Font & Maybe<J.Surface>) -> (J.Frame & J.Font) & String:
  (font, image) = r
  ((frame, font), image.maybe(image))

def image.drawn(frame: J.Frame, r: Result<&1, &1, (J.Surface & J.Font) & J.Surface.Error, J.Surface & J.Font>) -> (J.Frame & J.Font) & String:
  match r:
    case Done{Tuple{image, font}}: ((frame, font), image.out(image))
    case Fail{Tuple{Tuple{_, font}, _}}: ((frame, font), " R")

def image.draw_ex(+line: U32, frame: J.Frame, font: J.Font, target: Maybe<J.Surface>, text: +List<U32>, +x: F32, +y: F32, +size: F32, +spacing: F32, +tint: U32) -> (J.Frame & J.Font) & String:
  match target:
    case None{}: ((frame, font), " no-image")
    case Some{dst}: image.drawn(frame, J.Font.image_draw_text_ex_spaced(line, dst, font, TC.string(text), M.Vector2{x, y}, size, spacing, tint))

def fontop(call: FontOp, +line: U32, frame: J.Frame, font: J.Font) -> (J.Frame & J.Font) & String:
  match call:
    case FFilter{filter}: ((frame, J.Font.set_filter(font, filter)), "")
    case FInfo{}: keep(frame, info.font(J.Font.is_valid(font)))
    case FTable{}: keep(frame, table(font))
    case FGlyph{+cp}: keep(frame, glyph.indexed(cp, J.Font.glyph_index(font, cp)))
    case FMeasure{text, size, spacing}: keep(frame, vec(J.Font.measure_text_ex_spaced(line, font, TC.string(text), size, spacing)))
    case FMeasureCp{cps, size, spacing}: keep(frame, vec(J.Font.measure_text_codepoints_spaced(line, font, cps, size, spacing)))
    case FTextEx{text, x, y, size, spacing, tint}: drawn(J.Draw.text_ex_spaced(line, frame, font, TC.string(text), M.Vector2{x, y}, size, spacing, tint))
    case FTextPro{text, x, y, ox, oy, rotation, size, spacing, tint}:
      drawn(J.Draw.text_pro_spaced_for(libm(), line, frame, font, TC.string(text), M.Vector2{x, y}, M.Vector2{ox, oy}, rotation, size, spacing, tint))
    case FCodepoint{cp, x, y, size, tint}: drawn(J.Draw.text_codepoint(frame, font, cp, M.Vector2{x, y}, size, tint))
    case FCodepoints{cps, x, y, size, spacing, tint}: drawn(J.Draw.text_codepoints_spaced(line, frame, font, cps, M.Vector2{x, y}, size, spacing, tint))
    case FImageTextEx{text, size, spacing, tint}: image.font(frame, J.Font.image_text_ex_spaced(line, font, TC.string(text), size, spacing, tint))
    case FImageDrawTextEx{image, text, x, y, size, spacing, tint}: image.draw_ex(line, frame, font, Img.surface(image), text, x, y, size, spacing, tint)

def slot.pair(text: String, pair: J.Frame & J.Font) -> (J.Frame & Maybe<J.Font>) & String:
  (frame, font) = pair
  ((frame, Some{font}), text)

def slot.some(r: (J.Frame & J.Font) & String) -> (J.Frame & Maybe<J.Font>) & String:
  (pair, text) = r
  slot.pair(text, pair)

def slot.run(frame: J.Frame, font: Maybe<J.Font>, +line: U32, call: FontOp) -> (J.Frame & Maybe<J.Font>) & String:
  match font:
    case None{}: ((frame, None{}), " -")
    case Some{f}: slot.some(fontop(call, line, frame, f))

def St.put.at(slot: U32, text: String, frame: J.Frame, font: Maybe<J.Font>, f0: Maybe<J.Font>, f1: Maybe<J.Font>, f2: Maybe<J.Font>, +line: U32, log: +List<String>) -> St:
  match slot:
    case 0: St{frame, font, f1, f2, line, Con{text, log}}
    case 1: St{frame, f0, font, f2, line, Con{text, log}}
    case _: St{frame, f0, f1, font, line, Con{text, log}}

def St.put.pair(slot: U32, text: String, pair: J.Frame & Maybe<J.Font>, f0: Maybe<J.Font>, f1: Maybe<J.Font>, f2: Maybe<J.Font>, +line: U32, log: +List<String>) -> St:
  (frame, font) = pair
  St.put.at(slot, text, frame, font, f0, f1, f2, line, log)

def St.put(slot: U32, r: (J.Frame & Maybe<J.Font>) & String, f0: Maybe<J.Font>, f1: Maybe<J.Font>, f2: Maybe<J.Font>, +line: U32, log: +List<String>) -> St:
  (pair, text) = r
  St.put.pair(slot, text, pair, f0, f1, f2, line, log)

def St.font.at(slot: U32, frame: J.Frame, f0: Maybe<J.Font>, f1: Maybe<J.Font>, f2: Maybe<J.Font>, +line: U32, log: +List<String>, call: FontOp) -> St:
  match slot:
    case 0: St.put(0, slot.run(frame, f0, line, call), None{}, f1, f2, line, log)
    case 1: St.put(1, slot.run(frame, f1, line, call), f0, None{}, f2, line, log)
    case _: St.put(2, slot.run(frame, f2, line, call), f0, f1, None{}, line, log)

def St.font(s: St, +slot: U32, call: FontOp) -> St:
  St{frame, f0, f1, f2, line, log} = s
  St.font.at(slot, frame, f0, f1, f2, line, log, call)

def load.info(frame: J.Frame, r: J.Font & String) -> (J.Frame & Maybe<J.Font>) & String:
  (font, text) = r
  ((frame, Some{font}), " L" ++ text)

def load.text(r: J.Frame & Maybe<J.Font>) -> (J.Frame & Maybe<J.Font>) & String:
  match r:
    case Tuple{frame, None{}}: ((frame, None{}), " L-")
    case Tuple{frame, Some{font}}: load.info(frame, info.font(J.Font.is_valid(font)))

def load.dropped.rest(frame: J.Frame, rest: J.Surface & Maybe<J.Font>) -> J.Frame & Maybe<J.Font>:
  (_, font) = rest
  (frame, font)

def load.dropped(r: J.Frame & (J.Surface & Maybe<J.Font>)) -> J.Frame & Maybe<J.Font>:
  (frame, rest) = r
  load.dropped.rest(frame, rest)

def load.image(frame: J.Frame, image: Maybe<J.Surface>, +key: U32, +first: U32) -> (J.Frame & Maybe<J.Font>) & String:
  match image:
    case None{}: ((frame, None{}), " no-image")
    case Some{s}: load.text(load.dropped(J.Font.load_from_image(frame, s, key, first)))

def St.load.at(slot: U32, frame: J.Frame, f0: Maybe<J.Font>, f1: Maybe<J.Font>, f2: Maybe<J.Font>, +line: U32, log: +List<String>, +image: FontImg, +key: U32, +first: U32) -> St:
  match slot:
    case 0: St.put(0, load.image(frame, FontImg.surface(image), key, first), None{}, f1, f2, line, log)
    case 1: St.put(1, load.image(frame, FontImg.surface(image), key, first), f0, None{}, f2, line, log)
    case _: St.put(2, load.image(frame, FontImg.surface(image), key, first), f0, f1, None{}, line, log)

def St.load(s: St, +slot: U32, +image: FontImg, +key: U32, +first: U32) -> St:
  St{frame, f0, f1, f2, line, log} = s
  St.load.at(slot, frame, f0, f1, f2, line, log, image, key, first)

def unload.one(frame: J.Frame, font: Maybe<J.Font>) -> (J.Frame & Maybe<J.Font>) & String:
  match font:
    case None{}: ((frame, None{}), "")
    case Some{f}: ((J.Font.unload(frame, f), None{}), "")

def St.unload.at(slot: U32, frame: J.Frame, f0: Maybe<J.Font>, f1: Maybe<J.Font>, f2: Maybe<J.Font>, +line: U32, log: +List<String>) -> St:
  match slot:
    case 0: St.put(0, unload.one(frame, f0), None{}, f1, f2, line, log)
    case 1: St.put(1, unload.one(frame, f1), f0, None{}, f2, line, log)
    case _: St.put(2, unload.one(frame, f2), f0, f1, None{}, line, log)

def St.unload(s: St, +slot: U32) -> St:
  St{frame, f0, f1, f2, line, log} = s
  St.unload.at(slot, frame, f0, f1, f2, line, log)

def St.default.at(slot: U32, frame: J.Frame, f0: Maybe<J.Font>, f1: Maybe<J.Font>, f2: Maybe<J.Font>, +line: U32, log: +List<String>) -> St:
  match slot:
    case 0: St{frame, Some{J.Font.default()}, f1, f2, line, log}
    case 1: St{frame, f0, Some{J.Font.default()}, f2, line, log}
    case _: St{frame, f0, f1, Some{J.Font.default()}, line, log}

def St.default(s: St, +slot: U32) -> St:
  St{frame, f0, f1, f2, line, log} = s
  St.default.at(slot, frame, f0, f1, f2, line, log)

def St.note(s: St, text: String) -> St:
  St{frame, f0, f1, f2, line, log} = s
  St{frame, f0, f1, f2, line, Con{text, log}}

def St.frame(s: St, f: J.Frame -> U32 -> J.Frame) -> St:
  St{frame, f0, f1, f2, +line, log} = s
  St{f(frame, line), f0, f1, f2, line, log}

def St.spacing(s: St, +value: U32) -> St:
  St{frame, f0, f1, f2, _, log} = s
  St{frame, f0, f1, f2, value, log}

# Logs f(textLineSpacing).
def St.logged(s: St, f: U32 -> String) -> St:
  St{frame, f0, f1, f2, +line, log} = s
  St{frame, f0, f1, f2, line, Con{f(line), log}}

def measure.text(m: Maybe<U32>) -> String:
  match m:
    case None{}: " R"
    case Some{v}: " t" ++ sint(v)

def image.draw.result(r: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> String:
  match r:
    case Done{image}: image.out(image)
    case Fail{_}: " R"

def image.draw(+line: U32, target: Maybe<J.Surface>, text: +List<U32>, +x: F32, +y: F32, +size: F32, +color: U32) -> String:
  match target:
    case None{}: " no-image"
    case Some{dst}: image.draw.result(J.Font.image_draw_text_spaced(line, dst, TC.string(text), x, y, size, color))

def step.frame(op: Op, frame: J.Frame, +line: U32) -> J.Frame:
  match op:
    case OBegin{}: J.Frame.begin_drawing(frame)
    case OEnd{}: J.Frame.end_drawing(frame)
    case OClear{color}: J.Frame.clear_background(frame, color)
    case ORect{x, y, w, h, color}: J.Draw.rectangle(frame, x, y, w, h, color)
    case OMode2D{camera}: J.Frame.begin_mode_2d_for(libm(), frame, camera)
    case OEnd2D{}: J.Frame.end_mode_2d(frame)
    case OScissor{x, y, w, h}: J.Frame.begin_scissor_mode(frame, x, y, w, h)
    case OEndScissor{}: J.Frame.end_scissor_mode(frame)
    case OText{text, x, y, size, color}: J.Draw.text_spaced(line, frame, TC.string(text), x, y, size, color)
    case OFps{x, y, fps}: J.Draw.fps(frame, x, y, fps)
    case _: frame

def step(op: Op, s: St) -> St:
  match op:
    case OSpacing{value}: St.spacing(s, value)
    case OFps{x, y, +fps}: St.frame(St.note(s, " P" ++ sint(fps)), fr => ln => J.Draw.fps(fr, x, y, fps))
    case OMeasureText{text, size}: St.note(s, measure.text(J.Font.measure_text(TC.string(text), size)))
    case OImageText{text, size, color}: St.logged(s, ln => image.maybe(J.Font.image_text_spaced(ln, TC.string(text), size, color)))
    case OImageDrawText{image, text, x, y, size, color}: St.logged(s, ln => image.draw(ln, Img.surface(image), text, x, y, size, color))
    case ODefault{slot}: St.default(s, slot)
    case OLoad{slot, image, key, first}: St.load(s, slot, image, key, first)
    case OUnload{slot}: St.unload(s, slot)
    case OFont{slot, call}: St.font(s, slot, call)
    case _: St.frame(s, fr => ln => step.frame(op, fr, ln))

def exec(ops: +List<Op>, s: St) -> St:
  match ops:
    case Nil{}: s
    case Con{op, rest}: exec(rest, step(op, s))

def scene.finish(r: J.Frame & Maybe<J.Surface>, log: +List<String>) -> String:
  (_, surface) = r
  "S" ++ String.concat(List.reverse(&2, String, log)) ++ " F " ++ hex.maybe(surface)

def St.finish(s: St) -> String:
  St{frame, _, _, _, _, log} = s
  scene.finish(J.Frame.framebuffer(frame), log)

def St.run(ops: +List<Op>, frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: St.finish(exec(ops, St{f, None{}, None{}, None{}, 2, Nil{}}))
'''


def blist(values):
    return '[' + ', '.join(str(v) for v in values) + ']' if values else 'Nil{}'


def bimg(spec):
    return tp.bimg(spec)


def bfont_image(spec):
    boxes = [v for box in spec['boxes'] for v in box]
    return (f'FontImg{{{spec["width"]}, {spec["height"]}, {spec["key"]}, {spec["seed"]}, {"True{}" if spec["alpha"] else "False{}"}, '
            f'{blist(boxes)}, {spec["format"]}}}')


def b_op(op):
    name, a = op[0], op[1:]
    if name == 'load' and load_refused(op):
        pass  # Jonlib must refuse it on its own
    calls = {
        'begin': lambda: 'OBegin{}', 'end': lambda: 'OEnd{}', 'clear': lambda: f'OClear{{{a[0]}}}',
        'rect': lambda: f'ORect{{{bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]}}}',
        'mode2d': lambda: f'OMode2D{{J.Camera2D{{{fp.bv(a[0], a[1])}, {fp.bv(a[2], a[3])}, {bf(a[4])}, {bf(a[5])}}}}}', 'end2d': lambda: 'OEnd2D{}',
        'scissor': lambda: f'OScissor{{{bf(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}}}', 'end_scissor': lambda: 'OEndScissor{}',
        'spacing': lambda: f'OSpacing{{{a[0]}}}',
        'text': lambda: f'OText{{{blist(a[0])}, {bf(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]}}}',
        'fps': lambda: f'OFps{{{bf(a[0])}, {bf(a[1])}, {a[2]}}}',
        'measure_text': lambda: f'OMeasureText{{{blist(a[0])}, {bf(a[1])}}}',
        'image_text': lambda: f'OImageText{{{blist(a[0])}, {bf(a[1])}, {a[2]}}}',
        'image_draw_text': lambda: f'OImageDrawText{{{bimg(a[0])}, {blist(a[1])}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {a[5]}}}',
        'default': lambda: f'ODefault{{{a[0]}}}',
        'load': lambda: f'OLoad{{{a[0]}, {bfont_image(a[1])}, {a[2]}, {a[3]}}}',
        'unload': lambda: f'OUnload{{{a[0]}}}',
    }
    if name in calls:
        return calls[name]()
    fonts = {
        'filter': lambda: f'FFilter{{{a[1]}}}', 'info': lambda: 'FInfo{}', 'table': lambda: 'FTable{}', 'glyph': lambda: f'FGlyph{{{a[1]}}}',
        'measure': lambda: f'FMeasure{{{blist(a[1])}, {bf(a[2])}, {bf(a[3])}}}',
        'measure_cp': lambda: f'FMeasureCp{{{blist(a[1])}, {bf(a[2])}, {bf(a[3])}}}',
        'text_ex': lambda: f'FTextEx{{{blist(a[1])}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {bf(a[5])}, {a[6]}}}',
        'text_pro': lambda: f'FTextPro{{{blist(a[1])}, {", ".join(bf(v) for v in a[2:9])}, {a[9]}}}',
        'codepoint': lambda: f'FCodepoint{{{a[1]}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {a[5]}}}',
        'codepoints': lambda: f'FCodepoints{{{blist(a[1])}, {bf(a[2])}, {bf(a[3])}, {bf(a[4])}, {bf(a[5])}, {a[6]}}}',
        'image_text_ex': lambda: f'FImageTextEx{{{blist(a[1])}, {bf(a[2])}, {bf(a[3])}, {a[4]}}}',
        'image_draw_text_ex': lambda: f'FImageDrawTextEx{{{bimg(a[1])}, {blist(a[2])}, {bf(a[3])}, {bf(a[4])}, {bf(a[5])}, {bf(a[6])}, {a[7]}}}',
    }
    return f'OFont{{{a[0]}, {fonts[name]()}}}'


def strip(op):
    return op[:-1] if declared(op) else op


def b_scene(index, scene):
    return f'def scene.{index}() -> +List<Op>:\n  [' + ',\n    '.join(b_op(strip(op)) for op in scene['ops']) + ']'


def render(libm):
    def build(selected, gpu):
        body = [PROGRAM, f'def libm() -> M.Libm:\n  M.{libm}{{}}', NEW_BEND]
        prints = []
        for index, item in selected:
            body.append(b_scene(index, item))
            prints.append(f'    IO.print(St.run(scene.{index}(), J.Frame.init_window({item["width"]}, {item["height"]})))')
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(prints) + '\n')
        return '\n\n'.join(body)
    return build


def native_rows(probe, items, raylib_source):
    """One row per scene; contract scenes are not run."""
    source = C_PREFIX + drawfps_source(raylib_source) + '\nint main(void)\n{\n    SetTraceLogLevel(LOG_NONE);\n' + \
        '\n'.join(c_scene(s) for s in items) + '\n    return 0;\n}\n'
    lines = [line for line in probe.native(source, 'reference', extra_flags=('-ffp-contract=off',)).splitlines() if line.startswith('S')]
    if len(lines) != len(items):
        raise ProbeFailure(f'font: reference printed {len(lines)} rows for {len(items)} scenes')
    for scene, line in zip(items, lines):
        if any(op[0] == 'fps' and op[3] == 0 for op in scene['ops']) and ' P0' not in line:
            raise ProbeFailure(f'font: {scene["id"]}: GetFPS() is not 0 in the reference build')
    return lines


def charswidth_check(raylib_source):
    import re
    source = (raylib_source / 'src/rtext.c').read_text()
    start = source.index('int charsWidth[224] = {')
    native = [int(v) for v in re.findall(r'\d+', source[start + len('int charsWidth[224] = {'):source.index('};', start)])]
    text = (ROOT / 'src/fonts.bend').read_text()
    bend = [int(v) for line in re.findall(r'case \S+: \[([^\]]*)\]', text.split('def default.widths.chunk', 1)[1].split('\ndef ', 1)[0])
            for v in line.split(',')]
    if native != bend:
        raise ProbeFailure('font: src/fonts.bend charsWidth differs from the pinned rtext.c')


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('font', args, raylib_options=fp.OPTIONS)
    libm = gradient_reference()
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'font: the reference build contains fused multiply-adds: {fused}')
    if fp.font_words(args.raylib_source) != fp.bend_font_words():
        raise ProbeFailure('font: src/frame_font.bend differs from the pinned rtext.c defaultFontData')
    charswidth_check(args.raylib_source)
    items = scenes(libm)
    native_items = [s for s in items if not refused_scene(s, libm)]
    contracts = [s for s in items if s not in native_items]
    if any(op[0] not in ('text', 'text_pro', 'default', 'begin', 'end', 'clear') for s in contracts for op in s['ops']):
        raise ProbeFailure('font: contract scenes may only draw')
    expected_by_id = dict(zip((s['id'] for s in native_items), native_rows(probe, native_items, args.raylib_source)))
    for scene in contracts:
        expected_by_id[scene['id']] = 'S F null'
    expected = [expected_by_id[s['id']] for s in items]
    actions = list(enumerate(items))
    lanes = probe.candidates(render(libm), actions, batch=24, parse=lambda text, selected: [line for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda i: f'scene {items[i]["id"]}')
    refused_ops = sum(declared(op) or load_refused(op) for s in items for op in s['ops'])
    probe.finish(scenes=len(items), compared=len(native_items), contracts=len(contracts), refused_operations=refused_ops, libm=libm,
                 operations=sum(len(s['ops']) for s in items), fused_free_objects=len(fused),
                 scenes_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
