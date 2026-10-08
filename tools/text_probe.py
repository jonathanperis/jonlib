#!/usr/bin/env python3
"""Compare rtext.c's text strings and UTF-8 codepoint functions with Jonlib's
Text, Codepoint and UTF8 functions.

A C interpreter linked against the pinned raylib and a Bend interpreter read
the same binary case files (ASCII, multi-byte, invalid and truncated UTF-8,
empty texts, texts at and beyond the 1024-byte static buffers, many
delimiters, overlapping patterns, buffer writes, printf subsets) and print one
row per case; every Bend lane must print the native rows.

Cases where raylib's C code is undefined (reads or writes outside a string or
buffer, int overflow) are Jonlib None contracts stated in this file; they are
never run against the linked library. Instead the probe extracts the pinned
rtext.c text functions into an AddressSanitizer/UndefinedBehaviorSanitizer
build (when the host compiler supports it), which must run every defined case
cleanly with the linked rows and must report an error for every undefined
case. TextFormat specifications outside the typed subset are None without a
native run. TextToFloat rows hold both contraction profiles: the extracted
source compiled without contraction and with the multiply-add as fmaf, and the
linked result must equal the host's profile. CPU and JavaScript lanes; no GPU
claim.
"""
import hashlib
import json
import math
import os
import random
import struct
import subprocess
from concurrent.futures import ThreadPoolExecutor

import probekit
from probekit import ROOT, ProbeFailure
from conformance import contraction

WORK = '.build/text-probe'
INT_MAX = 2**31 - 1

OPS = ['LoadTextLines', 'TextCopy', 'TextIsEqual', 'TextLength', 'TextFormat', 'TextSubtext', 'TextRemoveSpaces',
       'GetTextBetween', 'TextReplace', 'TextReplaceAlloc', 'TextReplaceBetween', 'TextReplaceBetweenAlloc',
       'TextInsert', 'TextInsertAlloc', 'TextJoin', 'TextSplit', 'TextAppend', 'TextFindIndex', 'TextToUpper',
       'TextToLower', 'TextToPascal', 'TextToSnake', 'TextToCamel', 'TextToInteger', 'TextToFloat', 'LoadUTF8',
       'LoadCodepoints', 'GetCodepointCount', 'GetCodepoint', 'GetCodepointNext', 'GetCodepointPrevious',
       'CodepointToUTF8']
CODE = {name: index + 1 for index, name in enumerate(OPS)}

HARNESS = r'''
#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char *data;
static size_t at;
static unsigned word(void) { unsigned v = data[at] | data[at + 1] << 8 | data[at + 2] << 16 | (unsigned)data[at + 3] << 24; at += 4; return v; }
static void hex(const char *s, size_t n) { putchar('s'); for (size_t i = 0; i < n; i++) printf("%02x", (unsigned char)s[i]); }
static void str(const char *s) { hex(s, strlen(s)); }
static float f32(unsigned b) { float f; memcpy(&f, &b, 4); return f; }
static void format_case(unsigned id);

/* A destination buffer of exactly n bytes. An empty buffer for a write at a
   non-negative position ends at the end of a 1-byte allocation, since some
   sanitizer runtimes leave malloc(0) one usable byte. */
static char *buffer(const unsigned char *raw, unsigned n, int position, char **base) {
  if (n == 0 && position >= 0) { *base = malloc(1); return *base + 1; }
  *base = malloc(n); memcpy(*base, raw, n); return *base;
}

/* C strings are copied up to their first NUL into exact allocations, buffers
   (TextCopy/TextAppend destinations) into exact allocations of every byte. */
static void row(unsigned op, int *in, unsigned ni, char **t, const unsigned char **raw, unsigned *tn, unsigned nt) {
  switch (op) {
  case 1: { int n = 0; char **lines = LoadTextLines(t[0], &n); printf("%d", n); for (int i = 0; i < n; i++) { putchar(' '); str(lines[i]); } UnloadTextLines(lines, n); break; }
  case 2: { char *base = 0, *b = buffer(raw[0], tn[0], 0, &base); int n = TextCopy(b, t[1]); hex(b, tn[0]); printf(" %d", n); free(base); break; }
  case 3: printf("%d", TextIsEqual(t[0], t[1]) ? 1 : 0); break;
  case 4: printf("%u", TextLength(t[0])); break;
  case 5: format_case((unsigned)in[0]); break;
  case 6: str(TextSubtext(t[0], in[0], in[1])); break;
  case 7: str(TextRemoveSpaces(t[0])); break;
  case 8: str(GetTextBetween(t[0], t[1], t[2])); break;
  case 9: str(TextReplace(t[0], t[1], t[2])); break;
  case 10: { char *r = TextReplaceAlloc(t[0], t[1], t[2]); if (r) { str(r); free(r); } else printf("none"); break; }
  case 11: str(TextReplaceBetween(t[0], t[1], t[2], t[3])); break;
  case 12: { char *r = TextReplaceBetweenAlloc(t[0], t[1], t[2], t[3]); if (r) { str(r); free(r); } else printf("none"); break; }
  case 13: str(TextInsert(t[0], t[1], in[0])); break;
  case 14: { char *r = TextInsertAlloc(t[0], t[1], in[0]); str(r); free(r); break; }
  case 15: str(TextJoin(t + 1, (int)nt - 1, t[0])); break;
  case 16: { int n = 0; char **parts = TextSplit(t[0], (char)in[0], &n); printf("%d", n); for (int i = 0; i < n; i++) { putchar(' '); str(parts[i]); } break; }
  case 17: { char *base = 0, *b = buffer(raw[0], tn[0], in[0], &base); int p = in[0]; TextAppend(b, t[1], &p); hex(b, tn[0]); printf(" %d", p); free(base); break; }
  case 18: printf("%d", TextFindIndex(t[0], t[1])); break;
  case 19: str(TextToUpper(t[0])); break;
  case 20: str(TextToLower(t[0])); break;
  case 21: str(TextToPascal(t[0])); break;
  case 22: str(TextToSnake(t[0])); break;
  case 23: str(TextToCamel(t[0])); break;
  case 24: printf("%d", TextToInteger(t[0])); break;
  case 25: { float v = TextToFloat(t[0]); unsigned b; memcpy(&b, &v, 4); printf("%u", b); break; }
  case 26: { char *r = LoadUTF8(in, (int)ni); int size = 0; for (unsigned i = 0; i < ni; i++) { int n = 0; CodepointToUTF8(in[i], &n); size += n; }
             hex(r ? r : "", r ? (size_t)size : 0); UnloadUTF8(r); break; }
  case 27: { int n = 0; int *c = LoadCodepoints(t[0], &n); printf("%d", n); for (int i = 0; i < n; i++) printf(" %d", c[i]); UnloadCodepoints(c); break; }
  case 28: printf("%d", GetCodepointCount(t[0])); break;
  case 29: { int n = 0; int c = GetCodepoint(t[0], &n); printf("%d %d", c, n); break; }
  case 30: { int n = 0; int c = GetCodepointNext(t[0], &n); printf("%d %d", c, n); break; }
  case 31: { int n = 0; int c = GetCodepointPrevious(t[0] + in[0], &n); printf("%d %d", c, n); break; }
  case 32: { int n = 0; const char *u = CodepointToUTF8(in[0], &n); hex(u, (size_t)n); break; }
  }
}

/* argv[1]: case file; argv[2] (optional): run only that case, even if flagged. */
int main(int argc, char **argv) {
  if (argc < 2) return 0;
  SetTraceLogLevel(LOG_NONE);
  FILE *f = fopen(argv[1], "rb");
  if (!f) return 2;
  fseek(f, 0, SEEK_END); long size = ftell(f); fseek(f, 0, SEEK_SET);
  data = malloc((size_t)size);
  if (fread(data, 1, (size_t)size, f) != (size_t)size) return 2;
  fclose(f);
  long only = argc > 2 ? atol(argv[2]) : -1;
  unsigned count = word();
  for (unsigned k = 0; k < count; k++) {
    unsigned length = word(); size_t next = at + length;
    unsigned op = word(), ni = word();
    int *in = malloc((ni + 1) * sizeof(int));
    for (unsigned i = 0; i < ni; i++) in[i] = (int)word();
    unsigned nt = word();
    char **t = malloc((nt + 1) * sizeof(char *));
    const unsigned char **raw = malloc((nt + 1) * sizeof(char *));
    unsigned *tn = malloc((nt + 1) * sizeof(unsigned));
    for (unsigned i = 0; i < nt; i++) {
      tn[i] = word(); raw[i] = data + at;
      size_t c = 0; while (c < tn[i] && raw[i][c]) c++;
      t[i] = malloc(c + 1); memcpy(t[i], raw[i], c); t[i][c] = 0;
      at += tn[i];
    }
    if (only >= 0 ? (long)k == only : !(op & 256)) { row(op & 255, in, ni, t, raw, tn, nt); putchar('\n'); }
    else if (only < 0) puts("skip");
    for (unsigned i = 0; i < nt; i++) free(t[i]);
    free(t); free(raw); free(tn); free(in);
    at = next;
  }
  free(data);
  return 0;
}
'''

