#!/usr/bin/env python3
"""Native-only math profile diagnosis; completion is not a Jonlib parity pass."""
import hashlib
import json
from pathlib import Path
import platform
import struct

import probekit
from angle_probe import GNU_CONTROL, samples


CASES = {
    'vector2-angle-profiles', 'vector2-extrema', 'vector3-extrema',
    'vector4-extrema', 'vector2-clamp-components', 'vector3-clamp-components',
}
NATIVE_FLAGS = ['-fno-builtin-atan2f', '-fno-builtin-fminf', '-fno-builtin-fmaxf']
ZERO_PAIRS = [(0., 0.), (0., -0.), (-0., 0.), (-0., -0.), (1., -1.), (-1., 1.)]
DIMENSIONS = {'vector_value':2, 'vector3_value':3, 'vector4_value':4}
HEADER = r'''/* Diagnostic only. GNU_CONTROL below retains its Sun permission notice. */
#define _GNU_SOURCE
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <float.h>
#include <fenv.h>
#ifdef __GLIBC__
#include <gnu/libc-version.h>
#endif
#if defined(__linux__) || defined(__APPLE__)
#include <dlfcn.h>
#endif
#pragma STDC FP_CONTRACT OFF
#define RAYMATH_STATIC_INLINE
#include "raymath.h"
_Static_assert(sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24,
               "This diagnostic requires IEEE binary32 float");
'''
HELPERS = r'''
static float (*volatile native_min)(float,float)=fminf;
static float (*volatile native_max)(float,float)=fmaxf;
static float (*volatile native_atan2)(float,float)=atan2f;
static float (*volatile sun_atan2)(float,float)=gnu_atan2;
/* C models of jonmath.bend's documented finite zero-tie contracts.
 * These are diagnostics, not executions of the Bend implementation. */
static float profile_min(int gnu, float x,float y) {
  if(x==0 && y==0) {
    if(gnu)return x;
    unsigned b=(word(x)|word(y))&0x80000000u;
    float r;memcpy(&r,&b,4);return r;
  }
  return x<y?x:y;
}
static float profile_max(int gnu, float x,float y) {
  if(x==0 && y==0) {
    if(gnu)return x;
    unsigned b=(word(x)&word(y))&0x80000000u;
    float r;memcpy(&r,&b,4);return r;
  }
  return x>y?x:y;
}
static void scalar(const char *kind,const char *name,float x) {
  printf("%s\t%s\t%08x\n",kind,name,word(x));
}
static void vector(const char *kind,const char *name,const float *v,unsigned n) {
  printf("%s\t%s",kind,name);
  for(unsigned i=0;i<n;i++)printf("\t%08x",word(v[i]));
  puts("");
}
int main(void) {
#ifdef __GLIBC__
  printf("host\tglibc\t%s\n",gnu_get_libc_version());
#endif
  printf("host\trounding_mode\t%s\n",fegetround()==FE_TONEAREST?"FE_TONEAREST":"other");
#if defined(__linux__) || defined(__APPLE__)
  Dl_info info;
  if(dladdr((void *)native_atan2,&info))printf("host\tatan2_library\t%s\n",info.dli_fname);
  if(dladdr((void *)native_min,&info))printf("host\tfmin_library\t%s\n",info.dli_fname);
  if(dladdr((void *)native_max,&info))printf("host\tfmax_library\t%s\n",info.dli_fname);
#endif
'''
ENDPOINTS = [
    ('near-half-neg', 1., -1e-20), ('near-half-pos', 1., 1e-20),
    ('pi-poszero', 0., -1.), ('pi-negzero', -0., -1.),
    ('huge-ratio-neg', 1., -2**-70), ('near-half-neg-y', -1., -1e-20),
]


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def literal(value):
    return f32(value).hex()+'f'


def bits(value):
    return f'{struct.unpack("<I", struct.pack("<f", value))[0]:08x}'


