#!/usr/bin/env python3
"""Compare raylib's WaveFormat with Jonlib's Wave.format_for.

raylib is built with its audio module (miniaudio's ma_convert_frames does the
conversion). Without --uncontracted-control the linked build keeps the host's
contraction (conformance.contraction(): Fused on Darwin arm64, Uncontracted on
Linux x86-64); with it raylib is compiled with -ffp-contract=off and Jonlib
runs M.Uncontracted. At least 20 cases must differ between the two profiles.

Waves of 8-, 16- and 32-bit samples (every input/output format pair), 1 to 8
channels and wider maps (AUX and NONE positions past 8 and 32 channels), equal,
up and down sample rates (44100->48000, 8000->44100, 48000->11025, 2:1, 3:7,
44100->44101, 96000->8000, 48000->300, 1000000->1), tiny waves of 1 to 3
frames, silence (both float zeros), full-scale square waves, noise, sines,
out-of-range and subnormal floats, infinities and NaN go through native
WaveFormat and Wave.format_for on CPU-1, CPU-2 and JavaScript. Every output
field and sample must match, and a wave raylib leaves unchanged (its data
pointer kept) must be InvalidWaveRequest with the wave unchanged.

An independent Python model of the same miniaudio paths (binary32 arithmetic
through exact rounding, libm sin for the filter) classifies Jonlib's
contracts: InvalidWaveData for NaN input samples, NaN produced by f32
arithmetic, int32 overflow in the s16 filter and f32 samples whose s16
conversion depends on SIMD alignment; UnsupportedWaveFormat for chunk
starvation, reduced rates of 2^31 and more, more than 2^24 output samples and
(by construction, 1000000->1 with f32 filtering) uncertified filter
coefficients; InvalidWaveRequest for sample sizes other than 8/16/32 and sample
lists of the wrong length. Its converted waves must equal raylib's on every
case both run. Cases whose native behavior is undefined or huge are not run
natively.
"""
import hashlib
import json
import math
import random
import struct
from fractions import Fraction

from conformance import contraction
import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/wave-format-probe/cases'

# -----------------------------------------------------------------------------
# Binary32 arithmetic


def f32(x):
    try:
        return struct.unpack('<f', struct.pack('<f', x))[0]
    except OverflowError:
        return math.copysign(math.inf, x)


def bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def from_bits(b):
    return struct.unpack('<f', struct.pack('<I', b))[0]


def round32(q):
    """Fraction to the nearest binary32 (ties to even), with gradual underflow."""
    sign = -1.0 if q < 0 else 1.0
    q = abs(q)
    e = q.numerator.bit_length() - q.denominator.bit_length()
    if Fraction(2) ** e > q:
        e -= 1
    quantum = Fraction(2) ** (max(e, -126) - 23)
    m = q / quantum
    whole = m.numerator // m.denominator
    rest = m - whole
    if rest > Fraction(1, 2) or (rest == Fraction(1, 2) and whole % 2):
        whole += 1
    value = whole * quantum
    return sign * math.inf if value >= 2 ** 128 else sign * float(value)


def fma32(a, b, c):
    """fmaf: the product of two floats is exact in binary64; the sum rounds once."""
    if not (math.isfinite(a) and math.isfinite(b) and math.isfinite(c)):
        return f32(a * b + c)
    p = a * b
    s = p + c
    t = s - p
    e = (p - (s - t)) + (c - t)
    if e == 0 or f32(s) == s:
        return f32(s)
    exact = Fraction(p) + Fraction(c)
    return f32(s) if exact == 0 else round32(exact)


# -----------------------------------------------------------------------------
# Model of ma_convert_frames as WaveFormat calls it (miniaudio v0.11.24)

K_U8 = from_bits(1006665857)  # 0.00784313725490196078f


class Refuse(Exception):
    pass


def fmt(size):
    return {8: 'u8', 16: 's16'}.get(size, 'f32')


def s16(v):
    v &= 0xFFFF
    return v - 65536 if v >= 32768 else v


def decode(f, raw):
    return raw if f == 'u8' else s16(raw) if f == 's16' else from_bits(raw)


def encode(f, v):
    return v if f == 'u8' else v & 0xFFFF if f == 's16' else bits(v)