# The pinned rtext.c text functions compiled on their own (controls and the
# sanitizer build); raylib's allocators and TraceLog as their defaults.
PRELUDE = r'''#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <math.h>
#include "raylib.h"
#define RL_CALLOC(n, sz) calloc(n, sz)
#define RL_MALLOC(sz) malloc(sz)
#define RL_FREE(p) free(p)
#define TRACELOG(...) ((void)0)
#define MAX_TEXT_BUFFER_LENGTH 1024
#define MAX_TEXTSPLIT_COUNT 128
void SetTraceLogLevel(int logLevel) { (void)logLevel; }
/* Unaltered text functions from pinned raylib rtext.c; zlib, LICENSES/raylib.txt. */
'''
RULE = '//----------------------------------------------------------------------------------\n'
MULTIPLY_ADD = "value = value*10.0f + (float)(text[i] - '0');"

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def u32(bytes: +List<U32>) -> U32:
  match bytes:
    case Con{a, Con{b, Con{c, Con{d, _}}}}: (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)
    case _: 0
def skip(+bytes: +List<U32>, +n: U32) -> +List<U32>:
  List.drop(&2, U32, bytes, U32.to_nat(n))
def chars(n: Nat, bytes: +List<U32>) -> String:
  match n bytes:
    case 1n+k Con{b, rest}: SCon{Char.from_u32(b), chars(k, rest)}
    case _ _: SNil{}
def ints(n: Nat, +bytes: +List<U32>) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{u32(bytes), ints(k, skip(bytes, 4))}
def texts(n: Nat, +bytes: +List<U32>) -> +List<String>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +length = u32(bytes)
      Con{chars(U32.to_nat(length), skip(bytes, 4)), texts(k, skip(bytes, (4 + length : U32)))}
def head(values: +List<U32>) -> U32:
  match values:
    case Con{v, _}: v
    case Nil{}: 0
def number(+values: +List<U32>, k: Nat) -> U32:
  head(List.drop(&2, U32, values, k))
def first(values: +List<String>) -> String:
  match values:
    case Con{t, _}: t
    case Nil{}: ""
def text(+values: +List<String>, k: Nat) -> String:
  first(List.drop(&2, String, values, k))
def digit(+d: U32) -> Char:
  Char.from_u32(Bool.pick(U32, (d < 10 : U32), (48 + d : U32), (87 + d : U32)))
def hex(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+c, rest}: SCon{digit(((Char.to_u32(c) >> 4n) .&. 15 : U32)), SCon{digit((Char.to_u32(c) .&. 15 : U32)), hex(rest)}}
def s(text: String) -> String:
  "s" ++ hex(text)
def ms(found: Maybe<String>) -> String:
  match found:
    case None{}: "none"
    case Some{t}: s(t)
def sdec(+v: U32) -> String:
  Bool.pick(String, (v >= 2147483648 : U32), "-" ++ U32.show((0 - v : U32)), U32.show(v))
def list(values: +List<String>) -> String:
  match values:
    case Nil{}: ""
    case Con{t, rest}: " " ++ s(t) ++ list(rest)
def numbers(values: +List<U32>) -> String:
  match values:
    case Nil{}: ""
    case Con{v, rest}: " " ++ sdec(v) ++ numbers(rest)
def unit(u: Unit) -> String:
  ""
def lines(+values: +List<String>) -> String:
  U32.show(U32.from_nat(List.length(&2, String, values))) ++ list(values) ++ unit(J.Text.unload_lines(values))
def codepoints(+values: +List<U32>) -> String:
  U32.show(U32.from_nat(List.length(&2, U32, values))) ++ numbers(values) ++ unit(J.Codepoint.unload(values))
def utf8(+text: String) -> String:
  s(text) ++ unit(J.UTF8.unload(text))
def written(found: Maybe<(String & U32)>) -> String:
  match found:
    case None{}: "none"
    case Some{Tuple{buffer, n}}: s(buffer) ++ " " ++ sdec(n)
