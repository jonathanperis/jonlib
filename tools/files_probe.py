#!/usr/bin/env python3
"""Compare rcore.c path and file-data utilities with Jonlib's Files functions.

Pure path functions run over a corpus of drive, root, relative, dotted and long
paths; inputs where raylib's static buffers would overflow or read past the
string (empty or overlong paths, file extensions of 16+ bytes) are Jonlib
None contracts and are not run natively. File cases write the same fixtures,
then compare existence, length, loaded data/text, text search, and files each
side saves (data, text, data-as-code) read back byte for byte, and
FileTextReplace on fresh copies of text fixtures (its result and the
rewritten file). CPU and JavaScript lanes; no GPU claim.
"""
import hashlib
import json
import random

from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
import probekit
from probekit import ROOT, ProbeFailure

PATHS = ['', '.', '..', 'a', 'ab', 'abc', 'abcd', 'a.b', '.hidden', 'file.png', 'dir/file.png', 'dir.d/file',
         'dir.d/file.tar.gz', 'C:\\x\\y.txt', 'C:file.txt', 'C:\\', 'C:\\a', 'C:\\a\\b', '/', '/ab', '/abs',
         '/abs/path/', '/abc/d', '\\', 'a/b/c/', 'a\\b', 'x.', 'noext/', './rel/x.y', '../up.png', 'a/b.c/d',
         'dir/.git', '/a.b', 'a/.b.c', 'name.with.many.dots', 'd/' + 'n' * 300 + '.ext', 'p' * 4093,
         'p' * 4094, '/' + 'q' * 4095, 'r' * 4096 + '/s']
EXTENSIONS = [('image.PNG', '.png;.jpg'), ('a.png', 'png'), ('a.png', '.PNG'), ('a', '.png'), ('a.tar.gz', '.gz'),
              ('a.tar.gz', '.tar.gz'), ('.png', '.png'), ('x.', ''), ('x.', '.'), ('x.y', ';.y'), ('x.y', 'Y'),
              ('dir.d/file', '.d/file'), ('x.abcdefghijklmn', '.ABCDEFGHIJKLMN'), ('x.abcdefghijklmno', '.abcdefghijklmno'),
              ('a.e30', ';'.join(f'.e{i}' for i in range(40))), ('a.e31', ';'.join(f'.e{i}' for i in range(40))),
              ('a.e32', ';'.join(f'.e{i}' for i in range(40)))]
NAMES = ['', 'a', 'a.txt', '...', '.', '..', '. .', 'a<b', 'a>b', 'a:b', 'a"b', 'a/b', 'a\\b', 'a|b', 'a?b', 'a*b',
         'a\tb', 'a\x01b', 'CON', ' ', 'a b', 'end.']
SEARCHES = ['', 'abc', 'zz', 'tail', 'x']


def c_string(text):
    return '"' + ''.join(c if 32 <= ord(c) < 127 and c not in '"\\?' else f'\\{ord(c):03o}' for c in text) + '"'


def bend_string(text):
    """Runs of 8+ equal characters use String.repeat (long literals exhaust the JS stack)."""
    pieces, i = [], 0
    while i < len(text):
        j = i
        while j < len(text) and text[j] == text[i]:
            j += 1
        if j - i >= 8:
            pieces.append(f'String.repeat(Files.chars([{ord(text[i])}]), {j - i}n)')
        else:
            pieces.append('Files.chars([' + ','.join(str(ord(c)) for c in text[i:j]) + '])')
        i = j
    return '(' + ' ++ '.join(pieces or ['""']) + ')'


def directory_defined(path):
    return 1 <= len(path) <= 4093


def extension_of(path):
    dot = path.rfind('.')
    return None if dot <= 0 else path[dot:]


def extension_defined(path):
    ext = extension_of(path)
    return ext is None or len(ext) < 16


