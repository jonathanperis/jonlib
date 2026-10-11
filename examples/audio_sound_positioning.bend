# raylib [audio] example - sound positioning, ported to Jonlib.
# Adapted from raylib 6.0 examples/audio/audio_sound_positioning.c
# (zlib/libpng, Copyright (c) 2025 Le Juez Victor (@Bigfoot71)); see
# LICENSES/raylib.txt.
#
# A sphere circles the origin at the clock's angle and a sound follows it:
# its volume falls with the distance to the free camera (and behind it) and
# its pan follows the side it is on. The sound's buffer plays with that
# volume and pan, but nothing is mixed and no time passes for it
# (docs/AUDIO.md): it never ends, so it is played once. The perspective
# needs the libm profile's binary64 tan (docs/PERSPECTIVE.md), the sphere and
# UpdateCamera its sinf/cosf (docs/SINCOSF.md); a frame Jonlib refuses there
# refuses every later one. Loads resources/coin.wav from raylib's
# examples/audio (not copied into this repository): run it from that
# directory, or pass `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# The camera and spherePos (None once refused), the audio device and the
# sound.
type State is Data:
  State{camera: +Maybe<J.Camera3D>, audio: J.AudioDevice, sound: J.Sound, sphere: +Maybe<M.Vector3>}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{0.0, 5.0, 5.0}, M.Vector3.zero(), M.Vector3{0.0, 1.0, 0.0}, 60.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

# SetSoundPosition(listener, sound, position, 1.0f): the volume is
# 1/(1 + distance/maxDist) clamped to 0..1, reduced by (1 + dot*0.5) behind
# the listener, and the pan 0.5 + 0.5*dot(direction, right).
def positioned(+audio: J.AudioDevice, +sound: J.Sound, +camera: J.Camera3D, +position: M.Vector3) -> J.AudioDevice:
  J.Camera3D{+p, +t, +u, _, _} = camera
  +direction = M.Vector3.subtract(position, p)
  +near = M.Math.clamp((1.0 / (1.0 + (M.Vector3.length(direction) / 1.0)) : F32), 0.0, 1.0)
  +toward = M.Vector3.normalize(direction)
  +forward = M.Vector3.normalize(M.Vector3.subtract(t, p))
  +right = M.Vector3.normalize(M.Vector3.cross_product(u, forward))
  +facing = M.Vector3.dot_product(forward, toward)
  +volume = Bool.pick(F32, (facing < 0.0 : F32), (near * (1.0 + (facing * 0.5)) : F32), near)
  J.Sound.set_pan(J.Sound.set_volume(audio, sound, volume), sound, (0.5 + (0.5 * M.Vector3.dot_product(toward, right)) : F32))

# if (!IsSoundPlaying(sound)) PlaySound(sound).
def played(+audio: J.AudioDevice, +sound: J.Sound) -> J.AudioDevice:
  Bool.pick(J.AudioDevice, J.Sound.is_playing(audio, sound), audio, J.Sound.play(audio, sound))

# spherePos = (5.0f*cosf(th), 0.0f, 5.0f*sinf(th)).
def sphere.at(sine: Maybe<F32>, cosine: Maybe<F32>) -> +Maybe<M.Vector3>:
  match sine cosine:
    case Some{+s} Some{+c}: Some{M.Vector3{(5.0 * c : F32), 0.0, (5.0 * s : F32)}}
    case _ _: None{}

# th = (float)GetTime().
def sphere(th: Maybe<F32>, +libm: M.Libm) -> +Maybe<M.Vector3>:
  match th:
    case None{}: None{}
    case Some{+t}: sphere.at(M.Libm.sin(libm, t), M.Libm.cos(libm, t))

def update.kept(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{c}: Some{c}

def update.camera(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: update.kept(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_FREE()))

def update.sound(camera: +Maybe<J.Camera3D>, sphere: +Maybe<M.Vector3>, +audio: J.AudioDevice, +sound: J.Sound) -> State:
  match camera sphere:
    case Some{+c} Some{+s}: State{Some{c}, played(positioned(audio, sound, c, s), sound), sound, Some{s}}
    case _ _: State{None{}, audio, sound, None{}}

def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+camera, +audio, +sound, _} = state
  (core, update.sound(update.camera(libm, core, camera), sphere(M.Float64.to_f32(J.Core.get_time(core)), libm), audio, sound))

# BeginMode3D(camera): DrawGrid(10, 2) and DrawSphere(spherePos, 0.5f, RED).
def draw.scene(+libm: M.Libm, camera: +Maybe<J.Camera3D>, sphere: +Maybe<M.Vector3>, frame: J.Frame) -> J.Frame:
  match camera sphere:
    case Some{+c} Some{+s}: J.Frame.end_mode_3d(J.Draw.sphere_for(libm, J.Draw.grid(J.Frame.begin_mode_3d_for(libm, frame, c), 10.0, 2.0), s, 0.5, J.Color.RED()))
    case _ _: J.Frame.refuse(frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, _, _, +sphere} = state
  (core, (state, draw.scene(libm, camera, sphere, J.Frame.clear_background(frame, J.Color.RAYWHITE()))))

# The main loop's body; libm is the profile of UpdateCamera's and the sphere's sinf/cosf and BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# LoadSound gives the zero sound for a file it cannot load.
def setup.sound(r: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>) -> State:
  match r:
    case Tuple{+audio, Done{+sound}}: State{Some{start()}, audio, sound, None{}}
    case Tuple{+audio, Fail{_}}: State{Some{start()}, audio, J.Sound.none(), None{}}

# After InitWindow(800, 450): InitAudioDevice, LoadSound(dir ++
# "resources/coin.wav"), the camera, DisableCursor(), SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, J.Core & (J.Frame & State), J.Sound.load(J.AudioDevice.init(J.AudioDevice.none()), dir ++ "resources/coin.wav"),
    r => IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(J.Input.disable_cursor(core), 60), (frame, setup.sound(r)))))

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
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - sound positioning", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
