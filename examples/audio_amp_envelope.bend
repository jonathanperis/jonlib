# raylib [audio] example - amp envelope, ported to Jonlib.
# Adapted from raylib 6.2 examples/audio/audio_amp_envelope.c (zlib/libpng,
# Copyright (c) 2026 Arbinda Rizki Muhammad (@arbipink)); see
# LICENSES/raylib.txt.
#
# A 44100 Hz mono float stream of 4096-frame halves plays a 440 Hz sine
# under an ADSR envelope: SPACE starts the attack (then decay and sustain),
# its release the release. Whenever the device has read a half through, the
# program writes the next one, stepping the envelope once per sample, or
# silence (and the phase back to 0) while the envelope is idle at 0. Four
# raygui slider bars (Jongui) set the attack, decay, sustain and release; the
# envelope is drawn as four lines and its current gain as a dot.
#
# raylib's device reads the stream on a thread of its own. Here the device
# has a clock (J.AudioClock, docs/AUDIO.md): every pass of the loop first
# makes the callbacks that were due by the frame's time, one each 10 ms. The
# samples go nowhere: there is no host device. The samples' sinf and
# DrawCircleV's sinf/cosf follow the libm profile (M.Libm.sin,
# docs/SINCOSF.md); a frame is refused where it gives no answer, and every
# later one. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# The Envelope: attackTime, decayTime, sustainLevel, releaseTime,
# currentValue and state (0 IDLE, 1 ATTACK, 2 DECAY, 3 SUSTAIN, 4 RELEASE).
type Adsr is Data:
  Adsr{attack: F32, decay: F32, sustain: F32, release: F32, value: F32, phase: U32}

# valid: every callback and libm call was answered; at is audioTime.
type State is Data:
  State{valid: Bool, audio: J.AudioDevice, clock: J.AudioClock, stream: J.AudioStream, gui: G.Gui, env: Adsr, at: F32}

# What a filled buffer leaves: whether every sample was answered, the
# envelope, audioTime and the samples (F32 bits).
type Refill is Data:
  Refill{fine: Bool, env: Adsr, at: F32, data: +List<U32>}

def Adsr.attack(env: Adsr) -> F32:
  Adsr{attack, _, _, _, _, _} = env
  attack

def Adsr.decay(env: Adsr) -> F32:
  Adsr{_, decay, _, _, _, _} = env
  decay

def Adsr.sustain(env: Adsr) -> F32:
  Adsr{_, _, sustain, _, _, _} = env
  sustain

def Adsr.release(env: Adsr) -> F32:
  Adsr{_, _, _, release, _, _} = env
  release

def Adsr.value(env: Adsr) -> F32:
  Adsr{_, _, _, _, value, _} = env
  value

def Adsr.phase(env: Adsr) -> U32:
  Adsr{_, _, _, _, _, phase} = env
  phase

def Adsr.with_phase(env: Adsr, +phase: U32) -> Adsr:
  Adsr{+a, +d, +s, +r, +value, _} = env
  Adsr{a, d, s, r, value, phase}

# -----------------------------------------------------------------------------
# UpdateEnvelope, once per sample

# sampleTime = 1.0f/SAMPLE_RATE.
def tick() -> F32:
  (1.0 / 44100.0 : F32)

def Adsr.attacked(+v: F32, +a: F32, +d: F32, +s: F32, +r: F32) -> Adsr:
  Bool.pick(Adsr, (v >= 1.0 : F32), Adsr{a, d, s, r, 1.0, 2}, Adsr{a, d, s, r, v, 1})

def Adsr.decayed(+v: F32, +a: F32, +d: F32, +s: F32, +r: F32) -> Adsr:
  Bool.pick(Adsr, (v <= s : F32), Adsr{a, d, s, r, s, 3}, Adsr{a, d, s, r, v, 2})

def Adsr.released(+v: F32, +a: F32, +d: F32, +s: F32, +r: F32) -> Adsr:
  Bool.pick(Adsr, (v <= 0.001 : F32), Adsr{a, d, s, r, 0.0, 0}, Adsr{a, d, s, r, v, 4})

