# raylib [core] example - input gamepad, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_gamepad.c (zlib/libpng,
# Copyright (c) 2013-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The gamepad chosen with LEFT and RIGHT drawn by its name's layout (Xbox,
# PlayStation or a generic one) with its buttons, sticks, triggers and
# axes, and a button for SetGamepadVibration. The example reads
# GetGamepadAxisCount of any index, which raylib leaves unchecked past
# MAX_GAMEPADS (4): from that index on every frame is refused. Gamepad
# names are empty on the platform Jonlib models (docs/DRIVER.md), so a
# connected gamepad takes the generic layout; the three layouts are
# generated from the example's draw calls. The circles' and rounded
# rectangles' sinf/cosf follow the libm profile (docs/SINCOSF.md). MSAA
# does not change the software renderer. LoadTexture of a .png is the PNG
# loader (Surface.load_png). See docs/INPUT.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# gamepad; ok: no refusal so far; texXboxPad and texPs3Pad.
type State is Type:
  State{pad: U32, ok: Bool, xbox: Maybe<J.Texture>, ps3: Maybe<J.Texture>}

# The axis values after the deadzones.
type Sticks is Data:
  Sticks{lx: F32, ly: F32, rx: F32, ry: F32, lt: F32, rt: F32}

type Canvas is Type:
  Canvas{frame: J.Frame, xbox: Maybe<J.Texture>, ps3: Maybe<J.Texture>}

def held(down: Maybe<Bool>) -> Bool:
  match down:
    case None{}: False{}
    case Some{+d}: d

# IsGamepadButtonDown(gamepad, button), for a gamepad index the frame was not refused for.
def down(+core: J.Core, +pad: U32, +button: U32) -> Bool:
  held(J.Input.is_gamepad_button_down(core, pad, button))

def circle(on: Bool, +libm: M.Libm, frame: J.Frame, +x: F32, +y: F32, +radius: F32, +color: U32) -> J.Frame:
  match on:
    case False{}: frame
    case True{}: J.Draw.circle_for(libm, frame, x, y, radius, color)

def box(on: Bool, frame: J.Frame, +x: F32, +y: F32, +width: F32, +height: F32, +color: U32) -> J.Frame:
  match on:
    case False{}: frame
    case True{}: J.Draw.rectangle(frame, x, y, width, height, color)

def triangle(on: Bool, frame: J.Frame, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +color: U32) -> J.Frame:
  match on:
    case False{}: frame
    case True{}: J.Draw.triangle(frame, M.Vector2{ax, ay}, M.Vector2{bx, by}, M.Vector2{cx, cy}, color)

def rounded(on: Bool, +libm: M.Libm, frame: J.Frame, +x: F32, +y: F32, +width: F32, +height: F32, +roundness: F32, +segments: F32, +color: U32) -> J.Frame:
  match on:
    case False{}: frame
    case True{}: J.Draw.rectangle_rounded_for(libm, frame, J.Rectangle{x, y, width, height}, roundness, segments, color)

