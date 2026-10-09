# raylib [shapes] example - lines drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_lines_drawing.c (zlib/libpng,
# Copyright (c) 2025 Robin (@RobinsAviary)); see LICENSES/raylib.txt.
#
# Paint with the left button (the hue follows the distance drawn), erase
# with the right one, clear with the middle one; the wheel sets the
# thickness. The canvas is a render texture. See docs/DRIVER.md.
#
# raylib draws into the canvas in its update, before BeginDrawing; here the
# update records that work and the draw does it first, in texture mode, which
# gives the same pixels (BeginDrawing's modelview is the identity here).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A stroke from the previous to the current mouse position.
type Stroke is Data:
  Stroke{from: M.Vector2, to: M.Vector2, thick: F32, color: U32}

type State is Type:
  State{canvas: Maybe<J.RenderTexture>, previous: M.Vector2, thick: F32, hue: F32, start: Bool, left: Bool, clear: Bool, stroke: Maybe<Stroke>}

# while (lineHue >= 360.0f) lineHue -= 360.0f;
def wrap(fuel: Nat, +hue: F32) -> F32:
  match fuel:
    case 0n: hue
    case 1n+p: Bool.pick(F32, (hue >= 360.0 : F32), wrap(p, (hue - 360.0 : F32)), hue)

def stroke(+left: Bool, +right: Bool, +from: M.Vector2, +to: M.Vector2, +thick: F32, +hue: F32) -> Maybe<Stroke>:
  Bool.pick(Maybe<Stroke>, left, Some{Stroke{from, to, thick, J.Color.from_hsv(hue, 1.0, 1.0)}},
    Bool.pick(Maybe<Stroke>, right, Some{Stroke{from, to, thick, J.Color.RAYWHITE()}}, None{}))

def update(+core: J.Core, state: State) -> J.Core & State:
  State{canvas, +previous, +thick, +hue, +start, _, _, _} = state
  +mouse = J.Input.get_mouse_position(core)
  +left = J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  +right = J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_RIGHT())
  +h = Bool.pick(F32, left, wrap(4n, (hue + M.Vector2.distance(previous, mouse) / 3.0 : F32)), hue)
  +s = start && Bool.not(J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()))
  +clear = J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_MIDDLE())
  +t = M.Math.clamp((thick + J.Input.get_mouse_wheel_move(core) : F32), 1.0, 500.0)
  (core, State{canvas, mouse, t, h, s, left, clear, stroke(left, right, previous, mouse, thick, h)})

# BeginTextureMode(canvas) ... EndTextureMode() around `paint`.
def canvas.mode(frame: J.Frame, canvas: Maybe<J.RenderTexture>, paint: J.Frame -> J.Frame) -> J.Frame & Maybe<J.RenderTexture>:
  match canvas:
    case None{}: (frame, None{})
    case Some{target}: J.Frame.end_texture_mode(paint(J.Frame.begin_texture_mode(frame, target)))

def canvas.clear(clear: Bool, frame: J.Frame, canvas: Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match clear:
    case False{}: (frame, canvas)
    case True{}: canvas.mode(frame, canvas, f => J.Frame.clear_background(f, J.Color.RAYWHITE()))

def canvas.stroke(+libm: M.Libm, +s: Stroke, frame: J.Frame) -> J.Frame:
  Stroke{+from, +to, +thick, +color} = s
  f1 = J.Draw.circle_v_for(libm, frame, from, (thick / 2.0 : F32), color)
  f2 = J.Draw.circle_v_for(libm, f1, to, (thick / 2.0 : F32), color)
  J.Draw.line_ex(f2, from, to, thick, color)

def canvas.paint(+libm: M.Libm, stroke: Maybe<Stroke>, frame: J.Frame, canvas: Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match stroke:
    case None{}: (frame, canvas)
    case Some{+s}: canvas.mode(frame, canvas, f => canvas.stroke(libm, s, f))

def canvas.painted(+libm: M.Libm, stroke: Maybe<Stroke>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, canvas) = r
  canvas.paint(libm, stroke, frame, canvas)

# DrawTextureRec(canvas.texture, (0, 0, width, -height), (0, 0), WHITE): the
# render texture flipped back upright.
def canvas.shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

def canvas.show.at(frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  canvas.shown(id, depth, J.Draw.texture_rec(frame, J.Texture{tid, w, h, format, linear, alpha, texels},
    J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2.zero(), J.Color.WHITE()))

def canvas.show(r: J.Frame & Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, canvas) = r
  match canvas:
    case None{}: (frame, None{})
    case Some{target}: canvas.show.at(frame, target)

def draw.cursor(left: Bool, +libm: M.Libm, +mouse: M.Vector2, +thick: F32, frame: J.Frame) -> J.Frame:
  match left:
    case True{}: frame
    case False{}: J.Draw.circle_lines_v_for(libm, frame, mouse, (thick / 2.0 : F32), J.Color.rgba(127, 127, 127, 127))

def draw.hint(start: Bool, frame: J.Frame) -> J.Frame:
  match start:
    case False{}: frame
    case True{}: J.Draw.text(frame, "try clicking and dragging!", 275.0, 215.0, 20.0, J.Color.LIGHTGRAY())

def draw.done(+core: J.Core, +libm: M.Libm, +previous: M.Vector2, +thick: F32, +hue: F32, +start: Bool, +left: Bool, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, canvas) = r
  (core, (State{canvas, previous, thick, hue, start, left, False{}, None{}}, draw.hint(start, draw.cursor(left, libm, previous, thick, frame))))

# previous already holds this frame's GetMousePosition().
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{canvas, +previous, +thick, +hue, +start, +left, +clear, stroke} = state
  draw.done(core, libm, previous, thick, hue, start, left, canvas.show(canvas.painted(libm, stroke, canvas.clear(clear, frame, canvas))))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.cleared(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, canvas) = r
  (J.Core.set_target_fps(core, 60), (frame, State{canvas, J.Input.get_mouse_position(core), 8.0, 0.0, True{}, False{}, False{}, None{}}))

# After InitWindow(800, 450): the 800x450 canvas cleared to RAYWHITE, the
# thickness 8, the hue 0, SetTargetFPS(60).
def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (f, canvas) = r
  setup.cleared(core, canvas.clear(True{}, f, canvas))

def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(core, J.RenderTexture.load(frame, 800, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - lines drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
