#!/usr/bin/env python3
"""One-level KTX ExportImage bytes against pinned rl_save_ktx.

Pinned raylib ExportImage is the oracle. Surface.to_ktx covers memory bytes
and Surface.write_image covers .KTX and .KtX. CPU-1, CPU-2 and JavaScript are
exact lanes. No GPU claim.

rl_save_ktx copies a 4-byte level size past the buffer it allocates, then
fwrite writes only the allocated length. Freeing that buffer can fault. The
oracle asks malloc, calloc and realloc for 64 extra bytes so the copy stays
inside the allocation; the file length is still raylib's. The compared bytes
are that file, not the overrun.
"""
import json

import probekit
from probekit import ProbeFailure, bend_list, c_bytes


def fixtures():
    rows = [
        ('gray-1', 1, 1, 1, [0x11], False),
        ('gray-2', 2, 1, 1, [0x11, 0x22], False),
        ('gray-3', 3, 1, 1, [0x11, 0x22, 0x33], False),
        ('gray-4', 4, 1, 1, [0x11, 0x22, 0x33, 0x44], False),
        ('gray-5', 5, 1, 1, [0x11, 0x22, 0x33, 0x44, 0x55], False),
        ('ga-2', 2, 1, 2, [10, 20, 30, 40], False),
        ('565-2', 2, 1, 3, [0xFF, 0xFF, 0x00, 0x00], False),
        ('rgb-2', 2, 1, 4, [1, 2, 3, 4, 5, 6], False),
        ('5551-1', 1, 1, 5, [0x12, 0x34], False),
        ('4444-1', 1, 1, 6, [0x12, 0x34], False),
        ('rgba-2', 2, 1, 7, [10, 20, 30, 255, 1, 2, 3, 4], False),
        ('r32-2', 2, 1, 8, [0, 0, 128, 63, 0, 0, 0, 63], False),
        ('rgb-float', 1, 1, 9, [0, 0, 128, 63, 0, 0, 0, 63, 0, 0, 0, 0], False),
        ('suffix-ktx', 1, 1, 1, [9], True),
        ('suffix-mixed', 5, 1, 1, [0x11, 0x22, 0x33, 0x44, 0x55], True),
    ]
    cases = []
    for name, width, height, fmt, data, suffix in rows:
        path = {'suffix-ktx': 'photo.KTX', 'suffix-mixed': 'photo.KtX'}.get(name, name + '.ktx')
        cases.append(dict(id=name, width=width, height=height, format=fmt, data=list(data),
                          path=path, file=suffix))
    if len(cases) != len({case['id'] for case in cases}):
        raise ProbeFailure('ktx-export: duplicate case id')
    return cases


def c_source(cases, directory):
    lines = [
        '#include "raylib.h"',
        '#include <stdio.h>',
        '#include <stdlib.h>',
        '#include <string.h>',
        'void *__real_malloc(size_t);',
        'void *__real_realloc(void *, size_t);',
        'void *__wrap_malloc(size_t n) { return __real_malloc(n + 64); }',
        'void *__wrap_calloc(size_t n, size_t s) {',
        '  size_t bytes = n * s + 64;',
        '  void *p = __real_malloc(bytes);',
        '  if (p) memset(p, 0, bytes);',
        '  return p;',
        '}',
        'void *__wrap_realloc(void *p, size_t n) { return __real_realloc(p, n + 64); }',
        'int main(void){',
        'SetTraceLogLevel(LOG_NONE);',
    ]
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
def emit.ktx(+id: String, result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "ktx-export encode failed")
    case Done{bytes}: emit.bytes(id, bytes)
def payload(+id: String, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "ktx-export file read failed")
    case Done{bytes}: emit.bytes(id, bytes)
def received(+id: String, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(id, status)
def opened(+id: String, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "ktx-export file reopen failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, 65536), received(id))
def written(+id: String, +path: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(path, "r"), opened(id))
    case _: IO.die(Unit, 1, "ktx-export write failed")
def emit.memory(+id: String, image: Maybe<J.Surface>) -> IO(Unit):
  match image:
    case None{}: IO.die(Unit, 1, "ktx-export source rejected")
    case Some{surface}: emit.ktx(id, J.Surface.to_ktx(surface))
def emit.file(+id: String, +path: String, image: Maybe<J.Surface>) -> IO(Unit):
  match image:
    case None{}: IO.die(Unit, 1, "ktx-export source rejected")
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
    probe = probekit.Probe('ktx-export', args)
    cases = fixtures()
    expected = [json.loads(line) for line in probe.native(
        c_source(cases, probe.work),
        extra_flags=['-Wl,--wrap=malloc', '-Wl,--wrap=calloc', '-Wl,--wrap=realloc']).splitlines() if line.strip()]
    if len(expected) != len(cases):
        raise ProbeFailure(f'ktx-export: oracle produced {len(expected)} rows for {len(cases)} cases')
    lanes = probe.candidates(lambda selected, gpu: bend_source(selected, probe.work), cases,
                             batch=len(cases), timeout=600)
    probe.compare(expected, lanes, lambda index: cases[index]['id'])
    probe.finish(cases=len(cases))


if __name__ == '__main__':
    main()
