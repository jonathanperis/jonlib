#!/bin/sh
# Exhaustive model check on this host, for every float x and the exponent of
# stb_truetype's cube root: FUSED=1 against the host's own pow, FUSED=0
# against it with the FMA/AVX2 variants disabled (GLIBC_TUNABLES), and the
# two models against each other. Usage: run_exhaustive.sh <work directory>;
# prints one JSON object per comparison (about three minutes each on four
# cores).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$1
mkdir -p "$work"
for fused in 1 0; do
  cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=$fused -DMODEL_POW=model_pow -c "$here/model.c" -o "$work/model$fused.o"
  cc -std=gnu11 -O2 -ffp-contract=off "$here/exhaustive.c" "$work/model$fused.o" -lm -o "$work/exhaustive$fused"
done
cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_POW=fused_pow -c "$here/model.c" -o "$work/fused.o"
cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=0 -DMODEL_POW=plain_pow -c "$here/model.c" -o "$work/plain.o"
cc -std=gnu11 -O2 "$here/variants.c" "$work/fused.o" "$work/plain.o" -lm -o "$work/variants"
glibc=$(ldd --version | head -1)
for what in fma sse2 variants; do
  for part in 0 1 2 3; do
    first=$(printf '0x%x' $((part << 30)))
    case $what in
      fma) "$work/exhaustive1" $first 0x40000000 > "$work/out-$what-$part" & ;;
      sse2) GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4 "$work/exhaustive0" $first 0x40000000 > "$work/out-$what-$part" & ;;
      variants) "$work/variants" $first 0x40000000 > "$work/out-$what-$part" & ;;
    esac
  done
  wait
  cat "$work"/out-$what-* | awk -v what=$what -v glibc="$glibc" \
    '{n+=$1; d+=$2; f+=$3; r+=$4} END {printf "{\"comparison\": \"%s\", \"floats\": %d, \"doubles_that_differ\": %d, \"narrowed_floats_that_differ\": %d, \"refused\": %d, \"glibc\": \"%s\"}\n", what, n, d, f, r, glibc}'
done
