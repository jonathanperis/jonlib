# raylib [audio] example - module playing, ported to Jonlib.
# Adapted from raylib 6.0 examples/audio/audio_module_playing.c (zlib/libpng,
# Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# resources/mini1111.xm plays once as a music stream while 64 circles fade
# in and out: space restarts it, P pauses and resumes it, down and up
# change its speed, and a bar shows how much of it was played. The module
# is played by src/xm_player.bend and src/xm_mixer.bend (jar_xm's player
# and mixer), whose sines and powers of two are the libm profile's.
#
# raylib's device reads the stream on a thread of its own. Here the device
# has a clock (J.AudioClock, docs/AUDIO.md): every pass of the loop first
# makes the callbacks that were due by the frame's time, one each 10 ms, and
# then updates the music, as the example calls UpdateMusicStream first. The
# samples go nowhere: there is no host device. raylib seeds GetRandomValue
# from time(NULL) in InitWindow; here the seed is a setup argument. Loads
# resources/mini1111.xm from raylib's examples/audio directory: run from
# that directory, or pass `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# circles[i]: position, radius, alpha, speed, color.
type Circle is Data:
  Circle{x: F32, y: F32, radius: F32, alpha: F32, speed: F32, color: U32}

# valid: the music was loaded and every callback was answered. `circles`
# are in the order the loops go through them, the last of the array first.
# `played` is timePlayed, None where it has no answer.
type State is Type:
  State{valid: Bool, rng: J.Random.State, circles: +List<Circle>, audio: J.AudioDevice, clock: J.AudioClock, music: J.Music, pause: Bool, pitch: F32, played: +Maybe<F32>}

# colors[index]
def color.of(index: U32) -> U32:
  match index:
    case 0: J.Color.ORANGE()
    case 1: J.Color.RED()
    case 2: J.Color.GOLD()
    case 3: J.Color.LIME()
    case 4: J.Color.BLUE()
    case 5: J.Color.VIOLET()
    case 6: J.Color.BROWN()
    case 7: J.Color.LIGHTGRAY()
    case 8: J.Color.PINK()
    case 9: J.Color.YELLOW()
    case 10: J.Color.GREEN()
    case 11: J.Color.SKYBLUE()
    case 12: J.Color.PURPLE()
    case _: J.Color.BEIGE()

# A circle's radius and place: (float)GetRandomValue(10, 40), then
# GetRandomValue((int)radius, (int)(screenWidth - radius)) and the same by
# the height.
type Placed is Type:
  Placed{rng: J.Random.State, radius: F32, x: F32, y: F32}

def place.y(+radius: F32, +x: F32, drawn: J.Random.State & F32) -> Placed:
  (rng, +y) = drawn
  Placed{rng, radius, x, y}

def place.x(+radius: F32, drawn: J.Random.State & F32) -> Placed:
  (rng, +x) = drawn
  place.y(radius, x, J.Random.value(rng, radius, (450.0 - radius : F32)))

def place.radius(drawn: J.Random.State & F32) -> Placed:
  (rng, +radius) = drawn
  place.x(radius, J.Random.value(rng, radius, (800.0 - radius : F32)))

def place(rng: J.Random.State) -> Placed:
  place.radius(J.Random.value(rng, 10.0, 40.0))

# The setup's circle: after its place, speed = (float)GetRandomValue(1, 100)/2000.0f
# and then color = colors[GetRandomValue(0, 13)].
def circle.first.colored(+radius: F32, +x: F32, +y: F32, +speed: F32, drawn: J.Random.State & F32) -> J.Random.State & Circle:
  (rng, +index) = drawn
  (rng, Circle{x, y, radius, 0.0, speed, color.of(F32.to_u32(index))})

def circle.first.sped(+radius: F32, +x: F32, +y: F32, drawn: J.Random.State & F32) -> J.Random.State & Circle:
  (rng, +value) = drawn
  circle.first.colored(radius, x, y, (value / 2000.0 : F32), J.Random.value(rng, 0.0, 13.0))

def circle.first(placed: Placed) -> J.Random.State & Circle:
  Placed{rng, +radius, +x, +y} = placed
  circle.first.sped(radius, x, y, J.Random.value(rng, 1.0, 100.0))

