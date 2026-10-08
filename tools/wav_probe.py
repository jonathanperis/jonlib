#!/usr/bin/env python3
"""Compare raylib's WAV loading and Wave utilities with Jonlib's Wave.

raylib is built with its audio module. Generated files cover every container
dr_wav detects and every codec drwav_read_pcm_frames_s16 converts:

- RIFF: PCM 8, 12 (in 16-bit containers), 16, 20, 24, 32, 40 and 64-bit
  samples, 1/2/6 channels, 32- and 64-bit float (clamped, in range, infinite,
  subnormal, values next to the rounding boundaries of (c + 1) * 32767.5),
  float widths dr_wav silences, a-law and mu-law, WAVE_FORMAT_EXTENSIBLE
  headers, LIST/fact chunks with odd padding, short and extended "fmt "
  chunks, a "fmt " seek that moves the 64-bit cursor past 4 GiB, frames over
  dr_wav's 4096-byte read buffer, data sizes past the end of the file or not a
  whole number of frames, empty data and malformed headers;
- RIFX (big-endian): every PCM width, float, companded and extensible data;
- Wave64: GUID chunks, 64-bit and wrapping sizes, dr_wav's size-modulo-8
  padding, fact counts (including above 2^32), bad GUIDs and sizes;
- RF64: ds64 sizes and sample counts (zero, smaller, larger, odd chunks,
  short or missing ds64, a wrong RIFF size);
- AIFF/AIFC: COMM chunks with integral, fractional, huge, unnormalized,
  negative and special 80-bit rates, frame counts above and below the data,
  SSND offsets, odd chunks, repeated COMM chunks, NONE/raw /sowt/fl32/fl64/
  alaw/ulaw (both cases), ima4 and unknown compression, 4- to 64-bit samples;
- MS and IMA ADPCM: mono and stereo, partial final blocks and headers, bad
  predictors and step indices, negative header deltas, small and uneven block
  alignments, more than two channels, fact-chunk counts in Wave64 and RF64.

For each file the native program first runs dr_wav itself (drwav_init_memory,
then drwav_read_pcm_frames_s16 of (unsigned int)totalPCMFrameCount frames):
when dr_wav reads fewer frames, LoadWave would return uninitialized samples
and Jonlib must answer InvalidWaveData; otherwise LoadWave must give the same
frame count, sample rate, sample size, channels and every 16-bit sample, or
fail on both sides. Jonlib contracts not run natively (InvalidWaveData): NaN
float samples (an undefined float-to-int conversion), MS ADPCM samples whose
int arithmetic overflows, an 80-bit rate of -2^63 (negating INT64_MIN), AIFF
channel and bit counts whose int product overflows, byte swaps of 5-7 or 9+
byte samples in big-endian containers (dr_wav's assertion fails) and a chunk
walk that never ends. IsWaveValid, WaveCopy, WaveCrop, LoadWaveSamples and
ExportWave (.wav, .raw) and ExportWaveAsCode on 8-, 16- and 32-bit waves are
compared too. CPU/JS.
"""
import hashlib
import json
import math
import random
import struct
from fractions import Fraction

import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/wav-probe/cases'

# -----------------------------------------------------------------------------
# Writers


def chunk(name, body, size=None, be=False):
    data = name + struct.pack('>I' if be else '<I', len(body) if size is None else size) + body
    return data + (b'\0' if len(body) % 2 else b'')


def fmt(tag, channels, rate, bits, align=None, extra=b'', be=False):
    align = channels * bits // 8 if align is None else align
    return struct.pack('>HHIIHH' if be else '<HHIIHH', tag, channels, rate, rate * align & 0xFFFFFFFF, align, bits) + extra


def riff(*chunks, container=b'RIFF', size=None):
    body = b'WAVE' + b''.join(chunks)
    return container + struct.pack('<I', len(body) if size is None else size) + body


def rifx(*chunks):
    body = b'WAVE' + b''.join(chunks)
    return b'RIFX' + struct.pack('>I', len(body)) + body


def extensible(sub, valid, channels, rate, bits, be=False, align=None):
    guid = struct.pack('>H' if be else '<H', sub) + bytes([0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71])
    return fmt(0xFFFE, channels, rate, bits, align=align, extra=struct.pack('>HHI' if be else '<HHI', 22, valid, 3) + guid, be=be)


TAIL = bytes([0xF3, 0xAC, 0xD3, 0x11, 0x8C, 0xD1, 0x00, 0xC0, 0x4F, 0x8E, 0xDB, 0x8A])
W64_RIFF = b'riff' + bytes([0x2E, 0x91, 0xCF, 0x11, 0xA5, 0xD6, 0x28, 0xDB, 0x04, 0xC1, 0x00, 0x00])


def w64_chunk(name, body, size=None, pad=None):
    """A Wave64 chunk; `pad` defaults to 8-byte alignment as writers do."""
    head = (name + TAIL if len(name) == 4 else name) + struct.pack('<Q', len(body) + 24 if size is None else size)
    return head + body + b'\0' * ((-len(body)) % 8 if pad is None else pad)


def w64(*chunks, size=None, guid=W64_RIFF, wave=b'wave' + TAIL):
    body = b''.join(chunks)
    return guid + struct.pack('<Q', 40 + len(body) if size is None else size) + wave + body


def ds64(data_size, samples, extra=b'', size=None, riff_size=0):
    body = struct.pack('<QQQ', riff_size, data_size, samples) + extra
    return chunk(b'ds64', body, size=size)


def rf64(*chunks, size=0xFFFFFFFF):
    return b'RF64' + struct.pack('<I', size) + b'WAVE' + b''.join(chunks)


def ext80(value):
    """An 80-bit extended number (exact for the values used here)."""
    value = Fraction(value)
    if value == 0:
        return bytes(10)
    sign = 0x8000 if value < 0 else 0
    value = abs(value)
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    while Fraction(2) ** exponent > value:
        exponent -= 1
    while Fraction(2) ** (exponent + 1) <= value:
        exponent += 1
    significand = int(value / Fraction(2) ** exponent * 2 ** 63)
    return struct.pack('>HQ', sign | (exponent + 16383), significand)


