#!/usr/bin/env python3
"""Compare checked formats 1..8, exact ImageFormat pairs, chains and factory bounds."""
import hashlib
import json
import random
import struct
import sys

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER
import probekit
from probekit import ProbeFailure


BYTES_PER_PIXEL = {1:1, 2:2, 3:2, 4:3, 5:2, 6:2, 7:4, 8:4}


def word_bytes(words):
    return list(struct.pack('<'+'I'*len(words), *words))


def r32_words():
    """Inputs only: neighbors of native truncation/packed-rounding boundaries."""
    words = {0, 0x80000000, 1, 2, 0x007fffff, 0x00800000,
             0x00800001, 0x3effffff, 0x3f000000, 0x3f000001,
             0x3f7ffffe, 0x3f7fffff, 0x3f800000}
    for limit, offset in ((255, 0), (31, 0.5), (63, 0.5), (15, 0.5)):
        for level in range(1 if offset == 0 else 0, limit):
            bits = struct.unpack('<I', struct.pack('<f', (level+offset)/limit))[0]
            words.update((bits-1, bits, bits+1))
    rng = random.Random(0xF32)
    words.update(rng.randrange(0x3f800001) for _ in range(32))
    return sorted(words)


def input_expression(case):
    if 'repeat_words' in case:
        return f'repeat_bytes({case["repeat_count"]}n, {bend_bytes(word_bytes(case["repeat_words"]))}, Nil{{}})'
    return bend_bytes(case['bytes'])


def cases():
    rng = random.Random(0xF07A7)
    result = []
    for source, bpp in BYTES_PER_PIXEL.items():
        # Preserve the historical seven-format data and every previous chain.
        if source == 8:
            data = word_bytes([0,0x80000000,1,0x007fffff,0x00800000,0x3b808081,
                               0x3e800000,0x3effffff,0x3f000000,0x3f000001,0x3f7fffff,0x3f800000])
        else:
            data = [rng.randrange(256) for _ in range(12*bpp)]
            data[:bpp] = [0]*bpp
            data[bpp:2*bpp] = [255]*bpp
            data[2*bpp:3*bpp] = [1,*([0]*(bpp-1))]
            if source == 7:
                data[12:24] = [127,128,129,49, 17,63,201,50, 17,63,201,51]
        for target in range(9):
            result.append(dict(width=4,height=3,source=source,bytes=data,targets=[target],bridge=False))
        chain = [3,1,2,5,6,4,7,8]
        for count in range(2,len(chain)+1):
            result.append(dict(width=4,height=3,source=source,bytes=data,targets=chain[:count],bridge=False))
        result.append(dict(width=4,height=3,source=source,bytes=data,targets=[0],bridge=True))
        result.append(dict(width=4,height=3,source=source,bytes=data,targets=[8,7,8,source],bridge=False))
        if source in (6,7):
            for count in range(2,4):
                result.append(dict(width=4,height=3,source=source,bytes=data,targets=[6,5,7][:count],bridge=False))
    words = r32_words()
    for targets in ([0], [8], [1], [2], [3], [4], [5], [6], [7], [7,8], [1,8,1]):
        result.append(dict(width=len(words),height=1,source=8,bytes=word_bytes(words),targets=targets,bridge=False))
    # Full byte gray ramps plus independent RGB/alpha ramps exercise encode8's order.
    for source in (1,2,4,7):
        data = []
        for i in range(256):
            data.extend({1:[i],2:[i,255-i],4:[i,255-i,i^85],7:[i,255-i,i^85,i]}[source])
        result.append(dict(width=16,height=16,source=source,bytes=data,targets=[8],bridge=False))
    # A non-fused luminance discriminator; expected bits come only from pinned native.
    result.append(dict(width=1,height=1,source=4,bytes=[0,17,51],targets=[8],bridge=False))
    # Regression for recursive JS sample validation: compact generated input,
    # complete native output and exact no-op words, above the observed stack limit.
    pattern = [0,0x80000000,1,0x3f800000]
    result.append(dict(width=256,height=129,source=8,bytes=word_bytes(pattern*8256),
                       repeat_words=pattern,repeat_count=8256,targets=[0,8],bridge=False))
    return result