def actions(work):
    rng = random.Random(0xF11E5)
    data = bytes(rng.randrange(256) for _ in range(300)) + b'\0' + b'tail'
    text = b'hello abc world\0tail after nul x'
    files = {'data.bin': data, 'empty.bin': b'', 'text.txt': text}
    for name, payload in files.items():
        (work / name).write_bytes(payload)
    (work / 'c').mkdir(exist_ok=True)
    (work / 'bend').mkdir(exist_ok=True)
    rel = lambda name: str((work / name).relative_to(ROOT))
    out = []
    for path in PATHS:
        out += [('extension', path), ('name', path), ('stem', path), ('directory', path), ('previous', path)]
    out += [('has-extension', pair) for pair in EXTENSIONS]
    out += [('valid-name', name) for name in NAMES]
    out.append(('exists', str(work.relative_to(ROOT))))
    for name in ('data.bin', 'empty.bin', 'text.txt', 'missing.bin'):
        out += [('exists', rel(name)), ('length', rel(name))]
    for name in ('data.bin', 'empty.bin', 'text.txt', 'missing.bin'):
        out += [('load-data', rel(name)), ('load-text', rel(name))]
    out += [('find', (rel('text.txt'), search)) for search in SEARCHES]
    out += [('find', (rel('missing.bin'), 'abc')), ('find', (rel('empty.bin'), 'abc'))]
    out += [('save-data', ('saved.bin', list(data[:40]))), ('save-text', ('saved.txt', 'line one\nsecond\0hidden')),
            ('export-code', ('my-data.v2+x.h', list(data[:47])))]
    # FileTextReplace on a fresh copy of a fixture (None: the file is missing):
    # (copy name, fixture bytes, search, replacement).
    replaced = b'abc abcabc ab\nabc\0abc after'
    out += [('replace', (f'replace-{i}.txt', list(fixture) if fixture is not None else None, search, replacement))
            for i, (fixture, search, replacement) in enumerate([
                (replaced, 'abc', 'XYZW'), (replaced, 'abc', ''), (replaced, 'c a', 'Q'), (replaced, 'zz', 'never'),
                (text, 'o', '00'), (replaced, 'abc', 'abc'), (None, 'abc', 'x'), (b'', 'abc', 'x'), (replaced, '', 'x')])]
    return out


def defined(kind, arg):
    if kind == 'directory':
        return directory_defined(arg)
    if kind == 'previous':
        return len(arg) <= 4096
    if kind == 'has-extension':
        return extension_defined(arg[0])
    if kind == 'find':
        # raylib would strstr() through the NULL text of an empty file.
        return not arg[0].endswith('empty.bin')
    if kind == 'replace':
        # An empty file (LoadFileText's NULL) or an empty search (TextReplaceAlloc's
        # NULL) would reach fprintf("%s", NULL).
        _, fixture, search, _ = arg
        return fixture is None or (len(fixture) > 0 and search != '')
    return True


NATIVE_HELPERS = r'''
static void text(const char *s){if(!s){puts("null");return;}for(const char*p=s;*p;p++)byte((unsigned char)*p);end();}
static void flag(int b){byte(b?1:0);end();}
static void bytes(const unsigned char *d,int n,int present){if(!present){puts("null");return;}for(int i=0;i<n;i++)byte(d[i]);end();}
static void readback(const char *path,int ok){int n=0;unsigned char *d=LoadFileData(path,&n);byte(ok?1:0);for(int i=0;i<n;i++)byte(d[i]);end();UnloadFileData(d);}
'''


