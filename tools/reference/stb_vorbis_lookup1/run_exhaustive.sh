#!/bin/sh
# The exhaustive check on this host, with the C library's FMA variants of
# log, exp and pow and with them disabled (GLIBC_TUNABLES). Usage:
# run_exhaustive.sh <raylib source> <work directory>; prints one JSON object
# per variant.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
raylib=$1
work=$2
mkdir -p "$work"
cc -std=gnu11 -O2 -ffp-contract=off -w -I"$raylib/src" "$here/exhaustive.c" -lm -o "$work/exhaustive"
for variant in fma sse2; do
  if [ $variant = fma ]; then tunables=; else tunables=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4; fi
  for part in 0 1 2 3; do
    first=$((part << 22)); [ $part = 0 ] && first=1
    GLIBC_TUNABLES=$tunables "$work/exhaustive" $first $(((part + 1) << 22)) > "$work/part-$variant-$part" &
  done
  wait
  cat "$work"/part-$variant-* | awk -v variant=$variant -v tunables="$tunables" -v glibc="$(ldd --version | head -1)" \
    '{a+=$1; b+=$2; c+=$3; d+=$4; e+=$5; f+=$6; g+=$7; h+=$8; i+=$9; j+=$10} END {printf "{\"variant\": \"%s\", \"glibc_tunables\": \"%s\", \"pairs\": %d, \"sure\": %d, \"sure_differences\": %d, \"unsure\": %d, \"unsure_root\": %d, \"unsure_minus_one\": %d, \"unsure_other\": %d, \"undefined\": %d, \"undefined_root\": %d, \"undefined_root_plus_one\": %d, \"glibc\": \"%s\"}\n", variant, tunables, a, b, c, d, e, f, g, h, i, j, glibc}'
done
