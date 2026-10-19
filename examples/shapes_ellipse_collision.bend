# raylib [shapes] example - ellipse collision, ported to Jonlib.
# Adapted from raylib 6.2 examples/shapes/shapes_ellipse_collision.c (zlib/libpng,
# Copyright (c) 2025 Ziya (@Monjaris)); see LICENSES/raylib.txt.
#
# Two ellipses, one following the mouse (A or B selects which); they turn
# red when they collide. The example's CheckCollisionEllipses compares the
# centers' distance with the two radial distances to the boundaries in the
# direction theta = atan2f(dy, dx), through cosf/sinf(theta): theta is the
# negated checked Vector2LineAngle (the same subtractions), with the
# profile's sinf/cosf. Apart centers the libm profile cannot reproduce refuse
# the frame; under M.AppleLibm{} that is every frame whose centers differ by
# an angle other than a verified whole degree (docs/ANGLES.md,
# docs/SINCOSF.md). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The ellipses' centers (radii A 120x70, B 90x140) and whether B is the one
# controlled (controlled == 1).
type State is Data:
  State{a: M.Vector2, b: M.Vector2, on_b: Bool}

# CheckCollisionPointEllipse(point, center, rx, ry)
def inside(+px: F32, +py: F32, +cx: F32, +cy: F32, +rx: F32, +ry: F32) -> Bool:
  +dx = ((px - cx) / rx : F32)
  +dy = ((py - cy) / ry : F32)
  (dx * dx + dy * dy <= 1.0 : F32)

# r(theta) = (rx*ry)/sqrtf((ry*cosT)*(ry*cosT) + (rx*sinT)*(rx*sinT))
def radial(+rx: F32, +ry: F32, +c: F32, +s: F32) -> F32:
  (rx * ry / F32.sqrt(((ry * c) * (ry * c) + (rx * s) * (rx * s) : F32)) : F32)

def collide.reach(+dist: F32, +c: F32, +s: F32) -> Bool:
  +r1 = radial(120.0, 70.0, c, s)
  +r2 = radial(90.0, 140.0, c, s)
  (dist <= r1 + r2 : F32)

def collide.at(+dist: F32, cosine: Maybe<F32>, sine: Maybe<F32>) -> Maybe<Bool>:
  match cosine sine:
    case Some{c} Some{s}: Some{collide.reach(dist, c, s)}
    case _ _: None{}

# theta = atan2f(dy, dx): Vector2LineAngle(c1, c2) is -atan2f(c2.y - c1.y,
# c2.x - c1.x); negating it back is exact.
def collide.angle(+libm: M.Libm, +dist: F32, angle: Maybe<F32>) -> Maybe<Bool>:
  match angle:
    case None{}: None{}
    case Some{+negated}: collide.at(dist, M.Libm.cos(libm, F32.neg(negated)), M.Libm.sin(libm, F32.neg(negated)))

# Ellipses on top of each other (dist == 0) collide without atan2f.
def collide.apart(same: Bool, +libm: M.Libm, +dist: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32) -> Maybe<Bool>:
  match same:
    case True{}: Some{True{}}
    case False{}: collide.angle(libm, dist, M.Vector2.line_angle_for(libm, M.Vector2{x1, y1}, M.Vector2{x2, y2}))

# CheckCollisionEllipses(c1, 120, 70, c2, 90, 140); None where the libm
# profile has no atan2f/cosf/sinf result.
def collide(+libm: M.Libm, +c1: M.Vector2, +c2: M.Vector2) -> Maybe<Bool>:
  M.Vector2{+x1, +y1} = c1
  M.Vector2{+x2, +y2} = c2
  +dx = (x2 - x1 : F32)
  +dy = (y2 - y1 : F32)
  +dist = F32.sqrt((dx * dx + dy * dy : F32))
  collide.apart(F32.is_eq(dist, 0.0), libm, dist, x1, y1, x2, y2)

# IsKeyPressed(KEY_A) selects A, then IsKeyPressed(KEY_B) B; the controlled
# center is GetMousePosition().
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+a, +b, +on_b} = state
  +on = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_B()) || (Bool.not(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_A())) && on_b)
  +mouse = J.Input.get_mouse_position(core)
  (core, State{Bool.pick(M.Vector2, on, a, mouse), Bool.pick(M.Vector2, on, mouse, b), on})

