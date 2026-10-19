# raylib [shapes] example - polygon lines, ported to Jonlib.
# Adapted from raylib 6.2 examples/shapes/shapes_polygon_lines.c (zlib/libpng,
# Copyright (c) 2026 Matthew Roush (@MatthewRoush)); see LICENSES/raylib.txt.
#
# DrawRectangleLinesEx and DrawCircleLinesEx next to the DrawPolyLinesEx
# outlines that should match them, and eight polygons (3 to 10 sides)
# turning by 36 degrees a second of GetFrameTime; UP and DOWN set the
# thickness (1 to 60). DrawPoly and DrawPolyLinesEx evaluate sinf/cosf at the
# F32-accumulated angles rotation*DEG2RAD + k*360/sides*DEG2RAD, which the
# glibc profiles reproduce (glibc's own sinf/cosf, docs/SINCOSF.md) but the
# Apple profile does not (whole degrees only, and the heptagon's step of
# 360/7 degrees is none, whatever the rotation): under M.AppleLibm{} every
# frame is refused. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{thick: U32, rotation: F32}

# thick = (thick < 1) ? 1 : (thick > 60) ? 60 : thick (never negative here:
# it is at least 1 before a DOWN takes 1 away).
def clamped(+thick: U32) -> U32:
  Bool.pick(U32, (thick < 1 : U32), 1, Bool.pick(U32, (thick > 60 : U32), 60, thick))

# IsKeyPressed(KEY_UP) adds 1, IsKeyPressed(KEY_DOWN) takes 1; rotation +=
# (360.0f/10.0f)*GetFrameTime().
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+thick, +rotation} = state
  +up = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP()), (thick + 1 : U32), thick)
  +down = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN()), (up - 1 : U32), up)
  (core, State{clamped(down), (rotation + (360.0 / 10.0) * J.Core.get_frame_time(core) : F32)})

def draw.label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 280.0, 20.0, J.Color.LIME())

# DrawPoly and DrawPolyLinesEx of one turning polygon (radius 60).
def draw.turning(+libm: M.Libm, +x: F32, +y: F32, +sides: F32, +rotation: F32, +thick: F32, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.poly_for(libm, frame, M.Vector2{x, y}, sides, 60.0, rotation, J.Color.LIGHTGRAY())
  J.Draw.poly_lines_ex_for(libm, f1, M.Vector2{x, y}, sides, 60.0, rotation, thick, J.Color.BLUE())

def draw.scene(+libm: M.Libm, +count: U32, +rotation: F32, frame: J.Frame) -> J.Frame:
  +thick = U32.to_f32(count)
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = draw.label(J.Text.format("thick = %d", [J.TextInt{count}]), f1)
  f3 = J.Draw.text(f2, "These should look identical!", 10.0, 10.0, 20.0, J.Color.MAROON())
  # Outline pair 1
  f4 = J.Draw.rectangle(f3, 10.0, 40.0, 50.0, 50.0, J.Color.LIGHTGRAY())
  f5 = J.Draw.rectangle_lines_ex(f4, J.Rectangle{10.0, 40.0, 50.0, 50.0}, thick, J.Color.RED())
  f6 = J.Draw.circle_for(libm, f5, 95.0, 65.0, 25.0, J.Color.LIGHTGRAY())
  f7 = J.Draw.circle_lines_ex_for(libm, f6, M.Vector2{95.0, 65.0}, 25.0, thick, J.Color.RED())
  f8 = J.Draw.text(f7, "DrawRectangleLinesEx() and DrawCircleLinesEx()", 130.0, 60.0, 10.0, J.Color.BLACK())
  # Outline pair 2
  f9 = J.Draw.poly_for(libm, f8, M.Vector2{35.0, 125.0}, 4.0, 35.355, 45.0, J.Color.LIGHTGRAY())
  f10 = J.Draw.poly_lines_ex_for(libm, f9, M.Vector2{35.0, 125.0}, 4.0, 35.355, 45.0, thick, J.Color.RED())
  f11 = J.Draw.poly_for(libm, f10, M.Vector2{95.0, 125.0}, 36.0, 25.0, 0.0, J.Color.LIGHTGRAY())
  f12 = J.Draw.poly_lines_ex_for(libm, f11, M.Vector2{95.0, 125.0}, 36.0, 25.0, 0.0, thick, J.Color.RED())
  f13 = J.Draw.text(f12, "DrawPolyLinesEx()", 130.0, 120.0, 10.0, J.Color.BLACK())
  # Some other shapes, all with the same outline thickness
  f14 = draw.turning(libm, 290.0, 220.0, 3.0, rotation, thick, f13)
  f15 = draw.turning(libm, 430.0, 220.0, 4.0, rotation, thick, f14)
  f16 = draw.turning(libm, 570.0, 220.0, 5.0, rotation, thick, f15)
  f17 = draw.turning(libm, 710.0, 220.0, 6.0, rotation, thick, f16)
  f18 = draw.turning(libm, 290.0, 360.0, 7.0, rotation, thick, f17)
  f19 = draw.turning(libm, 430.0, 360.0, 8.0, rotation, thick, f18)
  f20 = draw.turning(libm, 570.0, 360.0, 9.0, rotation, thick, f19)
  draw.turning(libm, 710.0, 360.0, 10.0, rotation, thick, f20)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+thick, +rotation} = state
  (core, (State{thick, rotation}, draw.scene(libm, thick, rotation, frame)))

# The main loop's body; libm is the sinf/cosf profile.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): thick 2, rotation 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{2, 0.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - polygon lines", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
