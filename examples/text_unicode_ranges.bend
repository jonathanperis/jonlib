# raylib [text] example - unicode ranges, ported to Jonlib.
# Adapted from raylib 6.2 examples/text/text_unicode_ranges.c (zlib/libpng,
# Copyright (c) 2025 Vadim Gunko (@GuvaCode) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# Six greetings in a font generated from Noto Sans TC (7 MiB, 20812 glyphs)
# with the 95 ASCII glyphs LoadFont takes, beside the font's atlas. The keys
# 1 to 4 load more of Unicode: the font is loaded again and each range of
# the choice is added by loading it once more with the glyphs it has and
# the range's codepoints (the example's AddCodepointRange), so the first
# choice, two ranges, loads the file three times; the font it ends with has
# 212 glyphs, those of the 495 codepoints asked that Noto Sans TC has. The
# codepoints a font lacks are drawn as its '?'.
#
# The font is loaded inside the loop, so the program is a J.Effects one
# (docs/DRIVER.md). A frame is refused where the font does not load or
# Jonlib refuses it (docs/FONTS.md). The texts are their UTF-8 bytes.
# Loads resources/NotoSansTC-Regular.ttf from raylib's examples/text
# directory: run from that directory, or pass `--resources <dir/>`.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../src/fonts.bend as FontCore

# valid: the font is loaded. range and previous are unicodeRange and
# prevUnicodeRange.
type State is Type:
  State{valid: Bool, dir: String, font: Maybe<J.Font>, range: U32, previous: U32}

def file(+dir: String) -> String:
  dir ++ "resources/NotoSansTC-Regular.ttf"

# The ranges a choice adds, a first and a last codepoint each, in the order
# the example's switch falls through them: the choice's own, then those of
# the choices below it.
def ranges(range: U32) -> +List<U32>:
  match range:
    case 4: [19968, 40959, 13312, 19903, 12288, 12351, 12352, 12447, 12448, 12543, 12784, 12799, 65280, 65519, 44032, 55215, 4352, 4607, 1024, 1279, 1280, 1327, 11744, 11775, 42560, 42655, 880, 1023, 7936, 8191,
      192, 383, 384, 591]
    case 3: [1024, 1279, 1280, 1327, 11744, 11775, 42560, 42655, 880, 1023, 7936, 8191, 192, 383, 384, 591]
    case 2: [880, 1023, 7936, 8191, 192, 383, 384, 591]
    case 1: [192, 383, 384, 591]
    case _: Nil{}

def values(glyphs: +List<FontCore.Glyph>, acc: +List<U32>) -> +List<U32>:
  match glyphs:
    case Nil{}: acc
    case Con{FontCore.Glyph{+value, _, _, _, _, _, _, _}, +rest}: values(rest, Con{value, acc})

def counted(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: counted(rest, (n + 1 : U32))

# start, start + 1, ..., stop after the codepoints so far (the last first).
def extended(n: Nat, +at: U32, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k: extended(k, (at + 1 : U32), Con{at, acc})

# AddCodepointRange's codepoints: the font's glyphs' values and the range.
def codepoints(+glyphs: +List<FontCore.Glyph>, +start: U32, +stop: U32) -> +List<U32>:
  extended(U32.to_nat(((stop - start) + 1 : U32)), start, values(glyphs, Nil{}))

# The font a load gave, or none where it failed or was refused.
def loaded(r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> J.Frame & Maybe<J.Font>:
  match r:
    case Tuple{frame, Done{font}}: (frame, font)
    case Tuple{frame, Fail{_}}: (frame, None{})

# AddCodepointRange(&font, path, start, stop): UnloadFont, then LoadFontEx of
# the file at size 32 with the codepoints.
def added(+dir: String, +start: U32, +stop: U32, frame: J.Frame, font: J.Font) -> IO(J.Frame & Maybe<J.Font>):
  J.Font{+base, +padding, +glyphs, texture, atlas} = font
  +all = codepoints(glyphs, start, stop)
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Frame & Maybe<J.Font>,
    J.Font.load_ex(J.Font.unload(frame, J.Font{base, padding, glyphs, texture, atlas}), file(dir), 32, all, counted(all, 0)), r => IO.pure(J.Frame & Maybe<J.Font>, loaded(r)))

# The ranges added one after another; a font that did not load stays none.
def ranged(pairs: +List<U32>, +dir: String, r: J.Frame & Maybe<J.Font>) -> IO(J.Frame & Maybe<J.Font>):
  match pairs r:
    case Con{+start, Con{+stop, +rest}} Tuple{frame, Some{font}}:
      IO.bind(J.Frame & Maybe<J.Font>, J.Frame & Maybe<J.Font>, added(dir, start, stop, frame, font), next => ranged(rest, dir, next))
    case _ other: IO.pure(J.Frame & Maybe<J.Font>, other)

# UnloadFont(font).
def unloaded(frame: J.Frame, font: Maybe<J.Font>) -> J.Frame:
  match font:
    case None{}: frame
    case Some{f}: J.Font.unload(frame, f)

# if (IsKeyPressed(KEY_ZERO)) unicodeRange = 0; else if ... KEY_FOUR.
def chosen(+core: J.Core, +range: U32) -> U32:
  Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ZERO()), 0, Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ONE()), 1,
    Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_TWO()), 2, Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_THREE()), 3,
    Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_FOUR()), 4, range)))))

