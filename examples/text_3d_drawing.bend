# raylib [text] example - 3d drawing, ported to Jonlib.
# Adapted from raylib 6.2 examples/text/text_3d_drawing.c (zlib/libpng,
# Copyright (c) 2021-2025 Vlad Adrian (@demizdor)); see LICENSES/raylib.txt.
#
# Text laid out on the ground of a 3D scene as textured quads, one a glyph
# (the example's DrawTextCodepoint3D, DrawText3D and DrawTextWave3D over
# rlgl): a line whose part between "~~" marks waves, in up to 32 layers,
# above a cube that takes random colors when clicked, with its options and
# its help also drawn in 3D. The font is the default one: no platform
# Jonlib runs on delivers dropped files, so the branch that loads a dropped
# font is left out, and the glyphs' metrics are taken once (a table by
# byte; a codepoint above 255 has no glyph in the default font and takes
# '?'). The example sets the font texture for each glyph and unsets it;
# here it is held once around the 3D texts, which draws the same (the
# boundary boxes between glyphs are lines, which rlsw does not texture).
# The loops walk the text by bytes as the example does, its "~" rule
# included (a lone "~" skips the next character's byte count). The probe's
# scripts carry keys, not characters: the typed characters are the one part
# no reference run reaches (GetCharPressed answers 0 there). The wave's
# sinf, rlRotatef's and UpdateCamera's sinf/cosf follow the libm profile
# (docs/SINCOSF.md) and the perspective needs its binary64 tan
# (docs/PERSPECTIVE.md). raylib seeds the generator from time(NULL) in
# InitWindow; here the seed is a setup argument.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A glyph of the font: offsetX, offsetY and advanceX (C ints as words) and its atlas rectangle.
type Metric is Data:
  Metric{ox: U32, oy: U32, advance: U32, x: F32, y: F32, w: F32, h: F32}

# The font's numbers: baseSize, glyphPadding, the texture's size and the metrics by byte.
type Face is Data:
  Face{base: F32, padding: F32, tw: F32, th: F32, table: +List<Metric>}

# The example's options: spin, multicolor, SHOW_LETTER_BOUNDRY, SHOW_TEXT_BOUNDRY, fontSize, fontSpacing,
# lineSpacing, the text, layers, layerDistance, time, the light and dark colors and the layers' colors.
type Opts is Data:
  Opts{spin: Bool, multicolor: Bool, letters: Bool, box: Bool, size: F32, spacing: F32, line: F32, text: String, layers: U32, distance: F32, time: F32, light: U32, dark: U32, multi: +List<U32>}

# valid: no refusal so far. font is GetFontDefault() for the measures; texture is the drawn font's, held by the
# frame while the 3D texts are drawn.
type State is Type:
  State{valid: Bool, camera: +Maybe<J.Camera3D>, rng: J.Random.State, face: Face, font: J.Font, texture: Maybe<J.Texture>, shader: J.Shader, opts: Opts}

# DrawTextWave3D's loop variables: textOffsetX, textOffsetY, wave and k.
type Pen is Data:
  Pen{x: F32, y: F32, wave: Bool, k: U32}

# MeasureTextWave3D's: tempLen, lenCounter, tempTextWidth, textWidth and textHeight.
type Tape is Data:
  Tape{longest: U32, counter: U32, widest: F32, width: F32, height: F32}

# A line of the 3D options or help: its text (ok: it was formatted), fontSize, fontSpacing, what pos.z moves by
# after it besides its height, and its color.
type Line is Data:
  Line{text: String, ok: Bool, size: F32, spacing: F32, gap: F32, color: U32}

def signed(+word: U32) -> F32:
  Bool.pick(F32, (word >= 2147483648 : U32), F32.neg(U32.to_f32((0 - word : U32))), U32.to_f32(word))

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def metric.first(list: +List<Metric>) -> Metric:
  match list:
    case Nil{}: Metric{0, 0, 0, 0.0, 0.0, 0.0, 0.0}
    case Con{+m, _}: m

# font.glyphs[GetGlyphIndex(font, codepoint)]: the table's entry, '?' above 255.
def metric(+face: Face, +code: U32) -> Metric:
  Face{_, _, _, _, +table} = face
  metric.first(List.drop(&2, Metric, table, U32.to_nat(Bool.pick(U32, (code > 255 : U32), 63, code))))

def em(+face: Face) -> F32:
  Face{+base, _, _, _, _} = face
  base

# The glyph's advance: advanceX*scale, or recs.width*scale when advanceX is 0.
def step(+m: Metric, +scale: F32) -> F32:
  Metric{_, _, +advance, _, _, +w, _} = m
  Bool.pick(F32, U32.is_eq(advance, 0), (w * scale : F32), (signed(advance) * scale : F32))

def boundary(show: Bool, frame: J.Frame, +x: F32, +y: F32, +z: F32, +width: F32, +height: F32) -> J.Frame:
  match show:
    case False{}: frame
    case True{}: J.Draw.cube_wires_v(frame, M.Vector3{(x + width / 2.0 : F32), y, (z + height / 2.0 : F32)}, M.Vector3{width, 0.25, height}, J.Color.VIOLET())

