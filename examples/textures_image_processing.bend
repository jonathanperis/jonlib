# raylib [textures] example - image processing, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_image_processing.c
# (zlib/libpng, Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# Nine toggles (the mouse, or UP and DOWN) pick an image process applied to
# a copy of the image: grayscale, tint, invert, contrast, brightness,
# Gaussian blur and the two flips. The processed copy's LoadImageColors
# update the texture. UP from the first process goes to the eighth, as in
# the example. LoadImage of a .png is the PNG loader (Surface.load_png). An
# image operation Jonlib refuses refuses the frames. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# origin: imOrigin; hover: the toggle under the mouse (9: none).
type State is Type:
  State{valid: Bool, origin: Maybe<J.Surface>, texture: Maybe<J.Texture>, current: U32, hover: U32}

def name(process: U32) -> String:
  match process:
    case 0: "NO PROCESSING"
    case 1: "COLOR GRAYSCALE"
    case 2: "COLOR TINT"
    case 3: "COLOR INVERT"
    case 4: "COLOR CONTRAST"
    case 5: "COLOR BRIGHTNESS"
    case 6: "GAUSSIAN BLUR"
    case 7: "FLIP VERTICAL"
    case _: "FLIP HORIZONTAL"

# toggleRecs[i] = (40, 50 + 32*i, 150, 30).
def toggle(+i: U32) -> J.Rectangle:
  J.Rectangle{40.0, U32.to_f32((50 + 32 * i : U32)), 150.0, 30.0}

# The first toggle under the mouse, else none.
def hovered(n: Nat, +i: U32, +mouse: M.Vector2) -> U32:
  match n:
    case 0n: 9
    case 1n+p: Bool.pick(U32, J.Collision.point_rec(mouse, toggle(i)), i, hovered(p, (i + 1 : U32), mouse))

# The process applied to the copy.
def processed(process: U32, image: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  match process:
    case 1: J.Surface.color_grayscale(image)
    case 2: J.Surface.color_tint(image, J.Color.GREEN())
    case 3: J.Surface.color_invert(image)
    case 4: J.Surface.color_contrast(image, F32.neg(40.0))
    case 5: J.Surface.color_brightness(image, F32.neg(80.0))
    case 6: J.Surface.blur_gaussian(image, 10)
    case 7: Done{J.Surface.flip_vertical(image)}
    case 8: Done{J.Surface.flip_horizontal(image)}
    case _: Done{image}

def kept(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}

# LoadImageColors(imCopy).
def colors(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: kept(J.Surface.colors_image(image))

def updated(result: Result<&1, &1, J.Texture & J.Surface.Error, J.Texture>) -> Maybe<J.Texture>:
  match result:
    case Fail{_}: None{}
    case Done{texture}: Some{texture}

# UpdateTexture(texture, pixels).
def upload(texture: J.Texture, pixels: Maybe<J.Surface>) -> Maybe<J.Texture>:
  match pixels:
    case None{}: None{}
    case Some{p}: updated(J.Texture.update(texture, p))

def reload.done(+current: U32, +hover: U32, origin: J.Surface, texture: Maybe<J.Texture>) -> State:
  match texture:
    case None{}: State{False{}, Some{origin}, None{}, current, hover}
    case Some{t}: State{True{}, Some{origin}, Some{t}, current, hover}

def reload.copied(+current: U32, +hover: U32, texture: J.Texture, pair: J.Surface & J.Surface) -> State:
  (origin, copy) = pair
  reload.done(current, hover, origin, upload(texture, colors(processed(current, copy))))

# imCopy = ImageCopy(imOrigin), processed, into the texture.
def reload.at(+current: U32, +hover: U32, origin: Maybe<J.Surface>, texture: Maybe<J.Texture>) -> State:
  match origin texture:
    case Some{o} Some{t}: reload.copied(current, hover, t, J.Surface.copy(o))
    case _ _: State{False{}, None{}, None{}, current, hover}

def update.reload(reload: Bool, +valid: Bool, +current: U32, +hover: U32, origin: Maybe<J.Surface>, texture: Maybe<J.Texture>) -> State:
  match reload:
    case False{}: State{valid, origin, texture, current, hover}
    case True{}: reload.at(current, hover, origin, texture)

# A left release over a toggle picks it; DOWN takes the next process (after
# the last, the first), otherwise UP the previous (before the first, 7).
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, origin, texture, +current, _} = state
  +hover = hovered(9n, 0, J.Input.get_mouse_position(core))
  +clicked = (hover < 9 : U32) && J.Input.is_mouse_button_released(core, 0)
  +picked = Bool.pick(U32, clicked, hover, current)
  +down = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN())
  +up = Bool.not(down) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP())
  +next = Bool.pick(U32, down, Bool.pick(U32, (picked >= 8 : U32), 0, (picked + 1 : U32)), Bool.pick(U32, up, Bool.pick(U32, U32.is_eq(picked, 0), 7, (picked - 1 : U32)), picked))
  (core, update.reload(clicked || down || up, valid, next, hover, origin, texture))

