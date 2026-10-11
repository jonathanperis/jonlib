# raylib [shapes] example - pie chart, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_pie_chart.c (zlib/libpng,
# Copyright (c) 2025 Gideon Serfontein (@GideonSerf)); see LICENSES/raylib.txt.
#
# A pie chart of up to ten slices (the one under the pointer pops out), with
# raygui controls (Jongui): a spinner for the slice count, check boxes for
# the labels and the donut, a slider for the donut's radius and a scroll
# panel with a text box and a slider bar for each slice. The pointer's angle
# is the example's own atan2f and the labels its sinf/cosf, which follow the
# libm profile: where the profile does not answer, the frame is refused. See
# docs/GUI.md, docs/ANGLES.md, docs/SINCOSF.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# hovered is 4294967295 for none (-1); valid: atan2f answered this frame.
type State is Data:
  State{gui: G.Gui, editing: G.Gui.Editing, count: U32, donut: F32, values: +List<F32>, labels: +List<String>, edits: +List<Bool>, show_values: Bool, show_percent: Bool, show_donut: Bool,
    hovered: U32, scroll: M.Vector2, total: F32, valid: Bool}

# The slice editors drawn so far, their lists last one first.
type Rows is Type:
  Rows{frame: J.Frame, core: J.Core, gui: G.Gui, editing: G.Gui.Editing, labels: +List<String>, edits: +List<Bool>, values: +List<F32>}

def vx(v: M.Vector2) -> F32:
  M.Vector2{x, _} = v
  x

def vy(v: M.Vector2) -> F32:
  M.Vector2{_, y} = v
  y

def State.total(state: State) -> F32:
  State{_, _, _, _, _, _, _, _, _, _, _, _, total, _} = state
  total

def State.scroll(state: State) -> M.Vector2:
  State{_, _, _, _, _, _, _, _, _, _, _, scroll, _, _} = state
  scroll

def State.count(state: State) -> U32:
  State{_, _, count, _, _, _, _, _, _, _, _, _, _, _} = state
  count

# totalValue += values[i] over the first n values.
def sum(n: Nat, values: +List<F32>, +acc: F32) -> F32:
  match n values:
    case 1n+p Con{+v, rest}: sum(p, rest, (acc + v : F32))
    case _ _: acc

def sweep(+v: F32, +total: F32) -> F32:
  Bool.pick(F32, (total > 0.0 : F32), ((v / total) * 360.0 : F32), 0.0)

# The first slice whose sweep holds the angle.
def hover.scan(n: Nat, values: +List<F32>, +i: U32, +angle: F32, +current: F32, +total: F32) -> U32:
  match n values:
    case 1n+p Con{+v, rest}:
      Bool.pick(U32, (angle >= current : F32) && (angle < current + sweep(v, total) : F32), i, hover.scan(p, rest, (i + 1 : U32), angle, (current + sweep(v, total) : F32), total))
    case _ _: 4294967295

def with_hover(state: State, total: F32, hovered: U32, valid: Bool) -> State:
  State{gui, editing, count, donut, values, labels, edits, show_values, show_percent, show_donut, _, scroll, _, _} = state
  State{gui, editing, count, donut, values, labels, edits, show_values, show_percent, show_donut, hovered, scroll, total, valid}

def degrees(+radians: F32) -> F32:
  (radians * (180.0 / 3.14159265358979323846) : F32)

# angle = atan2f(dy, dx)*RAD2DEG, plus 360 when negative: Vector2LineAngle of
# (0, 0) and (dx, dy) is -atan2f(dy, dx) under the profile.
def hover.angle(angle: Maybe<F32>, +state: State, +total: F32) -> State:
  match angle:
    case None{}: with_hover(state, total, 4294967295, False{})
    case Some{+a}:
      State{_, _, +count, _, +values, _, _, _, _, _, _, _, _, _} = state
      +turned = degrees(F32.neg(a))
      with_hover(state, total, hover.scan(U32.to_nat(count), values, 0, Bool.pick(F32, (turned < 0.0 : F32), (turned + 360.0 : F32), turned), 0.0, total), True{})

def hover(near: Bool, +libm: M.Libm, +dx: F32, +dy: F32, +state: State, +total: F32) -> State:
  match near:
    case False{}: with_hover(state, total, 4294967295, True{})
    case True{}: hover.angle(M.Vector2.line_angle_for(libm, M.Vector2{0.0, 0.0}, M.Vector2{dx, dy}), state, total)

