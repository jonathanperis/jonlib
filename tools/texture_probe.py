#!/usr/bin/env python3
"""Compare Jonlib's 2D camera, matrix stack, scissor, blend modes, render
textures and textures with raylib's software renderer.

Same reference as tools/frame_probe.py: pinned raylib on PLATFORM=Memory
(rlgl.h's OpenGL 1.1 path into src/external/rlsw.h) built with
CMAKE_C_FLAGS=-ffp-contract=off, read back with rlCopyFramebuffer (top-down
BGRA, swapped to RGBA). Each scene runs InitWindow and a sequence of
operations: the shapes of tools/frame_probe.py plus BeginMode2D/EndMode2D,
rlPushMatrix/rlPopMatrix/rlLoadIdentity/rlTranslatef/rlRotatef/rlScalef/
rlMultMatrixf, BeginScissorMode/EndScissorMode, BeginBlendMode/EndBlendMode,
LoadTextureFromImage (images built from a byte formula both sides
reproduce), UnloadTexture, UpdateTexture(Rec), SetTextureFilter/Wrap,
GenTextureMipmaps, DrawTexture/V/Ex/Rec/Pro/NPatch, LoadImageFromTexture,
LoadRenderTexture/UnloadRenderTexture and BeginTextureMode/EndTextureMode
with draws of render textures (flipped and not). Info operations append the
texture fields raylib reports (ids, sizes, mipmaps, format) and
LoadImageFromTexture's size, format and byte sum to the scene's row, so pool
ids are compared too.

Scenes cover camera offsets, targets, zooms (fractional, negative, zero) and
the rotations the Apple sinf/cosf profile verifies, nested and overflowing
matrix stacks, scissor rectangles inside, across and outside the screen
(ClearBackground's one-pixel-larger fill included), scissors set before a
texture mode (stale clip bounds), every blend mode (none changes the
software renderer), texture formats 1..7 and float formats (drawn
untextured), sizes 1x1 to 16x16 including non-powers of two, nearest and
bilinear filtering with fractional, negative and repeating texture
coordinates, CLAMP and mirror wraps (rejected by rlsw: REPEAT stays), tinted
and translucent draws over opaque and translucent backgrounds, opaque
textures updated with translucent pixels, NPatch layouts with borders larger
than the patch, render textures drawn with negative source heights, and
pool reuse after unloads.

Contracts (Jonlib must answer null): unverified rotation arguments, popping
the last modelview matrix, scissor arguments beyond 2^22, undefined C int
conversions, a second BeginTextureMode, LoadRenderTexture during texture mode.
CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import math
import random
import struct

from conformance import gradient_reference
import frame_probe as fp
import probekit
from probekit import ROOT, ProbeFailure

C = fp.C
f32 = fp.f32
cf = fp.cf
cc = fp.cc
bf = fp.bf

# Bytes per pixel of the uncompressed formats 1..13.
BPP = {1: 1, 2: 2, 3: 2, 4: 3, 5: 2, 6: 2, 7: 4, 8: 4, 9: 12, 10: 16, 11: 2, 12: 6, 13: 8}
# Alpha byte masks (period, mask word) that make an image of the format opaque.
OPAQUE = {2: (2, 0xFF00), 5: (2, 0x0001), 6: (2, 0x000F), 7: (4, 0xFF000000)}


def pattern(count, seed, mask, period, zero):
    """The image bytes both sides build: a multiplicative hash per byte, ORed with a mask."""
    if zero:
        return [0] * count
    out = []
    for i in range(count):
        v = ((((i * 2654435761) + seed * 40503) & 0xFFFFFFFF) >> 13) & 255
        out.append(v | ((mask >> (8 * (i % period))) & 255))
    return out


def image(width, height, fmt, seed, opaque=False):
    period, mask = OPAQUE.get(fmt, (1, 0)) if opaque else (1, 0)
    return dict(width=width, height=height, format=fmt, seed=seed, mask=mask, period=period, zero=fmt >= 8)


def image_bytes(spec):
    return pattern(spec['width'] * spec['height'] * BPP[spec['format']], spec['seed'], spec['mask'], spec['period'], spec['zero'])


# -----------------------------------------------------------------------------
# Contract rules (mirrors docs/TEXTURES.md)

def rotation_arguments(op):
    """sinf/cosf arguments: BeginMode2D, rlRotatef and DrawTextureNPatch always
    evaluate them, DrawTexturePro (and Ex) only for a nonzero rotation."""
    name, a = op[0], op[1:]
    base = name[:-3] if name.endswith('_rt') else name
    if name == 'mode2d':
        return [f32(a[4] * fp.DEG2RAD)]
    if name == 'rotate':
        return [f32(a[0] * fp.DEG2RAD)]
    if base == 'npatch':
        return [f32(a[4] * fp.DEG2RAD)]
    if base in ('draw_ex', 'draw_pro'):
        rotation = a[3] if base == 'draw_ex' else a[4]
        return [] if rotation == 0.0 else [f32(rotation * fp.DEG2RAD)]
    return []


def refused(scene, libm):
    """Contracts: the scene's declared ones (libm-independent) and the
    rotations outside the host profile's verified sinf/cosf arguments."""
    if scene.get('contract'):
        return True
    if any(fp.refused(op, libm) for op in scene['ops'] if op[0] in SHAPE_OPS):
        return True
    return not all(fp.accepted(libm, x) for op in scene['ops'] for x in rotation_arguments(op))


SHAPE_OPS = ('pixel', 'pixel_v', 'line', 'line_v', 'line_ex', 'line_strip', 'rect', 'rect_v', 'rect_rec', 'rect_pro', 'grad_v', 'grad_h',
             'grad_ex', 'rect_lines', 'rect_lines_ex', 'tri', 'tri_lines', 'fan', 'strip', 'circle', 'circle_v', 'circle_lines',
             'circle_lines_v', 'circle_gradient', 'sector', 'sector_lines', 'ellipse', 'ellipse_v', 'ellipse_lines', 'ellipse_lines_v',
             'ring', 'poly', 'poly_lines', 'begin', 'end', 'clear')


# -----------------------------------------------------------------------------
# Scenes

