"""Shared driver for original-format (Image.Formatted) memory-decoding probes.

A codec module supplies a Codec: accepted fixtures, checked controls (typed
decode errors), raylib build options, extension tokens and the roles it
exercises. The driver records raylib's raw and RGBA8-normalized LoadImageFromMemory
output for every fixture (plus each alias token, which must equal raw), then
compares every Jonlib entry point on CPU-1/CPU-2/JavaScript:

  raw            Image.Formatted.decode_<codec>               -> native raw bytes
  bridge         raw -> Surface -> Formatted                  -> normalized RGBA8
  surface        Surface.decode_<codec>                       -> normalized RGBA8
  factory        Image.Formatted.from_bytes(native raw)       -> native raw bytes
  owner          bounded/unbounded Formatted.get reads        -> native raw bytes
  raw-roundtrip  export then from_bytes                       -> native raw bytes
  dispatch-<t>   Surface.decode_image(".<t>")                 -> normalized RGBA8
  uncontracted / fused  Surface.decode_image_for(profile)     -> normalized RGBA8
  formatted-error / surface-error  typed DecodeError codes on checked controls

Controls flagged native=True are additionally loaded by raylib, which must reject them.
"""
from dataclasses import dataclass, field
import hashlib
import json
from typing import Callable, Optional

import probekit
from probekit import ProbeFailure

RAW_ROLES = {'raw', 'factory', 'owner', 'raw-roundtrip'}
ERROR_ROLES = ('formatted-error', 'surface-error')
CHANNEL_BYTES = {1: 1, 2: 2, 4: 3, 7: 4}


@dataclass
class Codec:
    name: str                       # decode_<name> in Jonlib; also the probe name prefix
    token: str                      # primary native/dispatch token, e.g. '.bmp'
    aliases: tuple                  # extra native tokens observed for extended cases ('.BMP',)
    contraction_token: str          # token passed to decode_image_for
    formats: dict                   # native channels -> raylib pixel format
    fixtures: Callable              # () -> [dict(id, bytes, width, height, channels, extended)]
    controls: Callable              # () -> [dict(id, bytes, error[, native])]
    roles: tuple = ('raw', 'bridge', 'surface', 'factory', 'owner')
    extended_roles: Optional[tuple] = None   # default: a dispatch role per token, then both profiles
    raylib_options: tuple = ()
    batch: int = 32
    source_limit: Optional[int] = 196_608
    native_batch: Optional[int] = None   # split the C reference when fixtures are large
    qualification: Optional[tuple] = None  # (C program, expected stdout JSON object)
    little_endian: bool = True
    describe: str = ''
    extra: dict = field(default_factory=dict)

    @property
    def dispatch_roles(self):
        return tuple('dispatch-' + t[1:] for t in (self.token, *self.aliases))


C_PREFIX = r'''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
static int little_endian(void){uint16_t word=1;return *(unsigned char *)&word==1;}
static void emit(const unsigned char *p,int n){for(int start=0;start<n;start+=256){putchar('[');for(int i=start;i<n&&i<start+256;i++)printf("%s%u",i==start?"":",",p[i]);puts("]");}puts("\"end\"");}
static void observed(const char *id,const char *role,Image image){
  printf("{\"id\":\"%s\",\"role\":\"%s\",\"width\":%d,\"height\":%d,\"mipmaps\":%d,\"format\":%d}\n",id,role,image.width,image.height,image.mipmaps,image.format);
  emit(image.data,GetPixelDataSize(image.width,image.height,image.format));
}
'''

