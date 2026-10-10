# raylib [textures] example - mouse painting, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_mouse_painting.c
# (zlib/libpng, Copyright (c) 2019-2025 Chris Dill (@MysteriousSpace) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A canvas (a render texture) painted with circles under the left mouse
# button and erased under the right one, a palette of 23 colors picked by
# click or LEFT/RIGHT, the brush sized by the wheel, C to clear. The
# example draws into the render texture before BeginDrawing; here the draw
# does that first, in the same order. Its SAVE button (and S) exports the
# canvas to a file, which J.Program's update cannot do: that frame is
# refused. DrawCircle's sinf/cosf follow the libm profile (whole degrees
# only). The example runs at 120 frames a second. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# selected, previous, hover: colorSelected, colorSelectedPrev and colorMouseHover (23: none); was: mouseWasPressed;
# clear, paint, erase: what this frame draws into the canvas (paint with the color index ink).
type Brush is Data:
  Brush{valid: Bool, selected: U32, previous: U32, hover: U32, size: F32, was: Bool, save: Bool, mouse: M.Vector2, clear: Bool, paint: Bool, ink: U32, erase: Bool}

type State is Type:
  State{target: Maybe<J.RenderTexture>, brush: Brush}

def color(index: U32) -> U32:
  match index:
    case 0: J.Color.RAYWHITE()
    case 1: J.Color.YELLOW()
    case 2: J.Color.GOLD()
    case 3: J.Color.ORANGE()
    case 4: J.Color.PINK()
    case 5: J.Color.RED()
    case 6: J.Color.MAROON()
    case 7: J.Color.GREEN()
    case 8: J.Color.LIME()
    case 9: J.Color.DARKGREEN()
    case 10: J.Color.SKYBLUE()
    case 11: J.Color.BLUE()
    case 12: J.Color.DARKBLUE()
    case 13: J.Color.PURPLE()
    case 14: J.Color.VIOLET()
    case 15: J.Color.DARKPURPLE()
    case 16: J.Color.BEIGE()
    case 17: J.Color.BROWN()
    case 18: J.Color.DARKBROWN()
    case 19: J.Color.LIGHTGRAY()
    case 20: J.Color.GRAY()
    case 21: J.Color.DARKGRAY()
    case _: J.Color.BLACK()

# colorsRecs[i] = (10 + 30*i + 2*i, 10, 30, 30).
def swatch(+i: U32) -> J.Rectangle:
  J.Rectangle{(10.0 + 30.0 * U32.to_f32(i) + U32.to_f32((2 * i : U32)) : F32), 10.0, 30.0, 30.0}

# The first swatch under the mouse, else none.
def hovered(n: Nat, +i: U32, +mouse: M.Vector2) -> U32:
  match n:
    case 0n: 23
    case 1n+p: Bool.pick(U32, J.Collision.point_rec(mouse, swatch(i)), i, hovered(p, (i + 1 : U32), mouse))

def update.brush(+core: J.Core, +brush: Brush) -> Brush:
  Brush{+valid, +selected, +previous, _, +size, +was, _, _, _, _, _, _} = brush
  +mouse = J.Input.get_mouse_position(core)
  +keyed = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), U32.min((selected + 1 : U32), 22),
    Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()) && (selected > 0 : U32), (selected - 1 : U32), selected))
  +hover = hovered(23n, 0, mouse)
  +pick = (hover < 23 : U32) && J.Input.is_mouse_button_pressed(core, 0)
  +chosen = Bool.pick(U32, pick, hover, keyed)
  +kept = Bool.pick(U32, pick, hover, previous)
  +wheel = (size + J.Input.get_mouse_wheel_move(core) * 5.0 : F32)
  +low = Bool.pick(F32, (wheel < 2.0 : F32), 2.0, wheel)
  +right = J.Input.is_mouse_button_down(core, 1)
  +back = Bool.not(right) && J.Input.is_mouse_button_released(core, 1) && was
  +over = J.Collision.point_rec(mouse, J.Rectangle{750.0, 10.0, 40.0, 30.0})
  Brush{valid && Bool.not((over && J.Input.is_mouse_button_released(core, 0)) || J.Input.is_key_pressed(core, J.KeyboardKey.KEY_S())),
    Bool.pick(U32, right, 0, Bool.pick(U32, back, kept, chosen)), Bool.pick(U32, right && Bool.not(was), chosen, kept), hover,
    Bool.pick(F32, (low > 50.0 : F32), 50.0, low), right || (was && Bool.not(back)), over, mouse, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_C()),
    J.Input.is_mouse_button_down(core, 0) || U32.is_eq(J.Gestures.get_detected(core), J.Gesture.GESTURE_DRAG()), chosen, right}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{target, +brush} = state
  (core, State{target, update.brush(core, brush)})

def cleared(clear: Bool, frame: J.Frame) -> J.Frame:
  match clear:
    case False{}: frame
    case True{}: J.Frame.clear_background(frame, J.Color.RAYWHITE())