# The total of the shown slices and the slice under the pointer, when it is
# over the canvas and within the pie's radius of its center.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{_, _, +count, _, +values, _, _, _, _, _, _, _, _, _} = state
  +mouse = J.Input.get_mouse_position(core)
  +dx = (vx(mouse) - 262.5 : F32)
  +dy = (vy(mouse) - 225.0 : F32)
  (core, hover(J.Collision.point_rec(mouse, J.Rectangle{0.0, 0.0, 525.0, 450.0}) && (F32.sqrt((dx * dx + dy * dy : F32)) <= 205.0 : F32), libm, dx, dy, state, sum(U32.to_nat(count), values, 0.0)))

# ColorFromHSV((float)i/sliceCount*360.0f, 0.75f, 0.9f).
def hue(+i: U32, +count: U32) -> U32:
  J.Color.from_hsv(((U32.to_f32(i) / U32.to_f32(count)) * 360.0 : F32), 0.75, 0.9)

def size.of(r: J.Font & M.Vector2) -> M.Vector2:
  (_, size) = r
  size

# DrawText at the slice's middle angle, 0.7 of the radius out, centered on the text's size.
def label.put(size: M.Vector2, +cos: F32, +sin: F32, text: String, frame: J.Frame) -> J.Frame:
  M.Vector2{+tx, +ty} = size
  J.Draw.text(frame, text, F32.trunc(((262.5 + cos * (205.0 * 0.7) : F32) - tx / 2.0 : F32)), F32.trunc(((225.0 + sin * (205.0 * 0.7) : F32) - ty / 2.0 : F32)), 20.0, J.Color.WHITE())

def label.at(c: Maybe<F32>, s: Maybe<F32>, +size: M.Vector2, text: String, frame: J.Frame) -> J.Frame:
  match c s:
    case Some{+cos} Some{+sin}: label.put(size, cos, sin, text, frame)
    case _ _: J.Frame.refuse(frame)

