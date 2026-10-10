# raylib [shapes] example - rlgl color wheel, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_rlgl_color_wheel.c (zlib/libpng,
# Copyright (c) 2025 Robin (@RobinsAviary)); see LICENSES/raylib.txt.
#
# A hue wheel drawn with rlgl triangles (lines while SPACE is held) whose
# center takes the value of a raygui slider; a click on the wheel picks a
# color (ColorFromHSV by the handle's angle and distance, ColorLerp from
# the gray of the value), UP and DOWN scale the wheel, CTRL+C copies the
# color as hex. The wheel adds (unsigned int)GetMouseWheelMove() to the
# triangle count: a negative wheel move is an out-of-range conversion in C
# (C11 6.3.1.4), so that frame and every later one are refused. sinf/cosf
# and Vector2Angle's atan2f follow the libm profile (docs/SINCOSF.md,
# docs/ANGLES.md); a value outside it refuses the same way. MSAA does not
# change the software renderer. See docs/RLGL.md and docs/GUI.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# triangleCount, pointScale, value, circlePosition, color, sliderClicked, settingColor, renderType == RL_LINES;
# ok: no refusal so far.
type Wheel is Data:
  Wheel{count: U32, scale: F32, value: F32, circle: M.Vector2, color: U32, slider: Bool, setting: Bool, lines: Bool, ok: Bool}

type State is Data:
  State{wheel: Wheel, gui: G.Gui}

# pointScale and circlePosition.
type Dial is Data:
  Dial{scale: F32, circle: M.Vector2}

# circlePosition and color.
type Pick is Data:
  Pick{circle: M.Vector2, color: U32}

def center() -> M.Vector2:
  M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}

def turn.scaled(angle: Maybe<F32>) -> Maybe<F32>:
  match angle:
    case None{}: None{}
    case Some{+a}: Some{((a / M.Math.PI() + 1.0) / 2.0 : F32)}

# angle = ((Vector2Angle((0, -pointScale), center - circlePosition)/PI + 1.0f)/2.0f).
def turn(+libm: M.Libm, +scale: F32, +circle: M.Vector2) -> Maybe<F32>:
  turn.scaled(M.Vector2.angle_for(libm, M.Vector2{0.0, F32.neg(scale)}, M.Vector2.subtract(center(), circle)))

def rim.at(+scale: F32, sine: Maybe<F32>, cosine: Maybe<F32>) -> Maybe<M.Vector2>:
  match sine cosine:
    case Some{+s} Some{+c}: Some{M.Vector2.add(M.Vector2{(s * scale : F32), (F32.neg(c) * scale : F32)}, center())}
    case _ _: None{}

# (sinf(angle*(PI*2.0f))*pointScale, -cosf(angle*(PI*2.0f))*pointScale) + center.
def rim(+libm: M.Libm, +scale: F32, +angle: F32) -> Maybe<M.Vector2>:
  rim.at(scale, M.Libm.sin(libm, (angle * (M.Math.PI() * 2.0) : F32)), M.Libm.cos(libm, (angle * (M.Math.PI() * 2.0) : F32)))

def rim.turned(+libm: M.Libm, +scale: F32, angle: Maybe<F32>) -> Maybe<M.Vector2>:
  match angle:
    case None{}: None{}
    case Some{+a}: rim(libm, scale, a)

# (circlePosition - center)*factor + center.
def grown(circle: M.Vector2, +factor: F32) -> M.Vector2:
  M.Vector2.add(M.Vector2.multiply(M.Vector2.subtract(circle, center()), M.Vector2{factor, factor}), center())

# KEY_UP: the wheel 2.5% larger up to half the screen height, the handle with it.
def up(+pressed: Bool, +scale: F32, +circle: M.Vector2) -> Dial:
  +scaled = (scale * 1.025 : F32)
  +big = (scaled > (450.0 / 2.0) : F32)
  Bool.pick(Dial, pressed, Dial{Bool.pick(F32, big, (450.0 / 2.0 : F32), scaled), Bool.pick(M.Vector2, big, circle, grown(circle, 1.025))}, Dial{scale, circle})

