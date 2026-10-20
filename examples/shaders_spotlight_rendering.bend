# raylib [shaders] example - spotlight rendering, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_spotlight_rendering.c
# (zlib/libpng, Copyright (c) 2019-2025 Chris Camacho (@chriscamacho) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A star field and sixteen copies of a texture moving on cos and sin of the
# frame counter (binary64, the libm profile's M.Libm.cos64/sin64), under a
# shader that darkens everything outside three spots. The reference's
# software renderer runs no shader (docs/SHADERS.md): the white rectangle
# drawn in shader mode covers the screen, and a frame shows it with the
# frame rate and the three texts. The port still moves and draws the stars
# and the textures (their int conversions are checked) and sets the spots'
# uniforms. raylib seeds the generator from time(NULL) in InitWindow; here
# the seed is a setup argument. LoadTexture of a .png is the PNG loader
# (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Star is Data:
  Star{x: F32, y: F32, sx: F32, sy: F32}

# ok: the speed loop's comparison was answered.
type Spot is Data:
  Spot{x: F32, y: F32, sx: F32, sy: F32, ok: Bool}

# valid: the texture loaded, every spot was made and no refusal so far.
type State is Type:
  State{valid: Bool, rng: J.Random.State, stars: +List<Star>, spots: +List<Spot>, counter: U32, texture: Maybe<J.Texture>, shader: J.Shader}

# What the last random value is for in a loop that draws again.
type Stage is Data:
  AtFirst{}
  AtSecond{}
  AtThird{}
  AtFourth{}
  AtAgain{}
  AtDone{}
  AtFailed{}

def draw.speed(rng: J.Random.State) -> J.Random.State & F32:
  J.Random.value(rng, F32.neg(1000.0), 1000.0)

# ResetStar: speed = GetRandomValue(-1000, 1000)/100.0f on each axis, drawn
# again while fabs(speed.x) + (fabs(speed.y) > 1) is 0; the star starts 8
# steps from the middle of the screen. The loop is given its fuel's draws.
def star.reset(fuel: Nat, stage: Stage, +sx: F32, r: J.Random.State & F32) -> J.Random.State & Star:
  match fuel stage:
    case 1n+p AtFirst{}:
      (rng, +v) = r
      star.reset(p, AtSecond{}, (v / 100.0 : F32), draw.speed(rng))
    case 1n+p AtSecond{}:
      (rng, +v) = r
      star.reset(p, Bool.pick(Stage, F32.is_eq(sx, 0.0) && Bool.not((F32.abs((v / 100.0 : F32)) > 1.0 : F32)), AtAgain{}, AtDone{}), sx, (rng, (v / 100.0 : F32)))
    case 1n+p AtAgain{}:
      (rng, _) = r
      star.reset(p, AtFirst{}, 0.0, draw.speed(rng))
    case _ _:
      (rng, +sy) = r
      (rng, Star{(400.0 + sx * 8.0 : F32), (225.0 + sy * 8.0 : F32), sx, sy})

def star.new(rng: J.Random.State) -> J.Random.State & Star:
  star.reset(4096n, AtFirst{}, 0.0, draw.speed(rng))

def star.kept(out: Bool, +x: F32, +y: F32, +sx: F32, +sy: F32, rng: J.Random.State) -> J.Random.State & Star:
  match out:
    case False{}: (rng, Star{x, y, sx, sy})
    case True{}: star.new(rng)

# UpdateStar: a step, and ResetStar once outside the screen.
def star.updated(star: Star, rng: J.Random.State) -> J.Random.State & Star:
  Star{+x, +y, +sx, +sy} = star
  star.kept(((x + sx : F32) < 0.0 : F32) || ((x + sx : F32) > 800.0 : F32) || ((y + sy : F32) < 0.0 : F32) || ((y + sy : F32) > 450.0 : F32), (x + sx : F32), (y + sy : F32), sx, sy, rng)