def scenes(libm):
    rng = random.Random(0x7E47)
    out = []

    def add(name, width, height, ops, screen=False, contract=False):
        out.append(dict(id=name, width=width, height=height, ops=ops, screen=screen, contract=contract))

    red, green, blue, white, black = C(230, 41, 55), C(0, 228, 48), C(0, 121, 241), C(255, 255, 255), C(0, 0, 0)
    half = [C(255, 0, 0, 128), C(0, 255, 0, 64), C(0, 0, 255, 200), C(255, 255, 0, 1), C(17, 34, 51, 254)]
    trans_bg = C(255, 128, 128, 100)

    def shapes(w, h):
        return [('rect', 2.0, 2.0, 6.0, 4.0, red), ('rect_rec', 4.5, 3.25, 7.0, 5.5, half[0]), ('circle_v', f32(w / 2), f32(h / 2), 4.0, half[2]),
                ('line', 1.0, 1.0, float(w - 2), float(h - 3), white), ('tri', 3.0, 3.0, 3.0, 11.0, 12.0, 11.0, half[1]),
                ('pixel_v', 5.5, 6.5, green), ('rect_lines', 1.0, 1.0, 9.0, 7.0, blue), ('line_v', 2.5, 9.5, 14.5, 2.5, half[4])]

    # BeginMode2D: offsets, targets, zooms and verified rotations.
    cameras = [(0.0, 0.0, 0.0, 0.0, 0.0, 1.0), (8.0, 6.0, 4.0, 3.0, 0.0, 1.0), (16.0, 12.0, 16.0, 12.0, 0.0, 2.0), (3.5, 2.25, 1.25, 0.75, 0.0, 0.5),
               (16.0, 12.0, 8.0, 6.0, 90.0, 1.0), (16.0, 12.0, 8.0, 6.0, 45.0, 1.5), (10.0, 8.0, 5.0, 5.0, -30.0, 0.75), (16.0, 12.0, 8.0, 6.0, 180.0, 1.0),
               (12.0, 10.0, 6.0, 4.0, 270.0, 1.25), (16.0, 12.0, 8.0, 6.0, 0.0, -1.0), (16.0, 12.0, 8.0, 6.0, 0.0, 0.0), (4.0, 4.0, -3.0, -2.0, 60.0, 3.0),
               (16.0, 12.0, 8.0, 6.0, 359.0, 1.0), (0.5, 0.5, 0.0, 0.0, -90.0, 1.0)]
    for k, (ox, oy, tx, ty, rot, zoom) in enumerate(cameras):
        w, h = ((32, 24), (33, 17), (24, 24))[k % 3]
        ops = [('begin',), ('clear', C(30, 30, 40)), ('mode2d', ox, oy, tx, ty, rot, zoom)] + shapes(w, h) + [('end2d',), ('rect', 0.0, 0.0, 3.0, 3.0, green), ('end',)]
        add(f'camera-{k}', w, h, ops, screen=(k % 5 == 0))
    add('camera-twice', 32, 24, [('begin',), ('clear', black), ('mode2d', 4.0, 4.0, 0.0, 0.0, 0.0, 2.0), ('rect', 0.0, 0.0, 4.0, 4.0, red),
                                 ('mode2d', 20.0, 4.0, 0.0, 0.0, 90.0, 1.0), ('rect', 0.0, 0.0, 4.0, 2.0, blue), ('begin',), ('rect', 0.0, 0.0, 2.0, 2.0, white),
                                 ('end2d',), ('end',)])
    add('camera-unverified-13', 16, 12, [('mode2d', 8.0, 6.0, 0.0, 0.0, 13.0, 1.0), ('rect', 0.0, 0.0, 2.0, 2.0, red), ('end2d',)])
    add('camera-unverified-nan', 16, 12, [('mode2d', 8.0, 6.0, 0.0, 0.0, float('nan'), 1.0), ('end2d',)])

    # rlgl matrix stack.
    add('matrix-stack', 32, 24, [('begin',), ('clear', C(20, 20, 20)), ('push',), ('translate', 10.0, 5.0, 0.0), ('rect', 0.0, 0.0, 4.0, 4.0, red),
                                 ('push',), ('scale', 2.0, 1.5, 1.0), ('rect', 1.0, 1.0, 3.0, 3.0, half[2]), ('rotate', 90.0, 0.0, 0.0, 1.0),
                                 ('rect', 0.0, 0.0, 3.0, 2.0, green), ('pop',), ('circle_v', 4.0, 4.0, 3.0, half[0]), ('pop',),
                                 ('rotate', 30.0, 0.0, 0.0, 2.0), ('rect', 12.0, 2.0, 5.0, 5.0, white), ('identity',), ('line', 0.0, 20.0, 31.0, 20.0, blue),
                                 ('mult', (1.0, 0.0, 0.0, 0.0, 0.5, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 3.0, 2.0, 0.0, 1.0)), ('rect', 2.0, 2.0, 6.0, 6.0, half[1]),
                                 ('end',)])
    add('matrix-overflow', 24, 24, [('begin',), ('clear', black)] + [('push',), ('translate', 1.0, 1.0, 0.0)] * 9
        + [('rect', 0.0, 0.0, 2.0, 2.0, red)] + [('pop',)] * 7 + [('rect', 0.0, 0.0, 2.0, 2.0, green), ('end',)])
    add('matrix-rotate-axis', 24, 24, [('begin',), ('clear', black), ('translate', 12.0, 12.0, 0.0), ('rotate', 45.0, 0.0, 0.0, 3.0),
                                       ('rect', -4.0, -4.0, 8.0, 8.0, half[2]), ('rotate', 90.0, 1.0, 0.0, 0.0), ('rect', -2.0, -2.0, 6.0, 6.0, red),
                                       ('identity',), ('rotate', 180.0, 0.0, 1.0, 0.0), ('rect', -10.0, 2.0, 6.0, 6.0, green), ('end',)])
    add('matrix-camera-push', 32, 24, [('begin',), ('clear', black), ('mode2d', 16.0, 12.0, 0.0, 0.0, 0.0, 2.0), ('push',),
                                       ('translate', 2.0, 0.0, 0.0), ('rect', 0.0, 0.0, 2.0, 2.0, red), ('pop',), ('rect', -4.0, -4.0, 2.0, 2.0, blue),
                                       ('end2d',), ('end',)])
    add('matrix-pop-empty', 16, 12, [('pop',), ('rect', 0.0, 0.0, 2.0, 2.0, red)], contract=True)
    add('matrix-rotate-unverified', 16, 12, [('rotate', 19.0, 0.0, 0.0, 1.0)])

    # Scissor.
    add('scissor-basic', 32, 24, [('begin',), ('clear', C(240, 240, 240)), ('scissor', 4.0, 3.0, 12.0, 10.0)] + shapes(32, 24)
        + [('circle_v', 10.0, 8.0, 9.0, half[0]), ('line', 0.0, 5.0, 31.0, 5.0, red), ('line', 7.0, 0.0, 7.0, 23.0, blue), ('end_scissor',),
           ('rect', 20.0, 2.0, 4.0, 4.0, green), ('end',)])
    add('scissor-clear', 24, 16, [('begin',), ('clear', black), ('scissor', 3.0, 2.0, 5.0, 4.0), ('clear', red), ('scissor', -4.0, -3.0, 2.0, 2.0),
                                  ('clear', green), ('scissor', 30.0, 20.0, 3.0, 3.0), ('clear', blue), ('scissor', 10.0, 6.0, 0.0, 0.0), ('clear', white),
                                  ('end_scissor',), ('end',)], screen=True)
    add('scissor-negative', 24, 16, [('begin',), ('clear', black), ('scissor', 2.0, 2.0, 8.0, 6.0), ('scissor', 1.0, 1.0, -3.0, 5.0),
                                     ('rect', 0.0, 0.0, 24.0, 16.0, half[1]), ('end_scissor',), ('scissor', 5.0, 5.0, 4.0, -1.0),
                                     ('rect', 0.0, 0.0, 24.0, 16.0, half[0]), ('end_scissor',), ('end',)])
    add('scissor-offscreen', 24, 16, [('begin',), ('clear', black), ('scissor', -5.0, -5.0, 12.0, 12.0), ('rect', 0.0, 0.0, 24.0, 16.0, red),
                                      ('line', 0.0, 3.0, 23.0, 3.0, white), ('scissor', 20.0, 10.0, 30.0, 30.0), ('rect', 0.0, 0.0, 24.0, 16.0, blue),
                                      ('scissor', 30.0, 2.0, 5.0, 5.0), ('rect', 0.0, 0.0, 24.0, 16.0, green), ('end_scissor',), ('end',)])
    add('scissor-camera', 32, 24, [('begin',), ('clear', black), ('mode2d', 16.0, 12.0, 0.0, 0.0, 45.0, 2.0), ('scissor', 8.0, 4.0, 14.0, 12.0),
                                   ('rect', -6.0, -6.0, 12.0, 12.0, half[2]), ('circle_v', 0.0, 0.0, 5.0, red), ('line', -8.0, 0.0, 8.0, 0.0, white),
                                   ('end_scissor',), ('end2d',), ('end',)])
    add('scissor-overflow', 16, 12, [('scissor', 5000000.0, 0.0, 4.0, 4.0)], contract=True)

    # Blend modes: rlSetBlendMode is GL3-only, so none changes the software renderer.
    for mode in range(8):
        add(f'blend-{mode}', 16, 12, [('begin',), ('clear', trans_bg), ('blend', mode), ('rect', 1.0, 1.0, 8.0, 6.0, half[0]),
                                      ('circle_v', 9.0, 6.0, 4.0, half[2]), ('line', 0.0, 9.0, 15.0, 2.0, half[1]), ('rect', 5.0, 2.0, 3.0, 3.0, red),
                                      ('end_blend',), ('rect', 12.0, 8.0, 3.0, 3.0, half[0]), ('end',)])

    # Textures: every format, sizes, filters, tints and draw functions.
    formats = [1, 2, 3, 4, 5, 6, 7]
    sizes = [(1, 1), (3, 5), (4, 4), (7, 3), (16, 8), (13, 11), (5, 16)]
    for k, fmt in enumerate(formats):
        w, h = sizes[k]
        for opaque in (False, True):
            spec = image(w, h, fmt, 11 + 7 * k + opaque, opaque)
            ops = [('begin',), ('clear', (C(40, 60, 80), trans_bg)[k % 2]), ('load', 0, spec), ('info', 0), ('image', 0),
                   ('draw', 0, 1.0, 1.0, white), ('draw_v', 0, 6.5, 2.25, half[0]), ('draw_ex', 0, 12.0, 1.5, 0.0, 1.5, C(200, 255, 120)),
                   ('draw_rec', 0, (0.5, 0.5, 2.0, 2.0), 2.0, 14.0, white), ('draw_pro', 0, (0.0, 0.0, float(w), float(h)), (20.0, 10.0, 9.0, 7.0), (0.0, 0.0), 0.0, half[2]),
                   ('filter', 0, 1), ('draw_pro', 0, (0.0, 0.0, float(w), float(h)), (2.0, 18.0, 11.0, 5.5), (0.0, 0.0), 0.0, white),
                   ('draw_ex', 0, 24.0, 18.0, 0.0, 0.5, C(255, 255, 255, 160)), ('end',)]
            add(f'texture-format-{fmt}-{"opaque" if opaque else "alpha"}', 32, 24, ops, screen=(k == 6 and opaque))
    for fmt in (8, 10, 11, 13):
        add(f'texture-float-{fmt}', 16, 12, [('begin',), ('clear', C(9, 9, 9)), ('load', 0, image(3, 2, fmt, 5)), ('info', 0), ('image', 0),
                                             ('draw', 0, 2.0, 2.0, red), ('draw_pro', 0, (0.0, 0.0, 3.0, 2.0), (6.0, 3.0, 8.0, 6.0), (0.0, 0.0), 0.0, half[0]),
                                             ('filter', 0, 1), ('draw_v', 0, 10.0, 8.0, white), ('unload', 0), ('load', 1, image(2, 2, 7, 3)), ('info', 1), ('end',)])

    # Filtering with fractional, negative and repeating coordinates; wraps.
    for filt in (0, 1, 2, 3):
        for wrap in (0, 1, 2, 3):
            if filt in (2, 3) and wrap in (2, 3):
                continue
            spec = image(5, 4, 7, 100 + filt * 4 + wrap)
            ops = [('begin',), ('clear', C(50, 50, 50)), ('load', 0, spec), ('filter', 0, filt), ('wrap', 0, wrap),
                   ('draw_pro', 0, (-2.5, -1.25, 12.0, 9.0), (1.0, 1.0, 14.0, 10.0), (0.0, 0.0), 0.0, white),
                   ('draw_pro', 0, (0.25, 0.75, 2.5, 1.5), (16.0, 1.5, 15.0, 9.0), (0.0, 0.0), 0.0, white),
                   ('draw_pro', 0, (3.0, 2.0, -9.0, -7.0), (1.5, 12.5, 13.0, 10.25), (0.0, 0.0), 0.0, half[0]),
                   ('draw_pro', 0, (-7.0, 5.0, 4.0, 3.0), (17.25, 12.75, 6.5, 9.0), (1.0, 2.0), 0.0, C(255, 200, 100, 220)),
                   ('draw_rec', 0, (1.0, 1.0, -3.0, 2.0), 25.0, 13.0, white), ('draw_ex', 0, 26.0, 18.0, 0.0, 0.75, white), ('end',)]
            add(f'filter-{filt}-wrap-{wrap}', 32, 24, ops)
    add('filter-magnify', 32, 32, [('begin',), ('clear', black), ('load', 0, image(2, 2, 7, 77)), ('filter', 0, 1),
                                   ('draw_ex', 0, 0.0, 0.0, 0.0, 15.5, white), ('load', 1, image(3, 3, 4, 78)), ('filter', 1, 1),
                                   ('draw_pro', 1, (0.0, 0.0, 3.0, 3.0), (16.0, 16.0, 16.0, 16.0), (0.0, 0.0), 0.0, white), ('end',)])

    # Rotations, origins, flips.
    for k, rot in enumerate((90.0, 45.0, -30.0, 180.0, 270.0, 359.0, -1.0, 135.0)):
        spec = image(6, 4, (7, 4, 2, 6)[k % 4], 300 + k, k % 2 == 1)
        ops = [('begin',), ('clear', (C(10, 30, 50), trans_bg)[k % 2]), ('load', 0, spec), ('filter', 0, k % 2),
               ('draw_pro', 0, (0.0, 0.0, 6.0, 4.0), (16.0, 12.0, 12.0, 8.0), (6.0, 4.0), rot, white),
               ('draw_pro', 0, (1.0, 0.0, -4.0, 4.0), (6.0, 6.0, -6.0, 5.0), (1.5, 0.5), rot, half[0]),
               ('draw_ex', 0, 25.0, 4.0, rot, 1.25, C(180, 255, 180, 230)), ('end',)]
        add(f'texture-rotation-{k}', 32, 24, ops)
    add('texture-rotation-unverified', 16, 12, [('load', 0, image(2, 2, 7, 1)), ('draw_ex', 0, 4.0, 4.0, 22.0, 1.0, white)])
    add('texture-int-nan', 16, 12, [('load', 0, image(2, 2, 7, 1)), ('draw', 0, float('nan'), 4.0, white)], contract=True)

    # NPatch layouts.
    for layout in (0, 1, 2, 5):
        spec = image(9, 9, 7, 500 + layout, layout % 2 == 0)
        ops = [('begin',), ('clear', C(70, 70, 90)), ('load', 0, spec)]
        for k, (dest, rot, origin) in enumerate((((1.0, 1.0, 14.0, 10.0), 0.0, (0.0, 0.0)), ((17.0, 2.0, 5.0, 4.0), 0.0, (0.0, 0.0)),
                                                 ((24.0, 16.0, 12.0, 9.0), 90.0, (6.0, 4.5)), ((2.0, 14.0, 11.5, 8.75), 0.0, (0.0, 0.0)),
                                                 ((28.0, 1.0, -3.0, 6.0), 0.0, (0.0, 0.0)))):
            info = ((0.0, 0.0, 9.0, 9.0), 3.0, 2.0, 3.0, 4.0, float(layout)) if k % 2 == 0 else ((9.0, 0.0, -9.0, 9.0), 4.0, 4.0, 4.0, 4.0, float(layout))
            ops.append(('npatch', 0, info, dest, origin, rot, (white, half[0], C(255, 255, 0), half[2], white)[k]))
        ops.append(('end',))
        add(f'npatch-layout-{layout}', 32, 24, ops)
    add('npatch-filtered', 24, 24, [('begin',), ('clear', black), ('load', 0, image(6, 6, 2, 900)), ('filter', 0, 1),
                                    ('npatch', 0, ((1.0, 1.0, 5.0, 4.0), 1.0, 1.0, 2.0, 1.0, 0.0), (2.0, 2.0, 19.0, 17.0), (0.0, 0.0), 0.0, white),
                                    ('npatch', 0, ((0.0, 0.0, 6.0, 6.0), 2.0, 2.0, 2.0, 2.0, 0.0), (12.0, 12.0, 3.0, 3.0), (1.0, 1.0), 180.0, half[1]),
                                    ('end',)])
    add('npatch-unverified', 16, 12, [('load', 0, image(3, 3, 7, 1)), ('npatch', 0, ((0.0, 0.0, 3.0, 3.0), 1.0, 1.0, 1.0, 1.0, 0.0),
                                                                                    (1.0, 1.0, 8.0, 8.0), (0.0, 0.0), 103.0, white)])
    add('npatch-noninteger', 16, 12, [('load', 0, image(3, 3, 7, 1)), ('npatch', 0, ((0.0, 0.0, 3.0, 3.0), 1.5, 1.0, 1.0, 1.0, 0.0),
                                                                                     (1.0, 1.0, 8.0, 8.0), (0.0, 0.0), 0.0, white)], contract=True)

    # UpdateTexture / UpdateTextureRec: raw copies keep the load-time alpha mode.
    add('update-opaque-with-alpha', 24, 16, [('begin',), ('clear', C(255, 255, 255, 120)), ('load', 0, image(4, 4, 7, 40, True)),
                                             ('update', 0, image(4, 4, 7, 41)), ('draw', 0, 1.0, 1.0, white), ('draw_ex', 0, 6.0, 1.0, 0.0, 2.0, white),
                                             ('load', 1, image(4, 4, 7, 42)), ('update', 1, image(4, 4, 7, 43, True)), ('draw', 1, 15.0, 1.0, white),
                                             ('draw', 1, 15.0, 8.0, half[0]), ('end',)])
    for fmt in (1, 2, 3, 4, 5, 6, 7):
        add(f'update-rec-{fmt}', 24, 16, [('begin',), ('clear', black), ('load', 0, image(6, 5, fmt, 60 + fmt)),
                                          ('update_rec', 0, (1.0, 2.0, 3.0, 2.0), image(3, 2, fmt, 70 + fmt)),
                                          ('update_rec', 0, (4.9, 0.2, 2.7, 1.9), image(2, 1, fmt, 80 + fmt)),
                                          ('update_rec', 0, (5.0, 4.0, 3.0, 3.0), image(3, 3, fmt, 90 + fmt)),
                                          ('update_rec', 0, (-1.0, 0.0, 2.0, 2.0), image(2, 2, fmt, 91)),
                                          ('update_rec', 0, (0.0, 0.0, 0.0, 3.0), image(1, 1, fmt, 92)),
                                          ('draw_ex', 0, 1.0, 1.0, 0.0, 2.0, white), ('info', 0), ('end',)])

    # Pool ids: loads, unloads and reuse; mipmaps.
    add('texture-ids', 8, 6, [('load', 0, image(2, 2, 7, 1)), ('info', 0), ('load', 1, image(3, 1, 1, 2)), ('info', 1), ('unload', 0),
                              ('load', 2, image(1, 1, 4, 3)), ('info', 2), ('load', 0, image(2, 3, 6, 4)), ('info', 0), ('unload', 1), ('unload', 2),
                              ('load', 3, image(1, 2, 5, 5)), ('info', 3), ('load', 1, image(4, 4, 7, 6)), ('info', 1), ('mipmaps', 1), ('info', 1),
                              ('load_rt', 0, 4, 3), ('rt_info', 0), ('load_rt', 1, 2, 2), ('rt_info', 1), ('unload_rt', 0), ('load', 2, image(1, 1, 7, 7)),
                              ('info', 2), ('load_rt', 0, 3, 3), ('rt_info', 0), ('image_rt', 0), ('unload_rt', 1), ('unload_rt', 0),
                              ('load_rt', 1, 5, 5), ('rt_info', 1), ('begin',), ('clear', C(1, 2, 3)), ('end',)])

    # Render textures.
    def rt_scene(name, w, h, rw, rh, inner, outer, screen=False):
        ops = [('load_rt', 0, rw, rh), ('begin',), ('clear', C(20, 40, 60)), ('begin_rt', 0)] + inner + [('end_rt', 0)] + outer + [('end',)]
        add(name, w, h, ops, screen=screen)

    rt_inner = [('clear', C(250, 240, 200, 255)), ('rect', 1.0, 1.0, 5.0, 3.0, red), ('circle_v', 8.0, 6.0, 4.0, half[2]), ('line', 0.0, 0.0, 11.0, 9.0, blue),
                ('tri', 2.0, 2.0, 2.0, 8.0, 9.0, 8.0, half[0]), ('pixel', 10.0, 1.0, green)]
    rt_scene('rt-flipped', 32, 24, 12, 10, rt_inner,
             [('draw_rec_rt', 0, (0.0, 0.0, 12.0, -10.0), 1.0, 1.0, white), ('draw_rec_rt', 0, (0.0, 0.0, 12.0, 10.0), 17.0, 1.0, white),
              ('draw_pro_rt', 0, (0.0, 0.0, 12.0, -10.0), (2.0, 13.0, 18.0, 9.0), (0.0, 0.0), 0.0, half[0])], screen=True)
    rt_scene('rt-translucent', 32, 24, 9, 7, [('clear', C(0, 0, 0, 0)), ('rect', 1.0, 1.0, 4.0, 4.0, half[0]), ('circle_v', 6.0, 4.0, 3.0, half[1])],
             [('clear', trans_bg), ('draw_rt', 0, 1.0, 1.0, white), ('filter_rt', 0, 1), ('draw_ex_rt', 0, 12.0, 2.0, 0.0, 2.0, white),
              ('draw_pro_rt', 0, (0.0, 7.0, 9.0, -7.0), (3.0, 12.0, 7.0, 10.0), (0.0, 0.0), 90.0, half[2])])
    rt_scene('rt-camera-scissor', 32, 24, 16, 12,
             [('clear', white), ('mode2d', 8.0, 6.0, 0.0, 0.0, 45.0, 1.5), ('rect', -3.0, -3.0, 6.0, 6.0, red), ('end2d',), ('scissor', 2.0, 2.0, 6.0, 5.0),
              ('clear', green), ('rect', 0.0, 0.0, 16.0, 12.0, half[2]), ('end_scissor',)],
             [('draw_rec_rt', 0, (0.0, 0.0, 16.0, -12.0), 2.0, 2.0, white), ('mode2d', 16.0, 12.0, 8.0, 6.0, 0.0, 0.75),
              ('draw_rt', 0, 10.0, 8.0, half[0]), ('end2d',)])
    rt_scene('rt-stale-scissor', 24, 20, 10, 8,
             [('clear', white), ('rect', 0.0, 0.0, 10.0, 8.0, red)],
             [('draw_rec_rt', 0, (0.0, 0.0, 10.0, -8.0), 1.0, 1.0, white)])
    out[-1]['ops'] = [('load_rt', 0, 10, 8), ('begin',), ('clear', black), ('scissor', 4.0, 6.0, 8.0, 8.0), ('begin_rt', 0), ('clear', white),
                      ('rect', 0.0, 0.0, 10.0, 8.0, red), ('line', 0.0, 4.0, 9.0, 4.0, blue), ('end_rt', 0), ('end_scissor',),
                      ('draw_rec_rt', 0, (0.0, 0.0, 10.0, -8.0), 1.0, 1.0, white), ('scissor', 12.0, 2.0, 6.0, 6.0), ('draw_rt', 0, 12.0, 10.0, white),
                      ('end_scissor',), ('end',)]
    rt_scene('rt-matrix', 24, 20, 8, 8, [('clear', blue), ('push',), ('translate', 4.0, 4.0, 0.0), ('rotate', 45.0, 0.0, 0.0, 1.0),
                                         ('rect', -2.0, -2.0, 4.0, 4.0, white), ('pop',)],
             [('push',), ('scale', 2.0, 2.0, 1.0), ('draw_rt', 0, 1.0, 1.0, white), ('pop',), ('draw_npatch_rt', 0), ('end',)])
    out[-1]['ops'] = out[-1]['ops'][:-1]
    rt_scene('rt-reuse', 24, 20, 6, 6, [('clear', red)], [('begin_rt', 0), ('rect', 1.0, 1.0, 3.0, 3.0, green), ('end_rt', 0),
                                                          ('draw_rt', 0, 2.0, 2.0, white), ('end_rt', 0), ('load', 0, image(3, 3, 7, 9)),
                                                          ('begin_rt', 0), ('draw', 0, 1.0, 1.0, white), ('end_rt', 0), ('draw_ex_rt', 0, 10.0, 2.0, 0.0, 2.0, white),
                                                          ('image_rt', 0), ('rt_info', 0)])
    add('rt-nested', 16, 12, [('load_rt', 0, 4, 4), ('load_rt', 1, 4, 4), ('begin_rt', 0), ('begin_rt', 1), ('end_rt', 1), ('end_rt', 0)], contract=True)
    add('rt-load-in-texture-mode', 16, 12, [('load_rt', 0, 4, 4), ('begin_rt', 0), ('load_rt', 1, 4, 4), ('end_rt', 0)], contract=True)

    add('rt-unload-in-texture-mode', 16, 12, [('load_rt', 0, 4, 4), ('load_rt', 1, 4, 4), ('begin_rt', 0), ('unload_rt', 1), ('end_rt', 0)], contract=True)
    add('rt-unended', 16, 12, [('load_rt', 0, 4, 4), ('begin_rt', 0), ('clear', red)], contract=True)

    # Pool exhaustion: 126 texture ids after the font's, 7 framebuffer ids.
    add('pool-textures', 8, 6, [('load_many', 0, 125, image(1, 1, 7, 1)), ('info', 0), ('load', 1, image(2, 1, 1, 2)), ('info', 1),
                                ('load', 2, image(1, 1, 7, 3)), ('info', 2), ('unload', 1), ('load', 3, image(1, 2, 4, 4)), ('info', 3),
                                ('begin',), ('clear', C(4, 5, 6)), ('draw', 3, 1.0, 1.0, white), ('end',)])
    add('pool-framebuffers', 8, 6, [('load_rt', 0, 2, 2)] * 7 + [('rt_info', 0), ('load_rt', 1, 2, 2), ('rt_info', 1), ('load', 0, image(1, 1, 7, 9)),
                                                                  ('info', 0), ('begin',), ('clear', C(6, 5, 4)), ('end',)])

    # Nested scissors (each BeginScissorMode replaces the rectangle) and
    # nearest sampling at fract(u) == 1.0 (a texel of the next row).
    add('scissor-nested', 24, 16, [('begin',), ('clear', black), ('scissor', 2.0, 2.0, 16.0, 10.0), ('rect', 0.0, 0.0, 24.0, 16.0, half[0]),
                                   ('scissor', 6.0, 4.0, 4.0, 4.0), ('rect', 0.0, 0.0, 24.0, 16.0, green), ('end_scissor',),
                                   ('rect', 0.0, 0.0, 24.0, 16.0, half[1]), ('scissor', 12.0, 8.0, 30.0, 2.0), ('circle_v', 14.0, 9.0, 6.0, red),
                                   ('end_scissor',), ('end',)])
    add('nearest-row-wrap', 24, 16, [('begin',), ('clear', black), ('load', 0, image(4, 4, 7, 21, True)),
                                     ('draw_pro', 0, (-1e-07, 0.0, 4.0, 4.0), (0.0, 0.0, 16.0, 16.0), (0.0, 0.0), 0.0, white),
                                     ('draw_pro', 0, (f32(-3e-08), f32(-3e-08), 4.0, 2.0), (17.0, 1.0, 6.0, 6.0), (0.0, 0.0), 0.0, white), ('end',)])

    # Random textured scenes.
    for index in range(10):
        w, h = rng.choice(((32, 24), (24, 32), (17, 13)))
        ops = [('begin',), ('clear', C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, 80))))]
        for slot in range(3):
            fmt = rng.choice((1, 2, 3, 4, 5, 6, 7, 7))
            tw, th = rng.randint(1, 9), rng.randint(1, 9)
            ops.append(('load', slot, image(tw, th, fmt, rng.randrange(1 << 16), rng.random() < 0.4)))
            if rng.random() < 0.5:
                ops.append(('filter', slot, 1))
        for _ in range(rng.randint(6, 12)):
            slot = rng.randrange(3)
            tint = C(rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice((255, 255, 128, 30)))
            kind = rng.choice(('draw', 'draw_v', 'draw_ex', 'draw_rec', 'draw_pro', 'shape', 'camera'))
            x, y = f32(rng.uniform(-4, w)), f32(rng.uniform(-4, h))
            if kind == 'draw':
                ops.append(('draw', slot, float(round(x)), float(round(y)), tint))
            elif kind == 'draw_v':
                ops.append(('draw_v', slot, x, y, tint))
            elif kind == 'draw_ex':
                ops.append(('draw_ex', slot, x, y, rng.choice((0.0, 0.0, 90.0, 45.0, -60.0)), f32(rng.uniform(0.25, 3.0)), tint))
            elif kind == 'draw_rec':
                ops.append(('draw_rec', slot, tuple(f32(rng.uniform(-3, 6)) for _ in range(4)), x, y, tint))
            elif kind == 'draw_pro':
                ops.append(('draw_pro', slot, tuple(f32(rng.uniform(-3, 8)) for _ in range(4)), (x, y, f32(rng.uniform(-2, 14)), f32(rng.uniform(-2, 14))),
                            (f32(rng.uniform(-3, 3)), f32(rng.uniform(-3, 3))), rng.choice((0.0, 0.0, 30.0, 90.0, 270.0)), tint))
            elif kind == 'shape':
                ops.append(('rect_rec', x, y, f32(rng.uniform(0, 10)), f32(rng.uniform(0, 10)), tint))
            else:
                ops.append(('mode2d', f32(rng.uniform(0, w)), f32(rng.uniform(0, h)), f32(rng.uniform(0, 8)), f32(rng.uniform(0, 8)),
                            rng.choice((0.0, 45.0, 90.0, -30.0)), rng.choice((0.5, 1.0, 1.5, 2.0))))
                ops.append(('draw_pro', slot, (0.0, 0.0, 4.0, 4.0), (0.0, 0.0, 6.0, 6.0), (3.0, 3.0), 0.0, tint))
                ops.append(('end2d',))
        ops.append(('end',))
        add(f'random-{index}-{w}x{h}', w, h, ops, screen=(index % 4 == 0))
    return out


