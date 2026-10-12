# raylib [core] example - screen recording, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_screen_recording.c (zlib/libpng,
# Copyright (c) 2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A circle rides a sine wave. Ctrl+R starts a recording and ends it: while it
# runs, every sixth frame the screen goes to the GIF encoder the example
# brings with it (msf_gif.h; src/msf_gif.bend here, docs/GIF-ENCODER.md), and
# the end writes screenrecording.gif. The file is written inside the loop, so
# the program is a J.Effects one (docs/DRIVER.md).
#
# The example reads the screen before BeginDrawing: what it records is the
# frame drawn before, which is the frame the update is handed. It saves the
# file in GetApplicationDirectory(), which Base cannot ask for: the directory
# is a setup argument (`--directory <dir>`, the working directory by
# default), and the file is `<dir>/screenrecording.gif` as TextFormat makes
# it. A frame is refused where a sine has no answer under the libm profile
# or the screen cannot be read; msf_gif_frame's delay is the example's
# (int)((1.0f/60.0f)*5)/10, which is 0. With the AppleLibm profile the sines
# have no answer (docs/MATH.md) and every frame is refused.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../src/msf_gif.bend as G

# valid: no refusal so far. dir is the application directory; recording and
# counter are gifRecording and gifFrameCounter; gif is gifState (an empty
# recording before the first one begins). x, y and time are circlePosition
# and timeCounter; points are sinePoints, x and y in turn.
type State is Data:
  State{valid: Bool, dir: String, recording: Bool, counter: U32, gif: G.Gif, x: F32, y: F32, time: F32, points: +List<F32>}

# screenHeight/2.0f + 150*sinf(angle); None where the profile has no sine.
def wave(sine: Maybe<F32>) -> Maybe<F32>:
  match sine:
    case None{}: None{}
    case Some{+s}: Some{(225.0 + (150.0 * s) : F32)}

# The circle after a frame: x moves by GetScreenWidth()/180.0f and y follows
# the sine of (2*PI/1.5f)*timeCounter; past the right side all three start
# again, whatever the sine was.
type Moved is Data:
  Moved{valid: Bool, x: F32, y: F32, time: F32}

def circle.at(y: Maybe<F32>, +wrapped: Bool, +x: F32, +time: F32) -> Moved:
  match y:
    case None{}: Bool.pick(Moved, wrapped, Moved{True{}, 0.0, 225.0, 0.0}, Moved{False{}, x, 225.0, time})
    case Some{+v}: Bool.pick(Moved, wrapped, Moved{True{}, 0.0, 225.0, 0.0}, Moved{True{}, x, v, time})

def circle.moved(+libm: M.Libm, +x: F32, +time: F32) -> Moved:
  circle.at(wave(M.Libm.sin(libm, (((2.0 * M.Math.PI()) / 1.5) * time : F32))), (x > 800.0 : F32), x, time)

def words(colors: List<U32>, acc: +List<U32>) -> +List<U32>:
  match colors:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+c, rest}: words(rest, Con{c, acc})