def dial(+scale: F32, circle: Maybe<M.Vector2>) -> Maybe<Dial>:
  match circle:
    case None{}: None{}
    case Some{+c}: Some{Dial{scale, c}}

# if (distance > 1.0f): the handle back on the rim at its angle.
def down.snap(far: Bool, +libm: M.Libm, +scale: F32, +circle: M.Vector2) -> Maybe<Dial>:
  match far:
    case False{}: Some{Dial{scale, circle}}
    case True{}: dial(scale, rim.turned(libm, scale, turn(libm, scale, circle)))

def down.at(+libm: M.Libm, +scaled: F32, +circle: M.Vector2) -> Maybe<Dial>:
  +small = (scaled < 32.0 : F32)
  +scale = Bool.pick(F32, small, 32.0, scaled)
  +moved = Bool.pick(M.Vector2, small, circle, grown(circle, 0.975))
  down.snap(((M.Vector2.distance(center(), moved) / scale) > 1.0 : F32), libm, scale, moved)

# KEY_DOWN: the wheel 2.5% smaller down to 32, the handle with it and kept inside.
def down(pressed: Bool, +libm: M.Libm, +scale: F32, +circle: M.Vector2) -> Maybe<Dial>:
  match pressed:
    case False{}: Some{Dial{scale, circle}}
    case True{}: down.at(libm, (scale * 0.975 : F32), circle)

def down.dial(+pressed: Bool, +libm: M.Libm, dial: Dial) -> Maybe<Dial>:
  Dial{+scale, +circle} = dial
  down(pressed, libm, scale, circle)

# (Color){ (int)(value*255.0f), (int)(value*255.0f), (int)(value*255.0f), 255 }.
def gray(+value: F32) -> U32:
  J.Color.rgba(F32.to_u32((value * 255.0 : F32)), F32.to_u32((value * 255.0 : F32)), F32.to_u32((value * 255.0 : F32)), 255)

# Clamp(distance, 0.0f, 1.0f).
def unit(+distance: F32) -> F32:
  M.Math.clamp(distance, 0.0, 1.0)

# color = ColorLerp(gray, ColorFromHSV(angle*360.0f, Clamp(distance, 0.0f, 1.0f), 1.0f), Clamp(distance, 0.0f, 1.0f)).
def chosen.colored(+value: F32, +distance: F32, +angle: F32, spot: Maybe<M.Vector2>) -> Maybe<Pick>:
  match spot:
    case None{}: None{}
    case Some{+s}: Some{Pick{s, J.Color.lerp(gray(value), J.Color.from_hsv((angle * 360.0 : F32), unit(distance), 1.0), unit(distance))}}

# if (settingColor && distance > 1.0f): the handle on the rim.
def chosen.spot(snap: Bool, +libm: M.Libm, +scale: F32, +angle: F32, +circle: M.Vector2) -> Maybe<M.Vector2>:
  match snap:
    case False{}: Some{circle}
    case True{}: rim(libm, scale, angle)

def chosen.turned(+libm: M.Libm, +snap: Bool, +scale: F32, +value: F32, +distance: F32, +circle: M.Vector2, angle: Maybe<F32>) -> Maybe<Pick>:
  match angle:
    case None{}: None{}
    case Some{+a}: chosen.colored(value, distance, a, chosen.spot(snap, libm, scale, a, circle))

def chosen.at(+libm: M.Libm, +setting: Bool, +scale: F32, +value: F32, +circle: M.Vector2, +distance: F32) -> Maybe<Pick>:
  chosen.turned(libm, setting && (distance > 1.0 : F32), scale, value, distance, circle, turn(libm, scale, circle))

