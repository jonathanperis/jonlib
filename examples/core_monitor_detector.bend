# raylib [core] example - monitor detector, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_monitor_detector.c (zlib/libpng,
# Copyright (c) 2025 Maicon Santana (@maiconpintoabreu)); see
# LICENSES/raylib.txt.
#
# The monitors as scaled rectangles with their name, resolution, refresh
# rate, physical size and position, the window inside the current one, and
# ENTER to move the window to the next monitor. The answers are those of
# Jonlib's Core (docs/DRIVER.md): one unnamed monitor of size 0, as raylib's
# memory platform reports, which makes the example's scale 480 and its text
# 57600 pixels tall, below the window.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{current: U32}

# offset, width, height: monitorOffsetX, maxWidth and maxHeight.
type Extent is Data:
  Extent{offset: F32, width: F32, height: F32}

def extent.with(+acc: Extent, +position: M.Vector2, +width: F32, +height: F32) -> Extent:
  Extent{+offset, +most, +tall} = acc
  M.Vector2{+x, +y} = position
  Extent{Bool.pick(F32, (x < offset : F32), F32.neg(F32.trunc(x)), offset), F32.max(most, (F32.trunc(x) + width : F32)), F32.max(tall, (F32.trunc(y) + height : F32))}

# for (i = 0; i < monitorCount; i++): the leftmost offset and the farthest right and bottom edges.
def extent(n: Nat, +core: J.Core, +i: U32, +acc: Extent) -> Extent:
  match n:
    case 0n: acc
    case 1n+p: extent(p, core, (i + 1 : U32), extent.with(acc, J.Core.get_monitor_position(core, i), U32.to_f32(J.Core.get_monitor_width(core, i)), U32.to_f32(J.Core.get_monitor_height(core, i))))

# ENTER with more than one monitor moves the window to the next; otherwise the current monitor is asked.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+current} = state
  +count = J.Core.get_monitor_count(core)
  +move = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ENTER()) && (count > 1 : U32)
  +next = Bool.pick(U32, U32.is_eq((current + 1 : U32), count), 0, (current + 1 : U32))
  (Bool.pick(J.Core, move, J.Core.set_window_monitor(core, next), core), State{Bool.pick(U32, move, next, J.Core.get_current_monitor(core))})

def label(text: Maybe<String>, +x: F32, +y: F32, +size: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, size, color)

# The window: ((GetWindowPosition().x + monitorOffsetX)*monitorScale + 140, GetWindowPosition().y*monitorScale + 80), screen size times the scale.
def window(+position: M.Vector2, +offset: F32, +scale: F32, frame: J.Frame) -> J.Frame:
  M.Vector2{+wx, +wy} = position
  J.Draw.rectangle_v(frame, M.Vector2{((wx + offset) * scale + 140.0 : F32), (wy * scale + 80.0 : F32)},
    M.Vector2{(800.0 * scale : F32), (450.0 * scale : F32)}, J.Color.with_alpha(J.Color.GREEN(), 0.5))

# The current monitor in RED with the window (GREEN, half transparent) inside; the others in GRAY.
def outline(current: Bool, +core: J.Core, +rec: J.Rectangle, +offset: F32, +scale: F32, frame: J.Frame) -> J.Frame:
  match current:
    case False{}: J.Draw.rectangle_lines_ex(frame, rec, 5.0, J.Color.GRAY())
    case True{}: window(J.Core.get_window_position(core), offset, scale, J.Draw.rectangle_lines_ex(frame, rec, 5.0, J.Color.RED()))

def monitor.at(+core: J.Core, +i: U32, +current: U32, +offset: F32, +scale: F32, +position: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+px, +py} = position
  +x = ((px + offset) * scale + 140.0 : F32)
  +y = (py * scale + 80.0 : F32)
  +w = J.Core.get_monitor_width(core, i)
  +h = J.Core.get_monitor_height(core, i)
  f1 = label(J.Text.format("[%i] %s", [J.TextInt{i}, J.TextString{J.Core.get_monitor_name(core, i)}]), (F32.trunc(x) + 10.0 : F32), (F32.trunc(y) + F32.trunc((100.0 * scale : F32)) : F32),
    F32.trunc((120.0 * scale : F32)), J.Color.BLUE(), frame)
  f2 = label(J.Text.format("Resolution: [%ipx x %ipx]\nRefreshRate: [%ihz]\nPhysical Size: [%imm x %imm]\nPosition: %3.0f x %3.0f",
    [J.TextInt{w}, J.TextInt{h}, J.TextInt{J.Core.get_monitor_refresh_rate(core, i)}, J.TextInt{J.Core.get_monitor_physical_width(core, i)},
     J.TextInt{J.Core.get_monitor_physical_height(core, i)}, J.TextFloat{px}, J.TextFloat{py}]),
    (F32.trunc(x) + 10.0 : F32), (F32.trunc(y) + F32.trunc((200.0 * scale : F32)) : F32), F32.trunc((120.0 * scale : F32)), J.Color.DARKGRAY(), f1)
  outline(U32.is_eq(i, current), core, J.Rectangle{x, y, (U32.to_f32(w) * scale : F32), (U32.to_f32(h) * scale : F32)}, offset, scale, f2)

def monitors(n: Nat, +core: J.Core, +i: U32, +current: U32, +offset: F32, +scale: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: monitors(p, core, (i + 1 : U32), current, offset, scale, monitor.at(core, i, current, offset, scale, J.Core.get_monitor_position(core, i), frame))

# monitorScale = 0.6*(screenHeight/maxHeight) when the monitors are taller than wide, else 0.6*(screenWidth/(maxWidth + monitorOffsetX)).
def scene(+core: J.Core, +current: U32, +count: U32, +bounds: Extent, frame: J.Frame) -> J.Frame:
  Extent{+offset, +width, +height} = bounds
  +scale = Bool.pick(F32, (height > width + offset : F32), (0.6 * (450.0 / height) : F32), (0.6 * (800.0 / (width + offset)) : F32))
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "Press [Enter] to move window to next monitor available", 20.0, 20.0, 20.0, J.Color.DARKGRAY())
  monitors(U32.to_nat(count), core, 0, current, offset, scale, J.Draw.rectangle_lines(f1, 20.0, 60.0, (800.0 - 40.0 : F32), (450.0 - 100.0 : F32), J.Color.DARKGRAY()))

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+current} = state
  +count = J.Core.get_monitor_count(core)
  (core, (state, scene(core, current, count, extent(U32.to_nat(count), core, 0, Extent{0.0, 1.0, 1.0}), frame)))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): currentMonitorIndex = GetCurrentMonitor(), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Core.get_current_monitor(core)}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - monitor detector", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
