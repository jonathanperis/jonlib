#!/bin/sh
# Exhaustive model check on this host: the model against the host's tanf on
# every binary32 argument, and again with the FMA/AVX2 variants disabled
# (GLIBC_TUNABLES; glibc 2.39 has a single scalar tanf, so both must agree).
# Usage: run_exhaustive.sh <work directory>; prints one JSON object per run.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$1
mkdir -p "$work"
cc -std=gnu11 -O2 -ffp-contract=off -DMODEL_TANF=model_tanf -c "$here/model.c" -o "$work/model.o"
cc -std=gnu11 -O2 -ffp-contract=off "$here/exhaustive.c" "$work/model.o" -lm -o "$work/exhaustive"
for variant in default sse2; do
  if [ $variant = default ]; then tunables=; else tunables=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4; fi
  for part in 0 1 2 3; do
    GLIBC_TUNABLES=$tunables "$work/exhaustive" $(printf '%x %x' $((part << 30)) $(((part + 1) << 30))) > "$work/part-$variant-$part" 2> "$work/first-$variant-$part" &
  done
  wait
  cat "$work"/part-$variant-* | awk -v variant=$variant -v glibc="$(ldd --version | head -1)" \
    '{c+=$1; d+=$2} END {printf "{\"variant\": \"%s\", \"arguments\": %d, \"tanf_differences\": %d, \"glibc\": \"%s\"}\n", variant, c, d, glibc}'
done