def native_source(acts, work):
    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <string.h>', C_EMITTER, NATIVE_HELPERS,
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    rel = lambda name: c_string(str((work / name).relative_to(ROOT)))
    for kind, arg in acts:
        if not defined(kind, arg):
            continue
        if kind == 'extension':
            lines.append(f'text(GetFileExtension({c_string(arg)}));')
        elif kind == 'name':
            lines.append(f'text(GetFileName({c_string(arg)}));')
        elif kind == 'stem':
            lines.append(f'text(GetFileNameWithoutExt({c_string(arg)}));')
        elif kind == 'directory':
            lines.append(f'text(GetDirectoryPath({c_string(arg)}));')
        elif kind == 'previous':
            lines.append(f'text(GetPrevDirectoryPath({c_string(arg)}));')
        elif kind == 'has-extension':
            lines.append(f'flag(IsFileExtension({c_string(arg[0])},{c_string(arg[1])}));')
        elif kind == 'valid-name':
            lines.append(f'flag(IsFileNameValid({c_string(arg)}));')
        elif kind == 'exists':
            lines.append(f'flag(FileExists({c_string(arg)}));')
        elif kind == 'length':
            lines.append(f'word(GetFileLength({c_string(arg)}));end();')
        elif kind == 'load-data':
            # An existing empty file loads as no bytes (raylib: NULL with dataSize 0).
            lines.append(f'{{int n=0;unsigned char *d=LoadFileData({c_string(arg)},&n);bytes(d,n,d||FileExists({c_string(arg)}));UnloadFileData(d);}}')
        elif kind == 'load-text':
            lines.append(f'{{char *t=LoadFileText({c_string(arg)});int n=GetFileLength({c_string(arg)});'
                         f'bytes((unsigned char*)t,t?n:0,t||FileExists({c_string(arg)}));UnloadFileText(t);}}')
        elif kind == 'find':
            path, search = arg
            lines.append(f'{{int i=FileTextFindIndex({c_string(path)},{c_string(search)});if(i<0)puts("null");else{{word(i);end();}}}}')
        elif kind == 'save-data':
            name, data = arg
            lines.append(f'{{static unsigned char d[]={{{",".join(map(str, data))}}};readback({rel("c/" + name)},SaveFileData({rel("c/" + name)},d,sizeof d));}}')
        elif kind == 'save-text':
            name, value = arg
            lines.append(f'readback({rel("c/" + name)},SaveFileText({rel("c/" + name)},{c_string(value)}));')
        elif kind == 'export-code':
            name, data = arg
            lines.append(f'{{static unsigned char d[]={{{",".join(map(str, data))}}};readback({rel("c/" + name)},ExportDataAsCode(d,sizeof d,{rel("c/" + name)}));}}')
        elif kind == 'replace':
            # One result: the int FileTextReplace returns, then the file's bytes.
            name, fixture, search, replacement = arg
            path = rel('c/' + name)
            setup = '' if fixture is None else f'{{static unsigned char d[]={{{",".join(map(str, fixture or [0]))}}};SaveFileData({path},d,{len(fixture)});}}'
            lines.append(f'{setup}{{int r=FileTextReplace({path},{c_string(search)},{c_string(replacement)});int n=0;'
                         f'unsigned char *d=LoadFileData({path},&n);word(r);for(int i=0;i<n;i++)byte(d[i]);end();UnloadFileData(d);}}')
    return '\n'.join(lines + ['return 0;}']) + '\n'


PROGRAM = '''import Base
import ../../jonlib.bend as J
''' + BEND_EMITTER + '''def Files.chars(codes: List<U32>) -> String:
  match codes:
    case Nil{}: ""
    case Con{code, rest}: SCon{Char.from_u32(code), Files.chars(rest)}
def codes(text: String) -> List<U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{character, rest}: Con{Char.to_u32(character), codes(rest)}
def text(value: String) -> IO(Unit):
  emit_bytes(~&1, codes(value))
def maybe_text(value: Maybe<String>) -> IO(Unit):
  match value:
    case None{}: IO.print("null")
    case Some{found}: text(found)
def flag(value: Bool) -> IO(Unit):
  emit_bytes(~&1, [Bool.to_u32(value)])
def maybe_flag(value: Maybe<Bool>) -> IO(Unit):
  match value:
    case None{}: IO.print("null")
    case Some{found}: flag(found)
def word_bytes(+value: U32) -> List<U32>:
  [(value .&. 255 : U32), ((value >> 8n) .&. 255 : U32), ((value >> 16n) .&. 255 : U32), (value >> 24n : U32)]
def word(value: U32) -> IO(Unit):
  emit_bytes(~&1, word_bytes(value))
def maybe_word(value: Maybe<U32>) -> IO(Unit):
  match value:
    case None{}: IO.print("null")
    case Some{found}: word(found)
def data(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{bytes}: emit_bytes(~&2, bytes)
def loaded_text(result: Result<&1, &1, J.Surface.IOError, String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{value}: text(value)
def readback.bytes(ok: Bool, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: emit_bytes(~&1, [Bool.to_u32(ok)])
    case Done{bytes}: emit_bytes(~&2, Con{Bool.to_u32(ok), bytes})
def readback.ok(saved: Result<&1, &1, J.Surface.IOError, Unit>) -> Bool:
  match saved:
    case Fail{_}: False{}
    case Done{_}: True{}
def readback(path: String, saved: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data(path), readback.bytes(readback.ok(saved)))
def replaced.bytes(+r: U32, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: emit_bytes(~&1, word_bytes(r))
    case Done{bytes}: emit_bytes(~&2, Con{(r .&. 255 : U32), Con{((r >> 8n) .&. 255 : U32), Con{((r >> 16n) .&. 255 : U32), Con{(r >> 24n : U32), bytes}}}})
def replaced(path: String, result: Maybe<U32>) -> IO(Unit):
  match result:
    case None{}: IO.print("null")
    case Some{+r}: IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data(path), replaced.bytes(r))
'''


