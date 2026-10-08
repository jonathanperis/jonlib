# raylib [shapes] example - basic shapes, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_basic_shapes.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Not reproduced yet: the hexagons turn by 0.2 degrees a frame, so DrawPoly,
# DrawPolyLines and DrawPolyLinesEx evaluate sinf/cosf at angles outside
# every verified M.Libm set (the Apple profile accepts whole degrees only, the
# glibc profiles |x| <= 6.283186, which the closing vertex exceeds). Every
# frame is refused, and the interactive run stops at the first one
# (docs/DRIVER.md). Build and run as examples/core_basic_window.bend.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{rotation: F32}

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+rotation} = state
  (core, State{(rotation + 0.2 : F32)})

def draw.shapes(+libm: M.Libm, +rotation: F32, frame: J.Frame) -> J.Frame:
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.text(f1, "some basic shapes available on raylib", 20.0, 20.0, 20.0, J.Color.DARKGRAY())
  f3 = J.Draw.circle_for(libm, f2, 160.0, 120.0, 35.0, J.Color.DARKBLUE())
  f4 = J.Draw.circle_gradient_for(libm, f3, M.Vector2{160.0, 220.0}, 60.0, J.Color.GREEN(), J.Color.SKYBLUE())
  f5 = J.Draw.circle_lines_for(libm, f4, 160.0, 340.0, 80.0, J.Color.DARKBLUE())
  f6 = J.Draw.ellipse_for(libm, f5, 160.0, 120.0, 25.0, 20.0, J.Color.YELLOW())
  f7 = J.Draw.ellipse_lines_for(libm, f6, 160.0, 120.0, 30.0, 25.0, J.Color.YELLOW())
  f8 = J.Draw.rectangle(f7, 340.0, 100.0, 120.0, 60.0, J.Color.RED())
  f9 = J.Draw.rectangle_gradient_h(f8, 310.0, 170.0, 180.0, 130.0, J.Color.MAROON(), J.Color.GOLD())
  f10 = J.Draw.rectangle_lines(f9, 360.0, 320.0, 80.0, 60.0, J.Color.ORANGE())
  f11 = J.Draw.triangle(f10, M.Vector2{600.0, 80.0}, M.Vector2{540.0, 150.0}, M.Vector2{660.0, 150.0}, J.Color.VIOLET())
  f12 = J.Draw.triangle_lines(f11, M.Vector2{600.0, 160.0}, M.Vector2{580.0, 230.0}, M.Vector2{620.0, 230.0}, J.Color.DARKBLUE())
  f13 = J.Draw.poly_for(libm, f12, M.Vector2{600.0, 330.0}, 6.0, 80.0, rotation, J.Color.BROWN())
  f14 = J.Draw.poly_lines_for(libm, f13, M.Vector2{600.0, 330.0}, 6.0, 90.0, rotation, J.Color.BROWN())
  f15 = J.Draw.poly_lines_ex_for(libm, f14, M.Vector2{600.0, 330.0}, 6.0, 85.0, rotation, 6.0, J.Color.BEIGE())
  J.Draw.line(f15, 18.0, 42.0, 782.0, 42.0, J.Color.BLACK())

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+rotation} = state
  (core, (State{rotation}, draw.shapes(libm, rotation, frame)))

# The main loop's body; libm is the sinf/cosf profile.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): rotation 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0.0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - basic shapes", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