def pair(value: U32 & U32) -> String:
  (c, n) = value
  sdec(c) ++ " " ++ sdec(n)
def mpair(found: Maybe<(U32 & U32)>) -> String:
  match found:
    case None{}: "none"
    case Some{p}: pair(p)
def split(found: Maybe<+List<String>>) -> String:
  match found:
    case None{}: "none"
    case Some{+parts}: U32.show(U32.from_nat(List.length(&2, String, parts))) ++ list(parts)
def mint(found: Maybe<U32>) -> String:
  match found:
    case None{}: "none"
    case Some{v}: sdec(v)
def index(found: Maybe<U32>) -> String:
  match found:
    case None{}: "-1"
    case Some{v}: sdec(v)
def bits(+x: F32) -> String:
  U32.show(F32.bits(x))
def f32(+w: U32) -> F32:
  U32{b} = w
  F32{b}
def arg(kind: U32, +value: U32, +strings: +List<String>) -> J.Text.Arg:
  match kind:
    case 0: J.TextInt{value}
    case 1: J.TextString{text(strings, U32.to_nat(value))}
    case _: J.TextFloat{f32(value)}
def args(n: Nat, +values: +List<U32>, +strings: +List<String>) -> +List<J.Text.Arg>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{arg(number(values, 0n), number(values, 1n), strings), args(k, List.drop(&2, U32, values, 2n), strings)}
def row(op: U32, +i: +List<U32>, +t: +List<String>) -> String:
  match op:
    case 1: lines(J.Text.load_lines(text(t, 0n)))
    case 2: written(J.Text.copy(text(t, 0n), text(t, 1n)))
    case 3: Bool.pick(String, J.Text.is_equal(text(t, 0n), text(t, 1n)), "1", "0")
    case 4: U32.show(J.Text.length(text(t, 0n)))
    case 5: ms(J.Text.format(text(t, 0n), args(U32.to_nat(number(i, 1n)), List.drop(&2, U32, i, 2n), t)))
    case 6: ms(J.Text.subtext(text(t, 0n), number(i, 0n), number(i, 1n)))
    case 7: ms(J.Text.remove_spaces(text(t, 0n)))
    case 8: s(J.Text.between(text(t, 0n), text(t, 1n), text(t, 2n)))
    case 9: ms(J.Text.replace(text(t, 0n), text(t, 1n), text(t, 2n)))
    case 10: ms(J.Text.replace_alloc(text(t, 0n), text(t, 1n), text(t, 2n)))
    case 11: ms(J.Text.replace_between(text(t, 0n), text(t, 1n), text(t, 2n), text(t, 3n)))
    case 12: ms(J.Text.replace_between_alloc(text(t, 0n), text(t, 1n), text(t, 2n), text(t, 3n)))
    case 13: ms(J.Text.insert(text(t, 0n), text(t, 1n), number(i, 0n)))
    case 14: ms(J.Text.insert_alloc(text(t, 0n), text(t, 1n), number(i, 0n)))
    case 15: ms(J.Text.join(List.drop(&2, String, t, 1n), text(t, 0n)))
    case 16: split(J.Text.split(text(t, 0n), Char.from_u32(number(i, 0n))))
    case 17: written(J.Text.append(text(t, 0n), text(t, 1n), number(i, 0n)))
    case 18: index(J.Text.find_index(text(t, 0n), text(t, 1n)))
    case 19: s(J.Text.to_upper(text(t, 0n)))
    case 20: s(J.Text.to_lower(text(t, 0n)))
    case 21: ms(J.Text.to_pascal(text(t, 0n)))
    case 22: ms(J.Text.to_snake(text(t, 0n)))
    case 23: ms(J.Text.to_camel(text(t, 0n)))
    case 24: mint(J.Text.to_integer(text(t, 0n)))
    case 25: bits(J.Text.to_float_for(M.Uncontracted{}, text(t, 0n))) ++ " " ++ bits(J.Text.to_float_for(M.Fused{}, text(t, 0n)))
    case 26: utf8(J.UTF8.load(i))
    case 27: codepoints(J.Codepoint.load(text(t, 0n)))
    case 28: U32.show(J.Codepoint.count(text(t, 0n)))
    case 29: pair(J.Codepoint.get(text(t, 0n)))
    case 30: pair(J.Codepoint.next(text(t, 0n)))
    case 31: mpair(J.Codepoint.previous(text(t, 0n), number(i, 0n)))
    case 32: s(J.Codepoint.to_utf8(number(i, 0n)))
    case _: "unknown"
def parse(+bytes: +List<U32>) -> String:
  +count = u32(skip(bytes, 4))
  +after = skip(bytes, (8 + 4 * count : U32))
  row((u32(bytes) .&. 255 : U32), ints(U32.to_nat(count), skip(bytes, 8)), texts(U32.to_nat(u32(after)), skip(after, 4)))
def run(n: Nat, +bytes: +List<U32>) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        IO.print(parse(skip(bytes, 4)))
        run(k, skip(bytes, (4 + u32(bytes) : U32)))
def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{+bytes}: run(U32.to_nat(u32(bytes)), skip(bytes, 4))
def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data("PATH"), loaded)
    IO.print("done")