def clip(x):
    return -1.0 if x < -1 else 1.0 if x > 1 else x


def convert(fin, fout, x):
    if fin == fout:
        return x
    if (fin, fout) == ('u8', 's16'):
        return s16((x - 128) << 8)
    if (fin, fout) == ('u8', 'f32'):
        return f32(f32(float(x) * K_U8) - 1.0)
    if (fin, fout) == ('s16', 'u8'):
        return ((x >> 8) + 128) & 0xFF
    if (fin, fout) == ('s16', 'f32'):
        return f32(x * 0.000030517578125)
    if math.isnan(x):
        raise Refuse('data')
    if fout == 'u8':
        return int(f32(f32(clip(f32(x + 0.0)) + 1.0) * 127.5))
    product = f32(f32(x + 0.0) * 32767.0)
    if product <= -32768.0 or product >= 2147483648.0:
        raise Refuse('data')  # the SIMD blocks skip the clip
    return int(f32(clip(f32(x + 0.0)) * 32767.0))


def position(count, index):
    if count == 1:
        return 1
    table = {2: [2, 3], 3: [2, 3, 4], 4: [2, 3, 4, 10], 5: [2, 3, 4, 6, 7], 6: [2, 3, 4, 5, 11, 12],
             7: [2, 3, 4, 5, 10, 11, 12]}.get(count, [2, 3, 4, 5, 6, 7, 11, 12])
    return table[index] if index < 8 else 20 + index - 8 if index < 32 else 0


PLANES = {2: (.5, 0, .5, 0, 0, 0), 3: (0, .5, .5, 0, 0, 0), 4: (0, 0, 1, 0, 0, 0), 6: (.5, 0, 0, .5, 0, 0),
          7: (0, .5, 0, .5, 0, 0), 10: (0, 0, 0, 1, 0, 0), 11: (1, 0, 0, 0, 0, 0), 12: (0, 1, 0, 0, 0, 0)}


def weights(cin, cout):
    """ma_channel_converter_init_preallocated, rectangular mode, default maps."""
    pin = [position(cin, i) for i in range(cin)]
    pout = [position(cout, o) for o in range(cout)]
    w = [[1.0 if pin[i] == pout[o] else 0.0 for o in range(cout)] for i in range(cin)]
    rect = lambda a, b: sum(x * y for x, y in zip(PLANES[a], PLANES[b]))
    for i in range(cin):
        if pin[i] in PLANES and pin[i] not in pout:
            for o in range(cout):
                if pout[o] in PLANES and w[i][o] == 0:
                    w[i][o] = rect(pin[i], pout[o])
    for o in range(cout):
        if pout[o] in PLANES and pout[o] not in pin:
            for i in range(cin):
                if pin[i] in PLANES and w[i][o] == 0:
                    w[i][o] = rect(pin[i], pout[o])
    return w


