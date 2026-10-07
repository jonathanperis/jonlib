#!/usr/bin/env python3
"""Native-format QOI ordinary files: exact bytes, typed IO and closure.

Explicit QOI selection ignores suffix; native LoadImage and explicit
LoadFileData/LoadImageFromMemory references are recorded separately. QOI uses
its own 83,886,102-byte file cap (not the 1 MiB raster cap), so it keeps its
own runner on the shared prelude rather than formatted_file's driver.
"""
import errno
import hashlib
import json
import os
import sys

import formatted_codec
from formatted_codec import bend_bytes
import formatted_file
import probekit
from probekit import ROOT, ProbeFailure
from qoi_format_probe import CODEC as MEMORY, stream

QOI_CAP = 83886102
BATCH = 64
CLOSURE_LOADS = (('c3-s0-hidden-alpha-cache', 99), ('c4-s0-hidden-alpha-cache', 99), ('magic', 0), ('directory', 5),
                 ('cap-plus-one', 2), ('host-size-overflow', 5))
TERMINAL = dict(closure_checks=True, iterations=100, paths_per_iteration=8, synthetic_checks=7)


def fixtures():
    cases = [dict(c, filename=c['id'] + '.qoi', route='LoadImage', regress=c['extended'] or c['id'] == 'c3-seeded-mix')
             for c in MEMORY.fixtures()]
    by_id = {c['id']: c for c in cases}
    for channels in (3, 4):
        original = by_id[f'c{channels}-s0-hidden-alpha-cache']
        for name, suffix, route in [('upper', '.QOI', 'LoadImage'), ('mixed', '.QoI', 'explicit'), ('without-extension', '', 'explicit'),
                                    ('misnamed', '.png', 'explicit'), ('spaces', ' with spaces.qoi', 'LoadImage'),
                                    ('many.parts', '.v1.qoi', 'LoadImage'), ('directory-dotfile', '/.qoi', 'LoadImage')]:
            ident = f'path-c{channels}-{name}'
            cases.append(dict(original, id=ident, filename=ident + suffix, route=route, regress=True))
    return cases


def controls():
    result = [dict(c, filename='error-' + c['id'] + '.qoi') for c in MEMORY.controls() if all(0 <= b <= 255 for b in c['bytes'])]
    result += [dict(id='not-qoi-raster', filename='raster.qoi', bytes=list(b'P6\n1 1\n255\n\x12\x34\x56'), error=0, native=False)]
    for ident, filename, special, error in [('missing', 'missing.png', 'missing', 5), ('missing-parent', 'missing-parent/input.qoi', 'missing', 5),
                                            ('directory', 'directory.qoi', 'directory', 5), ('cap-plus-one', 'cap-plus-one.qoi', 'sparse', 2),
                                            ('cap-misleading', 'cap-plus-one.png', 'sparse', 2), ('host-size-overflow', 'host-size-overflow.qoi', 'overflow', 5)]:
        result.append(dict(id=ident, filename=filename, special=special, error=error, native=False))
    return result


def prepare(work, cases, invalid):
    for c in cases + invalid:
        path = work / 'fixtures' / c['filename']
        c['path'] = str(path.relative_to(ROOT))
        special = c.get('special')
        if special == 'missing':
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if special == 'directory':
            path.mkdir(exist_ok=True)
            (path / 'entry').write_bytes(b'x')
        elif special in ('sparse', 'overflow'):
            with path.open('wb') as handle:
                handle.write(bytes(stream(1, 1, 4, 0, [192])))
                handle.truncate(QOI_CAP + 1 if special == 'sparse' else 4294967296)
        else:
            path.write_bytes(bytes(c['bytes']))
    # Above the raster cap but inside QOI's: read completely, then rejected as a stream.
    stress = dict(id='in-cap-full-read', filename='in-cap-full-read.qoi', error=0)
    path = work / 'fixtures' / stress['filename']
    path.write_bytes(b'x' * 1048577)
    stress['path'] = str(path.relative_to(ROOT))
    return stress


def reference_program(cases, rejected):
    lines = [formatted_codec.C_PREFIX, 'int main(void){SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        path = json.dumps(c['path'])
        lines.append('{')
        if c['route'] == 'LoadImage':
            lines.append(f'Image image=LoadImage({path});')
        else:
            lines += [f'int size=0;unsigned char *data=LoadFileData({path},&size);',
                      f'if(!data||size!={len(c["bytes"])}||size<22){{if(data)UnloadFileData(data);return 7;}}',
                      'Image image=LoadImageFromMemory(".qoi",data,size);UnloadFileData(data);']
        lines += ['if(!image.data)return 2;',
                  f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={4 if c["channels"] == 3 else 7})return 3;',
                  f'observed({json.dumps(c["id"])},"raw",image);', 'ImageFormat(&image,7);if(!image.data)return 4;',
                  f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);', '}']
    for c in rejected:
        row = json.dumps(dict(id=c['id'], role='rejected', rejected=True), separators=(',', ':'))
        lines += ['{', f'Image image=LoadImage({json.dumps(c["path"])});if(image.data){{UnloadImage(image);return 6;}}',
                  'puts(' + json.dumps(row) + ');}']
    return '\n'.join(lines + ['return 0;}']) + '\n'