# -----------------------------------------------------------------------------
# C reference

C_PREFIX = fp.C_PREFIX.replace('static void dump(int w, int h, int screen)', '''static char log_text[65536];
static void note(const char *s) { strcat(log_text, s); }
static Texture2D tex_from(int w, int h, int format, const unsigned char *bytes, int n)
{
    Image img = { 0 };
    img.data = malloc(n); memcpy(img.data, bytes, n);
    img.width = w; img.height = h; img.mipmaps = 1; img.format = format;
    Texture2D t = LoadTextureFromImage(img);
    UnloadImage(img);
    return t;
}
static void info(Texture2D t)
{
    char s[96];
    if (t.id == 0) snprintf(s, sizeof s, " i-");
    else snprintf(s, sizeof s, " i%u,%d,%d,%d,%d,%d", t.id, t.width, t.height, t.mipmaps, t.format, (int)IsTextureValid(t));
    note(s);
}
static void rt_info(RenderTexture2D r)
{
    char s[96];
    if (r.id == 0) snprintf(s, sizeof s, " r-");
    else snprintf(s, sizeof s, " r%u,%u,%u,%d", r.id, r.texture.id, r.depth.id, (int)IsRenderTextureValid(r));
    note(s);
}
static void image_info(Texture2D t)
{
    char s[96];
    Image im = LoadImageFromTexture(t);
    if (im.data == NULL) snprintf(s, sizeof s, " m-");
    else
    {
        unsigned sum = 0; int n = GetPixelDataSize(im.width, im.height, im.format);
        for (int i = 0; i < n; i++) sum += ((unsigned char *)im.data)[i];
        snprintf(s, sizeof s, " m%d,%d,%d,%u", im.width, im.height, im.format, sum);
    }
    UnloadImage(im);
    note(s);
}
static void dump(int w, int h, int screen)''').replace('    printf("\\n");\n    free(p);', '    printf("%s\\n", log_text);\n    log_text[0] = 0;\n    free(p);')


