"""glibc 2.39 x86_64 sin and cos (the __sin_fma and __cos_fma ifunc variants) as linkable reference objects.

tools/reference/glibc_sin/model.c (LGPL-2.1+, FUSED=1) with the pinned
glibc 2.39 sincostab.c and branred.c equals the native glibc 2.39 x86_64 sin
and cos on CPUs with FMA and AVX2 (docs/MATH.md: no difference on sixteen
million random arguments of every range for each function). Probes link it
as the binary64 `sin` and `cos` when they check the Glibc239Libm profile on
hosts whose libm is not glibc's. Before a probe uses it, the compiled model
must reproduce the controls: arguments where the FMA and SSE2 variants
differ, across the table, the pi/2 - x range and both range reductions, with
the results of the Ubuntu 24.04 library (libm.so.6, build ID
d53fcbff9f855463606b25cfbe2a2e10856ea3a7).
"""
import probekit
from probekit import ROOT, ProbeFailure

GLIBC = ROOT / 'tools/reference/glibc239'
MODEL = ROOT / 'tools/reference/glibc_sin'
QUOTE = ROOT / 'tools/reference/glibc_tan/quote'
SHIM = ROOT / 'tools/reference/glibc_tan/shim'
SIN = 'glibc_sin_fma'
COS = 'glibc_cos_fma'

# (argument, native glibc 2.39 x86_64 result) binary64 words.
SIN_CONTROLS = (
    (0xbfc15142547c554e, 0xbfc143bf3fc9d9dd), (0x3fc46bcfd6fce2bd, 0x3fc455a9abd1d2db),
    (0x3fd75b475afed245, 0x3fd6d76f1bdff323), (0x3ffc85f0027664db, 0x3fef48c3b814a184),
    (0x3ff361411d6ffd59, 0x3fedf4283c2e76d0), (0x3ffe8f834ebe0323, 0x3fee2d1e14f8fda6),
    (0xc128722bf25c8f57, 0xbfdc96478fc5a58f), (0x40c95c3133b1fa2f, 0xbfc72962de6c9ef5),
    (0xc03f96888f5f74c3, 0xbfc5eb67a41948e7), (0xc22b87d30ce9389c, 0xbfe52c34dd7f84a7),
    (0x41c13a38891261e4, 0xbfc59e9dec46a3b4), (0x4dca997eb6dc8c20, 0x3fc9117fefbe22a9),
    (0x78b4a64befb9b4bd, 0xbfde2dc2b0209a1c), (0xd54b3e895451a1c7, 0xbfe68d3fd693e2bf),
    (0x6ccea2e78e20f688, 0x3fbbc1fd7416e636),
)
COS_CONTROLS = (
    (0x3f9d1434cdd2c4b8, 0x3feffcb278fcffc8), (0xbf9bba4233e4e5de, 0x3feffcff3a8b42ac),
    (0x3f88298b5ac6111e, 0x3fefff6e0c373645), (0xbfd634cde09ceccc, 0x3fee17cf23a3c639),
    (0x3fdd337dc61e4ffa, 0x3fecb9fbfce77e22), (0xbfca443b48aa1299, 0x3fef541f2ccd63d7),
    (0xbffcf285323fce3c, 0xbfce3a824c700b14), (0xbff410151fef2f40, 0x3fd3f12756d32593),
    (0xbff491ac9ab3f09a, 0x3fd2021ee96bf23a), (0x405578da39cdd824, 0xbfdefd8fce431ab2),
    (0x40fd8f2c96f27f20, 0xbfe2ad49d75b6244), (0xc0f89f800fd4e232, 0xbfbd99f01fc9647d),
    (0x422d46f3fe647c8e, 0xbfcfdb171c26ae9c), (0xcd42fb3080ec6ccb, 0x3fe7d7937b182194),
    (0xc756e5c211e3f2cc, 0x3fe8d275c9484d84), (0x564f24ce6091b62a, 0xbfe4685c8ee8d38f),
    (0x76f84d409984f45c, 0xbfc0718c9bcd5431), (0x5a984908dad33f32, 0x3fc39e038af16411),
)

CHECK = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
double MODEL_SIN(double);
double MODEL_COS(double);
static double (*volatile host_sin)(double) = sin;
static double (*volatile host_cos)(double) = cos;
static const uint64_t sines[][2] = {
@SINE_CONTROLS@
};
static const uint64_t cosines[][2] = {
@COSINE_CONTROLS@
};
static unsigned equal(double (*f)(double), const uint64_t (*controls)[2], unsigned count) {
  unsigned n = 0;
  for (unsigned i = 0; i < count; i++) {
    double x, y; uint64_t bits;
    memcpy(&x, &controls[i][0], 8);
    y = f(x);
    memcpy(&bits, &y, 8);
    n += bits == controls[i][1];
  }
  return n;
}
int main(void) {
  unsigned ns = sizeof sines / sizeof sines[0], nc = sizeof cosines / sizeof cosines[0];
  printf("%u %u\n", equal(MODEL_SIN, sines, ns) + equal(MODEL_COS, cosines, nc), equal(host_sin, sines, ns) + equal(host_cos, cosines, nc));
  return 0;
}
'''


def controls(pairs):
    return ',\n'.join('  {UINT64_C(0x%016x), UINT64_C(0x%016x)}' % pair for pair in pairs)


def check_source():
    return (CHECK.replace('@SINE_CONTROLS@', controls(SIN_CONTROLS)).replace('@COSINE_CONTROLS@', controls(COS_CONTROLS))
            .replace('MODEL_SIN', SIN).replace('MODEL_COS', COS))


def objects(probe):
    """Compile the model (contraction off, explicit fma), the pinned table and branred.c; return the object paths.

    probe.report['host_sin_controls'] records how many controls the host's own sin and cos reproduce.
    """
    branred, table, model = probe.work / 'glibc-sin-branred.o', probe.work / 'glibc-sin-table.o', probe.work / 'glibc-sin-model.o'
    shims = ['-iquote', QUOTE, '-I', QUOTE, '-I', SHIM, '-I', GLIBC]
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-frounding-math', '-fno-stack-protector',
                  '-fmath-errno', *shims, '-D__branred=glibc_sin_branred', '-c', GLIBC / 'branred.c', '-o', branred])
    probekit.run(['clang', '-std=gnu11', '-O2', *shims, '-D__sincostab=glibc_sin_table', '-c', GLIBC / 'sincostab.c', '-o', table])
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-iquote', QUOTE, '-iquote', GLIBC,
                  '-DFUSED=1', f'-DMODEL_SIN={SIN}', f'-DMODEL_COS={COS}', '-DMODEL_BRANRED=glibc_sin_branred',
                  '-DMODEL_TABLE=glibc_sin_table', '-c', MODEL / 'model.c', '-o', model])
    source, binary = probe.work / 'glibc-sin-check.c', probe.work / 'glibc-sin-check'
    source.write_text(check_source())
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, model, table, branred, '-lm', '-o', binary])
    mine, host = (int(part) for part in probekit.run([binary]).split())
    total = len(SIN_CONTROLS) + len(COS_CONTROLS)
    if mine != total:
        raise ProbeFailure(f'glibc sin/cos model failed its controls ({mine}/{total})')
    probe.report['host_sin_controls'] = f'{host}/{total}'
    return [model, table, branred]


def host_is_model(probe):
    """Whether the host's sin and cos reproduced every control (glibc 2.39 x86_64 on an FMA/AVX2 CPU); call after objects()."""
    done, _, total = probe.report.get('host_sin_controls', '0/1').partition('/')
    return done == total
