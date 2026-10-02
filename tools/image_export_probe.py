#!/usr/bin/env python3
"""Compare Surface.write_image dispatch, complete files and ownership with raylib."""
import argparse
import errno
import hashlib
import json
from pathlib import Path
import resource
import signal
import subprocess

from bmp_probe import bend_bytes
from conformance import BUILD, ENV, ROOT, checkout, run, source_gate

CODECS = ('png', 'bmp', 'tga', 'qoi', 'raw')
CLOSURE_ITERATIONS = 100
SENTINEL = b'unchanged\x00image-export-sentinel\xff'


def limit_handles():
    resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))


def limit_write_failures():
    limit_handles()
    # Applied only to the child process. Pipes used for stdout/stderr are not
    # subject to RLIMIT_FSIZE, while every ordinary output file write is.
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    resource.setrlimit(resource.RLIMIT_FSIZE, (0, 0))


def prepare_write_failure_paths(directory):
    if directory.is_symlink():
        raise ValueError('Write-failure directory must be task-owned')
    directory.mkdir(parents=True, exist_ok=True)
    for codec in (*CODECS, 'data'):
        path = directory/('write-failure.'+codec)
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise ValueError('Write-failure fixture must be an ordinary file')
        path.write_bytes(SENTINEL)


def write_failure_marker():
    return dict(write_failure_checks=True, iterations=CLOSURE_ITERATIONS,
                writes=len(CODECS)*CLOSURE_ITERATIONS, rejections=CLOSURE_ITERATIONS,
                error_code=errno.EFBIG)


def verify_write_failures(directory, text):
    rows = [json.loads(line) for line in text.splitlines()]
    marker = write_failure_marker()
    if (len(rows) != 1 or not isinstance(rows[0], dict) or rows[0] != marker
            or any(type(rows[0][key]) is not type(value) for key, value in marker.items())):
        raise ValueError('Incomplete post-open image-export write-failure checks')
    for codec in CODECS:
        path = directory/('write-failure.'+codec)
        if path.is_symlink() or not path.is_file() or path.read_bytes() != b'':
            raise ValueError(f'Post-open {codec} write-failure fixture was not truncated')
    path = directory/'write-failure.data'
    if path.is_symlink() or not path.is_file() or path.read_bytes() != SENTINEL:
        raise ValueError('Post-open unsupported image-export sentinel changed')
    return marker


def fixtures():
    mixed = [0x01020300, 0x113fc980, 0xff7f80ff, 0xfefdfc01, 0x00ff007f, 0xff00ffff]
    images = [dict(id='single-hidden', width=1, height=1, pixels=mixed[:1]),
              dict(id='wide-alpha', width=3, height=2, pixels=mixed),
              dict(id='tall-alpha', width=2, height=3, pixels=list(reversed(mixed))),
              dict(id='hidden-rgb', width=3, height=2, pixels=[v & 0xffffff00 for v in mixed])]
    cases = []
    for codec in CODECS:
        for image in images:
            cases.append(dict(image, id=image['id']+'-'+codec, path=image['id']+'.'+codec,
                              codec=codec, status='ok', native=True))
        for variant, path in [('upper', 'upper.'+codec.upper()),
                              ('mixed', 'mixed.'+codec[0].upper()+codec[1]+codec[2].upper()),
                              ('multiple-dots', 'many.parts.'+codec.upper()),
                              ('qualified-dotfile', 'qualified/.'+codec)]:
            cases.append(dict(images[1], id=variant+'-'+codec, path=path,
                              codec=codec, status='ok', native=True))
    # Both repeated and literal TGA packets cross the 128-pixel boundary and rows.
    run_pixels = []
    for y in range(2):
        run_pixels += [0x11335500 | (y*255)]*128
        run_pixels += [((x*53 & 255)<<24) | ((x*97 & 255)<<16) | ((y*127)<<8) | (x & 255)
                       for x in range(128)]
        run_pixels += [run_pixels[-1]]
    cases.append(dict(id='tga-run-boundary', width=257, height=2, pixels=run_pixels,
                      path='run-boundary.TgA', codec='tga', status='ok', native=True))
    for codec in CODECS:
        for kind, path in [('missing-parent', 'missing-parent/output.'+codec),
                           ('directory', 'directory.'+codec)]:
            cases.append(dict(images[1], id=kind+'-'+codec, path=path, codec=codec,
                              status='file', native=True))
    unsupported = ['no-extension', 'bad.data', 'trailing.', '.png', '.RAW',
                   'folder.png/no-extension', 'last.png.data', 'bad.pngx', 'bad.pnG ',
                   'bad.ppm', 'bad.pgm', 'bad.jpg', 'bad.jpeg', 'bad.gif',
                   'bad.psd', 'bad.pic', 'bad.ktx', 'bad.pnＧ']
    for index, path in enumerate(unsupported):
        # JPG/JPEG and KTX are outside this scoped Surface contract, although
        # some native builds have exporters for them. Do not call those oracles.
        native = not path.endswith(('.jpg', '.jpeg', '.ktx'))
        cases.append(dict(images[1], id='unsupported-'+str(index), path=path,
                          codec=None, status='unsupported', native=native))
    # Unsupported dispatch must happen even when opening the path would fail.
    cases.append(dict(images[1], id='unsupported-missing-parent', path='missing-parent/output.data',
                      codec=None, status='unsupported', native=True))
    return cases


