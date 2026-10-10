# raylib [text] example - sprite fonts, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_sprite_fonts.c (zlib/libpng,
# Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Eight sprite fonts, each drawing its credit line at twice its base size,
# centered with MeasureTextEx. LoadFont of a .png is LoadImage (the PNG
# loader, Surface.load_png) and LoadFontFromImage(image, MAGENTA, 32). A font
# that cannot be loaded draws nothing here (raylib falls back to its default
# font). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Line is Type:
  Line{font: Maybe<J.Font>, position: M.Vector2}

type State is Type:
  State{lines: List<Line>}

def message(index: U32) -> String:
  match index:
    case 0: "ALAGARD FONT designed by Hewett Tsoi"
    case 1: "PIXELPLAY FONT designed by Aleksander Shevchuk"
    case 2: "MECHA FONT designed by Captain Falcon"
    case 3: "SETBACK FONT designed by Brian Kent (AEnigma)"
    case 4: "ROMULUS FONT designed by Hewett Tsoi"
    case 5: "PIXANTIQUA FONT designed by Gerhard Grossmann"
    case 6: "ALPHA_BETA FONT designed by Brian Kent (AEnigma)"
    case _: "JUPITER_CRASH FONT designed by Brian Kent (AEnigma)"

def spacing(index: U32) -> F32:
  match index:
    case 0: 2.0
    case 1: 4.0
    case 2: 8.0
    case 3: 4.0
    case 4: 3.0
    case 5: 4.0
    case 6: 4.0
    case _: 1.0

def color(index: U32) -> U32:
  match index:
    case 0: J.Color.MAROON()
    case 1: J.Color.ORANGE()
    case 2: J.Color.DARKGREEN()
    case 3: J.Color.DARKBLUE()
    case 4: J.Color.DARKPURPLE()
    case 5: J.Color.LIME()
    case 6: J.Color.GOLD()
    case _: J.Color.RED()

# positions[3].y += 8; positions[4].y += 2; positions[7].y -= 8.
def nudge(index: U32) -> F32:
  match index:
    case 3: 8.0
    case 4: 2.0
    case 7: F32.neg(8.0)
    case _: 0.0

def file(index: U32) -> String:
  match index:
    case 0: "alagard.png"
    case 1: "pixelplay.png"
    case 2: "mecha.png"
    case 3: "setback.png"
    case 4: "romulus.png"
    case 5: "pixantiqua.png"
    case 6: "alpha_beta.png"
    case _: "jupiter_crash.png"

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def drawn.done(+position: M.Vector2, r: J.Frame & J.Font) -> J.Frame & Line:
  (frame, font) = r
  (frame, Line{Some{font}, position})

# DrawTextEx(font, message, position, baseSize*2, spacing, color).
def drawn.at(+i: U32, frame: J.Frame, font: J.Font, +position: M.Vector2) -> J.Frame & Line:
  J.Font{+base, +padding, +glyphs, texture, atlas} = font
  drawn.done(position, J.Draw.text_ex(frame, J.Font{base, padding, glyphs, texture, atlas}, message(i), position, (U32.to_f32(base) * 2.0 : F32), spacing(i), color(i)))

def drawn(+i: U32, frame: J.Frame, line: Line) -> J.Frame & Line:
  Line{font, +position} = line
  match font:
    case None{}: (frame, Line{None{}, position})
    case Some{f}: drawn.at(i, frame, f, position)

def lines.push(done: List<Line>, r: J.Frame & Line) -> J.Frame & List<Line>:
  (frame, line) = r
  (frame, Con{line, done})

def lines.step(+i: U32, line: Line, acc: J.Frame & List<Line>) -> J.Frame & List<Line>:
  (frame, done) = acc
  lines.push(done, drawn(i, frame, line))

# Every line drawn in order; the lines come back newest first.
def lines(list: List<Line>, +i: U32, acc: J.Frame & List<Line>) -> J.Frame & List<Line>:
  match list:
    case Nil{}: acc
    case Con{line, rest}: lines(rest, (i + 1 : U32), lines.step(i, line, acc))

def draw.done(+core: J.Core, r: J.Frame & List<Line>) -> J.Core & (State & J.Frame):
  (frame, reversed) = r
  (core, (State{List.reverse(&1, Line, reversed)}, frame))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{list} = state
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "free sprite fonts included with raylib", 220.0, 20.0, 20.0, J.Color.DARKGRAY())
  draw.done(core, lines(list, 0, (J.Draw.line(f1, 220.0, 50.0, 600.0, 50.0, J.Color.DARKGRAY()), Nil{})))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# (screenWidth/2 - MeasureTextEx(font, message, baseSize*2, spacing).x/2, 60 + baseSize + 45*i), nudged.
def placed.at(+i: U32, +base: U32, r: J.Font & M.Vector2) -> Line:
  (font, size) = r
  M.Vector2{w, _} = size
  Line{Some{font}, M.Vector2{(800.0 / 2.0 - w / 2.0 : F32), ((60.0 + U32.to_f32(base) + 45.0 * U32.to_f32(i)) + nudge(i) : F32)}}

def placed(+i: U32, font: Maybe<J.Font>) -> Line:
  match font:
    case None{}: Line{None{}, M.Vector2.zero()}
    case Some{f}:
      J.Font{+base, +padding, +glyphs, texture, atlas} = f
      placed.at(i, base, J.Font.measure_text_ex(J.Font{base, padding, glyphs, texture, atlas}, message(i), (U32.to_f32(base) * 2.0 : F32), spacing(i)))

def font.made(r: J.Frame & (J.Surface & Maybe<J.Font>)) -> J.Frame & Maybe<J.Font>:
  (frame, pair) = r
  (_, font) = pair
  (frame, font)

# LoadFontFromImage(image, MAGENTA, 32).
def font(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Font>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: font.made(J.Font.load_from_image(frame, image, J.Color.MAGENTA(), 32))

def loaded.push(+i: U32, acc: List<Line>, r: J.Frame & Maybe<J.Font>) -> J.Frame & List<Line>:
  (frame, font) = r
  (frame, Con{placed(i, font), acc})

def loaded(+i: U32, r: J.Frame & List<Line>, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & List<Line>:
  (frame, acc) = r
  loaded.push(i, acc, font(frame, result))

def setup.done(+core: J.Core, r: J.Frame & List<Line>) -> J.Core & (J.Frame & State):
  (frame, reversed) = r
  (J.Core.set_target_fps(core, 60), (frame, State{List.reverse(&1, Line, reversed)}))

# The fonts in order, each loaded and placed.
def setup.load(n: Nat, +i: U32, +dir: String, +core: J.Core, r: J.Frame & List<Line>) -> IO(J.Core & (J.Frame & State)):
  match n:
    case 0n: IO.pure(J.Core & (J.Frame & State), setup.done(core, r))
    case 1n+p:
      IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/sprite_fonts/" ++ file(i)),
        result => setup.load(p, (i + 1 : U32), dir, core, loaded(i, r, result)))

# After InitWindow(800, 450): the eight fonts and their positions, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  setup.load(8n, 0, dir, core, (frame, Nil{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - sprite fonts", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
