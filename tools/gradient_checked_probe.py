#!/usr/bin/env python3
"""Compare GenImageChecked, GenImageGradientSquare and GenImageGradientRadial.

Finite densities and positive checker sizes on small RGBA images. Raw bytes
are compared on CPU-1, CPU-2 and JavaScript.
"""
import probekit

CHECKED = ((5, 4, 2, 3, 0x01020304, 0x05060708), (4, 4, 1, 1, 0xFFFFFFFF, 0x000000FF), (3, 2, 3, 2, 0x11223344, 0x55667788))
DENSITIES = (0.0, 0.5, 1.0, 2.0, -1.0)
SIZES = ((5, 4), (2, 2), (1, 1))
INNER, OUTER = 0xFF0000FF, 0x0000FFFF


def channels(word):
    return (word >> 24) & 255, (word >> 16) & 255, (word >> 8) & 255, word & 255


def c_color(word):
    return '(Color){{{0},{1},{2},{3}}}'.format(*channels(word))


def f32_c(value):
    return f'{value:.1f}f'


def f32_bend(value):
    if value < 0:
        return f'F32.neg({abs(value):.1f})'
    return f'{value:.1f}'


def native():
    lines = [
        '#include "raylib.h"', '#include <stdio.h>',
        'static void dump(const char *name, Image im){unsigned char *p=im.data; int n=im.width*im.height*4;',
        ' printf("%s", name); for(int i=0;i<n;i++) printf(" %u", p[i]); printf("\\n"); UnloadImage(im);}',
        'int main(void){SetTraceLogLevel(LOG_NONE);',
    ]
    for w, h, tx, ty, first, second in CHECKED:
        lines.append(f'dump("checked", GenImageChecked({w},{h},{tx},{ty},{c_color(first)},{c_color(second)}));')
    for w, h in SIZES:
        for density in DENSITIES:
            lines.append(f'dump("square", GenImageGradientSquare({w},{h},{f32_c(density)},{c_color(INNER)},{c_color(OUTER)}));')
            lines.append(f'dump("radial", GenImageGradientRadial({w},{h},{f32_c(density)},{c_color(INNER)},{c_color(OUTER)}));')
    lines.append('return 0;}')
    return '\n'.join(lines) + '\n'


HEADER = r'''import Base
import ../../jonlib.bend as J
def bytes(values: List<U32>) -> String:
  match values:
    case Nil{}: ""
    case Con{head, rest}: " " ++ U32.show(head) ++ bytes(rest)
def image_bytes(data: (U32 & U32) & (U32 & List<U32>)) -> String:
  ((_, _), (_, values)) = data
  bytes(values)
def image_of(label: String, found: Maybe<J.Surface>) -> String:
  match found:
    case None{}: label ++ " none"
    case Some{image}: label ++ image_bytes(J.Surface.export(image))
'''


def program():
    body = [HEADER, 'def main() -> IO(Unit):', '  do IO<Unit>:']
    for w, h, tx, ty, first, second in CHECKED:
        body.append(f'    IO.print(image_of("checked", J.Surface.create_checked({w}, {h}, {tx}, {ty}, {first}, {second})))')
    for w, h in SIZES:
        for density in DENSITIES:
            factor = f32_bend(density)
            body.append(f'    IO.print(image_of("square", J.Surface.create_gradient_square({w}, {h}, {factor}, {INNER}, {OUTER})))')
            body.append(f'    IO.print(image_of("radial", J.Surface.create_gradient_radial({w}, {h}, {factor}, {INNER}, {OUTER})))')
    return '\n'.join(body) + '\n'


def kept(text):
    return [line for line in text.splitlines() if line and not line.startswith('INFO:')]


def main():
    probe = probekit.Probe('gradient-checked', probekit.arguments(__doc__))
    expected = kept(probe.native(native()))
    lanes = probe.candidates(lambda selected, gpu: program(), ['images'], batch=1,
                             parse=lambda text, selected: ['\n'.join(kept(text))])
    probe.compare(['\n'.join(expected)], lanes, describe=lambda index: 'images')
    probe.finish(lines=len(expected))


if __name__ == '__main__':
    main()