if 'log_text' not in C_PREFIX or 'printf("%s\\n", log_text)' not in C_PREFIX:
    raise ProbeFailure('texture: tools/frame_probe.py C_PREFIX changed; update the texture probe hooks')


def c_bytes(spec):
    return '(const unsigned char[]){' + ','.join(map(str, image_bytes(spec))) + '}'


def crec(r):
    return fp.crec(*r)


def c_tex_op(op):
    name, a = op[0], op[1:]
    rt = name.endswith('_rt')
    base = name[:-3] if rt else name
    t = f'r[{a[0]}].texture' if rt else f't[{a[0]}]'
    if base == 'draw':
        return f'DrawTexture({t}, {fp.ci(a[1])}, {fp.ci(a[2])}, {cc(a[3])});'
    if base == 'draw_v':
        return f'DrawTextureV({t}, {fp.cv(a[1], a[2])}, {cc(a[3])});'
    if base == 'draw_ex':
        return f'DrawTextureEx({t}, {fp.cv(a[1], a[2])}, {cf(a[3])}, {cf(a[4])}, {cc(a[5])});'
    if base == 'draw_rec':
        return f'DrawTextureRec({t}, {crec(a[1])}, {fp.cv(a[2], a[3])}, {cc(a[4])});'
    if base == 'draw_pro':
        return f'DrawTexturePro({t}, {crec(a[1])}, {crec(a[2])}, {fp.cv(*a[3])}, {cf(a[4])}, {cc(a[5])});'
    if base == 'draw_npatch':
        return (f'DrawTextureNPatch({t}, (NPatchInfo){{ (Rectangle){{ 0, 0, (float){t}.width, (float){t}.height }}, 2, 2, 2, 2, 0 }}, '
                f'(Rectangle){{ 12, 2, 9, 14 }}, (Vector2){{ 0, 0 }}, 0.0f, WHITE);')
    if base == 'npatch':
        src, l, tp, rr, b, layout = a[1]
        return (f'DrawTextureNPatch({t}, (NPatchInfo){{ {crec(src)}, (int){cf(l)}, (int){cf(tp)}, (int){cf(rr)}, (int){cf(b)}, (int){cf(layout)} }}, '
                f'{crec(a[2])}, {fp.cv(*a[3])}, {cf(a[4])}, {cc(a[5])});')
    if base == 'filter':
        return f'SetTextureFilter({t}, {a[1]});'
    raise ProbeFailure(f'unknown texture op {name}')