# The Xbox layout over its texture: the buttons held, the d-pad, the back buttons, the sticks and the triggers.
def pad.xbox(+libm: M.Libm, +core: J.Core, +pad: U32, +lx: F32, +ly: F32, +rx: F32, +ry: F32, +lt: F32, +rt: F32, frame: J.Frame) -> J.Frame:
  f1 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE()), libm, frame, 394.0, 89.0, 19.0, J.Color.RED())
  f2 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE_RIGHT()), libm, f1, 436.0, 150.0, 9.0, J.Color.RED())
  f3 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE_LEFT()), libm, f2, 352.0, 150.0, 9.0, J.Color.RED())
  f4 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_LEFT()), libm, f3, 501.0, 151.0, 15.0, J.Color.BLUE())
  f5 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_DOWN()), libm, f4, 536.0, 187.0, 15.0, J.Color.LIME())
  f6 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT()), libm, f5, 572.0, 151.0, 15.0, J.Color.MAROON())
  f7 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_UP()), libm, f6, 536.0, 115.0, 15.0, J.Color.GOLD())
  f8 = box(True{}, f7, 317.0, 202.0, 19.0, 71.0, J.Color.BLACK())
  f9 = box(True{}, f8, 293.0, 228.0, 69.0, 19.0, J.Color.BLACK())
  f10 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_UP()), f9, 317.0, 202.0, 19.0, 26.0, J.Color.RED())
  f11 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_DOWN()), f10, 317.0, (202.0 + 45.0 : F32), 19.0, 26.0, J.Color.RED())
  f12 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_LEFT()), f11, 292.0, 228.0, 25.0, 19.0, J.Color.RED())
  f13 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_RIGHT()), f12, (292.0 + 44.0 : F32), 228.0, 26.0, 19.0, J.Color.RED())
  f14 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_TRIGGER_1()), libm, f13, 259.0, 61.0, 20.0, J.Color.RED())
  f15 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_TRIGGER_1()), libm, f14, 536.0, 61.0, 20.0, J.Color.RED())
  +left = Bool.pick(U32, down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_THUMB()), J.Color.RED(), J.Color.BLACK())
  f16 = circle(True{}, libm, f15, 259.0, 152.0, 39.0, J.Color.BLACK())
  f17 = circle(True{}, libm, f16, 259.0, 152.0, 34.0, J.Color.LIGHTGRAY())
  f18 = circle(True{}, libm, f17, (259.0 + F32.trunc((lx * 20.0 : F32)) : F32), (152.0 + F32.trunc((ly * 20.0 : F32)) : F32), 25.0, left)
  +right = Bool.pick(U32, down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_THUMB()), J.Color.RED(), J.Color.BLACK())
  f19 = circle(True{}, libm, f18, 461.0, 237.0, 38.0, J.Color.BLACK())
  f20 = circle(True{}, libm, f19, 461.0, 237.0, 33.0, J.Color.LIGHTGRAY())
  f21 = circle(True{}, libm, f20, (461.0 + F32.trunc((rx * 20.0 : F32)) : F32), (237.0 + F32.trunc((ry * 20.0 : F32)) : F32), 25.0, right)
  f22 = box(True{}, f21, 170.0, 30.0, 15.0, 70.0, J.Color.GRAY())
  f23 = box(True{}, f22, 604.0, 30.0, 15.0, 70.0, J.Color.GRAY())
  f24 = box(True{}, f23, 170.0, 30.0, 15.0, F32.trunc((((1.0 + lt) / 2.0) * 70.0 : F32)), J.Color.RED())
  box(True{}, f24, 604.0, 30.0, 15.0, F32.trunc((((1.0 + rt) / 2.0) * 70.0 : F32)), J.Color.RED())