def profile_expression(profile, function, left, right):
    if profile == 'native':
        return f'native_{function}({left},{right})'
    return f'profile_{function}({int(profile == "gnu")},{left},{right})'


def generate_source(values, cases):
    lines = [HEADER, GNU_CONTROL, HELPERS]
    for x, y in ZERO_PAIRS:
        label = bits(x)+','+bits(y)
        lines.append(f'{{volatile float x={literal(x)},y={literal(y)};')
        for operation in ('min', 'max'):
            modes = [
                ('literal', f'f{operation}f({literal(x)},{literal(y)})'),
                ('volatile', f'f{operation}f(x,y)'),
                ('native', f'native_{operation}(x,y)'),
                ('gnu', f'profile_{operation}(1,x,y)'),
                ('accurate', f'profile_{operation}(0,x,y)'),
            ]
            for mode, expression in modes:
                lines.append(f'scalar("{operation}.{mode}","{label}",{expression});')
        lines.append('}')
    for label, y, x in ENDPOINTS:
        lines.append(f'{{volatile float y={literal(y)},x={literal(x)};')
        modes = [
            ('literal', f'atan2f({literal(y)},{literal(x)})'),
            ('volatile', 'atan2f(y,x)'), ('native', 'native_atan2(y,x)'),
            ('sun-literal', f'gnu_atan2({literal(y)},{literal(x)})'),
            ('sun-runtime', 'sun_atan2(y,x)'),
        ]
        for mode, expression in modes:
            lines.append(f'scalar("atan2.{mode}","{label}",{expression});')
        lines.append('}')
    lines.append(r'''{volatile float half=1.5707963705f,low=-8.7422776573e-08f,pi=3.1415927410f;
      float z=half+0.5f*low;
      scalar("sun-steps","half",half);scalar("sun-steps","low",low);
      scalar("sun-steps","z",z);scalar("sun-steps","z-low",z-low);
      scalar("sun-steps","pi-(z-low)",pi-(z-low));}''')
    for case in cases:
        for operation in case['operations']:
            args = operation['args']
            dimension = DIMENSIONS[operation['op']]
            function = operation['function']
            label = f'{case["id"]}@{operation["x"]}.{function}'
            for mode in ('literal', 'volatile'):
                lines.append('{')
                if mode == 'volatile':
                    lines.append('volatile float a[]={'+','.join(map(literal,args))+'};')
                groups = []
                for start in range(0, len(args), dimension):
                    cells = [literal(args[i]) if mode == 'literal' else f'a[{i}]'
                             for i in range(start, start+dimension)]
                    groups.append(f'(Vector{dimension}){{'+','.join(cells)+'}')
                expression = f'Vector{dimension}{function.capitalize()}('+','.join(groups)+')'
                if function == 'angle':
                    lines.append(f'scalar("raymath.{mode}","{label}",{expression});')
                else:
                    lines.append(f'Vector{dimension} v={expression};')
                    lines.append('float out[]={'+','.join('v.'+s for s in 'xyzw'[:dimension])+'};')
                    lines.append(f'vector("raymath.{mode}","{label}",out,{dimension});')
                lines.append('}')
            if function == 'angle':
                continue
            for profile in ('gnu', 'accurate', 'native'):
                expressions = []
                for i in range(dimension):
                    if function == 'clamp':
                        inner = profile_expression(profile, 'max', literal(args[dimension+i]), literal(args[i]))
                        value = profile_expression(profile, 'min', literal(args[2*dimension+i]), inner)
                    else:
                        value = profile_expression(profile, function, literal(args[i]), literal(args[dimension+i]))
                    expressions.append(value)
                lines.append('{float out[]={'+','.join(expressions)+'};'+
                             f'vector("profile.{profile}","{label}",out,{dimension});'+'}')
    lines.append('static const float samples[][2]={'+','.join(
        '{'+','.join(map(literal,pair))+'}' for pair in values)+'};')
    lines.append(r'''for(unsigned i=0;i<sizeof(samples)/sizeof(samples[0]);i++) {
      volatile float y=samples[i][0],x=samples[i][1];
      printf("sample\t%u\t%08x\t%08x\t%08x\t%08x\t%08x\n",i,word(y),word(x),
             word(native_atan2(y,x)),word(sun_atan2(y,x)),word(atan2f(y,x)));
    }
    return 0;}
''')
    return '\n'.join(lines)