def rgba_bytes(case):
    return b''.join(value.to_bytes(4, 'big') for value in case['pixels'])


def prepare_paths(directory, cases):
    directory.mkdir(parents=True, exist_ok=True)
    if (directory/'missing-parent').exists():
        raise ValueError('Task-owned missing-parent fixture unexpectedly exists')
    for case in cases:
        path = directory/case['path']
        if case['path'].startswith('missing-parent/'):
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if case['status'] == 'file':
            path.mkdir(exist_ok=True)
            (path/'entry').write_bytes(SENTINEL)
        else:
            # A successful write must replace every old byte. A rejection must
            # leave every sentinel byte alone, including embedded zero/high bits.
            path.write_bytes(SENTINEL)
    for codec in CODECS:
        (directory/('closure.'+codec)).write_bytes(SENTINEL)
    (directory/'closure.data').write_bytes(SENTINEL)


def parse_rows(text, cases, *, candidate=False):
    rows = [json.loads(line) for line in text.splitlines()]
    wanted = len(cases) + int(candidate)
    if len(rows) != wanted:
        raise ValueError(f'Image-export result count differs: expected {wanted}, got {len(rows)}')
    for case, row in zip(cases, rows):
        if not isinstance(row, dict) or row.get('id') != case['id'] or row.get('status') != case['status']:
            raise ValueError(f'Image-export identity/status differs: {case["id"]}')
        status = case['status']
        keys = {'id', 'status'}
        if status == 'ok':
            keys.add('bytes')
            data = row.get('bytes')
            if not isinstance(data, list) or not data or any(type(v) is not int or not 0 <= v <= 255 for v in data):
                raise ValueError(f'Invalid image-export bytes: {case["id"]}')
            if case['codec'] == 'raw' and bytes(data) != rgba_bytes(case):
                raise ValueError(f'RAW bytes differ: {case["id"]}')
        if status == 'unsupported' or (status == 'ok' and case['codec'] != 'raw'):
            keys.update(('width', 'height', 'pixels'))
            if (type(row.get('width')) is not int or type(row.get('height')) is not int
                    or row['width'] != case['width'] or row['height'] != case['height']):
                raise ValueError(f'Image-export dimensions differ: {case["id"]}')
            pixels = row.get('pixels')
            if (not isinstance(pixels, list) or len(pixels) != case['width']*case['height']
                    or any(type(v) is not int or not 0 <= v <= 0xffffffff for v in pixels)):
                raise ValueError(f'Invalid image-export pixels: {case["id"]}')
            # PNG/TGA/QOI and returned owners retain hidden RGB and alpha. BMP
            # is checked against the complete native decode, including its alpha
            # interpretation; never paper over a difference with an alpha mask.
            if (status == 'unsupported' or case['codec'] != 'bmp') and pixels != case['pixels']:
                raise ValueError(f'Image-export pixels/owner differ: {case["id"]}')
        if status == 'file' and candidate:
            keys.update(('code', 'message_empty'))
            if (type(row.get('code')) is not int or not 0 < row['code'] <= 0xffffffff
                    or type(row.get('message_empty')) is not int or row['message_empty'] != 0):
                raise ValueError(f'Invalid image-export file error: {case["id"]}')
        if set(row) != keys:
            raise ValueError(f'Unexpected image-export result fields: {case["id"]}')
    if candidate:
        closure = rows[-1]
        if (closure != {'closure_checks': True, 'iterations': CLOSURE_ITERATIONS}
                or type(closure.get('closure_checks')) is not bool
                or type(closure.get('iterations')) is not int):
            raise ValueError('Incomplete image-export closure checks')
    return rows