def ext80_raw(sign, exponent, significand):
    return struct.pack('>HQ', (0x8000 if sign else 0) | exponent, significand)


def comm(channels, frames, bits, rate, compression=None, size=None, extra=b''):
    rate = rate if isinstance(rate, bytes) else ext80(rate)
    body = struct.pack('>HIH', channels, frames, bits) + rate + (b'' if compression is None else compression + extra)
    return chunk(b'COMM', body, size=size, be=True)


def ssnd(data, offset=0, lead=b'', size=None):
    return chunk(b'SSND', struct.pack('>II', offset, 0) + lead + data, size=size, be=True)


def aiff(*chunks, form=b'AIFF', size=None):
    body = form + b''.join(chunks)
    return b'FORM' + struct.pack('>I', len(body) if size is None else size) + body


# -----------------------------------------------------------------------------
# MS ADPCM model (dr_wav's decoder): used only to generate nibbles that keep
# the int arithmetic in range, and to construct the overflowing contract case.

ADAPT = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]
COEFF1 = [256, 512, 0, 192, 240, 460, 392]
COEFF2 = [0, -256, 0, 64, 0, -208, -232]


class MsChannel:
    def __init__(self, predictor, delta, sample1, sample2):
        self.predictor, self.delta, self.x1, self.x0 = predictor, delta, sample1, sample2
        self.overflow = False

    def nibble(self, nibble):
        n = nibble - 16 if nibble & 8 else nibble
        base = (self.x1 * COEFF1[self.predictor] + self.x0 * COEFF2[self.predictor]) >> 8
        product = n * self.delta
        total = base + product
        if not (-2 ** 31 <= product < 2 ** 31 and -2 ** 31 <= total < 2 ** 31):
            self.overflow = True
        sample = max(-32768, min(32767, total))
        self.delta = max(16, min(0x7FFFFFFF, (ADAPT[nibble] * self.delta) >> 8))
        self.x0, self.x1 = self.x1, sample

    def choose(self, rng):
        return rng.choice([0, 1, 2, 3, 13, 14, 15]) if self.delta > 4096 else rng.randrange(16)


def ms_block(rng, channels, align, length=None, states=None):
    """One MS ADPCM block (`length` bytes, default `align`) with bounded deltas."""
    length = align if length is None else length
    states = states or [MsChannel(rng.randrange(7), rng.randrange(16, 600), rng.randrange(-3000, 3000), rng.randrange(-3000, 3000))
                        for _ in range(channels)]
    if channels == 1:
        s = states[0]
        head = struct.pack('<Bhhh', s.predictor, s.delta, s.x1, s.x0)
    else:
        a, b = states
        head = struct.pack('<BBhhhhhh', a.predictor, b.predictor, a.delta, b.delta, a.x1, b.x1, a.x0, b.x0)
    body = bytearray()
    while len(head) + len(body) < align:
        if channels == 1:
            n0 = states[0].choose(rng)
            states[0].nibble(n0)
            n1 = states[0].choose(rng)
            states[0].nibble(n1)
        else:
            n0 = states[0].choose(rng)
            states[0].nibble(n0)
            n1 = states[1].choose(rng)
            states[1].nibble(n1)
        body.append(n0 << 4 | n1)
    if any(s.overflow for s in states):
        raise ProbeFailure('wav: generated MS ADPCM block overflows')
    return (head + bytes(body))[:length]


