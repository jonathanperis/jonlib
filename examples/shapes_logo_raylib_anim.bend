# raylib [shapes] example - logo raylib anim, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_logo_raylib_anim.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The raylib logo drawn by a state machine: a blinking box, growing bars,
# letters one by one and a fade; R replays it. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{state: U32, frames: U32, letters: U32, top: U32, left: U32, bottom: U32, right: U32, alpha: F32}

def initial() -> State:
  State{0, 0, 0, 16, 16, 16, 16, 1.0}

def logo_x() -> F32:
  272.0

def logo_y() -> F32:
  97.0

# State 3: one more letter every 12 frames; from 10 letters alpha falls by
# 0.02f until it reaches 0, then state 4.
def update.fade(+s: State) -> State:
  State{_, +frames, +letters, +top, +left, +bottom, +right, +alpha} = s
  +a = (alpha - 0.02 : F32)
  Bool.pick(State, (a <= 0.0 : F32), State{4, frames, letters, top, left, bottom, right, 0.0}, State{3, frames, letters, top, left, bottom, right, a})

def State.letters_of(+s: State) -> U32:
  State{_, _, +letters, _, _, _, _, _} = s
  letters

def update.letters(+s: State) -> State:
  State{_, +frames, +letters, +top, +left, +bottom, +right, +alpha} = s
  +f = (frames + 1 : U32)
  +next = Bool.pick(State, U32.is_ne((f / 12 : U32), 0), State{3, 0, (letters + 1 : U32), top, left, bottom, right, alpha},
    State{3, f, letters, top, left, bottom, right, alpha})
  Bool.pick(State, (State.letters_of(next) >= 10 : U32), update.fade(next), next)

def update.at(+core: J.Core, state: U32, +frames: U32, +letters: U32, +top: U32, +left: U32, +bottom: U32, +right: U32, +alpha: F32) -> State:
  match state:
    case 0:
      +f = (frames + 1 : U32)
      Bool.pick(State, U32.is_eq(f, 120), State{1, 0, letters, top, left, bottom, right, alpha}, State{0, f, letters, top, left, bottom, right, alpha})
    case 1:
      +t = (top + 4 : U32)
      State{Bool.pick(U32, U32.is_eq(t, 256), 2, 1), frames, letters, t, (left + 4 : U32), bottom, right, alpha}
    case 2:
      +b = (bottom + 4 : U32)
      State{Bool.pick(U32, U32.is_eq(b, 256), 3, 2), frames, letters, top, left, b, (right + 4 : U32), alpha}
    case 3: update.letters(State{3, frames, letters, top, left, bottom, right, alpha})
    case _: Bool.pick(State, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R()), initial(), State{4, frames, letters, top, left, bottom, right, alpha})

def update(+core: J.Core, +s: State) -> J.Core & State:
  State{+state, +frames, +letters, +top, +left, +bottom, +right, +alpha} = s
  (core, update.at(core, state, frames, letters, top, left, bottom, right, alpha))

def box(frame: J.Frame, +x: F32, +y: F32, +w: U32, +h: U32, +color: U32) -> J.Frame:
  J.Draw.rectangle(frame, x, y, U32.to_f32(w), U32.to_f32(h), color)

def draw.letters(text: Maybe<String>, +alpha: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 356.0, 273.0, 50.0, J.Color.with_alpha(J.Color.BLACK(), alpha))

# State 0: the small box shows while (framesCounter/15)%2 is 1.
def draw.blink(on: Bool, frame: J.Frame) -> J.Frame:
  match on:
    case True{}: box(frame, logo_x(), logo_y(), 16, 16, J.Color.BLACK())
    case False{}: frame

def draw.at(state: U32, +frames: U32, +letters: U32, +top: U32, +left: U32, +bottom: U32, +right: U32, +alpha: F32, frame: J.Frame) -> J.Frame:
  match state:
    case 0: draw.blink(U32.is_eq(((frames / 15) % 2 : U32), 1), frame)
    case 1: box(box(frame, logo_x(), logo_y(), top, 16, J.Color.BLACK()), logo_x(), logo_y(), 16, left, J.Color.BLACK())
    case 2:
      f1 = box(box(frame, logo_x(), logo_y(), top, 16, J.Color.BLACK()), logo_x(), logo_y(), 16, left, J.Color.BLACK())
      box(box(f1, (logo_x() + 240.0 : F32), logo_y(), 16, right, J.Color.BLACK()), logo_x(), (logo_y() + 240.0 : F32), bottom, 16, J.Color.BLACK())
    case 3:
      +ink = J.Color.with_alpha(J.Color.BLACK(), alpha)
      f1 = box(frame, logo_x(), logo_y(), top, 16, ink)
      f2 = box(f1, logo_x(), (logo_y() + 16.0 : F32), 16, (left - 32 : U32), ink)
      f3 = box(f2, (logo_x() + 240.0 : F32), (logo_y() + 16.0 : F32), 16, (right - 32 : U32), ink)
      f4 = box(f3, logo_x(), (logo_y() + 240.0 : F32), bottom, 16, ink)
      f5 = box(f4, 288.0, 113.0, 224, 224, J.Color.with_alpha(J.Color.RAYWHITE(), alpha))
      draw.letters(J.Text.subtext("raylib", 0, letters), alpha, f5)
    case _: J.Draw.text(frame, "[R] REPLAY", 340.0, 200.0, 20.0, J.Color.GRAY())

def draw(+core: J.Core, +s: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+state, +frames, +letters, +top, +left, +bottom, +right, +alpha} = s
  (core, (s, draw.at(state, frames, letters, top, left, bottom, right, alpha, J.Frame.clear_background(frame, J.Color.RAYWHITE()))))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => s => update(core, s), core => s => frame => draw(core, s, frame)}

# After InitWindow(800, 450): every counter at its start, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, initial()))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - logo raylib anim", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
