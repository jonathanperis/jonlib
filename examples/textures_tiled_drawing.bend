# raylib [textures] example - tiled drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_tiled_drawing.c
# (zlib/libpng, Copyright (c) 2020-2025 Vlad Adrian (@demizdor) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# One of six patterns of a texture tiled over the area beside an options
# panel, scaled (UP/DOWN) and turned (LEFT/RIGHT) and tinted by one of ten
# colors; the mouse picks the pattern and the color, SPACE resets. The
# example's DrawTextureTiled is ported as its general case (rows and
# columns): its three special cases draw the same tiles with the same
# numbers when no full tile fits one way or the other. DrawTexturePro's
# sinf/cosf follow the libm profile. LoadTexture of a .png is the PNG loader
# (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{pattern: Maybe<J.Texture>, active: U32, color: U32, scale: F32, rotation: F32}

# The tiled area (x, y, w, h), the tile's size on screen and its source.
type Area is Data:
  Area{source: J.Rectangle, x: F32, y: F32, w: F32, h: F32, tw: F32, th: F32, rotation: F32, tint: U32}

# recPattern[]: the patterns inside the texture.
def pattern(index: U32) -> J.Rectangle:
  match index:
    case 0: J.Rectangle{3.0, 3.0, 66.0, 66.0}
    case 1: J.Rectangle{75.0, 3.0, 100.0, 100.0}
    case 2: J.Rectangle{3.0, 75.0, 66.0, 66.0}
    case 3: J.Rectangle{7.0, 156.0, 50.0, 50.0}
    case 4: J.Rectangle{85.0, 106.0, 90.0, 45.0}
    case _: J.Rectangle{75.0, 154.0, 100.0, 60.0}

def tint(index: U32) -> U32:
  match index:
    case 0: J.Color.BLACK()
    case 1: J.Color.MAROON()
    case 2: J.Color.ORANGE()
    case 3: J.Color.BLUE()
    case 4: J.Color.PURPLE()
    case 5: J.Color.BEIGE()
    case 6: J.Color.LIME()
    case 7: J.Color.RED()
    case 8: J.Color.DARKGRAY()
    case _: J.Color.SKYBLUE()

# colorRec[i]: two rows of five, 32x16, 8 apart, from (2 + MARGIN_SIZE, 22 + 256 + MARGIN_SIZE).
def color.cell(+i: U32) -> J.Rectangle:
  J.Rectangle{(2.0 + 8.0 + U32.to_f32((40 * (i % 5) : U32)) : F32), (22.0 + 256.0 + 8.0 + U32.to_f32((24 * (i / 5) : U32)) : F32), (16.0 * 2.0 : F32), 16.0}

# The pattern as the panel shows it: moved by (2 + MARGIN_SIZE, 40 + MARGIN_SIZE).
def pattern.moved(+source: J.Rectangle) -> J.Rectangle:
  J.Rectangle{+x, +y, +w, +h} = source
  J.Rectangle{(10.0 + x : F32), (48.0 + y : F32), w, h}

def pattern.cell(+i: U32) -> J.Rectangle:
  pattern.moved(pattern(i))

# The first pattern under the mouse, else the current one.
def pattern.at(n: Nat, +i: U32, +mouse: M.Vector2, +current: U32) -> U32:
  match n:
    case 0n: current
    case 1n+p: Bool.pick(U32, J.Collision.point_rec(mouse, pattern.cell(i)), i, pattern.at(p, (i + 1 : U32), mouse, current))

def color.at(n: Nat, +i: U32, +mouse: M.Vector2, +current: U32) -> U32:
  match n:
    case 0n: current
    case 1n+p: Bool.pick(U32, J.Collision.point_rec(mouse, color.cell(i)), i, color.at(p, (i + 1 : U32), mouse, current))

# A left click picks; UP/DOWN scale by 0.25 inside (0, 10]; LEFT/RIGHT turn
# by 25 degrees; SPACE resets both.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{pattern, +active, +color, +scale, +rotation} = state
  +mouse = J.Input.get_mouse_position(core)
  +click = J.Input.is_mouse_button_pressed(core, 0)
  +up = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP()), (scale + 0.25 : F32), scale)
  +down = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN()), (up - 0.25 : F32), up)
  +sized = Bool.pick(F32, (down > 10.0 : F32), 10.0, Bool.pick(F32, (down <= 0.0 : F32), 0.25, down))
  +left = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()), (rotation - 25.0 : F32), rotation)
  +right = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), (left + 25.0 : F32), left)
  +reset = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE())
  (core, State{pattern, Bool.pick(U32, click, pattern.at(6n, 0, mouse, active), active), Bool.pick(U32, click, color.at(10n, 0, mouse, color), color),
    Bool.pick(F32, reset, 1.0, sized), Bool.pick(F32, reset, 0.0, right)})