def stars.done(+acc: +List<Star>, r: J.Random.State & Star) -> J.Random.State & +List<Star>:
  (rng, +last) = r
  (rng, List.reverse(&2, Star, Con{last, acc}))

# The stars after r's one, each updated in order.
def stars.rest(stars: +List<Star>, +acc: +List<Star>, r: J.Random.State & Star) -> J.Random.State & +List<Star>:
  match stars:
    case Nil{}: stars.done(acc, r)
    case Con{+s, rest}:
      (rng, +previous) = r
      stars.rest(rest, Con{previous, acc}, star.updated(s, rng))

def stars.step(stars: +List<Star>, rng: J.Random.State) -> J.Random.State & +List<Star>:
  match stars:
    case Nil{}: (rng, Nil{})
    case Con{+s, rest}: stars.rest(rest, Nil{}, star.updated(s, rng))

# n more stars after r's one.
def stars.made(n: Nat, +acc: +List<Star>, r: J.Random.State & Star) -> J.Random.State & +List<Star>:
  match n:
    case 0n: stars.done(acc, r)
    case 1n+p:
      (rng, +star) = r
      stars.made(p, Con{star, acc}, star.new(rng))

# for (m < screenWidth/2.0) every star updates.
def stars.warmed(n: Nat, r: J.Random.State & +List<Star>) -> J.Random.State & +List<Star>:
  match n:
    case 0n: r
    case 1n+p:
      (rng, +stars) = r
      stars.warmed(p, stars.step(stars, rng))

def draw.spin(rng: J.Random.State) -> J.Random.State & F32:
  J.Random.value(rng, F32.neg(400.0), 40.0)

def below.sum(sum: Maybe<M.Float64>) -> Maybe<Bool>:
  match sum:
    case None{}: None{}
    case Some{M.Float64{high, _}}: Some{(high < 1073741824 : U32)}

# (fabs(a) + fabs(b)) < 2 in binary64, for nonnegative binary32 a and b.
def below(+a: F32, +b: F32) -> Maybe<Bool>:
  Bool.pick(Maybe<Bool>, F32.is_eq(a, 0.0), Some{(b < 2.0 : F32)}, Bool.pick(Maybe<Bool>, F32.is_eq(b, 0.0), Some{(a < 2.0 : F32)},
    below.sum(M.Float64.internal.add(M.Float64.from_f32(a), M.Float64.from_f32(b)))))

def spot.stage(again: Maybe<Bool>) -> Stage:
  match again:
    case None{}: AtFailed{}
    case Some{True{}}: AtAgain{}
    case Some{False{}}: AtDone{}

# A spot: position (GetRandomValue(64, 736), GetRandomValue(64, 386)), and a
# speed of GetRandomValue(-400, 40)/25.0f on each axis drawn until
# fabs(speed.x) + fabs(speed.y) is 2 or more.
def spot.made(fuel: Nat, stage: Stage, +x: F32, +y: F32, +sx: F32, r: J.Random.State & F32) -> J.Random.State & Spot:
  match fuel stage:
    case 1n+p AtFirst{}:
      (rng, +v) = r
      spot.made(p, AtSecond{}, v, 0.0, 0.0, J.Random.value(rng, 64.0, 386.0))
    case 1n+p AtSecond{}:
      (rng, +v) = r
      spot.made(p, AtThird{}, x, v, 0.0, draw.spin(rng))
    case 1n+p AtThird{}:
      (rng, +v) = r
      spot.made(p, AtFourth{}, x, y, (v / 25.0 : F32), draw.spin(rng))
    case 1n+p AtFourth{}:
      (rng, +v) = r
      spot.made(p, spot.stage(below(F32.abs(sx), F32.abs((v / 25.0 : F32)))), x, y, sx, (rng, (v / 25.0 : F32)))
    case 1n+p AtAgain{}:
      (rng, _) = r
      spot.made(p, AtThird{}, x, y, 0.0, draw.spin(rng))
    case 1n+p AtDone{}:
      (rng, +sy) = r
      (rng, Spot{x, y, sx, sy, True{}})
    case _ _:
      (rng, _) = r
      (rng, Spot{x, y, sx, 0.0, False{}})

