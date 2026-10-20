# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of msf_gif.h 2.2 (Miles Fogle; MIT or public
# domain), as raylib 6.2 ships it beside its examples
# (examples/core/msf_gif.h): msf_gif_begin, msf_gif_frame and msf_gif_end
# with the library's defaults (msf_gif_alpha_threshold 0, so no pixel is
# transparent by its alpha, and msf_gif_bgra_flag 0). See
# THIRD_PARTY_NOTICES.md and LICENSES/msf_gif.txt.
#
# A frame is cooked: each pixel is reduced to a few bits a channel with a
# 4x4 ordered dither, at the first depth, from the one the frame before
# allows down, that leaves fewer than 256 colors. It is written with a local
# palette of the colors it uses, in the order of their cooked values, and LZW
# codes of at most 12 bits; where the frame before has the same depth, a
# pixel equal to its pixel there is written as index 0, the transparent one.
#
# The C library cooks four pixels at a time with SSE2 where it has it and
# one at a time elsewhere; both give the same values (its saturating sums
# are the scalar code's minimum with 65535, and no product leaves 16 bits).
# This is the scalar code. Bytes are U32 values; pixels are R8G8B8A8 words
# (0xRRGGBBAA), row by row from the top.
import Base

# What msf_cook_frame makes of a depth: each channel's multiplier, the scale
# of its dither (k >> bits, for k = v << 12, is v << (12 - bits)), the
# divisor that its last shift is, and the masks of green and blue.
type Depth is Data:
  Depth{rmul: U32, gmul: U32, bmul: U32, rdither: U32, gdither: U32, bdither: U32, rdiv: U32, gdiv: U32, bdiv: U32, gmask: U32, bmask: U32}

# rdepthsArray, gdepthsArray and bdepthsArray: the three add up to the depth.
def red.bits(+depth: U32) -> U32:
  ((depth + 1) / 3 : U32)

def green.bits(+depth: U32) -> U32:
  ((depth + 2) / 3 : U32)

def blue.bits(+depth: U32) -> U32:
  (depth / 3 : U32)

# (short)((255.0f - diff)/255.0f*257) for diff = (1 << (8 - bits)) - 1 and
# the 0 to 6 bits a channel has.
def multiplier(bits: U32) -> U32:
  match bits:
    case 0: 0
    case 1: 129
    case 2: 193
    case 3: 225
    case 4: 241
    case 5: 249
    case _: 253

def cook.scales(+depth: U32) -> Depth:
  +r = red.bits(depth)
  +g = green.bits(depth)
  +b = blue.bits(depth)
  Depth{multiplier(r), multiplier(g), multiplier(b), (1 << U32.to_nat((12 - r : U32)) : U32), (1 << U32.to_nat((12 - g : U32)) : U32), (1 << U32.to_nat((12 - b : U32)) : U32),
    (1 << U32.to_nat((16 - r : U32)) : U32), (1 << U32.to_nat((16 - r - g : U32)) : U32), (1 << U32.to_nat((16 - r - g - b : U32)) : U32),
    (((1 << U32.to_nat(g)) - 1) << U32.to_nat(r) : U32), (((1 << U32.to_nat(b)) - 1) << U32.to_nat((r + g : U32)) : U32)}

# ditherKernel[(y & 3)*4 + (x & 3)] >> 12: the 4x4 ordered dither
# (0 8 2 10, 12 4 14 6, 3 11 1 9, 15 7 13 5).
def dither(+x: U32, +y: U32) -> U32:
  +t = ((x .^. y) .&. 3 : U32)
  (((t .&. 1) * 8) + ((y .&. 1) * 4) + (t .&. 2) + ((y >> 1n) .&. 1) : U32)

# The cooked pixel: blue, green and red reduced and packed, red lowest.
def cook.pixel(+word: U32, +v: U32, scales: Depth) -> U32:
  Depth{+rmul, +gmul, +bmul, +rdither, +gdither, +bdither, +rdiv, +gdiv, +bdiv, +gmask, +bmask} = scales
  +r = (U32.min(65535, (((word >> 24n) * rmul) + (v * rdither) : U32)) / rdiv : U32)
  +g = ((U32.min(65535, ((((word >> 16n) .&. 255) * gmul) + (v * gdither) : U32)) / gdiv) .&. gmask : U32)
  +b = ((U32.min(65535, ((((word >> 8n) .&. 255) * bmul) + (v * bdither) : U32)) / bdiv) .&. bmask : U32)
  (b .|. g .|. r : U32)

