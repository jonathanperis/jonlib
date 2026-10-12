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

import probekit
from probekit import ProbeFailure

SLOTS = 4
ZERO = (0, 0, 0, 0, 0)
FLAGS = ['-ffp-contract=off', '-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS', '-DMA_ENABLE_NULL', '-D_DEFAULT_SOURCE', '-Wno-everything']
FILES = {'boom': 'examples/textures/resources/boom.wav', 'buttonfx': 'examples/textures/resources/buttonfx.wav',
         'sound': 'examples/audio/resources/sound.wav', 'coin': 'examples/audio/resources/coin.wav'}
FILE_ERRORS = {'missing': 'file', 'text': 'header', 'other': 'unsupported'}


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


def odd(word):
    """A subnormal or a NaN: values the hosts' miniaudio builds do not treat alike in the device callback."""
    return bool(word & 0x007FFFFF) and (word & 0x7F800000) in (0, 0x7F800000)


def oddf(*values):
    return any(odd(bits(v)) for v in values)


def reduced(rate):
    g = math.gcd(48000, rate)
    return 48000 // g, rate // g


def set_rate(b, wanted):
    """ma_data_converter_set_rate(48000, wanted): the filter for the reduced rates, the timer in the new output rate."""
    old = reduced(b['rate'])[1]
    rin, rout = reduced(wanted)
    frac = ((b['t_frac'] // old) * rout + (((b['t_frac'] % old) * rout) & 0xFFFFFFFF) // old) & 0xFFFFFFFF
    # ma_lpf1_reinit: (float)exp(-2*pi*cutoff/rate) with libm exp, the cutoff min*0.5 and the rate max of the reduced rates.
    coef = None if rin == rout or rout >= 1 << 31 else f32(math.exp((-2 * math.pi * (min(rin, rout) * 0.5)) / max(rin, rout)))
    b.update(rate=wanted, t_int=(b['t_int'] + frac // rout) & 0xFFFFFFFF, t_frac=frac % rout, wide=rout >= 1 << 31, coef=coef)


def lowpass(b, frame):
    """ma_lpf1_process_pcm_frame_f32 on a frame: (the filtered frame, whether the hosts agree on every value)."""
    a, out, fine = b['coef'], [], True
    for channel, x in enumerate(frame):
        r1, c = b['r1'][channel], f32(1.0 - a)
        y = f32(f32(c * x) + f32(a * r1))
        fine &= not oddf(a, x, r1, c, f32(c * x), f32(a * r1), y)
        out.append(y)
    b['r1'] = list(out)
    return out, fine


def flow(b, frames, remaining):
    """ma_linear_resampler_process_pcm_frames_f32 on a stream: (input frames used, frames made, fine)."""
    rin, rout = reduced(b['rate'])
    plain, down, used, made, fine = rin == rout, rin > rout, 0, [], True
    while remaining > 0:
        if b['t_int'] > 0:
            if used >= len(frames):
                break
            frame = list(frames[used])
            used += 1
            fine &= not oddf(*frame)
            if not plain and down:
                frame, ok = lowpass(b, frame)
                fine &= ok
            b['x0'], b['x1'], b['t_int'] = b['x1'], frame, b['t_int'] - 1
        else:
            a = f32(f32(float(b['t_frac'])) / f32(float(rout)))
            y = [f32(p + f32(f32(q - p) * a)) for p, q in zip(b['x0'], b['x1'])]
            fine &= not oddf(a) and not any(oddf(p, q, f32(q - p), f32(f32(q - p) * a), v) for p, q, v in zip(b['x0'], b['x1'], y))
            if not plain and not down:
                y, ok = lowpass(b, y)
                fine &= ok
            made.append(y)
            remaining -= 1
            b['t_int'], b['t_frac'] = b['t_int'] + rin // rout, b['t_frac'] + rin % rout
            if b['t_frac'] >= rout:
                b['t_int'], b['t_frac'] = b['t_int'] + 1, b['t_frac'] - rout
    return used, made, fine


def turn(b, data, frames):
    """A playing buffer in a callback (raudio's runs of 512 frames over its converter): (frames made, fine)."""
    size, fine, made, need = b['frames'], not b['wide'] and b['frames'] > 0, [], frames
    if not fine:
        return [], False
    while need > 0 and b['playing']:
        now, total, broke = min(need, 512), 0, False
        while total < now and not broke:
            want = now - total
            if b['residual']:
                used, out, ok = flow(b, b['residual'], want)
                b['residual'] = b['residual'][used:]
            else:
                estimate = min(512, max(int(f32(f32(48000.0 / f32(float(b['rate']))) * float(want))), 1))
                half = max(size // 2 if size > 1 else size, 1)
                count = 0 if not b['playing'] or b['cursor'] // half > 1 else min(estimate, size - b['cursor'])
                read = [[fl(data[2 * (b['cursor'] + i)]), fl(data[2 * (b['cursor'] + i) + 1])] for i in range(count)]
                if count and count == size - b['cursor']:
                    b['playing'], b['cursor'] = False, 0
                else:
                    b['cursor'] += count
                used, out, ok = flow(b, read, want)
                b['residual'], broke = read[used:used + 8], count < estimate
            total, fine = total + len(out), fine and ok
            made += out
        if b['playing'] and total < now:
            b['playing'], b['cursor'] = False, 0
        need = need - total if b['playing'] else 0
    return made, fine


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


def tiny_wav():
    data = bytes([128, 200, 255, 130, 0, 60, 128, 190, 250, 128])
    return (b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 11025, 11025, 1, 8)
            + b'data' + struct.pack('<I', len(data)) + data)


# Steps: ('init',), ('close',), ('master', word), ('load', slot, wave), ('file', slot, name), ('alias', slot, source),
# ('unload', slot), ('unalias', slot), ('play'|'stop'|'pause'|'resume', slot), ('volume'|'pitch'|'pan', slot, word),
# ('update', slot, frames, words), ('mix', frames).
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

    add('refused-mix-unready', ('mix', 4), ('init',), ('load', 0, 'mono16'), ('play', 0), ('close',), ('mix', 4))
    add('refused-mix-no-frames', ('init',), ('mix', 0))
    add('refused-mix-too-long', ('init',), ('mix', 1048577))
    add('refused-mix-empty-buffer', ('init',), ('load', 0, 'noframes'), ('play', 0), ('mix', 2))
    add('refused-mix-freed', ('init',), ('load', 0, 'mono16'), ('alias', 1, 0), ('unload', 0), ('play', 1), ('mix', 2))
    add('refused-mix-subnormal', ('init',), ('load', 0, 'tiny32'), ('play', 0), ('mix', 1), ('mix', 3))
    add('refused-mix-subnormal-volume', ('init',), ('load', 0, 'stereo16'), ('volume', 0, bits(1e-40)), ('play', 0), ('mix', 2))
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
        self.catalog, self.ready, self.master, self.next = catalog, False, 0, 1
        self.buffers, self.blocks, self.sounds, self.undefined = [], {}, [ZERO] * SLOTS, False

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

    def track(self, frames, block):
        self.buffers.append(dict(id=self.next, block=block, frames=frames, volume=bits(1.0), pitch=bits(1.0), pan=0, playing=False, paused=False,
                                 rate=48000, cursor=0, t_int=1, t_frac=0, x0=[0.0, 0.0], x1=[0.0, 0.0], r1=[0.0, 0.0], residual=[], coef=None, wide=False))
        self.next += 1
        return self.next - 1

    def stop(self, found):
        if found['playing'] and not found['paused']:
            found['playing'], found['cursor'] = False, 0

    def mix(self, frames):
        """One device callback: the samples, or None (and nothing changed) for what Jonlib refuses."""
        if not self.ready or frames == 0 or frames > 1 << 20 or odd(self.master):
            return None
        out, fine, after = [0] * (2 * frames), True, []
        for b in self.buffers:
            if not b['playing'] or b['paused']:
                after.append(b)
                continue
            data = self.blocks.get(b['block'])
            if data is None:
                return None
            volume, pan = fl(b['volume']), fl(b['pan'])
            right = f32(f32(pan + 1.0) / 2.0)
            left = f32(1.0 - right)
            levels = []
            fine &= not (odd(b['volume']) or odd(b['pan']) or odd(bits(f32(pan + 1.0))))
            for side in (left, right):
                half, square = f32(volume * 0.5), f32(side * side)
                level = f32(f32(half * side) * f32(3.0 - square))
                fine &= not any(odd(bits(v)) for v in (side, half, f32(half * side), square, f32(3.0 - square), level))
                levels.append(level)
            b = copy.deepcopy(b)
            made, ok = turn(b, data, frames)
            fine &= ok
            for j, frame in enumerate(made):
                for channel in range(2):
                    total, scaled = out[2 * j + channel], f32(frame[channel] * levels[channel])
                    new = bits(f32(fl(total) + scaled))
                    fine &= not any(odd(w) for w in (bits(frame[channel]), total, bits(scaled), new))
                    out[2 * j + channel] = new
            after.append(b)
        master, sent = fl(self.master), []
        for word in out:
            x = f32(fl(word) * master) if self.master != bits(1.0) else fl(word)
            fine &= not (odd(word) or odd(bits(x)))
            sent.append(bits(-1.0 if x < -1 else 1.0 if x > 1 else x))
        if not fine:
            return None
        self.buffers = after
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
                    found['playing'], found['paused'], found['cursor'] = True, False, 0
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
                valid = frames <= found['frames'] and len(words) == 2 * frames
                held = found['block'] in self.blocks
                self.undefined |= not (valid and held)
                if valid and held:
                    self.stop(found)
                    self.blocks[found['block']][:len(words)] = words
        elif kind == 'mix':
            self.mixed = self.mix(step[1])
            self.undefined |= self.mixed is None
        else:
            raise ValueError(kind)
        return tag

    def state(self):
        parts = [f'R{int(self.ready)} M{self.master}']
        for slot, (number, frames, rate, size, channels) in enumerate(self.sounds):
            found = self.buffer(slot)
            valid = int(frames > 0 and number > 0 and rate > 0 and size > 0 and channels > 0)
            playing = int(found is not None and found['playing'] and not found['paused'])
            parts.append(f'S{number},{frames},{rate},{size},{channels},{valid},{playing}')
        for b in self.buffers:
            samples = '-' if not b['block'] else str(fnv(self.blocks[b['block']])) if b['block'] in self.blocks else 'x'
            held = [b['t_int'], b['t_frac'], *map(bits, b['x0'] + b['x1'] + b['r1']), 0 if b['coef'] is None else bits(b['coef']), len(b['residual']),
                    fnv(bits(v) for frame in b['residual'] for v in frame)]
            parts.append(f'B{b["id"]},{b["block"]},{b["frames"]},{b["volume"]},{b["pitch"]},{b["pan"]},{int(b["playing"])},{int(b["paused"])},{samples},'
                         f'{b["rate"]},{b["cursor"]},{",".join(map(str, held))}')
        return ' '.join(parts)


def expected(case, catalog):
    """(the row with error tags, the row without, whether raylib has a defined answer for every step)."""
    model, tagged, plain = Model(catalog), [], []
    for step in case['steps']:
        tag = model.step(step)
        state = model.state() + (('' if step[0] != 'mix' else ' X-' if model.mixed is None else f' X{fnv(model.mixed)}'))
        tagged.append(f'E:{tag} {state}')
        plain.append(state)
    return ';'.join(tagged), ';'.join(plain), not model.undefined


NATIVE = r'''#include "raudio.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SLOTS 4
#define MADE 64
static Sound slots[SLOTS];
static int slot_id[SLOTS];
static rAudioBuffer *created[MADE];
static int owner[MADE], gone[MADE], freed[MADE + 1], made;
static const char *files[] = { FILES };
static unsigned mixed_hash;

static unsigned rd(FILE *f) { unsigned v = 0; if (fread(&v, 4, 1, f) != 1) exit(3); return v; }
static unsigned word(float x) { unsigned v; memcpy(&v, &x, 4); return v; }
static float real(unsigned v) { float x; memcpy(&x, &v, 4); return x; }

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

static void state(int first)
{
    printf("%sR%d M%u", first? "" : ";", (int)IsAudioDeviceReady(), word(GetMasterVolume()));
    for (int s = 0; s < SLOTS; s++)
    {
        Sound x = slots[s];
        int live = (slot_id[s] > 0) && !gone[slot_id[s] - 1];
        printf(" S%d,%u,%u,%u,%u,%d,%d", slot_id[s], x.frameCount, x.stream.sampleRate, x.stream.sampleSize, x.stream.channels, (int)IsSoundValid(x),
               (AUDIO.System.isReady && live)? (int)IsSoundPlaying(x) : 0);
    }
    for (rAudioBuffer *b = AUDIO.Buffer.first; b != NULL; b = b->next)
    {
        int id = number(b);
        if (id < 1) exit(5);
        printf(" B%d,%d,%u,%u,%u,%u,%d,%d,", id, owner[id - 1], b->sizeInFrames, word(b->volume), word(b->pitch), word(b->pan), (int)b->playing, (int)b->paused);
        if (owner[id - 1] == 0) printf("-");
        else if (freed[owner[id - 1]]) printf("x");
        else printf("%u", fnv((const unsigned *)b->data, b->sizeInFrames*2));
        ma_linear_resampler *linear = &b->converter.resampler.state.linear;
        printf(",%u,%u,%u,%u,%u,%u,%u,%u", b->converter.resampler.sampleRateOut, b->frameCursorPos, linear->inTimeInt, linear->inTimeFrac,
               word(linear->x0.f32[0]), word(linear->x0.f32[1]), word(linear->x1.f32[0]), word(linear->x1.f32[1]));
        if ((linear->lpf.lpf1Count != 1) || (linear->lpf.lpf2Count != 0)) exit(8);
        printf(",%u,%u,%u", word(linear->lpf.pLPF1[0].pR1[0].f32), word(linear->lpf.pLPF1[0].pR1[1].f32),
               (linear->config.sampleRateIn != linear->config.sampleRateOut)? word(linear->lpf.pLPF1[0].a.f32) : 0);
        printf(",%u,%u", b->converterResidualCount, fnv((const unsigned *)b->converterResidual, b->converterResidualCount*2));
    }
}

int main(void)
{
    SetTraceLogLevel(LOG_NONE);
    FILE *f = fopen("PATH", "rb");
    if (!f) return 2;
    unsigned count = rd(f);
    for (unsigned k = 0; k < count; k++)
    {
        unsigned steps = rd(f), quiet = rd(f);
        memset(&AUDIO, 0, sizeof(AUDIO));
        memset(slots, 0, sizeof(slots)); memset(slot_id, 0, sizeof(slot_id));
        memset(owner, 0, sizeof(owner)); memset(gone, 0, sizeof(gone)); memset(freed, 0, sizeof(freed));
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
                    if (ma_device_handle_backend_data_callback(&AUDIO.System.device, mixed, NULL, a) != MA_SUCCESS) return 7;
                    mixed_hash = fnv((const unsigned *)mixed, a*2);
                    free(mixed);
                } break;
                default: return 6;
            }
            free(payload);
            if (!quiet) state(i == 0);
            if (!quiet && (code == 12)) printf(" X%u", mixed_hash);
        }
        if (!quiet) printf("\n");
        if (AUDIO.System.isReady) CloseAudioDevice();
    }
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/mixer.bend as Mixer
import ../../src/resampler.bend as Resampler

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

type St is Data:
  St{audio: J.AudioDevice, sounds: +List<J.Sound>, out: String}

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
  " S" ++ U32.show(buffer) ++ "," ++ U32.show(frames) ++ "," ++ U32.show(rate) ++ "," ++ U32.show(size) ++ "," ++ U32.show(channels) ++ "," ++ flag(J.Sound.is_valid(sound)) ++ "," ++ flag(J.Sound.is_playing(audio, sound))

def sounds.text(sounds: +List<J.Sound>, +audio: J.AudioDevice) -> String:
  match sounds:
    case Nil{}: ""
    case Con{+sound, rest}: sound.text(audio, sound) ++ sounds.text(rest, audio)

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

def head.text(head: Mixer.Head) -> String:
  Mixer.Head{rate, +mode, +coef, cursor, st, +residual} = head
  "," ++ U32.show(rate) ++ "," ++ U32.show(cursor) ++ st.text(st) ++ "," ++ U32.show(Bool.pick(U32, U32.is_eq(mode, 1), coef, 0)) ++ "," ++ U32.show(count(residual, 0)) ++ "," ++ U32.show(fnv.frames(residual, 2166136261))

def buffers.text(buffers: +List<J.AudioDevice.Buffer>, +blocks: +List<J.AudioDevice.Block>) -> String:
  match buffers:
    case Nil{}: ""
    case Con{J.AudioBuffer{+id, +block, +frames, +volume, +pitch, +pan, +playing, +paused, head}, rest}:
      " B" ++ U32.show(id) ++ "," ++ U32.show(block) ++ "," ++ U32.show(frames) ++ "," ++ U32.show(F32.bits(volume)) ++ "," ++ U32.show(F32.bits(pitch)) ++ "," ++ U32.show(F32.bits(pan)) ++ "," ++ flag(playing) ++ "," ++ flag(paused) ++ "," ++ hashed(block, J.AudioDevice.block.find(blocks, block)) ++ head.text(head) ++ buffers.text(rest, blocks)

def state(+audio: J.AudioDevice, +sounds: +List<J.Sound>) -> String:
  J.AudioDevice{_, _, _, +buffers, +blocks} = audio
  "R" ++ flag(J.AudioDevice.is_ready(audio)) ++ " M" ++ U32.show(F32.bits(J.AudioDevice.master_volume(audio))) ++ sounds.text(sounds, audio) ++ buffers.text(buffers, blocks)

def after(+tag: String, +audio: J.AudioDevice, +sounds: +List<J.Sound>, +out: String) -> St:
  St{audio, sounds, out ++ ";E:" ++ tag ++ " " ++ state(audio, sounds)}

def mixed(result: J.AudioDevice & Maybe<&2, +List<U32>>, +sounds: +List<J.Sound>, +out: String) -> St:
  match result:
    case Tuple{+audio, Some{+samples}}: St{audio, sounds, out ++ ";E:- " ++ state(audio, sounds) ++ " X" ++ U32.show(fnv(samples, 2166136261))}
    case Tuple{+audio, None{}}: St{audio, sounds, out ++ ";E:- " ++ state(audio, sounds) ++ " X-"}

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

def loaded(result: J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound>, +slot: U32, +sounds: +List<J.Sound>, +out: String) -> St:
  match result:
    case Tuple{+audio, Done{+sound}}: after("-", audio, set(sounds, slot, sound), out)
    case Tuple{+audio, Fail{error}}: after(tag(error), audio, set(sounds, slot, J.Sound.none()), out)

def aliased(result: J.AudioDevice & J.Sound, +slot: U32, +sounds: +List<J.Sound>, +out: String) -> St:
  match result:
    case Tuple{+audio, +sound}: after("-", audio, set(sounds, slot, sound), out)

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
  St{+audio, +sounds, +out} = st
  match op:
    case OpInit{}: IO.pure(St, after("-", J.AudioDevice.init(audio), sounds, out))
    case OpClose{}: IO.pure(St, after("-", J.AudioDevice.close(audio), sounds, out))
    case OpMaster{bits}: IO.pure(St, after("-", J.AudioDevice.set_master_volume(audio, J.Wave.float_bits(bits)), sounds, out))
    case OpLoad{slot, frames, rate, size, channels, data}: IO.pure(St, loaded(J.Sound.load_from_wave(audio, J.Wave{frames, rate, size, channels, data}), slot, sounds, out))
    case OpFile{+slot, path}:
      do IO<St>:
        result : J.AudioDevice & Result<&1, &1, J.Sound.Error, J.Sound> <- J.Sound.load(audio, path)
        IO.pure(St, loaded(result, slot, sounds, out))
    case OpAlias{slot, source}: IO.pure(St, aliased(J.Sound.load_alias(audio, get(sounds, source)), slot, sounds, out))
    case OpUnload{slot}: IO.pure(St, after("-", J.Sound.unload(audio, get(sounds, slot)), sounds, out))
    case OpUnalias{slot}: IO.pure(St, after("-", J.Sound.unload_alias(audio, get(sounds, slot)), sounds, out))
    case OpAct{slot, code}: IO.pure(St, after("-", acted(code, audio, get(sounds, slot)), sounds, out))
    case OpTune{slot, code, bits}: IO.pure(St, after("-", tuned(code, audio, get(sounds, slot), J.Wave.float_bits(bits)), sounds, out))
    case OpUpdate{slot, frames, data}: IO.pure(St, after("-", J.Sound.update(audio, get(sounds, slot), data, frames), sounds, out))
    case OpMix{frames}: IO.pure(St, mixed(J.AudioDevice.mix(audio, frames), sounds, out))

def run(ops: +List<Op>, +st: St) -> IO(String):
  match ops:
    case Nil{}:
      St{_, _, out} = st
      IO.pure(String, out)
    case Con{+op, rest}:
      do IO<String>:
        next : St <- step(st, op)
        run(rest, next)

def start() -> St:
  St{J.AudioDevice.none(), [J.Sound.none(), J.Sound.none(), J.Sound.none(), J.Sound.none()], ""}
'''


def words_text(words):
    return '[' + ', '.join(str(w) for w in words) + ']'


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
    if kind == 'mix':
        return 12, step[1], 0, 0, []
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
    return keys, steps


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
    for name, data in written.items():
        (work / name).write_bytes(data)
    paths.update(tiny=work / 'tiny.wav', text=work / 'text.wav', other=work / 'other.xyz', missing=work / 'missing.wav')
    order = list(paths)
    table, items = waves(), cases()
    keys, steps = catalog_steps(table, order)

    def reference(scripts, name):
        path = work / f'{name}.bin'
        path.write_bytes(script(scripts, table, order))
        source = NATIVE.replace('PATH', str(path)).replace('FILES', ', '.join(json.dumps(str(paths[n])) for n in order))
        return probe.native(source, name, extra_flags=FLAGS).splitlines()

    dumps = [line.split()[1:] for line in reference([(True, steps)], 'catalog') if line[:2] == 'D ']
    if len(dumps) != len(keys):
        raise ProbeFailure(f'sound: the reference converted {len(dumps)} of {len(keys)} waves')
    catalog = {('wave', name): wave[5] for name, wave in table.items() if wave[5] is not None}
    for key, (frames, *words) in zip(keys, dumps):
        catalog[key] = (int(frames), [int(w) for w in words])
    catalog['wave', 'zero'] = None
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