def draw.status(hit: Bool, frame: J.Frame) -> J.Frame:
  match hit:
    case True{}: J.Draw.text(frame, "ELLIPSES COLLIDE", (800.0 / 2.0 - 120.0 : F32), 40.0, 28.0, J.Color.RED())
    case False{}: J.Draw.text(frame, "NO COLLISION", (800.0 / 2.0 - 80.0 : F32), 40.0, 28.0, J.Color.DARKGRAY())

def draw.controlling(on_b: Bool, frame: J.Frame) -> J.Frame:
  match on_b:
    case False{}: J.Draw.text(frame, "Controlling: A", 20.0, (450.0 - 40.0 : F32), 20.0, J.Color.YELLOW())
    case True{}: J.Draw.text(frame, "Controlling: B", 20.0, (450.0 - 40.0 : F32), 20.0, J.Color.YELLOW())

def draw.inside(shown: Bool, text: String, +color: U32, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: J.Draw.text(frame, text, 20.0, (450.0 - 70.0 : F32), 20.0, color)

# DrawEllipse/DrawEllipseLines take (int)center.x, (int)center.y.
def draw.scene(+libm: M.Libm, +a: M.Vector2, +b: M.Vector2, +on_b: Bool, +mouse: M.Vector2, +hit: Bool, frame: J.Frame) -> J.Frame:
  M.Vector2{+ax, +ay} = a
  M.Vector2{+bx, +by} = b
  M.Vector2{+mx, +my} = mouse
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.ellipse_for(libm, f1, ax, ay, 120.0, 70.0, Bool.pick(U32, hit, J.Color.RED(), J.Color.BLUE()))
  f3 = J.Draw.ellipse_for(libm, f2, bx, by, 90.0, 140.0, Bool.pick(U32, hit, J.Color.RED(), J.Color.GREEN()))
  f4 = J.Draw.ellipse_lines_for(libm, f3, ax, ay, 120.0, 70.0, J.Color.WHITE())
  f5 = J.Draw.ellipse_lines_for(libm, f4, bx, by, 90.0, 140.0, J.Color.WHITE())
  f6 = J.Draw.circle_v_for(libm, f5, M.Vector2{ax, ay}, 4.0, J.Color.WHITE())
  f7 = J.Draw.circle_v_for(libm, f6, M.Vector2{bx, by}, 4.0, J.Color.WHITE())
  f8 = draw.controlling(on_b, draw.status(hit, f7))
  f9 = draw.inside(inside(mx, my, ax, ay, 120.0, 70.0) && on_b, "Mouse inside ellipse A", J.Color.BLUE(), f8)
  f10 = draw.inside(inside(mx, my, bx, by, 90.0, 140.0) && Bool.not(on_b), "Mouse inside ellipse B", J.Color.GREEN(), f9)
  J.Draw.text(f10, "Press [A] or [B] to switch control", 20.0, 20.0, 20.0, J.Color.GRAY())

def draw.checked(+libm: M.Libm, +a: M.Vector2, +b: M.Vector2, +on_b: Bool, +mouse: M.Vector2, collision: Maybe<Bool>, frame: J.Frame) -> J.Frame:
  match collision:
    case None{}: J.Frame.refuse(frame)
    case Some{+hit}: draw.scene(libm, a, b, on_b, mouse, hit, frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+a, +b, +on_b} = state
  (core, (State{a, b, on_b}, draw.checked(libm, a, b, on_b, J.Input.get_mouse_position(core), collide(libm, a, b), frame)))

# The main loop's body; libm is the profile of atan2f, sinf/cosf, DrawEllipse
# and DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): SetTargetFPS(60), A at (screenWidth/4,
# screenHeight/2), B at (screenWidth*3/4, screenHeight/2), A controlled.
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{M.Vector2{(800.0 / 4.0 : F32), (450.0 / 2.0 : F32)},
    M.Vector2{(800.0 * 3.0 / 4.0 : F32), (450.0 / 2.0 : F32)}, False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - ellipse collision", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
