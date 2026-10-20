# raylib [text] example - font sdf, ported to Jonlib.
# Adapted from raylib 6.2 examples/text/text_font_sdf.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# "Signed Distance Fields" in a font made by hand from LoadFontData's glyphs
# of resources/anonymous_pro_bold.ttf at 16 px and their atlas, and, while
# space is held, in the same font as signed distance fields (FONT_SDF:
# stbtt_GetCodepointSDF, whose cubic solver calls the C library's pow, acos
# and cos, reproduced under the glibc 2.39 profile, src/stb_cubic.bend). The
# mouse wheel scales the text; each font's atlas is drawn in the corner.
# raylib draws the SDF font through a shader (sdf.fs) that turns distances
# into coverage; the software renderer runs no shader, so the SDF glyphs
# show as their distance images, filtered bilinearly, as raylib's own
# software renderer shows them. Under another profile the SDF font is not
# made and every frame is refused. Loads from raylib's examples/text
# directory: run from there, or pass `--resources <dir/>`. See
# docs/FONTS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Fonts is Type:
  Fonts{regular: J.Font, sdf: J.Font}

# size: fontSize; text: MeasureTextEx of the message; position:
# fontPosition; sdf: whether space is held (currentFont).
type State is Type:
  State{fonts: Maybe<Fonts>, shader: J.Shader, size: F32, sdf: Bool, text: M.Vector2, position: M.Vector2}

def message() -> String:
  "Signed Distance Fields"

# fontPosition: the screen's middle less half the text, 80 lower.
def placed(+core: J.Core, +text: M.Vector2) -> M.Vector2:
  M.Vector2{+tw, +th} = text
  M.Vector2{((U32.to_f32(J.Core.get_screen_width(core)) / 2.0 : F32) - (tw / 2.0 : F32) : F32),
    (((U32.to_f32(J.Core.get_screen_height(core)) / 2.0 : F32) - (th / 2.0 : F32) : F32) + 80.0 : F32)}

def update.regular(+core: J.Core, +size: F32, sdf: J.Font, measured: J.Font & M.Vector2, shader: J.Shader) -> State:
  (regular, +text) = measured
  State{Some{Fonts{regular, sdf}}, shader, size, False{}, text, placed(core, text)}

def update.sdf(+core: J.Core, +size: F32, regular: J.Font, measured: J.Font & M.Vector2, shader: J.Shader) -> State:
  (sdf, +text) = measured
  State{Some{Fonts{regular, sdf}}, shader, size, True{}, text, placed(core, text)}

# textSize = MeasureTextEx(the current font, msg, fontSize, 0).
def update.picked(held: Bool, +core: J.Core, +size: F32, regular: J.Font, sdf: J.Font, shader: J.Shader) -> State:
  match held:
    case True{}: update.sdf(core, size, regular, J.Font.measure_text_ex(sdf, message(), size, 0.0), shader)
    case False{}: update.regular(core, size, sdf, J.Font.measure_text_ex(regular, message(), size, 0.0), shader)

def update.measured(held: Bool, +core: J.Core, +size: F32, fonts: Fonts, shader: J.Shader) -> State:
  Fonts{regular, sdf} = fonts
  update.picked(held, core, size, regular, sdf, shader)

def update.fonts(fonts: Maybe<Fonts>, +core: J.Core, +size: F32, shader: J.Shader, +text: M.Vector2, +position: M.Vector2) -> State:
  match fonts:
    case None{}: State{None{}, shader, size, False{}, text, position}
    case Some{f}: update.measured(J.Input.is_key_down(core, J.KeyboardKey.KEY_SPACE()), core, size, f, shader)

# fontSize += GetMouseWheelMove()*8.0f, at least 6; currentFont by space.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{fonts, shader, +size, _, +text, +position} = state
  +scaled = (size + (J.Input.get_mouse_wheel_move(core) * 8.0 : F32) : F32)
  (core, update.fonts(fonts, core, Bool.pick(F32, (scaled < 6.0 : F32), 6.0, scaled), shader, text, position))

def label(text: Maybe<String>, +x: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, 50.0, 20.0, J.Color.DARKGRAY())

