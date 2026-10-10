#!/usr/bin/env python3
"""Generate the tables of example ports that are transcribed from an upstream example's C source.

    python3 tools/example_tables.py keyboard RAYLIB   # core_keyboard_testbed: GetKeyText and the six key lines
    python3 tools/example_tables.py gamepad RAYLIB    # core_input_gamepad: the three controller layouts

RAYLIB is the pinned raylib checkout. The output is the block of the port between its hand-written head and
tail (examples/core_keyboard_testbed.bend from "# GetKeyText" to the last line's list;
examples/core_input_gamepad.bend from "# The Xbox layout" to the generic layout's last draw). Each generator
stops on a line of the example it does not recognize, so a changed example cannot be transcribed silently.
"""
import re
import sys
from pathlib import Path


def keyboard(raylib):
    """GetKeyText's cases by raylib.h keycode, then each line's keycodes and widths."""
    header = (raylib / 'src/raylib.h').read_text()
    source = (raylib / 'examples/core/core_keyboard_testbed.c').read_text()
    codes = {name: int(value) for name, value in re.findall(r'^\s*(KEY_[A-Z0-9_]+)\s*=\s*(\d+),', header, re.M)}
    def code(token):
        token = token.strip()
        return int(token) if token.isdigit() else codes[token]
    out = []
    out.append('# GetKeyText: the key\'s text on a US keyboard (the cases by keycode, as raylib.h numbers them).')
    out.append('def key.text(key: U32) -> String:')
    out.append('  match key:')
    cases = re.findall(r'case (KEY_[A-Z0-9_]+)\s*: return "((?:[^"\\]|\\.)*)";', source)
    assert len(cases) == source.count('case KEY_'), len(cases)
    for name, text in sorted(cases, key=lambda c: codes[c[0]]):
        out.append(f'    case {codes[name]}: "{text}"')
    out.append('    case _: ""')
    out.append('')
    rows = []
    for n, count in ((1, 15), (2, 15), (3, 15), (4, 14), (5, 14), (6, 11)):
        widths = [45] * count
        for index, width in re.findall(rf'line0{n}KeyWidths\[(\d+)\] = (\d+);', source):
            widths[int(index)] = int(width)
        body = re.search(rf'int line0{n}Keys\[{count}\] = \{{(.*?)\}};', source, re.S).group(1)
        body = re.sub(r'/\*.*?\*/', '', body)
        keys = [code(t) for t in body.split(',') if t.strip()]
        assert len(keys) == count, (n, keys)
        names = [t.strip() for t in body.split(',') if t.strip()]
        out.append(f'# Keyboard line 0{n}: ' + ', '.join(names) + '.')
        out.append(f'def line0{n}() -> +List<Cap>:')
        out.append('  [' + ', '.join(f'Cap{{{k}, {w}}}' for k, w in zip(keys, widths)) + ']')
        out.append('')
    return '\n'.join(out)


NAMES = {'leftStickX': 'lx', 'leftStickY': 'ly', 'rightStickX': 'rx', 'rightStickY': 'ry', 'leftTrigger': 'lt', 'rightTrigger': 'rt'}

def split(args):
    out, depth, cur = [], 0, ''
    for ch in args:
        if ch in '({': depth += 1
        if ch in ')}': depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip()); cur = ''
        else:
            cur += ch
    out.append(cur.strip())
    return out

def number(text):
    """A C int/float expression of the layouts as an F32 expression (ints are exact in F32)."""
    text = text.strip()
    if re.fullmatch(r'\d+', text):
        return text + '.0'
    if re.fullmatch(r'\d+\.\d+f', text):
        return text[:-1]
    m = re.fullmatch(r'(\d+) \+ (\d+)', text)
    if m:
        return f'({m.group(1)}.0 + {m.group(2)}.0 : F32)'
    m = re.fullmatch(r'(\d+) \+ \(int\)\((\w+)\*20\)', text)
    if m:
        return f'({m.group(1)}.0 + F32.trunc(({NAMES[m.group(2)]} * 20.0 : F32)) : F32)'
    m = re.fullmatch(r'\(int\)\(\(\(1 \+ (\w+)\)/2\)\*70\)', text)
    if m:
        return f'F32.trunc((((1.0 + {NAMES[m.group(1)]}) / 2.0) * 70.0 : F32))'
    raise SystemExit(f'number: {text!r}')

def color(text):
    text = text.strip()
    return {'leftGamepadColor': 'left', 'rightGamepadColor': 'right'}.get(text) or f'J.Color.{text}()'

