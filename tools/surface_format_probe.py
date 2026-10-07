#!/usr/bin/env python3
"""Run every format-generic Surface operation on pixel formats 1..13 against raylib.

Each case converts one R8G8B8A8 fixture with ImageFormat, applies one operation
and compares the complete stored result (format, dimensions and raw sample
bytes, or the returned colors) exactly; `to-N` cases are ImageFormat to every
format. ImageRotate blends float bytes too; when raylib's R32/R16 result leaves
finite [0,1] or a wide F32 result holds NaN, Jonlib must refuse it (the owner
domain), so those cases expect a rejection.
"""
import hashlib
import json
import random
import struct

from byte_probe import C_IMAGE, SURFACE_EMITTER, parse_results
from conformance import gradient_reference
import probekit
from probekit import ProbeFailure

FORMATS = range(1, 14)
SIZES = ((5, 4), (6, 3))
DRAW = (230, 40, 120, 200)
FILL = (10, 200, 30, 128)
UNSUPPORTED = set()
LIBM = gradient_reference()


def word(color):
    r, g, b, a = color
    return (r << 24) | (g << 16) | (b << 8) | a


def c_color(color):
    return '(Color){%d,%d,%d,%d}' % color


WHITE = (255, 255, 255, 255)
TINT = (200, 100, 50, 180)
HALF = (255, 255, 255, 200)
# ImageDraw sources: (name, source format or 0 for the image's, srcRec, dstRec, tint);
# draw.op in PROGRAM runs the same calls by index.
DRAWS = (
    ('same', 0, '(Rectangle){0,0,m.width,m.height}', '(Rectangle){1,1,m.width,m.height}', WHITE),
    ('rgba-tinted', 7, '(Rectangle){0,0,m.width,m.height}', '(Rectangle){-1,1,m.width,m.height}', TINT),
    ('gray', 1, '(Rectangle){0,0,m.width,m.height}', '(Rectangle){2,-1,m.width,m.height}', WHITE),
    ('float', 9, '(Rectangle){0,0,m.width,m.height}', '(Rectangle){1,0,m.width,m.height}', WHITE),
    ('rect-rgb', 4, '(Rectangle){0.5f,0,3,2}', '(Rectangle){1,1,5,3}', WHITE),
    ('region-gray-alpha', 2, '(Rectangle){1,0,2,2}', '(Rectangle){0,1,2,2}', HALF),
)


