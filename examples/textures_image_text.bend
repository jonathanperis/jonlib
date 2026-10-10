# raylib [textures] example - image text, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_image_text.c
# (zlib/libpng, Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A line of text drawn into an image with a font generated from a TTF at
# size 64 (ImageDrawTextEx), the image shown as a texture with the same text
# drawn under it; SPACE shows the font's atlas texture instead. LoadImage of
# a .png is the PNG loader (Surface.load_png). A font or an image operation
# Jonlib refuses refuses the frames. See docs/FONTS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>, font: Maybe<J.Font>, show: Bool}

type Made is Type:
  Made{image: Maybe<J.Surface>, font: Maybe<J.Font>}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{texture, font, _} = state
  (core, State{texture, font, J.Input.is_key_down(core, J.KeyboardKey.KEY_SPACE())})

def draw.done(+core: J.Core, +show: Bool, texture: J.Texture, r: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  (frame, font) = r
  (core, (State{Some{texture}, Some{font}, show}, J.Draw.text(frame, "PRESS SPACE to SHOW FONT ATLAS USED", 290.0, 420.0, 10.0, J.Color.DARKGRAY())))

# DrawTextEx(font, text, (position.x + 20, position.y + 20 + 280), font.baseSize, 0, WHITE).
def draw.text(+core: J.Core, +x: F32, +y: F32, font: J.Font, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  J.Font{+base, +padding, +glyphs, texture, atlas} = font
  (frame, image) = r
  draw.done(core, False{}, image, J.Draw.text_ex(frame, J.Font{base, padding, glyphs, texture, atlas}, "[Parrots font drawing]",
    M.Vector2{(x + 20.0 : F32), ((y + 20.0) + 280.0 : F32)}, U32.to_f32(base), 0.0, J.Color.WHITE()))

# DrawTextureV(texture, (screenWidth/2 - width/2, screenHeight/2 - height/2 - 20), WHITE).
def draw.image(+core: J.Core, frame: J.Frame, texture: J.Texture, font: J.Font) -> J.Core & (State & J.Frame):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  +x = (800.0 / 2.0 - U32.to_f32(w) / 2.0 : F32)
  +y = ((450.0 / 2.0 - U32.to_f32(h) / 2.0) - 20.0 : F32)
  draw.text(core, x, y, font, J.Draw.texture_v(frame, J.Texture{id, w, h, format, linear, alpha, texels}, M.Vector2{x, y}, J.Color.WHITE()))

def draw.atlas.at(+core: J.Core, frame: J.Frame, texture: J.Texture, r: J.Font & (U32 & U32)) -> J.Core & (State & J.Frame):
  (font, size) = r
  (+w, _) = size
  draw.done(core, True{}, texture, J.Draw.font_texture(frame, font, (800.0 / 2.0 - U32.to_f32((w / 2 : U32)) : F32), 50.0, J.Color.BLACK()))

# DrawTexture(font.texture, screenWidth/2 - font.texture.width/2, 50, BLACK).
def draw.atlas(+core: J.Core, frame: J.Frame, texture: J.Texture, font: J.Font) -> J.Core & (State & J.Frame):
  draw.atlas.at(core, frame, texture, J.Font.texture_size(font))

def draw.at(+core: J.Core, show: Bool, frame: J.Frame, texture: J.Texture, font: J.Font) -> J.Core & (State & J.Frame):
  match show:
    case False{}: draw.image(core, frame, texture, font)
    case True{}: draw.atlas(core, frame, texture, font)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture, font, show} = state
  match texture font:
    case Some{t} Some{f}: draw.at(core, show, J.Frame.clear_background(frame, J.Color.RAYWHITE()), t, f)
    case _ _: (core, (State{None{}, None{}, False{}}, J.Frame.refuse(frame)))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def titled.pair(pair: J.Surface & J.Font) -> Made:
  (image, font) = pair
  Made{Some{image}, Some{font}}

def titled.kept(result: Result<&1, &1, (J.Surface & J.Font) & J.Surface.Error, J.Surface & J.Font>) -> Made:
  match result:
    case Fail{_}: Made{None{}, None{}}
    case Done{pair}: titled.pair(pair)

# ImageDrawTextEx(&parrots, font, "[Parrots font drawing]", (20, 20), font.baseSize, 0, RED).
def titled.at(image: J.Surface, font: J.Font) -> Made:
  J.Font{+base, +padding, +glyphs, texture, atlas} = font
  titled.kept(J.Font.image_draw_text_ex(image, J.Font{base, padding, glyphs, texture, atlas}, "[Parrots font drawing]", M.Vector2{20.0, 20.0}, U32.to_f32(base), 0.0, J.Color.RED()))

def titled(image: Maybe<J.Surface>, font: Maybe<J.Font>) -> Made:
  match image font:
    case Some{i} Some{f}: titled.at(i, f)
    case _ _: Made{None{}, None{}}

def loaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}

def font(result: Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> Maybe<J.Font>:
  match result:
    case Fail{_}: None{}
    case Done{f}: f

def upload(frame: J.Frame, image: Maybe<J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match image:
    case None{}: (frame, None{})
    case Some{i}: J.Texture.load_from_image(frame, i)

def setup.done(+core: J.Core, font: Maybe<J.Font>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture, font, False{}}))

def setup.upload(+core: J.Core, frame: J.Frame, made: Made) -> J.Core & (J.Frame & State):
  Made{image, font} = made
  setup.done(core, font, upload(frame, image))

def setup.made(+core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  (frame, result) = r
  setup.upload(core, frame, titled(image, font(result)))

# LoadFontEx("resources/KAISG.ttf", 64, 0, 0): the default 95 codepoints.
def setup.font(+dir: String, +core: J.Core, frame: J.Frame, image: Maybe<J.Surface>) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load_ex(frame, dir ++ "resources/KAISG.ttf", 64, Nil{}, 0),
    r => IO.pure(J.Core & (J.Frame & State), setup.made(core, r, image)))

# After InitWindow(800, 450): the parrots image, the font, the text drawn
# into the image, the texture, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/parrots.png"),
    result => setup.font(dir, core, frame, loaded(result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - image text", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