# The back face: its normal down and the quad wound the other way.
def quad.back(back: Bool, frame: J.Frame, +width: F32, +height: F32, +tx: F32, +ty: F32, +tw: F32, +th: F32) -> J.Frame:
  match back:
    case False{}: frame
    case True{}:
      b1 = J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(J.Rlgl.normal3f(frame, 0.0, F32.neg(1.0), 0.0), tx, ty), 0.0, 0.0, 0.0)
      b2 = J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(b1, tw, ty), (0.0 + width : F32), 0.0, 0.0)
      b3 = J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(b2, tw, th), (0.0 + width : F32), 0.0, (0.0 + height : F32))
      J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(b3, tx, th), 0.0, 0.0, (0.0 + height : F32))

# The quad's vertices: the front face, and the back face when asked.
def quad(+back: Bool, frame: J.Frame, +width: F32, +height: F32, +tx: F32, +ty: F32, +tw: F32, +th: F32) -> J.Frame:
  f1 = J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(J.Rlgl.normal3f(frame, 0.0, 1.0, 0.0), tx, ty), 0.0, 0.0, 0.0)
  f2 = J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(f1, tx, th), 0.0, 0.0, (0.0 + height : F32))
  f3 = J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(f2, tw, th), (0.0 + width : F32), 0.0, (0.0 + height : F32))
  quad.back(back, J.Rlgl.vertex3f(J.Rlgl.tex_coord2f(f3, tw, ty), (0.0 + width : F32), 0.0, 0.0), width, height, tx, ty, tw, th)

def limited(r: J.Frame & Bool) -> J.Frame:
  (frame, _) = r
  frame

# The glyph's quad: position moved by its offsets, the source rectangle with the padding around it.
def glyph.at(+m: Metric, +face: Face, +x: F32, +y: F32, +z: F32, +size: F32, +back: Bool, +letters: Bool, +tint: U32, frame: J.Frame) -> J.Frame:
  Metric{+ox, +oy, _, +rx, +ry, +rw, +rh} = m
  Face{+base, +padding, +tw, +th, _} = face
  +scale = (size / base : F32)
  +px = (x + (signed(ox) - padding) * scale : F32)
  +pz = (z + (signed(oy) - padding) * scale : F32)
  +width = ((rw + 2.0 * padding) * scale : F32)
  +height = ((rh + 2.0 * padding) * scale : F32)
  f1 = limited(J.Rlgl.check_render_batch_limit(boundary(letters, frame, px, y, pz, width, height), Bool.pick(F32, back, 8.0, 4.0)))
  f2 = J.Rlgl.color4ub(J.Rlgl.begin(J.Rlgl.translatef(J.Rlgl.push_matrix(f1), px, y, pz), 7), ((tint >> 24n) : U32), ((tint >> 16n) .&. 255 : U32), ((tint >> 8n) .&. 255 : U32), (tint .&. 255 : U32))
  J.Rlgl.pop_matrix(J.Rlgl.end(quad(back, f2, width, height, ((rx - padding) / tw : F32), ((ry - padding) / th : F32), (((rx - padding) + (rw + 2.0 * padding)) / tw : F32),
    (((ry - padding) + (rh + 2.0 * padding)) / th : F32))))

# DrawTextCodepoint3D(font, codepoint, position, fontSize, backface, tint) with the font texture held.
def glyph(+face: Face, +code: U32, +x: F32, +y: F32, +z: F32, +size: F32, +back: Bool, +letters: Bool, +tint: U32, frame: J.Frame) -> J.Frame:
  glyph.at(metric(face, code), face, x, y, z, size, back, letters, tint, frame)

def waved(value: Maybe<F32>, +range: F32) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+v}: Some{(v * range : F32)}

# sinf(time*speed - k*offset)*range.
def wave(+libm: M.Libm, +time: F32, +k: U32, +speed: F32) -> Maybe<F32>:
  waved(M.Libm.sin(libm, (time * speed - U32.to_f32(k) * 0.35 : F32)), 0.45)

# pos = position plus the wave on each axis, then the pen's offsets.
def drawn.waved(wx: Maybe<F32>, wy: Maybe<F32>, wz: Maybe<F32>, +face: Face, +code: U32, +x: F32, +y: F32, +z: F32, +ox: F32, +oy: F32, +size: F32, +back: Bool, +letters: Bool, +tint: U32,
    frame: J.Frame) -> J.Frame:
  match wx wy wz:
    case Some{+a} Some{+b} Some{+c}: glyph(face, code, ((x + a) + ox : F32), (y + b : F32), ((z + c) + oy : F32), size, back, letters, tint, frame)
    case _ _ _: J.Frame.refuse(frame)

# A character: 0 draws nothing (a line feed, a "~", a space or a tab), 1 the glyph at the pen, 2 the glyph in the wave.
def drawn(kind: U32, +libm: M.Libm, +face: Face, +code: U32, +x: F32, +y: F32, +z: F32, +pen: Pen, +size: F32, +back: Bool, +letters: Bool, +tint: U32, +time: F32, frame: J.Frame) -> J.Frame:
  match kind:
    case 0: frame
    case 1:
      Pen{+ox, +oy, _, _} = pen
      glyph(face, code, (x + ox : F32), y, (z + oy : F32), size, back, letters, tint, frame)
    case _:
      Pen{+ox, +oy, _, +k} = pen
      drawn.waved(wave(libm, time, k, 3.0), wave(libm, time, k, 3.0), wave(libm, time, k, 0.5), face, code, x, y, z, ox, oy, size, back, letters, tint, frame)

def draw.kind(+pen: Pen, +code: U32) -> U32:
  Pen{_, _, +wave, _} = pen
  Bool.pick(U32, U32.is_eq(code, 10) || U32.is_eq(code, 126) || U32.is_eq(code, 32) || U32.is_eq(code, 9), 0, Bool.pick(U32, wave, 2, 1))