# name: (C statement on `Image im` that leaves the result in `out`, kind, Bend expression on `s`)
# kind: 'total' and 'image' (Result) emit a Surface; 'colors' RGBA bytes; 'color' one RGBA color;
# 'rect' four F32 words; 'palette' the count and every padded entry.
OPS = {
    'flip-vertical': ('ImageFlipVertical(&im);', 'total', 'J.Surface.flip_vertical(s)'),
    'flip-horizontal': ('ImageFlipHorizontal(&im);', 'total', 'J.Surface.flip_horizontal(s)'),
    'rotate-cw': ('ImageRotateCW(&im);', 'total', 'J.Surface.rotate_cw(s)'),
    'rotate-ccw': ('ImageRotateCCW(&im);', 'total', 'J.Surface.rotate_ccw(s)'),
    'crop': ('ImageCrop(&im,(Rectangle){1,1,3,2});', 'image', 'J.Surface.crop(s, J.Rectangle{1.0, 1.0, 3.0, 2.0})'),
    'from-image': ('{Image r=ImageFromImage(im,(Rectangle){1,0,2,3});UnloadImage(im);im=r;}', 'image',
                   'second(J.Surface.extract(s, J.Rectangle{1.0, 0.0, 2.0, 3.0}))'),
    'resize-canvas': (f'ImageResizeCanvas(&im,7,3,-1,1,{c_color(FILL)});', 'image',
                      f'J.Surface.resize_canvas(s, 7, 3, F32.neg(1.0), 1.0, {word(FILL)})'),
    'copy': ('{Image r=ImageCopy(im);UnloadImage(im);im=r;}', 'image', 'copied(J.Surface.copy(s))'),
    'tint': ('ImageColorTint(&im,(Color){200,100,50,180});', 'image', f'J.Surface.color_tint(s, {word((200, 100, 50, 180))})'),
    'invert': ('ImageColorInvert(&im);', 'image', 'J.Surface.color_invert(s)'),
    'contrast': ('ImageColorContrast(&im,37.5f);', 'image', 'J.Surface.color_contrast(s, 37.5)'),
    'brightness': ('ImageColorBrightness(&im,-40);', 'image', 'J.Surface.color_brightness(s, F32.neg(40.0))'),
    'replace': ('ImageColorReplace(&im,(Color){0,0,0,255},(Color){12,34,56,78});', 'image',
                f'J.Surface.color_replace(s, 255, {word((12, 34, 56, 78))})'),
    'grayscale': ('ImageColorGrayscale(&im);', 'image', 'J.Surface.color_grayscale(s)'),
    'premultiply': ('ImageAlphaPremultiply(&im);', 'image', 'J.Surface.alpha_premultiply(s)'),
    'blur': ('ImageBlurGaussian(&im,1);', 'image', 'J.Surface.blur_gaussian(s, 1)'),
    'convolution': ('{float k[9]={0.0625f,0.125f,0.0625f,0.125f,0.25f,0.125f,0.0625f,0.125f,0.0625f};ImageKernelConvolution(&im,k,9);}',
                    'image', 'J.Surface.kernel_convolution(s, [0.0625, 0.125, 0.0625, 0.125, 0.25, 0.125, 0.0625, 0.125, 0.0625])'),
    'resize': ('ImageResize(&im,7,3);', 'image', 'J.Surface.resize(s, 7, 3)'),
    'resize-nn': ('ImageResizeNN(&im,7,3);', 'image', 'J.Surface.resize_nn(s, 7, 3)'),
    'dither': ('ImageDither(&im,5,6,5,0);', 'image', 'J.Surface.dither(s, 5, 6, 5, 0)'),
    'dither-4444': ('ImageDither(&im,4,4,4,4);', 'image', 'J.Surface.dither(s, 4, 4, 4, 4)'),
    'clear': (f'ImageClearBackground(&im,{c_color(DRAW)});', 'total', f'J.Surface.clear(s, {word(DRAW)})'),
    'pixel': (f'ImageDrawPixel(&im,2,1,{c_color(DRAW)});', 'total', f'J.Surface.draw_pixel(s, 2.0, 1.0, {word(DRAW)})'),
    'rectangle': (f'ImageDrawRectangle(&im,1,1,3,2,{c_color(DRAW)});', 'total',
                  f'J.Surface.draw_rectangle(s, 1.0, 1.0, 3.0, 2.0, {word(DRAW)})'),
    'circle': (f'ImageDrawCircle(&im,2,2,2,{c_color(DRAW)});', 'total', f'J.Surface.draw_circle(s, 2.0, 2.0, 2, {word(DRAW)})'),
    'line': (f'ImageDrawLine(&im,0,0,4,3,{c_color(DRAW)});', 'total', f'J.Surface.draw_line(s, 0.0, 0.0, 4.0, 3.0, {word(DRAW)})'),
    'triangle': (f'ImageDrawTriangle(&im,(Vector2){{0,0}},(Vector2){{1,3}},(Vector2){{4,1}},{c_color(DRAW)});', 'total',
                 f'J.Surface.draw_triangle(s, M.Vector2{{0.0, 0.0}}, M.Vector2{{1.0, 3.0}}, M.Vector2{{4.0, 1.0}}, {word(DRAW)})'),
    'triangle-ex': ('ImageDrawTriangleEx(&im,(Vector2){0,0},(Vector2){1,3},(Vector2){4,1},(Color){255,0,0,255},(Color){0,255,0,128},(Color){0,0,255,0});',
                    'total', f'J.Surface.draw_triangle_ex(s, M.Vector2{{0.0, 0.0}}, M.Vector2{{1.0, 3.0}}, M.Vector2{{4.0, 1.0}}, '
                    f'{word((255, 0, 0, 255))}, {word((0, 255, 0, 128))}, {word((0, 0, 255, 0))})'),
    'from-channel': ('{Image r=ImageFromChannel(im,1);UnloadImage(im);im=r;}', 'image', 'second(J.Surface.from_channel(s, 1.0))'),
    'alpha-crop': ('ImageAlphaCrop(&im,0.3f);', 'total', 'J.Surface.alpha_crop(s, 0.3)'),
    'pixel-v': (f'ImageDrawPixelV(&im,(Vector2){{2.7f,1.2f}},{c_color(DRAW)});', 'total', f'J.Surface.draw_pixel_v(s, M.Vector2{{2.7, 1.2}}, {word(DRAW)})'),
    'rectangle-v': (f'ImageDrawRectangleV(&im,(Vector2){{1,1}},(Vector2){{3,2}},{c_color(DRAW)});', 'total',
                    f'J.Surface.draw_rectangle_v(s, M.Vector2{{1.0, 1.0}}, M.Vector2{{3.0, 2.0}}, {word(DRAW)})'),
    'rectangle-rec': (f'ImageDrawRectangleRec(&im,(Rectangle){{0.5f,1,3.5f,2}},{c_color(DRAW)});', 'total',
                      f'J.Surface.draw_rectangle_rec(s, J.Rectangle{{0.5, 1.0, 3.5, 2.0}}, {word(DRAW)})'),
    'rectangle-lines': (f'ImageDrawRectangleLines(&im,(Rectangle){{0,0,5,3}},1,{c_color(DRAW)});', 'total',
                        f'J.Surface.draw_rectangle_lines(s, J.Rectangle{{0.0, 0.0, 5.0, 3.0}}, 1, {word(DRAW)})'),
    'circle-v': (f'ImageDrawCircleV(&im,(Vector2){{2,2}},2,{c_color(DRAW)});', 'total', f'J.Surface.draw_circle_v(s, M.Vector2{{2.0, 2.0}}, 2, {word(DRAW)})'),
    'circle-lines': (f'ImageDrawCircleLines(&im,2,2,2,{c_color(DRAW)});', 'total', f'J.Surface.draw_circle_lines(s, 2.0, 2.0, 2, {word(DRAW)})'),
    'circle-lines-v': (f'ImageDrawCircleLinesV(&im,(Vector2){{2,2}},2,{c_color(DRAW)});', 'total',
                       f'J.Surface.draw_circle_lines_v(s, M.Vector2{{2.0, 2.0}}, 2, {word(DRAW)})'),
    'line-v': (f'ImageDrawLineV(&im,(Vector2){{0,0}},(Vector2){{4,3}},{c_color(DRAW)});', 'total',
               f'J.Surface.draw_line_v(s, M.Vector2{{0.0, 0.0}}, M.Vector2{{4.0, 3.0}}, {word(DRAW)})'),
    'line-ex': (f'ImageDrawLineEx(&im,(Vector2){{0,0}},(Vector2){{4,3}},2,{c_color(DRAW)});', 'total',
                f'J.Surface.draw_line_ex(s, M.Vector2{{0.0, 0.0}}, M.Vector2{{4.0, 3.0}}, 2, {word(DRAW)})'),
    'triangle-lines': (f'ImageDrawTriangleLines(&im,(Vector2){{0,0}},(Vector2){{1,3}},(Vector2){{4,1}},{c_color(DRAW)});', 'total',
                       f'J.Surface.draw_triangle_lines(s, M.Vector2{{0.0, 0.0}}, M.Vector2{{1.0, 3.0}}, M.Vector2{{4.0, 1.0}}, {word(DRAW)})'),
    'triangle-fan': (f'{{Vector2 p[4]={{{{2,2}},{{0,0}},{{0,3}},{{4,3}}}};ImageDrawTriangleFan(&im,p,4,{c_color(DRAW)});}}', 'total',
                     f'J.Surface.draw_triangle_fan(s, [M.Vector2{{2.0, 2.0}}, M.Vector2{{0.0, 0.0}}, M.Vector2{{0.0, 3.0}}, M.Vector2{{4.0, 3.0}}], {word(DRAW)})'),
    'triangle-strip': (f'{{Vector2 p[4]={{{{0,0}},{{0,3}},{{3,0}},{{4,3}}}};ImageDrawTriangleStrip(&im,p,4,{c_color(DRAW)});}}', 'total',
                       f'J.Surface.draw_triangle_strip(s, [M.Vector2{{0.0, 0.0}}, M.Vector2{{0.0, 3.0}}, M.Vector2{{3.0, 0.0}}, M.Vector2{{4.0, 3.0}}], {word(DRAW)})'),
    'to-pot': (f'ImageToPOT(&im,{c_color(FILL)});', 'image', f'J.Surface.to_pot(s, {word(FILL)})'),
    'alpha-clear': (f'ImageAlphaClear(&im,{c_color(DRAW)},0.3f);', 'image', f'J.Surface.alpha_clear(s, {word(DRAW)}, 0.3)'),
    'alpha-clear-high': (f'ImageAlphaClear(&im,{c_color(FILL)},0.8f);', 'image', f'J.Surface.alpha_clear(s, {word(FILL)}, 0.8)'),
    'rotate': ('ImageRotate(&im,30);', 'image', f'J.Surface.rotate_degrees_for(M.{LIBM}{{}}, s, 30.0)'),
    'rotate-obtuse': ('ImageRotate(&im,-135);', 'image', f'J.Surface.rotate_degrees_for(M.{LIBM}{{}}, s, F32.neg(135.0))'),
    **{f'draw-{name}': (f'{{Image m=ImageCopy(im);ImageFlipVertical(&m);{fmt_c}ImageDraw(&im,m,{src_rec},{dst_rec},{c_color(tint)});UnloadImage(m);}}',
                        'image', f'drawn({kind}, {target}, J.Surface.copy(s))')
       for kind, (name, target, src_rec, dst_rec, tint) in enumerate(DRAWS)
       for fmt_c in [f'ImageFormat(&m,{target});' if target else '']},
    **{f'to-{target}': (f'ImageFormat(&im,{target});', 'image', f'J.Surface.format(s, {target})') for target in range(1, 14)},
    'alpha-mask': ('{Image m=ImageCopy(im);ImageFlipHorizontal(&m);ImageAlphaMask(&im,m);UnloadImage(m);}', 'image', 'masked(0, J.Surface.copy(s))'),
    'alpha-mask-rgb': ('{Image m=ImageCopy(im);ImageFlipHorizontal(&m);ImageFormat(&m,4);ImageAlphaMask(&im,m);UnloadImage(m);}', 'image',
                       'masked(4, J.Surface.copy(s))'),
    'alpha-border': ('', 'rect', 'J.Surface.alpha_border(s, 0.3)'),
    'palette': ('', 'palette', 'J.Surface.load_palette(s, 8)'),
    'colors': ('', 'colors', 'J.Surface.colors(s)'),
    'get': ('', 'color', 'J.Surface.get(s, 2, 1)'),
}

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
''' + SURFACE_EMITTER + '''def color_bytes(colors: List<U32>, values: List<U32>) -> List<U32>:
  match colors:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{+color, rest}: color_bytes(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), values}}}})
