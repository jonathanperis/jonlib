# raylib [shapes] example - ball physics, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_ball_physics.c (zlib/libpng,
# Copyright (c) 2025 David Buzatto (@davidbuzatto)); see LICENSES/raylib.txt.
#
# A left press grabs the topmost ball under the mouse and a release throws
# it; a right press adds a ball (held with left control: one a frame); a
# middle press shakes them; the wheel changes gravity. The press test is C's
# hypot(dx, dy) <= radius in binary64: M.Libm.hypot_within, which refuses the
# frame where two faithful hypot results could disagree. raylib seeds
# GetRandomValue from time(NULL) in InitWindow; here the seed is a setup
# argument. A new ball's GetRandomValue calls are an initializer list, whose
# order C leaves unspecified; the reference compiler (clang) evaluates them
# in source order, as here. The pointer to the grabbed ball is the ball's
# flag: one ball at most is grabbed. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Ball is Data:
  Ball{x: F32, y: F32, sx: F32, sy: F32, px: F32, py: F32, radius: F32, color: U32, grabbed: Bool}

type State is Type:
  State{rng: J.Random.State, balls: +List<Ball>, count: U32, ox: F32, oy: F32, gravity: F32, refused: Bool}

# The result of a press over the balls from one index up: status 0 while no
# ball was hit, 1 once one is grabbed, 2 when the test was refused; the offset
# of the last ball examined.
type Press is Data:
  Press{balls: +List<Ball>, status: U32, ox: F32, oy: F32}

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# 0.99f and 0.9f: every ball's friction and elasticity.
def friction() -> F32:
  float(1065185444)

def elasticity() -> F32:
  float(1063675494)

def press.grabbed(+ball: Ball) -> Ball:
  Ball{+x, +y, +sx, +sy, +px, +py, +radius, +color, _} = ball
  Ball{x, y, sx, sy, px, py, radius, color, True{}}

def press.status(inside: Maybe<Bool>) -> U32:
  match inside:
    case None{}: 2
    case Some{hit}: Bool.to_u32(hit)

def press.here(+mx: F32, +my: F32, +ball: Ball, +rest: +List<Ball>) -> Press:
  Ball{+x, +y, _, _, _, _, +radius, _, _} = ball
  +dx = (mx - x : F32)
  +dy = (my - y : F32)
  +status = press.status(M.Libm.hypot_within(dx, dy, radius))
  Press{Con{Bool.pick(Ball, U32.is_eq(status, 1), press.grabbed(ball), ball), rest}, status, dx, dy}

# The balls after this one were examined first (the loop runs from the last).
def press.before(+mx: F32, +my: F32, +ball: Ball, later: Press) -> Press:
  Press{+rest, +status, +ox, +oy} = later
  Bool.pick(Press, U32.is_eq(status, 0), press.here(mx, my, ball, rest), Press{Con{ball, rest}, status, ox, oy})

def press(balls: +List<Ball>, +mx: F32, +my: F32, +ox: F32, +oy: F32) -> Press:
  match balls:
    case Nil{}: Press{Nil{}, 0, ox, oy}
    case Con{+ball, rest}: press.before(mx, my, ball, press(rest, mx, my, ox, oy))

def released(balls: +List<Ball>) -> +List<Ball>:
  match balls:
    case Nil{}: Nil{}
    case Con{Ball{+x, +y, +sx, +sy, +px, +py, +radius, +color, _}, rest}: Con{Ball{x, y, sx, sy, px, py, radius, color, False{}}, released(rest)}

def channel(r: J.Random.State & F32) -> J.Random.State & U32:
  (rng, +v) = r
  (rng, F32.to_u32(v))

def created.blue(+mx: F32, +my: F32, +sx: F32, +sy: F32, +radius: F32, +red: U32, +green: U32, r: J.Random.State & U32) -> J.Random.State & Ball:
  (rng, +blue) = r
  (rng, Ball{mx, my, sx, sy, 0.0, 0.0, radius, J.Color.rgba(red, green, blue, 255), False{}})

def created.green(+mx: F32, +my: F32, +sx: F32, +sy: F32, +radius: F32, +red: U32, r: J.Random.State & U32) -> J.Random.State & Ball:
  (rng, +green) = r
  created.blue(mx, my, sx, sy, radius, red, green, channel(J.Random.value(rng, 0.0, 255.0)))

def created.red(+mx: F32, +my: F32, +sx: F32, +sy: F32, +radius: F32, r: J.Random.State & U32) -> J.Random.State & Ball:
  (rng, +red) = r
  created.green(mx, my, sx, sy, radius, red, channel(J.Random.value(rng, 0.0, 255.0)))

def created.radius(+mx: F32, +my: F32, +sx: F32, +sy: F32, r: J.Random.State & F32) -> J.Random.State & Ball:
  (rng, +extra) = r
  created.red(mx, my, sx, sy, (20.0 + extra : F32), channel(J.Random.value(rng, 0.0, 255.0)))

