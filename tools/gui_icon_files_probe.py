#!/usr/bin/env python3
"""Compare raygui's GuiLoadIcons, GuiGetIcons and GuiIconText with Jongui's.

The reference is the pinned raylib's raygui.h (examples/core/raygui.h,
raygui 5.1-dev) linked with the reference library (PLATFORM_MEMORY); no
window is opened. raygui 5.1-dev's GuiLoadIcons reads the whole file and
hands it to GuiLoadIconsFromMemory, which replaces the icon table with a new
one of the icon count times size*size/32 words copied from the data. Python
writes a corpus of .rgi files in the probe's work directory: icon sets of 16,
32 and 0 pixels and of a negative size, with and without name ids (one 32
bytes long without a terminator), tables of 256 and 512 icons, 513 icons
without names, a header without icons, an empty file, a wrong signature, a
file that does not exist and a directory. One script loads them in order,
with and without names, printing the names raygui returns (NULL, or each
name's 32 bytes), then the length of GuiGetIcons's table (which the script
knows: 4096 words at start, the last signed load's after it) and a hash of
its words after each load. Then GuiIconText for ids of one to eleven
characters (negative ones among them) and texts NULL, empty, short and 1018
bytes long.

Contracts (Jongui answers undefined and the reference does not run them): a
file shorter than the 12-byte header (raygui copies the header before it
checks anything), name ids or words past the data, more than 512 name ids
asked (raygui's name array), an icon count times words per icon whose byte
size passes int's range, a negative icon count, and GuiIconText of a text of
1019 bytes or more (raygui's buffer is left without its terminator). CPU-1,
CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import random
import struct

import probekit
from probekit import ROOT, ProbeFailure

WORDS = 4096


def rgi(count, size, names, words, *, signature=b'rGI ', cut=None):
    """An .rgi file: the header, `names` (each padded or cut to 32 bytes) and the words, cut to `cut` bytes."""
    data = signature + struct.pack('<hhhh', 100, 0, count, size)
    data += b''.join(name[:32].ljust(32, b'\0') for name in names)
    data += b''.join(struct.pack('<I', w) for w in words)
    return data if cut is None else data[:cut]


def corpus():
    """(file name, bytes or None for a missing file or 'dir' for a directory, names asked) in script order."""
    rnd = random.Random(20261016)
    words = lambda n: [rnd.getrandbits(32) for _ in range(n)]
    three = [b'ICON_ONE', b'ICON_TWO', b'X' * 32]
    return [
        ('three.rgi', rgi(3, 16, three, words(24)), True),
        ('full.rgi', rgi(256, 16, [b'N%03d' % i for i in range(256)], words(2048)), False),
        ('big.rgi', rgi(2, 32, [b'BIG_A', b'BIG_B'], words(64)), True),
        ('negative-size.rgi', rgi(4, -16, [b'NEG'] * 4, words(32)), False),
        ('zero-size.rgi', rgi(5, 0, [b'Z'] * 5, words(8)), True),
        ('all.rgi', rgi(512, 16, [b'I%03d' % i for i in range(512)], words(4096)), True),
        ('header-only.rgi', rgi(0, 16, [], []), True),
        ('more.rgi', rgi(513, 16, [b'M'] * 513, words(513 * 8)), False),
        ('empty.rgi', b'', True),
        ('bad-signature.rgi', rgi(3, 16, three, words(24), signature=b'rGIx'), True),
        ('no-names.rgi', rgi(2, 16, [b'Q1', b'Q2'], words(16)), False),
        ('missing.rgi', None, True),
        ('folder.rgi', 'dir', False),
        ('twelve-bytes.rgi', rgi(0, 32, [], []), False),
        # Contracts.
        ('more-named.rgi', rgi(513, 16, [b'M'] * 513, words(513 * 8)), True),
        ('short-data.rgi', rgi(4, 16, [b'S1', b'S2', b'S3', b'S4'], words(32), cut=12 + 4 * 32 + 20 * 4), False),
        ('short-names.rgi', rgi(3, 16, three, [], cut=12 + 32 + 10), True),
        ('six-bytes.rgi', rgi(9, 16, [], [], cut=6), False),
        ('eleven-bytes.rgi', rgi(9, 16, [], [], cut=11), True),
        ('overflow.rgi', rgi(32767, 32767, [], words(8)), False),
        ('negative-count.rgi', rgi(-1, 16, [], words(8)), False),
        ('torn-word.rgi', rgi(2, 16, [b'T1', b'T2'], words(16), cut=12 + 2 * 32 + 5 * 4 + 2), True),
    ]


def short(data, at):
    return struct.unpack('<h', data[at:at + 2])[0] if len(data) >= at + 2 else 0


def signed(data):
    return isinstance(data, bytes) and len(data) >= 12 and data[:4] == b'rGI '


def table(data):
    """The words raygui's new table holds after a signed load: count*(size*size/32) (C's int division)."""
    return short(data, 8) * (short(data, 10) * short(data, 10) // 32)


def defined(data, names):
    """Whether raygui's load of these bytes is defined (a missing file, a directory, an empty file and a wrong
    signature are: NULL, the table kept)."""
    if not isinstance(data, bytes) or len(data) == 0:
        return True
    if len(data) < 12:
        return False
    if data[:4] != b'rGI ':
        return True
    count = short(data, 8)
    if count < 0 or table(data) * 4 >= 2 ** 31:
        return False
    start = 12 + 32 * count
    if names and (count > 512 or start > len(data)):
        return False
    return table(data) == 0 or start + 4 * table(data) <= len(data)


ICON_IDS = [0, 5, 42, 99, 100, 255, 256, 999, 1000, 12345, 2147483647, -1, -5, -50, -99, -100, -500, -2147483648]


def icon_texts():
    long_text = ''.join(chr(65 + i % 26) for i in range(1018))
    return [None, '', 'Save', 'two\nlines', long_text, long_text + 'Z']


def script():
    """('load', name, names, defined, words) and ('text', id, text, defined) operations; words is the table's length
    after the load (the reference hashes that many)."""
    ops, words = [], WORDS
    for name, data, names in corpus() + [('three.rgi', dict((n, d) for n, d, _ in corpus())['three.rgi'], False)]:
        ok = defined(data, names)
        if ok and signed(data):
            words = table(data)
        ops.append(('load', name, names, ok, words))
    for text in icon_texts():
        for icon in ICON_IDS:
            ops.append(('text', icon, text, text is None or len(text.encode()) < 1019))
    return ops


def c_string(text):
    return '"' + ''.join(c if 32 <= ord(c) < 127 and c not in '"\\?' else f'\\{ord(c):03o}' for c in text) + '"'


def bend_bytes(text):
    return '[' + ', '.join(str(b) for b in text.encode()) + ']'


C_PREFIX = r'''#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"
#include <stdio.h>
#include <stdlib.h>
static void loaded(const char *path, bool names, int count, int words)
{
    char **n = GuiLoadIcons(path, names);
    if (n == NULL) printf("null");
    else
    {
        unsigned int nh = 0;
        for (int i = 0; i < count; i++)
        {
            for (int j = 0; j < 32; j++) nh = nh*31u + (unsigned char)n[i][j];
            free(n[i]);
        }
        free(n);
        printf("%d:%u", count, nh);
    }
    unsigned int h = 0;
    unsigned int *icons = GuiGetIcons();
    for (int i = 0; i < words; i++) h = h*31u + icons[i];
    printf(" %d %u\n", words, h);
}
static void text(int id, const char *t)
{
    printf("%s\n", GuiIconText(id, t));
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
'''


def c_op(op, work):
    if op[0] == 'load':
        _, name, names, _, words = op
        data = next(d for n, d, _ in corpus() if n == name)
        count = short(data, 8) if signed(data) else 0
        return f'loaded({c_string(str(work / name))}, {"true" if names else "false"}, {count}, {words});'
    _, a, b, _ = op
    return f'text({a}, {"NULL" if b is None else c_string(b)});'


def native_source(ops, work):
    return C_PREFIX + ''.join(f'    {c_op(op, work)}\n' for op in ops if op[3]) + '    return 0;\n}\n'


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jongui.bend as G
import ../../src/text.bend as TextCore

# The name ids' bytes hashed in order (h*31 + byte, the reference's loop):
# 512 names are 16384 bytes, past the JavaScript lane's stack as a string.
def ids.bytes(name: +List<U32>, +h: U32) -> U32:
  match name:
    case Nil{}: h
    case Con{+b, rest}: ids.bytes(rest, (h * 31 + b : U32))

def ids.hash(names: +List<+List<U32>>, +h: U32) -> U32:
  match names:
    case Nil{}: h
    case Con{+n, rest}: ids.hash(rest, ids.bytes(n, h))

def hash(words: +List<U32>, +h: U32) -> U32:
  match words:
    case Nil{}: h
    case Con{+w, rest}: hash(rest, (h * 31 + w : U32))

def count(names: +List<+List<U32>>, +n: U32) -> U32:
  match names:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def named(names: G.Gui.Names) -> String:
  match names:
    case G.GuiNamesNull{}: "null"
    case G.GuiNames{+ns}: U32.show(count(ns, 0)) ++ ":" ++ U32.show(ids.hash(ns, 0))
    case G.GuiNamesUndefined{}: "undefined"

def table.size(icons: +List<U32>, +n: U32) -> U32:
  match icons:
    case Nil{}: n
    case Con{_, rest}: table.size(rest, (n + 1 : U32))

def shown(+gui: G.Gui, names: G.Gui.Names) -> String:
  named(names) ++ " " ++ U32.show(table.size(G.Gui.get_icons(gui), 0)) ++ " " ++ U32.show(hash(G.Gui.get_icons(gui), 0))

def texted(found: Maybe<String>) -> String:
  match found:
    case None{}: "undefined"
    case Some{+t}: t

'''


def render(ops, work):
    loads = [op for op in ops if op[0] == 'load']
    texts = [op for op in ops if op[0] == 'text']
    out = [PROGRAM]
    # Each load is a def that prints and hands the gui to the next one (defs come before their callers).
    out.append(f'def step{len(loads)}(gui: G.Gui) -> IO(Unit):\n  IO.pure(Unit, Unit{{}})\n\n')
    for index in reversed(range(len(loads))):
        _, name, names, _, _ = loads[index]
        path = 'TextCore.string(' + bend_bytes(str(work / name)) + ')'
        out.append(f'def step{index}.after(r: G.Gui & G.Gui.Names) -> IO(Unit):\n'
                   f'  (+gui, names) = r\n'
                   f'  do IO<Unit>:\n'
                   f'    Unit <- IO.print(shown(gui, names))\n'
                   f'    step{index + 1}(gui)\n\n'
                   f'def step{index}(gui: G.Gui) -> IO(Unit):\n'
                   f'  IO.bind(G.Gui & G.Gui.Names, Unit, G.Gui.load_icons(gui, {path}, {"True{}" if names else "False{}"}), step{index}.after)\n\n')
    out.append('def main() -> IO(Unit):\n  do IO<Unit>:\n    Unit <- step0(G.Gui.new())\n')
    for _, icon, text, _ in texts:
        arg = 'None{}' if text is None else 'Some{TextCore.string(' + bend_bytes(text) + ')}'
        out.append(f'    Unit <- IO.print(texted(G.Gui.icon_text({icon & 0xFFFFFFFF}, {arg})))\n')
    out.append('    IO.print("done")\n')
    return ''.join(out)


def parse(text):
    lines = text.split('\n')
    if len(lines) < 2 or lines[-2] != 'done' or lines[-1] != '':
        raise ProbeFailure(f'gui-icon-files: the candidate did not finish: {text[-400:]!r}')
    return lines[:-2]


def write_corpus(work):
    folder = work / 'folder.rgi'
    folder.mkdir(parents=True, exist_ok=True)
    for name, data, _ in corpus():
        path = work / name
        if data is None:
            path.unlink(missing_ok=True)
        elif isinstance(data, bytes):
            path.write_bytes(data)


def expected_rows(ops, native):
    """The reference's lines in script order, 'undefined' for the contracts; a text's lines are joined back."""
    lines = native.split('\n')
    if lines[-1] != '':
        raise ProbeFailure('gui-icon-files: the reference output does not end with a newline')
    it, out = iter(lines[:-1]), []
    for op in ops:
        if not op[3]:
            out.append('undefined')
            continue
        row = next(it)
        if op[0] == 'text' and op[2] is not None and '\n' in op[2]:
            row += '\n' + next(it)
        out.append(row)
    if next(it, None) is not None:
        raise ProbeFailure('gui-icon-files: the reference printed more lines than its script')
    return out


def candidate_rows(ops, text):
    lines, it, out = parse(text), None, []
    it = iter(lines)
    for op in ops:
        row = next(it, None)
        if row is None:
            raise ProbeFailure('gui-icon-files: the candidate printed fewer lines than its script')
        if op[0] == 'text' and op[3] and op[2] is not None and '\n' in op[2]:
            row += '\n' + next(it)
        # A refused load prints the table's hash too; the reference does not run it, and the next load's hash shows the
        # table was left as it was.
        out.append(row if op[3] else row.split(' ')[0])
    if next(it, None) is not None:
        raise ProbeFailure('gui-icon-files: the candidate printed more lines than its script')
    return out


def main():
    probe = probekit.Probe('gui-icon-files', probekit.arguments(__doc__))
    work = probe.work.resolve()
    ops = script()
    write_corpus(work)
    native = probe.native(native_source(ops, work), extra_flags=('-I' + str(probe.args.raylib_source / 'examples/core'),))
    expected = expected_rows(ops, native)
    loads = [e for op, e in zip(ops, expected) if op[0] == 'load' and op[3]]
    if (len({e.split(' ')[-1] for e in loads}) < 6 or not any(e.startswith('512:') for e in loads) or sum(e.startswith('null') for e in loads) < 6
            or not any(e.split(' ')[-2] == '4104' for e in loads) or not any(e.split(' ')[-2] == '0' for e in loads)):
        raise ProbeFailure('gui-icon-files: the loads lost coverage')
    lanes = probe.candidates(lambda chosen, gpu: render(chosen, work), ops, batch=len(ops),
                             parse_lane=lambda text, selected, lane: candidate_rows(selected, text), timeout=1800)
    lanes = {name: rows for name, rows in lanes.items() if name != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: json.dumps(ops[i][:3])[:120])
    probe.finish(operations=len(ops), contracts=sum(not op[3] for op in ops),
                 script_sha256=hashlib.sha256(json.dumps(ops).encode()).hexdigest())


if __name__ == '__main__':
    main()
