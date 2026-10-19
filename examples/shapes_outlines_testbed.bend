# raylib [shapes] example - outlines testbed, ported to Jonlib.
# Adapted from raylib 6.2 examples/shapes/shapes_outlines_testbed.c
# (zlib/libpng, Copyright (c) 2026 Matthew Roush (@MatthewRoush)); see
# LICENSES/raylib.txt.
#
# Eight filled shapes outlined three times through a 2D camera: with
# Draw*Lines, with Draw*LinesEx at a world-space thickness and with
# Draw*LinesEx at thickness/zoom (a constant screen-space thickness), each
# row in a raygui group box. Ten raygui slider bars (Jongui) set the outline
# opacity, thickness, roundness, segment counts, ellipse radius, angles, ring
# radius and polygon sides; they run last in the frame, so a changed value
# shows from the next frame on. The LABEL text color is white
# (GuiSetStyle(LABEL, TEXT_COLOR_NORMAL, ColorToInt(WHITE))).
#
# The left button drags the camera (GetMouseDelta/zoom) and wraps the mouse
# inside the scene with SetMousePosition; the wheel and UP/DOWN zoom around
# the scene's center by exp2f(0.3*wheel) and exp2f(+-0.1), clamped to
# [0.1, 1000]; WASD move it by 10/zoom; Z resets the zoom and C the
# position. A press over the options panel turns the mouse control off until
# a release (on the memory platform only a touch point's release is seen).
# exp2f is M.Libm.pow2, GetScreenToWorld2D's matrix and the shapes'
# sinf/cosf, asinf, atan2f and acosf (segment estimates) follow the libm
# profile: a value outside the profile refuses that frame and, for the
# camera, every later one. See docs/GUI.md, docs/CAMERA.md and
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# values: lineOpacity, lineThickness, rectangleRoundness, rectangleSegments,
# ellipseRadiusY, circleStartAngle, circleEndAngle, circleSegments,
# ringInnerRadiusScale, polygonSides; disabled: disableMouseControl; ok: no
# camera refusal so far.
type State is Data:
  State{gui: G.Gui, camera: J.Camera2D, values: +List<F32>, disabled: Bool, ok: Bool}

def first(values: +List<F32>) -> F32:
  match values:
    case Con{v, _}: v
    case Nil{}: 0.0

def at(+values: +List<F32>, n: Nat) -> F32:
  first(List.drop(&2, F32, values, n))

# (int)x: C's conversion toward zero, as a two's-complement word.
def int(+x: F32) -> U32:
  Bool.pick(U32, (x < 0.0 : F32), (0 - F32.to_u32(F32.neg(x)) : U32), F32.to_u32(x))

def x.of(vector: M.Vector2) -> F32:
  M.Vector2{+x, _} = vector
  x

def y.of(vector: M.Vector2) -> F32:
  M.Vector2{_, +y} = vector
  y

# optionsBackground = { 510, 0, 290, 450 }.
def options() -> J.Rectangle:
  J.Rectangle{510.0, 0.0, 290.0, 450.0}

# zoomPoint = { ((float)screenWidth - optionsBackground.width)/2, (float)screenHeight/2 }.
def zoom_point() -> M.Vector2:
  M.Vector2{((800.0 - 290.0) / 2.0 : F32), (450.0 / 2.0 : F32)}

# -----------------------------------------------------------------------------
# Update

def camera_zoom(camera: J.Camera2D) -> F32:
  J.Camera2D{_, _, _, +zoom} = camera
  zoom

def with_zoom(+camera: J.Camera2D, +zoom: F32) -> J.Camera2D:
  J.Camera2D{+offset, +target, +rotation, _} = camera
  J.Camera2D{offset, target, rotation, zoom}

# camera.target = Vector2Add(camera.target, Vector2Subtract(prevWorldZoomPoint, worldZoomPoint)).
def rezoomed.moved(camera: J.Camera2D, +prev: M.Vector2, world: Maybe<M.Vector2>) -> Maybe<J.Camera2D>:
  J.Camera2D{+offset, +target, +rotation, +zoom} = camera
  match world:
    case None{}: None{}
    case Some{+w}: Some{J.Camera2D{offset, M.Vector2.add(target, M.Vector2.subtract(prev, w)), rotation, zoom}}

