"""Shared probekit driver for the private binary64 emulation probes.

Each probe supplies a deterministic labelled corpus, an exact rational oracle
(binary64_*_oracle.py) producing one expected row per observation, a qualified
native C program and a Bend program. The driver:

1. derives every expected row from the rational oracle;
2. compiles and runs the native C program (strict FE_TONEAREST, no FTZ/DAZ,
   runtime preflight controls) over the natively expressible rows, checks its
   environment record and requires its rows to equal the rational oracle's;
3. runs the Bend candidate on CPU-1/CPU-2/JavaScript (and --gpu) and requires
   every lane to equal the rational oracle row for row.

Rows are flat lists of 32-bit words beginning with the observation id; the
candidate prints `line` rows per output line as one flattened list.
"""
from collections import Counter
import hashlib
import json

import probekit
from probekit import ProbeFailure

SIGN = 1 << 63
FRACTION = (1 << 52) - 1
# Control-register bits that must be clear: x86 MXCSR FTZ/DAZ/rounding, AArch64 FPCR FZ/FZ16/RMode/FIZ+AH.
FORBIDDEN = {'mxcsr': (1 << 15) | (1 << 6) | (3 << 13), 'fpcr': (1 << 24) | (1 << 19) | (3 << 22) | 3}
# Strict IEEE evaluation without contraction for every native reference program.
FLAGS = ('-frounding-math', '-fno-fast-math', '-ffp-contract=off', '-fno-lto')


def normal(exponent, fraction=0, sign=0):
    """Encode a normal binary64 value from its unbiased exponent, fraction and sign bit."""
    if (type(exponent) is not int or type(fraction) is not int or type(sign) is not int
            or not -1022 <= exponent <= 1023 or not 0 <= fraction <= FRACTION or sign not in (0, 1)):
        raise ValueError('Invalid normal binary64 parameters')
    return (sign << 63) | ((exponent + 1023) << 52) | fraction


def labelled():
    """Return (rows, add): add(key, row, label) keeps the first row per key and accumulates its labels."""
    rows, seen = [], {}

    def add(key, row, label):
        if key not in seen:
            rows.append(row)
            seen[key] = row
        if label not in seen[key]['labels']:
            seen[key]['labels'].append(label)
    return rows, add


# Bend scaffolding for kinded probes: rows are [id, kind, accepted, high, low].
OBSERVE = '''def observe(index: U32, kind: U32, value: Maybe<F.Words>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{index, Con{kind, Con{0, Con{0, Con{0, rest}}}}}
    case Some{pair}:
      F.Words{high, low} = pair
      Con{index, Con{kind, Con{1, Con{high, Con{low, rest}}}}}
'''
CALCULATE = '''def calculate(values: +List<Task>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{task, rest}: one(task, calculate(rest))
def main() -> IO(Unit):
  do IO<Unit>:
'''
FIELDS = ('ah', 'al', 'bh', 'bl')


def kinded(kinds, checked):
    """expected_row, Bend task literal and native input line for [id, kind, accepted, high, low] rows."""
    def expected_row(row):
        result = checked(row['kind'], *(row[field] for field in FIELDS))
        prefix = [word32(row['id']), kinds[row['kind']]]
        return [*prefix, 0, 0, 0] if result is None else [*prefix, 1, *result]
    values = lambda row: (row['id'], *(row[field] for field in FIELDS))
    task = lambda row: row['kind'].title() + '{' + ','.join(map(str, values(row))) + '}'
    native = lambda row: ' '.join(map(str, (row['id'], kinds[row['kind']], *values(row)[1:])))
    return expected_row, task, native


def word32(value):
    if type(value) is not int or not 0 <= value < 1 << 32:
        raise ValueError('Expected unsigned 32-bit integer')
    return value


def controls(table):
    """Render native preflight controls as a C uint64_t initializer body."""
    return ',\n'.join('    {' + ','.join(f'UINT64_C(0x{value:016x})' for value in row) + '}' for row in table)