def remains(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{_, _}: True{}

# The bytes after this character: its byte count ('?' moves one byte); after "~~" two bytes; after a lone "~" the
# byte count GetCodepoint gave for the next byte.
def skipped(+rest: String, +code: U32, +count: U32, +after: U32, +ahead: U32) -> String:
  String.drop(rest, U32.to_nat(Bool.pick(U32, U32.is_eq(code, 126), Bool.pick(U32, U32.is_eq(after, 126), (ahead + 1 : U32), ahead), Bool.pick(U32, U32.is_eq(code, 63), 1, count))))

# The pen after a character: a line feed starts a line (k = 0, then ++k); "~~" toggles the wave; the others advance.
def penned(+pen: Pen, +code: U32, +after: U32, +advance: F32, +size: F32, +spacing: F32, +line: F32) -> Pen:
  Pen{+x, +y, +wave, +k} = pen
  Bool.pick(Pen, U32.is_eq(code, 10), Pen{0.0, (y + (size + line) : F32), wave, 1}, Bool.pick(Pen, U32.is_eq(code, 126), Pen{x, y, Bool.pick(Bool, U32.is_eq(after, 126), Bool.not(wave), wave), (k + 1 : U32)},
    Pen{(x + (advance + spacing) : F32), y, wave, (k + 1 : U32)}))

# DrawTextWave3D's loop over the bytes left: r is GetCodepoint there and n GetCodepoint one byte on.
def written(fuel: Nat, more: Bool, r: U32 & U32, n: U32 & U32, +rest: String, +libm: M.Libm, +face: Face, +x: F32, +y: F32, +z: F32, +size: F32, +spacing: F32, +line: F32, +back: Bool, +letters: Bool,
    +tint: U32, +time: F32, +pen: Pen, frame: J.Frame) -> J.Frame:
  match fuel more r n:
    case 0n _ _ _: frame
    case 1n+_ False{} _ _: frame
    case 1n+f True{} Tuple{+code, +count} Tuple{+after, +ahead}:
      +left = skipped(rest, code, count, after, ahead)
      written(f, remains(left), J.Codepoint.get(left), J.Codepoint.get(String.drop(left, 1n)), left, libm, face, x, y, z, size, spacing, line, back, letters, tint, time,
        penned(pen, code, after, step(metric(face, code), (size / em(face) : F32)), size, spacing, line), drawn(draw.kind(pen, code), libm, face, code, x, y, z, pen, size, back, letters, tint, time, frame))

# DrawTextWave3D(font, text, position, fontSize, fontSpacing, lineSpacing, backface, &wcfg, time, tint), and
# DrawText3D for a text without "~" (the same loop then).
def write(+libm: M.Libm, +face: Face, +text: String, +x: F32, +y: F32, +z: F32, +size: F32, +spacing: F32, +line: F32, +back: Bool, +letters: Bool, +tint: U32, +time: F32, frame: J.Frame) -> J.Frame:
  written(U32.to_nat((J.Text.length(text) + 1 : U32)), remains(text), J.Codepoint.get(text), J.Codepoint.get(String.drop(text, 1n)), text, libm, face, x, y, z, size, spacing, line, back, letters, tint, time,
    Pen{0.0, 0.0, False{}, 0}, frame)

# i += next - 1; a "~~" skips its second byte.
def measure.rest(+rest: String, +code: U32, +count: U32, +after: U32) -> String:
  String.drop(rest, U32.to_nat((Bool.pick(U32, U32.is_eq(code, 63), 1, count) + Bool.pick(U32, U32.is_eq(code, 126) && U32.is_eq(after, 126), 1, 0) : U32)))

# A line feed closes the line; "~~" counts nothing; another character counts its advanceX, or recs.width + offsetX.
def measure.next(+tape: Tape, +code: U32, +after: U32, +m: Metric, +scale: F32, +size: F32, +line: F32) -> Tape:
  Tape{+longest, +counter, +widest, +width, +height} = tape
  Metric{+ox, _, +advance, _, _, +w, _} = m
  +wider = (width + Bool.pick(F32, U32.is_ne(advance, 0), (signed(advance) * scale : F32), ((w + signed(ox)) * scale : F32)) : F32)
  Bool.pick(Tape, U32.is_eq(code, 10), Tape{longest, 0, Bool.pick(F32, (widest < width : F32), width, widest), 0.0, (height + (size + line) : F32)},
    Bool.pick(Tape, U32.is_eq(code, 126) && U32.is_eq(after, 126), tape, Tape{Bool.pick(U32, (longest < (counter + 1) : U32), (counter + 1 : U32), longest), (counter + 1 : U32), widest, wider, height}))

# MeasureTextWave3D's loop, over the bytes left as in written.
def measured(fuel: Nat, more: Bool, r: U32 & U32, n: U32 & U32, +rest: String, +face: Face, +size: F32, +line: F32, +tape: Tape) -> Tape:
  match fuel more r n:
    case 0n _ _ _: tape
    case 1n+_ False{} _ _: tape
    case 1n+f True{} Tuple{+code, +count} Tuple{+after, _}:
      +left = measure.rest(rest, code, count, after)
      measured(f, remains(left), J.Codepoint.get(left), J.Codepoint.get(String.drop(left, 1n)), left, face, size, line, measure.next(tape, code, after, metric(face, code), (size / em(face) : F32), size, line))

def box.of(+tape: Tape, +spacing: F32) -> M.Vector3:
  Tape{+longest, _, +widest, +width, +height} = tape
  M.Vector3{(Bool.pick(F32, (widest < width : F32), width, widest) + (signed((longest - 1 : U32)) * spacing) : F32), 0.25, height}

# tbox = MeasureTextWave3D(font, text, fontSize, fontSpacing, lineSpacing): textHeight starts at the scale.
def box(+face: Face, +text: String, +size: F32, +spacing: F32, +line: F32) -> M.Vector3:
  box.of(measured(U32.to_nat((J.Text.length(text) + 1 : U32)), remains(text), J.Codepoint.get(text), J.Codepoint.get(String.drop(text, 1n)), text, face, size, line,
    Tape{0, 0, 0.0, 0.0, (size / em(face) : F32)}), spacing)

# fmodf((h + h*Phi), 360.0f) for h in 0..360: the sum is below 720.
def hue(+h: F32) -> F32:
  +turned = (h + h * 0.618033988749895 : F32)
  Bool.pick(F32, (turned >= 360.0 : F32), (turned - 360.0 : F32), turned)

# GenerateRandomColor(s, v) of GetRandomValue(0, 360).
def random.color(+s: F32, +v: F32, r: J.Random.State & F32) -> J.Random.State & U32:
  (rng, +h) = r
  (rng, J.Color.from_hsv(hue(h), s, v))

def multi.alpha(+color: U32, r: J.Random.State & F32) -> J.Random.State & U32:
  (rng, +a) = r
  (rng, ((color .&. 4294967040) .|. F32.to_u32(a) : U32))

def multi.color(r: J.Random.State & U32) -> J.Random.State & U32:
  (rng, +color) = r
  multi.alpha(color, J.Random.value(rng, 0.0, 255.0))

# multi[i] = GenerateRandomColor(0.5f, 0.8f); multi[i].a = GetRandomValue(0, 255).
def multi.one(rng: J.Random.State) -> J.Random.State & U32:
  multi.color(random.color(0.5, 0.8, J.Random.value(rng, 0.0, 360.0)))

def multi.fill(n: Nat, r: J.Random.State & U32, +acc: +List<U32>) -> J.Random.State & +List<U32>:
  match n r:
    case 0n Tuple{rng, +color}: (rng, List.reverse(&2, U32, Con{color, acc}))
    case 1n+k Tuple{rng, +color}: multi.fill(k, multi.one(rng), Con{color, acc})

def lit(+opts: Opts, r: J.Random.State & U32) -> J.Random.State & Opts:
  Opts{+spin, +multicolor, +letters, +box, +size, +spacing, +line, +text, +layers, +distance, +time, _, +dark, +multi} = opts
  (rng, +light) = r
  (rng, Opts{spin, multicolor, letters, box, size, spacing, line, text, layers, distance, time, light, dark, multi})

def darkened.with(+opts: Opts, r: J.Random.State & U32) -> J.Random.State & Opts:
  Opts{+spin, +multicolor, +letters, +box, +size, +spacing, +line, +text, +layers, +distance, +time, +light, _, +multi} = opts
  (rng, +dark) = r
  (rng, Opts{spin, multicolor, letters, box, size, spacing, line, text, layers, distance, time, light, dark, multi})

def darkened(r: J.Random.State & Opts) -> J.Random.State & Opts:
  (rng, +opts) = r
  darkened.with(opts, random.color(0.4, 0.58, J.Random.value(rng, 0.0, 360.0)))

# A click on the cube: light = GenerateRandomColor(0.5f, 0.78f); dark = GenerateRandomColor(0.4f, 0.58f).
def recolored(hit: Bool, +opts: Opts, rng: J.Random.State) -> J.Random.State & Opts:
  match hit:
    case False{}: (rng, opts)
    case True{}: darkened(lit(opts, random.color(0.5, 0.78, J.Random.value(rng, 0.0, 360.0))))

def refilled.with(+opts: Opts, r: J.Random.State & +List<U32>) -> J.Random.State & Opts:
  Opts{+spin, +multicolor, +letters, +box, +size, +spacing, +line, +text, +layers, +distance, +time, +light, +dark, _} = opts
  (rng, +multi) = r
  (rng, Opts{spin, multicolor, letters, box, size, spacing, line, text, layers, distance, time, light, dark, multi})

# TAB turning multicolor on fills the 32 colors.
def refilled(fill: Bool, r: J.Random.State & Opts) -> J.Random.State & Opts:
  match fill r:
    case False{} Tuple{rng, +opts}: (rng, opts)
    case True{} Tuple{rng, +opts}: refilled.with(opts, multi.fill(31n, multi.one(rng), Nil{}))

# The camera of a mode: orbital from (-10, 15, -10) when spinning, free from (10, 10, -10).
def start(+spin: Bool) -> J.Camera3D:
  J.Camera3D{Bool.pick(M.Vector3, spin, M.Vector3{F32.neg(10.0), 15.0, F32.neg(10.0)}, M.Vector3{10.0, 10.0, F32.neg(10.0)}), M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# UpdateCamera(&camera, camera_mode): CAMERA_ORBITAL (2) while spinning, CAMERA_FREE (1) otherwise.
def view.moved(camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +spin: Bool) -> Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: J.Camera.update_for(M.Uncontracted{}, libm, core, c, Bool.pick(U32, spin, 2, 1))

# F3 resets the camera for the mode it changes to.
def view.next(moved: Maybe<J.Camera3D>, +f3: Bool, +spin: Bool) -> +Maybe<J.Camera3D>:
  match moved:
    case None{}: None{}
    case Some{+c}: Some{Bool.pick(J.Camera3D, f3, start(spin), c)}

def view.some(camera: +Maybe<J.Camera3D>) -> Bool:
  match camera:
    case None{}: False{}
    case Some{_}: True{}

# The cube at (0, 1, 0) of size 2: its box from position -/+ size/2.
def cube() -> J.BoundingBox:
  J.BoundingBox{M.Vector3{(0.0 - 2.0 / 2.0 : F32), (1.0 - 2.0 / 2.0 : F32), (0.0 - 2.0 / 2.0 : F32)}, M.Vector3{(0.0 + 2.0 / 2.0 : F32), (1.0 + 2.0 / 2.0 : F32), (0.0 + 2.0 / 2.0 : F32)}}

def hit.of(collision: Maybe<J.RayCollision>) -> U32:
  match collision:
    case None{}: 2
    case Some{J.RayCollision{+hit, _, _, _}}: Bool.pick(U32, hit, 1, 0)

def hit.ray(ray: Maybe<J.Ray>, +libm: M.Libm) -> U32:
  match ray:
    case None{}: 2
    case Some{+r}: hit.of(J.Collision.ray_box_for(M.Uncontracted{}, libm, r, cube()))

# A left click: 1 when GetScreenToWorldRay(GetMousePosition(), camera) hits the cube, 2 when Jonlib refuses the ray.
def clicked(click: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core) -> U32:
  match click camera:
    case True{} Some{+c}: hit.ray(J.Camera.screen_to_world_ray_for(M.Uncontracted{}, libm, J.Input.get_mouse_position(core), c, core), libm)
    case _ _: 0

# The else-if chain of the text keys: LEFT 1, RIGHT 2, UP 3, DOWN 4, PAGE_UP 5, PAGE_DOWN 6, INSERT down 7, DELETE down 8, TAB 9.
def chain(+core: J.Core) -> U32:
  Bool.pick(U32, J.Input.is_key_pressed(core, 263), 1, Bool.pick(U32, J.Input.is_key_pressed(core, 262), 2, Bool.pick(U32, J.Input.is_key_pressed(core, 265), 3, Bool.pick(U32, J.Input.is_key_pressed(core, 264), 4,
    Bool.pick(U32, J.Input.is_key_pressed(core, 266), 5, Bool.pick(U32, J.Input.is_key_pressed(core, 267), 6, Bool.pick(U32, J.Input.is_key_down(core, 260), 7, Bool.pick(U32, J.Input.is_key_down(core, 261), 8,
    Bool.pick(U32, J.Input.is_key_pressed(core, 258), 9, 0)))))))))

# value -= amount for one key of the chain, += for the other.
def stepped(+value: F32, +keys: U32, +less: U32, +more: U32, +amount: F32) -> F32:
  Bool.pick(F32, U32.is_eq(keys, less), (value - amount : F32), Bool.pick(F32, U32.is_eq(keys, more), (value + amount : F32), value))

def toggled(+value: Bool, +flip: Bool) -> Bool:
  Bool.pick(Bool, flip, Bool.not(value), value)

def appended(ok: Bool, +text: String, +code: U32) -> String:
  match ok:
    case False{}: text
    case True{}: String.append(text, SCon{Char.from_u32(code), SNil{}})

# The text[64] buffer: BACKSPACE (0) removes the last byte, ENTER (1) appends a line feed, and otherwise (char)ch is
# written at the end, which changes nothing for a 0; the last two below 63 bytes only.
def typed(kind: U32, +text: String, +ch: U32) -> String:
  match kind:
    case 0: String.take(text, U32.to_nat(Bool.pick(U32, U32.is_eq(J.Text.length(text), 0), 0, (J.Text.length(text) - 1 : U32))))
    case 1: appended((J.Text.length(text) < 63 : U32), text, 10)
    case _: appended((J.Text.length(text) < 63 : U32) && U32.is_ne((ch .&. 255 : U32), 0), text, (ch .&. 255 : U32))

def update.done(+core: J.Core, +valid: Bool, +camera: +Maybe<J.Camera3D>, +face: Face, font: J.Font, texture: Maybe<J.Texture>, +shader: J.Shader, r: J.Random.State & Opts) -> J.Core & State:
  (rng, +opts) = r
  (core, State{valid, camera, rng, face, font, texture, shader, opts})

# The loop's update, after GetCharPressed (ch).
def update.typed(+libm: M.Libm, +valid: Bool, +camera: +Maybe<J.Camera3D>, rng: J.Random.State, +face: Face, font: J.Font, texture: Maybe<J.Texture>, +shader: J.Shader, +opts: Opts, r: J.Core & U32) -> J.Core & State:
  Opts{+spin, +multicolor, +letters, +box, +size, +spacing, +line, +text, +layers, +distance, +time, +light, +dark, +multi} = opts
  (+core, +ch) = r
  +f3 = J.Input.is_key_pressed(core, 292)
  +spun = toggled(spin, f3)
  +next = view.next(view.moved(camera, libm, core, spin), f3, spun)
  +hit = clicked(J.Input.is_mouse_button_pressed(core, 0), next, libm, core)
  +keys = chain(core)
  +colored = toggled(multicolor, U32.is_eq(keys, 9))
  +stacked = Bool.pick(U32, J.Input.is_key_pressed(core, 268), Bool.pick(U32, (layers > 1 : U32), (layers - 1 : U32), layers),
    Bool.pick(U32, J.Input.is_key_pressed(core, 269) && (layers < 32 : U32), (layers + 1 : U32), layers))
  +kind = Bool.pick(U32, J.Input.is_key_pressed(core, 259), 0, Bool.pick(U32, J.Input.is_key_pressed(core, 257), 1, 2))
  update.done(core, valid && view.some(next) && U32.is_ne(hit, 2), next, face, font, texture, shader, refilled(U32.is_eq(keys, 9) && colored, recolored(U32.is_eq(hit, 1),
    Opts{spun, colored, toggled(letters, J.Input.is_key_pressed(core, 290)), toggled(box, J.Input.is_key_pressed(core, 291)), stepped(size, keys, 1, 2, 0.5), stepped(spacing, keys, 3, 4, 0.1), stepped(line, keys, 5, 6, 0.1),
      typed(kind, text, ch), stacked, stepped(distance, keys, 7, 8, 0.001), (time + J.Core.get_frame_time(core) : F32), light, dark, multi}, rng)))

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +camera, rng, +face, font, texture, +shader, +opts} = state
  update.typed(libm, valid, camera, rng, face, font, texture, shader, opts, J.Input.get_char_pressed(core))

def opt(text: Maybe<String>, +color: U32) -> Line:
  match text:
    case None{}: Line{"", False{}, 0.8, 0.1, 0.5, color}
    case Some{t}: Line{t, True{}, 0.8, 0.1, 0.5, color}

def switch(+on: Bool) -> String:
  Bool.pick(String, on, "ON", "OFF")

# The 3D options: fontSize 0.8, fontSpacing 0.1, pos.z += 0.5 + m.y after each.
def options(+opts: Opts) -> +List<Line>:
  Opts{_, _, +letters, +box, +size, +spacing, +line, _, _, +distance, _, _, _, _} = opts
  [opt(J.Text.format("< SIZE: %2.1f >", [J.TextFloat{size}]), J.Color.BLUE()), opt(J.Text.format("< SPACING: %2.1f >", [J.TextFloat{spacing}]), J.Color.BLUE()),
    opt(J.Text.format("< LINE: %2.1f >", [J.TextFloat{line}]), J.Color.BLUE()), opt(J.Text.format("< LBOX: %3s >", [J.TextString{switch(letters)}]), J.Color.RED()),
    opt(J.Text.format("< TBOX: %3s >", [J.TextString{switch(box)}]), J.Color.RED()), opt(J.Text.format("< LAYER DISTANCE: %.3f >", [J.TextFloat{distance}]), J.Color.DARKPURPLE())]

def help(text: String) -> Line:
  Line{text, True{}, 0.6, 0.05, 0.5, J.Color.DARKBLUE()}

# The 3D info text: the first line at fontSize 1 (pos.z += 1.5 + m.y), the others at 0.6.
def info() -> +List<Line>:
  [Line{"All the text displayed here is in 3D", True{}, 1.0, 0.05, 1.5, J.Color.DARKBLUE()}, help("press [Left]/[Right] to change the font size"), help("press [Up]/[Down] to change the font spacing"),
    help("press [PgUp]/[PgDown] to change the line spacing"), help("press [F1] to toggle the letter boundry"), help("press [F2] to toggle the text boundry")]

# quads += TextLength(opt) over the options.
def lengths(list: +List<Line>) -> U32:
  match list:
    case Nil{}: 0
    case Con{Line{+text, _, _, _, _, _}, rest}: (J.Text.length(text) + lengths(rest) : U32)

# m = MeasureTextEx(GetFontDefault(), opt, fontSize, fontSpacing) of the first line.
def measure.head(list: +List<Line>, font: J.Font) -> J.Font & M.Vector2:
  match list:
    case Nil{}: (font, M.Vector2.zero())
    case Con{Line{+text, _, +size, +spacing, _, _}, _}: J.Font.measure_text_ex(font, text, size, spacing)

# DrawText3D of each line at pos = (-m.x/2, 0.01, z), z then moving by the line's gap + m.y; r is the measure of
# the first line.
def lines(list: +List<Line>, r: J.Font & M.Vector2, +libm: M.Libm, +face: Face, +z: F32, frame: J.Frame) -> J.Frame & J.Font:
  match list r:
    case Nil{} Tuple{font, _}: (frame, font)
    case Con{Line{+text, +ok, +size, +spacing, +gap, +color}, +rest} Tuple{font, M.Vector2{+mx, +my}}:
      lines(rest, measure.head(rest, font), libm, face, (z + (gap + my) : F32), write(libm, face, text, (F32.neg(mx) / 2.0 : F32), 0.01, z, size, spacing, 0.0, False{}, False{}, color, 0.0, checked(ok, frame)))

def lines.from(+list: +List<Line>, font: J.Font, +libm: M.Libm, +face: Face, frame: J.Frame) -> J.Frame & J.Font:
  lines(list, measure.head(list, font), libm, face, 2.0, frame)

# One layer: DrawTextWave3D(font, text, (-tbox.x/2, layerDistance*i, -4.5), fontSize, fontSpacing, lineSpacing, true, &wcfg, time, clr).
def layer(+libm: M.Libm, +face: Face, +opts: Opts, +x: F32, +i: U32, +color: U32, frame: J.Frame) -> J.Frame:
  Opts{_, _, +letters, _, +size, +spacing, +line, +text, _, +distance, +time, _, _, _} = opts
  write(libm, face, text, x, (distance * U32.to_f32(i) : F32), F32.neg(4.5), size, spacing, line, True{}, letters, color, time, frame)

# for (int i = 0; i < layers; i++): clr = light, or multi[i] in multicolor mode.
def layered(n: Nat, multi: +List<U32>, +i: U32, +libm: M.Libm, +face: Face, +opts: Opts, +x: F32, +multicolor: Bool, +light: U32, frame: J.Frame) -> J.Frame:
  match n multi:
    case 0n _: frame
    case 1n+k Nil{}: layered(k, Nil{}, (i + 1 : U32), libm, face, opts, x, multicolor, light, layer(libm, face, opts, x, i, light, frame))
    case 1n+k Con{+color, +rest}: layered(k, rest, (i + 1 : U32), libm, face, opts, x, multicolor, light, layer(libm, face, opts, x, i, Bool.pick(U32, multicolor, color, light), frame))

# if (SHOW_TEXT_BOUNDRY) DrawCubeWiresV((0, 0, -4.5 + tbox.z/2), tbox, dark).
def bounded(show: Bool, frame: J.Frame, +tbox: M.Vector3, +dark: U32) -> J.Frame:
  match show:
    case False{}: frame
    case True{}:
      M.Vector3{_, _, +bz} = tbox
      J.Draw.cube_wires_v(frame, M.Vector3{0.0, 0.0, (F32.neg(4.5) + bz / 2.0 : F32)}, tbox, dark)

# EndShaderMode() and EndMode3D(), the font texture taken back.
def scene.released(font: J.Font, r: J.Frame & Maybe<J.Texture>) -> J.Frame & (J.Font & Maybe<J.Texture>):
  (frame, texture) = r
  (J.Frame.end_mode_3d(J.Frame.end_shader_mode(frame)), (font, texture))

def scene.done(r: J.Frame & J.Font) -> J.Frame & (J.Font & Maybe<J.Texture>):
  (frame, font) = r
  scene.released(font, J.Rlgl.set_texture(frame, None{}))

# rlPopMatrix() after the options, then the info text.
def scene.info(+libm: M.Libm, +face: Face, r: J.Frame & J.Font) -> J.Frame & (J.Font & Maybe<J.Texture>):
  (frame, font) = r
  scene.done(lines.from(info(), font, libm, face, J.Rlgl.pop_matrix(frame)))

# The 3D text above the cube in its layers, its boundary, and the options turned 180 degrees about Y.
def scene.texts(+libm: M.Libm, +face: Face, +opts: Opts, +tbox: M.Vector3, font: J.Font, r: J.Frame & Maybe<J.Texture>) -> J.Frame & (J.Font & Maybe<J.Texture>):
  Opts{_, +multicolor, _, +box, _, _, _, _, +layers, _, _, +light, +dark, +multi} = opts
  M.Vector3{+bx, _, _} = tbox
  (frame, _) = r
  f1 = J.Rlgl.rotatef_for(libm, J.Rlgl.rotatef_for(libm, J.Rlgl.push_matrix(frame), 90.0, 1.0, 0.0, 0.0), 90.0, 0.0, 0.0, F32.neg(1.0))
  f2 = J.Rlgl.pop_matrix(bounded(box, layered(U32.to_nat(layers), multi, 0, libm, face, opts, (F32.neg(bx) / 2.0 : F32), multicolor, light, f1), tbox, dark))
  scene.info(libm, face, lines.from(options(opts), font, libm, face, J.Rlgl.rotatef_for(libm, J.Rlgl.push_matrix(f2), 180.0, 0.0, 1.0, 0.0)))

# BeginMode3D(camera): the cube, its wires and the grid, then the texts under BeginShaderMode(alphaDiscard).
def scene(+libm: M.Libm, +face: Face, +shader: J.Shader, +opts: Opts, +camera: J.Camera3D, frame: J.Frame, font: J.Font, texture: Maybe<J.Texture>) -> J.Frame & (J.Font & Maybe<J.Texture>):
  Opts{_, _, _, _, +size, +spacing, +line, +text, _, _, _, +light, +dark, _} = opts
  f1 = J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera)
  f2 = J.Draw.cube_wires(J.Draw.cube_v(f1, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{2.0, 2.0, 2.0}, dark), M.Vector3{0.0, 1.0, 0.0}, 2.1, 2.1, 2.1, light)
  scene.texts(libm, face, opts, box(face, text, size, spacing, line), font, J.Rlgl.set_texture(J.Frame.begin_shader_mode(J.Draw.grid(f2, 10.0, 2.0), shader), texture))

