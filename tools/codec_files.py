"""Shared driver for native-format file-loading probes (J.Surface.load_<codec>).

Builds on a codec_formats.Codec. Every accepted memory fixture becomes a real
file; extra path variants exercise raylib's whole-path extension routing:
recognized tokens go through native LoadImage, anything else through
LoadFileData + LoadImageFromMemory(<codec token>). Candidate roles per file:

  raw / owner / factory / raw-roundtrip   Surface.load_<codec>          -> native raw
  bridge / surface                        Surface.format(7) / colors    -> normalized
  dispatch-<codec> / uncontracted / fused Surface.load_image(_for)      -> normalized
  formatted-error                         typed Surface.IOError codes on file controls
                                          (exact errno and message for missing/
                                          directory/overflow)
  surface-error                           generic dispatch rejects unrecognized paths

Then three resource runs on every lane under RLIMIT_NOFILE=64 with RSS ceilings:
a 100-iteration open/close closure loop plus staged read/size failures,
the sparse/oversized controls (rejected before reading), and an exact-cap file.
"""
from dataclasses import dataclass
import errno
import hashlib
import json
import os
import sys
from typing import Callable, Optional

import codec_formats
from codec_formats import bend_bytes, bend_input
import probekit
from probekit import ROOT, ProbeFailure

ALIAS_MACROS = ('BMP', 'PNG', 'TGA', 'JPG', 'GIF', 'PIC', 'PNM', 'PSD')
ALIAS_NAMES = ('bmp', 'png', 'tga', 'jpg', 'jpeg', 'gif', 'pic', 'pgm', 'ppm', 'psd')
RECOGNIZED = {'.' + n for n in ALIAS_NAMES} | {'.' + n.upper() for n in ALIAS_NAMES}
MAX_SPARSE_RSS = 256 * 1024 * 1024
MAX_STRESS_RSS = 1024 * 1024 * 1024
ITERATIONS = 100
STAGES = (('stage-short', 3), ('stage-read-failure', 5), ('stage-size-failure', 5), ('stage-long', 3))
SPECIAL_SIZE = {'large': 256 * 1024 * 1024, 'overflow': 4294967296}
RSS_RUNNER = ('import json,resource,subprocess,sys;'
              'resource.setrlimit(resource.RLIMIT_NOFILE,(64,64));'
              'code=subprocess.run(sys.argv[2:],timeout=230).returncode;'
              'rss=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss;'
              "open(sys.argv[1],'w').write(str(int(rss if sys.platform=='darwin' else rss*1024)));sys.exit(code)")


@dataclass
class FileCodec:
    memory: codec_formats.Codec
    suffixes: tuple                 # (name, suffix or case->suffix) path variants applied to each base fixture
    path_bases: tuple               # fixture ids that get every path variant
    other_codecs: tuple             # (id, bytes) other-format content saved with this codec's suffix
    sparse_prefix: list             # tiny valid prefix for sparse/large/overflow controls
    exact_cap_base: str             # fixture id padded to exactly `cap` bytes
    bad_size: list                  # encoded stream with an unsupported size (staged continuation)
    roles: tuple = ('raw', 'owner', 'bridge', 'surface')
    cap: int = 1048576
    synthetic: bool = True          # also run non-byte controls through the file continuation
    loop_loads: tuple = ()          # ids loaded each closure iteration (default: singles + 3 controls)
    upper_suffix_names: tuple = ()  # suffix names given an '-upper' filename (case-insensitive filesystems)
    token_for: Optional[Callable] = None     # case -> file suffix (default: the codec token)
    control_suffix: Optional[str] = None     # suffix for memory-control files (default: token)
    other_suffix: Optional[str] = None       # suffix for other-codec files (default: token)
    specials: Optional[tuple] = None         # (id, filename, kind, error) special file controls
    batch: int = 32

    @property
    def name(self):
        return self.memory.name


def extension(path):
    """Pinned GetFileExtension: last dot of the whole path, excluding index 0."""
    index = path.rfind('.')
    return path[index:] if index > 0 else ''


