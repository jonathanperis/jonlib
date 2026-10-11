# raylib [shapes] example - splines drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_splines_drawing.c (zlib/libpng,
# Copyright (c) 2023-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A spline through up to 32 points, as a linear, basis, Catmull-Rom or cubic
# Bezier one (keys 1 to 4 or a raygui dropdown box, Jongui). The points are
# dragged with the left button and added with the right one; the Bezier
# spline has two control points a segment, dragged the same way. A slider
# sets the thickness and a check box hides the point helpers. The circles
# and the curves follow the libm profile. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# The two control points of a cubic Bezier segment.
type Control is Data:
  Control{start: M.Vector2, end: M.Vector2}

# selected and focused are point indices; the control ones are 2*segment for a
# start and 2*segment + 1 for an end. 4294967295 is none (-1 and NULL).
type State is Data:
  State{gui: G.Gui, points: +List<M.Vector2>, controls: +List<Control>, selected: U32, focused: U32, selected_control: U32, focused_control: U32, thick: F32, kind: U32, edit: Bool, helpers: Bool}

def count(points: +List<M.Vector2>, +n: U32) -> U32:
  match points:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def last(points: +List<M.Vector2>, +fallback: M.Vector2) -> M.Vector2:
  match points:
    case Nil{}: fallback
    case Con{+p, rest}: last(rest, p)

# control.start = (a.x + 50, a.y), control.end = (b.x - 50, b.y).
def between(a: M.Vector2, b: M.Vector2) -> Control:
  M.Vector2{ax, ay} = a
  M.Vector2{bx, by} = b
  Control{M.Vector2{(ax + 50.0 : F32), ay}, M.Vector2{(bx - 50.0 : F32), by}}

def put(points: +List<M.Vector2>, +index: U32, +value: M.Vector2) -> +List<M.Vector2>:
  match points:
    case Nil{}: Nil{}
    case Con{+p, +rest}: Bool.pick(+List<M.Vector2>, U32.is_eq(index, 0), Con{value, rest}, Con{p, put(rest, (index - 1 : U32), value)})

def control.with(c: Control, +start: Bool, +value: M.Vector2) -> Control:
  Control{+a, +b} = c
  Bool.pick(Control, start, Control{value, b}, Control{a, value})

def control.put(controls: +List<Control>, +code: U32, +value: M.Vector2) -> +List<Control>:
  match controls:
    case Nil{}: Nil{}
    case Con{+c, +rest}: Bool.pick(+List<Control>, (code < 2 : U32), Con{control.with(c, U32.is_eq(code, 0), value), rest}, Con{c, control.put(rest, (code - 2 : U32), value)})

# The first point within 8 pixels of the pointer.
def focus.point(points: +List<M.Vector2>, +mouse: M.Vector2, +i: U32) -> U32:
  match points:
    case Nil{}: 4294967295
    case Con{+p, rest}: Bool.pick(U32, J.Collision.point_circle(mouse, p, 8.0), i, focus.point(rest, mouse, (i + 1 : U32)))

def focus.control.at(c: Control, +mouse: M.Vector2, +code: U32, +later: U32) -> U32:
  Control{+a, +b} = c
  Bool.pick(U32, J.Collision.point_circle(mouse, a, 6.0), code, Bool.pick(U32, J.Collision.point_circle(mouse, b, 6.0), (code + 1 : U32), later))

# The first control point within 6 pixels of the pointer, a segment's start before its end.
def focus.control(controls: +List<Control>, +mouse: M.Vector2, +code: U32) -> U32:
  match controls:
    case Nil{}: 4294967295
    case Con{+c, rest}: focus.control.at(c, mouse, code, focus.control(rest, mouse, (code + 2 : U32)))

