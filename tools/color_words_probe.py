#!/usr/bin/env python3
"""Compare packed color words, GenImageColor bytes and short quadratic splines.

ColorIsEqual, ColorAlpha, Fade, ColorTint, ColorBrightness, ColorContrast,
ColorLerp, ColorAlphaBlend, ColorToInt, GetColor, ColorNormalize, ColorToHSV
and GenImageColor are bit-exact. UnloadFileData, UnloadFileText,
UnloadDirectoryFiles, UnloadImagePalette and UnloadRandomSequence run on the
values they free. DrawSplineBezierQuadratic with fewer than three points leaves
the cleared frame unchanged, as raylib does. CPU-1, CPU-2 and JavaScript.
"""
import probekit

COLORS = (
    0x00000000, 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF,
    0x11223344, 0xFFFFFFFF, 0x01020304, 0x80808080, 0x7F000001,
)
FACTORS = (0.0, 0.5, 1.0, -1.0, 2.0)
PAIRS = ((0x11223344, 0x11223344), (0x11223344, 0x11223345), (0x00000000, 0xFFFFFFFF))


def channels(word):
    return (word >> 24) & 255, (word >> 16) & 255, (word >> 8) & 255, word & 255


def c_color(word):
    r, g, b, a = channels(word)
    return f'(Color){{{r},{g},{b},{a}}}'


def f32_bend(value):
    if value < 0:
        return f'F32.neg({abs(value):.1f})'
    return f'{value:.1f}'


def native():
    lines = [
        '#include "raylib.h"', '#include "rlgl.h"', '#include <stdio.h>', '#include <string.h>',
        'static unsigned pack(Color c){return ((unsigned)c.r<<24)|((unsigned)c.g<<16)|((unsigned)c.b<<8)|c.a;}',
        'static unsigned bits(float x){unsigned u; memcpy(&u,&x,4); return u;}',
        'static unsigned fb(void){unsigned char p[8*8*4]; rlCopyFramebuffer(0,0,8,8,PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,p);',
        '  unsigned h=2166136261u; for(int i=0;i<8*8*4;i++){h^=p[i]; h*=16777619u;} return h;}',
        'int main(void){SetTraceLogLevel(LOG_NONE);',
    ]
    for left, right in PAIRS:
        lines.append(f'printf("eq %d\\n", ColorIsEqual({c_color(left)}, {c_color(right)}));')
    for word in COLORS:
        lines.append(f'printf("int %u\\n", (unsigned)ColorToInt({c_color(word)}));')
        lines.append(f'printf("get %u\\n", pack(GetColor((int){word}u)));')
        lines.append(
            'printf("norm %u %u %u %u\\n", '
            f'bits(ColorNormalize({c_color(word)}).x), bits(ColorNormalize({c_color(word)}).y), '
            f'bits(ColorNormalize({c_color(word)}).z), bits(ColorNormalize({c_color(word)}).w));')
        lines.append(
            'printf("hsv %u %u %u\\n", '
            f'bits(ColorToHSV({c_color(word)}).x), bits(ColorToHSV({c_color(word)}).y), bits(ColorToHSV({c_color(word)}).z));')
        for factor in FACTORS:
            lines.append(f'printf("alpha %u\\n", pack(ColorAlpha({c_color(word)}, {factor}f)));')
            lines.append(f'printf("fade %u\\n", pack(Fade({c_color(word)}, {factor}f)));')
            lines.append(f'printf("bright %u\\n", pack(ColorBrightness({c_color(word)}, {factor}f)));')
            lines.append(f'printf("contrast %u\\n", pack(ColorContrast({c_color(word)}, {factor}f)));')
            lines.append(f'printf("lerp %u\\n", pack(ColorLerp({c_color(word)}, {c_color(0xFFFFFFFF)}, {factor}f)));')
        lines.append(f'printf("tint %u\\n", pack(ColorTint({c_color(word)}, {c_color(0x80808080)})));')
        lines.append(
            f'printf("blend %u\\n", pack(ColorAlphaBlend({c_color(word)}, {c_color(0xFF000080)}, {c_color(0xFFFFFFFF)})));')
        lines.append(
            f'{{Image im=GenImageColor(2,1,{c_color(word)}); unsigned char *p=im.data; '
            'printf("image"); for(int i=0;i<8;i++) printf(" %u", p[i]); printf("\\n"); UnloadImage(im);}')
    lines += [
        '{unsigned char *bytes=MemAlloc(4); bytes[0]=1; bytes[1]=2; bytes[2]=3; bytes[3]=4; UnloadFileData(bytes); printf("data 1\\n");}',
        '{char *text=MemAlloc(3); memcpy(text,"hi",3); UnloadFileText(text); printf("text 1\\n");}',
        '{FilePathList files={0}; UnloadDirectoryFiles(files); printf("dir 1\\n");}',
        '{Image im=GenImageColor(2,2,(Color){1,2,3,4}); int n=0; Color *pal=LoadImagePalette(im,8,&n);',
        ' printf("palette %d %u\\n", n, n?pack(pal[0]):0u); UnloadImagePalette(pal); UnloadImage(im);}',
        'SetRandomSeed(1); {int *seq=LoadRandomSequence(3,0,5); printf("seq");',
        ' for(int i=0;i<3;i++) printf(" %d", seq[i]); printf("\\n"); UnloadRandomSequence(seq);}',
        'InitWindow(8,8,"spline");',
        'BeginDrawing(); ClearBackground(RAYWHITE); EndDrawing(); unsigned plain=fb();',
        'Vector2 none[1]={{0,0}};',
        'BeginDrawing(); ClearBackground(RAYWHITE); DrawSplineBezierQuadratic(none,0,2.0f,RED); EndDrawing();',
        'printf("quad0 %d\\n", fb()==plain);',
        'BeginDrawing(); ClearBackground(RAYWHITE); DrawSplineBezierQuadratic(none,1,2.0f,RED); EndDrawing();',
        'printf("quad1 %d\\n", fb()==plain);',
        'Vector2 two[2]={{1,1},{4,4}};',
        'BeginDrawing(); ClearBackground(RAYWHITE); DrawSplineBezierQuadratic(two,2,2.0f,RED); EndDrawing();',
        'printf("quad2 %d\\n", fb()==plain);',
        'for(int n=0;n<4;n++){BeginDrawing(); ClearBackground(RAYWHITE); DrawSplineBasis(two,n,2.0f,RED); EndDrawing();',
        ' printf("basis%d %d\\n", n, fb()==plain);}',
        'for(int n=0;n<4;n++){BeginDrawing(); ClearBackground(RAYWHITE); DrawSplineCatmullRom(two,n,2.0f,RED); EndDrawing();',
        ' printf("cat%d %d\\n", n, fb()==plain);}',
        'CloseWindow(); return 0;}',
    ]
    return '\n'.join(lines) + '\n'