# A circle that faded out: after its place, the color and then the speed.
def circle.again.sped(+radius: F32, +x: F32, +y: F32, +color: U32, drawn: J.Random.State & F32) -> J.Random.State & Circle:
  (rng, +value) = drawn
  (rng, Circle{x, y, radius, 0.0, (value / 2000.0 : F32), color})

def circle.again.colored(+radius: F32, +x: F32, +y: F32, drawn: J.Random.State & F32) -> J.Random.State & Circle:
  (rng, +index) = drawn
  circle.again.sped(radius, x, y, color.of(F32.to_u32(index)), J.Random.value(rng, 1.0, 100.0))

def circle.again(placed: Placed) -> J.Random.State & Circle:
  Placed{rng, +radius, +x, +y} = placed
  circle.again.colored(radius, x, y, J.Random.value(rng, 0.0, 13.0))

# alpha += speed; radius += speed*10.0f; if (alpha > 1.0f) speed *= -1;
def circle.moved(circle: Circle) -> Circle:
  Circle{x, y, +radius, +alpha, +speed, color} = circle
  +risen = (alpha + speed : F32)
  Circle{x, y, (radius + (speed * 10.0) : F32), risen, Bool.pick(F32, (risen > 1.0 : F32), F32.neg(speed), speed), color}

def circle.alpha(circle: Circle) -> F32:
  Circle{_, _, _, alpha, _, _} = circle
  alpha

# if (alpha <= 0.0f): the circle is made again.
def circle.settled(out: Bool, rng: J.Random.State, +circle: Circle) -> J.Random.State & Circle:
  match out:
    case False{}: (rng, circle)
    case True{}: circle.again(place(rng))

def circle.step(rng: J.Random.State, +circle: Circle) -> J.Random.State & Circle:
  +moved = circle.moved(circle)
  circle.settled((circle.alpha(moved) <= 0.0 : F32), rng, moved)

def circles.cons(+rest: +List<Circle>, r: J.Random.State & Circle) -> J.Random.State & +List<Circle>:
  (rng, +circle) = r
  (rng, Con{circle, rest})

def circles.made(r: J.Random.State & +List<Circle>) -> J.Random.State & +List<Circle>:
  (rng, +acc) = r
  circles.cons(acc, circle.first(place(rng)))

def circles.reversed(r: J.Random.State & +List<Circle>) -> J.Random.State & +List<Circle>:
  (rng, +acc) = r
  (rng, List.reverse(&2, Circle, acc))

# The setup's loop: MAX_CIRCLES circles, from the last of the array.
def circles.initial(n: Nat, r: J.Random.State & +List<Circle>) -> J.Random.State & +List<Circle>:
  match n:
    case 0n: circles.reversed(r)
    case 1n+p: circles.initial(p, circles.made(r))

def circles.push(+circle: Circle, r: J.Random.State & +List<Circle>) -> J.Random.State & +List<Circle>:
  (rng, +acc) = r
  circles.cons(acc, circle.step(rng, circle))

# The animation's loop, in the same order.
def circles.step(circles: +List<Circle>, r: J.Random.State & +List<Circle>) -> J.Random.State & +List<Circle>:
  match circles:
    case Nil{}: circles.reversed(r)
    case Con{+circle, rest}: circles.step(rest, circles.push(circle, r))

# timePlayed = GetMusicTimePlayed(music)/GetMusicTimeLength(music)*(screenWidth - 40),
# where the bar's (int) of it is defined.
def played.ranged(fine: Bool, +bar: F32) -> +Maybe<F32>:
  match fine:
    case True{}: Some{bar}
    case False{}: None{}

def played.bar(+bar: F32) -> +Maybe<F32>:
  played.ranged((bar >= 0.0 : F32) && (bar < 2147483648.0 : F32), bar)

def played(time: Maybe<F32>, +length: F32) -> +Maybe<F32>:
  match time:
    case None{}: None{}
    case Some{t}: played.bar(((t / length) * 760.0 : F32))

