#!/usr/bin/env python3
"""Compare TraceLog output and MemAlloc/MemRealloc with Jonlib's Log and Memory.

Native programs set a threshold with SetTraceLogLevel and call TraceLog with
'%'-free texts (Jonlib prints preformatted text literally); the candidate prints
the same messages through Log.trace with a Log.Logger. The complete standard
output is compared, including prefixes, threshold filtering, unknown types and
the 244-character truncation. LOG_FATAL runs in its own program on each side
and must print its line and exit with status 1. CPU/JS lanes.
"""
import json
import subprocess

import probekit
from probekit import ROOT, ProbeFailure

TEXTS = ['hello', '', 'x' * 300, 'spaces  and\ttabs', 'end.']
CASES = [(level, kind, text) for level in (0, 3, 5, 7) for kind in range(0, 9) if kind != 6 for text in TEXTS[:2]]
CASES += [(3, 3, TEXTS[2]), (3, 4, TEXTS[3]), (1, 1, TEXTS[4])]


def c_string(text):
    return '"' + ''.join(c if 32 <= ord(c) < 127 and c not in '"\\?' else f'\\{ord(c):03o}' for c in text) + '"'


def bend_string(text):
    return json.dumps(text)


def native_log(probe):
    lines = ['#include "raylib.h"', 'int main(void){']
    for level, kind, text in CASES:
        lines.append(f'SetTraceLogLevel({level});TraceLog({kind},{c_string(text)});')
    return probe.native('\n'.join(lines + ['return 0;}']) + '\n', 'log-reference')


def render_log(selected, gpu):
    body = 'import Base\nimport ../../jonlib.bend as J\ndef main() -> IO(Unit):\n  do IO<Unit>:\n'
    for level, kind, text in CASES:
        body += f'    J.Log.trace(J.Log.level({level}), {kind}, {bend_string(text)})\n'
    body += '    IO.print("")\n'
    return body


def main():
    probe = probekit.Probe('log', probekit.arguments(__doc__))
    expected = native_log(probe)
    lanes = probe.candidates(render_log, ['all messages'], batch=1, parse=lambda text, selected: [text.rstrip('\n') + '\n'])
    probe.compare([expected.rstrip('\n') + '\n'], {k: v for k, v in lanes.items() if k != 'gpu'}, describe=lambda i: 'trace log output')
    # LOG_FATAL: native prints and exits 1; the candidate must do the same.
    fatal_c = probe.work / 'fatal.c'
    fatal_c.write_text('#include "raylib.h"\nint main(void){TraceLog(LOG_FATAL,"stop here");TraceLog(LOG_INFO,"unreached");return 0;}\n')
    source_dir = probe.args.raylib_source / 'src'
    subprocess.run(['clang', '-std=c11', '-O2', fatal_c, '-I' + str(source_dir), probe.library, '-lm', '-o', probe.work / 'fatal'], check=True,
                   capture_output=True)
    native = subprocess.run([probe.work / 'fatal'], capture_output=True, text=True)
    fatal_bend = probe.work / 'fatal.bend'
    fatal_bend.write_text('import Base\nimport ../../jonlib.bend as J\ndef main() -> IO(Unit):\n  do IO<Unit>:\n'
                          '    J.Log.trace(J.Log.default(), 6, "stop here")\n    J.Log.trace(J.Log.default(), 3, "unreached")\n')
    subprocess.run(['bun', probe.args.bend_source / 'bend2/main.ts', fatal_bend, '-o', probe.work / 'fatal.js'], check=True, capture_output=True)
    candidate = subprocess.run(['bun', probe.work / 'fatal.js'], capture_output=True, text=True)
    if (native.returncode, native.stdout) != (1, 'FATAL: stop here\n') or candidate.returncode != 1 or not candidate.stdout.startswith('FATAL: stop here\n') \
            or 'unreached' in candidate.stdout:
        raise ProbeFailure(f'log: LOG_FATAL differs: native={native.returncode} {native.stdout!r} '
                           f'jonlib={candidate.returncode} {candidate.stdout!r}')
    probe.finish(messages=len(CASES), fatal_exit=1, reference_lines=expected.count('\n'))


if __name__ == '__main__':
    main()