# The loop's update: a right press adds a point at the pointer; a point (or,
# for the Bezier spline with no point focused, a control point) under the
# pointer is focused, selected by a left press and follows the pointer until
# the release; keys 1 to 4 choose the spline.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+gui, +points, +controls, +selected, +focused, +selected_control, +focused_control, +thick, +kind, +edit, +helpers} = state
  +mouse = J.Input.get_mouse_position(core)
  +pressed = J.Input.is_mouse_button_pressed(core, 0)
  +released = J.Input.is_mouse_button_released(core, 0)
  +add = J.Input.is_mouse_button_pressed(core, 1) && (count(points, 0) < 32 : U32)
  +points1 = Bool.pick(+List<M.Vector2>, add, List.append(&2, M.Vector2, points, [mouse]), points)
  +controls1 = Bool.pick(+List<Control>, add, List.append(&2, Control, controls, [between(last(points, mouse), mouse)]), controls)
  +seek = U32.is_eq(selected, 4294967295) && (U32.is_ne(kind, 3) || U32.is_eq(selected_control, 4294967295))
  +focused1 = Bool.pick(U32, seek, focus.point(points1, mouse, 0), focused)
  +selected1 = Bool.pick(U32, seek && pressed, focused1, selected)
  +moving = U32.is_ne(selected1, 4294967295)
  +points2 = Bool.pick(+List<M.Vector2>, moving, put(points1, selected1, mouse), points1)
  +selected2 = Bool.pick(U32, moving && released, 4294967295, selected1)
  +bezier = U32.is_eq(kind, 3) && U32.is_eq(focused1, 4294967295)
  +free = bezier && U32.is_eq(selected_control, 4294967295)
  +focused_control1 = Bool.pick(U32, free, focus.control(controls1, mouse, 0), focused_control)
  +selected_control1 = Bool.pick(U32, free && pressed, focused_control1, selected_control)
  +dragging = bezier && U32.is_ne(selected_control1, 4294967295)
  +controls2 = Bool.pick(+List<Control>, dragging, control.put(controls1, selected_control1, mouse), controls1)
  +selected_control2 = Bool.pick(U32, dragging && released, 4294967295, selected_control1)
  +one = J.Input.is_key_pressed(core, 49)
  +two = J.Input.is_key_pressed(core, 50)
  +three = J.Input.is_key_pressed(core, 51)
  +kind1 = Bool.pick(U32, one, 0, Bool.pick(U32, two, 1, Bool.pick(U32, three, 2, Bool.pick(U32, J.Input.is_key_pressed(core, 52), 3, kind))))
  (core, State{gui, points2, controls2, selected2, focused1, Bool.pick(U32, one || two || three, 4294967295, selected_control2), focused_control1, thick, kind1, edit, helpers})

def interleaved.one(p: M.Vector2, c: Control, tail: +List<M.Vector2>) -> +List<M.Vector2>:
  Control{a, b} = c
  Con{p, Con{a, Con{b, tail}}}

# Each point followed by its segment's two control points, and the last point.
def interleaved(points: +List<M.Vector2>, controls: +List<Control>) -> +List<M.Vector2>:
  match points controls:
    case Con{+p, rest} Con{+c, more}: interleaved.one(p, c, interleaved(rest, more))
    case Con{+p, _} Nil{}: [p]
    case _ _: Nil{}

def marked(which: U32, +libm: M.Libm, +a: M.Vector2, +b: M.Vector2, frame: J.Frame) -> J.Frame:
  match which:
    case 0: frame
    case 1: J.Draw.circle_v_for(libm, frame, a, 8.0, J.Color.GREEN())
    case _: J.Draw.circle_v_for(libm, frame, b, 8.0, J.Color.GREEN())

# A segment's control points (the focused one larger and green) and the lines to their points.
def handle(c: Control, +p: M.Vector2, +q: M.Vector2, +libm: M.Libm, +code: U32, +focused: U32, frame: J.Frame) -> J.Frame:
  Control{+a, +b} = c
  f1 = J.Draw.circle_v_for(libm, frame, a, 6.0, J.Color.GOLD())
  f2 = J.Draw.circle_v_for(libm, f1, b, 6.0, J.Color.GOLD())
  f3 = marked(Bool.pick(U32, U32.is_eq(focused, code), 1, Bool.pick(U32, U32.is_eq(focused, (code + 1 : U32)), 2, 0)), libm, a, b, f2)
  f4 = J.Draw.line_ex(f3, p, a, 1.0, J.Color.LIGHTGRAY())
  f5 = J.Draw.line_ex(f4, q, b, 1.0, J.Color.LIGHTGRAY())
  f6 = J.Draw.line_v(f5, p, a, J.Color.GRAY())
  J.Draw.line_v(f6, b, q, J.Color.GRAY())

def handles(points: +List<M.Vector2>, controls: +List<Control>, +libm: M.Libm, +code: U32, +focused: U32, frame: J.Frame) -> J.Frame:
  match points controls:
    case Con{+p, Con{+q, +rest}} Con{+c, more}: handles(Con{q, rest}, more, libm, (code + 2 : U32), focused, handle(c, p, q, libm, code, focused, frame))
    case _ _: frame