# DrawTexturePro of the source's corner (sw x sh) to (x + dx, y + dy, w, h).
def tile(+libm: M.Libm, +area: Area, +sw: F32, +sh: F32, +dx: F32, +dy: F32, +w: F32, +h: F32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  Area{+source, +x, +y, _, _, _, _, +rotation, +tint} = area
  J.Rectangle{+sx, +sy, _, _} = source
  (frame, texture) = r
  J.Draw.texture_pro_for(libm, frame, texture, J.Rectangle{sx, sy, sw, sh}, J.Rectangle{(x + dx : F32), (y + dy : F32), w, h}, M.Vector2.zero(), rotation, tint)

# One column at dx, w wide from a source sw wide: n full tiles, then the last
# cut to the area ((dest.height - dy)/tileHeight of the source's height).
def column(+libm: M.Libm, +area: Area, n: Nat, +sw: F32, +dx: F32, +w: F32, +dy: F32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  Area{+source, _, _, _, +h, _, +th, _, _} = area
  J.Rectangle{_, _, _, +sh} = source
  match n:
    case 0n: tile(libm, area, sw, (((h - dy) / th) * sh : F32), dx, dy, w, (h - dy : F32), r)
    case 1n+p: column(libm, area, p, sw, dx, w, (dy + th : F32), tile(libm, area, sw, sh, dx, dy, w, th, r))

# m full columns, then the last cut to the area ((dest.width - dx)/tileWidth of the source's width).
def columns(+libm: M.Libm, +area: Area, m: Nat, +rows: U32, +dx: F32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  Area{+source, _, _, +w, _, +tw, _, _, _} = area
  J.Rectangle{_, _, +sw, _} = source
  match m:
    case 0n: column(libm, area, U32.to_nat(rows), (((w - dx) / tw) * sw : F32), dx, (w - dx : F32), 0.0, r)
    case 1n+p: columns(libm, area, p, rows, (dx + tw : F32), column(libm, area, U32.to_nat(rows), sw, dx, tw, 0.0, r))

def tiled.in(inside: Bool, +libm: M.Libm, +area: Area, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  match inside:
    case False{}: r
    case True{}:
      Area{_, _, _, +w, +h, +tw, +th, _, _} = area
      columns(libm, area, U32.to_nat(((F32.to_u32(w) - 1) / F32.to_u32(tw) : U32)), ((F32.to_u32(h) - 1) / F32.to_u32(th) : U32), 0.0, r)

# DrawTextureTiled: the loops "for (d = 0; d + tile < dest; d += tile)" run
# (dest - 1)/tile times for these whole sizes, and a last tile always
# follows. An area or a tile under one pixel draws nothing.
def tiled(+libm: M.Libm, +area: Area, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  Area{_, _, _, +w, +h, +tw, +th, _, _} = area
  tiled.in((w >= 1.0 : F32) && (h >= 1.0 : F32) && (tw >= 1.0 : F32) && (th >= 1.0 : F32), libm, area, r)

# tileWidth = (int)(source.width*scale), tileHeight = (int)(source.height*scale); dest =
# (OPT_WIDTH + MARGIN_SIZE, MARGIN_SIZE, GetScreenWidth() - OPT_WIDTH - 2*MARGIN_SIZE, GetScreenHeight() - 2*MARGIN_SIZE).
def area.of(+core: J.Core, +source: J.Rectangle, +color: U32, +scale: F32, +rotation: F32) -> Area:
  J.Rectangle{_, _, +sw, +sh} = source
  Area{source, (220.0 + 8.0 : F32), 8.0, (U32.to_f32((J.Core.get_screen_width(core) - 220 : U32)) - 2.0 * 8.0 : F32),
    (U32.to_f32(J.Core.get_screen_height(core)) - 2.0 * 8.0 : F32), F32.trunc((sw * scale : F32)), F32.trunc((sh * scale : F32)), rotation, tint(color)}

def area(+core: J.Core, +active: U32, +color: U32, +scale: F32, +rotation: F32) -> Area:
  area.of(core, pattern(active), color, scale, rotation)

# DrawRectangleLinesEx(colorRec[i], 3, ColorAlpha(WHITE, 0.5f)) on the active color.
def swatch(active: Bool, +i: U32, frame: J.Frame) -> J.Frame:
  match active:
    case False{}: frame
    case True{}: J.Draw.rectangle_lines_ex(frame, color.cell(i), 3.0, J.Color.with_alpha(J.Color.WHITE(), 0.5))

# DrawRectangleRec(colorRec[i], colors[i]); the active one framed.
def swatches(n: Nat, +i: U32, +active: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: swatches(p, (i + 1 : U32), active, swatch(U32.is_eq(i, active), i, J.Draw.rectangle_rec(frame, color.cell(i), tint(i))))

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, J.Color.BLACK())

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, label(J.Text.format("%i FPS", [J.TextInt{fps}]), 10.0, frame)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# The options panel over the texture (drawn BLACK at (2 + MARGIN_SIZE, 40 + MARGIN_SIZE)).
def panel(+core: J.Core, +active: U32, +color: U32, +scale: F32, +rotation: F32, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle_rec(frame, pattern.cell(active), J.Color.with_alpha(J.Color.DARKBLUE(), 0.3))
  f2 = swatches(10n, 0, color, J.Draw.text(f1, "Select Color", 10.0, 274.0, 10.0, J.Color.BLACK()))
  f3 = J.Draw.text(f2, "Scale (UP/DOWN to change)", 10.0, 344.0, 10.0, J.Color.BLACK())
  f4 = label(J.Text.format("%.2fx", [J.TextFloat{scale}]), 356.0, f3)
  f5 = J.Draw.text(f4, "Rotation (LEFT/RIGHT to change)", 10.0, 386.0, 10.0, J.Color.BLACK())
  f6 = label(J.Text.format("%.0f degrees", [J.TextFloat{rotation}]), 398.0, f5)
  J.Draw.text(f6, "Press [SPACE] to reset", 10.0, 428.0, 10.0, J.Color.DARKBLUE())

def options(+core: J.Core, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle(frame, 8.0, 8.0, (220.0 - 8.0 : F32), U32.to_f32((J.Core.get_screen_height(core) - 16 : U32)), J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.5))
  J.Draw.text(f1, "Select Pattern", 10.0, 38.0, 10.0, J.Color.BLACK())

def draw.shown(+core: J.Core, +active: U32, +color: U32, +scale: F32, +rotation: F32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  draw.fps.done(State{Some{texture}, active, color, scale, rotation}, panel(core, active, color, scale, rotation, frame), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.tiled(+core: J.Core, +active: U32, +color: U32, +scale: F32, +rotation: F32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  draw.shown(core, active, color, scale, rotation, J.Draw.texture(options(core, frame), texture, 10.0, 48.0, J.Color.BLACK()))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{pattern, +active, +color, +scale, +rotation} = state
  match pattern:
    case None{}: draw.fps.done(State{None{}, active, color, scale, rotation},
      panel(core, active, color, scale, rotation, options(core, J.Frame.clear_background(frame, J.Color.RAYWHITE()))), J.Core.get_fps(core, J.Core.get_time(core)), core)
    case Some{t}: draw.tiled(core, active, color, scale, rotation,
      tiled(libm, area(core, active, color, scale, rotation), (J.Frame.clear_background(frame, J.Color.RAYWHITE()), t)))

# The main loop's body; libm is the profile of DrawTexturePro's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# SetTextureFilter(texPattern, TEXTURE_FILTER_BILINEAR).
def filtered(pattern: Maybe<J.Texture>) -> Maybe<J.Texture>:
  match pattern:
    case None{}: None{}
    case Some{t}: Some{J.Texture.set_filter(t, J.TextureFilter.TEXTURE_FILTER_BILINEAR())}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, pattern) = r
  (J.Core.set_target_fps(core, 60), (frame, State{filtered(pattern), 0, 0, 1.0, 0.0}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, 0, 0, 1.0, 0.0}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After SetConfigFlags(FLAG_WINDOW_RESIZABLE) and InitWindow(800, 450):
# LoadTexture("resources/patterns.png"), bilinear, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/patterns.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - tiled drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