def colors(result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{values}: emit_bytes(~&1, color_bytes(values, Nil{}))
def color(result: J.Surface & Maybe<&2, U32>) -> IO(Unit):
  match result:
    case Tuple{_, None{}}: IO.print("null")
    case Tuple{_, Some{value}}: emit_bytes(~&1, color_bytes([value], Nil{}))
def float_bytes(+x: F32, +y: F32, +width: F32, +height: F32) -> List<U32>:
  List.reverse(&1, U32, word_bytes(4n, F32.bits(height), word_bytes(4n, F32.bits(width), word_bytes(4n, F32.bits(y), word_bytes(4n, F32.bits(x), Nil{})))))
def rect(result: J.Surface & J.Rectangle) -> IO(Unit):
  match result:
    case Tuple{_, J.Rectangle{x, y, width, height}}: emit_bytes(~&1, float_bytes(x, y, width, height))
def entry_bytes(colors: +List<U32>, values: List<U32>) -> List<U32>:
  match colors:
    case Nil{}: List.reverse(&1, U32, values)
    case Con{+color, rest}: entry_bytes(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), values}}}})
def palette_entries(entries: U32 & +List<U32>) -> IO(Unit):
  (count, colors) = entries
  emit_bytes(~&1, prepend(word_bytes(4n, count, Nil{}), entry_bytes(colors, Nil{})))