def toggle.text(width: Maybe<U32>, +i: U32, +color: U32, frame: J.Frame) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{w}: J.Draw.text(frame, name(i), F32.trunc((40.0 + 150.0 / 2.0 - U32.to_f32(w) / 2.0 : F32)), U32.to_f32((50 + 32 * i + 11 : U32)), 10.0, color)

# A toggle: its box, outline and centered name, highlighted when current or hovered.
def toggles(n: Nat, +i: U32, +current: U32, +hover: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +lit = U32.is_eq(i, current) || U32.is_eq(i, hover)
      f1 = J.Draw.rectangle_rec(frame, toggle(i), Bool.pick(U32, lit, J.Color.SKYBLUE(), J.Color.LIGHTGRAY()))
      f2 = J.Draw.rectangle_lines(f1, 40.0, U32.to_f32((50 + 32 * i : U32)), 150.0, 30.0, Bool.pick(U32, lit, J.Color.BLUE(), J.Color.GRAY()))
      toggles(p, (i + 1 : U32), current, hover, toggle.text(J.Font.measure_text(name(i), 10.0), i, Bool.pick(U32, lit, J.Color.DARKBLUE(), J.Color.DARKGRAY()), f2))

def draw.shown(+core: J.Core, origin: Maybe<J.Surface>, +current: U32, +hover: U32, +x: F32, +y: F32, +w: F32, +h: F32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{True{}, origin, Some{texture}, current, hover}, J.Draw.rectangle_lines(frame, x, y, w, h, J.Color.BLACK())))

# DrawTexture(texture, screenWidth - texture.width - 60, screenHeight/2 - texture.height/2, WHITE) and its outline.
def draw.at(+core: J.Core, origin: Maybe<J.Surface>, +current: U32, +hover: U32, frame: J.Frame, texture: J.Texture) -> J.Core & (State & J.Frame):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.shown(core, origin, current, hover, (800.0 - U32.to_f32(w) - 60.0 : F32), (225.0 - U32.to_f32((h / 2 : U32)) : F32), U32.to_f32(w), U32.to_f32(h),
    J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, (800.0 - U32.to_f32(w) - 60.0 : F32), (225.0 - U32.to_f32((h / 2 : U32)) : F32), J.Color.WHITE()))

def draw.valid(valid: Bool, +core: J.Core, origin: Maybe<J.Surface>, +current: U32, +hover: U32, frame: J.Frame, texture: Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  match valid texture:
    case True{} Some{t}: draw.at(core, origin, current, hover,
      toggles(9n, 0, current, hover, J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "IMAGE PROCESSING:", 40.0, 30.0, 10.0, J.Color.DARKGRAY())), t)
    case False{} Some{t}: (core, (State{False{}, origin, Some{t}, current, hover}, J.Frame.refuse(frame)))
    case _ None{}: (core, (State{False{}, origin, None{}, current, hover}, J.Frame.refuse(frame)))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, origin, texture, +current, +hover} = state
  draw.valid(valid, core, origin, current, hover, frame, texture)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.uploaded(+core: J.Core, origin: J.Surface, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, Some{origin}, texture, 0, 9}))

def setup.copied(+core: J.Core, frame: J.Frame, pair: J.Surface & J.Surface) -> J.Core & (J.Frame & State):
  (origin, copy) = pair
  setup.uploaded(core, origin, J.Texture.load_from_image(frame, copy))

# ImageFormat(&imOrigin, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8); texture = LoadTextureFromImage(imOrigin).
def setup.formatted(+core: J.Core, frame: J.Frame, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  match image:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{False{}, None{}, None{}, 0, 9}))
    case Some{i}: setup.copied(core, frame, J.Surface.copy(i))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{False{}, None{}, None{}, 0, 9}))
    case Done{image}: setup.formatted(core, frame, kept(J.Surface.format(image, 7)))

# After InitWindow(800, 450): LoadImage("resources/parrots.png") as RGBA, its texture, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/parrots.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - image processing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
