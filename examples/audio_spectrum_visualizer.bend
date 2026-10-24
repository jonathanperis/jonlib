# raylib [audio] example - spectrum visualizer, ported to Jonlib.
# Adapted from raylib 6.2 examples/audio/audio_spectrum_visualizer.c
# (zlib/libpng, Copyright (c) 2025 Seth Archambault (@AnAxaholic)); see
# LICENSES/raylib.txt.
#
# resources/country.mp3 is loaded whole as a wave, brought to 16-bit mono and
# fed to an audio stream 2048 samples at a time; each frame the last 1024
# samples (pairs averaged) go through a Blackman window and a fast Fourier
# transform, their 512 magnitudes are smoothed over time, put on a decibel
# scale from -100 to -30, and written as the red of a 512x1 image, which a
# fragment shader would draw as bars.
#
# raylib's software renderer runs no shader (docs/SHADERS.md): the frame is
# the render texture the example draws under it, which nothing was drawn
# into. The spectrum is computed all the same, as the example computes it;
# `capture` and `render` below are its CaptureFrame and RenderFrame, and the
# `spectrum` gate compares them with the example's own (docs/AUDIO.md).
#
# Each frame's Blackman weights and the transform's twiddle factors depend
# on nothing but their place, so they are computed once, with the libm
# profile's cosf and sinf (M.Libm), as the example computes them every
# frame; a frame is refused where one of those, or a frame's logf, has no
# answer (AppleLibm has none). The device has a clock (J.AudioClock,
# docs/AUDIO.md). Loads resources/country.mp3 from raylib's examples/audio
# directory: run from that directory, or pass `--resources <dir/>`.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A complex number of the transform (FFTComplex).
type Bin is Data:
  Bin{re: F32, im: F32}

# What does not change from frame to frame: whether every cosf and sinf was
# answered, the 1024 Blackman weights, the twiddle factors of each of the
# ten stages (the first of a stage is 1), and 1e-40f.
type Tables is Data:
  Tables{fine: Bool, weights: +List<F32>, stages: +List<+List<Bin>>, tiny: F32}

def Tables.fine(tables: Tables) -> Bool:
  Tables{fine, _, _, _} = tables
  fine

# FFTData: prevMagnitudes, fftHistory (45 rows of 512) and historyPos.
type Fft is Data:
  Fft{previous: +List<F32>, history: +List<+List<F32>>, position: U32}

# -----------------------------------------------------------------------------
# The tables

# 0.42f - 0.5f*cosf(x) + 0.08f*cosf(2.0f*x) for x = (2.0f*PI*i)/(1024 - 1.0f).
def weight(first: Maybe<F32>, second: Maybe<F32>) -> Maybe<F32>:
  match first second:
    case Some{+a} Some{+b}: Some{((0.42 - (0.5 * a)) + (0.08 * b) : F32)}
    case _ _: None{}

type Weights is Data:
  Weights{fine: Bool, list: +List<F32>}

def weights.with(w: Maybe<F32>, +fine: Bool, +acc: +List<F32>) -> Weights:
  match w:
    case None{}: Weights{False{}, Con{0.0, acc}}
    case Some{+v}: Weights{fine, Con{v, acc}}

def Weights.fine(weights: Weights) -> Bool:
  Weights{fine, _} = weights
  fine

def Weights.list(weights: Weights) -> +List<F32>:
  Weights{_, list} = weights
  list

# The weights from the last to the first, so that the list ends in order.
def window.weights(n: Nat, +libm: M.Libm, +i: U32, +made: Weights) -> Weights:
  match n:
    case 0n: made
    case 1n+k:
      +x = (((2.0 * M.Math.PI()) * U32.to_f32(i)) / (1024.0 - 1.0) : F32)
      window.weights(k, libm, (i - 1 : U32), weights.with(weight(M.Libm.cos(libm, x), M.Libm.cos(libm, (2.0 * x : F32))), Weights.fine(made), Weights.list(made)))

# twiddleCurrent after each step of a stage: (1, 0), then times twiddleUnit,
# the imaginary part from the real part before the step.
def twiddles(n: Nat, +cr: F32, +ci: F32, +ur: F32, +ui: F32, acc: +List<Bin>) -> +List<Bin>:
  match n:
    case 0n: List.reverse(&2, Bin, acc)
    case 1n+k: twiddles(k, ((cr * ur) - (ci * ui) : F32), ((cr * ui) + (ci * ur) : F32), ur, ui, Con{Bin{cr, ci}, acc})