'''


class Case:
    def __init__(self, op, ints=(), texts=(), call=None):
        self.op, self.ints, self.texts, self.call = op, [int(v) for v in ints], [bytes(t) for t in texts], call
        self.defined = defined(self)


def cstr(text):
    return text.split(b'\0', 1)[0]


def s32(value):
    value &= 0xFFFFFFFF
    return value - (1 << 32) if value >= 1 << 31 else value


# -----------------------------------------------------------------------------
# Defined-input contracts (the cases Jonlib answers None for)

def join_defined(items, delimiter):
    size, total = len(cstr(delimiter)), 0
    for index, item in enumerate(items):
        length = len(cstr(item))
        if total + length < 1024:
            total += length
            if size > 0 and index < len(items) - 1:
                total += size
                if total > 1023:
                    return False
    return True


def split_defined(text, delimiter):
    text, counter = cstr(text), 1
    for i in range(1024):
        if i == len(text):
            return True
        if text[i] == delimiter:
            counter += 1
            if counter == 128:
                return i + 1 < 1024
    return False


def cased_defined(text):
    text = cstr(text)
    if not text:
        return False
    i = j = 1
    while i < 1023:
        if j > len(text):
            return False
        if j == len(text):
            return True
        if text[j] == ord('_'):
            j += 1
        i += 1
        j += 1
    return True


def snake_defined(text):
    text, i, j = cstr(text), 0, 0
    while i < 1023 and j < len(text):
        if 65 <= text[j] <= 90 and i >= 1:
            i += 1
            if i >= 1023:
                return False
        i += 1
        j += 1
    return True


def integer_defined(text):
    text, value = cstr(text), 0
    k = 1 if text[:1] in (b'+', b'-') else 0
    while k < len(text) and 48 <= text[k] <= 57:
        value = value * 10 + text[k] - 48
        if value > INT_MAX:
            return False
        k += 1
    return True


def subtext_defined(text, position, length):
    total = len(cstr(text))
    if position >= total:
        return True
    if length < 0:
        return False
    if position < 0:
        return length == 0 and total - position <= INT_MAX
    return True


def insert_defined(limited, text, insert, position):
    total, size = len(cstr(text)), len(cstr(insert))
    if limited and total + size >= 1023:
        return True
    return not (position < 0 or position >= total + 2 or (size >= 2 and position < total))


def previous_defined(text, position):
    text = cstr(text)
    if position < 0 or position > len(text) + 1:
        return False
    if position == len(text) + 1:
        return True
    k = position - 1
    while k >= 0 and text[k] & 0xC0 == 0x80:
        k -= 1
    return k >= 0


def replace_between_defined(text, begin, end, replacement):
    text, begin, end = cstr(text), cstr(begin), cstr(end)
    first = text.find(begin)
    if first < 0:
        return True
    after = text[first + len(begin):]
    last = after.find(end)
    return last < 0 or first + len(begin) + len(cstr(replacement)) + len(after) - last <= 1023


FLAGS = {ord('-'): 1, ord('+'): 2, ord(' '): 4, ord('#'): 8, ord('0'): 16}
ALLOWED = {'d': 23, 'i': 23, 'u': 17, 'x': 25, 'X': 25, 'o': 25, 'c': 1, 's': 1, 'f': 23, 'F': 23, '%': 0}


def conversions(fmt):
    """The conversion characters of a format in the typed subset, or None."""
    fmt, found, i = cstr(fmt), [], 0
    while i < len(fmt):
        if fmt[i] != ord('%'):
            i += 1
            continue
        i += 1
        flags = width = precision = 0
        dot = False
        while i < len(fmt) and fmt[i] in FLAGS:
            flags |= FLAGS[fmt[i]]
            i += 1
        while i < len(fmt) and 48 <= fmt[i] <= 57:
            width = min(width * 10 + fmt[i] - 48, 100000)
            i += 1
        if i < len(fmt) and fmt[i] == ord('.'):
            dot = True
            i += 1
            while i < len(fmt) and 48 <= fmt[i] <= 57:
                precision = min(precision * 10 + fmt[i] - 48, 100000)
                i += 1
        if i >= len(fmt):
            return None
        kind = chr(fmt[i])
        i += 1
        if kind not in ALLOWED or flags & ~ALLOWED[kind] or width > 4096 or precision > 4096:
            return None
        if (kind == 'c' and dot) or (kind in 'fF' and precision > 9) or (kind == '%' and (dot or width)):
            return None
        if kind != '%':
            found.append(kind)
    return found


def format_types(fmt, args):
    kinds = conversions(fmt)
    if kinds is None or len(kinds) > len(args):
        return None
    for kind, (tag, value) in zip(kinds, args):
        expected = 'float' if kind in 'fF' else 'string' if kind == 's' else 'int'
        if tag != expected or (tag == 'float' and math.isnan(struct.unpack('<f', struct.pack('<I', value))[0])):
            return None
    return kinds


def defined(case):
    op, i, t = case.op, [s32(v) for v in case.ints], case.texts
    if op == 'TextCopy':
        return len(cstr(t[1])) + 1 <= len(t[0])
    if op == 'TextAppend':
        return i[0] >= 0 and i[0] + len(cstr(t[1])) + 1 <= len(t[0])
    if op == 'TextFormat':
        return case.call is not None
    if op == 'TextSubtext':
        return subtext_defined(t[0], i[0], i[1])
    if op == 'TextRemoveSpaces':
        return not (len(cstr(t[0])) <= 1021 and cstr(t[0]).count(b' ') >= 2)
    if op == 'TextReplaceBetween':
        return replace_between_defined(*t)
    if op in ('TextInsert', 'TextInsertAlloc'):
        return insert_defined(op == 'TextInsert', t[0], t[1], i[0])
    if op == 'TextJoin':
        return join_defined(t[1:], t[0])
    if op == 'TextSplit':
        return split_defined(t[0], i[0] & 0xFF)
    if op in ('TextToPascal', 'TextToCamel'):
        return cased_defined(t[0])
    if op == 'TextToSnake':
        return snake_defined(t[0])
    if op == 'TextToInteger':
        return integer_defined(t[0])
    if op == 'GetCodepointPrevious':
        return previous_defined(t[0], i[0])
    return True


# -----------------------------------------------------------------------------
# Corpus

UTF8 = ['héllo wörld', '日本語テキスト', '😀 emoji 🎉', 'Ελληνικά', 'mixed ascii ü 漢 😀 end', 'ﬁ€𐍈ŉ']
INVALID = [b'\x80', b'\xbf\x80', b'\xc3', b'\xc3(', b'\xc0\xaf', b'\xc1\xbf', b'\xc2\x80', b'\xdf\xbf', b'\xe0\x80\xaf',
           b'\xe0\xa0\x80', b'\xe0\x9f\xbf', b'\xe2\x82', b'\xe2\x82\xac', b'\xe2(\xa1', b'\xed\xa0\x80', b'\xed\x9f\xbf',
           b'\xef\xbf\xbf', b'\xf0\x80\x80\xaf', b'\xf0\x8f\xbf\xbf', b'\xf0\x90\x80\x80', b'\xf0\x9f\x98', b'\xf0\x9f\x98\x80',
           b'\xf4\x8f\xbf\xbf', b'\xf4\x90\x80\x80', b'\xf5\x80\x80\x80', b'\xf7\xbf\xbf\xbf', b'\xf8\x88\x80\x80\x80',
           b'\xfc\x84\x80\x80\x80\x80', b'\xfe', b'\xff', b'a\xc3', b'\xe2\x82a', b'\xf0\x9f\x98a', b'\xf0\x9fa\x80',
           b'\xf0\x9f', b'\xe2', b'\xc3\xa9\x80\x80', b'\xc3\xa9\xc3']
PLAIN = [b'', b'a', b'hello', b'Hello World', b'  two  spaces ', b'tab\there', b'line1\nline2\n', b'a,b,,c', b'ab\0cd',
         b'\0abc', b'snake_case_text', b'PascalCaseText', b'x1_y2', b'_lead', b'trail_', b'a__b', b'\xe9t\xe9 caf\xe9']


def letters(rng, n, alphabet=b'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ ,.'):
    return bytes(rng.choice(alphabet) for _ in range(n))


def random_utf8(rng, n):
    out = []
    for _ in range(n):
        out.append(chr(rng.choice([rng.randrange(0x20, 0x7F), rng.randrange(0x80, 0x800), rng.randrange(0x800, 0xD800),
                                   rng.randrange(0xE000, 0x10000), rng.randrange(0x10000, 0x110000)])))
    return ''.join(out).encode('utf-8', 'surrogatepass')


def texts(rng):
    out = list(PLAIN) + [s.encode() for s in UTF8] + INVALID
    out += [bytes(rng.randrange(1, 256) for _ in range(rng.randrange(0, 24))) for _ in range(20)]
    out += [random_utf8(rng, rng.randrange(1, 12)) for _ in range(10)]
    return out


def word(value):
    return value & 0xFFFFFFFF


def f32_bits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def c_string(text):
    return '"' + ''.join(chr(c) if 32 <= c < 127 and chr(c) not in '"\\?' else f'\\{c:03o}' for c in text) + '"'


def format_case(fmt, args, cases):
    """args: ('int', value) | ('string', bytes) | ('float', bits)."""
    strings, ints = [fmt], [len(cases), len(args)]
    for tag, value in args:
        if tag == 'string':
            ints += [1, len(strings)]
            strings.append(value)
        else:
            ints += [0 if tag == 'int' else 2, word(value)]
    plain = [(tag, word(value) if tag != 'string' else value) for tag, value in args]
    kinds = format_types(fmt, plain)
    call = None
    if kinds is not None:
        parts = []
        for index, (tag, value) in enumerate(plain):
            kind = kinds[index] if index < len(kinds) else 'd'
            if tag == 'string':
                parts.append(c_string(value))
            elif tag == 'float':
                parts.append(f'f32({value}u)')
            else:
                parts.append(f'(unsigned){value}u' if kind in 'uxXo' else f'(int){value}u')
        call = f'str(TextFormat({c_string(fmt)}{"".join(", " + p for p in parts)}))'
    return Case('TextFormat', ints, strings, call)


def format_corpus(rng, cases):
    out = []
    ints = [0, 1, -1, 7, 42, -42, 255, 256, 65, INT_MAX, -INT_MAX - 1, 0x7FFF, 12345678, -987654, 4095, 8]
    floats = [0.0, -0.0, 1.5, 3.14159, -2.5, 0.125, 1e10, 3.4e38, 1e-10, 1.0 / 3, 0.5, 2.5, 0.05, 123.456, -0.004,
              1e-45, float('inf'), float('-inf')]
    widths, precisions = ['', '1', '5', '12', '30'], ['', '.', '.0', '.1', '.3', '.8', '.12']

    def add(fmt, args):
        case = format_case(fmt.encode('latin-1') if isinstance(fmt, str) else fmt, args, cases + out)
        out.append(case)

    for kind in 'diuxXo':
        for _ in range(28):
            flags = ''.join(rng.choice('-+ #0') for _ in range(rng.randrange(0, 3)))
            spec = '%' + flags + rng.choice(widths) + rng.choice(precisions) + kind
            add(f'[{spec}]', [('int', rng.choice(ints))])
    for _ in range(30):
        flags = rng.choice(['', '-', '+', ' ', '0', '-0', '+0', ' 0'])
        spec = '%' + flags + rng.choice(widths) + rng.choice(['', '.', '.0', '.1', '.4', '.6', '.9']) + rng.choice('fF')
        add(f'<{spec}>', [('float', f32_bits(rng.choice(floats)))])
    for value in floats:
        add('%f|%.0f|%.9f|%12.3f|%-12.1F|%+f|% .2f|%010.4f', [('float', f32_bits(value))] * 8)
    for text in [b'', b'abc', b'hello world', 'ünïcode'.encode(), b'with\0nul', b'x' * 50]:
        add('%s|%10s|%-10s|%.2s|%5.1s|%.0s|', [('string', text)] * 6)
    for value in [65, 0, 255, 256 + 66, -1, 10]:
        add('[%c][%3c][%-3c]', [('int', value)] * 3)
    add('ab%cde', [('int', 0)])
    add('%%|%d%%|100%%', [('int', 5)])
    add('plain text, no conversions', [])
    add('extra args ignored %d', [('int', 1), ('string', b'unused'), ('float', f32_bits(1.0))])
    add('mixed %s=%d (%x) %.2f%%', [('string', b'key'), ('int', -17), ('int', 3054), ('float', f32_bits(99.5))])
    add('%1023d', [('int', 1)])
    add('%1024d', [('int', 1)])
    add('%1500d|tail', [('int', -5)])
    add('%1019d%c%5d', [('int', 1), ('int', 0), ('int', 2)])
    add('%1021d%c%5d', [('int', 1), ('int', 0), ('int', 2)])
    add('%s', [('string', b'z' * 2000)])
    add('%s%s', [('string', b'y' * 1020), ('string', b'1234')])
    add('%s%s', [('string', b'y' * 1019), ('string', b'1234')])
    add('%.4096d', [('int', 3)])
    add(b'bytes \xe9\xff %d', [('int', 9)])
    add(b'cut\0here %d', [('int', 9)])
    # Outside the subset or undefined in C: None without a native run.
    for fmt, args in [('%', []), ('abc%', []), ('%5', [('int', 1)]), ('%e', [('float', f32_bits(1.0))]),
                      ('%g', [('float', f32_bits(1.0))]), ('%ld', [('int', 1)]), ('%*d', [('int', 3), ('int', 1)]),
                      ('%#d', [('int', 1)]), ('%05s', [('string', b'a')]), ('%.3c', [('int', 65)]), ('%+u', [('int', 1)]),
                      ('% x', [('int', 1)]), ('%#f', [('float', f32_bits(1.0))]), ('%d %d', [('int', 1)]),
                      ('%d', [('string', b'1')]), ('%s', [('int', 1)]), ('%f', [('int', 1)]), ('%d', [('float', 0)]),
                      ('%f', [('float', 0x7FC00000)]), ('%5%', []), ('%-%', []), ('%.10f', [('float', f32_bits(1.0))]),
                      ('%5000d', [('int', 1)]), ('%.5000d', [('int', 1)]), ('%p', [('int', 0)]), ('%n', [('int', 0)]),
                      ('%5.2.1d', [('int', 1)]), ('%-5-d', [('int', 1)]), ('%lf', [('float', f32_bits(1.0))])]:
        add(fmt, args)
    return out


def corpus():
    rng = random.Random(0x7E47)
    cases = []

    def add(op, ints=(), strings=()):
        cases.append(Case(op, [word(v) for v in ints], strings))

    pool = texts(rng)
    long_texts = [letters(rng, n) for n in (1021, 1022, 1023, 1024, 1025, 1500, 2100)]
    for text in pool + [b'\n', b'\n\n', b'a\r\nb\r\n', b'one\ntwo\nthree', b'\nlead', b'x' * 1500 + b'\n' + b'y' * 30]:
        add('LoadTextLines', strings=[text])
        add('TextLength', strings=[text])
        add('TextToUpper', strings=[text])
        add('TextToLower', strings=[text])
        add('TextRemoveSpaces', strings=[text])
        add('TextToPascal', strings=[text])
        add('TextToCamel', strings=[text])
        add('TextToSnake', strings=[text])
        add('LoadCodepoints', strings=[text])
        add('GetCodepointCount', strings=[text])
    for text in long_texts:
        for op in ('TextLength', 'TextToUpper', 'TextToLower', 'TextToPascal', 'TextToCamel', 'TextToSnake', 'TextRemoveSpaces',
                   'LoadTextLines', 'GetCodepointCount'):
            add(op, strings=[text])
    upper = bytes(rng.choice(b'abcdefgh') for _ in range(1030))
    for at in (1019, 1020, 1021, 1022, 1023):
        snake = bytearray(upper)
        snake[at] = ord('Q')
        add('TextToSnake', strings=[bytes(snake[:at + 3])])
        add('TextToSnake', strings=[b'aB' + bytes(snake[2:at + 3])])
    for at in (1019, 1020, 1021, 1022, 1023, 1024):
        add('TextToPascal', strings=[upper[:at] + b'_'])
        add('TextToCamel', strings=[upper[:at] + b'_'])
        add('TextToPascal', strings=[upper[:at] + b'_x'])
        add('TextToCamel', strings=[upper[:at] + b'_' + upper[:5]])
    for text in [b'hello_world', b'hello_World', b'hello_9lives', b'hello__x', b'_a_b_c', b'a_', b'_', b'x', b'A', b'ab_\xe9x',
                 b'MixedCase_snake_Words', b'HTTPServer', b'getHTTPResponseCode', b'a1B2c3D4', b'already_lower']:
        for op in ('TextToPascal', 'TextToCamel', 'TextToSnake'):
            add(op, strings=[text])
    for count in (0, 1, 2, 3, 1019, 1020, 1021, 1022, 1023):
        add('TextRemoveSpaces', strings=[b' ' * min(count, 2) + letters(rng, max(count - 2, 0), b'abc')])
        add('TextRemoveSpaces', strings=[b'a b' + b'c' * count])
        add('TextRemoveSpaces', strings=[b'a b c' + b'd' * count])
    add('TextRemoveSpaces', strings=[b' ' * 1500])
    add('TextRemoveSpaces', strings=[b'a b c' + b'd' * 2000])
    # Codepoint decoding on every suffix of some texts.
    for text in [s.encode() for s in UTF8] + INVALID + [random_utf8(rng, 8) for _ in range(4)]:
        for start in range(len(text) + 1):
            add('GetCodepoint', strings=[text[start:]])
            add('GetCodepointNext', strings=[text[start:]])
        for position in range(-1, len(text) + 3):
            add('GetCodepointPrevious', ints=[position], strings=[text])
    for text in [b'\x80\x80\x80', b'\xbf', b'a\x80\x80', b'\xe2\x82\xac\xe2\x82\xac', b'\x80\xe2\x82\xac']:
        for position in range(-2, len(text) + 3):
            add('GetCodepointPrevious', ints=[position], strings=[text])
    values = [0, 1, 0x41, 0x7F, 0x80, 0x7FF, 0x800, 0xFFFF, 0x10000, 0x10FFFF, 0x110000, -1, -256, -255, 0xD800, 0xDFFF,
              INT_MAX, -INT_MAX - 1, 0xE9, 0x20AC, 0x1F600] + [rng.randrange(0, 0x110000) for _ in range(20)]
    for value in values:
        add('CodepointToUTF8', ints=[value])
    for size in (0, 1, 2, 5, 40):
        add('LoadUTF8', ints=[rng.choice(values) for _ in range(size)])
    add('LoadUTF8', ints=values)
    add('LoadUTF8', ints=[0x41, 0, 0x42])
    add('LoadUTF8', ints=[rng.randrange(0, 0x110000) for _ in range(300)])
    # Equality, search and between.
    pairs = [(b'', b''), (b'a', b''), (b'', b'a'), (b'abc', b'abc'), (b'abc', b'abd'), (b'abc', b'ab'), (b'ab\0x', b'ab\0y'),
             ('é'.encode(), b'e'), (b'x' * 1500, b'x' * 1500), (b'x' * 1500, b'x' * 1499 + b'y')]
    for left, right in pairs:
        add('TextIsEqual', strings=[left, right])
    finds = [(b'hello world', b'world'), (b'hello world', b''), (b'hello', b'hello world'), (b'aaaa', b'aa'), (b'abc', b'd'),
             (b'', b''), (b'', b'a'), ('naïve café'.encode(), 'é'.encode()), (b'ab\0cd', b'cd'), (b'x' * 2000 + b'needle', b'needle')]
    for text, search in finds:
        add('TextFindIndex', strings=[text, search])
    betweens = [(b'<a>text</a>', b'<a>', b'</a>'), (b'no markers', b'[', b']'), (b'[open only', b'[', b']'), (b'close] only', b'[', b']'),
                (b'[a][b]', b'[', b']'), (b'empty markers', b'', b''), (b'xx', b'x', b'x'), (b'][wrong order][', b'[', b']'),
                (b'[' + b'm' * 1500 + b']', b'[', b']'), (b'[' + b'm' * 1023 + b']', b'[', b']'), (b'[' + b'm' * 1022 + b']', b'[', b']'),
                ('«ü»'.encode(), '«'.encode(), '»'.encode())]
    for text, begin, end in betweens:
        add('GetTextBetween', strings=[text, begin, end])
        for replacement in (b'', b'R', b'replacement text'):
            add('TextReplaceBetween', strings=[text, begin, end, replacement])
            add('TextReplaceBetweenAlloc', strings=[text, begin, end, replacement])
    for size in (1015, 1016, 1017, 1018, 1019):
        add('TextReplaceBetween', strings=[b'(' + b'k' * size + b')', b'(', b')', b'1234567'])
        add('TextReplaceBetweenAlloc', strings=[b'(' + b'k' * size + b')', b'(', b')', b'1234567'])
    # Replacement.
    replaces = [(b'hello world', b'o', b'0'), (b'aaaa', b'aa', b'b'), (b'aaa', b'aa', b'x'), (b'abcabc', b'abc', b''),
                (b'abc', b'', b'x'), (b'', b'a', b'b'), (b'abc', b'abcd', b'x'), (b'a.b.c', b'.', b'::'), (b'xyz', b'xyz', b'XYZ'),
                ('ünïcode ü'.encode(), 'ü'.encode(), b'u'), (b'banana', b'ana', b'_'), (b'ab\0ab', b'ab', b'X')]
    for count in (0, 1, 2, 3):
        base = b'a' * (1022 - 2 * count) + b'.' * count
        replaces += [(base, b'.', b'xxx'), (b'b' * (1021 + count), b'b', b'b'), (b'c' * 1020 + b'.' * count, b'.', b'')]
    replaces += [(b'.' * 511, b'.', b'..'), (b'.' * 512, b'.', b'..'), (b'q' * 1500, b'q', b''), (b'q' * 1500, b'qq', b'r')]
    for text, search, replacement in replaces:
        add('TextReplace', strings=[text, search, replacement])
        add('TextReplaceAlloc', strings=[text, search, replacement])
    # Insertion.
    for text in (b'', b'a', b'abc', b'hello world'):
        for insert in (b'', b'X', b'XY', b'XYZW'):
            for position in sorted({-2, -1, 0, 1, len(text) - 1, len(text), len(text) + 1, len(text) + 2, len(text) + 5}):
                add('TextInsert', ints=[position], strings=[text, insert])
                add('TextInsertAlloc', ints=[position], strings=[text, insert])
    for size in (1019, 1020, 1021, 1022, 1023):
        text = letters(rng, size, b'lmn')
        add('TextInsert', ints=[size], strings=[text, b'++'])
        add('TextInsert', ints=[5], strings=[text, b'+'])
        add('TextInsert', ints=[-1], strings=[text, b'++'])
        add('TextInsertAlloc', ints=[size], strings=[text, b'++'])
    add('TextInsertAlloc', ints=[2000], strings=[b'w' * 2000, b'tail'])
    # Subtext.
    for text in (b'', b'hello', b'hello world', b'x' * 1500):
        n = len(text)
        for position in sorted({-INT_MAX - 1, -3, -1, 0, 1, n // 2, n - 1, n, n + 1, INT_MAX}):
            for length in sorted({-INT_MAX - 1, -1, 0, 1, 3, n, 1022, 1023, 1024, INT_MAX}):
                add('TextSubtext', ints=[position, length], strings=[text])
    # Joining.
    joins = [([], b','), ([b''], b','), ([b'a'], b', '), ([b'a', b'b', b'c'], b', '), ([b'a', b'', b'c'], b''),
             ([b'x', b'y'], b'\xe2\x80\x94'), ([b'p' * 600, b'q' * 600, b'r' * 10], b'-'),
             ([b'p' * 1023], b'-'), ([b'p' * 1024, b'r'], b'-'), ([b'p' * 1022, b'q'], b'-'), ([b'p' * 1022, b'q'], b'--'),
             ([b'p' * 1021, b'q', b'r'], b'-'), ([b'p' * 1020, b'q'], b'abc'), ([b'p' * 1021, b'q'], b'abc'),
             ([b'p' * 1000, b'q' * 30, b'rr'], b'+'), ([b'w'] * 200, b','), ([b'w' * 5] * 200, b'')]
    for items, delimiter in joins:
        add('TextJoin', strings=[delimiter] + items)
    # Splitting.
    splits = [(b'a,b,,c', ','), (b'', ','), (b',', ','), (b',,,', ','), (b'no delimiter', ','), (b'a b c', ' '), (b'x', 'x'),
              (b'ab\0c,d', ','), ('é,ü'.encode(), ','), (b'a\xffb', '\xff'), (b'abc', '\0')]
    splits += [(b',' * n, ',') for n in (126, 127, 128, 200)]
    splits += [(b'v,' * n, ',') for n in (126, 127, 128)]
    splits += [(letters(rng, n, b'abc'), ',') for n in (1023, 1024, 1500)]
    splits += [(b',' * 126 + b'z' * 895 + b',' + b'tail', ','), (b',' * 126 + b'z' * 896 + b',' + b'tail', ','),
               (b',' * 126 + b'z' * 897 + b',' + b'tail', ','), (b'a,' * 300, ','), (b'z' * 1023 + b',', ','),
               (b'z' * 1022 + b',', ','), (b'z' * 1023 + b',' + b'y', ',')]
    for text, delimiter in splits:
        add('TextSplit', ints=[ord(delimiter)], strings=[text])
    # Buffers.
    for size in (0, 1, 2, 5, 6, 7, 32):
        for fill in (b'\0', b'#'):
            buffer = fill * size
            for text in (b'', b'abc', b'hello', b'hello!', 'é'.encode()):
                add('TextCopy', strings=[buffer, text])
                for position in (-1, 0, 1, 2, size - len(text) - 1, size - len(text)):
                    add('TextAppend', ints=[position], strings=[buffer, text])
    # Numbers.
    for text in [b'', b'+', b'-', b'0', b'7', b'-7', b'+42', b'123abc', b' 12', b'00012', b'-0', b'2147483647', b'2147483648',
                 b'-2147483647', b'-2147483648', b'99999999999', b'214748364', b'2147483646x', b'+-5', b'12.5', b'\xd9\xa1']:
        add('TextToInteger', strings=[text])
    floats = [b'', b'1', b'-1', b'+1.5', b'3.14159', b'0.1', b'.5', b'-.5', b'1.', b'1e5', b'-0', b'0.0', b'123456789',
              b'16777216', b'16777217', b'16777219', b'33554435', b'1234567890123456789012345678901234567890',
              b'340282356779733661637539395458142568447', b'340282366920938463463374607431768211455',
              b'0.' + b'0' * 44 + b'1', b'0.' + b'9' * 50, b'1.2.3', b'12a.5', b'7.', b'+.', b'-' + b'9' * 60,
              b'98765.4321', b'0.30000001', b'2.718281828459045', b'1' * 39, b'1' * 40]
    floats += [str(rng.randrange(0, 10 ** rng.randrange(1, 30))).encode() for _ in range(40)]
    floats += [(str(rng.randrange(0, 10 ** 9)) + '.' + str(rng.randrange(0, 10 ** rng.randrange(1, 12)))).encode() for _ in range(40)]
    for text in floats:
        add('TextToFloat', strings=[text])
    cases += format_corpus(rng, cases)
    return cases


def encode(cases, indices, run_all=False):
    out = bytearray(struct.pack('<I', len(indices)))
    for index in indices:
        case = cases[index]
        flagged = 0 if run_all or case.defined else 256
        body = struct.pack('<II', CODE[case.op] | flagged, len(case.ints)) + b''.join(struct.pack('<I', v) for v in case.ints)
        body += struct.pack('<I', len(case.texts)) + b''.join(struct.pack('<I', len(t)) + t for t in case.texts)
        out += struct.pack('<I', len(body)) + body
    return bytes(out)


def harness(cases):
    calls = '\n'.join(f'  case {case.ints[0]}: {case.call}; break;' for case in cases if case.op == 'TextFormat' and case.call)
    return (HARNESS + 'static void format_case(unsigned id) {\n  switch (id) {\n' + calls + '\n  }\n}\n')


def extracted(raylib):
    source = (raylib / 'src/rtext.c').read_text()
    begin = source.index(RULE + '// Text strings management functions')
    end = source.index(RULE + '// Module Internal Functions Definition')
    return source[begin:end]


def build(probe, name, text, flags):
    source, binary = probe.work / f'{name}.c', probe.work / name
    source.write_text(text)
    probekit.run(['clang', '-std=c11', *flags, '-I' + str(probe.args.raylib_source / 'src'), source, '-lm', '-o', binary])
    return binary


def rows(binary, path, env=None):
    return probekit.run([binary, path], env=env).splitlines()


def sanitizer_check(probe, cases, region, path, linked):
    """None when the host has no sanitizer runtime; else the number of undefined cases reported."""
    env = dict(probekit.ENV, ASAN_OPTIONS='detect_leaks=0:abort_on_error=0', UBSAN_OPTIONS='print_stacktrace=0')
    flags = ['-O1', '-g', '-fno-omit-frame-pointer', '-fsanitize=address,undefined', '-fno-sanitize-recover=all', '-ffp-contract=off']
    try:
        binary = build(probe, 'sanitized', PRELUDE + region + harness(cases), flags)
    except ProbeFailure as error:
        probe.report['sanitizer_unavailable'] = str(error)[-400:]
        return None
    clean = rows(binary, path, env)
    different = [i for i, case in enumerate(cases) if case.op != 'TextToFloat' and clean[i] != linked[i]]
    if len(clean) != len(cases) or different:
        raise ProbeFailure(f'text: sanitizer build differs from linked raylib at {len(different)} cases; first {different[:1]}')
    def reported(index):
        result = subprocess.run([binary, path, str(index)], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        return result.returncode != 0 and ('Sanitizer' in result.stderr or 'runtime error' in result.stderr)

    undefined = [index for index, case in enumerate(cases) if not case.defined and case.op != 'TextFormat']
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
        missed = [index for index, ok in zip(undefined, pool.map(reported, undefined)) if not ok]
    if missed:
        case = cases[missed[0]]
        raise ProbeFailure(f'text: {len(missed)} cases classified undefined ran cleanly under sanitizers; first {missed[0]} '
                           f'{case.op} {case.ints} {[t[:40] for t in case.texts]}')
    return len(undefined)


def parse(text, selected):
    lines = text.splitlines()
    if lines[-1:] != ['done']:
        raise ValueError('text: candidate output did not finish')
    return lines[:-1]


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('text', args)
    cases = corpus()
    work = ROOT / WORK
    work.mkdir(parents=True, exist_ok=True)
    path = work / 'cases-all.bin'
    path.write_bytes(encode(cases, range(len(cases))))
    probe.native(harness(cases), 'linked')
    linked = rows(probe.work / 'linked', path)
    if len(linked) != len(cases):
        raise ProbeFailure(f'text: native harness printed {len(linked)} rows for {len(cases)} cases')
    region = extracted(args.raylib_source)
    if region.count(MULTIPLY_ADD) != 1:
        raise ProbeFailure('text: TextToFloat multiply-add not found in the pinned source')
    plain = rows(build(probe, 'control-uncontracted', PRELUDE + region + harness(cases), ['-O2', '-ffp-contract=off']), path)
    fused = rows(build(probe, 'control-fused', PRELUDE + region.replace(MULTIPLY_ADD, "value = fmaf(value, 10.0f, (float)(text[i] - '0'));")
                       + harness(cases), ['-O2', '-ffp-contract=off']), path)
    profile = contraction()
    expected = []
    for index, case in enumerate(cases):
        if case.op == 'TextToFloat':
            if linked[index] != (fused if profile == 'Fused' else plain)[index]:
                raise ProbeFailure(f'text: linked TextToFloat differs from the {profile} control at case {index}')
            expected.append(f'{plain[index]} {fused[index]}')
            continue
        if plain[index] != linked[index]:
            raise ProbeFailure(f'text: extracted rtext.c differs from linked raylib at case {index} ({case.op})')
        expected.append(linked[index] if case.defined else 'none')
        if case.defined == (linked[index] == 'skip'):
            raise ProbeFailure(f'text: native skip flag mismatch at case {index}')
    reported = sanitizer_check(probe, cases, region, path, linked)

    def render(selected, gpu):
        name = f'{WORK}/cases-{selected[0]}-{len(selected)}.bin'
        (ROOT / name).write_bytes(encode(cases, selected, run_all=True))
        return PROGRAM.replace('PATH', name)

    lanes = probe.candidates(render, list(range(len(cases))), batch=1000, parse=parse)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}

    def describe(i):
        case = cases[i]
        return f'case {i} {case.op} ints={case.ints[:4]} texts={[t[:24] for t in case.texts[:3]]}'

    probe.compare(expected, lanes, describe=describe)
    counts = {}
    for case in cases:
        counts[case.op] = counts.get(case.op, 0) + 1
    probe.finish(cases=len(cases), undefined=sum(not c.defined for c in cases), functions=len(counts),
                 sanitizer_reported=reported if reported is not None else 'unavailable', linked_profile=profile,
                 inputs_sha256=hashlib.sha256(path.read_bytes()).hexdigest()[:16])


if __name__ == '__main__':
    main()
