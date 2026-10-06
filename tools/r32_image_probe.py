#!/usr/bin/env python3
"""Check exact R32 observations, ownership, distinct memory/file PNG and rejections.

Pure operations run on CPU/JS and optionally forced Metal. File IO runs only on
CPU/JS. Packed memory PNG, formatted format-9 loading, out-of-domain FloatRGB->R32 and GetPixelColor remain
explicit Jonlib rejection contracts, not assertions of native equivalence.
"""
import hashlib
import json
import re
import struct
import sys
import zlib

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER, parse_results
from conformance import f32
from image_format_probe import r32_words, word_bytes
import probekit
from probekit import ProbeFailure


SELECTORS = (-32767, 0, 1, 2, 3, 32767)
# Bound compiler emission memory without trimming fixtures or observations.
BATCH_OPERATIONS = 8


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
        for kind in ('png','code','raw','memory_png','convert_reject'):
            result.append(dict(kind=kind,case=case))
    result.extend(dict(kind='packed_memory_reject',case=dict(id=f'packed-{format}',
                  width=1,height=1,format=format,bytes=[0x31,0xf8])) for format in (3,5,6))
    source = cases[1]
    result.extend(dict(kind='point_reject',case=source,x=x,y=y) for x,y in
                  ((source['width'],0),(0,source['height']),(0xffffffff,0)))
    result.extend(dict(kind='channel_reject',case=source,bits=bits) for bits in
                  (0x3f000000,0x47000000,0xc7000000,0x7f800000,0x7fc00000,0x80000001))
    result.extend((dict(kind='independent',case=cases[0]),dict(kind='float_reject'),dict(kind='pixel_reject')))
    return result


def image_row(case):
    return list(struct.pack('<III',case['width'],case['height'],case.get('format',8)))+case['bytes']


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
            'memory_png': lambda:[dict(kind='png',width=case['width'],height=case['height']),dict(kind='exact',value=case['bytes'])],
            'code': lambda:[dict(kind='code')],
            'raw': lambda:[dict(kind='exact',value=case['bytes'])],
            'packed_memory_reject': lambda:[owner],
            'convert_reject': lambda:[owner],
            'point_reject': lambda:[dict(kind='exact',value=[0]),owner],
            'channel_reject': lambda:[owner],
            'independent': lambda:[owner,dict(kind='exact',value=list(struct.pack('<III',1,1,1))+[0])],
            'float_reject': lambda:[dict(kind='exact',value=list(struct.pack('<6I',1,1,9,0x80000000,0x80000001,0x3f400000)))],
            'pixel_reject': lambda:[dict(kind='exact',value=[1])],
        }[kind]()
        result.extend(dict(row,operation=index,operation_kind=kind) for row in rows)
    return result


def valid_png(row, width, height):
    """Validate the complete pinned-writer RGBA8 container, including chunk CRCs."""
    data = bytes(row)
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return False
    offset, parts = 8, []
    while offset < len(data):
        if len(data)-offset < 12:
            return False
        size = struct.unpack_from('>I',data,offset)[0]
        end = offset+12+size
        if end > len(data):
            return False
        kind, payload = data[offset+4:offset+8], data[offset+8:end-4]
        if zlib.crc32(kind+payload) != struct.unpack_from('>I',data,end-4)[0]:
            return False
        parts.append((kind,payload))
        offset = end
    return (len(parts) == 3 and [kind for kind,_ in parts] == [b'IHDR',b'IDAT',b'IEND']
            and parts[0][1] == struct.pack('>IIBBBBB',width,height,8,6,0,0,0)
            and bool(parts[1][1]) and parts[2][1] == b'')


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
            valid = valid_png(row,shape['width'],shape['height'])
        elif kind == 'code':
            valid = bool(row) and all(v < 128 for v in row) and re.search(rb'_FORMAT\s+8\b', bytes(row)) is not None
        else:
            raise ValueError('Unknown R32 output schema')
        if not valid:
            raise ValueError(f'R32 output shape/owner differs at result {index} ({shape.get("operation_kind",kind)})')
    return rows