def spline(kind: U32, +libm: M.Libm, +points: +List<M.Vector2>, +controls: +List<Control>, +thick: F32, +focused_control: U32, frame: J.Frame) -> J.Frame:
  match kind:
    case 0: J.Draw.spline_linear(frame, points, thick, J.Color.RED())
    case 1: J.Draw.spline_basis_for(libm, frame, points, thick, J.Color.RED())
    case 2: J.Draw.spline_catmull_rom_for(libm, frame, points, thick, J.Color.RED())
    case 3: handles(points, controls, libm, 0, focused_control, J.Draw.spline_bezier_cubic_for(libm, frame, interleaved(points, controls), thick, J.Color.RED()))
    case _: frame

# DrawText(TextFormat("[%.0f, %.0f]", x, y), (int)x, (int)y + 10, 10, BLACK).
def helper.text(text: Maybe<String>, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, F32.trunc(x), (F32.trunc(y) + 10.0 : F32), 10.0, J.Color.BLACK())

def helper.link(next: +List<M.Vector2>, +p: M.Vector2, frame: J.Frame) -> J.Frame:
  match next:
    case Nil{}: frame
    case Con{q, _}: J.Draw.line_v(frame, p, q, J.Color.GRAY())

def helper.linked(linked: Bool, +p: M.Vector2, +next: +List<M.Vector2>, frame: J.Frame) -> J.Frame:
  match linked:
    case False{}: frame
    case True{}: helper.link(next, p, frame)

# A point's circle (larger and blue when focused), the line to the next
# point for the basis and Catmull-Rom splines, and its coordinates.
def helper(+p: M.Vector2, +rest: +List<M.Vector2>, +libm: M.Libm, +hot: Bool, +linked: Bool, frame: J.Frame) -> J.Frame:
  M.Vector2{+x, +y} = p
  f1 = J.Draw.circle_lines_v_for(libm, frame, p, Bool.pick(F32, hot, 12.0, 8.0), Bool.pick(U32, hot, J.Color.BLUE(), J.Color.DARKBLUE()))
  helper.text(J.Text.format("[%.0f, %.0f]", [J.TextFloat{x}, J.TextFloat{y}]), x, y, helper.linked(linked, p, rest, f1))

def helpers.go(points: +List<M.Vector2>, +libm: M.Libm, +i: U32, +focused: U32, +linked: Bool, frame: J.Frame) -> J.Frame:
  match points:
    case Nil{}: frame
    case Con{+p, +rest}: helpers.go(rest, libm, (i + 1 : U32), focused, linked, helper(p, rest, libm, U32.is_eq(i, focused), linked, frame))