def spot.new(rng: J.Random.State) -> J.Random.State & Spot:
  spot.made(4096n, AtFirst{}, 0.0, 0.0, 0.0, J.Random.value(rng, 64.0, 736.0))

def spots.done(+acc: +List<Spot>, r: J.Random.State & Spot) -> J.Random.State & +List<Spot>:
  (rng, +last) = r
  (rng, List.reverse(&2, Spot, Con{last, acc}))

def spots.made(n: Nat, +acc: +List<Spot>, r: J.Random.State & Spot) -> J.Random.State & +List<Spot>:
  match n:
    case 0n: spots.done(acc, r)
    case 1n+p:
      (rng, +spot) = r
      spots.made(p, Con{spot, acc}, spot.new(rng))

def spots.ok(spots: +List<Spot>) -> Bool:
  match spots:
    case Nil{}: True{}
    case Con{Spot{_, _, _, _, ok}, rest}: ok && spots.ok(rest)

# The first spot follows the mouse (y from the bottom); the others move and
# turn back 64 pixels from an edge.
def spot.moved(first: Bool, spot: Spot, mouse: M.Vector2) -> Spot:
  Spot{+x, +y, +sx, +sy, ok} = spot
  M.Vector2{mx, my} = mouse
  Bool.pick(Spot, first, Spot{mx, (450.0 - my : F32), sx, sy, True{}},
    Spot{(x + sx : F32), (y + sy : F32), Bool.pick(F32, ((x + sx : F32) < 64.0 : F32) || ((x + sx : F32) > 736.0 : F32), F32.neg(sx), sx),
      Bool.pick(F32, ((y + sy : F32) < 64.0 : F32) || ((y + sy : F32) > 386.0 : F32), F32.neg(sy), sy), True{}})

def spots.moved(spots: +List<Spot>, +first: Bool, +mouse: M.Vector2) -> +List<Spot>:
  match spots:
    case Nil{}: Nil{}
    case Con{+spot, rest}: Con{spot.moved(first, spot, mouse), spots.moved(rest, False{}, mouse)}

# SetShaderValue(shdrSpot, spots[i].positionLoc, &spots[i].position.x, SHADER_UNIFORM_VEC2) for each spot.
def spots.sent(spots: +List<Spot>, +i: U32, +shader: J.Shader) -> J.Shader:
  match spots:
    case Nil{}: shader
    case Con{Spot{+x, +y, _, _, _}, rest}: spots.sent(rest, (i + 1 : U32), J.Shader.set_value(shader, J.Shader.get_location(shader, "spots[" ++ U32.show(i) ++ "].pos"), [F32.bits(x), F32.bits(y)], 1))

def update.stars(r: J.Random.State & +List<Star>, +core: J.Core, +valid: Bool, +spots: +List<Spot>, +counter: U32, texture: Maybe<J.Texture>, +shader: J.Shader) -> State:
  (rng, +stars) = r
  State{valid, rng, stars, spots.moved(spots, True{}, J.Input.get_mouse_position(core)), (counter + 1 : U32), texture,
    spots.sent(spots.moved(spots, True{}, J.Input.get_mouse_position(core)), 0, shader)}

# frameCounter++, the stars, the spots.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, rng, +stars, +spots, +counter, texture, +shader} = state
  (core, update.stars(stars.step(stars, rng), core, valid, spots, counter, texture, shader))

def scaled(value: Maybe<M.Float64>, +by: F32) -> Maybe<M.Float64>:
  match value:
    case None{}: None{}
    case Some{v}: M.Float64.internal.multiply(v, M.Float64.from_f32(by))

def raised(value: Maybe<M.Float64>, +by: F32) -> Maybe<M.Float64>:
  match value:
    case None{}: None{}
    case Some{v}: M.Float64.internal.add(M.Float64.from_f32(by), v)