def bend_factor(value):
    return f32_bend(value)


HEADER = r'''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def flag(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"
def bits(+value: F32) -> String:
  U32.show(F32.bits(value))
def v4(value: M.Vector4) -> String:
  M.Vector4{+x, +y, +z, +w} = value
  bits(x) ++ " " ++ bits(y) ++ " " ++ bits(z) ++ " " ++ bits(w)
def v3(value: M.Vector3) -> String:
  M.Vector3{+x, +y, +z} = value
  bits(x) ++ " " ++ bits(y) ++ " " ++ bits(z)
def bytes(values: List<U32>) -> String:
  match values:
    case Nil{}: ""
    case Con{head, rest}: " " ++ U32.show(head) ++ bytes(rest)
def image_bytes(data: (U32 & U32) & (U32 & List<U32>)) -> String:
  ((_, _), (_, values)) = data
  "image" ++ bytes(values)
def image_of(found: Maybe<J.Surface>) -> String:
  match found:
    case None{}: "image none"
    case Some{image}: image_bytes(J.Surface.export(image))
def released_data() -> Unit:
  J.Files.unload_data([1, 2, 3, 4])
def released_text() -> Unit:
  J.Files.unload_text("hi")
def released_directory() -> Unit:
  J.Files.unload_directory_files(J.FilePathList{0, Nil{}})
def palette_drop(colors: +List<U32>, +text: String) -> String:
  text
def palette_text(colors: +List<U32>) -> String:
  match colors:
    case Con{head, rest}: palette_drop(rest, " " ++ U32.show(head))
    case Nil{}: " 0"
def palette_shown(pair: U32 & +List<U32>) -> String:
  (count, colors) = pair
  "palette " ++ U32.show(count) ++ palette_text(colors)
def palette_entries(palette: J.Image.Palette) -> String:
  palette_shown(J.Image.Palette.entries(palette))
def palette_after(done: Unit, found: Maybe<J.Image.Palette>) -> String:
  match found:
    case None{}: "palette 0 0"
    case Some{palette}: palette_entries(palette)
def palette_of(pair: J.Surface & Maybe<J.Image.Palette>) -> String:
  (surface, found) = pair
  palette_after(J.Surface.unload(surface), found)
def palette_created(found: Maybe<J.Surface>) -> String:
  match found:
    case None{}: "palette 0 0"
    case Some{image}: palette_of(J.Surface.load_palette(image, 8))
def released_palette(found: Maybe<J.Image.Palette>) -> Unit:
  match found:
    case None{}: Unit{}
    case Some{palette}: J.Image.Palette.unload(palette)
def released_after(done: Unit, found: Maybe<J.Image.Palette>) -> Unit:
  released_palette(found)
def released_palette_of(pair: J.Surface & Maybe<J.Image.Palette>) -> Unit:
  (surface, found) = pair
  released_after(J.Surface.unload(surface), found)
def released_palette_created(found: Maybe<J.Surface>) -> Unit:
  match found:
    case None{}: Unit{}
    case Some{image}: released_palette_of(J.Surface.load_palette(image, 8))
def sequence_text(values: +List<F32>) -> String:
  match values:
    case Nil{}: ""
    case Con{+head, rest}: " " ++ U32.show(F32.to_u32(head)) ++ sequence_text(rest)
def sequence_done(result: Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> String:
  match result:
    case Fail{_}: "seq fail"
    case Done{sequence}: sequence_text(J.Random.Sequence.values(sequence))
def sequence_of(pair: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> String:
  (_, result) = pair
  sequence_done(result)
def released_sequence(result: Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> Unit:
  match result:
    case Fail{_}: Unit{}
    case Done{sequence}: J.Random.unload_sequence(sequence)
def released_sequence_of(pair: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> Unit:
  (_, result) = pair
  released_sequence(result)
def hash_bytes(values: List<U32>, +h: U32) -> U32:
  match values:
    case Nil{}: h
    case Con{+head, rest}: hash_bytes(rest, (U32.xor(h, head) * 16777619 : U32))
def hash_image(data: (U32 & U32) & (U32 & List<U32>)) -> U32:
  ((_, _), (_, values)) = data
  hash_bytes(values, 2166136261)
def hash_frame(pair: J.Frame & Maybe<J.Surface>) -> J.Frame & U32:
  (frame, found) = pair
  match found:
    case None{}: (frame, 0)
    case Some{image}: (frame, hash_image(J.Surface.export(image)))
def cleared(frame: J.Frame) -> J.Frame & U32:
  hash_frame(J.Frame.framebuffer(J.Frame.end_drawing(J.Frame.clear_background(J.Frame.begin_drawing(frame), 4294967295))))
def points_n(n: Nat) -> +List<M.Vector2>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{M.Vector2{1.0, 4.0}, points_n(k)}
def drawn(kind: U32, frame: J.Frame, points: +List<M.Vector2>) -> J.Frame & U32:
  match kind:
    case 1: hash_frame(J.Frame.framebuffer(J.Frame.end_drawing(J.Draw.spline_basis(J.Frame.clear_background(J.Frame.begin_drawing(frame), 4294967295), points, 2.0, 4294901760))))
    case 2: hash_frame(J.Frame.framebuffer(J.Frame.end_drawing(J.Draw.spline_catmull_rom(J.Frame.clear_background(J.Frame.begin_drawing(frame), 4294967295), points, 2.0, 4294901760))))
    case _: hash_frame(J.Frame.framebuffer(J.Frame.end_drawing(J.Draw.spline_bezier_quadratic(J.Frame.clear_background(J.Frame.begin_drawing(frame), 4294967295), points, 2.0, 4294901760))))
def quad_flag(pair: J.Frame & U32, +plain: U32) -> J.Frame & String:
  (frame, +hash) = pair
  (frame, flag(U32.is_eq(hash, plain)))
def short_join(pair: J.Frame & String, +acc: String, +label: String, +count: Nat) -> J.Frame & String:
  (frame, bit) = pair
  (frame, acc ++ label ++ U32.show(U32.from_nat(count)) ++ " " ++ bit ++ "\n")
def then_text(done: Unit, +text: String) -> String:
  text
def short_close(frame: J.Frame, +text: String) -> String:
  then_text(J.Frame.close_window(frame), text)
def short_close_pair(pair: J.Frame & String) -> String:
  (frame, acc) = pair
  short_close(frame, acc)
def short_draw_join(+count: Nat, +kind: U32, +label: String, pair: J.Frame & String, +plain: U32) -> J.Frame & String:
  (frame, acc) = pair
  short_join(quad_flag(drawn(kind, frame, points_n(count)), plain), acc, label, count)
def short_step(+left: Nat, +count: Nat, +kind: U32, +label: String, pair: J.Frame & String, +plain: U32) -> String:
  match left:
    case 0n: short_close_pair(pair)
    case 1n+rest: short_step(rest, (1n + count : Nat), kind, label, short_draw_join(count, kind, label, pair, plain), plain)
def short_run(kind: U32, +label: String, +limit: Nat, pair: J.Frame & U32) -> String:
  (frame, +plain) = pair
  short_step(limit, 0n, kind, label, (frame, ""), plain)
def spline_lines(kind: U32, +label: String, +limit: Nat, opened: Maybe<J.Frame>) -> String:
  match opened:
    case None{}: label ++ " missing"
    case Some{frame}: short_run(kind, label, limit, cleared(frame))
'''


