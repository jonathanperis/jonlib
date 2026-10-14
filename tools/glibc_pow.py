"""glibc 2.39 x86_64 pow (the __pow_fma ifunc variant) as a linkable reference object.

tools/reference/glibc_pow/model.c (Arm optimized-routines' pow, MIT
alternative; FUSED=1) equals the native glibc 2.39 x86_64 pow on CPUs with
FMA and AVX2 for every float x and the exponent of stb_truetype's cube
root, (double) (1.0f/3.0f) (docs/MATH.md: all 2^32 words, and the SSE2
model with those variants disabled). Probes link it as the binary64 `pow`
when they check that call on hosts whose libm is not glibc's. Before a
probe uses it, the compiled model must reproduce the controls: floats on
which the FMA and SSE2 variants' doubles differ, two in each of sixteen
ranges of the exponent, with the doubles of the Ubuntu 24.04 library (glibc
2.39-0ubuntu8.9) and the floats they narrow to.
"""
import probekit
from probekit import ROOT, ProbeFailure

MODEL = ROOT / 'tools/reference/glibc_pow'
POW = 'glibc_pow_fma'
# (double) (1.0f/3.0f)
THIRD = 0x3FD5555560000000

# (the float x's word, native glibc 2.39 x86_64 pow((double) x, (double) (1.0f/3.0f))'s binary64 word, the float it narrows to).
CONTROLS = (
    (0x008ff5fb, 0x3d50a39f3acb0d47, 0x2a851cfa), (0x00a46646, 0x3d51645acaf03ead, 0x2a8b22d6),
    (0x088894dc, 0x3da49979a19043b3, 0x2d24cbcd), (0x08924d28, 0x3da513b765283ec1, 0x2d289dbb),
    (0x108251f8, 0x3df98d0aa49b35af, 0x2fcc6855), (0x109241b5, 0x3dfa8d7c0f8fd609, 0x2fd46be0),
    (0x18ad6f04, 0x3e51b4764ea47425, 0x328da3b2), (0x18b95c24, 0x3e521a0f6b51ff25, 0x3290d07b),
    (0x2083cf9c, 0x3ea45b59c30ea7a7, 0x3522dace), (0x20864cf3, 0x3ea47bf4d56ae817, 0x3523dfa7),
    (0x28909a16, 0x3efa73c0ee2c4935, 0x37d39e07), (0x289e41ea, 0x3efb428a3528df0f, 0x37da1452),
    (0x309a70ea, 0x3f5108942ae40249, 0x3a8844a1), (0x30a770d2, 0x3f517fa4fdff3fa3, 0x3a8bfd28),
    (0x3889d570, 0x3fa4a98bdf0d51bd, 0x3d254c5f), (0x38936f34, 0x3fa5219cde4ecc5f, 0x3d290ce7),
    (0x409c27cd, 0x3ffb2381f28a05eb, 0x3fd91c10), (0x40b0cd86, 0x3ffc49215c5200d5, 0x3fe2490b),
    (0x48adbb58, 0x4051b70f9b20a2d9, 0x428db87d), (0x48c48a72, 0x4052756cee65aa6d, 0x4293ab67),
    (0x50aac7b2, 0x40a631464b44f185, 0x45318a32), (0x50ad3d67, 0x40a64c6bc695116f, 0x4532635e),
    (0x589e32a6, 0x40fb41aaf9afe16d, 0x47da0d58), (0x58aa49c1, 0x40fbef1412eee12b, 0x47df78a1),
    (0x60857b0c, 0x415039a5a837c7a5, 0x4a81cd2d), (0x60a14c76, 0x415148309b3b1397, 0x4a8a4185),
    (0x68dce674, 0x41a82e1e268d128f, 0x4d4170f1), (0x68f119af, 0x41a8e5537885f621, 0x4d472a9c),
    (0x709e8a6d, 0x41fb46b52c5c2a85, 0x4fda35a9), (0x70aedd64, 0x41fc2e947b6a15d3, 0x4fe174a4),
    (0x78a818be, 0x4251857daf77fc2b, 0x528c2bed), (0x78aa2397, 0x4251979588537365, 0x528cbcac),
)

CHECK = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
double MODEL_POW(double, double, int *);
static double (*volatile host_pow)(double, double) = pow;
static double model(double x, double y) { int refused; double value = MODEL_POW(x, y, &refused); return refused ? 0.0 : value; }
static const uint64_t controls[][2] = {
@CONTROLS@
};
static unsigned equal(double (*f)(double, double)) {
  unsigned n = 0;
  double third;
  uint64_t w = UINT64_C(0x3FD5555560000000);
  memcpy(&third, &w, 8);
  for (unsigned i = 0; i < sizeof controls / sizeof controls[0]; i++) {
    uint32_t word = (uint32_t) controls[i][0];
    float x; double y; uint64_t bits;
    memcpy(&x, &word, 4);
    y = f((double) x, third);
    memcpy(&bits, &y, 8);
    n += bits == controls[i][1];
  }
  return n;
}
int main(void) {
  printf("%u %u\n", equal(model), equal(host_pow));
  return 0;
}
'''


def check_source():
    rows = ',\n'.join('  {UINT64_C(0x%08x), UINT64_C(0x%016x)}' % (x, y) for x, y, _ in CONTROLS)
    return CHECK.replace('@CONTROLS@', rows).replace('MODEL_POW', POW)


def objects(probe):
    """Compile the model (contraction off, explicit fma) and return the object paths.

    probe.report['host_pow_controls'] records how many controls the host's own pow reproduces.
    """
    model = probe.work / 'glibc-pow-model.o'
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-DFUSED=1', f'-DMODEL_POW={POW}', '-c', MODEL / 'model.c', '-o', model])
    source, binary = probe.work / 'glibc-pow-check.c', probe.work / 'glibc-pow-check'
    source.write_text(check_source())
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, model, '-lm', '-o', binary])
    mine, host = (int(part) for part in probekit.run([binary]).split())
    if mine != len(CONTROLS):
        raise ProbeFailure(f'glibc pow model failed its controls ({mine}/{len(CONTROLS)})')
    probe.report['host_pow_controls'] = f'{host}/{len(CONTROLS)}'
    return [model]


def host_is_model(probe):
    """Whether the host's pow reproduced every control (glibc 2.39 x86_64 on an FMA/AVX2 CPU); call after objects()."""
    done, _, total = probe.report.get('host_pow_controls', '0/1').partition('/')
    return done == total
