# raylib [text] example - inline styling, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_inline_styling.c (zlib/libpng,
# Copyright (c) 2025 Wagner Barongello (@SultansOfCode) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# The example's DrawTextStyled and MeasureTextStyled: [cRRGGBBAA] sets the
# foreground color, [bRRGGBBAA] the background and [r] resets them; the
# last text takes a random color every 20 frames. The texts are ASCII, so
# each byte is a codepoint; the default font's glyphs have no advanceX or
# offsetX, so a glyph's width is its atlas rectangle's. A color tag with
# more than 8 hex digits overflows the example's buffer and is refused,
# as is a measured text with a line feed or a '[' that opens no tag (the
# example's MeasureTextStyled never advances past either). raylib seeds
# GetRandomValue from time(NULL) in InitWindow; here the seed is a setup
# argument (docs/DRIVER.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# colRandom and frameCounter.
type State is Type:
  State{rng: J.Random.State, font: J.Font, color: U32, counter: U32}

# A character to draw with colFront and colBack.
type Styled is Data:
  Styled{code: U32, front: U32, back: U32}

# The parser: the bytes left, colFront, colBack, the characters so far (reversed); ok: no tag overflowed.
type Scan is Data:
  Scan{rest: +List<U32>, front: U32, back: U32, out: +List<Styled>, ok: Bool}

# textOffsetX and textOffsetY; for MeasureTextStyled, the glyph widths' sum and validCodepointCounter.
type Pen is Type:
  Pen{x: F32, y: F32, width: F32, count: U32, frame: J.Frame, font: J.Font}

def first(codes: +List<U32>) -> U32:
  match codes:
    case Nil{}: 0
    case Con{+code, _}: code

def digit(+code: U32) -> Bool:
  ((code >= 48 : U32) && (code <= 57 : U32)) || ((code >= 65 : U32) && (code <= 70 : U32)) || ((code >= 97 : U32) && (code <= 102 : U32))

def digit.value(+code: U32) -> U32:
  Bool.pick(U32, (code <= 57 : U32), (code - 48 : U32), Bool.pick(U32, (code <= 70 : U32), (code - 55 : U32), (code - 87 : U32)))

# The hex digits a tag starts with (strtoul of them) and their count.
def hex(codes: +List<U32>, +value: U32, +count: U32, +open: Bool) -> U32 & U32:
  match codes:
    case Nil{}: (value, count)
    case Con{+code, rest}:
      +more = open && digit(code)
      hex(rest, Bool.pick(U32, more, (value * 16 + digit.value(Bool.pick(U32, more, code, 48)) : U32), value), Bool.pick(U32, more, (count + 1 : U32), count), more)

# "[c" or "[b": the color, then the digits and one more byte (the ']') skipped.
def step.color(+front: U32, +back: U32, +out: +List<Styled>, +ok: Bool, +kind: U32, +after: +List<U32>, parsed: U32 & U32) -> Scan:
  (+value, +count) = parsed
  Scan{List.drop(&2, U32, after, U32.to_nat((count + 1 : U32))), Bool.pick(U32, U32.is_eq(kind, 99), value, front), Bool.pick(U32, U32.is_eq(kind, 98), value, back), out,
    ok && (count <= 8 : U32)}

def step.tag(color: Bool, +code: U32, +front: U32, +back: U32, +out: +List<Styled>, +ok: Bool, +tail: +List<U32>) -> Scan:
  match color:
    case False{}: Scan{tail, front, back, Con{Styled{code, front, back}, out}, ok}
    case True{}: step.color(front, back, out, ok, first(tail), List.drop(&2, U32, tail, 1n), hex(List.drop(&2, U32, tail, 1n), 0, 0, True{}))

# One pass of DrawTextStyled's loop: "[r]" resets the colors, "[c"/"[b" sets one, anything else is drawn.
def step.code(+base: U32, +code: U32, +tail: +List<U32>, +front: U32, +back: U32, +out: +List<Styled>, +ok: Bool) -> Scan:
  +open = U32.is_eq(code, 91)
  +kind = first(tail)
  +reset = open && U32.is_eq(kind, 114) && U32.is_eq(first(List.drop(&2, U32, tail, 1n)), 93)
  Bool.pick(Scan, reset, Scan{List.drop(&2, U32, tail, 2n), base, J.Color.BLANK(), out, ok},
    step.tag(open && Bool.not(reset) && (U32.is_eq(kind, 99) || U32.is_eq(kind, 98)), code, front, back, out, ok, tail))

def step.rest(rest: +List<U32>, +base: U32, +front: U32, +back: U32, +out: +List<Styled>, +ok: Bool) -> Scan:
  match rest:
    case Nil{}: Scan{Nil{}, front, back, out, ok}
    case Con{+code, +tail}: step.code(base, code, tail, front, back, out, ok)

def step(+base: U32, scan: Scan) -> Scan:
  Scan{+rest, +front, +back, +out, +ok} = scan
  step.rest(rest, base, front, back, out, ok)

