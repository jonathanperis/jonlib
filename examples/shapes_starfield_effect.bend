# raylib [shapes] example - starfield effect, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_starfield_effect.c (zlib/libpng,
# Copyright (c) 2025 JP Mortiboys (@themushroompirates)); see LICENSES/raylib.txt.
#
# 420 stars flying toward the viewer; the wheel changes the speed, SPACE
# switches between streaks and circles. raylib seeds GetRandomValue from
# time(NULL) in InitWindow; here the seed is a setup argument. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# stars[i] and starsScreenPos[i].
type Star is Data:
  Star{x: F32, y: F32, z: F32, sx: F32, sy: F32}

type State is Type:
  State{rng: J.Random.State, stars: +List<Star>, speed: F32, lines: Bool}

# stars[i].x and .y: (float)GetRandomValue(-400, 400) and (-225, 225), z = 1.
def spawn.y(+x: F32, +sx: F32, +sy: F32, drawn: J.Random.State & F32) -> J.Random.State & Star:
  (rng, +y) = drawn
  (rng, Star{x, y, 1.0, sx, sy})

def spawn.x(+sx: F32, +sy: F32, drawn: J.Random.State & F32) -> J.Random.State & Star:
  (rng, +x) = drawn
  spawn.y(x, sx, sy, J.Random.value(rng, F32.neg(225.0), 225.0))

def spawn(rng: J.Random.State, +sx: F32, +sy: F32) -> J.Random.State & Star:
  spawn.x(sx, sy, J.Random.value(rng, F32.neg(400.0), 400.0))

def stars.cons(+rest: +List<Star>, r: J.Random.State & Star) -> J.Random.State & +List<Star>:
  (rng, +star) = r
  (rng, Con{star, rest})

def stars.push(r: J.Random.State & +List<Star>) -> J.Random.State & +List<Star>:
  (rng, +acc) = r
  stars.cons(acc, spawn(rng, 0.0, 0.0))

def stars.reversed(r: J.Random.State & +List<Star>) -> J.Random.State & +List<Star>:
  (rng, +acc) = r
  (rng, List.reverse(&2, Star, acc))

# Built in index order (reversed at the end).
def stars.initial(n: Nat, r: J.Random.State & +List<Star>) -> J.Random.State & +List<Star>:
  match n:
    case 0n: stars.reversed(r)
    case 1n+p: stars.initial(p, stars.push(r))

def star.respawn(out: Bool, rng: J.Random.State, +star: Star) -> J.Random.State & Star:
  match out:
    case False{}: (rng, star)
    case True{}:
      Star{_, _, _, +sx, +sy} = star
      spawn(rng, sx, sy)

# z -= dt*speed, then the screen position; a star behind the viewer or off
# the screen respawns (its screen position keeps this frame's value).
def star.step(rng: J.Random.State, +dt: F32, +speed: F32, +star: Star) -> J.Random.State & Star:
  Star{+x, +y, +z, _, _} = star
  +nz = (z - dt * speed : F32)
  +sx = (800.0 * 0.5 + x / nz : F32)
  +sy = (450.0 * 0.5 + y / nz : F32)
  +out = (nz < 0.0 : F32) || (sx < 0.0 : F32) || (sy < 0.0 : F32) || (sx > 800.0 : F32) || (sy > 450.0 : F32)
  star.respawn(out, rng, Star{x, y, nz, sx, sy})

def stars.stepped(+star: Star, +dt: F32, +speed: F32, r: J.Random.State & +List<Star>) -> J.Random.State & +List<Star>:
  (rng, +acc) = r
  stars.cons(acc, star.step(rng, dt, speed, star))

# In index order: each respawn draws from the stream as raylib's loop does.
def stars.step(stars: +List<Star>, +dt: F32, +speed: F32, r: J.Random.State & +List<Star>) -> J.Random.State & +List<Star>:
  match stars:
    case Nil{}: stars.reversed(r)
    case Con{+star, rest}: stars.step(rest, dt, speed, stars.stepped(star, dt, speed, r))