# if (IsKeyPressed(KEY_SPACE)) { StopMusicStream(music); PlayMusicStream(music); pause = false; }
def restart.play(stopped: J.AudioDevice & J.Music) -> J.AudioDevice & J.Music:
  (+audio, +music) = stopped
  (J.Music.play(audio, music), music)

def restart(space: Bool, +audio: J.AudioDevice, +music: J.Music) -> J.AudioDevice & J.Music:
  match space:
    case False{}: (audio, music)
    case True{}: restart.play(J.Music.stop(audio, music))

# P turns `pause` and pauses or resumes the music.
def paused(pressed: Bool, +pause: Bool, +audio: J.AudioDevice, +music: J.Music) -> J.AudioDevice:
  match pressed:
    case False{}: audio
    case True{}: Bool.pick(J.AudioDevice, pause, J.Music.resume(audio, music), J.Music.pause(audio, music))

def update.moved(r: J.Random.State & +List<Circle>, +valid: Bool, +audio: J.AudioDevice, +clock: J.AudioClock, +music: J.Music, +pitch: F32, played: +Maybe<F32>) -> State:
  (rng, +circles) = r
  State{valid, rng, circles, audio, clock, music, False{}, pitch, played}

# The circles move unless the music is paused.
def update.circles(pause: Bool, rng: J.Random.State, +circles: +List<Circle>, +valid: Bool, +audio: J.AudioDevice, +clock: J.AudioClock, +music: J.Music, +pitch: F32, played: +Maybe<F32>) -> State:
  match pause:
    case True{}: State{valid, rng, circles, audio, clock, music, True{}, pitch, played}
    case False{}: update.moved(circles.step(circles, (rng, Nil{})), valid, audio, clock, music, pitch, played)

# The keys after the restart: P, then down or up (pitch by 0.01f),
# SetMusicPitch(music, pitch), then timePlayed and the circles.
def update.keys(restarted: J.AudioDevice & J.Music, +core: J.Core, +valid: Bool, rng: J.Random.State, +circles: +List<Circle>, +clock: J.AudioClock, +pause: Bool, +pitch: F32) -> State:
  (+audio, +music) = restarted
  +pressed = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_P())
  +down = J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN())
  +up = J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()) && Bool.not(down)
  +speed = Bool.pick(F32, down, (pitch - 0.01 : F32), Bool.pick(F32, up, (pitch + 0.01 : F32), pitch))
  +set = J.Music.set_pitch(paused(pressed, pause, audio, music), music, speed)
  update.circles((pressed && Bool.not(pause)) || (Bool.not(pressed) && pause), rng, circles, valid, set, clock, music, speed, played(J.Music.time_played(set, music), J.Music.time_length(music)))

# UpdateMusicStream(music), then the space key.
def update.music(updated: J.AudioDevice & J.Music, +core: J.Core, +valid: Bool, rng: J.Random.State, +circles: +List<Circle>, +clock: J.AudioClock, +pause: Bool, +pitch: F32) -> State:
  (+audio, +music) = updated
  +space = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE())
  update.keys(restart(space, audio, music), core, valid, rng, circles, clock, pause && Bool.not(space), pitch)

def update.clocked(step: J.AudioClock.Step, +core: J.Core, +valid: Bool, rng: J.Random.State, +circles: +List<Circle>, +music: J.Music, +pause: Bool, +pitch: F32) -> State:
  J.AudioStep{+clock, +audio, +fine} = step
  update.music(J.Music.update(audio, music), core, valid && fine, rng, circles, clock, pause, pitch)

# The device's callbacks up to this pass's time come first.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, rng, +circles, +audio, +clock, +music, +pause, +pitch, _} = state
  (core, update.clocked(J.AudioClock.advance(clock, audio, J.Core.get_time(core)), core, valid, rng, circles, music, pause, pitch))

