# raylib [shapes] example - drag puzzle, ported to Jonlib.
# Adapted from raylib 6.2 examples/shapes/shapes_drag_puzzle.c (zlib/libpng,
# Copyright (c) 2026 Gabriel Piangers (@gabriel-piangers)); see LICENSES/raylib.txt.
#
# Drag a rectangle, a circle and a triangle into their outlined areas; an
# area turns green while its object fits inside. An object is picked up when
# the left button is pressed over it (rectangle first, then circle, then
# triangle) and dropped when the button is released (one object per
# release). The circles are DrawCircleV and DrawCircleLinesEx (DrawRing) at
# whole multiples of 10 degrees, which every libm profile reproduces: no
# frame is refused. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The rectangle's corner, the circle's center and the triangle's vertices
# (v1 = a, v2 = b, v3 = q), each with its picked-up flag; the pickup offset
# (mouseOffset) and this frame's placed flags. The rectangle is 100x100 and
# the circle's radius 50 throughout.
type State is Data:
  State{rx: F32, ry: F32, rec_up: Bool, cx: F32, cy: F32, circ_up: Bool, ax: F32, ay: F32, bx: F32, by: F32, qx: F32, qy: F32,
    tri_up: Bool, ox: F32, oy: F32, rec_placed: Bool, circ_placed: Bool, tri_placed: Bool}

# recArea = { screenWidth/2 - 60, screenHeight/2 - 110, 110, 110 }
def rec_area() -> J.Rectangle:
  J.Rectangle{340.0, 115.0, 110.0, 110.0}

# circArea = { { screenWidth/2 - 195, screenHeight/2 - 55 }, 55 }
def circ_area() -> M.Vector2:
  M.Vector2{205.0, 170.0}

# triArea = { { 600, 115 }, { 540, 222 }, { 660, 222 } }
def in_tri_area(+x: F32, +y: F32) -> Bool:
  J.Collision.point_triangle(M.Vector2{x, y}, M.Vector2{600.0, 115.0}, M.Vector2{540.0, 222.0}, M.Vector2{660.0, 222.0})

# RecCol = GetCollisionRec(recArea, rec); placed when RecCol's size is rec's.
def rec.fits(+overlap: J.Rectangle) -> Bool:
  J.Rectangle{_, _, +w, +h} = overlap
  F32.is_eq(w, 100.0) && F32.is_eq(h, 100.0)

# The update after the pickup tests: the drop (one object per release, in the
# C's else-if order), the moves by the mouse plus the offset, and the placed
# tests. The triangle keeps its shape: v2 and v3 follow v1 by their offsets.
def update.moved(+mx: F32, +my: F32, +released: Bool, +r1: Bool, +c1: Bool, +t1: Bool, +ox: F32, +oy: F32,
    +rx: F32, +ry: F32, +cx: F32, +cy: F32, +ax: F32, +ay: F32, +bx: F32, +by: F32, +qx: F32, +qy: F32) -> State:
  +r2 = r1 && Bool.not(released)
  +c2 = c1 && Bool.not(released && Bool.not(r1))
  +t2 = t1 && Bool.not(released && Bool.not(r1) && Bool.not(c1))
  +nrx = Bool.pick(F32, r2, (mx + ox : F32), rx)
  +nry = Bool.pick(F32, r2, (my + oy : F32), ry)
  +ncx = Bool.pick(F32, c2, (mx + ox : F32), cx)
  +ncy = Bool.pick(F32, c2, (my + oy : F32), cy)
  +nax = Bool.pick(F32, t2, (mx + ox : F32), ax)
  +nay = Bool.pick(F32, t2, (my + oy : F32), ay)
  +nbx = Bool.pick(F32, t2, (nax + (bx - ax) : F32), bx)
  +nby = Bool.pick(F32, t2, (nay + (by - ay) : F32), by)
  +nqx = Bool.pick(F32, t2, (nax + (qx - ax) : F32), qx)
  +nqy = Bool.pick(F32, t2, (nay + (qy - ay) : F32), qy)
  +rec_placed = rec.fits(J.Collision.rectangle(rec_area(), J.Rectangle{nrx, nry, 100.0, 100.0}))
  +circ_placed = (M.Vector2.distance(M.Vector2{ncx, ncy}, circ_area()) < (55.0 - 50.0) : F32)
  # The C tests v1, v2 and v2 again (not v3).
  +tri_placed = in_tri_area(nax, nay) && in_tri_area(nbx, nby) && in_tri_area(nbx, nby)
  State{nrx, nry, r2, ncx, ncy, c2, nax, nay, nbx, nby, nqx, nqy, t2, ox, oy, rec_placed, circ_placed, tri_placed}