def verify_files(directory, cases, rows):
    if not cases or len(rows) not in (len(cases), len(cases)+1):
        raise ValueError('Image-export file result count differs')
    for case, row in zip(cases, rows):
        path = directory/case['path']
        if case['status'] == 'ok':
            if not path.is_file() or path.read_bytes() != bytes(row['bytes']):
                raise ValueError(f'Complete image-export file differs: {case["id"]}')
        elif case['path'].startswith('missing-parent/'):
            if (directory/'missing-parent').exists():
                raise ValueError('Image export unexpectedly created missing parent')
        elif case['status'] == 'unsupported':
            if not path.is_file() or path.read_bytes() != SENTINEL:
                raise ValueError(f'Rejected image-export sentinel changed: {case["id"]}')
        elif not path.is_dir() or (path/'entry').read_bytes() != SENTINEL:
            raise ValueError(f'Image-export directory control changed: {case["id"]}')
    if (directory/'closure.data').read_bytes() != SENTINEL:
        raise ValueError('Rejected image-export closure sentinel changed')


def verify_closure_files(directory, reference):
    if set(reference) != set(CODECS):
        raise ValueError('Incomplete image-export closure reference')
    for codec in CODECS:
        path = directory/('closure.'+codec)
        if not path.is_file() or path.read_bytes() != bytes(reference[codec]):
            raise ValueError(f'Complete image-export closure file differs: {codec}')


def compare_rows(cases, expected, actual):
    if len(actual) != len(cases)+1 or len(expected) != len(cases):
        raise ValueError('Image-export comparison result count differs')
    for case, wanted, got in zip(cases, expected, actual):
        normalized = {key: value for key, value in got.items() if key not in ('code', 'message_empty')}
        if normalized != wanted:
            raise ValueError(f'Native image-export bytes/pixels/dispatch differ: {case["id"]}')