def helpers(shown: Bool, +points: +List<M.Vector2>, +libm: M.Libm, +focused: U32, +kind: U32, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: helpers.go(points, libm, 0, focused, U32.is_ne(kind, 0) && U32.is_ne(kind, 3), frame)

def with_gui(state: State, gui: G.Gui) -> State:
  State{_, points, controls, selected, focused, selected_control, focused_control, thick, kind, edit, helpers} = state
  State{gui, points, controls, selected, focused, selected_control, focused_control, thick, kind, edit, helpers}

def with_thick(state: State, gui: G.Gui, thick: F32) -> State:
  State{_, points, controls, selected, focused, selected_control, focused_control, _, kind, edit, helpers} = state
  State{gui, points, controls, selected, focused, selected_control, focused_control, thick, kind, edit, helpers}

def with_helpers(state: State, helpers: Bool) -> State:
  State{gui, points, controls, selected, focused, selected_control, focused_control, thick, kind, edit, _} = state
  State{gui, points, controls, selected, focused, selected_control, focused_control, thick, kind, edit, helpers}

# The dropdown's result: the active item, and the edit mode flipped when raygui answers true.
def with_kind(state: State, pair: U32 & Bool) -> State:
  State{gui, points, controls, selected, focused, selected_control, focused_control, thick, _, +edit, helpers} = state
  (kind, +flip) = pair
  State{G.Gui.unlock(gui), points, controls, selected, focused, selected_control, focused_control, thick, kind, Bool.pick(Bool, flip, Bool.not(edit), edit), helpers}

def gui_of(state: State) -> G.Gui:
  State{gui, _, _, _, _, _, _, _, _, _, _} = state
  gui

def thick_of(state: State) -> F32:
  State{_, _, _, _, _, _, _, thick, _, _, _} = state
  thick

def kind_of(state: State) -> U32:
  State{_, _, _, _, _, _, _, _, kind, _, _} = state
  kind

def edit_of(state: State) -> Bool:
  State{_, _, _, _, _, _, _, _, _, edit, _} = state
  edit

def helpers_of(state: State) -> Bool:
  State{_, _, _, _, _, _, _, _, _, _, helpers} = state
  helpers

def first(pair: F32 & Bool) -> F32:
  (value, _) = pair
  value

def checked(pair: Bool & Bool) -> Bool:
  (value, _) = pair
  value

def ui.type(+core: J.Core, +state: State, r: J.Frame & (U32 & Bool)) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  (core, (with_kind(state, pair), frame))

# if (splineTypeEditMode) GuiUnlock(); the label, the dropdown box, GuiUnlock().
def ui.box.to(+core: J.Core, +state: State, +gui: G.Gui, frame: J.Frame) -> J.Core & (State & J.Frame):
  ui.type(core, with_gui(state, gui), G.Gui.dropdown_box(gui, core, G.Gui.label(gui, frame, J.Rectangle{12.0, 10.0, 140.0, 24.0}, "Spline type:"),
    J.Rectangle{12.0, 32.0, 140.0, 28.0}, "LINEAR;BSPLINE;CATMULLROM;BEZIER", kind_of(state), edit_of(state)))

def ui.box(+core: J.Core, +state: State, r: J.Frame & (Bool & Bool)) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  ui.box.to(core, with_helpers(state, checked(pair)), Bool.pick(G.Gui, edit_of(state), G.Gui.unlock(gui_of(state)), gui_of(state)), frame)

def ui.bar.to(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  ui.box(core, state, G.Gui.check_box(gui_of(state), core, frame, J.Rectangle{12.0, 110.0, 20.0, 20.0}, "Show point helpers", helpers_of(state)))

def ui.bar.rest(+core: J.Core, +state: State, frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> J.Core & (State & J.Frame):
  (gui, pair) = rest
  ui.bar.to(core, with_thick(state, gui, first(pair)), frame)

def ui.bar(+core: J.Core, +state: State, r: J.Frame & (G.Gui & (F32 & Bool))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  ui.bar.rest(core, state, frame, rest)

# The thickness label and its slider bar, with the gui locked while the
# dropdown is open or something is being dragged.
def ui.label(text: Maybe<String>, +core: J.Core, +state: State, +gui: G.Gui, frame: J.Frame) -> J.Core & (State & J.Frame):
  match text:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{t}: ui.bar(core, state, G.Gui.slider_bar(gui, core, G.Gui.label(gui, frame, J.Rectangle{12.0, 62.0, 140.0, 24.0}, t), J.Rectangle{12.0, 84.0, 140.0, 16.0}, None{}, None{}, thick_of(state), 1.0, 40.0))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +points, +controls, +selected, +focused, +selected_control, +focused_control, +thick, +kind, +edit, +shown} = state
  f1 = spline(kind, libm, points, controls, thick, focused_control, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = helpers(shown, points, libm, focused, kind, f1)
  +locked = edit || U32.is_ne(selected, 4294967295) || U32.is_ne(selected_control, 4294967295)
  ui.label(J.Text.format("Spline thickness: %i", [J.TextInt{F32.to_u32(F32.trunc(thick))}]), core, state, Bool.pick(G.Gui, locked, G.Gui.lock(gui), gui), f2)

# The main loop's body; libm is the profile of raylib's sinf/cosf and powf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def v(+x: F32, +y: F32) -> M.Vector2:
  M.Vector2{x, y}

# SetConfigFlags(FLAG_MSAA_4X_HINT) before InitWindow: Desktop.run_flags.
# After InitWindow(800, 450): five points with their control points, a
# linear spline 8 thick, the helpers shown, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), [v(50.0, 400.0), v(160.0, 220.0), v(340.0, 380.0), v(520.0, 60.0), v(710.0, 260.0)],
    [between(v(50.0, 400.0), v(160.0, 220.0)), between(v(160.0, 220.0), v(340.0, 380.0)), between(v(340.0, 380.0), v(520.0, 60.0)), between(v(520.0, 60.0), v(710.0, 260.0))],
    4294967295, 4294967295, 4294967295, 4294967295, 8.0, 0, False{}, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [shapes] example - splines drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
