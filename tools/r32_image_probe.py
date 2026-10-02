#!/usr/bin/env python3
"""Check exact R32 image observations, ownership, file PNG and scoped rejections.

Pure operations run on CPU/JS and optionally forced Metal. File IO runs only on
CPU/JS. Memory PNG, raw loading, FloatRGB->R32 and GetPixelColor remain explicit
Jonlib rejection contracts, not assertions of native support or equivalence.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import struct
import sys

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import BUILD, ROOT, checkout, f32, run, source_gate
from image_format_probe import r32_words, word_bytes


SELECTORS = (-32767, 0, 1, 2, 3, 32767)


def fixtures():
    words = r32_words()
    return [dict(id='half',width=1,height=1,bytes=word_bytes([0x3f000000])),
            dict(id='edges',width=4,height=3,bytes=word_bytes([0,0x80000000,1,2,0x007fffff,
                 0x00800000,0x00800001,0x3e800000,0x3f000000,0x3f000001,0x3f7fffff,0x3f800000])),
            dict(id='boundaries',width=len(words),height=1,bytes=word_bytes(words))]


def operations(cases):
    result = []
    for case in cases:
        for kind in ('float','colors','points'):
            result.append(dict(kind=kind,case=case))
        result.extend(dict(kind='channel',case=case,selected=selected) for selected in SELECTORS)
        for kind in ('png','code','raw','memory_reject','convert_reject'):
            result.append(dict(kind=kind,case=case))
    source = cases[1]
    result.extend(dict(kind='point_reject',case=source,x=x,y=y) for x,y in
                  ((source['width'],0),(0,source['height']),(0xffffffff,0)))
    result.extend(dict(kind='channel_reject',case=source,bits=bits) for bits in
                  (0x3f000000,0x47000000,0xc7000000,0x7f800000,0x7fc00000,0x80000001))
    result.extend((dict(kind='independent',case=cases[0]),dict(kind='float_reject'),dict(kind='pixel_reject')))
    return result


def image_row(case, format=8):
    return list(struct.pack('<III',case['width'],case['height'],format))+case['bytes']


def schemas(ops):
    result = []
    for index, op in enumerate(ops):
        kind, case = op['kind'], op.get('case')
        owner = dict(kind='exact',value=image_row(case)) if case else None
        image = lambda format,bpp: dict(kind='image',width=case['width'],height=case['height'],format=format,size=bpp*case['width']*case['height'])
        rows = {
            'float': lambda:[image(9,12)],
            'colors': lambda:[dict(kind='bytes',size=4*case['width']*case['height'])],
            'points': lambda:[dict(kind='bytes',size=4*case['width']*case['height']),owner],
            'channel': lambda:[owner,image(1,1)],
            'png': lambda:[dict(kind='png',width=case['width'],height=case['height']),dict(kind='bytes',size=4*case['width']*case['height'])],
            'code': lambda:[dict(kind='code')],
            'raw': lambda:[dict(kind='exact',value=case['bytes'])],
            'memory_reject': lambda:[owner],
            'convert_reject': lambda:[owner],
            'point_reject': lambda:[dict(kind='exact',value=[0]),owner],
            'channel_reject': lambda:[owner],
            'independent': lambda:[owner,dict(kind='exact',value=list(struct.pack('<III',1,1,1))+[0])],
            'float_reject': lambda:[dict(kind='exact',value=list(struct.pack('<6I',1,1,9,0x80000000,1,0x3f400000)))],
            'pixel_reject': lambda:[dict(kind='exact',value=[1])],
        }[kind]()
        result.extend(dict(row,operation=index,operation_kind=kind) for row in rows)
    return result


def parse_rows(text, expected_shapes):
    rows = parse_results(text)
    if len(rows) != len(expected_shapes):
        raise ValueError(f'Incomplete R32 result count: {len(rows)} != {len(expected_shapes)}')
    for index,(row,shape) in enumerate(zip(rows,expected_shapes)):
        if type(row) is not list or any(type(v) is not int or not 0 <= v <= 255 for v in row):
            raise ValueError(f'Malformed R32 byte result {index}')
        kind = shape['kind']
        valid = True
        if kind == 'exact':
            valid = row == shape['value']
        elif kind == 'bytes':
            valid = len(row) == shape['size']
        elif kind == 'image':
            valid = row[:12] == list(struct.pack('<III',shape['width'],shape['height'],shape['format'])) and len(row) == 12+shape['size']
        elif kind == 'png':
            valid = len(row) >= 33 and bytes(row[:8]) == b'\x89PNG\r\n\x1a\n' and bytes(row[12:16]) == b'IHDR' and bytes(row[16:24]) == struct.pack('>II',shape['width'],shape['height'])
        elif kind == 'code':
            valid = bool(row) and all(v < 128 for v in row) and re.search(rb'_FORMAT\s+8\b', bytes(row)) is not None
        else:
            raise ValueError('Unknown R32 output schema')
        if not valid:
            raise ValueError(f'R32 output shape/owner differs at result {index} ({shape.get("operation_kind",kind)})')
    return rows


def differences(expected, actual):
    if len(expected) != len(actual):
        raise ValueError('Incomplete R32 comparison result count')
    return [i for i,(a,b) in enumerate(zip(expected,actual)) if a != b]


def file_expectations(ops, rows):
    if len(rows) != len(schemas(ops)):
        raise ValueError('Incomplete R32 file reference result count')
    result, cursor = {}, 0
    for op in ops:
        kind, case = op['kind'], op.get('case')
        if kind in ('png','code','raw'):
            suffix = {'png':'png','code':'h','raw':'raw'}[kind]
            result[f'{case["id"]}.{suffix}'] = bytes(rows[cursor])
        cursor += len(schemas([op]))
    return result


def prepare_files(directory, files):
    directory.mkdir(parents=True,exist_ok=True)
    for name in files:
        (directory/name).unlink(missing_ok=True)


def verify_files(directory, files):
    for name,wanted in files.items():
        path = directory/name
        if not path.is_file() or path.read_bytes() != wanted:
            raise ValueError(f'Complete R32 exported file differs: {name}')


C_PREAMBLE = r'''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int used=0;
static void byte(unsigned v){if(!used)putchar('[');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}
static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}
static void end(void){if(used){puts("]");used=0;}puts("\"end\"");}
static void bytes(const unsigned char *p,int n){for(int i=0;i<n;i++)byte(p[i]);end();}
static void emit(Image image){if(!image.data)exit(2);word(image.width);word(image.height);word(image.format);
int n=GetPixelDataSize(image.width,image.height,image.format);for(int i=0;i<n;i++)byte(((unsigned char*)image.data)[i]);end();}
static void file(const char *path){int n=0;unsigned char *p=LoadFileData(path,&n);if(!p||n<=0)exit(3);bytes(p,n);UnloadFileData(p);}
int main(void){SetTraceLogLevel(LOG_NONE);
'''


def reference_program(ops, directory):
    lines = [C_PREAMBLE]
    for op in ops:
        kind, case = op['kind'], op.get('case')
        if case:
            lines.extend(('{','unsigned char data[]={'+','.join(map(str,case['bytes']))+'};',
                f'Image image={{malloc(sizeof(data)),{case["width"]},{case["height"]},1,8}};',
                'if(!image.data)return 4;memcpy(image.data,data,sizeof(data));'))
        if kind == 'float':
            lines.append('ImageFormat(&image,9);emit(image);')
        elif kind == 'colors':
            lines.append('Color *c=LoadImageColors(image);if(!c)return 5;for(int i=0;i<image.width*image.height;i++)word(ColorToInt(c[i]));end();UnloadImageColors(c);')
        elif kind == 'points':
            lines.append('for(int i=0;i<image.width*image.height;i++)word(ColorToInt(GetImageColor(image,i%image.width,i/image.width)));end();emit(image);')
        elif kind in ('channel','independent'):
            selected = op.get('selected',0)
            lines.append(f'Image channel=ImageFromChannel(image,{selected});if(!channel.data)return 6;')
            if kind == 'independent':
                lines.append('((unsigned char*)channel.data)[0]=0;')
            lines.append('emit(image);emit(channel);UnloadImage(channel);')
        elif kind == 'png':
            path = json.dumps(str(directory/(case['id']+'.png')))
            lines.append(f'if(!ExportImage(image,{path}))return 7;file({path});')
            lines.append(f'Image decoded=LoadImage({path});if(!decoded.data||decoded.width!=image.width||decoded.height!=image.height)return 8;ImageFormat(&decoded,7);')
            lines.append('Color *colors=LoadImageColors(image);if(!colors||memcmp(colors,decoded.data,image.width*image.height*4))return 9;bytes(decoded.data,image.width*image.height*4);UnloadImageColors(colors);UnloadImage(decoded);')
        elif kind in ('code','raw'):
            suffix = 'h' if kind == 'code' else 'raw'
            path = json.dumps(str(directory/(case['id']+'.'+suffix)))
            call = 'ExportImageAsCode' if kind == 'code' else 'ExportImage'
            lines.append(f'if(!{call}(image,{path}))return 10;file({path});')
        elif kind in ('memory_reject','convert_reject','channel_reject'):
            # These are deliberately narrower Jonlib contracts; native source bytes
            # establish retained-owner expectations without invoking unsafe controls.
            lines.append('emit(image);')
        elif kind == 'point_reject':
            lines.append('byte(0);end();emit(image);')
        elif kind == 'float_reject':
            lines.append('{unsigned words[]={0x80000000,1,0x3f400000};Image image={words,1,1,1,9};emit(image);}')
        elif kind == 'pixel_reject':
            lines.append('byte(1);end();')
        else:
            raise ValueError(f'Unknown R32 operation {kind}')
        if case:
            lines.append('UnloadImage(image);}')
    return '\n'.join(lines+['}'])+'\n'


BEND_PREAMBLE = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/hdr.bend as H
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def word_bytes(~q: Quant, n: Nat, +word: U32, values: List<q, U32>) -> List<q, U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(~q, rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def words(values: List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: List.reverse(&1, U32, bytes)
    case Con{word, rest}: words(rest, word_bytes(~&1, 4n, word, bytes))
def rgba(values: List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: List.reverse(&1, U32, bytes)
    case Con{+color, rest}: rgba(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), bytes}}}})
def text_bytes(text: String, values: List<U32>) -> List<U32>:
  match text:
    case SNil{}: List.reverse(&1, U32, values)
    case SCon{character, rest}: text_bytes(rest, Con{Char.to_u32(character), values})
'''+BEND_EMITTER+'''
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "R32 dimensions differ")
def emitted(~q: Quant, width: U32, height: U32, format: U32, bytes: List<q, U32>) -> IO(Unit):
  header = List.reverse(q, U32, word_bytes(~q, 4n, format, word_bytes(~q, 4n, height, word_bytes(~q, 4n, width, Nil{}))))
  emit_bytes(~q, List.append(q, U32, header, bytes))
def formatted(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  emitted(~&1, width, height, format, bytes)
def float_bytes(width: U32, height: U32, result: Result<&1, &1, J.Image.FloatRGB, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "R32 normalized float export rejected")
    case Done{bytes}: emitted(~&2, width, height, 9, bytes)
def float_image(image: J.Image.FloatRGB) -> IO(Unit):
  J.FloatRGB{+width, +height, pixels} = image
  float_bytes(width, height, J.Image.FloatRGB.to_bytes(J.FloatRGB{width, height, pixels}))
def normalized(result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.FloatRGB>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.to_float_rgb(image)}
def observe_float(result: Maybe<J.Image.FloatRGB>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "R32 normalization source rejected")
    case Some{image}: float_image(image)
def bulk(result: Maybe<J.Image.Formatted>) -> Maybe<List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.colors(image)}
def observe_colors(result: Maybe<List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "R32 bulk source rejected")
    case Some{values}: emit_bytes(~&1, words(values, Nil{}))
def read_point(values: List<U32>, result: J.Image.Formatted & Maybe<&2, U32>) -> Maybe<(J.Image.Formatted & List<U32>)>:
  match result:
    case Tuple{source, Some{color}}: Some{(source, Con{color, values})}
    case _: None{}
def points(n: Nat, +index: U32, +width: U32, state: Maybe<(J.Image.Formatted & List<U32>)>) -> Maybe<(J.Image.Formatted & List<U32>)>:
  match n state:
    case _ None{}: None{}
    case 0n _: state
    case 1n+rest Some{Tuple{source, values}}:
      points(rest, (index + 1 : U32), width, read_point(values, J.Image.Formatted.get(source, (index % width : U32), (index / width : U32))))
def walked(result: Maybe<J.Image.Formatted>) -> Maybe<(J.Image.Formatted & List<U32>)>:
  match result:
    case None{}: None{}
    case Some{J.FormattedImage{+width, +height, format, pixels}}:
      points(U32.to_nat((width * height : U32)), 0, width, Some{(J.FormattedImage{width, height, format, pixels}, Nil{})})
def observe_points(result: Maybe<(J.Image.Formatted & List<U32>)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "R32 point observation rejected")
    case Some{Tuple{source, values}}:
      do IO<Unit>:
        emit_bytes(~&1, words(List.reverse(&1, U32, values), Nil{}))
        formatted(J.Image.Formatted.export(source))
def channel(selected: F32, result: Maybe<J.Image.Formatted>) -> Maybe<(J.Image.Formatted & Maybe<J.Image.Formatted>)>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.from_channel(image, selected)}
def observe_channel(reject: Bool, result: Maybe<(J.Image.Formatted & Maybe<J.Image.Formatted>)>) -> IO(Unit):
  match reject result:
    case False{} Some{Tuple{source, Some{gray}}}:
      do IO<Unit>:
        formatted(J.Image.Formatted.export(source))
        formatted(J.Image.Formatted.export(gray))
    case True{} Some{Tuple{source, None{}}}: formatted(J.Image.Formatted.export(source))
    case _ _: IO.die(Unit, 1, "R32 channel acceptance/owner differs")
def altered(result: Maybe<(J.Image.Formatted & Maybe<J.Image.Formatted>)>) -> Maybe<(J.Image.Formatted & Maybe<J.Image.Formatted>)>:
  match result:
    case Some{Tuple{source, Some{J.FormattedImage{width, height, format, pixels}}}}:
      Some{(source, Some{J.FormattedImage{width, height, format, Array.set(U32, pixels, 0, 0)}})}
    case _: None{}
def independent(result: Maybe<J.Image.Formatted>) -> Maybe<(J.Image.Formatted & Maybe<J.Image.Formatted>)>:
  altered(channel(0.0, result))
def get(x: U32, y: U32, result: Maybe<J.Image.Formatted>) -> Maybe<(J.Image.Formatted & Maybe<&2, U32>)>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.get(image, x, y)}
def observe_missing(result: Maybe<(J.Image.Formatted & Maybe<&2, U32>)>) -> IO(Unit):
  match result:
    case Some{Tuple{source, None{}}}:
      do IO<Unit>:
        emit_bytes(~&1, [0])
        formatted(J.Image.Formatted.export(source))
    case _: IO.die(Unit, 1, "R32 out-of-range point accepted")
def memory(result: Maybe<J.Image.Formatted>) -> Maybe<Result<&1, &1, J.Image.Formatted & J.Pixel.Error, +List<U32>>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.to_png(image)}
def observe_memory(result: Maybe<Result<&1, &1, J.Image.Formatted & J.Pixel.Error, +List<U32>>>) -> IO(Unit):
  match result:
    case Some{Fail{Tuple{image, J.UnsupportedPixelFormat{}}}}: formatted(J.Image.Formatted.export(image))
    case _: IO.die(Unit, 1, "R32 memory PNG must retain UnsupportedPixelFormat owner")
def conversion(result: Maybe<J.Image.Formatted>) -> Maybe<Result<&1, &1, J.Image.Formatted & J.Pixel.Error, J.Image.Formatted>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.convert(image, 9)}
def observe_conversion(result: Maybe<Result<&1, &1, J.Image.Formatted & J.Pixel.Error, J.Image.Formatted>>) -> IO(Unit):
  match result:
    case Some{Fail{Tuple{image, J.UnsupportedPixelFormat{}}}}: formatted(J.Image.Formatted.export(image))
    case _: IO.die(Unit, 1, "R32 unsupported conversion owner differs")
def png(result: Maybe<J.Image.Formatted>) -> Maybe<&2, +List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.png.file_bytes(image)}
def raw(result: Maybe<J.Image.Formatted>) -> Maybe<&2, +List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.raw_bytes(image)}
def observe_bytes(result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "R32 byte export source rejected")
    case Some{bytes}: emit_bytes(~&2, bytes)
def decoded(width: U32, height: U32, result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "R32 PNG round trip rejected")
    case Done{J.Surface{+w, +h, pixels}}:
      do IO<Unit>:
        checked(U32.is_eq(width, w) && U32.is_eq(height, h))
        emit_bytes(~&1, rgba(J.Surface.colors(J.Surface{w, h, pixels}), Nil{}))
def observe_png(width: U32, height: U32, result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "R32 file PNG source rejected")
    case Some{+bytes}:
      do IO<Unit>:
        emit_bytes(~&2, bytes)
        decoded(width, height, J.Surface.decode_pngBANG(bytes))
def code(path: String, result: Maybe<J.Image.Formatted>) -> Maybe<Result<&1, &1, J.Image.Formatted, String>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.to_code(image, path)}
def observe_code(result: Maybe<Result<&1, &1, J.Image.Formatted, String>>) -> IO(Unit):
  match result:
    case Some{Done{text}}: emit_bytes(~&1, text_bytes(text, Nil{}))
    case _: IO.die(Unit, 1, "R32 code export rejected")
def reject_float() -> Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>:
  J.Image.FloatRGB.to_formatted(J.FloatRGB{1, 1, Array.new(M.Vector3, 0n, M.Vector3{H.float_bits(2147483648), H.float_bits(1), 0.75})}, 8)
def observe_float_reject(result: Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{image}: float_image(image)
    case _: IO.die(Unit, 1, "FloatRGB to format8 expanded beyond this slice")
def pixel_result(result: Result<&2, &2, J.Pixel.Error, U32>) -> Bool:
  match result:
    case Fail{J.UnsupportedPixelFormat{}}: True{}
    case _: False{}
def pixel_rejected() -> Bool:
  pixel_result(J.Pixel.get_color([0,0,0,63], 8))
'''


BEND_IO = '''def written(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Done{_}: emit_bytes(~&1, [1])
    case Fail{_}: IO.die(Unit, 1, "R32 file write failed")
def code_written(result: Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: emit_bytes(~&1, [1])
    case Fail{_}: IO.die(Unit, 1, "R32 code file write failed")
def save(kind: U32, path: String, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match kind result:
    case _ None{}: IO.die(Unit, 1, "R32 file source rejected")
    case 0 Some{image}: IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, J.Image.Formatted.write_png(image, path), written)
    case 1 Some{image}: IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, J.Image.Formatted.write_raw(image, path), written)
    case _ Some{image}: IO.bind(Result<&1, &1, J.Image.Formatted.CodeWriteError, Unit>, Unit, J.Image.Formatted.write_code(image, path), code_written)
def raw_load_rejected(result: Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{J.InvalidRawRequest{}}: emit_bytes(~&1, [1])
    case _: IO.die(Unit, 1, "R32 raw loading expanded beyond this slice")
'''


def image_expr(case):
    return f'J.Image.Formatted.from_bytes({case["width"]}, {case["height"]}, 8, {bend_bytes(case["bytes"])})'


def candidate_program(ops, lane, directory):
    bang = '!' if lane == 'metal' else ''
    body = BEND_PREAMBLE.replace('BANG',bang)
    if lane != 'metal':
        body += BEND_IO
    body += 'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    for op in ops:
        kind, case = op['kind'], op.get('case')
        image = image_expr(case) if case else ''
        if kind == 'float':
            line = f'observe_float(normalized{bang}({image}))'
        elif kind == 'colors':
            line = f'observe_colors(bulk{bang}({image}))'
        elif kind == 'points':
            line = f'observe_points(walked{bang}({image}))'
        elif kind in ('channel','channel_reject'):
            selector = f32(op["selected"]) if kind == 'channel' else f'H.float_bits({op["bits"]})'
            line = f'observe_channel({"True" if kind == "channel_reject" else "False"}{{}}, channel{bang}({selector}, {image}))'
        elif kind == 'independent':
            line = f'observe_channel(False{{}}, independent{bang}({image}))'
        elif kind == 'point_reject':
            line = f'observe_missing(get{bang}({op["x"]}, {op["y"]}, {image}))'
        elif kind == 'memory_reject':
            line = f'observe_memory(memory{bang}({image}))'
        elif kind == 'convert_reject':
            line = f'observe_conversion(conversion{bang}({image}))'
        elif kind == 'png':
            line = f'observe_png({case["width"]}, {case["height"]}, png{bang}({image}))'
        elif kind == 'raw':
            line = f'observe_bytes(raw{bang}({image}))'
        elif kind == 'code':
            line = f'observe_code(code{bang}({json.dumps(str(directory/(case["id"]+".h")))}, {image}))'
        elif kind == 'float_reject':
            line = f'observe_float_reject(reject_float{bang}())'
        elif kind == 'pixel_reject':
            line = f'emit_bytes(~&1, [Bool.to_u32(pixel_rejected{bang}())])'
        else:
            raise ValueError(f'Unknown R32 operation {kind}')
        body += '    '+line+'\n'
    if lane != 'metal':
        for op in ops:
            if op['kind'] in ('png','raw','code'):
                kind, case = op['kind'], op['case']
                number,suffix = {'png':(0,'png'),'raw':(1,'raw'),'code':(2,'h')}[kind]
                path = json.dumps(str(directory/(case['id']+'.'+suffix)))
                body += f'    save({number}, {path}, {image_expr(case)})\n'
        # Test both a present valid R32 payload and an absent path: request rejection
        # must happen before file opening, and does not claim native load parity.
        first = next(op['case'] for op in ops if op.get('case'))
        for name in (first['id']+'.raw','absent-r32.raw'):
            path = json.dumps(str(directory/name))
            body += f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw({path}, 1, 1, 8, 0), raw_load_rejected)\n'
    return body


def io_shapes(ops):
    return [dict(kind='exact',value=[1]) for _ in range(sum(op['kind'] in ('png','raw','code') for op in ops)+2)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true',help='Add forced Metal for pure operations only; file IO remains CPU/JS')
    args = parser.parse_args()
    work = BUILD/'r32-image-probe';work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    if sys.byteorder != 'little':
        raise ValueError('Current R32 profile requires a little-endian reference')
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    cases = fixtures();ops = operations(cases);shapes = schemas(ops)
    reference_dir = work/'reference-files';reference_dir.mkdir(exist_ok=True)
    source = work/'reference.c';source.write_text(reference_program(ops,reference_dir))
    binary = work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    text = run([binary]);expected = parse_rows(text,shapes);files = file_expectations(ops,expected)
    verify_files(reference_dir,files)
    report = dict(passed=False,source_format=8,fixtures=len(cases),source_pixels=sum(c['width']*c['height'] for c in cases),
                  pure_operations=len(ops),pure_results=len(expected),file_exports=len(files),
                  memory_png='UnsupportedPixelFormat with exact retained owner',
                  raw_loading='unsupported',float_rgb_target8='unsupported',pixel_get_color8='unsupported',
                  sources=source_gate(),inputs_sha256=hashlib.sha256(json.dumps(ops).encode()).hexdigest(),
                  reference_sha256=hashlib.sha256(text.encode()).hexdigest(),
                  reference_program_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  harness_sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in
                                  ('tools/r32_image_probe.py','tools/image_format_probe.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py','tests/test_r32_harness.py')},lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        directory = work/lane;prepare_files(directory,files)
        source = work/f'{lane}.bend';source.write_text(candidate_program(ops,lane,directory))
        report['lanes'][lane] = dict(passed=False,candidate_program_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        binary = work/('candidate.js' if lane == 'javascript' else 'candidate-'+lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command = ['bun',binary] if lane == 'javascript' else [binary,*(['--gpu','on'] if lane == 'metal' else [])]
        extra_shapes = [] if lane == 'metal' else io_shapes(ops)
        actual = parse_rows(run(command),shapes+extra_shapes)
        wanted = expected+[shape['value'] for shape in extra_shapes]
        delta = differences(wanted,actual)
        if lane != 'metal':
            verify_files(directory,files)
        report['lanes'][lane].update(passed=not delta,result_count=len(actual),different_results=delta,
                                    file_exports=0 if lane == 'metal' else len(files),file_io=lane != 'metal')
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if delta:
            raise ValueError(f'{lane}: R32 exact native differences {delta[:10]}')
        print(f'{lane}: {len(expected)} exact R32 pure observations and {0 if lane == "metal" else len(files)} complete file exports passed',flush=True)
    report['passed'] = True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