# ATTACK: currentValue += (1/attackTime)*sampleTime up to 1, then DECAY;
# DECAY: -= ((1 - sustainLevel)/decayTime)*sampleTime down to the sustain
# level, then SUSTAIN; SUSTAIN: the sustain level; RELEASE: -=
# (sustainLevel/releaseTime)*sampleTime down to 0.001f, then 0 and IDLE.
def Adsr.stepped(phase: U32, +a: F32, +d: F32, +s: F32, +r: F32, +value: F32) -> Adsr:
  match phase:
    case 1: Adsr.attacked((value + (1.0 / a) * tick() : F32), a, d, s, r)
    case 2: Adsr.decayed((value - ((1.0 - s) / d) * tick() : F32), a, d, s, r)
    case 3: Adsr{a, d, s, r, s, 3}
    case 4: Adsr.released((value - (s / r) * tick() : F32), a, d, s, r)
    case _: Adsr{a, d, s, r, value, 0}

def Adsr.step(env: Adsr) -> Adsr:
  Adsr{+a, +d, +s, +r, +value, +phase} = env
  Adsr.stepped(phase, a, d, s, r, value)

# -----------------------------------------------------------------------------
# The stream

# sinf(2.0f*PI*frequency*audioTime) with frequency 440.
def wave(+libm: M.Libm, +at: F32) -> Maybe<F32>:
  M.Libm.sin(libm, (((2.0 * M.Math.PI()) * 440.0) * at : F32))

# For each of BUFFER_SIZE samples: UpdateEnvelope, buffer[i] =
# currentValue*sinf(...) and audioTime += 1.0f/SAMPLE_RATE. `sine` is the
# sine of audioTime `at`, `env` the envelope before this sample's step.
def fill(n: Nat, sine: Maybe<F32>, +libm: M.Libm, +env: Adsr, +at: F32, +acc: +List<U32>) -> Refill:
  match n:
    case 0n: Refill{True{}, env, at, List.reverse(&2, U32, acc)}
    case 1n+rest:
      match sine:
        case None{}: Refill{False{}, env, at, Nil{}}
        case Some{+s}:
          +next = Adsr.step(env)
          +later = (at + tick() : F32)
          fill(rest, wave(libm, later), libm, next, later, Con{F32.bits((Adsr.value(next) * s : F32)), acc})

def zeros(n: Nat, +acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+rest: zeros(rest, Con{0, acc})

# if (!IsAudioStreamPlaying(stream)) PlayAudioStream(stream).
def finish(+valid: Bool, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +gui: G.Gui, +env: Adsr, +at: F32) -> State:
  State{valid, Bool.pick(J.AudioDevice, J.AudioStream.is_playing(audio, stream), audio, J.AudioStream.play(audio, stream)), clock, stream, gui, env, at}

# UpdateAudioStream(stream, buffer, BUFFER_SIZE).
def update.fed(filled: Refill, +valid: Bool, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +gui: G.Gui) -> State:
  Refill{+fine, +env, +at, +data} = filled
  finish(valid && fine, Bool.pick(J.AudioDevice, fine, J.AudioStream.update(audio, stream, data, 4096), audio), clock, stream, gui, env, at)

# The envelope's samples, or a buffer of zeros and audioTime back to 0.
def update.sound(sounding: Bool, +libm: M.Libm, +valid: Bool, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +gui: G.Gui, +env: Adsr, +at: F32) -> State:
  match sounding:
    case True{}: update.fed(fill(4096n, wave(libm, at), libm, env, at, Nil{}), valid, audio, clock, stream, gui)
    case False{}: finish(valid, J.AudioStream.update(audio, stream, zeros(4096n, Nil{}), 4096), clock, stream, gui, env, 0.0)

# if (IsAudioStreamProcessed(stream)): sound while the envelope is not idle
# or not yet at 0.
def update.stream(processed: Bool, +libm: M.Libm, +valid: Bool, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +gui: G.Gui, +env: Adsr, +at: F32) -> State:
  match processed:
    case False{}: finish(valid, audio, clock, stream, gui, env, at)
    case True{}: update.sound(Bool.not(U32.is_eq(Adsr.phase(env), 0)) || (Adsr.value(env) > 0.0 : F32), libm, valid, audio, clock, stream, gui, env, at)

# SPACE pressed: ATTACK; SPACE released while not IDLE: RELEASE.
def update.keys(step: J.AudioClock.Step, +libm: M.Libm, +core: J.Core, +valid: Bool, +stream: J.AudioStream, +gui: G.Gui, +env: Adsr, +at: F32) -> State:
  J.AudioStep{+clock, +audio, +fine} = step
  +pressed = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), 1, Adsr.phase(env))
  +released = Bool.pick(U32, J.Input.is_key_released(core, J.KeyboardKey.KEY_SPACE()) && Bool.not(U32.is_eq(pressed, 0)), 4, pressed)
  update.stream(J.AudioStream.is_processed(audio, stream), libm, valid && fine, audio, clock, stream, gui, Adsr.with_phase(env, released), at)