def mark.new(+count: U32, swapped: Array<U32> & U32) -> Array<U32> & U32:
  (used, +old) = swapped
  (used, ((count + 1) - old : U32))

# used[cooked] = 1, counting the colors as they are first marked. A pixel
# cooked as the one before it is marked already.
def mark(same: Bool, +value: U32, used: Array<U32>, +count: U32) -> Array<U32> & U32:
  match same:
    case True{}: (used, count)
    case False{}: mark.new(count, Array.swap(U32, used, value, 1))

# A depth's cooking: the pixels (the last first), the colors marked (an
# array of the depth's 1 << depth colors) and their count.
type Cooking is Type:
  Cooking{pixels: +List<U32>, used: Array<U32>, count: U32}

def cook.loop(raw: +List<U32>, +width: U32, +x: U32, +y: U32, +scales: Depth, +last: U32, acc: +List<U32>, state: Array<U32> & U32) -> Cooking:
  match raw state:
    case Nil{} Tuple{used, +count}: Cooking{acc, used, count}
    case Con{+word, +rest} Tuple{used, +count}:
      +value = cook.pixel(word, dither(x, y), scales)
      +wrap = U32.is_eq((x + 1 : U32), width)
      cook.loop(rest, width, Bool.pick(U32, wrap, 0, (x + 1 : U32)), Bool.pick(U32, wrap, (y + 1 : U32), y), scales, value, Con{value, acc}, mark(U32.is_eq(value, last), value, used, count))

def marked.read(+i: U32, +acc: +List<U32>, read: Array<U32> & U32) -> Array<U32> & +List<U32>:
  (used, +flag) = read
  (used, Bool.pick(+List<U32>, U32.is_eq(flag, 0), acc, Con{i, acc}))

# The colors marked, in ascending order: `i` goes down from the last one.
def marked(n: Nat, +i: U32, state: Array<U32> & +List<U32>) -> +List<U32>:
  match n state:
    case 0n Tuple{_, +acc}: acc
    case 1n+k Tuple{used, +acc}: marked(k, (i - 1 : U32), marked.read(i, acc, Array.get(U32, used, i)))

# A frame cooked at a depth: its pixels, the count of its colors and the
# colors, ascending.
type Pass is Data:
  Pass{pixels: +List<U32>, count: U32, values: +List<U32>}

def Pass.count(pass: Pass) -> U32:
  Pass{_, count, _} = pass
  count

def pass.done(+depth: U32, cooking: Cooking) -> Pass:
  Cooking{+pixels, used, +count} = cooking
  Pass{List.reverse(&2, U32, pixels), count, marked(U32.to_nat((1 << U32.to_nat(depth) : U32)), ((1 << U32.to_nat(depth)) - 1 : U32), (used, Nil{}))}

def cook.pass(+raw: +List<U32>, +width: U32, +depth: U32) -> Pass:
  pass.done(depth, cook.loop(raw, width, 0, 0, cook.scales(depth), 4294967295, Nil{}, (Array.new(U32, U32.to_nat(depth), 0), 0)))

# The frame msf_cook_frame leaves: the depth it stopped at and its cooking.
type Cooked is Data:
  Cooked{depth: U32, pass: Pass}

# do { ... } while (count >= 256 && --depth): `again` says the pass at hand
# has 256 colors or more. Such a pass has a depth of 8 or more, so the depth
# never reaches 0.
def cook.depths(n: Nat, +raw: +List<U32>, +width: U32, +depth: U32, again: Bool, +pass: Pass) -> Cooked:
  match n again:
    case 1n+k True{}:
      +next = cook.pass(raw, width, (depth - 1 : U32))
      cook.depths(k, raw, width, (depth - 1 : U32), (Pass.count(next) >= 256 : U32), next)
    case _ _: Cooked{depth, pass}

# A channel's bits spread over a byte: c << (8 - bits), or'ed with itself
# shifted down by bits, 2*bits and 3*bits.
def channel(+c: U32, +bits: U32) -> U32:
  +high = (c << U32.to_nat((8 - bits : U32)) : U32)
  (high .|. (high >> U32.to_nat(bits)) .|. (high >> U32.to_nat((bits * 2 : U32))) .|. (high >> U32.to_nat((bits * 3 : U32))) : U32)

