# raylib [textures] example - particles blending, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_particles_blending.c
# (zlib/libpng, Copyright (c) 2017-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A tail of up to 200 smoke particles follows the mouse: one starts a frame,
# falls, turns and fades out; SPACE switches alpha and additive blending
# (the software renderer blends both the same way). raylib seeds
# GetRandomValue from time(NULL) in InitWindow; here the seed is a setup
# argument. A color's three GetRandomValue calls are an initializer list,
# whose order C leaves unspecified; the reference compiler (clang) draws them
# left to right, as here. DrawTexturePro's sinf/cosf of each particle's
# rotation follow the libm profile. LoadTexture of a .png is the PNG loader
# (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Particle is Data:
  Particle{x: F32, y: F32, color: U32, alpha: F32, size: F32, rotation: F32, active: Bool}

type State is Type:
  State{tail: +List<Particle>, smoke: Maybe<J.Texture>, additive: Bool}

# -----------------------------------------------------------------------------
# Setup: 200 particles, each with a color, a size of 1..30 twentieths and a rotation of 0..360.

def made.rotation(+color: U32, +size: F32, r: J.Random.State & F32) -> J.Random.State & Particle:
  (rng, +rotation) = r
  (rng, Particle{0.0, 0.0, color, 1.0, size, rotation, False{}})

def made.size(+color: U32, r: J.Random.State & F32) -> J.Random.State & Particle:
  (rng, +size) = r
  made.rotation(color, (size / 20.0 : F32), J.Random.value(rng, 0.0, 360.0))

def made.blue(+red: F32, +green: F32, r: J.Random.State & F32) -> J.Random.State & Particle:
  (rng, +blue) = r
  made.size(J.Color.rgba(F32.to_u32(red), F32.to_u32(green), F32.to_u32(blue), 255), J.Random.value(rng, 1.0, 30.0))

def made.green(+red: F32, r: J.Random.State & F32) -> J.Random.State & Particle:
  (rng, +green) = r
  made.blue(red, green, J.Random.value(rng, 0.0, 255.0))

def made.red(r: J.Random.State & F32) -> J.Random.State & Particle:
  (rng, +red) = r
  made.green(red, J.Random.value(rng, 0.0, 255.0))

def made.push(acc: +List<Particle>, one: J.Random.State & Particle) -> J.Random.State & +List<Particle>:
  (rng, +p) = one
  (rng, Con{p, acc})

def made.step(r: J.Random.State & +List<Particle>) -> J.Random.State & +List<Particle>:
  (rng, acc) = r
  made.push(acc, made.red(J.Random.value(rng, 0.0, 255.0)))

def made.done(r: J.Random.State & +List<Particle>) -> +List<Particle>:
  (_, acc) = r
  List.reverse(&2, Particle, acc)

def made(n: Nat, r: J.Random.State & +List<Particle>) -> +List<Particle>:
  match n:
    case 0n: made.done(r)
    case 1n+p: made(p, made.step(r))

# -----------------------------------------------------------------------------
# Update

# The first inactive particle starts at the mouse with alpha 1.
def started(tail: +List<Particle>, +mouse: M.Vector2) -> +List<Particle>:
  match tail:
    case Nil{}: Nil{}
    case Con{+p, +rest}:
      Particle{_, _, +color, _, +size, +rotation, +active} = p
      M.Vector2{+mx, +my} = mouse
      Bool.pick(+List<Particle>, active, Con{p, started(rest, mouse)}, Con{Particle{mx, my, color, 1.0, size, rotation, True{}}, rest})

# An active particle falls gravity/2, fades by 0.005 (to inactive at 0) and turns 2 degrees.
def aged(+p: Particle) -> Particle:
  Particle{+x, +y, +color, +alpha, +size, +rotation, +active} = p
  +faded = (alpha - 0.005 : F32)
  Bool.pick(Particle, active, Particle{x, (y + 3.0 / 2.0 : F32), color, faded, size, (rotation + 2.0 : F32), Bool.not((faded <= 0.0 : F32))}, p)