# The labels at the right and the help at the bottom.
def draw.help(+core: J.Core, +size: F32, frame: J.Frame) -> J.Frame:
  +right = (U32.to_f32(J.Core.get_screen_width(core)) - 240.0 : F32)
  f1 = J.Draw.text(frame, "FONT SIZE: 16.0", right, 20.0, 20.0, J.Color.DARKGRAY())
  f2 = label(J.Text.format("RENDER SIZE: %02.02f", [J.TextFloat{size}]), right, f1)
  f3 = J.Draw.text(f2, "Use MOUSE WHEEL to SCALE TEXT!", right, 90.0, 10.0, J.Color.DARKGRAY())
  J.Draw.text(f3, "HOLD SPACE to USE SDF FONT VERSION!", 340.0, (U32.to_f32(J.Core.get_screen_height(core)) - 30.0 : F32), 20.0, J.Color.MAROON())

# DrawTexture(font.texture, 10, 10, BLACK).
def draw.atlas(drawn: J.Frame & J.Font) -> J.Frame & J.Font:
  (frame, font) = drawn
  J.Draw.font_texture(frame, font, 10.0, 10.0, J.Color.BLACK())

def draw.regular(+core: J.Core, +size: F32, +position: M.Vector2, sdf: J.Font, shader: J.Shader, +text: M.Vector2, drawn: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  (frame, regular) = drawn
  (core, (State{Some{Fonts{regular, sdf}}, shader, size, False{}, text, position},
    draw.help(core, size, J.Draw.text(frame, "default font", 315.0, 40.0, 30.0, J.Color.GRAY()))))

def draw.sdf(+core: J.Core, +size: F32, +position: M.Vector2, regular: J.Font, shader: J.Shader, +text: M.Vector2, drawn: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  (frame, sdf) = drawn
  (core, (State{Some{Fonts{regular, sdf}}, shader, size, True{}, text, position},
    draw.help(core, size, J.Draw.text(frame, "SDF!", 320.0, 20.0, 80.0, J.Color.RED()))))

def draw.text.ended(drawn: J.Frame & J.Font) -> J.Frame & J.Font:
  (frame, font) = drawn
  draw.atlas((J.Frame.end_shader_mode(frame), font))

# The SDF font between BeginShaderMode and EndShaderMode (which do nothing
# on the software renderer), its atlas, and the labels.
def draw.text.sdf(frame: J.Frame, sdf: J.Font, +shader: J.Shader, +position: M.Vector2, +size: F32) -> J.Frame & J.Font:
  draw.text.ended(J.Draw.text_ex(J.Frame.begin_shader_mode(frame, shader), sdf, message(), position, size, 0.0, J.Color.BLACK()))

def draw.picked(held: Bool, +core: J.Core, regular: J.Font, sdf: J.Font, +shader: J.Shader, +size: F32, +text: M.Vector2, +position: M.Vector2, frame: J.Frame) -> J.Core & (State & J.Frame):
  match held:
    case True{}: draw.sdf(core, size, position, regular, shader, text, draw.text.sdf(J.Frame.clear_background(frame, J.Color.RAYWHITE()), sdf, shader, position, size))
    case False{}: draw.regular(core, size, position, sdf, shader, text,
      draw.atlas(J.Draw.text_ex(J.Frame.clear_background(frame, J.Color.RAYWHITE()), regular, message(), position, size, 0.0, J.Color.BLACK())))

def draw.fonts(held: Bool, +core: J.Core, fonts: Fonts, +shader: J.Shader, +size: F32, +text: M.Vector2, +position: M.Vector2, frame: J.Frame) -> J.Core & (State & J.Frame):
  Fonts{regular, sdf} = fonts
  draw.picked(held, core, regular, sdf, shader, size, text, position, frame)

def draw.valid(fonts: Maybe<Fonts>, +core: J.Core, +shader: J.Shader, +size: F32, +held: Bool, +text: M.Vector2, +position: M.Vector2, frame: J.Frame) -> J.Core & (State & J.Frame):
  match fonts:
    case None{}: (core, (State{None{}, shader, size, held, text, position}, J.Frame.refuse(frame)))
    case Some{f}: draw.fonts(held, core, f, shader, size, text, position, frame)

# A frame is refused where the fonts were not made.
def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{fonts, shader, +size, +held, +text, +position} = state
  draw.valid(fonts, core, shader, size, held, text, position, frame)

# No libm call in the loop: the profile is the setup's (LoadFontData and
# GenImageFontAtlas).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# The glyphs' atlas and the font made of it (J.Font.assemble: the program's
# own Font struct, its texture LoadTextureFromImage of the atlas).
def setup.textured(frame: J.Frame, glyphs: List<J.GlyphInfo>, atlas: Maybe<(J.Surface & +List<J.Rectangle>)>) -> J.Frame & Maybe<J.Font>:
  match atlas:
    case None{}: (frame, None{})
    case Some{Tuple{image, +recs}}: J.Font.assemble(frame, 16, glyphs, image, recs)

def setup.atlas(frame: J.Frame, made: List<J.GlyphInfo> & Maybe<(J.Surface & +List<J.Rectangle>)>) -> J.Frame & Maybe<J.Font>:
  (glyphs, atlas) = made
  setup.textured(frame, glyphs, atlas)

# GenImageFontAtlas(font.glyphs, &font.recs, 95, 16, padding, method).
def setup.glyphs(+libm: M.Libm, frame: J.Frame, data: J.Font.Data, +padding: U32, +method: U32) -> J.Frame & Maybe<J.Font>:
  match data:
    case J.FontDataGlyphs{gs}: setup.atlas(frame, J.Font.gen_image_atlas_for(libm, gs, 95, 16, padding, method))
    case _: (frame, None{})

# LoadFontData(fileData, fileSize, 16, 0, count, kind) under the profile.
def setup.font(+libm: M.Libm, frame: J.Frame, +bytes: +List<U32>, +count: U32, +kind: U32, +padding: U32, +method: U32) -> J.Frame & Maybe<J.Font>:
  setup.glyphs(libm, frame, J.Font.load_data_for(libm, bytes, 16, Nil{}, count, kind), padding, method)

# SetTextureFilter(fontSDF.texture, TEXTURE_FILTER_BILINEAR).
def setup.paired(regular: Maybe<J.Font>, sdf: Maybe<J.Font>) -> Maybe<Fonts>:
  match regular sdf:
    case Some{r} Some{s}: Some{Fonts{r, J.Font.set_filter(s, J.TextureFilter.TEXTURE_FILTER_BILINEAR())}}
    case _ _: None{}

def setup.joined(regular: Maybe<J.Font>, second: J.Frame & Maybe<J.Font>) -> J.Frame & Maybe<Fonts>:
  (made, sdf) = second
  (made, setup.paired(regular, sdf))

def setup.second(+libm: M.Libm, +bytes: +List<U32>, first: J.Frame & Maybe<J.Font>) -> J.Frame & Maybe<Fonts>:
  (made, regular) = first
  setup.joined(regular, setup.font(libm, made, bytes, 0, 2, 0, 1))

# fontDefault: 95 glyphs, FONT_DEFAULT, padding 4, rows; then fontSDF: 0
# glyphs (95), FONT_SDF, padding 0, skyline.
def setup.both(+libm: M.Libm, frame: J.Frame, +bytes: +List<U32>) -> J.Frame & Maybe<Fonts>:
  setup.second(libm, bytes, setup.font(libm, frame, bytes, 95, 0, 4, 0))

# LoadShader(0, "resources/shaders/glsl330/sdf.fs"); fontPosition {40,
# screenHeight/2.0f - 50}; textSize {0, 0}; fontSize 16; SetTargetFPS(60).
def setup.made(+core: J.Core, dir: String, made: J.Frame & Maybe<Fonts>) -> J.Core & (J.Frame & State):
  (frame, fonts) = made
  (J.Core.set_target_fps(core, 60), (frame, State{fonts, J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/sdf.fs"}), 16.0, False{}, M.Vector2.zero(),
    M.Vector2{40.0, ((450.0 / 2.0 : F32) - 50.0 : F32)}}))

def setup.read(+libm: M.Libm, +core: J.Core, frame: J.Frame, +dir: String, r: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> J.Core & (J.Frame & State):
  match r:
    case Fail{_}: setup.made(core, dir, (frame, None{}))
    case Done{+bytes}: setup.made(core, dir, setup.both(libm, frame, bytes))

# After InitWindow(800, 450): LoadFileData(dir ++
# "resources/anonymous_pro_bold.ttf"), the two fonts, the shader.
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, J.Core & (J.Frame & State), J.Files.load_data(dir ++ "resources/anonymous_pro_bold.ttf"),
    r => IO.pure(J.Core & (J.Frame & State), setup.read(libm, core, frame, dir, r)))

# "--resources DIR/" (default: the working directory) and "--frames N".
def options(args: List<String>, +mode: U32, dir: String, +frames: U32) -> String & U32:
  match args:
    case Nil{}: (dir, frames)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames)
        case 2: options(rest, 0, dir, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--resources"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, 0)), dir, frames)

def run.with(parsed: String & U32) -> IO(Unit):
  (dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [text] example - font sdf", 800, 450, limit,
    core => frame => setup(M.Glibc239Libm{}, dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
