#!/usr/bin/env python3
"""Compare raylib's WAV loading and Wave utilities with Jonlib's Wave.

raylib is built with its audio module. Generated RIFF files cover PCM 8, 12
(in 16-bit containers), 16, 20, 24, 32 and 40-bit samples, 1/2/6 channels,
32-bit float (clamped and in range), a-law and mu-law, WAVE_FORMAT_EXTENSIBLE
headers, LIST/fact chunks with odd padding, short and extended "fmt " chunks,
data sizes past the end of the file or not a whole number of frames, empty
data and malformed headers. LoadWave on each file must give the same frame
count, sample rate, sample size, channels and every 16-bit sample, or fail on
both sides. Jonlib contracts (not native comparisons): RIFX, ADPCM and 64-bit
float data are UnsupportedWaveFormat; formats dr_wav reads no frames from and
NaN float samples, which leave raylib's samples uninitialized or undefined,
are InvalidWaveData. IsWaveValid, WaveCopy, WaveCrop, LoadWaveSamples and
ExportWave (.wav, .raw) on 8-, 16- and 32-bit waves are compared too. CPU/JS.
"""
import hashlib
import json
import math
import random
import struct

import probekit
from probekit import ROOT, ProbeFailure

WORK = '.build/wav-probe/cases'


def chunk(name, body, size=None):
    data = name + struct.pack('<I', len(body) if size is None else size) + body
    return data + (b'\0' if len(body) % 2 else b'')


def fmt(tag, channels, rate, bits, align=None, extra=b''):
    align = channels * bits // 8 if align is None else align
    return struct.pack('<HHIIHH', tag, channels, rate, rate * align, align, bits) + extra


def riff(*chunks, container=b'RIFF'):
    body = b'WAVE' + b''.join(chunks)
    return container + struct.pack('<I', len(body)) + body


def extensible(sub, valid, channels, rate, bits):
    guid = struct.pack('<H', sub) + bytes([0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71])
    return fmt(0xFFFE, channels, rate, bits, extra=struct.pack('<HHI', 22, valid, 3) + guid)


