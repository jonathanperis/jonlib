# raylib [text] example - input box, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_input_box.c (zlib/libpng,
# Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Type up to 9 characters while the mouse is over the box; BACKSPACE
# deletes. Characters come from GetCharPressed (the platform's character
# queue), which replayed automation events do not fill. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{name: +List<U32>, count: U32, on: Bool, frames: U32}

def box() -> J.Rectangle:
  J.Rectangle{(800.0 / 2.0 - 100.0 : F32), 180.0, 225.0, 50.0}

def text(chars: +List<U32>) -> String:
  match chars:
    case Nil{}: SNil{}
    case Con{+c, rest}: SCon{Chr{c}, text(rest)}

# while ((key = GetCharPressed()) > 0): the queued characters (raylib keeps
# at most 16), read until the first 0.
def chars(fuel: Nat, r: J.Core & U32, +acc: +List<U32>) -> J.Core & +List<U32>:
  match fuel:
    case 0n:
      (+core, _) = r
      (core, acc)
    case 1n+p:
      (+core, +key) = r
      Bool.pick(J.Core & +List<U32>, U32.is_eq(key, 0), (core, acc), chars(p, J.Input.get_char_pressed(core), List.append(&2, U32, acc, [key])))

# Characters 32..125 are appended while fewer than MAX_INPUT_CHARS (9) are held.
def typed(keys: +List<U32>, +name: +List<U32>, +count: U32) -> +List<U32> & U32:
  match keys:
    case Nil{}: (name, count)
    case Con{+key, rest}:
      +accepted = ((key >= 32) && (key <= 125) && (count < 9) : U32)
      typed(rest, Bool.pick(+List<U32>, accepted, List.append(&2, U32, name, [key]), name), Bool.pick(U32, accepted, (count + 1 : U32), count))

def typed.done(+frames: U32, +core: J.Core, r: +List<U32> & U32) -> J.Core & State:
  (+name, +count) = r
  +back = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_BACKSPACE())
  +c = Bool.pick(U32, back, Bool.pick(U32, U32.is_eq(count, 0), 0, (count - 1 : U32)), count)
  (core, State{List.take(&2, U32, name, U32.to_nat(c)), c, True{}, (frames + 1 : U32)})

def typed.read(+frames: U32, +name: +List<U32>, +count: U32, r: J.Core & +List<U32>) -> J.Core & State:
  (+core, +keys) = r
  typed.done(frames, core, typed(keys, name, count))

def update.on(on: Bool, +core: J.Core, +name: +List<U32>, +count: U32, +frames: U32) -> J.Core & State:
  match on:
    case True{}:
      +c = J.Input.set_mouse_cursor(core, J.MouseCursor.MOUSE_CURSOR_IBEAM())
      typed.read(frames, name, count, chars(17n, J.Input.get_char_pressed(c), Nil{}))
    case False{}: (J.Input.set_mouse_cursor(core, J.MouseCursor.MOUSE_CURSOR_DEFAULT()), State{name, count, False{}, 0})

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+name, +count, _, +frames} = state
  update.on(J.Collision.point_rec(J.Input.get_mouse_position(core), box()), core, name, count, frames)

def draw.counter(t: Maybe<String>, frame: J.Frame) -> J.Frame:
  match t:
    case None{}: J.Frame.refuse(frame)
    case Some{s}: J.Draw.text(frame, s, 315.0, 250.0, 20.0, J.Color.DARKGRAY())

def draw.caret(width: Maybe<U32>, frame: J.Frame) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+w}: J.Draw.text(frame, "_", (300.0 + 8.0 + U32.to_f32(w) : F32), (180.0 + 12.0 : F32), 40.0, J.Color.MAROON())

def draw.blink(blink: Bool, +name: +List<U32>, frame: J.Frame) -> J.Frame:
  match blink:
    case False{}: frame
    case True{}: draw.caret(J.Font.measure_text(text(name), 40.0), frame)

def draw.hint.at(room: Bool, +blink: Bool, +name: +List<U32>, frame: J.Frame) -> J.Frame:
  match room:
    case False{}: J.Draw.text(frame, "Press BACKSPACE to delete chars...", 230.0, 300.0, 20.0, J.Color.GRAY())
    case True{}: draw.blink(blink, name, frame)

# The caret blinks every 20 frames below 9 characters; at 9 the hint shows.
def draw.hint(on: Bool, +name: +List<U32>, +count: U32, +frames: U32, frame: J.Frame) -> J.Frame:
  match on:
    case False{}: frame
    case True{}:
      draw.hint.at((count < 9 : U32), U32.is_eq(((frames / 20) % 2 : U32), 0), name, frame)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+name, +count, +on, +frames} = state
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "PLACE MOUSE OVER INPUT BOX!", 240.0, 140.0, 20.0, J.Color.GRAY())
  f2 = J.Draw.rectangle_rec(f1, box(), J.Color.LIGHTGRAY())
  f3 = J.Draw.rectangle_lines(f2, 300.0, 180.0, 225.0, 50.0, Bool.pick(U32, on, J.Color.RED(), J.Color.DARKGRAY()))
  f4 = J.Draw.text(f3, text(name), (300.0 + 5.0 : F32), (180.0 + 8.0 : F32), 40.0, J.Color.MAROON())
  f5 = draw.counter(J.Text.format("INPUT CHARS: %i/%i", [J.TextInt{count}, J.TextInt{9}]), f4)
  (core, (state, draw.hint(on, name, count, frames, f5)))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): an empty name, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Nil{}, 0, False{}, 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - input box", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