def created.sy(+mx: F32, +my: F32, +sx: F32, r: J.Random.State & F32) -> J.Random.State & Ball:
  (rng, +sy) = r
  created.radius(mx, my, sx, sy, J.Random.value(rng, 0.0, 30.0))

def created.sx(+mx: F32, +my: F32, r: J.Random.State & F32) -> J.Random.State & Ball:
  (rng, +sx) = r
  created.sy(mx, my, sx, J.Random.value(rng, F32.neg(300.0), 300.0))

# A new ball at the mouse: speed.x, speed.y, the radius, then the color's r, g, b.
def created(rng: J.Random.State, +mx: F32, +my: F32) -> J.Random.State & Ball:
  created.sx(mx, my, J.Random.value(rng, F32.neg(300.0), 300.0))

def shaken.y(+ball: Ball, +sx: F32, r: J.Random.State & F32) -> J.Random.State & Ball:
  Ball{+x, +y, _, _, +px, +py, +radius, +color, +grabbed} = ball
  (rng, +sy) = r
  (rng, Ball{x, y, sx, sy, px, py, radius, color, grabbed})

def shaken.x(+ball: Ball, r: J.Random.State & F32) -> J.Random.State & Ball:
  (rng, +sx) = r
  shaken.y(ball, sx, J.Random.value(rng, F32.neg(2000.0), 2000.0))

def shaken.one(rng: J.Random.State, +ball: Ball) -> J.Random.State & Ball:
  Ball{_, _, _, _, _, _, _, _, +grabbed} = ball
  match grabbed:
    case True{}: (rng, ball)
    case False{}: shaken.x(ball, J.Random.value(rng, F32.neg(2000.0), 2000.0))

def shaken.kept(+done: +List<Ball>, r: J.Random.State & Ball) -> J.Random.State & +List<Ball>:
  (rng, +ball) = r
  (rng, List.append(&2, Ball, done, [ball]))

def shaken.step(+ball: Ball, r: J.Random.State & +List<Ball>) -> J.Random.State & +List<Ball>:
  (rng, +done) = r
  shaken.kept(done, shaken.one(rng, ball))

# Every ball that is not grabbed gets a random speed, in order.
def shaken(balls: +List<Ball>, r: J.Random.State & +List<Ball>) -> J.Random.State & +List<Ball>:
  match balls:
    case Nil{}: r
    case Con{+ball, rest}: shaken(rest, shaken.step(ball, r))

# One axis of a free ball: position += speed*delta, then the far and the near
# wall (the position on the wall, the speed reversed and damped).
def axis(+position: F32, +speed: F32, +radius: F32, +limit: F32, +delta: F32) -> F32 & F32:
  +moved = (position + speed * delta : F32)
  +back = (F32.neg(speed) * elasticity() : F32)
  +far = ((moved + radius : F32) >= limit : F32)
  +near = ((moved - radius : F32) <= 0.0 : F32)
  (Bool.pick(F32, far, (limit - radius : F32), Bool.pick(F32, near, radius, moved)), Bool.pick(F32, far || near, back, speed))

def free.done(+px: F32, +py: F32, +radius: F32, +color: U32, +gravity: F32, horizontal: F32 & F32, vertical: F32 & F32) -> Ball:
  (+x, +sx) = horizontal
  (+y, +sy) = vertical
  Ball{x, y, (sx * friction() : F32), (sy * friction() + gravity : F32), px, py, radius, color, False{}}

# A grabbed ball follows the mouse; its speed is the move over the frame time.
def held(+mx: F32, +my: F32, +ox: F32, +oy: F32, +delta: F32, +px: F32, +py: F32, +radius: F32, +color: U32) -> Ball:
  +x = (mx - ox : F32)
  +y = (my - oy : F32)
  Ball{x, y, ((x - px : F32) / delta : F32), ((y - py : F32) / delta : F32), x, y, radius, color, True{}}

def stepped(+ball: Ball, +mx: F32, +my: F32, +ox: F32, +oy: F32, +delta: F32, +gravity: F32) -> Ball:
  Ball{+x, +y, +sx, +sy, +px, +py, +radius, +color, +grabbed} = ball
  match grabbed:
    case True{}: held(mx, my, ox, oy, delta, px, py, radius, color)
    case False{}: free.done(px, py, radius, color, gravity, axis(x, sx, radius, 800.0, delta), axis(y, sy, radius, 450.0, delta))

def all.stepped(balls: +List<Ball>, +mx: F32, +my: F32, +ox: F32, +oy: F32, +delta: F32, +gravity: F32) -> +List<Ball>:
  match balls:
    case Nil{}: Nil{}
    case Con{+ball, rest}: Con{stepped(ball, mx, my, ox, oy, delta, gravity), all.stepped(rest, mx, my, ox, oy, delta, gravity)}

