# raylib [core] example - viewport scaling, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_viewport_scaling.c (zlib/libpng,
# Copyright (c) 2025 Agnis Aldiņš (@nezvers)); see LICENSES/raylib.txt.
#
# A game drawn at a small resolution into a render texture and scaled to the
# window in one of six ways (integer or exact, keeping the aspect, the height
# or the width); four small buttons change the resolution and the way, each
# reloading the render texture. The example reloads it in the update; here
# the draw does (it holds the frame), before anything is drawn, with the
# same texture ids. The mouse is mapped into the render texture with the
# example's formula (it uses the horizontal ratio for both axes). A render
# texture size Jonlib refuses refuses the frame. DrawCircleV's and
# DrawTexturePro's sinf/cosf follow the libm profile. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type View is Data:
  View{source: J.Rectangle, dest: J.Rectangle}

# kind: viewportType; index: resolutionIndex; gw, gh: the game's size; sw, sh: the window's;
# reload: the render texture must be reloaded for this view; mouse: the mouse inside the render texture.
type Game is Data:
  Game{kind: U32, index: U32, gw: U32, gh: U32, sw: U32, sh: U32, view: View, reload: Bool, mouse: M.Vector2}

type State is Type:
  State{target: Maybe<J.RenderTexture>, game: Game}

def name(kind: U32) -> String:
  match kind:
    case 0: "KEEP_ASPECT_INTEGER"
    case 1: "KEEP_HEIGHT_INTEGER"
    case 2: "KEEP_WIDTH_INTEGER"
    case 3: "KEEP_ASPECT"
    case 4: "KEEP_HEIGHT"
    case _: "KEEP_WIDTH"

def resolution.width(index: U32) -> U32:
  match index:
    case 0: 64
    case 1: 256
    case 2: 320
    case _: 3840

def resolution.height(index: U32) -> U32:
  match index:
    case 0: 64
    case 1: 240
    case 2: 180
    case _: 2160

# The destination: centered, each value (float)(int).
def centered(+sw: F32, +sh: F32, +width: F32, +height: F32) -> J.Rectangle:
  J.Rectangle{F32.trunc(((sw - width) * 0.5 : F32)), F32.trunc(((sh - height) * 0.5 : F32)), F32.trunc(width), F32.trunc(height)}

# KeepAspectCenteredInteger (whole) and KeepAspectCentered: the smaller of the two ratios.
def aspect(+whole: Bool, +sw: U32, +sh: U32, +gw: U32, +gh: U32) -> View:
  +ratio = Bool.pick(F32, whole, U32.to_f32(U32.min((sw / gw : U32), (sh / gh : U32))), F32.min((U32.to_f32(sw) / U32.to_f32(gw) : F32), (U32.to_f32(sh) / U32.to_f32(gh) : F32)))
  View{J.Rectangle{0.0, U32.to_f32(gh), U32.to_f32(gw), F32.neg(U32.to_f32(gh))},
    centered(U32.to_f32(sw), U32.to_f32(sh), (U32.to_f32(gw) * ratio : F32), (U32.to_f32(gh) * ratio : F32))}

# KeepHeightCenteredInteger and KeepHeightCentered (the same arithmetic): the source widens to the window's aspect.
def tall(+sw: U32, +sh: U32, +gh: U32) -> View:
  +ratio = (U32.to_f32(sh) / U32.to_f32(gh) : F32)
  +width = F32.trunc((U32.to_f32(sw) / ratio : F32))
  View{J.Rectangle{0.0, 0.0, width, F32.neg(U32.to_f32(gh))}, centered(U32.to_f32(sw), U32.to_f32(sh), (width * ratio : F32), (U32.to_f32(gh) * ratio : F32))}

# KeepWidthCenteredInteger and KeepWidthCentered (the same arithmetic): the source grows to the window's aspect.
def wide(+sw: U32, +sh: U32, +gw: U32) -> View:
  +ratio = (U32.to_f32(sw) / U32.to_f32(gw) : F32)
  +height = F32.trunc((U32.to_f32(sh) / ratio : F32))
  View{J.Rectangle{0.0, 0.0, U32.to_f32(gw), (height * F32.neg(1.0) : F32)}, centered(U32.to_f32(sw), U32.to_f32(sh), (U32.to_f32(gw) * ratio : F32), (height * ratio : F32))}