def c_op(op):
    name, a = op[0], op[1:]
    if name in SHAPE_OPS:
        return fp.c_op(op, 0)
    simple = {
        'mode2d': lambda: f'BeginMode2D((Camera2D){{ {fp.cv(a[0], a[1])}, {fp.cv(a[2], a[3])}, {cf(a[4])}, {cf(a[5])} }});',
        'end2d': lambda: 'EndMode2D();', 'push': lambda: 'rlPushMatrix();', 'pop': lambda: 'rlPopMatrix();', 'identity': lambda: 'rlLoadIdentity();',
        'translate': lambda: f'rlTranslatef({cf(a[0])}, {cf(a[1])}, {cf(a[2])});', 'scale': lambda: f'rlScalef({cf(a[0])}, {cf(a[1])}, {cf(a[2])});',
        'rotate': lambda: f'rlRotatef({cf(a[0])}, {cf(a[1])}, {cf(a[2])}, {cf(a[3])});',
        'mult': lambda: f'{{ float m[16] = {{ {", ".join(cf(v) for v in a[0])} }}; rlMultMatrixf(m); }}',
        'scissor': lambda: f'BeginScissorMode({fp.ci(a[0])}, {fp.ci(a[1])}, {fp.ci(a[2])}, {fp.ci(a[3])});', 'end_scissor': lambda: 'EndScissorMode();',
        'blend': lambda: f'BeginBlendMode({a[0]});', 'end_blend': lambda: 'EndBlendMode();',
        'load': lambda: f't[{a[0]}] = tex_from({a[1]["width"]}, {a[1]["height"]}, {a[1]["format"]}, {c_bytes(a[1])}, {len(image_bytes(a[1]))});',
        'load_many': lambda: (f'for (int k = 0; k < {a[1]}; k++) t[{a[0]}] = tex_from({a[2]["width"]}, {a[2]["height"]}, {a[2]["format"]}, '
                              f'{c_bytes(a[2])}, {len(image_bytes(a[2]))});'),
        'unload': lambda: f'UnloadTexture(t[{a[0]}]); t[{a[0]}] = (Texture2D){{ 0 }};',
        'wrap': lambda: f'SetTextureWrap(t[{a[0]}], {a[1]});', 'mipmaps': lambda: f'GenTextureMipmaps(&t[{a[0]}]);',
        'update': lambda: f'UpdateTexture(t[{a[0]}], {c_bytes(a[1])});',
        'update_rec': lambda: f'UpdateTextureRec(t[{a[0]}], {crec(a[1])}, {c_bytes(a[2])});',
        'info': lambda: f'info(t[{a[0]}]);', 'image': lambda: f'image_info(t[{a[0]}]);',
        'load_rt': lambda: f'r[{a[0]}] = LoadRenderTexture({a[1]}, {a[2]});', 'unload_rt': lambda: f'UnloadRenderTexture(r[{a[0]}]); r[{a[0]}] = (RenderTexture2D){{ 0 }};',
        'begin_rt': lambda: f'BeginTextureMode(r[{a[0]}]);', 'end_rt': lambda: 'EndTextureMode();',
        'rt_info': lambda: f'rt_info(r[{a[0]}]);', 'image_rt': lambda: f'image_info(r[{a[0]}].texture);',
    }
    if name in simple:
        return '    ' + simple[name]()
    return '    ' + c_tex_op(op)


def c_scene(scene):
    lines = [f'    {{ Texture2D t[4] = {{ 0 }}; RenderTexture2D r[2] = {{ 0 }}; (void)t; (void)r;', f'    InitWindow({scene["width"]}, {scene["height"]}, "");']
    lines += [c_op(op) for op in scene['ops']]
    lines += [f'    dump({scene["width"]}, {scene["height"]}, {int(scene["screen"])});', '    CloseWindow(); }']
    return '\n'.join(lines)


# -----------------------------------------------------------------------------
# Bend candidate