def right.at(width: Maybe<U32>, +text: String, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+w}: J.Draw.text(frame, text, signed((780 - w : U32)), y, 10.0, color)

# width = MeasureText(tmp, 10); DrawText(tmp, screenWidth - 20 - width, y, 10, color).
def right(+text: String, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  right.at(J.Font.measure_text(text, 10.0), text, y, color, frame)

def right.format(text: Maybe<String>, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{+t}: right(t, y, color, frame)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# The 2D info text and the stats: the quads of the options (their lengths), of the info text (248) and of the layers.
def state.of(rng: J.Random.State, +face: Face, +shader: J.Shader, +opts: Opts, +camera: J.Camera3D, held: J.Font & Maybe<J.Texture>) -> State:
  (font, texture) = held
  State{True{}, Some{camera}, rng, face, font, texture, shader, opts}

def draw.stats(+core: J.Core, rng: J.Random.State, +face: Face, +shader: J.Shader, +opts: Opts, +camera: J.Camera3D, r: J.Frame & (J.Font & Maybe<J.Texture>)) -> J.Core & (State & J.Frame):
  Opts{+spin, _, _, _, _, _, _, +text, +layers, _, _, _, _, _} = opts
  (frame, held) = r
  +quads = (lengths(options(opts)) + 248 + J.Text.length(text) * 2 * layers : U32)
  f1 = J.Draw.text(frame, "Drag & drop a font file to change the font!\nType something, see what happens!\n\nPress [F3] to toggle the camera", 10.0, 35.0, 10.0, J.Color.BLACK())
  f2 = right.format(J.Text.format("%2i layer(s) | %s camera | %4i quads (%4i verts)", [J.TextInt{layers}, J.TextString{Bool.pick(String, spin, "ORBITAL", "FREE")}, J.TextInt{quads}, J.TextInt{(quads * 4 : U32)}]), 10.0,
    J.Color.DARKGREEN(), f1)
  f3 = right("[Insert]/[Delete] to increase/decrease distance between layers", 40.0, J.Color.DARKGRAY(), right("[Home]/[End] to add/remove 3D text layers", 25.0, J.Color.DARKGRAY(), f2))
  f4 = right("[Tab] to toggle multicolor mode", 70.0, J.Color.DARKGRAY(), right("click the [CUBE] for a random color", 55.0, J.Color.DARKGRAY(), f3))
  draw.fps.done(state.of(rng, face, shader, opts, camera, held), f4, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.at(valid: Bool, camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, rng: J.Random.State, +face: Face, +shader: J.Shader, +opts: Opts, frame: J.Frame, font: J.Font, texture: Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  match valid camera:
    case True{} Some{+c}: draw.stats(core, rng, face, shader, opts, c, scene(libm, face, shader, opts, c, frame, font, texture))
    case _ _: (core, (State{False{}, None{}, rng, face, font, texture, shader, opts}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +camera, rng, +face, font, texture, +shader, +opts} = state
  draw.at(valid, camera, libm, core, rng, face, shader, opts, frame, font, texture)

# The main loop's body; libm is the profile of the wave's sinf, rlRotatef, UpdateCamera, the ray and the perspective tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def offsets(found: Maybe<J.GlyphInfo>) -> Metric:
  match found:
    case None{}: Metric{0, 0, 0, 0.0, 0.0, 0.0, 0.0}
    case Some{J.GlyphInfo{_, +ox, +oy, +advance, _}}: Metric{ox, oy, advance, 0.0, 0.0, 0.0, 0.0}

def metric.made(+m: Metric, r: J.Font & J.Rectangle) -> J.Font & Metric:
  Metric{+ox, +oy, +advance, _, _, _, _} = m
  (font, J.Rectangle{+x, +y, +w, +h}) = r
  (font, Metric{ox, oy, advance, x, y, w, h})

def metric.rec(+code: U32, r: J.Font & Maybe<J.GlyphInfo>) -> J.Font & Metric:
  (font, found) = r
  metric.made(offsets(found), J.Font.glyph_atlas_rec(font, code))

# glyphs[GetGlyphIndex(font, code)] and recs[GetGlyphIndex(font, code)].
def metric.of(+code: U32, font: J.Font) -> J.Font & Metric:
  metric.rec(code, J.Font.glyph_info(font, code))

# The metrics of the codes from `code` on; r is the first one's.
def table(n: Nat, r: J.Font & Metric, +code: U32, +acc: +List<Metric>) -> J.Font & +List<Metric>:
  match n r:
    case 0n Tuple{font, +m}: (font, List.reverse(&2, Metric, Con{m, acc}))
    case 1n+k Tuple{font, +m}: table(k, metric.of((code + 1 : U32), font), (code + 1 : U32), Con{m, acc})

# font = GetFontDefault(): its numbers and its texture; the options of the example's start.
def setup.made(+seed: U32, +core: J.Core, frame: J.Frame, r: J.Font & +List<Metric>) -> J.Core & (J.Frame & State):
  (font, +table) = r
  J.Font{+base, +padding, _, texture, _} = font
  J.Texture{+id, +width, +height, +format, +linear, +alpha, texels} = texture
  (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, State{True{}, Some{start(True{})}, J.Random.seed(seed), Face{signed(base), signed(padding), U32.to_f32(width), U32.to_f32(height), table}, J.Font.default(),
    Some{J.Texture{id, width, height, format, linear, alpha, texels}}, J.Shader.load(None{}, Some{"resources/shaders/glsl330/alpha_discard.fs"}),
    Opts{True{}, False{}, False{}, False{}, 0.8, 0.05, F32.neg(0.1), "Hello ~~World~~ in 3D!", 1, 0.01, 0.0, J.Color.MAROON(), J.Color.RED(), Nil{}}}))

# After SetConfigFlags(FLAG_MSAA_4X_HINT | FLAG_VSYNC_HINT), InitWindow(800, 450) and SetRandomSeed(seed): the
# orbital camera, the default font, LoadShader(NULL, alpha_discard.fs), DisableCursor(), SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.made(seed, core, frame, table(255n, metric.of(0, J.Font.default()), 0, Nil{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [text] example - 3d drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
