# raylib [core] example - window flags, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_window_flags.c (zlib/libpng,
# Copyright (c) 2020-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A bouncing ball under a list of the window's state flags, each toggled by
# a key (F fullscreen, R resizable, D undecorated, H hidden and N minimized
# for 240 frames, M maximized, U unfocused, T topmost, A always run, V
# vsync, B borderless). What each call does to the flags is Jonlib's Core
# (docs/DRIVER.md, as raylib's memory platform answers). DrawCircleV's
# sinf/cosf follow the libm profile (whole degrees only).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{ball: M.Vector2, speed: M.Vector2, frames: U32}

def on(+core: J.Core, +flag: U32) -> Bool:
  J.Core.is_window_state(core, flag)

def pressed(+core: J.Core, +key: U32) -> Bool:
  J.Input.is_key_pressed(core, key)

# if (IsWindowState(flag)) ClearWindowState(flag); else SetWindowState(flag), when the key is pressed.
def toggled(+core: J.Core, +key: U32, +flag: U32) -> J.Core:
  Bool.pick(J.Core, pressed(core, key), Bool.pick(J.Core, on(core, flag), J.Core.clear_window_state(core, flag), J.Core.set_window_state(core, flag)), core)

def bounced(+at: F32, +speed: F32, +limit: F32) -> F32:
  Bool.pick(F32, (at >= limit - 20.0 : F32) || (at <= 20.0 : F32), (speed * F32.neg(1.0) : F32), speed)

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+ball, +speed, +frames} = state
  M.Vector2{+x, +y} = ball
  M.Vector2{+sx, +sy} = speed
  +c1 = Bool.pick(J.Core, pressed(core, J.KeyboardKey.KEY_F()), J.Core.toggle_fullscreen(core), core)
  +c2 = toggled(c1, J.KeyboardKey.KEY_R(), J.ConfigFlags.FLAG_WINDOW_RESIZABLE())
  +c3 = toggled(c2, J.KeyboardKey.KEY_D(), J.ConfigFlags.FLAG_WINDOW_UNDECORATED())
  +hide = pressed(c3, J.KeyboardKey.KEY_H())
  +c4 = Bool.pick(J.Core, hide && Bool.not(on(c3, J.ConfigFlags.FLAG_WINDOW_HIDDEN())), J.Core.set_window_state(c3, J.ConfigFlags.FLAG_WINDOW_HIDDEN()), c3)
  +f1 = Bool.pick(U32, hide, 0, frames)
  +hidden = on(c4, J.ConfigFlags.FLAG_WINDOW_HIDDEN())
  +f2 = Bool.pick(U32, hidden, (f1 + 1 : U32), f1)
  +c5 = Bool.pick(J.Core, hidden && (f2 >= 240 : U32), J.Core.clear_window_state(c4, J.ConfigFlags.FLAG_WINDOW_HIDDEN()), c4)
  +shrink = pressed(c5, J.KeyboardKey.KEY_N())
  +c6 = Bool.pick(J.Core, shrink && Bool.not(on(c5, J.ConfigFlags.FLAG_WINDOW_MINIMIZED())), J.Core.minimize_window(c5), c5)
  +f3 = Bool.pick(U32, shrink, 0, f2)
  +small = on(c6, J.ConfigFlags.FLAG_WINDOW_MINIMIZED())
  +f4 = Bool.pick(U32, small, (f3 + 1 : U32), f3)
  +back = small && (f4 >= 240 : U32)
  +c7 = Bool.pick(J.Core, back, J.Core.restore_window(c6), c6)
  +c8 = Bool.pick(J.Core, pressed(c7, J.KeyboardKey.KEY_M()), Bool.pick(J.Core, on(c7, J.ConfigFlags.FLAG_WINDOW_MAXIMIZED()), J.Core.restore_window(c7), J.Core.maximize_window(c7)), c7)
  +c9 = toggled(c8, J.KeyboardKey.KEY_U(), J.ConfigFlags.FLAG_WINDOW_UNFOCUSED())
  +c10 = toggled(c9, J.KeyboardKey.KEY_T(), J.ConfigFlags.FLAG_WINDOW_TOPMOST())
  +c11 = toggled(c10, J.KeyboardKey.KEY_A(), J.ConfigFlags.FLAG_WINDOW_ALWAYS_RUN())
  +c12 = toggled(c11, J.KeyboardKey.KEY_V(), J.ConfigFlags.FLAG_VSYNC_HINT())
  +c13 = Bool.pick(J.Core, pressed(c12, J.KeyboardKey.KEY_B()), J.Core.toggle_borderless_windowed(c12), c12)
  +nx = (x + sx : F32)
  +ny = (y + sy : F32)
  (c13, State{M.Vector2{nx, ny}, M.Vector2{bounced(nx, sx, U32.to_f32(J.Core.get_screen_width(c13))), bounced(ny, sy, U32.to_f32(J.Core.get_screen_height(c13)))}, Bool.pick(U32, back, 0, f4)})

def flag(+core: J.Core, +flag: U32, +yes: String, +no: String, +y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.text(frame, Bool.pick(String, on(core, flag), yes, no), 10.0, y, 10.0, Bool.pick(U32, on(core, flag), J.Color.LIME(), J.Color.MAROON()))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 40.0, 10.0, J.Color.GREEN())