def cases():
    rng = random.Random(0x3A7)
    noise = lambda n: bytes(rng.randrange(256) for _ in range(n))
    out = []

    def add(name, data, kind='native'):
        out.append(dict(id=name, bytes=data, kind=kind))

    for bits, channels in ((8, 1), (8, 2), (16, 1), (16, 2), (24, 2), (32, 1), (40, 1), (16, 6)):
        frames = 7
        add(f'pcm{bits}-{channels}ch', riff(chunk(b'fmt ', fmt(1, channels, 22050, bits)), chunk(b'data', noise(frames * channels * bits // 8))))
    add('pcm12-in-16', riff(chunk(b'fmt ', fmt(1, 2, 8000, 12, align=4)), chunk(b'data', noise(20))))
    add('pcm20-in-24', riff(chunk(b'fmt ', fmt(1, 1, 8000, 20, align=3)), chunk(b'data', noise(15))))
    floats = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -2.0, 0.999999, -0.999999, 1e-7, -1e-7, 0.25, 3.0e38, -math.inf, math.inf,
              0.3333333, -0.7777777]
    add('float32', riff(chunk(b'fmt ', fmt(3, 2, 48000, 32)), chunk(b'data', struct.pack('<18f', *floats))))
    add('float32-random', riff(chunk(b'fmt ', fmt(3, 1, 44100, 32)), chunk(b'data', struct.pack('<64f', *[rng.uniform(-1.2, 1.2) for _ in range(64)]))))
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
    add('rifx', riff(chunk(b'fmt ', fmt(1, 1, 8000, 16)), chunk(b'data', noise(8)), container=b'RIFX'), 'unsupported')
    add('adpcm', riff(chunk(b'fmt ', fmt(2, 1, 8000, 4, align=256, extra=struct.pack('<H', 32) + noise(32))), chunk(b'data', noise(256))), 'unsupported')
    add('float64', riff(chunk(b'fmt ', fmt(3, 1, 8000, 64)), chunk(b'data', struct.pack('<2d', 0.5, -0.25))), 'unsupported')
    add('float32-nan', riff(chunk(b'fmt ', fmt(3, 1, 8000, 32)), chunk(b'data', struct.pack('<3f', 0.5, math.nan, 0.25))), 'data')
    add('mp3-tag', riff(chunk(b'fmt ', fmt(0x55, 1, 8000, 16)), chunk(b'data', noise(8))), 'data')
    return out


EXPECTED = {'unsupported': ['error', 'unsupported'], 'data': ['error', 'data']}

# Waves built in memory for the utilities: (size, channels, rate, samples).
WAVES = [(8, 1, 8000, [0, 1, 127, 128, 129, 200, 255]), (16, 2, 22050, [0, 1, 32767, 32768, 65535, 12345, 40000, 7]),
         (32, 1, 44100, [struct.unpack('<I', struct.pack('<f', v))[0] for v in (0.0, -0.5, 0.25, 1.75, -3.0)])]


def c_wave(size, channels, rate, samples):
    kind = {8: 'unsigned char', 16: 'unsigned short', 32: 'unsigned int'}[size]
    return f'(Wave){{{len(samples) // channels},{rate},{size},{channels},(void*)({kind}[]){{{",".join(map(str, samples))}}}}}'


def native(probe, items):
    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <string.h>',
             'static void wave(Wave w){if(!w.data||(!w.frameCount&&!w.sampleRate)){puts("null");return;}'
             'printf("[%u,%u,%u,%u,[",w.frameCount,w.sampleRate,w.sampleSize,w.channels);unsigned n=w.frameCount*w.channels;'
             'for(unsigned i=0;i<n;i++){unsigned v=w.sampleSize==8?((unsigned char*)w.data)[i]:w.sampleSize==16?((unsigned short*)w.data)[i]:((unsigned*)w.data)[i];'
             'printf("%s%u",i?",":"",v);}puts("]]");}',
             'static void file(const char *path){FILE *f=fopen(path,"rb");int c,i=0;printf("[");while((c=fgetc(f))!=EOF)printf("%s%d",i++?",":"",c);puts("]");fclose(f);}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in items:
        if case['kind'] == 'native':
            lines.append(f'{{Wave w=LoadWave("{case["path"]}");wave(w);UnloadWave(w);}}')
    for index, (size, channels, rate, samples) in enumerate(WAVES):
        w = c_wave(size, channels, rate, samples)
        lines.append(f'{{Wave w={w};printf("%d\\n",IsWaveValid(w));Wave c=WaveCopy(w);wave(c);UnloadWave(c);'
                     f'Wave k=WaveCopy(w);WaveCrop(&k,1,{len(samples) // channels - 1});wave(k);'
                     f'WaveCrop(&k,2,1);wave(k);UnloadWave(k);'
                     f'float *s=LoadWaveSamples(w);printf("[");for(unsigned i=0;i<w.frameCount*w.channels;i++){{unsigned b;memcpy(&b,s+i,4);printf("%s%u",i?",":"",b);}}puts("]");'
                     f'UnloadWaveSamples(s);ExportWave(w,"{WORK}/out{index}.wav");file("{WORK}/out{index}.wav");'
                     f'ExportWave(w,"{WORK}/out{index}.RAW");file("{WORK}/out{index}.RAW");}}')
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
def utilities(+w: J.Wave, +last: U32, +wav: String, +raw: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print(Bool.pick(String, J.Wave.is_valid(w), "1", "0"))
    Unit <- IO.print(wave(w))
    Unit <- IO.print(cropped(J.Wave.crop(w, 1, last)))
    Unit <- IO.print(cropped(J.Wave.crop(cropped.wave(J.Wave.crop(w, 1, last)), 2, 1)))
    Unit <- IO.print(samples(J.Wave.samples(w)))
    Unit <- IO.bind(Result<&1, &1, J.Wave.IOError, Unit>, Unit, J.Wave.write(w, wav), written)
    IO.bind(Result<&1, &1, J.Wave.IOError, Unit>, Unit, J.Wave.write(w, raw), written)
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
                     f'{len(samples) // channels - 1}, "{WORK}/jon{index}.wav", "{WORK}/jon{index}.RAW")\n')
    return body + '    IO.print("\\"done\\"")\n'


def main():
    probe = probekit.Probe('wav', probekit.arguments(__doc__), raylib_options=('SUPPORT_MODULE_RAUDIO=ON',))
    (ROOT / WORK).mkdir(parents=True, exist_ok=True)
    items = cases()
    for index, case in enumerate(items):
        case['path'] = f'{WORK}/{index:02}-{case["id"]}.wav'
        (ROOT / case['path']).write_bytes(case['bytes'])
    text = native(probe, items).splitlines()
    rows = iter(json.loads(line) for line in text)
    expected = [next(rows) if case['kind'] == 'native' else EXPECTED[case['kind']] for case in items]
    if sum(row is None for row in expected) < 6 or sum(isinstance(row, list) and row[:1] != ['error'] for row in expected) < 20:
        raise ProbeFailure('wav: unexpected native outcomes')
    utility_rows = []
    for _ in WAVES:
        valid, copy, crop, bad_crop, floats, wav, raw = (next(rows) for _ in range(7))
        utility_rows.append([valid, copy, crop, bad_crop, floats, wav, raw])
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
                for name in ('wav', 'RAW'):
                    status = next(values)
                    got.append(list((ROOT / f'{WORK}/jon{index}.{name}').read_bytes()) if status == 'written' else None)
                out.append(got)
        if next(values) != 'done':
            raise ValueError('wav: candidate output did not finish')
        return out
    expected += utility_rows
    lanes = probe.candidates(render, actions, batch=48, parse=parse)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: items[i]['id'] if i < len(items) else f'utilities {i - len(items)}')
    probe.finish(files=len(items), decoded=sum(isinstance(r, list) and r[:1] != ['error'] for r in expected[:len(items)]),
                 contracts=sum(case['kind'] != 'native' for case in items), utility_waves=len(WAVES),
                 inputs_sha256=hashlib.sha256(b''.join(case['bytes'] for case in items)).hexdigest())


if __name__ == '__main__':
    main()
