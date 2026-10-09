# raylib [text] example - writing anim, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_writing_anim.c (zlib/libpng,
# Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The message appears one character every 10 frames; SPACE speeds it up 8
# times, ENTER restarts. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{frames: U32}

def message() -> String:
  "This sample illustrates a text writing\nanimation effect! Check it out! ;)"

# framesCounter += 8 while SPACE is down, else 1; ENTER resets it to 0.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+frames} = state
  +f = (frames + Bool.pick(U32, J.Input.is_key_down(core, J.KeyboardKey.KEY_SPACE()), 8, 1) : U32)
  (core, State{Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ENTER()), 0, f)})

def draw.message(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 210.0, 160.0, 20.0, J.Color.MAROON())

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+frames} = state
  f1 = draw.message(J.Text.subtext(message(), 0, (frames / 10 : U32)), J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.text(f1, "PRESS [ENTER] to RESTART!", 240.0, 260.0, 20.0, J.Color.LIGHTGRAY())
  (core, (state, J.Draw.text(f2, "HOLD [SPACE] to SPEED UP!", 239.0, 300.0, 20.0, J.Color.LIGHTGRAY())))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): framesCounter 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - writing anim", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