def label.made(text: Maybe<String>, +libm: M.Libm, +middle: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{+t}:
      label.at(M.Libm.cos(libm, (middle * (3.14159265358979323846 / 180.0) : F32)), M.Libm.sin(libm, (middle * (3.14159265358979323846 / 180.0) : F32)),
        size.of(J.Font.measure_text_ex(J.Font.default(), t, 20.0, 1.0)), t, frame)

# "%.1f (%.0f%%)", "%.1f" or "%.0f%%" of the value and its share.
def label.text(+values: Bool, +percent: Bool, +v: F32, +share: F32) -> Maybe<String>:
  Bool.pick(Maybe<String>, values && percent, J.Text.format("%.1f (%.0f%%)", [J.TextFloat{v}, J.TextFloat{share}]),
    Bool.pick(Maybe<String>, values, J.Text.format("%.1f", [J.TextFloat{v}]), J.Text.format("%.0f%%", [J.TextFloat{share}])))

def labeled(shown: Bool, +libm: M.Libm, +v: F32, +total: F32, +middle: F32, +values: Bool, +percent: Bool, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: label.made(label.text(values, percent, v, ((v / total) * 100.0 : F32)), libm, middle, frame)

def ringed(donut: Bool, +libm: M.Libm, +radius: F32, frame: J.Frame) -> J.Frame:
  match donut:
    case False{}: frame
    case True{}: J.Draw.circle_v_for(libm, frame, M.Vector2{262.5, 225.0}, radius, J.Color.RAYWHITE())

# One slice: its sector (20 pixels larger under the pointer), its label and the donut's hole.
def slice(+libm: M.Libm, +v: F32, +i: U32, +start: F32, +state: State, frame: J.Frame) -> J.Frame:
  State{_, _, +count, +donut, _, _, _, +show_values, +show_percent, +show_donut, +hovered, _, +total, _} = state
  f1 = J.Draw.circle_sector_for(libm, frame, M.Vector2{262.5, 225.0}, Bool.pick(F32, U32.is_eq(i, hovered), (205.0 + 20.0 : F32), 205.0), start, (start + sweep(v, total) : F32), 120.0, hue(i, count))
  ringed(show_donut, libm, donut, labeled((v > 0.0 : F32) && (show_values || show_percent), libm, v, total, (start + sweep(v, total) / 2.0 : F32), show_values, show_percent, f1))

def slices(n: Nat, values: +List<F32>, +libm: M.Libm, +i: U32, +start: F32, +state: State, frame: J.Frame) -> J.Frame:
  match n values:
    case 1n+p Con{+v, rest}: slices(p, rest, libm, (i + 1 : U32), (start + sweep(v, State.total(state)) : F32), state, slice(libm, v, i, start, state, frame))
    case _ _: frame

def first(pair: F32 & Bool) -> F32:
  (value, _) = pair
  value

def row.slid(rest: G.Gui & (F32 & Bool), frame: J.Frame, +core: J.Core, +editing: G.Gui.Editing, +label: String, +edit: Bool, +labels: +List<String>, +edits: +List<Bool>, +values: +List<F32>) -> Rows:
  (+gui, pair) = rest
  Rows{frame, core, gui, editing, Con{label, labels}, Con{edit, edits}, Con{first(pair), values}}

def row.bar(r: J.Frame & (G.Gui & (F32 & Bool)), +core: J.Core, +editing: G.Gui.Editing, +label: String, +edit: Bool, +labels: +List<String>, +edits: +List<Bool>, +values: +List<F32>) -> Rows:
  (frame, rest) = r
  row.slid(rest, frame, core, editing, label, edit, labels, edits, values)

# The text box's result flips the row's edit mode; then the value's slider bar.
def row.pair(pair: G.Gui.Editing & Bool, +label: String, +core: J.Core, frame: J.Frame, +gui: G.Gui, +edit: Bool, +value: F32, +x: F32, +y: F32, +labels: +List<String>, +edits: +List<Bool>, +values: +List<F32>) -> Rows:
  (+editing, +toggled) = pair
  row.bar(G.Gui.slider_bar(gui, core, frame, J.Rectangle{(x + 130.0 : F32), y, 110.0, 30.0}, None{}, None{}, value, 0.0, 1000.0), core, editing, label, Bool.pick(Bool, toggled, Bool.not(edit), edit), labels, edits, values)

def row.text(more: String & (G.Gui.Editing & Bool), +core: J.Core, frame: J.Frame, +gui: G.Gui, +edit: Bool, +value: F32, +x: F32, +y: F32, +labels: +List<String>, +edits: +List<Bool>, +values: +List<F32>) -> Rows:
  (+label, pair) = more
  row.pair(pair, label, core, frame, gui, edit, value, x, y, labels, edits, values)

def row.core(rest: J.Core & (String & (G.Gui.Editing & Bool)), frame: J.Frame, +gui: G.Gui, +edit: Bool, +value: F32, +x: F32, +y: F32, +labels: +List<String>, +edits: +List<Bool>, +values: +List<F32>) -> Rows:
  (+core, more) = rest
  row.text(more, core, frame, gui, edit, value, x, y, labels, edits, values)

def row.box(r: J.Frame & (J.Core & (String & (G.Gui.Editing & Bool))), +gui: G.Gui, +edit: Bool, +value: F32, +x: F32, +y: F32, +labels: +List<String>, +edits: +List<Bool>, +values: +List<F32>) -> Rows:
  (frame, rest) = r
  row.core(rest, frame, gui, edit, value, x, y, labels, edits, values)

# A slice's editor at rowY = (int)(contentY + 5 + i*35): its color, its label's text box and its value's slider bar.
def row(rows: Rows, +i: U32, +count: U32, +label: String, +edit: Bool, +value: F32, +cx: F32, +cy: F32) -> Rows:
  Rows{frame, +core, +gui, +editing, +labels, +edits, +values} = rows
  +y = F32.trunc(((cy + 5.0 : F32) + U32.to_f32((i * 35 : U32)) : F32))
  row.box(G.Gui.text_box(gui, core, J.Draw.rectangle(frame, F32.trunc((cx + 15.0 : F32)), (y + 5.0 : F32), 20.0, 20.0, hue(i, count)), J.Rectangle{(cx + 45.0 : F32), y, 75.0, 30.0}, label, 32, edit, editing),
    gui, edit, value, cx, y, labels, edits, values)

def row.kept(rows: Rows, +label: String, +edit: Bool, +value: F32) -> Rows:
  Rows{frame, core, gui, editing, labels, edits, values} = rows
  Rows{frame, core, gui, editing, Con{label, labels}, Con{edit, edits}, Con{value, values}}

def row.one(active: Bool, rows: Rows, +i: U32, +count: U32, +label: String, +edit: Bool, +value: F32, +cx: F32, +cy: F32) -> Rows:
  match active:
    case False{}: row.kept(rows, label, edit, value)
    case True{}: row(rows, i, count, label, edit, value, cx, cy)

# The first count rows are drawn; the others keep their label, flag and value.
def rows.go(labels: +List<String>, edits: +List<Bool>, values: +List<F32>, +i: U32, +count: U32, +cx: F32, +cy: F32, rows: Rows) -> Rows:
  match labels edits values:
    case Con{+label, rest} Con{+edit, more} Con{+value, others}: rows.go(rest, more, others, (i + 1 : U32), count, cx, cy, row.one((i < count : U32), rows, i, count, label, edit, value, cx, cy))
    case _ _ _: rows

def with_gui(state: State, gui: G.Gui) -> State:
  State{_, editing, count, donut, values, labels, edits, show_values, show_percent, show_donut, hovered, scroll, total, valid} = state
  State{gui, editing, count, donut, values, labels, edits, show_values, show_percent, show_donut, hovered, scroll, total, valid}

def with_count(state: State, count: U32) -> State:
  State{gui, editing, _, donut, values, labels, edits, show_values, show_percent, show_donut, hovered, scroll, total, valid} = state
  State{gui, editing, count, donut, values, labels, edits, show_values, show_percent, show_donut, hovered, scroll, total, valid}

def with_flags(state: State, show_values: Bool, show_percent: Bool, show_donut: Bool) -> State:
  State{gui, editing, count, donut, values, labels, edits, _, _, _, hovered, scroll, total, valid} = state
  State{gui, editing, count, donut, values, labels, edits, show_values, show_percent, show_donut, hovered, scroll, total, valid}

def with_donut(state: State, gui: G.Gui, donut: F32) -> State:
  State{_, editing, count, _, values, labels, edits, show_values, show_percent, show_donut, hovered, scroll, total, valid} = state
  State{gui, editing, count, donut, values, labels, edits, show_values, show_percent, show_donut, hovered, scroll, total, valid}

def refused(valid: Bool, frame: J.Frame) -> J.Frame:
  match valid:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# EndScissorMode, and the rows' lists back in order.
def ui.rows(rows: Rows, +state: State, +scroll: M.Vector2) -> J.Core & (State & J.Frame):
  Rows{frame, +core, +gui, +editing, +labels, +edits, +values} = rows
  State{_, _, +count, +donut, _, _, _, +show_values, +show_percent, +show_donut, +hovered, _, +total, +valid} = state
  (core, (State{gui, editing, count, donut, List.reverse(&2, F32, values), List.reverse(&2, String, labels), List.reverse(&2, Bool, edits), show_values, show_percent, show_donut, hovered, scroll, total, valid},
    refused(valid, J.Frame.end_scissor_mode(frame))))

# The slice editors inside the view, placed by the scroll offset.
def ui.view(more: M.Vector2 & J.Rectangle, +gui: G.Gui, +core: J.Core, frame: J.Frame, +state: State) -> J.Core & (State & J.Frame):
  (+scroll, +view) = more
  J.Rectangle{+rx, +ry, +rw, +rh} = view
  State{_, +editing, +count, _, +values, +labels, +edits, _, _, _, _, _, _, _} = state
  ui.rows(rows.go(labels, edits, values, 0, count, (rx + vx(scroll) : F32), (ry + vy(scroll) : F32),
    Rows{J.Frame.begin_scissor_mode(frame, F32.trunc(rx), F32.trunc(ry), F32.trunc(rw), F32.trunc(rh)), core, gui, editing, Nil{}, Nil{}, Nil{}}), state, scroll)

def ui.pane.rest(rest: G.Gui & (M.Vector2 & J.Rectangle), +core: J.Core, frame: J.Frame, +state: State) -> J.Core & (State & J.Frame):
  (+gui, more) = rest
  ui.view(more, gui, core, frame, state)

def ui.pane(r: J.Frame & (G.Gui & (M.Vector2 & J.Rectangle)), +core: J.Core, +state: State) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  ui.pane.rest(rest, core, frame, state)

# GuiEnable(), the rule and the scroll panel over sliceCount rows of 35 pixels.
def ui.donut.rest(rest: G.Gui & (F32 & Bool), +core: J.Core, frame: J.Frame, +state: State) -> J.Core & (State & J.Frame):
  (+slid, pair) = rest
  +gui = G.Gui.enable(slid)
  ui.pane(G.Gui.scroll_panel(gui, core, G.Gui.line(gui, frame, J.Rectangle{535.0, 187.0, 250.0, 1.0}, None{}), J.Rectangle{530.0, 207.0, 260.0, 637.0}, None{},
    J.Rectangle{0.0, 0.0, 245.0, U32.to_f32((State.count(state) * 35 : U32))}, State.scroll(state)), core, with_donut(state, gui, first(pair)))

def ui.donut(r: J.Frame & (G.Gui & (F32 & Bool)), +core: J.Core, +state: State) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  ui.donut.rest(rest, core, frame, state)

def checked.at(frame: J.Frame, pair: Bool & Bool) -> J.Frame & Bool:
  (value, _) = pair
  (frame, value)

def checked(r: J.Frame & (Bool & Bool)) -> J.Frame & Bool:
  (frame, pair) = r
  checked.at(frame, pair)

# The donut's check box, then its radius slider (disabled while the donut is shown).
def ui.third(r: J.Frame & Bool, +core: J.Core, +state: State, +show_values: Bool, +show_percent: Bool) -> J.Core & (State & J.Frame):
  (frame, +show_donut) = r
  State{+gui, _, _, +donut, _, _, _, _, _, _, _, _, _, _} = state
  ui.donut(G.Gui.slider_bar(Bool.pick(G.Gui, show_donut, G.Gui.disable(gui), gui), core, frame, J.Rectangle{605.0, 147.0, 170.0, 30.0}, Some{"Inner Radius"}, None{}, donut, 5.0, (205.0 - 10.0 : F32)),
    core, with_flags(state, show_values, show_percent, show_donut))

def ui.second(r: J.Frame & Bool, +core: J.Core, +state: State, +show_values: Bool) -> J.Core & (State & J.Frame):
  (frame, +show_percent) = r
  State{+gui, _, _, _, _, _, _, _, _, +show_donut, _, _, _, _} = state
  ui.third(checked(G.Gui.check_box(gui, core, frame, J.Rectangle{545.0, 117.0, 20.0, 20.0}, "Make Donut", show_donut)), core, state, show_values, show_percent)

def ui.first(r: J.Frame & Bool, +core: J.Core, +state: State) -> J.Core & (State & J.Frame):
  (frame, +show_values) = r
  State{+gui, _, _, _, _, _, _, _, +show_percent, _, _, _, _, _} = state
  ui.second(checked(G.Gui.check_box(gui, core, frame, J.Rectangle{545.0, 87.0, 20.0, 20.0}, "Show Percentages", show_percent)), core, state, show_values)

def ui.count(pair: U32 & Bool, frame: J.Frame, +core: J.Core, +state: State) -> J.Core & (State & J.Frame):
  (+count, _) = pair
  State{+gui, _, _, _, _, _, _, +show_values, _, _, _, _, _, _} = state
  ui.first(checked(G.Gui.check_box(gui, core, frame, J.Rectangle{545.0, 57.0, 20.0, 20.0}, "Show Values", show_values)), core, with_count(state, count))

def ui.spinner(r: J.Frame & (U32 & Bool), +core: J.Core, +state: State) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  ui.count(pair, frame, core, state)

# The pie, then the panel (Fade(LIGHTGRAY, 0.5f) with a GRAY outline) and its controls.
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, _, +count, _, +values, _, _, _, _, _, _, _, _, _} = state
  f1 = slices(U32.to_nat(count), values, libm, 0, 0.0, state, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.rectangle_rec(f1, J.Rectangle{525.0, 5.0, 270.0, 440.0}, J.Color.rgba(200, 200, 200, 127))
  f3 = J.Draw.rectangle_lines_ex(f2, J.Rectangle{525.0, 5.0, 270.0, 440.0}, 1.0, J.Color.GRAY())
  ui.spinner(G.Gui.spinner(gui, core, f3, J.Rectangle{620.0, 17.0, 125.0, 25.0}, Some{"Slices "}, count, 1, 10, False{}), core, state)

# The main loop's body; libm is the profile of the example's atan2f, sinf and cosf and of raylib's circles.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): seven slices with their values, ten labels "Slice %02i", the values shown, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), G.Gui.editing(), 7, 25.0, [300.0, 100.0, 450.0, 350.0, 600.0, 380.0, 750.0, 0.0, 0.0, 0.0],
    ["Slice 01", "Slice 02", "Slice 03", "Slice 04", "Slice 05", "Slice 06", "Slice 07", "Slice 08", "Slice 09", "Slice 10"],
    [False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}], True{}, False{}, False{}, 4294967295, M.Vector2{0.0, 0.0}, 0.0, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - pie chart", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