PROGRAM = fp.PROGRAM.replace('import ../../src/trig.bend as Trig\n', 'import ../../src/trig.bend as Trig\n') + '''
type St is Type:
  St{frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String}

def St.new(frame: J.Frame) -> St:
  St{frame, None{}, None{}, None{}, None{}, None{}, None{}, ""}

def St.frame(s: St, f: J.Frame -> J.Frame) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St{f(frame), t0, t1, t2, t3, r0, r1, log}

def pattern.byte(+i: U32, +seed: U32, +mask: U32, +period: U32) -> U32:
  ((((i * 2654435761 + seed * 40503 : U32) >> 13n) .&. 255) .|. ((mask >> U32.to_nat((8 * (i % period) : U32))) .&. 255) : U32)

def pattern(n: Nat, +i: U32, +seed: U32, +mask: U32, +period: U32, +zero: Bool) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+rest: Con{Bool.pick(U32, zero, 0, pattern.byte(i, seed, mask, period)), pattern(rest, (i + 1 : U32), seed, mask, period, zero)}

def img(+width: U32, +height: U32, +format: U32, +bpp: U32, +seed: U32, +mask: U32, +period: U32, +zero: Bool) -> Maybe<J.Surface>:
  J.Surface.from_bytes(width, height, format, pattern(U32.to_nat((width * height * bpp : U32)), 0, seed, mask, period, zero))

def slot.some(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, t) = r
  (frame, Some{t})

def slot.apply(frame: J.Frame, tex: Maybe<J.Texture>, f: J.Frame -> J.Texture -> J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  match tex:
    case None{}: (frame, None{})
    case Some{t}: slot.some(f(frame, t))

def St.put0(r: J.Frame & Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (frame, t) = r
  St{frame, t, t1, t2, t3, r0, r1, log}

def St.put1(r: J.Frame & Maybe<J.Texture>, t0: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (frame, t) = r
  St{frame, t0, t, t2, t3, r0, r1, log}

def St.put2(r: J.Frame & Maybe<J.Texture>, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (frame, t) = r
  St{frame, t0, t1, t, t3, r0, r1, log}

def St.put3(r: J.Frame & Maybe<J.Texture>, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (frame, t) = r
  St{frame, t0, t1, t2, t, r0, r1, log}

def St.tex.at(slot: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String, f: J.Frame -> J.Texture -> J.Frame & J.Texture) -> St:
  match slot:
    case 0: St.put0(slot.apply(frame, t0, f), t1, t2, t3, r0, r1, log)
    case 1: St.put1(slot.apply(frame, t1, f), t0, t2, t3, r0, r1, log)
    case 2: St.put2(slot.apply(frame, t2, f), t0, t1, t3, r0, r1, log)
    case _: St.put3(slot.apply(frame, t3, f), t0, t1, t2, r0, r1, log)

# A texture operation on slot k (skipped when the slot is empty).
def St.tex(s: St, +slot: U32, f: J.Frame -> J.Texture -> J.Frame & J.Texture) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.tex.at(slot, frame, t0, t1, t2, t3, r0, r1, log, f)

def St.loaded(r: J.Frame & Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  r

def St.load.image(frame: J.Frame, image: Maybe<J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match image:
    case None{}: (frame, None{})
    case Some{surface}: J.Texture.load_from_image(frame, surface)

def St.load.at(slot: U32, r: J.Frame & Maybe<J.Texture>, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match slot:
    case 0: St.put0(r, t1, t2, t3, r0, r1, log)
    case 1: St.put1(r, t0, t2, t3, r0, r1, log)
    case 2: St.put2(r, t0, t1, t3, r0, r1, log)
    case _: St.put3(r, t0, t1, t2, r0, r1, log)

# LoadTextureFromImage into slot k (the previous texture is dropped, as the C
# variable is overwritten without UnloadTexture).
def St.load(s: St, +slot: U32, image: Maybe<J.Surface>) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.load.at(slot, St.load.image(frame, image), t0, t1, t2, t3, r0, r1, log)

def St.unload.one(frame: J.Frame, tex: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match tex:
    case None{}: (frame, None{})
    case Some{t}: (J.Texture.unload(frame, t), None{})

def St.unload.at(slot: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match slot:
    case 0: St.put0(St.unload.one(frame, t0), t1, t2, t3, r0, r1, log)
    case 1: St.put1(St.unload.one(frame, t1), t0, t2, t3, r0, r1, log)
    case 2: St.put2(St.unload.one(frame, t2), t0, t1, t3, r0, r1, log)
    case _: St.put3(St.unload.one(frame, t3), t0, t1, t2, r0, r1, log)

def St.unload(s: St, +slot: U32) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.unload.at(slot, frame, t0, t1, t2, t3, r0, r1, log)

def St.note(s: St, text: String) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St{frame, t0, t1, t2, t3, r0, r1, log ++ text}

def info.text(info: J.TextureInfo) -> String:
  J.TextureInfo{id, width, height, mipmaps, format} = info
  " i" ++ U32.show(id) ++ "," ++ U32.show(width) ++ "," ++ U32.show(height) ++ "," ++ U32.show(mipmaps) ++ "," ++ U32.show(format)

def info.valid(text: String, r: J.Texture & Bool) -> J.Texture & String:
  (t, valid) = r
  (t, text ++ "," ++ Bool.pick(String, valid, "1", "0"))

def info.pair(r: J.Texture & J.TextureInfo) -> J.Texture & String:
  (t, info) = r
  info.valid(info.text(info), J.Texture.is_valid(t))

def info.some(r: J.Texture & String) -> Maybe<J.Texture> & String:
  (t, text) = r
  (Some{t}, text)

def info.maybe(tex: Maybe<J.Texture>) -> Maybe<J.Texture> & String:
  match tex:
    case None{}: (None{}, " i-")
    case Some{t}: info.some(info.pair(J.Texture.info(t)))

def bytesum(bytes: List<U32>, +acc: U32) -> U32:
  match bytes:
    case Nil{}: acc
    case Con{b, rest}: bytesum(rest, (acc + b : U32))

def image.surface(s: J.Surface) -> String:
  J.Surface{+w, +h, +format, pixels} = s
  " m" ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(format) ++ "," ++ U32.show(bytesum(J.Surface.raw(~&1, J.Surface{w, h, format, pixels}), 0))

def image.text(image: Maybe<J.Surface>) -> String:
  match image:
    case None{}: " m-"
    case Some{s}: image.surface(s)

def image.pair(r: J.Texture & Maybe<J.Surface>) -> J.Texture & String:
  (t, image) = r
  (t, image.text(image))

def image.maybe(tex: Maybe<J.Texture>) -> Maybe<J.Texture> & String:
  match tex:
    case None{}: (None{}, " m-")
    case Some{t}: info.some(image.pair(J.Texture.load_image(t)))

def St.logged(kind: U32, tex: Maybe<J.Texture>) -> Maybe<J.Texture> & String:
  match kind:
    case 0: info.maybe(tex)
    case _: image.maybe(tex)

def St.log.at(slot: U32, t: Maybe<J.Texture>, text: String, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match slot:
    case 0: St{frame, t, t1, t2, t3, r0, r1, log ++ text}
    case 1: St{frame, t0, t, t2, t3, r0, r1, log ++ text}
    case 2: St{frame, t0, t1, t, t3, r0, r1, log ++ text}
    case _: St{frame, t0, t1, t2, t, r0, r1, log ++ text}

def St.put.log(r: Maybe<J.Texture> & String, slot: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (t, text) = r
  St.log.at(slot, t, text, frame, t0, t1, t2, t3, r0, r1, log)

def St.log.pick(slot: U32, +kind: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match slot:
    case 0: St.put.log(St.logged(kind, t0), 0, frame, None{}, t1, t2, t3, r0, r1, log)
    case 1: St.put.log(St.logged(kind, t1), 1, frame, t0, None{}, t2, t3, r0, r1, log)
    case 2: St.put.log(St.logged(kind, t2), 2, frame, t0, t1, None{}, t3, r0, r1, log)
    case _: St.put.log(St.logged(kind, t3), 3, frame, t0, t1, t2, None{}, r0, r1, log)

# info (kind 0) or LoadImageFromTexture (kind 1) of slot k, appended to the log.
def St.log(s: St, +slot: U32, +kind: U32) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.log.pick(slot, kind, frame, t0, t1, t2, t3, r0, r1, log)

# Render textures.
def St.rt.put(slot: U32, frame: J.Frame, rt: Maybe<J.RenderTexture>, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match slot:
    case 0: St{frame, t0, t1, t2, t3, rt, r1, log}
    case _: St{frame, t0, t1, t2, t3, r0, rt, log}

def St.rt.loaded(slot: U32, r: J.Frame & Maybe<J.RenderTexture>, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (frame, rt) = r
  St.rt.put(slot, frame, rt, t0, t1, t2, t3, r0, r1, log)

def St.load_rt(s: St, +slot: U32, +width: U32, +height: U32) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rt.loaded(slot, J.RenderTexture.load(frame, width, height), t0, t1, t2, t3, r0, r1, log)

def rt.unload(frame: J.Frame, rt: Maybe<J.RenderTexture>) -> J.Frame:
  match rt:
    case None{}: frame
    case Some{r}: J.RenderTexture.unload(frame, r)

def rt.begin(frame: J.Frame, rt: Maybe<J.RenderTexture>) -> J.Frame:
  match rt:
    case None{}: frame
    case Some{r}: J.Frame.begin_texture_mode(frame, r)

def St.rt.act(action: U32, frame: J.Frame, rt: Maybe<J.RenderTexture>) -> J.Frame:
  match action:
    case 0: rt.unload(frame, rt)
    case _: rt.begin(frame, rt)

def St.rt.pick(slot: U32, +action: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match slot:
    case 0: St{St.rt.act(action, frame, r0), t0, t1, t2, t3, None{}, r1, log}
    case _: St{St.rt.act(action, frame, r1), t0, t1, t2, t3, r0, None{}, log}

# UnloadRenderTexture (action 0) or BeginTextureMode (1): the slot empties.
def St.rt(s: St, +slot: U32, +action: U32) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rt.pick(slot, action, frame, t0, t1, t2, t3, r0, r1, log)

def St.rt.keep(rt: Maybe<J.RenderTexture>, slot: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match rt:
    case None{}: St{frame, t0, t1, t2, t3, r0, r1, log}
    case Some{r}: St.rt.put(slot, frame, Some{r}, t0, t1, t2, t3, r0, r1, log)

def St.rt.ended(slot: U32, r: J.Frame & Maybe<J.RenderTexture>, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (frame, rt) = r
  St.rt.keep(rt, slot, frame, t0, t1, t2, t3, r0, r1, log)

# EndTextureMode: the render texture handed back goes to slot k.
def St.end_rt(s: St, +slot: U32) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rt.ended(slot, J.Frame.end_texture_mode(frame), t0, t1, t2, t3, r0, r1, log)

def rt.tex.rebuilt(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

def rt.tex.parts(frame: J.Frame, target: J.RenderTexture, f: J.Frame -> J.Texture -> J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  rt.tex.rebuilt(id, depth, f(frame, texture))

def rt.tex(frame: J.Frame, rt: Maybe<J.RenderTexture>, f: J.Frame -> J.Texture -> J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  match rt:
    case None{}: (frame, None{})
    case Some{target}: rt.tex.parts(frame, target, f)

def St.rt.texed(slot: U32, r: J.Frame & Maybe<J.RenderTexture>, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (frame, rt) = r
  St.rt.put(slot, frame, rt, t0, t1, t2, t3, r0, r1, log)

def St.rt.tex.pick(slot: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String, f: J.Frame -> J.Texture -> J.Frame & J.Texture) -> St:
  match slot:
    case 0: St.rt.texed(0, rt.tex(frame, r0, f), t0, t1, t2, t3, None{}, r1, log)
    case _: St.rt.texed(1, rt.tex(frame, r1, f), t0, t1, t2, t3, r0, None{}, log)

# A texture operation on render texture k's color texture.
def St.rt_tex(s: St, +slot: U32, f: J.Frame -> J.Texture -> J.Frame & J.Texture) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rt.tex.pick(slot, frame, t0, t1, t2, t3, r0, r1, log, f)

def rt.info.valid(text: String, r: J.RenderTexture & Bool) -> J.RenderTexture & String:
  (target, valid) = r
  (target, text ++ "," ++ Bool.pick(String, valid, "1", "0"))

def rt.info.show(+id: U32, +depth: U32, texture: J.Texture, info: J.TextureInfo) -> J.RenderTexture & String:
  J.TextureInfo{tid, _, _, _, _} = info
  rt.info.valid(" r" ++ U32.show(id) ++ "," ++ U32.show(tid) ++ "," ++ U32.show(depth), J.RenderTexture.is_valid(J.RenderTexture{id, texture, depth}))

def rt.info.with(+id: U32, +depth: U32, r: J.Texture & J.TextureInfo) -> J.RenderTexture & String:
  (texture, info) = r
  rt.info.show(id, depth, texture, info)

def rt.info.text(target: J.RenderTexture) -> J.RenderTexture & String:
  J.RenderTexture{+id, texture, +depth} = target
  rt.info.with(id, depth, J.Texture.info(texture))

def rt.image.with(+id: U32, +depth: U32, r: J.Texture & String) -> J.RenderTexture & String:
  (texture, text) = r
  (J.RenderTexture{id, texture, depth}, text)

def rt.image.text(target: J.RenderTexture) -> J.RenderTexture & String:
  J.RenderTexture{+id, texture, +depth} = target
  rt.image.with(id, depth, image.pair(J.Texture.load_image(texture)))

def rt.logged.wrap(r: J.RenderTexture & String) -> Maybe<J.RenderTexture> & String:
  (target, text) = r
  (Some{target}, text)

def rt.logged.some(kind: U32, target: J.RenderTexture) -> Maybe<J.RenderTexture> & String:
  match kind:
    case 0: rt.logged.wrap(rt.info.text(target))
    case _: rt.logged.wrap(rt.image.text(target))

def rt.logged(kind: U32, rt: Maybe<J.RenderTexture>) -> Maybe<J.RenderTexture> & String:
  match rt:
    case None{}: (None{}, " r-")
    case Some{target}: rt.logged.some(Bool.pick(U32, U32.is_eq(kind, 0), 0, 1), target)

def St.rt.log.put(slot: U32, r: Maybe<J.RenderTexture> & String, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  (rt, text) = r
  St.rt.put(slot, frame, rt, t0, t1, t2, t3, r0, r1, log ++ text)

def St.rt.log.pick(slot: U32, +kind: U32, frame: J.Frame, t0: Maybe<J.Texture>, t1: Maybe<J.Texture>, t2: Maybe<J.Texture>, t3: Maybe<J.Texture>, r0: Maybe<J.RenderTexture>, r1: Maybe<J.RenderTexture>, log: String) -> St:
  match slot:
    case 0: St.rt.log.put(0, rt.logged(kind, r0), frame, t0, t1, t2, t3, None{}, r1, log)
    case _: St.rt.log.put(1, rt.logged(kind, r1), frame, t0, t1, t2, t3, r0, None{}, log)

# rt_info (kind 0) or LoadImageFromTexture of its color texture (kind 1).
def St.rt_log(s: St, +slot: U32, +kind: U32) -> St:
  St{frame, t0, t1, t2, t3, r0, r1, log} = s
  St.rt.log.pick(slot, kind, frame, t0, t1, t2, t3, r0, r1, log)

def result.failed(frame: J.Frame, pair: J.Texture & J.Surface.Error) -> J.Frame & J.Texture:
  (t, _) = pair
  (frame, t)

def result.texture(frame: J.Frame, r: Result<&1, &1, J.Texture & J.Surface.Error, J.Texture>) -> J.Frame & J.Texture:
  match r:
    case Done{t}: (frame, t)
    case Fail{pair}: result.failed(frame, pair)

def update.with(frame: J.Frame, t: J.Texture, image: Maybe<J.Surface>) -> J.Frame & J.Texture:
  match image:
    case None{}: (frame, t)
    case Some{s}: result.texture(frame, J.Texture.update(t, s))

def update_rec.with(frame: J.Frame, t: J.Texture, rec: J.Rectangle, image: Maybe<J.Surface>) -> J.Frame & J.Texture:
  match image:
    case None{}: (frame, t)
    case Some{s}: result.texture(frame, J.Texture.update_rec(t, rec, s))

def St.finish.read(log: String, r: J.Frame & Maybe<J.Surface>) -> String:
  (_, surface) = r
  hex.maybe(surface) ++ log

def St.finish.screen(log: String, r: J.Frame & Maybe<J.Surface>) -> String:
  (frame, surface) = r
  hex.maybe(surface) ++ " " ++ screen.show(J.Frame.load_image_from_screen(frame)) ++ log

def St.finish.select(screen: Bool, log: String, frame: J.Frame) -> String:
  match screen:
    case False{}: St.finish.read(log, J.Frame.framebuffer(frame))
    case True{}: St.finish.screen(log, J.Frame.framebuffer(frame))

def St.finish(+screen: Bool, s: St) -> String:
  St{frame, _, _, _, _, _, _, log} = s
  St.finish.select(screen, log, frame)

'''