def fixtures(codec):
    token_for = codec.token_for or (lambda case: codec.memory.token)
    cases = [dict(c, filename=c['id'] + token_for(c), route='LoadImage', regress=c['extended'])
             for c in codec.memory.fixtures() if len(c['bytes']) <= codec.cap]
    originals = {c['id']: c for c in cases}
    for base in codec.path_bases:
        original = originals[base]
        for name, suffix in codec.suffixes:
            suffix = suffix(original) if callable(suffix) else suffix
            ident = f'path-{base.removesuffix("-single")}-{name}'
            filename = ident + ('-upper' if name in codec.upper_suffix_names else '') + suffix
            routed = extension('fixtures/' + filename) in RECOGNIZED
            cases.append(dict(original, id=ident, filename=filename, route='LoadImage' if routed else 'explicit', regress=True))
    if len({c['filename'] for c in cases}) != len(cases):
        raise ProbeFailure(f'{codec.name}: duplicate file fixture names')
    return cases


def controls(codec):
    token = codec.memory.token
    result = [dict(c, filename='error-' + c['id'] + (codec.control_suffix or token)) for c in codec.memory.controls()
              if all(0 <= b <= 255 for b in c['bytes'])]
    # Memory-valid fixtures above the file cap must be rejected by the bounded loader.
    result += [dict(id=c['id'], bytes=c['bytes'], filename='error-' + c['id'] + token, error=2)
               for c in codec.memory.fixtures() if len(c['bytes']) > codec.cap]
    for ident, data in codec.other_codecs:
        result.append(dict(id=ident, filename=ident + (codec.other_suffix or token), bytes=list(data), error=0))
    specials = codec.specials or (('missing', 'missing.qoi', 'missing', 5), ('missing-parent', f'missing-parent/input{token}', 'missing', 5),
                                  ('directory', f'directory{token}', 'directory', 5), ('cap-plus-one', f'cap-plus-one{token}', 'sparse', 2),
                                  ('cap-misleading', 'cap-plus-one.qoi', 'sparse', 2), ('larger-file', f'larger-file{token}', 'large', 2),
                                  ('host-size-overflow', f'host-size-overflow{token}', 'overflow', 5))
    for ident, filename, special, error in specials:
        result.append(dict(id=ident, filename=filename, special=special, error=error))
    return result


def prepare(codec, work, cases, invalid):
    """Write fixtures under work/fixtures; return the exact-cap case."""
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
        elif special in ('sparse', 'large', 'overflow'):
            # A tiny valid prefix, then holes that must never be read.
            with path.open('wb') as handle:
                handle.write(bytes(codec.sparse_prefix))
                handle.truncate(codec.cap + 1 if special == 'sparse' else SPECIAL_SIZE[special])
        else:
            path.write_bytes(bytes(c['bytes']))
    original = next(c for c in cases if c['id'] == codec.exact_cap_base)
    stress = dict(original, id='exact-cap-accepted', filename='exact-cap' + (codec.token_for or (lambda c: codec.memory.token))(original), regress=False)
    stress['bytes'] = original['bytes'] + [i % 256 for i in range(codec.cap - len(original['bytes']))]
    path = work / 'fixtures' / stress['filename']
    stress['path'] = str(path.relative_to(ROOT))
    path.write_bytes(bytes(stress['bytes']))
    return stress


def reference_program(codec, cases):
    memory = codec.memory
    lines = [codec_formats.C_PREFIX, 'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        path, fmt = json.dumps(c['path']), memory.formats[c['channels']]
        raw_size = c['width'] * c['height'] * codec_formats.CHANNEL_BYTES[fmt]
        lines.append('{')
        if c['route'] == 'LoadImage':
            lines.append(f'Image image=LoadImage({path});')
        else:
            lines += [f'int size=0;unsigned char *data=LoadFileData({path},&size);',
                      f'if(!data||size!={len(c["bytes"])}){{if(data)UnloadFileData(data);return 7;}}',
                      f'Image image=LoadImageFromMemory("{memory.token}",data,size);UnloadFileData(data);']
        lines += ['if(!image.data)return 2;',
                  f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}'
                  f'||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 3;}}',
                  f'observed({json.dumps(c["id"])},"raw",image);', 'ImageFormat(&image,7);if(!image.data)return 4;',
                  f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);', '}']
    return '\n'.join(lines + ['return 0;}']) + '\n'