# ResizeRenderSize's rectangles for the viewport type.
def fitted(kind: U32, +sw: U32, +sh: U32, +gw: U32, +gh: U32) -> View:
  match kind:
    case 0: aspect(True{}, sw, sh, gw, gh)
    case 1: tall(sw, sh, gh)
    case 2: wide(sw, sh, gw)
    case 3: aspect(False{}, sw, sh, gw, gh)
    case 4: tall(sw, sh, gh)
    case _: wide(sw, sh, gw)

def button(index: U32) -> J.Rectangle:
  match index:
    case 0: J.Rectangle{200.0, 30.0, 10.0, 10.0}
    case 1: J.Rectangle{215.0, 30.0, 10.0, 10.0}
    case 2: J.Rectangle{200.0, 45.0, 10.0, 10.0}
    case _: J.Rectangle{215.0, 45.0, 10.0, 10.0}

# Screen2RenderTexturePosition: (point - scaled.xy) times textureRect.width/scaledRect.width, for both axes.
def inside(+point: M.Vector2, +view: View) -> M.Vector2:
  M.Vector2{+x, +y} = point
  View{+source, +dest} = view
  J.Rectangle{_, _, +tw, _} = source
  J.Rectangle{+dx, +dy, +dw, _} = dest
  M.Vector2{((x - dx) * (tw / dw) : F32), ((y - dy) * (tw / dw) : F32)}

# The four buttons: the previous or next resolution, the previous or next viewport type; any of them, or a
# resized window, recomputes the rectangles with the window's size and reloads the render texture.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{target, +game} = state
  Game{+kind, +index, _, _, +sw, +sh, +view, +reload, _} = game
  +mouse = J.Input.get_mouse_position(core)
  +pressed = J.Input.is_mouse_button_pressed(core, 0)
  +less = pressed && J.Collision.point_rec(mouse, button(0))
  +more = pressed && J.Collision.point_rec(mouse, button(1))
  +back = pressed && J.Collision.point_rec(mouse, button(2))
  +next = pressed && J.Collision.point_rec(mouse, button(3))
  +i1 = Bool.pick(U32, less, ((index + 3) % 4 : U32), index)
  +i2 = Bool.pick(U32, more, ((i1 + 1) % 4 : U32), i1)
  +k1 = Bool.pick(U32, back, ((kind + 5) % 6 : U32), kind)
  +k2 = Bool.pick(U32, next, ((k1 + 1) % 6 : U32), k1)
  +resize = J.Core.is_window_resized(core) || less || more || back || next
  +w = Bool.pick(U32, resize, J.Core.get_screen_width(core), sw)
  +h = Bool.pick(U32, resize, J.Core.get_screen_height(core), sh)
  +fresh = Bool.pick(View, resize, fitted(k2, w, h, resolution.width(i2), resolution.height(i2)), view)
  (core, State{target, Game{k2, i2, resolution.width(i2), resolution.height(i2), w, h, fresh, reload || resize, inside(mouse, fresh)}})

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 15.0, y, 10.0, J.Color.BLACK())

def ratio.label(valid: Bool, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Draw.text(frame, "Scale ratio: INVALID", 15.0, 60.0, 10.0, J.Color.BLACK())
    case True{}: label(J.Text.format("Scale ratio: %.2f x %.2f", [J.TextFloat{x}, J.TextFloat{y}]), 60.0, frame)

def arrow(+text: String, +rec: J.Rectangle, frame: J.Frame) -> J.Frame:
  J.Rectangle{+x, +y, _, _} = rec
  J.Draw.text(frame, text, (F32.trunc(x) + 3.0 : F32), (F32.trunc(y) + 1.0 : F32), 10.0, J.Color.BLACK())

# The information box and the four buttons.
def info(+game: Game, frame: J.Frame) -> J.Frame:
  Game{+kind, _, +gw, +gh, +sw, +sh, +view, _, _} = game
  View{+source, +dest} = view
  J.Rectangle{_, _, +tw, +th} = source
  J.Rectangle{_, _, +dw, +dh} = dest
  f1 = J.Draw.rectangle_lines_ex(J.Draw.rectangle_rec(frame, J.Rectangle{5.0, 5.0, 330.0, 105.0}, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.7)), J.Rectangle{5.0, 5.0, 330.0, 105.0}, 1.0, J.Color.BLUE())
  f2 = label(J.Text.format("Window Resolution: %d x %d", [J.TextInt{sw}, J.TextInt{sh}]), 15.0, f1)
  f3 = label(J.Text.format("Game Resolution: %d x %d", [J.TextInt{gw}, J.TextInt{gh}]), 30.0, f2)
  f4 = label(J.Text.format("Type: %s", [J.TextString{name(kind)}]), 45.0, f3)
  f5 = ratio.label(Bool.not((dw / tw < 0.001 : F32) || (F32.neg(dh) / th < 0.001 : F32)), (dw / tw : F32), (F32.neg(dh) / th : F32), f4)
  f6 = label(J.Text.format("Source size: %.2f x %.2f", [J.TextFloat{tw}, J.TextFloat{F32.neg(th)}]), 75.0, f5)
  f7 = label(J.Text.format("Destination size: %.2f x %.2f", [J.TextFloat{dw}, J.TextFloat{dh}]), 90.0, f6)
  f8 = J.Draw.rectangle_rec(J.Draw.rectangle_rec(J.Draw.rectangle_rec(J.Draw.rectangle_rec(f7, button(2), J.Color.SKYBLUE()), button(3), J.Color.SKYBLUE()), button(0), J.Color.SKYBLUE()), button(1), J.Color.SKYBLUE())
  arrow(">", button(1), arrow("<", button(0), arrow(">", button(3), arrow("<", button(2), f8))))