def reference_program(cases):
    lines = ['#include "raylib.h"', '#include <stdio.h>',
             'static void pixels(Image image){Color *p=LoadImageColors(image);',
             'printf(",\\"width\\":%d,\\"height\\":%d,\\"pixels\\":[",image.width,image.height);',
             'for(int i=0;i<image.width*image.height;i++)printf("%s%u",i?",":"",(unsigned)ColorToInt(p[i]));',
             'putchar(\']\');UnloadImageColors(p);}',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in cases:
        path = json.dumps(case['path'], ensure_ascii=False)
        lines += ['{', f'Image image=GenImageColor({case["width"]},{case["height"]},BLANK);',
                  'unsigned colors[]={'+','.join(str(v)+'u' for v in case['pixels'])+'};',
                  f'for(int i=0;i<{len(case["pixels"])};i++)((Color*)image.data)[i]=GetColor(colors[i]);',
                  f'int wrote=ExportImage(image,{path});',
                  f'printf("{{\\"id\\":\\"{case["id"]}\\",\\"status\\":\\"%s\\"",wrote?"ok":"{case["status"]}");']
        if case['status'] == 'ok':
            lines += ['if(!wrote)return 2;int n=0;', f'unsigned char *data=LoadFileData({path},&n);if(!data||n<=0)return 3;',
                      'printf(",\\"bytes\\":[");for(int i=0;i<n;i++)printf("%s%u",i?",":"",data[i]);putchar(\']\');']
            if case['codec'] != 'raw':
                lines += [f'Image decoded=LoadImageFromMemory(".{case["codec"]}",data,n);if(!decoded.data)return 4;',
                          'pixels(decoded);UnloadImage(decoded);']
            lines += ['UnloadFileData(data);']
        elif case['status'] == 'unsupported':
            lines += ['if(wrote)return 5;pixels(image);']
        else:
            lines += ['if(wrote)return 6;']
        lines += ['puts("}");UnloadImage(image);}']
    return '\n'.join(lines+['}'])+'\n'


BEND_PROGRAM = '''import Base
import ../../jonlib.bend as J
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def surface(result: Maybe<J.Image.Formatted>) -> J.Surface:
  match result:
    case Some{image}: J.Image.Formatted.to_surface(image)
    case None{}: J.Surface{1, 1, Array.new(U32, 0n, 0)}
def small() -> J.Surface:
  surface(J.Image.Formatted.from_bytes(1, 1, 7, [1, 2, 3, 0]))
def emit_surface(prefix: String, owner: J.Surface) -> IO(Unit):
  J.Surface{+width, +height, pixels} = owner
  IO.print(prefix ++ ",\\"width\\":" ++ U32.show(width) ++ ",\\"height\\":" ++ U32.show(height) ++ ",\\"pixels\\":" ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{width, height, pixels})) ++ "}")
def decoded(prefix: String, result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "image-export round trip failed")
    case Done{owner}: emit_surface(prefix, owner)
def payload_decoded(kind: U32, prefix: String, bytes: +List<U32>) -> IO(Unit):
  match kind:
    case 1: decoded(prefix, J.Surface.decode_png(bytes))
    case 2: decoded(prefix, J.Surface.decode_bmp(bytes))
    case 3: decoded(prefix, J.Surface.decode_tga(bytes))
    case 4: decoded(prefix, J.Surface.decode_qoi(bytes))
    case _: IO.print(prefix ++ "}")
def payload(id: String, kind: U32, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "image-export file read failed")
    case Done{+bytes}:
      prefix = "{\\"id\\":\\"" ++ id ++ "\\",\\"status\\":\\"ok\\",\\"bytes\\":" ++ List.show(~&2, ~U32, ~U32.show, bytes)
      payload_decoded(kind, prefix, bytes)
def received(id: String, kind: U32, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(id, kind, status)
def opened(id: String, kind: U32, size: U32, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "image-export file reopen failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(id, kind))
def written(id: String, path: String, kind: U32, size: U32, result: Result<&1, &1, J.Image.ExportError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(path, "r"), opened(id, kind, size))
    case Fail{J.UnsupportedImageExport{owner}}: emit_surface("{\\"id\\":\\"" ++ id ++ "\\",\\"status\\":\\"unsupported\\"", owner)
    case Fail{J.ImageExportFileError{code, message}}: IO.print("{\\"id\\":\\"" ++ id ++ "\\",\\"status\\":\\"file\\",\\"code\\":" ++ U32.show(code) ++ ",\\"message_empty\\":" ++ U32.show(Bool.to_u32(String.eq(message, ""))) ++ "}")
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "image-export closure status/owner differs")
def owner_pixel(pixels: List<U32>) -> Bool:
  match pixels:
    case Con{color, Nil{}}: U32.is_eq(color, 16909056)
    case _: False{}
def owner_valid(owner: J.Surface) -> Bool:
  J.Surface{+width, +height, pixels} = owner
  U32.is_eq(width, 1) && U32.is_eq(height, 1) && owner_pixel(J.Surface.colors(J.Surface{width, height, pixels}))
def required(expected: U32, result: Result<&1, &1, J.Image.ExportError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: checked(U32.is_eq(expected, 0))
    case Fail{J.UnsupportedImageExport{owner}}: checked(U32.is_eq(expected, 1) && owner_valid(owner))
    case Fail{J.ImageExportFileError{code, message}}: checked(U32.is_eq(expected, 2) && U32.is_gt(code, 0) && Bool.not(String.eq(message, "")))
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"closure_checks\\":true,\\"iterations\\":100}")
    case 1n+rest:
      do IO<Unit>:
CLOSURE_BODY
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def candidate_program(cases, expected):
    closure = []
    for codec in CODECS:
        for path, status in [('closure.'+codec, 0), ('directory.'+codec, 2), ('missing-parent/output.'+codec, 2)]:
            closure.append(f'        IO.bind(Result<&1, &1, J.Image.ExportError, Unit>, Unit, J.Surface.write_image(small(), {json.dumps(path)}), required({status}))')
    closure.append('        IO.bind(Result<&1, &1, J.Image.ExportError, Unit>, Unit, J.Surface.write_image(small(), "closure.data"), required(1))')
    program = BEND_PROGRAM.replace('CLOSURE_BODY', '\n'.join(closure))
    for case, row in zip(cases, expected):
        kind = CODECS.index(case['codec'])+1 if case['codec'] else 0
        owner = f'surface(J.Image.Formatted.from_bytes({case["width"]}, {case["height"]}, 7, {bend_bytes(list(rgba_bytes(case)))}))'
        path = json.dumps(case['path'], ensure_ascii=False)
        program += f'    IO.bind(Result<&1, &1, J.Image.ExportError, Unit>, Unit, J.Surface.write_image({owner}, {path}), written({json.dumps(case["id"])}, {path}, {kind}, {len(row.get("bytes", []))+1}))\n'
    return program+f'    closure_loop({CLOSURE_ITERATIONS}n)\n'


def write_failure_program():
    # Reuse the ownership checks but give this process a dedicated main. The
    # exact EFBIG requirement rejects EMFILE/other errors caused by leaked FDs.
    program = BEND_PROGRAM[:BEND_PROGRAM.index('def closure_loop(')]
    program += '''def write_failure_required(result: Result<&1, &1, J.Image.ExportError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.ImageExportFileError{code, message}}: checked(U32.is_eq(code, ERROR_CODE) && Bool.not(String.eq(message, "")))
    case _: IO.die(Unit, 1, "expected post-open image-export write failure")
def write_failure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print(MARKER)
    case 1n+rest:
      do IO<Unit>:
'''.replace('ERROR_CODE', str(errno.EFBIG)).replace('MARKER', json.dumps(json.dumps(write_failure_marker())))
    for codec in CODECS:
        program += f'        IO.bind(Result<&1, &1, J.Image.ExportError, Unit>, Unit, J.Surface.write_image(small(), "write-failure.{codec}"), write_failure_required)\n'
    program += '''        IO.bind(Result<&1, &1, J.Image.ExportError, Unit>, Unit, J.Surface.write_image(small(), "write-failure.data"), required(1))
        write_failure_loop(rest)
def main() -> IO(Unit):
'''
    return program+f'  write_failure_loop({CLOSURE_ITERATIONS}n)\n'


def run_write_failure_lane(args, work, lane):
    directory = work/(lane+'-write-failure-files')
    prepare_write_failure_paths(directory)
    source = work/'write-failure.bend'
    source.write_text(write_failure_program())
    binary = work/('write-failure.js' if lane=='javascript' else 'write-failure-cpu')
    run(['bun', args.bend_source/'bend2/main.ts', source, '-o', binary], timeout=600)
    command = ['bun', binary] if lane=='javascript' else [binary]
    process = subprocess.run(list(map(str, command)), cwd=directory, env=ENV, capture_output=True,
                             text=True, timeout=240, preexec_fn=limit_write_failures)
    if process.returncode:
        raise RuntimeError(f'{lane}: post-open image-export write-failure run failed\n{process.stderr[-2000:]}')
    marker = verify_write_failures(directory, process.stdout)
    return dict(passed=True, **marker, file_size_limit=0, file_descriptor_limit=64,
                signal_xfsz='ignored', program_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                stdout_sha256=hashlib.sha256(process.stdout.encode()).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--raylib-source', type=Path, required=True)
    args = parser.parse_args()
    work = BUILD/'image-export-probe'
    work.mkdir(parents=True, exist_ok=True)
    report_path = work/'results.json'
    # Invalidate an earlier pass before provenance checks or any external command.
    report_path.write_text(json.dumps(dict(passed=False))+'\n')
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
    checkout(args.raylib_source, lock['raylib']['revision'])
    cases = fixtures()
    if not cases or len({case['id'] for case in cases}) != len(cases):
        raise ValueError('Empty or duplicate image-export fixture set')
    native_cases = [case for case in cases if case['native']]
    reference_directory = work/'native-files'
    prepare_paths(reference_directory, native_cases)
    source = work/'reference.c'
    source.write_text(reference_program(native_cases))
    binary = work/'reference'
    run(['clang', '-std=c11', '-O2', '-I'+str(args.raylib_source/'src'), source,
         BUILD/'raylib/raylib/libraylib.a', '-lm', '-o', binary])
    reference_text = run([binary], cwd=reference_directory)
    reference = parse_rows(reference_text, native_cases)
    verify_files(reference_directory, native_cases, reference)
    reference_by_id = {row['id']: row for row in reference}
    closure_reference = {codec: reference_by_id['single-hidden-'+codec]['bytes'] for codec in CODECS}
    expected = [reference_by_id[case['id']] if case['native'] else
                dict(id=case['id'], status='unsupported', width=case['width'], height=case['height'], pixels=case['pixels'])
                for case in cases]
    report = dict(passed=False, cases=len(cases), reference_cases=len(native_cases),
                  export_cases=sum(case['status']=='ok' for case in cases),
                  rejected_owner_controls=sum(case['status']=='unsupported' for case in cases),
                  io_error_controls=sum(case['status']=='file' for case in cases),
                  post_open_write_error_controls=len(CODECS),
                  encoded_bytes=sum(len(row.get('bytes', [])) for row in reference),
                  roundtrip_pixels=sum(len(row.get('pixels', [])) for case, row in zip(native_cases, reference) if case['status']=='ok'),
                  closure_iterations=CLOSURE_ITERATIONS, closure_operations_per_iteration=len(CODECS)*3+1,
                  file_descriptor_limit=64, sources=source_gate(),
                  harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  inputs_sha256=hashlib.sha256(json.dumps(cases, sort_keys=True).encode()).hexdigest(),
                  reference_sha256=hashlib.sha256(reference_text.encode()).hexdigest(),
                  reference_program_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), lanes={})
    report_path.write_text(json.dumps(report, indent=2)+'\n')
    source = work/'candidate.bend'
    source.write_text(candidate_program(cases, expected))
    report['candidate_program_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
    for lane in ('cpu', 'javascript'):
        report['lanes'][lane] = dict(passed=False)
        report_path.write_text(json.dumps(report, indent=2)+'\n')
        directory = work/(lane+'-files')
        prepare_paths(directory, cases)
        binary = work/('candidate.js' if lane=='javascript' else 'candidate-cpu')
        run(['bun', args.bend_source/'bend2/main.ts', source, '-o', binary], timeout=600)
        command = ['bun', binary] if lane=='javascript' else [binary]
        process = subprocess.run(list(map(str, command)), cwd=directory, env=ENV, capture_output=True,
                                 text=True, timeout=240, preexec_fn=limit_handles)
        if process.returncode:
            raise RuntimeError(f'{lane}: image-export run failed\n{process.stderr[-2000:]}')
        actual = parse_rows(process.stdout, cases, candidate=True)
        compare_rows(cases, expected, actual)
        verify_files(directory, cases, actual)
        verify_closure_files(directory, closure_reference)
        # This is a mandatory second CPU/JS execution. No lane passes if its
        # post-open failures, repeated descriptor closure, or sentinels differ.
        write_failures = run_write_failure_lane(args, work, lane)
        report['lanes'][lane] = dict(passed=True, result_rows=len(actual),
                                    post_open_write_failures=write_failures,
                                    stdout_sha256=hashlib.sha256(process.stdout.encode()).hexdigest())
        report_path.write_text(json.dumps(report, indent=2)+'\n')
        print(f'{lane}: {report["export_cases"]} complete native image files, {report["rejected_owner_controls"]} retained-owner rejections, '
              f'{report["io_error_controls"]} open errors, {write_failures["writes"]} post-open write errors and '
              f'{CLOSURE_ITERATIONS} low-descriptor cycles passed', flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