# The PlayStation layout over its texture.
def pad.playstation(+libm: M.Libm, +core: J.Core, +pad: U32, +lx: F32, +ly: F32, +rx: F32, +ry: F32, +lt: F32, +rt: F32, frame: J.Frame) -> J.Frame:
  f1 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE()), libm, frame, 396.0, 222.0, 13.0, J.Color.RED())
  f2 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE_LEFT()), f1, 328.0, 170.0, 32.0, 13.0, J.Color.RED())
  f3 = triangle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE_RIGHT()), f2, 436.0, 168.0, 436.0, 185.0, 464.0, 177.0, J.Color.RED())
  f4 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_UP()), libm, f3, 557.0, 144.0, 13.0, J.Color.LIME())
  f5 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT()), libm, f4, 586.0, 173.0, 13.0, J.Color.RED())
  f6 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_DOWN()), libm, f5, 557.0, 203.0, 13.0, J.Color.VIOLET())
  f7 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_LEFT()), libm, f6, 527.0, 173.0, 13.0, J.Color.PINK())
  f8 = box(True{}, f7, 225.0, 132.0, 24.0, 84.0, J.Color.BLACK())
  f9 = box(True{}, f8, 195.0, 161.0, 84.0, 25.0, J.Color.BLACK())
  f10 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_UP()), f9, 225.0, 132.0, 24.0, 29.0, J.Color.RED())
  f11 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_DOWN()), f10, 225.0, (132.0 + 54.0 : F32), 24.0, 30.0, J.Color.RED())
  f12 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_LEFT()), f11, 195.0, 161.0, 30.0, 25.0, J.Color.RED())
  f13 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_RIGHT()), f12, (195.0 + 54.0 : F32), 161.0, 30.0, 25.0, J.Color.RED())
  f14 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_TRIGGER_1()), libm, f13, 239.0, 82.0, 20.0, J.Color.RED())
  f15 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_TRIGGER_1()), libm, f14, 557.0, 82.0, 20.0, J.Color.RED())
  +left = Bool.pick(U32, down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_THUMB()), J.Color.RED(), J.Color.BLACK())
  f16 = circle(True{}, libm, f15, 319.0, 255.0, 35.0, J.Color.BLACK())
  f17 = circle(True{}, libm, f16, 319.0, 255.0, 31.0, J.Color.LIGHTGRAY())
  f18 = circle(True{}, libm, f17, (319.0 + F32.trunc((lx * 20.0 : F32)) : F32), (255.0 + F32.trunc((ly * 20.0 : F32)) : F32), 25.0, left)
  +right = Bool.pick(U32, down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_THUMB()), J.Color.RED(), J.Color.BLACK())
  f19 = circle(True{}, libm, f18, 475.0, 255.0, 35.0, J.Color.BLACK())
  f20 = circle(True{}, libm, f19, 475.0, 255.0, 31.0, J.Color.LIGHTGRAY())
  f21 = circle(True{}, libm, f20, (475.0 + F32.trunc((rx * 20.0 : F32)) : F32), (255.0 + F32.trunc((ry * 20.0 : F32)) : F32), 25.0, right)
  f22 = box(True{}, f21, 169.0, 48.0, 15.0, 70.0, J.Color.GRAY())
  f23 = box(True{}, f22, 611.0, 48.0, 15.0, 70.0, J.Color.GRAY())
  f24 = box(True{}, f23, 169.0, 48.0, 15.0, F32.trunc((((1.0 + lt) / 2.0) * 70.0 : F32)), J.Color.RED())
  box(True{}, f24, 611.0, 48.0, 15.0, F32.trunc((((1.0 + rt) / 2.0) * 70.0 : F32)), J.Color.RED())