def invalid_cases():
    base = dict(width=1,height=1,source=8,bytes=word_bytes([0x3f000000]))
    controls = [dict(base,bytes=data) for data in ([],[0],[0,0,0],base['bytes']+[0],
                [0,0,0,256],[0,0,0,0xffffffff])]
    controls += [dict(base,**change) for change in (dict(width=0),dict(height=0),
                 dict(width=4097),dict(height=4097),dict(width=0xffffffff),
                 dict(source=0),dict(source=9),dict(source=0xffffffff))]
    controls.append(dict(base,source=9,bytes=word_bytes([0x3f000000]*3)))
    invalid_words = [0x80000001,0x807fffff,0xbf000000,0x3f800001,0x7f7fffff,
                     0x7f800000,0xff800000,0x7fc00000,0x7f800001,0xffc12345]
    for word in invalid_words:
        controls.append(dict(base,bytes=word_bytes([word])))
        controls.append(dict(base,width=3,bytes=word_bytes([0,word,0x3f800000])))
        controls.append(dict(base,width=3,bytes=word_bytes([0,0x3f800000,word])))
    return controls


def output_format(case):
    target = case['source']
    for value in case['targets']:
        if value:
            target = value
    return 7 if case['bridge'] else target


def parse_rows(text, inputs, controls=()):
    rows, header, payload = [], None, []
    for line in text.splitlines():
        row = json.loads(line)
        if header is not None:
            if row == 'end':
                rows.append(dict(header,bytes=payload))
                header, payload = None, []
            elif type(row) is list and 1 <= len(row) <= 256 and all(type(v) is int and 0 <= v <= 255 for v in row):
                payload.extend(row)
            else:
                raise ValueError('Malformed ImageFormat byte chunk')
        elif type(row) is dict and 'chunked' in row:
            if set(row) != {'width','height','format','chunked'} or row['chunked'] is not True:
                raise ValueError('Malformed ImageFormat chunk header')
            header = {key:row[key] for key in ('width','height','format')}
        else:
            rows.append(row)
    if header is not None:
        raise ValueError('Unterminated ImageFormat byte chunks')
    if len(rows) != len(inputs)+len(controls):
        raise ValueError(f'Incomplete ImageFormat result count: {len(rows)} != {len(inputs)+len(controls)}')
    for index, (case, row) in enumerate(zip(inputs, rows)):
        format = output_format(case)
        if (type(row) is not dict or set(row) != {'width','height','format','bytes'} or
            any(type(row[key]) is not int for key in ('width','height','format')) or
            (row['width'],row['height'],row['format']) != (case['width'],case['height'],format) or
            type(row['bytes']) is not list or
            len(row['bytes']) != case['width']*case['height']*BYTES_PER_PIXEL[format] or
            any(type(value) is not int or not 0 <= value <= 255 for value in row['bytes'])):
            raise ValueError(f'Malformed ImageFormat output at case {index}')
        if not case['bridge'] and all(target in (0,case['source']) for target in case['targets']):
            if row['bytes'] != case['bytes']:
                raise ValueError(f'ImageFormat no-op changed exact source words at case {index}')
    for row in rows[len(inputs):]:
        if type(row) is not dict or set(row) != {'rejected'} or row['rejected'] is not True:
            raise ValueError('Invalid ImageFormat factory control was accepted or malformed')
    return rows


def reference_program(inputs):
    lines = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
             'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in inputs:
        lines.append('{')
        if 'repeat_words' in case:
            lines += ['unsigned words[]={'+','.join(map(str,case['repeat_words']))+'};',
                      f'unsigned char input[{len(case["bytes"])}];',
                      f'for(int i=0;i<{case["width"]*case["height"]};i++)memcpy(input+4*i,&words[i%{len(case["repeat_words"])}],4);']
        else:
            lines.append('unsigned char input[]={'+','.join(map(str,case['bytes']))+'};')
        lines += [f'Image image={{malloc(sizeof(input)),{case["width"]},{case["height"]},1,{case["source"]}}};',
                  'if(!image.data)return 2;memcpy(image.data,input,sizeof(input));']
        for target in case['targets']:
            lines += [f'ImageFormat(&image,{target});']
        if case['bridge']:
            lines += ['ImageFormat(&image,7);']
        lines += ['if(!image.data)return 3;',
                  'printf("{\\"width\\":%d,\\"height\\":%d,\\"format\\":%d,\\"bytes\\":[",image.width,image.height,image.format);',
                  'int size=GetPixelDataSize(image.width,image.height,image.format);',
                  'for(int i=0;i<size;i++)printf("%s%u",i?",":"",((unsigned char*)image.data)[i]);',
                  'puts("]}");UnloadImage(image);','}']
    return '\n'.join(lines+['}'])+'\n'