def aged.all(tail: +List<Particle>) -> +List<Particle>:
  match tail:
    case Nil{}: Nil{}
    case Con{+p, rest}: Con{aged(p), aged.all(rest)}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{tail, smoke, +additive} = state
  (core, State{aged.all(started(tail, J.Input.get_mouse_position(core))), smoke,
    Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(additive), additive)})

# -----------------------------------------------------------------------------
# Draw

def spark.at(+libm: M.Libm, +x: F32, +y: F32, +size: F32, +rotation: F32, +tint: U32, frame: J.Frame, texture: J.Texture) -> J.Frame & J.Texture:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  +sw = (U32.to_f32(w) * size : F32)
  +sh = (U32.to_f32(h) * size : F32)
  J.Draw.texture_pro_for(libm, frame, J.Texture{id, w, h, format, linear, alpha, texels}, J.Rectangle{0.0, 0.0, U32.to_f32(w), U32.to_f32(h)},
    J.Rectangle{x, y, sw, sh}, M.Vector2{(sw / 2.0 : F32), (sh / 2.0 : F32)}, rotation, tint)

# DrawTexturePro(smoke, the whole texture, (position, size*texture), its middle, rotation, Fade(color, alpha)).
def spark(+libm: M.Libm, +p: Particle, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  Particle{+x, +y, +color, +alpha, +size, +rotation, _} = p
  (frame, texture) = r
  spark.at(libm, x, y, size, rotation, J.Color.with_alpha(color, alpha), frame, texture)

def sparks.one(active: Bool, +libm: M.Libm, +p: Particle, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  match active:
    case False{}: r
    case True{}: spark(libm, p, r)

def sparks(tail: +List<Particle>, +libm: M.Libm, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  match tail:
    case Nil{}: r
    case Con{+p, rest}:
      Particle{_, _, _, _, _, _, +active} = p
      sparks(rest, libm, sparks.one(active, libm, p, r))

def drawn.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

def drawn(+libm: M.Libm, +tail: +List<Particle>, frame: J.Frame, smoke: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match smoke:
    case None{}: (frame, None{})
    case Some{t}: drawn.kept(sparks(tail, libm, (frame, t)))

def mode(additive: Bool, frame: J.Frame) -> J.Frame:
  match additive:
    case False{}: J.Draw.text(frame, "ALPHA BLENDING", 290.0, (450.0 - 40.0 : F32), 20.0, J.Color.BLACK())
    case True{}: J.Draw.text(frame, "ADDITIVE BLENDING", 280.0, (450.0 - 40.0 : F32), 20.0, J.Color.RAYWHITE())

def draw.done(+core: J.Core, +tail: +List<Particle>, +additive: Bool, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, smoke) = r
  f1 = J.Draw.text(J.Frame.end_blend_mode(frame), "PRESS SPACE to CHANGE BLENDING MODE", 180.0, 20.0, 20.0, J.Color.BLACK())
  (core, (State{tail, smoke, additive}, mode(additive, f1)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+tail, smoke, +additive} = state
  +blending = Bool.pick(U32, additive, J.BlendMode.BLEND_ADDITIVE(), J.BlendMode.BLEND_ALPHA())
  draw.done(core, tail, additive, drawn(libm, tail, J.Frame.begin_blend_mode(J.Frame.clear_background(frame, J.Color.DARKGRAY()), blending), smoke))

# The main loop's body; libm is the sinf/cosf profile of DrawTexturePro.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.uploaded(+seed: U32, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, smoke) = r
  (J.Core.set_target_fps(core, 60), (frame, State{made(200n, (J.Random.seed(seed), Nil{})), smoke, False{}}))

def setup.loaded(+seed: U32, +core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: setup.uploaded(seed, core, (frame, None{}))
    case Done{image}: setup.uploaded(seed, core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450) and SetRandomSeed(seed): the particles, then
# LoadTexture("resources/spark_flame.png"), alpha blending, SetTargetFPS(60).
def setup(+seed: U32, dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/spark_flame.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(seed, core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - particles blending", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(0, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
