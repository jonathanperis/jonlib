# raylib [shapes] example - collision area, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_collision_area.c (zlib/libpng,
# Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A bouncing box and a mouse-driven box; their overlap is drawn with its
# area. SPACE pauses. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{a: J.Rectangle, speed: F32, b: J.Rectangle, overlap: J.Rectangle, pause: Bool, collision: Bool, mouse_ok: Bool}

# A C int held in a U32 (two's complement) as an F32.
def signed(+value: U32) -> F32:
  Bool.pick(F32, (value >= 2147483648 : U32), F32.neg(U32.to_f32((0 - value : U32))), U32.to_f32(value))

def mouse.or_zero(value: Maybe<U32>) -> F32:
  match value:
    case None{}: 0.0
    case Some{+v}: signed(v)

def mouse.ok(value: Maybe<U32>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

# boxB centered on the mouse, kept inside the screen below the 40-pixel menu.
def box_b(+mx: F32, +my: F32) -> J.Rectangle:
  +x0 = (mx - 60.0 / 2.0 : F32)
  +y0 = (my - 60.0 / 2.0 : F32)
  +x = Bool.pick(F32, ((x0 + 60.0 : F32) >= 800.0 : F32), (800.0 - 60.0 : F32), Bool.pick(F32, (x0 <= 0.0 : F32), 0.0, x0))
  +y = Bool.pick(F32, ((y0 + 60.0 : F32) >= 450.0 : F32), (450.0 - 60.0 : F32), Bool.pick(F32, (y0 <= 40.0 : F32), 40.0, y0))
  J.Rectangle{x, y, 60.0, 60.0}

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+a, +speed, _, +overlap, +pause, _, _} = state
  J.Rectangle{+ax, +ay, +aw, +ah} = a
  +x = Bool.pick(F32, pause, ax, (ax + speed : F32))
  +s = Bool.pick(F32, ((x + aw : F32) >= 800.0 : F32) || (x <= 0.0 : F32), F32.neg(speed), speed)
  +na = {J.Rectangle{x, ay, aw, ah} : J.Rectangle}
  +b = box_b(mouse.or_zero(J.Input.get_mouse_x(core)), mouse.or_zero(J.Input.get_mouse_y(core)))
  +hit = J.Collision.recs(na, b)
  +ok = mouse.ok(J.Input.get_mouse_x(core)) && mouse.ok(J.Input.get_mouse_y(core))
  +p = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(pause), pause)
  (core, State{na, s, b, Bool.pick(J.Rectangle, hit, J.Collision.rectangle(na, b), overlap), p, hit, ok})

def draw.area(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 300.0, 50.0, 20.0, J.Color.BLACK())

def draw.title(width: Maybe<U32>, frame: J.Frame) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+w}: J.Draw.text(frame, "COLLISION!", (400.0 - U32.to_f32((w / 2 : U32)) : F32), 10.0, 20.0, J.Color.BLACK())

# The overlap, "COLLISION!" centered with MeasureText/2 (int division) and
# TextFormat("Collision Area: %i", (int)width*(int)height).
def draw.collision(hit: Bool, +overlap: J.Rectangle, frame: J.Frame) -> J.Frame:
  match hit:
    case False{}: frame
    case True{}:
      J.Rectangle{_, _, +w, +h} = overlap
      f1 = J.Draw.rectangle_rec(frame, overlap, J.Color.LIME())
      f2 = draw.title(J.Font.measure_text("COLLISION!", 20.0), f1)
      draw.area(J.Text.format("Collision Area: %i", [J.TextInt{(F32.to_u32(w) * F32.to_u32(h) : U32)}]), f2)

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+a, _, +b, +overlap, _, +hit, +ok} = state
  f1 = J.Frame.clear_background(draw.checked(ok, frame), J.Color.RAYWHITE())
  f2 = J.Draw.rectangle(f1, 0.0, 0.0, 800.0, 40.0, Bool.pick(U32, hit, J.Color.RED(), J.Color.BLACK()))
  f3 = J.Draw.rectangle_rec(J.Draw.rectangle_rec(f2, a, J.Color.GOLD()), b, J.Color.BLUE())
  f4 = draw.collision(hit, overlap, f3)
  f5 = J.Draw.text(f4, "Press SPACE to PAUSE/RESUME", 20.0, 415.0, 20.0, J.Color.LIGHTGRAY())
  draw.fps.done(state, f5, J.Core.get_fps(core, J.Core.get_time(core)), core)

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): boxA (10, 175, 200, 100) moving 4 px a frame,
# boxB (370, 195, 60, 60), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  +zero = {J.Rectangle{0.0, 0.0, 0.0, 0.0} : J.Rectangle}
  (J.Core.set_target_fps(core, 60), (frame, State{J.Rectangle{10.0, (450.0 / 2.0 - 50.0 : F32), 200.0, 100.0}, 4.0,
    J.Rectangle{(800.0 / 2.0 - 30.0 : F32), (450.0 / 2.0 - 30.0 : F32), 60.0, 60.0}, zero, False{}, False{}, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - collision area", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