def candidate_program(actions, gpu=False):
    """Conversions then factory controls, one ('input'|'control', case) action per output row."""
    program = '''import Base
import ../../jonlib.bend as J
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def repeat_bytes(n: Nat, +chunk: +List<U32>, values: +List<U32>) -> +List<U32>:
  match n:
    case 0n: List.reverse(&2, U32, values)
    case 1n+rest: repeat_bytes(rest, chunk, reverse_into(chunk, values))
def chain(targets: +List<U32>, result: Result<&1, &1, J.Image.Formatted & J.Pixel.Error, J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match targets result:
    case _ Fail{_}: None{}
    case Nil{} Done{image}: Some{image}
    case Con{target, rest} Done{image}: chain(rest, J.Image.Formatted.convert(image, target))
def created(result: Maybe<J.Image.Formatted>, targets: +List<U32>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: chain(targets, Done{image})
def bridged(bridge: Bool, result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match bridge result:
    case False{} _: result
    case True{} None{}: None{}
    case True{} Some{image}: Some{J.Surface.to_formatted(J.Image.Formatted.to_surface(image))}
def calculate(width: U32, height: U32, format: U32, bytes: +List<U32>, targets: +List<U32>, bridge: Bool) -> Maybe<J.Image.Formatted>:
  bridged(bridge, created(J.Image.Formatted.from_bytes(width, height, format, bytes), targets))
def emit(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  do IO<Unit>:
    IO.print("{\\\"width\\\":" ++ U32.show(width) ++ ",\\\"height\\\":" ++ U32.show(height) ++ ",\\\"format\\\":" ++ U32.show(format) ++ ",\\\"chunked\\\":true}")
    emit_bytes(~&1, bytes)
def observed(result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid image-format request rejected")
    case Some{image}: emit(J.Image.Formatted.export(image))
def rejected(result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.print("{\\"rejected\\":true}")
    case Some{_}: IO.die(Unit, 1, "invalid image-format factory accepted")
def main() -> IO(Unit):
  do IO<Unit>:
'''
    program = program.replace('def chain(', BEND_EMITTER+'def chain(', 1)
    bang = '!' if gpu else ''
    for kind, case in actions:
        if kind == 'input':
            targets = ','.join(map(str,case['targets']))
            program += f'    observed(calculate{bang}({case["width"]}, {case["height"]}, {case["source"]}, {input_expression(case)}, [{targets}], {"True{}" if case["bridge"] else "False{}"}))\n'
        else:
            program += f'    rejected(J.Image.Formatted.from_bytes{bang}({case["width"]}, {case["height"]}, {case["source"]}, {bend_bytes(case["bytes"])}))\n'
    return program


def main():
    probe = probekit.Probe('image-format', probekit.arguments(__doc__))
    if sys.byteorder != 'little':
        raise ProbeFailure('Current formatted-image profile requires a little-endian reference')
    inputs, controls = cases(), invalid_cases()
    reference_text = probe.native(reference_program(inputs))
    expected = parse_rows(reference_text, inputs)
    actions = [('input', case) for case in inputs]+[('control', case) for case in controls]

    def parse(text, selected):
        return parse_rows(text, [c for k, c in selected if k == 'input'], [c for k, c in selected if k == 'control'])

    # One program as before; candidate rows pass the same strict shape/no-op parser.
    lanes = probe.candidates(candidate_program, actions, batch=len(actions), parse=parse)
    probe.compare(expected+[dict(rejected=True) for _ in controls], lanes, lambda i: f'{actions[i][0]} {i}')
    probe.finish(format_pairs=64, cases=len(inputs), factory_controls=len(controls), r32_boundary_samples=len(r32_words()),
                 checked_bytes=sum(len(row['bytes']) for row in expected),
                 inputs_sha256=hashlib.sha256(json.dumps([inputs,controls]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(reference_text.encode()).hexdigest())


if __name__ == '__main__':
    main()