# The generic layout: a rounded body, the buttons, the d-pad, the back buttons and the sticks.
def pad.generic(+libm: M.Libm, +core: J.Core, +pad: U32, +lx: F32, +ly: F32, +rx: F32, +ry: F32, +lt: F32, +rt: F32, frame: J.Frame) -> J.Frame:
  f1 = rounded(True{}, libm, frame, 175.0, 110.0, 460.0, 220.0, 0.3, 16.0, J.Color.DARKGRAY())
  f2 = circle(True{}, libm, f1, 365.0, 170.0, 12.0, J.Color.RAYWHITE())
  f3 = circle(True{}, libm, f2, 405.0, 170.0, 12.0, J.Color.RAYWHITE())
  f4 = circle(True{}, libm, f3, 445.0, 170.0, 12.0, J.Color.RAYWHITE())
  f5 = circle(True{}, libm, f4, 516.0, 191.0, 17.0, J.Color.RAYWHITE())
  f6 = circle(True{}, libm, f5, 551.0, 227.0, 17.0, J.Color.RAYWHITE())
  f7 = circle(True{}, libm, f6, 587.0, 191.0, 17.0, J.Color.RAYWHITE())
  f8 = circle(True{}, libm, f7, 551.0, 155.0, 17.0, J.Color.RAYWHITE())
  f9 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE_LEFT()), libm, f8, 365.0, 170.0, 10.0, J.Color.RED())
  f10 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE()), libm, f9, 405.0, 170.0, 10.0, J.Color.GREEN())
  f11 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_MIDDLE_RIGHT()), libm, f10, 445.0, 170.0, 10.0, J.Color.BLUE())
  f12 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_LEFT()), libm, f11, 516.0, 191.0, 15.0, J.Color.GOLD())
  f13 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_DOWN()), libm, f12, 551.0, 227.0, 15.0, J.Color.BLUE())
  f14 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT()), libm, f13, 587.0, 191.0, 15.0, J.Color.GREEN())
  f15 = circle(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_UP()), libm, f14, 551.0, 155.0, 15.0, J.Color.RED())
  f16 = box(True{}, f15, 245.0, 145.0, 28.0, 88.0, J.Color.RAYWHITE())
  f17 = box(True{}, f16, 215.0, 174.0, 88.0, 29.0, J.Color.RAYWHITE())
  f18 = box(True{}, f17, 247.0, 147.0, 24.0, 84.0, J.Color.BLACK())
  f19 = box(True{}, f18, 217.0, 176.0, 84.0, 25.0, J.Color.BLACK())
  f20 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_UP()), f19, 247.0, 147.0, 24.0, 29.0, J.Color.RED())
  f21 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_DOWN()), f20, 247.0, (147.0 + 54.0 : F32), 24.0, 30.0, J.Color.RED())
  f22 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_LEFT()), f21, 217.0, 176.0, 30.0, 25.0, J.Color.RED())
  f23 = box(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_RIGHT()), f22, (217.0 + 54.0 : F32), 176.0, 30.0, 25.0, J.Color.RED())
  f24 = rounded(True{}, libm, f23, 215.0, 98.0, 100.0, 10.0, 0.5, 16.0, J.Color.DARKGRAY())
  f25 = rounded(True{}, libm, f24, 495.0, 98.0, 100.0, 10.0, 0.5, 16.0, J.Color.DARKGRAY())
  f26 = rounded(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_TRIGGER_1()), libm, f25, 215.0, 98.0, 100.0, 10.0, 0.5, 16.0, J.Color.RED())
  f27 = rounded(down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_TRIGGER_1()), libm, f26, 495.0, 98.0, 100.0, 10.0, 0.5, 16.0, J.Color.RED())
  +left = Bool.pick(U32, down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_LEFT_THUMB()), J.Color.RED(), J.Color.BLACK())
  f28 = circle(True{}, libm, f27, 345.0, 260.0, 40.0, J.Color.BLACK())
  f29 = circle(True{}, libm, f28, 345.0, 260.0, 35.0, J.Color.LIGHTGRAY())
  f30 = circle(True{}, libm, f29, (345.0 + F32.trunc((lx * 20.0 : F32)) : F32), (260.0 + F32.trunc((ly * 20.0 : F32)) : F32), 25.0, left)
  +right = Bool.pick(U32, down(core, pad, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_THUMB()), J.Color.RED(), J.Color.BLACK())
  f31 = circle(True{}, libm, f30, 465.0, 260.0, 40.0, J.Color.BLACK())
  f32 = circle(True{}, libm, f31, 465.0, 260.0, 35.0, J.Color.LIGHTGRAY())
  f33 = circle(True{}, libm, f32, (465.0 + F32.trunc((rx * 20.0 : F32)) : F32), (260.0 + F32.trunc((ry * 20.0 : F32)) : F32), 25.0, right)
  f34 = box(True{}, f33, 151.0, 110.0, 15.0, 70.0, J.Color.GRAY())
  f35 = box(True{}, f34, 644.0, 110.0, 15.0, 70.0, J.Color.GRAY())
  f36 = box(True{}, f35, 151.0, 110.0, 15.0, F32.trunc((((1.0 + lt) / 2.0) * 70.0 : F32)), J.Color.RED())
  box(True{}, f36, 644.0, 110.0, 15.0, F32.trunc((((1.0 + rt) / 2.0) * 70.0 : F32)), J.Color.RED())