def qualification_program(codec):
    """The memory qualification plus pinned GetFileExtension path-token rules."""
    checks = ('if(GetFileExtension(".x")!=NULL||GetFileExtension("dir/.x")==NULL||strcmp(GetFileExtension("dir/.x"),".x")'
              '||GetFileExtension("dir.x/leaf")==NULL||strcmp(GetFileExtension("dir.x/leaf"),".x/leaf"))return 14;')
    program = codec.memory.qualification[0] if codec.memory.qualification else (
        codec_formats.C_PREFIX + 'int main(void){SetTraceLogLevel(LOG_NONE);puts("{}");return 0;}\n')
    return '#include <string.h>\n' + program.replace('SetTraceLogLevel(LOG_NONE);', 'SetTraceLogLevel(LOG_NONE);' + checks, 1)


LOADED = 'Result<&1, &1, J.Surface.IOError, J.Surface>'


def bend_prelude(codec):
    from byte_probe import BEND_EMITTER
    n = codec.name
    return codec_formats.BEND_PRELUDE.replace('def reverse_into(', BEND_EMITTER + 'def reverse_into(', 1) + rf'''
def loaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{{_}}: None{{}}
    case Done{{image}}: checked(image)
def surface.loaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{{_}}: None{{}}
    case Done{{image}}: rgba(image)
def load.error(error: J.Surface.IOError) -> U32:
  match error:
    case J.FileError{{_, _}}: 5
    case J.DataError{{error}}: error.code(error)
    case _: 97
def load.emitted(id: String, role: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  observed(id, role, loaded(result))
def bridge.emitted(id: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  observed(id, "bridge", bridge(loaded(result)))
def roundtrip.emitted(id: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  observed(id, "raw-roundtrip", roundtrip(loaded(result)))
def factory.emitted(id: String, width: U32, height: U32, format: U32, bytes: +List<U32>, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{{_}}: IO.die(Unit, 1, "file factory source rejected")
    case Done{{_}}: observed(id, "factory", J.Surface.from_bytes(width, height, format, bytes))
def surface.emitted(id: String, role: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  observed(id, role, surface.loaded(result))
def load.failed(id: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Done{{_}}: emit.error(id, "formatted-error", 99)
    case Fail{{error}}: emit.error(id, "formatted-error", load.error(error))
def surface.failed(id: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Done{{_}}: emit.error(id, "surface-error", 99)
    case Fail{{error}}: emit.error(id, "surface-error", load.error(error))
def require(ok: Bool) -> IO(Unit):
  match ok:
    case True{{}}: IO.pure(Unit, Unit{{}})
    case False{{}}: IO.die(Unit, 1, "file boundary or closure differs")
def required(expected: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Done{{_}}: require(U32.is_eq(expected, 99))
    case Fail{{error}}: require(U32.is_eq(expected, load.error(error)))
def exact.error(code: U32, message: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{{J.FileError{{actual, text}}}}: require(U32.is_eq(code, actual) && String.eq(message, text))
    case _: require(False{{}})
def file.failed(id: String, expected: U32, message: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  do IO<Unit>:
    exact.error(expected, message, result)
    emit.error(id, "formatted-error", 5)
def codec.loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Result<&1, &1, J.Surface.IOError, J.Surface>):
  J.Surface.load.decoded(~J.Surface.decode_{n}, result)
def surface.codec.loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Result<&1, &1, J.Surface.IOError, J.Surface>):
  match result:
    case Fail{{error}}: IO.pure(Result<&1, &1, J.Surface.IOError, J.Surface>, Fail{{error}})
    case Done{{bytes}}: IO.pure(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Image.file.decoded(J.Surface, J.Surface.decode_{n}(bytes)))
def surface.codec(path: String) -> IO(Result<&1, &1, J.Surface.IOError, J.Surface>):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Result<&1, &1, J.Surface.IOError, J.Surface>, J.Image.file.bytes(path, J.Image.file.limit(J.RasterFile{{}})), surface.codec.loaded)
def owner.emitted(id: String, +width: U32, +height: U32, first: U32, last: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  observed(id, "owner", owner(loaded(result), width, height, first, last))
def stage.emitted(id: String, +expected: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  do IO<Unit>:
    required(expected, result)
    emit.error(id, "formatted-error", expected)
def stage.exact(id: String, code: U32, message: String, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  do IO<Unit>:
    exact.error(code, message, result)
    emit.error(id, "formatted-error", 5)
def stage.loaded(id: String, expected: U32, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, codec.loaded(result), stage.emitted(id, expected))
def stage.failed(id: String, code: U32, message: String, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, codec.loaded(result), stage.exact(id, code, message))
def stage.opened(mode: U32, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match mode result:
    case _ Fail{{_}}: IO.die(Unit, 1, "stage fixture open failed")
    case 0 Done{{file}}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.read(2, (file, Done{{[1]}})), stage.loaded("stage-short", 3))
    case 1 Done{{file}}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.read(2, (file, Fail{{(731, "stage-read-failure")}})), stage.failed("stage-read-failure", 731, "stage-read-failure"))
    case 2 Done{{file}}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.sized(1048576, (file, Fail{{(733, "stage-size-failure")}})), stage.failed("stage-size-failure", 733, "stage-size-failure"))
    case _ Done{{file}}:
      IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.read(1, (file, Done{{[1, 2]}})), stage.loaded("stage-long", 3))
'''