def png_observations(ops, rows):
    """Summarize native PNG observations and guard the raw/normalized distinction."""
    if len(rows) != len(schemas(ops)):
        raise ValueError('Incomplete R32 PNG observation result count')
    result, cursor = {}, 0
    for op in ops:
        kind, case = op['kind'], op.get('case')
        if kind in ('png','memory_png'):
            encoded, decoded = rows[cursor:cursor+2]
            if kind == 'memory_png' and decoded != case['bytes']:
                raise ValueError('R32 memory PNG changed raw little-endian sample bytes')
            if kind == 'png' and (len(decoded) != 4*case['width']*case['height'] or
                                any(decoded[i:i+3] != [0,0,255] for i in range(1,len(decoded),4))):
                raise ValueError('R32 file PNG is not normalized red-only RGBA8')
            result.setdefault(case['id'],{})[kind] = dict(encoded_bytes=len(encoded),decoded_rgba=decoded)
        cursor += len(schemas([op]))
    if 'half' in result and {'png','memory_png'} <= result['half'].keys():
        half = result['half']
        if half['memory_png']['decoded_rgba'] != [0,0,0,63] or half['png']['decoded_rgba'] != [127,0,0,255]:
            raise ValueError('R32 memory/file PNG half-sample discriminator differs')
    return result


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
    (directory/'present-format9.raw').write_bytes(struct.pack('<fff',0.25,0.5,0.75))
    if (directory/'absent-format9.raw').exists():
        raise ValueError('Task-owned missing format-9 fixture unexpectedly exists')


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
                f'Image image={{malloc(sizeof(data)),{case["width"]},{case["height"]},1,{case.get("format",8)}}};',
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
        elif kind == 'memory_png':
            lines.append('int size=0;unsigned char *png=ExportImageToMemory(image,".png",&size);if(!png||size<=0)return 11;bytes(png,size);')
            lines.append('Image decoded=LoadImageFromMemory(".png",png,size);if(!decoded.data||decoded.width!=image.width||decoded.height!=image.height)return 12;ImageFormat(&decoded,7);')
            lines.append('if(memcmp(decoded.data,image.data,image.width*image.height*4))return 13;bytes(decoded.data,image.width*image.height*4);UnloadImage(decoded);MemFree(png);')
        elif kind in ('code','raw'):
            suffix = 'h' if kind == 'code' else 'raw'
            path = json.dumps(str(directory/(case['id']+'.'+suffix)))
            call = 'ExportImageAsCode' if kind == 'code' else 'ExportImage'
            lines.append(f'if(!{call}(image,{path}))return 10;file({path});')
        elif kind in ('packed_memory_reject','convert_reject','channel_reject'):
            # These are deliberately narrower Jonlib contracts; native source bytes
            # establish retained-owner expectations without invoking unsafe controls.
            lines.append('emit(image);')
        elif kind == 'point_reject':
            lines.append('byte(0);end();emit(image);')
        elif kind == 'float_reject':
            lines.append('{unsigned words[]={0x80000000,0x80000001,0x3f400000};Image image={words,1,1,1,9};emit(image);}')
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
def observe_memory_reject(result: Maybe<Result<&1, &1, J.Image.Formatted & J.Pixel.Error, +List<U32>>>) -> IO(Unit):
  match result:
    case Some{Fail{Tuple{image, J.UnsupportedPixelFormat{}}}}: formatted(J.Image.Formatted.export(image))
    case _: IO.die(Unit, 1, "Packed memory PNG must retain UnsupportedPixelFormat owner")
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
def observe_memory(width: U32, height: U32, result: Maybe<Result<&1, &1, J.Image.Formatted & J.Pixel.Error, +List<U32>>>) -> IO(Unit):
  match result:
    case Some{Done{bytes}}: observe_png(width, height, Some{bytes})
    case _: IO.die(Unit, 1, "R32 memory PNG source rejected")
def code(path: String, result: Maybe<J.Image.Formatted>) -> Maybe<Result<&1, &1, J.Image.Formatted, String>>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Image.Formatted.to_code(image, path)}
def observe_code(result: Maybe<Result<&1, &1, J.Image.Formatted, String>>) -> IO(Unit):
  match result:
    case Some{Done{text}}: emit_bytes(~&1, text_bytes(text, Nil{}))
    case _: IO.die(Unit, 1, "R32 code export rejected")
def reject_float() -> Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>:
  J.Image.FloatRGB.to_formatted(J.FloatRGB{1, 1, Array.new(M.Vector3, 0n, M.Vector3{H.float_bits(2147483648), H.float_bits(2147483649), 0.75})}, 8)
