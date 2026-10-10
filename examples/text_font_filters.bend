# raylib [text] example - font filters, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_font_filters.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A font generated from a TTF at size 96 drawn at a size the mouse wheel
# changes, with its texture filter switched by the 1, 2 and 3 keys (POINT,
# BILINEAR, TRILINEAR; raylib's software renderer keeps one mipmap level, so
# GenTextureMipmaps changes nothing and TRILINEAR is LINEAR,
# docs/TEXTURES.md). The example reloads the font from a dropped .ttf file;
# J.Program's update cannot load files, so a frame with dropped files is
# refused. See docs/FONTS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# text: MeasureTextEx of the message at the current size.
type State is Type:
  State{valid: Bool, font: Maybe<J.Font>, size: F32, x: F32, filter: U32, text: M.Vector2}

def name(filter: U32) -> String:
  match filter:
    case 0: "POINT"
    case 1: "BILINEAR"
    case _: "TRILINEAR"

# SetTextureFilter(font.texture, filter) when a filter key was pressed.
def refiltered(changed: Bool, +filter: U32, font: J.Font) -> J.Font:
  match changed:
    case False{}: font
    case True{}: J.Font.set_filter(font, filter)

def update.measured(+valid: Bool, +filter: U32, +size: F32, +x: F32, r: J.Font & M.Vector2) -> State:
  (font, text) = r
  State{valid, Some{font}, size, x, filter, text}

def update.font(+valid: Bool, +changed: Bool, +filter: U32, +size: F32, +x: F32, +text: M.Vector2, font: Maybe<J.Font>) -> State:
  match font:
    case None{}: State{False{}, None{}, size, x, filter, text}
    case Some{f}: update.measured(valid, filter, size, x, J.Font.measure_text_ex(refiltered(changed, filter, f), "Loaded Font", size, 0.0))

# fontSize += GetMouseWheelMove()*4; 1, 2 or 3 pick the filter; LEFT or RIGHT move the text by 10.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{_, font, +size, +x, +filter, +text} = state
  +one = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ONE())
  +two = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_TWO())
  +three = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_THREE())
  +moved = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT()), (x - 10.0 : F32),
    Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT()), (x + 10.0 : F32), x))
  (core, update.font(Bool.not(J.Core.is_file_dropped(core)), one || two || three, Bool.pick(U32, one, 0, Bool.pick(U32, two, 1, Bool.pick(U32, three, 2, filter))),
    (size + J.Input.get_mouse_wheel_move(core) * 4.0 : F32), moved, text, font))

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 20.0, y, 10.0, J.Color.DARKGRAY())

def header(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "Use mouse wheel to change font size", 20.0, 20.0, 10.0, J.Color.GRAY())
  f2 = J.Draw.text(f1, "Use KEY_RIGHT and KEY_LEFT to move text", 20.0, 40.0, 10.0, J.Color.GRAY())
  f3 = J.Draw.text(f2, "Use 1, 2, 3 to change texture filter", 20.0, 60.0, 10.0, J.Color.GRAY())
  J.Draw.text(f3, "Drop a new TTF font for dynamic loading", 20.0, 80.0, 10.0, J.Color.DARKGRAY())

def draw.done(+core: J.Core, +size: F32, +x: F32, +filter: U32, +text: M.Vector2, r: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  M.Vector2{+tw, +th} = text
  (frame, font) = r
  f1 = J.Draw.rectangle(frame, 0.0, (450.0 - 80.0 : F32), 800.0, 80.0, J.Color.LIGHTGRAY())
  f2 = label(J.Text.format("Font size: %02.02f", [J.TextFloat{size}]), (450.0 - 50.0 : F32), f1)
  f3 = label(J.Text.format("Text size: [%02.02f, %02.02f]", [J.TextFloat{tw}, J.TextFloat{th}]), (450.0 - 30.0 : F32), f2)
  f4 = J.Draw.text(f3, "CURRENT TEXTURE FILTER:", 250.0, 400.0, 20.0, J.Color.GRAY())
  (core, (State{True{}, Some{font}, size, x, filter, text}, J.Draw.text(f4, name(filter), 570.0, 400.0, 20.0, J.Color.BLACK())))

# DrawTextEx(font, msg, fontPosition, fontSize, 0, BLACK) between the help lines and the status bar.
def draw.valid(valid: Bool, +core: J.Core, +size: F32, +x: F32, +filter: U32, +text: M.Vector2, frame: J.Frame, font: Maybe<J.Font>) -> J.Core & (State & J.Frame):
  match valid font:
    case True{} Some{f}: draw.done(core, size, x, filter, text,
      J.Draw.text_ex(header(frame), f, "Loaded Font", M.Vector2{x, (450.0 / 2.0 - 80.0 : F32)}, size, 0.0, J.Color.BLACK()))
    case False{} Some{f}: (core, (State{False{}, Some{f}, size, x, filter, text}, J.Frame.refuse(frame)))
    case _ None{}: (core, (State{False{}, None{}, size, x, filter, text}, J.Frame.refuse(frame)))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, font, +size, +x, +filter, +text} = state
  draw.valid(valid, core, size, x, filter, text, frame, font)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# GenTextureMipmaps(&font.texture); fontSize = font.baseSize; SetTextureFilter(font.texture, TEXTURE_FILTER_POINT).
def start.at(font: J.Font) -> State:
  J.Font{+base, padding, glyphs, texture, atlas} = font
  State{True{}, Some{J.Font{base, padding, glyphs, J.Texture.set_filter(J.Texture.gen_mipmaps(texture), J.TextureFilter.TEXTURE_FILTER_POINT()), atlas}},
    U32.to_f32(base), 40.0, 0, M.Vector2.zero()}

def start(result: Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> State:
  match result:
    case Done{Some{f}}: start.at(f)
    case _: State{False{}, None{}, 0.0, 40.0, 0, M.Vector2.zero()}

def setup.done(+core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> J.Core & (J.Frame & State):
  (frame, result) = r
  (J.Core.set_target_fps(core, 60), (frame, start(result)))

# After InitWindow(800, 450): LoadFontEx("resources/KAISG.ttf", 96, 0, 0), SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load_ex(frame, dir ++ "resources/KAISG.ttf", 96, Nil{}, 0),
    r => IO.pure(J.Core & (J.Frame & State), setup.done(core, r)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - font filters", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
