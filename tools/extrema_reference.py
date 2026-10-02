"""Qualify the canonical literal extrema reference, never Bend/native parity.

The independent controls here are not user fixtures. The caller supplies the
unchanged canonical fixture validator, C generator, output parser, and runner;
this module deliberately does not import conformance (including in script mode).
"""
import copy
from datetime import datetime, timezone
import hashlib
import inspect
import itertools
import json
from pathlib import Path
import platform
import shutil
import struct
import uuid


PROFILES = ('AccurateGradient', 'GnuGradient')
CONTROL_VALUES = (-1.0, -0.0, 0.0, 1.0)
CONTROL_BITS = (0xbf800000, 0x80000000, 0x00000000, 0x3f800000)
KINDS = {2: 'vector_value', 3: 'vector3_value', 4: 'vector4_value'}

# Indices into CONTROL_BITS. These are predefined independent truth tables,
# not observations of a Bend candidate, the host, or the user's fixture output.
# Accurate: min zero-sign OR / max zero-sign AND. GNU: first zero operand.
TABLES = {
    'AccurateGradient': {
        'min': ((0, 0, 0, 0), (0, 1, 1, 1), (0, 1, 2, 2), (0, 1, 2, 3)),
        'max': ((0, 1, 2, 3), (1, 1, 2, 3), (2, 2, 2, 3), (3, 3, 3, 3)),
    },
    'GnuGradient': {
        'min': ((0, 0, 0, 0), (0, 1, 1, 1), (0, 2, 2, 2), (0, 1, 2, 3)),
        'max': ((0, 1, 2, 3), (1, 1, 1, 3), (2, 2, 2, 3), (3, 3, 3, 3)),
    },
}


def _bits(value):
    return struct.unpack('>I', struct.pack('>f', value))[0]


def _number(word):
    return struct.unpack('>f', struct.pack('>I', word))[0]


def _json(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def _hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def control_document():
    """All ordered pairs/triples, uniform and isolated in every vector lane."""
    cases = []
    for size, kind in KINDS.items():
        for function in ('min', 'max', 'clamp'):
            if function == 'clamp' and size == 4:
                continue
            arity = 3 if function == 'clamp' else 2
            for indices in itertools.product(range(4), repeat=arity):
                values = tuple(CONTROL_VALUES[index] for index in indices)
                for lane in (None, *range(size)):
                    if lane is None:
                        vectors = [[value] * size for value in values]
                        context = 'uniform'
                    else:
                        # Nonzero, exactly representable, lane-distinct finite
                        # sentinels expose mixed-lane/component routing errors.
                        if function == 'clamp':
                            vectors = [[(-8.0-j if j % 2 == 0 else 8.0+j) for j in range(size)],
                                       [-4.0-j for j in range(size)], [4.0+j for j in range(size)]]
                        else:
                            left = [(-2.0-j if j % 2 == 0 else 2.0+j) for j in range(size)]
                            vectors = [left, [-value for value in left]]
                        for vector, value in zip(vectors, values):
                            vector[lane] = value
                        context = f'lane-{lane}'
                    name = f'extrema-v{size}-{function}-' + ''.join(map(str, indices)) + f'-{context}'
                    cases.append(dict(id=name, width=size, height=1, background=[0, 0, 0, 0],
                                      operations=[dict(op=kind, function=function, x=0, y=0,
                                                       args=list(itertools.chain.from_iterable(vectors)))]))
    return dict(schema=1, cases=cases)


def _extreme(profile, function, left, right):
    if left in CONTROL_BITS and right in CONTROL_BITS:
        index = TABLES[profile][function][CONTROL_BITS.index(left)][CONTROL_BITS.index(right)]
        return CONTROL_BITS[index]
    # All remaining operands are the fixed finite nonzero lane sentinels.
    a, b = _number(left), _number(right)
    return left if (a < b if function == 'min' else a > b) else right


def _expected_rows(cases, profile):
    rows = []
    for case in cases:
        size, operation = case['width'], case['operations'][0]
        args = list(map(_bits, operation['args']))
        pixels = []
        for lane in range(size):
            if operation['function'] == 'clamp':
                # Raymath argument order: min(upper, max(lower, value)).
                inner = _extreme(profile, 'max', args[size+lane], args[lane])
                value = _extreme(profile, 'min', args[2*size+lane], inner)
            else:
                value = _extreme(profile, operation['function'], args[lane], args[size+lane])
            pixels.append(value)
        rows.append(dict(id=case['id'], width=size, height=1, pixels=pixels))
    return rows


def _strict_rows(output, cases, parse_output):
    """Keep the canonical parser, additionally reject unknown/duplicate fields."""
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'Duplicate native observation field: {key}')
            result[key] = value
        return result

    raw = [json.loads(line, object_pairs_hook=unique_object)
           for line in output.splitlines() if line.strip()]
    if len(raw) != len(cases):
        raise ValueError(f'Expected {len(cases)} native observations, received {len(raw)}')
    for row, case in zip(raw, cases):
        if not isinstance(row, dict) or set(row) != {'id', 'width', 'height', 'pixels'}:
            raise ValueError('Unexpected native observation fields')
        if not isinstance(row['pixels'], list):
            raise ValueError('Native observation components must be an array')
        if (row['id'] != case['id'] or type(row['width']) is not int or type(row['height']) is not int
                or (row['width'], row['height']) != (case['width'], 1)):
            raise ValueError('Wrong native observation identity/dimensions')
        if len(row['pixels']) != case['width']:
            raise ValueError('Wrong native observation component count')
        if not all(type(pixel) is int and 0 <= pixel < 2**32 for pixel in row['pixels']):
            raise ValueError('Invalid native observation component bits')
    rows = parse_output(output, cases)
    # The injected canonical parser must preserve the actual native output.
    if _json(rows) != _json(raw):
        raise ValueError('Native observation parser changed the output')
    return rows