def expectations(codec, cases, invalid, reference, synthetic=()):
    memory, actions = codec.memory, []
    for c in cases:
        raw, normal = reference[c['id']]
        roles = list(codec.roles) + ([f'dispatch-{codec.name}', 'uncontracted', 'fused'] if c['regress'] and c['route'] == 'LoadImage' else [])
        for role in roles:
            actions.append(dict(case=c, role=role, normalized=normal['bytes'],
                                expected=dict(raw if role in codec_formats.RAW_ROLES else normal, role=role)))
        if c['regress'] and c['route'] == 'explicit':
            control = dict(c, id=c['id'] + '-generic', error=0)
            actions.append(dict(case=control, role='surface-error', expected=dict(id=control['id'], role='surface-error', error=0)))
    actions += [dict(case=c, role='formatted-error', expected=dict(id=c['id'], role='formatted-error', error=c['error'])) for c in invalid]
    actions += [dict(case=c, role='formatted-error', synthetic=True, expected=dict(id=c['id'], role='formatted-error', error=c['error']))
                for c in synthetic]
    return actions


def candidate_lines(codec, actions):
    n, lines = codec.name, []
    for a in actions:
        c, role = a['case'], a['role']
        ident = json.dumps(c['id'])
        if a.get('synthetic'):
            lines.append(f'IO.bind({LOADED}, Unit, codec.loaded(Done{{{bend_input(c["bytes"])}}}), load.failed({ident}))')
            continue
        path = json.dumps(c['path'])
        call = f'J.Surface.load_{n}({path})'
        if role == 'raw':
            then = f'load.emitted({ident}, "raw")'
        elif role == 'owner':
            first, last = int.from_bytes(bytes(a['normalized'][:4]), 'big'), int.from_bytes(bytes(a['normalized'][-4:]), 'big')
            then = f'owner.emitted({ident}, {c["width"]}, {c["height"]}, {first}, {last})'
        elif role == 'bridge':
            then = f'bridge.emitted({ident})'
        elif role == 'raw-roundtrip':
            then = f'roundtrip.emitted({ident})'
        elif role == 'factory':
            then = (f'factory.emitted({ident}, {c["width"]}, {c["height"]}, {codec.memory.formats[c["channels"]]}, '
                    f'{bend_input(a["expected"]["bytes"])})')
        elif role == 'formatted-error':
            then = f'load.failed({ident})'
            code = {'overflow': errno.EOVERFLOW, 'directory': errno.EISDIR, 'missing': errno.ENOENT}.get(c.get('special'))
            if code is not None:
                then = f'file.failed({ident}, {code}, {json.dumps(os.strerror(code))})'
        elif role in ('surface', f'dispatch-{n}', 'uncontracted', 'fused', 'surface-error'):
            then = f'surface.emitted({ident}, {json.dumps(role)})'
            if role == 'surface':
                call = f'surface.codec({path})'
            elif role in (f'dispatch-{n}', 'surface-error'):
                call = f'J.Surface.load_image({path})'
            else:
                call = f'J.Surface.load_image_for(M.{"Uncontracted" if role == "uncontracted" else "Fused"}{{}}, {path})'
            if role == 'surface-error':
                then = f'surface.failed({ident})'
        else:
            raise ProbeFailure(f'{n}: unknown file role {role}')
        lines.append(f'IO.bind({LOADED}, Unit, {call}, {then})')
    return lines


def candidate_program(codec, actions):
    body = ['    ' + line for line in candidate_lines(codec, actions)]
    return '\n'.join([bend_prelude(codec), 'def main() -> IO(Unit):', '  do IO<Unit>:', *body]) + '\n'