# if (settingColor || sliderClicked): the color of the handle (the mouse while setting the color).
def chosen(active: Bool, +libm: M.Libm, +setting: Bool, +scale: F32, +value: F32, +color: U32, +circle: M.Vector2) -> Maybe<Pick>:
  match active:
    case False{}: Some{Pick{circle, color}}
    case True{}: chosen.at(libm, setting, scale, value, circle, (M.Vector2.distance(center(), circle) / scale : F32))

def update.picked(+gui: G.Gui, +count: U32, +scale: F32, +value: F32, +circle: M.Vector2, +color: U32, +slider: Bool, +setting: Bool, +lines: Bool, +ok: Bool, pick: Maybe<Pick>) -> State:
  match pick:
    case None{}: State{Wheel{count, scale, value, circle, color, slider, setting, lines, False{}}, gui}
    case Some{Pick{+spot, +tint}}: State{Wheel{count, scale, value, spot, tint, slider, setting, lines, ok}, gui}

# The wheel and slider clicks, the render mode, then the color.
def update.flags(+libm: M.Libm, +core: J.Core, +gui: G.Gui, +count: U32, +value: F32, +color: U32, +slider: Bool, +setting: Bool, +lines: Bool, +ok: Bool, +hover: Bool,
    +mouse: M.Vector2, +scale: F32, +circle: M.Vector2) -> State:
  +pressed = J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  +released = J.Input.is_mouse_button_released(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  +set = Bool.not(released) && (setting || (pressed && (M.Vector2.distance(mouse, center()) <= (scale + 10.0) : F32)))
  +slid = Bool.not(released) && (slider || (hover && pressed))
  +wire = Bool.not(J.Input.is_key_released(core, J.KeyboardKey.KEY_SPACE())) && (lines || J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()))
  +spot = Bool.pick(M.Vector2, set, mouse, circle)
  update.picked(gui, count, scale, value, spot, color, slid, set, wire, ok, chosen(set || slid, libm, set, scale, value, color, spot))

def update.dial(+libm: M.Libm, +core: J.Core, +gui: G.Gui, +count: U32, +value: F32, +color: U32, +slider: Bool, +setting: Bool, +lines: Bool, +ok: Bool, +hover: Bool,
    +mouse: M.Vector2, +scale: F32, +circle: M.Vector2, dial: Maybe<Dial>) -> State:
  match dial:
    case None{}: State{Wheel{count, scale, value, circle, color, slider, setting, lines, False{}}, gui}
    case Some{Dial{+s, +c}}: update.flags(libm, core, gui, count, value, color, slider, setting, lines, ok, hover, mouse, s, c)

# The mouse over sliderRectangle = { 42.0f, 16.0f + 64.0f + 45.0f, 64.0f, 16.0f }.
def hover(mouse: M.Vector2) -> Bool:
  M.Vector2{+x, +y} = mouse
  (x >= 42.0 : F32) && (y >= (16.0 + 64.0 + 45.0) : F32) && (x < (42.0 + 64.0) : F32) && (y < (16.0 + 64.0 + 45.0 + 16.0) : F32)

def hex(+color: U32) -> Maybe<String>:
  J.Text.format("#%02X%02X%02X", [J.TextInt{J.Color.red(color)}, J.TextInt{J.Color.green(color)}, J.TextInt{J.Color.blue(color)}])

def copy.text(text: Maybe<String>, +core: J.Core) -> J.Core:
  match text:
    case None{}: core
    case Some{t}: J.Core.set_clipboard_text(core, t)

# CTRL+C: SetClipboardText(TextFormat("#%02X%02X%02X", color.r, color.g, color.b)); the draw refuses a text that does not format.
def copy(copying: Bool, +core: J.Core, +color: U32) -> J.Core:
  match copying:
    case False{}: core
    case True{}: copy.text(hex(color), core)

