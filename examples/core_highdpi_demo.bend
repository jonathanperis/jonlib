# raylib [core] example - highdpi demo, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_highdpi_demo.c (zlib/libpng,
# Copyright (c) 2025 Jonathan Marler (@marler8997)); see LICENSES/raylib.txt.
#
# Two rulers, one in logical points and one in physical pixels, with the DPI
# scale and the monitor as centered text (MeasureTextEx and DrawTextEx with
# the default font); N moves the window to the next monitor. The answers
# are those of Jonlib's Core (docs/DRIVER.md, as raylib's memory platform
# reports them: scale 1, one monitor), so both rulers coincide. A text
# Jonlib cannot format refuses the frame.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{frames: U32}

# With several monitors, N: SetWindowMonitor((GetCurrentMonitor() + 1)%monitorCount).
def update(+core: J.Core, +state: State) -> J.Core & State:
  +count = J.Core.get_monitor_count(core)
  (Bool.pick(J.Core, (count > 1 : U32) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_N()),
    J.Core.set_window_monitor(core, ((J.Core.get_current_monitor(core) + 1) % U32.max(count, 1) : U32)), core), state)

def drawn(r: J.Frame & J.Font) -> J.Frame:
  (frame, _) = r
  frame

def centered.at(+x: F32, +y: F32, +size: F32, +color: U32, +text: String, frame: J.Frame, r: J.Font & M.Vector2) -> J.Frame:
  (font, measure) = r
  M.Vector2{+w, +h} = measure
  drawn(J.Draw.text_ex(frame, font, text, M.Vector2{(x - w / 2.0 : F32), (y - h / 2.0 : F32)}, size, 3.0, color))

# DrawTextCenter: DrawTextEx(GetFontDefault(), text, (x - size.x/2, y - size.y/2), fontSize, 3, color).
def centered(text: Maybe<String>, +x: F32, +y: F32, +size: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{+t}: centered.at(x, y, size, color, t, frame, J.Font.measure_text_ex(J.Font.default(), t, size, 3.0))

def band(odd: Bool, +x: F32, +y: F32, +width: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match odd:
    case False{}: frame
    case True{}: J.Draw.rectangle(frame, x, y, width, 80.0, color)

# for (i = cellSize; i < GetScreenWidth(); i += cellSize, odd = !odd): the logical ruler.
def logical(n: Nat, +i: U32, +odd: Bool, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: logical(p, (i + 50 : U32), Bool.not(odd), J.Draw.line(centered(J.Text.format("%d", [J.TextInt{i}]), U32.to_f32(i), 150.0, 10.0, J.Color.LIGHTGRAY(),
      band(odd, U32.to_f32(i), 180.0, 50.0, J.Color.ORANGE(), frame)), U32.to_f32(i), 160.0, U32.to_f32(i), 260.0, J.Color.GRAY()))

def tick(shown: Bool, +i: U32, +x: F32, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: centered(J.Text.format("%d", [J.TextInt{i}]), x, 350.0, 10.0, J.Color.LIGHTGRAY(), frame)

# for (i = cellSize; i < GetRenderWidth(); i += cellSize, odd = !odd): the pixel ruler at x = (int)(i/dpiScale.x);
# a label only 30 or more points after the last one.
def physical(n: Nat, +i: U32, +odd: Bool, +scale: F32, +last: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +x = F32.trunc((U32.to_f32(i) / scale : F32))
      +shown = (x - last >= 30.0 : F32)
      physical(p, (i + 50 : U32), Bool.not(odd), scale, Bool.pick(F32, shown, x, last), tick(shown, i, x,
        J.Draw.line(band(odd, x, 240.0, F32.trunc((50.0 / scale : F32)), J.Color.rgba(0, 121, 241, 100), frame), x, 240.0, x, (350.0 - 10.0 : F32), J.Color.GRAY())))

def corner.at(+width: F32, +height: F32, frame: J.Frame, r: J.Font & M.Vector2) -> J.Frame:
  (font, measure) = r
  M.Vector2{+w, +h} = measure
  drawn(J.Draw.text_ex(frame, font, "Can you see this?", M.Vector2{((width - w) - 5.0 : F32), ((height - h) - 5.0 : F32)}, 20.0, 3.0, J.Color.LIGHTGRAY()))

def scene(+core: J.Core, +scale: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+sx, _} = scale
  +w = J.Core.get_screen_width(core)
  +rw = J.Core.get_render_width(core)
  +center = U32.to_f32((w / 2 : U32))
  f1 = centered(J.Text.format("Dpi Scale: %f", [J.TextFloat{sx}]), center, 30.0, 40.0, J.Color.DARKGRAY(), J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = centered(J.Text.format("Monitor: %d/%d ([N] next monitor)", [J.TextInt{(J.Core.get_current_monitor(core) + 1 : U32)}, J.TextInt{J.Core.get_monitor_count(core)}]), center, 70.0, 20.0, J.Color.LIGHTGRAY(), f1)
  f3 = centered(J.Text.format("Window is %d \"logical points\" wide", [J.TextInt{w}]), center, 120.0, 20.0, J.Color.ORANGE(), f2)
  f4 = physical(U32.to_nat(((rw - 1) / 50 : U32)), 50, True{}, sx, F32.neg(30.0), logical(U32.to_nat(((w - 1) / 50 : U32)), 50, True{}, f3))
  f5 = centered(J.Text.format("Window is %d \"physical pixels\" wide", [J.TextInt{rw}]), center, 380.0, 20.0, J.Color.BLUE(), f4)
  corner.at(U32.to_f32(w), U32.to_f32(J.Core.get_screen_height(core)), f5, J.Font.measure_text_ex(J.Font.default(), "Can you see this?", 20.0, 3.0))

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, (state, scene(core, J.Core.get_window_scale_dpi(core), frame)))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After SetConfigFlags(FLAG_WINDOW_HIGHDPI | FLAG_WINDOW_RESIZABLE) and InitWindow(800, 450): SetWindowMinSize(450, 450), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Core.set_window_min_size(core, 450, 450), 60), (frame, State{0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - highdpi demo", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