def boundary(codec, cases, invalid, reference):
    """Closure program: helper contracts, staged failures, then ITERATIONS load cycles."""
    by_id = {c['id']: c for c in cases + invalid}
    loads = codec.loop_loads or tuple(codec.path_bases) + (codec.other_codecs[0][0], 'directory', 'cap-plus-one', 'host-size-overflow')
    synthetic = [('Fail{J.FileError{719, "continuation-failure"}}', 'stage.exact("continuation-error", 719, "continuation-failure")', 'continuation-error', 5),
                 ('J.Image.file.payload(2, Fail{(727, "payload-failure")})', 'stage.exact("payload-error", 727, "payload-failure")', 'payload-error', 5),
                 ('J.Image.file.payload(2, Done{[1]})', 'stage.emitted("payload-short", 3)', 'payload-short', 3),
                 ('J.Image.file.payload(1, Done{[1, 2]})', 'stage.emitted("payload-long", 3)', 'payload-long', 3),
                 ('Done{[256]}', 'stage.emitted("invalid-byte", 1)', 'invalid-byte', 1),
                 ('Done{Nil{}}', 'stage.emitted("empty-header", 0)', 'empty-header', 0),
                 ('Done{' + bend_bytes(codec.bad_size) + '}', 'stage.emitted("bad-size", 2)', 'bad-size', 2)]
    expected = [dict(id=i, role='formatted-error', error=e) for *_, i, e in synthetic]
    expected.append(dict(id='wrapped-stream', role='formatted-error', error=4))
    cycle_actions = []
    for ident in loads:
        c = by_id[ident]
        if ident in reference:
            cycle_actions.append(dict(case=c, role='raw', expected=reference[ident][0]))
        else:
            cycle_actions.append(dict(case=c, role='formatted-error', expected=dict(id=ident, role='formatted-error', error=c['error'])))
    cycle = [a['expected'] for a in cycle_actions] + [dict(id=i, role='formatted-error', error=e) for i, e in STAGES]
    expected += cycle * ITERATIONS
    final = by_id[codec.exact_cap_base]
    expected.append(dict(reference[final['id']][0], id='closure-final'))
    n, valid = codec.name, json.dumps(final['path'])
    token = codec.memory.token
    lines = [bend_prelude(codec), 'def closure_loop(k: Nat) -> IO(Unit):', '  match k:', '    case 0n: IO.pure(Unit, Unit{})',
             '    case 1n+rest:', '      do IO<Unit>:']
    lines += ['        ' + line for line in candidate_lines(codec, cycle_actions)]
    lines += [f'        IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({valid}, "r"), stage.opened({mode}))' for mode in range(4)]
    lines += ['        closure_loop(rest)', 'def main() -> IO(Unit):', '  do IO<Unit>:',
              '    require(U32.is_eq(J.Image.file.limit(J.RasterFile{}), 1048576) && (1048576 <= J.Image.file.limit(J.RasterFile{}) : U32) && Bool.not((1048577 <= J.Image.file.limit(J.RasterFile{}) : U32)))',
              f'    require(String.eq(J.Image.file.token("{token}"), "") && String.eq(J.Image.file.token("dir/{token}"), "{token}") && String.eq(J.Image.file.token("dir{token}/leaf"), "{token}/leaf"))',
              '    require(J.Image.file.complete(0n, Nil{}) && J.Image.file.complete(2n, [1, 2]) && Bool.not(J.Image.file.complete(2n, [1])) && Bool.not(J.Image.file.complete(1n, [1, 2])))']
    lines += [f'    IO.bind({LOADED}, Unit, codec.loaded({value}), {then})'
              for value, then, *_ in synthetic]
    lines += ['    stage.emitted("wrapped-stream", 4, J.Image.file.decoded(J.Surface, Fail{J.InvalidImageStream{}}))',
              f'    closure_loop({ITERATIONS}n)',
              f'    IO.bind({LOADED}, Unit, J.Surface.load_{n}({valid}), load.emitted("closure-final", "raw"))']
    return '\n'.join(lines) + '\n', expected