# SetTextureFilter(font.texture, TEXTURE_FILTER_BILINEAR), then the keys.
def update.font(font: Maybe<J.Font>, +core: J.Core, +dir: String, +range: U32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match font:
    case None{}: (core, (State{False{}, dir, None{}, chosen(core, range), range}, frame))
    case Some{f}: (core, (State{True{}, dir, Some{J.Font.set_filter(f, J.TextureFilter.TEXTURE_FILTER_BILINEAR())}, chosen(core, range), range}, frame))

def update.ranged(r: J.Frame & Maybe<J.Font>, +core: J.Core, +dir: String, +range: U32) -> IO(J.Core & (State & J.Frame)):
  (frame, font) = r
  IO.pure(J.Core & (State & J.Frame), update.font(font, core, dir, range, frame))

# if (unicodeRange != prevUnicodeRange): UnloadFont, LoadFont, the choice's
# ranges, prevUnicodeRange = unicodeRange and the filter.
def update.at(changed: Bool, +core: J.Core, +valid: Bool, +dir: String, +range: U32, +previous: U32, font: Maybe<J.Font>, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match changed:
    case False{}: IO.pure(J.Core & (State & J.Frame), (core, (State{valid, dir, font, chosen(core, range), previous}, frame)))
    case True{}:
      IO.bind(J.Frame & Maybe<J.Font>, J.Core & (State & J.Frame),
        IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Frame & Maybe<J.Font>, J.Font.load(unloaded(frame, font), file(dir)), r => ranged(ranges(range), dir, loaded(r))),
        r => update.ranged(r, core, dir, range))

def update(+core: J.Core, state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  State{+valid, +dir, font, +range, +previous} = state
  update.at(U32.is_ne(range, previous), core, valid, dir, range, previous, font, frame)

def text(index: U32) -> String:
  match index:
    case 0: "> English: Hello World!"
    case 1: "> Espa\u{c3}\u{b1}ol: Hola mundo!"
    case 2: "> \u{ce}\u{95}\u{ce}\u{bb}\u{ce}\u{bb}\u{ce}\u{b7}\u{ce}\u{bd}\u{ce}\u{b9}\u{ce}\u{ba}\u{ce}\u{ac}: \u{ce}\u{93}\u{ce}\u{b5}\u{ce}\u{b9}\u{ce}\u{ac} \u{cf}\u{83}\u{ce}\u{bf}\u{cf}\u{85} \u{ce}\u{ba}\u{cf}\u{8c}\u{cf}\u{83}\u{ce}\u{bc}\u{ce}\u{b5}!"
    case 3: "> \u{d0}\u{a0}\u{d1}\u{83}\u{d1}\u{81}\u{d1}\u{81}\u{d0}\u{ba}\u{d0}\u{b8}\u{d0}\u{b9}: \u{d0}\u{9f}\u{d1}\u{80}\u{d0}\u{b8}\u{d0}\u{b2}\u{d0}\u{b5}\u{d1}\u{82} \u{d0}\u{bc}\u{d0}\u{b8}\u{d1}\u{80}!"
    case 4: "> \u{e4}\u{b8}\u{ad}\u{e6}\u{96}\u{87}: \u{e4}\u{bd}\u{a0}\u{e5}\u{a5}\u{bd}\u{e4}\u{b8}\u{96}\u{e7}\u{95}\u{8c}!"
    case _: "> \u{e6}\u{97}\u{a5}\u{e6}\u{9c}\u{ac}\u{e8}\u{aa}\u{9e}: \u{e3}\u{81}\u{93}\u{e3}\u{82}\u{93}\u{e3}\u{81}\u{ab}\u{e3}\u{81}\u{a1}\u{e3}\u{81}\u{af}\u{e4}\u{b8}\u{96}\u{e7}\u{95}\u{8c}!"

# DrawTextEx(font, text, (Vector2){ 50, y }, 32, spacing, DARKGRAY).
def line(r: J.Frame & J.Font, +index: U32, +y: F32, +spacing: F32) -> J.Frame & J.Font:
  (frame, font) = r
  J.Draw.text_ex(frame, font, text(index), M.Vector2{50.0, y}, 32.0, spacing, J.Color.DARKGRAY())

def label(value: Maybe<String>, frame: J.Frame, +y: F32, +color: U32) -> J.Frame:
  match value:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 20.0, y, 20.0, color)

def glyph.count(glyphs: +List<FontCore.Glyph>, +n: U32) -> U32:
  match glyphs:
    case Nil{}: n
    case Con{_, +rest}: glyph.count(rest, (n + 1 : U32))

# if (prevUnicodeRange != unicodeRange): the notice over the frame.
def notice(shown: Bool, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}:
      J.Draw.text(J.Draw.rectangle(J.Draw.rectangle(frame, 0.0, 0.0, 800.0, 450.0, 4294967244), 0.0, 125.0, 800.0, 200.0, J.Color.GRAY()), "GENERATING FONT ATLAS...", 120.0, 210.0, 40.0, J.Color.BLACK())

# The atlas scaled to 380 pixels wide over black, its frame, the two counts
# and the credit. Fade(WHITE, 0.8f) is 0xFFFFFFCC.
def draw.atlas(r: J.Frame & J.Texture, +core: J.Core, +dir: String, +range: U32, +previous: U32, +base: U32, +padding: U32, +glyphs: +List<FontCore.Glyph>, atlas: J.Surface, +w: U32, +h: U32,
    +scale: F32) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = J.Draw.rectangle_lines(frame, 400.0, 16.0, 380.0, 380.0, J.Color.RED())
  f2 = label(J.Text.format("ATLAS SIZE: %ix%i px (x%02.2f)", [J.TextInt{w}, J.TextInt{h}, J.TextFloat{scale}]), f1, 380.0, J.Color.BLUE())
  f3 = label(J.Text.format("CODEPOINTS GLYPHS LOADED: %i", [J.TextInt{glyph.count(glyphs, 0)}]), f2, 410.0, J.Color.LIME())
  f4 = J.Draw.text(f3, "Font: Noto Sans TC. License: SIL Open Font License 1.1", 500.0, 430.0, 10.0, J.Color.GRAY())
  (core, (State{True{}, dir, Some{J.Font{base, padding, glyphs, texture, atlas}}, range, previous}, notice(U32.is_ne(previous, range), f4)))

def draw.lines(r: J.Frame & J.Font, +core: J.Core, +dir: String, +range: U32, +previous: U32) -> J.Core & (State & J.Frame):
  (frame, font) = r
  J.Font{+base, +padding, +glyphs, J.Texture{+id, +w, +h, +format, +linear, +alpha, texels}, atlas} = font
  +scale = (380.0 / U32.to_f32(w) : F32)
  draw.atlas(J.Draw.texture_pro(J.Draw.rectangle_rec(frame, J.Rectangle{400.0, 16.0, (U32.to_f32(w) * scale : F32), (U32.to_f32(h) * scale : F32)}, J.Color.BLACK()),
    J.Texture{id, w, h, format, linear, alpha, texels}, J.Rectangle{0.0, 0.0, U32.to_f32(w), U32.to_f32(h)}, J.Rectangle{400.0, 16.0, (U32.to_f32(w) * scale : F32), (U32.to_f32(h) * scale : F32)},
    M.Vector2{0.0, 0.0}, 0.0, J.Color.WHITE()), core, dir, range, previous, base, padding, glyphs, atlas, w, h, scale)

def draw.font(font: Maybe<J.Font>, +core: J.Core, +dir: String, +range: U32, +previous: U32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match font:
    case None{}: (core, (State{False{}, dir, None{}, range, previous}, J.Frame.refuse(frame)))
    case Some{f}:
      draw.lines(line(line(line(line(line(line((J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "ADD CODEPOINTS: [1][2][3][4]", 20.0, 20.0, 20.0, J.Color.MAROON()), f),
        0, 70.0, 1.0), 1, 120.0, 1.0), 2, 170.0, 1.0), 3, 220.0, 0.0), 4, 270.0, 1.0), 5, 320.0, 1.0), core, dir, range, previous)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{_, +dir, font, +range, +previous} = state
  draw.font(font, core, dir, range, previous, frame)

# Nothing in the loop follows the libm profile; nothing follows EndDrawing.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Effects{core => state => frame => update(core, state, frame), core => state => frame => draw(core, state, frame),
    core => state => frame => IO.pure(J.Core & (State & J.Frame), (core, (state, frame)))}

