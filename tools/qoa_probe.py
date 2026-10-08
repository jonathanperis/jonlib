#!/usr/bin/env python3
"""Compare raylib's QOA loading and export with Jonlib's Wave.

raylib is built with its audio module (QOA support is on by default). Waves
of 1, 2, 3 and 8 channels, partial and multiple 5120-frame QOA frames, sines,
noise, full-scale square waves (whose residuals overflow qoa_div's int
product, as compiled) and silence go through ExportWave(".qoa"); the encoded
bytes must match. ExportWave also refuses non-16-bit waves (no file) and waves
qoa_encode rejects (an empty file): no frames, sample rate 0 or above
0xffffff, more than 8 channels.

The native encodings and edits of them are then loaded (LoadWave of ".qoa"
and ".QOA" names): truncated frames and slices, a later frame with another
channel count or sample rate, a frame size past the data, a frame claiming
more samples than its slices hold, a declared total above the encoded
samples, bad magic, zero total/channels/rate and short files. Frame count,
sample rate, sample size, channels and every sample must match, or both sides
fail. Jonlib contracts (not native comparisons): files whose frames decode
past the declared total (qoa.h writes past its buffer) or with more than 8
channels (past its LMS state) are InvalidWaveData. CPU/JS.
"""
import hashlib
import json
import math
import random
import struct

import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/qoa-probe/cases'


def riff16(channels, rate, samples):
    data = struct.pack(f'<{len(samples)}H', *samples)
    fmt = struct.pack('<HHIIHH', 1, channels, rate, rate * channels * 2, channels * 2, 16)
    body = b'WAVE' + b'fmt ' + struct.pack('<I', 16) + fmt + b'data' + struct.pack('<I', len(data)) + data
    return b'RIFF' + struct.pack('<I', len(body)) + body


def u16(value):
    return int(value) & 0xFFFF


