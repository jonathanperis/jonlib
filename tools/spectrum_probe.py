#!/usr/bin/env python3
"""Compare the spectrum of examples/audio_spectrum_visualizer.bend with the
example's own.

raylib's audio_spectrum_visualizer computes a spectrum each frame
(CaptureFrame: a Blackman window, a fast Fourier transform of 1024 samples,
magnitudes smoothed over time and put on a decibel scale) and writes it as
the red of a 512x1 image (RenderFrame) for a fragment shader to draw. The
software renderer runs no shader, so no frame of the example shows any of
it and the examples gate cannot compare it. This gate does.

Reference. The example's source, unmodified, included in the reference
program with its main renamed (and raudio.c, which the example calls): its
static CaptureFrame and RenderFrame run on an FFTData made as its main makes
it, over a sequence of frames of 2048 16-bit samples turned into the 1024
floats the example's loop makes of them. Per frame: historyPos, the FNV-1a
of prevMagnitudes' bits, and the image's 512 pixels.

Candidate. The port's `capture` and `render` over the same frames, read from
the same file, with the tables the port computes once (`tables.for`): the
same three things.

The frames: silence (every magnitude is under the 1e-40f the example floors
them with, a subnormal float), a tone, full-scale square waves and noise,
silence again while the smoothing decays, a constant, an impulse, the
quietest samples, a ramp, two tones, and silence until the history's 45
rows have gone round. On a host whose libm profile is AppleLibm the port
has no cosf for its tables and every frame is refused: the rows are then
contracts and nothing is compared natively. CPU-1, CPU-2 and JavaScript
lanes.
"""
import json
import math
import struct

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure

EXAMPLE = 'examples/audio/audio_spectrum_visualizer.c'
WORK = '.build/spectrum-probe/frames.bin'
FLAGS = ['-ffp-contract=off', '-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS', '-DMA_ENABLE_NULL', '-D_DEFAULT_SOURCE', '-Wno-everything']

NATIVE = r'''#include "raudio.c"
#define main example_main
#include "audio_spectrum_visualizer.c"
#undef main
#include <stdio.h>

int main(int argc, char **argv)
{
    FILE *file = fopen(argv[1], "rb");
    static short chunk[AUDIO_STREAM_RING_BUFFER_SIZE];
    static float audioSamples[FFT_WINDOW_SIZE];
    if (!file) return 2;
    // the data as the example's main makes it
    int fftHistoryLen = (int)ceilf(FFT_HISTORICAL_SMOOTHING_DUR/WINDOW_TIME) + 1;
    FFTData fft = {
        .spectrum = RL_CALLOC(sizeof(FFTComplex), FFT_WINDOW_SIZE),
        .workBuffer = RL_CALLOC(sizeof(FFTComplex), FFT_WINDOW_SIZE),
        .prevMagnitudes = RL_CALLOC(BUFFER_SIZE, sizeof(float)),
        .fftHistory = RL_CALLOC(fftHistoryLen, sizeof(float[BUFFER_SIZE])),
        .fftHistoryLen = fftHistoryLen,
        .historyPos = 0,
        .lastFftTime = 0.0,
        .tapbackPos = 0.01f
    };
    Image fftImage = GenImageColor(BUFFER_SIZE, TEXTURE_HEIGHT, WHITE);
    printf("%d\n", fftHistoryLen);
    while (fread(chunk, sizeof(short), AUDIO_STREAM_RING_BUFFER_SIZE, file) == AUDIO_STREAM_RING_BUFFER_SIZE)
    {
        // the example's loop, after UpdateAudioStream
        for (int i = 0; i < FFT_WINDOW_SIZE; i++) audioSamples[i] = (chunk[i*2] + chunk[i*2 + 1])*0.5f/32767.0f;
        CaptureFrame(&fft, audioSamples);
        RenderFrame(&fft, &fftImage);
        unsigned h = 2166136261u;
        for (int i = 0; i < BUFFER_SIZE; i++) { unsigned w; memcpy(&w, &fft.prevMagnitudes[i], 4); h = (h ^ w)*16777619u; }
        printf("%d %u", fft.historyPos, h);
        Color *pixels = fftImage.data;
        for (int i = 0; i < BUFFER_SIZE; i++) printf(" %u", (unsigned)pixels[i].r << 24 | (unsigned)pixels[i].g << 16 | (unsigned)pixels[i].b << 8 | pixels[i].a);
        printf("\n");
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../examples/audio_spectrum_visualizer.bend as Ex

def fnv(xs: +List<F32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, ((h .^. F32.bits(x)) * 16777619 : U32))

def shown(words: List<U32>, +acc: String) -> String:
  match words:
    case Nil{}: acc
    case Con{+w, rest}: shown(rest, acc ++ " " ++ U32.show(w))

def pixels(colors: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> String:
  match colors:
    case Fail{_}: " unread"
    case Done{list}: shown(list, "")

# A frame's 2048 samples: two bytes each, the low one first.
def shorts(n: Nat, bytes: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+k:
      match bytes:
        case Con{+low, Con{+high, +rest}}: shorts(k, rest, Con{(low + (high * 256) : U32), acc})
        case _: List.reverse(&2, U32, acc)

def row(fft: Ex.Fft, pair: J.Surface & J.Surface, fine: Bool) -> J.Surface & String:
  Ex.Fft{+previous, _, +position} = fft
  (image, copy) = pair
  match fine:
    case False{}: (image, "refused")
    case True{}: (image, U32.show(position) ++ " " ++ U32.show(fnv(previous, 2166136261)) ++ pixels(J.Surface.colors(copy)))

def rendered(+captured: Ex.Captured, image: J.Surface) -> J.Surface & String:
  Ex.Captured{+fine, +fft} = captured
  row(fft, J.Surface.copy(Ex.render(fft, image)), fine)

def fft.of(captured: Ex.Captured) -> Ex.Fft:
  Ex.Captured{_, fft} = captured
  fft

# The frames in turn: a line each.
def frames(n: Nat, +libm: M.Libm, +tables: Ex.Tables, +bytes: +List<U32>, +fft: Ex.Fft, state: J.Surface & String, +out: String) -> String:
  match n state:
    case 0n Tuple{_, +line}: out ++ line
    case 1n+k Tuple{image, +line}:
      +captured = Ex.capture(libm, tables, Ex.averaged(shorts(2048n, bytes, Nil{}), Nil{}), fft)
      frames(k, libm, tables, List.drop(&2, U32, bytes, 4096n), fft.of(captured), rendered(captured, image), out ++ line ++ "\\n")

def start(image: Maybe<J.Surface>, +libm: M.Libm, +bytes: +List<U32>, +count: Nat) -> String:
  match image:
    case None{}: "no image"
    case Some{i}: frames(count, libm, Ex.tables.for(libm), bytes, Ex.Fft{Ex.zeros(512n, Nil{}), Ex.rows(45n, Nil{}), 0}, (i, "45"), "")

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +count: Nat) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(start(J.Surface.create(512, 1, J.Color.WHITE()), M.LIBM{}, bytes, count))

def main() -> IO(Unit):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data(PATH), result => loaded(result, COUNTn))
'''