# msf_gif_frame(&gifState, imScreen.data, 0, 16, imScreen.width*4).
def shot.colors(+gif: G.Gif, colors: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> Maybe<G.Gif>:
  match colors:
    case Fail{_}: None{}
    case Done{list}: G.frame(gif, words(list, Nil{}), 0, 16)

def shot.image(+gif: G.Gif, image: Maybe<J.Surface>) -> Maybe<G.Gif>:
  match image:
    case None{}: None{}
    case Some{surface}: shot.colors(gif, J.Surface.colors(surface))

# LoadImageFromScreen and the frame it gives the recording: None where the
# screen cannot be read or the encoder refuses the frame.
def shot(+gif: G.Gif, r: J.Frame & Maybe<J.Surface>) -> J.Frame & Maybe<G.Gif>:
  (frame, image) = r
  (frame, shot.image(gif, image))

def update.done(+core: J.Core, +valid: Bool, +dir: String, +recording: Bool, +counter: U32, +gif: G.Gif, +x: F32, +y: F32, +time: F32, +points: +List<F32>, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  IO.pure(J.Core & (State & J.Frame), (core, (State{valid, dir, recording, counter, gif, x, y, time, points}, frame)))

# What the encoder answered: the recording goes on with it, or the frame is
# refused.
def update.answered(answer: Maybe<G.Gif>, +core: J.Core, +valid: Bool, +dir: String, +counter: U32, +gif: G.Gif, +x: F32, +y: F32, +time: F32, +points: +List<F32>, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match answer:
    case None{}: update.done(core, False{}, dir, True{}, counter, gif, x, y, time, points, frame)
    case Some{+g}: update.done(core, valid, dir, True{}, counter, g, x, y, time, points, frame)

def update.shot(+core: J.Core, +valid: Bool, +dir: String, +gif: G.Gif, +x: F32, +y: F32, +time: F32, +points: +List<F32>, r: J.Frame & Maybe<G.Gif>) -> IO(J.Core & (State & J.Frame)):
  (frame, answer) = r
  update.answered(answer, core, valid, dir, 0, gif, x, y, time, points, frame)

# if (gifRecording): the counter goes up and, above GIF_RECORD_FRAMERATE,
# the screen is recorded and the counter starts again. kind: 0 not
# recording, 1 counting, 2 recording the screen.
def update.recorded(kind: U32, +core: J.Core, +valid: Bool, +dir: String, +counter: U32, +gif: G.Gif, +x: F32, +y: F32, +time: F32, +points: +List<F32>, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match kind:
    case 0: update.done(core, valid, dir, False{}, counter, gif, x, y, time, points, frame)
    case 1: update.done(core, valid, dir, True{}, (counter + 1 : U32), gif, x, y, time, points, frame)
    case _: update.shot(core, valid, dir, gif, x, y, time, points, shot(gif, J.Frame.load_image_from_screen(frame)))

# Ctrl+R while recording: msf_gif_end, and SaveFileData of its bytes to
# TextFormat("%s/screenrecording.gif", GetApplicationDirectory()) (its
# answer is not used).
def update.saved(+core: J.Core, +valid: Bool, +dir: String, +counter: U32, +gif: G.Gif, +x: F32, +y: F32, +time: F32, +points: +List<F32>, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, J.Core & (State & J.Frame), J.Files.save_data(dir ++ "/screenrecording.gif", G.finish(gif)),
    written => update.recorded(0, core, valid, dir, counter, gif, x, y, time, points, frame))

# Ctrl+R while not recording: gifFrameCounter = 0 and
# msf_gif_begin(GetRenderWidth(), GetRenderHeight()); the counter is 1 by
# the end of the pass.
def update.begun(answer: Maybe<G.Gif>, +core: J.Core, +valid: Bool, +dir: String, +gif: G.Gif, +x: F32, +y: F32, +time: F32, +points: +List<F32>, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  update.answered(answer, core, valid, dir, 1, gif, x, y, time, points, frame)

# kind: 0 no key, 1 Ctrl+R ends the recording, 2 Ctrl+R begins one, 3 a
# refusal before (nothing more is recorded or written).
def update.keyed(kind: U32, +core: J.Core, +valid: Bool, +dir: String, +recording: Bool, +counter: U32, +gif: G.Gif, +x: F32, +y: F32, +time: F32, +points: +List<F32>, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match kind:
    case 0: update.recorded(Bool.pick(U32, recording, Bool.pick(U32, (counter >= 5 : U32), 2, 1), 0), core, valid, dir, counter, gif, x, y, time, points, frame)
    case 1: update.saved(core, valid, dir, counter, gif, x, y, time, points, frame)
    case 3: update.done(core, False{}, dir, recording, counter, gif, x, y, time, points, frame)
    case _: update.begun(G.begin(J.Core.get_render_width(core), J.Core.get_render_height(core)), core, valid, dir, gif, x, y, time, points, frame)

def update.moved(+core: J.Core, +valid: Bool, +dir: String, +recording: Bool, +counter: U32, +gif: G.Gif, +points: +List<F32>, frame: J.Frame, moved: Moved) -> IO(J.Core & (State & J.Frame)):
  Moved{+fine, +x, +y, +time} = moved
  +pressed = J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT_CONTROL()) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R())
  update.keyed(Bool.pick(U32, valid && fine, Bool.pick(U32, pressed, Bool.pick(U32, recording, 1, 2), 0), 3), core, valid && fine, dir, recording, counter, gif, x, y, time, points, frame)

def update(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  State{+valid, +dir, +recording, +counter, +gif, +x, _, +time, +points} = state
  update.moved(core, valid, dir, recording, counter, gif, points, frame, circle.moved(libm, (x + (800.0 / 180.0) : F32), (time + J.Core.get_frame_time(core) : F32)))

# DrawLineV(sinePoints[i], sinePoints[i + 1], MAROON) and
# DrawCircleV(sinePoints[i], 3, MAROON) for the first 255 points: (x, y) is
# the point at hand.
def draw.wave(points: +List<F32>, +libm: M.Libm, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match points:
    case Con{+u, Con{+v, +rest}}:
      draw.wave(rest, libm, u, v, J.Draw.circle_v_for(libm, J.Draw.line_v(frame, M.Vector2{x, y}, M.Vector2{u, v}, J.Color.MAROON()), M.Vector2{x, y}, 3.0, J.Color.MAROON()))
    case _: frame

def draw.points(points: +List<F32>, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match points:
    case Con{+x, Con{+y, +rest}}: draw.wave(rest, libm, x, y, frame)
    case _: frame

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +state: State, +x: F32, +y: F32, +points: +List<F32>, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (state, J.Frame.refuse(frame)))
    case True{}:
      draw.fps(state, J.Draw.circle_v_for(libm, draw.points(points, libm, J.Frame.clear_background(frame, J.Color.RAYWHITE())), M.Vector2{x, y}, 30.0, J.Color.RED()),
        J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _, +x, +y, _, +points} = state
  draw.valid(valid, libm, core, state, x, y, points, frame)

# Nothing follows EndDrawing in the loop.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Effects{core => state => frame => update(libm, core, state, frame), core => state => frame => draw(libm, core, state, frame),
    core => state => frame => IO.pure(J.Core & (State & J.Frame), (core, (state, frame)))}

# sinePoints[i] = { i*GetScreenWidth()/180.0f, screenHeight/2.0f +
# 150*sinf((2*PI/1.5f)*(1.0f/60.0f)*(float)i) } for the 256 points, the
# last first; `fine` is whether every sine had an answer.
type Points is Data:
  Points{fine: Bool, list: +List<F32>}

def sines.with(y: Maybe<F32>, +i: U32, +fine: Bool, +acc: +List<F32>) -> Points:
  match y:
    case None{}: Points{False{}, acc}
    case Some{+v}: Points{fine, Con{(U32.to_f32((i * 800 : U32)) / 180.0 : F32), Con{v, acc}}}

def Points.fine(points: Points) -> Bool:
  Points{fine, _} = points
  fine

def Points.list(points: Points) -> +List<F32>:
  Points{_, list} = points
  list

def sines(n: Nat, +libm: M.Libm, +i: U32, +made: Points) -> Points:
  match n:
    case 0n: made
    case 1n+k:
      sines(k, libm, (i - 1 : U32), sines.with(wave(M.Libm.sin(libm, ((((2.0 * M.Math.PI()) / 1.5) * (1.0 / 60.0)) * U32.to_f32(i) : F32))), i, Points.fine(made), Points.list(made)))

def setup.made(+dir: String, +core: J.Core, frame: J.Frame, +made: Points) -> IO(J.Core & (J.Frame & State)):
  IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, State{Points.fine(made), dir, False{}, 0, G.Gif{0, 0, Nil{}, 0, 0, Nil{}}, 0.0, 225.0, 0.0, Points.list(made)})))

# After InitWindow(800, 450): nothing recorded, the circle at
# (0, screenHeight/2), the sine's points, SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  setup.made(dir, core, frame, sines(256n, libm, 255, Points{True{}, Nil{}}))

# "--directory DIR" (default: the working directory) and "--frames N".
def options(args: List<String>, +mode: U32, dir: String, +frames: U32) -> String & U32:
  match args:
    case Nil{}: (dir, frames)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames)
        case 2: options(rest, 0, dir, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--directory"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, 0)), dir, frames)

def run.with(parsed: String & U32) -> IO(Unit):
  (dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - screen recording", 800, 450, limit,
    core => frame => setup(M.Glibc239Libm{}, dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, ".", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