def lowered(value: Maybe<M.Float64>) -> Maybe<M.Float64>:
  match value:
    case None{}: None{}
    case Some{v}: M.Float64.internal.subtract(v, M.Float64{1077936128, 0})

def whole(value: Maybe<M.Float64>) -> Maybe<U32>:
  match value:
    case None{}: None{}
    case Some{v}: M.Float64.to_int(v)

# A C int held as a two's-complement word, as a float.
def int.f32(+x: U32) -> F32:
  Bool.pick(F32, (x >= 2147483648 : U32), F32.neg(U32.to_f32((0 - x : U32))), U32.to_f32(x))

type Place is Data:
  Place{x: F32, y: F32}

def place.of(x: Maybe<U32>, y: Maybe<U32>) -> Maybe<Place>:
  match x y:
    case Some{+px} Some{+py}: Some{Place{int.f32(px), int.f32(py)}}
    case _ _: None{}

# (int)((screenWidth/2.0f) + cos((frameCounter + i*8)/51.45f)*(screenWidth/2.2f) - 32) and
# (int)((screenHeight/2.0f) + sin((frameCounter + i*8)/17.87f)*(screenHeight/4.2f)): the float
# arguments promoted, the products, sums and difference in binary64.
def place(+libm: M.Libm, +counter: U32, +i: U32) -> Maybe<Place>:
  place.of(whole(lowered(raised(scaled(M.Libm.cos64(libm, M.Float64.from_f32((U32.to_f32((counter + i * 8 : U32)) / 51.45 : F32))), (800.0 / 2.2 : F32)), 400.0))),
    whole(raised(scaled(M.Libm.sin64(libm, M.Float64.from_f32((U32.to_f32((counter + i * 8 : U32)) / 17.87 : F32))), (450.0 / 4.2 : F32)), 225.0)))

def ray(place: Maybe<Place>, frame: J.Frame, texture: J.Texture) -> J.Frame & J.Texture:
  match place:
    case None{}: (J.Frame.refuse(frame), texture)
    case Some{Place{x, y}}: J.Draw.texture(frame, texture, x, y, J.Color.WHITE())