def _match(cases, rows):
    comparisons, matches = {}, []
    for profile in PROFILES:
        differences = []
        for observed, expected in zip(rows, _expected_rows(cases, profile)):
            for component, (actual, wanted) in enumerate(zip(observed['pixels'], expected['pixels'])):
                if actual != wanted:
                    differences.append(dict(id=observed['id'], component=component,
                                            observed=f'{actual:08x}', expected=f'{wanted:08x}'))
        comparisons[profile] = dict(mismatch_count=len(differences), differences=differences)
        if not differences:
            matches.append(profile)
    return matches, comparisons


def qualify(raylib_source, library, build_dir, *, c_source, cases_from, parse_output, run):
    """Fresh native-only qualification; persist and raise on every failure.

    ``build_dir`` is the conformance build root, normally ``.build``. A single
    common profile must exactly match all controls. The report returned on
    success is also written to ``build_dir/extrema-reference/results.json``.
    Existing results are never read or reused, even after a failed rerun.
    """
    output_dir = Path(build_dir).resolve() / 'extrema-reference'
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / 'results.json'
    report = dict(schema=1, run_id=uuid.uuid4().hex,
                  started_at=datetime.now(timezone.utc).isoformat(),
                  qualified=False, selected_profile=None, parity_established=False,
                  numeric_reference_only=True, phase='setup', error=None,
                  matching_profiles=[], native_observations=[], commands=[],
                  contract='literal-vector-extrema-v1',
                  scope=['Vector2.min', 'Vector2.max', 'Vector2.clamp',
                         'Vector3.min', 'Vector3.max', 'Vector3.clamp', 'Vector4.min', 'Vector4.max'])

    def persist():
        temporary = report_path.with_suffix('.json.tmp')
        temporary.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
        temporary.replace(report_path)

    # Invalidate any stale success before source reads or subprocess execution.
    persist()

    def execute(argv, phase, filename):
        command = dict(argv=[str(arg) for arg in argv], phase=phase, completed=False)
        report['commands'].append(command)
        report['phase'] = phase
        persist()
        try:
            result = run(command['argv'])
            if not isinstance(result, str):
                raise ValueError(f'{phase}: command output must be text')
            (output_dir / filename).write_text(result)
            command.update(completed=True, output_file=filename)
            persist()
            return result
        except BaseException as error:
            # conformance.run includes command diagnostics in RuntimeError;
            # TimeoutExpired additionally retains stdout/stderr attributes.
            diagnostics = str(error)
            for field in ('stdout', 'stderr'):
                value = getattr(error, field, None)
                if value:
                    diagnostics += '\n' + (value.decode(errors='replace') if isinstance(value, bytes) else str(value))
            (output_dir / filename).write_text(diagnostics + '\n')
            command.update(output_file=filename, error=diagnostics)
            raise

    try:
        raylib_source, library = Path(raylib_source).resolve(), Path(library).resolve()
        document = control_document()
        control_spec = dict(document=document, values=list(CONTROL_VALUES),
                            bits=[f'{word:08x}' for word in CONTROL_BITS], truth_tables=TABLES,
                            clamp_order='min(upper,max(lower,value))')
        controls_path = output_dir / 'controls.json'
        controls_path.write_text(_json(control_spec) + '\n')
        report['controls_sha256'] = _hash(controls_path)
        cases = cases_from(copy.deepcopy(document))
        if _json(cases) != _json(document['cases']):
            raise ValueError('Canonical validator changed the fixed extrema controls')
        report.update(control_cases=len(cases), control_components=sum(case['width'] for case in cases))
        source_path, binary = output_dir / 'reference.c', output_dir / 'reference'
        source_path.write_text(c_source(copy.deepcopy(cases)))
        report['generated_source_sha256'] = _hash(source_path)
        # A successful command that produced nothing cannot run an old binary.
        binary.unlink(missing_ok=True)
        source_files = {Path(__file__).resolve()}
        for callback in (c_source, cases_from, parse_output):
            path = inspect.getsourcefile(callback)
            if path is None:
                raise ValueError('Missing canonical callback source provenance')
            source_files.add(Path(path).resolve())
        report['source_sha256'] = {str(path): _hash(path) for path in sorted(source_files)}
        report['raylib'] = dict(source=str(raylib_source), headers_sha256={}, library=str(library))
        for name in ('raymath.h', 'raylib.h'):
            report['raylib']['headers_sha256'][name] = _hash(raylib_source / 'src' / name)
        report['raylib']['library_sha256'] = _hash(library)
        compiler_path = shutil.which('clang')
        if not compiler_path:
            raise ValueError('Canonical clang compiler was not found')
        report.update(compiler=dict(requested='clang', path=compiler_path,
                                    real_path=str(Path(compiler_path).resolve())),
                      host=dict(system=platform.system(), machine=platform.machine(), libc=list(platform.libc_ver())))
        identity = execute(['clang', '--version'], 'compiler-identity', 'compiler.version.log').strip()
        if not identity:
            raise ValueError('Empty canonical compiler identity')
        report['compiler']['identity'] = identity
        command = ['clang', '-std=c11', '-O2', '-fno-builtin-atan2f',
                   '-I' + str(raylib_source / 'src'), str(source_path), str(library), '-lm', '-o', str(binary)]
        report['compile_command'] = command
        execute(command, 'compile', 'compile.log')
        output = execute([str(binary)], 'native-run', 'observations.jsonl')
        report.update(phase='parse', native_output_sha256=hashlib.sha256(output.encode()).hexdigest(),
                      native_output_file='observations.jsonl')
        persist()
        rows = _strict_rows(output, cases, parse_output)
        report['native_observations'] = rows
        report['phase'] = 'match'
        matches, comparisons = _match(cases, rows)
        report.update(matching_profiles=matches, comparisons=comparisons)
        if len(matches) != 1:
            reason = 'ambiguous' if matches else 'unsupported or mixed'
            raise ValueError(f'Extrema reference has an {reason} native signature; no unique common profile')
        report.update(qualified=True, selected_profile=matches[0], phase='qualified',
                      completed_at=datetime.now(timezone.utc).isoformat())
        persist()
        return report
    except BaseException as error:
        report.update(qualified=False, selected_profile=None,
                      failed_at=datetime.now(timezone.utc).isoformat(),
                      error=dict(type=type(error).__name__, message=str(error)))
        persist()
        raise