type Stages is Data:
  Stages{fine: Bool, list: +List<+List<Bin>>}

# twiddleUnit = { cosf(angle), sinf(angle) } for angle = -2.0f*PI/len.
def stage.with(c: Maybe<F32>, s: Maybe<F32>, +half: U32, +fine: Bool, +acc: +List<+List<Bin>>) -> Stages:
  match c s:
    case Some{+ur} Some{+ui}: Stages{fine, Con{twiddles(U32.to_nat(half), 1.0, 0.0, ur, ui, Nil{}), acc}}
    case _ _: Stages{False{}, Con{Nil{}, acc}}

def Stages.fine(stages: Stages) -> Bool:
  Stages{fine, _} = stages
  fine

def Stages.list(stages: Stages) -> +List<+List<Bin>>:
  Stages{_, list} = stages
  list

# The stages from len = 1024 down to 2, so that the list begins with len = 2.
def twiddle.stages(n: Nat, +libm: M.Libm, +len: U32, +made: Stages) -> Stages:
  match n:
    case 0n: made
    case 1n+k:
      +angle = ((F32.neg(2.0) * M.Math.PI()) / U32.to_f32(len) : F32)
      twiddle.stages(k, libm, (len / 2 : U32), stage.with(M.Libm.cos(libm, angle), M.Libm.sin(libm, angle), (len / 2 : U32), Stages.fine(made), Stages.list(made)))

def tables.made(+w: Weights, +s: Stages) -> Tables:
  Tables{Weights.fine(w) && Stages.fine(s), Weights.list(w), Stages.list(s), J.Wave.float_bits(71362)}

def tables.for(+libm: M.Libm) -> Tables:
  tables.made(window.weights(1024n, libm, 1023, Weights{True{}, Nil{}}), twiddle.stages(10n, libm, 1024, Stages{True{}, Nil{}}))

# -----------------------------------------------------------------------------
# CooleyTukeyFFTSlow

def evens(xs: +List<Bin>, acc: +List<Bin>) -> +List<Bin>:
  match xs:
    case Con{+a, Con{_, +rest}}: evens(rest, Con{a, acc})
    case Con{+a, Nil{}}: List.reverse(&2, Bin, Con{a, acc})
    case Nil{}: List.reverse(&2, Bin, acc)

def odds(xs: +List<Bin>, acc: +List<Bin>) -> +List<Bin>:
  match xs:
    case Con{_, Con{+b, +rest}}: odds(rest, Con{b, acc})
    case _: List.reverse(&2, Bin, acc)

# The bit-reversal the example makes by swaps: the values at the even places
# reordered, then those at the odd ones.
def reversed(+n: Nat, +xs: +List<Bin>) -> +List<Bin>:
  match n:
    case 0n: xs
    case 1n+k: List.append(&2, Bin, reversed(k, evens(xs, Nil{})), reversed(k, odds(xs, Nil{})))

# A block of a stage: its sums and its differences (the last first) and what
# follows the block.
type Block is Data:
  Block{sums: +List<Bin>, diffs: +List<Bin>, rest: +List<Bin>}

# even + twiddle*odd and even - twiddle*odd for each pair of a block, `a` at
# its first half and `b` at its second.
def butterflies(n: Nat, a: +List<Bin>, b: +List<Bin>, tw: +List<Bin>, +sums: +List<Bin>, +diffs: +List<Bin>) -> Block:
  match n:
    case 0n: Block{sums, diffs, b}
    case 1n+k:
      match a b tw:
        case Con{Bin{+er, +ei}, +ra} Con{Bin{+or, +oi}, +rb} Con{Bin{+tr, +ti}, +rt}:
          +xr = ((or * tr) - (oi * ti) : F32)
          +xi = ((or * ti) + (oi * tr) : F32)
          butterflies(k, ra, rb, rt, Con{Bin{(er + xr : F32), (ei + xi : F32)}, sums}, Con{Bin{(er - xr : F32), (ei - xi : F32)}, diffs})
        case _ _ _: Block{sums, diffs, Nil{}}

def block.out(block: Block, +out: +List<Bin>) -> +List<Bin>:
  Block{+sums, +diffs, _} = block
  List.append(&2, Bin, diffs, List.append(&2, Bin, sums, out))