# DrawTexture(texRay, x, y, WHITE) sixteen times.
def rays(n: Nat, +i: U32, +libm: M.Libm, +counter: U32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  match n:
    case 0n: r
    case 1n+p:
      (frame, texture) = r
      rays(p, (i + 1 : U32), libm, counter, ray(place(libm, counter, i), frame, texture))

# DrawRectangle((int)stars[n].position.x, (int)stars[n].position.y, 2, 2, WHITE).
def stars.drawn(stars: +List<Star>, frame: J.Frame) -> J.Frame:
  match stars:
    case Nil{}: frame
    case Con{Star{x, y, _, _}, rest}: stars.drawn(rest, J.Draw.rectangle(frame, x, y, 2.0, 2.0, J.Color.WHITE()))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  f1 = J.Draw.text(J.Draw.fps(frame, 10.0, 10.0, fps), "Move the mouse!", 10.0, 30.0, 20.0, J.Color.GREEN())
  f2 = J.Draw.text(f1, "Pitch Black", F32.trunc((800.0 * 0.2 : F32)), 225.0, 20.0, J.Color.GREEN())
  (core, (state, J.Draw.text(f2, "Dark", F32.trunc((800.0 * 0.66 : F32)), 225.0, 20.0, J.Color.GREEN())))

def draw.fps(result: Maybe<(J.Core & U32)>, state: State, frame: J.Frame, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# BeginShaderMode(shdrSpot); DrawRectangle(0, 0, screenWidth, screenHeight, WHITE); EndShaderMode(); DrawFPS(10, 10) and the texts.
def draw.lit(r: J.Frame & J.Texture, +core: J.Core, +valid: Bool, rng: J.Random.State, +stars: +List<Star>, +spots: +List<Spot>, +counter: U32, +shader: J.Shader) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  draw.fps(J.Core.get_fps(core, J.Core.get_time(core)), State{valid, rng, stars, spots, counter, Some{texture}, shader},
    J.Frame.end_shader_mode(J.Draw.rectangle(J.Frame.begin_shader_mode(frame, shader), 0.0, 0.0, 800.0, 450.0, J.Color.WHITE())), core)

def draw.at(valid: Bool, texture: Maybe<J.Texture>, +libm: M.Libm, +core: J.Core, rng: J.Random.State, +stars: +List<Star>, +spots: +List<Spot>, +counter: U32, +shader: J.Shader, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid texture:
    case True{} Some{t}: draw.lit(rays(16n, 0, libm, counter, (stars.drawn(stars, J.Frame.clear_background(frame, J.Color.DARKBLUE())), t)), core, True{}, rng, stars, spots, counter, shader)
    case True{} None{}: (core, (State{False{}, rng, stars, spots, counter, None{}, shader}, J.Frame.refuse(frame)))
    case False{} Some{t}: (core, (State{False{}, rng, stars, spots, counter, Some{t}, shader}, J.Frame.refuse(frame)))
    case False{} None{}: (core, (State{False{}, rng, stars, spots, counter, None{}, shader}, J.Frame.refuse(frame)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, rng, +stars, +spots, +counter, texture, +shader} = state
  draw.at(valid, texture, libm, core, rng, stars, spots, counter, shader, frame)

# The main loop's body; libm is the profile of the binary64 cos and sin.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# spots[i].inner = 28.0f*(i + 1) and radius = 48.0f*(i + 1), with the position.
def spots.described(spots: +List<Spot>, +i: U32, +shader: J.Shader) -> J.Shader:
  match spots:
    case Nil{}: shader
    case Con{_, rest}: spots.described(rest, (i + 1 : U32), J.Shader.set_value(J.Shader.set_value(shader, J.Shader.get_location(shader, "spots[" ++ U32.show(i) ++ "].inner"), [F32.bits((28.0 * U32.to_f32((i + 1 : U32)) : F32))], 0),
      J.Shader.get_location(shader, "spots[" ++ U32.show(i) ++ "].radius"), [F32.bits((48.0 * U32.to_f32((i + 1 : U32)) : F32))], 0))

# sw = (float)GetScreenWidth() to the screenWidth uniform, then each spot's values.
def shader.made(+spots: +List<Spot>, +shader: J.Shader) -> J.Shader:
  spots.described(spots, 0, spots.sent(spots, 0, J.Shader.set_value(shader, J.Shader.get_location(shader, "screenWidth"), [F32.bits(800.0)], 0)))

def setup.spots(r: J.Random.State & +List<Spot>, +dir: String, +core: J.Core, frame: J.Frame, +stars: +List<Star>, texture: Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (rng, +spots) = r
  (J.Core.set_target_fps(core, 60), (frame, State{spots.ok(spots), rng, stars, spots, 0, texture,
    shader.made(spots, J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/spotlight.fs"}))}))

def setup.stars(r: J.Random.State & +List<Star>, +dir: String, +core: J.Core, frame: J.Frame, texture: Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (rng, +stars) = r
  setup.spots(spots.made(2n, Nil{}, spot.new(rng)), dir, core, frame, stars, texture)

def setup.uploaded(+seed: U32, +dir: String, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  setup.stars(stars.warmed(400n, stars.made(399n, Nil{}, star.new(J.Random.seed(seed)))), dir, core, frame, texture)

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# After InitWindow(800, 450) and SetRandomSeed(seed): HideCursor(), LoadTexture("resources/raysan.png"), 400
# stars reset and updated 400 times, the shader, three spots, SetTargetFPS(60).
def setup(+seed: U32, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/raysan.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.uploaded(seed, dir, J.Input.hide_cursor(core), upload(frame, result))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - spotlight rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(0, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
