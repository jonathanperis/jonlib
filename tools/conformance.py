#!/usr/bin/env python3
"""Full-pixel differential tests. Requires existing pinned checkouts; installs nothing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import subprocess
import platform
import time

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"
ENV = dict(os.environ, BEND_NO_TELEMETRY="1")


def run(command, cwd=ROOT):
    result = subprocess.run([str(x) for x in command], cwd=cwd, env=ENV,
                            capture_output=True, text=True, timeout=240)
    if result.returncode:
        raise RuntimeError(f"Command failed: {' '.join(map(str, command))}\n"
                           + result.stdout[-4000:] + result.stderr[-4000:])
    return result.stdout


def checkout(path, revision, overlay=None):
    actual = run(["git", "rev-parse", "HEAD"], path).strip()
    if actual != revision:
        raise ValueError(f"{path}: expected {revision}, found {actual}")
    if overlay is None:
        if run(["git", "status", "--porcelain", "--untracked-files=no"], path).strip():
            raise ValueError(f"{path}: tracked changes invalidate the pinned reference")
        return
    patch = ROOT / overlay['path']
    if hashlib.sha256(patch.read_bytes()).hexdigest() != overlay['sha256']:
        raise ValueError('Declared compiler patch hash mismatch')
    files = overlay['files']
    if not files:
        raise ValueError('A compiler overlay must declare its resulting source files')
    changed = set(run(['git', 'diff', 'HEAD', '--name-only'], path).splitlines())
    if changed - set(files):
        raise ValueError(f'{path}: unexpected tracked changes outside the compiler overlay')
    for filename, expected in files.items():
        source = path / filename
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
            raise ValueError(f'{path}: compiler overlay mismatch in {filename}; apply the declared patch')


def integer(value, minimum, maximum):
    return type(value) is int and minimum <= value <= maximum


def rgba(value):
    if not isinstance(value, list) or len(value) != 4 or not all(integer(c, 0, 255) for c in value):
        raise ValueError(f"Invalid RGBA color: {value!r}")
    return sum(c << shift for c, shift in zip(value, (24, 16, 8, 0)))


def cases_from(document):
    if document.get("schema") != 1 or not isinstance(document.get("cases"), list):
        raise ValueError("Expected fixture schema 1 and a cases array")
    cases = list(document["cases"])
    config = document.get("random")
    if config:
        if not (integer(config.get("seed"), 0, 2**32 - 1)
                and integer(config.get("cases"), 0, 100)
                and integer(config.get("operations_per_case"), 0, 100)):
            raise ValueError("Invalid seeded-fixture configuration")
        rng = random.Random(config["seed"])
        for i in range(config["cases"]):
            w, h = rng.randint(1, 23), rng.randint(1, 19)
            ops = []
            for _ in range(config["operations_per_case"]):
                op = rng.choice(("pixel", "rectangle", "circle", "clear", "flip_horizontal", "flip_vertical"))
                item = {"op": op}
                if not op.startswith('flip_'):
                    item['color'] = [rng.randrange(256) for _ in range(4)]
                if op in ('pixel', 'rectangle', 'circle'):
                    item.update(x=rng.randint(-12, w + 5), y=rng.randint(-12, h + 5))
                if op == "rectangle":
                    item.update(width=rng.randint(-3, 30), height=rng.randint(-3, 26))
                elif op == "circle":
                    item["radius"] = rng.randint(0, 18)
                ops.append(item)
            cases.append(dict(id=f"seeded-{i:03}", width=w, height=h,
                              background=[rng.randrange(256) for _ in range(4)], operations=ops))
    if not cases:
        raise ValueError("An empty conformance suite cannot pass")
    ids = set()
    for case in cases:
        name = case.get("id")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9-]+", name) or name in ids:
            raise ValueError(f"Invalid or duplicate scenario ID: {name!r}")
        ids.add(name)
        if not all(integer(case.get(k), 1, 4096) for k in ("width", "height")):
            raise ValueError(f"{name}: dimensions must be 1..4096")
        rgba(case["background"])
        if not isinstance(case.get("operations"), list):
            raise ValueError(f"{name}: operations must be an array")
        for op in case["operations"]:
            kind = op.get("op")
            if kind not in ("pixel", "rectangle", "circle", "clear", "flip_horizontal", "flip_vertical", "blend_color"):
                raise ValueError(f"{name}: unknown operation {kind!r}")
            if not kind.startswith('flip_'):
                rgba(op["color"])
            if kind == 'blend_color':
                rgba(op['destination'])
                rgba(op['tint'])
            fields = [] if kind == "clear" or kind.startswith('flip_') else ["x", "y"]
            if kind == "rectangle":
                fields += ["width", "height"]
            if any(not integer(op.get(k), -32767, 32767) for k in fields):
                raise ValueError(f"{name}: coordinates must be integral and in -32767..32767")
            if kind == "circle" and not integer(op.get("radius"), 0, 32767):
                raise ValueError(f"{name}: radius must be 0..32767")
    return cases


def c_source(cases):
    lines = ['#include "raylib.h"', '#include <stdio.h>', 'int main(void) {',
             'SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        w, h = case["width"], case["height"]
        lines += ['{', f'Image image = GenImageColor({w}, {h}, GetColor({rgba(case["background"])}u));']
        for op in case["operations"]:
            kind = op["op"]
            if kind.startswith('flip_'):
                function = 'ImageFlipHorizontal' if kind == 'flip_horizontal' else 'ImageFlipVertical'
                lines += [f'{function}(&image);']
                continue
            color = f'GetColor({rgba(op["color"])}u)'
            if kind == "clear":
                lines += [f'ImageClearBackground(&image, {color});']
            elif kind == "pixel":
                lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, {color});']
            elif kind == "rectangle":
                lines += [f'ImageDrawRectangle(&image, {op["x"]}, {op["y"]}, {op["width"]}, {op["height"]}, {color});']
            elif kind == "circle":
                lines += [f'ImageDrawCircle(&image, {op["x"]}, {op["y"]}, {op["radius"]}, {color});']
            elif kind == "blend_color":
                lines += [f'ImageDrawPixel(&image, {op["x"]}, {op["y"]}, ColorAlphaBlend(GetColor({rgba(op["destination"])}u), {color}, GetColor({rgba(op["tint"])}u)));']
        prefix = '{"id":"' + case["id"] + '","width":%d,"height":%d,"pixels":['
        lines += [f'printf({json.dumps(prefix)}, image.width, image.height);',
                  'for (int y = 0; y < image.height; y++) for (int x = 0; x < image.width; x++) {',
                  'if (x || y) putchar(\',\');',
                  'printf("%u", (unsigned int)ColorToInt(GetImageColor(image, x, y)));',
                  '}', 'puts("]}");', 'UnloadImage(image);', '}']
    return '\n'.join(lines + ['return 0;', '}']) + '\n'


def f32(value):
    return f"{value}.0" if value >= 0 else f"(0.0 - {-value}.0 : F32)"


def bend_source(cases, gpu=False):
    lines = ['import Base', 'import ../jonlib.bend as J', '',
             'def emit(name: String, image: J.Surface) -> IO(Unit):',
             '  J.Surface{+w, +h, pixels} = image',
             '  IO.print("{\\"id\\":\\"" ++ name ++ "\\",\\"width\\":" ++ U32.show(w)',
             '    ++ ",\\"height\\":" ++ U32.show(h) ++ ",\\"pixels\\":"',
             '    ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{w, h, pixels})) ++ "}")', '']
    for i, case in enumerate(cases):
        lines += [f'def draw_{i}(surface: J.Surface) -> J.Surface:']
        previous = 'surface'
        for j, op in enumerate(case["operations"]):
            kind = op["op"]
            args = [previous]
            if kind not in ('clear', 'flip_horizontal', 'flip_vertical'):
                args += [f32(op['x']), f32(op['y'])]
            if kind == 'rectangle':
                args += [f32(op['width']), f32(op['height'])]
            if kind == 'circle':
                args += [str(op['radius'])]
            if kind == 'blend_color':
                args += [f'J.Color.alpha_blend({rgba(op["destination"])}, {rgba(op["color"])}, {rgba(op["tint"])})']
            elif not kind.startswith('flip_'):
                args += [str(rgba(op['color']))]
            function = kind if kind == 'clear' or kind.startswith('flip_') else 'draw_' + kind
            if kind == 'blend_color':
                function = 'draw_pixel'
            previous = f's{j}'
            lines += [f'  {previous} = J.Surface.{function}({", ".join(args)})']
        lines += [f'  {previous}', '', f'def case_{i}(created: Maybe<J.Surface>) -> IO(Unit):',
                  '  match created:', '    case None{}:',
                  '      IO.die(Unit, 1, "valid fixture image creation failed")',
                  '    case Some{surface}:',
                  f'      emit("{case["id"]}", draw_{i}{"!" if gpu else ""}(surface))', '']
    lines += ['def main() -> IO(Unit):', '  do IO<Unit>:']
    for i, case in enumerate(cases):
        lines += [f'    case_{i}(J.Surface.create({case["width"]}, {case["height"]}, {rgba(case["background"])}))']
    return '\n'.join(lines) + '\n'


def parse_output(output, cases):
    rows = [json.loads(line) for line in output.splitlines() if line.strip()]
    if len(rows) != len(cases):
        raise ValueError(f"Expected {len(cases)} result rows, received {len(rows)}")
    for row, case in zip(rows, cases):
        if not all(integer(row[k], 1, 4096) for k in ('width', 'height')):
            raise ValueError(f"Invalid output dimensions: {row['id']}")
        if (row['id'], row['width'], row['height']) != (case['id'], case['width'], case['height']):
            raise ValueError(f"Wrong scenario identity/dimensions: {row['id']}")
        if len(row['pixels']) != case['width'] * case['height']:
            raise ValueError(f"Wrong pixel count: {row['id']}")
        if not all(integer(p, 0, 2**32 - 1) for p in row['pixels']):
            raise ValueError(f"Invalid RGBA word: {row['id']}")
    return rows


def compare(expected, actual):
    if not expected or len(expected) != len(actual):
        raise ValueError("Missing or empty results")
    for reference, candidate in zip(expected, actual):
        if {k: reference[k] for k in ('id', 'width', 'height')} != {k: candidate[k] for k in ('id', 'width', 'height')}:
            raise ValueError("Scenario identity/dimensions mismatch")
        if len(reference['pixels']) != len(candidate['pixels']):
            raise ValueError(f"{reference['id']}: pixel count mismatch")
        for i, (a, b) in enumerate(zip(reference['pixels'], candidate['pixels'])):
            if a != b:
                x, y = i % reference['width'], i // reference['width']
                raise ValueError(f"{reference['id']}: pixel ({x}, {y}): raylib={a:08x}, Jonlib={b:08x}")


def source_gate():
    sources = [ROOT / 'jonlib.bend', *sorted((ROOT / 'src').glob('**/*.bend'))]
    for path in sources:
        text = path.read_text()
        if re.search(r'@unsafe|^def\s+[\w.]+\?', text, re.M):
            raise ValueError(f"Unsafe library implementation: {path}")
        for line in text.splitlines():
            if line.strip().startswith('import '):
                if line.startswith((' ', '\t')) or not re.fullmatch(r'import (Base|\./[\w/.-]+\.bend(?: as \w+)?)', line):
                    raise ValueError(f"Unexpected library import: {path}: {line}")
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}


def inventory(header):
    declarations = re.findall(r'^RLAPI\s+(.+?\b([A-Za-z_]\w*)\s*\([^;]*\));', header, re.M)
    names = [name for _, name in declarations]
    if len(names) != 600 or len(set(names)) != 600:
        raise ValueError('The pinned raylib 6.0 API inventory must contain 600 unique declarations')
    mapping = json.loads((ROOT / 'docs/api-map.json').read_text())
    if set(mapping) - set(names):
        raise ValueError('Compatibility map contains unknown raylib APIs')
    return [dict(raylib=name, signature=signature,
                 **mapping.get(name, dict(jonlib=None, status='not-implemented')))
            for signature, name in declarations]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, default=Path.home() / 'Projetos/bendlang/bend')
    parser.add_argument('--raylib-source', type=Path, default=Path.home() / 'Projetos/raysan5/raylib')
    parser.add_argument('--fixtures', type=Path, default=ROOT / 'tests/fixtures/images.json')
    parser.add_argument('--gpu', action='store_true', help='Build and force the native GPU lane; failure is fatal')
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    report = dict(passed=False, lanes={}, profile='rgba8-cpu-images-v1')
    report_path = BUILD / 'conformance.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    started = time.monotonic()
    lock = json.loads((ROOT / 'toolchain.json').read_text())
    checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
    checkout(args.raylib_source, lock['raylib']['revision'])
    report['toolchain'] = lock
    report['host'] = dict(system=platform.system(), machine=platform.machine(),
                          bun=run(['bun', '--version']).strip(),
                          clang=run(['clang', '--version']).splitlines()[0])
    report['sources'] = source_gate()
    api = inventory((args.raylib_source / 'src/raylib.h').read_text())
    (BUILD / 'api-inventory.json').write_text(json.dumps(api, indent=2) + '\n')
    report['api_inventory'] = dict(total=len(api), mapped=sum(row['jonlib'] is not None for row in api))
    report['verification_sources'] = {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (ROOT / 'tools/conformance.py', ROOT / 'tests/contracts.bend',
                     ROOT / 'LAWS.bend', ROOT / 'PROOF.bend', ROOT / 'examples/headless.bend',
                     ROOT / 'docs/api-map.json')
    }
    cases = cases_from(json.loads(args.fixtures.read_text()))
    expanded = json.dumps(cases, sort_keys=True)
    (BUILD / 'scenarios.json').write_text(expanded + '\n')
    report['fixtures_sha256'] = hashlib.sha256(expanded.encode()).hexdigest()
    report['scenarios'] = [c['id'] for c in cases]
    report['pixels_per_lane'] = sum(c['width'] * c['height'] for c in cases)
    cli = ['bun', args.bend_source / 'bend2/main.ts']
    library_verdict = run([*cli, ROOT / 'jonlib.bend', '--check-only'])
    if library_verdict.strip() != 'All terms check.':
        raise ValueError(f"Unexpected library verdict: {library_verdict}")
    proof_verdict = run([*cli, ROOT / 'PROOF.bend', '--check-only'])
    if proof_verdict.strip() != 'All terms check.':
        raise ValueError(f"Unexpected proof verdict: {proof_verdict}")
    report['proof'] = proof_verdict.strip()
    cmake = BUILD / 'raylib'
    print('Building pinned raylib reference...', flush=True)
    run(['cmake', '-S', args.raylib_source, '-B', cmake, '-DPLATFORM=Memory',
         '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_EXAMPLES=OFF', '-DCUSTOMIZE_BUILD=ON',
         '-DSUPPORT_MODULE_RAUDIO=OFF', '-DUSE_EXTERNAL_GLFW=OFF'])
    run(['cmake', '--build', cmake, '--parallel', '4'])
    (BUILD / 'reference.c').write_text(c_source(cases))
    run(['clang', '-std=c11', '-O2', '-I' + str(args.raylib_source / 'src'),
         BUILD / 'reference.c', cmake / 'raylib/libraylib.a', '-lm', '-o', BUILD / 'reference'])
    reference_text = run([BUILD / 'reference'])
    (BUILD / 'reference.jsonl').write_text(reference_text)
    reference = parse_output(reference_text, cases)
    source = BUILD / 'candidate.bend'
    source.write_text(bend_source(cases))
    print('Building Bend CPU and JavaScript runners...', flush=True)
    run([*cli, source, '-o', BUILD / 'candidate', '-o', BUILD / 'candidate.js'])
    lanes = [('cpu-1', [BUILD / 'candidate', '--threads', '1']),
             ('cpu-2', [BUILD / 'candidate', '--threads', '2']),
             ('javascript', ['bun', BUILD / 'candidate.js'])]
    if args.gpu:
        gpu_source = BUILD / 'candidate-gpu.bend'
        gpu_source.write_text(bend_source(cases, gpu=True))
        print('Building native GPU runner...', flush=True)
        run([*cli, gpu_source, '-o', BUILD / 'candidate-gpu'])
        lanes.append(('gpu-forced', [BUILD / 'candidate-gpu', '--gpu', 'on']))
    for lane, command in lanes:
        output = run(command)
        (BUILD / f'{lane}.jsonl').write_text(output)
        compare(reference, parse_output(output, cases))
        report['lanes'][lane] = dict(passed=True, scenarios=len(cases), pixels=report['pixels_per_lane'])
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(f'{lane}: {len(cases)} scenarios, {report["pixels_per_lane"]} pixels match exactly', flush=True)
    run([*cli, ROOT / 'tests/contracts.bend', '-o', BUILD / 'contracts', '-o', BUILD / 'contracts.js'])
    for lane, command in [('cpu', [BUILD / 'contracts']), ('javascript', ['bun', BUILD / 'contracts.js'])]:
        if run(command).strip() != 'contracts ok':
            raise ValueError(f'{lane}: ownership/color/adapter contract failed')
    report['contracts'] = ['cpu', 'javascript']
    print('Ownership, bounds, color and Base.Image contracts: CPU/JS passed', flush=True)
    example_reference = next((row for row in reference if row['id'] == 'radius-12-regression'), None)
    if example_reference is None:
        raise ValueError('Fixtures must include radius-12-regression for the headless example comparison')
    run([*cli, ROOT / 'examples/headless.bend', '-o', BUILD / 'headless'])
    run([BUILD / 'headless'])
    ppm = (BUILD / 'headless.ppm').read_text().split()
    if ppm[:4] != ['P3', str(example_reference['width']), str(example_reference['height']), '255']:
        raise ValueError('Headless example PPM header mismatch')
    expected_rgb = [str((p >> shift) & 255) for p in example_reference['pixels'] for shift in (24, 16, 8)]
    if ppm[4:] != expected_rgb:
        raise ValueError('Headless example RGB pixels differ from raylib')
    report['example'] = dict(path='.build/headless.ppm', pixels=len(example_reference['pixels']), passed=True)
    print('Headless PPM export: every RGB pixel matches raylib', flush=True)
    report['passed'] = True
    report['elapsed_seconds'] = round(time.monotonic() - started, 3)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS — evidence: .build/conformance.json')


if __name__ == '__main__':
    main()
