# raylib [core] example - basic screen manager, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_basic_screen_manager.c
# (zlib/libpng, Copyright (c) 2021-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# Four screens: LOGO (for 120 frames), then TITLE, GAMEPLAY and ENDING, each
# left with ENTER or a tap gesture. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# screen: 0 LOGO, 1 TITLE, 2 GAMEPLAY, 3 ENDING.
type State is Data:
  State{screen: U32, frames: U32}

def advance(+core: J.Core) -> Bool:
  J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ENTER()) || J.Gestures.is_detected(core, J.Gesture.GESTURE_TAP())

def update.at(screen: U32, +core: J.Core, +frames: U32) -> State:
  match screen:
    case 0: State{Bool.pick(U32, ((frames + 1) > 120 : U32), 1, 0), (frames + 1 : U32)}
    case 1: State{Bool.pick(U32, advance(core), 2, 1), frames}
    case 2: State{Bool.pick(U32, advance(core), 3, 2), frames}
    case _: State{Bool.pick(U32, advance(core), 1, 3), frames}

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+screen, +frames} = state
  (core, update.at(screen, core, frames))

def draw.at(screen: U32, frame: J.Frame) -> J.Frame:
  match screen:
    case 0: J.Draw.text(J.Draw.text(frame, "LOGO SCREEN", 20.0, 20.0, 40.0, J.Color.LIGHTGRAY()), "WAIT for 2 SECONDS...", 290.0, 220.0, 20.0, J.Color.GRAY())
    case 1:
      f1 = J.Draw.text(J.Draw.rectangle(frame, 0.0, 0.0, 800.0, 450.0, J.Color.GREEN()), "TITLE SCREEN", 20.0, 20.0, 40.0, J.Color.DARKGREEN())
      J.Draw.text(f1, "PRESS ENTER or TAP to JUMP to GAMEPLAY SCREEN", 120.0, 220.0, 20.0, J.Color.DARKGREEN())
    case 2:
      f1 = J.Draw.text(J.Draw.rectangle(frame, 0.0, 0.0, 800.0, 450.0, J.Color.PURPLE()), "GAMEPLAY SCREEN", 20.0, 20.0, 40.0, J.Color.MAROON())
      J.Draw.text(f1, "PRESS ENTER or TAP to JUMP to ENDING SCREEN", 130.0, 220.0, 20.0, J.Color.MAROON())
    case _:
      f1 = J.Draw.text(J.Draw.rectangle(frame, 0.0, 0.0, 800.0, 450.0, J.Color.BLUE()), "ENDING SCREEN", 20.0, 20.0, 40.0, J.Color.DARKBLUE())
      J.Draw.text(f1, "PRESS ENTER or TAP to RETURN to TITLE SCREEN", 120.0, 220.0, 20.0, J.Color.DARKBLUE())

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+screen, _} = state
  (core, (state, draw.at(screen, J.Frame.clear_background(frame, J.Color.RAYWHITE()))))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): the LOGO screen, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0, 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - basic screen manager", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