def rewrap(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTexture(texture, 0, 0, tint); a texture that did not load refuses the frame.
def textured(texture: Maybe<J.Texture>, +tint: U32, frame: J.Frame) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (J.Frame.refuse(frame), None{})
    case Some{t}: rewrap(J.Draw.texture(frame, t, 0.0, 0.0, tint))

def label(text: Maybe<String>, +x: F32, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, 10.0, color)

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def has(index: Maybe<U32>) -> Bool:
  match index:
    case None{}: False{}
    case Some{_}: True{}

# The layout of the lowercase name: 0 with "xbox" or "x-box", 1 with "playstation" or "sony", else 2.
def kind(+lower: String) -> U32:
  Bool.pick(U32, has(J.Text.find_index(lower, "xbox")) || has(J.Text.find_index(lower, "x-box")), 0,
    Bool.pick(U32, has(J.Text.find_index(lower, "playstation")) || has(J.Text.find_index(lower, "sony")), 1, 2))

def pair(first: Maybe<F32>, second: Maybe<F32>) -> Maybe<M.Vector2>:
  match first second:
    case Some{+a} Some{+b}: Some{M.Vector2{a, b}}
    case _ _: None{}

# A stick axis inside its deadzone (0.1) is 0.
def dead(+value: F32) -> F32:
  Bool.pick(F32, (value > F32.neg(0.1) : F32) && (value < 0.1 : F32), 0.0, value)

# A trigger below its deadzone (-0.9) is -1.
def rest(+value: F32) -> F32:
  Bool.pick(F32, (value < F32.neg(0.9) : F32), F32.neg(1.0), value)

def sticks.at(left: M.Vector2, right: M.Vector2, triggers: M.Vector2) -> Sticks:
  M.Vector2{+lx, +ly} = left
  M.Vector2{+rx, +ry} = right
  M.Vector2{+lt, +rt} = triggers
  Sticks{dead(lx), dead(ly), dead(rx), dead(ry), rest(lt), rest(rt)}

def sticks.all(left: Maybe<M.Vector2>, right: Maybe<M.Vector2>, triggers: Maybe<M.Vector2>) -> Maybe<Sticks>:
  match left right triggers:
    case Some{+l} Some{+r} Some{+t}: Some{sticks.at(l, r, t)}
    case _ _ _: None{}

# GetGamepadAxisMovement of the six axes (left and right X and Y, the two triggers).
def sticks(+core: J.Core, +pad: U32) -> Maybe<Sticks>:
  sticks.all(pair(J.Input.get_gamepad_axis_movement(core, pad, 0), J.Input.get_gamepad_axis_movement(core, pad, 1)),
    pair(J.Input.get_gamepad_axis_movement(core, pad, 2), J.Input.get_gamepad_axis_movement(core, pad, 3)),
    pair(J.Input.get_gamepad_axis_movement(core, pad, 4), J.Input.get_gamepad_axis_movement(core, pad, 5)))

def layout.xbox(+libm: M.Libm, +core: J.Core, +pad: U32, +lx: F32, +ly: F32, +rx: F32, +ry: F32, +lt: F32, +rt: F32, ps3: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> Canvas:
  (frame, texture) = r
  Canvas{pad.xbox(libm, core, pad, lx, ly, rx, ry, lt, rt, frame), texture, ps3}

def layout.playstation(+libm: M.Libm, +core: J.Core, +pad: U32, +lx: F32, +ly: F32, +rx: F32, +ry: F32, +lt: F32, +rt: F32, xbox: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> Canvas:
  (frame, texture) = r
  Canvas{pad.playstation(libm, core, pad, lx, ly, rx, ry, lt, rt, frame), xbox, texture}

# DrawTexture(texXboxPad or texPs3Pad, 0, 0, DARKGRAY) under its layout, or the generic one.
def layout(+libm: M.Libm, +core: J.Core, +pad: U32, sticks: Sticks, canvas: Canvas, which: U32) -> Canvas:
  Sticks{+lx, +ly, +rx, +ry, +lt, +rt} = sticks
  Canvas{frame, xbox, ps3} = canvas
  match which:
    case 0: layout.xbox(libm, core, pad, lx, ly, rx, ry, lt, rt, ps3, textured(xbox, J.Color.DARKGRAY(), frame))
    case 1: layout.playstation(libm, core, pad, lx, ly, rx, ry, lt, rt, xbox, textured(ps3, J.Color.DARKGRAY(), frame))
    case _: Canvas{pad.generic(libm, core, pad, lx, ly, rx, ry, lt, rt, frame), xbox, ps3}

def axis.text(+i: U32, movement: Maybe<F32>) -> Maybe<String>:
  match movement:
    case None{}: None{}
    case Some{+m}: J.Text.format("AXIS %i: %.02f", [J.TextInt{i}, J.TextFloat{m}])

# for (i = 0; i < GetGamepadAxisCount(gamepad); i++) DrawText(TextFormat("AXIS %i: %.02f", i, GetGamepadAxisMovement(gamepad, i)), 20, 70 + 20*i, 10, DARKGRAY).
def axes(n: Nat, +i: U32, +core: J.Core, +pad: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: axes(p, (i + 1 : U32), core, pad, label(axis.text(i, J.Input.get_gamepad_axis_movement(core, pad, i)), 20.0, U32.to_f32((70 + 20 * i : U32)), J.Color.DARKGRAY(), frame))

# vibrateButton = { 10, 70.0f + 20*GetGamepadAxisCount(gamepad) + 20, 75, 24 }.
def button(+count: U32) -> J.Rectangle:
  J.Rectangle{10.0, (70.0 + U32.to_f32((20 * count : U32)) + 20.0 : F32), 75.0, 24.0}

# if (GetGamepadButtonPressed() != GAMEPAD_BUTTON_UNKNOWN) the button's number in RED, else "NONE" in GRAY.
def detected(none: Bool, +pressed: U32, frame: J.Frame) -> J.Frame:
  match none:
    case True{}: J.Draw.text(frame, "DETECTED BUTTON: NONE", 10.0, 430.0, 10.0, J.Color.GRAY())
    case False{}: label(J.Text.format("DETECTED BUTTON: %i", [J.TextInt{pressed}]), 10.0, 430.0, J.Color.RED(), frame)

# The axes, the vibrate button and the detected button.
def info(+core: J.Core, +pad: U32, +ok: Bool, +count: U32, canvas: Canvas) -> J.Core & (State & J.Frame):
  Canvas{frame, xbox, ps3} = canvas
  f1 = axes(U32.to_nat(count), 0, core, pad, label(J.Text.format("DETECTED AXIS [%i]:", [J.TextInt{count}]), 10.0, 50.0, J.Color.MAROON(), frame))
  f2 = J.Draw.text(J.Draw.rectangle_rec(f1, button(count), J.Color.SKYBLUE()), "VIBRATE", (10.0 + 14.0 : F32), F32.trunc((70.0 + U32.to_f32((20 * count : U32)) + 20.0 + 1.0 : F32)), 10.0, J.Color.DARKGRAY())
  (core, (State{pad, ok, xbox, ps3}, detected(U32.is_eq(J.Input.get_gamepad_button_pressed(core), 0), J.Input.get_gamepad_button_pressed(core), f2)))

def refused(+core: J.Core, +pad: U32, canvas: Canvas) -> J.Core & (State & J.Frame):
  Canvas{frame, xbox, ps3} = canvas
  (core, (State{pad, False{}, xbox, ps3}, J.Frame.refuse(frame)))

def found.drawn(+libm: M.Libm, +core: J.Core, +pad: U32, +ok: Bool, +which: U32, canvas: Canvas, sticks: Maybe<Sticks>, count: Maybe<U32>) -> J.Core & (State & J.Frame):
  match sticks count:
    case Some{+s} Some{+n}: info(core, pad, ok, n, layout(libm, core, pad, s, canvas, which))
    case _ _: refused(core, pad, canvas)

# The gamepad's name, then its layout by the name.
def found(name: Maybe<String>, +libm: M.Libm, +core: J.Core, +pad: U32, +ok: Bool, xbox: Maybe<J.Texture>, ps3: Maybe<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match name:
    case None{}: refused(core, pad, Canvas{frame, xbox, ps3})
    case Some{+n}: found.drawn(libm, core, pad, ok, kind(J.Text.to_lower(n)), Canvas{label(J.Text.format("GP%d: %s", [J.TextInt{pad}, J.TextString{n}]), 10.0, 10.0, J.Color.BLACK(), frame), xbox, ps3},
      sticks(core, pad), J.Input.get_gamepad_axis_count(core, pad))

def missing(+core: J.Core, +pad: U32, +ok: Bool, ps3: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, xbox) = r
  (core, (State{pad, ok, xbox, ps3}, frame))

# if (IsGamepadAvailable(gamepad)) the gamepad; else "NOT DETECTED" and DrawTexture(texXboxPad, 0, 0, LIGHTGRAY).
def draw.at(available: Bool, +libm: M.Libm, +core: J.Core, +pad: U32, +ok: Bool, xbox: Maybe<J.Texture>, ps3: Maybe<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match available:
    case True{}: found(J.Input.get_gamepad_name(pad), libm, core, pad, ok, xbox, ps3, frame)
    case False{}: missing(core, pad, ok, ps3, textured(xbox, J.Color.LIGHTGRAY(), label(J.Text.format("GP%d: NOT DETECTED", [J.TextInt{pad}]), 10.0, 10.0, J.Color.GRAY(), frame)))

def draw.kind(available: Maybe<Bool>, +libm: M.Libm, +core: J.Core, +pad: U32, +ok: Bool, xbox: Maybe<J.Texture>, ps3: Maybe<J.Texture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match available:
    case None{}: refused(core, pad, Canvas{frame, xbox, ps3})
    case Some{+a}: draw.at(a, libm, core, pad, ok, xbox, ps3, frame)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+pad, +ok, xbox, ps3} = state
  draw.kind(J.Input.is_gamepad_available(core, pad), libm, core, pad, ok, xbox, ps3, J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()))

# A click on the vibrate button: SetGamepadVibration(gamepad, 1.0, 1.0, 1.0).
def vibrated(on: Bool, +core: J.Core, +pad: U32) -> J.Core:
  match on:
    case False{}: core
    case True{}: J.Input.set_gamepad_vibration(core, pad, 1.0, 1.0, 1.0)

def update.count(count: Maybe<U32>, +core: J.Core, +pad: U32, +ok: Bool, xbox: Maybe<J.Texture>, ps3: Maybe<J.Texture>) -> J.Core & State:
  match count:
    case None{}: (core, State{pad, False{}, xbox, ps3})
    case Some{+n}: (vibrated(J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()) && J.Collision.point_rec(J.Input.get_mouse_position(core), button(n)), core, pad),
      State{pad, ok, xbox, ps3})

# LEFT (above gamepad 0) and RIGHT choose the gamepad; the vibrate button under the axes of that gamepad.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+pad, +ok, xbox, ps3} = state
  +less = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()) && (pad > 0 : U32), (pad - 1 : U32), pad)
  +next = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), (less + 1 : U32), less)
  update.count(J.Input.get_gamepad_axis_count(core, next), core, next, ok, xbox, ps3)

# The main loop's body; libm is the profile of the circles' and rounded rectangles' sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

def setup.xbox(+core: J.Core, ps3: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, xbox) = r
  (J.Core.set_target_fps(core, 60), (frame, State{0, True{}, xbox, ps3}))

# texXboxPad = LoadTexture("resources/xbox.png").
def setup.ps3(+dir: String, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, ps3) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/xbox.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.xbox(core, ps3, upload(frame, result))))

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): texPs3Pad = LoadTexture("resources/ps3.png"), the Xbox one, gamepad 0, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/ps3.png"),
    result => setup.ps3(dir, core, upload(frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input gamepad", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
