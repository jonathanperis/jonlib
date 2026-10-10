# raylib [text] example - font spritefont, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_font_spritefont.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Three messages in three sprite fonts, centered with MeasureTextEx. LoadFont
# of a .png is LoadImage (the PNG loader, Surface.load_png) and
# LoadFontFromImage(image, MAGENTA, 32). A font that cannot be loaded draws
# nothing here (raylib falls back to its default font). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Line is Type:
  Line{font: Maybe<J.Font>, position: M.Vector2}

type State is Type:
  State{first: Line, second: Line, third: Line}

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def line.done(+position: M.Vector2, r: J.Frame & J.Font) -> J.Frame & Line:
  (frame, font) = r
  (frame, Line{Some{font}, position})

# DrawTextEx(font, msg, position, (float)font.baseSize, spacing, WHITE).
def line.at(frame: J.Frame, font: J.Font, +position: M.Vector2, text: String, +spacing: F32) -> J.Frame & Line:
  J.Font{+base, +padding, +glyphs, texture, atlas} = font
  line.done(position, J.Draw.text_ex(frame, J.Font{base, padding, glyphs, texture, atlas}, text, position, U32.to_f32(base), spacing, J.Color.WHITE()))

def line(frame: J.Frame, line: Line, text: String, +spacing: F32) -> J.Frame & Line:
  Line{font, +position} = line
  match font:
    case None{}: (frame, Line{None{}, position})
    case Some{f}: line.at(frame, f, position, text, spacing)

def draw.third(+core: J.Core, first: Line, second: Line, r: J.Frame & Line) -> J.Core & (State & J.Frame):
  (frame, third) = r
  (core, (State{first, second, third}, frame))

def draw.second(+core: J.Core, first: Line, third: Line, r: J.Frame & Line) -> J.Core & (State & J.Frame):
  (frame, second) = r
  draw.third(core, first, second, line(frame, third, "...and a THIRD one! GREAT! :D", 2.0))

def draw.first(+core: J.Core, second: Line, third: Line, r: J.Frame & Line) -> J.Core & (State & J.Frame):
  (frame, first) = r
  draw.second(core, first, third, line(frame, second, "...and this is ANOTHER CUSTOM font...", F32.neg(2.0)))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{first, second, third} = state
  draw.first(core, second, third, line(J.Frame.clear_background(frame, J.Color.RAYWHITE()), first, "THIS IS A custom SPRITE FONT...", F32.neg(3.0)))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# (screenWidth/2 - MeasureTextEx(font, msg, baseSize, spacing).x/2, screenHeight/2 - baseSize/2 + dy).
def placed.at(+base: U32, +dy: F32, r: J.Font & M.Vector2) -> Line:
  (font, size) = r
  M.Vector2{w, _} = size
  Line{Some{font}, M.Vector2{(800.0 / 2.0 - w / 2.0 : F32), (450.0 / 2.0 - U32.to_f32(base) / 2.0 + dy : F32)}}

def placed(font: Maybe<J.Font>, text: String, +spacing: F32, +dy: F32) -> Line:
  match font:
    case None{}: Line{None{}, M.Vector2.zero()}
    case Some{f}:
      J.Font{+base, +padding, +glyphs, texture, atlas} = f
      placed.at(base, dy, J.Font.measure_text_ex(J.Font{base, padding, glyphs, texture, atlas}, text, U32.to_f32(base), spacing))

def font.made(r: J.Frame & (J.Surface & Maybe<J.Font>)) -> J.Frame & Maybe<J.Font>:
  (frame, pair) = r
  (_, font) = pair
  (frame, font)

# LoadFontFromImage(image, MAGENTA, 32).
def font(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Font>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: font.made(J.Font.load_from_image(frame, image, J.Color.MAGENTA(), 32))

def setup.third(+core: J.Core, first: Maybe<J.Font>, second: Maybe<J.Font>, r: J.Frame & Maybe<J.Font>) -> J.Core & (J.Frame & State):
  (frame, third) = r
  (J.Core.set_target_fps(core, 60), (frame, State{placed(first, "THIS IS A custom SPRITE FONT...", F32.neg(3.0), F32.neg(80.0)),
    placed(second, "...and this is ANOTHER CUSTOM font...", F32.neg(2.0), F32.neg(10.0)), placed(third, "...and a THIRD one! GREAT! :D", 2.0, 50.0)}))

def setup.second(dir: String, +core: J.Core, first: Maybe<J.Font>, r: J.Frame & Maybe<J.Font>) -> IO(J.Core & (J.Frame & State)):
  (frame, second) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/custom_jupiter_crash.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.third(core, first, second, font(frame, result))))

def setup.first(+dir: String, +core: J.Core, r: J.Frame & Maybe<J.Font>) -> IO(J.Core & (J.Frame & State)):
  (frame, first) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/custom_alagard.png"),
    result => setup.second(dir, core, first, font(frame, result)))

# After InitWindow(800, 450): the three fonts and their centered positions, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/custom_mecha.png"),
    result => setup.first(dir, core, font(frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - font spritefont", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
