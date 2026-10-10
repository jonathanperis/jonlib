# raylib [shapes] example - simple particles, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_simple_particles.c (zlib/libpng,
# Copyright (c) 2025 Jordi Santonja (@JordSant)); see LICENSES/raylib.txt.
#
# Water, smoke and fire particles from an emitter (the left button moves
# it, LEFT/RIGHT change the type, UP/DOWN the emission rate) in a circular
# buffer of 3000: here the particles from the buffer's tail to its head, in
# order. The example draws its random numbers from the C library's rand()
# without seeding it: M.Libc.rand from the seed 1 under the glibc profiles;
# Apple's generator is not modeled, so every frame is refused there. cosf
# and sinf follow the libm profile (docs/SINCOSF.md). See docs/RANDOM.md and
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A Particle: type (0 water, 1 smoke, 2 fire), position, velocity, radius, color, lifeTime, alive.
type Particle is Data:
  Particle{kind: U32, position: M.Vector2, velocity: M.Vector2, radius: F32, color: U32, life: F32, alive: Bool}

# rand()'s state, the buffer from tail to head; ok: no refusal so far.
type Pool is Data:
  Pool{rand: M.Libc.Rand, particles: +List<Particle>, ok: Bool}

# emissionRate (a C int), currentType and emitterPosition.
type State is Data:
  State{pool: Pool, rate: F32, kind: U32, emitter: M.Vector2}

# The particles after UpdateParticles, and whether every cosf was answered.
type Aged is Data:
  Aged{particles: +List<Particle>, ok: Bool}

def size(+particles: +List<Particle>) -> U32:
  U32.from_nat(List.length(&2, Particle, particles))

# The new particle's radius and color by type.
def look(kind: U32) -> F32 & U32:
  match kind:
    case 0: (5.0, J.Color.BLUE())
    case 1: (7.0, J.Color.GRAY())
    case _: (10.0, J.Color.YELLOW())

def emit.look(+kind: U32, +emitter: M.Vector2, +velocity: M.Vector2, look: F32 & U32) -> Particle:
  (+radius, +color) = look
  Particle{kind, emitter, velocity, radius, color, 0.0, True{}}

# velocity = (speed*cosf(direction*DEG2RAD), speed*sinf(direction*DEG2RAD)).
def emit.made(+emitter: M.Vector2, +kind: U32, +particles: +List<Particle>, +ok: Bool, +speed: F32, +rand: M.Libc.Rand, cosine: Maybe<F32>, sine: Maybe<F32>) -> Pool:
  match cosine sine:
    case Some{+c} Some{+s}: Pool{rand, List.append(&2, Particle, particles, Con{emit.look(kind, emitter, M.Vector2{(speed * c : F32), (speed * s : F32)}, look(kind)), Nil{}}), ok}
    case _ _: Pool{rand, particles, False{}}

# direction = (float)(rand()%360).
def emit.direction(+libm: M.Libm, +emitter: M.Vector2, +kind: U32, +particles: +List<Particle>, +ok: Bool, +speed: F32, r: M.Libc.Rand & U32) -> Pool:
  (+rand, +value) = r
  emit.made(emitter, kind, particles, ok, speed, rand, M.Libm.cos(libm, (U32.to_f32((value % 360 : U32)) * M.Math.DEG2RAD() : F32)),
    M.Libm.sin(libm, (U32.to_f32((value % 360 : U32)) * M.Math.DEG2RAD() : F32)))

# speed = (float)(rand()%10)/5.0f, a tenth of it for fire.
def emit.speed(+libm: M.Libm, +emitter: M.Vector2, +kind: U32, +particles: +List<Particle>, +ok: Bool, r: M.Libc.Rand & U32) -> Pool:
  (+rand, +value) = r
  +speed = (U32.to_f32((value % 10 : U32)) / 5.0 : F32)
  emit.direction(libm, emitter, kind, particles, ok, Bool.pick(F32, U32.is_eq(kind, 2), (speed / 10.0 : F32), speed), M.Libc.rand(rand))

def emit.room(room: Bool, +libm: M.Libm, +emitter: M.Vector2, +kind: U32, +rand: M.Libc.Rand, +particles: +List<Particle>, +ok: Bool) -> Pool:
  match room:
    case False{}: Pool{rand, particles, ok}
    case True{}: emit.speed(libm, emitter, kind, particles, ok, M.Libc.rand(rand))

# EmitParticle: nothing (and no rand()) when the buffer is full, 2999 particles.
def emit(+libm: M.Libm, +emitter: M.Vector2, +kind: U32, pool: Pool) -> Pool:
  Pool{+rand, +particles, +ok} = pool
  emit.room((size(particles) < 2999 : U32), libm, emitter, kind, rand, particles, ok)

def emits(n: Nat, +libm: M.Libm, +emitter: M.Vector2, +kind: U32, +pool: Pool) -> Pool:
  match n:
    case 0n: pool
    case 1n+p: emits(p, libm, emitter, kind, emit(libm, emitter, kind, pool))

