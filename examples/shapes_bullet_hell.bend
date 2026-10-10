# raylib [shapes] example - bullet hell, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_bullet_hell.c (zlib/libpng,
# Copyright (c) 2025 Zero (@zerohorsepower)); see LICENSES/raylib.txt.
#
# A spawner fires rows of bullets around the screen center every few frames,
# turning by an angle increment; bullets leaving the screen are disabled. The
# bullets are drawn from a 24x24 render texture (or, after ENTER, as circles).
# The bullet directions' sinf/cosf and DrawRectanglePro's rotations follow the
# libm profile: under M.AppleLibm{} (whole degrees within one turn) the first
# direction past 360 degrees refuses the frame and every later one
# (docs/SINCOSF.md, docs/DRIVER.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Bullet is Data:
  Bullet{x: F32, y: F32, ax: F32, ay: F32, disabled: Bool, color: U32}

type Config is Data:
  Config{speed: F32, rows: U32, base: F32, increment: U32, cooldown: F32, timer: F32, rotation: F32, performance: Bool, valid: Bool}

type State is Type:
  State{bullets: +List<Bullet>, count: U32, disabled: U32, config: Config, target: Maybe<J.RenderTexture>}

# -----------------------------------------------------------------------------
# Update

def trig(value: Maybe<F32>) -> F32 & Bool:
  match value:
    case Some{+v}: (v, True{})
    case None{}: (0.0, False{})

def bullet.at(+speed: F32, +color: U32, c: F32 & Bool, s: F32 & Bool) -> Bullet & Bool:
  (+cosine, +cok) = c
  (+sine, +sok) = s
  (Bullet{400.0, 225.0, (speed * cosine : F32), (speed * sine : F32), False{}, color}, cok && sok)

# One row: direction base + degreesPerRow*row, color bulletColor[row % 2].
def bullet(+libm: M.Libm, +speed: F32, +direction: F32, +row: U32) -> Bullet & Bool:
  +radians = (direction * (3.14159265358979323846 / 180.0) : F32)
  bullet.at(speed, Bool.pick(U32, U32.is_eq((row % 2 : U32), 0), J.Color.RED(), J.Color.BLUE()),
    trig(M.Libm.cos(libm, radians)), trig(M.Libm.sin(libm, radians)))

def spawned.push(rest: +List<Bullet> & Bool, b: Bullet & Bool) -> +List<Bullet> & Bool:
  (bullets, +ok) = rest
  (+one, +fine) = b
  (Con{one, bullets}, ok && fine)

# The rows in order (row 0 first).
def spawned(n: Nat, +libm: M.Libm, +speed: F32, +base: F32, +per: F32, +row: U32) -> +List<Bullet> & Bool:
  match n:
    case 0n: (Nil{}, True{})
    case 1n+p:
      spawned.push(spawned(p, libm, speed, base, per, (row + 1 : U32)), bullet(libm, speed, (base + per * U32.to_f32(row) : F32), row))

# Moves an enabled bullet; 1 when it leaves the screen (disabled now).
def moved.step(off: Bool, +b: Bullet) -> Bullet & U32:
  match off:
    case True{}: (b, 0)
    case False{}:
      Bullet{+x, +y, +ax, +ay, _, +color} = b
      +nx = (x + ax : F32)
      +ny = (y + ay : F32)
      +out = (nx < F32.neg(20.0) : F32) || (nx > 820.0 : F32) || (ny < F32.neg(20.0) : F32) || (ny > 470.0 : F32)
      (Bullet{nx, ny, ax, ay, out, color}, Bool.to_u32(out))

def moved.one(+b: Bullet) -> Bullet & U32:
  Bullet{_, _, _, _, +off, _} = b
  moved.step(off, b)

def moved.cons(one: Bullet & U32, rest: +List<Bullet> & U32) -> +List<Bullet> & U32:
  (+b, +k) = one
  (bullets, +total) = rest
  (Con{b, bullets}, (k + total : U32))

# The bullets after one step, with the number disabled by it.
def moved(bullets: +List<Bullet>) -> +List<Bullet> & U32:
  match bullets:
    case Nil{}: (Nil{}, 0)
    case Con{+b, rest}: moved.cons(moved.one(b), moved(rest))

