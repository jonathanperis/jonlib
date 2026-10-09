# raylib [core] example - random values, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_random_values.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A new GetRandomValue(-8, 5) every 120 frames. raylib seeds the generator
# from time(NULL) in InitWindow; here the seed is a setup argument. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{rng: J.Random.State, value: F32, frames: U32}

def drawn(+frames: U32, r: J.Random.State & F32) -> State:
  (rng, +value) = r
  State{rng, value, frames}

def update.at(roll: Bool, rng: J.Random.State, +value: F32, +frames: U32) -> State:
  match roll:
    case True{}: drawn(0, J.Random.value(rng, F32.neg(8.0), 5.0))
    case False{}: State{rng, value, frames}

# framesCounter++; when (framesCounter/120)%2 is 1 a new value is drawn and
# the counter restarts.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{rng, +value, +frames} = state
  +f = (frames + 1 : U32)
  (core, update.at(U32.is_eq(((f / 120) % 2 : U32), 1), rng, value, f))

def int(+x: F32) -> U32:
  Bool.pick(U32, (x < 0.0 : F32), (0 - F32.to_u32(F32.neg(x)) : U32), F32.to_u32(x))

def draw.value(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 360.0, 180.0, 80.0, J.Color.LIGHTGRAY())

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +value, +frames} = state
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "Every 2 seconds a new random value is generated:", 130.0, 100.0, 20.0, J.Color.MAROON())
  (core, (State{rng, value, frames}, draw.value(J.Text.format("%i", [J.TextInt{int(value)}]), f1)))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.drawn(+core: J.Core, frame: J.Frame, r: J.Random.State & F32) -> J.Core & (J.Frame & State):
  (rng, +value) = r
  (J.Core.set_target_fps(core, 60), (frame, State{rng, value, 0}))

# After InitWindow(800, 450) and SetRandomSeed(seed): the first value,
# framesCounter 0, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.drawn(core, frame, J.Random.value(J.Random.seed(seed), F32.neg(8.0), 5.0))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - random values", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