# DrawCircleV(position, radius, Fade(color, alpha)), from the last circle.
def draw.circles(circles: +List<Circle>, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match circles:
    case Nil{}: frame
    case Con{Circle{+x, +y, +radius, +alpha, _, +color}, rest}:
      draw.circles(rest, libm, J.Draw.circle_v_for(libm, frame, M.Vector2{x, y}, radius, J.Color.with_alpha(color, alpha)))

def draw.speed(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 40.0, 130.0, 20.0, J.Color.MAROON())

# The frame: the circles, the time bar (its width C's (int) of timePlayed)
# and the help.
def draw.bars(+t: F32, +pitch: F32, +circles: +List<Circle>, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  f1 = draw.circles(circles, libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.rectangle(f1, 20.0, 418.0, 760.0, 12.0, J.Color.LIGHTGRAY())
  f3 = J.Draw.rectangle(f2, 20.0, 418.0, F32.trunc(t), 12.0, J.Color.MAROON())
  f4 = J.Draw.rectangle_lines(f3, 20.0, 418.0, 760.0, 12.0, J.Color.GRAY())
  f5 = J.Draw.rectangle_lines(J.Draw.rectangle(f4, 20.0, 20.0, 425.0, 145.0, J.Color.WHITE()), 20.0, 20.0, 425.0, 145.0, J.Color.GRAY())
  f6 = J.Draw.text(f5, "PRESS SPACE TO RESTART MUSIC", 40.0, 40.0, 20.0, J.Color.BLACK())
  f7 = J.Draw.text(f6, "PRESS P TO PAUSE/RESUME", 40.0, 70.0, 20.0, J.Color.BLACK())
  f8 = J.Draw.text(f7, "PRESS UP/DOWN TO CHANGE SPEED", 40.0, 100.0, 20.0, J.Color.BLACK())
  draw.speed(J.Text.format("SPEED: %f", [J.TextFloat{pitch}]), f8)

# A frame is refused where the music was not loaded, a callback was not
# answered or the time played has no answer.
def draw.frame(valid: Bool, played: +Maybe<F32>, +pitch: F32, +circles: +List<Circle>, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match valid played:
    case True{} Some{+t}: draw.bars(t, pitch, circles, libm, frame)
    case _ _: J.Frame.refuse(frame)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, rng, +circles, audio, clock, music, pause, +pitch, +played} = state
  (core, (State{valid, rng, circles, audio, clock, music, pause, pitch, played}, draw.frame(valid, played, pitch, circles, libm, frame)))

# The main loop's body; libm is the sinf/cosf profile of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# music.looping = false
def once(music: J.Music) -> J.Music:
  J.Music{stream, frames, _, kind, context} = music
  J.Music{stream, frames, False{}, kind, context}

# PlayMusicStream(music), pitch 1, timePlayed 0, not paused.
def setup.playing(+audio: J.AudioDevice, +music: J.Music, rng: J.Random.State, +circles: +List<Circle>, +now: M.Float64) -> State:
  State{True{}, rng, circles, J.Music.play(audio, music), J.AudioClock.at(now), music, False{}, 1.0, Some{0.0}}

def setup.loaded(r: J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, rng: J.Random.State, +circles: +List<Circle>, +now: M.Float64) -> State:
  match r:
    case Tuple{+audio, Fail{_}}: State{False{}, rng, circles, audio, J.AudioClock.at(now), J.Music.none(), False{}, 1.0, None{}}
    case Tuple{+audio, Done{music}}: setup.playing(audio, once(music), rng, circles, now)

def setup.made(made: J.Random.State & +List<Circle>, r: J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, +now: M.Float64) -> State:
  (rng, +circles) = made
  setup.loaded(r, rng, circles, now)

# After SetConfigFlags(FLAG_MSAA_4X_HINT), InitWindow(800, 450) and
# SetRandomSeed(seed): InitAudioDevice, the 64 circles,
# LoadMusicStream(dir ++ "resources/mini1111.xm") under the libm profile,
# the music played once, and SetTargetFPS(60).
def setup(+seed: U32, +libm: M.Libm, dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, J.Core & (J.Frame & State), J.Music.load_for(libm, J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/mini1111.xm"),
    r => IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, setup.made(circles.initial(64n, (J.Random.seed(seed), Nil{})), r, J.Core.get_time(core))))))

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
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [audio] example - module playing", 800, 450, limit,
    core => frame => setup(0, M.Glibc239Libm{}, dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
