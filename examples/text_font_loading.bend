# raylib [text] example - font loading, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_font_loading.c (zlib/libpng,
# Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The same message drawn with a BMFont (AngelCode .fnt and its .png page) or,
# while SPACE is held, with a font generated from a TTF at size 32 with 250
# codepoints. The message is the example's UTF-8 bytes (Jonlib strings are C
# byte strings). SetTextLineSpacing(16) is the line spacing passed to the
# drawing calls. A font Jonlib cannot load refuses the frames. See
# docs/FONTS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{bm: Maybe<J.Font>, ttf: Maybe<J.Font>, use_ttf: Bool}

def message() -> String:
  "!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHI\nJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmn\nopqrstuvwxyz{|}~\u{c2}\u{bf}\u{c3}\u{80}\u{c3}\u{81}\u{c3}\u{82}\u{c3}\u{83}\u{c3}\u{84}\u{c3}\u{85}\u{c3}\u{86}\u{c3}\u{87}\u{c3}\u{88}\u{c3}\u{89}\u{c3}\u{8a}\u{c3}\u{8b}\u{c3}\u{8c}\u{c3}\u{8d}\u{c3}\u{8e}\u{c3}\u{8f}\u{c3}\u{90}\u{c3}\u{91}\u{c3}\u{92}\u{c3}\u{93}\n\u{c3}\u{94}\u{c3}\u{95}\u{c3}\u{96}\u{c3}\u{97}\u{c3}\u{98}\u{c3}\u{99}\u{c3}\u{9a}\u{c3}\u{9b}\u{c3}\u{9c}\u{c3}\u{9d}\u{c3}\u{9e}\u{c3}\u{9f}\u{c3}\u{a0}\u{c3}\u{a1}\u{c3}\u{a2}\u{c3}\u{a3}\u{c3}\u{a4}\u{c3}\u{a5}\u{c3}\u{a6}\u{c3}\u{a7}\u{c3}\u{a8}\u{c3}\u{a9}\u{c3}\u{aa}\u{c3}\u{ab}\u{c3}\u{ac}\u{c3}\u{ad}\u{c3}\u{ae}\u{c3}\u{af}\u{c3}\u{b0}\u{c3}\u{b1}\u{c3}\u{b2}\u{c3}\u{b3}\u{c3}\u{b4}\u{c3}\u{b5}\u{c3}\u{b6}\u{c3}\u{b7}\n\u{c3}\u{b8}\u{c3}\u{b9}\u{c3}\u{ba}\u{c3}\u{bb}\u{c3}\u{bc}\u{c3}\u{bd}\u{c3}\u{be}\u{c3}\u{bf}"

def update(+core: J.Core, state: State) -> J.Core & State:
  State{bm, ttf, _} = state
  (core, State{bm, ttf, J.Input.is_key_down(core, J.KeyboardKey.KEY_SPACE())})

def shown(r: J.Frame & J.Font) -> J.Frame & Maybe<J.Font>:
  (frame, font) = r
  (frame, Some{font})

# DrawTextEx(font, msg, (20, 100), font.baseSize, 2, tint).
def show.at(+tint: U32, frame: J.Frame, font: J.Font) -> J.Frame & Maybe<J.Font>:
  J.Font{+base, +padding, +glyphs, texture, atlas} = font
  shown(J.Draw.text_ex_spaced(16, frame, J.Font{base, padding, glyphs, texture, atlas}, message(), M.Vector2{20.0, 100.0}, U32.to_f32(base), 2.0, tint))

def show(+tint: U32, frame: J.Frame, font: Maybe<J.Font>) -> J.Frame & Maybe<J.Font>:
  match font:
    case None{}: (J.Frame.refuse(frame), None{})
    case Some{f}: show.at(tint, frame, f)

def draw.bm(+core: J.Core, ttf: Maybe<J.Font>, r: J.Frame & Maybe<J.Font>) -> J.Core & (State & J.Frame):
  (frame, bm) = r
  (core, (State{bm, ttf, False{}}, J.Draw.text(frame, "Using BMFont (Angelcode) imported", 20.0, (450.0 - 30.0 : F32), 20.0, J.Color.GRAY())))

def draw.ttf(+core: J.Core, bm: Maybe<J.Font>, r: J.Frame & Maybe<J.Font>) -> J.Core & (State & J.Frame):
  (frame, ttf) = r
  (core, (State{bm, ttf, True{}}, J.Draw.text(frame, "Using TTF font generated", 20.0, (450.0 - 30.0 : F32), 20.0, J.Color.GRAY())))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{bm, ttf, use_ttf} = state
  match use_ttf:
    case False{}: draw.bm(core, ttf, show(J.Color.MAROON(), J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "Hold SPACE to use TTF generated font", 20.0, 20.0, 20.0, J.Color.LIGHTGRAY()), bm))
    case True{}: draw.ttf(core, bm, show(J.Color.LIME(), J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "Hold SPACE to use TTF generated font", 20.0, 20.0, 20.0, J.Color.LIGHTGRAY()), ttf))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def font(result: Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> Maybe<J.Font>:
  match result:
    case Fail{_}: None{}
    case Done{f}: f

def setup.done(+core: J.Core, bm: Maybe<J.Font>, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> J.Core & (J.Frame & State):
  (frame, result) = r
  (J.Core.set_target_fps(core, 60), (frame, State{bm, font(result), False{}}))

# LoadFontEx("resources/pixantiqua.ttf", 32, 0, 250).
def setup.ttf(+dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load_ex(frame, dir ++ "resources/pixantiqua.ttf", 32, Nil{}, 250),
    loaded => IO.pure(J.Core & (J.Frame & State), setup.done(core, font(result), loaded)))

# After InitWindow(800, 450): LoadFont("resources/pixantiqua.fnt") (with its
# pixantiqua.png page), the TTF font, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load(frame, dir ++ "resources/pixantiqua.fnt"),
    loaded => setup.ttf(dir, core, loaded))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - font loading", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
