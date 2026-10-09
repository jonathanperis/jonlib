# raylib [textures] example - bunnymark, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_bunnymark.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Holding the left button adds 100 bunnies a frame at the mouse with random
# speeds and colors; P pauses. raylib seeds GetRandomValue from time(NULL) in
# InitWindow; here the seed is a setup argument. The color's three
# GetRandomValue calls are an initializer list, whose order C leaves
# unspecified; the reference compiler (clang) draws them left to right, as
# here. LoadTexture of a .png file is LoadImage (raylib's PNG loader,
# Surface.load_png here) and LoadTextureFromImage. No SetTargetFPS: frames
# do not wait. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Bunny is Data:
  Bunny{x: F32, y: F32, sx: F32, sy: F32, color: U32}

type State is Type:
  State{rng: J.Random.State, bunnies: +List<Bunny>, count: U32, paused: Bool, texture: Maybe<J.Texture>, w: F32, h: F32}

def drawn.channel(r: J.Random.State & F32) -> J.Random.State & U32:
  (rng, +v) = r
  (rng, F32.to_u32(v))

def bunny.blue(+x: F32, +y: F32, +sx: F32, +sy: F32, +red: U32, +green: U32, r: J.Random.State & U32) -> J.Random.State & Bunny:
  (rng, +blue) = r
  (rng, Bunny{x, y, sx, sy, J.Color.rgba(red, green, blue, 255)})

def bunny.green(+x: F32, +y: F32, +sx: F32, +sy: F32, +red: U32, r: J.Random.State & U32) -> J.Random.State & Bunny:
  (rng, +green) = r
  bunny.blue(x, y, sx, sy, red, green, drawn.channel(J.Random.value(rng, 100.0, 240.0)))

def bunny.red(+x: F32, +y: F32, +sx: F32, +sy: F32, r: J.Random.State & U32) -> J.Random.State & Bunny:
  (rng, +red) = r
  bunny.green(x, y, sx, sy, red, drawn.channel(J.Random.value(rng, 80.0, 240.0)))

def bunny.sy(+x: F32, +y: F32, +sx: F32, r: J.Random.State & F32) -> J.Random.State & Bunny:
  (rng, +sy) = r
  bunny.red(x, y, sx, sy, drawn.channel(J.Random.value(rng, 50.0, 240.0)))

def bunny.sx(+x: F32, +y: F32, r: J.Random.State & F32) -> J.Random.State & Bunny:
  (rng, +sx) = r
  bunny.sy(x, y, sx, J.Random.value(rng, F32.neg(250.0), 250.0))

# A new bunny at the mouse: speed.x, speed.y, then the color's r, g, b.
def bunny(rng: J.Random.State, +mouse: M.Vector2) -> J.Random.State & Bunny:
  M.Vector2{+x, +y} = mouse
  bunny.sx(x, y, J.Random.value(rng, F32.neg(250.0), 250.0))

def added.one(+rest: +List<Bunny>, r: J.Random.State & Bunny) -> J.Random.State & +List<Bunny>:
  (rng, +b) = r
  (rng, List.append(&2, Bunny, rest, [b]))

def added.room(room: Bool, +mouse: M.Vector2, rng: J.Random.State, +bunnies: +List<Bunny>) -> J.Random.State & +List<Bunny>:
  match room:
    case True{}: added.one(bunnies, bunny(rng, mouse))
    case False{}: (rng, bunnies)

def added.step(+mouse: M.Vector2, +count: U32, r: J.Random.State & +List<Bunny>) -> J.Random.State & +List<Bunny>:
  (rng, +bunnies) = r
  added.room((count < 80000 : U32), mouse, rng, bunnies)

# 100 bunnies while below MAX_BUNNIES (80000), appended in order.
def added(n: Nat, +mouse: M.Vector2, +count: U32, r: J.Random.State & +List<Bunny>) -> J.Random.State & +List<Bunny>:
  match n:
    case 0n: r
    case 1n+p: added(p, mouse, (count + 1 : U32), added.step(mouse, count, r))

# position += speed*GetFrameTime(); a speed flips when the bunny's center
# leaves the screen (the top edge 40 pixels down).
def moved(+ft: F32, +hw: F32, +hh: F32, +b: Bunny) -> Bunny:
  Bunny{+x, +y, +sx, +sy, +color} = b
  +nx = (x + sx * ft : F32)
  +ny = (y + sy * ft : F32)
  +fx = Bool.pick(F32, ((nx + hw : F32) > 800.0 : F32) || ((nx + hw : F32) < 0.0 : F32), (sx * F32.neg(1.0) : F32), sx)
  +fy = Bool.pick(F32, ((ny + hh : F32) > 450.0 : F32) || ((ny + hh - 40.0 : F32) < 0.0 : F32), (sy * F32.neg(1.0) : F32), sy)
  Bunny{nx, ny, fx, fy, color}