# The local color table after its entry 0 (the last byte first) and tlb, the
# table index of each cooked color: the colors take 1, 2, ... in ascending
# order.
def palette(values: +List<U32>, +r: U32, +g: U32, +b: U32, +index: U32, tlb: Array<U32>, out: +List<U32>) -> Array<U32> & +List<U32>:
  match values:
    case Nil{}: (tlb, out)
    case Con{+i, +rest}:
      palette(rest, r, g, b, (index + 1 : U32), Array.set(U32, tlb, i, index),
        Con{channel((i >> U32.to_nat((r + g : U32)) : U32), b), Con{channel(((i >> U32.to_nat(r)) .&. ((1 << U32.to_nat(g)) - 1) : U32), g), Con{channel((i .&. ((1 << U32.to_nat(r)) - 1) : U32), r), out}}})

# The code stream: the bits not yet in a byte (`word`, `scale` being 1 <<
# their count), the bytes written (the last first) and their count.
type Bits is Data:
  Bits{word: U32, scale: U32, bytes: +List<U32>, size: U32}

def drain(n: Nat, +word: U32, +scale: U32, +bytes: +List<U32>, +size: U32) -> Bits:
  match n:
    case 0n: Bits{word, scale, bytes, size}
    case 1n+k:
      +full = (scale >= 256 : U32)
      drain(k, Bool.pick(U32, full, (word >> 8n : U32), word), Bool.pick(U32, full, (scale >> 8n : U32), scale), Bool.pick(+List<U32>, full, Con{(word .&. 255 : U32), bytes}, bytes),
        (size + Bool.pick(U32, full, 1, 0) : U32))

# msf_put_code: `code` in the bits `top` is 1 << of, low bits first. Codes
# have at most 12 bits, so at most two bytes fill.
def put(+code: U32, +top: U32, bits: Bits) -> Bits:
  Bits{+word, +scale, +bytes, +size} = bits
  drain(2n, (word + (code * scale) : U32), (scale * top : U32), bytes, size)

# The codes that follow a code: (color << 12) | code for each.
type Kids is Data:
  Kids{list: +List<U32>}

def kid.find(list: +List<U32>, +index: U32, +found: U32) -> U32:
  match list:
    case Nil{}: found
    case Con{+entry, +rest}: kid.find(rest, index, Bool.pick(U32, U32.is_eq((entry >> 12n : U32), index), (entry .&. 4095 : U32), found))

# The code of `index` after a code, 0 where the table has none.
def kid(kids: Kids, +index: U32) -> U32:
  Kids{+list} = kids
  kid.find(list, index, 0)

def kid.added(kids: Kids, +index: U32, +code: U32) -> Kids:
  Kids{+list} = kids
  Kids{Con{((index * 4096) + code : U32), list}}

# msf_compress_frame's loop: tlb, the LZW table by code (lzw.data, whose
# stride is the palette's size), lzw.len, `top` (1 << the bits of a code now,
# msf_bit_log(lzw.len - 1)), lastCode and the code stream. `seen` and
# `color` are the last cooked color looked up in tlb and its index.
type Lzw is Type:
  Lzw{tlb: Array<U32>, table: Array<Kids>, len: U32, top: U32, last: U32, bits: Bits, seen: U32, color: U32}

# color = (framesCompatible && the pixel is the frame before's)? 0 : tlb[pixel].
def lzw.color(skip: Bool, cached: Bool, +c: U32, +color: U32, tlb: Array<U32>) -> Array<U32> & U32:
  match skip cached:
    case True{} _: (tlb, 0)
    case False{} True{}: (tlb, color)
    case False{} False{}: Array.get(U32, tlb, c)

# The table is full at 4096 codes: the clear code, and a new table.
# Otherwise the code gets its new kid.
def lzw.grown(full: Bool, +clear: U32, tlb: Array<U32>, table: Array<Kids>, +kids: Kids, +len: U32, +top: U32, +last: U32, +bits: Bits, +seen: U32, +color: U32, +index: U32) -> Lzw:
  match full:
    case True{}: Lzw{tlb, Array.new(Kids, 12n, Kids{Nil{}}), (clear + 2 : U32), (clear * 2 : U32), index, put(clear, top, bits), seen, color}
    case False{}: Lzw{tlb, Array.set(Kids, table, last, kid.added(kids, index, len)), (len + 1 : U32), Bool.pick(U32, U32.is_eq(len, top), (top * 2 : U32), top), index, bits, seen, color}

