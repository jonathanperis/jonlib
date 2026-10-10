# raylib [textures] example - image drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_image_drawing.c
# (zlib/libpng, Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# One texture composed from images before the loop: a cat cropped, flipped
# and resized, drawn scaled over the parrots, the result cropped, marked with
# a pixel, a circle and a rectangle and titled with a sprite font. LoadImage
# of a .png is the PNG loader (Surface.load_png) and LoadFont of one is
# LoadFontFromImage(image, MAGENTA, 32). An image operation Jonlib refuses
# leaves no texture and refuses the frames. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>}

def loaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}

def kept(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}

# ImageFlipHorizontal(&cat); ImageResize(&cat, 150, 200).
def cat.resized(image: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match image:
    case None{}: None{}
    case Some{i}: kept(J.Surface.resize(J.Surface.flip_horizontal(i), 150, 200))

# ImageCrop(&cat, (100, 10, 280, 380)).
def cat(image: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match image:
    case None{}: None{}
    case Some{i}: cat.resized(kept(J.Surface.crop(i, J.Rectangle{100.0, 10.0, 280.0, 380.0})))

def composed.first(pair: J.Surface & J.Surface) -> Maybe<J.Surface>:
  (destination, _) = pair
  Some{destination}

def composed.kept(result: Result<&1, &1, (J.Surface & J.Surface) & J.Surface.Error, J.Surface & J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{pair}: composed.first(pair)

# ImageDraw(&parrots, cat, the whole cat (150x200), (30, 40, cat.width*1.5f, cat.height*1.5f), WHITE).
def composed(parrots: Maybe<J.Surface>, cat: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match parrots cat:
    case Some{p} Some{c}: composed.kept(J.Surface.draw_image_rect(p, c, J.Rectangle{0.0, 0.0, 150.0, 200.0},
      J.Rectangle{30.0, 40.0, (150.0 * 1.5 : F32), (200.0 * 1.5 : F32)}, J.Color.WHITE()))
    case _ _: None{}

# ImageCrop(&parrots, (0, 50, parrots.width, parrots.height - 100)).
def cropped.at(image: J.Surface) -> Maybe<J.Surface>:
  J.Surface{+w, +h, format, pixels} = image
  kept(J.Surface.crop(J.Surface{w, h, format, pixels}, J.Rectangle{0.0, 50.0, U32.to_f32(w), (U32.to_f32(h) - 100.0 : F32)}))

def cropped(image: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match image:
    case None{}: None{}
    case Some{i}: cropped.at(i)

# ImageDrawPixel(10, 10), ImageDrawCircleLines(10, 10, 5), ImageDrawRectangle(5, 20, 10, 10), all RAYWHITE.
def marked(image: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match image:
    case None{}: None{}
    case Some{i}: Some{J.Surface.draw_rectangle(J.Surface.draw_circle_lines(J.Surface.draw_pixel(i, 10.0, 10.0, J.Color.RAYWHITE()), 10.0, 10.0, 5, J.Color.RAYWHITE()),
      5.0, 20.0, 10.0, 10.0, J.Color.RAYWHITE())}

def titled.first(pair: J.Surface & J.Font) -> Maybe<J.Surface>:
  (image, _) = pair
  Some{image}

def titled.kept(result: Result<&1, &1, (J.Surface & J.Font) & J.Surface.Error, J.Surface & J.Font>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{pair}: titled.first(pair)

# ImageDrawTextEx(&parrots, font, "PARROTS & CAT", (300, 230), font.baseSize, -2, WHITE).
def titled.at(image: J.Surface, font: J.Font) -> Maybe<J.Surface>:
  J.Font{+base, +padding, +glyphs, texture, atlas} = font
  titled.kept(J.Font.image_draw_text_ex(image, J.Font{base, padding, glyphs, texture, atlas}, "PARROTS & CAT", M.Vector2{300.0, 230.0}, U32.to_f32(base), F32.neg(2.0), J.Color.WHITE()))

def titled(image: Maybe<J.Surface>, font: Maybe<J.Font>) -> Maybe<J.Surface>:
  match image font:
    case Some{i} Some{f}: titled.at(i, f)
    case _ _: None{}

def font(result: Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> Maybe<J.Font>:
  match result:
    case Fail{_}: None{}
    case Done{f}: f

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def draw.shown(+core: J.Core, +x: F32, +y: F32, +w: F32, +h: F32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = J.Draw.rectangle_lines(frame, x, y, w, h, J.Color.DARKGRAY())
  f2 = J.Draw.text(f1, "We are drawing only one texture from various images composed!", 240.0, 350.0, 10.0, J.Color.DARKGRAY())
  (core, (State{Some{texture}}, J.Draw.text(f2, "Source images have been cropped, scaled, flipped and copied one over the other.", 190.0, 370.0, 10.0, J.Color.DARKGRAY())))

# DrawTexture(texture, screenWidth/2 - texture.width/2, screenHeight/2 - texture.height/2 - 40, WHITE) and its outline.
def draw.at(+core: J.Core, frame: J.Frame, texture: J.Texture) -> J.Core & (State & J.Frame):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  +x = U32.to_f32((800 / 2 - w / 2 : U32))
  +y = U32.to_f32((450 / 2 - h / 2 - 40 : U32))
  draw.shown(core, x, y, U32.to_f32(w), U32.to_f32(h), J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, x, y, J.Color.WHITE()))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture} = state
  match texture:
    case None{}: (core, (State{None{}}, J.Frame.refuse(frame)))
    case Some{t}: draw.at(core, J.Frame.clear_background(frame, J.Color.RAYWHITE()), t)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def upload(frame: J.Frame, image: Maybe<J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match image:
    case None{}: (frame, None{})
    case Some{i}: J.Texture.load_from_image(frame, i)

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture}))

def setup.made(+core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  (frame, result) = r
  setup.uploaded(core, upload(frame, titled(image, font(result))))

def setup.font(+dir: String, +core: J.Core, frame: J.Frame, image: Maybe<J.Surface>) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load(frame, dir ++ "resources/custom_jupiter_crash.png"),
    r => IO.pure(J.Core & (J.Frame & State), setup.made(core, r, image)))

def setup.parrots(+dir: String, +core: J.Core, frame: J.Frame, cat: Maybe<J.Surface>) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/parrots.png"),
    result => setup.font(dir, core, frame, marked(cropped(composed(loaded(result), cat)))))

# After InitWindow(800, 450): the cat, the parrots composed with it, the
# font's title, the texture, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cat.png"),
    result => setup.parrots(dir, core, frame, cat(loaded(result))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - image drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
