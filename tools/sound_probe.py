#!/usr/bin/env python3
"""Compare Jonlib's audio device and sounds (AudioDevice.*, Sound.*) with the pinned raylib.

The reference is raudio.c itself, compiled into the reference program with
-ffp-contract=off and miniaudio's null backend only, so that its AUDIO state
and audio buffers can be read. InitAudioDevice is followed by ma_device_stop:
the device thread never mixes, and a playing buffer stays at its start, as in
a Jonlib AudioDevice value (no case opens the device over a playing buffer,
which it would mix before it is stopped). Every case starts from a zeroed
AUDIO.

A case is a script over four sound slots: InitAudioDevice, CloseAudioDevice,
SetMasterVolume, LoadSoundFromWave, LoadSound, LoadSoundAlias, UnloadSound,
UnloadSoundAlias, PlaySound, StopSound, PauseSound, ResumeSound,
SetSoundVolume, SetSoundPitch, SetSoundPan and UpdateSound. After every step
both sides print IsAudioDeviceReady and GetMasterVolume's bits; each slot's
buffer number, frame count, stream fields, IsSoundValid and IsSoundPlaying;
and every tracked buffer in raudio's order with its number, the buffer that
allocated its samples, its size, volume, pitch and pan bits, its playing and
paused flags and an FNV-1a hash of its samples. Buffers are numbered in the
order they were made.

The waves: 8-, 16- and 32-bit samples; one, two, four and six channels;
48000 Hz (no resampling) and 8000, 22050, 44100 and 96000 Hz; the zero wave;
waves without frames, without channels and with a zero rate; and the four
.wav files of the examples that only need sounds (boom, buttonfx, sound and
coin), a small generated .wav, a missing file, a .wav that is not one and
another extension. raylib's converted samples for each wave come from a first
reference pass.

The musics are WAV files written here, the examples' target.qoa and two
cuts of raylib's country.mp3 (the mp3 gate's): its Info frame with eleven
frames, whose count is the whole file's and whose LAME delay is 1105
frames, and twelve frames without a tag, which dr_mp3 counts. The
reference's first pass also reads each MP3 cut's frames through dr_mp3,
and the model plays those: it keeps dr_mp3's count of frames, which a seek
goes by, and takes the stream back to its start whenever a read comes
short. The cases play a cut round its end, stop it, seek forward, back and
to 0, and let one end without looping.

A Python model of raudio's state gives the expected rows for both sides and
finds the steps raylib has no defined answer for. Cases with such a step are
contracts (the reference does not run them): sounds loaded on an unready
device; waves WaveFormat refuses (a 24-bit size, a short sample list, a NaN
sample, a rate that does not reduce below 2^31); a handle used after its
buffer was unloaded; an alias of a buffer whose samples were freed, of the
zero sound; InitAudioDevice on a ready device; buffer operations and
StopSound on an unready device; UpdateSound past the buffer, from a short
list, on freed samples and on a buffer without samples; a pitch whose rate
does not fit an unsigned int. IsSoundPlaying is only asked of the reference
on a ready device and for a tracked buffer. CPU-1, CPU-2 and JavaScript
lanes.
"""
import copy
import hashlib
import json
import math
import struct

import mp3_probe
import probekit
from probekit import ProbeFailure
import wave_format_probe as wf

SLOTS = 4
ZERO = (0, 0, 0, 0, 0)
FLAGS = ['-ffp-contract=off', '-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS', '-DMA_ENABLE_NULL', '-D_DEFAULT_SOURCE', '-Wno-everything']
FILES = {'boom': 'examples/textures/resources/boom.wav', 'buttonfx': 'examples/textures/resources/buttonfx.wav',
         'sound': 'examples/audio/resources/sound.wav', 'coin': 'examples/audio/resources/coin.wav'}
FILE_ERRORS = {'missing': 'file', 'text': 'header', 'other': 'unsupported'}
# Files the reference decodes for the model (LoadWave): the QOA music of raylib's examples.
RAW_FILES = {'target': 'examples/audio/resources/target.qoa'}
# MP3 musics: the mp3 gate's cuts of raylib's country.mp3. `first12` is its Info frame (a LAME delay of 1105 frames, and the
# whole file's count) and eleven frames; `noinfo` twelve frames with no tag, which dr_mp3 counts.
MP3_SOURCE = 'examples/audio/resources/country.mp3'
MP3_FILES = {'mp3tag': 'first12', 'mp3plain': 'noinfo'}


def bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def fl(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def f32(x):
    try:
        return struct.unpack('<f', struct.pack('<f', x))[0]
    except OverflowError:
        return math.copysign(math.inf, x)


def fnv(words):
    h = 2166136261
    for word in words:
        h = ((h ^ word) * 16777619) & 0xFFFFFFFF
    return h


NAN = 0x7FC00000


def fz(x):
    """A subnormal as the zero of its sign: the device callback runs with denormals-are-zero and flush-to-zero on x86."""
    return math.copysign(0.0, x) if x != 0 and abs(x) < 2.0 ** -126 else x


def fadd(x, y):
    return fz(f32(fz(x) + fz(y)))


def fsub(x, y):
    return fz(f32(fz(x) - fz(y)))


def fmul(x, y):
    return fz(f32(fz(x) * fz(y)))


def fdiv(x, y):
    return fz(f32(fz(x) / fz(y)))


def nans(*values):
    return any(math.isnan(v) for v in values)


def reduced(source, rate):
    g = math.gcd(source, rate)
    return source // g, rate // g


def coefficient(rin, rout):
    """ma_lpf1_reinit: (float)exp(-2*pi*cutoff/rate) with libm exp, the cutoff min*0.5 and the rate max of the reduced rates."""
    return None if rin == rout or max(rin, rout) >= 1 << 31 else f32(math.exp((-2 * math.pi * (min(rin, rout) * 0.5)) / max(rin, rout)))


def set_rate(b, wanted):
    """ma_data_converter_set_rate(48000, wanted): the filter for the reduced rates, the timer in the new output rate."""
    old = reduced(b['source'], b['rate'])[1]
    rin, rout = reduced(b['source'], wanted)
    frac = ((b['t_frac'] // old) * rout + (((b['t_frac'] % old) * rout) & 0xFFFFFFFF) // old) & 0xFFFFFFFF
    b.update(rate=wanted, t_int=(b['t_int'] + frac // rout) & 0xFFFFFFFF, t_frac=frac % rout, wide=max(rin, rout) >= 1 << 31, coef=coefficient(rin, rout))


def lowpass(b, frame):
    """ma_lpf1_process_pcm_frame_f32 on a frame."""
    a = b['coef']
    out = [fadd(fmul(fsub(1.0, a), x), fmul(a, r1)) for x, r1 in zip(frame, b['r1'])]
    b['r1'] = list(out)
    return out


def flow(b, frames, remaining):
    """ma_linear_resampler_process_pcm_frames_f32 on a stream: (input frames used, frames made, fine)."""
    rin, rout = reduced(b['source'], b['rate'])
    plain, down, used, made, fine = rin == rout, rin > rout, 0, [], True
    while remaining > 0:
        if b['t_int'] > 0:
            if used >= len(frames):
                break
            frame = list(frames[used])
            used += 1
            if not plain and down:
                frame = lowpass(b, frame)
            fine &= not nans(*frame)
            b['x0'], b['x1'], b['t_int'] = b['x1'], frame, b['t_int'] - 1
        else:
            a = fdiv(f32(float(b['t_frac'])), f32(float(rout)))
            y = [fadd(p, fmul(fsub(q, p), a)) for p, q in zip(b['x0'], b['x1'])]
            if not plain and not down:
                y = lowpass(b, y)
            fine &= not nans(*y)
            made.append(y)
            remaining -= 1
            b['t_int'], b['t_frac'] = b['t_int'] + rin // rout, b['t_frac'] + rin % rout
            if b['t_frac'] >= rout:
                b['t_int'], b['t_frac'] = b['t_int'] + 1, b['t_frac'] - rout
    return used, made, fine


INF = 0xFFFFFFFF


def converted(b, raw):
    """The resampler's input for raw frames (the buffer's own samples): f32, and more than two channels mixed to stereo."""
    stream = b['stream']
    if stream is None:
        return [[fl(w) for w in frame] for frame in raw]
    form = wf.fmt(stream['size'])
    frames = [[wf.convert(form, 'f32', wf.decode(form, w)) for w in frame] for frame in raw]
    if stream['channels'] <= 2:
        return frames
    weights, out = wf.weights(stream['channels'], 2), []
    for frame in frames:
        mixed = [0.0, 0.0]
        for side in range(2):
            for x, row in zip(frame, weights):
                mixed[side] = fadd(mixed[side], fmul(x, row[side]))
        out.append(mixed)
    return out


def caps(b):
    """ma_data_converter's passes: (input frames a pass takes, output frames it makes, whether its input is what the resampler needs)."""
    stream = b['stream']
    channels, formatted = (2, False) if stream is None else (stream['channels'], stream['size'] != 32)
    if channels == 2:
        return (512 if formatted else INF), INF, False
    if channels == 1:
        return (1024 if formatted else INF), 1024, True
    return (min(512, 1024 // channels) if formatted else 512), 512, True


def required(b, out):
    """ma_linear_resampler_get_required_input_frame_count."""
    rin, rout = reduced(b['source'], b['rate'])
    more = max(out, 1) - 1
    return INF if rin // rout > 1 << 22 else b['t_int'] + more * (rin // rout) + (b['t_frac'] + min(more, 1024) * (rin % rout)) // rout


def feed(b, raw, want):
    """ma_data_converter_process_pcm_frames: (the raw frames not taken, the frames made, fine)."""
    in_cap, out_cap, limited = caps(b)
    made, fine = [], True
    for _ in range(2048):
        out = min(want - len(made), out_cap)
        taken = min(len(raw), in_cap, required(b, out) if limited else INF)
        used, new, flowed = flow(b, converted(b, raw[:taken]), out)
        raw, fine = raw[used:], fine and flowed
        made += new
        if not new or len(made) >= want:
            break
    return raw, made, fine


def answer_sample(size, c):
    """Sample c of the probe's stream callback, as the stream holds it."""
    if size == 8:
        return (c * 37 + 11) & 255
    if size == 16:
        return ((c * 53) % 301 * 97 + 50986) & 65535
    return bits(((c * 31) % 67 - 33) / 64)


def read(b, data, estimate, callback=None):
    """ReadAudioBufferFramesInInternalFormat: (raw frames, whether fewer than asked)."""
    size, stream, cursor = b['frames'], b['stream'], b['cursor']
    if b['playing'] and stream is not None and stream['called']:
        return callback(estimate), False
    if stream is None or not b['playing']:
        half = max(size // 2 if size > 1 else size, 1)
        count = 0 if not b['playing'] or stream is not None or cursor // half > 1 else min(estimate, size - cursor)
        frames = [[data[2 * (cursor + i)], data[2 * (cursor + i) + 1]] for i in range(count)]
        if count and count == size - cursor:
            b['playing'], b['cursor'] = False, 0
        else:
            b['cursor'] += count
        return frames, count < estimate
    channels, half = stream['channels'], size // 2
    upper = cursor >= half
    here, there = ('second', 'first') if upper else ('first', 'second')
    left = (size - cursor) if upper else (half - cursor)
    a = 0 if stream[here] else min(estimate, left)
    ended = a > 0 and a == left
    more = min(estimate - a, half) if ended and not stream[there] else 0
    start = 0 if upper else half
    words = data[cursor * channels:(cursor + a) * channels] + data[start * channels:(start + more) * channels] + [0] * ((estimate - a - more) * channels)
    stream[here] = stream[here] or ended
    stream[there] = stream[there] or (more > 0 and more == half)
    b['cursor'] = (cursor + a + more) % size
    return [words[i * channels:(i + 1) * channels] for i in range(estimate)], False


def turn(b, data, frames, callback=None):
    """A playing buffer in a callback (raudio's runs of 512 frames over its converter): (frames made, fine)."""
    stream = b['stream']
    fine = not b['wide'] and b['frames'] > 0 and not (stream is not None and stream['channels'] > 1024)
    cap = 512 if stream is None else 4096 // max(stream['channels'] * (stream['size'] // 8), 1)
    made, need = [], frames
    if not fine:
        return [], False
    while need > 0 and b['playing']:
        now, total, broke = min(need, 512), 0, False
        while total < now and not broke:
            want = now - total
            if b['residual']:
                b['residual'], out, ok = feed(b, b['residual'], want)
            else:
                estimate = min(cap, max(int(f32(f32(f32(float(b['source'])) / f32(float(b['rate']))) * float(want))), 1))
                raw, broke = read(b, data, estimate, callback)
                rest, out, ok = feed(b, raw, want)
                b['residual'] = rest[:8]
            total, fine = total + len(out), fine and ok
            made += out
        if b['playing'] and total < now:
            b['playing'], b['cursor'] = False, 0
        need = need - total if b['playing'] else 0
    return [frame * 2 if len(frame) == 1 else frame for frame in made], fine


def s16(values):
    return [v & 0xFFFF for v in values]


def floats(values):
    return [bits(v) for v in values]


def waves():
    """name -> (frames, rate, size, channels, samples, refusal or None)."""
    ramp = [((i * 2311) % 4001 - 2000) * 13 for i in range(64)]
    return {
        'mono16': (8, 48000, 16, 1, s16([100, -200, 300, -400, 500, -600, 700, -800]), None),
        'stereo16': (6, 48000, 16, 2, s16(ramp[:12]), None),
        'stereo32': (5, 48000, 32, 2, floats([0.0, -0.0, 0.5, -0.25, 1.0, -1.0, 1.5, -3.0, 1e-40, 0.125]), None),
        'mono8up': (12, 22050, 8, 1, [0, 255, 128, 127, 129, 1, 254, 64, 192, 100, 200, 128], None),
        'stereo16up': (16, 44100, 16, 2, s16(ramp[:32]), None),
        'mono16down': (24, 96000, 16, 1, s16(ramp[:24]), None),
        'mono32up': (6, 8000, 32, 1, floats([0.25, -0.5, 0.75, -1.0, 0.1, 0.0]), None),
        'quad16': (4, 48000, 16, 4, s16(ramp[:16]), None),
        'six8up': (6, 22050, 8, 6, [(i * 37 + 11) & 255 for i in range(36)], None),
        'one': (1, 44100, 16, 1, s16([12345]), None),
        'five32': (5, 48000, 32, 2, floats([0.5, -0.25, 1.5, -3.0, 0.125, 0.75, -1.0, 1.0, 0.0625, -0.0]), None),
        'long513': (513, 48000, 16, 1, s16([((i * 97) % 2001 - 1000) * 31 for i in range(513)]), None),
        'tiny32': (3, 48000, 32, 2, floats([0.5, 1e-40, 0.25, 0.5, -0.5, 0.125]), None),
        'tone': (40, 48000, 32, 2, floats([((i * 29) % 61 - 30) / 32 for i in range(80)]), None),
        'zero': (0, 0, 0, 0, [], None),
        'noframes': (0, 48000, 16, 1, [], None),
        'nochannels': (5, 48000, 16, 0, [], None),
        'rate0': (4, 0, 16, 1, s16([1, 2, 3, 4]), None),
        'size24': (4, 48000, 24, 1, [1, 2, 3, 4], 'request'),
        'short': (4, 48000, 16, 1, s16([1, 2, 3]), 'request'),
        'nan': (3, 48000, 32, 1, [bits(0.5), NAN, bits(0.25)], 'data'),
        'hugerate': (4, 4294967291, 16, 1, s16([1, 2, 3, 4]), 'unsupported'),
    }


def wav_file(kind, size, channels, rate, values):
    """A RIFF file of PCM (kind 1) or IEEE float (kind 3) samples; `values` are sample words."""
    width = size // 8
    data = b''.join(struct.pack('<I', v & 0xFFFFFFFF)[:width] for v in values)
    return (b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, kind, channels, rate, rate * channels * width, channels * width, size)
            + b'data' + struct.pack('<I', len(data)) + data)


def music_files():
    """name -> (file, rate, the stream's sample size (None where Jonlib plays none), channels, frames, the samples as the stream holds them)."""
    m16 = [((i * 53) % 301 - 150) * 97 for i in range(1400)]
    m24 = [((i * 7919) % 16001 - 8000) * 1000 for i in range(300)]
    mf32 = [bits(((i * 29) % 61 - 30) / 32) for i in range(1000)]
    mi32 = [((i * 104729) % 2000001 - 1000000) * 2000 for i in range(400)]
    return {
        'm16': (wav_file(1, 16, 2, 22050, m16), 22050, 16, 2, 700, [v & 65535 for v in m16]),
        'm24': (wav_file(1, 24, 1, 44100, m24), 44100, 16, 1, 300, [(v & 0xFFFFFF) >> 8 for v in m24]),       # drwav_s24_to_s16: the two high bytes
        'mf32': (wav_file(3, 32, 1, 48000, mf32), 48000, 32, 1, 1000, mf32),
        'mi32': (wav_file(1, 32, 2, 8000, mi32), 8000, 32, 2, 200, [bits(f32(v / 2147483648.0)) for v in mi32]),
        'm8': (wav_file(1, 8, 1, 11025, [(i * 37 + 11) & 255 for i in range(600)]), 11025, None, 1, 600, []),
    }


def tiny_wav():
    data = bytes([128, 200, 255, 130, 0, 60, 128, 190, 250, 128])
    return (b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 11025, 11025, 1, 8)
            + b'data' + struct.pack('<I', len(data)) + data)


# Steps: ('init',), ('close',), ('master', word), ('load', slot, wave), ('file', slot, name), ('alias', slot, source),
# ('unload', slot), ('unalias', slot), ('play'|'stop'|'pause'|'resume', slot), ('volume'|'pitch'|'pan', slot, word),
# ('update', slot, frames, words), ('mix', frames), ('default', size), ('stream', slot, rate, size, channels),
# ('feed', slot, frames, words).
STATE = {'play': 0, 'stop': 1, 'pause': 2, 'resume': 3}
TUNE = {'volume': 4, 'pitch': 5, 'pan': 6}


def cases():
    w = waves()
    out = []

    def add(name, *steps):
        out.append(dict(id=name, steps=list(steps)))

    add('lifecycle', ('master', bits(0.25)), ('init',), ('master', bits(-1.0)), ('master', bits(3.5)), ('master', NAN), ('master', bits(-0.0)),
        ('close',), ('master', bits(0.5)), ('close',), ('init',), ('close',))
    for name, wave in w.items():
        if wave[5] is None and name not in ('zero', 'noframes', 'nochannels', 'rate0'):
            add(f'wave-{name}', ('init',), ('load', 0, name), ('alias', 1, 0), ('play', 0), ('unalias', 1), ('unload', 0), ('close',))
    add('empty-buffers', ('init',), ('load', 0, 'noframes'), ('load', 1, 'nochannels'), ('load', 2, 'rate0'), ('load', 3, 'zero'), ('alias', 3, 0),
        ('play', 0), ('pause', 0), ('resume', 0), ('stop', 0), ('volume', 1, bits(0.5)), ('unload', 0), ('unalias', 1), ('unload', 2), ('unload', 3), ('close',))
    add('playing', ('init',), ('load', 0, 'mono16'), ('play', 0), ('pause', 0), ('stop', 0), ('resume', 0), ('stop', 0), ('pause', 0), ('stop', 0),
        ('resume', 0), ('pause', 0), ('play', 0), ('play', 0), ('stop', 0), ('stop', 0), ('resume', 0), ('unload', 0), ('close',))
    add('volume', ('init',), ('load', 0, 'stereo16'), ('volume', 0, bits(0.0)), ('volume', 0, bits(-2.5)), ('volume', 0, bits(1e30)), ('volume', 0, NAN),
        ('volume', 0, bits(math.inf)), ('volume', 0, bits(-0.0)), ('volume', 0, bits(0.3)), ('close',))
    add('pitch', ('init',), ('load', 0, 'stereo16'), ('pitch', 0, bits(2.0)), ('pitch', 0, bits(0.0)), ('pitch', 0, bits(-1.0)), ('pitch', 0, NAN),
        ('pitch', 0, bits(0.5)), ('pitch', 0, bits(2e-5)), ('pitch', 0, bits(1e9)), ('pitch', 0, bits(math.inf)), ('pitch', 0, bits(-0.0)),
        ('pitch', 0, bits(1.0)), ('close',))
    add('pan', ('init',), ('load', 0, 'stereo16'), ('pan', 0, bits(-7.0)), ('pan', 0, bits(7.0)), ('pan', 0, bits(0.25)), ('pan', 0, NAN),
        ('pan', 0, bits(-0.0)), ('pan', 0, bits(-1.0)), ('pan', 0, bits(1.0)), ('pan', 0, bits(-math.inf)), ('pan', 0, bits(math.inf)), ('close',))
    add('aliases', ('init',), ('load', 0, 'mono8up'), ('alias', 1, 0), ('alias', 2, 1), ('play', 1), ('volume', 2, bits(0.25)), ('pitch', 0, bits(1.5)),
        ('pan', 1, bits(-0.5)), ('pause', 1), ('alias', 3, 1), ('unalias', 1), ('play', 0), ('play', 3), ('unalias', 2), ('unalias', 3), ('unload', 0), ('close',))
    add('order', ('init',), ('load', 0, 'mono16'), ('load', 1, 'stereo16'), ('load', 2, 'stereo32'), ('unload', 1), ('load', 3, 'quad16'), ('alias', 1, 2),
        ('unload', 0), ('load', 0, 'one'), ('unalias', 1), ('unload', 3), ('unload', 2), ('unload', 0), ('close',))
    add('update', ('init',), ('load', 0, 'mono16'), ('alias', 1, 0), ('play', 0), ('play', 1), ('update', 0, 3, floats([0.5, -0.5, 0.25, -0.25, 1.0, 2.0])),
        ('play', 0), ('pause', 0), ('update', 0, 1, [NAN, bits(-0.0)]), ('update', 1, 0, []), ('update', 1, 8, floats([i / 16 for i in range(16)])),
        ('unalias', 1), ('unload', 0), ('close',))
    add('unload-by-alias', ('init',), ('load', 0, 'stereo16'), ('alias', 1, 0), ('unload', 1), ('play', 0), ('close',))
    add('unalias-a-source', ('init',), ('load', 0, 'stereo16'), ('alias', 1, 0), ('unalias', 0), ('play', 1), ('unalias', 1), ('close',))
    add('zero-handles', ('init',), ('play', 0), ('stop', 0), ('pause', 0), ('resume', 0), ('volume', 0, bits(0.5)), ('pitch', 0, bits(2.0)),
        ('pan', 0, bits(1.0)), ('unload', 0), ('unalias', 0), ('update', 0, 0, []), ('update', 0, 2, floats([1.0, 1.0, 1.0, 1.0])), ('close',))
    add('zero-handles-unready', ('play', 0), ('pause', 0), ('resume', 0), ('volume', 0, bits(0.5)), ('pitch', 0, bits(2.0)), ('pan', 0, bits(1.0)),
        ('unload', 0), ('unalias', 0), ('update', 0, 0, []), ('close',))
    add('reopened', ('init',), ('load', 0, 'mono16'), ('play', 0), ('pause', 0), ('master', bits(0.5)), ('close',), ('init',), ('resume', 0), ('stop', 0),
        ('alias', 1, 0), ('unalias', 1), ('unload', 0), ('close',))
    add('file-boom', ('init',), ('file', 0, 'boom'), ('alias', 1, 0), ('file', 2, 'missing'), ('file', 3, 'text'), ('play', 0), ('unalias', 1), ('unload', 0), ('close',))
    add('file-buttonfx', ('init',), ('file', 0, 'buttonfx'), ('file', 1, 'other'), ('file', 2, 'tiny'), ('play', 2), ('unload', 2), ('unload', 0), ('close',))
    add('file-sound', ('init',), ('file', 0, 'sound'), ('alias', 1, 0), ('alias', 2, 0), ('alias', 3, 0), ('play', 0), ('play', 1), ('play', 2), ('play', 3),
        ('unalias', 1), ('unalias', 2), ('unalias', 3), ('unload', 0), ('close',))
    add('file-coin', ('init',), ('file', 0, 'coin'), ('volume', 0, bits(0.4)), ('pan', 0, bits(0.6)), ('play', 0), ('unload', 0), ('close',))

    add('mix-silence', ('init',), ('mix', 4), ('load', 0, 'mono16'), ('mix', 3), ('play', 0), ('pause', 0), ('mix', 2), ('master', bits(0.0)), ('mix', 1), ('close',))
    add('mix-to-the-end', ('init',), ('load', 0, 'mono16'), ('play', 0), ('mix', 3), ('mix', 3), ('mix', 480), ('mix', 4), ('play', 0), ('mix', 8), ('play', 0), ('mix', 7),
        ('pause', 0), ('mix', 5), ('resume', 0), ('mix', 1), ('mix', 1), ('close',))
    add('mix-levels', ('init',), ('load', 0, 'stereo16'), ('volume', 0, bits(0.5)), ('play', 0), ('mix', 2), ('pan', 0, bits(-1.0)), ('mix', 1), ('pan', 0, bits(1.0)), ('mix', 1),
        ('pan', 0, bits(0.25)), ('volume', 0, bits(-2.0)), ('mix', 1), ('master', bits(0.5)), ('mix', 1), ('play', 0), ('volume', 0, bits(400.0)), ('master', bits(3.5)),
        ('mix', 6), ('close',))
    add('mix-together', ('init',), ('load', 0, 'stereo16'), ('load', 1, 'mono8up'), ('alias', 2, 0), ('play', 0), ('mix', 2), ('play', 1), ('play', 2), ('pan', 2, bits(-0.5)),
        ('mix', 3), ('pause', 1), ('mix', 2), ('resume', 1), ('stop', 2), ('mix', 480), ('mix', 2), ('close',))
    add('mix-odd-size', ('init',), ('load', 0, 'five32'), ('play', 0), ('mix', 4), ('mix', 1), ('play', 0), ('mix', 480), ('play', 0), ('mix', 5), ('play', 0), ('mix', 3), ('mix', 2),
        ('load', 1, 'one'), ('play', 1), ('mix', 1), ('play', 1), ('mix', 9), ('close',))
    add('mix-odd-run', ('init',), ('load', 0, 'long513'), ('play', 0), ('mix', 600), ('play', 0), ('mix', 512), ('mix', 2), ('play', 0), ('mix', 100), ('mix', 500), ('play', 0),
        ('mix', 513), ('play', 0), ('mix', 511), ('mix', 2), ('close',))
    add('mix-pitch-back', ('init',), ('load', 0, 'stereo16'), ('pitch', 0, bits(2.0)), ('pitch', 0, bits(1.0)), ('play', 0), ('mix', 2), ('pitch', 0, bits(0.9999999)), ('mix', 2),
        ('pitch', 0, bits(1e9)), ('mix', 480), ('close',))
    add('mix-update', ('init',), ('load', 0, 'mono16'), ('alias', 1, 0), ('update', 0, 2, floats([0.5, -0.5, 2.0, -2.0])), ('play', 1), ('mix', 3), ('play', 0), ('mix', 480), ('close',))
    add('mix-file', ('init',), ('file', 0, 'boom'), ('play', 0), ('mix', 480), ('mix', 480), ('volume', 0, bits(0.4)), ('pan', 0, bits(0.6)), ('mix', 480), ('mix', 29000),
        ('play', 0), ('mix', 30000), ('close',))

    add('mix-pitched-down', ('init',), ('load', 0, 'tone'), ('pitch', 0, bits(2.0)), ('play', 0), ('mix', 3), ('mix', 5), ('mix', 480), ('play', 0), ('mix', 480), ('close',))
    add('mix-pitched-up', ('init',), ('load', 0, 'tone'), ('pitch', 0, bits(0.5)), ('play', 0), ('mix', 7), ('mix', 30), ('mix', 480), ('play', 0), ('mix', 1), ('mix', 600),
        ('close',))
    add('mix-pitched-ratios', ('init',), ('load', 0, 'tone'), ('pitch', 0, bits(1.5)), ('play', 0), ('mix', 480), ('pitch', 0, bits(0.8)), ('play', 0), ('mix', 480),
        ('pitch', 0, bits(1.0001)), ('play', 0), ('mix', 480), ('pitch', 0, bits(3.7)), ('play', 0), ('mix', 480), ('pitch', 0, bits(0.07)), ('play', 0), ('mix', 600),
        ('close',))
    add('mix-pitch-midway', ('init',), ('load', 0, 'tone'), ('play', 0), ('mix', 5), ('pitch', 0, bits(2.0)), ('mix', 4), ('pitch', 0, bits(1.0)), ('mix', 3),
        ('pitch', 0, bits(0.5)), ('mix', 9), ('pitch', 0, bits(1.3)), ('mix', 6), ('pause', 0), ('pitch', 0, bits(0.75)), ('resume', 0), ('mix', 4), ('pitch', 0, bits(1.0)),
        ('mix', 480), ('play', 0), ('mix', 480), ('close',))
    add('mix-pitched-together', ('init',), ('load', 0, 'tone'), ('alias', 1, 0), ('alias', 2, 0), ('pitch', 1, bits(1.25)), ('pitch', 2, bits(0.6)), ('volume', 1, bits(0.5)),
        ('pan', 2, bits(-0.75)), ('play', 0), ('play', 1), ('play', 2), ('mix', 10), ('mix', 20), ('mix', 480), ('close',))
    add('mix-pitched-long', ('init',), ('load', 0, 'long513'), ('pitch', 0, bits(2.5)), ('play', 0), ('mix', 480), ('play', 0), ('pitch', 0, bits(0.4)), ('mix', 2000),
        ('close',))
    add('mix-pitched-file', ('init',), ('file', 0, 'boom'), ('pitch', 0, bits(1.25)), ('play', 0), ('mix', 480), ('mix', 480), ('mix', 30000), ('close',))
    add('mix-pitched-then-back', ('init',), ('load', 0, 'stereo16'), ('pitch', 0, bits(2.0)), ('play', 0), ('mix', 2), ('pitch', 0, bits(1.0)), ('mix', 2), ('mix', 480),
        ('close',))

    ramp16 = s16([((i * 53) % 301 - 150) * 97 for i in range(600)])
    add('stream-load', ('init',), ('stream', 0, 44100, 16, 1), ('stream', 1, 48000, 32, 2), ('stream', 2, 22050, 8, 2), ('stream', 3, 96000, 16, 6), ('play', 0), ('pause', 0),
        ('resume', 0), ('stop', 0), ('volume', 1, bits(0.5)), ('pan', 2, bits(-0.5)), ('unload', 1), ('unload', 0), ('unload', 3), ('unload', 2), ('close',))
    add('stream-none', ('stream', 0, 44100, 16, 1), ('default', 480), ('init',), ('stream', 1, 0, 16, 1), ('stream', 2, 44100, 16, 0), ('play', 1), ('feed', 2, 0, []),
        ('unload', 2), ('stream', 3, 44100, 16, 255), ('stream', 0, 8000, 8, 1000), ('unload', 3), ('close',))
    add('stream-default', ('default', 100), ('init',), ('stream', 0, 44100, 16, 1), ('default', 600), ('stream', 1, 44100, 16, 2), ('default', 0), ('stream', 2, 48000, 8, 1),
        ('default', 479), ('stream', 3, 11025, 32, 3), ('close',), ('default', 7))
    add('stream-feed', ('default', 500), ('init',), ('stream', 0, 44100, 16, 1), ('feed', 0, 100, ramp16[:100]), ('feed', 0, 500, ramp16[100:600]), ('feed', 0, 10, ramp16[:10]),
        ('play', 0), ('feed', 0, 0, []), ('feed', 0, 501, []), ('feed', 0, 0xFFFFFFFF, []), ('feed', 0, 3, ramp16[5:8]), ('stop', 0), ('feed', 0, 1, ramp16[:1]),
        ('pause', 0), ('feed', 0, 2, ramp16[:2]), ('unload', 0), ('close',))
    add('stream-feed-formats', ('default', 480), ('init',), ('stream', 0, 22050, 8, 2), ('stream', 1, 48000, 32, 2), ('stream', 2, 32000, 16, 3),
        ('feed', 0, 4, [0, 255, 128, 127, 1, 254, 64, 192]), ('feed', 1, 2, floats([0.5, -0.5, 1.5, -0.0])), ('feed', 2, 2, s16([1, -1, 300, -300, 32767, -32768])),
        ('feed', 0, 480, [(i * 7) & 255 for i in range(960)]), ('feed', 1, 1, [NAN, bits(math.inf)]), ('close',))
    add('stream-pitch', ('init',), ('default', 480), ('stream', 0, 44100, 16, 1), ('pitch', 0, bits(2.0)), ('pitch', 0, bits(1.0)), ('pitch', 0, bits(0.91875)),
        ('stream', 1, 48000, 8, 2), ('pitch', 1, bits(0.5)), ('pitch', 1, bits(0.0)), ('stream', 2, 8000, 32, 1), ('pitch', 2, bits(6.0)), ('close',))

    tone32 = floats([((i * 29) % 61 - 30) / 32 for i in range(2000)])
    add('stream-play-silence', ('init',), ('default', 480), ('stream', 0, 44100, 16, 1), ('stream', 1, 22050, 8, 2), ('play', 0), ('mix', 7), ('play', 1), ('mix', 480),
        ('feed', 0, 4, s16([1, 2, 3, 4])), ('mix', 3), ('close',))
    add('stream-play', ('init',), ('default', 480), ('stream', 0, 48000, 32, 2), ('play', 0), ('feed', 0, 480, tone32[:960]), ('mix', 100), ('feed', 0, 300, tone32[960:1560]),
        ('mix', 480), ('mix', 480), ('feed', 0, 480, tone32[200:1160]), ('mix', 600), ('pause', 0), ('mix', 5), ('resume', 0), ('mix', 5), ('stop', 0), ('mix', 5),
        ('play', 0), ('feed', 0, 10, tone32[:20]), ('feed', 0, 480, tone32[20:980]), ('mix', 1000), ('close',))
    add('stream-play-mono', ('init',), ('default', 480), ('stream', 0, 44100, 16, 1), ('play', 0), ('feed', 0, 480, ramp16[:480]), ('feed', 0, 100, ramp16[480:580]),
        ('mix', 64), ('mix', 480), ('mix', 480), ('feed', 0, 480, ramp16[100:580]), ('pitch', 0, bits(1.5)), ('mix', 480), ('pitch', 0, bits(0.25)), ('mix', 480),
        ('close',))
    add('stream-play-bytes', ('init',), ('default', 500), ('stream', 0, 22050, 8, 2), ('stream', 1, 8000, 8, 1), ('play', 0), ('play', 1),
        ('feed', 0, 500, [(i * 37 + 11) & 255 for i in range(1000)]), ('feed', 1, 200, [(i * 91 + 3) & 255 for i in range(200)]), ('mix', 480), ('volume', 1, bits(0.5)),
        ('pan', 0, bits(0.75)), ('mix', 480), ('mix', 480), ('close',))
    add('stream-play-channels', ('init',), ('default', 480), ('stream', 0, 32000, 16, 3), ('stream', 1, 96000, 32, 6), ('play', 0), ('play', 1),
        ('feed', 0, 400, s16([((i * 53) % 301 - 150) * 97 for i in range(1200)])), ('feed', 1, 480, floats([((i * 31) % 67 - 33) / 64 for i in range(2880)])), ('mix', 200),
        ('mix', 480), ('pitch', 1, bits(3.0)), ('feed', 1, 480, floats([((i * 17) % 71 - 35) / 64 for i in range(2880)])), ('mix', 480), ('close',))
    add('stream-play-passes', ('init',), ('default', 480), ('stream', 0, 48000, 16, 400), ('play', 0), ('feed', 0, 6, s16([((i * 7) % 201 - 100) * 150 for i in range(2400)])),
        ('pitch', 0, bits(6.0)), ('mix', 3), ('mix', 5), ('pitch', 0, bits(1.0)), ('mix', 4), ('close',))
    add('stream-with-sounds', ('init',), ('default', 480), ('load', 0, 'tone'), ('stream', 1, 44100, 16, 1), ('play', 0), ('play', 1), ('feed', 1, 300, ramp16[:300]),
        ('pitch', 0, bits(0.5)), ('mix', 100), ('alias', 2, 0), ('play', 2), ('mix', 480), ('unload', 1), ('mix', 10), ('close',))

    # Streams with a callback: the frames are the callback's, asked for by raudio's guess and again while the converter wants more.
    add('stream-callback', ('init',), ('default', 480), ('stream', 0, 44100, 32, 1), ('play', 0), ('callback', 0, 1), ('mix', 480), ('mix', 480), ('mix', 1), ('mix', 600),
        ('pause', 0), ('mix', 5), ('resume', 0), ('mix', 5), ('stop', 0), ('mix', 5), ('play', 0), ('mix', 100), ('close',))
    add('stream-callback-formats', ('init',), ('default', 500), ('stream', 0, 22050, 16, 2), ('stream', 1, 8000, 8, 3), ('callback', 0, 1), ('callback', 1, 1), ('play', 0),
        ('play', 1), ('mix', 480), ('pitch', 0, bits(1.5)), ('volume', 1, bits(0.5)), ('mix', 480), ('pitch', 1, bits(0.3)), ('mix', 700), ('close',))
    add('stream-callback-off', ('init',), ('default', 480), ('stream', 0, 48000, 32, 2), ('play', 0), ('feed', 0, 480, tone32[:960]), ('mix', 100), ('callback', 0, 1),
        ('mix', 200), ('feed', 0, 480, tone32[200:1160]), ('mix', 50), ('callback', 0, 0), ('mix', 480), ('mix', 480), ('close',))
    add('stream-callback-with-sounds', ('init',), ('default', 480), ('load', 0, 'tone'), ('stream', 1, 44100, 16, 1), ('stream', 2, 96000, 32, 6), ('callback', 1, 1),
        ('callback', 2, 1), ('play', 0), ('play', 1), ('play', 2), ('pitch', 0, bits(0.5)), ('mix', 300), ('unload', 1), ('mix', 300), ('stream', 1, 32000, 8, 1),
        ('callback', 1, 1), ('play', 1), ('mix', 64), ('close',))
    # The clock's periods with a callback: each period asks, answers and mixes; a closed device makes none.
    add('clock-periods', ('init',), ('default', 480), ('load', 0, 'tone'), ('stream', 1, 44100, 32, 1), ('stream', 2, 22050, 16, 2), ('callback', 1, 1), ('play', 0), ('play', 1),
        ('play', 2), ('feed', 2, 480, ramp16[:480] + ramp16[:480]), ('periods', 3), ('pitch', 1, bits(2.0)), ('periods', 2), ('periods', 0), ('callback', 1, 0), ('periods', 1),
        ('close',), ('periods', 2))
    # Processors: a stream's on each run of at most 512 frames it gives, in the order attached, then the mixed ones on
    # the whole mix; a detach takes every one with the function.
    add('processors', ('init',), ('default', 480), ('load', 0, 'tone'), ('stream', 1, 48000, 32, 2), ('attach', 1, 1), ('attach', 0, 2), ('attach', 0, 3), ('play', 0),
        ('play', 1), ('feed', 1, 480, tone32[:960]), ('mix', 30), ('attach', 0, 2), ('attach', 1, 3), ('mix', 20), ('detach', 0, 2), ('mix', 100), ('attachmixed', 1),
        ('attachmixed', 3), ('mix', 64), ('detachmixed', 1), ('detach', 1, 2), ('mix', 5), ('detachmixed', 3), ('detach', 1, 1), ('detach', 1, 3), ('detach', 0, 3), ('mix', 5),
        ('close',))
    add('processors-runs', ('init',), ('default', 600), ('stream', 0, 44100, 16, 1), ('stream', 1, 22050, 8, 2), ('callback', 0, 1), ('attach', 0, 2), ('attach', 0, 3),
        ('attach', 1, 1), ('attachmixed', 2), ('play', 0), ('play', 1), ('feed', 1, 600, [(i * 37 + 11) & 255 for i in range(1200)]), ('mix', 600), ('mix', 1100),
        ('pause', 0), ('mix', 513), ('stop', 1), ('close',), ('init',), ('mix', 3), ('close',))
    add('processors-clock', ('init',), ('default', 480), ('stream', 0, 44100, 32, 1), ('callback', 0, 1), ('attach', 0, 3), ('attachmixed', 2), ('play', 0), ('periods', 3),
        ('detach', 0, 3), ('periods', 2), ('close',))
    add('refused-processor-zero', ('init',), ('attach', 0, 1))
    add('refused-processor-detach-zero', ('init',), ('detach', 0, 1))
    add('refused-processor-unready', ('attachmixed', 1), ('init',), ('default', 480), ('stream', 0, 44100, 16, 1), ('close',), ('attach', 0, 1))
    add('refused-processor-loses-a-sample', ('init',), ('load', 0, 'tone'), ('attach', 0, 9), ('play', 0), ('mix', 4))
    add('refused-mixed-processor-loses-a-sample', ('init',), ('attachmixed', 9), ('mix', 4))
    # Music: a WAV file's frames through the two halves of a stream, looping (the file again from its first frame) or to
    # its end, where the music stops; a stop and a seek move the decoder.
    add('music', ('init',), ('default', 480), ('music', 0, 'm16'), ('play', 0), ('musicupdate', 0), ('mix', 480), ('musicupdate', 0), ('mix', 480), ('mix', 480),
        ('musicupdate', 0), ('mix', 300), ('musicstop', 0), ('musicupdate', 0), ('play', 0), ('musicupdate', 0), ('mix', 100), ('musicupdate', 0), ('close',))
    add('music-once', ('init',), ('default', 480), ('music', 0, 'm16'), ('looping', 0, 0), ('play', 0), ('musicupdate', 0), ('mix', 480), ('musicupdate', 0), ('mix', 480),
        ('musicupdate', 0), ('mix', 480), ('musicupdate', 0), ('mix', 10), ('play', 0), ('musicupdate', 0), ('mix', 200), ('close',))
    add('music-formats', ('init',), ('default', 600), ('music', 0, 'm24'), ('music', 1, 'mf32'), ('music', 2, 'mi32'), ('music', 3, 'missing'), ('play', 0), ('play', 1),
        ('play', 2), ('play', 3), ('musicupdate', 0), ('musicupdate', 1), ('musicupdate', 2), ('musicupdate', 3), ('mix', 480), ('volume', 1, bits(0.5)),
        ('pitch', 2, bits(1.5)), ('pan', 0, bits(-0.5)), ('musicupdate', 2), ('mix', 480), ('musicupdate', 0), ('musicupdate', 1), ('musicupdate', 2), ('mix', 480), ('close',))
    add('music-seek', ('init',), ('default', 480), ('music', 0, 'mf32'), ('play', 0), ('musicupdate', 0), ('mix', 480), ('seek', 0, bits(0.0125)), ('musicupdate', 0),
        ('mix', 100), ('seek', 0, bits(5.0)), ('musicupdate', 0), ('mix', 100), ('looping', 0, 0), ('seek', 0, bits(0.02)), ('musicupdate', 0), ('mix', 480),
        ('musicupdate', 0), ('mix', 480), ('musicupdate', 0), ('seek', 0, bits(-0.00001)), ('musicupdate', 0), ('close',))
    add('music-pause', ('init',), ('default', 480), ('music', 0, 'm16'), ('musicupdate', 0), ('play', 0), ('pause', 0), ('musicupdate', 0), ('mix', 100), ('resume', 0),
        ('mix', 500), ('musicupdate', 0), ('stop', 0), ('musicupdate', 0), ('play', 0), ('musicupdate', 0), ('mix', 50), ('musicunload', 0), ('mix', 5), ('close',))
    add('music-unready', ('music', 0, 'm16'), ('play', 0), ('musicupdate', 0), ('init',), ('default', 480), ('music', 1, 'm24'), ('play', 1),
        ('musicupdate', 1), ('mix', 480), ('musicupdate', 0), ('musicstop', 1), ('close',))
    add('music-processed', ('init',), ('default', 480), ('music', 0, 'mi32'), ('attach', 0, 1), ('play', 0), ('musicupdate', 0), ('periods', 2), ('musicupdate', 0),
        ('periods', 1), ('close',))
    # QOA music: floats of sample/32768.0; a seek goes to the QOA frame (5120 samples) the position is in, at most the
    # last one's start; a read past the file's end goes on from its first frame.
    add('music-qoa', ('init',), ('default', 2000), ('music', 0, 'target'), ('play', 0), ('musicupdate', 0), ('mix', 480), ('musicupdate', 0), ('seek', 0, bits(0.5)),
        ('musicupdate', 0), ('mix', 100), ('seek', 0, bits(1.99)), ('musicupdate', 0), ('mix', 480), ('mix', 480), ('mix', 480), ('mix', 480), ('mix', 480),
        ('musicupdate', 0), ('seek', 0, bits(50.0)), ('musicupdate', 0), ('mix', 480), ('musicstop', 0), ('looping', 0, 0), ('play', 0), ('musicupdate', 0), ('mix', 50),
        ('close',))
    add('music-qoa-whole-halves', ('init',), ('music', 0, 'target'), ('play', 0), ('musicupdate', 0), ('mix', 480), ('musicupdate', 0), ('seek', 0, bits(1.5)),
        ('musicupdate', 0), ('mix', 480), ('close',))
    turn = [('musicupdate', 0), ('mix', 480), ('mix', 480)]
    add('music-mp3', ('init',), ('default', 2000), ('music', 0, 'mp3tag'), ('play', 0), *(turn * 14), ('musicstop', 0), ('play', 0), ('musicupdate', 0), ('mix', 480),
        ('seek', 0, bits(0.1)), ('musicupdate', 0), ('mix', 480), ('seek', 0, bits(0.02)), ('musicupdate', 0), ('mix', 200), ('close',))
    add('music-mp3-counted', ('init',), ('default', 2000), ('music', 0, 'mp3plain'), ('play', 0), ('musicupdate', 0), ('mix', 480), ('seek', 0, bits(0.05)), ('musicupdate', 0),
        ('mix', 480), ('seek', 0, bits(0.01)), ('musicupdate', 0), ('mix', 480), ('seek', 0, bits(0.0)), ('musicupdate', 0), ('mix', 300), ('looping', 0, 0), *(turn * 9),
        ('musicupdate', 0), ('musicunload', 0), ('close',))
    add('refused-music-8-bit', ('init',), ('music', 0, 'm8'))
    add('refused-music-seek-negative', ('init',), ('default', 480), ('music', 0, 'm16'), ('seek', 0, bits(-1.0)))
    add('refused-music-seek-no-buffer', ('music', 0, 'm16'), ('seek', 0, bits(0.5)))
    add('refused-music-seek-nothing', ('init',), ('seek', 0, bits(0.5)))
    add('stream-callback-zero', ('init',), ('callback', 0, 1), ('default', 480), ('stream', 0, 44100, 16, 1), ('callback', 0, 0), ('play', 0), ('mix', 10), ('close',))
    add('refused-callback-unanswered', ('init',), ('default', 480), ('stream', 0, 44100, 32, 1), ('callback', 0, 1), ('plain', 4), ('play', 0), ('plain', 4))
    add('refused-callback-sound', ('init',), ('load', 0, 'mono16'), ('callback', 0, 1))
    add('refused-callback-unready', ('init',), ('default', 480), ('stream', 0, 44100, 16, 1), ('close',), ('callback', 0, 1))

    add('refused-mix-stream-wide', ('init',), ('default', 480), ('stream', 0, 48000, 16, 1025), ('play', 0), ('mix', 2))
    add('stream-play-tiny', ('init',), ('default', 480), ('stream', 0, 48000, 32, 3), ('play', 0), ('feed', 0, 3, floats([0.5, 1e-35, 0.25, 1e-38, 2e-38, -1e-38, 1e-41, 0.5, -1e-44])), ('mix', 5), ('close',))
    add('refused-stream-size', ('init',), ('stream', 0, 44100, 24, 1), ('stream', 1, 44100, 0, 1))
    add('refused-stream-negative-default', ('init',), ('default', 0xFFFFFFFF), ('stream', 0, 44100, 16, 1))
    add('refused-stream-too-large', ('init',), ('default', 3000000), ('stream', 0, 44100, 16, 1), ('default', 20000), ('stream', 1, 44100, 16, 200))
    add('refused-stream-feed-list', ('init',), ('default', 480), ('stream', 0, 44100, 16, 2), ('feed', 0, 3, s16([1, 2, 3, 4, 5])), ('feed', 0, 2, s16([1, 2, 3, 4, 5])))
    add('refused-stream-feed-sound', ('init',), ('load', 0, 'mono16'), ('feed', 0, 2, floats([0.5, 0.5, 0.25, 0.25])))
    add('refused-stream-update-sound', ('init',), ('default', 480), ('stream', 0, 48000, 32, 2), ('update', 0, 1, floats([0.5, 0.5])))
    add('refused-stream-unready', ('init',), ('default', 480), ('stream', 0, 44100, 16, 1), ('close',), ('feed', 0, 1, s16([1])), ('play', 0))
    add('refused-mix-unready', ('mix', 4), ('init',), ('load', 0, 'mono16'), ('play', 0), ('close',), ('mix', 4))
    add('refused-mix-no-frames', ('init',), ('mix', 0))
    add('refused-mix-too-long', ('init',), ('mix', 1048577))
    add('refused-mix-empty-buffer', ('init',), ('load', 0, 'noframes'), ('play', 0), ('mix', 2))
    add('refused-mix-freed', ('init',), ('load', 0, 'mono16'), ('alias', 1, 0), ('unload', 0), ('play', 1), ('mix', 2))
    add('mix-subnormal', ('init',), ('load', 0, 'tiny32'), ('play', 0), ('mix', 1), ('mix', 3), ('close',))
    add('mix-subnormal-levels', ('init',), ('load', 0, 'stereo16'), ('volume', 0, bits(1e-40)), ('play', 0), ('mix', 2), ('volume', 0, bits(1e-36)), ('pan', 0, bits(-0.99999994)),
        ('mix', 2), ('master', bits(1e-39)), ('mix', 1), ('master', bits(1e-20)), ('volume', 0, bits(1e-20)), ('mix', 1), ('pan', 0, 1), ('mix', 1), ('close',))
    add('refused-mix-nan-master', ('init',), ('master', NAN), ('mix', 2))
    add('refused-mix-nan-pan', ('init',), ('load', 0, 'stereo16'), ('pan', 0, NAN), ('play', 0), ('mix', 2))
    add('refused-mix-infinite', ('init',), ('load', 0, 'stereo16'), ('update', 0, 1, [bits(math.inf), bits(0.5)]), ('play', 0), ('mix', 2))
    add('refused-unready-load', ('load', 0, 'mono16'), ('file', 1, 'tiny'), ('file', 2, 'missing'), ('init',), ('close',), ('load', 3, 'stereo16'))
    add('refused-waves', ('init',), ('load', 0, 'size24'), ('load', 1, 'short'), ('load', 2, 'nan'), ('load', 3, 'hugerate'), ('load', 0, 'mono16'), ('close',))
    add('refused-stale-handle', ('init',), ('load', 0, 'mono16'), ('load', 1, 'stereo16'), ('unload', 0), ('play', 0), ('volume', 0, bits(0.5)), ('alias', 2, 0),
        ('unload', 0), ('unalias', 0), ('update', 0, 1, floats([1.0, 1.0])), ('pause', 0), ('close',))
    add('refused-freed-samples', ('init',), ('load', 0, 'mono16'), ('alias', 1, 0), ('unload', 0), ('alias', 2, 1), ('update', 1, 1, floats([1.0, 1.0])),
        ('play', 1), ('unalias', 1), ('close',))
    add('refused-alias-of-zero', ('init',), ('alias', 1, 0), ('load', 0, 'zero'), ('alias', 2, 0), ('close',))
    add('refused-second-init', ('init',), ('master', bits(0.5)), ('load', 0, 'mono16'), ('init',), ('close',))
    add('refused-unready-buffers', ('init',), ('load', 0, 'mono16'), ('load', 1, 'stereo16'), ('play', 1), ('close',), ('play', 0), ('stop', 1), ('pause', 0),
        ('resume', 0), ('volume', 0, bits(0.5)), ('pitch', 0, bits(2.0)), ('pan', 0, bits(1.0)), ('alias', 2, 0), ('update', 0, 1, floats([1.0, 1.0])),
        ('unalias', 1), ('unload', 0))
    add('refused-unready-stop', ('stop', 0))
    add('refused-update-past', ('init',), ('load', 0, 'mono16'), ('play', 0), ('update', 0, 9, floats([0.0] * 18)), ('close',))
    add('refused-update-negative', ('init',), ('load', 0, 'mono16'), ('play', 0), ('update', 0, 0xFFFFFFFF, []), ('close',))
    add('refused-update-short', ('init',), ('load', 0, 'mono16'), ('play', 0), ('update', 0, 2, floats([0.0, 0.0, 0.0])), ('update', 0, 1, floats([0.0, 0.0, 0.0])), ('close',))
    add('refused-update-empty', ('init',), ('load', 0, 'noframes'), ('play', 0), ('update', 0, 0, []), ('close',))
    add('refused-pitch', ('init',), ('load', 0, 'mono16'), ('pitch', 0, bits(1e-5)), ('pitch', 0, 1), ('pitch', 0, bits(1.1175870895385742e-05)), ('close',))
    return out


class Model:
    """raudio's state for one case; `undefined` once raylib has no defined answer for a step."""

    def __init__(self, catalog):
        self.catalog, self.ready, self.master, self.next, self.default = catalog, False, 0, 1, 0
        self.buffers, self.blocks, self.sounds, self.undefined = [], {}, [ZERO] * SLOTS, False
        self.calls, self.asks = [0] * SLOTS, []
        self.attached, self.proc, self.log = [], dict(count=0, prev=[0, 0]), []
        self.musics, self.music_files = [None] * SLOTS, music_files()

    def buffer(self, slot):
        number = self.sounds[slot][0]
        return next((b for b in self.buffers if b['id'] == number), None) if self.ready else None

    def used(self, slot, *, zero_fine=True):
        """The tracked buffer of a slot; a handle raylib cannot use makes the case undefined."""
        number = self.sounds[slot][0]
        if number == 0:
            self.undefined |= not zero_fine
            return None
        found = self.buffer(slot)
        self.undefined |= found is None
        return found

    def track(self, frames, block, source=48000, stream=None):
        held = 2 if stream is None else min(stream['channels'], 2)
        rin, rout = reduced(source, 48000)
        self.buffers.append(dict(id=self.next, block=block, frames=frames, volume=bits(1.0), pitch=bits(1.0), pan=0, playing=False, paused=False, source=source,
                                 rate=48000, cursor=0, t_int=1, t_frac=0, x0=[0.0] * held, x1=[0.0] * held, r1=[0.0] * held, residual=[], coef=coefficient(rin, rout),
                                 wide=max(rin, rout) >= 1 << 31, stream=stream))
        self.next += 1
        return self.next - 1

    def rewind(self, found):
        found['cursor'] = 0
        if found['stream'] is not None:
            found['stream'].update(first=True, second=True, done=0)

    def stop(self, found):
        if found['playing'] and not found['paused']:
            found['playing'] = False
            self.rewind(found)

    def stream(self, slot, rate, size, channels):
        """LoadAudioStream: raylib gives a buffer on a ready device for a rate and channels that are not 0; Jonlib for fewer."""
        self.sounds[slot] = (0, 0, rate, size, channels)
        if not (self.ready and rate > 0 and channels > 0):
            return
        half = max(self.default or 12800, 480)
        if size not in (8, 16, 32) or self.default >= 1 << 31 or 2 * half * channels > 1 << 22:
            self.undefined = True
            return
        number = self.track(2 * half, self.next, rate, dict(size=size, channels=channels, first=True, second=True, called=False, done=0))
        self.blocks[number] = [0] * (2 * half * channels)
        self.sounds[slot] = (number, 0, rate, size, channels)

    def feed(self, slot, frames, words):
        """UpdateAudioStream."""
        found = self.used(slot)
        if found is None:
            return
        stream = found['stream']
        if stream is None or found['block'] not in self.blocks:
            self.undefined = True
            return
        target = 0 if stream['first'] else 1 if stream['second'] else None
        if target is None:
            return
        half, channels = found['frames'] // 2, stream['channels']
        if frames <= half and len(words) != frames * channels:
            self.undefined = True
            return
        if stream['first'] and stream['second']:
            found['cursor'] = 0
        stream['done'] = (stream['done'] + frames) & 0xFFFFFFFF      # framesProcessed: the frames asked for, written or not
        if frames <= half:
            start = target * half * channels
            self.blocks[found['block']][start:start + half * channels] = list(words) + [0] * ((half - frames) * channels)
            stream['first' if target == 0 else 'second'] = False

    def answer(self, b, calls, asks, count):
        """The probe's stream callback: `count` frames from the counter of the slot that holds the stream."""
        slot = next(i for i, sound in enumerate(self.sounds) if sound[0] == b['id'])
        size, channels = b['stream']['size'], b['stream']['channels']
        asks.append((b['id'], count))
        b['stream']['done'] = (b['stream']['done'] + count) & 0xFFFFFFFF
        words = [answer_sample(size, calls[slot] + i) for i in range(count * channels)]
        calls[slot] += count * channels
        return [words[i * channels:(i + 1) * channels] for i in range(count)]

    def process(self, tag, flat, proc, log):
        """The probe's processors on the samples of a run (f32 bits, two a frame): half the level; the sides swapped
        and a counted offset on the right; a delay of one frame; and (Jonlib only) one that loses a sample."""
        log.append((tag, len(flat) // 2))
        if tag == 1:
            return [bits(fmul(fl(w), 0.5)) for w in flat]
        if tag == 2:
            out = []
            for i in range(0, len(flat), 2):
                out += [flat[i + 1], bits(fadd(fl(flat[i]), (proc['count'] % 5) / 8))]
                proc['count'] += 1
            return out
        if tag == 3:
            out = []
            for i in range(0, len(flat), 2):
                out += proc['prev']
                proc['prev'] = flat[i:i + 2]
            return out
        return flat[:-1]

    def music(self, slot, name):
        """LoadMusicStream: a stream of the file's format, looping; no music for a file raylib does not open."""
        self.musics[slot], self.sounds[slot] = None, ZERO
        if name in RAW_FILES:               # QOA: a float stream of sample/32768.0, and seeks to QOA frames of 5120 samples
            frames, rate, _, channels, words = self.catalog['raw', name]
            self.stream(slot, rate, 32, channels)
            self.musics[slot] = dict(frames=frames, looping=True, at=0, samples=[bits((w - 65536 if w >= 32768 else w) / 32768.0) for w in words], rate=rate, channels=channels, qoa=True)
            return '-'
        if name in MP3_FILES:               # dr_mp3: a float stream of sample/32768.0, read through the stream's count of frames
            frames, rate, channels, delay, readable, words = self.catalog['mp3', name]
            self.stream(slot, rate, 32, channels)
            self.musics[slot] = dict(frames=frames, looping=True, at=0, samples=[bits((w - 65536 if w >= 32768 else w) / 32768.0) for w in words], rate=rate, channels=channels, qoa=False,
                                     mp3=dict(delay=delay, readable=readable, read=0, started=False))
            return '-'
        if name not in self.music_files:
            return FILE_ERRORS[name]
        _, rate, size, channels, frames, samples = self.music_files[name]
        if size is None:
            self.undefined = True          # raylib streams what its shared buffer holds
            return 'unsupported'
        self.stream(slot, rate, size, channels)
        self.musics[slot] = dict(frames=frames, looping=True, at=0, samples=samples, rate=rate, channels=channels, qoa=False)
        return '-'

    def music_stop(self, slot):
        """StopMusicStream: the stream stops, and the decoder is at its first frame either way."""
        self.undefined |= not self.ready
        found = self.used(slot)
        if found is not None:
            self.stop(found)
        if self.musics[slot] is not None:
            self.musics[slot]['at'] = 0
            if 'mp3' in self.musics[slot]:
                self.musics[slot]['mp3'].update(read=0, started=False)

    @staticmethod
    def mp3_read(m, need):
        """drmp3_read_pcm_frames: `need` frames or what the stream has left (its readable frames are those after the LAME delay, up to
        its end). currentPCMFrame, which is what a seek goes by, counts the delay once a frame was read."""
        state = m['mp3']
        take = min(need, state['readable'] - state['read'])
        data = m['samples'][state['read'] * m['channels']:(state['read'] + take) * m['channels']]
        state['read'] += take
        state['started'] = state['started'] or state['readable'] > 0
        m['at'] = (state['delay'] if state['started'] else 0) + state['read']
        return take, data

    @staticmethod
    def mp3_rewind(m):
        m['mp3'].update(read=0, started=False)
        m['at'] = 0

    def music_update(self, slot):
        """UpdateMusicStream."""
        m, found = self.musics[slot], self.used(slot)
        if m is None or found is None or not found['playing']:
            return
        sub = found['frames'] // 2
        for half in ('first', 'second'):
            stream = found['stream']
            left = (m['frames'] - stream['done']) & 0xFFFFFFFF
            count = sub if left >= sub or m['looping'] else left
            if count == 0:
                if stream['first'] and stream['second']:
                    self.music_stop(slot)
                return
            if not stream[half]:
                continue
            data, need = [], count
            while need and 'mp3' in m:                      # the stream again from its start while more are needed
                take, more = self.mp3_read(m, need)
                data, need = data + more, need - take
                if need:
                    self.mp3_rewind(m)
            while need:                                     # the file again from its first frame while more are needed
                take = min(need, m['frames'] - m['at'])
                data += m['samples'][m['at'] * m['channels']:(m['at'] + take) * m['channels']]
                m['at'], need = m['at'] + take, need - take
                if need:
                    m['at'] = 0
            self.feed(slot, count, data)

    def music_seek(self, slot, word):
        """SeekMusicStream: raylib writes through the stream's buffer pointer."""
        m, found = self.musics[slot], self.used(slot, zero_fine=False)
        if m is None or found is None:
            self.undefined = True
            return
        frame = f32(fl(word) * float(m['rate']))
        if not -1.0 < frame < 4294967296.0:
            self.undefined = True
            return
        if 'mp3' in m:                      # drmp3_seek_to_pcm_frame: by its count, reading up to the frame (from the start when the count passed it)
            if int(frame) == 0:
                self.mp3_rewind(m)
            elif int(frame) > m['at']:
                self.mp3_read(m, int(frame) - m['at'])
            elif int(frame) < m['at']:
                self.mp3_rewind(m)
                self.mp3_read(m, int(frame))
            found['stream'].update(first=True, second=True, done=int(frame))
            return
        if m['qoa']:                        # qoaplay_seek_frame, and its sample_position is the frames given
            m['at'] = min(int(frame) // 5120, m['frames'] // 5120) * 5120
            found['stream'].update(first=True, second=True, done=m['at'])
            return
        m['at'] = min(int(frame), m['frames']) if m['frames'] else m['at']
        found['stream'].update(first=True, second=True, done=int(frame))

    def music_text(self, slot):
        m = self.musics[slot]
        if m is None:
            return 'U-'
        number, found = self.sounds[slot][0], self.buffer(slot)
        length = bits(f32(f32(float(m['frames'])) / f32(float(m['rate']))))
        if number == 0:
            played = bits(0.0)
        elif found is None:
            played = '-'
        else:
            stream, sub = found['stream'], found['frames'] // 2
            held = (0 if stream['first'] else sub) + (0 if stream['second'] else sub)
            if held > m['frames'] and not m['looping']:
                held = m['frames']
            a = stream['done'] - held + found['cursor'] % sub
            rest = abs(a) % m['frames']                     # C's remainder has the sign of the dividend
            rest = m['frames'] - rest if a < 0 and rest else rest
            played = bits(f32(f32(float(rest)) / f32(float(m['rate']))))
        return f'U1,{m["frames"]},{int(m["looping"])},{m["at"]},{length},{played}'

    def mix(self, frames, answered=True):
        """One device callback: the samples, or None (and nothing changed) for what Jonlib refuses."""
        self.asks, self.log = [], []
        if not self.ready or frames == 0 or frames > 1 << 20 or math.isnan(fl(self.master)):
            return None
        out, fine, after, calls, asks = [0] * (2 * frames), True, [], list(self.calls), []
        proc, log = copy.deepcopy(self.proc), []
        for b in self.buffers:
            if not b['playing'] or b['paused']:
                after.append(b)
                continue
            data = self.blocks.get(b['block'])
            if data is None:
                return None
            volume, pan = fl(b['volume']), fl(b['pan'])
            right = fdiv(fadd(pan, 1.0), 2.0)
            left = fsub(1.0, right)
            levels = [fmul(fmul(fmul(volume, 0.5), side), fsub(3.0, fmul(side, side))) for side in (left, right)]
            fine &= not nans(*levels)
            b = copy.deepcopy(b)
            made, ok = turn(b, data, frames, lambda count, b=b: self.answer(b, calls, asks, count))
            fine &= ok
            tags = [tag for number, tag in self.attached if number == b['id']]
            for start in range(0, len(made) if tags else 0, 512):       # raudio's runs of at most 512 frames
                run = [bits(v) for frame in made[start:start + 512] for v in frame]
                for tag in tags:
                    run = self.process(tag, run, proc, log)
                fine &= len(run) == 2 * len(made[start:start + 512])
                if not fine:
                    break
                made[start:start + 512] = [[fl(run[2 * i]), fl(run[2 * i + 1])] for i in range(len(run) // 2)]
            if not fine:
                return None
            for j, frame in enumerate(made):
                for channel in range(2):
                    new = fadd(fl(out[2 * j + channel]), fmul(frame[channel], levels[channel]))
                    fine &= not math.isnan(new)
                    out[2 * j + channel] = bits(new)
            after.append(b)
        for tag in [tag for number, tag in self.attached if number == 0]:    # the mixed processors, on the whole mix
            out = self.process(tag, out, proc, log)
        if len(out) != 2 * frames:
            return None
        master, sent = fl(self.master), []
        for word in out:
            x = fmul(fl(word), master) if self.master != bits(1.0) else fl(word)
            fine &= not math.isnan(x)
            sent.append(bits(-1.0 if x < -1 else 1.0 if x > 1 else x))
        if not fine or (asks and not answered):
            return None
        self.buffers, self.calls, self.asks, self.proc, self.log = after, calls, asks, proc, log
        return sent

    def loaded(self, slot, entry):
        if not self.ready:
            self.undefined = True
            self.sounds[slot] = ZERO
            return 'device'
        if isinstance(entry, str):
            self.undefined = True
            self.sounds[slot] = ZERO
            return entry
        if entry is None:
            self.sounds[slot] = ZERO
            return '-'
        frames, words = entry
        number = self.track(frames, self.next if frames else 0)
        if frames:
            self.blocks[number] = list(words)
        self.sounds[slot] = (number, frames, 48000, 32, 2)
        return '-'

    def step(self, step):
        kind, tag = step[0], '-'
        if kind == 'init':
            if any(b['playing'] and not b['paused'] for b in self.buffers):
                raise ValueError('the reference device would mix a playing buffer before it is stopped')
            self.undefined |= self.ready
            if not self.ready:
                self.ready, self.master = True, bits(1.0)
        elif kind == 'close':
            if self.ready:
                self.ready, self.master = False, 0
        elif kind == 'master':
            if not fl(step[1]) < 0:
                self.master = step[1]
        elif kind == 'load':
            tag = self.loaded(step[1], self.catalog['wave', step[2]])
        elif kind == 'file':
            entry = self.catalog['file', step[2]]
            if step[2] in FILE_ERRORS:
                self.sounds[step[1]], tag = ZERO, FILE_ERRORS[step[2]]
            else:
                tag = self.loaded(step[1], entry)
        elif kind == 'alias':
            slot, source, frames = step[1], self.used(step[2], zero_fine=False), self.sounds[step[2]][1]
            self.sounds[slot] = ZERO
            if source is not None and source['block']:
                if source['block'] in self.blocks:
                    self.sounds[slot] = (self.track(source['frames'], source['block']), frames, 48000, 32, 2)
                else:
                    self.undefined = True
        elif kind in ('unload', 'unalias'):
            found = self.used(step[1])
            if found is not None:
                self.buffers.remove(found)
                if kind == 'unload':
                    self.blocks.pop(found['block'], None)
        elif kind in STATE:
            self.undefined |= kind == 'stop' and not self.ready
            found = self.used(step[1])
            if found is not None:
                if kind == 'play':
                    found['playing'], found['paused'] = True, False
                    self.rewind(found)
                elif kind == 'stop':
                    self.stop(found)
                else:
                    found['paused'] = kind == 'pause'
        elif kind in TUNE:
            value = fl(step[2])
            wide = kind == 'pitch' and value > 0 and not f32(48000.0 / value) < 4294967296.0
            if wide and self.sounds[step[1]][0]:
                self.undefined = True
            found = None if wide else self.used(step[1])
            if found is not None:
                if kind == 'volume':
                    found['volume'] = step[2]
                elif kind == 'pitch':
                    if value > 0:
                        found['pitch'] = step[2]
                        if int(f32(48000.0 / value)):
                            set_rate(found, int(f32(48000.0 / value)))
                else:
                    found['pan'] = bits(-1.0) if value < -1 else bits(1.0) if value > 1 else step[2]
        elif kind == 'update':
            _, slot, frames, words = step
            found = self.used(slot)
            if found is not None:
                valid = frames <= found['frames'] and len(words) == 2 * frames and found['stream'] is None
                held = found['block'] in self.blocks
                self.undefined |= not (valid and held)
                if valid and held:
                    self.stop(found)
                    self.blocks[found['block']][:len(words)] = words
        elif kind in ('mix', 'plain'):
            self.mixed = self.mix(step[1], answered=kind == 'mix')
            self.undefined |= self.mixed is None
        elif kind == 'periods':
            asks, log, self.mixed = [], [], []
            for _ in range(step[1] if self.ready else 0):     # an unready device makes no callback
                if self.mix(480) is None:
                    self.undefined, self.mixed = True, None
                    break
                asks += self.asks
                log += self.log
            self.asks, self.log = asks, log
        elif kind == 'music':
            tag = self.music(step[1], step[2])
        elif kind == 'musicupdate':
            self.music_update(step[1])
        elif kind == 'musicstop':
            self.music_stop(step[1])
        elif kind == 'seek':
            self.music_seek(step[1], step[2])
        elif kind == 'looping':
            if self.musics[step[1]] is not None:
                self.musics[step[1]]['looping'] = bool(step[2])
        elif kind == 'musicunload':
            found = self.used(step[1])
            if found is not None:
                self.buffers.remove(found)
                self.blocks.pop(found['block'], None)
            self.musics[step[1]] = None
        elif kind in ('attach', 'detach'):
            found = self.used(step[1], zero_fine=False)       # raylib reads through the stream's buffer pointer
            if found is not None:
                if kind == 'attach':
                    self.attached.append((found['id'], step[2]))
                else:
                    self.attached = [entry for entry in self.attached if entry != (found['id'], step[2])]
        elif kind in ('attachmixed', 'detachmixed'):
            self.undefined |= not self.ready                  # raylib locks a mutex that does not exist
            if self.ready:
                if kind == 'attachmixed':
                    self.attached.append((0, step[1]))
                else:
                    self.attached = [entry for entry in self.attached if entry != (0, step[1])]
        elif kind == 'callback':
            found = self.used(step[1])
            if found is not None:
                if found['stream'] is None:
                    self.undefined = True      # raylib calls it for the sound's frames; Jonlib gives a sound no callback
                else:
                    found['stream']['called'] = bool(step[2])
        elif kind == 'default':
            self.default = step[1]
        elif kind == 'stream':
            self.stream(*step[1:])
        elif kind == 'feed':
            self.feed(*step[1:])
        else:
            raise ValueError(kind)
        return tag

    def state(self):
        tags = lambda number: '.'.join(str(tag) for of, tag in self.attached if of == number)
        parts = [f'R{int(self.ready)} M{self.master} D{self.default} Q{tags(0)}']
        for slot, (number, frames, rate, size, channels) in enumerate(self.sounds):
            found = self.buffer(slot)
            valid = int(frames > 0 and number > 0 and rate > 0 and size > 0 and channels > 0)
            playing = int(found is not None and found['playing'] and not found['paused'])
            streams = int(number > 0 and rate > 0 and size > 0 and channels > 0)
            processed = int(found is not None and (found['stream'] is None or found['stream']['first'] or found['stream']['second']))
            parts.append(f'S{number},{frames},{rate},{size},{channels},{valid},{playing},{streams},{processed}')
        parts += [self.music_text(slot) for slot in range(SLOTS)]
        for b in self.buffers:
            samples = '-' if not b['block'] else str(fnv(self.blocks[b['block']])) if b['block'] in self.blocks else 'x'
            held = [b['t_int'], b['t_frac'], *map(bits, b['x0'] + b['x1'] + b['r1']), 0 if b['coef'] is None else bits(b['coef']), len(b['residual']),
                    fnv(w for frame in b['residual'] for w in frame)]
            feed = 's' if b['stream'] is None else (f'{b["stream"]["size"]}/{b["stream"]["channels"]}/{int(b["stream"]["first"])}{int(b["stream"]["second"])}'
                                                    f'{int(b["stream"]["called"])}/{b["stream"]["done"]}')
            parts.append(f'B{b["id"]},{b["block"]},{b["frames"]},{b["volume"]},{b["pitch"]},{b["pan"]},{int(b["playing"])},{int(b["paused"])},{samples},'
                         f'{b["source"]},{b["rate"]},{b["cursor"]},{",".join(map(str, held))},{feed},p{tags(b["id"])}')
        return ' '.join(parts)


def expected(case, catalog):
    """(the row with error tags, the row without, whether raylib has a defined answer for every step)."""
    model, tagged, plain = Model(catalog), [], []
    for step in case['steps']:
        tag = model.step(step)
        asks = ''.join(f' A{number}:{count}' for number, count in model.asks) + ''.join(f' P{tag}:{count}' for tag, count in model.log)
        state = model.state() + (('' if step[0] not in ('mix', 'plain') else ' X-' if model.mixed is None else f' X{fnv(model.mixed)}{asks}'))
        if step[0] == 'periods':
            state += ' N0' if model.mixed is None else f' N1{asks}'

        tagged.append(f'E:{tag} {state}')
        plain.append(state)
    return ';'.join(tagged), ';'.join(plain), not model.undefined


NATIVE = r'''#include "raudio.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef ALONE
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

#define SLOTS 4
#define MADE 64
static Sound slots[SLOTS];
static int slot_id[SLOTS];
static rAudioBuffer *created[MADE];
static int owner[MADE], gone[MADE], freed[MADE + 1], made;
static const char *files[] = { FILES };
static unsigned mixed_hash;

// The probe's stream callbacks, one a slot: the next samples of the slot's counter in the stream's format, and
// what each call was asked for.
#define ASKS 256
static unsigned calls[SLOTS], asked_slot[ASKS], asked_frames[ASKS], asked;
static void answer(int slot, void *out, unsigned frames)
{
    unsigned size = slots[slot].stream.sampleSize, count = frames*slots[slot].stream.channels;
    if (asked == ASKS) exit(9);
    asked_slot[asked] = slot; asked_frames[asked++] = frames;
    for (unsigned i = 0; i < count; i++)
    {
        unsigned c = calls[slot]++;
        if (size == 8) ((unsigned char *)out)[i] = (unsigned char)((c*37 + 11) & 255);
        else if (size == 16) ((unsigned short *)out)[i] = (unsigned short)(((c*53)%301*97 + 50986) & 65535);
        else ((float *)out)[i] = ((float)((int)((c*31)%67) - 33))/64.0f;
    }
}
static void answer0(void *out, unsigned frames) { answer(0, out, frames); }
static void answer1(void *out, unsigned frames) { answer(1, out, frames); }
static void answer2(void *out, unsigned frames) { answer(2, out, frames); }
static void answer3(void *out, unsigned frames) { answer(3, out, frames); }
static AudioCallback answers[SLOTS] = { answer0, answer1, answer2, answer3 };
static Music musics[SLOTS];

// The probe's processors (they run inside the callback, so with its denormal handling): half the level; the
// sides swapped and a counted offset on the right; a delay of one frame. Each call is noted.
static unsigned pcount, noted_tag[ASKS], noted_frames[ASKS], noted;
static float pprev[2];
static void noting(unsigned tag, unsigned frames) { if (noted == ASKS) exit(9); noted_tag[noted] = tag; noted_frames[noted++] = frames; }
static void process1(void *buffer, unsigned frames) { float *x = (float *)buffer; noting(1, frames); for (unsigned i = 0; i < frames*2; i++) x[i] = x[i]*0.5f; }
static void process2(void *buffer, unsigned frames)
{
    float *x = (float *)buffer;
    noting(2, frames);
    for (unsigned i = 0; i < frames; i++) { float l = x[2*i], r = x[2*i + 1]; x[2*i] = r; x[2*i + 1] = l + ((float)(pcount%5))/8.0f; pcount++; }
}
static void process3(void *buffer, unsigned frames)
{
    unsigned *x = (unsigned *)buffer, *held = (unsigned *)pprev;
    noting(3, frames);
    for (unsigned i = 0; i < frames; i++) { unsigned l = x[2*i], r = x[2*i + 1]; x[2*i] = held[0]; x[2*i + 1] = held[1]; held[0] = l; held[1] = r; }
}
static AudioCallback processes[4] = { NULL, process1, process2, process3 };
static void tags(rAudioProcessor *list)
{
    for (rAudioProcessor *q = list; q != NULL; q = q->next)
    {
        int tag = (q->process == process1)? 1 : ((q->process == process2)? 2 : 3);
        printf("%s%d", (q == list)? "" : ".", tag);
    }
}

static unsigned rd(FILE *f) { unsigned v = 0; if (fread(&v, 4, 1, f) != 1) exit(3); return v; }
static unsigned word(float x) { unsigned v; memcpy(&v, &x, 4); return v; }
static float real(unsigned v) { float x; memcpy(&x, &v, 4); return x; }
// a time's bits; a NaN (the length of a music without a rate) as one NaN, whatever sign the machine gives it
static unsigned timed(float x) { return (x != x)? 2143289344u : word(x); }

static int number(rAudioBuffer *b)
{
    for (int i = made - 1; i >= 0; i--) if (!gone[i] && created[i] == b) return i + 1;
    return -1;
}

static void put(int slot, Sound sound, int block)
{
    slots[slot] = sound;
    slot_id[slot] = 0;
    if (sound.stream.buffer != NULL)
    {
        if (made == MADE) exit(4);
        created[made] = sound.stream.buffer;
        owner[made] = (block < 0)? ((sound.stream.buffer->data != NULL)? made + 1 : 0) : block;
        slot_id[slot] = ++made;
    }
}

static unsigned fnv(const unsigned *words, unsigned count)
{
    unsigned h = 2166136261u;
    for (unsigned i = 0; i < count; i++) h = (h ^ words[i])*16777619u;
    return h;
}

// `frames` frames of the buffer's format as unsigned sample values, hashed.
static unsigned hashed(rAudioBuffer *b, const unsigned char *data, unsigned frames)
{
    unsigned count = frames*b->converter.channelsIn, h = 2166136261u;
    for (unsigned i = 0; i < count; i++)
    {
        unsigned v = (b->converter.formatIn == ma_format_u8)? data[i] : ((b->converter.formatIn == ma_format_s16)? ((const unsigned short *)data)[i] : ((const unsigned *)data)[i]);
        h = (h ^ v)*16777619u;
    }
    return h;
}

static unsigned samples(rAudioBuffer *b) { return hashed(b, b->data, b->sizeInFrames); }

static void state(int first)
{
    printf("%sR%d M%u D%u Q", first? "" : ";", (int)IsAudioDeviceReady(), word(GetMasterVolume()), (unsigned)AUDIO.Buffer.defaultSize);
    tags(AUDIO.mixedProcessor);
    for (int s = 0; s < SLOTS; s++)
    {
        Sound x = slots[s];
        int live = (slot_id[s] > 0) && !gone[slot_id[s] - 1];
        printf(" S%d,%u,%u,%u,%u,%d,%d,%d,%d", slot_id[s], x.frameCount, x.stream.sampleRate, x.stream.sampleSize, x.stream.channels, (int)IsSoundValid(x),
               (AUDIO.System.isReady && live)? (int)IsSoundPlaying(x) : 0, (int)IsAudioStreamValid(x.stream), (AUDIO.System.isReady && live)? (int)IsAudioStreamProcessed(x.stream) : 0);
    }
    for (int s = 0; s < SLOTS; s++)
    {
        Music m = musics[s];
        int live = (slot_id[s] > 0) && !gone[slot_id[s] - 1];
        if (m.ctxData == NULL) { printf(" U-"); continue; }
        if ((m.ctxType != MUSIC_AUDIO_WAV) && (m.ctxType != MUSIC_AUDIO_QOA) && (m.ctxType != MUSIC_AUDIO_MP3) && (m.ctxType != MUSIC_MODULE_XM) && (m.ctxType != MUSIC_MODULE_MOD)
            && (m.ctxType != MUSIC_AUDIO_OGG)) exit(10);
        printf(" U%d,%u,%d,%u,%u,", (int)IsMusicValid(m), m.frameCount, (int)m.looping,
               (m.ctxType == MUSIC_AUDIO_WAV)? (unsigned)((drwav *)m.ctxData)->readCursorInPCMFrames :
               (m.ctxType == MUSIC_AUDIO_MP3)? (unsigned)((drmp3 *)m.ctxData)->currentPCMFrame :
               (m.ctxType == MUSIC_MODULE_XM)? (unsigned)((jar_xm_context_t *)m.ctxData)->generated_samples :
               (m.ctxType == MUSIC_MODULE_MOD)? (unsigned)((jar_mod_context_t *)m.ctxData)->samplenb :
               (m.ctxType == MUSIC_AUDIO_OGG)? (unsigned)stb_vorbis_get_sample_offset((stb_vorbis *)m.ctxData) : ((qoaplay_desc *)m.ctxData)->sample_position, timed(GetMusicTimeLength(m)));
        // a module's time is its player's count of samples: raylib reads neither the buffer nor the device for it
        if ((m.stream.buffer == NULL) || (AUDIO.System.isReady && live) || (m.ctxType == MUSIC_MODULE_XM)) printf("%u", timed(GetMusicTimePlayed(m)));
        else printf("-");
    }
    for (rAudioBuffer *b = AUDIO.Buffer.first; b != NULL; b = b->next)
    {
        int id = number(b);
        if (id < 1) exit(5);
        printf(" B%d,%d,%u,%u,%u,%u,%d,%d,", id, owner[id - 1], b->sizeInFrames, word(b->volume), word(b->pitch), word(b->pan), (int)b->playing, (int)b->paused);
        if (owner[id - 1] == 0) printf("-");
        else if (freed[owner[id - 1]]) printf("x");
        else printf("%u", samples(b));
        ma_linear_resampler *linear = &b->converter.resampler.state.linear;
        unsigned held = linear->config.channels;
        printf(",%u,%u,%u,%u,%u", b->converter.resampler.sampleRateIn, b->converter.resampler.sampleRateOut, b->frameCursorPos, linear->inTimeInt, linear->inTimeFrac);
        for (unsigned c = 0; c < held; c++) printf(",%u", word(linear->x0.f32[c]));
        for (unsigned c = 0; c < held; c++) printf(",%u", word(linear->x1.f32[c]));
        if ((linear->lpf.lpf1Count != 1) || (linear->lpf.lpf2Count != 0) || (linear->config.format != ma_format_f32)) exit(8);
        for (unsigned c = 0; c < held; c++) printf(",%u", word(linear->lpf.pLPF1[0].pR1[c].f32));
        printf(",%u", (linear->config.sampleRateIn != linear->config.sampleRateOut)? word(linear->lpf.pLPF1[0].a.f32) : 0);
        printf(",%u,%u", b->converterResidualCount, hashed(b, b->converterResidual, b->converterResidualCount));
        if (b->usage == AUDIO_BUFFER_USAGE_STATIC) printf(",s");
        else printf(",%d/%u/%d%d%d/%u", (b->converter.formatIn == ma_format_u8)? 8 : ((b->converter.formatIn == ma_format_s16)? 16 : 32), b->converter.channelsIn,
                    (int)b->isSubBufferProcessed[0], (int)b->isSubBufferProcessed[1], (int)(b->callback != NULL), b->framesProcessed);
        printf(",p");
        tags(b->processor);
    }
}

int main(void)
{
    SetTraceLogLevel(LOG_NONE);
    FILE *f = fopen("PATH", "rb");
    if (!f) return 2;
    unsigned count = rd(f);
#ifdef ALONE
    long *place = (long *)mmap(NULL, sizeof(long), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (place == MAP_FAILED) return 13;
#endif
    for (unsigned k = 0; k < count; k++)
    {
#ifdef ALONE
        // A case in a process of its own (jar_xm's random waveform keeps its state in a static): the child runs it and says where
        // in the script it ends.
        fflush(stdout);
        pid_t child = fork();
        if (child < 0) return 13;
        if (child > 0)
        {
            int status = 0;
            if ((waitpid(child, &status, 0) != child) || !WIFEXITED(status) || (WEXITSTATUS(status) != 0)) return 14;
            if (fseek(f, *place, SEEK_SET) != 0) return 13;
            continue;
        }
#endif
        unsigned steps = rd(f), quiet = rd(f);
        memset(&AUDIO, 0, sizeof(AUDIO));
        memset(slots, 0, sizeof(slots)); memset(slot_id, 0, sizeof(slot_id));
        memset(owner, 0, sizeof(owner)); memset(gone, 0, sizeof(gone)); memset(freed, 0, sizeof(freed));
        memset(calls, 0, sizeof(calls));
        memset(musics, 0, sizeof(musics));
        pcount = 0; pprev[0] = pprev[1] = 0.0f;
        made = 0;
        if (!quiet) printf("C ");
        for (unsigned i = 0; i < steps; i++)
        {
            unsigned code = rd(f), a = rd(f), b = rd(f), c = rd(f), n = rd(f);
            unsigned *payload = (unsigned *)malloc((n + 1)*4);
            for (unsigned j = 0; j < n; j++) payload[j] = rd(f);
            switch (code)
            {
                case 0: InitAudioDevice(); ma_device_stop(&AUDIO.System.device); break;
                case 1: CloseAudioDevice(); break;
                case 2: SetMasterVolume(real(a)); break;
                case 3:
                {
                    unsigned size = payload[0], channels = payload[1], samples = n - 2;
                    void *data = NULL;
                    if (b || c || size || channels || samples)
                    {
                        data = malloc(samples*4 + 4);
                        for (unsigned j = 0; j < samples; j++)
                        {
                            if (size == 8) ((unsigned char *)data)[j] = (unsigned char)payload[2 + j];
                            else if (size == 16) ((unsigned short *)data)[j] = (unsigned short)payload[2 + j];
                            else ((unsigned *)data)[j] = payload[2 + j];
                        }
                    }
                    Wave wave = { b, c, size, channels, data };
                    put(a, LoadSoundFromWave(wave), -1);
                    free(data);
                } break;
                case 4: put(a, LoadSound(files[b]), -1); break;
                case 5: put(a, LoadSoundAlias(slots[b]), slot_id[b]? owner[slot_id[b] - 1] : 0); break;
                case 6: if (slot_id[a]) { freed[owner[slot_id[a] - 1]] = 1; gone[slot_id[a] - 1] = 1; } UnloadSound(slots[a]); break;
                case 7: if (slot_id[a]) gone[slot_id[a] - 1] = 1; UnloadSoundAlias(slots[a]); break;
                case 8:
                    if (b == 0) PlaySound(slots[a]);
                    else if (b == 1) StopSound(slots[a]);
                    else if (b == 2) PauseSound(slots[a]);
                    else ResumeSound(slots[a]);
                    break;
                case 9:
                    if (b == 4) SetSoundVolume(slots[a], real(c));
                    else if (b == 5) SetSoundPitch(slots[a], real(c));
                    else SetSoundPan(slots[a], real(c));
                    break;
                case 10: UpdateSound(slots[a], payload, (int)b); break;
                case 11:
                {
                    rAudioBuffer *buffer = slots[a].stream.buffer;
                    printf("D %u", slots[a].frameCount);
                    if ((buffer != NULL) && (buffer->data != NULL)) for (unsigned j = 0; j < buffer->sizeInFrames*2; j++) printf(" %u", ((unsigned *)buffer->data)[j]);
                    printf("\n");
                } break;
                case 12:
                {
                    float *mixed = (float *)malloc((size_t)a*8 + 8);
                    asked = 0; noted = 0;
                    if (ma_device_handle_backend_data_callback(&AUDIO.System.device, mixed, NULL, a) != MA_SUCCESS) return 7;
                    mixed_hash = fnv((const unsigned *)mixed, a*2);
                    free(mixed);
                } break;
                case 13:
                {
                    Sound sound = { 0 };
                    sound.stream = LoadAudioStream(b, c, payload[0]);
                    put(a, sound, -1);
                } break;
                case 14:
                {
                    unsigned size = slots[a].stream.sampleSize;
                    void *data = malloc((size_t)n*4 + 4);
                    for (unsigned j = 0; j < n; j++)
                    {
                        if (size == 8) ((unsigned char *)data)[j] = (unsigned char)payload[j];
                        else if (size == 16) ((unsigned short *)data)[j] = (unsigned short)payload[j];
                        else ((unsigned *)data)[j] = payload[j];
                    }
                    UpdateAudioStream(slots[a].stream, data, (int)b);
                    free(data);
                } break;
                case 15: SetAudioStreamBufferSizeDefault((int)a); break;
                case 16: SetAudioStreamCallback(slots[a].stream, b? answers[a] : NULL); break;
                case 22:
                {
                    Sound sound = { 0 };
                    musics[a] = LoadMusicStream(files[b]);
                    sound.stream = musics[a].stream;
                    put(a, sound, -1);
                } break;
                case 23: UpdateMusicStream(musics[a]); break;
                case 24: StopMusicStream(musics[a]); break;
                case 25: SeekMusicStream(musics[a], real(b)); break;
                case 26: musics[a].looping = (b != 0); break;
                case 27:
                    if (slot_id[a]) { freed[owner[slot_id[a] - 1]] = 1; gone[slot_id[a] - 1] = 1; }
                    UnloadMusicStream(musics[a]);
                    memset(&musics[a], 0, sizeof(Music));
                    break;
                case 28:
                {
                    Wave wave = LoadWave(files[a]);
                    if (wave.sampleSize != 16) return 11;
                    printf("W %u %u %u %u", wave.frameCount, wave.sampleRate, wave.sampleSize, wave.channels);
                    for (unsigned j = 0; j < wave.frameCount*wave.channels; j++) printf(" %u", (unsigned)((unsigned short *)wave.data)[j]);
                    printf("\n");
                    UnloadWave(wave);
                } break;
                case 29:
                {
                    static drmp3 mp3;
                    static drmp3_int16 all[1 << 16];
                    unsigned count, got;
                    if (!drmp3_init_file(&mp3, files[a], NULL)) return 12;
                    count = (unsigned)drmp3_get_pcm_frame_count(&mp3);
                    got = (unsigned)drmp3_read_pcm_frames_s16(&mp3, (1 << 16)/2, all);
                    printf("M %u %u %u %u %u", count, mp3.sampleRate, mp3.channels, mp3.delayInPCMFrames, got);
                    for (unsigned j = 0; j < got*mp3.channels; j++) printf(" %u", (unsigned)(unsigned short)all[j]);
                    printf("\n");
                    drmp3_uninit(&mp3);
                } break;
                case 18: AttachAudioStreamProcessor(slots[a].stream, processes[b]); break;
                case 19: DetachAudioStreamProcessor(slots[a].stream, processes[b]); break;
                case 20: AttachAudioMixedProcessor(processes[a]); break;
                case 21: DetachAudioMixedProcessor(processes[a]); break;
                case 17:
                {
                    float period[960];
                    asked = 0; noted = 0;
                    if (AUDIO.System.isReady) for (unsigned j = 0; j < a; j++) if (ma_device_handle_backend_data_callback(&AUDIO.System.device, period, NULL, 480) != MA_SUCCESS) return 7;
                } break;
                default: return 6;
            }
            free(payload);
            if (!quiet) state(i == 0);
            if (!quiet && (code == 12))
            {
                printf(" X%u", mixed_hash);
                for (unsigned j = 0; j < asked; j++) printf(" A%d:%u", slot_id[asked_slot[j]], asked_frames[j]);
                for (unsigned j = 0; j < noted; j++) printf(" P%u:%u", noted_tag[j], noted_frames[j]);
            }
            if (!quiet && (code == 17))
            {
                printf(" N1");
                for (unsigned j = 0; j < asked; j++) printf(" A%d:%u", slot_id[asked_slot[j]], asked_frames[j]);
                for (unsigned j = 0; j < noted; j++) printf(" P%u:%u", noted_tag[j], noted_frames[j]);
            }
        }
        if (!quiet) printf("\n");
        if (AUDIO.System.isReady) CloseAudioDevice();
        AUDIO.mixedProcessor = NULL;
#ifdef ALONE
        *place = ftell(f);
        fflush(stdout);
        _exit(0);
#endif
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/mixer.bend as Mixer
import ../../src/resampler.bend as Resampler
import ../../src/mp3_stream.bend as Mp3S
import ../../src/xm_mixer.bend as XmX
import ../../src/mod.bend as ModS
import ../../src/vorbis_packet.bend as VorbisK
import ../../src/vorbis_frame.bend as VorbisF

type Op is Data:
  OpInit{}
  OpClose{}
  OpMaster{bits: U32}
  OpLoad{slot: U32, frames: U32, rate: U32, size: U32, channels: U32, data: +List<U32>}
  OpFile{slot: U32, path: String}
  OpAlias{slot: U32, source: U32}
  OpUnload{slot: U32}
  OpUnalias{slot: U32}
  OpAct{slot: U32, op: U32}
  OpTune{slot: U32, op: U32, bits: U32}
  OpUpdate{slot: U32, frames: U32, data: +List<U32>}
  OpMix{frames: U32}
  OpDefault{size: U32}
  OpStream{slot: U32, rate: U32, size: U32, channels: U32}
  OpFeed{slot: U32, frames: U32, data: +List<U32>}
  OpCallback{slot: U32, on: U32}
  OpPlain{frames: U32}
  OpPeriods{count: U32}
  OpAttach{slot: U32, tag: U32}
  OpDetach{slot: U32, tag: U32}
  OpAttachMixed{tag: U32}
  OpDetachMixed{tag: U32}
  OpMusic{slot: U32, path: String}
  OpMusicUpdate{slot: U32}
  OpMusicStop{slot: U32}
  OpSeek{slot: U32, bits: U32}
  OpLooping{slot: U32, on: U32}
  OpMusicUnload{slot: U32}

# What the program keeps beside the device: how many samples each slot's stream callback has written, the processors
# attached, the processors' own state (the frames the second has counted, the frame the third holds), and each
# slot's music.
type Ext is Data:
  Ext{calls: +List<U32>, attached: +List<J.AudioDevice.Processor>, count: U32, left: U32, right: U32, musics: +List<J.Music>}

def ext.musics(ext: Ext) -> +List<J.Music>:
  Ext{_, _, _, _, _, musics} = ext
  musics

def ext.attached(ext: Ext) -> +List<J.AudioDevice.Processor>:
  Ext{_, attached, _, _, _, _} = ext
  attached

def tags.text(tags: +List<U32>, +first: Bool) -> String:
  match tags:
    case Nil{}: ""
    case Con{+tag, rest}: Bool.pick(String, first, "", ".") ++ U32.show(tag) ++ tags.text(rest, False{})

def get(sounds: +List<J.Sound>, +i: U32) -> J.Sound:
  match sounds:
    case Nil{}: J.Sound.none()
    case Con{+s, rest}: Bool.pick(J.Sound, U32.is_eq(i, 0), s, get(rest, (i - 1 : U32)))

def set(sounds: +List<J.Sound>, +i: U32, +s: J.Sound) -> +List<J.Sound>:
  match sounds:
    case Nil{}: Nil{}
    case Con{+x, +rest}: Bool.pick(+List<J.Sound>, U32.is_eq(i, 0), Con{s, rest}, Con{x, set(rest, (i - 1 : U32), s)})

def fnv(xs: +List<U32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, rest}: fnv(rest, (U32.xor(h, x) * 16777619 : U32))

def hashed(+block: U32, found: Maybe<&2, +List<U32>>) -> String:
  match found:
    case None{}: Bool.pick(String, U32.is_eq(block, 0), "-", "x")
    case Some{+data}: U32.show(fnv(data, 2166136261))

def flag(value: Bool) -> String:
  U32.show(Bool.to_u32(value))

def sound.text(+audio: J.AudioDevice, +sound: J.Sound) -> String:
  J.Sound{stream, +frames} = sound
  J.AudioStream{+buffer, +rate, +size, +channels} = stream
  " S" ++ U32.show(buffer) ++ "," ++ U32.show(frames) ++ "," ++ U32.show(rate) ++ "," ++ U32.show(size) ++ "," ++ U32.show(channels) ++ "," ++ flag(J.Sound.is_valid(sound)) ++ "," ++ flag(J.Sound.is_playing(audio, sound)) ++ "," ++ flag(J.AudioStream.is_valid(J.AudioStream{buffer, rate, size, channels})) ++ "," ++ flag(J.AudioStream.is_processed(audio, J.AudioStream{buffer, rate, size, channels}))

def sounds.text(sounds: +List<J.Sound>, +audio: J.AudioDevice) -> String:
  match sounds:
    case Nil{}: ""
    case Con{+sound, rest}: sound.text(audio, sound) ++ sounds.text(rest, audio)

# Long lists arrive in chunks: the JavaScript target cannot parse a literal of
# thousands of nested cells.
def words.onto(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{+head, tail}: words.onto(tail, Con{head, rest})

def words.joined(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: words.joined(tail, words.onto(head, values))

def words.text(words: +List<U32>) -> String:
  match words:
    case Nil{}: ""
    case Con{+word, rest}: "," ++ U32.show(word) ++ words.text(rest)

def chans.text(chans: +List<Resampler.Chan>) -> String:
  match chans:
    case Nil{}: ""
    case Con{Resampler.Chan{r1a, _, _, _}, rest}: "," ++ U32.show(r1a) ++ chans.text(rest)

def count(frames: +List<+List<U32>>, +n: U32) -> U32:
  match frames:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def fnv.frames(frames: +List<+List<U32>>, +h: U32) -> U32:
  match frames:
    case Nil{}: h
    case Con{+frame, rest}: fnv.frames(rest, fnv(frame, h))

def st.text(st: Resampler.St) -> String:
  Resampler.St{t_int, t_frac, x0, x1, chans, _} = st
  "," ++ U32.show(t_int) ++ "," ++ U32.show(t_frac) ++ words.text(x0) ++ words.text(x1) ++ chans.text(chans)

def feed.text(feed: Mixer.Feed) -> String:
  match feed:
    case Mixer.HeadStatic{}: ",s"
    case Mixer.HeadStream{size, channels, first, second, called, done}: "," ++ U32.show(size) ++ "/" ++ U32.show(channels) ++ "/" ++ flag(first) ++ flag(second) ++ flag(called) ++ "/" ++ U32.show(done)

def head.text(head: Mixer.Head) -> String:
  Mixer.Head{source, rate, +mode, +coef, cursor, st, +residual, feed} = head
  "," ++ U32.show(source) ++ "," ++ U32.show(rate) ++ "," ++ U32.show(cursor) ++ st.text(st) ++ "," ++ U32.show(Bool.pick(U32, U32.is_eq(mode, 1), coef, 0)) ++ "," ++ U32.show(count(residual, 0)) ++ "," ++ U32.show(fnv.frames(residual, 2166136261)) ++ feed.text(feed)

def buffers.text(buffers: +List<J.AudioDevice.Buffer>, +blocks: +List<J.AudioDevice.Block>, +attached: +List<J.AudioDevice.Processor>) -> String:
  match buffers:
    case Nil{}: ""
    case Con{J.AudioBuffer{+id, +block, +frames, +volume, +pitch, +pan, +playing, +paused, head}, rest}:
      " B" ++ U32.show(id) ++ "," ++ U32.show(block) ++ "," ++ U32.show(frames) ++ "," ++ U32.show(F32.bits(volume)) ++ "," ++ U32.show(F32.bits(pitch)) ++ "," ++ U32.show(F32.bits(pan)) ++ "," ++ flag(playing) ++ "," ++ flag(paused) ++ "," ++ hashed(block, J.AudioDevice.block.find(blocks, block)) ++ head.text(head) ++ ",p" ++ tags.text(J.AudioProcessors.tags(attached, id, Nil{}), True{}) ++ buffers.text(rest, blocks, attached)

# stb_vorbis_get_sample_offset: current_loc where it is valid, else -1.
def ogg.offset(state: VorbisK.State) -> String:
  VorbisK.State{_, _, loc, known, _} = state
  U32.show(Bool.pick(U32, known, loc, 4294967295))

def music.at(context: J.Music.Context) -> String:
  match context:
    case J.MusicNone{}: "-"
    case J.MusicWav{_, at}: U32.show(at)
    case J.MusicQoa{_, at}: U32.show(at)
    case J.MusicMp3{player}: U32.show(Mp3S.Player.current(player))
    case J.MusicXm{player}: U32.show(XmX.generated.of(player))
    case J.MusicMod{player}: U32.show(ModS.Player.samples(player))
    case J.MusicOgg{_, frames, _, _}: ogg.offset(VorbisF.Frames.state(frames))

# A time's bits; a NaN (the length of a music without a rate) as one NaN, whatever sign the machine gives it.
def timed(time: F32) -> String:
  +word = F32.bits(time)
  U32.show(Bool.pick(U32, Mixer.nan(word), 2143289344, word))

def played.text(played: Maybe<F32>) -> String:
  match played:
    case None{}: "-"
    case Some{t}: timed(t)

def music.text(+audio: J.AudioDevice, +music: J.Music) -> String:
  J.Music{_, +frames, +looping, _, +context} = music
  match context:
    case J.MusicNone{}: " U-"
    case +loaded:
      " U" ++ flag(J.Music.is_valid(music)) ++ "," ++ U32.show(frames) ++ "," ++ flag(looping) ++ "," ++ music.at(loaded) ++ "," ++ timed(J.Music.time_length(music)) ++ "," ++ played.text(J.Music.time_played(audio, music))

def musics.text(musics: +List<J.Music>, +audio: J.AudioDevice) -> String:
  match musics:
    case Nil{}: ""
    case Con{+music, rest}: music.text(audio, music) ++ musics.text(rest, audio)

def music.get(musics: +List<J.Music>, +i: U32) -> J.Music:
  match musics:
    case Nil{}: J.Music.none()
    case Con{+m, rest}: Bool.pick(J.Music, U32.is_eq(i, 0), m, music.get(rest, (i - 1 : U32)))

def music.set(musics: +List<J.Music>, +i: U32, +m: J.Music) -> +List<J.Music>:
  match musics:
    case Nil{}: Nil{}
    case Con{+x, +rest}: Bool.pick(+List<J.Music>, U32.is_eq(i, 0), Con{m, rest}, Con{x, music.set(rest, (i - 1 : U32), m)})

type St is Data:
  St{audio: J.AudioDevice, sounds: +List<J.Sound>, out: String, calls: Ext}

def state(+audio: J.AudioDevice, +sounds: +List<J.Sound>, +ext: Ext) -> String:
  J.AudioDevice{_, _, _, +buffers, +blocks, +default} = audio
  "R" ++ flag(J.AudioDevice.is_ready(audio)) ++ " M" ++ U32.show(F32.bits(J.AudioDevice.master_volume(audio))) ++ " D" ++ U32.show(default) ++ " Q" ++ tags.text(J.AudioProcessors.tags(ext.attached(ext), 0, Nil{}), True{}) ++ sounds.text(sounds, audio) ++ musics.text(ext.musics(ext), audio) ++ buffers.text(buffers, blocks, ext.attached(ext))

def after(+tag: String, +audio: J.AudioDevice, +sounds: +List<J.Sound>, +out: String, +calls: Ext) -> St:
  St{audio, sounds, out ++ ";E:" ++ tag ++ " " ++ state(audio, sounds, calls), calls}

# A refused callback leaves the program's state as it was.
def mixed(result: J.AudioDevice & Maybe<&2, +List<U32>>, +sounds: +List<J.Sound>, +out: String, +before: Ext, +calls: Ext, +asks: String) -> St:
  match result:
    case Tuple{+audio, Some{+samples}}: St{audio, sounds, out ++ ";E:- " ++ state(audio, sounds, calls) ++ " X" ++ U32.show(fnv(samples, 2166136261)) ++ asks, calls}
    case Tuple{+audio, None{}}: St{audio, sounds, out ++ ";E:- " ++ state(audio, sounds, before) ++ " X-", before}

def nth(xs: +List<U32>, +i: U32) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+x, rest}: Bool.pick(U32, U32.is_eq(i, 0), x, nth(rest, (i - 1 : U32)))

def put(xs: +List<U32>, +i: U32, +v: U32) -> +List<U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{+x, +rest}: Bool.pick(+List<U32>, U32.is_eq(i, 0), Con{v, rest}, Con{x, put(rest, (i - 1 : U32), v)})

# The slot whose stream is the buffer.
def slot.of(sounds: +List<J.Sound>, +id: U32, +i: U32) -> U32:
  match sounds:
    case Nil{}: i
    case Con{J.Sound{J.AudioStream{+buffer, _, _, _}, _}, rest}: Bool.pick(U32, U32.is_eq(buffer, id), i, slot.of(rest, id, (i + 1 : U32)))

def size.of(sound: J.Sound) -> U32:
  J.Sound{J.AudioStream{_, _, size, _}, _} = sound
  size

def channels.of(sound: J.Sound) -> U32:
  J.Sound{J.AudioStream{_, _, _, channels}, _} = sound
  channels

# Sample c of the probe's stream callback, as the stream holds it.
def answer.sample(size: U32, +c: U32) -> U32:
  match size:
    case 8: (((c * 37) + 11) % 256 : U32)
    case 16: (((((c * 53) % 301) * 97) + 50986) % 65536 : U32)
    case _: F32.bits(((U32.to_f32(((c * 31) % 67 : U32)) - 33.0) / 64.0 : F32))

def answer.samples(n: Nat, +size: U32, +c: U32, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+m: answer.samples(m, size, (c + 1 : U32), Con{answer.sample(size, c), acc})

type Answered is Data:
  Answered{calls: +List<U32>, data: +List<U32>, text: String}

# The answers to what a callback's streams are asked for (last sample first while they are made).
def answered(asks: +List<J.AudioDevice.Ask>, +sounds: +List<J.Sound>, +calls: +List<U32>, acc: +List<U32>, +text: String) -> Answered:
  match asks:
    case Nil{}: Answered{calls, List.reverse(&2, U32, acc), text}
    case Con{J.AudioAsk{+buffer, +frames}, rest}:
      +slot = slot.of(sounds, buffer, 0)
      +count = (frames * channels.of(get(sounds, slot)) : U32)
      answered(rest, sounds, put(calls, slot, (nth(calls, slot) + count : U32)), answer.samples(U32.to_nat(count), size.of(get(sounds, slot)), nth(calls, slot), acc),
        text ++ " A" ++ U32.show(buffer) ++ ":" ++ U32.show(frames))

# The program's side of the callbacks and the processors: the slots, the counters, what the callbacks were asked for,
# the processors' state and what they were called with (the functions are templates: they close over nothing).
type Asked is Data:
  Asked{sounds: +List<J.Sound>, calls: +List<U32>, text: String, count: U32, left: U32, right: U32, log: String}

def answer.one(+buffer: U32, +frames: U32, state: Asked) -> Asked & +List<U32>:
  Asked{+sounds, +calls, +text, count, left, right, log} = state
  +slot = slot.of(sounds, buffer, 0)
  +total = (frames * channels.of(get(sounds, slot)) : U32)
  (Asked{sounds, put(calls, slot, (nth(calls, slot) + total : U32)), text ++ " A" ++ U32.show(buffer) ++ ":" ++ U32.show(frames), count, left, right, log},
    List.reverse(&2, U32, answer.samples(U32.to_nat(total), size.of(get(sounds, slot)), nth(calls, slot), Nil{})))

def half(samples: +List<U32>, +n: U32) -> U32:
  match samples:
    case Nil{}: (n / 2 : U32)
    case Con{_, rest}: half(rest, (n + 1 : U32))

# Processor 1: half the level (the callback's arithmetic).
def gained(samples: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match samples:
    case Nil{}: List.reverse(&2, U32, acc)
    case Con{+x, rest}: gained(rest, Con{F32.bits(Mixer.fmul(J.Wave.float_bits(x), 0.5)), acc})

type Swapped is Data:
  Swapped{out: +List<U32>, count: U32}

# Processor 2: the sides swapped, and (count % 5)/8 more on the right for each frame it has counted.
def swapped(samples: +List<U32>, +count: U32, acc: +List<U32>) -> Swapped:
  match samples:
    case Con{+l, Con{+r, rest}}: swapped(rest, (count + 1 : U32), Con{F32.bits(Mixer.fadd(J.Wave.float_bits(l), (U32.to_f32((count % 5 : U32)) / 8.0 : F32))), Con{r, acc}})
    case _: Swapped{List.reverse(&2, U32, acc), count}

type Delayed is Data:
  Delayed{out: +List<U32>, left: U32, right: U32}

# Processor 3: each frame one frame late.
def delayed(samples: +List<U32>, +left: U32, +right: U32, acc: +List<U32>) -> Delayed:
  match samples:
    case Con{+l, Con{+r, rest}}: delayed(rest, l, r, Con{right, Con{left, acc}})
    case _: Delayed{List.reverse(&2, U32, acc), left, right}

def process.swapped(result: Swapped, +sounds: +List<J.Sound>, +calls: +List<U32>, +text: String, +left: U32, +right: U32, +log: String) -> Asked & +List<U32>:
  Swapped{+out, +count} = result
  (Asked{sounds, calls, text, count, left, right, log}, out)

def process.delayed(result: Delayed, +sounds: +List<J.Sound>, +calls: +List<U32>, +text: String, +count: U32, +log: String) -> Asked & +List<U32>:
  Delayed{+out, +left, +right} = result
  (Asked{sounds, calls, text, count, left, right, log}, out)

# The processors: 1, 2 and 3; any other loses the last sample it was given.
def process.one(tag: U32, +samples: +List<U32>, state: Asked) -> Asked & +List<U32>:
  match tag:
    case 1:
      Asked{sounds, calls, text, count, left, right, +log} = state
      (Asked{sounds, calls, text, count, left, right, log ++ " P1:" ++ U32.show(half(samples, 0))}, gained(samples, Nil{}))
    case 2:
      Asked{+sounds, +calls, +text, +count, +left, +right, +log} = state
      process.swapped(swapped(samples, count, Nil{}), sounds, calls, text, left, right, log ++ " P2:" ++ U32.show(half(samples, 0)))
    case 3:
      Asked{+sounds, +calls, +text, +count, +left, +right, +log} = state
      process.delayed(delayed(samples, left, right, Nil{}), sounds, calls, text, count, log ++ " P3:" ++ U32.show(half(samples, 0)))
    case _:
      Asked{sounds, calls, text, count, left, right, +log} = state
      (Asked{sounds, calls, text, count, left, right, log ++ " P9:" ++ U32.show(half(samples, 0))}, List.reverse(&2, U32, List.drop(&2, U32, List.reverse(&2, U32, samples), 1n)))

def asked.of(+sounds: +List<J.Sound>, ext: Ext, +text: String) -> Asked:
  Ext{calls, _, count, left, right, _} = ext
  Asked{sounds, calls, text, count, left, right, ""}

# The program's state after callbacks: the processors and musics of before.
def ext.of(asked: Asked, +before: Ext) -> Ext:
  Asked{_, calls, _, count, left, right, _} = asked
  Ext{calls, ext.attached(before), count, left, right, ext.musics(before)}

def asked.text(asked: Asked) -> String:
  Asked{_, _, text, _, _, _, log} = asked
  text ++ log

def clocked(result: J.AudioClock.Step & Asked, +sounds: +List<J.Sound>, +out: String, +before: Ext) -> St:
  match result:
    case Tuple{J.AudioStep{_, +audio, True{}}, +asked}:
      St{audio, sounds, out ++ ";E:- " ++ state(audio, sounds, before) ++ " N1" ++ asked.text(asked), ext.of(asked, before)}
    case Tuple{J.AudioStep{_, +audio, False{}}, _}: St{audio, sounds, out ++ ";E:- " ++ state(audio, sounds, before) ++ " N0", before}

# `count` periods on a clock opened at 0 (the time is half a period past the last one), with the processors when
# there are any.
def periods.run(processors: +List<J.AudioDevice.Processor>, +count: U32, +audio: J.AudioDevice, +sounds: +List<J.Sound>, +calls: Ext) -> J.AudioClock.Step & Asked:
  match processors:
    case Nil{}:
      J.AudioClock.advance_answering(~Asked, ~(buffer => frames => state => answer.one(buffer, frames, state)), J.AudioClock.at(M.Float64{0, 0}), audio,
        M.Float64.from_f32(((U32.to_f32(count) / 100.0) + 0.005 : F32)), asked.of(sounds, calls, ""))
    case Con{+first, +rest}:
      J.AudioClock.advance_processing(~Asked, ~(buffer => frames => state => answer.one(buffer, frames, state)), ~(tag => samples => state => process.one(tag, samples, state)),
        J.AudioClock.at(M.Float64{0, 0}), audio, J.AudioProcessors{Con{first, rest}}, M.Float64.from_f32(((U32.to_f32(count) / 100.0) + 0.005 : F32)), asked.of(sounds, calls, ""))

def periods(+count: U32, +audio: J.AudioDevice, +sounds: +List<J.Sound>, +out: String, +calls: Ext) -> St:
  clocked(periods.run(ext.attached(calls), count, audio, sounds, calls), sounds, out, calls)

def mix.processed(result: (J.AudioDevice & Maybe<&2, +List<U32>>) & Asked, +sounds: +List<J.Sound>, +out: String, +before: Ext) -> St:
  match result:
    case Tuple{mix, +asked}: mixed(mix, sounds, out, before, ext.of(asked, before), asked.text(asked))

# The mix with the answers, through the processors when there are any.
def mix.run(processors: +List<J.AudioDevice.Processor>, +audio: J.AudioDevice, +frames: U32, +data: +List<U32>, +sounds: +List<J.Sound>, +out: String, +before: Ext, +calls: +List<U32>,
    +text: String) -> St:
  match processors:
    case Nil{}:
      Ext{_, _, +count, +left, +right, +musics} = before
      mixed(J.AudioDevice.mix_answered(audio, frames, data), sounds, out, before, Ext{calls, Nil{}, count, left, right, musics}, text)
    case Con{+first, +rest}:
      Ext{_, _, +count, +left, +right, _} = before
      mix.processed(J.AudioDevice.mix_processed(~Asked, ~(tag => samples => state => process.one(tag, samples, state)), audio, J.AudioProcessors{Con{first, rest}}, frames, data,
        Asked{sounds, calls, text, count, left, right, ""}), sounds, out, before)

def mix.answered(answers: Answered, +audio: J.AudioDevice, +frames: U32, +sounds: +List<J.Sound>, +out: String, +before: Ext) -> St:
  Answered{+calls, +data, +text} = answers
  mix.run(ext.attached(before), audio, frames, data, sounds, out, before, calls, text)

def ext.calls(ext: Ext) -> +List<U32>:
  Ext{calls, _, _, _, _, _} = ext
  calls

# One device callback: what the stream callbacks will be asked for, their answers, and the mix with them.
def mix.asked(asks: Maybe<&2, +List<J.AudioDevice.Ask>>, +audio: J.AudioDevice, +frames: U32, +sounds: +List<J.Sound>, +out: String, +calls: Ext) -> St:
  match asks:
    case None{}: St{audio, sounds, out ++ ";E:- " ++ state(audio, sounds, calls) ++ " X-", calls}
    case Some{+list}: mix.answered(answered(list, sounds, ext.calls(calls), Nil{}, ""), audio, frames, sounds, out, calls)

def ext.with(processors: J.AudioProcessors, ext: Ext) -> Ext:
  J.AudioProcessors{attached} = processors
  Ext{calls, _, count, left, right, musics} = ext
  Ext{calls, attached, count, left, right, musics}

# AttachAudioStreamProcessor, DetachAudioStreamProcessor, AttachAudioMixedProcessor and DetachAudioMixedProcessor.
def attached(op: U32, +audio: J.AudioDevice, +stream: J.AudioStream, +tag: U32, +ext: Ext) -> Ext:
  match op:
    case 0: ext.with(J.AudioStream.attach_processor(J.AudioProcessors{ext.attached(ext)}, audio, stream, tag), ext)
    case 1: ext.with(J.AudioStream.detach_processor(J.AudioProcessors{ext.attached(ext)}, audio, stream, tag), ext)
    case 2: ext.with(J.AudioDevice.attach_mixed_processor(J.AudioProcessors{ext.attached(ext)}, audio, tag), ext)
    case _: ext.with(J.AudioDevice.detach_mixed_processor(J.AudioProcessors{ext.attached(ext)}, audio, tag), ext)

def wave.tag(error: J.Wave.Error) -> String:
  match error:
    case J.InvalidWaveHeader{}: "header"
    case J.UnsupportedWaveFormat{}: "unsupported"
    case J.InvalidWaveData{}: "data"
    case J.InvalidWaveRequest{}: "request"

def tag(error: J.Sound.Error) -> String:
  match error:
    case J.SoundDeviceNotReady{}: "device"
    case J.SoundWaveError{J.WaveFileError{_, _}}: "file"
    case J.SoundWaveError{J.WaveDataError{inner}}: wave.tag(inner)

def ext.playing(ext: Ext, +musics: +List<J.Music>) -> Ext:
  Ext{calls, attached, count, left, right, _} = ext
  Ext{calls, attached, count, left, right, musics}

def io.tag(error: J.Wave.IOError) -> String:
  match error:
    case J.WaveFileError{_, _}: "file"
    case J.WaveDataError{inner}: wave.tag(inner)

# LoadMusicStream: the slot holds the music and its stream.
def musicked(result: J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, +slot: U32, +sounds: +List<J.Sound>, +out: String, +calls: Ext) -> St:
  match result:
    case Tuple{+audio, Done{+music}}: after("-", audio, set(sounds, slot, J.Sound{J.Music.stream(music), 0}), out, ext.playing(calls, music.set(ext.musics(calls), slot, music)))
    case Tuple{+audio, Fail{error}}: after(io.tag(error), audio, set(sounds, slot, J.Sound.none()), out, ext.playing(calls, music.set(ext.musics(calls), slot, J.Music.none())))

# UpdateMusicStream, StopMusicStream and SeekMusicStream give the music back.
def musicking(result: J.AudioDevice & J.Music, +slot: U32, +sounds: +List<J.Sound>, +out: String, +calls: Ext) -> St:
  match result:
    case Tuple{+audio, +music}: after("-", audio, sounds, out, ext.playing(calls, music.set(ext.musics(calls), slot, music)))

def looped(music: J.Music, +on: Bool) -> J.Music:
  J.Music{stream, frames, _, kind, context} = music
  J.Music{stream, frames, on, kind, context}

def loaded(result: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, +slot: U32, +sounds: +List<J.Sound>, +out: String, +calls: Ext) -> St:
  match result:
    case Tuple{+audio, Done{+sound}}: after("-", audio, set(sounds, slot, sound), out, calls)
    case Tuple{+audio, Fail{error}}: after(tag(error), audio, set(sounds, slot, J.Sound.none()), out, calls)

def aliased(result: J.AudioDevice & J.Sound, +slot: U32, +sounds: +List<J.Sound>, +out: String, +calls: Ext) -> St:
  match result:
    case Tuple{+audio, +sound}: after("-", audio, set(sounds, slot, sound), out, calls)

def streamed(result: J.AudioDevice & J.AudioStream, +slot: U32, +sounds: +List<J.Sound>, +out: String, +calls: Ext) -> St:
  match result:
    case Tuple{+audio, +stream}: after("-", audio, set(sounds, slot, J.Sound{stream, 0}), out, calls)

def stream.of(sound: J.Sound) -> J.AudioStream:
  J.Sound{stream, _} = sound
  stream

def acted(op: U32, +audio: J.AudioDevice, +sound: J.Sound) -> J.AudioDevice:
  match op:
    case 0: J.Sound.play(audio, sound)
    case 1: J.Sound.stop(audio, sound)
    case 2: J.Sound.pause(audio, sound)
    case _: J.Sound.resume(audio, sound)

def tuned(op: U32, +audio: J.AudioDevice, +sound: J.Sound, +value: F32) -> J.AudioDevice:
  match op:
    case 4: J.Sound.set_volume(audio, sound, value)
    case 5: J.Sound.set_pitch(audio, sound, value)
    case _: J.Sound.set_pan(audio, sound, value)

def step(+st: St, op: Op) -> IO(St):
  St{+audio, +sounds, +out, +calls} = st
  match op:
    case OpInit{}: IO.pure(St, after("-", J.AudioDevice.init(audio), sounds, out, calls))
    case OpClose{}: IO.pure(St, after("-", J.AudioDevice.close(audio), sounds, out, calls))
    case OpMaster{bits}: IO.pure(St, after("-", J.AudioDevice.set_master_volume(audio, J.Wave.float_bits(bits)), sounds, out, calls))
    case OpLoad{slot, frames, rate, size, channels, data}: IO.pure(St, loaded(J.Sound.load_from_wave(audio, J.Wave{frames, rate, size, channels, data}), slot, sounds, out, calls))
    case OpFile{+slot, path}:
      do IO<St>:
        result : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound> <- J.Sound.load(audio, path)
        IO.pure(St, loaded(result, slot, sounds, out, calls))
    case OpAlias{slot, source}: IO.pure(St, aliased(J.Sound.load_alias(audio, get(sounds, source)), slot, sounds, out, calls))
    case OpUnload{slot}: IO.pure(St, after("-", J.Sound.unload(audio, get(sounds, slot)), sounds, out, calls))
    case OpUnalias{slot}: IO.pure(St, after("-", J.Sound.unload_alias(audio, get(sounds, slot)), sounds, out, calls))
    case OpAct{slot, code}: IO.pure(St, after("-", acted(code, audio, get(sounds, slot)), sounds, out, calls))
    case OpTune{slot, code, bits}: IO.pure(St, after("-", tuned(code, audio, get(sounds, slot), J.Wave.float_bits(bits)), sounds, out, calls))
    case OpUpdate{slot, frames, data}: IO.pure(St, after("-", J.Sound.update(audio, get(sounds, slot), data, frames), sounds, out, calls))
    case OpMix{+frames}: IO.pure(St, mix.asked(J.AudioDevice.asks(audio, frames), audio, frames, sounds, out, calls))
    case OpPlain{frames}: IO.pure(St, mixed(J.AudioDevice.mix(audio, frames), sounds, out, calls, calls, ""))
    case OpPeriods{+count}: IO.pure(St, periods(count, audio, sounds, out, calls))
    case OpMusic{+slot, path}:
      do IO<St>:
        result : J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music> <- J.Music.load(audio, path)
        IO.pure(St, musicked(result, slot, sounds, out, calls))
    case OpMusicUpdate{+slot}: IO.pure(St, musicking(J.Music.update(audio, music.get(ext.musics(calls), slot)), slot, sounds, out, calls))
    case OpMusicStop{+slot}: IO.pure(St, musicking(J.Music.stop(audio, music.get(ext.musics(calls), slot)), slot, sounds, out, calls))
    case OpSeek{+slot, bits}: IO.pure(St, musicking(J.Music.seek(audio, music.get(ext.musics(calls), slot), J.Wave.float_bits(bits)), slot, sounds, out, calls))
    case OpLooping{+slot, on}: IO.pure(St, after("-", audio, sounds, out, ext.playing(calls, music.set(ext.musics(calls), slot, looped(music.get(ext.musics(calls), slot), U32.is_ne(on, 0))))))
    case OpMusicUnload{+slot}:
      IO.pure(St, after("-", J.Music.unload(audio, music.get(ext.musics(calls), slot)), sounds, out, ext.playing(calls, music.set(ext.musics(calls), slot, J.Music.none()))))
    case OpAttach{slot, +tag}: IO.pure(St, after("-", audio, sounds, out, attached(0, audio, stream.of(get(sounds, slot)), tag, calls)))
    case OpDetach{slot, +tag}: IO.pure(St, after("-", audio, sounds, out, attached(1, audio, stream.of(get(sounds, slot)), tag, calls)))
    case OpAttachMixed{+tag}: IO.pure(St, after("-", audio, sounds, out, attached(2, audio, J.AudioStream{0, 0, 0, 0}, tag, calls)))
    case OpDetachMixed{+tag}: IO.pure(St, after("-", audio, sounds, out, attached(3, audio, J.AudioStream{0, 0, 0, 0}, tag, calls)))
    case OpCallback{slot, on}: IO.pure(St, after("-", J.AudioStream.set_callback(audio, stream.of(get(sounds, slot)), U32.is_ne(on, 0)), sounds, out, calls))
    case OpDefault{size}: IO.pure(St, after("-", J.AudioDevice.set_stream_buffer_size_default(audio, size), sounds, out, calls))
    case OpStream{slot, rate, size, channels}: IO.pure(St, streamed(J.AudioStream.load(audio, rate, size, channels), slot, sounds, out, calls))
    case OpFeed{slot, frames, data}: IO.pure(St, after("-", J.AudioStream.update(audio, stream.of(get(sounds, slot)), data, frames), sounds, out, calls))

def run(ops: +List<Op>, +st: St) -> IO(String):
  match ops:
    case Nil{}:
      St{_, _, out, _} = st
      IO.pure(String, out)
    case Con{+op, rest}:
      do IO<String>:
        next : St <- step(st, op)
        run(rest, next)

def start() -> St:
  St{J.AudioDevice.none(), [J.Sound.none(), J.Sound.none(), J.Sound.none(), J.Sound.none()], "", Ext{[0, 0, 0, 0], Nil{}, 0, 0, 0, [J.Music.none(), J.Music.none(), J.Music.none(), J.Music.none()]}}
'''


def words_text(words):
    if len(words) <= 256:
        return '[' + ', '.join(str(w) for w in words) + ']'
    chunks = ', '.join('[' + ', '.join(str(w) for w in words[start:start + 64]) + ']' for start in range(0, len(words), 64))
    return f'words.joined([{chunks}], Nil{{}})'


def bend_step(step, table, paths):
    kind = step[0]
    if kind == 'init':
        return 'OpInit{}'
    if kind == 'close':
        return 'OpClose{}'
    if kind == 'master':
        return f'OpMaster{{{step[1]}}}'
    if kind == 'load':
        frames, rate, size, channels, data, _ = table[step[2]]
        return f'OpLoad{{{step[1]}, {frames}, {rate}, {size}, {channels}, {words_text(data)}}}'
    if kind == 'file':
        return f'OpFile{{{step[1]}, {json.dumps(str(paths[step[2]]))}}}'
    if kind == 'alias':
        return f'OpAlias{{{step[1]}, {step[2]}}}'
    if kind == 'unload':
        return f'OpUnload{{{step[1]}}}'
    if kind == 'unalias':
        return f'OpUnalias{{{step[1]}}}'
    if kind in STATE:
        return f'OpAct{{{step[1]}, {STATE[kind]}}}'
    if kind in TUNE:
        return f'OpTune{{{step[1]}, {TUNE[kind]}, {step[2]}}}'
    if kind == 'update':
        return f'OpUpdate{{{step[1]}, {step[2]}, {words_text(step[3])}}}'
    if kind == 'mix':
        return f'OpMix{{{step[1]}}}'
    if kind == 'default':
        return f'OpDefault{{{step[1]}}}'
    if kind == 'stream':
        return f'OpStream{{{step[1]}, {step[2]}, {step[3]}, {step[4]}}}'
    if kind == 'feed':
        return f'OpFeed{{{step[1]}, {step[2]}, {words_text(step[3])}}}'
    if kind == 'callback':
        return f'OpCallback{{{step[1]}, {step[2]}}}'
    if kind == 'plain':
        return f'OpPlain{{{step[1]}}}'
    if kind == 'periods':
        return f'OpPeriods{{{step[1]}}}'
    if kind in ('attach', 'detach'):
        return f'Op{kind.capitalize()}{{{step[1]}, {step[2]}}}'
    if kind in ('attachmixed', 'detachmixed'):
        return f'Op{"Attach" if kind == "attachmixed" else "Detach"}Mixed{{{step[1]}}}'
    if kind == 'music':
        return f'OpMusic{{{step[1]}, {json.dumps(str(paths[step[2]]))}}}'
    if kind in ('musicupdate', 'musicstop', 'musicunload'):
        return f'Op{dict(musicupdate="MusicUpdate", musicstop="MusicStop", musicunload="MusicUnload")[kind]}{{{step[1]}}}'
    if kind in ('seek', 'looping'):
        return f'Op{kind.capitalize()}{{{step[1]}, {step[2]}}}'
    raise ValueError(kind)


def native_step(step, table, order):
    """(code, a, b, c, payload words) of one step in the reference script."""
    kind = step[0]
    if kind == 'init':
        return 0, 0, 0, 0, []
    if kind == 'close':
        return 1, 0, 0, 0, []
    if kind == 'master':
        return 2, step[1], 0, 0, []
    if kind == 'load':
        frames, rate, size, channels, data, _ = table[step[2]]
        return 3, step[1], frames, rate, [size, channels, *data]
    if kind == 'file':
        return 4, step[1], order.index(step[2]), 0, []
    if kind == 'alias':
        return 5, step[1], step[2], 0, []
    if kind == 'unload':
        return 6, step[1], 0, 0, []
    if kind == 'unalias':
        return 7, step[1], 0, 0, []
    if kind in STATE:
        return 8, step[1], STATE[kind], 0, []
    if kind in TUNE:
        return 9, step[1], TUNE[kind], step[2], []
    if kind == 'update':
        return 10, step[1], step[2], 0, list(step[3])
    if kind == 'dump':
        return 11, step[1], 0, 0, []
    if kind in ('mix', 'plain'):
        return 12, step[1], 0, 0, []
    if kind == 'callback':
        return 16, step[1], step[2], 0, []
    if kind == 'periods':
        return 17, step[1], 0, 0, []
    if kind in ('attach', 'detach'):
        return 18 + (kind == 'detach'), step[1], step[2], 0, []
    if kind in ('attachmixed', 'detachmixed'):
        return 20 + (kind == 'detachmixed'), step[1], 0, 0, []
    if kind == 'music':
        return 22, step[1], order.index(step[2]), 0, []
    if kind == 'raw':
        return 28, order.index(step[1]), 0, 0, []
    if kind == 'mp3':
        return 29, order.index(step[1]), 0, 0, []
    if kind in ('musicupdate', 'musicstop', 'musicunload'):
        return {'musicupdate': 23, 'musicstop': 24, 'musicunload': 27}[kind], step[1], 0, 0, []
    if kind in ('seek', 'looping'):
        return 25 + (kind == 'looping'), step[1], step[2], 0, []
    if kind == 'stream':
        return 13, step[1], step[2], step[3], [step[4]]
    if kind == 'feed':
        return 14, step[1], step[2], 0, list(step[3])
    if kind == 'default':
        return 15, step[1], 0, 0, []
    raise ValueError(kind)


def script(scripts, table, order):
    blob = bytearray(struct.pack('<I', len(scripts)))
    for quiet, steps in scripts:
        blob += struct.pack('<II', len(steps), int(quiet))
        for step in steps:
            code, a, b, c, payload = native_step(step, table, order)
            blob += struct.pack('<5I', code, a, b, c, len(payload)) + b''.join(struct.pack('<I', w) for w in payload)
    return bytes(blob)


def catalog_steps(table, order):
    """The reference pass that converts every wave and file the reference can load."""
    keys, steps = [], [('init',)]
    for name, wave in table.items():
        if wave[5] is None:
            keys.append(('wave', name))
            steps += [('load', 0, name), ('dump', 0), ('unload', 0)]
    for name in order:
        keys.append(('file', name))
        steps += [('file', 0, name), ('dump', 0), ('unload', 0)]
    return keys, steps + [('raw', name) for name in RAW_FILES] + [('mp3', name) for name in MP3_FILES]


def render_for(table, paths):
    def render(selected, gpu):
        lines = [PROGRAM, 'def main() -> IO(Unit):\n  do IO<Unit>:']
        for index, (_, case) in enumerate(selected):
            ops = ', '.join(bend_step(step, table, paths) for step in case['steps'])
            lines.append(f'    s{index} : String <- run([{ops}], start())\n    IO.print(s{index})')
        return '\n'.join(lines) + '\n'
    return render


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('sound', args)
    work = (probe.work / 'files').resolve()
    work.mkdir(parents=True, exist_ok=True)
    raylib = args.raylib_source.resolve()
    paths = {name: raylib / relative for name, relative in FILES.items()}
    written = {'tiny.wav': tiny_wav(), 'text.wav': b'This is not a RIFF file, whatever its name says.\n', 'other.xyz': tiny_wav()}
    written.update({f'{name}.wav': entry[0] for name, entry in music_files().items()})
    cuts = mp3_probe.cases((raylib / MP3_SOURCE).read_bytes())
    written.update({f'{name}.mp3': cuts[cut] for name, cut in MP3_FILES.items()})
    for name, data in written.items():
        (work / name).write_bytes(data)
    paths.update(tiny=work / 'tiny.wav', text=work / 'text.wav', other=work / 'other.xyz', missing=work / 'missing.wav')
    paths.update({name: work / f'{name}.wav' for name in music_files()})
    paths.update({name: raylib / relative for name, relative in RAW_FILES.items()})
    paths.update({name: work / f'{name}.mp3' for name in MP3_FILES})
    order = list(paths)
    table, items = waves(), cases()
    keys, steps = catalog_steps(table, order)

    def reference(scripts, name):
        path = work / f'{name}.bin'
        path.write_bytes(script(scripts, table, order))
        source = NATIVE.replace('PATH', str(path)).replace('FILES', ', '.join(json.dumps(str(paths[n])) for n in order))
        return probe.native(source, name, extra_flags=FLAGS).splitlines()

    cataloged = reference([(True, steps)], 'catalog')
    dumps = [line.split()[1:] for line in cataloged if line[:2] == 'D ']
    raws = [[int(w) for w in line.split()[1:]] for line in cataloged if line[:2] == 'W ']
    streams = [[int(w) for w in line.split()[1:]] for line in cataloged if line[:2] == 'M ']
    if len(dumps) != len(keys) or len(raws) != len(RAW_FILES) or len(streams) != len(MP3_FILES):
        raise ProbeFailure(f'sound: the reference converted {len(dumps)} of {len(keys)} waves and decoded {len(raws)} of {len(RAW_FILES)} and {len(streams)} of {len(MP3_FILES)} files')
    catalog = {('wave', name): wave[5] for name, wave in table.items() if wave[5] is not None}
    for key, (frames, *words) in zip(keys, dumps):
        catalog[key] = (int(frames), [int(w) for w in words])
    catalog['wave', 'zero'] = None
    for name, (frames, rate, size, channels, *words) in zip(RAW_FILES, raws):
        catalog['raw', name] = (frames, rate, size, channels, words)
    for name, (frames, rate, channels, delay, readable, *words) in zip(MP3_FILES, streams):
        catalog['mp3', name] = (frames, rate, channels, delay, readable, words)
    if catalog['mp3', 'mp3tag'][:5] != (4125934, 44100, 2, 1105, 11567) or catalog['mp3', 'mp3plain'][:5] != (13824, 44100, 2, 0, 13824):
        raise ProbeFailure(f'sound: the reference read the MP3 cuts as {catalog["mp3", "mp3tag"][:5]} and {catalog["mp3", "mp3plain"][:5]}')
    if catalog['raw', 'target'][:4] != (44100, 22050, 16, 2):
        raise ProbeFailure(f'sound: the reference decoded target.qoa as {catalog["raw", "target"][:4]}')
    sizes = {name: catalog['file', name][0] for name in FILES}
    if sizes != dict(boom=29647, buttonfx=48000, sound=26522, coin=39334) or catalog['file', 'tiny'][0] != 44:
        raise ProbeFailure(f'sound: the reference loaded the files as {sizes}')
    if any(catalog['file', name][0] for name in FILE_ERRORS) or catalog['wave', 'mono16'][1][:4] != [bits(100 / 32768)] * 2 + [bits(-200 / 32768)] * 2:
        raise ProbeFailure('sound: the reference did not convert the waves as expected')

    rows = [expected(case, catalog) for case in items]
    for case, (_, _, defined) in zip(items, rows):
        if case['id'].startswith('refused-') == defined:
            raise ProbeFailure(f'sound: {case["id"]} is {"" if defined else "not "}defined for raylib')
    native = [(case, row) for case, row in zip(items, rows) if row[2]]
    contracts = [case['id'] for case, row in zip(items, rows) if not row[2]]
    if len(native) < 25 or len(contracts) < 12:
        raise ProbeFailure(f'sound: {len(native)} compared and {len(contracts)} refused cases; the corpus lost coverage')
    output = [line[2:] for line in reference([(False, case['steps']) for case, _ in native], 'reference') if line[:2] == 'C ']
    if len(output) != len(native):
        raise ProbeFailure(f'sound: the reference printed {len(output)} rows for {len(native)} cases')
    for (case, row), line in zip(native, output):
        if line != row[1]:
            mine, theirs = row[1].split(';'), line.split(';')
            at = next((i for i, (a, b) in enumerate(zip(mine, theirs)) if a != b), min(len(mine), len(theirs)))
            raise ProbeFailure(f'sound: the model disagrees with raylib on {case["id"]} at step {at} {case["steps"][at] if at < len(case["steps"]) else ""}:\n'
                               f'  model  {mine[at] if at < len(mine) else None}\n  raylib {theirs[at] if at < len(theirs) else None}')

    lanes = probe.candidates(render_for(table, paths), list(enumerate(items)), batch=12,
                             parse=lambda text, selected: [line.strip().lstrip(';') for line in text.splitlines() if line.strip()])
    probe.compare([row[0] for row in rows], lanes, describe=lambda index: items[index]['id'])
    probe.finish(cases=len(items), compared=len(native), contracts=len(contracts), refused=contracts, steps=sum(len(case['steps']) for case in items),
                 waves=len(table), files=len(order), files_sha256=hashlib.sha256(b''.join(name.encode() + data for name, data in sorted(written.items()))).hexdigest())


if __name__ == '__main__':
    main()