# A color the last code has no code for writes the last code.
def lzw.coded(miss: Bool, +clear: U32, tlb: Array<U32>, table: Array<Kids>, +kids: Kids, +len: U32, +top: U32, +last: U32, +bits: Bits, +seen: U32, +color: U32, +index: U32, +code: U32) -> Lzw:
  match miss:
    case False{}: Lzw{tlb, table, len, top, code, bits, seen, color}
    case True{}: lzw.grown((len > 4095 : U32), clear, tlb, table, kids, len, top, last, put(last, top, bits), seen, color, index)

def lzw.looked(+clear: U32, tlb: Array<U32>, +len: U32, +top: U32, +last: U32, +bits: Bits, +seen: U32, +color: U32, +index: U32, read: Array<Kids> & Kids) -> Lzw:
  (table, +kids) = read
  +code = kid(kids, index)
  lzw.coded(U32.is_eq(code, 0), clear, tlb, table, kids, len, top, last, bits, seen, color, index, code)

def lzw.indexed(+skip: Bool, +clear: U32, table: Array<Kids>, +len: U32, +top: U32, +last: U32, +bits: Bits, +seen: U32, +color: U32, read: Array<U32> & U32) -> Lzw:
  (tlb, +index) = read
  lzw.looked(clear, tlb, len, top, last, bits, seen, Bool.pick(U32, skip, color, index), index, Array.get(Kids, table, last))

def lzw.step(+skip: Bool, +c: U32, +clear: U32, state: Lzw) -> Lzw:
  Lzw{tlb, table, +len, +top, +last, +bits, +seen, +color} = state
  lzw.indexed(skip, clear, table, len, top, last, bits, Bool.pick(U32, skip, seen, c), color, lzw.color(skip, U32.is_eq(c, seen), c, color, tlb))

# The pixels after the first, with the frame before's.
def lzw.loop(cur: +List<U32>, prev: +List<U32>, +same: Bool, +clear: U32, state: Lzw) -> Lzw:
  match cur prev:
    case Con{+c, +rest} Con{+p, +more}: lzw.loop(rest, more, same, clear, lzw.step(same && U32.is_eq(c, p), c, clear, state))
    case _ _: state

# The first pixel is lastCode; the stream begins with the clear code.
def lzw.begun(rest: +List<U32>, more: +List<U32>, +same: Bool, +clear: U32, +c: U32, +skip: Bool, read: Array<U32> & U32) -> Lzw:
  (tlb, +index) = read
  lzw.loop(rest, more, same, clear,
    Lzw{tlb, Array.new(Kids, 12n, Kids{Nil{}}), (clear + 2 : U32), (clear * 2 : U32), index, put(clear, (clear * 2 : U32), Bits{0, 1, Nil{}, 0}), Bool.pick(U32, skip, 4294967295, c), index})

def lzw.run(cur: +List<U32>, prev: +List<U32>, +same: Bool, +clear: U32, tlb: Array<U32>) -> Lzw:
  match cur prev:
    case Con{+c, +rest} Con{+p, +more}: lzw.begun(rest, more, same, clear, c, same && U32.is_eq(c, p), lzw.color(same && U32.is_eq(c, p), False{}, c, 0, tlb))
    case _ _: Lzw{tlb, Array.new(Kids, 12n, Kids{Nil{}}), (clear + 2 : U32), (clear * 2 : U32), 0, put(clear, (clear * 2 : U32), Bits{0, 1, Nil{}, 0}), 4294967295, 0}