def all.moved(bunnies: +List<Bunny>, +ft: F32, +hw: F32, +hh: F32) -> +List<Bunny>:
  match bunnies:
    case Nil{}: Nil{}
    case Con{+b, rest}: Con{moved(ft, hw, hh, b), all.moved(rest, ft, hw, hh)}

def update.added(+core: J.Core, +count: U32, +paused: Bool, texture: Maybe<J.Texture>, +w: F32, +h: F32, r: J.Random.State & +List<Bunny>) -> J.Core & State:
  (rng, +bunnies) = r
  +n = List.length(&2, Bunny, bunnies)
  +p = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_P()), Bool.not(paused), paused)
  +b = Bool.pick(+List<Bunny>, p, bunnies, all.moved(bunnies, J.Core.get_frame_time(core), (w / 2.0 : F32), (h / 2.0 : F32)))
  (core, State{rng, b, U32.from_nat(n), p, texture, w, h})

def update.adding(down: Bool, +mouse: M.Vector2, +count: U32, r: J.Random.State & +List<Bunny>) -> J.Random.State & +List<Bunny>:
  match down:
    case True{}: added(100n, mouse, count, r)
    case False{}: r

def update(+core: J.Core, state: State) -> J.Core & State:
  State{rng, +bunnies, +count, +paused, texture, +w, +h} = state
  +down = J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  update.added(core, count, paused, texture, w, h, update.adding(down, J.Input.get_mouse_position(core), count, (rng, bunnies)))

def draw.one(+x: F32, +y: F32, +color: U32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  (frame, texture) = r
  J.Draw.texture(frame, texture, x, y, color)

# DrawTexture(texBunny, (int)x, (int)y, color) for every bunny in order.
def draw.bunnies(bunnies: +List<Bunny>, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  match bunnies:
    case Nil{}: r
    case Con{Bunny{+x, +y, _, _, +color}, rest}: draw.bunnies(rest, draw.one(x, y, color, r))

def draw.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

def draw.all(bunnies: +List<Bunny>, frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.kept(draw.bunnies(bunnies, (frame, t)))

def draw.line(text: Maybe<String>, +x: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, 10.0, 20.0, color)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.done(+core: J.Core, rng: J.Random.State, +bunnies: +List<Bunny>, +count: U32, +paused: Bool, +w: F32, +h: F32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = J.Draw.rectangle(frame, 0.0, 0.0, 800.0, 40.0, J.Color.BLACK())
  f2 = draw.line(J.Text.format("bunnies: %i", [J.TextInt{count}]), 120.0, J.Color.GREEN(), f1)
  f3 = draw.line(J.Text.format("batched draw calls: %i", [J.TextInt{(1 + count / 8192 : U32)}]), 320.0, J.Color.MAROON(), f2)
  draw.fps.done(State{rng, bunnies, count, paused, texture, w, h}, f3, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +bunnies, +count, +paused, texture, +w, +h} = state
  draw.done(core, rng, bunnies, count, paused, w, h, draw.all(bunnies, J.Frame.clear_background(frame, J.Color.RAYWHITE()), texture))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.sized(+seed: U32, +core: J.Core, frame: J.Frame, texture: J.Texture) -> J.Core & (J.Frame & State):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  (core, (frame, State{J.Random.seed(seed), Nil{}, 0, False{}, Some{J.Texture{id, w, h, format, linear, alpha, texels}}, U32.to_f32(w), U32.to_f32(h)}))

def setup.uploaded(+seed: U32, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: (core, (frame, State{J.Random.seed(seed), Nil{}, 0, False{}, None{}, 0.0, 0.0}))
    case Some{t}: setup.sized(seed, core, frame, t)

def setup.loaded(+seed: U32, +core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (core, (frame, State{J.Random.seed(seed), Nil{}, 0, False{}, None{}, 0.0, 0.0}))
    case Done{image}: setup.uploaded(seed, core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450) and SetRandomSeed(seed): LoadTexture("resources/raybunny.png"), no bunnies.
def setup(+seed: U32, dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/raybunny.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(seed, core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - bunnymark", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(0, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
