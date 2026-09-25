#!/usr/bin/env python3
"""Measure serial-tree and balanced-tree generation with identical pixel work."""
import argparse
import json
import statistics
import time
from pathlib import Path

from conformance import BUILD, ROOT, checkout, run, source_gate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--raylib-source', type=Path, required=True)
    parser.add_argument('--gpu', action='store_true')
    args = parser.parse_args()
    pins = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,pins['bend']['revision'],pins['bend'].get('patch'))
    checkout(args.raylib_source,pins['raylib']['revision'])
    work = BUILD/'gradient-bench'
    work.mkdir(exist_ok=True)
    report_path = work/'results.json'
    report_path.write_text(json.dumps(dict(passed=False))+'\n')
    c = work/'reference.c'
    c.write_text('''#include "raylib.h"
#include <stdio.h>
int main(void) {
  SetTraceLogLevel(LOG_NONE);
  Image image=GenImageGradientRadial(512,512,0.2f,GetColor(0x0d2f6503u),GetColor(0xf1c797fdu));
  unsigned int sum=0;
  for(int y=0;y<512;y++)for(int x=0;x<512;x++)sum+=(unsigned int)ColorToInt(GetImageColor(image,x,y));
  printf("%u\\n",sum); UnloadImage(image); return 0;
}
''')
    reference = work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),c,BUILD/'raylib/raylib/libraylib.a','-lm','-o',reference])
    expected = int(run([reference]).strip())
    programs = {}
    for mode in ('serial','parallel', *(['gpu'] if args.gpu else [])):
        source = work/f'{mode}.bend'
        generate = 'G.serial(18n, 0, 512, 262144, paint)' if mode=='serial' else 'G.generate(18n, 512, 262144, paint)'
        source.write_text('''import Base
import ../../src/gradients.bend as G
def checksum(pixels: Array<U32>) -> U32:
  match pixels:
    case ALeaf{value}: value
    case ANode{left, right}: (checksum(left) + checksum(right) : U32)
def image() -> Array<U32>:
  paint = {G.Radial{256.0,256.0,256.0,0.2,221209859,4056389629} : G.Paint}
  GENERATE
def main() -> IO(Unit):
  IO.print(U32.show(checksum(imageBANG())))
'''.replace('GENERATE',generate).replace('BANG','!' if mode=='gpu' else ''))
        binary=work/mode
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary])
        programs[mode]=binary
    lanes = {'serial-1':[programs['serial'],'--threads','1'],
             'parallel-1':[programs['parallel'],'--threads','1'],
             'parallel-2':[programs['parallel'],'--threads','2']}
    if args.gpu:
        lanes['metal']=[programs['gpu'],'--gpu','on']
    for command in lanes.values():
        if int(run(command).strip()) != expected:
            raise ValueError('Benchmark checksum differs from actual raylib')
    timings={name:[] for name in lanes}
    for _ in range(5):
        for name,command in lanes.items():
            started=time.perf_counter()
            actual=int(run(command).strip())
            timings[name].append(time.perf_counter()-started)
            if actual != expected:
                raise ValueError(f'{name}: checksum changed during timing')
    report=dict(passed=True,source_sha256=source_gate(),dimensions=[512,512],checksum=expected,
                timing_scope='Warm full-process elapsed seconds; includes allocation, checksum, runtime startup and device setup.',
                lanes={name:dict(samples_seconds=values,median_seconds=statistics.median(values)) for name,values in timings.items()})
    report_path.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report['lanes'],indent=2))


if __name__ == '__main__':
    main()
