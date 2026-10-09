#!/bin/bash
set -e
P=/repo/tools/reference/glibc239; G=/repo/tools/reference/glibc_tan; C=/repo/tools/reference/core_math
B=${1:-/work/build}; CC=${CC:-gcc}
mkdir -p $B; cd $B
GF="-std=gnu11 -fgnu89-inline -O2 -frounding-math -fmerge-all-constants -fno-stack-protector -fmath-errno -fPIC"
INC="-iquote $G/quote -I $G/shim -I $P"
$CC $GF $INC -mfma -mavx2 -D__tan=pinned_tan_fma -D__branred=pinned_branred -c $P/s_tan.c -o pinned_fma.o
$CC $GF $INC -D__tan=pinned_tan_sse2 -D__branred=pinned_branred -c $P/s_tan.c -o pinned_sse2.o
$CC $GF -ffp-contract=off $INC -D__branred=pinned_branred -c $P/branred.c -o pinned_branred.o
$CC -std=gnu11 -O2 -ffp-contract=off -iquote $G/quote -iquote $P -DFUSED=1 -DMODEL_TAN=model_tan_fma -DMODEL_BRANRED=pinned_branred -c $G/model.c -o model_fma.o
$CC -std=gnu11 -O2 -ffp-contract=off -iquote $G/quote -iquote $P -DFUSED=0 -DMODEL_TAN=model_tan_sse2 -DMODEL_BRANRED=pinned_branred -c $G/model.c -o model_sse2.o
$CC -std=gnu11 -O2 -ffp-contract=off -c $C/tan.c -o cr_tan.o
$CC -std=gnu11 -O2 -ffp-contract=off -DHAVE_PINNED=1 $G/tan_survey.c pinned_fma.o pinned_sse2.o pinned_branred.o model_fma.o model_sse2.o cr_tan.o -lm -lpthread -o tan_survey
echo built