def flags(+core: J.Core, frame: J.Frame) -> J.Frame:
  f1 = flag(core, J.ConfigFlags.FLAG_FULLSCREEN_MODE(), "[F] FLAG_FULLSCREEN_MODE: on", "[F] FLAG_FULLSCREEN_MODE: off", 80.0, J.Draw.text(frame, "Following flags can be set after window creation:", 10.0, 60.0, 10.0, J.Color.GRAY()))
  f2 = flag(core, J.ConfigFlags.FLAG_WINDOW_RESIZABLE(), "[R] FLAG_WINDOW_RESIZABLE: on", "[R] FLAG_WINDOW_RESIZABLE: off", 100.0, f1)
  f3 = flag(core, J.ConfigFlags.FLAG_WINDOW_UNDECORATED(), "[D] FLAG_WINDOW_UNDECORATED: on", "[D] FLAG_WINDOW_UNDECORATED: off", 120.0, f2)
  f4 = flag(core, J.ConfigFlags.FLAG_WINDOW_HIDDEN(), "[H] FLAG_WINDOW_HIDDEN: on", "[H] FLAG_WINDOW_HIDDEN: off (hides for 3 seconds)", 140.0, f3)
  f5 = flag(core, J.ConfigFlags.FLAG_WINDOW_MINIMIZED(), "[N] FLAG_WINDOW_MINIMIZED: on", "[N] FLAG_WINDOW_MINIMIZED: off (restores after 3 seconds)", 160.0, f4)
  f6 = flag(core, J.ConfigFlags.FLAG_WINDOW_MAXIMIZED(), "[M] FLAG_WINDOW_MAXIMIZED: on", "[M] FLAG_WINDOW_MAXIMIZED: off", 180.0, f5)
  f7 = flag(core, J.ConfigFlags.FLAG_WINDOW_UNFOCUSED(), "[G] FLAG_WINDOW_UNFOCUSED: on", "[U] FLAG_WINDOW_UNFOCUSED: off", 200.0, f6)
  f8 = flag(core, J.ConfigFlags.FLAG_WINDOW_TOPMOST(), "[T] FLAG_WINDOW_TOPMOST: on", "[T] FLAG_WINDOW_TOPMOST: off", 220.0, f7)
  f9 = flag(core, J.ConfigFlags.FLAG_WINDOW_ALWAYS_RUN(), "[A] FLAG_WINDOW_ALWAYS_RUN: on", "[A] FLAG_WINDOW_ALWAYS_RUN: off", 240.0, f8)
  f10 = flag(core, J.ConfigFlags.FLAG_VSYNC_HINT(), "[V] FLAG_VSYNC_HINT: on", "[V] FLAG_VSYNC_HINT: off", 260.0, f9)
  f11 = flag(core, J.ConfigFlags.FLAG_BORDERLESS_WINDOWED_MODE(), "[B] FLAG_BORDERLESS_WINDOWED_MODE: on", "[B] FLAG_BORDERLESS_WINDOWED_MODE: off", 280.0, f10)
  f12 = flag(core, J.ConfigFlags.FLAG_WINDOW_HIGHDPI(), "FLAG_WINDOW_HIGHDPI: on", "FLAG_WINDOW_HIGHDPI: off", 340.0, J.Draw.text(f11, "Following flags can only be set before window creation:", 10.0, 320.0, 10.0, J.Color.GRAY()))
  f13 = flag(core, J.ConfigFlags.FLAG_WINDOW_TRANSPARENT(), "FLAG_WINDOW_TRANSPARENT: on", "FLAG_WINDOW_TRANSPARENT: off", 360.0, f12)
  flag(core, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "FLAG_MSAA_4X_HINT: on", "FLAG_MSAA_4X_HINT: off", 380.0, f13)

def draw.fps.at(+libm: M.Libm, +state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (+core, +fps) = pair
  (core, (state, flags(core, label(J.Text.format("Screen Size: [%i, %i]", [J.TextInt{J.Core.get_screen_width(core)}, J.TextInt{J.Core.get_screen_height(core)}]), J.Draw.fps(frame, 10.0, 10.0, fps)))))

def draw.fps.done(+libm: M.Libm, +state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(libm, state, frame, pair)

# ClearBackground(BLANK) on a transparent window, else RAYWHITE; the ball, the border, the mouse.
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+ball, _, _} = state
  f1 = J.Draw.circle_v_for(libm, J.Frame.clear_background(frame, Bool.pick(U32, on(core, J.ConfigFlags.FLAG_WINDOW_TRANSPARENT()), J.Color.BLANK(), J.Color.RAYWHITE())), ball, 20.0, J.Color.MAROON())
  f2 = J.Draw.rectangle_lines_ex(f1, J.Rectangle{0.0, 0.0, U32.to_f32(J.Core.get_screen_width(core)), U32.to_f32(J.Core.get_screen_height(core))}, 4.0, J.Color.RAYWHITE())
  draw.fps.done(libm, state, J.Draw.circle_v_for(libm, f2, J.Input.get_mouse_position(core), 10.0, J.Color.DARKBLUE()), J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of DrawCircleV's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the ball at the center with speed (5, 4), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{M.Vector2{(U32.to_f32(J.Core.get_screen_width(core)) / 2.0 : F32), (U32.to_f32(J.Core.get_screen_height(core)) / 2.0 : F32)}, M.Vector2{5.0, 4.0}, 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - window flags", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