def observe_float_reject(result: Result<&1, &1, J.Image.FloatRGB, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{image}: float_image(image)
    case _: IO.die(Unit, 1, "Out-of-domain FloatRGB to format8 must retain owner")
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
    return f'J.Image.Formatted.from_bytes({case["width"]}, {case["height"]}, {case.get("format",8)}, {bend_bytes(case["bytes"])})'


def candidate_program(ops, gpu, directory, raw_load_controls=True):
    """Pure operations (forced '!' calls on GPU); CPU/JS also write files and run raw-load controls."""
    bang = '!' if gpu else ''
    body = BEND_PREAMBLE.replace('BANG',bang)
    if not gpu:
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
        elif kind == 'memory_png':
            line = f'observe_memory({case["width"]}, {case["height"]}, memory{bang}({image}))'
        elif kind == 'packed_memory_reject':
            line = f'observe_memory_reject(memory{bang}({image}))'
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
    if not gpu:
        for op in ops:
            if op['kind'] in ('png','raw','code'):
                kind, case = op['kind'], op['case']
                number,suffix = {'png':(0,'png'),'raw':(1,'raw'),'code':(2,'h')}[kind]
                path = json.dumps(str(directory/(case['id']+'.'+suffix)))
                body += f'    save({number}, {path}, {image_expr(case)})\n'
        # Test a present payload and an absent path with unsupported format 9: rejection
        # must happen before file opening, and does not claim native load parity.
        if raw_load_controls:
            for name in ('present-format9.raw','absent-format9.raw'):
                path = json.dumps(str(directory/name))
                body += f'    IO.bind(Result<&1, &1, J.Image.RawLoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_raw({path}, 1, 1, 9, 0), raw_load_rejected)\n'
    return body


FILE_SUFFIX = {'png':'png','code':'h','raw':'raw'}
RAW_CONTROLS = dict(kind='raw_load_controls')


def main():
    probe = probekit.Probe('r32-image', probekit.arguments(__doc__))
    if sys.byteorder != 'little':
        raise ProbeFailure('Current R32 profile requires a little-endian reference')
    work, cases = probe.work, fixtures()
    ops = operations(cases)
    reference_dir = work/'reference-files';reference_dir.mkdir(exist_ok=True)
    text = probe.native(reference_program(ops,reference_dir))
    expected = parse_rows(text,schemas(ops));files = file_expectations(ops,expected)
    png_profiles = png_observations(ops,expected)
    verify_files(reference_dir,files)
    directory = work/'files';prepare_files(directory,files)
    # One action per operation (its result rows); CPU/JS rows of file operations also
    # carry the write status and the complete file this lane wrote. The final action
    # stands for the two raw-load controls, which CPU/JS run after the last batch's writes.
    actions,cpu,gpu,cursor = ops+[RAW_CONTROLS],[],[],0
    for op in ops:
        rows = expected[cursor:cursor+len(schemas([op]))];cursor += len(rows)
        gpu.append(rows)
        cpu.append(rows+([[1],list(files[f'{op["case"]["id"]}.{FILE_SUFFIX[op["kind"]]}'])] if op['kind'] in FILE_SUFFIX else []))
    cpu.append([[1],[1]]);gpu.append(None)

    def render(selected,gpu):
        return candidate_program([a for a in selected if a is not RAW_CONTROLS],gpu,directory,RAW_CONTROLS in selected)

    def parse_lane(text,selected,lane):
        rows,grouped = parse_results(text),[]
        for op in selected:
            if op is not RAW_CONTROLS:
                count = len(schemas([op]));grouped.append(rows[:count]);rows = rows[count:]
        for index,op in enumerate(selected if lane != 'gpu' else ()):
            if op is RAW_CONTROLS:
                grouped.append(rows[:2]);rows = rows[2:]
            elif op['kind'] in FILE_SUFFIX:
                path = directory/f'{op["case"]["id"]}.{FILE_SUFFIX[op["kind"]]}'
                # Read and remove the file so every lane must write it again.
                grouped[index] += [rows[0] if rows else None,list(path.read_bytes()) if path.is_file() else None]
                rows = rows[1:];path.unlink(missing_ok=True)
        if lane == 'gpu' and RAW_CONTROLS in selected:
            grouped.append(None)
        if rows:
            raise ProbeFailure(f'{lane}: {len(rows)} unexpected trailing R32 output rows')
        return grouped

    lanes = probe.candidates(render,actions,batch=BATCH_OPERATIONS,parse_lane=parse_lane)
    describe = lambda i:f'{actions[i]["kind"]} {actions[i].get("case",{}).get("id","")}'
    probe.compare(cpu,{lane:rows for lane,rows in lanes.items() if lane != 'gpu'},describe)
    if 'gpu' in lanes:
        probe.compare(gpu,{'gpu':lanes['gpu']},describe)
    probe.finish(source_format=8,fixtures=len(cases),source_pixels=sum(c['width']*c['height'] for c in cases),
                 pure_operations=len(ops),pure_results=len(expected),file_exports=len(files),
                 memory_png_images=sum(op['kind'] == 'memory_png' for op in ops),
                 packed_memory_rejections=sum(op['kind'] == 'packed_memory_reject' for op in ops),
                 png_profiles={name:{kind:dict(encoded_bytes=profile['encoded_bytes'],decoded_bytes=len(profile['decoded_rgba']))
                                     for kind,profile in profiles.items()} for name,profiles in png_profiles.items()},
                 inputs_sha256=hashlib.sha256(json.dumps(ops).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