BEND_PRELUDE = r'''import Base
import ../../jonlib.bend as J
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def repeat_input(n: Nat, +value: U32, values: +List<U32>) -> +List<U32>:
  match n:
    case 0n: values
    case 1n+rest: repeat_input(rest, value, Con{value, values})
def words.read(+format: U32, state: Array<U32> & U32) -> Array<U32> & Bool:
  (pixels, +word) = state
  (pixels, (U32.is_eq(format, 1) && (word <= 255 : U32)) || (U32.is_eq(format, 2) && (word <= 65535 : U32)) || (U32.is_eq(format, 4) && (word <= 16777215 : U32)) || U32.is_eq(format, 7))
def words(n: Nat, +index: U32, +format: U32, state: Array<U32> & Bool) -> Array<U32> & Bool:
  match n state:
    case _ Tuple{pixels, False{}}: (pixels, False{})
    case 0n Tuple{pixels, True{}}: (pixels, True{})
    case 1n+rest Tuple{pixels, True{}}: words(rest, (index + 1 : U32), format, words.read(format, Array.get(U32, pixels, index)))
def checked.words(width: U32, height: U32, format: U32, state: Array<U32> & Bool) -> Maybe<J.Image.Formatted>:
  match state:
    case Tuple{pixels, True{}}: Some{J.FormattedImage{width, height, format, pixels}}
    case _: None{}
def checked(image: J.Image.Formatted) -> Maybe<J.Image.Formatted>:
  J.FormattedImage{+width, +height, +format, pixels} = image
  checked.words(width, height, format, words(U32.to_nat((width * height : U32)), 0, format, (pixels, True{})))
def decoded(result: Result<&1, &1, J.Image.DecodeError, J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: checked(image)
def surface(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{J.Surface.to_formatted(image)}
def bridge(result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Surface.to_formatted(J.Image.Formatted.to_surface(image))}
def owner.got(expected: Maybe<&2, U32>, result: J.Image.Formatted & Maybe<&2, U32>) -> Maybe<J.Image.Formatted>:
  match expected result:
    case None{} Tuple{image, None{}}: Some{image}
    case Some{wanted} Tuple{image, Some{value}}: Bool.pick(Maybe<J.Image.Formatted>, U32.is_eq(wanted, value), Some{image}, None{})
    case _ _: None{}
def owner.read(result: Maybe<J.Image.Formatted>, x: U32, y: U32, expected: Maybe<&2, U32>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: owner.got(expected, J.Image.Formatted.get(image, x, y))
def owner(result: Maybe<J.Image.Formatted>, +width: U32, +height: U32, first: U32, last: U32) -> Maybe<J.Image.Formatted>:
  image = owner.read(result, 0, 0, Some{first})
  image = owner.read(image, (width - 1 : U32), (height - 1 : U32), Some{last})
  image = owner.read(image, width, 0, None{})
  image = owner.read(image, 0, height, None{})
  image = owner.read(image, 4294967295, 0, None{})
  owner.read(image, 0, 4294967295, None{})
def roundtrip.bytes(values: List<U32>, bytes: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: List.reverse(&2, U32, bytes)
    case Con{head, tail}: roundtrip.bytes(tail, Con{head, bytes})
def roundtrip.exported(data: (U32 & U32) & (U32 & List<U32>)) -> Maybe<J.Image.Formatted>:
  ((width, height), (format, bytes)) = data
  J.Image.Formatted.from_bytes(width, height, format, roundtrip.bytes(bytes, Nil{}))
def roundtrip(result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: roundtrip.exported(J.Image.Formatted.export(image))
def emit(id: String, role: String, data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  do IO<Unit>:
    IO.print("{\"id\":\"" ++ id ++ "\",\"role\":\"" ++ role ++ "\",\"width\":" ++ U32.show(width) ++ ",\"height\":" ++ U32.show(height) ++ ",\"mipmaps\":1,\"format\":" ++ U32.show(format) ++ "}")
    emit_bytes(~&1, bytes)
def observed(id: String, role: String, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid image or owner invariant rejected")
    case Some{image}: emit(id, role, J.Image.Formatted.export(image))
def error.code(error: J.Image.DecodeError) -> U32:
  match error:
    case J.InvalidImageHeader{}: 0
    case J.InvalidImageByte{}: 1
    case J.UnsupportedImageSize{}: 2
    case J.TruncatedImageData{}: 3
    case J.InvalidImageStream{}: 4
def formatted.error(result: Result<&1, &1, J.Image.DecodeError, J.Image.Formatted>) -> U32:
  match result:
    case Fail{error}: error.code(error)
    case Done{_}: 99
def surface.error(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> U32:
  match result:
    case Fail{error}: error.code(error)
    case Done{_}: 99
def emit.error(id: String, role: String, code: U32) -> IO(Unit):
  IO.print("{\"id\":\"" ++ id ++ "\",\"role\":\"" ++ role ++ "\",\"error\":" ++ U32.show(code) ++ "}")
'''


