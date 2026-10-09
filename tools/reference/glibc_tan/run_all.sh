#!/bin/bash
cd /work/build
mkdir -p /work/results
for s in perspective begin3d; do
  /usr/bin/time -v ./tan_survey $s 4 1 > /work/results/$s-fma.json 2> /work/results/$s-fma.time
done
for s in perspective begin3d; do
  GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4 /usr/bin/time -v ./tan_survey $s 4 1 > /work/results/$s-sse2.json 2> /work/results/$s-sse2.time
done
echo done > /work/results/ALLDONE