NEW_BEND = '''type Img is Data:
  Img{width: U32, height: U32, format: U32, bpp: U32, seed: U32, mask: U32, period: U32, zero: Bool}

def Img.surface(+i: Img) -> Maybe<J.Surface>:
  Img{width, height, format, bpp, seed, mask, period, zero} = i
  img(width, height, format, bpp, seed, mask, period, zero)

# A scene is data run by one interpreter: generated per-scene code made large
# inlined segments that Apple clang 21's arm64 backend rejects ("live register
# clobbered by inserted prologue instructions"). An operation is a kind and its
# argument words (F32 bits, ints, colors), so no def takes the flattened
# fields of a large sum type (which the same backend also rejected).
type Op is Data:
  Op{kind: U32, w: +List<U32>}

def word.at(n: Nat, ws: +List<U32>) -> U32:
  match n ws:
    case 0n Con{w, _}: w
    case _ Nil{}: 0
    case 1n+k Con{_, rest}: word.at(k, rest)

def word.drop(n: Nat, ws: +List<U32>) -> +List<U32>:
  match n ws:
    case 0n _: ws
    case _ Nil{}: Nil{}
    case 1n+k Con{_, rest}: word.drop(k, rest)

def wf(n: Nat, +ws: +List<U32>) -> F32:
  FC.float(word.at(n, ws))

def wu(n: Nat, +ws: +List<U32>) -> U32:
  word.at(n, ws)

def wb(n: Nat, +ws: +List<U32>) -> Bool:
  Bool.not(U32.is_eq(word.at(n, ws), 0))

def wv(n: Nat, +ws: +List<U32>) -> M.Vector2:
  +rest = word.drop(n, ws)
  M.Vector2{wf(0n, rest), wf(1n, rest)}

def wrect(n: Nat, +ws: +List<U32>) -> J.Rectangle:
  +rest = word.drop(n, ws)
  J.Rectangle{wf(0n, rest), wf(1n, rest), wf(2n, rest), wf(3n, rest)}

def wimg(n: Nat, +ws: +List<U32>) -> Img:
  +r = word.drop(n, ws)
  Img{wu(0n, r), wu(1n, r), wu(2n, r), wu(3n, r), wu(4n, r), wu(5n, r), wu(6n, r), wb(7n, r)}

def wmatrix(+r: +List<U32>) -> M.Matrix:
  M.Matrix{wf(0n, r), wf(4n, r), wf(8n, r), wf(12n, r), wf(1n, r), wf(5n, r), wf(9n, r), wf(13n, r), wf(2n, r), wf(6n, r), wf(10n, r), wf(14n, r),
    wf(3n, r), wf(7n, r), wf(11n, r), wf(15n, r)}

def wnpatch(+r: +List<U32>) -> J.NPatchInfo:
  J.NPatchInfo{wrect(0n, r), wf(4n, r), wf(5n, r), wf(6n, r), wf(7n, r), wf(8n, r)}

# Texture operations (kinds 100..): words after the slot and render-texture flag.
def texop(kind: U32, +w: +List<U32>, frame: J.Frame, tex: J.Texture) -> J.Frame & J.Texture:
  match kind:
    case 100: J.Draw.texture(frame, tex, wf(0n, w), wf(1n, w), wu(2n, w))
    case 101: J.Draw.texture_v(frame, tex, wv(0n, w), wu(2n, w))
    case 102: J.Draw.texture_ex_for(libm(), frame, tex, wv(0n, w), wf(2n, w), wf(3n, w), wu(4n, w))
    case 103: J.Draw.texture_rec(frame, tex, wrect(0n, w), wv(4n, w), wu(6n, w))
    case 104: J.Draw.texture_pro_for(libm(), frame, tex, wrect(0n, w), wrect(4n, w), wv(8n, w), wf(10n, w), wu(11n, w))
    case 105: J.Draw.texture_npatch_for(libm(), frame, tex, wnpatch(w), wrect(9n, w), wv(13n, w), wf(15n, w), wu(16n, w))
    case 106: (frame, J.Texture.set_filter(tex, wu(0n, w)))
    case 107: (frame, J.Texture.set_wrap(tex, wu(0n, w)))
    case 108: (frame, J.Texture.gen_mipmaps(tex))
    case 109: update.with(frame, tex, Img.surface(wimg(0n, w)))
    case _: update_rec.with(frame, tex, wrect(0n, w), Img.surface(wimg(4n, w)))

def step.tex(rt: Bool, +slot: U32, +kind: U32, +w: +List<U32>, s: St) -> St:
  match rt:
    case False{}: St.tex(s, slot, fr => tx => texop(kind, w, fr, tx))
    case True{}: St.rt_tex(s, slot, fr => tx => texop(kind, w, fr, tx))

# Frame operations (kinds 0..39).
def step.frame(kind: U32, +w: +List<U32>, frame: J.Frame) -> J.Frame:
  match kind:
    case 0: J.Frame.begin_drawing(frame)
    case 1: J.Frame.end_drawing(frame)
    case 2: J.Frame.clear_background(frame, wu(0n, w))
    case 3: J.Draw.rectangle(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w), wu(4n, w))
    case 4: J.Draw.rectangle_rec(frame, wrect(0n, w), wu(4n, w))
    case 5: J.Draw.rectangle_lines(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w), wu(4n, w))
    case 6: J.Draw.circle_v_for(libm(), frame, wv(0n, w), wf(2n, w), wu(3n, w))
    case 7: J.Draw.line(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w), wu(4n, w))
    case 8: J.Draw.line_v(frame, wv(0n, w), wv(2n, w), wu(4n, w))
    case 9: J.Draw.triangle(frame, wv(0n, w), wv(2n, w), wv(4n, w), wu(6n, w))
    case 10: J.Draw.pixel(frame, wf(0n, w), wf(1n, w), wu(2n, w))
    case 11: J.Draw.pixel_v(frame, wv(0n, w), wu(2n, w))
    case 12: J.Frame.begin_mode_2d_for(libm(), frame, J.Camera2D{wv(0n, w), wv(2n, w), wf(4n, w), wf(5n, w)})
    case 13: J.Frame.end_mode_2d(frame)
    case 14: J.Rlgl.push_matrix(frame)
    case 15: J.Rlgl.pop_matrix(frame)
    case 16: J.Rlgl.load_identity(frame)
    case 17: J.Rlgl.translatef(frame, wf(0n, w), wf(1n, w), wf(2n, w))
    case 18: J.Rlgl.scalef(frame, wf(0n, w), wf(1n, w), wf(2n, w))
    case 19: J.Rlgl.rotatef_for(libm(), frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w))
    case 20: J.Rlgl.mult_matrixf(frame, wmatrix(w))
    case 21: J.Frame.begin_scissor_mode(frame, wf(0n, w), wf(1n, w), wf(2n, w), wf(3n, w))
    case 22: J.Frame.end_scissor_mode(frame)
    case 23: J.Frame.begin_blend_mode(frame, wu(0n, w))
    case 24: J.Frame.end_blend_mode(frame)
    case _: frame

def St.load.many(n: Nat, s: St, +slot: U32, +image: Img) -> St:
  match n:
    case 0n: s
    case 1n+rest: St.load.many(rest, St.load(s, slot, Img.surface(image)), slot, image)

# Slot operations (kinds 40..99).
def step.slot(kind: U32, +w: +List<U32>, s: St) -> St:
  match kind:
    case 40: St.load(s, wu(0n, w), Img.surface(wimg(1n, w)))
    case 41: St.load.many(U32.to_nat(wu(1n, w)), s, wu(0n, w), wimg(2n, w))
    case 42: St.unload(s, wu(0n, w))
    case 43: St.log(s, wu(0n, w), 0)
    case 44: St.log(s, wu(0n, w), 1)
    case 45: St.load_rt(s, wu(0n, w), wu(1n, w), wu(2n, w))
    case 46: St.rt(s, wu(0n, w), 0)
    case 47: St.rt(s, wu(0n, w), 1)
    case 48: St.end_rt(s, wu(0n, w))
    case 49: St.rt_log(s, wu(0n, w), 0)
    case 50: St.rt_log(s, wu(0n, w), 1)
    case _: step.tex(wb(1n, w), wu(0n, w), wu(2n, w), word.drop(3n, w), s)

def step.select(frame_op: Bool, +kind: U32, +w: +List<U32>, s: St) -> St:
  match frame_op:
    case True{}: St.frame(s, f => step.frame(kind, w, f))
    case False{}: step.slot(kind, w, s)

def step(op: Op, s: St) -> St:
  Op{+kind, +w} = op
  step.select((kind < 40 : U32), kind, w, s)

def exec(ops: +List<Op>, s: St) -> St:
  match ops:
    case Nil{}: s
    case Con{op, rest}: exec(rest, step(op, s))

def St.run(ops: +List<Op>, +screen: Bool, frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: St.finish(screen, exec(ops, St.new(f)))
'''