# The pickup: IsMouseButtonPressed and the rectangle, else the circle, else
# the triangle under the mouse (their positions of the previous frame); the
# offset is the picked object's pivot (rec's corner, the center, v1) minus
# the mouse.
def update.step(+state: State, +mouse: M.Vector2, +pressed: Bool, +released: Bool) -> State:
  State{+rx, +ry, +rec_up, +cx, +cy, +circ_up, +ax, +ay, +bx, +by, +qx, +qy, +tri_up, +ox, +oy, _, _, _} = state
  M.Vector2{+mx, +my} = mouse
  +hit_rec = pressed && J.Collision.point_rec(M.Vector2{mx, my}, J.Rectangle{rx, ry, 100.0, 100.0})
  +hit_circ = pressed && Bool.not(hit_rec) && J.Collision.point_circle(M.Vector2{mx, my}, M.Vector2{cx, cy}, 50.0)
  +hit_tri = pressed && Bool.not(hit_rec) && Bool.not(hit_circ)
    && J.Collision.point_triangle(M.Vector2{mx, my}, M.Vector2{ax, ay}, M.Vector2{bx, by}, M.Vector2{qx, qy})
  +nox = Bool.pick(F32, hit_rec, (rx - mx : F32), Bool.pick(F32, hit_circ, (cx - mx : F32), Bool.pick(F32, hit_tri, (ax - mx : F32), ox)))
  +noy = Bool.pick(F32, hit_rec, (ry - my : F32), Bool.pick(F32, hit_circ, (cy - my : F32), Bool.pick(F32, hit_tri, (ay - my : F32), oy)))
  update.moved(mx, my, released, rec_up || hit_rec, circ_up || hit_circ, tri_up || hit_tri, nox, noy, rx, ry, cx, cy, ax, ay, bx, by, qx, qy)

# On the reference platform IsMouseButtonReleased only fires for a touch
# point (a mouse button's previous state is never registered), and
# IsMouseButtonPressed fires every frame a mouse button is held: J.Input
# answers the same.
def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, update.step(state, J.Input.get_mouse_position(core),
    J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()),
    J.Input.is_mouse_button_released(core, J.MouseButton.MOUSE_BUTTON_LEFT())))

def draw.tri(show: Bool, +ax: F32, +ay: F32, +bx: F32, +by: F32, +qx: F32, +qy: F32, frame: J.Frame) -> J.Frame:
  match show:
    case False{}: frame
    case True{}: J.Draw.triangle(frame, M.Vector2{ax, ay}, M.Vector2{bx, by}, M.Vector2{qx, qy}, J.Color.VIOLET())

def draw.circ(show: Bool, +libm: M.Libm, +cx: F32, +cy: F32, frame: J.Frame) -> J.Frame:
  match show:
    case False{}: frame
    case True{}: J.Draw.circle_v_for(libm, frame, M.Vector2{cx, cy}, 50.0, J.Color.BLUE())

def draw.rec(show: Bool, +rx: F32, +ry: F32, frame: J.Frame) -> J.Frame:
  match show:
    case False{}: frame
    case True{}: J.Draw.rectangle_rec(frame, J.Rectangle{rx, ry, 100.0, 100.0}, J.Color.ORANGE())

def placed.color(+ok: Bool) -> U32:
  Bool.pick(U32, ok, J.Color.GREEN(), J.Color.RED())

def draw.scene(+libm: M.Libm, +state: State, frame: J.Frame) -> J.Frame:
  State{+rx, +ry, +rec_up, +cx, +cy, +circ_up, +ax, +ay, +bx, +by, +qx, +qy, +tri_up, _, _, +rec_placed, +circ_placed, +tri_placed} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.rectangle_lines_ex(f1, rec_area(), 2.0, placed.color(rec_placed))
  f3 = J.Draw.circle_lines_ex_for(libm, f2, circ_area(), 55.0, 2.0, placed.color(circ_placed))
  f4 = J.Draw.triangle_lines_ex(f3, M.Vector2{600.0, 115.0}, M.Vector2{540.0, 222.0}, M.Vector2{660.0, 222.0}, 2.0, placed.color(tri_placed))
  # The objects not picked up first, then the dragged ones on top.
  f5 = draw.tri(Bool.not(tri_up), ax, ay, bx, by, qx, qy, f4)
  f6 = draw.circ(Bool.not(circ_up), libm, cx, cy, f5)
  f7 = draw.rec(Bool.not(rec_up), rx, ry, f6)
  f8 = draw.tri(tri_up, ax, ay, bx, by, qx, qy, f7)
  f9 = draw.circ(circ_up, libm, cx, cy, f8)
  f10 = draw.rec(rec_up, rx, ry, f9)
  J.Draw.text(f10, "Use mouse to drag and drop the objects into the right spot!", 10.0, 10.0, 20.0, J.Color.GRAY())

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, (state, draw.scene(libm, state, frame)))

# The main loop's body; libm is the profile of DrawCircleV and DrawCircleLinesEx.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): rec (150, 275, 100, 100), circ ((400, 325), 50),
# tri ((600, 282), (550, 369), (650, 369)), nothing picked up, mouseOffset
# (0, 0), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{(800.0 / 2.0 - 250.0 : F32), (450.0 / 2.0 + 50.0 : F32), False{},
    (800.0 / 2.0 : F32), (450.0 / 2.0 + 100.0 : F32), False{}, 600.0, 282.0, 550.0, 369.0, 650.0, 369.0, False{},
    0.0, 0.0, False{}, False{}, False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - drag puzzle", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