def render(acts, work):
    rel = lambda name: json.dumps(str((work / name).relative_to(ROOT)))
    def emit(selected, gpu):
        body = PROGRAM + 'def main() -> IO(Unit):\n  do IO<Unit>:\n'
        for kind, arg in selected:
            if kind == 'extension':
                line = f'maybe_text(J.Files.extension({bend_string(arg)}))'
            elif kind == 'name':
                line = f'text(J.Files.name({bend_string(arg)}))'
            elif kind == 'stem':
                line = f'text(J.Files.name_without_ext({bend_string(arg)}))'
            elif kind == 'directory':
                line = f'maybe_text(J.Files.directory({bend_string(arg)}))'
            elif kind == 'previous':
                line = f'maybe_text(J.Files.previous_directory({bend_string(arg)}))'
            elif kind == 'has-extension':
                line = f'maybe_flag(J.Files.has_extension({bend_string(arg[0])}, {bend_string(arg[1])}))'
            elif kind == 'valid-name':
                line = f'flag(J.Files.valid_name({bend_string(arg)}))'
            elif kind == 'exists':
                line = f'IO.bind(Bool, Unit, J.Files.exists({json.dumps(arg)}), flag)'
            elif kind == 'length':
                line = f'IO.bind(U32, Unit, J.Files.length({json.dumps(arg)}), word)'
            elif kind == 'load-data':
                line = f'IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(arg)}), data)'
            elif kind == 'load-text':
                line = f'IO.bind(Result<&1, &1, J.Surface.IOError, String>, Unit, J.Files.load_text({json.dumps(arg)}), loaded_text)'
            elif kind == 'find':
                path, search = arg
                line = f'IO.bind(Maybe<U32>, Unit, J.Files.text_find_index({json.dumps(path)}, {bend_string(search)}), maybe_word)'
            elif kind == 'save-data':
                name, values = arg
                line = (f'IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Files.save_data({rel("bend/" + name)}, '
                        f'[{",".join(map(str, values))}]), readback({rel("bend/" + name)}))')
            elif kind == 'save-text':
                name, value = arg
                line = (f'IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Files.save_text({rel("bend/" + name)}, '
                        f'{bend_string(value)}), readback({rel("bend/" + name)}))')
            elif kind == 'replace':
                name, fixture, search, replacement = arg
                path = rel('bend/' + name)
                replace = (f'IO.bind(Maybe<U32>, Unit, J.Files.text_replace({path}, {bend_string(search)}, {bend_string(replacement)}), '
                           f'replaced({path}))')
                line = replace if fixture is None else (f'IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, '
                                                        f'J.Files.save_data({path}, [{",".join(map(str, fixture))}]), u => {replace})')
            else:
                name, values = arg
                line = (f'IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Files.export_data_as_code([{",".join(map(str, values))}], '
                        f'{rel("bend/" + name)}), readback({rel("bend/" + name)}))')
            body += '    ' + line + '\n'
        return body
    return emit


def main():
    probe = probekit.Probe('files', probekit.arguments(__doc__))
    work = probe.work
    acts = actions(work)
    observed = iter(parse_results(probe.native(native_source(acts, work))))
    expected = []
    for kind, arg in acts:
        expected.append(next(observed) if defined(kind, arg) else None)
    if next(observed, 'done') != 'done':
        raise ProbeFailure('files: unexpected native rows')
    lanes = probe.candidates(render(acts, work), acts, batch=len(acts), parse=lambda text, selected: parse_results(text))
    lanes = {name: rows for name, rows in lanes.items() if name != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'{acts[i][0]} {str(acts[i][1])[:60]!r}')
    probe.finish(cases=len(acts), contracts=sum(not defined(k, a) for k, a in acts),
                 inputs_sha256=hashlib.sha256(json.dumps(acts).encode()).hexdigest())


if __name__ == '__main__':
    main()