def bimg(spec):
    return [spec['width'], spec['height'], spec['format'], BPP[spec['format']], spec['seed'], spec['mask'], spec['period'], int(spec['zero'])]


def wrec(r):
    return [fp.word(x) for x in r]


NPATCH_RT = ('npatch', 0, ((0.0, 0.0, 8.0, 8.0), 2.0, 2.0, 2.0, 2.0, 0.0), (12.0, 2.0, 9.0, 14.0), (0.0, 0.0), 0.0, C(255, 255, 255))

FRAME_KINDS = {'begin': 0, 'end': 1, 'clear': 2, 'rect': 3, 'rect_rec': 4, 'rect_lines': 5, 'circle_v': 6, 'line': 7, 'line_v': 8, 'tri': 9,
               'pixel': 10, 'pixel_v': 11, 'mode2d': 12, 'end2d': 13, 'push': 14, 'pop': 15, 'identity': 16, 'translate': 17, 'scale': 18,
               'rotate': 19, 'mult': 20, 'scissor': 21, 'end_scissor': 22, 'blend': 23, 'end_blend': 24}
SLOT_KINDS = {'load': 40, 'load_many': 41, 'unload': 42, 'info': 43, 'image': 44, 'load_rt': 45, 'unload_rt': 46, 'begin_rt': 47, 'end_rt': 48,
              'rt_info': 49, 'image_rt': 50}
TEX_KINDS = {'draw': 100, 'draw_v': 101, 'draw_ex': 102, 'draw_rec': 103, 'draw_pro': 104, 'npatch': 105, 'filter': 106, 'wrap': 107,
             'mipmaps': 108, 'update': 109, 'update_rec': 110}
COLOR_LAST = {'clear', 'rect', 'rect_rec', 'rect_lines', 'circle_v', 'line', 'line_v', 'tri', 'pixel', 'pixel_v'}


def op_words(op):
    """(kind, words) of an operation: floats as F32 bits, ints and colors as they are."""
    name, a = op[0], op[1:]
    if name in FRAME_KINDS:
        if name in COLOR_LAST:
            return FRAME_KINDS[name], [fp.word(x) for x in a[:-1]] + [a[-1]]
        if name == 'mult':
            return FRAME_KINDS[name], [fp.word(x) for x in a[0]]
        if name == 'blend':
            return FRAME_KINDS[name], [a[0]]
        return FRAME_KINDS[name], [fp.word(x) for x in a]
    if name == 'draw_npatch_rt':
        return op_words(('npatch_rt', a[0]) + NPATCH_RT[2:])
    if name in SLOT_KINDS:
        if name in ('load', 'load_many'):
            return SLOT_KINDS[name], list(a[:-1]) + bimg(a[-1])
        return SLOT_KINDS[name], list(a)
    rt = name.endswith('_rt')
    base = name[:-3] if rt else name
    slot, b = a[0], a[1:]
    words = {
        'draw': lambda: [fp.word(b[0]), fp.word(b[1]), b[2]],
        'draw_v': lambda: [fp.word(b[0]), fp.word(b[1]), b[2]],
        'draw_ex': lambda: [fp.word(x) for x in b[:4]] + [b[4]],
        'draw_rec': lambda: wrec(b[0]) + [fp.word(b[1]), fp.word(b[2]), b[3]],
        'draw_pro': lambda: wrec(b[0]) + wrec(b[1]) + [fp.word(b[2][0]), fp.word(b[2][1]), fp.word(b[3]), b[4]],
        'npatch': lambda: wrec(b[0][0]) + [fp.word(x) for x in b[0][1:]] + wrec(b[1]) + [fp.word(b[2][0]), fp.word(b[2][1]), fp.word(b[3]), b[4]],
        'filter': lambda: [b[0]], 'wrap': lambda: [b[0]], 'mipmaps': lambda: [],
        'update': lambda: bimg(b[0]), 'update_rec': lambda: wrec(b[0]) + bimg(b[1]),
    }[base]()
    return 99, [slot, int(rt), TEX_KINDS[base]] + words


def b_op(op):
    kind, words = op_words(op)
    return f'Op{{{kind}, [{", ".join(str(w) for w in words)}]}}'


def b_scene(index, scene):
    return f'def scene.{index}() -> +List<Op>:\n  [' + ',\n    '.join(b_op(op) for op in scene['ops']) + ']'


def render(libm):
    def build(selected, gpu):
        body = [PROGRAM, f'def libm() -> M.Libm:\n  M.{libm}{{}}', NEW_BEND]
        prints = []
        for index, item in selected:
            body.append(b_scene(index, item))
            screen = 'True{}' if item['screen'] else 'False{}'
            prints.append(f'    IO.print(St.run(scene.{index}(), {screen}, J.Frame.init_window({item["width"]}, {item["height"]})))')
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(prints) + '\n')
        return '\n\n'.join(body)
    return build


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('texture', args, raylib_options=fp.OPTIONS)
    libm = gradient_reference()
    fused = fp.fused_instructions(probe.library)
    if any(fused.values()):
        raise ProbeFailure(f'texture: the reference build contains fused multiply-adds: {fused}')
    items = scenes(libm)
    native_items = [s for s in items if not refused(s, libm)]
    contracts = [s for s in items if s not in native_items]
    source = C_PREFIX + '\n'.join(c_scene(s) for s in native_items) + '\n    return 0;\n}\n'
    output = [line for line in probe.native(source, 'reference', extra_flags=('-ffp-contract=off',)).splitlines() if line.startswith('F ')]
    if len(output) != len(native_items):
        raise ProbeFailure(f'texture: reference printed {len(output)} frames for {len(native_items)} scenes')
    expected_by_id = {}
    for scene, line in zip(native_items, output):
        parts = line[2:].split(' ')
        frames = 1 + scene['screen']
        if 'MISMATCH' in parts:
            raise ProbeFailure(f'texture: {scene["id"]}: LoadImageFromScreen is not the flipped, swapped, opaque framebuffer')
        expected_by_id[scene['id']] = ' '.join(parts[:frames]) + ''.join(' ' + p for p in parts[frames:] if p)
    for scene in contracts:
        expected_by_id[scene['id']] = 'null' + (' null' if scene['screen'] else '')
    expected = [expected_by_id[s['id']] for s in items]
    actions = list(enumerate(items))
    lanes = probe.candidates(render(libm), actions, batch=24, parse=lambda text, selected: [line for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda i: f'scene {items[i]["id"]}')
    probe.finish(scenes=len(items), compared=len(native_items), contracts=len(contracts), libm=libm,
                 operations=sum(len(s['ops']) for s in items), fused_free_objects=len(fused),
                 scenes_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
