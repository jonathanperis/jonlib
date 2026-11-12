#!/usr/bin/env python3
"""Compare GCC aarch64 builds of the fused probe references with clang's.

usage: gcc_arm64_check.py <jonlib tree> <raylib source>

A local diagnostic, not a gate: it needs Docker on an arm64 host and the image
`jonlib-gcc-arm64` (FROM --platform=linux/arm64 ubuntu:24.04, apt-get install
gcc libc6-dev). Run the fused probes first so their references exist.

For each contracted reference a probe wrote (.build/*/{reference-fused,
shape-fused,matrix-arith-fused}.c), build it natively with clang
-ffp-contract=off and =on, and in the arm64 Ubuntu 24.04 container with GCC
13 at -O1 and -O3 (GCC's default -ffp-contract=fast). Fresh quiet NaNs are
folded (their sign is unspecified, as in the probes). Prints, per reference,
how many rows each GCC build differs from each clang build.
"""
import json
import subprocess
import sys
from pathlib import Path

tree, raylib = Path(sys.argv[1]), Path(sys.argv[2])
out = Path('/tmp/gcc-arm64-check')
out.mkdir(exist_ok=True)


def fold(value):
    if isinstance(value, list):
        return [fold(item) for item in value]
    if isinstance(value, int) and (value & 0x7FFFFFFF) > 0x7F800000:
        return 0x7FC00000
    return value


def rows(text):
    return [fold(json.loads(line)) for line in text.splitlines() if line.strip()]


def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


sources = sorted(p for name in ('reference-fused.c', 'shape-fused.c', 'matrix-arith-fused.c')
                 for p in (tree / '.build').glob(f'*/{name}'))
report = {}
for source in sources:
    tag = source.parent.name + '-' + source.stem
    builds = {}
    for contract in ('off', 'on'):
        binary = out / f'{tag}-clang-{contract}'
        run(['clang', '-std=c11', '-O2', f'-ffp-contract={contract}', '-fno-builtin-atan2f',
             f'-I{raylib / "src"}', str(source), '-lm', '-o', str(binary)])
        builds[f'clang-{contract}'] = rows(run([str(binary)]))
    script = ('for o in O1 O3; do gcc -std=gnu99 -$o -I/rl /w/r.c -lm -o /tmp/r$o && '
              '/tmp/r$o > /out/' + tag + '-gcc-$o.txt; done')
    run(['docker', 'run', '--rm', '-v', f'{source}:/w/r.c:ro', '-v', f'{raylib / "src"}:/rl:ro',
         '-v', f'{out}:/out', 'jonlib-gcc-arm64', 'sh', '-c', script])
    for level in ('O1', 'O3'):
        builds[f'gcc-{level}'] = rows((out / f'{tag}-gcc-{level}.txt').read_text())
    result = {}
    for gcc in ('gcc-O1', 'gcc-O3'):
        for clang in ('clang-off', 'clang-on'):
            result[f'{gcc} vs {clang}'] = sum(a != b for a, b in zip(builds[gcc], builds[clang]))
    result['rows'] = len(builds['clang-on'])
    report[tag] = result
    print(tag, result, flush=True)
(out / 'report.json').write_text(json.dumps(report, indent=1))