def Block.rest(block: Block) -> +List<Bin>:
  Block{_, _, rest} = block
  rest

# A stage over its blocks of 2*half values; `out` is the stage so far, the
# last value first.
def stage(n: Nat, +xs: +List<Bin>, +half: Nat, +tw: +List<Bin>, +out: +List<Bin>) -> +List<Bin>:
  match n:
    case 0n: List.reverse(&2, Bin, out)
    case 1n+k:
      +block = butterflies(half, xs, List.drop(&2, Bin, xs, half), tw, Nil{}, Nil{})
      stage(k, Block.rest(block), half, tw, block.out(block, out))

# The stages in turn: len = 2 (512 blocks, half 1) up to len = 1024.
def transform(tables: +List<+List<Bin>>, +xs: +List<Bin>, +blocks: U32, +half: U32) -> +List<Bin>:
  match tables:
    case Nil{}: xs
    case Con{+tw, +rest}: transform(rest, stage(U32.to_nat(blocks), xs, U32.to_nat(half), tw, Nil{}), (blocks / 2 : U32), (half * 2 : U32))

# workBuffer[i] = audioSamples[i]*blackmanWeight, imaginary 0.
def windowed(samples: +List<F32>, weights: +List<F32>, acc: +List<Bin>) -> +List<Bin>:
  match samples weights:
    case Con{+s, +more} Con{+w, +rest}: windowed(more, rest, Con{Bin{(s * w : F32), 0.0}, acc})
    case _ _: List.reverse(&2, Bin, acc)

# -----------------------------------------------------------------------------
# CaptureFrame and RenderFrame

# logf(fmaxf(smoothedMagnitude, 1e-40f))*DB_TO_LINEAR_SCALE, then
# (db - MIN_DECIBELS)*INVERSE_DECIBEL_RANGE kept from 0 to 1. The magnitudes
# are not negative, so the greater float is the one with the greater bits.
def level(log: Maybe<F32>) -> Maybe<F32>:
  match log:
    case None{}: None{}
    case Some{+l}:
      +normalized = (((l * (20.0 / 2.302585092994046)) + 100.0) * (1.0 / (F32.neg(30.0) + 100.0)) : F32)
      Some{Bool.pick(F32, (normalized < 0.0 : F32), 0.0, Bool.pick(F32, (normalized > 1.0 : F32), 1.0, normalized))}

# The bins after a frame: whether every logf was answered, the smoothed
# magnitudes and the spectrum (both the last first).
type Smoothed is Data:
  Smoothed{fine: Bool, magnitudes: +List<F32>, spectrum: +List<F32>}

def smoothed.with(value: Maybe<F32>, +fine: Bool, +magnitude: F32, +magnitudes: +List<F32>, +spectrum: +List<F32>) -> Smoothed:
  match value:
    case None{}: Smoothed{False{}, Con{magnitude, magnitudes}, Con{0.0, spectrum}}
    case Some{+v}: Smoothed{fine, Con{magnitude, magnitudes}, Con{v, spectrum}}

def Smoothed.fine(smoothed: Smoothed) -> Bool:
  Smoothed{fine, _, _} = smoothed
  fine

def Smoothed.magnitudes(smoothed: Smoothed) -> +List<F32>:
  Smoothed{_, magnitudes, _} = smoothed
  magnitudes

def Smoothed.spectrum(smoothed: Smoothed) -> +List<F32>:
  Smoothed{_, _, spectrum} = smoothed
  spectrum

# The first 512 bins: linearMagnitude = sqrtf(re*re + im*im)/FFT_WINDOW_SIZE,
# smoothed with the bin's magnitude of the frame before.
def bins(n: Nat, spectrum: +List<Bin>, previous: +List<F32>, +libm: M.Libm, +tiny: F32, +made: Smoothed) -> Smoothed:
  match n:
    case 0n: made
    case 1n+k:
      match spectrum previous:
        case Con{Bin{+re, +im}, +rest} Con{+before, +more}:
          +linear = (F32.sqrt(((re * re) + (im * im) : F32)) / 1024.0 : F32)
          +magnitude = ((0.8 * before) + ((1.0 - 0.8) * linear) : F32)
          bins(k, rest, more, libm, tiny, smoothed.with(level(M.Libm.log(libm, Bool.pick(F32, (F32.bits(magnitude) > F32.bits(tiny) : U32), magnitude, tiny))), Smoothed.fine(made), magnitude,
            Smoothed.magnitudes(made), Smoothed.spectrum(made)))
        case _ _: made

