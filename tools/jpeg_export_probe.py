#!/usr/bin/env python3
"""Quality-90 JPEG ExportImage bytes for stored and expanded sources.

Pinned raylib ExportImage is the oracle. Surface.to_jpeg covers the byte
formats, RGB565, R32 and R32G32B32. Surface.write_image covers .JPG and .JpEg.
CPU-1, CPU-2 and JavaScript are exact lanes. No GPU claim.
"""
import json
from pathlib import Path

import probekit
from probekit import ProbeFailure, bend_list, c_bytes


def ramp(count, channels):
    return [((index * 17 + 3) & 255) for index in range(count * channels)]


def fixtures():
    rows = [
        ('rgba-2x1', 2, 1, 7, [10, 20, 30, 255, 1, 2, 3, 4], False),
        ('rgba-3x1', 3, 1, 7, [10, 20, 30, 255, 1, 2, 3, 4, 9, 8, 7, 6], False),
        ('gray-5x1', 5, 1, 1, [0, 128, 255, 7, 8], False),
        ('ga-3x1', 3, 1, 2, [10, 20, 30, 40, 50, 60], False),
        ('rgb-5x1', 5, 1, 4, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], False),
        ('odd-17x3', 17, 3, 4, ramp(17 * 3, 3), False),
        ('one', 1, 1, 7, [255, 0, 128, 64], False),
        ('block-8x8', 8, 8, 4, ramp(64, 3), False),
        ('edge-16x9', 16, 9, 4, ramp(16 * 9, 3), False),
        ('rgb565', 2, 1, 3, [255, 255, 0, 0], False),
        ('r32', 1, 1, 8, [0, 0, 128, 63], False),
        ('rgb-float', 1, 1, 9, [0, 0, 128, 63, 0, 0, 0, 63, 0, 0, 0, 0], False),
        ('suffix-jpg', 2, 1, 7, [10, 20, 30, 255, 1, 2, 3, 4], True),
        ('suffix-jpeg', 5, 1, 1, [0, 128, 255, 7, 8], True),
    ]
    cases = []
    for name, width, height, fmt, data, suffix in rows:
        path = {'suffix-jpg': 'photo.JPG', 'suffix-jpeg': 'photo.JpEg'}.get(name, name + '.jpg')
        cases.append(dict(id=name, width=width, height=height, format=fmt, data=list(data),
                          path=path, file=suffix))
    if len(cases) != len({case['id'] for case in cases}):
        raise ProbeFailure('jpeg-export: duplicate case id')
    return cases


def c_source(cases, directory):
    lines = ['#include "raylib.h"', '#include <stdio.h>', 'int main(void){',
             'SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path = json.dumps(str(directory / case['path']))
        lines += [
            '{',
            f'unsigned char data[]={c_bytes(case["data"])};',
            'Image image={0};',
            'image.data=data;',
            f'image.width={case["width"]};image.height={case["height"]};image.mipmaps=1;image.format={case["format"]};',
            f'if(!ExportImage(image,{path}))return 2;',
            'int n=0;',
            f'unsigned char *file=LoadFileData({path},&n);',
            'if(!file||n<=0)return 3;',
            f'printf("{{\\"id\\":\\"{case["id"]}\\",\\"bytes\\":[");',
            'for(int i=0;i<n;i++)printf("%s%u",i?", ":"",file[i]);',
            'printf("]}\\n");',
            'UnloadFileData(file);',
            '}',
        ]
    return '\n'.join(lines + ['return 0;', '}']) + '\n'


BEND = '''import Base
import ../../jonlib.bend as J
def emit.bytes(id: String, bytes: +List<U32>) -> IO(Unit):
  IO.print("{\\"id\\":\\"" ++ id ++ "\\",\\"bytes\\":" ++ List.show(~&2, ~U32, ~U32.show, bytes) ++ "}")
def emit.jpeg(+id: String, result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "jpeg-export encode failed")
    case Done{bytes}: emit.bytes(id, bytes)
def payload(+id: String, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "jpeg-export file read failed")
    case Done{bytes}: emit.bytes(id, bytes)
def received(+id: String, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(id, status)
def opened(+id: String, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "jpeg-export file reopen failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, 65536), received(id))
def written(+id: String, +path: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(path, "r"), opened(id))
    case _: IO.die(Unit, 1, "jpeg-export write failed")
def emit.memory(+id: String, image: Maybe<J.Surface>) -> IO(Unit):
  match image:
    case None{}: IO.die(Unit, 1, "jpeg-export source rejected")
    case Some{surface}: emit.jpeg(id, J.Surface.to_jpeg(surface))
def emit.file(+id: String, +path: String, image: Maybe<J.Surface>) -> IO(Unit):
  match image:
    case None{}: IO.die(Unit, 1, "jpeg-export source rejected")
    case Some{surface}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_image(surface, path), written(id, path))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def bend_source(cases, directory):
    lines = [BEND]
    for case in cases:
        image = f'J.Surface.from_bytes({case["width"]}, {case["height"]}, {case["format"]}, {bend_list(case["data"])})'
        if case['file']:
            path = json.dumps(str(directory / case['path']))
            lines.append(f'    Unit <- emit.file({json.dumps(case["id"])}, {path}, {image})')
        else:
            lines.append(f'    Unit <- emit.memory({json.dumps(case["id"])}, {image})')
    lines.append('    IO.pure(Unit, Unit{})')
    return '\n'.join(lines) + '\n'


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('jpeg-export', args)
    cases = fixtures()
    expected = [json.loads(line) for line in probe.native(c_source(cases, probe.work)).splitlines() if line.strip()]
    if len(expected) != len(cases):
        raise ProbeFailure(f'jpeg-export: oracle produced {len(expected)} rows for {len(cases)} cases')
    lanes = probe.candidates(lambda selected, gpu: bend_source(selected, probe.work), cases,
                             batch=len(cases), timeout=600)
    probe.compare(expected, lanes, lambda index: cases[index]['id'])
    probe.finish(cases=len(cases))


if __name__ == '__main__':
    main()