# if (rand()%(-emissionRate) == 0) EmitParticle(...).
def emit.chance(+libm: M.Libm, +emitter: M.Vector2, +kind: U32, +every: U32, +particles: +List<Particle>, +ok: Bool, r: M.Libc.Rand & U32) -> Pool:
  (+rand, +value) = r
  emits(Bool.pick(Nat, U32.is_eq((value % every : U32), 0), 1n, 0n), libm, emitter, kind, Pool{rand, particles, ok})

def emitted.sparse(+libm: M.Libm, +emitter: M.Vector2, +kind: U32, +every: U32, pool: Pool) -> Pool:
  Pool{+rand, +particles, +ok} = pool
  emit.chance(libm, emitter, kind, every, particles, ok, M.Libc.rand(rand))

# A negative rate: one particle every -rate frames on average; else rate + 1 particles a frame.
def emitted(sparse: Bool, +libm: M.Libm, +emitter: M.Vector2, +kind: U32, +rate: F32, +pool: Pool) -> Pool:
  match sparse:
    case False{}: emits(U32.to_nat(F32.to_u32((rate + 1.0 : F32))), libm, emitter, kind, pool)
    case True{}: emitted.sparse(libm, emitter, kind, F32.to_u32(F32.neg(rate)), pool)

# The channel's unsigned char minus a step, wrapping.
def faded(+channel: U32, +step: U32) -> U32:
  ((channel + 256 - step) % 256 : U32)

# Disable particle when out of screen.
def outside(+x: F32, +y: F32, +radius: F32) -> Bool:
  (x < F32.neg(radius) : F32) || (x > (800.0 + radius) : F32) || (y < F32.neg(radius) : F32) || (y > (450.0 + radius) : F32)

def aged.cons(+particle: Particle, +fine: Bool, rest: Aged) -> Aged:
  Aged{+particles, +ok} = rest
  Aged{Con{particle, particles}, ok && fine}

# Fire: position.x += velocity.x + cosf(lifeTime*215), upwards, shrinking by 0.15 (dead at 0.02), green -= 3.
def aged.fire(+x: F32, +y: F32, +vx: F32, +vy: F32, +radius: F32, +color: U32, +life: F32, +alive: Bool, cosine: Maybe<F32>, rest: Aged) -> Aged:
  match cosine:
    case None{}: aged.cons(Particle{2, M.Vector2{x, y}, M.Vector2{vx, vy}, radius, color, life, alive}, False{}, rest)
    case Some{+c}: aged.cons(Particle{2, M.Vector2{(x + (vx + c) : F32), (y + (vy - 0.05) : F32)}, M.Vector2{vx, (vy - 0.05 : F32)}, (radius - 0.15 : F32),
      J.Color.rgba(J.Color.red(color), faded(J.Color.green(color), 3), J.Color.blue(color), J.Color.alpha(color)), life,
      alive && Bool.not(((radius - 0.15) <= 0.02 : F32)) && Bool.not(outside((x + (vx + c) : F32), (y + (vy - 0.05) : F32), (radius - 0.15 : F32)))}, True{}, rest)

# Water: gravity 0.2. Smoke: upwards 0.05, growing by 0.5, alpha -= 4 (dead below 4).
def aged.plain(smoke: Bool, +x: F32, +y: F32, +vx: F32, +vy: F32, +radius: F32, +color: U32, +life: F32, +alive: Bool) -> Particle:
  match smoke:
    case False{}: Particle{0, M.Vector2{(x + vx : F32), (y + (vy + 0.2) : F32)}, M.Vector2{vx, (vy + 0.2 : F32)}, radius, color, life,
      alive && Bool.not(outside((x + vx : F32), (y + (vy + 0.2) : F32), radius))}
    case True{}: Particle{1, M.Vector2{(x + vx : F32), (y + (vy - 0.05) : F32)}, M.Vector2{vx, (vy - 0.05 : F32)}, (radius + 0.5 : F32),
      J.Color.rgba(J.Color.red(color), J.Color.green(color), J.Color.blue(color), faded(J.Color.alpha(color), 4)), life,
      alive && Bool.not((faded(J.Color.alpha(color), 4) < 4 : U32)) && Bool.not(outside((x + vx : F32), (y + (vy - 0.05) : F32), (radius + 0.5 : F32)))}

def aged.kind(fire: Bool, +libm: M.Libm, +kind: U32, +x: F32, +y: F32, +vx: F32, +vy: F32, +radius: F32, +color: U32, +life: F32, +alive: Bool, rest: Aged) -> Aged:
  match fire:
    case True{}: aged.fire(x, y, vx, vy, radius, color, life, alive, M.Libm.cos(libm, (life * 215.0 : F32)), rest)
    case False{}: aged.cons(aged.plain(U32.is_eq(kind, 1), x, y, vx, vy, radius, color, life, alive), True{}, rest)

# lifeTime += 1.0f/60.0f, then the move of the particle's type (dead particles move too, until they leave the buffer).
def aged.one(+libm: M.Libm, particle: Particle, rest: Aged) -> Aged:
  Particle{+kind, +position, +velocity, +radius, +color, +life, +alive} = particle
  M.Vector2{+x, +y} = position
  M.Vector2{+vx, +vy} = velocity
  aged.kind(U32.is_eq(kind, 2), libm, kind, x, y, vx, vy, radius, color, (life + 1.0 / 60.0 : F32), alive, rest)

