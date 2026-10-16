#!/usr/bin/env python3
"""Compare raygui's GuiLoadIcons, GuiGetIcons and GuiIconText with Jongui's.

The reference is the pinned raylib's raygui.h (examples/core/raygui.h) linked
with the reference library (PLATFORM_MEMORY); no window is opened. Python
writes a corpus of .rgi files in the probe's work directory: icon sets of 16,
32 and 0 pixels and of a negative size, with and without name ids (one 32
bytes long without a terminator), a full table of 256 icons, data cut short
at a word's end, headers cut short before and at the icon count and size, a
wrong signature, a file that does not exist, a directory, and headers that ask
for more than the table holds over data that does not (fread stops at the
end of the file, so raygui stays inside its table). One script loads
them in order, with and without names (raygui's icon table carries over from
one load to the next), printing the names raygui returns (NULL, or each name's
32 bytes) and a hash of the 2048 words of GuiGetIcons after each load. Then
GuiIconText for ids of one to eleven characters (negative ones among them) and
texts NULL, empty, short and 1018 bytes long.

Contracts (Jongui answers undefined and the reference does not run them): a
load whose data would pass raygui's 2048-word table, an icon count times
words per icon past int's range, a negative icon count, a
header that ends inside the count or the size, data that ends inside a word,
and GuiIconText of a text of 1019 bytes or more (raygui's buffer is left
without its terminator). CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import random
import struct

import probekit
from probekit import ROOT, ProbeFailure

WORDS = 2048


def rgi(count, size, names, words, *, signature=b'rGI ', cut=None):
    """An .rgi file: the header, `names` (each padded or cut to 32 bytes) and the words, cut to `cut` bytes."""
    data = signature + struct.pack('<hhhh', 100, 0, count, size)
    data += b''.join(name[:32].ljust(32, b'\0') for name in names)
    data += b''.join(struct.pack('<I', w) for w in words)
    return data if cut is None else data[:cut]


def corpus():
    """(file name, bytes or None for a missing file or 'dir' for a directory) in script order."""
    rnd = random.Random(20261016)
    words = lambda n: [rnd.getrandbits(32) for _ in range(n)]
    three = [b'ICON_ONE', b'ICON_TWO', b'X' * 32]
    return [
        ('three.rgi', rgi(3, 16, three, words(24))),
        ('full.rgi', rgi(256, 16, [b'N%03d' % i for i in range(256)], words(WORDS))),
        ('big.rgi', rgi(2, 32, [b'BIG_A', b'BIG_B'], words(64))),
        ('negative-size.rgi', rgi(4, -16, [b'NEG'] * 4, words(32))),
        ('zero-size.rgi', rgi(5, 0, [b'Z'] * 5, words(8))),
        ('short-data.rgi', rgi(4, 16, [b'S1', b'S2', b'S3', b'S4'], words(32), cut=12 + 4 * 32 + 20 * 4)),
        ('short-names.rgi', rgi(3, 16, three, [], cut=12 + 32 + 10)),
        ('header-only.rgi', rgi(0, 16, [], [])),
        ('six-bytes.rgi', rgi(9, 16, [], [], cut=6)),
        ('eight-bytes.rgi', rgi(9, 16, [], [], cut=8)),
        ('ten-bytes.rgi', rgi(9, 16, [], [], cut=10)),
        ('bad-signature.rgi', rgi(3, 16, three, words(24), signature=b'rGIx')),
        ('no-names.rgi', rgi(2, 16, [b'Q1', b'Q2'], words(16))),
        ('missing.rgi', None),
        ('folder.rgi', 'dir'),
        ('many-short.rgi', rgi(257, 16, [], words(8))),
        ('big-short.rgi', rgi(65, 32, [], words(8))),
        # Contracts.
        ('too-many.rgi', rgi(257, 16, [b'M'] * 257, words(257 * 8))),
        ('overflow.rgi', rgi(32767, 32767, [], words(8))),
        ('negative-count.rgi', rgi(-1, 16, [], words(8))),
        ('nine-bytes.rgi', rgi(9, 16, [], [], cut=9)),
        ('eleven-bytes.rgi', rgi(9, 16, [], [], cut=11)),
        ('torn-word.rgi', rgi(2, 16, [b'T1', b'T2'], words(16), cut=12 + 2 * 32 + 5 * 4 + 2)),
    ]


def short(data, at):
    return struct.unpack('<h', data[at:at + 2])[0] if len(data) >= at + 2 else 0


def defined(data):
    """Whether raygui's load of these bytes is defined (a missing file, a directory and a wrong signature are)."""
    if not isinstance(data, bytes) or data[:4] != b'rGI ':
        return True
    if len(data) in (9, 11):
        return False
    count, size = short(data, 8), short(data, 10)
    if count < 0:
        return False
    total = count * (size * size // 32)
    avail = max(0, len(data) - (12 + 32 * count))
    return total < 2 ** 31 and min(total, avail // 4) <= WORDS and not (avail // 4 < total and avail % 4)


ICON_IDS = [0, 5, 42, 99, 100, 255, 256, 999, 1000, 12345, 2147483647, -1, -5, -50, -99, -100, -500, -2147483648]


def icon_texts():
    long_text = ''.join(chr(65 + i % 26) for i in range(1018))
    return [None, '', 'Save', 'two\nlines', long_text, long_text + 'Z']


def script():
    """('load', name, names, defined) and ('text', id, text, defined) operations."""
    ops = []
    for index, (name, data) in enumerate(corpus()):
        ops.append(('load', name, index % 2 == 0 or name == 'three.rgi', defined(data)))
    ops.append(('load', 'three.rgi', False, True))
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
static void loaded(const char *path, bool names, int count)
{
    char **n = GuiLoadIcons(path, names);
    if (n == NULL) printf("null");
    else
    {
        printf("%d:", count);
        for (int i = 0; i < count; i++)
        {
            for (int j = 0; j < 32; j++) printf("%02x", (unsigned char)n[i][j]);
            if (i + 1 < count) printf(",");
            free(n[i]);
        }
        free(n);
    }
    unsigned int h = 0;
    unsigned int *icons = GuiGetIcons();
    for (int i = 0; i < 2048; i++) h = h*31u + icons[i];
    printf(" %u\n", h);
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
    kind, a, b, _ = op
    if kind == 'load':
        data = dict(corpus())[a]
        count = short(data, 8) if isinstance(data, bytes) and data[:4] == b'rGI ' else 0
        return f'loaded({c_string(str(work / a))}, {"true" if b else "false"}, {count});'
    return f'text({a}, {"NULL" if b is None else c_string(b)});'


def native_source(ops, work):
    return C_PREFIX + ''.join(f'    {c_op(op, work)}\n' for op in ops if op[3]) + '    return 0;\n}\n'


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jongui.bend as G
import ../../src/text.bend as TextCore

def hex.digit(+d: U32) -> U32:
  Bool.pick(U32, (d < 10 : U32), (48 + d : U32), (87 + d : U32))

def hex(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: Con{hex.digit((b >> 4n : U32)), Con{hex.digit((b .&. 15 : U32)), hex(rest)}}

def joined.rest(names: +List<+List<U32>>) -> +List<U32>:
  match names:
    case Nil{}: Nil{}
    case Con{+n, rest}: Con{44, TextCore.glue(hex(n), joined.rest(rest))}

def joined(names: +List<+List<U32>>) -> +List<U32>:
  match names:
    case Nil{}: Nil{}
    case Con{+n, rest}: TextCore.glue(hex(n), joined.rest(rest))

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
    case G.GuiNames{+ns}: U32.show(count(ns, 0)) ++ ":" ++ TextCore.string(joined(ns))
    case G.GuiNamesUndefined{}: "undefined"

def shown(+gui: G.Gui, names: G.Gui.Names) -> String:
  named(names) ++ " " ++ U32.show(hash(G.Gui.get_icons(gui), 0))

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
        _, name, names, _ = loads[index]
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
    for name, data in corpus():
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
    if len({e.split(' ')[-1] for e in loads}) < 6 or not any(e.startswith('65:') for e in loads) or sum(e.startswith('null') for e in loads) < 6:
        raise ProbeFailure('gui-icon-files: the loads lost coverage')
    lanes = probe.candidates(lambda chosen, gpu: render(chosen, work), ops, batch=len(ops),
                             parse_lane=lambda text, selected, lane: candidate_rows(selected, text), timeout=1800)
    lanes = {name: rows for name, rows in lanes.items() if name != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: json.dumps(ops[i][:3])[:120])
    probe.finish(operations=len(ops), contracts=sum(not op[3] for op in ops),
                 script_sha256=hashlib.sha256(json.dumps(ops).encode()).hexdigest())


if __name__ == '__main__':
    main()
