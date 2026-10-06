#!/usr/bin/env python3
"""Compile examples/math.bend (standalone Jonmath import) and require identical CPU and JS output."""
import probekit
from probekit import ROOT, ProbeFailure


def main(argv=None):
    probe = probekit.Probe('example', probekit.arguments(__doc__, argv=argv, raylib=False))
    binary, script = probe.work / 'math', probe.work / 'math.js'
    probekit.run(['bun', probe.args.bend_source / 'bend2/main.ts', ROOT / 'examples/math.bend', '-o', binary, '-o', script],
                 timeout=probekit.COMPILE_TIMEOUT)
    outputs = {'cpu-1': probekit.run([binary, '--gpu', 'off', '--threads', '1']),
               'cpu-2': probekit.run([binary, '--gpu', 'off', '--threads', '2']),
               'javascript': probekit.run(['bun', script])}
    if not outputs['cpu-1'].strip() or len(set(outputs.values())) != 1:
        raise ProbeFailure(f'examples/math.bend output differs or is empty across lanes: {outputs}')
    probe.report['lanes'] = {lane: dict(passed=True) for lane in outputs}
    probe.finish(lines=len(outputs['cpu-1'].splitlines()))


if __name__ == '__main__':
    main()
