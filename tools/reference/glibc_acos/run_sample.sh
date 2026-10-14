#!/bin/sh
# The model against this host's acos on seeded samples: FUSED=1 against the
# host's own acos, FUSED=0 against it with the FMA/AVX2 variants disabled
# (GLIBC_TUNABLES), and the two models against each other. Usage:
# run_sample.sh <work directory> <arguments per seed>; four seeds a mode,
# five modes (sample.c). Prints one JSON object per comparison and mode.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$1
count=$2
mkdir -p "$work"
for fused in 1 0; do
  cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=$fused -DMODEL_ACOS=model_acos -c "$here/model.c" -o "$work/model$fused.o"
  cc -std=gnu11 -O2 -ffp-contract=off "$here/sample.c" "$work/model$fused.o" -lm -o "$work/sample$fused"
done
cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=1 -DMODEL_ACOS=fused_acos -c "$here/model.c" -o "$work/fused.o"
cc -std=gnu11 -O2 -ffp-contract=off -mfma -DFUSED=0 -DMODEL_ACOS=plain_acos -c "$here/model.c" -o "$work/plain.o"
cc -std=gnu11 -O2 "$here/variants.c" "$work/fused.o" "$work/plain.o" -lm -o "$work/variants"
glibc=$(ldd --version | head -1)
for mode in 0 1 2 3 4; do
  for what in fma sse2 variants; do
    for seed in 1 2 3 4; do
      case $what in
        fma) "$work/sample1" "$count" $mode $seed > "$work/out-$what-$mode-$seed" & ;;
        sse2) GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA,-FMA4 "$work/sample0" "$count" $mode $seed > "$work/out-$what-$mode-$seed" & ;;
        variants) "$work/variants" "$count" $mode $seed > "$work/out-$what-$mode-$seed" & ;;
      esac
    done
    wait
    if [ $what = variants ]; then
      cat "$work"/out-$what-$mode-* | awk -v mode=$mode -v glibc="$glibc" \
        '{n+=$1; d+=$2; f+=$3} END {printf "{\"comparison\": \"variants\", \"mode\": %d, \"arguments\": %d, \"doubles\": %d, \"floats\": %d, \"glibc\": \"%s\"}\n", mode, n, d, f, glibc}'
    else
      cat "$work"/out-$what-$mode-* | awk -v what=$what -v mode=$mode -v glibc="$glibc" \
        '{n+=$1; d+=$2} END {printf "{\"comparison\": \"%s\", \"mode\": %d, \"arguments\": %d, \"differences\": %d, \"glibc\": \"%s\"}\n", what, mode, n, d, glibc}'
    fi
  done
done
