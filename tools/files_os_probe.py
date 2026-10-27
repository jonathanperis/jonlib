#!/usr/bin/env python3
"""Compare rcore.c's file-system functions with Jonlib's, over a tree each side gets afresh.

FileExists, IsPathFile, DirectoryExists, GetFileModTime, GetDirectoryFileCount(Ex),
LoadDirectoryFiles(Ex) and UnloadDirectoryFiles, FileRename, FileRemove, FileCopy,
FileMove, MakeDirectory, ChangeDirectory, GetWorkingDirectory,
GetApplicationDirectory and OpenURL, through Jonlib's Files.* and System.open_url
on Bend Base's Path, Dir and Process effects (patches/bend-os-effects.patch).

The reference is the linked raylib (PLATFORM_MEMORY). Python builds the same tree
before the reference runs and before each candidate lane does: regular files of
several extensions (one upper-case), an empty file, a link and a dangling one, a
file without permissions and a directory without them (DirectoryExists cannot open
it), nested directories, a file with a 17-byte extension (raylib 6.2's
IsFileExtension keeps 15 bytes), a chain of directories whose deepest entries are 4096 bytes and
more from the root (raylib skips them) and one whose entry is exactly 4095 bytes
(snprintf cuts it to 4094), with fixed modification times; directories are
made in the same order, so readdir gives the same order on every side. Then one
script runs in order: the queries, the listings with every filter tag and
extension lists, with and without subdirectories, the renames, removals,
directories made, copies and moves (with raylib's results, among them FileMove's
-1 after a successful copy, which leaves the source), OpenURL through a fake
`explorer` first on PATH that logs its arguments (the reference platform runs
explorer "url"), and last ChangeDirectory and GetWorkingDirectory. Files the
script writes are read back on each side. GetApplicationDirectory differs by
lane (the reference, the native candidate and the JavaScript one are different
programs): each side answers whether it ends with '/' and is a directory.
LoadDirectoryFiles and GetDirectoryFileCount use the *.* filter, which never
calls IsFileExtension, so the 17-byte name is listed in full; a `.png` filter
compares its first 15 bytes. CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import os
import shutil
import stat

import probekit
from probekit import ROOT, ProbeFailure

TIME = 1700000000
LONG_NAME = 250


def c_string(text):
    return '"' + ''.join(c if 32 <= ord(c) < 127 and c not in '"\\?' else f'\\{ord(c):03o}' for c in text) + '"'


def bend_string(text):
    return 'chars([' + ', '.join(str(ord(c)) for c in text) + '])'


def chain(fd, names):
    """Directories nested by name under the directory fd, made through file descriptors (the paths pass PATH_MAX)."""
    for name in names:
        os.mkdir(name, dir_fd=fd)
        inner = os.open(name, os.O_RDONLY | os.O_DIRECTORY, dir_fd=fd)
        if fd >= 0:
            os.close(fd)
        fd = inner
    return fd


def chain_names(base_length, target, exact):
    """Names of LONG_NAME bytes (the last shortened) so the deepest entry's path is `target` bytes; with `exact` no other
    entry is 4095 bytes either way."""
    names, length = [], base_length
    while length + 1 + LONG_NAME < target:
        names.append('d' * LONG_NAME)
        length += 1 + LONG_NAME
    names.append('e' * (target - length - 1))
    lengths = [base_length + sum(1 + len(n) for n in names[:i + 1]) for i in range(len(names))]
    if not exact and 4095 in lengths:
        raise ProbeFailure(f'files-os: the long chain has a 4095-byte entry: {lengths}')
    if exact and lengths[-1] != 4095:
        raise ProbeFailure(f'files-os: the exact chain ends at {lengths[-1]} bytes')
    return names


def unlock(path):
    for name in ('noread',):
        target = path / name
        if target.exists():
            os.chmod(target, 0o755)
    if (path / 'unreadable.txt').exists():
        os.chmod(path / 'unreadable.txt', 0o644)


def build(tree):
    """The tree, made in the same order every time."""
    odd = tree.parent / (tree.name + '-odd')
    for top in (tree, odd):
        if top.exists():
            unlock(top)
            shutil.rmtree(top)
    tree.mkdir(parents=True)
    # beside the tree: a recursive scan of the tree never meets its file
    odd.mkdir()
    (odd / 'x.abcdefghijklmnopq').write_bytes(b'odd')
    (odd / 'y.png').write_bytes(b'why')
    rel = str(tree.relative_to(ROOT))
    (tree / 'a.png').write_bytes(b'PNG fixture')
    (tree / 'b.txt').write_bytes(b'bee')
    (tree / 'C.PNG').write_bytes(b'upper')
    (tree / 'empty.dat').write_bytes(b'')
    (tree / 'sub').mkdir()
    (tree / 'sub' / 'c.png').write_bytes(b'see')
    (tree / 'sub' / 'deep').mkdir()
    (tree / 'sub' / 'deep' / 'd.txt').write_bytes(b'dee')
    (tree / 'sub' / 'emptydir').mkdir()
    (tree / 'noread').mkdir()
    (tree / 'noread' / 'hidden.txt').write_bytes(b'x')
    (tree / 'unreadable.txt').write_bytes(b'secret')
    os.symlink('a.png', tree / 'link')
    os.symlink('nothing.png', tree / 'dangling')
    (tree / 'bin').mkdir()
    log = (tree / 'url.log').resolve()
    (tree / 'bin' / 'explorer').write_text(f'#!/bin/sh\nprintf "[%s]" "$@" >> {json.dumps(str(log))}\n')
    os.chmod(tree / 'bin' / 'explorer', 0o755)
    for name, target, exact in (('long', 4200, False), ('exact', 4095, True)):
        (tree / name).mkdir()
        (tree / name / 'top.txt').write_bytes(b'top')
        names = chain_names(len(rel) + 1 + len(name), target, exact)
        fd = chain(os.open(tree / name, os.O_RDONLY | os.O_DIRECTORY), names[:-1])
        with open(os.open(names[-1], os.O_WRONLY | os.O_CREAT, 0o644, dir_fd=fd), 'wb') as f:
            f.write(b'deep')
        os.close(fd)
    stamp = TIME
    for name in ('a.png', 'b.txt', 'C.PNG', 'empty.dat', 'sub/c.png', 'sub/deep/d.txt', 'sub/deep', 'sub/emptydir', 'sub',
                 'noread/hidden.txt', 'noread', 'unreadable.txt', 'long', 'exact', 'bin'):
        os.utime(tree / name, (stamp, stamp))
        stamp += 1
    os.utime(tree, (stamp, stamp))
    for name in ('x.abcdefghijklmnopq', 'y.png', ''):
        stamp += 1
        os.utime(odd / name if name else odd, (stamp, stamp))
    os.chmod(tree / 'noread', 0)
    os.chmod(tree / 'unreadable.txt', 0)


def script(tree):
    """(op, args, defined): the operations, in order."""
    t = str(tree.relative_to(ROOT))
    out = []
    assert tree.name == 'tree'

    def add(op, *args, defined=True):
        out.append((op, list(args), defined))

    for name in ('a.png', 'missing', 'unreadable.txt', 'sub', 'dangling', 'link', 'noread', ''):
        add('exists', f'{t}/{name}' if name else t)
    for name in ('a.png', 'sub', 'missing', 'link', 'dangling', 'unreadable.txt', 'noread'):
        add('is_file', f'{t}/{name}')
    for name in ('', 'sub', 'a.png', 'noread', 'missing', 'link', 'sub/emptydir'):
        add('dir_exists', f'{t}/{name}' if name else t)
    # raylib 6.2: IsPathDirectory is !IsPathFile; IsPathAbsolute and IsFileHidden read the text alone
    for name in ('', 'sub', 'a.png', 'missing', 'link', 'dangling', 'noread'):
        add('is_dir', f'{t}/{name}' if name else t)
    for path in ('/', '/tmp/x', 'rel/x', '', './x', '~/x', '//net'):
        add('absolute', path)
    for path in ('.hidden', 'dir/.hidden', 'dir/visible', '.', '..', 'a/.', 'a/..', '...', '.a.b', 'a.b/c', '', '/', 'dir\\.x', 'x/'):
        add('hidden', path)
    for name in ('a.png', 'sub/c.png', 'sub', 'missing', 'link', 'unreadable.txt', 'noread'):
        add('mod_time', f'{t}/{name}')
    for path in (t, f'{t}/sub', f'{t}/a.png', f'{t}/missing', f'{t}/noread', f'{t}/long', f'{t}-odd'):
        add('count', path)
        add('load', path)
    filters = [None, '', '*.*', 'FILES*', 'DIRS*', '.png', '.PNG;.txt', 'png', '.png;DIRS*', 'FILES*;DIRS*', '.dat', '.zz']
    for path in (t, f'{t}/sub'):
        for subdirs in (False, True):
            for flt in filters:
                add('count_ex', path, flt, subdirs)
                add('load_ex', path, flt, subdirs)
    for subdirs in (False, True):
        add('load_ex', f'{t}/long', '*.*', subdirs)
        add('count_ex', f'{t}/long', None, subdirs)
    # x.abcdefghijklmnopq's 17-byte extension: raylib 6.2's IsFileExtension copies at most 15 bytes (6.0 overflowed)
    add('load_ex', f'{t}-odd', '.png', False)
    add('count_ex', f'{t}-odd', '.png', False)
    add('load_ex', f'{t}-odd', 'FILES*', False)
    # a 4095-byte path, which snprintf cuts to 4094 bytes (and the cut path does not exist)
    add('load_ex', f'{t}/exact', '*.*', True)
    add('count_ex', f'{t}/exact', None, True)
    add('load_ex', f'{t}/exact', '*.*', False)
    add('rename', f'{t}/b.txt', f'{t}/b2.txt')
    add('exists', f'{t}/b.txt')
    add('text', f'{t}/b2.txt')
    add('rename', f'{t}/missing', f'{t}/m2')
    add('rename', f'{t}/sub/c.png', f'{t}/sub/deep')
    add('remove', f'{t}/b2.txt')
    add('exists', f'{t}/b2.txt')
    add('remove', f'{t}/sub/emptydir')
    add('remove', f'{t}/sub')
    add('remove', f'{t}/missing')
    add('remove', f'{t}/link')
    add('exists', f'{t}/a.png')
    for path in (f'{t}/new/x/y', '', t, f'{t}/a.png/z', f'{t}/sub/deep', f'{t}/w1\\w2/w3', f'{t}/c:d/e'):
        add('make', path)
        add('dir_exists', path)
    add('load_ex', f'{t}/new', None, True)
    add('load_ex', f'{t}/new', 'DIRS*', True)
    add('copy', f'{t}/a.png', f'{t}/copied/q/a.png')
    add('text', f'{t}/copied/q/a.png')
    add('copy', f'{t}/missing', f'{t}/copied/none')
    add('exists', f'{t}/copied/none')
    add('copy', f'{t}/empty.dat', f'{t}/copied/empty.dat')
    add('exists', f'{t}/copied/empty.dat')
    add('copy', f'{t}/a.png', f'{t}/a.png/inside')
    add('copy', f'{t}/sub/c.png', f'{t}/c-copy.png')
    add('text', f'{t}/c-copy.png')
    add('move', f'{t}/C.PNG', f'{t}/moved/C.PNG')
    add('exists', f'{t}/C.PNG')
    add('text', f'{t}/moved/C.PNG')
    add('move', f'{t}/empty.dat', f'{t}/moved/empty.dat')
    add('exists', f'{t}/empty.dat')
    add('move', f'{t}/missing', f'{t}/moved/missing')
    add('load_ex', t, '*.*', False)
    add('app')
    for url in ('https://www.raylib.com', 'https://example.com/a b?c=1&d=2', "https://example.com/it's", 'plain'):
        add('url', url, f'{t}/url.log')
    add('change', f'{t}/missing')
    add('cwd')
    add('change', f'{t}/sub/deep')
    add('cwd')
    add('exists', 'd.txt')
    add('load', '.')
    add('change', '..')
    add('cwd')
    return out


C_PREFIX = r'''#include "raylib.h"
#include <stdio.h>
#include <string.h>
static void list(FilePathList l)
{
    printf("%u", l.count);
    for (unsigned int i = 0; i < l.count; i++) printf("|%s", l.paths[i]);
    printf("\n");
    UnloadDirectoryFiles(l);
}
static void text(const char *path)
{
    char *t = FileExists(path) ? LoadFileText(path) : NULL;
    printf("%s\n", t ? t : "(none)");
    if (t) UnloadFileText(t);
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''


def c_op(op, args, tree):
    s = [c_string(a) if isinstance(a, str) else a for a in args]
    flt = lambda f: 'NULL' if f is None else c_string(f)
    return {
        'exists': lambda: f'printf("%d\\n", (int)FileExists({s[0]}));',
        'is_file': lambda: f'printf("%d\\n", (int)IsPathFile({s[0]}));',
        'dir_exists': lambda: f'printf("%d\\n", (int)DirectoryExists({s[0]}));',
        'mod_time': lambda: f'printf("%ld\\n", GetFileModTime({s[0]}));',
        'count': lambda: f'printf("%u\\n", GetDirectoryFileCount({s[0]}));',
        'count_ex': lambda: f'printf("%u\\n", GetDirectoryFileCountEx({s[0]}, {flt(args[1])}, {"true" if args[2] else "false"}));',
        'load': lambda: f'list(LoadDirectoryFiles({s[0]}));',
        'load_ex': lambda: f'list(LoadDirectoryFilesEx({s[0]}, {flt(args[1])}, {"true" if args[2] else "false"}));',
        'rename': lambda: f'printf("%u\\n", (unsigned)FileRename({s[0]}, {s[1]}));',
        'remove': lambda: f'printf("%u\\n", (unsigned)FileRemove({s[0]}));',
        'make': lambda: f'printf("%u\\n", (unsigned)MakeDirectory({s[0]}));',
        'copy': lambda: f'printf("%u\\n", (unsigned)FileCopy({s[0]}, {s[1]}));',
        'move': lambda: f'printf("%u\\n", (unsigned)FileMove({s[0]}, {s[1]}));',
        'text': lambda: f'text({s[0]});',
        'change': lambda: f'printf("%d\\n", (int)ChangeDirectory({s[0]}));',
        'is_dir': lambda: f'printf("%d\\n", (int)IsPathDirectory({s[0]}));',
        'absolute': lambda: f'printf("%d\\n", (int)IsPathAbsolute({s[0]}));',
        'hidden': lambda: f'printf("%d\\n", (int)IsFileHidden({s[0]}));',
        'cwd': lambda: '{ const char *d = GetWorkingDirectory(); printf("%s\\n", d ? d : "(null)"); }',
        'app': lambda: '{ const char *d = GetApplicationDirectory(); size_t n = strlen(d); printf("%d\\n", (int)(n > 0 && d[n - 1] == \'/\' && DirectoryExists(d))); }',
        'url': lambda: f'OpenURL({s[0]}); text({s[1]});',
    }[op]()


def native_source(ops, tree):
    return C_PREFIX + ''.join(f'    {c_op(op, args, tree)}\n' for op, args, defined in ops if defined) + '    return 0;\n}\n'


PROGRAM = '''import Base
import ../../jonlib.bend as J

def chars(codes: List<U32>) -> String:
  match codes:
    case Nil{}: ""
    case Con{code, rest}: SCon{Char.from_u32(code), chars(rest)}

def flag(+value: Bool) -> String:
  Bool.pick(String, value, "1", "0")

def int.text(+value: U32) -> String:
  Bool.pick(String, (value >= 2147483648 : U32), "-" ++ U32.show((0 - value : U32)), U32.show(value))

def paths(xs: +List<String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+x, rest}: "|" ++ x ++ paths(rest)

def listing(found: Maybe<J.FilePathList>) -> String:
  match found:
    case None{}: "null"
    case Some{J.FilePathList{+count, +xs}}: U32.show(count) ++ paths(xs)

def counted(found: Maybe<U32>) -> String:
  match found:
    case None{}: "null"
    case Some{+n}: U32.show(n)

def directory(found: Maybe<String>) -> String:
  match found:
    case None{}: "(null)"
    case Some{+text}: text

def loaded(result: Result<&1, &1, J.Surface.IOError, String>) -> String:
  match result:
    case Fail{_}: "(none)"
    case Done{+text}: text

def text.existing(exists: Bool, path: String) -> IO(String):
  match exists:
    case False{}: IO.pure(String, "(none)")
    case True{}: IO.bind(Result<&1, &1, J.Surface.IOError, String>, String, J.Files.load_text(path), r => IO.pure(String, loaded(r)))

def text(+path: String) -> IO(String):
  IO.bind(Bool, String, J.Files.exists(path), exists => text.existing(exists, path))

def ends_slash(text: String, last: U32) -> Bool:
  match text:
    case SNil{}: U32.is_eq(last, 47)
    case SCon{character, rest}: ends_slash(rest, Char.to_u32(character))

def app(+dir: String) -> IO(String):
  IO.bind(Bool, String, J.Files.directory_exists(dir), exists => IO.pure(String, flag(exists && ends_slash(dir, 0))))

def said(line: String) -> IO(Unit):
  IO.print(line)

def main() -> IO(Unit):
  do IO<Unit>:
'''


def bend_maybe(value):
    return 'None{}' if value is None else f'Some{{{bend_string(value)}}}'


def bend_op(op, args):
    s = [bend_string(a) if isinstance(a, str) else a for a in args]
    b = lambda v: 'True{}' if v else 'False{}'
    shown = {
        'exists': lambda: ('Bool', f'J.Files.exists({s[0]})', 'flag(r)'),
        'is_file': lambda: ('Bool', f'J.Files.is_path_file({s[0]})', 'flag(r)'),
        'dir_exists': lambda: ('Bool', f'J.Files.directory_exists({s[0]})', 'flag(r)'),
        'mod_time': lambda: ('Nat', f'J.Files.mod_time({s[0]})', 'Nat.show(r)'),
        'count': lambda: ('Maybe<U32>', f'J.Files.directory_file_count({s[0]})', 'counted(r)'),
        'load': lambda: ('Maybe<J.FilePathList>', f'J.Files.load_directory_files({s[0]})', 'listing(r)'),
        'rename': lambda: ('U32', f'J.Files.rename({s[0]}, {s[1]})', 'U32.show(r)'),
        'remove': lambda: ('U32', f'J.Files.remove({s[0]})', 'U32.show(r)'),
        'make': lambda: ('U32', f'J.Files.make_directory({s[0]})', 'U32.show(r)'),
        'copy': lambda: ('Maybe<U32>', f'J.Files.copy({s[0]}, {s[1]})', 'counted(r)'),
        'move': lambda: ('Maybe<U32>', f'J.Files.move({s[0]}, {s[1]})', 'counted(r)'),
        'change': lambda: ('U32', f'J.Files.change_directory_with(J.Log.level(7), {s[0]})', 'int.text(r)'),
        'is_dir': lambda: ('Bool', f'J.Files.is_path_directory({s[0]})', 'flag(r)'),
        'cwd': lambda: ('Maybe<String>', 'J.Files.working_directory()', 'directory(r)'),
    }
    if op in ('count_ex', 'load_ex'):
        kind, call, show = (('Maybe<U32>', 'J.Files.directory_file_count_ex', 'counted(r)') if op == 'count_ex'
                            else ('Maybe<J.FilePathList>', 'J.Files.load_directory_files_ex', 'listing(r)'))
        return f'Unit <- IO.bind({kind}, Unit, {call}({s[0]}, {bend_maybe(args[1])}, {b(args[2])}), r => said({show}))'
    if op in ('absolute', 'hidden'):
        call = 'J.Files.is_path_absolute' if op == 'absolute' else 'J.Files.is_file_hidden'
        return f'Unit <- said(flag({call}({s[0]})))'
    if op == 'text':
        return f'Unit <- IO.bind(String, Unit, text({s[0]}), said)'
    if op == 'app':
        return 'Unit <- IO.bind(String, Unit, IO.bind(String, String, J.Files.application_directory(), d => app(d)), said)'
    if op == 'url':
        return f'Unit <- IO.bind(Unit, Unit, J.System.open_url({s[0]}), u => IO.bind(String, Unit, text({s[1]}), said))'
    kind, call, show = shown[op]()
    return f'Unit <- IO.bind({kind}, Unit, {call}, r => said({show}))'


def render(ops):
    return PROGRAM + ''.join(f'    {bend_op(op, args)}\n' for op, args, _ in ops) + '    IO.print("done")\n'


def parse(text):
    lines = text.splitlines()
    if not lines or lines[-1] != 'done':
        raise ProbeFailure(f'files-os: the candidate did not finish: {text[-400:]!r}')
    return lines[:-1]


def main():
    probe = probekit.Probe('files-os', probekit.arguments(__doc__))
    tree = probe.work / 'tree'
    probekit.ENV['PATH'] = str((tree / 'bin').resolve()) + os.pathsep + probekit.ENV.get('PATH', '')
    ops = script(tree)
    build(tree)
    native = probe.native(native_source(ops, tree)).splitlines()
    expected, it = [], iter(native)
    for op, args, defined in ops:
        expected.append(next(it) if defined else 'null')
    if next(it, None) is not None:
        raise ProbeFailure('files-os: the reference printed more lines than its script')
    rows = dict(zip(range(len(ops)), expected))
    if (rows[0], expected[[o for o, _, _ in ops].index('app')]) != ('1', '1'):
        raise ProbeFailure('files-os: the reference does not see its tree or its application directory')
    lists = [e for (op, _, d), e in zip(ops, expected) if op in ('load', 'load_ex') and d]
    if sum(e.count('|') for e in lists) < 100 or not any('/long/' in e for e in lists):
        raise ProbeFailure('files-os: the listings lost coverage')

    def rebuilt(text, selected, lane):
        rows = parse(text)
        build(tree)
        return rows

    build(tree)
    lanes = probe.candidates(lambda chosen, gpu: render(chosen), ops, batch=len(ops), parse_lane=rebuilt, timeout=1800)
    lanes = {name: rows for name, rows in lanes.items() if name != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'{ops[i][0]} {json.dumps(ops[i][1])[:120]}')
    unlock(tree)
    probe.finish(operations=len(ops), contracts=sum(not d for _, _, d in ops),
                 listed_paths=sum(e.count('|') for e in lists),
                 script_sha256=hashlib.sha256(json.dumps(ops).encode()).hexdigest())


if __name__ == '__main__':
    main()
