# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of stb_image_write's quality-8 zlib compressor.
# MIT notice: LICENSES/stb-image.txt. Internal PNG encoding dependency.
import Base

type Writer is Data:
  Writer{buffer: U32, count: U32, bytes: +List<U32>, length: U32}

def flush(n: Nat, +buffer: U32, count: U32, bytes: +List<U32>, length: U32) -> Writer:
  match n:
    case 0n: Writer{buffer, count, bytes, length}
    case 1n+rest: flush(rest, (buffer >> 8n : U32), (count - 8 : U32), Con{(buffer .&. 255 : U32), bytes}, (length + 1 : U32))

def put(code: U32, bits: U32, writer: Writer) -> Writer:
  Writer{buffer, +count, bytes, length} = writer
  +total = (count + bits : U32)
  flush(U32.to_nat((total / 8 : U32)), (buffer .|. (code << U32.to_nat(count)) : U32), total, bytes, length)

def reverse(n: Nat, +code: U32, value: U32) -> U32:
  match n:
    case 0n: value
    case 1n+rest: reverse(rest, (code >> 1n : U32), ((value << 1n) .|. (code .&. 1) : U32))

def huffman.code(code: U32, +bits: U32, writer: Writer) -> Writer:
  put(reverse(U32.to_nat(bits), code, 0), bits, writer)

def huffman.range(small: Bool, medium: Bool, lower: Bool, value: U32, writer: Writer) -> Writer:
  match small medium lower:
    case True{} _ _: huffman.code((48 + value : U32), 8, writer)
    case False{} True{} _: huffman.code((400 + value - 144 : U32), 9, writer)
    case False{} False{} True{}: huffman.code((value - 256 : U32), 7, writer)
    case False{} False{} False{}: huffman.code((192 + value - 280 : U32), 8, writer)

def huffman(+value: U32, writer: Writer) -> Writer:
  huffman.range((value <= 143 : U32), (value <= 255 : U32), (value <= 279 : U32), value, writer)

def length(last: Bool, +value: U32, writer: Writer) -> Writer:
  match last:
    case True{}: huffman(285, writer)
    case False{}:
      +extra = (U32.log2((value - 3 : U32)) - 2n : Nat)
      +part = ((value - 3) >> extra : U32)
      code = (4 * U32.from_nat(extra) + part + 257 : U32)
      put((value - ((part << extra) + 3) : U32), U32.from_nat(extra), huffman(code, writer))

def distance(+value: U32, writer: Writer) -> Writer:
  +extra = (U32.log2((value - 1 : U32)) - 1n : Nat)
  +part = ((value - 1) >> extra : U32)
  code = (2 * U32.from_nat(extra) + part : U32)
  put((value - ((part << extra) + 1) : U32), U32.from_nat(extra), put(reverse(5n, code, 0), 5, writer))

def word.read(shift: Nat, value: U32, read: Array<U32> & U32) -> Array<U32> & U32:
  (input, byte) = read
  (input, (value .|. (byte << shift) : U32))

def word(n: Nat, +index: U32, +shift: Nat, state: Array<U32> & U32) -> Array<U32> & U32:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{input, value}: word(rest, (index + 1 : U32), (shift + 8n : Nat), word.read(shift, value, Array.get(U32, input, index)))

def hash(+value: U32) -> U32:
  +a = (value .^. (value << 3n) : U32)
  +b = (a + (a >> 5n) : U32)
  +c = (b .^. (b << 4n) : U32)
  +d = (c + (c >> 17n) : U32)
  +e = (d .^. (d << 25n) : U32)
  ((e + (e >> 6n)) .&. 16383 : U32)

def equal.right(value: U32, read: Array<U32> & U32) -> Array<U32> & Bool:
  (input, other) = read
  (input, U32.is_eq(value, other))

def equal.left(index: U32, read: Array<U32> & U32) -> Array<U32> & Bool:
  (input, value) = read
  equal.right(value, Array.get(U32, input, index))

type Counting is Type:
  Counting{input: Array<U32>, length: U32, active: Bool}

def count.step(length: U32, read: Array<U32> & Bool) -> Counting:
  (input, +same) = read
  Counting{input, (length + Bool.to_u32(same) : U32), same}

def count(n: Nat, +a: U32, +b: U32, state: Counting) -> Array<U32> & U32:
  match n state:
    case 0n Counting{input, length, _}: (input, length)
    case _ Counting{input, length, False{}}: (input, length)
    case 1n+rest Counting{input, length, True{}}:
      count(rest, (a + 1 : U32), (b + 1 : U32), count.step(length, equal.left(b, Array.get(U32, input, a))))

type Best is Data:
  Best{length: U32, position: U32}

type Search is Type:
  Search{input: Array<U32>, best: Best}