def setup.font(font: Maybe<J.Font>, +dir: String) -> State:
  match font:
    case None{}: State{False{}, dir, None{}, 0, 0}
    case Some{f}: State{True{}, dir, Some{J.Font.set_filter(f, J.TextureFilter.TEXTURE_FILTER_BILINEAR())}, 0, 0}

def setup.loaded(r: J.Frame & Maybe<J.Font>, +dir: String, +core: J.Core) -> J.Core & (J.Frame & State):
  (frame, font) = r
  (J.Core.set_target_fps(core, 60), (frame, setup.font(font, dir)))

# After InitWindow(800, 450): LoadFont("resources/NotoSansTC-Regular.ttf"),
# SetTextureFilter(font.texture, TEXTURE_FILTER_BILINEAR), SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load(frame, file(dir)), r => IO.pure(J.Core & (J.Frame & State), setup.loaded(loaded(r), dir, core)))

# "--resources DIR/" (default: the working directory) and "--frames N".
def options(args: List<String>, +mode: U32, dir: String, +frames: U32) -> String & U32:
  match args:
    case Nil{}: (dir, frames)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames)
        case 2: options(rest, 0, dir, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--resources"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, 0)), dir, frames)

def run.with(parsed: String & U32) -> IO(Unit):
  (+dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - unicode ranges", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