# fftHistory with its row `at` replaced.
def history.set(rows: +List<+List<F32>>, +at: U32, +row: +List<F32>, acc: +List<+List<F32>>) -> +List<+List<F32>>:
  match rows:
    case Nil{}: List.reverse(&2, +List<F32>, acc)
    case Con{+old, +rest}: history.set(rest, (at - 1 : U32), row, Con{Bool.pick(+List<F32>, U32.is_eq(at, 0), row, old), acc})

# What CaptureFrame leaves: whether every logf was answered, and the data.
type Captured is Data:
  Captured{fine: Bool, fft: Fft}

def capture.done(+ready: Bool, +smoothed: Smoothed, +history: +List<+List<F32>>, +position: U32) -> Captured:
  Captured{ready && Smoothed.fine(smoothed), Fft{List.reverse(&2, F32, Smoothed.magnitudes(smoothed)), history.set(history, position, List.reverse(&2, F32, Smoothed.spectrum(smoothed)), Nil{}),
    ((position + 1) % 45 : U32)}}

# CaptureFrame(&fft, audioSamples): the window, the transform, the smoothed
# magnitudes as decibels in the history's row at historyPos, which moves on.
# A frame whose Blackman weights or twiddle factors were not answered is
# refused with the frame whose logf was not.
def capture(+libm: M.Libm, tables: Tables, +samples: +List<F32>, fft: Fft) -> Captured:
  Tables{ready, +window, +twiddled, +tiny} = tables
  Fft{+previous, +history, +position} = fft
  capture.done(ready, bins(512n, transform(twiddled, reversed(10n, windowed(samples, window, Nil{})), 512, 1), previous, libm, tiny, Smoothed{True{}, Nil{}, Nil{}}), history, position)

def row.at(rows: +List<+List<F32>>, +at: U32) -> +List<F32>:
  match rows:
    case Nil{}: Nil{}
    case Con{+row, +rest}: Bool.pick(+List<F32>, U32.is_eq(at, 0), row, row.at(rest, (at - 1 : U32)))

# ImageDrawPixel(fftImage, bin, FFT_ROW, ColorFromNormalized({ amplitude, 0, 0, 0 })).
def pixels(amplitudes: +List<F32>, +bin: U32, image: J.Surface) -> J.Surface:
  match amplitudes:
    case Nil{}: image
    case Con{+amplitude, +rest}: pixels(rest, (bin + 1 : U32), J.Surface.draw_pixel(image, U32.to_f32(bin), 0.0, J.Color.from_normalized(M.Vector4{amplitude, 0.0, 0.0, 0.0})))

# RenderFrame(&fft, &fftImage): the history's row tapbackPos/WINDOW_TIME
# frames back from the last written. tapbackPos is 0.01f and a window is
# 1024/22050 of a second, so that is the last row itself.
def render(+fft: Fft, image: J.Surface) -> J.Surface:
  Fft{_, +history, +position} = fft
  pixels(row.at(history, ((position + 44) % 45 : U32)), 0, image)

# -----------------------------------------------------------------------------
# The program

# valid: the wave was loaded, every callback answered and every libm call
# too. wave is wav.data after WaveFormat (16-bit mono, a word a sample) and
# rest what follows wavCursor; samples are audioSamples; image, texture and
# target are fftImage, fftTexture and bufferA.
type State is Type:
  State{valid: Bool, tables: Tables, audio: J.AudioDevice, clock: J.AudioClock, stream: J.AudioStream, wave: +List<U32>, rest: +List<U32>, samples: +List<F32>, fft: Fft,
    image: Maybe<J.Surface>, texture: Maybe<J.Texture>, target: Maybe<J.RenderTexture>, shader: J.Shader}

def wrapped(more: +List<U32>, +wave: +List<U32>) -> +List<U32>:
  match more:
    case Nil{}: wave
    case Con{+x, +rest}: Con{x, rest}

# The next `n` samples of the wave, which begins again after its last one
# (chunkSamples: with a mono wave left and right are one sample).
type Chunk is Data:
  Chunk{samples: +List<U32>, rest: +List<U32>}