def lcg(state):
    return (state * 1664525 + 1013904223) & 0xFFFFFFFF


def frames():
    """The frames, 2048 16-bit samples each: (name, samples)."""
    def tone(amplitude, cycles, other=0, loud=0):
        return [round(amplitude * math.sin(2 * math.pi * cycles * j / 2048) + loud * math.sin(2 * math.pi * other * j / 2048)) for j in range(2048)]

    def noise(seed):
        out, state = [], seed
        for _ in range(2048):
            state = lcg(state)
            out.append((state >> 16) - 32768)
        return out

    silence = [0] * 2048
    out = [('silence', silence), ('silence', silence)]
    out += [('tone', tone(12000, 37))] * 3
    out += [('square', [32767 if (j // 32) % 2 else -32768 for j in range(2048)])]
    out += [('noise', noise(seed)) for seed in (1, 2, 3)]
    out += [('silence', silence)] * 3
    out += [('constant', [1000] * 2048), ('impulse', [32767 if j == 700 else 0 for j in range(2048)]),
            ('quiet', [1 if j % 2 else -1 for j in range(2048)]), ('faint', tone(3, 200)),
            ('ramp', [j * 16 - 16384 for j in range(2048)]), ('tones', tone(9000, 5, 311, 4000)), ('tones', tone(9000, 5, 311, 4000)),
            ('high', tone(20000, 1023))]
    return out + [('silence', silence)] * 30


def packed(items):
    return b''.join(struct.pack('<2048h', *samples) for _, samples in items)


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('spectrum', args)
    if not (args.raylib_source / EXAMPLE).is_file():
        raise ProbeFailure(f'spectrum: {EXAMPLE} is not in the raylib checkout')
    items = frames()
    path = ROOT / WORK
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(packed(items))
    libm = gradient_reference()
    if libm == 'AppleLibm':
        expected = ['45'] + ['refused'] * len(items)
        compared = 0
    else:
        source, binary = probe.work / 'reference.c', probe.work / 'reference'
        source.write_text(NATIVE)
        raylib = args.raylib_source
        probekit.run(['clang', '-std=c11', '-O2', *FLAGS, source, '-I' + str(raylib / 'src'), '-I' + str(raylib / 'examples/audio'), probe.library, '-lm', '-o', binary])
        expected = probekit.run([binary, path]).splitlines()
        compared = len(items)
        if len(expected) != len(items) + 1 or expected[0] != '45':
            raise ProbeFailure(f'spectrum: the reference printed {len(expected)} lines for {len(items)} frames (history {expected[:1]})')
        rows = [[int(v) for v in line.split()] for line in expected[1:]]
        if any(len(row) != 514 or any(w & 0x00FFFFFF for w in row[2:]) for row in rows):
            raise ProbeFailure('spectrum: a reference frame is not 512 pixels of red alone')
        reds = [[w >> 24 for w in row[2:]] for row in rows]
        positions = [row[0] for row in rows]
        # silence is a flat floor; a tone stands above it at its bin; the history goes round
        if len(set(reds[0])) != 1 or reds[2].index(max(reds[2])) not in (36, 37, 38) or max(reds[5]) < 200 or positions[44:46] != [0, 1] or len({tuple(r) for r in reds}) < 20:
            raise ProbeFailure(f'spectrum: the reference frames are not the ones this probe was written for (floor {set(reds[0])}, tone at {reds[2].index(max(reds[2]))}, positions {positions[43:46]})')

    def render(selected, gpu):
        return PROGRAM.replace('LIBM', libm).replace('PATH', json.dumps(WORK)).replace('COUNT', str(len(items)))

    def parse(text, selected):
        return [text.splitlines()]

    lanes = probe.candidates(render, [items], batch=1, parse=parse, timeout=1500)

    def first(index):
        for rows in lanes.values():
            for k, (a, b) in enumerate(zip(expected, rows[0])):
                if a != b:
                    return f'line {k} ({items[k - 1][0] if k else "history"}): raylib={a[:120]} jonlib={b[:120]}'
        return 'a different number of lines'

    probe.compare([expected], lanes, describe=first)
    probe.finish(frames=len(items), compared=compared, libm=libm, kinds=len({name for name, _ in items}))


if __name__ == '__main__':
    main()