def update.moved(+core: J.Core, +count: U32, +ox: F32, +oy: F32, +gravity: F32, +refused: Bool, +mx: F32, +my: F32, r: J.Random.State & +List<Ball>) -> J.Core & State:
  (rng, +balls) = r
  +g = (gravity + J.Input.get_mouse_wheel_move(core) * 5.0 : F32)
  (core, State{rng, all.stepped(balls, mx, my, ox, oy, J.Core.get_frame_time(core), g), count, ox, oy, g, refused})

def update.shaken(r: J.Random.State & +List<Ball>) -> J.Random.State & +List<Ball>:
  (rng, +balls) = r
  shaken(balls, (rng, Nil{}))

def update.shaking(shake: Bool, r: J.Random.State & +List<Ball>) -> J.Random.State & +List<Ball>:
  match shake:
    case False{}: r
    case True{}: update.shaken(r)

def update.appended(+balls: +List<Ball>, r: J.Random.State & Ball) -> J.Random.State & +List<Ball>:
  (rng, +ball) = r
  (rng, List.append(&2, Ball, balls, [ball]))

def update.creating(create: Bool, rng: J.Random.State, +balls: +List<Ball>, +mx: F32, +my: F32) -> J.Random.State & +List<Ball>:
  match create:
    case False{}: (rng, balls)
    case True{}: update.appended(balls, created(rng, mx, my))

def update.pressed(+core: J.Core, rng: J.Random.State, +count: U32, +gravity: F32, +refused: Bool, +mx: F32, +my: F32, result: Press) -> J.Core & State:
  Press{+pressed, +status, +ox, +oy} = result
  +left = J.MouseButton.MOUSE_BUTTON_LEFT()
  +right = J.MouseButton.MOUSE_BUTTON_RIGHT()
  +balls = Bool.pick(+List<Ball>, J.Input.is_mouse_button_released(core, left), released(pressed), pressed)
  +wanted = J.Input.is_mouse_button_pressed(core, right) || (J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT_CONTROL()) && J.Input.is_mouse_button_down(core, right))
  +create = wanted && (count < 5000 : U32)
  update.moved(core, (count + Bool.to_u32(create) : U32), ox, oy, gravity, refused || U32.is_eq(status, 2), mx, my,
    update.shaking(J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_MIDDLE()), update.creating(create, rng, balls, mx, my)))

def update.at(+core: J.Core, state: State, +mouse: M.Vector2) -> J.Core & State:
  State{rng, +balls, +count, +ox, +oy, +gravity, +refused} = state
  M.Vector2{+mx, +my} = mouse
  +down = J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  update.pressed(core, rng, count, gravity, refused, mx, my, Bool.pick(Press, down, press(balls, mx, my, ox, oy), Press{balls, 0, ox, oy}))

def update(+core: J.Core, state: State) -> J.Core & State:
  update.at(core, state, J.Input.get_mouse_position(core))

def draw.balls(+libm: M.Libm, balls: +List<Ball>, frame: J.Frame) -> J.Frame:
  match balls:
    case Nil{}: frame
    case Con{Ball{+x, +y, _, _, _, _, +radius, +color, _}, rest}:
      draw.balls(libm, rest, J.Draw.circle_lines_v_for(libm, J.Draw.circle_v_for(libm, frame, M.Vector2{x, y}, radius, color), M.Vector2{x, y}, radius, J.Color.BLACK()))

def draw.line(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, J.Color.BLACK())

def draw.shown(refused: Bool, frame: J.Frame) -> J.Frame:
  match refused:
    case True{}: J.Frame.refuse(frame)
    case False{}: frame

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +balls, +count, +ox, +oy, +gravity, +refused} = state
  f1 = draw.balls(libm, balls, J.Frame.clear_background(draw.shown(refused, frame), J.Color.RAYWHITE()))
  f2 = J.Draw.text(f1, "grab a ball by pressing with the mouse and throw it by releasing", 10.0, 10.0, 10.0, J.Color.DARKGRAY())
  f3 = J.Draw.text(f2, "right click to create new balls (keep left control pressed to create a lot)", 10.0, 30.0, 10.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, "use mouse wheel to change gravity", 10.0, 50.0, 10.0, J.Color.DARKGRAY())
  f5 = J.Draw.text(f4, "middle click to shake", 10.0, 70.0, 10.0, J.Color.DARKGRAY())
  f6 = draw.line(J.Text.format("BALL COUNT: %d", [J.TextInt{count}]), 380.0, f5)
  (core, (State{rng, balls, count, ox, oy, gravity, refused}, draw.line(J.Text.format("GRAVITY: %.2f", [J.TextFloat{gravity}]), 410.0, f6)))

# The main loop's body; libm is the sinf/cosf profile of the circles.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450) and SetRandomSeed(seed): one blue ball of radius
# 40 at the center moving at (200, 200), gravity 100, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Random.seed(seed), [Ball{400.0, 225.0, 200.0, 200.0, 0.0, 0.0, 40.0, J.Color.BLUE(), False{}}], 1, 0.0, 0.0, 100.0, False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - ball physics", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