# UpdateParticles.
def aged(particles: +List<Particle>, +libm: M.Libm) -> Aged:
  match particles:
    case Nil{}: Aged{Nil{}, True{}}
    case Con{+particle, rest}: aged.one(libm, particle, aged(rest, libm))

def breathing(particle: Particle) -> Bool:
  Particle{_, _, _, _, _, _, +alive} = particle
  alive

# The dead particles at the tail (UpdateCircularBuffer advances the tail over them).
def stale(particles: +List<Particle>, +count: U32, +open: Bool) -> U32:
  match particles:
    case Nil{}: count
    case Con{+particle, rest}: stale(rest, Bool.pick(U32, open && Bool.not(breathing(particle)), (count + 1 : U32), count), open && Bool.not(breathing(particle)))

def update.aged(+rand: M.Libc.Rand, +ok: Bool, aged: Aged) -> Pool:
  Aged{+particles, +fine} = aged
  Pool{rand, List.drop(&2, Particle, particles, U32.to_nat(stale(particles, 0, True{}))), ok && fine}

def update.pool(+libm: M.Libm, pool: Pool) -> Pool:
  Pool{+rand, +particles, +ok} = pool
  update.aged(rand, ok, aged(particles, libm))

# The emission, the particles' update and the buffer's tail; then UP/DOWN the rate, RIGHT/LEFT the type, the left button the emitter.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+pool, +rate, +kind, +emitter} = state
  +faster = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP()), (rate + 1.0 : F32), rate)
  +next = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), Bool.pick(U32, U32.is_eq(kind, 2), 0, (kind + 1 : U32)), kind)
  (core, State{update.pool(libm, emitted((rate < 0.0 : F32), libm, emitter, kind, rate, pool)),
    Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN()), (faster - 1.0 : F32), faster),
    Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()), Bool.pick(U32, U32.is_eq(next, 0), 2, (next - 1 : U32)), next),
    Bool.pick(M.Vector2, J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT()), J.Input.get_mouse_position(core), emitter)})

def drawn(alive: Bool, +libm: M.Libm, +position: M.Vector2, +radius: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match alive:
    case False{}: frame
    case True{}: J.Draw.circle_v_for(libm, frame, position, radius, color)

# DrawParticles: DrawCircleV(position, radius, color) for the particles alive.
def particles.drawn(particles: +List<Particle>, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match particles:
    case Nil{}: frame
    case Con{Particle{_, +position, _, +radius, +color, _, +alive}, rest}: particles.drawn(rest, libm, drawn(alive, libm, position, radius, color, frame))

def name(kind: U32) -> String:
  match kind:
    case 0: "WATER"
    case 1: "SMOKE"
    case _: "FIRE"

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 15.0, 95.0, 10.0, J.Color.DARKGRAY())

def rate.text(sparse: Bool, +rate: F32, +kind: U32) -> Maybe<String>:
  match sparse:
    case True{}: J.Text.format("Particles every %d frames | Type: %s", [J.TextInt{F32.to_u32(F32.neg(rate))}, J.TextString{name(kind)}])
    case False{}: J.Text.format("%d Particles per frame | Type: %s", [J.TextInt{F32.to_u32((rate + 1.0 : F32))}, J.TextString{name(kind)}])

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, (800.0 - 80.0 : F32), 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+pool, +rate, +kind, _} = state
  Pool{_, +particles, +ok} = pool
  f1 = J.Draw.rectangle(particles.drawn(particles, libm, J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE())), 5.0, 5.0, 315.0, 75.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5))
  f2 = J.Draw.text(J.Draw.text(J.Draw.rectangle_lines(f1, 5.0, 5.0, 315.0, 75.0, J.Color.BLUE()), "CONTROLS:", 15.0, 15.0, 10.0, J.Color.BLACK()), "UP/DOWN: Change Particle Emission Rate", 15.0, 35.0, 10.0,
    J.Color.BLACK())
  f3 = label(rate.text((rate < 0.0 : F32), rate, kind), J.Draw.text(f2, "LEFT/RIGHT: Change Particle Type (Water, Smoke, Fire)", 15.0, 55.0, 10.0, J.Color.BLACK()))
  draw.fps.done(state, f3, J.Core.get_fps(core, J.Core.get_time(core)), core)

# The main loop's body; libm is the profile of the particles' cosf/sinf, of DrawCircleV and of the C library's rand().
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.rand(rand: Maybe<M.Libc.Rand>) -> State:
  match rand:
    case None{}: State{Pool{M.LibcRand{Nil{}}, Nil{}, False{}}, F32.neg(2.0), 0, M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}}
    case Some{+r}: State{Pool{r, Nil{}, True{}}, F32.neg(2.0), 0, M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}}

# After InitWindow(800, 450): an empty buffer, emissionRate -2, water, the emitter at the center; rand() as a program
# that never called srand has it; SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, setup.rand(M.Libc.srand(libm, 1))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - simple particles", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
