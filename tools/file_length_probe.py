#!/usr/bin/env python3
"""Compare GetFileLength, including directories and sizes past INT_MAX.

fopen/ftell: a file that does not open is 0; a size that fits in a signed int
is that size; a larger size is 0 and a WARNING that names the path. On Linux a
directory that opens seeks to the maximum long, so it takes the warning path.
On macOS that ftell is the directory's size. An unreadable directory does not
open. The candidate takes the level as a Log.Logger. CPU-1, CPU-2 and JavaScript.
"""
import json
import os
import platform

import probekit
from probekit import ProbeFailure

INT_MAX = 2147483647


def c_string(text):
    return '"' + ''.join(c if 32 <= ord(c) < 127 and c not in '"\\' else f'\\{ord(c):03o}' for c in text) + '"'


def prepare(root):
    root.mkdir(parents=True, exist_ok=True)
    small = root / 'small'
    small.write_bytes(b'abcd')
    empty = root / 'empty'
    empty.write_bytes(b'')
    percent = root / 'a%b'
    percent.mkdir(exist_ok=True)
    blocked = root / 'blocked'
    blocked.mkdir(exist_ok=True)
    os.chmod(blocked, 0)
    exact = root / 'exact'
    over = root / 'over'
    huge = root / 'huge'
    for path, size in ((exact, INT_MAX), (over, INT_MAX + 1), (huge, 5 * 1024 * 1024 * 1024)):
        fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o644)
        os.ftruncate(fd, size)
        os.close(fd)
    opened = root / 'dir'
    opened.mkdir(exist_ok=True)
    return [
        (level, path)
        for level in (3, 7)
        for path in (
            str(root / 'missing'), str(empty), str(small), str(opened), str(blocked),
            str(percent), str(exact), str(over), str(huge),
        )
    ] + [(4, str(opened)), (4, str(over))]


def native(probe, rows):
    lines = ['#include "raylib.h"', '#include <stdio.h>', 'int main(void){']
    for level, path in rows:
        lines.append(f'SetTraceLogLevel({level});printf("%d\\n",(int)GetFileLength({c_string(path)}));')
    lines.append('return 0;}')
    return probe.native('\n'.join(lines) + '\n', 'file-length')


PROGRAM = '''import Base
import ../../jonlib.bend as J
def int.text(+value: U32) -> String:
  Bool.pick(String, (value >= 2147483648 : U32), "-" ++ U32.show((0 - value : U32)), U32.show(value))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(rows):
    def draw(selected, gpu):
        body = PROGRAM
        for level, path in rows:
            body += (f'    Unit <- IO.bind(U32, Unit, J.Files.length_with(J.Log.level({level}), {json.dumps(path)}), '
                     f'r => IO.print(int.text(r)))\n')
        return body + '    IO.pure(Unit, Unit{})\n'
    return draw


def main():
    probe = probekit.Probe('file-length', probekit.arguments(__doc__))
    root = probe.work / 'tree'
    try:
        rows = prepare(root)
        expected = native(probe, rows)
        lanes = probe.candidates(render(rows), ['all'], batch=1, parse=lambda text, selected: [text])
        lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
        probe.compare([expected], lanes, describe=lambda i: 'GetFileLength')
        if 'File size overflows expected limit' not in expected:
            raise ProbeFailure('file-length: the reference dropped the overflow warning')
        # Linux names the directory in that warning. macOS ftell fits, so the
        # warning names the huge file instead; the directory size is in the row.
        if platform.system() != 'Darwin' and 'a%b' not in expected:
            raise ProbeFailure('file-length: the reference dropped the directory overflow warning')
        if f'\n{INT_MAX}\n' not in f'\n{expected}':
            raise ProbeFailure('file-length: the reference did not return INT_MAX')
        probe.finish(cases=len(rows), reference_lines=expected.count('\n'))
    finally:
        blocked = root / 'blocked'
        if blocked.exists():
            os.chmod(blocked, 0o755)


if __name__ == '__main__':
    main()