def chunk.taken(n: Nat, rest: +List<U32>, +wave: +List<U32>, +acc: +List<U32>) -> Chunk:
  match n:
    case 0n: Chunk{List.reverse(&2, U32, acc), rest}
    case 1n+k:
      match rest:
        case Nil{}: Chunk{List.reverse(&2, U32, acc), Nil{}}
        case Con{+x, +more}: chunk.taken(k, wrapped(more, wave), wave, Con{x, acc})

def short(+word: U32) -> F32:
  Bool.pick(F32, (word >= 32768 : U32), F32.neg(U32.to_f32((65536 - word : U32))), U32.to_f32(word))

# audioSamples[i] = (chunkSamples[i*2] + chunkSamples[i*2 + 1])*0.5f/32767.0f.
def averaged(samples: +List<U32>, acc: +List<F32>) -> +List<F32>:
  match samples:
    case Con{+a, Con{+b, +rest}}: averaged(rest, Con{(((short(a) + short(b)) * 0.5) / 32767.0 : F32), acc})
    case _: List.reverse(&2, F32, acc)

# The stream's data: the device, what follows the cursor and audioSamples.
type Fed is Data:
  Fed{audio: J.AudioDevice, rest: +List<U32>, samples: +List<F32>}

def fed.chunk(+audio: J.AudioDevice, +stream: J.AudioStream, +taken: Chunk) -> Fed:
  Chunk{+samples, +rest} = taken
  Fed{J.AudioStream.update(audio, stream, samples, 2048), rest, averaged(samples, Nil{})}

def Fed.audio(fed: Fed) -> J.AudioDevice:
  Fed{audio, _, _} = fed
  audio

def fed.next(+stream: J.AudioStream, +wave: +List<U32>, fed: Fed) -> Fed:
  Fed{+audio, +rest, _} = fed
  fed.chunk(audio, stream, chunk.taken(2048n, rest, wave, Nil{}))

# while (IsAudioStreamProcessed(audioStream)): the stream has two halves, so
# no more than two turns. `processed` is the stream's answer for `fed`.
def feed(n: Nat, processed: Bool, +stream: J.AudioStream, +wave: +List<U32>, +fed: Fed) -> Fed:
  match n processed:
    case 1n+k True{}:
      +next = fed.next(stream, wave, fed)
      feed(k, J.AudioStream.is_processed(Fed.audio(next), stream), stream, wave, next)
    case _ _: fed

def update.texture(result: Result<&1, &1, J.Texture & J.Surface.Error, J.Texture>) -> Maybe<J.Texture>:
  match result:
    case Fail{Tuple{texture, _}}: Some{texture}
    case Done{texture}: Some{texture}

# UpdateTexture(fftTexture, fftImage.data): the image is kept, a copy of it
# goes into the texture.
def update.copied(pair: J.Surface & J.Surface, texture: Maybe<J.Texture>) -> Maybe<J.Surface> & Maybe<J.Texture>:
  (image, copy) = pair
  match texture:
    case None{}: (Some{image}, None{})
    case Some{t}: (Some{image}, update.texture(J.Texture.update(t, copy)))

def update.image(image: Maybe<J.Surface>, texture: Maybe<J.Texture>, +fft: Fft) -> Maybe<J.Surface> & Maybe<J.Texture>:
  match image:
    case None{}: (None{}, texture)
    case Some{i}: update.copied(J.Surface.copy(render(fft, i)), texture)

def update.drawn(pair: Maybe<J.Surface> & Maybe<J.Texture>, +valid: Bool, +tables: Tables, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +wave: +List<U32>, +rest: +List<U32>,
    +samples: +List<F32>, +fft: Fft, target: Maybe<J.RenderTexture>, +shader: J.Shader) -> State:
  (image, texture) = pair
  State{valid, tables, audio, clock, stream, wave, rest, samples, fft, image, texture, target, shader}

def update.captured(+captured: Captured, +valid: Bool, +tables: Tables, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +wave: +List<U32>, +rest: +List<U32>, +samples: +List<F32>,
    image: Maybe<J.Surface>, texture: Maybe<J.Texture>, target: Maybe<J.RenderTexture>, +shader: J.Shader) -> State:
  Captured{+fine, +fft} = captured
  update.drawn(update.image(image, texture, fft), valid && fine, tables, audio, clock, stream, wave, rest, samples, fft, target, shader)