def pressed(+core: J.Core, +a: U32, +b: U32) -> Bool:
  J.Input.is_key_pressed(core, a) || J.Input.is_key_pressed(core, b)

# The input logic after the bullets move.
def configured(+core: J.Core, +config: Config) -> Config:
  Config{+speed, +rows, +base, +increment, +cooldown, +timer, +rotation, +performance, +valid} = config
  +r1 = Bool.pick(U32, pressed(core, J.KeyboardKey.KEY_RIGHT(), J.KeyboardKey.KEY_D()) && (rows < 359 : U32), (rows + 1 : U32), rows)
  +r2 = Bool.pick(U32, pressed(core, J.KeyboardKey.KEY_LEFT(), J.KeyboardKey.KEY_A()) && (r1 > 1 : U32), (r1 - 1 : U32), r1)
  +s1 = Bool.pick(F32, pressed(core, J.KeyboardKey.KEY_UP(), J.KeyboardKey.KEY_W()), (speed + 0.25 : F32), speed)
  +s2 = Bool.pick(F32, pressed(core, J.KeyboardKey.KEY_DOWN(), J.KeyboardKey.KEY_S()) && (s1 > 0.5 : F32), (s1 - 0.25 : F32), s1)
  +c1 = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Z()) && (cooldown > 1.0 : F32), (cooldown - 1.0 : F32), cooldown)
  +c2 = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_X()), (c1 + 1.0 : F32), c1)
  +mode = Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_ENTER()), Bool.not(performance), performance)
  +turn = Bool.pick(U32, J.Input.is_key_down(core, J.KeyboardKey.KEY_SPACE()), ((increment + 1) % 360 : U32), increment)
  Config{s2, r2, base, turn, c2, timer, rotation, mode, valid}

def update.moved(+core: J.Core, +count: U32, +disabled: U32, +config: Config, target: Maybe<J.RenderTexture>, r: +List<Bullet> & U32) -> J.Core & State:
  (bullets, +off) = r
  +clear = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_C())
  +kept = Bool.pick(U32, clear, 0, count)
  (core, State{Bool.pick(+List<Bullet>, clear, Nil{}, bullets), kept, Bool.pick(U32, clear, 0, (disabled + off : U32)), configured(core, config), target})

def update.spawned(+core: J.Core, bullets: +List<Bullet>, +count: U32, +disabled: U32, +config: Config, target: Maybe<J.RenderTexture>, r: +List<Bullet> & Bool) -> J.Core & State:
  Config{+speed, +rows, +base, +increment, +cooldown, _, +rotation, +performance, +valid} = config
  (fresh, +ok) = r
  update.moved(core, (count + rows : U32), disabled,
    Config{speed, rows, (base + U32.to_f32(increment) : F32), increment, cooldown, cooldown, rotation, performance, valid && ok},
    target, moved(List.append(&2, Bullet, bullets, fresh)))

def update.timed(spawn: Bool, +libm: M.Libm, +core: J.Core, bullets: +List<Bullet>, +count: U32, +disabled: U32, +config: Config, target: Maybe<J.RenderTexture>) -> J.Core & State:
  match spawn:
    case True{}:
      Config{+speed, +rows, +base, _, _, _, _, _, _} = config
      update.spawned(core, bullets, count, disabled, config, target, spawned(U32.to_nat(rows), libm, speed, base, (360.0 / U32.to_f32(rows) : F32), 0))
    case False{}: update.moved(core, count, disabled, config, target, moved(bullets))

# spawnCooldownTimer--; below zero it restarts and one bullet per row spawns.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{bullets, +count, +disabled, +config, target} = state
  Config{+speed, +rows, +base, +increment, +cooldown, +timer, +rotation, +performance, +valid} = config
  +t = (timer - 1.0 : F32)
  update.timed((t < 0.0 : F32), libm, core, bullets, count, disabled, Config{speed, rows, base, increment, cooldown, t, rotation, performance, valid}, target)

