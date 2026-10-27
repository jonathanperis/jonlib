#!/usr/bin/env python3
"""Compare ChangeDirectory's trace lines with Files.change_directory_with.

The reference prints INFO "SYSTEM: Working Directory: " plus the path when
chdir succeeds, and WARNING "SYSTEM: Failed to change to directory: " plus
the path when it fails, unless the level hides that kind. %s copies the path,
so a '%' is literal and a path longer than Log.message's 244 characters is
printed whole. The candidate takes the level as a Log.Logger. CPU-1, CPU-2
and JavaScript.
"""
import json

import probekit
from probekit import ProbeFailure


def c_string(text):
    return '"' + ''.join(c if 32 <= ord(c) < 127 and c not in '"\\' else f'\\{ord(c):03o}' for c in text) + '"'


def cases(root):
    ok = root / 'here'
    percent = root / 'a%b'
    ok.mkdir(parents=True, exist_ok=True)
    percent.mkdir(exist_ok=True)
    long_path = root / ('p' * 240)
    return [
        (level, path)
        for level in (3, 4, 7)
        for path in (str(ok), str(percent), str(root / 'missing'), str(root / 'no%d'), '', str(long_path))
    ]


def native(probe, rows):
    lines = ['#include "raylib.h"', '#include <stdio.h>', 'int main(void){']
    for level, path in rows:
        lines.append(f'SetTraceLogLevel({level});printf("%d\\n",(int)ChangeDirectory({c_string(path)}));')
    lines.append('return 0;}')
    return probe.native('\n'.join(lines) + '\n', 'directory-log')


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
            body += (f'    Unit <- IO.bind(U32, Unit, J.Files.change_directory_with(J.Log.level({level}), {json.dumps(path)}), '
                     f'r => IO.print(int.text(r)))\n')
        return body + '    IO.pure(Unit, Unit{})\n'
    return draw


def main():
    probe = probekit.Probe('directory-log', probekit.arguments(__doc__))
    rows = cases(probe.work / 'dir')
    expected = native(probe, rows)
    lanes = probe.candidates(render(rows), ['all'], batch=1, parse=lambda text, selected: [text])
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare([expected], lanes, describe=lambda i: 'ChangeDirectory trace lines')
    if 'INFO: SYSTEM: Working Directory: ' not in expected or 'WARNING: SYSTEM: Failed to change to directory: ' not in expected:
        raise ProbeFailure('directory-log: the reference printed neither trace line')
    if 'a%b' not in expected or 'no%d' not in expected or 'p' * 240 not in expected:
        raise ProbeFailure('directory-log: the reference dropped a path')
    probe.finish(cases=len(rows), reference_lines=expected.count('\n'))


if __name__ == '__main__':
    main()
