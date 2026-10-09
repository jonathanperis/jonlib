# raylib [textures] example - sprite animation, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_sprite_animation.c
# (zlib/libpng, Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# Right/Left change the animation speed. Loads resources/scarfy.png from
# raylib's examples/textures (not copied into this repository): run it from
# that directory, or pass `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The texture (None when it did not load) and its size, frameRec.x, the
# current sprite frame, the frame counter and the speed (C ints).
type State is Type:
  State{scarfy: Maybe<J.Texture>, w: U32, h: U32, x: F32, current: U32, counter: U32, speed: U32}

# Every 60/framesSpeed frames the next of the 6 sprite frames:
# frameRec.x = (float)currentFrame*(float)scarfy.width/6.
def advance(+due: Bool, +w: U32, +x: F32, +current: U32) -> F32 & U32:
  +next = Bool.pick(U32, (current >= 5 : U32), 0, (current + 1 : U32))
  Bool.pick(F32 & U32, due, (((U32.to_f32(next) * U32.to_f32(w) : F32) / 6.0 : F32), next), (x, current))

# Right/Left change framesSpeed, clamped to MIN_FRAME_SPEED 1..MAX_FRAME_SPEED 15
# (it starts at 8 and moves by one, so it never leaves 0..16).
def speed(+core: J.Core, +speed: U32) -> U32:
  +changed = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()), (speed + 1 : U32),
    Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()), (speed - 1 : U32), speed))
  Bool.pick(U32, (changed > 15 : U32), 15, Bool.pick(U32, (changed < 1 : U32), 1, changed))

def update.advanced(+core: J.Core, scarfy: Maybe<J.Texture>, +w: U32, +h: U32, +due: Bool, +counter: U32, +framespeed: U32, moved: F32 & U32) -> J.Core & State:
  (+x, +current) = moved
  (core, State{scarfy, w, h, x, current, Bool.pick(U32, due, 0, counter), speed(core, framespeed)})

def update(+core: J.Core, state: State) -> J.Core & State:
  State{scarfy, +w, +h, +x, +current, +counter, +framespeed} = state
  +counted = (counter + 1 : U32)
  +due = (counted >= (60 / framespeed) : U32)
  update.advanced(core, scarfy, w, h, due, counted, framespeed, advance(due, w, x, current))

def drawn(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

def draw.sheet(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: drawn(J.Draw.texture(frame, t, 15.0, 40.0, J.Color.WHITE()))

def draw.sprite(frame: J.Frame, texture: Maybe<J.Texture>, +rec: J.Rectangle) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: drawn(J.Draw.texture_rec(frame, t, rec, M.Vector2{350.0, 280.0}, J.Color.WHITE()))

def draw.filled(filled: Bool, +x: F32, frame: J.Frame) -> J.Frame:
  match filled:
    case True{}: J.Draw.rectangle(frame, x, 205.0, 20.0, 20.0, J.Color.RED())
    case False{}: frame

# for (i = 0; i < MAX_FRAME_SPEED; i++): the filled speed boxes and their outlines.
def draw.boxes(n: Nat, +i: U32, +speed: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+k:
      +x = U32.to_f32((250 + 21 * i : U32))
      draw.boxes(k, (i + 1 : U32), speed, J.Draw.rectangle_lines(draw.filled((i < speed : U32), x, frame), x, 205.0, 20.0, 20.0, J.Color.MAROON()))

def text.of(text: Maybe<String>) -> String:
  match text:
    case None{}: ""
    case Some{t}: t

def draw.end(+core: J.Core, +w: U32, +h: U32, +x: F32, +current: U32, +counter: U32, +speed: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{texture, w, h, x, current, counter, speed}, J.Draw.text(frame, "(c) Scarfy sprite by Eiden Marsal", 600.0, 430.0, 10.0, J.Color.GRAY())))

def draw.rest(+core: J.Core, +w: U32, +h: U32, +x: F32, +current: U32, +counter: U32, +speed: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  +fw = (U32.to_f32(w) / 6.0 : F32)
  f1 = J.Draw.rectangle_lines(frame, 15.0, 40.0, U32.to_f32(w), U32.to_f32(h), J.Color.LIME())
  f2 = J.Draw.rectangle_lines(f1, (15.0 + F32.trunc(x) : F32), 40.0, F32.trunc(fw), U32.to_f32(h), J.Color.RED())
  f3 = J.Draw.text(f2, "FRAME SPEED: ", 165.0, 210.0, 10.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, text.of(J.Text.format("%02i FPS", [J.TextInt{speed}])), 575.0, 210.0, 10.0, J.Color.DARKGRAY())
  f5 = J.Draw.text(f4, "PRESS RIGHT/LEFT KEYS to CHANGE SPEED!", 290.0, 240.0, 10.0, J.Color.DARKGRAY())
  f6 = draw.boxes(15n, 0, speed, f5)
  draw.end(core, w, h, x, current, counter, speed, draw.sprite(f6, texture, J.Rectangle{x, 0.0, fw, U32.to_f32(h)}))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{scarfy, +w, +h, +x, +current, +counter, +speed} = state
  draw.rest(core, w, h, x, current, counter, speed, draw.sheet(J.Frame.clear_background(frame, J.Color.RAYWHITE()), scarfy))

# The main loop's body; libm is the sinf/cosf profile (unused: no rotation).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.sized(+core: J.Core, frame: J.Frame, texture: J.Texture) -> J.Core & (J.Frame & State):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  (J.Core.set_target_fps(core, 60), (frame, State{Some{J.Texture{id, w, h, format, linear, alpha, texels}}, w, h, 0.0, 0, 0, 8}))

def setup.texture(+core: J.Core, frame: J.Frame, texture: Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  match texture:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, 0, 0, 0.0, 0, 0, 8}))
    case Some{t}: setup.sized(core, frame, t)

def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  setup.texture(core, frame, texture)

# After InitWindow(800, 450): LoadTexture(dir ++ "resources/scarfy.png"),
# frameRec (0, 0, width/6.0f, height), framesSpeed 8, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/scarfy.png"),
    r => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, r)))

# "--resources DIR/" (default: the working directory) and "--frames N".
def options(args: List<String>, +mode: U32, dir: String, +frames: U32) -> String & U32:
  match args:
    case Nil{}: (dir, frames)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames)
        case 2: options(rest, 0, dir, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--resources"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, 0)), dir, frames)

def run.with(parsed: String & U32) -> IO(Unit):
  (dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - sprite animation", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