# The whole text: a step per byte at most.
def styled(fuel: Nat, +base: U32, +scan: Scan) -> Scan:
  match fuel:
    case 0n: scan
    case 1n+p: styled(p, base, step(base, scan))

# if (colBack.a > 0) DrawRectangleRec({ x, y - backRecPadding, increaseX, fontSize + 2*backRecPadding }, colBack).
def backed(visible: Bool, frame: J.Frame, +x: F32, +y: F32, +width: F32, +size: F32, +back: U32) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.rectangle_rec(frame, J.Rectangle{x, (y - 4.0 : F32), width, (size + 2.0 * 4.0 : F32)}, back)

# if ((codepoint != ' ') && (codepoint != '\t')) DrawTextCodepoint(font, codepoint, (x, y), fontSize, colFront).
def inked(visible: Bool, frame: J.Frame, font: J.Font, +code: U32, +x: F32, +y: F32, +size: F32, +front: U32) -> J.Frame & J.Font:
  match visible:
    case False{}: (frame, font)
    case True{}: J.Draw.text_codepoint(frame, font, code, M.Vector2{x, y}, size, front)

def stroke.done(+x: F32, +y: F32, +width: F32, +count: U32, r: J.Frame & J.Font) -> Pen:
  (frame, font) = r
  Pen{x, y, width, count, frame, font}

# increaseX = recs[index].width*scaleFactor + spacing (2).
def stroke.glyph(+code: U32, +front: U32, +back: U32, +px: F32, +py: F32, +size: F32, +x: F32, +y: F32, +width: F32, +count: U32, frame: J.Frame, r: J.Font & J.Rectangle) -> Pen:
  (font, rec) = r
  J.Rectangle{_, _, +w, _} = rec
  +increase = (w * (size / 10.0) + 2.0 : F32)
  stroke.done((x + increase : F32), y, (width + w : F32), (count + 1 : U32),
    inked(Bool.not(U32.is_eq(code, 32)) && Bool.not(U32.is_eq(code, 9)), backed((J.Color.alpha(back) > 0 : U32), frame, (px + x : F32), (py + y : F32), increase, size, back), font,
      code, (px + x : F32), (py + y : F32), size, front))

# A line feed moves to the next line (textLineSpacing is 0); any other character is drawn.
def stroke.at(newline: Bool, +code: U32, +front: U32, +back: U32, +px: F32, +py: F32, +size: F32, +x: F32, +y: F32, +width: F32, +count: U32, frame: J.Frame, font: J.Font) -> Pen:
  match newline:
    case True{}: Pen{0.0, (y + size : F32), width, count, frame, font}
    case False{}: stroke.glyph(code, front, back, px, py, size, x, y, width, count, frame, J.Font.glyph_atlas_rec(font, code))

def stroke(glyph: Styled, +px: F32, +py: F32, +size: F32, pen: Pen) -> Pen:
  Styled{+code, +front, +back} = glyph
  Pen{+x, +y, +width, +count, frame, font} = pen
  stroke.at(U32.is_eq(code, 10), code, front, back, px, py, size, x, y, width, count, frame, font)

def strokes(glyphs: +List<Styled>, +px: F32, +py: F32, +size: F32, pen: Pen) -> Pen:
  match glyphs:
    case Nil{}: pen
    case Con{+glyph, rest}: strokes(rest, px, py, size, stroke(glyph, px, py, size, pen))

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def text.parsed(+px: F32, +py: F32, +size: F32, frame: J.Frame, font: J.Font, scan: Scan) -> Pen:
  Scan{_, _, _, +out, +ok} = scan
  strokes(List.reverse(&2, Styled, out), px, py, size, Pen{0.0, 0.0, 0.0, 0, checked(ok, frame), font})

def text.codes(+codes: +List<U32>, +px: F32, +py: F32, +size: F32, +base: U32, frame: J.Frame, font: J.Font) -> Pen:
  text.parsed(px, py, size, frame, font, styled(List.length(&2, U32, codes), base, Scan{codes, base, J.Color.BLANK(), Nil{}, True{}}))

# DrawTextStyled(GetFontDefault(), text, (px, py), fontSize, 2.0f, color), after the text before it.
def text(text: String, +px: F32, +py: F32, +size: F32, +base: U32, pen: Pen) -> Pen:
  Pen{_, _, _, _, frame, font} = pen
  text.codes(J.Font.codepoints(text), px, py, size, base, frame, font)

# MeasureTextStyled does not advance at a line feed or at a '[' that opens no tag.
def hangs(glyphs: +List<Styled>) -> Bool:
  match glyphs:
    case Nil{}: False{}
    case Con{Styled{+code, _, _}, rest}: U32.is_eq(code, 10) || U32.is_eq(code, 91) || hangs(rest)

# textSize = (textWidth*scaleFactor + (validCodepointCounter - 1)*spacing, fontSize); DrawRectangleLines(100, 240, (int)textSize.x, (int)textSize.y, GREEN).
def draw.done(+core: J.Core, rng: J.Random.State, +color: U32, +counter: U32, pen: Pen) -> J.Core & (State & J.Frame):
  Pen{_, _, +width, +count, frame, font} = pen
  (core, (State{rng, font, color, counter}, J.Draw.rectangle_lines(frame, 100.0, 240.0, F32.trunc((width * (40.0 / 10.0) + (U32.to_f32(count) - 1.0) * 2.0 : F32)), 40.0, J.Color.GREEN())))