def copying(+core: J.Core) -> Bool:
  J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT_CONTROL()) && J.Input.is_key_down(core, J.KeyboardKey.KEY_C())

# triangleCount += (unsigned int)GetMouseWheelMove(), clamped to 3..256; the wheel scaling; the clicks and the color.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+wheel, +gui} = state
  Wheel{+count, +scale, +value, +circle, +color, +slider, +setting, +lines, +ok} = wheel
  +turns = J.Input.get_mouse_wheel_move(core)
  +fine = ok && (turns >= 0.0 : F32) && (turns < 4294967296.0 : F32)
  +next = F32.to_u32(M.Math.clamp(U32.to_f32((count + F32.to_u32(Bool.pick(F32, fine, turns, 0.0)) : U32)), 3.0, 256.0))
  +mouse = J.Input.get_mouse_position(core)
  (copy(copying(core) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_C()), core, color),
    update.dial(libm, core, gui, next, value, color, slider, setting, lines, fine, hover(mouse), mouse, scale, circle,
      down.dial(J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), libm, up(J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), scale, circle))))

def tinted(frame: J.Frame, +color: U32) -> J.Frame:
  J.Rlgl.color4ub(frame, J.Color.red(color), J.Color.green(color), J.Color.blue(color), J.Color.alpha(color))

def point(frame: J.Frame, point: M.Vector2) -> J.Frame:
  M.Vector2{+x, +y} = point
  J.Rlgl.vertex2f(frame, x, y)

# RL_TRIANGLES: three vertices, the center with rlColor4f(value, value, value, 1.0f); RL_LINES: the three edges.
def slice.drawn(lines: Bool, +value: F32, +from: M.Vector2, +to: M.Vector2, +current: U32, +offset: U32, frame: J.Frame) -> J.Frame:
  match lines:
    case False{}: point(tinted(point(J.Rlgl.color4f(point(tinted(frame, current), from), value, value, value, 1.0), center()), offset), to)
    case True{}:
      f1 = point(tinted(point(tinted(frame, current), from), J.Color.WHITE()), center())
      f2 = point(tinted(point(f1, center()), offset), to)
      point(tinted(point(f2, to), current), from)

def slice.at(+lines: Bool, +value: F32, +current: U32, +offset: U32, frame: J.Frame, from: Maybe<M.Vector2>, to: Maybe<M.Vector2>) -> J.Frame:
  match from to:
    case Some{+a} Some{+b}: slice.drawn(lines, value, a, b, current, offset, frame)
    case _ _: J.Frame.refuse(frame)

def spoke.at(+scale: F32, sine: Maybe<F32>, cosine: Maybe<F32>) -> Maybe<M.Vector2>:
  match sine cosine:
    case Some{+s} Some{+c}: Some{M.Vector2.add(center(), M.Vector2.multiply(M.Vector2{s, F32.neg(c)}, M.Vector2{scale, scale}))}
    case _ _: None{}

# center + (sinf(angle), -cosf(angle))*scale.
def spoke(+libm: M.Libm, +scale: F32, +angle: F32) -> Maybe<M.Vector2>:
  spoke.at(scale, M.Libm.sin(libm, angle), M.Libm.cos(libm, angle))

# Triangle i: the hues at its two angles.
def slice(+i: U32, +libm: M.Libm, +count: U32, +scale: F32, +value: F32, +lines: Bool, frame: J.Frame) -> J.Frame:
  +step = ((M.Math.PI() * 2.0) / U32.to_f32(count) : F32)
  +angle = (step * U32.to_f32(i) : F32)
  +hue = ((angle / (2.0 * M.Math.PI())) * 360.0 : F32)
  slice.at(lines, value, J.Color.from_hsv(hue, 1.0, 1.0), J.Color.from_hsv((hue + (step / (2.0 * M.Math.PI())) * 360.0 : F32), 1.0, 1.0), frame,
    spoke(libm, scale, angle), spoke(libm, scale, ((U32.to_f32(i) + 1.0) * step : F32)))

