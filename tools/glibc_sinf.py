"""glibc 2.39/2.41 x86_64 sinf/cosf (the __sinf_fma/__cosf_fma ifunc variants) as a linkable reference object.

tools/reference/glibc_sinf/model.c (Arm optimized-routines, MIT alternative)
with FUSED=1 equals the native glibc 2.39 and 2.41 x86_64 sinf, cosf and
sincosf on CPUs with FMA and AVX2 on every binary32 argument (exhaustive,
docs/SINCOSF.md). Before a probe uses it, the compiled model must reproduce
CONTROLS: the arguments where the FMA and SSE2 variants differ (all 17
positive ones of tools/reference/glibc_sinf/variant_differences.txt).
"""
import probekit
from probekit import ROOT, ProbeFailure

MODEL = ROOT / 'tools/reference/glibc_sinf/model.c'
SINF, COSF = 'glibc_sinf_fma', 'glibc_cosf_fma'

# (argument, native glibc 2.39 x86_64 sinf, cosf) binary32 words.
CONTROLS = (
    (0x418a3adb, 0xbf800000, 0xb7b4f770), (0x418a3adc, 0xbf800000, 0xb7a4f770),
    (0x418a3add, 0xbf800000, 0xb794f770), (0x418a3ade, 0xbf800000, 0xb784f770),
    (0x41bc76d9, 0xbf7fff80, 0xbb803f6b), (0x4202eb4b, 0x3f779884, 0x3e821ce2),
    (0x4255b0a9, 0xbc7d08a9, 0xbf7ff82f), (0x42687a55, 0x3f800000, 0xb552257c),
    (0x4280ce28, 0x3f800000, 0x34fdd672), (0x42870e40, 0xbf7ff72d, 0xbc866cc4),
    (0x42a35c07, 0xbadaa3b4, 0x3f7fffe9), (0x42a35d44, 0x3a44b889, 0x3f7ffffb),
    (0x42a97360, 0x3dc7b08a, 0xbf7ec7ba), (0x42c55faa, 0xbf767f39, 0xbe8a34d1),
    (0x42cf5854, 0x382ee64e, 0xbf800000), (0x42d8d23e, 0x3f7fea63, 0xbcd25ea8),
    (0x42e87a55, 0xb5d2257c, 0xbf800000),
)

CHECK = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
float SINF(float), COSF(float);
static float (*volatile sine)(float) = SINF, (*volatile cosine)(float) = COSF;
static const uint32_t controls[][3] = {
CONTROLS
};
int main(void) {
  unsigned equal = 0;
  for (unsigned i = 0; i < sizeof controls / sizeof controls[0]; i++) {
    float x, s, c; uint32_t a, b;
    memcpy(&x, &controls[i][0], 4);
    s = sine(x); c = cosine(x);
    memcpy(&a, &s, 4); memcpy(&b, &c, 4);
    equal += a == controls[i][1] && b == controls[i][2];
  }
  printf("%u\n", equal);
  return 0;
}
'''


def table():
    return ',\n'.join(f'  {{0x{x:08x}u, 0x{s:08x}u, 0x{c:08x}u}}' for x, s, c in CONTROLS)


def equal_controls(probe, name, symbols, objects):
    source, binary = probe.work / f'{name}.c', probe.work / name
    source.write_text(CHECK.replace('SINF', symbols[0]).replace('COSF', symbols[1]).replace('CONTROLS', table()))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin', source, *objects, '-lm', '-o', binary])
    return int(probekit.run([binary]).strip())


def objects(probe):
    """Compile the model (contraction off, explicit fma) and check its controls; return the object paths."""
    model = probe.work / 'glibc-sinf-model.o'
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-DFUSED=1', f'-DMODEL_SINF={SINF}',
                  f'-DMODEL_COSF={COSF}', '-c', MODEL, '-o', model])
    if equal_controls(probe, 'glibc-sinf-check', (SINF, COSF), [model]) != len(CONTROLS):
        raise ProbeFailure('glibc sinf/cosf model failed its controls')
    return [model]


def host_is_model(probe):
    """Whether the host's sinf/cosf reproduce every control (glibc 2.39/2.41 x86_64 on an FMA/AVX2 CPU)."""
    equal = equal_controls(probe, 'host-sinf', ('sinf', 'cosf'), [])
    probe.report['host_sinf_controls'] = f'{equal}/{len(CONTROLS)}'
    return equal == len(CONTROLS)
