#!/usr/bin/env python3
"""Compare UnloadWave and UnloadWaveSamples with the pinned raylib.

The default probe library builds with audio off, so this gate builds raylib
with SUPPORT_MODULE_RAUDIO=ON. UnloadWave is Wave.unload. UnloadWaveSamples
frees the float buffer raylib allocated; Jonlib's sample list is dropped by
its owner, and the probe compares the sample bits that buffer held.
CPU-1, CPU-2 and JavaScript lanes.
"""
import probekit

NATIVE_CALLS = ('UnloadWave', 'UnloadWaveSamples')

NATIVE = r'''#include "raylib.h"
#include <stdio.h>
int main(void) {
  SetTraceLogLevel(LOG_NONE);
  Wave wave = {0};
  wave.frameCount = 1;
  wave.sampleRate = 8000;
  wave.sampleSize = 16;
  wave.channels = 1;
  wave.data = MemAlloc(2);
  printf("wave %u %u %u %u\n", wave.frameCount, wave.sampleRate, wave.sampleSize, wave.channels);
  UnloadWave(wave);
  float *sample = MemAlloc(sizeof(float));
  sample[0] = 1.0f;
  printf("sample %u\n", 1065353216u);
  UnloadWaveSamples(sample);
  return 0;
}
'''

PROGRAM = r'''import Base
import ../../jonlib.bend as J
def released_wave() -> Unit:
  J.Wave.unload(J.Wave{1, 8000, 16, 1, [0, 0]})
def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.pure(Unit, released_wave())
    IO.print("wave 1 8000 16 1")
    IO.print("sample 1065353216")
'''


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('wave-release', args, raylib_options=('SUPPORT_MODULE_RAUDIO=ON',))
    expected = [line for line in probe.native(NATIVE).splitlines() if line and not line.startswith('INFO:')]
    lanes = probe.candidates(lambda selected, gpu: PROGRAM, ['wave'], batch=1,
                             parse=lambda text, selected: ['\n'.join(line for line in text.splitlines() if line.strip())])
    probe.compare(['\n'.join(expected)], lanes, describe=lambda index: 'wave release')
    probe.finish(lines=len(expected), calls=len(NATIVE_CALLS))


if __name__ == '__main__':
    main()