# -----------------------------------------------------------------------------
# Draw

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTexture(bulletTexture.texture, (int)(x - width*0.5f), (int)(y - height*0.5f), color).
def textured.at(+b: Bullet, frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  Bullet{+x, +y, _, _, _, +color} = b
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  shown(id, depth, J.Draw.texture(frame, J.Texture{tid, w, h, format, linear, alpha, texels},
    F32.trunc((x - U32.to_f32(w) * 0.5 : F32)), F32.trunc((y - U32.to_f32(h) * 0.5 : F32)), color))

def textured(+b: Bullet, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match target:
    case None{}: (frame, None{})
    case Some{t}: textured.at(b, frame, t)

def textured.enabled(off: Bool, +b: Bullet, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match off:
    case True{}: (frame, target)
    case False{}: textured(b, frame, target)

def textured.step(+b: Bullet, r: J.Frame & Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  Bullet{_, _, _, _, +off, _} = b
  (frame, target) = r
  textured.enabled(off, b, frame, target)

def textured.all(bullets: +List<Bullet>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match bullets:
    case Nil{}: r
    case Con{+b, rest}: textured.all(rest, textured.step(b, r))

def circle(off: Bool, +libm: M.Libm, +b: Bullet, frame: J.Frame) -> J.Frame:
  match off:
    case True{}: frame
    case False{}:
      Bullet{+x, +y, _, _, _, +color} = b
      J.Draw.circle_lines_v_for(libm, J.Draw.circle_v_for(libm, frame, M.Vector2{x, y}, 10.0, color), M.Vector2{x, y}, 10.0, J.Color.BLACK())

# DrawCircleV and DrawCircleLinesV with the bullet radius.
def circles(+libm: M.Libm, bullets: +List<Bullet>, frame: J.Frame) -> J.Frame:
  match bullets:
    case Nil{}: frame
    case Con{+b, rest}:
      Bullet{_, _, _, _, +off, _} = b
      circles(libm, rest, circle(off, libm, b, frame))

def ui.mode(performance: Bool, frame: J.Frame) -> J.Frame:
  match performance:
    case True{}: J.Draw.text(frame, "Draw method: DrawTexture(*)", 620.0, 20.0, 10.0, J.Color.GREEN())
    case False{}: J.Draw.text(frame, "Draw method: DrawCircle(*)", 620.0, 20.0, 10.0, J.Color.RED())

def ui.status(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 155.0, 420.0, 10.0, J.Color.GREEN())

def ui(+fps: U32, +live: U32, +config: Config, frame: J.Frame) -> J.Frame:
  Config{+speed, +rows, _, +increment, +cooldown, _, _, +performance, _} = config
  +shade = J.Color.rgba(0, 0, 0, 200)
  f1 = J.Draw.text(J.Draw.rectangle(frame, 10.0, 10.0, 280.0, 150.0, shade), "Controls:", 20.0, 20.0, 10.0, J.Color.LIGHTGRAY())
  f2 = J.Draw.text(f1, "- Right/Left or A/D: Change rows number", 40.0, 40.0, 10.0, J.Color.LIGHTGRAY())
  f3 = J.Draw.text(f2, "- Up/Down or W/S: Change bullet speed", 40.0, 60.0, 10.0, J.Color.LIGHTGRAY())
  f4 = J.Draw.text(f3, "- Z or X: Change spawn cooldown", 40.0, 80.0, 10.0, J.Color.LIGHTGRAY())
  f5 = J.Draw.text(f4, "- Space (Hold): Change the angle increment", 40.0, 100.0, 10.0, J.Color.LIGHTGRAY())
  f6 = J.Draw.text(f5, "- Enter: Switch draw method (Performance)", 40.0, 120.0, 10.0, J.Color.LIGHTGRAY())
  f7 = J.Draw.text(f6, "- C: Clear bullets", 40.0, 140.0, 10.0, J.Color.LIGHTGRAY())
  f8 = ui.mode(performance, J.Draw.rectangle(f7, 610.0, 10.0, 170.0, 30.0, shade))
  ui.status(J.Text.format("[ FPS: %d, Bullets: %d, Rows: %d, Bullet speed: %.2f, Angle increment per frame: %d, Cooldown: %.0f ]",
    [J.TextInt{fps}, J.TextInt{live}, J.TextInt{rows}, J.TextFloat{speed}, J.TextInt{increment}, J.TextFloat{cooldown}]),
    J.Draw.rectangle(f8, 135.0, 410.0, 530.0, 30.0, shade))

def draw.status(bullets: +List<Bullet>, +count: U32, +disabled: U32, +config: Config, target: Maybe<J.RenderTexture>, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (State{bullets, count, disabled, config, target}, ui(fps, (count - disabled : U32), config, frame)))

def draw.finish(+core: J.Core, bullets: +List<Bullet>, +count: U32, +disabled: U32, +config: Config, target: Maybe<J.RenderTexture>, frame: J.Frame, result: Maybe<(J.Core & U32)>) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (State{bullets, count, disabled, config, target}, J.Frame.refuse(frame)))
    case Some{pair}: draw.status(bullets, count, disabled, config, target, frame, pair)

def draw.bullets(+core: J.Core, bullets: +List<Bullet>, +count: U32, +disabled: U32, +config: Config, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  draw.finish(core, bullets, count, disabled, config, target, frame, J.Core.get_fps(core, J.Core.get_time(core)))

def draw.mode(+libm: M.Libm, performance: Bool, +bullets: +List<Bullet>, frame: J.Frame, target: Maybe<J.RenderTexture>) -> (J.Frame & Maybe<J.RenderTexture>) & +List<Bullet>:
  match performance:
    case True{}: (textured.all(bullets, (frame, target)), bullets)
    case False{}: ((circles(libm, bullets, frame), target), bullets)

def draw.drawn(+core: J.Core, +count: U32, +disabled: U32, +config: Config, r: (J.Frame & Maybe<J.RenderTexture>) & +List<Bullet>) -> J.Core & (State & J.Frame):
  (drawn, bullets) = r
  draw.bullets(core, bullets, count, disabled, config, drawn)

def draw.valid(+libm: M.Libm, +core: J.Core, bullets: +List<Bullet>, +count: U32, +disabled: U32, +config: Config, target: Maybe<J.RenderTexture>, frame: J.Frame) -> J.Core & (State & J.Frame):
  Config{+speed, +rows, +base, +increment, +cooldown, +timer, +rotation, +performance, +valid} = config
  +turned = (rotation + 1.0 : F32)
  +next = {Config{speed, rows, base, increment, cooldown, timer, turned, performance, valid} : Config}
  +square = {J.Rectangle{400.0, 225.0, 120.0, 120.0} : J.Rectangle}
  f1 = J.Draw.rectangle_pro_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), square, M.Vector2{60.0, 60.0}, turned, J.Color.PURPLE())
  f2 = J.Draw.rectangle_pro_for(libm, f1, square, M.Vector2{60.0, 60.0}, (turned + 45.0 : F32), J.Color.PURPLE())
  f3 = J.Draw.circle_lines_for(libm, J.Draw.circle_lines_for(libm, J.Draw.circle_lines_for(libm, f2, 400.0, 225.0, 70.0, J.Color.BLACK()), 400.0, 225.0, 50.0, J.Color.BLACK()), 400.0, 225.0, 30.0, J.Color.BLACK())
  draw.drawn(core, count, disabled, next, draw.mode(libm, performance, bullets, f3, target))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{bullets, +count, +disabled, +config, target} = state
  Config{_, _, _, _, _, _, _, _, +valid} = config
  match valid:
    case True{}: draw.valid(libm, core, bullets, count, disabled, config, target, frame)
    case False{}: (core, (State{bullets, count, disabled, config, target}, J.Frame.refuse(frame)))

# The main loop's body; libm is the sinf/cosf profile of the bullet directions and DrawRectanglePro.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# -----------------------------------------------------------------------------
# Setup

def setup.drawn(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{Nil{}, 0, 0, Config{3.0, 6, 0.0, 5, 2.0, 2.0, 0.0, True{}, True{}}, target}))

def setup.loaded(+libm: M.Libm, +core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  match target:
    case None{}: setup.drawn(core, (frame, None{}))
    case Some{t}:
      painted = J.Draw.circle_lines_for(libm, J.Draw.circle_for(libm, J.Frame.begin_texture_mode(frame, t), 12.0, 12.0, 10.0, J.Color.WHITE()), 12.0, 12.0, 10.0, J.Color.BLACK())
      setup.drawn(core, J.Frame.end_texture_mode(painted))

# After InitWindow(800, 450): the 24x24 bullet texture with a white circle and
# its black outline, six rows at speed 3 every third frame, SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(libm, core, J.RenderTexture.load(frame, 24, 24))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - bullet hell", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