# The device's callbacks up to this pass's time come first.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{+valid, +audio, +clock, +stream, +gui, +env, +at} = state
  (core, update.keys(J.AudioClock.advance(clock, audio, J.Core.get_time(core)), libm, core, valid, stream, gui, env, at))

# -----------------------------------------------------------------------------
# Draw

# The state the sliders leave alone.
type Kept is Data:
  Kept{valid: Bool, audio: J.AudioDevice, clock: J.AudioClock, stream: J.AudioStream, at: F32, phase: U32, value: F32}

def Kept.phase(kept: Kept) -> U32:
  Kept{_, _, _, _, _, phase, _} = kept
  phase

def Kept.value(kept: Kept) -> F32:
  Kept{_, _, _, _, _, _, value} = kept
  value

# A slider's outcome: the frame, the Gui and the value.
type Slider is Type:
  Slider{frame: J.Frame, gui: G.Gui, value: F32}

def slid.value(gui: G.Gui, frame: J.Frame, pair: F32 & Bool) -> Slider:
  (value, _) = pair
  Slider{frame, gui, value}

def slid.gui(frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> Slider:
  (gui, pair) = rest
  slid.value(gui, frame, pair)

def slid.done(r: J.Frame & (G.Gui & (F32 & Bool))) -> Slider:
  (frame, rest) = r
  slid.gui(frame, rest)

# GuiSliderBar((100, y, 400, 30), label, text, &value, min, max).
def slid(+gui: G.Gui, +core: J.Core, frame: J.Frame, +y: F32, label: String, text: Maybe<String>, +value: F32, +min: F32, +max: F32) -> Slider:
  match text:
    case None{}: Slider{J.Frame.refuse(frame), gui, value}
    case Some{t}: slid.done(G.Gui.slider_bar(gui, core, frame, J.Rectangle{100.0, y, 400.0, 30.0}, Some{label}, Some{t}, value, min, max))

def checked(valid: Bool, frame: J.Frame) -> J.Frame:
  match valid:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# DrawADSRGraph(&env, (Rectangle){ 100, 250, 400, 100 }): totalTime is the
# sum of the times with 1 for the sustain, scaleX = width/totalTime, scaleY =
# height.
def graph(+a: F32, +d: F32, +s: F32, +r: F32, frame: J.Frame) -> J.Frame:
  +scale = (400.0 / (((a + d) + 1.0) + r) : F32)
  +peak = (100.0 + a * scale : F32)
  +held = (peak + d * scale : F32)
  +level = (250.0 + (1.0 - s) * 100.0 : F32)
  +rel = (held + 1.0 * scale : F32)
  +end = (rel + r * scale : F32)
  f1 = J.Draw.rectangle_rec(frame, J.Rectangle{100.0, 250.0, 400.0, 100.0}, J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.3))
  f2 = J.Draw.rectangle_lines_ex(f1, J.Rectangle{100.0, 250.0, 400.0, 100.0}, 1.0, J.Color.GRAY())
  f3 = J.Draw.line_v(f2, M.Vector2{100.0, (250.0 + 100.0 : F32)}, M.Vector2{peak, 250.0}, J.Color.SKYBLUE())
  f4 = J.Draw.line_v(f3, M.Vector2{peak, 250.0}, M.Vector2{held, level}, J.Color.BLUE())
  f5 = J.Draw.line_v(f4, M.Vector2{held, level}, M.Vector2{rel, level}, J.Color.DARKBLUE())
  f6 = J.Draw.line_v(f5, M.Vector2{rel, level}, M.Vector2{end, (250.0 + 100.0 : F32)}, J.Color.ORANGE())
  J.Draw.text(f6, "ADSR Visualizer", 100.0, (250.0 - 20.0 : F32), 10.0, J.Color.DARKGRAY())

# DrawText(TextFormat("Current Gain: %2.2f", currentValue), 535, 345 - currentValue*100, 10, MAROON).
def gain(line: Maybe<String>, +value: F32, frame: J.Frame) -> J.Frame:
  match line:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 535.0, (345.0 - value * 100.0 : F32), 10.0, J.Color.MAROON())