def waves():
    """Encoder inputs: (id, channels, rate, samples, size); larger ones go through WAV files."""
    rng = random.Random(0x0A0)
    out = []
    out.append(('noise-1ch-50', 1, 44100, [u16(rng.randrange(-32768, 32768)) for _ in range(50)], 16))
    out.append(('sine-1ch-997', 1, 22050, [u16(round(12000 * math.sin(i * 0.07))) for i in range(997)], 16))
    out.append(('square-1ch-300', 1, 8000, [u16(32767 if (i // 9) % 2 else -32768) for i in range(300)], 16))
    stereo = []
    for i in range(5125):
        stereo += [u16(round(9000 * math.sin(i * 0.031) + rng.randrange(-300, 300))), u16(round(20000 * math.sin(i * 0.0021)))]
    out.append(('stereo-5125', 2, 48000, stereo, 16))
    out.append(('three-ch-61', 3, 11025, [u16(rng.randrange(-4000, 4000) * (c + 1)) for _ in range(61) for c in range(3)], 16))
    out.append(('eight-ch-45', 8, 16000, [u16(rng.randrange(-32768, 32768) >> c) for _ in range(45) for c in range(8)], 16))
    out.append(('silence-1ch-20', 1, 16777215, [0] * 20, 16))
    out.append(('one-frame', 1, 1, [u16(-1)], 16))
    # Refusals: qoa_encode returns NULL (empty file); non-16-bit waves write nothing.
    out.append(('nine-ch', 9, 8000, [u16(i * 100) for i in range(27)], 16))
    out.append(('rate-zero', 1, 0, [1, 2, 3], 16))
    out.append(('rate-2^24', 1, 16777216, [1, 2, 3], 16))
    out.append(('no-frames', 2, 8000, [], 16))
    out.append(('eight-bit', 1, 8000, [0, 128, 255], 8))
    return out


INLINE = 64


def c_wave(channels, rate, samples, size):
    kind = {8: 'unsigned char', 16: 'unsigned short'}[size]
    data = f'(void*)({kind}[]){{{",".join(map(str, samples))}}}' if samples else 'NULL'
    frames = len(samples) // channels
    return f'(Wave){{{frames},{rate},{size},{channels},{data}}}'


PRINTERS = ['#include "raylib.h"', '#include <stdio.h>', '#include <string.h>',
            'static void wave(Wave w){if(!w.data){puts("null");return;}'
            'printf("[%u,%u,%u,%u,[",w.frameCount,w.sampleRate,w.sampleSize,w.channels);unsigned n=w.frameCount*w.channels;'
            'for(unsigned i=0;i<n;i++)printf("%s%u",i?",":"",((unsigned short*)w.data)[i]);puts("]]");}',
            'static void file(const char *path){FILE *f=fopen(path,"rb");int c,i=0;if(!f){puts("null");return;}'
            'printf("[");while((c=fgetc(f))!=EOF)printf("%s%d",i++?",":"",c);puts("]");fclose(f);}',
            'int main(void){SetTraceLogLevel(LOG_NONE);']


def native_export(probe, items):
    lines = list(PRINTERS)
    for index, (name, channels, rate, samples, size) in enumerate(items):
        path = f'{WORK}/native/{index:02}-{name}.qoa'
        (ROOT / path).unlink(missing_ok=True)
        source = (f'Wave w={c_wave(channels, rate, samples, size)};' if len(samples) <= INLINE else
                  f'Wave w=LoadWave("{WORK}/{index:02}-{name}.wav");')
        lines.append(f'{{{source}printf("%d\\n",ExportWave(w,"{path}"));file("{path}");}}')
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n', name='export')


def native_load(probe, items):
    lines = list(PRINTERS)
    for case in items:
        if case['kind'] == 'native':
            lines.append(f'{{Wave w=LoadWave("{case["path"]}");wave(w);UnloadWave(w);}}')
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n', name='load')


def be64(value):
    return struct.pack('>Q', value)


def frame_at(data, p):
    header = struct.unpack('>Q', data[p:p + 8])[0]
    return header >> 56, (header >> 32) & 0xFFFFFF, (header >> 16) & 0xFFFF, header & 0xFFFF


def edit_frame(data, p, channels=None, rate=None, count=None, size=None):
    ch, sr, n, fs = frame_at(data, p)
    ch, sr, n, fs = (ch if channels is None else channels, sr if rate is None else rate,
                     n if count is None else count, fs if size is None else size)
    return data[:p] + be64(ch << 56 | sr << 32 | n << 16 | fs) + data[p + 8:]


def header(data, magic=None, total=None):
    m, t = struct.unpack('>II', data[:8])
    return struct.pack('>II', m if magic is None else magic, t if total is None else total) + data[8:]


def loads(encoded):
    """Decoder cases from the native encodings: (id, bytes, kind)."""
    out = []

    def add(name, data, kind='native'):
        out.append(dict(id=name, bytes=data, kind=kind))

    for name, data in encoded.items():
        add(name, data)
    mono, stereo, eight = encoded['sine-1ch-997'], encoded['stereo-5125'], encoded['eight-ch-45']
    second = 8 + frame_at(stereo, 8)[3]
    add('truncated-slice', mono[:len(mono) - 13])
    add('truncated-header', mono[:12])
    add('truncated-state', mono[:8 + 8 + 10])
    add('stereo-first-frame', stereo[:second])
    add('stereo-cut-second', stereo[:second + 50])
    add('second-frame-mono', edit_frame(stereo, second, channels=1))
    add('second-frame-rate', edit_frame(stereo, second, rate=44100))
    add('frame-size-past-end', edit_frame(mono, 8, size=frame_at(mono, 8)[3] + 8))
    add('frame-count-past-slices', edit_frame(mono, 8, count=frame_at(mono, 8)[2] + 20))
    add('frame-short-count', edit_frame(mono, 8, count=500))
    add('total-above', header(mono, total=2000))
    add('total-above-stereo', header(stereo, total=12000))
    add('bad-magic', header(mono, magic=0x716F6167))
    add('total-zero', header(mono, total=0))
    add('channels-zero', edit_frame(mono, 8, channels=0))
    add('rate-zero', edit_frame(mono, 8, rate=0))
    add('fifteen-bytes', mono[:15])
    add('empty', b'')
    add('eight-ch-rate-one', edit_frame(eight, 8, rate=1))
    add('total-below', header(mono, total=996), 'data')
    add('total-below-stereo', header(stereo, total=5121), 'data')
    add('nine-channels', edit_frame(eight, 8, channels=9), 'data')
    return out


EXPECTED = {'data': ['error', 'data']}

PROGRAM = '''import Base
import ../../jonlib.bend as J
def show(+values: +List<U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, values)
def wave(+w: J.Wave) -> String:
  J.Wave{frames, rate, size, channels, data} = w
  "[" ++ U32.show(frames) ++ "," ++ U32.show(rate) ++ "," ++ U32.show(size) ++ "," ++ U32.show(channels) ++ "," ++ show(data) ++ "]"
def error(e: J.Wave.Error) -> String:
  match e:
    case J.InvalidWaveData{}: "[\\"error\\", \\"data\\"]"
    case _: "null"
def loaded(result: Result<&1, &1, J.Wave.IOError, J.Wave>) -> IO(Unit):
  match result:
    case Fail{J.WaveDataError{e}}: IO.print(error(e))
    case Fail{_}: IO.print("null")
    case Done{w}: IO.print(wave(w))
def written(result: Result<&1, &1, J.Wave.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("0")
    case Done{_}: IO.print("1")
def exported(path: String, result: Result<&1, &1, J.Wave.IOError, J.Wave>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("load failed")
    case Done{w}: IO.bind(Result<&1, &1, J.Wave.IOError, Unit>, Unit, J.Wave.write(w, path), written)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for kind, payload in selected:
        if kind == 'load':
            body += f'    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, J.Wave>, Unit, J.Wave.load({json.dumps(payload)}), loaded)\n'
        else:
            index, (name, channels, rate, samples, size) = payload
            path = json.dumps(f'{WORK}/jon/{index:02}-{name}.qoa')
            if len(samples) <= INLINE:
                body += (f'    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, Unit>, Unit, J.Wave.write(J.Wave{{{len(samples) // channels}, {rate}, {size}, '
                         f'{channels}, [{", ".join(map(str, samples))}]}}, {path}), written)\n')
            else:
                body += (f'    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, J.Wave>, Unit, J.Wave.load("{WORK}/{index:02}-{name}.wav"), '
                         f'exported({path}))\n')
    return body + '    IO.print("\\"done\\"")\n'


def parse_lane(text, selected, lane):
    values = iter(text.splitlines())
    out = []
    for kind, payload in selected:
        if kind == 'load':
            out.append(json.loads(next(values)))
        else:
            index, (name, *_rest) = payload
            status = int(next(values))
            path = ROOT / f'{WORK}/jon/{index:02}-{name}.qoa'
            out.append([status, list(path.read_bytes()) if path.exists() else None])
            path.unlink(missing_ok=True)
    if json.loads(next(values)) != 'done':
        raise ValueError('qoa: candidate output did not finish')
    return out


def main():
    probe = probekit.Probe('qoa', probekit.arguments(__doc__), raylib_options=('SUPPORT_MODULE_RAUDIO=ON',))
    for folder in ('', '/native', '/jon', '/load'):
        (ROOT / (WORK + folder)).mkdir(parents=True, exist_ok=True)
    encodes = waves()
    for index, (name, channels, rate, samples, size) in enumerate(encodes):
        if len(samples) > INLINE:
            (ROOT / f'{WORK}/{index:02}-{name}.wav').write_bytes(riff16(channels, rate, samples))
        (ROOT / f'{WORK}/jon/{index:02}-{name}.qoa').unlink(missing_ok=True)
    lines = native_export(probe, encodes).splitlines()
    if len(lines) != 2 * len(encodes):
        raise ProbeFailure('qoa: incomplete native export output')
    exports = [[int(lines[2 * i]), json.loads(lines[2 * i + 1])] for i in range(len(encodes))]
    if sum(row[0] for row in exports) != 8 or sum(row[1] == [] for row in exports) != 4:
        raise ProbeFailure(f'qoa: unexpected native export outcomes {[row[0] for row in exports]}')
    encoded = {name: bytes(row[1]) for (name, *_rest), row in zip(encodes, exports) if row[0]}

    items = loads(encoded)
    for index, case in enumerate(items):
        case['path'] = f'{WORK}/load/{index:02}-{case["id"]}.{"QOA" if index % 5 == 4 else "qoa"}'
        (ROOT / case['path']).write_bytes(case['bytes'])
    rows = iter(json.loads(line) for line in native_load(probe, items).splitlines())
    expected = [next(rows) if case['kind'] == 'native' else EXPECTED[case['kind']] for case in items]
    for case, row in zip(items, expected):
        if case['id'] in encoded:
            name = case['id']
            channels, samples = next((c, s) for n, c, _r, s, _z in encodes if n == name)
            if row is None or row[0] != len(samples) // channels or row[3] != channels:
                raise ProbeFailure(f'qoa: native did not decode its own encoding of {name}')
    if sum(row is None for row in expected) < 6:
        raise ProbeFailure('qoa: unexpected native load outcomes')

    actions = [('export', (index, wave)) for index, wave in enumerate(encodes)] + [('load', case['path']) for case in items]
    lanes = probe.candidates(render, actions, batch=8, parse_lane=parse_lane)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare(exports + expected, lanes,
                  describe=lambda i: f'export {encodes[i][0]}' if i < len(encodes) else f'load {items[i - len(encodes)]["id"]}')
    probe.finish(exports=len(encodes), encoded=len(encoded), files=len(items),
                 decoded=sum(isinstance(r, list) and r[:1] != ['error'] for r in expected),
                 contracts=sum(case['kind'] != 'native' for case in items),
                 inputs_sha256=hashlib.sha256(json.dumps(encodes).encode() + b''.join(case['bytes'] for case in items)).hexdigest())


if __name__ == '__main__':
    main()