def search.compared(position: U32, +best: Best, read: Array<U32> & U32) -> Search:
  Best{old, _} = best
  (input, +length) = read
  Search{input, Bool.pick(Best, (length > old : U32), Best{length, position}, best)}

def search.candidate(valid: Bool, +candidate: U32, at: U32, limit: U32, input: Array<U32>, best: Best) -> Search:
  match valid:
    case False{}: Search{input, best}
    case True{}: search.compared(candidate, best, count(U32.to_nat(limit), candidate, at, Counting{input, 0, True{}}))

def search(entries: +List<U32>, +at: U32, +limit: U32, state: Search) -> Search:
  match entries state:
    case Nil{} _: state
    case Con{+candidate, rest} Search{input, best}:
      search(rest, at, limit, search.candidate((at - candidate < 32768 : U32), candidate, at, limit, input, best))

type Bucket is Data:
  Bucket{count: U32, positions: +List<U32>}

def remember(full: Bool, +at: U32, count: U32, positions: +List<U32>) -> Bucket:
  match full:
    case False{}: Bucket{(count + 1 : U32), Con{at, positions}}
    case True{}: Bucket{9, Con{at, List.take(&2, U32, positions, 8n)}}

type Encoding is Type:
  Active{position: U32, input: Array<U32>, table: Array<Bucket>, writer: Writer}
  Encoded{input: Array<U32>, writer: Writer}

def advance(done: Bool, position: U32, input: Array<U32>, table: Array<Bucket>, writer: Writer) -> Encoding:
  match done:
    case True{}: Encoded{input, writer}
    case False{}: Active{position, input, table, writer}

def literal(+at: U32, size: U32, table: Array<Bucket>, writer: Writer, read: Array<U32> & U32) -> Encoding:
  (input, byte) = read
  advance((at + 1 >= size : U32), (at + 1 : U32), input, table, huffman(byte, writer))

def selected(use_match: Bool, +at: U32, size: U32, table: Array<Bucket>, writer: Writer, best: Best, input: Array<U32>) -> Encoding:
  match use_match best:
    case False{} _: literal(at, size, table, writer, Array.get(U32, input, at))
    case True{} Best{+len, position}:
      advance((at + len >= size : U32), (at + len : U32), input, table, distance((at - position : U32), length(U32.is_eq(len, 258), len, writer)))

def lazy.compared(at: U32, size: U32, table: Array<Bucket>, writer: Writer, +best: Best, result: Search) -> Encoding:
  Best{old, _} = best
  Search{input, Best{new, _}} = result
  selected((new <= old : U32), at, size, table, writer, best, input)

def lazy.bucket(+at: U32, +size: U32, input: Array<U32>, writer: Writer, +best: Best, read: Array<Bucket> & Bucket) -> Encoding:
  (table, Bucket{_, entries}) = read
  +remaining = (size - at - 1 : U32)
  lazy.compared(at, size, table, writer, best, search(entries, (at + 1 : U32), Bool.pick(U32, (remaining < 258 : U32), remaining, 258), Search{input, best}))

def lazy.hash(at: U32, size: U32, table: Array<Bucket>, writer: Writer, best: Best, read: Array<U32> & U32) -> Encoding:
  (input, value) = read
  lazy.bucket(at, size, input, writer, best, Array.get(Bucket, table, hash(value)))

def lazy(valid: Bool, +at: U32, size: U32, input: Array<U32>, table: Array<Bucket>, writer: Writer, best: Best) -> Encoding:
  match valid:
    case False{}: literal(at, size, table, writer, Array.get(U32, input, at))
    case True{}: lazy.hash(at, size, table, writer, best, word(3n, (at + 1 : U32), 0n, (input, 0)))

def current(+at: U32, h: U32, size: U32, table: Array<Bucket>, writer: Writer, +count: U32, entries: +List<U32>, result: Search) -> Encoding:
  Search{input, +best} = result
  Best{length, _} = best
  lazy((length >= 3 : U32), at, size, input, Array.set(Bucket, table, h, remember(U32.is_eq(count, 16), at, count, entries)), writer, best)

def bucket(+at: U32, h: U32, +size: U32, input: Array<U32>, writer: Writer, read: Array<Bucket> & Bucket) -> Encoding:
  (table, Bucket{count, +entries}) = read
  +remaining = (size - at : U32)
  current(at, h, size, table, writer, count, entries,
    search(entries, at, Bool.pick(U32, (remaining < 258 : U32), remaining, 258), Search{input, Best{2, 0}}))

def hashed(at: U32, size: U32, table: Array<Bucket>, writer: Writer, read: Array<U32> & U32) -> Encoding:
  (input, value) = read
  +h = hash(value)
  bucket(at, h, size, input, writer, Array.get(Bucket, table, h))

