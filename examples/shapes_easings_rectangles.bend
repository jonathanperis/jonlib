# raylib [shapes] example - easings rectangles, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_easings_rectangles.c and the
# EaseCircOut/EaseLinearIn of examples/shapes/reasings.h (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5); reasings.h after Robert
# Penner's easing equations, BSD); see LICENSES/raylib.txt.
#
# A 16x9 grid of rectangles shrinks and turns over 240 frames; SPACE plays it
# again. DrawRectanglePro's sinf/cosf follow the libm profile (AppleLibm
# verifies whole degrees only, so its frames are refused from the first
# half-degree turn). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# Every rectangle shares width, height and rotation; state 0 plays, 1 waits.
type State is Data:
  State{frames: U32, width: F32, height: F32, rotation: F32, state: U32}

# EaseCircOut(t, b, c, d): t = t/d - 1; c*sqrtf(1 - t*t) + b.
def ease.circ_out(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = (t / d - 1.0 : F32)
  (c * F32.sqrt((1.0 - u * u : F32)) + b : F32)

# EaseLinearIn(t, b, c, d): c*t/d + b.
def ease.linear_in(+t: F32, +b: F32, +c: F32, +d: F32) -> F32:
  (c * t / d + b : F32)

def clamp0(+v: F32) -> F32:
  Bool.pick(F32, (v < 0.0 : F32), 0.0, v)

def update.play(+frames: U32) -> State:
  +f = (frames + 1 : U32)
  +t = U32.to_f32(f)
  +h = clamp0(ease.circ_out(t, 50.0, F32.neg(50.0), 240.0))
  +w = clamp0(ease.circ_out(t, 50.0, F32.neg(50.0), 240.0))
  +done = F32.is_eq(h, 0.0) && F32.is_eq(w, 0.0)
  State{f, w, h, ease.linear_in(t, 0.0, 360.0, 240.0), Bool.pick(U32, done, 1, 0)}

def update.at(state: U32, +core: J.Core, +s: State) -> State:
  match state:
    case 0:
      State{+frames, _, _, _, _} = s
      update.play(frames)
    case _:
      State{_, _, _, +rotation, _} = s
      Bool.pick(State, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), State{0, 50.0, 50.0, rotation, 0}, s)

def update(+core: J.Core, +s: State) -> J.Core & State:
  State{_, _, _, _, +state} = s
  (core, update.at(state, core, s))

# recs[y*16 + x] at (25 + 50x, 25 + 50y), the origin at half its size.
def draw.grid(n: Nat, +libm: M.Libm, +w: F32, +h: F32, +rotation: F32, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +rec = {J.Rectangle{(50.0 / 2.0 + 50.0 * U32.to_f32((i % 16 : U32)) : F32), (50.0 / 2.0 + 50.0 * U32.to_f32((i / 16 : U32)) : F32), w, h} : J.Rectangle}
      draw.grid(p, libm, w, h, rotation, (i + 1 : U32), J.Draw.rectangle_pro_for(libm, frame, rec, M.Vector2{(w / 2.0 : F32), (h / 2.0 : F32)}, rotation, J.Color.RED()))

def draw.at(state: U32, +libm: M.Libm, +w: F32, +h: F32, +rotation: F32, frame: J.Frame) -> J.Frame:
  match state:
    case 0: draw.grid(144n, libm, w, h, rotation, 0, frame)
    case _: J.Draw.text(frame, "PRESS [SPACE] TO PLAY AGAIN!", 240.0, 200.0, 20.0, J.Color.GRAY())

def draw(+libm: M.Libm, +core: J.Core, +s: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{_, +w, +h, +rotation, +state} = s
  (core, (s, draw.at(state, libm, w, h, rotation, J.Frame.clear_background(frame, J.Color.RAYWHITE()))))

# The main loop's body; libm is the sinf/cosf profile of DrawRectanglePro.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => s => update(core, s), core => s => frame => draw(libm, core, s, frame)}

# After InitWindow(800, 450): 50x50 rectangles, rotation 0, playing, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0, 50.0, 50.0, 0.0, 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - easings rectangles", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