def observation_schema(cases):
    """Expected (kind, label) -> component count; independent of observed output."""
    expected = {}

    def add(kind, label, components=1):
        key = (kind, label)
        if key in expected:
            raise ValueError(f'Duplicate expected diagnostic observation: {key}')
        expected[key] = components

    for x, y in ZERO_PAIRS:
        for operation in ('min', 'max'):
            for mode in ('literal', 'volatile', 'native', 'gnu', 'accurate'):
                add(f'{operation}.{mode}', bits(x)+','+bits(y))
    for label, _, _ in ENDPOINTS:
        for mode in ('literal', 'volatile', 'native', 'sun-literal', 'sun-runtime'):
            add(f'atan2.{mode}', label)
    for label in ('half', 'low', 'z', 'z-low', 'pi-(z-low)'):
        add('sun-steps', label)
    for case in cases:
        for operation in case['operations']:
            function = operation['function']
            dimension = DIMENSIONS[operation['op']]
            if function not in ('angle', 'min', 'max', 'clamp'):
                raise ValueError(f'Unsupported diagnostic operation: {function}')
            label = f'{case["id"]}@{operation["x"]}.{function}'
            components = 1 if function == 'angle' else dimension
            for mode in ('literal', 'volatile'):
                add(f'raymath.{mode}', label, components)
            if function != 'angle':
                for profile in ('gnu', 'accurate', 'native'):
                    add(f'profile.{profile}', label, components)
    return expected


def validate_host(hosts, expected_host):
    required = {'rounding_mode'}
    if expected_host['system'] in ('Linux', 'Darwin'):
        required.update(('atan2_library', 'fmin_library', 'fmax_library'))
    if expected_host['libc'][0] == 'glibc':
        required.add('glibc')
    if set(hosts) != required:
        raise ValueError(f'Unexpected/missing host fields: expected {sorted(required)}, got {sorted(hosts)}')
    if hosts['rounding_mode'] != 'FE_TONEAREST':
        raise ValueError('Diagnostic requires FE_TONEAREST rounding mode')
    if 'glibc' in required and hosts['glibc'] != expected_host['libc'][1]:
        raise ValueError('Runtime glibc version differs from recorded host identity')
    for key in required - {'rounding_mode', 'glibc'}:
        if not Path(hosts[key]).is_absolute():
            raise ValueError(f'Native library path must be absolute: {key}')