def program():
    body = [HEADER, 'def main() -> IO(Unit):', '  do IO<Unit>:']
    for left, right in PAIRS:
        body.append(f'    IO.print("eq " ++ flag(J.Color.is_equal({left}, {right})))')
    for word in COLORS:
        body.append(f'    IO.print("int " ++ U32.show(J.Color.rgba(J.Color.red({word}), J.Color.green({word}), J.Color.blue({word}), J.Color.alpha({word}))))')
        body.append(f'    IO.print("get " ++ U32.show({word}))')
        body.append(f'    IO.print("norm " ++ v4(J.Color.normalize({word})))')
        body.append(f'    IO.print("hsv " ++ v3(J.Color.to_hsv({word})))')
        for factor in FACTORS:
            f = bend_factor(factor)
            body.append(f'    IO.print("alpha " ++ U32.show(J.Color.with_alpha({word}, {f})))')
            body.append(f'    IO.print("fade " ++ U32.show(J.Color.with_alpha({word}, {f})))')
            body.append(f'    IO.print("bright " ++ U32.show(J.Color.brightness({word}, {f})))')
            body.append(f'    IO.print("contrast " ++ U32.show(J.Color.contrast({word}, {f})))')
            body.append(f'    IO.print("lerp " ++ U32.show(J.Color.lerp({word}, 4294967295, {f})))')
        body.append(f'    IO.print("tint " ++ U32.show(J.Color.multiply({word}, 2155905152)))')
        body.append(f'    IO.print("blend " ++ U32.show(J.Color.alpha_blend({word}, 4278190208, 4294967295)))')
        body.append(f'    IO.print(image_of(J.Surface.create(2, 1, {word})))')
    body += [
        '    Unit <- IO.pure(Unit, released_data())',
        '    IO.print("data 1")',
        '    Unit <- IO.pure(Unit, released_text())',
        '    IO.print("text 1")',
        '    Unit <- IO.pure(Unit, released_directory())',
        '    IO.print("dir 1")',
        '    IO.print(palette_created(J.Surface.create(2, 2, 16909060)))',
        '    Unit <- IO.pure(Unit, released_palette_created(J.Surface.create(2, 2, 16909060)))',
        '    IO.print("seq" ++ sequence_of(J.Random.load_sequence(J.Random.seed(1), 3, 0.0, 5.0, 4096n)))',
        '    Unit <- IO.pure(Unit, released_sequence_of(J.Random.load_sequence(J.Random.seed(1), 3, 0.0, 5.0, 4096n)))',
        '    IO.print(spline_lines(0, "quad", 3n, J.Frame.init_window(8, 8)))',
        '    IO.print(spline_lines(1, "basis", 4n, J.Frame.init_window(8, 8)))',
        '    IO.print(spline_lines(2, "cat", 4n, J.Frame.init_window(8, 8)))',
    ]
    return '\n'.join(body) + '\n'


def kept(text):
    return [line for line in text.splitlines() if line and not line.startswith('INFO:')]


def main():
    probe = probekit.Probe('color-words', probekit.arguments(__doc__))
    expected = kept(probe.native(native()))
    lanes = probe.candidates(lambda selected, gpu: program(), ['colors'], batch=1,
                             parse=lambda text, selected: ['\n'.join(kept(text))])
    probe.compare(['\n'.join(expected)], lanes, describe=lambda index: 'color words')
    probe.finish(lines=len(expected))


if __name__ == '__main__':
    main()