def check_environment(metadata, keys, preflights=None, layout=None):
    """The native oracle must run in RN-even with gradual underflow and all runtime controls passing."""
    if type(metadata) is not dict or set(metadata) != set(keys):
        raise ProbeFailure(f'Malformed native environment metadata: {metadata}')
    runtime = [key for key in keys if key.startswith('runtime_') or key == 'binary64_evaluation']
    if (metadata['rounding'] != 'FE_TONEAREST' or metadata['selected_rounding'] != 0
            or metadata['ftz'] is not False or metadata['daz'] is not False
            or any(metadata[key] is not True for key in runtime) or metadata['control_name'] not in FORBIDDEN):
        raise ProbeFailure(f'Unsupported native rounding/denormal/runtime environment: {metadata}')
    controls = [metadata[key] for key in ('control', 'control_after') if key in metadata]
    if any(type(value) is not int or value < 0 or value & FORBIDDEN[metadata['control_name']] for value in controls):
        raise ProbeFailure(f'Native rounding/denormal mode does not match metadata: {metadata}')
    if preflights is not None and metadata['preflight_count'] != preflights:
        raise ProbeFailure('Incomplete native preflight')
    if layout and any(type(metadata[key]) is not type(value) or metadata[key] != value for key, value in layout.items()):
        raise ProbeFailure('Unqualified native binary32/binary64 layout')


def framed(text, count, width, line):
    """Split candidate output into rows; each line holds `line` rows (the last may be short)."""
    lines, rows = text.splitlines(), []
    if len(lines) != -(-count // line):
        raise ProbeFailure(f'Wrong output line count/framing: {len(lines)} lines for {count} rows')
    for index, text_line in enumerate(lines):
        values = json.loads(text_line)
        size = min(line, count - index * line)
        if type(values) is not list or len(values) != width * size or any(type(v) is not int for v in values):
            raise ProbeFailure('Wrong output shape/count')
        rows += [values[width * i:width * (i + 1)] for i in range(size)]
    return rows


def run(name, doc, *, rows, expected_row, native, native_rows, native_input, metadata, header, task,
        width, line=16, batch=256, flags=FLAGS, preflights=None, layout=None, **summary):
    """Run one binary64 probe end to end; `summary` extends the PASS line and results.json."""
    probe = probekit.Probe(name, probekit.arguments(doc, raylib=False))
    expected = [expected_row(row) for row in rows]
    for path, value in (('inputs.json', rows), ('expected.json', expected)):
        (probe.work / path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    selected = [row for row in rows if native_rows(row)]
    inputs = probe.work / 'native-input.txt'
    inputs.write_text(''.join(native_input(row) + '\n' for row in selected))
    text = probe.native(f'#define INPUT {json.dumps(str(inputs))}\n' + native, extra_flags=flags, link_raylib=False)
    lines = text.splitlines()
    if len(lines) != len(selected) + 1:
        raise ProbeFailure(f'Wrong native line count: {len(lines)} for {len(selected)} inputs')
    check_environment(json.loads(lines[0]), metadata, preflights, layout)
    for row, record in zip(selected, lines[1:]):
        if json.loads(record) != expected[row['id']]:
            raise ProbeFailure(f'{name}: native differs from the rational oracle at id {row["id"]} {row["labels"]}: '
                               f'native={record} oracle={expected[row["id"]]}')
    print(f'{name}: exact rational/native oracle agreement on {len(selected)} inputs', flush=True)

    def render(chosen, gpu):
        call = 'calculate!' if gpu else 'calculate'
        return header + ''.join(f'    IO.print(List.show(~&1, ~U32, ~U32.show, {call}(['
                                + ','.join(map(task, chosen[start:start + line])) + '])))\n'
                                for start in range(0, len(chosen), line))

    lanes = probe.candidates(render, rows, batch=batch, parse=lambda out, chosen: framed(out, len(chosen), width, line))
    probe.compare(expected, lanes, describe=lambda i: f'id {i} {rows[i]["kind"]} {rows[i]["labels"]}')
    digest = lambda value: hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
    tags = [row[width - 3] for row in expected]
    probe.finish(observations=len(rows), native_checked=len(selected), accepted=tags.count(1), rejected=tags.count(0),
                 kinds=dict(Counter(row['kind'] for row in rows)), **summary,
                 inputs_sha256=digest(rows), oracle_sha256=digest(expected),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())
