#!/usr/bin/env python3
"""Compare M.Float64.from_decimal with strtod.

M.Float64.from_decimal gives the binary64 value of a decimal number in JSON's
grammar, as the C library's strtod and atof do (correctly rounded, ties to
even), and M.Float64.to_f32 of it is (float)strtod(...), which is how cgltf
reads a glTF file's numbers. The expected words come from Python's float(),
which is correctly rounded too; the host's strtod and atof must give the same
words for every case. Cases: integers, the numbers of the glTF models the
examples load, powers of ten on both sides, exact halves between two doubles
(up and down to the even neighbour) and their one-digit neighbours, 17-digit
round-trip forms of doubles from a fixed generator, 19-digit numbers, the
edges of the domain, and the refused forms (more than 19 significant digits,
a decimal exponent beyond 60, a long exponent field, and texts outside the
grammar). CPU-1, CPU-2 and JavaScript lanes.
"""
import json
import re
import struct

import probekit
from probekit import ProbeFailure

GRAMMAR = re.compile(r'-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?')

NATIVE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const char *texts[] = {TEXTS};
int main(void) {
  for (unsigned i = 0; i < sizeof texts / sizeof texts[0]; i++) {
    double a = strtod(texts[i], NULL), b = atof(texts[i]);
    float f = (float)a;
    unsigned long long wa, wb; unsigned wf;
    memcpy(&wa, &a, 8); memcpy(&wb, &b, 8); memcpy(&wf, &f, 4);
    printf("%llu %llu %u\n", wa, wb, wf);
  }
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonmath.bend as M
def narrow(value: Maybe<F32>) -> List<U32>:
  match value:
    case None{}: [0, 0]
    case Some{v}: [1, F32.bits(v)]
def show(value: Maybe<M.Float64>) -> List<U32>:
  match value:
    case None{}: [0, 0, 0, 0, 0]
    case Some{+v}:
      M.Float64{+high, +low} = v
      Con{1, Con{high, Con{low, narrow(M.Float64.to_f32(v))}}}
def all(texts: List<+List<U32>>) -> List<U32>:
  match texts:
    case Nil{}: Nil{}
    case Con{+t, rest}: List.append(&1, U32, show(M.Float64.from_decimal(t)), all(rest))
def main() -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, all([TEXTS])))
'''


def significant(text):
    """The significant digits of a number of the grammar: from the first nonzero digit on."""
    digits = re.sub(r'[eE].*', '', text).replace('-', '').replace('.', '')
    return len(digits.lstrip('0'))


def power(text):
    """The decimal exponent once the fraction digits are counted."""
    match = GRAMMAR.fullmatch(text)
    return int((match[3] or 'e0')[1:]) - len((match[2] or '.')[1:])


def inside(text):
    """Whether M.Float64.from_decimal answers the text."""
    match = GRAMMAR.fullmatch(text)
    return bool(match) and significant(text) <= 19 and abs(power(text)) <= 60 and len((match[3] or 'e0')[1:].lstrip('+-')) <= 3


def words(text):
    """(high, low) of strtod(text), which Python's float() equals."""
    bits = struct.unpack('<Q', struct.pack('<d', float(text)))[0]
    return bits >> 32, bits & 0xFFFFFFFF


def narrowed(text):
    """[1, word] of (float)strtod(text); [0, 0] where Float64.to_f32 is None (never for a finite value)."""
    try:
        return [1, struct.unpack('<I', struct.pack('<f', float(text)))[0]]
    except OverflowError:
        return [1, 0x7F800000 | (0x80000000 if text.startswith('-') else 0)]


def expected(text):
    if not inside(text):
        return [0, 0, 0, 0, 0]
    high, low = words(text)
    return [1, high, low, *narrowed(text)]


def halves():
    """Decimals exactly halfway between two doubles, and one digit to each side."""
    out = []
    for mantissa, exponent in ((2 ** 52 + 1, -53), (2 ** 52 + 2, -53), (2 ** 53 - 1, -54), (2 ** 52 + 5, -55), (2 ** 52 + 12345, -60), (2 ** 53 - 3, -58)):
        # (2*mantissa + 1)*2^(exponent - 1) has a finite decimal expansion: 5^k digits.
        k = 1 - exponent
        digits = str((2 * mantissa + 1) * 5 ** k)
        text = '0.' + digits.rjust(k, '0') if len(digits) <= k else digits[:-k] + '.' + digits[-k:]
        text = text.rstrip('0')
        if significant(text) <= 19:
            out += [text, text[:-1] + str(int(text[-1]) - 1), text + '1']
    out += ['9007199254740993', '9007199254740995', '9007199254740992', '9007199254740994', '18014398509481985', '4503599627370496.5', '4503599627370497.5',
            '4503599627370496.25', '4503599627370496.75', '4503599627370496.50000', '2251799813685248.25', '2251799813685248.75', '1125899906842624.125']
    return out


def cases():
    out = ['0', '-0', '0.0', '-0.000', '0e5', '1', '-1', '2', '10', '255', '65535', '4294967295', '4294967296', '18446744073709551615', '9999999999999999999',
           '0.5', '0.25', '0.1', '-0.1', '0.2', '0.3', '1.5', '-2.5', '3.14159265358979323', '2.718281828459045', '1e0', '1E0', '1e1', '1e+1', '1e-1', '1.0e2', '-1.25e-3',
           '0.02540000155568123', '-0.12091026455163956', '0.800000011920929', '0.6399999856948853', '0.7071067690849304', '-0.7071068286895752', '1.0000001192092896',
           '5e-324', '1e22', '1e23', '8.5e22', '1e60', '1e-60', '123456789012345678e42', '1.2345678901234567e-43', '0.000001', '1000000', '1e15', '1e16', '123456.789e3',
           '9.999999999999999e22', '2.2250738585072014e-30', '1.7976931348623157e30', '4.35e-10', '6.02214076e23', '6.62607015e-34', '299792458', '0.30000000000000004',
           '16777217', '16777216', '16777219', '33554433', '0.1e1', '0.10', '100e-2', '7e-45', '3.4028235e38', '3.4028236e38', '1e39', '1.401298464324817e-45', '1e-46']
    out += halves()
    for k in range(0, 61, 4):
        out += [f'1e{k}', f'1e-{k}', f'37e{max(k - 1, 0)}', f'9.5e-{k}']
    state = 20240911
    for index in range(60):
        state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        value = struct.unpack('<d', struct.pack('<Q', (state & 0x800FFFFFFFFFFFFF) | ((1023 - 60 + (state >> 52) % 120) << 52)))[0]
        text = repr(value)
        if GRAMMAR.fullmatch(text):
            out.append(text)
        out.append(('%d' % (state % 10 ** 19)) + ('e-%d' % (index % 40) if index % 3 else ''))
        out.append('0.' + '%019d' % (state >> 3 & (10 ** 19 - 1) if False else state % 10 ** 19))
    # Refused: outside the domain or the grammar.
    out += ['12345678901234567890', '1.2345678901234567890', '1e61', '1e-61', '0.1e-60', '1e1000', '1e0001', '1e', '1e+', '.5', '5.', '+1', '01', '-', '', '1.e2', '0x10', 'nan',
            'inf', '1 ', ' 1', '1,5', '1e5.0', '--1', '1ee5', '00', '-01', '0.', '1e-']
    seen, unique = set(), []
    for text in out:
        if text not in seen:
            seen.add(text)
            unique.append(text)
    return unique


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('strtod', args)
    chosen = cases()
    want = [expected(text) for text in chosen]
    answered = [text for text in chosen if inside(text)]
    lines = probe.native(NATIVE.replace('TEXTS', ', '.join(json.dumps(text) for text in answered)), link_raylib=False).splitlines()
    if len(lines) != len(answered):
        raise ProbeFailure('strtod: incomplete native output')
    for text, line in zip(answered, lines):
        strtod, atof, narrow = (int(value) for value in line.split())
        high, low = words(text)
        if strtod != (high << 32 | low) or atof != strtod or narrow != narrowed(text)[1]:
            raise ProbeFailure(f'strtod: the host gives {strtod:#x}/{atof:#x}/{narrow:#x} for {text!r}, the model {high << 32 | low:#x}/{narrowed(text)[1]:#x}')

    def render(selected, gpu):
        return PROGRAM.replace('TEXTS', ', '.join('[' + ', '.join(str(byte) for byte in text.encode()) + ']' for text in selected))

    def parse(text, selected):
        values = [value for line in text.splitlines() if line.strip() for value in json.loads(line)]
        if len(values) != 5 * len(selected):
            raise ProbeFailure('strtod: wrong candidate output size')
        return [values[i:i + 5] for i in range(0, len(values), 5)]

    probe.compare(want, probe.candidates(render, chosen, batch=len(chosen), parse=parse), describe=lambda i: f'{chosen[i]!r}')
    probe.finish(cases=len(chosen), answered=len(answered), refused=len(chosen) - len(answered))


if __name__ == '__main__':
    main()