def compact_segments(data):
    """Runs of >=256 equal bytes become ('repeat', (value, count)); the rest stay literal."""
    result, literal, at = [], [], 0
    while at < len(data):
        end = at + 1
        while end < len(data) and data[end] == data[at]:
            end += 1
        if end - at >= 256:
            if literal:
                result.append(('literal', literal))
                literal = []
            result.append(('repeat', (data[at], end - at)))
        else:
            literal.extend(data[at:end])
        at = end
    if literal:
        result.append(('literal', literal))
    return result


def bend_bytes(values):
    """A byte list literal; long lists are 64-byte chunks (one huge literal overflows the compiler)."""
    if len(values) <= 256:
        return '[' + ','.join(map(str, values)) + ']'
    chunks = ','.join('[' + ','.join(map(str, values[at:at+64])) + ']' for at in range(0, len(values), 64))
    return f'input_bytes([{chunks}], Nil{{}})'


def bend_input(data):
    segments = compact_segments(data)
    if not any(kind == 'repeat' for kind, _ in segments):
        return bend_bytes(data)
    parts = [bend_bytes(v) if kind == 'literal' else f'repeat_input({v[1]}n, {v[0]}, Nil{{}})' for kind, v in segments]
    return 'input_bytes([' + ','.join(parts) + '], Nil{})'


def c_input(data):
    """(declaration, cleanup) defining `data` with exactly these bytes."""
    segments = compact_segments(data)
    if not any(kind == 'repeat' for kind, _ in segments):
        return 'const unsigned char data[]=' + probekit.c_bytes(data) + ';', ''
    lines, at = [f'unsigned char *data=malloc({len(data)});if(!data)return 20;'], 0
    for index, (kind, values) in enumerate(segments):
        if kind == 'repeat':
            lines.append(f'memset(data+{at},{values[0]},{values[1]});')
            at += values[1]
        else:
            lines.append(f'const unsigned char part{index}[]=' + probekit.c_bytes(values) + ';')
            lines.append(f'memcpy(data+{at},part{index},sizeof(part{index}));')
            at += len(values)
    return '\n'.join(lines), 'free(data);'


def validate(codec, cases, controls):
    ids = [c['id'] for c in cases] + [c['id'] for c in controls]
    if not cases or len(ids) != len(set(ids)):
        raise ProbeFailure(f'{codec.name}: empty or duplicate fixture/control IDs')
    for c in cases:
        if c['channels'] not in codec.formats:
            raise ProbeFailure(f'{codec.name}: {c["id"]} has unsupported channels {c["channels"]}')
    for c in controls:
        if c['error'] not in range(5):
            raise ProbeFailure(f'{codec.name}: {c["id"]} has invalid typed error {c["error"]}')


def native_roles(codec, case):
    return ('raw', 'normalized', *(('alias-' + t[1:] for t in codec.aliases) if case['extended'] else ()))