def channel_frames(mid, cin, cout, frames, fused):
    if cout == 1:
        if mid == 's16':
            return [[s16((sum(frame) % (1 << 32)) // cin)] for frame in frames]
        out = []
        for frame in frames:
            t = 0.0
            for x in frame:
                t = f32(t + x)
            out.append([f32(t / float(cin))])
        return out
    if cin == 1:
        return [frame * cout for frame in frames]
    w = weights(cin, cout)
    out = []
    for frame in frames:
        acc = [0 if mid == 's16' else 0.0] * cout
        for i in range(cin):
            for o in range(cout):
                if mid == 's16':
                    acc[o] = max(-32768, min(32767, acc[o] + ((frame[i] * int(w[i][o] * 4096)) >> 12)))
                else:
                    acc[o] = fma32(frame[i], w[i][o], acc[o]) if fused else f32(acc[o] + f32(frame[i] * w[i][o]))
        out.append(acc)
    return out


def coefficients(rin, rout, mid):
    """ma_lpf2__get_biquad_config for both sections, libm sin (as the host's raylib)."""
    lo, hi = min(rin, rout), max(rin, rout)
    w = 2 * math.pi * (lo * 0.5) / hi
    s, c = math.sin(w), math.sin(math.pi * 0.5 - w)
    sections = []
    for i in (0, 1):
        q = 1 / (2 * math.sin(math.pi * 0.5 - (1 + 2 * i) * (math.pi / 8)))
        a = s / (2 * q)
        b0, b1, a0, a1, a2 = (1 - c) / 2, 1 - c, 1 + a, -2 * c, 1 - a
        norm = [b0 / a0, b1 / a0, b0 / a0, a1 / a0, a2 / a0]
        sections.append([f32(v) for v in norm] if mid == 'f32' else [int(v * 16384) for v in norm])
    return sections


def int32(v):
    if not -(1 << 31) <= v < 1 << 31:
        raise Refuse('data')
    return v


def lowpass(sections, state, frame, mid, fused):
    frame = list(frame)
    for stage, (b0, b1, b2, a1, a2) in enumerate(sections):
        for c, x in enumerate(frame):
            r1, r2 = state[stage][c]
            if mid == 'f32':
                if fused:
                    y = fma32(b0, x, r1)
                    state[stage][c] = [f32(fma32(b1, x, -f32(a1 * y)) + r2), fma32(b2, x, -f32(a2 * y))]
                else:
                    y = f32(f32(b0 * x) + r1)
                    state[stage][c] = [f32(f32(f32(b1 * x) - f32(a1 * y)) + r2), f32(f32(b2 * x) - f32(a2 * y))]
                frame[c] = y
            else:
                y = int32(int32(b0 * x) + r1) >> 14
                state[stage][c] = [int32(int32(int32(b1 * x) - int32(a1 * y)) + r2), int32(int32(b2 * x) - int32(a2 * y))]
                frame[c] = max(-32768, min(32767, y))
    return frame


def resample(mid, channels, rin, rout, frames, expected, fused):
    sections = coefficients(rin, rout, mid)
    zero = 0.0 if mid == 'f32' else 0
    state = [[[zero, zero] for _ in range(channels)] for _ in sections]
    down = rin > rout
    x0, x1 = [zero] * channels, [zero] * channels
    t_int, t_frac, out, i = 1, 0, [], 0
    while len(out) < expected:
        while t_int > 0 and i < len(frames):
            x0, x1 = x1, lowpass(sections, state, frames[i], mid, fused) if down else list(frames[i])
            i += 1
            t_int -= 1
        if t_int > 0:
            break
        if mid == 'f32':
            a = f32(f32(float(t_frac)) / f32(float(rout)))
            y = [f32(p + f32(f32(q - p) * a)) for p, q in zip(x0, x1)]
        else:
            a = ((t_frac << 12) % (1 << 32)) // rout
            y = [s16((p * (4096 - a) + q * a) >> 12) for p, q in zip(x0, x1)]
        out.append(y if down else lowpass(sections, state, y, mid, fused))
        t_int += rin // rout
        t_frac += rin % rout
        if t_frac >= rout:
            t_frac -= rout
            t_int += 1
    if len(out) != expected:
        raise ProbeFailure('wave-format: the model resampler produced fewer frames than expected')
    return out


def model(case, fused):
    """('ok', wave) | ('unchanged',) | ('error', kind)."""
    frames, rate, size, channels, data = case['wave']
    orate, osize, ochannels = case['target']
    if size not in (8, 16, 32) or osize not in (8, 16, 32) or len(data) != frames * channels:
        return ('error', 'request')
    if frames == 0 or channels == 0 or ochannels == 0 or (rate != orate and 0 in (rate, orate)):
        return ('unchanged',)
    fin, fout = fmt(size), fmt(osize)
    has_rs, has_cc = rate != orate, channels != ochannels
    g = math.gcd(rate, orate)
    rin, rout = (rate // g, orate // g) if has_rs else (1, 1)
    if rin >= 1 << 31 or rout >= 1 << 31:
        return ('error', 'unsupported')
    expected = -(-frames * rout // rin)
    if expected * ochannels > 1 << 24:
        return ('error', 'unsupported')
    values = [decode(fin, v) for v in data]
    if not has_rs and not has_cc and fin == fout:
        return ('ok', [frames, orate, osize, ochannels, list(data)])
    if fin == 'f32' and any(math.isnan(v) for v in values):
        return ('error', 'data')
    mid = fout if fout != 'u8' else fin if fin != 'u8' else 'f32'
    try:
        if not has_rs and not has_cc:
            return ('ok', [frames, orate, osize, ochannels, [encode(fout, convert(fin, fout, v)) for v in values]])
        if fin != mid or fout != mid or (has_rs and has_cc):
            cap = 4096 // ((2 if mid == 's16' else 4) * max(channels, ochannels))
            if cap < (rin // rout + 1 if has_rs else 1):
                return ('error', 'unsupported')
        values = [convert(fin, mid, v) for v in values]
        stream = [values[i * channels:(i + 1) * channels] for i in range(frames)]
        if channels >= ochannels:
            stream = channel_frames(mid, channels, ochannels, stream, fused) if has_cc else stream
            stream = resample(mid, ochannels, rin, rout, stream, expected, fused) if has_rs else stream
        else:
            stream = resample(mid, channels, rin, rout, stream, expected, fused) if has_rs else stream
            stream = channel_frames(mid, channels, ochannels, stream, fused)
        flat = [v for frame in stream for v in frame]
        if mid == 'f32' and any(math.isnan(v) for v in flat):
            return ('error', 'data')
        return ('ok', [expected, orate, osize, ochannels, [encode(fout, convert(mid, fout, v)) for v in flat]])
    except Refuse as refusal:
        return ('error', str(refusal))


# -----------------------------------------------------------------------------
# Cases


def signal(kind, frames, channels, size, rng, period=7):
    count = frames * channels
    if size == 8:
        make = {'noise': lambda i: rng.randrange(256), 'square': lambda i: 255 if (i // channels // period) % 2 else 0,
                'silence': lambda i: 128, 'sine': lambda i: 128 + round(100 * math.sin(i * 0.05))}
        return [make[kind](i) for i in range(count)]
    if size == 16:
        make = {'noise': lambda i: rng.randrange(65536), 'square': lambda i: 32767 if (i // channels // period) % 2 else 32768,
                'silence': lambda i: 0, 'sine': lambda i: round(26000 * math.sin(i * 0.031)) & 0xFFFF}
        return [make[kind](i) for i in range(count)]
    specials = [math.inf, -math.inf, 0.0, -0.0, 1e-45, -3e-39, 0.5]
    make = {'noise': lambda i: rng.uniform(-1, 1), 'square': lambda i: 1.0 if (i // channels // period) % 2 else -1.0,
            'silence': lambda i: -0.0 if i % 3 else 0.0, 'sine': lambda i: 0.9 * math.sin(i * 0.043),
            'wild': lambda i: rng.choice([rng.uniform(-3, 3), 1.5, -1.00002, -1.0000305, -1.00003, 100.0, -0.0, 3e38, -3e38]),
            'subnormal': lambda i: rng.choice([1e-45, -1e-45, 3e-45, 2.5e-39, -1.1e-38, 7e-39, 0.25]),
            'special': lambda i: specials[i % len(specials)] if i % 5 else rng.uniform(-1, 1),
            'nan': lambda i: math.nan if i == count // 2 else rng.uniform(-1, 1)}
    return [bits(f32(make[kind](i))) for i in range(count)]


RATES = [(44100, 48000), (48000, 44100), (22050, 22050), (8000, 44100), (44100, 8000), (48000, 11025), (11025, 48000),
         (44100, 22050), (22050, 44100), (3, 7), (7, 3), (96000, 8000), (16000, 16000)]


def case(cases, name, frames, rate, size, channels, data, target, *, native=True, label=None):
    cases.append(dict(id=f'{len(cases):03}-{name}', wave=(frames, rate, size, channels, data), target=target, native=native, label=label))


def cases():
    rng = random.Random(0x3AF0)
    out = []
    sizes = (8, 16, 32)
    # Every format pair with random channels, rates, lengths and signals.
    for size in sizes:
        for osize in sizes:
            for k in range(11):
                rate, orate = RATES[(k * 5 + size + osize) % len(RATES)]
                channels, ochannels = rng.choice([(1, 1), (1, 2), (2, 1), (2, 2), (3, 5), (6, 2), (8, 8), (5, 1), (1, 8), (4, 6), (7, 3)])
                frames = rng.choice([1, 2, 3, 9, 64, 300, 701])
                kind = rng.choice(['noise', 'square', 'silence', 'sine'] + (['wild', 'subnormal'] if size == 32 else []))
                case(out, f'{size}-{osize}-{kind}-{channels}x{rate}-{ochannels}x{orate}', frames, rate, size, channels,
                     signal(kind, frames, channels, size, rng, period=1 + k % 9), (orate, osize, ochannels))
    # Tiny waves at odd ratios.
    for frames in (1, 2, 3):
        for rate, orate in ((8000, 44100), (48000, 11025), (44100, 48000), (1, 2), (2, 1), (7, 3)):
            for size, osize in ((16, 16), (32, 32), (8, 32), (32, 8)):
                case(out, f'tiny-{frames}-{rate}-{orate}-{size}-{osize}', frames, rate, size, 2,
                     signal('noise', frames, 2, size, rng), (orate, osize, 2 if frames % 2 else 1))
    # Full-scale square waves through every filter format; near-equal rates
    # overflow the s16 filter's int32 arithmetic.
    for size in sizes:
        for rate, orate in ((44100, 48000), (48000, 44100), (44100, 44101), (44101, 44100), (8000, 44100)):
            for period in (1, 3):
                case(out, f'square-{size}-{rate}-{orate}-{period}', 400, rate, size, 1, signal('square', 400, 1, size, rng, period),
                     (orate, size, 1))
    # Wide channel maps: AUX positions from 8 and NONE from 32 channels.
    for channels, ochannels in ((10, 3), (3, 12), (40, 36), (36, 40), (9, 1), (1, 33)):
        for size in (16, 32, 8):
            case(out, f'wide-{channels}-{ochannels}-{size}', 5, 22050, size, channels, signal('noise', 5, channels, size, rng),
                 (22050 if size != 8 else 16000, size, ochannels))
    # Large ratios: 96000->8000 (12:1); 48000->300 starves the 4096-byte
    # chunks with 8 f32 channels but not with one; 1000000->1 skips the chunks
    # (same format and channels) and its f32 filter is not certified.
    for size, osize, channels in ((32, 8, 8), (32, 8, 1), (16, 8, 8), (16, 16, 2), (32, 32, 8)):
        case(out, f'ratio-160-{size}-{osize}-{channels}', 500, 48000, size, channels, signal('sine', 500, channels, size, rng), (300, osize, channels))
    case(out, 'ratio-12-f32', 600, 96000, 32, 2, signal('noise', 600, 2, 32, rng), (8000, 32, 2))
    case(out, 'million-s16', 3, 1000000, 16, 1, signal('noise', 3, 1, 16, rng), (1, 16, 1))
    case(out, 'million-f32', 3, 1000000, 32, 1, signal('noise', 3, 1, 32, rng), (1, 32, 1), label='uncertified')
    case(out, 'million-f32-up', 1, 1, 32, 1, signal('noise', 1, 1, 32, rng), (2, 32, 1))
    # Floats: out of range, infinities, NaN, subnormals (fused and unfused
    # channel mixing differ on inexact subnormal products).
    for kind in ('wild', 'special', 'nan', 'subnormal'):
        for target in ((44100, 32, 2), (44100, 16, 2), (44100, 8, 2), (48000, 32, 2), (48000, 8, 3), (44100, 32, 5), (44100, 32, 1), (22050, 32, 2)):
            case(out, f'float-{kind}-{target[0]}-{target[1]}-{target[2]}', 37, 44100, 32, 2, signal(kind, 37, 2, 32, rng), target)
    for target in ((44100, 32, 5), (44100, 32, 4), (44100, 32, 1)):
        case(out, f'subnormal-mix-3-{target[2]}', 50, 44100, 32, 3, signal('subnormal', 50, 3, 32, rng), target)
    # raylib leaves these unchanged (ma_convert_frames returns 0).
    case(out, 'no-frames', 0, 44100, 16, 2, [], (48000, 16, 2))
    case(out, 'zero-channels-out', 4, 44100, 16, 1, signal('noise', 4, 1, 16, rng), (44100, 16, 0))
    case(out, 'zero-channels-in', 4, 44100, 16, 0, [], (48000, 16, 2))
    case(out, 'zero-rate-out', 4, 44100, 32, 1, signal('noise', 4, 1, 32, rng), (0, 32, 1))
    case(out, 'zero-rate-in', 4, 0, 8, 1, signal('noise', 4, 1, 8, rng), (8000, 8, 1))
    case(out, 'zero-rates', 4, 0, 16, 1, signal('noise', 4, 1, 16, rng), (0, 8, 1))
    case(out, 'passthrough-nan', 4, 8000, 32, 2, signal('nan', 4, 2, 32, rng), (8000, 32, 2))
    # Jonlib contracts, not run natively: wrong sample widths (raylib reads or
    # allocates with another width), wrong sample counts, huge rates and outputs.
    case(out, 'size-24', 4, 8000, 24, 1, [1, 2, 3, 4], (8000, 16, 1), native=False)
    case(out, 'target-size-12', 4, 8000, 16, 1, [1, 2, 3, 4], (8000, 12, 1), native=False)
    case(out, 'short-data', 4, 8000, 16, 2, [1, 2, 3], (16000, 16, 2), native=False)
    case(out, 'rate-2^31', 4, 44100, 16, 1, [1, 2, 3, 4], (2147483659, 16, 1), native=False)
    case(out, 'output-2^25', 2, 1, 8, 1, [0, 255], (1 << 24, 8, 1), native=False)
    return out


# -----------------------------------------------------------------------------
# Native and candidate programs

NATIVE = r'''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned rd(FILE *f) { unsigned v = 0; if (fread(&v, 4, 1, f) != 1) exit(3); return v; }
int main(void) {
    SetTraceLogLevel(LOG_NONE);
    FILE *f = fopen("PATH", "rb");
    if (!f) return 2;
    unsigned count = rd(f);
    for (unsigned k = 0; k < count; k++) {
        unsigned frames = rd(f), rate = rd(f), size = rd(f), channels = rd(f);
        int orate = (int)rd(f), osize = (int)rd(f), ochannels = (int)rd(f);
        unsigned bytes = rd(f);
        void *data = malloc(bytes ? bytes : 1);
        if (bytes && fread(data, 1, bytes, f) != bytes) return 4;
        Wave w = { frames, rate, size, channels, data };
        WaveFormat(&w, orate, osize, ochannels);
        printf("[%d,%u,%u,%u,%u,[", w.data != data, w.frameCount, w.sampleRate, w.sampleSize, w.channels);
        unsigned n = w.frameCount * w.channels;
        for (unsigned i = 0; i < n; i++) {
            unsigned v = w.sampleSize == 8 ? ((unsigned char *)w.data)[i] : w.sampleSize == 16 ? ((unsigned short *)w.data)[i] : ((unsigned *)w.data)[i];
            printf("%s%u", i ? "," : "", v);
        }
        puts("]]");
        free(w.data);
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def words(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: Con{(a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), words(rest)}
    case _: Nil{}
def fields(+w: J.Wave) -> String:
  J.Wave{frames, rate, size, channels, data} = w
  U32.show(frames) ++ "," ++ U32.show(rate) ++ "," ++ U32.show(size) ++ "," ++ U32.show(channels) ++ "," ++ List.show(~&2, ~U32, ~U32.show, data) ++ "]"
def kind(e: J.Wave.Error) -> String:
  match e:
    case J.InvalidWaveRequest{}: "request"
    case J.InvalidWaveData{}: "data"
    case J.UnsupportedWaveFormat{}: "unsupported"
    case _: "other"
def row(r: Result<&1, &1, J.Wave & J.Wave.Error, J.Wave>) -> String:
  match r:
    case Done{w}: "[\\"ok\\"," ++ fields(w)
    case Fail{Tuple{w, e}}: "[\\"error\\",\\"" ++ kind(e) ++ "\\"," ++ fields(w)
def run(+frames: U32, +rate: U32, +size: U32, +channels: U32, +orate: U32, +osize: U32, +ochannels: U32, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{bytes}: IO.print(row(J.Wave.format_for(M.PROFILE{}, J.Wave{frames, rate, size, channels, words(bytes)}, orate, osize, ochannels)))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def u32(value):
    return int(value) & 0xFFFFFFFF


def native_rows(probe, items):
    blob = bytearray(struct.pack('<I', len(items)))
    for item in items:
        frames, rate, size, channels, data = item['wave']
        raw = b''.join(struct.pack({8: '<B', 16: '<H'}.get(size, '<I'), v) for v in data)
        blob += struct.pack('<8I', frames, rate, size, channels, *map(u32, item['target']), len(raw)) + raw
    path = ROOT / WORK / 'native.bin'
    path.write_bytes(bytes(blob))
    text = probe.native(NATIVE.replace('PATH', str(path)), 'reference')
    rows = [json.loads(line) for line in text.splitlines()]
    if len(rows) != len(items):
        raise ProbeFailure('wave-format: incomplete native output')
    return rows


def main():
    def configure(parser):
        parser.add_argument('--uncontracted-control', action='store_true',
                            help='build raylib with -ffp-contract=off and run M.Uncontracted')
    args = probekit.arguments(__doc__, configure)
    options = ('SUPPORT_MODULE_RAUDIO=ON',) + (('CMAKE_C_FLAGS=-ffp-contract=off',) if args.uncontracted_control else ())
    name = 'wave-format' + ('-uncontracted' if args.uncontracted_control else '')
    probe = probekit.Probe(name, args, raylib_options=options)
    profile = 'Uncontracted' if args.uncontracted_control else contraction()
    fused = profile == 'Fused'
    (ROOT / WORK).mkdir(parents=True, exist_ok=True)
    items = cases()
    for item in items:
        item['path'] = f'{WORK}/{item["id"]}.bin'
        (ROOT / item['path']).write_bytes(b''.join(struct.pack('<I', v) for v in item['wave'][4]))
    ran = [item for item in items if item['native']]
    natives = dict(zip((item['id'] for item in ran), native_rows(probe, ran)))
    expected, tally = [], {}
    for item in items:
        frames, rate, size, channels, data = item['wave']
        unchanged = [frames, rate, size, channels, list(data)]
        outcome = model(item, fused)
        if item['native']:
            changed, *wave = natives[item['id']]
            if outcome[0] == 'unchanged' and (changed or wave != unchanged):
                raise ProbeFailure(f'wave-format: raylib changed {item["id"]}, the model expects it unchanged')
            if outcome[0] == 'ok' and (not changed or wave != outcome[1]):
                raise ProbeFailure(f'wave-format: the model disagrees with raylib on {item["id"]}')
        if outcome[0] == 'ok' and item['label'] == 'uncertified':
            outcome = ('error', 'unsupported')
        key = outcome[0] if outcome[0] != 'error' else outcome[1]
        tally[key] = tally.get(key, 0) + 1
        if outcome[0] == 'ok':
            expected.append(['ok', *outcome[1]])
        else:
            expected.append(['error', 'request' if outcome[0] == 'unchanged' else outcome[1], *unchanged])
    if tally.get('ok', 0) < 150 or min(tally.get(k, 0) for k in ('unchanged', 'request', 'data', 'unsupported')) < 3:
        raise ProbeFailure(f'wave-format: unexpected outcome mix {tally}')
    # The corpus must tell the contraction profiles apart (f32 filters and mixing).
    sensitive = sum(model(item, True) != model(item, False) for item in items)
    if sensitive < 20:
        raise ProbeFailure(f'wave-format: only {sensitive} cases depend on the contraction profile')
    program = PROGRAM.replace('PROFILE', profile)

    def render(selected, gpu):
        body = program
        for item in selected:
            frames, rate, size, channels, _ = item['wave']
            orate, osize, ochannels = map(u32, item['target'])
            body += (f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data("{item["path"]}"), '
                     f'run({frames}, {rate}, {size}, {channels}, {orate}, {osize}, {ochannels}))\n')
        return body + '    IO.print("\\"done\\"")\n'

    def parse(text, selected):
        rows = [json.loads(line) for line in text.splitlines()]
        if rows[-1:] != ['done'] or len(rows) != len(selected) + 1:
            raise ProbeFailure('wave-format: candidate output did not finish')
        return rows[:-1]

    lanes = probe.candidates(render, items, batch=24, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: items[i]['id'])
    digest = hashlib.sha256(json.dumps([[item['wave'], item['target']] for item in items]).encode()).hexdigest()
    probe.finish(reference='linked raylib' + (' (-ffp-contract=off)' if args.uncontracted_control else ''), profile=profile,
                 cases=len(items), native=len(ran), outcomes=tally, profile_sensitive=sensitive, inputs_sha256=digest)


if __name__ == '__main__':
    main()