# The wheel adds 2*move/9 when (int)move is nonzero; below 0 the speed is
# 0.1, above 2 it is 2.
def speed.next(+speed: F32, +move: F32) -> F32:
  +s = Bool.pick(F32, F32.is_ne(F32.trunc(move), 0.0), (speed + 2.0 * move / 9.0 : F32), speed)
  Bool.pick(F32, (s < 0.0 : F32), 0.1, Bool.pick(F32, (s > 2.0 : F32), 2.0, s))

def update.done(+speed: F32, +lines: Bool, r: J.Random.State & +List<Star>) -> State:
  (rng, +stars) = r
  State{rng, stars, speed, lines}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{rng, +stars, +speed, +lines} = state
  +s = speed.next(speed, J.Input.get_mouse_wheel_move(core))
  +l = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(lines), lines)
  (core, update.done(s, l, stars.step(stars, J.Core.get_frame_time(core), s, (rng, Nil{}))))

def draw.streak.at(shown: Bool, +from: M.Vector2, +to: M.Vector2, frame: J.Frame) -> J.Frame:
  match shown:
    case True{}: J.Draw.line_v(frame, from, to, J.Color.RAYWHITE())
    case False{}: frame

# The streak from where the star was 1/32 of the depth ago; only when
# (t - z) > 1e-3 in double, which for a float difference is >= 0.001f.
def draw.streak(+star: Star, frame: J.Frame) -> J.Frame:
  Star{+x, +y, +z, +sx, +sy} = star
  +t = M.Math.clamp((z + 1.0 / 32.0 : F32), 0.0, 1.0)
  draw.streak.at(((t - z : F32) >= 0.001 : F32), M.Vector2{(800.0 * 0.5 + x / t : F32), (450.0 * 0.5 + y / t : F32)}, M.Vector2{sx, sy}, frame)

def draw.star(lines: Bool, +libm: M.Libm, +star: Star, frame: J.Frame) -> J.Frame:
  match lines:
    case True{}: draw.streak(star, frame)
    case False{}:
      Star{_, _, +z, +sx, +sy} = star
      J.Draw.circle_v_for(libm, frame, M.Vector2{sx, sy}, M.Math.lerp(z, 1.0, 5.0), J.Color.RAYWHITE())

def draw.stars(stars: +List<Star>, +lines: Bool, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match stars:
    case Nil{}: frame
    case Con{+star, rest}: draw.stars(rest, lines, libm, draw.star(lines, libm, star, frame))

def draw.text(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, J.Color.RAYWHITE())

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +stars, +speed, +lines} = state
  f1 = draw.stars(stars, lines, libm, J.Frame.clear_background(frame, J.Color.lerp(J.Color.DARKBLUE(), J.Color.BLACK(), 0.69)))
  f2 = draw.text(J.Text.format("[MOUSE WHEEL] Current Speed: %.0f", [J.TextFloat{(9.0 * speed / 2.0 : F32)}]), 40.0, f1)
  f3 = draw.text(J.Text.format("[SPACE] Current draw mode: %s", [J.TextString{Bool.pick(String, lines, "Lines", "Circles")}]), 70.0, f2)
  draw.fps.done(State{rng, stars, speed, lines}, f3, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.made(+core: J.Core, frame: J.Frame, r: J.Random.State & +List<Star>) -> J.Core & (J.Frame & State):
  (rng, +stars) = r
  (J.Core.set_target_fps(core, 60), (frame, State{rng, stars, (10.0 / 9.0 : F32), True{}}))

# After InitWindow(800, 450) and SetRandomSeed(seed): STAR_COUNT 420 stars,
# speed 10/9, lines on, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.made(core, frame, stars.initial(420n, (J.Random.seed(seed), Nil{})))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - starfield effect", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