def draw.rest(+libm: M.Libm, +core: J.Core, kept: Kept, +gui: G.Gui, +env: Adsr, frame: J.Frame) -> J.Core & (State & J.Frame):
  Kept{+valid, +audio, +clock, +stream, +at, _, +value} = kept
  f1 = graph(Adsr.attack(env), Adsr.decay(env), Adsr.sustain(env), Adsr.release(env), frame)
  f2 = J.Draw.circle_v_for(libm, f1, M.Vector2{520.0, (350.0 - value * 100.0 : F32)}, 5.0, J.Color.MAROON())
  f3 = gain(J.Text.format("Current Gain: %2.2f", [J.TextFloat{value}]), value, f2)
  f4 = J.Draw.text(f3, "Press SPACE to PLAY the sound!", 200.0, 400.0, 20.0, J.Color.LIGHTGRAY())
  (core, (State{valid, audio, clock, stream, gui, env, at}, f4))

def draw.release(+libm: M.Libm, +core: J.Core, +kept: Kept, +a: F32, +d: F32, +s: F32, slider: Slider) -> J.Core & (State & J.Frame):
  Slider{frame, +gui, +rl} = slider
  draw.rest(libm, core, kept, gui, Adsr{a, d, s, rl, Kept.value(kept), Kept.phase(kept)}, frame)

def draw.sustain(+libm: M.Libm, +core: J.Core, +kept: Kept, +a: F32, +d: F32, +rl: F32, slider: Slider) -> J.Core & (State & J.Frame):
  Slider{frame, +gui, +s} = slider
  draw.release(libm, core, kept, a, d, s, slid(gui, core, frame, 180.0, "Release (s)", J.Text.format("%2.2fs", [J.TextFloat{rl}]), rl, 0.1, 3.0))

def draw.decay(+libm: M.Libm, +core: J.Core, +kept: Kept, +a: F32, +s: F32, +rl: F32, slider: Slider) -> J.Core & (State & J.Frame):
  Slider{frame, +gui, +d} = slider
  draw.sustain(libm, core, kept, a, d, rl, slid(gui, core, frame, 140.0, "Sustain", J.Text.format("%2.2f", [J.TextFloat{s}]), s, 0.0, 1.0))

def draw.attack(+libm: M.Libm, +core: J.Core, +kept: Kept, +d: F32, +s: F32, +rl: F32, slider: Slider) -> J.Core & (State & J.Frame):
  Slider{frame, +gui, +a} = slider
  draw.decay(libm, core, kept, a, s, rl, slid(gui, core, frame, 100.0, "Decay (s)", J.Text.format("%2.2fs", [J.TextFloat{d}]), d, 0.1, 3.0))

# The four slider bars run inside the frame, in order, before the graph: a
# value one changes shows in the graph of the same frame, and reaches the
# envelope from the next update on.
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +audio, +clock, +stream, +gui, +env, +at} = state
  draw.attack(libm, core, Kept{valid, audio, clock, stream, at, Adsr.phase(env), Adsr.value(env)}, Adsr.decay(env), Adsr.sustain(env), Adsr.release(env),
    slid(gui, core, J.Frame.clear_background(checked(valid, frame), J.Color.RAYWHITE()), 60.0, "Attack (s)", J.Text.format("%2.2fs", [J.TextFloat{Adsr.attack(env)}]),
      Adsr.attack(env), 0.1, 3.0))

# The main loop's body; libm is the profile of the samples' sinf and of DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# The envelope 1 s, 1 s, 0.5, 1 s, at 0 and IDLE; audioTime 0.
def setup.stream(loaded: J.AudioDevice & J.AudioStream, +now: M.Float64) -> State:
  (+audio, +stream) = loaded
  State{True{}, audio, J.AudioClock.at(now), stream, G.Gui.new(), Adsr{1.0, 1.0, 0.5, 1.0, 0.0, 0}, 0.0}

# After InitWindow(800, 450): InitAudioDevice,
# SetAudioStreamBufferSizeDefault(4096), LoadAudioStream(44100, 32, 1) and
# SetTargetFPS(60); the stream is played by the loop's first pass.
def setup(+core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60),
    (frame, setup.stream(J.AudioStream.load(J.AudioDevice.set_stream_buffer_size_default(J.AudioDevice.init(J.AudioDevice.none()), 4096), 44100, 32, 1), J.Core.get_time(core)))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - amp envelope", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