def reference_program(codec, cases, rejected=()):
    lines = [C_PREFIX, 'int main(void){' + ('if(!little_endian())return 10;' if codec.little_endian else '') + 'SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        fmt, ident = codec.formats[c['channels']], json.dumps(c['id'])
        raw_size = c['width'] * c['height'] * CHANNEL_BYTES[fmt]
        check = (f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}'
                 f'||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 3;}}')
        declaration, cleanup = c_input(c['bytes'])
        lines += ['{' + declaration,
                  f'Image image=LoadImageFromMemory("{codec.token}",data,{len(c["bytes"])});if(!image.data)return 2;', check,
                  f'observed({ident},"raw",image);',
                  # The raw observation precedes any normalization.
                  'ImageFormat(&image,7);if(!image.data)return 4;',
                  f'observed({ident},"normalized",image);UnloadImage(image);']
        if c['extended']:
            for token in codec.aliases:
                lines += [f'image=LoadImageFromMemory("{token}",data,{len(c["bytes"])});if(!image.data)return 6;', check,
                          f'observed({ident},"alias-{token[1:]}",image);UnloadImage(image);']
        lines += [cleanup + '}']
    for c in rejected:
        declaration, cleanup = c_input(c['bytes'])
        row = json.dumps(dict(id=c['id'], role='rejected', rejected=True), separators=(',', ':'))
        lines += ['{' + declaration,
                  f'Image image=LoadImageFromMemory("{codec.token}",data,{len(c["bytes"])});if(image.data){{UnloadImage(image);return 7;}}',
                  'puts(' + json.dumps(row) + ');' + cleanup + '}']
    return '\n'.join(lines + ['return 0;}']) + '\n'


def parse_rows(text, expected_heads):
    """Parse framed records: a JSON header line, then (for images) byte chunks and "end"."""
    lines, cursor, rows = text.splitlines(), 0, []
    for head in expected_heads:
        if cursor >= len(lines):
            raise ProbeFailure(f'missing record for {head.get("id")}/{head.get("role")}')
        row = json.loads(lines[cursor])
        cursor += 1
        if isinstance(row, dict) and 'width' in row:
            data = []
            while True:
                if cursor >= len(lines):
                    raise ProbeFailure('unterminated byte record')
                chunk = json.loads(lines[cursor])
                cursor += 1
                if chunk == 'end':
                    break
                data.extend(chunk)
            row = dict(row, bytes=data)
        rows.append(row)
    if cursor != len(lines):
        raise ProbeFailure(f'{len(lines) - cursor} unexpected trailing lines')
    return rows


def expectations(codec, cases, controls, native_rows):
    """Turn native observations into ordered candidate actions with expected rows."""
    reference, cursor = {}, 0
    for c in cases:
        raw, normal = native_rows[cursor:cursor + 2]
        heads = [(row['id'], row['role']) for row in (raw, normal)]
        if heads != [(c['id'], 'raw'), (c['id'], 'normalized')]:
            raise ProbeFailure(f'{codec.name}: native record order differs at {c["id"]}')
        cursor += 2
        if c['extended']:
            for token in codec.aliases:
                if native_rows[cursor] != dict(raw, role='alias-' + token[1:]):
                    raise ProbeFailure(f'{codec.name}: native {token} output differs from {codec.token} for {c["id"]}')
                cursor += 1
        expected_raw = c['width'] * c['height'] * CHANNEL_BYTES[codec.formats[c['channels']]]
        if raw['format'] != codec.formats[c['channels']] or len(raw['bytes']) != expected_raw or normal['format'] != 7:
            raise ProbeFailure(f'{codec.name}: native format/size differs for {c["id"]}')
        reference[c['id']] = (raw, normal)
    rejected = native_rows[cursor:]
    if [r for r in rejected if r.get('role') != 'rejected']:
        raise ProbeFailure(f'{codec.name}: unexpected native records after the fixtures')
    actions = []
    for c in cases:
        raw, normal = reference[c['id']]
        extended = codec.extended_roles if codec.extended_roles is not None else codec.dispatch_roles + ('uncontracted', 'fused')
        roles = codec.roles + (extended if c['extended'] else ())
        for role in roles:
            actions.append(dict(case=c, role=role, expected=dict(raw if role in RAW_ROLES else normal, role=role),
                                normalized=normal['bytes']))
    for c in controls:
        for role in ERROR_ROLES:
            actions.append(dict(case=c, role=role, expected=dict(id=c['id'], role=role, error=c['error'])))
    return actions, len(rejected)


