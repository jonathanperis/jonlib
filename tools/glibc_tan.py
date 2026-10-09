"""glibc 2.39/2.41 x86_64 tan (the __tan_fma ifunc variant) as linkable reference objects.

tools/reference/glibc_tan/model.c (LGPL-2.1+, FUSED=1) with the pinned
glibc 2.39 branred.c equals the native glibc 2.39 x86_64 tan on CPUs with FMA
and AVX2 on every argument MatrixPerspective and BeginMode3D can pass
(exhaustive, docs/PERSPECTIVE.md). Probes link it as `tan` when they check the
Glibc239Libm/Glibc241Libm profiles on hosts whose libm is not glibc's. Before a
probe uses it, the compiled model must reproduce CONTROLS: arguments from the
exhaustive survey where the FMA and SSE2 variants differ and where glibc is not
correctly rounded, across the polynomial, table and all three range-reduction
regions.
"""
import probekit
from probekit import ROOT, ProbeFailure

GLIBC = ROOT / 'tools/reference/glibc239'
MODEL = ROOT / 'tools/reference/glibc_tan'
SYMBOL = 'glibc_tan_fma'

# (argument, native glibc 2.39 x86_64 tan) binary64 words.
CONTROLS = (
    (0x3f4f139f20000000, 0x3f4f139fbc50b505), (0x4022ba97e0000000, 0xbfaeee3bc2dca543),
    (0x40a124afa0000000, 0x4030ccff034f9c9b), (0x4120a6a9c0000000, 0xc031132a082de2fa),
    (0x41a0d611e0000000, 0xbfaa7cdf51a4c77a), (0x42301deda0000000, 0xc05115eb2c388a61),
    (0x42b0510700000000, 0xc03214a1759dfcef), (0x433097df60000000, 0xc03c43bad30cfedd),
    (0x43b17d0540000000, 0xc0416912f1577568), (0x44400a6840000000, 0x3fad49764e54050b),
    (0x44c0760fc0000000, 0x3faebdd7bf79a77c), (0x45402aa200000000, 0xc040c82428ac5e6a),
    (0x45c08f66e0000000, 0x403b5b213633f007), (0x46504aff00000000, 0xbfa519b1d9f019c1),
    (0x46d0452ea0000000, 0x3fae1ab9d4f69515), (0x47502721c0000000, 0xbfaebfe1681b2ba8),
    (0x3f491aae20000000, 0x3f491aae7266f97c), (0x3fd0013d40000000, 0x3fd058d795261ef0),
    (0x40500153c0000000, 0x4003eb3126c82f84), (0x40e0001480000000, 0xc00e42e211416c00),
    (0x4160018f60000000, 0xbfdea80fb08a0bb8), (0x41f0000620000000, 0xbfd25032afcb26bc),
    (0x4270003720000000, 0xc01d4a10c930a0be), (0x43000059c0000000, 0xbfe3149201fdfa39),
    (0x4380003c00000000, 0xbffcd294bdb53aa6), (0x4410001880000000, 0x4027a3a392d35bf6),
    (0x4490004da0000000, 0xbffc2fab3578e7ce), (0x4520000ba0000000, 0x4006727ed8e0e38c),
    (0x45a000b080000000, 0xc014503b4953d713), (0x4630003940000000, 0xbfdebf7e4822ac5a),
    (0x46b00066c0000000, 0x400c40568b90413e), (0x4740009780000000, 0x4026b3b81557b782),
)

CHECK = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
double SYMBOL(double);
static const uint64_t controls[][2] = {
CONTROLS
};
int main(void) {
  for (unsigned i = 0; i < sizeof controls / sizeof controls[0]; i++) {
    double x, y; uint64_t bits;
    memcpy(&x, &controls[i][0], 8);
    y = SYMBOL(x);
    memcpy(&bits, &y, 8);
    if (bits != controls[i][1]) { printf("control %u: %016llx\n", i, (unsigned long long) bits); return 1; }
  }
  printf("ok\n");
  return 0;
}
'''


def objects(probe):
    """Compile the model (contraction off, explicit fma) and the pinned branred.c; return the object paths."""
    branred, model = probe.work / 'glibc-branred.o', probe.work / 'glibc-tan-model.o'
    shims = ['-iquote', MODEL / 'quote', '-I', MODEL / 'shim', '-I', GLIBC]
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-frounding-math', '-fno-stack-protector',
                  '-fmath-errno', *shims, '-D__branred=glibc_pinned_branred', '-c', GLIBC / 'branred.c', '-o', branred])
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-iquote', MODEL / 'quote', '-iquote', GLIBC,
                  '-DFUSED=1', f'-DMODEL_TAN={SYMBOL}', '-DMODEL_BRANRED=glibc_pinned_branred',
                  '-c', MODEL / 'model.c', '-o', model])
    source, binary = probe.work / 'glibc-tan-check.c', probe.work / 'glibc-tan-check'
    table = ',\n'.join(f'  {{UINT64_C(0x{x:016x}), UINT64_C(0x{y:016x})}}' for x, y in CONTROLS)
    source.write_text(CHECK.replace('SYMBOL', SYMBOL).replace('CONTROLS', table))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', source, model, branred, '-lm', '-o', binary])
    if probekit.run([binary]).strip() != 'ok':
        raise ProbeFailure('glibc tan model failed its controls')
    return [model, branred]


NATIVE = r'''#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static double (*volatile host_tan)(double) = tan;
static const uint64_t controls[][2] = {
CONTROLS
};
int main(void) {
  unsigned equal = 0;
  for (unsigned i = 0; i < sizeof controls / sizeof controls[0]; i++) {
    double x, y; uint64_t bits;
    memcpy(&x, &controls[i][0], 8);
    y = host_tan(x);
    memcpy(&bits, &y, 8);
    equal += bits == controls[i][1];
  }
  printf("%u\n", equal);
  return 0;
}
'''


def host_is_model(probe):
    """Whether the host's tan reproduces every control (glibc 2.39/2.41 x86_64 on an FMA/AVX2 CPU)."""
    source, binary = probe.work / 'host-tan.c', probe.work / 'host-tan'
    table = ',\n'.join(f'  {{UINT64_C(0x{x:016x}), UINT64_C(0x{y:016x})}}' for x, y in CONTROLS)
    source.write_text(NATIVE.replace('CONTROLS', table))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, '-lm', '-o', binary])
    equal = int(probekit.run([binary]).strip())
    probe.report['host_tan_controls'] = f'{equal}/{len(CONTROLS)}'
    return equal == len(CONTROLS)