def parse_output(output, values, cases, expected_host=None):
    if expected_host is None:
        expected_host = dict(system=platform.system(), libc=platform.libc_ver())
    expected = observation_schema(cases)
    rows = [line.split('\t') for line in output.splitlines()]
    hosts, observations, sample_rows, seen = {}, [], [], set()
    for row in rows:
        if row[0] == 'host' and len(row) == 3:
            if row[1] in hosts:
                raise ValueError(f'Duplicate host field: {row[1]}')
            if not row[2] or row[2] != row[2].strip():
                raise ValueError(f'Empty or padded host field: {row[1]}')
            hosts[row[1]] = row[2]
        elif row[0] == 'sample' and len(row) == 7:
            sample_rows.append(row)
        elif len(row) >= 2 and tuple(row[:2]) in expected:
            key = tuple(row[:2])
            if key in seen:
                raise ValueError(f'Duplicate diagnostic observation: {key}')
            if len(row) != expected[key]+2:
                raise ValueError(f'Wrong observation component count: {key}')
            seen.add(key)
            for word in row[2:]:
                if len(word) != 8 or any(c not in '0123456789abcdef' for c in word):
                    raise ValueError(f'Invalid result bits: {row}')
            observations.append(dict(kind=row[0], label=row[1], bits=row[2:]))
        else:
            raise ValueError(f'Unexpected diagnostic output: {row}')
    validate_host(hosts, expected_host)
    if seen != set(expected):
        raise ValueError(f'Incomplete observations: {sorted(set(expected)-seen)}')
    # Validate completeness, index ordering and exact input bits before counting differences.
    if len(sample_rows) != len(values):
        raise ValueError(f'Incomplete samples: {len(sample_rows)} of {len(values)}')
    native_sun, native_direct = [], []
    for i, row in enumerate(sample_rows):
        if row[1:4] != [str(i), bits(values[i][0]), bits(values[i][1])]:
            raise ValueError(f'Unexpected sample order/input: {row}')
        for word in row[4:]:
            if len(word) != 8 or any(c not in '0123456789abcdef' for c in word):
                raise ValueError(f'Invalid sample result bits: {row}')
        result = dict(index=i, y=row[2], x=row[3], native=row[4], sun_control=row[5], direct_volatile=row[6])
        if row[4] != row[5]:
            native_sun.append(result)
        if row[4] != row[6]:
            native_direct.append(result)
    return dict(host=hosts, observations=observations, samples_observed=len(sample_rows),
                sun_control_vs_native_mismatch_count=len(native_sun),
                sun_control_vs_native_differences=native_sun,
                direct_volatile_vs_native_mismatch_count=len(native_direct),
                direct_volatile_vs_native_differences=native_direct)


def main():
    def configure(parser):
        parser.add_argument('--clang', default='clang', help='Existing Clang executable (four modes)')
        parser.add_argument('--gcc', help='Optional existing GCC executable (two additional modes)')
    args = probekit.arguments(__doc__, configure, bend=False)
    probe = probekit.Probe('native-math-profile', args)
    values = samples()
    fixtures = json.loads((probekit.ROOT/'tests/fixtures/images.json').read_text())['cases']
    cases = [case for case in fixtures if case['id'] in CASES]
    if {case['id'] for case in cases} != CASES:
        raise probekit.ProbeFailure('Missing one or more diagnostic fixture scenarios')
    source = probe.work/'diagnostic.c'
    source.write_text(generate_source(values, cases))
    modes = [('clang-o0',args.clang,['-O0']), ('clang-o2',args.clang,['-O2']),
             ('clang-o2-native',args.clang,['-O2',*NATIVE_FLAGS]),
             ('clang-o2-strict',args.clang,['-O2','-ffp-model=strict'])]
    if args.gcc:
        modes += [('gcc-o2',args.gcc,['-O2']), ('gcc-o2-native',args.gcc,['-O2',*NATIVE_FLAGS])]
    host = dict(system=platform.system(), machine=platform.machine(), libc=platform.libc_ver())
    variants = {}
    for name, compiler, flags in modes:
        flags = ['-std=c11', *flags, '-ffp-contract=off']
        probekit.run([compiler, *flags, '-I', args.raylib_source/'src', source, '-lm',
                      *(['-ldl'] if platform.system() == 'Linux' else []), '-o', probe.work/name])
        variants[name] = dict(flags=flags, compiler_version=probekit.run([compiler, '--version']).strip(),
                              **parse_output(probekit.run([probe.work/name]), values, cases, host))
        print(f'{name}: {variants[name]["sun_control_vs_native_mismatch_count"]}/{len(values)} '
              'native/Sun differences (diagnostic only)', flush=True)
    probe.report.update(host=host, variants=variants, fixture_scenarios=[case['id'] for case in cases],
                        generated_source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    probe.diagnostic(samples=len(values), inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),
                     modes='/'.join(variants),
                     sun_native_differences=sorted({v['sun_control_vs_native_mismatch_count'] for v in variants.values()}))


if __name__ == '__main__':
    main()