def draw.refused(+core: J.Core, rng: J.Random.State, +color: U32, +counter: U32, pen: Pen) -> J.Core & (State & J.Frame):
  Pen{_, _, _, _, frame, font} = pen
  (core, (State{rng, font, color, counter}, J.Frame.refuse(frame)))

def measured.checked(+hangs: Bool, pen: Pen) -> Pen:
  Pen{+x, +y, +width, +count, frame, font} = pen
  Pen{x, y, width, count, checked(Bool.not(hangs), frame), font}

def measured.scan(+px: F32, +py: F32, +size: F32, frame: J.Frame, font: J.Font, +scan: Scan) -> Pen:
  Scan{_, _, _, +out, _} = scan
  measured.checked(hangs(out), text.parsed(px, py, size, frame, font, scan))

def measured.codes(+codes: +List<U32>, pen: Pen) -> Pen:
  Pen{_, _, _, _, frame, font} = pen
  measured.scan(100.0, 240.0, 40.0, frame, font, styled(List.length(&2, U32, codes), J.Color.BLACK(), Scan{codes, J.Color.BLACK(), J.Color.BLANK(), Nil{}, True{}}))

# DrawTextStyled(GetFontDefault(), text, (100, 240), 40.0f, 2.0f, BLACK) and its measure.
def draw.measured(+core: J.Core, rng: J.Random.State, +color: U32, +counter: U32, text: String, pen: Pen) -> J.Core & (State & J.Frame):
  draw.done(core, rng, color, counter, measured.codes(J.Font.codepoints(text), pen))

def draw.creative(text: Maybe<String>, +core: J.Core, rng: J.Random.State, +color: U32, +counter: U32, pen: Pen) -> J.Core & (State & J.Frame):
  match text:
    case None{}: draw.refused(core, rng, color, counter, pen)
    case Some{t}: draw.measured(core, rng, color, counter, t, pen)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, font, +color, +counter} = state
  p1 = text("This changes the [cFF0000FF]foreground color[r] of provided text!!!", 100.0, 80.0, 20.0, J.Color.BLACK(),
    Pen{0.0, 0.0, 0.0, 0, J.Frame.clear_background(frame, J.Color.RAYWHITE()), font})
  p2 = text("This changes the [bFF00FFFF]background color[r] of provided text!!!", 100.0, 120.0, 20.0, J.Color.BLACK(), p1)
  p3 = text("This changes the [c00ff00ff][bff0000ff]foreground and background colors[r]!!!", 100.0, 160.0, 20.0, J.Color.BLACK(), p2)
  p4 = text("This changes the [c00ff00ff]alpha[r] relative [cffffffff][b000000ff]from source[r] [cff000088]color[r]!!!", 100.0, 200.0, 20.0, J.Color.rgba(0, 0, 0, 100), p3)
  draw.creative(J.Text.format("Let's be [c%02x%02x%02xFF]CREATIVE[r] !!!", [J.TextInt{J.Color.red(color)}, J.TextInt{J.Color.green(color)}, J.TextInt{J.Color.blue(color)}]),
    core, rng, color, counter, p4)

def update.blue(+core: J.Core, font: J.Font, +counter: U32, +r: U32, +g: U32, draw: J.Random.State & F32) -> J.Core & State:
  (rng, +b) = draw
  (core, State{rng, font, J.Color.rgba(r, g, F32.to_u32(b), 255), counter})

def update.green(+core: J.Core, font: J.Font, +counter: U32, +r: U32, draw: J.Random.State & F32) -> J.Core & State:
  (rng, +g) = draw
  update.blue(core, font, counter, r, F32.to_u32(g), J.Random.value(rng, 0.0, 255.0))

def update.red(+core: J.Core, font: J.Font, +counter: U32, draw: J.Random.State & F32) -> J.Core & State:
  (rng, +r) = draw
  update.green(core, font, counter, F32.to_u32(r), J.Random.value(rng, 0.0, 255.0))

# if ((frameCounter%20) == 0): colRandom's r, g and b from GetRandomValue(0, 255), in that order.
def update.at(random: Bool, +core: J.Core, rng: J.Random.State, font: J.Font, +color: U32, +counter: U32) -> J.Core & State:
  match random:
    case False{}: (core, State{rng, font, color, counter})
    case True{}: update.red(core, font, counter, J.Random.value(rng, 0.0, 255.0))

def update(+core: J.Core, state: State) -> J.Core & State:
  State{rng, font, +color, +counter} = state
  update.at(U32.is_eq(((counter + 1) % 20 : U32), 0), core, rng, font, color, (counter + 1 : U32))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450) and SetRandomSeed(seed): colRandom = RED, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Random.seed(seed), J.Font.default(), J.Color.RED(), 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - inline styling", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
