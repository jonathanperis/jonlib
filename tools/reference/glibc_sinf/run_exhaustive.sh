#!/bin/sh
# Exhaustive model check on this host: FUSED=1 against the host's own
# functions, FUSED=0 against them with the FMA/AVX2 variants disabled
# (GLIBC_TUNABLES). Usage: run_exhaustive.sh <work directory>; prints one
# JSON object per variant.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$1
mkdir -p "$work"
for fused in 1 0; do
  cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=$fused -DMODEL_SINF=model_sinf -DMODEL_COSF=model_cosf \
    -c "$here/model.c" -o "$work/model$fused.o"
  cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=$fused "$here/exhaustive.c" "$work/model$fused.o" -lm -o "$work/exhaustive$fused"
  if [ $fused = 1 ]; then tunables=; else tunables=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4; fi
  for part in 0 1 2 3; do
    GLIBC_TUNABLES=$tunables "$work/exhaustive$fused" $(printf '%x %x' $((part << 30)) $(((part + 1) << 30))) > "$work/part$fused-$part" &
  done
  wait
  cat "$work"/part$fused-* | awk -v fused=$fused -v glibc="$(ldd --version | head -1)" \
    '{s+=$1; c+=$2; b+=$3; d+=$4} END {printf "{\"fused\": %d, \"arguments\": 4294967296, \"sinf_differences\": %d, \"cosf_differences\": %d, \"sincosf_differences\": %d, \"domain_violations\": %d, \"glibc\": \"%s\"}\n", fused, s, c, b, d, glibc}'
done