def pair(text):
    m = re.fullmatch(r'\(Vector2\)\{ *([^,]+), *([^}]+?) *\}', text.strip())
    return number(m.group(1)), number(m.group(2))

def layout(name, block, comment):
    lines = [f'# {comment}', f'def {name}(+libm: M.Libm, +core: J.Core, +pad: U32, +lx: F32, +ly: F32, +rx: F32, +ry: F32, +lt: F32, +rt: F32, frame: J.Frame) -> J.Frame:']
    lets, steps, pending = [], [], None
    for raw in block.split('\n'):
        line = raw.strip()
        if not line or line.startswith('//') or line in ('{', '}', 'else') or line.startswith('DrawTexture('):
            continue
        m = re.fullmatch(r'Color (\w+) = BLACK;', line)
        if m:
            pending = m.group(1); continue
        m = re.fullmatch(r'if \(IsGamepadButtonDown\(gamepad, (GAMEPAD_BUTTON_\w+)\)\) (\w+GamepadColor) = RED;', line)
        if m:
            assert m.group(2) == pending
            steps.append(('let', f'+{color(pending)} = Bool.pick(U32, down(core, pad, J.GamepadButton.{m.group(1)}()), J.Color.RED(), J.Color.BLACK())')); continue
        m = re.fullmatch(r'(?:if \(IsGamepadButtonDown\(gamepad, (GAMEPAD_BUTTON_\w+)\)\) )?(Draw\w+)\((.*)\);', line)
        if not m:
            raise SystemExit(f'line: {line!r}')
        on = f'down(core, pad, J.GamepadButton.{m.group(1)}())' if m.group(1) else 'True{}'
        call, args = m.group(2), split(m.group(3))
        if call == 'DrawCircle':
            steps.append(('draw', f'circle({on}, libm, @@, {number(args[0])}, {number(args[1])}, {number(args[2])}, {color(args[3])})'))
        elif call == 'DrawRectangle':
            steps.append(('draw', f'box({on}, @@, {number(args[0])}, {number(args[1])}, {number(args[2])}, {number(args[3])}, {color(args[4])})'))
        elif call == 'DrawTriangle':
            (ax, ay), (bx, by), (cx, cy) = pair(args[0]), pair(args[1]), pair(args[2])
            steps.append(('draw', f'triangle({on}, @@, {ax}, {ay}, {bx}, {by}, {cx}, {cy}, {color(args[3])})'))
        elif call == 'DrawRectangleRounded':
            r = re.fullmatch(r'\(Rectangle\)\{ *([^,]+), *([^,]+), *([^,]+), *([^}]+?) *\}', args[0])
            steps.append(('draw', f'rounded({on}, libm, @@, {number(r.group(1))}, {number(r.group(2))}, {number(r.group(3))}, {number(r.group(4))}, {number(args[1])}, {number(args[2])}, {color(args[3])})'))
        else:
            raise SystemExit(f'call: {call}')
    index, previous = 0, 'frame'
    draws = sum(1 for kind, _ in steps if kind == 'draw')
    for kind, text in steps:
        if kind == 'let':
            lines.append('  ' + text); continue
        index += 1
        if index == draws:
            lines.append('  ' + text.replace('@@', previous))
        else:
            lines.append(f'  f{index} = ' + text.replace('@@', previous)); previous = f'f{index}'
    return '\n'.join(lines)


def gamepad(raylib):
    """The draw calls of the Xbox, PlayStation and generic branches as Bend draw chains."""
    source = (raylib / 'examples/core/core_input_gamepad.c').read_text()
    xbox = source[source.index('DrawTexture(texXboxPad, 0, 0, DARKGRAY);'):source.index('else if ((TextFindIndex(TextToLower(GetGamepadName(gamepad)), PS_ALIAS_1)')]
    ps = source[source.index('DrawTexture(texPs3Pad, 0, 0, DARKGRAY);'):source.index('// Draw background: generic')]
    generic = source[source.index('// Draw background: generic'):source.index('DrawText(TextFormat("DETECTED AXIS [%i]:"')]
    return '\n\n'.join([
        layout('pad.xbox', xbox, 'The Xbox layout over its texture: the buttons held, the d-pad, the back buttons, the sticks and the triggers.'),
        layout('pad.playstation', ps, 'The PlayStation layout over its texture.'),
        layout('pad.generic', generic, 'The generic layout: a rounded body, the buttons, the d-pad, the back buttons and the sticks.')])


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('keyboard', 'gamepad'):
        raise SystemExit(__doc__)
    print({'keyboard': keyboard, 'gamepad': gamepad}[sys.argv[1]](Path(sys.argv[2])))


if __name__ == '__main__':
    main()