def rezoomed.from(+libm: M.Libm, +camera: J.Camera2D, prev: Maybe<M.Vector2>) -> Maybe<J.Camera2D>:
  match prev:
    case None{}: None{}
    case Some{+p}: rezoomed.moved(camera, p, J.Camera.screen_to_world_2d_for(M.Uncontracted{}, libm, zoom_point(), camera))

# The world point under zoomPoint before the zoom changes, the new zoom, and the target moved back under it.
def rezoomed(+libm: M.Libm, +camera: J.Camera2D, +zoom: F32) -> Maybe<J.Camera2D>:
  rezoomed.from(libm, with_zoom(camera, zoom), J.Camera.screen_to_world_2d_for(M.Uncontracted{}, libm, zoom_point(), camera))

# camera.zoom *= exp2f(k); camera.zoom = Clamp(camera.zoom, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX).
def scaled(+libm: M.Libm, +camera: J.Camera2D, factor: Maybe<F32>) -> Maybe<J.Camera2D>:
  match factor:
    case None{}: None{}
    case Some{+f}: rezoomed(libm, camera, M.Math.clamp((camera_zoom(camera) * f : F32), 0.1, 1000.0))

def step.zoom.by(+libm: M.Libm, +k: F32, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match camera:
    case None{}: None{}
    case Some{+c}: scaled(libm, c, M.Libm.pow2(libm, k))

# A zoom by exp2f(k) around zoomPoint when on.
def step.zoom(on: Bool, +libm: M.Libm, +k: F32, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match on:
    case False{}: camera
    case True{}: step.zoom.by(libm, k, camera)

# camera.target.x -= mouseDelta.x/camera.zoom; camera.target.y -= mouseDelta.y/camera.zoom.
def panned(+camera: J.Camera2D, delta: M.Vector2) -> J.Camera2D:
  J.Camera2D{+offset, +target, +rotation, +zoom} = camera
  M.Vector2{+tx, +ty} = target
  M.Vector2{+dx, +dy} = delta
  J.Camera2D{offset, M.Vector2{(tx - dx / zoom : F32), (ty - dy / zoom : F32)}, rotation, zoom}

def step.pan.at(+delta: M.Vector2, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match camera:
    case None{}: None{}
    case Some{+c}: Some{panned(c, delta)}

def step.pan(on: Bool, +delta: M.Vector2, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match on:
    case False{}: camera
    case True{}: step.pan.at(delta, camera)

# camera.target.x -= or += KEYBOARD_CAMERA_MOVE_SPEED/camera.zoom.
def moved.x(+on: Bool, +minus: Bool, +camera: J.Camera2D) -> J.Camera2D:
  J.Camera2D{+offset, +target, +rotation, +zoom} = camera
  M.Vector2{+tx, +ty} = target
  +s = (10.0 / zoom : F32)
  J.Camera2D{offset, M.Vector2{Bool.pick(F32, on, Bool.pick(F32, minus, (tx - s : F32), (tx + s : F32)), tx), ty}, rotation, zoom}

def moved.y(+on: Bool, +minus: Bool, +camera: J.Camera2D) -> J.Camera2D:
  J.Camera2D{+offset, +target, +rotation, +zoom} = camera
  M.Vector2{+tx, +ty} = target
  +s = (10.0 / zoom : F32)
  J.Camera2D{offset, M.Vector2{tx, Bool.pick(F32, on, Bool.pick(F32, minus, (ty - s : F32), (ty + s : F32)), ty)}, rotation, zoom}

# KEY_A, KEY_D, KEY_W, KEY_S in that order.
def step.moves(+a: Bool, +d: Bool, +w: Bool, +s: Bool, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match camera:
    case None{}: None{}
    case Some{+c}: Some{moved.y(s, False{}, moved.y(w, True{}, moved.x(d, False{}, moved.x(a, True{}, c))))}

def step.reset.at(+libm: M.Libm, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match camera:
    case None{}: None{}
    case Some{+c}: rezoomed(libm, c, 1.0)

# KEY_Z: camera.zoom = 1 around zoomPoint.
def step.reset(on: Bool, +libm: M.Libm, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match on:
    case False{}: camera
    case True{}: step.reset.at(libm, camera)

def centered(+camera: J.Camera2D) -> J.Camera2D:
  J.Camera2D{+offset, _, +rotation, +zoom} = camera
  J.Camera2D{offset, M.Vector2.zero(), rotation, zoom}

def step.center.at(camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match camera:
    case None{}: None{}
    case Some{+c}: Some{centered(c)}

# KEY_C: camera.target = (Vector2){ 0 }.
def step.center(on: Bool, camera: Maybe<J.Camera2D>) -> Maybe<J.Camera2D>:
  match on:
    case False{}: camera
    case True{}: step.center.at(camera)

# The C modulus (n%m + m)%m of a two's-complement int n, m > 0.
def wrap(+n: U32, +m: U32) -> U32:
  +r = Bool.pick(U32, (n >= 2147483648 : U32), (0 - ((0 - n : U32) % m : U32) : U32), (n % m : U32))
  ((r + m : U32) % m : U32)

# SetMousePosition(newX, newY) when the wrapped position differs from (int)mousePosScreen.
def wrapped(on: Bool, +core: J.Core, +x: U32, +y: U32) -> J.Core:
  match on:
    case False{}: core
    case True{}: J.Input.set_mouse_position(core, x, y)

def update.done(+gui: G.Gui, +values: +List<F32>, +disabled: Bool, +ok: Bool, +old: J.Camera2D, camera: Maybe<J.Camera2D>) -> State:
  match camera:
    case None{}: State{gui, old, values, disabled, False{}}
    case Some{+c}: State{gui, c, values, disabled, ok}

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+gui, +camera, +values, +disabled, +ok} = state
  +mouse = J.Input.get_mouse_position(core)
  +wheel = y.of(J.Input.get_mouse_wheel_move_v(core))
  +left = J.MouseButton.MOUSE_BUTTON_LEFT()
  +grabbed = (J.Input.is_mouse_button_pressed(core, left) && J.Collision.point_rec(mouse, options())) || disabled
  +off = grabbed && Bool.not(J.Input.is_mouse_button_released(core, left))
  +free = Bool.not(off)
  +down = free && J.Input.is_mouse_button_down(core, left)
  +mx = int(x.of(mouse))
  +my = int(y.of(mouse))
  +nx = wrap(mx, 510)
  +ny = wrap(my, 450)
  moving = step.moves(J.Input.is_key_down(core, J.KeyboardKey.KEY_A()), J.Input.is_key_down(core, J.KeyboardKey.KEY_D()), J.Input.is_key_down(core, J.KeyboardKey.KEY_W()), J.Input.is_key_down(core, J.KeyboardKey.KEY_S()),
    step.pan(down, J.Input.get_mouse_delta(core), step.zoom(free && Bool.not(F32.is_eq(wheel, 0.0)), libm, (0.3 * wheel : F32), Some{camera})))
  zoomed = step.zoom(J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), libm, F32.neg(0.1), step.zoom(J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), libm, 0.1, moving))
  (wrapped(down && (U32.is_ne(nx, mx) || U32.is_ne(ny, my)), core, nx, ny),
    update.done(gui, values, off, ok, camera, step.center(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_C()), step.reset(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Z()), libm, zoomed))))

# -----------------------------------------------------------------------------
# Draw

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# posX = shapeOffset + shapePaddingX*order.
def px(+k: F32) -> F32:
  (20.0 + 60.0 * k : F32)

def cell(+k: F32, +y: F32) -> J.Rectangle:
  J.Rectangle{px(k), y, 46.0, 46.0}

# (Vector2){ posX + SHAPE_SIZE/2.0f, posY + SHAPE_SIZE/2.0f }.
def mid(+k: F32, +y: F32) -> M.Vector2:
  M.Vector2{(px(k) + 46.0 / 2.0 : F32), (y + 46.0 / 2.0 : F32)}

# The triangle's vertices: posX/posY plus { 0, SHAPE_SIZE*0.8f }, { SHAPE_SIZE*0.6f, SHAPE_SIZE }, { SHAPE_SIZE, 0 }.
def tri.a(+y: F32) -> M.Vector2:
  M.Vector2{(px(6.0) + 0.0 : F32), (y + 46.0 * 0.8 : F32)}

def tri.b(+y: F32) -> M.Vector2:
  M.Vector2{(px(6.0) + 46.0 * 0.6 : F32), (y + 46.0 : F32)}

def tri.c(+y: F32) -> M.Vector2:
  M.Vector2{(px(6.0) + 46.0 : F32), (y + 0.0 : F32)}

# GuiGroupBox((Rectangle){ shapeOffset - BOX_SPACING, posY - BOX_SPACING, BOX_WIDTH, BOX_HEIGHT }, title).
def grouped(+gui: G.Gui, +y: F32, title: String, frame: J.Frame) -> J.Frame:
  G.Gui.group_box(gui, frame, J.Rectangle{(20.0 - 10.0 : F32), (y - 10.0 : F32), ((46.0 * 8.0 + 14.0 * 7.0 : F32) + 10.0 * 2.0 : F32), (46.0 + 10.0 * 2.0 : F32)}, Some{title})

# The filled shapes of a row (COLOR_FILLED), each followed by its outline in the row's own def.
def fill.rect(+y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.rectangle_rec(frame, cell(0.0, y), J.Color.DARKBLUE())

def fill.rounded(+libm: M.Libm, +v: +List<F32>, +y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.rectangle_rounded_for(libm, frame, cell(1.0, y), at(v, 2n), F32.trunc(at(v, 3n)), J.Color.DARKBLUE())

def fill.circle(+libm: M.Libm, +y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.circle_v_for(libm, frame, mid(2.0, y), (46.0 / 2.0 : F32), J.Color.DARKBLUE())

def fill.ellipse(+libm: M.Libm, +v: +List<F32>, +y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.ellipse_v_for(libm, frame, mid(3.0, y), (46.0 / 2.0 : F32), ((46.0 / 2.0 : F32) * at(v, 4n) : F32), J.Color.DARKBLUE())

def fill.sector(+libm: M.Libm, +v: +List<F32>, +y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.circle_sector_for(libm, frame, mid(4.0, y), (46.0 / 2.0 : F32), at(v, 5n), at(v, 6n), F32.trunc(at(v, 7n)), J.Color.DARKBLUE())

def fill.ring(+libm: M.Libm, +v: +List<F32>, +y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.ring_for(libm, frame, mid(5.0, y), ((46.0 / 2.0 : F32) * at(v, 8n) : F32), (46.0 / 2.0 : F32), at(v, 5n), at(v, 6n), F32.trunc(at(v, 7n)), J.Color.DARKBLUE())

def fill.triangle(+y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.triangle(frame, tri.a(y), tri.b(y), tri.c(y), J.Color.DARKBLUE())

def fill.poly(+libm: M.Libm, +v: +List<F32>, +y: F32, frame: J.Frame) -> J.Frame:
  J.Draw.poly_for(libm, frame, mid(7.0, y), F32.trunc(at(v, 9n)), (46.0 / 2.0 : F32), 0.0, J.Color.DARKBLUE())

# Draw*Lines() at posY.
def row.lines(+libm: M.Libm, +gui: G.Gui, +v: +List<F32>, +outline: U32, +y: F32, frame: J.Frame) -> J.Frame:
  +r = (46.0 / 2.0 : F32)
  f1 = J.Draw.rectangle_lines(fill.rect(y, frame), px(0.0), y, 46.0, 46.0, outline)
  f2 = J.Draw.rectangle_rounded_lines_for(libm, fill.rounded(libm, v, y, f1), cell(1.0, y), at(v, 2n), F32.trunc(at(v, 3n)), outline)
  f3 = J.Draw.circle_lines_v_for(libm, fill.circle(libm, y, f2), mid(2.0, y), r, outline)
  f4 = J.Draw.ellipse_lines_v_for(libm, fill.ellipse(libm, v, y, f3), mid(3.0, y), r, (r * at(v, 4n) : F32), outline)
  f5 = J.Draw.circle_sector_lines_for(libm, fill.sector(libm, v, y, f4), mid(4.0, y), r, at(v, 5n), at(v, 6n), F32.trunc(at(v, 7n)), outline)
  f6 = J.Draw.ring_lines_for(libm, fill.ring(libm, v, y, f5), mid(5.0, y), (r * at(v, 8n) : F32), r, at(v, 5n), at(v, 6n), F32.trunc(at(v, 7n)), outline)
  f7 = J.Draw.triangle_lines(fill.triangle(y, f6), tri.a(y), tri.b(y), tri.c(y), outline)
  f8 = J.Draw.poly_lines_for(libm, fill.poly(libm, v, y, f7), mid(7.0, y), F32.trunc(at(v, 9n)), r, 0.0, outline)
  grouped(gui, y, "Draw*Lines()", f8)

# Draw*LinesEx() at posY with the thickness t.
def row.ex(+libm: M.Libm, +gui: G.Gui, +v: +List<F32>, +outline: U32, +y: F32, +t: F32, title: String, frame: J.Frame) -> J.Frame:
  +r = (46.0 / 2.0 : F32)
  f1 = J.Draw.rectangle_lines_ex(fill.rect(y, frame), cell(0.0, y), t, outline)
  f2 = J.Draw.rectangle_rounded_lines_ex_for(libm, fill.rounded(libm, v, y, f1), cell(1.0, y), at(v, 2n), F32.trunc(at(v, 3n)), t, outline)
  f3 = J.Draw.circle_lines_ex_for(libm, fill.circle(libm, y, f2), mid(2.0, y), r, t, outline)
  f4 = J.Draw.ellipse_lines_ex_for(libm, fill.ellipse(libm, v, y, f3), mid(3.0, y), r, (r * at(v, 4n) : F32), t, outline)
  f5 = J.Draw.circle_sector_lines_ex_for(libm, fill.sector(libm, v, y, f4), mid(4.0, y), r, at(v, 5n), at(v, 6n), F32.trunc(at(v, 7n)), t, outline)
  f6 = J.Draw.ring_lines_ex_for(libm, fill.ring(libm, v, y, f5), mid(5.0, y), (r * at(v, 8n) : F32), r, at(v, 5n), at(v, 6n), F32.trunc(at(v, 7n)), t, outline)
  f7 = J.Draw.triangle_lines_ex(fill.triangle(y, f6), tri.a(y), tri.b(y), tri.c(y), t, outline)
  f8 = J.Draw.poly_lines_ex_for(libm, fill.poly(libm, v, y, f7), mid(7.0, y), F32.trunc(at(v, 9n)), r, 0.0, t, outline)
  grouped(gui, y, title, f8)

# The options panel's background, help texts and border.
def panel(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle_rec(frame, options(), J.Color.with_alpha(J.Color.DARKGRAY(), 0.75))
  f2 = J.Draw.rectangle_rec(f1, J.Rectangle{510.0, 360.0, 290.0, 90.0}, J.Color.with_alpha(J.Color.BLACK(), 0.4))
  f3 = J.Draw.line_ex(f2, M.Vector2{510.0, 360.0}, M.Vector2{(510.0 + 290.0 : F32), 360.0}, 1.0, J.Color.BLACK())
  f4 = J.Draw.text(f3, "Move with the mouse or WASD keys", (510.0 + 10.0 : F32), 370.0, 10.0, J.Color.ORANGE())
  f5 = J.Draw.text(f4, "Zoom with the mouse or UP and DOWN keys", (510.0 + 10.0 : F32), 390.0, 10.0, J.Color.ORANGE())
  f6 = J.Draw.text(f5, "Press C to reset position", (510.0 + 10.0 : F32), 410.0, 10.0, J.Color.ORANGE())
  f7 = J.Draw.text(f6, "Press Z to reset zoom", (510.0 + 10.0 : F32), 430.0, 10.0, J.Color.ORANGE())
  J.Draw.line_ex(f7, M.Vector2{510.0, 0.0}, M.Vector2{510.0, (0.0 + 450.0 : F32)}, 1.0, J.Color.BLACK())

# GuiSliderBar((Rectangle){ 605, y, 150, 25 }, label, TextFormat(format, value), &value, low, high);
# whole: the format is "%d" of (int)value, otherwise "%.2f".
type Setting is Data:
  Setting{y: F32, label: String, whole: Bool, low: F32, high: F32}

def settings() -> +List<Setting>:
  [Setting{10.0, "Line Opacity", True{}, 0.0, 255.0},
   Setting{45.0, "Thickness", False{}, F32.neg(20.0), 40.0},
   Setting{80.0, "Rect Roundness", False{}, F32.neg(1.0), 2.0},
   Setting{115.0, "Rect Segments", True{}, F32.neg(1.0), 100.0},
   Setting{150.0, "Ellipse Radius Y", False{}, 0.0, 1.25},
   Setting{185.0, "Start Angle", False{}, F32.neg(360.0), 360.0},
   Setting{220.0, "End Angle", False{}, F32.neg(360.0), 360.0},
   Setting{255.0, "Circle Segments", True{}, F32.neg(1.0), 100.0},
   Setting{290.0, "Ring Radius", False{}, F32.neg(1.0), 2.0},
   Setting{325.0, "Poly Sides", True{}, F32.neg(1.0), 100.0}]

def formatted(whole: Bool, +value: F32) -> Maybe<String>:
  match whole:
    case True{}: J.Text.format("%d", [J.TextInt{int(value)}])
    case False{}: J.Text.format("%.2f", [J.TextFloat{value}])

# A slider's outcome: the frame, the Gui and the value.
type Slid is Type:
  Slid{frame: J.Frame, gui: G.Gui, value: F32}

def slid.value(gui: G.Gui, frame: J.Frame, pair: F32 & Bool) -> Slid:
  (value, _) = pair
  Slid{frame, gui, value}

def slid.gui(frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> Slid:
  (gui, pair) = rest
  slid.value(gui, frame, pair)

def slid.done(r: J.Frame & (G.Gui & (F32 & Bool))) -> Slid:
  (frame, rest) = r
  slid.gui(frame, rest)

def slide.text(text: Maybe<String>, +gui: G.Gui, +core: J.Core, frame: J.Frame, +y: F32, label: String, +value: F32, +low: F32, +high: F32) -> Slid:
  match text:
    case None{}: Slid{J.Frame.refuse(frame), gui, value}
    case Some{t}: slid.done(G.Gui.slider_bar(gui, core, frame, J.Rectangle{605.0, y, 150.0, 25.0}, Some{label}, Some{t}, value, low, high))

# The sliders run in order; acc holds the new values, last first.
type Bars is Type:
  Bars{frame: J.Frame, gui: G.Gui, acc: +List<F32>}

def bars.take(acc: +List<F32>, s: Slid) -> Bars:
  Slid{frame, +gui, +value} = s
  Bars{frame, gui, Con{value, acc}}

def bars.one(+setting: Setting, +value: F32, +core: J.Core, pending: Bars) -> Bars:
  Setting{+y, +label, +whole, +low, +high} = setting
  Bars{frame, +gui, acc} = pending
  bars.take(acc, slide.text(formatted(whole, value), gui, core, frame, y, label, value, low, high))

def bars.go(items: +List<Setting>, values: +List<F32>, +core: J.Core, pending: Bars) -> Bars:
  match items values:
    case Con{+setting, rest} Con{+value, more}: bars.go(rest, more, core, bars.one(setting, value, core, pending))
    case _ _: pending

def draw.done(+core: J.Core, +camera: J.Camera2D, +disabled: Bool, +ok: Bool, pending: Bars) -> J.Core & (State & J.Frame):
  Bars{frame, +gui, acc} = pending
  (core, (State{gui, camera, List.reverse(&2, F32, acc), disabled, ok}, frame))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +camera, +values, +disabled, +ok} = state
  +outline = ((J.Color.YELLOW() .&. 4294967040) .|. (F32.to_u32(at(values, 0n)) .&. 255) : U32)
  +world = at(values, 1n)
  f1 = J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(checked(ok, frame), J.Color.rgba(50, 50, 55, 255)), camera)
  f2 = row.lines(libm, gui, values, outline, (20.0 + 80.0 * 0.0 : F32), f1)
  f3 = row.ex(libm, gui, values, outline, (20.0 + 80.0 * 1.0 : F32), world, "Draw*LinesEx() with *world space* pixel thickness", f2)
  f4 = row.ex(libm, gui, values, outline, (20.0 + 80.0 * 2.0 : F32), (world / camera_zoom(camera) : F32), "Draw*LinesEx() with *screen space* pixel thickness", f3)
  f5 = panel(J.Frame.end_mode_2d(f4))
  draw.done(core, camera, disabled, ok, bars.go(settings(), values, core, Bars{f5, gui, Nil{}}))

# The main loop's body; libm is the profile of exp2f, the camera and the shapes.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): camera = { .zoom = 1 }, the options' initial values, mouse control on,
# GuiSetStyle(LABEL, TEXT_COLOR_NORMAL, ColorToInt(WHITE)), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.set_style(G.Gui.new(), G.Gui.LABEL(), 2, 4294967295), J.Camera2D{M.Vector2.zero(), M.Vector2.zero(), 0.0, 1.0},
    [130.0, 4.0, 0.4, 9.0, 0.5, 20.0, 270.0, 36.0, 0.3, 6.0], False{}, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - outlines testbed", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