def step(full: Bool, +at: U32, size: U32, input: Array<U32>, table: Array<Bucket>, writer: Writer) -> Encoding:
  match full:
    case False{}: literal(at, size, table, writer, Array.get(U32, input, at))
    case True{}: hashed(at, size, table, writer, word(3n, at, 0n, (input, 0)))

def loop(n: Nat, +size: U32, state: Encoding) -> Array<U32> & Writer:
  match n state:
    case _ Encoded{input, writer}: (input, writer)
    case 0n Active{_, input, _, writer}: (input, writer)
    case 1n+rest Active{+at, input, table, writer}: loop(rest, size, step((at + 3 < size : U32), at, size, input, table, writer))

def pad(writer: Writer) -> Writer:
  Writer{buffer, +count, bytes, length} = writer
  put(0, ((8 - count) % 8 : U32), Writer{buffer, count, bytes, length})

def byte(value: U32, writer: Writer) -> Writer:
  Writer{buffer, count, bytes, length} = writer
  Writer{buffer, count, Con{value, bytes}, (length + 1 : U32)}

def stored.header(start: Bool, +remaining: U32, writer: Writer) -> Writer:
  match start:
    case False{}: writer
    case True{}:
      +length = Bool.pick(U32, (remaining < 32767 : U32), remaining, 32767)
      +inverse = (length .^. 65535 : U32)
      byte((inverse >> 8n : U32), byte((inverse .&. 255 : U32), byte((length >> 8n : U32), byte((length .&. 255 : U32), byte(Bool.to_u32(U32.is_eq(remaining, length)), writer)))))

def stored.read(writer: Writer, read: Array<U32> & U32) -> Array<U32> & Writer:
  (input, value) = read
  (input, byte(value, writer))

def stored(n: Nat, +at: U32, +size: U32, state: Array<U32> & Writer) -> Array<U32> & Writer:
  match n state:
    case 0n _: state
    case 1n+rest Tuple{input, writer}:
      stored(rest, (at + 1 : U32), size, stored.read(stored.header(U32.is_eq((at % 32767 : U32), 0), (size - at : U32), writer), Array.get(U32, input, at)))

def choose(stored_form: Bool, +size: U32, input: Array<U32>, writer: Writer) -> Array<U32> & Writer:
  match stored_form:
    case False{}: (input, writer)
    case True{}: stored(U32.to_nat(size), 0, size, (input, Writer{0, 0, [94,120], 2}))

def choose.writer(+size: U32, input: Array<U32>, writer: Writer) -> Array<U32> & Writer:
  Writer{buffer, count, bytes, +length} = writer
  choose((length > size + 2 + ((size + 32766) / 32767) * 5 : U32), size, input, Writer{buffer, count, bytes, length})

type Adler is Type:
  Adler{input: Array<U32>, a: U32, b: U32, left: U32}

def adler.block(end: Bool, input: Array<U32>, a: U32, b: U32, left: U32) -> Adler:
  match end:
    case True{}: Adler{input, (a % 65521 : U32), (b % 65521 : U32), 5552}
    case False{}: Adler{input, a, b, left}

def adler.read(a: U32, b: U32, +left: U32, read: Array<U32> & U32) -> Adler:
  (input, value) = read
  +next = (a + value : U32)
  adler.block(U32.is_eq(left, 1), input, next, (b + next : U32), (left - 1 : U32))

def adler(n: Nat, +at: U32, state: Adler) -> U32:
  match n state:
    case 0n Adler{_, a, b, _}: ((b << 16n) .|. a : U32)
    case 1n+rest Adler{input, a, b, left}: adler(rest, (at + 1 : U32), adler.read(a, b, left, Array.get(U32, input, at)))

type Stream is Data:
  Stream{size: U32, bytes: +List<U32>}

def wrap(writer: Writer, +checksum: U32) -> Stream:
  Writer{_, _, bytes, length} = writer
  Stream{(length + 4 : U32), List.reverse(&2, U32, Con{(checksum .&. 255 : U32), Con{((checksum >> 8n) .&. 255 : U32), Con{((checksum >> 16n) .&. 255 : U32), Con{(checksum >> 24n : U32), bytes}}}})}

def checksummed(+size: U32, result: Array<U32> & Writer) -> Stream:
  (input, writer) = result
  +first = (size % 5552 : U32)
  wrap(writer, adler(U32.to_nat(size), 0, Adler{input, 1, 0, Bool.pick(U32, U32.is_eq(first, 0), 5552, first)}))

def finish(+size: U32, result: Array<U32> & Writer) -> Stream:
  (input, writer) = result
  checksummed(size, choose.writer(size, input, pad(huffman(256, writer))))

def compress(+size: U32, input: Array<U32>) -> Stream:
  finish(size, loop(U32.to_nat(size), size, Active{0, input, Array.new(Bucket, 14n, Bucket{0, Nil{}}), Writer{3, 3, [94,120], 2}}))