def resource_run(probe, name, program, expected, ceiling):
    """Compile once; run every lane under RLIMIT_NOFILE=64 and an RSS ceiling."""
    commands = probe._compile(name, lambda gpu: program)
    for lane, command in commands.items():
        usage = probe.work / f'{name}-{lane}.rss'
        text = probekit.run([sys.executable, '-c', RSS_RUNNER, usage, *command], timeout=240)
        rows = codec_formats.parse_rows(text, expected)
        if rows != expected:
            first = next(i for i, (a, b) in enumerate(zip(expected, rows)) if a != b) if len(rows) == len(expected) else 0
            raise ProbeFailure(f'{codec_name(probe)} {name}: {lane} differs at record {first}')
        rss = int(usage.read_text())
        if not 0 < rss <= ceiling:
            raise ProbeFailure(f'{name}: {lane} RSS {rss} exceeds {ceiling}')
        probe.report.setdefault('resources', {}).setdefault(name, {})[lane] = dict(records=len(rows), maximum_rss_bytes=rss)


def codec_name(probe):
    return probe.name


def main(codec, argv=None, description=None):
    memory = codec.memory
    options = tuple(f'SUPPORT_FILEFORMAT_{m}=ON' for m in ALIAS_MACROS)
    probe = probekit.Probe(f'{codec.name}-file', probekit.arguments(description or __doc__, argv=argv), raylib_options=options)
    if sys.byteorder != 'little':
        raise ProbeFailure('file probes require a little-endian host')
    cases, invalid = fixtures(codec), controls(codec)
    synthetic = [c for c in memory.controls() if any(v > 255 for v in c['bytes'])] if codec.synthetic else []
    stress = prepare(codec, probe.work, cases, invalid)
    # The directory control must fail at read (EISDIR) on this host, as the Bend runtime reports it.
    fd = os.open(ROOT / next(c['path'] for c in invalid if c.get('special') == 'directory'), os.O_RDONLY)
    try:
        os.read(fd, 1)
        raise ProbeFailure('directory fixture unexpectedly readable')
    except IsADirectoryError:
        pass
    finally:
        os.close(fd)
    if memory.qualification:
        if json.loads(probe.native(qualification_program(codec), 'qualification')) != memory.qualification[1]:
            raise ProbeFailure(f'{codec.name}: native build does not route this format as expected')
    heads = [dict(id=c['id'], role=r) for c in cases for r in ('raw', 'normalized')]
    text = probe.native_batches(lambda selected: reference_program(codec, selected), cases, batch=codec.batch,
                                source_limit=memory.source_limit)
    rows = codec_formats.parse_rows(text, heads)
    reference = {c['id']: (rows[2*i], rows[2*i+1]) for i, c in enumerate(cases)}
    stress_rows = codec_formats.parse_rows(probe.native(reference_program(codec, [stress]), 'exact-cap-reference'),
                                             [dict(id=stress['id'], role=r) for r in ('raw', 'normalized')])
    actions = expectations(codec, cases, invalid, reference, synthetic)
    lanes = probe.candidates(lambda selected, gpu: candidate_program(codec, selected), actions, batch=codec.batch,
                             source_limit=memory.source_limit,
                             parse=lambda out, selected: codec_formats.parse_rows(out, [a['expected'] for a in selected]))
    probe.compare([a['expected'] for a in actions], lanes, describe=lambda i: f'{actions[i]["case"]["id"]}/{actions[i]["role"]}')
    closure, closure_expected = boundary(codec, cases, invalid, reference)
    resource_run(probe, 'boundary', closure, closure_expected, MAX_SPARSE_RSS)
    sparse = [dict(case=c, role='formatted-error', expected=dict(id=c['id'], role='formatted-error', error=c['error']))
              for c in invalid if c.get('special') in ('sparse', 'large', 'overflow')]
    resource_run(probe, 'sparse', candidate_program(codec, sparse), [a['expected'] for a in sparse], MAX_SPARSE_RSS)
    exact = expectations(codec, [stress], [], {stress['id']: (stress_rows[0], stress_rows[1])})
    resource_run(probe, 'exact-cap', candidate_program(codec, exact), [a['expected'] for a in exact], MAX_STRESS_RSS)
    probe.finish(files=len(cases), file_controls=len(invalid), synthetic_controls=len(synthetic),
                 native_routes={r: sum(c['route'] == r for c in cases) for r in ('LoadImage', 'explicit')},
                 observations=len(actions), compared_bytes=sum(len(a['expected'].get('bytes', [])) for a in actions),
                 closure_records=len(closure_expected), reference_sha256=hashlib.sha256(text.encode()).hexdigest())