def slices(n: Nat, +i: U32, +libm: M.Libm, +count: U32, +scale: F32, +value: F32, +lines: Bool, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: slices(p, (i + 1 : U32), libm, count, scale, value, lines, slice(i, libm, count, scale, value, lines, frame))

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 8.0, y, 20.0, J.Color.DARKGRAY())

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, (64.0 + 16.0 : F32), 8.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.slid(+core: J.Core, wheel: Wheel, frame: J.Frame, +gui: G.Gui, pair: F32 & Bool) -> J.Core & (State & J.Frame):
  Wheel{+count, +scale, _, +circle, +color, +slider, +setting, +lines, +ok} = wheel
  (+value, _) = pair
  draw.fps.done(State{Wheel{count, scale, value, circle, color, slider, setting, lines, ok}, gui}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.bar.rest(+core: J.Core, +wheel: Wheel, frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> J.Core & (State & J.Frame):
  (+gui, pair) = rest
  draw.slid(core, wheel, frame, gui, pair)

# GuiSliderBar(sliderRectangle, "value: ", "", &value, 0.0f, 1.0f); DrawFPS(64 + 16, 8).
def draw.bar(+core: J.Core, +wheel: Wheel, r: J.Frame & (G.Gui & (F32 & Bool))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.bar.rest(core, wheel, frame, rest)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+wheel, +gui} = state
  Wheel{+count, +scale, +value, +circle, +color, _, _, +lines, +ok} = wheel
  f1 = J.Rlgl.end(slices(U32.to_nat(count), 0, libm, count, scale, value, lines, J.Rlgl.begin(J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()), Bool.pick(U32, lines, 1, 4))))
  +handle = Bool.pick(U32, ((M.Vector2.distance(center(), circle) / scale) <= 0.5 : F32) && (value <= 0.5 : F32), J.Color.DARKGRAY(), J.Color.BLACK())
  f2 = J.Draw.rectangle_v(J.Draw.circle_lines_v_for(libm, f1, circle, 4.0, handle), M.Vector2{8.0, 8.0}, M.Vector2{64.0, 64.0}, color)
  f3 = J.Draw.rectangle_lines_ex(f2, J.Rectangle{8.0, 8.0, 64.0, 64.0}, 2.0, J.Color.lerp(color, J.Color.BLACK(), 0.5))
  f4 = label(J.Text.format("#%02X%02X%02X\n(%d, %d, %d)", [J.TextInt{J.Color.red(color)}, J.TextInt{J.Color.green(color)}, J.TextInt{J.Color.blue(color)},
    J.TextInt{J.Color.red(color)}, J.TextInt{J.Color.green(color)}, J.TextInt{J.Color.blue(color)}]), (8.0 + 64.0 + 8.0 : F32), f3)
  +held = copying(core)
  f5 = J.Draw.text(f4, "press ctrl+c to copy!", 8.0, Bool.pick(F32, held, (425.0 - 4.0 : F32), 425.0), 20.0, Bool.pick(U32, held, J.Color.DARKGREEN(), J.Color.DARKGRAY()))
  draw.bar(core, wheel, G.Gui.slider_bar(gui, core, label(J.Text.format("triangle count: %d", [J.TextInt{count}]), 395.0, f5),
    J.Rectangle{42.0, (16.0 + 64.0 + 45.0 : F32), 64.0, 16.0}, Some{"value: "}, Some{""}, value, 0.0, 1.0))

# The main loop's body; libm is the profile of the example's sinf/cosf, Vector2Angle's atan2f and DrawCircleLinesV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): 64 triangles of radius 150, value 1, the handle at the center, white; SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Wheel{64, 150.0, 1.0, center(), J.Color.rgba(255, 255, 255, 255), False{}, False{}, False{}, True{}}, G.Gui.new()}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - rlgl color wheel", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