# The reload is done.
def settled(+game: Game) -> Game:
  Game{+kind, +index, +gw, +gh, +sw, +sh, +view, _, +mouse} = game
  Game{kind, index, gw, gh, sw, sh, view, False{}, mouse}

def unloaded(frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Frame:
  match target:
    case None{}: frame
    case Some{t}: J.RenderTexture.unload(frame, t)

def loaded(+view: View, frame: J.Frame) -> J.Frame & Maybe<J.RenderTexture>:
  View{+source, _} = view
  J.Rectangle{_, _, +w, +h} = source
  J.RenderTexture.load(frame, F32.to_u32(w), F32.to_u32(F32.neg(h)))

def draw.shown(+libm: M.Libm, +core: J.Core, +game: Game, +id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{Some{J.RenderTexture{id, texture, depth}}, settled(game)}, info(game, frame)))

# DrawTexturePro(target.texture, sourceRect, destRect, (0, 0), 0, WHITE).
def draw.screen(+libm: M.Libm, +core: J.Core, +game: Game, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  Game{_, _, _, _, _, _, +view, _, _} = game
  View{+source, +dest} = view
  J.RenderTexture{+id, texture, +depth} = target
  draw.shown(libm, core, game, id, depth, J.Draw.texture_pro_for(libm, J.Frame.clear_background(frame, J.Color.BLACK()), texture, source, dest, M.Vector2.zero(), 0.0, J.Color.WHITE()))

def draw.ended(+libm: M.Libm, +core: J.Core, +game: Game, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{None{}, settled(game)}, J.Frame.refuse(frame)))
    case Some{t}: draw.screen(libm, core, game, frame, t)

# The game: ClearBackground(WHITE); DrawCircleV(textureMousePosition, 20, LIME).
def draw.game(+libm: M.Libm, +core: J.Core, +game: Game, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  Game{_, _, _, _, _, _, _, _, +mouse} = game
  (frame, target) = r
  match target:
    case None{}: (core, (State{None{}, settled(game)}, J.Frame.refuse(frame)))
    case Some{t}: draw.ended(libm, core, game, J.Frame.end_texture_mode(J.Draw.circle_v_for(libm, J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.WHITE()), mouse, 20.0, J.Color.LIME())))

# UnloadRenderTexture(*target); *target = LoadRenderTexture((int)sourceRect->width, -(int)sourceRect->height).
def reloaded(reload: Bool, +view: View, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match reload:
    case False{}: (frame, target)
    case True{}: loaded(view, unloaded(frame, target))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{target, +game} = state
  Game{_, _, _, _, _, _, +view, +reload, _} = game
  draw.game(libm, core, game, reloaded(reload, view, frame, target))

# The main loop's body; libm is the profile of DrawCircleV's and DrawTexturePro's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.loaded(+core: J.Core, +game: Game, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{target, game}))

# After SetConfigFlags(FLAG_WINDOW_RESIZABLE) and InitWindow(800, 450): the 64x64 game kept in integer
# aspect, its render texture, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(core, Game{0, 0, 64, 64, J.Core.get_screen_width(core), J.Core.get_screen_height(core), fitted(0, J.Core.get_screen_width(core), J.Core.get_screen_height(core), 64, 64), False{}, M.Vector2.zero()},
    loaded(fitted(0, J.Core.get_screen_width(core), J.Core.get_screen_height(core), 64, 64), frame))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - viewport scaling", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
