"""glibc 2.39 x86_64 acos (the __ieee754_acos_fma ifunc variant) as a linkable reference object.

tools/reference/glibc_acos/model.c (LGPL-2.1+, FUSED=1) equals the native
glibc 2.39 x86_64 acos on CPUs with FMA and AVX2 (docs/MATH.md: no
difference on five billion sampled arguments, nor for the SSE2 model with
those variants disabled). Probes link it as the binary64 `acos` when they
check the Glibc239Libm profile on hosts whose libm is not glibc's. Before a
probe uses it, the compiled model must reproduce the controls: arguments on
which the FMA and SSE2 variants differ, four in each interval of
e_asin.c's acos (two of each sign), with the results of the Ubuntu 24.04
library (glibc 2.39-0ubuntu8.9).
"""
import probekit
from probekit import ROOT, ProbeFailure

MODEL = ROOT / 'tools/reference/glibc_acos'
ACOS = 'glibc_acos_fma'

# (argument, native glibc 2.39 x86_64 result) binary64 words, by interval: below 1/8, 1/4, 1/2, 3/4, 0.921875, 0.953125, 0.96875 and 1.
CONTROLS = (
    (0x3fbf2ffb2bceace6, 0x3ff72dbd841f38af), (0x3fbdbb5dc5c3a330, 0x3ff74532042a60b5),
    (0xbfbb7e4874a20678, 0x3ffadab976f17646), (0xbfbf5fd63b5e16f9, 0x3ffb193c9d4f6191),
    (0x3fcbab8d7937bcaf, 0x3ff5a57e0425d9e4), (0x3fc870e0acc7b724, 0x3ff60f0a2be18d43),
    (0xbfc857f9c9afe11c, 0x3ffc31c0c029e2d7), (0xbfcd55d5b4121006, 0x3ffcd5211bb393f4),
    (0x3fd8847dfc00f892, 0x3ff2d7b2c8b39f6f), (0x3fdd3cf820c3e535, 0x3ff18aa5fb44bbe4),
    (0xbfd5fd22f1e4e3bf, 0x3ffebe8932ba43b8), (0xbfd936d2d042f1ad, 0x3fff9ca64de603db),
    (0x3fe618d28441cf8b, 0x3fe9dfd804869670), (0x3fe464347c324f62, 0x3fec2819962fbe2e),
    (0xbfe5657767c4a598, 0x40026ce40755044e), (0xbfe1f6f28b743c6f, 0x400155be43f3c27d),
    (0x3fe84630b59060cf, 0x3fe6b5ba27e026fc), (0x3fecbfd9a6d76465, 0x3fdd18d202a496a1),
    (0xbfed07b553d8a6ff, 0x4005a8a9a254da52), (0xbfea97c1239b7291, 0x400469f89b926880),
    (0x3fee02eb97af5334, 0x3fd6ae69ee5c2c69), (0x3fee1d284205bfcb, 0x3fd61543fd8395a1),
    (0xbfee74a415145a15, 0x4006a31e40a67228), (0xbfee20c4139c5364, 0x400661fee1ab203c),
    (0x3fee84b0fc8200d7, 0x3fd38d42177b69f6), (0x3feee21f5ed10f0f, 0x3fd0f51cd39fcfd3),
    (0xbfeefb94e30e82dd, 0x40071c345167c799), (0xbfeec6c2dd98e057, 0x4006e9cec43cc6c4),
    (0x3fef4438f2539678, 0x3fcb7581db75cada), (0x3fef20b8c021b85d, 0x3fcdf40b5d6b305c),
    (0xbfef01df5af93e34, 0x40072287973a2392), (0xbfef2716d4deec8e, 0x400749a49db89cde),
)

CHECK = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
double MODEL_ACOS(double);
static double (*volatile host_acos)(double) = acos;
static const uint64_t controls[][2] = {
@CONTROLS@
};
static unsigned equal(double (*f)(double)) {
  unsigned n = 0;
  for (unsigned i = 0; i < sizeof controls / sizeof controls[0]; i++) {
    double x, y; uint64_t bits;
    memcpy(&x, &controls[i][0], 8);
    y = f(x);
    memcpy(&bits, &y, 8);
    n += bits == controls[i][1];
  }
  return n;
}
int main(void) {
  printf("%u %u\n", equal(MODEL_ACOS), equal(host_acos));
  return 0;
}
'''


def check_source():
    rows = ',\n'.join('  {UINT64_C(0x%016x), UINT64_C(0x%016x)}' % pair for pair in CONTROLS)
    return CHECK.replace('@CONTROLS@', rows).replace('MODEL_ACOS', ACOS)


def objects(probe):
    """Compile the model (contraction off, explicit fma) and return the object paths.

    probe.report['host_acos_controls'] records how many controls the host's own acos reproduces.
    """
    model = probe.work / 'glibc-acos-model.o'
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-DFUSED=1', f'-DMODEL_ACOS={ACOS}', '-c', MODEL / 'model.c', '-o', model])
    source, binary = probe.work / 'glibc-acos-check.c', probe.work / 'glibc-acos-check'
    source.write_text(check_source())
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, model, '-lm', '-o', binary])
    mine, host = (int(part) for part in probekit.run([binary]).split())
    if mine != len(CONTROLS):
        raise ProbeFailure(f'glibc acos model failed its controls ({mine}/{len(CONTROLS)})')
    probe.report['host_acos_controls'] = f'{host}/{len(CONTROLS)}'
    return [model]


def host_is_model(probe):
    """Whether the host's acos reproduced every control (glibc 2.39 x86_64 on an FMA/AVX2 CPU); call after objects()."""
    done, _, total = probe.report.get('host_acos_controls', '0/1').partition('/')
    return done == total