def palette(result: J.Surface & Maybe<J.Image.Palette>) -> IO(Unit):
  match result:
    case Tuple{_, None{}}: IO.print("null")
    case Tuple{_, Some{found}}: palette_entries(J.Image.Palette.entries(found))
def masked.result(result: Result<&1, &1, (J.Surface & J.Surface) & J.Surface.Error, J.Surface & J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match result:
    case Fail{Tuple{Tuple{image, _}, error}}: Fail{(image, error)}
    case Done{Tuple{image, _}}: Done{image}
def masked.with(image: J.Surface, mask: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match mask:
    case Fail{Tuple{_, error}}: Fail{(image, error)}
    case Done{alpha}: masked.result(J.Surface.alpha_mask(image, alpha))
def masked(+format: U32, pair: J.Surface & J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  (image, copy) = pair
  masked.with(image, J.Surface.format(J.Surface.flip_horizontal(copy), format))
def draw.op(kind: U32, image: J.Surface, source: J.Surface) -> Result<&1, &1, (J.Surface & J.Surface) & J.Surface.Error, J.Surface & J.Surface>:
  match kind:
    case 0: J.Surface.draw_image(image, source, 1.0, 1.0, 4294967295)
    case 1: J.Surface.draw_image(image, source, F32.neg(1.0), 1.0, 3362009780)
    case 2: J.Surface.draw_image(image, source, 2.0, F32.neg(1.0), 4294967295)
    case 3: J.Surface.draw_image(image, source, 1.0, 0.0, 4294967295)
    case 4: J.Surface.draw_image_rect(image, source, J.Rectangle{0.5, 0.0, 3.0, 2.0}, J.Rectangle{1.0, 1.0, 5.0, 3.0}, 4294967295)
    case _: J.Surface.draw_image_region(image, source, J.Rectangle{1.0, 0.0, 2.0, 2.0}, 0.0, 1.0, 4294967240)
def drawn.with(kind: U32, image: J.Surface, source: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match source:
    case Fail{Tuple{_, error}}: Fail{(image, error)}
    case Done{drawn_source}: masked.result(draw.op(kind, image, drawn_source))
def drawn(kind: U32, +format: U32, pair: J.Surface & J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  (image, copy) = pair
  drawn.with(kind, image, J.Surface.format(J.Surface.flip_vertical(copy), format))
def done(surface: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  Done{surface}
def second(result: J.Surface & Maybe<J.Surface>) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match result:
    case Tuple{original, None{}}: Fail{(original, J.InvalidRequest{})}
    case Tuple{_, Some{region}}: Done{region}
def copied(pair: J.Surface & J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  (_, copy) = pair
  Done{copy}
def formatted(~operation: J.Surface -> IO(Unit), result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "fixture format conversion failed")
    case Done{surface}: operation(surface)
def run(~operation: J.Surface -> IO(Unit), +format: U32, source: Maybe<J.Surface>) -> IO(Unit):
  match source:
    case None{}: IO.die(Unit, 1, "fixture creation failed")
    case Some{surface}: formatted(~operation, J.Surface.format(surface, format))
'''


def fixtures():
    rng = random.Random(0x5355524641)
    cases = []
    for width, height in SIZES:
        data = [rng.randrange(256) for _ in range(width * height * 4)]
        data[:4] = [0, 0, 0, 255]
        for i in range(1, width * height):
            data[4 * i + 3] = (0, 255, 77, 128, 255, 200)[i % 6]
        cases.append(dict(width=width, height=height, bytes=data))
    return cases


def actions(cases):
    return [(i, op, fmt) for i in range(len(cases)) for op in OPS for fmt in FORMATS]


def native(probe, cases, selected):
    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <stdlib.h>', '#include <string.h>',
             C_IMAGE,
             'static void color(Color c){byte(c.r);byte(c.g);byte(c.b);byte(c.a);}',
             'static void fword(float f){unsigned u;memcpy(&u,&f,4);word(u);}']
    for i, case in enumerate(cases):
        lines.append(f'static const unsigned char fixture{i}[]={{{",".join(map(str, case["bytes"]))}}};')
        lines.append(f'static Image source{i}(int format){{Image im={{0}};im.width={case["width"]};im.height={case["height"]};'
                     f'im.mipmaps=1;im.format=7;im.data=malloc(sizeof fixture{i});memcpy(im.data,fixture{i},sizeof fixture{i});'
                     'ImageFormat(&im,format);if(im.format!=format)exit(4);return im;}')
    lines.append('int main(void){SetTraceLogLevel(LOG_NONE);')
    for i, op, fmt in selected:
        statement, kind, _ = OPS[op]
        if (op, fmt) in UNSUPPORTED:
            lines.append('puts("null");')
        elif kind in ('image', 'total'):
            lines.append(f'{{Image im=source{i}({fmt});{statement}image(im);UnloadImage(im);}}')
        elif kind == 'colors':
            lines.append(f'{{Image im=source{i}({fmt});Color *c=LoadImageColors(im);for(int k=0;k<im.width*im.height;k++)color(c[k]);'
                         'end();UnloadImageColors(c);UnloadImage(im);}')
        elif kind == 'rect':
            lines.append(f'{{Image im=source{i}({fmt});Rectangle r=GetImageAlphaBorder(im,0.3f);fword(r.x);fword(r.y);fword(r.width);fword(r.height);'
                         'end();UnloadImage(im);}')
        elif kind == 'palette':
            lines.append(f'{{Image im=source{i}({fmt});int count=0;Color *p=LoadImagePalette(im,8,&count);word(count);for(int k=0;k<8;k++)color(p[k]);'
                         'end();UnloadImagePalette(p);UnloadImage(im);}')
        else:
            lines.append(f'{{Image im=source{i}({fmt});color(GetImageColor(im,2,1));end();UnloadImage(im);}}')
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n')


def render(cases):
    def emit(selected, gpu):
        body = PROGRAM
        used = sorted({op for _, op, _ in selected})
        for op in used:
            _, kind, expression = OPS[op]
            call = {'total': f'image(done({expression}))', 'image': f'image({expression})',
                    'colors': f'colors({expression})', 'color': f'color({expression})',
                    'rect': f'rect({expression})', 'palette': f'palette({expression})'}[kind]
            body += f'def op_{op.replace("-", "_")}(s: J.Surface) -> IO(Unit):\n  {call}\n'
        sources = {i for i, _, _ in selected}
        for i in sorted(sources):
            case = cases[i]
            body += (f'def source{i}() -> Maybe<J.Surface>:\n  J.Surface.from_bytes({case["width"]}, {case["height"]}, 7, '
                     f'[{",".join(map(str, case["bytes"]))}])\n')
        body += 'def main() -> IO(Unit):\n  do IO<Unit>:\n'
        for i, op, fmt in selected:
            body += f"    run(~op_{op.replace('-', '_')}, {fmt}, source{i}())\n"
        return body
    return emit


def owner_domain(op, fmt, row):
    """Jonlib refuses rotated float bytes outside the owner domain: R32 and R16
    finite [0,1], F32 samples of R32G32B32(A32) not NaN."""
    if not op.startswith('rotate') or fmt not in (8, 9, 10, 11) or row is None:
        return row
    data = bytes(row[12:])
    if fmt == 11:
        halves = struct.unpack(f'<{len(data) // 2}H', data)
        return None if any(h > 0x3C00 and h != 0x8000 for h in halves) else row
    words = struct.unpack(f'<{len(data) // 4}I', data)
    if fmt == 8 and any(w > 0x3F800000 and w != 0x80000000 for w in words):
        return None
    if fmt in (9, 10) and any((w & 0x7FFFFFFF) > 0x7F800000 for w in words):
        return None
    return row


def main():
    probe = probekit.Probe('surface-format', probekit.arguments(__doc__))
    cases = fixtures()
    planned = actions(cases)
    native_rows = parse_results(native(probe, cases, planned))
    expected = [owner_domain(op, fmt, row) for (_, op, fmt), row in zip(planned, native_rows)]
    if len(expected) != len(planned):
        raise ProbeFailure(f'native output has {len(expected)} rows for {len(planned)} cases')
    for (i, op, fmt), row in zip(planned, native_rows):
        if (row is None) != ((op, fmt) in UNSUPPORTED):
            raise ProbeFailure(f'native row presence differs from the profile for {op} on format {fmt}')
    lanes = probe.candidates(render(cases), planned, batch=96, parse=lambda text, selected: parse_results(text))
    for lane, rows in lanes.items():
        wrong = sorted({(op, fmt) for (i, op, fmt), a, b in zip(planned, expected, rows) if a != b})
        if wrong:
            probe.report.setdefault('mismatches', {})[lane] = [f'{op}@{fmt}' for op, fmt in wrong]
    probe.compare(expected, lanes, describe=lambda index: '{1} on format {2}, fixture {0}'.format(*planned[index]))
    probe.finish(cases=len(planned), operations=len(OPS), formats=len(FORMATS), fixtures=len(cases),
                 negative_controls=sum((op, fmt) in UNSUPPORTED for _, op, fmt in planned),
                 domain_refusals=sum(a is not None and b is None for a, b in zip(native_rows, expected)),
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(json.dumps(expected).encode()).hexdigest())


if __name__ == '__main__':
    main()