# if (mousePos.y > 50) DrawCircle((int)mousePos.x, (int)mousePos.y, brushSize, color).
def dabbed(dab: Bool, +libm: M.Libm, +mouse: M.Vector2, +size: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match dab:
    case False{}: frame
    case True{}:
      M.Vector2{+x, +y} = mouse
      J.Draw.circle_for(libm, frame, F32.trunc(x), F32.trunc(y), size, color)

# The canvas pass: C clears, the left button paints, the right one erases.
def canvas(+libm: M.Libm, +brush: Brush, frame: J.Frame) -> J.Frame:
  Brush{_, _, _, _, +size, _, _, +mouse, +clear, +paint, +ink, +erase} = brush
  M.Vector2{_, +y} = mouse
  dabbed(erase && (y > 50.0 : F32), libm, mouse, size, color(0), dabbed(paint && (y > 50.0 : F32), libm, mouse, size, color(ink), cleared(clear, frame)))

def swatches(n: Nat, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: swatches(p, (i + 1 : U32), J.Draw.rectangle_rec(frame, swatch(i), color(i)))

def highlighted(shown: Bool, +hover: U32, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: J.Draw.rectangle_rec(frame, swatch(hover), J.Color.with_alpha(J.Color.WHITE(), 0.6))

def selection(+rec: J.Rectangle, frame: J.Frame) -> J.Frame:
  J.Rectangle{+x, +y, +w, +h} = rec
  J.Draw.rectangle_lines_ex(frame, J.Rectangle{(x - 2.0 : F32), (y - 2.0 : F32), (w + 4.0 : F32), (h + 4.0 : F32)}, 2.0, J.Color.BLACK())

def preview.at(+libm: M.Libm, +brush: Brush, +ix: F32, +iy: F32, frame: J.Frame, right: Bool) -> J.Frame:
  Brush{_, +selected, _, _, +size, _, _, +mouse, _, _, _, _} = brush
  M.Vector2{+x, +y} = mouse
  match right:
    case True{}: J.Draw.circle_lines_for(libm, frame, F32.trunc(x), F32.trunc(y), size, J.Color.GRAY())
    case False{}: J.Draw.circle_for(libm, frame, ix, iy, size, color(selected))

# The brush preview: DrawCircleLines under the right button, else DrawCircle(GetMouseX(), GetMouseY(), brushSize, color).
def preview(shown: Bool, +libm: M.Libm, +core: J.Core, +brush: Brush, mx: Maybe<U32>, my: Maybe<U32>, frame: J.Frame) -> J.Frame:
  match shown mx my:
    case False{} _ _: frame
    case True{} Some{+ix} Some{+iy}: preview.at(libm, brush, U32.to_f32(ix), U32.to_f32(iy), frame, J.Input.is_mouse_button_down(core, 1))
    case True{} _ _: J.Frame.refuse(frame)

def panel(+core: J.Core, +brush: Brush, frame: J.Frame) -> J.Frame:
  Brush{_, +selected, _, +hover, _, _, +save, _, _, _, _, _} = brush
  +width = U32.to_f32(J.Core.get_screen_width(core))
  f1 = J.Draw.line(J.Draw.rectangle(frame, 0.0, 0.0, width, 50.0, J.Color.RAYWHITE()), 0.0, 50.0, width, 50.0, J.Color.LIGHTGRAY())
  f2 = J.Draw.rectangle_lines(swatches(23n, 0, f1), 10.0, 10.0, 30.0, 30.0, J.Color.LIGHTGRAY())
  f3 = selection(swatch(selected), highlighted((hover < 23 : U32), hover, f2))
  J.Draw.text(J.Draw.rectangle_lines_ex(f3, J.Rectangle{750.0, 10.0, 40.0, 30.0}, 2.0, Bool.pick(U32, save, J.Color.RED(), J.Color.BLACK())), "SAVE!", 755.0, 20.0, 10.0,
    Bool.pick(U32, save, J.Color.RED(), J.Color.BLACK()))

def draw.shown(+libm: M.Libm, +core: J.Core, +brush: Brush, +id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  Brush{_, _, _, _, _, _, _, +mouse, _, _, _, _} = brush
  M.Vector2{_, +y} = mouse
  (frame, texture) = r
  (core, (State{Some{J.RenderTexture{id, texture, depth}}, brush},
    panel(core, brush, preview((y > 50.0 : F32), libm, core, brush, J.Input.get_mouse_x(core), J.Input.get_mouse_y(core), frame))))

def draw.at(+libm: M.Libm, +core: J.Core, +brush: Brush, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.shown(libm, core, brush, id, depth, J.Draw.texture_rec(frame, J.Texture{tid, w, h, format, linear, alpha, texels},
    J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2.zero(), J.Color.WHITE()))

# DrawTextureRec(target.texture, (0, 0, width, -height), (0, 0), WHITE).
def draw.screen(+libm: M.Libm, +core: J.Core, +brush: Brush, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{None{}, brush}, J.Frame.refuse(frame)))
    case Some{t}: draw.at(libm, core, brush, J.Frame.clear_background(frame, J.Color.RAYWHITE()), t)

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +brush: Brush, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match valid target:
    case True{} Some{t}: draw.screen(libm, core, brush, J.Frame.end_texture_mode(canvas(libm, brush, J.Frame.begin_texture_mode(frame, t))))
    case False{} Some{t}: (core, (State{Some{t}, brush}, J.Frame.refuse(frame)))
    case _ None{}: (core, (State{None{}, brush}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{target, +brush} = state
  Brush{+valid, _, _, _, _, _, _, _, _, _, _, _} = brush
  draw.valid(valid, libm, core, brush, frame, target)

# The main loop's body; libm is the profile of DrawCircle's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.cleared(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 120), (frame, State{target, Brush{True{}, 0, 0, 0, 20.0, False{}, False{}, M.Vector2.zero(), False{}, False{}, 0, False{}}}))

# BeginTextureMode(target); ClearBackground(colors[0]); EndTextureMode().
def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  match target:
    case None{}: setup.cleared(core, (frame, None{}))
    case Some{t}: setup.cleared(core, J.Frame.end_texture_mode(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.RAYWHITE())))

# After InitWindow(800, 450): the 800x450 canvas cleared to RAYWHITE, SetTargetFPS(120).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(core, J.RenderTexture.load(frame, 800, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - mouse painting", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