def candidate_program(codec, actions, gpu=False):
    from byte_probe import BEND_EMITTER
    lines = [BEND_PRELUDE.replace('def reverse_into(', BEND_EMITTER + 'def reverse_into(', 1), 'def main() -> IO(Unit):']
    bindings = {}
    for action in actions:
        c = action['case']
        if c['id'] not in bindings:
            bindings[c['id']] = name = f'input{len(bindings)}'
            lines.append(f'  +{name} = {{{bend_input(c["bytes"])} : +List<U32>}}')
    lines.append('  do IO<Unit>:')
    decoder = 'decode_' + codec.name
    for action in actions:
        c, role = action['case'], action['role']
        data, ident = bindings[c['id']], json.dumps(c['id'])
        decode = f'decoded(J.Image.Formatted.{decoder}({data}))'
        if role in ERROR_ROLES:
            mode = role.split('-')[0]
            call = 'J.Image.Formatted' if mode == 'formatted' else 'J.Surface'
            lines.append(f'    emit.error({ident}, {json.dumps(role)}, {mode}.error({call}.{decoder}({data})))')
            continue
        if role == 'raw':
            image = decode
        elif role == 'bridge':
            image = f'bridge({decode})'
        elif role == 'raw-roundtrip':
            image = f'roundtrip({decode})'
        elif role == 'surface':
            image = f'surface(J.Surface.{decoder}({data}))'
        elif role.startswith('dispatch-'):
            image = f'surface(J.Surface.decode_image({json.dumps("." + role[len("dispatch-"):])}, {data}))'
        elif role in ('uncontracted', 'fused'):
            profile = 'UncontractedDecode' if role == 'uncontracted' else 'FusedDecode'
            image = f'surface(J.Surface.decode_image_for(J.{profile}{{}}, {json.dumps(codec.contraction_token)}, {data}))'
        elif role == 'factory':
            image = (f'J.Image.Formatted.from_bytes({c["width"]}, {c["height"]}, {codec.formats[c["channels"]]}, '
                     f'{bend_bytes(action["expected"]["bytes"])})')
        elif role == 'owner':
            normal = action['normalized']
            first, last = int.from_bytes(bytes(normal[:4]), 'big'), int.from_bytes(bytes(normal[-4:]), 'big')
            image = f'owner({decode}, {c["width"]}, {c["height"]}, {first}, {last})'
        else:
            raise ProbeFailure(f'{codec.name}: unknown role {role}')
        lines.append(f'    observed({ident}, {json.dumps(role)}, {image})')
    return '\n'.join(lines) + '\n'


def main(codec, argv=None):
    probe = probekit.Probe(f'{codec.name}-format', probekit.arguments(codec.describe or __doc__, argv=argv),
                           raylib_options=codec.raylib_options)
    cases, controls = codec.fixtures(), codec.controls()
    validate(codec, cases, controls)
    rejected = [c for c in controls if c.get('native')]
    if codec.qualification:
        program, expected = codec.qualification
        if json.loads(probe.native(program, 'qualification')) != expected:
            raise ProbeFailure(f'{codec.name}: native build does not route this format as expected')
    if codec.native_batch:
        text = probe.native_batches(lambda selected: reference_program(codec, selected), cases,
                                    batch=codec.native_batch, source_limit=codec.source_limit)
        if rejected:
            text += probe.native(reference_program(codec, [], rejected), 'reference-rejections')
    else:
        text = probe.native(reference_program(codec, cases, rejected))
    heads = [dict(id=c['id'], role=role) for c in cases for role in native_roles(codec, c)]
    heads += [dict(id=c['id'], role='rejected') for c in rejected]
    native_rows = parse_rows(text, heads)
    actions, native_rejections = expectations(codec, cases, controls, native_rows)

    def parse(text, selected):
        return parse_rows(text, [a['expected'] for a in selected])

    lanes = probe.candidates(lambda selected, gpu: candidate_program(codec, selected, gpu), actions,
                             batch=codec.batch, source_limit=codec.source_limit, parse=parse)
    probe.compare([a['expected'] for a in actions], lanes,
                  describe=lambda i: f'{actions[i]["case"]["id"]}/{actions[i]["role"]}')
    probe.finish(cases=len(cases), controls=len(controls), native_rejections=native_rejections,
                 observations=len(actions), compared_bytes=sum(len(a['expected'].get('bytes', [])) for a in actions),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())