# The stream's bytes in data sub-blocks of at most 255, each after its size:
# `left` bytes are left of the block at hand, `remaining` of the stream.
def chunk(bytes: +List<U32>, +left: U32, +remaining: U32, +out: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: out
    case Con{+b, +rest}:
      +start = U32.is_eq(left, 0)
      +size = U32.min(255, remaining)
      chunk(rest, (Bool.pick(U32, start, size, left) - 1 : U32), (remaining - 1 : U32), Con{b, Bool.pick(+List<U32>, start, Con{size, out}, out)})

# What msf_compress_frame wrote: the bytes (the last first) and whether its
# buffer held them.
type Written is Data:
  Written{fits: Bool, out: +List<U32>}

# The bits left over fill a last byte; then the blocks and the terminating
# empty one. The C code clears 260 bytes ahead of each sub-block it begins,
# in a buffer of 800 + width*height*3/2 bytes: a small frame of many colors
# does not fit (`room` is what the buffer has after the first sub-block's
# 260 bytes; each further sub-block takes 256).
def blocks.flushed(+room: U32, +out: +List<U32>, bits: Bits) -> Written:
  Bits{+word, +scale, +bytes, +size} = bits
  +partial = (scale > 1 : U32)
  Written{(((size / 255) * 256) <= room : U32),
    Con{0, chunk(List.reverse(&2, U32, Bool.pick(+List<U32>, partial, Con{(word .&. 255 : U32), bytes}, bytes)), 0, (size + Bool.pick(U32, partial, 1, 0) : U32), out)}}

# After the pixels: lastCode, then the end code, in
# msf_imin(12, msf_bit_log(lzw.len)) bits.
def blocks(+clear: U32, +room: U32, +out: +List<U32>, state: Lzw) -> Written:
  Lzw{_, _, +len, +top, +last, +bits, _, _} = state
  blocks.flushed(room, out, put((clear + 1 : U32), U32.min(4096, Bool.pick(U32, U32.is_eq(len, top), (top * 2 : U32), top)), put(last, top, bits)))

def onto(xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}: acc
    case Con{+x, +rest}: onto(rest, Con{x, acc})

def zeros(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n: acc
    case 1n+k: zeros(k, Con{0, acc})

def length(xs: +List<U32>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case Con{_, +rest}: length(rest, (n + 1 : U32))

# A recording (MsfGifState): the size, the frame before (its cooked pixels,
# depth and count of colors; depth 0 before the first frame) and the file's
# bytes so far, the last first.
type Gif is Data:
  Gif{width: U32, height: U32, pixels: +List<U32>, depth: U32, count: U32, out: +List<U32>}

# msf_gif_begin(width, height): the header, the logical screen without a
# global table and the NETSCAPE2.0 block that loops for ever. None for a
# side of 0 (msf_gif_frame would read a pixel that is not there) or above
# 4096, Jonlib's image limit.
def begin(+width: U32, +height: U32) -> Maybe<Gif>:
  +valid = (width >= 1 : U32) && (width <= 4096 : U32) && (height >= 1 : U32) && (height <= 4096 : U32)
  Bool.pick(Maybe<Gif>, valid, Some{Gif{width, height, Nil{}, 0, 0, onto([71, 73, 70, 56, 57, 97, (width .&. 255 : U32), (width >> 8n : U32), (height .&. 255 : U32), (height >> 8n : U32), 112, 0, 0,
    33, 255, 11, 78, 69, 84, 83, 67, 65, 80, 69, 50, 46, 48, 3, 1, 0, 0, 0], Nil{})}}, None{})

# The graphic control extension (no disposal, index 0 transparent, the
# delay) and the image descriptor with its local table's size.
def frame.header(+width: U32, +height: U32, +centiseconds: U32, +minimum: U32) -> +List<U32>:
  [33, 249, 4, 5, (centiseconds .&. 255 : U32), ((centiseconds >> 8n) .&. 255 : U32), 0, 0, 44, 0, 0, 0, 0, (width .&. 255 : U32), (width >> 8n : U32), (height .&. 255 : U32), (height >> 8n : U32),
    (127 + minimum : U32)]

# msf_imax(2, msf_bit_log(count)) for the 1 to 255 colors of a frame: the
# bits of the table's size, and LZW's minimum code size.
def lzw.minimum(+count: U32) -> U32:
  Bool.pick(U32, (count < 4 : U32), 2, Bool.pick(U32, (count < 8 : U32), 3, Bool.pick(U32, (count < 16 : U32), 4, Bool.pick(U32, (count < 32 : U32), 5, Bool.pick(U32, (count < 64 : U32), 6,
    Bool.pick(U32, (count < 128 : U32), 7, 8))))))

def held(+holds: Bool, written: Written) -> Written:
  Written{+fits, +out} = written
  Written{holds && fits, out}

def frame.written(+width: U32, +height: U32, +depth: U32, +count: U32, +pixels: +List<U32>, written: Written) -> Maybe<Gif>:
  Written{+fits, +out} = written
  Bool.pick(Maybe<Gif>, fits, Some{Gif{width, height, pixels, depth, count, out}}, None{})

# The table's unused entries are zeros; then the minimum code size and the
# codes. The header, the table, the size and the first sub-block's 260
# bytes must fit the buffer: 279 + 3*clear of its 800 + width*height*3/2.
def frame.coded(+width: U32, +height: U32, +depth: U32, +count: U32, +pixels: +List<U32>, +prev: +List<U32>, +same: Bool, +clear: U32, +minimum: U32, made: Array<U32> & +List<U32>) -> Maybe<Gif>:
  (tlb, +table) = made
  +space = (800 + ((width * height * 3) / 2) : U32)
  +taken = (279 + (clear * 3) : U32)
  +holds = (taken <= space : U32)
  frame.written(width, height, depth, count, pixels,
    held(holds, blocks(clear, Bool.pick(U32, holds, (space - taken : U32), 0), Con{minimum, zeros(U32.to_nat((((clear - 1) - count) * 3 : U32)), table)}, lzw.run(pixels, prev, same, clear, tlb))))

def frame.passed(+width: U32, +height: U32, +previous: +List<U32>, +same: Bool, +out: +List<U32>, +centiseconds: U32, +depth: U32, pass: Pass) -> Maybe<Gif>:
  Pass{+pixels, +count, +values} = pass
  +minimum = lzw.minimum(count)
  frame.coded(width, height, depth, count, pixels, Bool.pick(+List<U32>, same, previous, pixels), same, (1 << U32.to_nat(minimum) : U32), minimum,
    palette(values, red.bits(depth), green.bits(depth), blue.bits(depth), 1, Array.new(U32, U32.to_nat(depth), 0), Con{0, Con{0, Con{0, onto(frame.header(width, height, centiseconds, minimum), out)}}}))

# The frames are compatible where their depths are the same (the three
# channels' bits are a function of the depth) and nothing is transparent.
def frame.cooked(+width: U32, +height: U32, +previous: +List<U32>, +depth: U32, +out: +List<U32>, +centiseconds: U32, cooked: Cooked) -> Maybe<Gif>:
  Cooked{+now, +pass} = cooked
  frame.passed(width, height, previous, U32.is_eq(now, depth), out, centiseconds, now, pass)

# msf_imax(1, msf_imin(16, maxBitDepth)) for the int's word.
def asked.depth(+max: U32) -> U32:
  Bool.pick(U32, (max >= 2147483648 : U32), 1, U32.max(1, U32.min(16, max)))

def frame.checked(valid: Bool, +width: U32, +height: U32, +previous: +List<U32>, +depth: U32, +count: U32, +out: +List<U32>, +pixels: +List<U32>, +centiseconds: U32, +max: U32) -> Maybe<Gif>:
  match valid:
    case False{}: None{}
    case True{}:
      +start = U32.min(asked.depth(max), (depth + (160 / U32.max(1, count)) : U32))
      +first = cook.pass(pixels, width, start)
      frame.cooked(width, height, previous, depth, out, centiseconds, cook.depths(16n, pixels, width, start, (Pass.count(first) >= 256 : U32), first))

# msf_gif_frame(handle, pixels, centiSecondsPerFrame, maxBitDepth, width*4):
# the recording with the frame written. `pixels` are the frame's width*height
# words; None for any other count (the C code reads width*height pixels) and
# for a frame the C code writes past its buffer (small frames of many
# colors: with 128 colors or more, any frame under 165 pixels).
# `centiseconds` and `max_depth` are the ints' words.
def frame(gif: Gif, +pixels: +List<U32>, +centiseconds: U32, +max_depth: U32) -> Maybe<Gif>:
  Gif{+width, +height, +previous, +depth, +count, +out} = gif
  frame.checked(U32.is_eq(length(pixels, 0), (width * height : U32)), width, height, previous, depth, count, out, pixels, centiseconds, max_depth)

# msf_gif_end(handle): the file's bytes, with the trailer.
def finish(gif: Gif) -> +List<U32>:
  Gif{_, _, _, _, _, +out} = gif
  List.reverse(&2, U32, Con{59, out})
