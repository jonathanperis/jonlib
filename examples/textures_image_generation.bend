# raylib [textures] example - image generation, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_image_generation.c (zlib/libpng,
# Copyright (c) 2016-2025 Wilhem Barbier (@nounoursheureux) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Nine procedural images (linear gradients at 0, 90 and 45 degrees, radial,
# square, checked, white noise, Perlin noise, cellular); a left click or
# RIGHT cycles them. raylib seeds GetRandomValue from time(NULL) in
# InitWindow; here the seed is a setup argument (white noise and cellular
# draw from it, in the example's order). The 45-degree gradient's sinf/cosf
# follow the libm profile. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{textures: List<Maybe<J.Texture>>, current: U32}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{textures, +current} = state
  +next = J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()) || J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())
  (core, State{textures, Bool.pick(U32, next, ((current + 1) % 9 : U32), current)})

def kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: kept(J.Draw.texture(frame, t, 0.0, 0.0, J.Color.WHITE()))

def draw.cons(rest: List<Maybe<J.Texture>>, r: J.Frame & Maybe<J.Texture>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, t) = r
  (frame, Con{t, rest})

def draw.consed(t: Maybe<J.Texture>, r: J.Frame & List<Maybe<J.Texture>>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, rest) = r
  (frame, Con{t, rest})

# DrawTexture(textures[current], 0, 0, WHITE), handing every texture back.
def draw.nth(textures: List<Maybe<J.Texture>>, n: Nat, frame: J.Frame) -> J.Frame & List<Maybe<J.Texture>>:
  match textures n:
    case Nil{} _: (frame, Nil{})
    case Con{t, rest} 0n: draw.cons(rest, draw.texture(frame, t))
    case Con{t, rest} 1n+p: draw.consed(t, draw.nth(rest, p, frame))

def label(current: U32, frame: J.Frame) -> J.Frame:
  match current:
    case 0: J.Draw.text(frame, "VERTICAL GRADIENT", 560.0, 10.0, 20.0, J.Color.RAYWHITE())
    case 1: J.Draw.text(frame, "HORIZONTAL GRADIENT", 540.0, 10.0, 20.0, J.Color.RAYWHITE())
    case 2: J.Draw.text(frame, "DIAGONAL GRADIENT", 540.0, 10.0, 20.0, J.Color.RAYWHITE())
    case 3: J.Draw.text(frame, "RADIAL GRADIENT", 580.0, 10.0, 20.0, J.Color.LIGHTGRAY())
    case 4: J.Draw.text(frame, "SQUARE GRADIENT", 580.0, 10.0, 20.0, J.Color.LIGHTGRAY())
    case 5: J.Draw.text(frame, "CHECKED", 680.0, 10.0, 20.0, J.Color.RAYWHITE())
    case 6: J.Draw.text(frame, "WHITE NOISE", 640.0, 10.0, 20.0, J.Color.RED())
    case 7: J.Draw.text(frame, "PERLIN NOISE", 640.0, 10.0, 20.0, J.Color.RED())
    case _: J.Draw.text(frame, "CELLULAR", 670.0, 10.0, 20.0, J.Color.RAYWHITE())

def draw.done(+core: J.Core, +current: U32, r: J.Frame & List<Maybe<J.Texture>>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Draw.rectangle(frame, 30.0, 400.0, 325.0, 30.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5))
  f2 = J.Draw.rectangle_lines(f1, 30.0, 400.0, 325.0, 30.0, J.Color.with_alpha(J.Color.WHITE(), 0.5))
  f3 = J.Draw.text(f2, "MOUSE LEFT BUTTON to CYCLE PROCEDURAL TEXTURES", 40.0, 410.0, 10.0, J.Color.WHITE())
  (core, (State{textures, current}, label(current, f3)))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{textures, +current} = state
  draw.done(core, current, draw.nth(textures, U32.to_nat(current), J.Frame.clear_background(frame, J.Color.RAYWHITE())))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def upload(frame: J.Frame, image: Maybe<J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match image:
    case None{}: (frame, None{})
    case Some{i}: J.Texture.load_from_image(frame, i)

def uploaded.push(i: Maybe<J.Surface>, r: J.Frame & List<Maybe<J.Texture>>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, acc) = r
  draw.cons(acc, upload(frame, i))

def uploaded.reversed(r: J.Frame & List<Maybe<J.Texture>>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, acc) = r
  (frame, List.reverse(&1, Maybe<J.Texture>, acc))

# Uploads the images in order (textures[0..8]).
def uploaded(images: List<Maybe<J.Surface>>, r: J.Frame & List<Maybe<J.Texture>>) -> J.Frame & List<Maybe<J.Texture>>:
  match images:
    case Nil{}: uploaded.reversed(r)
    case Con{i, rest}: uploaded(rest, uploaded.push(i, r))

def setup.done(+core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> J.Core & (J.Frame & State):
  (frame, textures) = r
  (J.Core.set_target_fps(core, 60), (frame, State{textures, 0}))

def setup.cellular(+core: J.Core, frame: J.Frame, +libm: M.Libm, white: Maybe<J.Surface>, r: J.Random.State & Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  (_, cellular) = r
  setup.done(core, uploaded([J.Surface.create_gradient_linear_for(libm, 800, 450, 0.0, J.Color.RED(), J.Color.BLUE()),
    J.Surface.create_gradient_linear_for(libm, 800, 450, 90.0, J.Color.RED(), J.Color.BLUE()),
    J.Surface.create_gradient_linear_for(libm, 800, 450, 45.0, J.Color.RED(), J.Color.BLUE()),
    J.Surface.create_gradient_radial(800, 450, 0.0, J.Color.WHITE(), J.Color.BLACK()),
    J.Surface.create_gradient_square(800, 450, 0.0, J.Color.WHITE(), J.Color.BLACK()),
    J.Surface.create_checked(800, 450, 32, 32, J.Color.RED(), J.Color.BLUE()), white,
    J.Surface.create_perlin(800, 450, 50.0, 50.0, 4.0), cellular], (frame, Nil{})))

def setup.white(+core: J.Core, frame: J.Frame, +libm: M.Libm, r: J.Random.State & Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  (rng, white) = r
  setup.cellular(core, frame, libm, white, J.Surface.create_cellular(rng, 800, 450, 32))

# After InitWindow(800, 450) and SetRandomSeed(seed): the nine images
# (white noise, then cellular, drawing from the stream) as textures,
# SetTargetFPS(60).
def setup(+seed: U32, +libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.white(core, frame, libm, J.Surface.create_white_noise(J.Random.seed(seed), 800, 450, 0.5))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - image generation", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
