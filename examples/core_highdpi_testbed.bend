# raylib [core] example - highdpi testbed, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_highdpi_testbed.c (zlib/libpng,
# Copyright (c) 2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A 40-pixel grid with the monitor, window position, screen and render
# sizes and the DPI scale as text, corner markers and a cross following the
# mouse; SPACE toggles the borderless mode and F fullscreen. The answers are
# those of Jonlib's Core (docs/DRIVER.md, as raylib's memory platform
# reports them). DrawCircleV's sinf/cosf follow the libm profile (whole
# degrees only). A mouse coordinate outside C's int refuses the frame.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{mouse: M.Vector2}

# SPACE: ToggleBorderlessWindowed(); F: ToggleFullscreen().
def update(+core: J.Core, +state: State) -> J.Core & State:
  +c1 = Bool.pick(J.Core, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), J.Core.toggle_borderless_windowed(core), core)
  (Bool.pick(J.Core, J.Input.is_key_pressed(c1, J.KeyboardKey.KEY_F()), J.Core.toggle_fullscreen(c1), c1), State{J.Input.get_mouse_position(core)})

def label(text: Maybe<String>, +x: F32, +y: F32, +size: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, size, color)

# for (h = 0; h < GetScreenHeight()/gridSpacing + 1; h++): the row's number and line.
def rows(n: Nat, +h: U32, +width: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: rows(p, (h + 1 : U32), width, J.Draw.line(label(J.Text.format("%02i", [J.TextInt{(h * 40 : U32)}]), 4.0, (U32.to_f32((h * 40 : U32)) - 4.0 : F32), 10.0, J.Color.GRAY(), frame),
      24.0, U32.to_f32((h * 40 : U32)), width, U32.to_f32((h * 40 : U32)), J.Color.LIGHTGRAY()))

# for (v = 0; v < GetScreenWidth()/gridSpacing + 1; v++): the column's number and line.
def columns(n: Nat, +v: U32, +height: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: columns(p, (v + 1 : U32), height, J.Draw.line(label(J.Text.format("%02i", [J.TextInt{(v * 40 : U32)}]), (U32.to_f32((v * 40 : U32)) - 10.0 : F32), 4.0, 10.0, J.Color.GRAY(), frame),
      U32.to_f32((v * 40 : U32)), 20.0, U32.to_f32((v * 40 : U32)), height, J.Color.LIGHTGRAY()))

# The monitor, window position, screen and render sizes and the scale factor.
def info(+core: J.Core, +monitor: U32, +window: M.Vector2, +scale: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+wx, +wy} = window
  M.Vector2{+sx, +sy} = scale
  f1 = label(J.Text.format("CURRENT MONITOR: %i/%i (%ix%i)", [J.TextInt{(monitor + 1 : U32)}, J.TextInt{J.Core.get_monitor_count(core)},
    J.TextInt{J.Core.get_monitor_width(core, monitor)}, J.TextInt{J.Core.get_monitor_height(core, monitor)}]), 50.0, 50.0, 20.0, J.Color.DARKGRAY(), frame)
  f2 = label(J.Text.format("WINDOW POSITION: %ix%i", [J.TextInt{F32.to_u32(wx)}, J.TextInt{F32.to_u32(wy)}]), 50.0, 90.0, 20.0, J.Color.DARKGRAY(), f1)
  f3 = label(J.Text.format("SCREEN SIZE: %ix%i", [J.TextInt{J.Core.get_screen_width(core)}, J.TextInt{J.Core.get_screen_height(core)}]), 50.0, 130.0, 20.0, J.Color.DARKGRAY(), f2)
  f4 = label(J.Text.format("RENDER SIZE: %ix%i", [J.TextInt{J.Core.get_render_width(core)}, J.TextInt{J.Core.get_render_height(core)}]), 50.0, 170.0, 20.0, J.Color.DARKGRAY(), f3)
  label(J.Text.format("SCALE FACTOR: %.2fx%.2f", [J.TextFloat{sx}, J.TextFloat{sy}]), 50.0, 210.0, 20.0, J.Color.GRAY(), f4)

# DrawRectangleRec((mousePos.x - 25, mousePos.y, 50, 2)), ((mousePos.x, mousePos.y - 25, 2, 50)) and
# DrawText("[GetMouseX(),GetMouseY()]", mousePos.x - 44, mousePos.y > GetScreenHeight() - 60? y - 46 : y + 30, 20, BLACK).
def cross.at(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, +ix: U32, +iy: U32, frame: J.Frame) -> J.Frame:
  M.Vector2{+x, +y} = mouse
  f1 = J.Draw.rectangle_rec(J.Draw.rectangle_rec(frame, J.Rectangle{(x - 25.0 : F32), y, 50.0, 2.0}, J.Color.BLACK()), J.Rectangle{x, (y - 25.0 : F32), 2.0, 50.0}, J.Color.BLACK())
  label(J.Text.format("[%i,%i]", [J.TextInt{ix}, J.TextInt{iy}]), F32.trunc((x - 44.0 : F32)),
    Bool.pick(F32, (y > U32.to_f32(J.Core.get_screen_height(core)) - 60.0 : F32), (F32.trunc(y) - 46.0 : F32), (F32.trunc(y) + 30.0 : F32)), 20.0, J.Color.BLACK(), f1)

# The cross on the mouse and its "[x,y]" label, above the mouse near the bottom edge.
def cross(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, mx: Maybe<U32>, my: Maybe<U32>, frame: J.Frame) -> J.Frame:
  match mx my:
    case Some{+ix} Some{+iy}: cross.at(libm, core, mouse, ix, iy, frame)
    case _ _: J.Frame.refuse(frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+mouse} = state
  +w = J.Core.get_screen_width(core)
  +h = J.Core.get_screen_height(core)
  f1 = columns(U32.to_nat((w / 40 + 1 : U32)), 0, U32.to_f32(h), rows(U32.to_nat((h / 40 + 1 : U32)), 0, U32.to_f32(w), J.Frame.clear_background(frame, J.Color.RAYWHITE())))
  f2 = info(core, J.Core.get_current_monitor(core), J.Core.get_window_position(core), J.Core.get_window_scale_dpi(core), f1)
  f3 = J.Draw.rectangle(J.Draw.rectangle(f2, 0.0, 0.0, 30.0, 60.0, J.Color.RED()), (U32.to_f32(w) - 30.0 : F32), (U32.to_f32(h) - 60.0 : F32), 30.0, 60.0, J.Color.BLUE())
  (core, (state, cross(libm, core, mouse, J.Input.get_mouse_x(core), J.Input.get_mouse_y(core), J.Draw.circle_v_for(libm, f3, J.Input.get_mouse_position(core), 20.0, J.Color.MAROON()))))

# The main loop's body; libm is the profile of DrawCircleV's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_WINDOW_HIGHDPI) and InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Input.get_mouse_position(core)}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - highdpi testbed", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