def update.fed(+libm: M.Libm, fed: Fed, +valid: Bool, +tables: Tables, +clock: J.AudioClock, +stream: J.AudioStream, +wave: +List<U32>, +fft: Fft, image: Maybe<J.Surface>, texture: Maybe<J.Texture>,
    target: Maybe<J.RenderTexture>, +shader: J.Shader) -> State:
  Fed{+audio, +rest, +samples} = fed
  update.captured(capture(libm, tables, samples, fft), valid, tables, audio, clock, stream, wave, rest, samples, image, texture, target, shader)

# A state that is not valid does nothing more: its frames are refused.
def update.clocked(step: J.AudioClock.Step, +libm: M.Libm, +valid: Bool, +tables: Tables, +stream: J.AudioStream, +wave: +List<U32>, +rest: +List<U32>, +samples: +List<F32>, +fft: Fft,
    image: Maybe<J.Surface>, texture: Maybe<J.Texture>, target: Maybe<J.RenderTexture>, +shader: J.Shader) -> State:
  J.AudioStep{+clock, +audio, +fine} = step
  match valid:
    case False{}: State{False{}, tables, audio, clock, stream, wave, rest, samples, fft, image, texture, target, shader}
    case True{}: update.fed(libm, feed(2n, J.AudioStream.is_processed(audio, stream), stream, wave, Fed{audio, rest, samples}), fine, tables, clock, stream, wave, fft, image, texture, target, shader)

# The device's callbacks up to this pass's time come first.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+valid, +tables, +audio, +clock, +stream, +wave, +rest, +samples, +fft, image, texture, target, +shader} = state
  (core, update.clocked(J.AudioClock.advance(clock, audio, J.Core.get_time(core)), libm, valid, tables, stream, wave, rest, samples, fft, image, texture, target, shader))

def draw.kept(r: J.Frame & J.Texture, +id: U32, +depth: U32) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTextureRec(bufferA.texture, (Rectangle){ 0, 0, 800, -450 }, (Vector2){ 0, 0 }, WHITE)
# between BeginShaderMode and EndShaderMode.
def draw.target(target: Maybe<J.RenderTexture>, +shader: J.Shader, frame: J.Frame) -> J.Frame & Maybe<J.RenderTexture>:
  match target:
    case None{}: (J.Frame.refuse(frame), None{})
    case Some{J.RenderTexture{+id, texture, +depth}}:
      draw.kept(J.Draw.texture_rec(J.Frame.begin_shader_mode(frame, shader), texture, J.Rectangle{0.0, 0.0, 800.0, F32.neg(450.0)}, M.Vector2{0.0, 0.0}, J.Color.WHITE()), id, depth)

def draw.done(r: J.Frame & Maybe<J.RenderTexture>, +core: J.Core, +valid: Bool, +tables: Tables, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +wave: +List<U32>, +rest: +List<U32>,
    +samples: +List<F32>, +fft: Fft, image: Maybe<J.Surface>, texture: Maybe<J.Texture>, +shader: J.Shader) -> J.Core & (State & J.Frame):
  (frame, target) = r
  (core, (State{valid, tables, audio, clock, stream, wave, rest, samples, fft, image, texture, target, shader}, J.Frame.end_shader_mode(frame)))

def draw.valid(valid: Bool, +core: J.Core, +tables: Tables, +audio: J.AudioDevice, +clock: J.AudioClock, +stream: J.AudioStream, +wave: +List<U32>, +rest: +List<U32>, +samples: +List<F32>, +fft: Fft,
    image: Maybe<J.Surface>, texture: Maybe<J.Texture>, target: Maybe<J.RenderTexture>, +shader: J.Shader, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (State{False{}, tables, audio, clock, stream, wave, rest, samples, fft, image, texture, target, shader}, J.Frame.refuse(frame)))
    case True{}:
      draw.done(draw.target(target, shader, J.Frame.clear_background(frame, J.Color.RAYWHITE())), core, True{}, tables, audio, clock, stream, wave, rest, samples, fft, image, texture, shader)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +tables, +audio, +clock, +stream, +wave, +rest, +samples, +fft, image, texture, target, +shader} = state
  draw.valid(valid, core, tables, audio, clock, stream, wave, rest, samples, fft, image, texture, target, shader, frame)

# The main loop's body; libm is the profile of the transform's cosf, sinf
# and logf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(core, state, frame)}

def zeros(n: Nat, acc: +List<F32>) -> +List<F32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0.0, acc})