def prelude():
    return formatted_file.bend_prelude(formatted_file.FileCodec(memory=MEMORY, suffixes=(), path_bases=(), other_codecs=(),
                                                                sparse_prefix=[], exact_cap_base='', bad_size=[])) + r'''
def bytes.eq(actual: List<U32>, expected: +List<U32>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case Con{a, rest} Con{b, tail}: U32.is_eq(a, b) && bytes.eq(rest, tail)
    case _ _: False{}
def success.exported(format: U32, bytes: +List<U32>, data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{3, 1}, Tuple{actual, values}}: require(U32.is_eq(format, actual) && bytes.eq(values, bytes))
    case _: require(False{})
def success.required(format: U32, bytes: +List<U32>, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Done{image}: success.exported(format, bytes, J.Surface.export(image))
    case _: require(False{})
def file.code.required(expected: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{J.FileError{code, _}}: require(U32.is_eq(expected, code))
    case _: require(False{})
def qoi.stage.short(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, codec.loaded(result), required(3))
def qoi.stage.failure(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, codec.loaded(result), exact.error(731, "stage-read-failure"))
def qoi.stage.opened(fail: Bool, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match fail result:
    case _ Fail{_}: IO.die(Unit, 1, "stage fixture open failed")
    case False{} Done{file}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.read(2, (file, Done{[1]})), qoi.stage.short)
    case True{} Done{file}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.read(2, (file, Fail{(731, "stage-read-failure")})), qoi.stage.failure)
'''


def actions_for(cases, invalid, reference):
    actions = []
    for c in cases:
        raw, normal = reference[c['id']]
        roles = ['raw'] + (['bridge', 'surface'] + (['dispatch', 'uncontracted', 'fused'] if c['route'] == 'LoadImage' else []) if c['regress'] else [])
        actions += [dict(case=c, role=role, expected=dict(raw if role == 'raw' else normal, role=role)) for role in roles]
        if c['regress'] and c['route'] == 'explicit':
            control = dict(c, id=c['id'] + '-generic', error=0)
            actions.append(dict(case=control, role='surface-error', expected=dict(id=control['id'], role='surface-error', error=0)))
    actions += [dict(case=c, role='formatted-error', expected=dict(id=c['id'], role='formatted-error', error=c['error'])) for c in invalid]
    return actions


def candidate_program(actions):
    lines = [prelude(), 'def main() -> IO(Unit):', '  do IO<Unit>:']
    for a in actions:
        c, role = a['case'], a['role']
        ident, path = json.dumps(c['id']), json.dumps(c['path'])
        call = f'J.Surface.load_qoi({path})'
        if role == 'raw':
            then = f'load.emitted({ident}, "raw")'
        elif role == 'bridge':
            then = f'bridge.emitted({ident})'
        elif role == 'formatted-error':
            then = f'load.failed({ident})'
            if c.get('special') == 'overflow':
                then = f'file.failed({ident}, {errno.EOVERFLOW}, {json.dumps(os.strerror(errno.EOVERFLOW))})'
        elif role == 'surface-error':
            call, then = f'J.Surface.load_image({path})', f'surface.failed({ident})'
        else:
            then = f'surface.emitted({ident}, {json.dumps(role)})'
            call = {'surface': f'J.Surface.load_qoi({path})', 'dispatch': f'J.Surface.load_image({path})'}.get(role) or \
                f'J.Surface.load_image_for(M.{"Uncontracted" if role == "uncontracted" else "Fused"}{{}}, {path})'
        lines.append(f'    IO.bind({formatted_file.LOADED}, Unit, {call}, {then})')
    return '\n'.join(lines) + '\n'


