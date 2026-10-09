# raylib [shapes] example - mouse trail, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_mouse_trail.c (zlib/libpng,
# Copyright (c) 2025 Balamurugan R (@Bala050814)); see LICENSES/raylib.txt.
#
# The last 30 mouse positions drawn as shrinking, fading circles. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{trail: +List<M.Vector2>}

def zeros(n: Nat) -> +List<M.Vector2>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{M.Vector2.zero(), zeros(p)}

# trailPositions shifted by one, the newest (the mouse) first: MAX_TRAIL_LENGTH = 30.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+trail} = state
  (core, State{Con{J.Input.get_mouse_position(core), List.take(&2, M.Vector2, trail, 29n)}})

def draw.point.at(shown: Bool, +libm: M.Libm, +ratio: F32, +p: M.Vector2, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: J.Draw.circle_v_for(libm, frame, p, (15.0 * ratio : F32), J.Color.with_alpha(J.Color.SKYBLUE(), (ratio * 0.5 + 0.5 : F32)))

# Entries at (0, 0) are skipped; ratio = (float)(30 - i)/30.
def draw.point(+libm: M.Libm, +i: U32, +p: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+x, +y} = p
  +ratio = (U32.to_f32((30 - i : U32)) / 30.0 : F32)
  draw.point.at(F32.is_ne(x, 0.0) || F32.is_ne(y, 0.0), libm, ratio, p, frame)

def draw.trail(trail: +List<M.Vector2>, +libm: M.Libm, +i: U32, frame: J.Frame) -> J.Frame:
  match trail:
    case Nil{}: frame
    case Con{+p, rest}: draw.trail(rest, libm, (i + 1 : U32), draw.point(libm, i, p, frame))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+trail} = state
  f1 = draw.trail(trail, libm, 0, J.Frame.clear_background(frame, J.Color.BLACK()))
  f2 = J.Draw.circle_v_for(libm, f1, J.Input.get_mouse_position(core), 15.0, J.Color.WHITE())
  (core, (state, J.Draw.text(f2, "Move the mouse to see the trail effect!", 10.0, 420.0, 20.0, J.Color.LIGHTGRAY())))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): 30 zero positions, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{zeros(30n)}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - mouse trail", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