def rows(n: Nat, acc: +List<+List<F32>>) -> +List<+List<F32>>:
  match n:
    case 0n: acc
    case 1n+k: rows(k, Con{zeros(512n, Nil{}), acc})

# The wave as the example reads it: 16-bit mono samples; none where the file
# did not load or WaveFormat refused it.
def setup.samples(result: Result<&1, &1, J.Wave & J.Wave.Error, J.Wave>) -> +List<U32>:
  match result:
    case Fail{_}: Nil{}
    case Done{J.Wave{_, _, _, _, +data}}: data

def setup.wave(result: Result<&1, &1, J.Wave.IOError, J.Wave>) -> +List<U32>:
  match result:
    case Fail{_}: Nil{}
    case Done{+wave}: setup.samples(J.Wave.format(wave, 44100, 16, 1))

def some(wave: +List<U32>) -> Bool:
  match wave:
    case Nil{}: False{}
    case Con{_, _}: True{}

# LoadAudioStream(44100, 16, 1) and PlayAudioStream after
# SetAudioStreamBufferSizeDefault(2048); the transform's data zeroed, the
# cursor at the wave's start.
def setup.stream(loaded: J.AudioDevice & J.AudioStream, +tables: Tables, +wave: +List<U32>, +now: M.Float64, image: Maybe<J.Surface>, texture: Maybe<J.Texture>, target: Maybe<J.RenderTexture>) -> State:
  (+audio, +stream) = loaded
  State{Tables.fine(tables) && some(wave), tables, J.AudioStream.play(audio, stream), J.AudioClock.at(now), stream, wave, wave, zeros(1024n, Nil{}), Fft{zeros(512n, Nil{}), rows(45n, Nil{}), 0}, image,
    texture, target, J.Shader.load(None{}, Some{"resources/shaders/glsl330/fft.fs"})}


def setup.target(r: J.Frame & Maybe<J.RenderTexture>, +core: J.Core, +tables: Tables, +wave: +List<U32>, image: Maybe<J.Surface>, texture: Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, setup.stream(J.AudioStream.load(J.AudioDevice.set_stream_buffer_size_default(J.AudioDevice.init(J.AudioDevice.none()), 2048), 44100, 16, 1), tables, wave,
    J.Core.get_time(core), image, texture, target)))

# RenderTexture2D bufferA = LoadRenderTexture(screenWidth, screenHeight).
def setup.texture(r: J.Frame & Maybe<J.Texture>, +core: J.Core, +tables: Tables, +wave: +List<U32>, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  setup.target(J.RenderTexture.load(frame, 800, 450), core, tables, wave, image, texture)

# Texture2D fftTexture = LoadTextureFromImage(fftImage): the image is kept.
def setup.copied(pair: J.Surface & J.Surface, +core: J.Core, +tables: Tables, +wave: +List<U32>, frame: J.Frame) -> J.Core & (J.Frame & State):
  (image, copy) = pair
  setup.texture(J.Texture.load_from_image(frame, copy), core, tables, wave, Some{image})

# Image fftImage = GenImageColor(BUFFER_SIZE, TEXTURE_HEIGHT, WHITE).
def setup.image(image: Maybe<J.Surface>, +core: J.Core, +tables: Tables, +wave: +List<U32>, frame: J.Frame) -> J.Core & (J.Frame & State):
  match image:
    case None{}: setup.target(J.RenderTexture.load(frame, 800, 450), core, tables, wave, None{}, None{})
    case Some{i}: setup.copied(J.Surface.copy(i), core, tables, wave, frame)

# After InitWindow(800, 450): the image and its texture, the render texture,
# the shader, InitAudioDevice, the stream's buffer size, LoadWave(dir ++
# "resources/country.mp3") brought to 44100 Hz, 16 bits and one channel, the
# stream played, and SetTargetFPS(60).
def setup(+libm: M.Libm, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Wave.IOError, J.Wave>, J.Core & (J.Frame & State), J.Wave.load(dir ++ "resources/country.mp3"),
    loaded => IO.pure(J.Core & (J.Frame & State), setup.image(J.Surface.create(512, 1, J.Color.WHITE()), core, tables.for(libm), setup.wave(loaded), frame)))

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
  (+dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [audio] example - spectrum visualizer", 800, 450, limit,
    core => frame => setup(M.Glibc239Libm{}, dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