def boundary_program(by_id, reference):
    lines = [prelude(), 'def closure_loop(n: Nat) -> IO(Unit):', '  match n:', '    case 0n: IO.pure(Unit, Unit{})', '    case 1n+rest:', '      do IO<Unit>:']
    for name, code in CLOSURE_LOADS:
        then = f'required({code})'
        if code == 99:
            then = f'success.required({4 if by_id[name]["channels"] == 3 else 7}, {bend_bytes(reference[name][0]["bytes"])})'
        if name == 'host-size-overflow':
            then = f'file.code.required({errno.EOVERFLOW})'
        lines.append(f'        IO.bind({formatted_file.LOADED}, Unit, J.Surface.load_qoi({json.dumps(by_id[name]["path"])}), {then})')
    valid = json.dumps(by_id['c3-s0-hidden-alpha-cache']['path'])
    lines += [f'        IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({valid}, "r"), qoi.stage.opened({v}))' for v in ('False{}', 'True{}')]
    lines += ['        closure_loop(rest)', 'def main() -> IO(Unit):', '  do IO<Unit>:',
              '    require(U32.is_eq(J.Image.file.limit(J.QoiFile{}), 83886102) && (83886102 <= J.Image.file.limit(J.QoiFile{}) : U32) && Bool.not((83886103 <= J.Image.file.limit(J.QoiFile{}) : U32)))',
              '    require(J.Image.file.complete(0n, Nil{}) && J.Image.file.complete(2n, [1, 2]) && Bool.not(J.Image.file.complete(2n, [1])) && Bool.not(J.Image.file.complete(1n, [1, 2])))']
    for value, then in [('Fail{J.FileError{719, "continuation-failure"}}', 'exact.error(719, "continuation-failure")'),
                        ('J.Image.file.payload(2, Fail{(727, "payload-failure")})', 'exact.error(727, "payload-failure")'),
                        ('J.Image.file.payload(2, Done{[1]})', 'required(3)'), ('J.Image.file.payload(1, Done{[1, 2]})', 'required(3)'),
                        ('Done{[256]}', 'required(1)')]:
        lines.append(f'    IO.bind({formatted_file.LOADED}, Unit, codec.loaded({value}), {then})')
    lines += ['    closure_loop(100n)',
              f'    IO.bind({formatted_file.LOADED}, Unit, J.Surface.load_qoi({valid}), load.emitted("closure-final", "raw"))',
              '    IO.print(' + json.dumps(json.dumps(TERMINAL, separators=(',', ':'))) + ')']
    return '\n'.join(lines) + '\n'


def main(argv=None):
    probe = probekit.Probe('qoi-file', probekit.arguments(__doc__, argv=argv))
    cases, invalid = fixtures(), controls()
    stress = prepare(probe.work, cases, invalid)
    rejected = [c for c in invalid if c.get('native')]
    text = probe.native(reference_program(cases, rejected))
    heads = [dict(id=c['id'], role=r) for c in cases for r in ('raw', 'normalized')] + [dict(id=c['id'], role='rejected') for c in rejected]
    rows = formatted_codec.parse_rows(text, heads)
    reference = {c['id']: (rows[2*i], rows[2*i+1]) for i, c in enumerate(cases)}
    actions = actions_for(cases, invalid, reference)
    lanes = probe.candidates(lambda selected, gpu: candidate_program(selected), actions, batch=BATCH,
                             parse=lambda out, selected: formatted_codec.parse_rows(out, [a['expected'] for a in selected]))
    probe.compare([a['expected'] for a in actions], lanes, describe=lambda i: f'{actions[i]["case"]["id"]}/{actions[i]["role"]}')
    by_id = {c['id']: c for c in cases + invalid}
    final = dict(reference['c3-s0-hidden-alpha-cache'][0], id='closure-final')
    for name, program, expected, ceiling in [
            ('boundary', boundary_program(by_id, reference), [final], formatted_file.MAX_SPARSE_RSS),
            ('stress', candidate_program([dict(case=stress, role='formatted-error')]),
             [dict(id=stress['id'], role='formatted-error', error=0)], formatted_file.MAX_STRESS_RSS)]:
        commands = probe._compile(name, lambda gpu: program)
        for lane, command in commands.items():
            usage = probe.work / f'{name}-{lane}.rss'
            out = probekit.run([sys.executable, '-c', formatted_file.RSS_RUNNER, usage, *command], timeout=240)
            body = out.splitlines()
            if name == 'boundary':
                if not body or json.loads(body[-1]) != TERMINAL:
                    raise ProbeFailure(f'qoi-file boundary: {lane} missing closure terminal')
                body = body[:-1]
            if formatted_codec.parse_rows('\n'.join(body), expected) != expected:
                raise ProbeFailure(f'qoi-file {name}: {lane} differs')
            rss = int(usage.read_text())
            if not 0 < rss <= ceiling:
                raise ProbeFailure(f'qoi-file {name}: {lane} RSS {rss} exceeds {ceiling}')
    probe.finish(files=len(cases), file_controls=len(invalid), native_rejections=len(rejected), observations=len(actions),
                 compared_bytes=sum(len(a['expected'].get('bytes', [])) for a in actions),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