def ms_fmt(channels, align, rate=22050, be=False):
    frames = max(0, (align - 7 * channels) * 2 // channels + 2)
    coefficients = struct.pack('<14h', 256, 0, 512, -256, 0, 0, 192, 64, 240, 0, 460, -208, 392, -232)
    return fmt(2, channels, rate, 4, align=align, extra=struct.pack('<HHH', 32, frames, 7) + coefficients, be=be)


def ima_fmt(channels, align, rate=22050):
    frames = (align - 4 * channels) * 8 // (4 * channels) + 1
    return fmt(0x11, channels, rate, 4, align=align, extra=struct.pack('<HH', 2, frames))


def ima_block(rng, channels, align, length=None, steps=None):
    length = align if length is None else length
    head = b''.join(struct.pack('<hBB', rng.randrange(-20000, 20000), rng.randrange(89) if steps is None else steps[c], 0)
                    for c in range(channels))
    return (head + bytes(rng.randrange(256) for _ in range(align - len(head))))[:length]


def f64s(values, be=False):
    return struct.pack(('>' if be else '<') + f'{len(values)}d', *values)


def cases():
    rng = random.Random(0x3A7)
    noise = lambda n: bytes(rng.randrange(256) for _ in range(n))
    out = []

    def add(name, data, kind='native'):
        out.append(dict(id=name, bytes=data, kind=kind))

    # RIFF PCM, float, companded and header cases.
    for bits, channels in ((8, 1), (8, 2), (16, 1), (16, 2), (24, 2), (32, 1), (40, 1), (16, 6), (64, 1)):
        frames = 7
        add(f'pcm{bits}-{channels}ch', riff(chunk(b'fmt ', fmt(1, channels, 22050, bits)), chunk(b'data', noise(frames * channels * bits // 8))))
    add('pcm12-in-16', riff(chunk(b'fmt ', fmt(1, 2, 8000, 12, align=4)), chunk(b'data', noise(20))))
    add('pcm20-in-24', riff(chunk(b'fmt ', fmt(1, 1, 8000, 20, align=3)), chunk(b'data', noise(15))))
    add('pcm12-frame-4096', riff(chunk(b'fmt ', fmt(1, 1, 8000, 12, align=4096)), chunk(b'data', noise(8192))))
    add('pcm12-frame-4098', riff(chunk(b'fmt ', fmt(1, 2, 8000, 12, align=4098)), chunk(b'data', noise(8196))))
    floats = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -2.0, 0.999999, -0.999999, 1e-7, -1e-7, 0.25, 3.0e38, -math.inf, math.inf,
              0.3333333, -0.7777777]
    add('float32', riff(chunk(b'fmt ', fmt(3, 2, 48000, 32)), chunk(b'data', struct.pack('<18f', *floats))))
    add('float32-random', riff(chunk(b'fmt ', fmt(3, 1, 44100, 32)), chunk(b'data', struct.pack('<64f', *[rng.uniform(-1.2, 1.2) for _ in range(64)]))))
    doubles = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -2.0, math.inf, -math.inf, 1e300, -1e300, 0.999999999999, -0.999999999999,
               -1 + 2 ** -53, 1 - 2 ** -53, -1 + 2 ** -52, 2 ** -53, -(2 ** -53), 2 ** -54, -(2 ** -54), 2 ** -60, -(2 ** -60),
               5e-324, -5e-324, 1e-310, 2 ** -899, -(2 ** -899), 2 ** -901, -(2 ** -901), 1 / 3, -2 / 3, 1e-5, -1e-5,
               1 + 2 ** -52, -1 - 2 ** -52, 2.0 ** 1023, 1.0 / 65535, -1.0 / 65535]
    doubles += [n / 32767.5 - 1 for n in (1, 2, 3, 32767, 32768, 32769, 65533, 65534, 65535)]
    doubles += [math.nextafter(n / 32767.5 - 1, d) for n in (1, 100, 12345, 32768, 40000, 65534) for d in (-2, 2)]
    add('float64', riff(chunk(b'fmt ', fmt(3, 1, 8000, 64)), chunk(b'data', f64s(doubles))))
    add('float64-random', riff(chunk(b'fmt ', fmt(3, 2, 44100, 64)), chunk(b'data', f64s([rng.uniform(-1.3, 1.3) for _ in range(40)]))))
    add('float64-extensible', riff(chunk(b'fmt ', extensible(3, 64, 1, 44100, 64)), chunk(b'data', f64s([0.1, -0.2, 0.75, -1.25]))))
    add('float16-silence', riff(chunk(b'fmt ', fmt(3, 1, 8000, 16)), chunk(b'data', noise(10))))
    add('float24-silence', riff(chunk(b'fmt ', fmt(3, 2, 8000, 24)), chunk(b'data', noise(18))))
    add('alaw', riff(chunk(b'fmt ', fmt(6, 2, 8000, 8)), chunk(b'data', bytes(range(256)))))
    add('mulaw', riff(chunk(b'fmt ', fmt(7, 1, 8000, 8)), chunk(b'data', bytes(range(256)))))
    add('alaw-16bit-frame', riff(chunk(b'fmt ', fmt(6, 1, 8000, 16)), chunk(b'data', noise(8))))
    add('extensible-pcm24', riff(chunk(b'fmt ', extensible(1, 24, 2, 44100, 24)), chunk(b'data', noise(36))))
    add('extensible-float', riff(chunk(b'fmt ', extensible(3, 32, 1, 44100, 32)), chunk(b'data', struct.pack('<4f', 0.1, -0.2, 0.3, 2.0))))
    add('extensible-bad-size', riff(chunk(b'fmt ', fmt(0xFFFE, 1, 8000, 16, extra=struct.pack('<H', 10) + noise(10))), chunk(b'data', noise(8))))
    add('fmt-cbsize-zero', riff(chunk(b'fmt ', fmt(1, 1, 8000, 16, extra=struct.pack('<H', 0))), chunk(b'data', noise(10))))
    add('fmt-extra-bytes', riff(chunk(b'fmt ', fmt(1, 1, 8000, 16, extra=struct.pack('<H', 3) + noise(3))), chunk(b'data', noise(10))))
    add('list-and-fact', riff(chunk(b'LIST', b'INFOISFT' + struct.pack('<I', 3) + b'ab\0'), chunk(b'fmt ', fmt(1, 1, 11025, 16)),
                              chunk(b'fact', struct.pack('<I', 5)), chunk(b'junk', noise(5)), chunk(b'data', noise(10))))
    add('data-past-end', riff(chunk(b'fmt ', fmt(1, 2, 8000, 16)), chunk(b'data', noise(17), size=1000))[:-1])
    add('data-partial-frame', riff(chunk(b'fmt ', fmt(1, 2, 8000, 16)), chunk(b'data', noise(11))))
    add('data-empty', riff(chunk(b'fmt ', fmt(1, 1, 8000, 16)), chunk(b'data', b'')))
    add('fmt-short-14', riff(chunk(b'fmt ', fmt(1, 1, 8000, 16)[:14]), chunk(b'data', noise(12))))
    add('no-fmt', riff(chunk(b'data', noise(8))))
    add('no-data', riff(chunk(b'fmt ', fmt(1, 1, 8000, 16))))
    add('rate-zero', riff(chunk(b'fmt ', fmt(1, 1, 0, 16)), chunk(b'data', noise(8))))
    add('bits-72', riff(chunk(b'fmt ', fmt(1, 1, 8000, 72)), chunk(b'data', noise(18))))
    add('not-wave', b'RIFF' + struct.pack('<I', 4) + b'AVI ')
    add('tiny', b'RIF')
    add('float32-nan', riff(chunk(b'fmt ', fmt(3, 1, 8000, 32)), chunk(b'data', struct.pack('<3f', 0.5, math.nan, 0.25))), 'data')
    add('float64-nan', riff(chunk(b'fmt ', fmt(3, 1, 8000, 64)), chunk(b'data', f64s([0.5, -math.nan, 0.25]))), 'data')
    add('mp3-tag', riff(chunk(b'fmt ', fmt(0x55, 1, 8000, 16)), chunk(b'data', noise(8))))
    # A "fmt " chunk whose int seek goes back into a preceding chunk's fake
    # "data" header while dr_wav's 64-bit cursor passes 4 GiB, and one whose
    # seek lands on itself forever.
    fake = b'data' + struct.pack('<I', 8) + noise(8)
    back = 24
    add('fmt-seek-cursor-4g', riff(chunk(b'junk', fake), chunk(b'fmt ', fmt(1, 1, 8000, 16, extra=struct.pack('<H', 0)), size=2 ** 32 - back),
                                   chunk(b'data', noise(8))))
    add('fmt-seek-endless', riff(chunk(b'fmt ', fmt(1, 1, 8000, 16, extra=struct.pack('<H', 0)), size=2 ** 32 - 8), chunk(b'data', noise(8))), 'data')

    # RIFX: big-endian sizes, fields and samples.
    for bits, channels in ((8, 1), (16, 2), (24, 1), (32, 2), (64, 1)):
        add(f'rifx-pcm{bits}-{channels}ch', rifx(chunk(b'fmt ', fmt(1, channels, 16000, bits, be=True), be=True),
                                                 chunk(b'data', noise(5 * channels * bits // 8), be=True)))
    add('rifx-pcm12-in-16', rifx(chunk(b'fmt ', fmt(1, 1, 8000, 12, align=2, be=True), be=True), chunk(b'data', noise(12), be=True)))
    add('rifx-float32', rifx(chunk(b'fmt ', fmt(3, 1, 8000, 32, be=True), be=True), chunk(b'data', struct.pack('>6f', 0.5, -0.25, 1.5, -3.0, 0.125, 1e-9), be=True)))
    add('rifx-float64', rifx(chunk(b'fmt ', fmt(3, 2, 8000, 64, be=True), be=True), chunk(b'data', f64s([0.5, -0.25, 1.5, -3.0, 2 ** -60, -1 + 2 ** -53], True), be=True)))
    add('rifx-alaw', rifx(chunk(b'fmt ', fmt(6, 1, 8000, 8, be=True), be=True), chunk(b'data', bytes(range(0, 256, 3)), be=True)))
    add('rifx-mulaw', rifx(chunk(b'fmt ', fmt(7, 2, 8000, 8, be=True), be=True), chunk(b'data', bytes(range(1, 256, 5)), be=True)))
    add('rifx-extensible', rifx(chunk(b'fmt ', extensible(1, 24, 2, 44100, 24, be=True), be=True), chunk(b'data', noise(24), be=True)))
    add('rifx-fact-list', rifx(chunk(b'fact', struct.pack('>I', 3), be=True), chunk(b'LIST', noise(5), be=True),
                               chunk(b'fmt ', fmt(1, 1, 8000, 16, extra=struct.pack('>H', 2) + noise(2), be=True), be=True), chunk(b'data', noise(9), be=True)))
    add('rifx-le-sizes', rifx(chunk(b'fmt ', fmt(1, 1, 8000, 16, be=True)), chunk(b'data', noise(8))))
    add('rifx-pcm40', rifx(chunk(b'fmt ', fmt(1, 1, 8000, 40, be=True), be=True), chunk(b'data', noise(15), be=True)), 'data')

    # Wave64.
    w_fmt = lambda tag, channels, rate, bits, **k: w64_chunk(b'fmt ', fmt(tag, channels, rate, bits, **k))
    add('w64-pcm16', w64(w_fmt(1, 2, 22050, 16), w64_chunk(b'data', noise(40))))
    add('w64-pcm24-odd', w64(w_fmt(1, 1, 22050, 24), w64_chunk(b'data', noise(21))))
    add('w64-float64', w64(w_fmt(3, 1, 8000, 64), w64_chunk(b'data', f64s([0.75, -0.5, 1e-200, -1.5, 0.1]))))
    add('w64-extensible', w64(w64_chunk(b'fmt ', extensible(1, 16, 1, 8000, 16)), w64_chunk(b'data', noise(12))))
    add('w64-junk-aligned', w64(w64_chunk(b'junk', noise(12)), w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(10))))
    add('w64-junk-6', w64(w64_chunk(b'junk', noise(6)), w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(10))))
    add('w64-junk-6-dr-padding', w64(w64_chunk(b'junk', noise(6), pad=6), w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(10))))
    add('w64-size-23', w64(w64_chunk(b'junk', noise(6), size=23, pad=0), w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(10))))
    add('w64-size-10', w64(w64_chunk(b'junk', b'', size=10, pad=0), w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(10))))
    add('w64-fact-smaller', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'fact', struct.pack('<Q', 3)), w64_chunk(b'data', noise(16))))
    add('w64-fact-larger', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'fact', struct.pack('<Q', 30)), w64_chunk(b'data', noise(16))))
    add('w64-fact-2pow32', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'fact', struct.pack('<Q', 2 ** 32 + 4)), w64_chunk(b'data', noise(16))))
    add('w64-fact-short', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'fact', b'', size=24, pad=0)) + b'\1\2\3')
    add('w64-data-size-0', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(12), size=0)))
    add('w64-data-size-huge', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(12), size=2 ** 40)))
    add('w64-fmt-cursor-4g', w64(w64_chunk(b'fmt ', fmt(1, 1, 8000, 16, extra=struct.pack('<H', 0)), size=2 ** 32 + 18 + 24, pad=2), w64_chunk(b'data', noise(8))))
    add('w64-bad-riff-guid', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(8)), guid=W64_RIFF[:15] + b'\1'))
    add('w64-bad-wave-guid', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(8)), wave=b'wave' + TAIL[:11] + b'\0'))
    add('w64-size-79', w64(w_fmt(1, 1, 8000, 16), w64_chunk(b'data', noise(8)), size=79))
    add('w64-riff-guid-only', W64_RIFF[:10])
    add('w64-bad-chunk-guid', w64(w64_chunk(b'fmt ' + TAIL[:11] + b'\0', fmt(1, 1, 8000, 16)), w_fmt(1, 1, 8000, 8), w64_chunk(b'data', noise(8))))
    w_ms = ms_block(rng, 1, 64) + ms_block(rng, 1, 64, 30)
    add('w64-msadpcm-fact', w64(w64_chunk(b'fmt ', ms_fmt(1, 64), pad=2), w64_chunk(b'fact', struct.pack('<Q', 150)), w64_chunk(b'data', w_ms)))
    add('w64-msadpcm-fact-large', w64(w64_chunk(b'fmt ', ms_fmt(1, 64), pad=2), w64_chunk(b'fact', struct.pack('<Q', 2 ** 32 + 100)), w64_chunk(b'data', w_ms)))

    # RF64.
    pcm = noise(24)
    rf_fmt = chunk(b'fmt ', fmt(1, 2, 32000, 16))
    add('rf64-pcm16', rf64(ds64(24, 6, struct.pack('<I', 0)), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    add('rf64-count-zero', rf64(ds64(24, 0), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    add('rf64-count-smaller', rf64(ds64(24, 2), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    add('rf64-count-larger', rf64(ds64(24, 50), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    add('rf64-size-past-end', rf64(ds64(2 ** 33, 0), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    add('rf64-size-smaller', rf64(ds64(9, 0), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    add('rf64-ds64-odd', rf64(ds64(24, 0, b'\7'), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    add('rf64-ds64-short-size', rf64(ds64(24, 0, size=20), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    add('rf64-ds64-truncated', rf64(chunk(b'ds64', struct.pack('<QQ', 0, 24), size=28)))
    add('rf64-no-ds64', rf64(rf_fmt, chunk(b'data', pcm)))
    add('rf64-riff-size', rf64(ds64(24, 0), rf_fmt, chunk(b'data', pcm), size=1000))
    add('rf64-fact', rf64(ds64(24, 0), chunk(b'fact', struct.pack('<I', 2)), rf_fmt, chunk(b'data', pcm, size=0xFFFFFFFF)))
    rf_ms = ms_block(rng, 2, 128) + ms_block(rng, 2, 128, 60)
    add('rf64-msadpcm', rf64(ds64(len(rf_ms), 0), chunk(b'fmt ', ms_fmt(2, 128)), chunk(b'data', rf_ms, size=0xFFFFFFFF)))

    # AIFF and AIFC.
    def a16(name, rate, channels=1, frames=6, **k):
        add(name, aiff(comm(channels, frames, 16, rate), ssnd(noise(2 * channels * frames))), **k)

    add('aiff-pcm16-2ch', aiff(comm(2, 6, 16, 44100), ssnd(noise(24))))
    add('aiff-pcm8', aiff(comm(1, 9, 8, 8000), ssnd(noise(9))))
    add('aiff-pcm24', aiff(comm(2, 4, 24, 48000), ssnd(noise(24))))
    add('aiff-pcm32', aiff(comm(1, 5, 32, 48000), ssnd(noise(20))))
    add('aiff-pcm12', aiff(comm(1, 5, 12, 48000), ssnd(noise(10))))
    add('aiff-pcm4-stereo', aiff(comm(2, 6, 4, 8000), ssnd(noise(12))))
    add('aiff-pcm4-mono', aiff(comm(1, 6, 4, 8000), ssnd(noise(6))))
    add('aiff-pcm64', aiff(comm(1, 3, 64, 8000), ssnd(noise(24))))
    a16('aiff-rate-fraction', Fraction(44101, 2))
    a16('aiff-rate-1', 1)
    a16('aiff-rate-half', Fraction(1, 2))
    a16('aiff-rate-zero', 0)
    a16('aiff-rate-384000', 384000)
    a16('aiff-rate-384001', 384001)
    a16('aiff-rate-2pow40', 2 ** 40)
    a16('aiff-rate-max', 2 ** 32 - 1)
    a16('aiff-rate-negative', -44100)
    a16('aiff-rate-infinite', ext80_raw(0, 0x7FFF, 2 ** 63))
    a16('aiff-rate-unnormal', ext80_raw(0, 16383 + 63, 44100))
    a16('aiff-rate-unnormal-31', ext80_raw(0, 16383 + 31, 22050 << 32))
    a16('aiff-rate-negative-wrap', ext80_raw(1, 16383 + 63, 2 ** 64 - 8000))
    a16('aiff-rate-negative-zero', ext80_raw(1, 16383 + 63, 0))
    a16('aiff-rate-top-bit', ext80_raw(0, 16383 + 63, 2 ** 63 + 8000))
    a16('aiff-rate-exponent-zero', ext80_raw(0, 0, 44100))
    a16('aiff-rate-int64-min', ext80_raw(1, 16383 + 63, 2 ** 63), kind='data')
    add('aiff-frames-zero', aiff(comm(1, 0, 16, 8000), ssnd(noise(10))))
    add('aiff-frames-fewer', aiff(comm(1, 2, 16, 8000), ssnd(noise(10))))
    add('aiff-frames-more', aiff(comm(1, 9, 16, 8000), ssnd(noise(10))))
    add('aiff-ssnd-offset', aiff(comm(1, 4, 16, 8000), ssnd(noise(8), offset=3, lead=noise(3))))
    add('aiff-ssnd-offset-past', aiff(comm(1, 4, 16, 8000), ssnd(noise(8), offset=500)))
    add('aiff-ssnd-first', aiff(ssnd(noise(12)), chunk(b'ANNO', b'hello', be=True), comm(2, 3, 16, 11025)))
    add('aiff-two-comm', aiff(comm(1, 4, 8, 8000), ssnd(noise(8)), comm(2, 2, 16, 22050)))
    add('aiff-no-ssnd', aiff(comm(1, 4, 16, 8000)))
    add('aiff-comm-17', aiff(comm(1, 4, 16, 8000, size=17), ssnd(noise(8))))
    add('aiff-comm-short', aiff() + b'COMM' + struct.pack('>I', 18) + b'\0\1')
    add('aiff-form-17', aiff(comm(1, 4, 16, 8000), ssnd(noise(8)), size=17))
    add('aiff-form-type', aiff(comm(1, 4, 16, 8000), ssnd(noise(8)), form=b'AIFX'))
    add('aiff-channels-zero', aiff(comm(0, 4, 16, 8000), ssnd(noise(8))))
    add('aiff-pcm40', aiff(comm(1, 3, 40, 8000), ssnd(noise(15))), 'data')
    add('aiff-overflow-align', aiff(comm(40000, 1, 60000, 8000), ssnd(noise(8))), 'data')
    for name, bits, frames, channels in ((b'NONE', 16, 5, 2), (b'sowt', 16, 5, 2), (b'sowt', 8, 7, 1), (b'raw ', 8, 7, 1), (b'raw ', 16, 4, 1),
                                         (b'fl32', 32, 4, 1), (b'FL32', 32, 3, 2), (b'alaw', 8, 9, 1), (b'ALAW', 16, 8, 1),
                                         (b'ulaw', 8, 9, 1), (b'ULAW', 8, 6, 2)):
        if name in (b'fl32', b'FL32'):
            data = struct.pack(f'>{frames * channels}f', *[rng.uniform(-1.5, 1.5) for _ in range(frames * channels)])
        else:
            data = noise(frames * channels * (8 if name in (b'alaw', b'ALAW', b'ulaw', b'ULAW') else bits) // 8)
        add(f'aifc-{name.decode().strip()}-{bits}-{channels}ch', aiff(comm(channels, frames, bits, 22050, name, extra=b'\4none\0'), ssnd(data), form=b'AIFC'))
    add('aifc-fl64', aiff(comm(1, 6, 64, 22050, b'fl64', extra=b'\0\0'), ssnd(f64s([0.5, -0.75, 2.0, -1e-9, 1e-320, -1], True)), form=b'AIFC'))
    add('aifc-FL64', aiff(comm(2, 2, 64, 22050, b'FL64', extra=b'\0\0'), ssnd(f64s([0.25, -0.125, 3.0, -1 + 2 ** -53], True)), form=b'AIFC'))
    add('aifc-ima4', aiff(comm(1, 64, 16, 22050, b'ima4', extra=b'\0\0'), ssnd(noise(34)), form=b'AIFC'))
    add('aifc-unknown', aiff(comm(1, 4, 16, 22050, b'twos', extra=b'\0\0'), ssnd(noise(8)), form=b'AIFC'))
    add('aifc-comm-23', aiff(comm(1, 4, 16, 22050, b'NON', size=23), ssnd(noise(8)), form=b'AIFC'))
    add('aifc-comm-25', aiff(comm(1, 4, 16, 22050, b'NONE', extra=b'\1x\0'), ssnd(noise(8)), form=b'AIFC'))
    add('aifc-comm-26', aiff(comm(1, 4, 16, 22050, b'NONE', extra=b'\3abc'), ssnd(noise(8)), form=b'AIFC'))
    add('aifc-comm-past-end', aiff(comm(1, 4, 16, 22050, b'NONE', size=400), form=b'AIFC'))
    add('aifc-raw-sticky', aiff(comm(1, 4, 8, 8000, b'raw ', extra=b'\0\0'), comm(1, 6, 8, 8000, b'NONE', extra=b'\0\0'), ssnd(noise(6)), form=b'AIFC'))
    add('aifc-alaw-signed-quirk', aiff(comm(2, 4, 8, 8000, b'alaw', extra=b'\0\0'), ssnd(bytes(range(0, 256, 32))), form=b'AIFC'))

    # MS ADPCM.
    ms1 = b''.join(ms_block(rng, 1, 64) for _ in range(3)) + ms_block(rng, 1, 64, 20)
    add('msadpcm-mono', riff(chunk(b'fmt ', ms_fmt(1, 64)), chunk(b'fact', struct.pack('<I', 999)), chunk(b'data', ms1)))
    ms2 = b''.join(ms_block(rng, 2, 96) for _ in range(2)) + ms_block(rng, 2, 96, 41)
    add('msadpcm-stereo', riff(chunk(b'fmt ', ms_fmt(2, 96)), chunk(b'data', ms2)))
    add('msadpcm-header-only', riff(chunk(b'fmt ', ms_fmt(1, 7)), chunk(b'data', b''.join(ms_block(rng, 1, 7) for _ in range(3)))))
    add('msadpcm-partial-header', riff(chunk(b'fmt ', ms_fmt(1, 32)), chunk(b'data', ms_block(rng, 1, 32) + ms_block(rng, 1, 32, 5))))
    add('msadpcm-partial-header-trailing', riff(chunk(b'fmt ', ms_fmt(1, 32)), chunk(b'data', ms_block(rng, 1, 32) + ms_block(rng, 1, 32, 5)),
                                                chunk(b'LIST', noise(40))))
    bad = bytearray(ms_block(rng, 1, 32) + ms_block(rng, 1, 32))
    bad[32] = 7
    add('msadpcm-bad-predictor-later', riff(chunk(b'fmt ', ms_fmt(1, 32)), chunk(b'data', bytes(bad))))
    bad = bytearray(ms_block(rng, 2, 40))
    bad[1] = 200
    add('msadpcm-bad-predictor-first', riff(chunk(b'fmt ', ms_fmt(2, 40)), chunk(b'data', bytes(bad))))
    neg = ms_block(rng, 1, 32, states=[MsChannel(1, -300, 1000, -1000)])
    add('msadpcm-negative-delta', riff(chunk(b'fmt ', ms_fmt(1, 32)), chunk(b'data', neg)))
    add('msadpcm-align-small', riff(chunk(b'fmt ', ms_fmt(1, 4)), chunk(b'data', ms_block(rng, 1, 7) + noise(20))))
    add('msadpcm-3ch', riff(chunk(b'fmt ', fmt(2, 3, 8000, 4, align=96)), chunk(b'data', noise(96))))
    add('msadpcm-extensible', riff(chunk(b'fmt ', extensible(2, 4, 1, 8000, 4, align=32)), chunk(b'data', ms_block(rng, 1, 32) * 2)))
    add('ima-extensible-stereo', riff(chunk(b'fmt ', extensible(0x11, 4, 2, 8000, 4, align=24)), chunk(b'data', ima_block(rng, 2, 24) * 2)))
    add('w64-ima', w64(w64_chunk(b'fmt ', ima_fmt(1, 36)), w64_chunk(b'data', ima_block(rng, 1, 36) + ima_block(rng, 1, 36, 20))))
    over = MsChannel(0, 32767, 0, 0)
    for _ in range(40):
        over.nibble(7)
        over.nibble(7)
    if not over.overflow:
        raise ProbeFailure('wav: the overflow case does not overflow')
    add('msadpcm-overflow', riff(chunk(b'fmt ', ms_fmt(1, 47)), chunk(b'data', struct.pack('<Bhhh', 0, 32767, 0, 0) + b'\x77' * 40)), 'data')

    # IMA ADPCM.
    ima1 = b''.join(ima_block(rng, 1, 36) for _ in range(2)) + ima_block(rng, 1, 36, 16)
    add('ima-mono', riff(chunk(b'fmt ', ima_fmt(1, 36)), chunk(b'data', ima1)))
    ima2 = b''.join(ima_block(rng, 2, 40) for _ in range(2)) + ima_block(rng, 2, 40, 24)
    add('ima-stereo', riff(chunk(b'fmt ', ima_fmt(2, 40)), chunk(b'data', ima2)))
    add('ima-stereo-partial-group', riff(chunk(b'fmt ', ima_fmt(2, 40)), chunk(b'data', ima_block(rng, 2, 40) + ima_block(rng, 2, 40, 12))))
    add('ima-mono-partial-header', riff(chunk(b'fmt ', ima_fmt(1, 36)), chunk(b'data', ima_block(rng, 1, 36) + ima_block(rng, 1, 36, 3))))
    add('ima-bad-step-later', riff(chunk(b'fmt ', ima_fmt(1, 20)), chunk(b'data', ima_block(rng, 1, 20) + ima_block(rng, 1, 20, steps=[89]))))
    add('ima-bad-step-right', riff(chunk(b'fmt ', ima_fmt(2, 24)), chunk(b'data', ima_block(rng, 2, 24, steps=[3, 120]))))
    add('ima-align-uneven', riff(chunk(b'fmt ', ima_fmt(1, 10)), chunk(b'data', noise(30))))
    add('ima-extreme-steps', riff(chunk(b'fmt ', ima_fmt(1, 20)), chunk(b'data', ima_block(rng, 1, 20, steps=[88]) + struct.pack('<hBB', -32768, 0, 0) + b'\x88' * 16)))
    add('ima-3ch', riff(chunk(b'fmt ', fmt(0x11, 3, 8000, 4, align=96)), chunk(b'data', noise(96))))
    add('ima-rifx', rifx(chunk(b'fmt ', fmt(0x11, 1, 8000, 4, align=20, be=True), be=True), chunk(b'data', ima_block(rng, 1, 20) * 2, be=True)))
    return out


EXPECTED = {'data': ['error', 'data']}

# Waves built in memory for the utilities: (size, channels, rate, samples).
WAVES = [(8, 1, 8000, [0, 1, 127, 128, 129, 200, 255]), (16, 2, 22050, [0, 1, 32767, 32768, 65535, 12345, 40000, 7]),
         (32, 1, 44100, [struct.unpack('<I', struct.pack('<f', v))[0] for v in (0.0, -0.5, 0.25, 1.75, -3.0)]),
         (8, 1, 11025, [(i * 37) % 256 for i in range(43)]),
         (32, 2, 48000, [struct.unpack('<I', struct.pack('<f', v))[0] for v in [(i - 23) / 7.0 for i in range(46)]])]


def c_wave(size, channels, rate, samples):
    kind = {8: 'unsigned char', 16: 'unsigned short', 32: 'unsigned int'}[size]
    return f'(Wave){{{len(samples) // channels},{rate},{size},{channels},(void*)({kind}[]){{{",".join(map(str, samples))}}}}}'


def native(probe, items):
    lines = ['#include "raylib.h"', '#include "external/dr_wav.h"', '#include <stdio.h>', '#include <string.h>',
             'static void wave(Wave w){if(!w.data||(!w.frameCount&&!w.sampleRate)){puts("null");return;}'
             'printf("[%u,%u,%u,%u,[",w.frameCount,w.sampleRate,w.sampleSize,w.channels);unsigned n=w.frameCount*w.channels;'
             'for(unsigned i=0;i<n;i++){unsigned v=w.sampleSize==8?((unsigned char*)w.data)[i]:w.sampleSize==16?((unsigned short*)w.data)[i]:((unsigned*)w.data)[i];'
             'printf("%s%u",i?",":"",v);}puts("]]");}',
             'static void file(const char *path){FILE *f=fopen(path,"rb");int c,i=0;printf("[");while((c=fgetc(f))!=EOF)printf("%s%d",i++?",":"",c);puts("]");fclose(f);}',
             # dr_wav itself first: LoadWaveFromMemory reads (unsigned int)totalPCMFrameCount
             # frames; fewer frames read leave its samples uninitialized.
             'static short scratch[4096*256];',
             'static void load(const char *path){int n=0;unsigned char *d=LoadFileData(path,&n);drwav w;'
             'if(!d||!drwav_init_memory(&w,d,(size_t)n,NULL)){puts("null");if(d)UnloadFileData(d);return;}'
             'unsigned count=(unsigned)w.totalPCMFrameCount,got=0;'
             'while(got<count){unsigned want=count-got>4096?4096:count-got;drwav_uint64 r=drwav_read_pcm_frames_s16(&w,want,scratch);got+=(unsigned)r;if(r<want)break;}'
             'drwav_uninit(&w);UnloadFileData(d);if(got<count){puts("\\"unread\\"");return;}'
             'Wave v=LoadWave(path);wave(v);UnloadWave(v);}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in items:
        if case['kind'] == 'native':
            lines.append(f'load("{case["path"]}");')
    for index, (size, channels, rate, samples) in enumerate(WAVES):
        w = c_wave(size, channels, rate, samples)
        lines.append(f'{{Wave w={w};printf("%d\\n",IsWaveValid(w));Wave c=WaveCopy(w);wave(c);UnloadWave(c);'
                     f'Wave k=WaveCopy(w);WaveCrop(&k,1,{len(samples) // channels - 1});wave(k);'
                     f'WaveCrop(&k,2,1);wave(k);UnloadWave(k);'
                     f'float *s=LoadWaveSamples(w);printf("[");for(unsigned i=0;i<w.frameCount*w.channels;i++){{unsigned b;memcpy(&b,s+i,4);printf("%s%u",i?",":"",b);}}puts("]");'
                     f'UnloadWaveSamples(s);ExportWave(w,"{WORK}/out{index}.wav");file("{WORK}/out{index}.wav");'
                     f'ExportWave(w,"{WORK}/out{index}.RAW");file("{WORK}/out{index}.RAW");'
                     f'ExportWaveAsCode(w,"{WORK}/native/wave_{index}.h");file("{WORK}/native/wave_{index}.h");}}')
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n')


PROGRAM = '''import Base
import ../../jonlib.bend as J
def show(+values: +List<U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, values)
def wave(+w: J.Wave) -> String:
  J.Wave{frames, rate, size, channels, data} = w
  "[" ++ U32.show(frames) ++ "," ++ U32.show(rate) ++ "," ++ U32.show(size) ++ "," ++ U32.show(channels) ++ "," ++ show(data) ++ "]"
def error(e: J.Wave.Error) -> String:
  match e:
    case J.UnsupportedWaveFormat{}: "[\\"error\\", \\"unsupported\\"]"
    case J.InvalidWaveData{}: "[\\"error\\", \\"data\\"]"
    case _: "null"
def loaded(result: Result<&1, &1, J.Wave.IOError, J.Wave>) -> IO(Unit):
  match result:
    case Fail{J.WaveDataError{e}}: IO.print(error(e))
    case Fail{_}: IO.print("null")
    case Done{w}: IO.print(wave(w))
def cropped(result: Result<&1, &1, J.Wave & J.Wave.Error, J.Wave>) -> String:
  match result:
    case Fail{Tuple{w, _}}: wave(w)
    case Done{w}: wave(w)
def floats(values: List<F32>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{v, rest}: Con{F32.bits(v), floats(rest)}
def samples(result: Result<&1, &1, J.Wave.Error, List<F32>>) -> String:
  match result:
    case Fail{_}: "null"
    case Done{values}: List.show(~&1, ~U32, ~U32.show, floats(values))
def written(result: Result<&1, &1, J.Wave.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{_}: IO.print("written")
def cropped.wave(result: Result<&1, &1, J.Wave & J.Wave.Error, J.Wave>) -> J.Wave:
  match result:
    case Fail{Tuple{w, _}}: w
    case Done{w}: w
def utilities(+w: J.Wave, +last: U32, +wav: String, +raw: String, +code: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print(Bool.pick(String, J.Wave.is_valid(w), "1", "0"))
    Unit <- IO.print(wave(w))
    Unit <- IO.print(cropped(J.Wave.crop(w, 1, last)))
    Unit <- IO.print(cropped(J.Wave.crop(cropped.wave(J.Wave.crop(w, 1, last)), 2, 1)))
    Unit <- IO.print(samples(J.Wave.samples(w)))
    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, Unit>, Unit, J.Wave.write(w, wav), written)
    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, Unit>, Unit, J.Wave.write(w, raw), written)
    IO.bind(Result<&1, &1, J.Wave.IOError, Unit>, Unit, J.Wave.write_code(w, code), written)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for kind, payload in selected:
        if kind == 'load':
            body += f'    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, J.Wave>, Unit, J.Wave.load({json.dumps(payload)}), loaded)\n'
        else:
            index, (size, channels, rate, samples) = payload
            body += (f'    Unit <- utilities(J.Wave{{{len(samples) // channels}, {rate}, {size}, {channels}, [{", ".join(map(str, samples))}]}}, '
                     f'{len(samples) // channels - 1}, "{WORK}/jon{index}.wav", "{WORK}/jon{index}.RAW", "{WORK}/jon/wave_{index}.h")\n')
    return body + '    IO.print("\\"done\\"")\n'


def main():
    probe = probekit.Probe('wav', probekit.arguments(__doc__), raylib_options=('SUPPORT_MODULE_RAUDIO=ON',))
    for folder in ('', '/native', '/jon'):
        (ROOT / (WORK + folder)).mkdir(parents=True, exist_ok=True)
    for stale in (ROOT / WORK).glob('*.wav'):
        stale.unlink()
    items = cases()
    if len({case['id'] for case in items}) != len(items):
        raise ProbeFailure('wav: duplicate case ids')
    for index, case in enumerate(items):
        case['path'] = f'{WORK}/{index:03}-{case["id"]}.wav'
        (ROOT / case['path']).write_bytes(case['bytes'])
    text = native(probe, items).splitlines()
    rows = iter(json.loads(line) for line in text)
    expected = []
    for case in items:
        row = next(rows) if case['kind'] == 'native' else EXPECTED[case['kind']]
        expected.append(EXPECTED['data'] if row == 'unread' else row)
        case['unread'] = row == 'unread'
    decoded = sum(isinstance(row, list) and row[:1] != ['error'] for row in expected)
    failed = sum(row is None for row in expected)
    unread = sum(case['unread'] for case in items)
    if failed < 40 or decoded < 100 or unread < 10:
        raise ProbeFailure(f'wav: unexpected native outcomes (decoded={decoded}, failed={failed}, unread={unread})')
    utility_rows = []
    for _ in WAVES:
        utility_rows.append([next(rows) for _ in range(8)])
    actions = [('load', case['path']) for case in items] + [('utilities', (index, wave)) for index, wave in enumerate(WAVES)]

    def parse(text, selected):
        values = iter(json.loads(line) if line not in ('written',) else line for line in text.splitlines())
        out = []
        for kind, payload in selected:
            if kind == 'load':
                out.append(next(values))
            else:
                index = payload[0]
                got = [next(values) for _ in range(5)]
                for name in (f'jon{index}.wav', f'jon{index}.RAW', f'jon/wave_{index}.h'):
                    status = next(values)
                    got.append(list((ROOT / f'{WORK}/{name}').read_bytes()) if status == 'written' else None)
                out.append(got)
        if next(values) != 'done':
            raise ValueError('wav: candidate output did not finish')
        return out
    expected += utility_rows
    lanes = probe.candidates(render, actions, batch=48, parse=parse)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: items[i]['id'] if i < len(items) else f'utilities {i - len(items)}')
    probe.finish(files=len(items), decoded=decoded, failed=failed, unread=unread,
                 contracts=sum(case['kind'] != 'native' for case in items), utility_waves=len(WAVES),
                 inputs_sha256=hashlib.sha256(b''.join(case['bytes'] for case in items)).hexdigest())


if __name__ == '__main__':
    main()
