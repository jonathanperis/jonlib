# raylib [text] example - words alignment, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_words_alignment.c (zlib/libpng,
# Copyright (c) 2025 JP Mortiboys (@themushroompirates)); see
# LICENSES/raylib.txt.
#
# One word of a sentence a second ((int)GetTime() picks it) inside a blue
# box, aligned left, centre or right and top, middle or bottom by the arrow
# keys with MeasureTextEx and Lerp. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{font: J.Font, words: +List<String>, word: U32, h: U32, v: U32}

def horizontal(index: U32) -> String:
  match index:
    case 0: "Left"
    case 1: "Centre"
    case _: "Right"

def vertical(index: U32) -> String:
  match index:
    case 0: "Top"
    case 1: "Middle"
    case _: "Bottom"

def count(words: +List<String>, +n: U32) -> U32:
  match words:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

# (int)GetTime() % wordCount (0 without words or without a clock in int range).
def picked(time: Maybe<U32>, +total: U32) -> U32:
  match time:
    case None{}: 0
    case Some{seconds}: Bool.pick(U32, (total > 0 : U32), (seconds % U32.max(total, 1) : U32), 0)

# LEFT/RIGHT and UP/DOWN move the alignments inside 0..2.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{font, +words, _, +h, +v} = state
  +left = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()) && (h > 0 : U32), (h - 1 : U32), h)
  +right = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), U32.min((left + 1 : U32), 2), left)
  +up = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP()) && (v > 0 : U32), (v - 1 : U32), v)
  +down = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN()), U32.min((up + 1 : U32), 2), up)
  (core, State{font, words, picked(M.Float64.to_int(J.Core.get_time(core)), count(words, 0)), right, down})

def text(words: +List<String>) -> String:
  match words:
    case Con{w, _}: w
    case Nil{}: ""

def word(+words: +List<String>, +index: U32) -> String:
  text(List.drop(&2, String, words, U32.to_nat(index)))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 20.0, 40.0, 20.0, J.Color.LIGHTGRAY())

def draw.done(+core: J.Core, +words: +List<String>, +index: U32, +h: U32, +v: U32, r: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  (frame, font) = r
  (core, (State{font, words, index, h, v}, frame))

# textPos = container + Lerp(0, container size - text size, alignment*0.5).
def draw.measured(+core: J.Core, +words: +List<String>, +index: U32, +h: U32, +v: U32, frame: J.Frame, r: J.Font & M.Vector2) -> J.Core & (State & J.Frame):
  (font, size) = r
  M.Vector2{+tw, +th} = size
  +x = ((800.0 / 2.0 - 800.0 / 4.0) + M.Math.lerp(0.0, ((800.0 / 2.0) - tw : F32), (U32.to_f32(h) * 0.5 : F32)) : F32)
  +y = ((450.0 / 2.0 - 450.0 / 3.0) + M.Math.lerp(0.0, ((450.0 * 2.0 / 3.0) - th : F32), (U32.to_f32(v) * 0.5 : F32)) : F32)
  draw.done(core, words, index, h, v, J.Draw.text_ex(frame, font, word(words, index), M.Vector2{x, y}, 40.0, (40.0 * 0.1 : F32), J.Color.RAYWHITE()))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{font, +words, +index, +h, +v} = state
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.DARKBLUE()), "Use Arrow Keys to change the text alignment", 20.0, 20.0, 20.0, J.Color.LIGHTGRAY())
  f2 = label(J.Text.format("Alignment: Horizontal = %s, Vertical = %s", [J.TextString{horizontal(h)}, J.TextString{vertical(v)}]), f1)
  f3 = J.Draw.rectangle_rec(f2, J.Rectangle{(800.0 / 2.0 - 800.0 / 4.0 : F32), (450.0 / 2.0 - 450.0 / 3.0 : F32), (800.0 / 2.0 : F32), (450.0 * 2.0 / 3.0 : F32)}, J.Color.BLUE())
  draw.measured(core, words, index, h, v, f3, J.Font.measure_text_ex(font, word(words, index), 40.0, (40.0 * 0.1 : F32)))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def words(split: Maybe<+List<String>>) -> +List<String>:
  match split:
    case None{}: Nil{}
    case Some{list}: list

# After InitWindow(800, 450): TextSplit of the sentence, the default font,
# centre and middle alignment, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Font.default(),
    words(J.Text.split("raylib is a simple and easy-to-use library to enjoy videogames programming", ' ')), 0, 1, 1}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - words alignment", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
