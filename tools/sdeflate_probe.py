#!/usr/bin/env python3
"""Verify quality-8 raw compression and its private native LZ observations."""
import hashlib
import json
import random
import struct
import zlib

from byte_probe import BEND_EMITTER, parse_results
from conformance import source_gate
import probekit
from probekit import ROOT, ProbeFailure


def fixtures():
    rng = random.Random(0x73646566)
    cases = []

    def add(name, data, valid=True):
        cases.append(dict(id=name, data=data, valid=valid))

    for size in (0, 1, 2, 3, 4, 5, 6, 10, 11, 18, 130, 258, 259, 260):
        add(f'tail-{size}', b'a' * size)
    add('all-bytes', bytes(range(256)))
    add('literal-only', bytes(range(256)) * 2)
    add('lazy', b'xxxxabcdefghixabcabcdefghijklmnabcdefghijklmno' * 25)
    add('newest-ties', b'abcdef0abcdef1abcdef2abcdef3abcdef4')
    lengths = (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
               22, 23, 26, 27, 30, 31, 34, 35, 42, 43, 50, 51, 58, 59,
               66, 67, 82, 83, 98, 99, 114, 115, 130, 131, 162, 163,
               194, 195, 226, 227, 257, 258)
    add('length-codes', b''.join(bytes([i]) * (length + 1) for i, length in enumerate(lengths)))
    distances = (4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385,
                 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
                 16385, 24577, 32767)
    segments = [b'a' * 20, b'ab' * 20, b'abc' * 20]
    for i, distance in enumerate(distances):
        marker = bytes([255, i, 254, i])
        segments.append(marker + rng.randbytes(distance - 4) + marker + bytes([253, i]))
    add('distance-codes', b''.join(segments))
    for size in (65534, 65535, 65536, 262143, 262144, 262145, 524289, 1048576):
        add(f'pattern-{size}', (b'abcde12345' * ((size + 9) // 10))[:size])
    for size in (31, 256, 4096, 65535, 65536, 262145):
        add(f'random-{size}', rng.randbytes(size))
    for size in (32767, 32768, 32769):
        prefix = rng.randbytes(size)
        add(f'window-{size}', prefix + prefix[:400])
    add('biased', bytes(rng.choice(b'aaabbcdef') for _ in range(8192)))
    add('stored-then-dynamic', rng.randbytes(262144) + b'x' * 4096)
    add('maximum-incompressible', rng.randbytes(1048576))
    # Distinct four-byte words with changing one-byte markers exhaust native seq[].
    overflow_rng = random.Random(0x5e9)
    words = []
    seen = set()
    while len(words) < 6000:
        word = overflow_rng.getrandbits(32)
        if word not in seen:
            seen.add(word)
            words.append(struct.pack('<I', word))
    overflow = b''.join(word + bytes([cycle]) for cycle in range(9) for word in words)[:262144]
    if hashlib.sha256(overflow).hexdigest() != 'fce67ca40147a6626eac0db48738b0afb53edc2096f66076b7ba5376fd66c1b3':
        raise ValueError('Native overflow reproducer drift')
    add('sequence-limit', overflow, False)
    add('size-limit', bytes(1048577), False)
    return cases


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/checksum.bend as C
import ../../src/sdeflate_lz.bend as L
def fill(bytes: +List<U32>, +index: U32, input: Array<U32>) -> Array<U32>:
  match bytes:
    case Nil{}: input
    case Con{byte, rest}: fill(rest, (index + 1 : U32), Array.set(U32, input, index, byte))
def sequence_words(sequences: +List<L.Sequence>, words: +List<U32>, +count: U32) -> +List<U32> & U32:
  match sequences:
    case Nil{}: (words, count)
    case Con{L.Literals{offset, length}, rest}: sequence_words(rest, Con{length, Con{offset, words}}, (count + 1 : U32))
    case Con{L.Match{distance, length}, rest}: sequence_words(rest, Con{length, Con{(0 - distance : U32), words}}, (count + 1 : U32))
def block_sequences(begin: U32, end: U32, core: L.Core, literals: Array<U32>, distances: Array<U32>, words: +List<U32>, result: +List<U32> & U32) -> L.Core & +List<U32>:
  (sequences, count) = result
  values = List.reverse(&2, U32, Con{count, Con{end, Con{begin, Nil{}}}})
  a = List.foldl(~&2, ~U32, ~+List<U32>, ~(xs => x => Con{x, xs}), values, words)
  b = List.foldl(~&2, ~U32, ~+List<U32>, ~(xs => x => Con{x, xs}), List.reverse(&2, U32, sequences), a)
  c = List.foldl(~&1, ~U32, ~+List<U32>, ~(xs => x => Con{x, xs}), J.Image.list.take(~U32, Array.to_list(~U32, literals), 288n), b)
  d = List.foldl(~&1, ~U32, ~+List<U32>, ~(xs => x => Con{x, xs}), Array.to_list(~U32, distances), c)
  (core, d)
def block_words(words: +List<U32>, result: Maybe<&1, (L.Core & L.Block)>) -> Maybe<&1, (L.Core & +List<U32>)>:
  match result:
    case None{}: None{}
    case Some{Tuple{core, L.Block{begin, end, sequences, literals, distances}}}:
      Some{block_sequences(begin, end, core, literals, distances, words, sequence_words(sequences, Nil{}, 0))}
def blocks(n: Nat, +size: U32, +begin: U32, state: Maybe<&1, (L.Core & +List<U32>)>) -> Maybe<&2, +List<U32>>:
  match n state:
    case _ None{}: None{}
    case 0n Some{Tuple{_, words}}: Some{List.reverse(&2, U32, words)}
    case 1n+rest Some{Tuple{core, words}}:
      +end = U32.min(size, (begin + 262144 : U32))
      blocks(rest, size, end, block_words(words, L.block(size, begin, end, core)))
def sized(bytes: +List<U32>, size: Maybe<&2, U32>) -> Maybe<&2, +List<U32>>:
  match size:
    case None{}: None{}
    case Some{+size}:
      +capacity = U32.max(size, 1)
      input = fill(bytes, 0, Array.new(U32, 1n+U32.log2((capacity - 1 : U32)), 0))
      blocks(U32.to_nat(((capacity + 262143) / 262144 : U32)), size, 0,
        Some{(L.Core{input, Array.new(U32, 15n, 4294967295), Array.new(U32, 15n, 4294967295)}, Nil{})})
def calculate(+bytes: +List<U32>) -> Maybe<&2, +List<U32>>:
  sized(bytes, C.input_size(bytes, 0, True{}))
def word_bytes(n: Nat, +word: U32, bytes: List<U32>) -> List<U32>:
  match n:
    case 0n: bytes
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), bytes})
def array_bytes(values: +List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: List.reverse(&1, U32, bytes)
    case Con{value, rest}: array_bytes(rest, word_bytes(4n, value, bytes))
''' + BEND_EMITTER + '''
def observed(result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.print("null")
    case Some{words}: emit_bytes(~&1, array_bytes(words, Nil{}))
def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "sdefl fixture read failed")
    case Done{bytes}: observed(calculateBANG(bytes))
def main() -> IO(Unit):
  do IO<Unit>:
'''


COMPRESSION_PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/checksum.bend as C
import ../../src/inflate.bend as I
type Observation is Type:
  Observation{compressed: +List<U32>, decoded: Maybe<List<U32>>}
def output_size(bytes: +List<U32>, +count: U32, valid: Bool) -> Maybe<&2, U32>:
  match bytes valid:
    case _ False{}: None{}
    case Nil{} True{}: Some{count}
    case Con{byte, rest} True{}: output_size(rest, (count + 1 : U32), ((byte <= 255) && (count < 1048679) : U32))
def decoded(supported: Bool, size: U32, count: U32, +bytes: +List<U32>, result: Maybe<List<U32>>) -> Observation:
  match supported result:
    case True{} Some{values}: Observation{bytes, Some{values}}
    case False{} None{}: Observation{bytes, I.start(True{}, size, bytes, Some{count})}
    case _ _: Observation{bytes, None{}}
def bounded(+size: U32, +bytes: +List<U32>, count: Maybe<&2, U32>) -> Observation:
  match count:
    case None{}: Observation{bytes, None{}}
    case Some{+count}: decoded((count <= 1048576 : U32), size, count, bytes, J.Compression.decompress(bytes, size))
def compressed(empty: Bool, size: U32, result: Maybe<&2, +List<U32>>) -> Maybe<Observation>:
  match empty result:
    case _ None{}: None{}
    case True{} Some{bytes}: Some{Observation{bytes, Some{Nil{}}}}
    case False{} Some{+bytes}: Some{bounded(size, bytes, output_size(bytes, 0, True{}))}
def sized(size: Maybe<&2, U32>, result: Maybe<&2, +List<U32>>) -> Maybe<Observation>:
  match size result:
    case _ None{}: None{}
    case None{} Some{bytes}: Some{Observation{bytes, None{}}}
    case Some{+size} Some{bytes}: compressed(U32.is_eq(size, 0), size, Some{bytes})
def calculate(+bytes: +List<U32>) -> Maybe<Observation>:
  sized(C.input_size(bytes, 0, True{}), J.Compression.compress(bytes))
''' + BEND_EMITTER + '''
def observed(result: Maybe<Observation>) -> IO(Unit):
  match result:
    case None{}:
      do IO<Unit>:
        IO.print("null")
        IO.print("null")
    case Some{Observation{compressed, Some{decoded}}}:
      do IO<Unit>:
        emit_bytes(~&2, compressed)
        emit_bytes(~&1, decoded)
    case Some{Observation{_, None{}}}: IO.die(Unit, 1, "candidate decompression failed")
def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "sdefl fixture read failed")
    case Done{bytes}: observed(calculateBANG(bytes))
def main() -> IO(Unit):
  do IO<Unit>:
'''


REFERENCE = '''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
struct sdefl;
static void observe(const struct sdefl *s, int begin, int end);
#define SDEFL_IMPLEMENTATION
#define sdeflate probe_sdeflate
#define zsdeflate probe_zsdeflate
#define sdefl_bound probe_sdefl_bound
#include "sdefl-observed.h"
static FILE *observations;
static void word(unsigned value){unsigned char b[4];for(int i=0;i<4;i++)b[i]=(value>>(8*i))&255;if(fwrite(b,1,4,observations)!=4)exit(3);}
static void observe(const struct sdefl *s,int begin,int end){word(begin);word(end);word(s->seq_cnt);
for(int i=0;i<s->seq_cnt;i++){word(s->seq[i].off);word(s->seq[i].len);}
for(int i=0;i<288;i++)word(s->freq.lit[i]);for(int i=0;i<32;i++)word(s->freq.off[i]);}
static void compare(const char *input_path,const char *observed_path,const char *compressed_path,int expected){
int size=0,count=0;unsigned char empty=0;unsigned char *input=LoadFileData(input_path,&size);if(size!=expected||(!input&&size))exit(2);
unsigned char *data=size?input:&empty;unsigned char *native=CompressData(data,size,&count);
struct sdefl *state=calloc(1,sizeof(*state));unsigned char *out=malloc(sdefl_bound(size));if(!state||!out)exit(4);
observations=fopen(observed_path,"wb");if(!observations)exit(5);int n=sdeflate(state,out,data,size,8);fclose(observations);
if(n!=count||memcmp(out,native,n))exit(6);if(n&&!SaveFileData(compressed_path,native,n))exit(7);
free(state);free(out);MemFree(native);UnloadFileData(input);}
int main(void){SetTraceLogLevel(LOG_NONE);
'''


def main():
    args = probekit.arguments(__doc__, lambda parser: parser.add_argument('--stage', choices=('lz', 'compression'), default='compression'))
    probe = probekit.Probe('sdeflate-lz' if args.stage == 'lz' else 'sdeflate', args)
    probe.report['sources'] = source_gate()
    work = probe.work
    cases = fixtures()
    for i, case in enumerate(cases):
        (work / f'{i}.dat').write_bytes(case['data'])
    # Task-local observation hook only. Its complete bytes must equal the linked API.
    original = (args.raylib_source / 'src/external/sdefl.h').read_text()
    needle = '  int blk_len = blk_end - blk_begin;'
    if original.count(needle) != 1:
        raise ProbeFailure('Native observation insertion point drift')
    (work / 'sdefl-observed.h').write_text(original.replace(needle, '  observe(s, blk_begin, blk_end);\n' + needle))
    reference = REFERENCE
    for i, case in enumerate(cases):
        if case['valid']:
            paths = [json.dumps(str((work / f'{i}.{suffix}').relative_to(ROOT))) for suffix in ('dat', 'observed', 'deflate')]
            reference += f'compare({",".join(paths)},{len(case["data"])});\n'
    probe.native(reference + '}\n')
    expected = []
    compressed = []
    for i, case in enumerate(cases):
        if case['valid']:
            observed = (work / f'{i}.observed').read_bytes()
            raw = (work / f'{i}.deflate').read_bytes() if case['data'] else b''
            if case['data'] and zlib.decompress(raw, -15) != case['data']:
                raise ProbeFailure('Native compression failed independent decompression')
            if not case['data'] and raw:
                raise ProbeFailure('Native empty compression changed')
            expected.append(list(observed))
            compressed.append(list(raw))
        else:
            expected.append(None)
            compressed.append(None)
    observation_hash = hashlib.sha256(json.dumps(expected).encode()).hexdigest()
    observation_words = sum(len(row) // 4 for row in expected if row is not None)
    # Two out-of-range byte controls follow the fixtures; each compression action yields a [stream, decoded] pair.
    if args.stage == 'compression':
        expected = [[raw, list(case['data']) if case['valid'] else None] for case, raw in zip(cases, compressed)]
        expected += [[None, None], [None, None]]
    else:
        expected += [None, None]
    actions = [('file', i) for i in range(len(cases))] + [('values', '[256]'), ('values', '[0, 4294967295]')]

    def render(selected, gpu):
        bang = '!' if gpu else ''
        body = (PROGRAM if args.stage == 'lz' else COMPRESSION_PROGRAM).replace('BANG', bang)
        for kind, value in selected:
            if kind == 'file':
                path = json.dumps(str((work / f'{value}.dat').relative_to(ROOT)))
                body += f'    IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.bytes({path}, 2097152), loaded)\n'
            else:
                body += f'    observed(calculate{bang}({value}))\n'
        return body

    def parse(text, selected):
        rows = parse_results(text)
        return rows if args.stage == 'lz' else [rows[i:i + 2] for i in range(0, len(rows), 2)]

    probe.compare(expected, probe.candidates(render, actions, batch=16, parse=parse),
                  describe=lambda index: f'case {cases[index]["id"]}' if index < len(cases) else f'control {actions[index][1]}')
    probe.finish(native_cases=sum(c['valid'] for c in cases), invalid_controls=4, stage=args.stage,
                 input_bytes=sum(len(c['data']) for c in cases if c['valid']),
                 inputs_sha256=hashlib.sha256(json.dumps([dict(c, data=c['data'].hex()) for c in cases]).encode()).hexdigest(),
                 observations_sha256=observation_hash, observation_words=observation_words,
                 compressed_bytes=sum(len(row) for row in compressed if row is not None),
                 public_decoder_size_exclusions=sum(len(row) > 1048576 for row in compressed if row is not None),
                 reference_sha256=hashlib.sha256(json.dumps(compressed).encode()).hexdigest(),
                 instrumented_output_matches_linked_api=True)

if __name__ == '__main__':
    main()
