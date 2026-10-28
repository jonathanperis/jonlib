# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered adaptation of raylib's Base64 utilities in rcore.c; see LICENSES/raylib.txt.
import Base

type Encoded is Data:
  Encoded{size: U32, text: String}

def character(+value: U32) -> Char:
  Char.from_u32(Bool.pick(U32, (value < 26 : U32), (value + 65 : U32),
    Bool.pick(U32, (value < 52 : U32), (value + 71 : U32),
      Bool.pick(U32, (value < 62 : U32), (value - 4 : U32), Bool.pick(U32, U32.is_eq(value, 62), 43, 47)))))

def block(+size: U32, a: U32, b: U32, c: U32, reversed: String) -> String:
  +packed = ((a << 16n) .|. (b << 8n) .|. c : U32)
  first = character(((packed >> 18n) .&. 63 : U32))
  second = character(((packed >> 12n) .&. 63 : U32))
  third = Bool.pick(Char, (size > 1 : U32), character(((packed >> 6n) .&. 63 : U32)), '=')
  fourth = Bool.pick(Char, (size > 2 : U32), character((packed .&. 63 : U32)), '=')
  SCon{fourth, SCon{third, SCon{second, SCon{first, reversed}}}}

def encoded(valid: Bool, size: U32, reversed: String) -> Maybe<&2, Encoded>:
  match valid:
    case False{}: None{}
    case True{}: Some{Encoded{(size + 1 : U32), String.reverse(reversed)}}

def encoding(bytes: +List<U32>, +count: U32, +size: U32, reversed: String, valid: Bool) -> Maybe<&2, Encoded>:
  match bytes valid:
    case _ False{}: None{}
    case Nil{} True{}: encoded(True{}, size, reversed)
    case Con{+a, Nil{}} True{}:
      encoded(((a <= 255) && (count + 1 <= 1048576) : U32), (size + 4 : U32), block(1, a, 0, 0, reversed))
    case Con{+a, Con{+b, Nil{}}} True{}:
      encoded(((a <= 255) && (b <= 255) && (count + 2 <= 1048576) : U32), (size + 4 : U32), block(2, a, b, 0, reversed))
    case Con{+a, Con{+b, Con{+c, rest}}} True{}:
      encoding(rest, (count + 3 : U32), (size + 4 : U32), block(3, a, b, c, reversed),
        ((a <= 255) && (b <= 255) && (c <= 255) && (count + 3 <= 1048576) : U32))

def encode(bytes: +List<U32>) -> Maybe<&2, Encoded>:
  encoding(bytes, 0, 0, "", True{})

# 1610612733 is the largest length whose rounded multiple of 3 keeps
# 4*(paddedSize/3)+1 inside a signed int.
def encoding_until(bytes: +List<U32>, +count: U32, +size: U32, reversed: String, valid: Bool, +limit: U32) -> Maybe<&2, Encoded>:
  match bytes valid:
    case _ False{}: None{}
    case Nil{} True{}: encoded(True{}, size, reversed)
    case Con{+a, Nil{}} True{}:
      encoded(((a <= 255) && (count + 1 <= limit) : U32), (size + 4 : U32), block(1, a, 0, 0, reversed))
    case Con{+a, Con{+b, Nil{}}} True{}:
      encoded(((a <= 255) && (b <= 255) && (count + 2 <= limit) : U32), (size + 4 : U32), block(2, a, b, 0, reversed))
    case Con{+a, Con{+b, Con{+c, rest}}} True{}:
      encoding_until(rest, (count + 3 : U32), (size + 4 : U32), block(3, a, b, c, reversed),
        ((a <= 255) && (b <= 255) && (c <= 255) && (count + 3 <= limit) : U32), limit)

def encode_wide(bytes: +List<U32>) -> Maybe<&2, Encoded>:
  encoding_until(bytes, 0, 0, "", True{}, 1610612733)

def value(character: Char) -> U32:
  +code = Char.to_u32(character)
  Bool.pick(U32, ((code >= 65) && (code <= 90) : U32), (code - 65 : U32),
    Bool.pick(U32, ((code >= 97) && (code <= 122) : U32), (code - 71 : U32),
      Bool.pick(U32, ((code >= 48) && (code <= 57) : U32), (code + 4 : U32),
        Bool.pick(U32, U32.is_eq(code, 43), 62, Bool.pick(U32, U32.is_eq(code, 47), 63, Bool.pick(U32, U32.is_eq(code, 61), 64, 65))))))

def ended(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{character, _}: U32.is_eq(Char.to_u32(character), 0)

type Step is Data:
  Step{count: U32, reversed: +List<U32>, valid: Bool, finished: Bool}

def prefix(missing: U32, a: U32, b: U32, c: U32, reversed: +List<U32>) -> +List<U32>:
  match missing:
    case 0: Con{c, Con{b, Con{a, reversed}}}
    case 1: Con{b, Con{a, reversed}}
    case _: Con{a, reversed}

def step(+a: U32, +b: U32, +c: U32, +d: U32, count: U32, reversed: +List<U32>) -> Step:
  +missing = Bool.pick(U32, U32.is_eq(c, 64), 2, Bool.pick(U32, U32.is_eq(d, 64), 1, 0))
  +next = (count + 3 - missing : U32)
  +packed = ((a << 18n) .|. (b << 12n) .|. ((c .&. 63) << 6n) .|. (d .&. 63) : U32)
  Step{next, prefix(missing, ((packed >> 16n) .&. 255 : U32), ((packed >> 8n) .&. 255 : U32), (packed .&. 255 : U32), reversed),
    ((a < 64) && (b < 64) && (c <= 64) && (d <= 64) && ((c < 64) || U32.is_eq(d, 64)) && (next <= 1048576) : U32),
    (missing > 0 : U32)}

def decoded(valid: Bool, reversed: +List<U32>) -> Maybe<&2, +List<U32>>:
  match valid:
    case False{}: None{}
    case True{}: Some{List.reverse(&2, U32, reversed)}

def decoding(text: String, state: Step) -> Maybe<&2, +List<U32>>:
  match text state:
    case _ Step{_, _, False{}, _}: None{}
    case _ Step{_, reversed, True{}, True{}}: decoded(ended(text), reversed)
    case SNil{} Step{count, reversed, True{}, False{}}: decoded((count > 0 : U32), reversed)
    case SCon{Chr{0}, _} Step{count, reversed, True{}, False{}}: decoded((count > 0 : U32), reversed)
    case SCon{a, SCon{b, SCon{c, SCon{d, rest}}}} Step{count, reversed, True{}, False{}}:
      decoding(rest, step(value(a), value(b), value(c), value(d), count, reversed))
    case _ _: None{}

def decode(text: String) -> Maybe<&2, +List<U32>>:
  decoding(text, Step{0, Nil{}, True{}, False{}})

# DecodeDataBase64 for a C string whose length fits in a signed int.
# Unknown bytes are sextet 0. The size is 3*(length/4) minus the trailing
# padding and may be negative; the bytes are the positive prefix of that size.
type Decoded is Data:
  Decoded{size: U32, bytes: +List<U32>}

type WideScan is Data:
  WideReady{count: U32, padding: U32, reversed: +List<U32>}
  WideRefused{}

type Prep is Data:
  WideGo{}
  WideStop{code: U32}
  WideReject{}

def sextet(+code: U32) -> U32:
  Bool.pick(U32, ((code >= 65) && (code <= 90) : U32), (code - 65 : U32),
    Bool.pick(U32, ((code >= 97) && (code <= 122) : U32), (code - 71 : U32),
      Bool.pick(U32, ((code >= 48) && (code <= 57) : U32), (code + 4 : U32),
        Bool.pick(U32, U32.is_eq(code, 43), 62, Bool.pick(U32, U32.is_eq(code, 47), 63, 0)))))

def dropped(same: Bool) -> WideScan:
  match same:
    case True{}: WideRefused{}
    case False{}: WideRefused{}

def refuse(text: String, bytes: +List<U32>, seen: Bool, +mixed: U32) -> WideScan:
  match text bytes seen:
    case _ _ _: dropped(U32.is_eq((mixed .&. 0 : U32), 0))

def finished(seen: Bool, +count: U32, +padding: U32, reversed: +List<U32>, +code: U32) -> WideScan:
  match seen:
    case False{}: refuse("", reversed, False{}, (count .|. (padding .|. (code .&. 0) : U32) : U32))
    case True{}: WideReady{(count .|. (code .&. 0) : U32), padding, reversed}

def swallow3(a: Bool, b: Bool, c: Bool, +value: U32) -> U32:
  match a b c:
    case _ _ _: value

def swallow2(a: Bool, b: Bool, +value: U32) -> U32:
  match a b:
    case _ _: value

def swallow1(a: Bool, +value: U32) -> U32:
  match a:
    case _: value

def next_count(zero: Bool, foreign: Bool, room: Bool, +count: U32) -> U32:
  match zero:
    case True{}: swallow2(foreign, room, count)
    case False{}:
      match foreign:
        case True{}: swallow1(room, count)
        case False{}:
          match room:
            case False{}: count
            case True{}: (count + 1 : U32)

def next_padding(zero: Bool, foreign: Bool, equals: Bool, room: Bool, +padding: U32) -> U32:
  match zero:
    case True{}: swallow3(foreign, equals, room, padding)
    case False{}:
      match foreign:
        case True{}: swallow2(equals, room, padding)
        case False{}:
          match equals:
            case True{}:
              match room:
                case True{}: (padding + 1 : U32)
                case False{}: padding
            case False{}:
              match room:
                case True{}: (padding .&. 0 : U32)
                case False{}: padding

def keep_list(same: Bool, +code: U32, reversed: +List<U32>) -> +List<U32>:
  match same:
    case True{}: reversed
    case False{}: reversed

def next_list(zero: Bool, foreign: Bool, room: Bool, +code: U32, reversed: +List<U32>) -> +List<U32>:
  match zero:
    case True{}: keep_list(U32.is_eq((code .&. 0 : U32), 0), code, reversed)
    case False{}:
      match foreign:
        case True{}: keep_list(U32.is_eq((code .&. 0 : U32), 0), code, reversed)
        case False{}:
          match room:
            case False{}: keep_list(U32.is_eq((code .&. 0 : U32), 0), code, reversed)
            case True{}: Con{code, reversed}

def next_seen(zero: Bool, foreign: Bool, equals: Bool, room: Bool, seen: Bool) -> Bool:
  match zero:
    case True{}:
      match foreign equals room seen:
        case _ _ _ flag: flag
    case False{}:
      match foreign:
        case True{}:
          match equals room seen:
            case _ _ flag: flag
        case False{}:
          match equals:
            case True{}:
              match room seen:
                case _ flag: flag
            case False{}:
              match room:
                case True{}: True{}
                case False{}: seen

def reject_code(same: Bool) -> Prep:
  match same:
    case True{}: WideReject{}
    case False{}: WideReject{}

def go_code(same: Bool) -> Prep:
  match same:
    case True{}: WideGo{}
    case False{}: WideGo{}

def next_prep(zero: Bool, foreign: Bool, room: Bool, +code: U32) -> Prep:
  match zero:
    case True{}: WideStop{swallow2(foreign, room, code)}
    case False{}:
      match foreign:
        case True{}: reject_code(U32.is_eq(swallow1(room, (code .&. 0 : U32)), 0))
        case False{}:
          match room:
            case False{}: reject_code(U32.is_eq((code .&. 0 : U32), 0))
            case True{}: go_code(U32.is_eq((code .&. 0 : U32), 0))

def ignore_text(text: String, scan: WideScan) -> WideScan:
  match text:
    case _: scan

def scanning(text: String, prep: Prep, +count: U32, +padding: U32, reversed: +List<U32>, seen: Bool) -> WideScan:
  match text prep:
    case leftover WideStop{code}: ignore_text(leftover, finished(seen, count, padding, reversed, code))
    case leftover WideReject{}: refuse(leftover, reversed, seen, (count .|. padding : U32))
    case SNil{} WideGo{}: finished(seen, count, padding, reversed, 0)
    case SCon{character, rest} WideGo{}:
      +code = Char.to_u32(character)
      +zero = U32.is_eq(code, 0)
      +foreign = (code > 255 : U32)
      +equals = U32.is_eq(code, 61)
      +room = (count < 2147483647 : U32)
      scanning(rest, next_prep(zero, foreign, room, code), next_count(zero, foreign, room, count), next_padding(zero, foreign, equals, room, padding), next_list(zero, foreign, room, code, reversed), next_seen(zero, foreign, equals, room, seen))

def packed(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  ((a << 18n) .|. (b << 12n) .|. (c << 6n) .|. d : U32)

def emit3(+word: U32, reversed: +List<U32>) -> +List<U32>:
  Con{(word .&. 255 : U32), Con{((word >> 8n) .&. 255 : U32), Con{((word >> 16n) .&. 255 : U32), reversed}}}

def keep_groups(bytes: +List<U32>, reversed: +List<U32>) -> +List<U32>:
  match bytes:
    case _: reversed

def groups(bytes: +List<U32>, reversed: +List<U32>) -> +List<U32>:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      groups(rest, emit3(packed(sextet(a), sextet(b), sextet(c), sextet(d)), reversed))
    case other: keep_groups(other, reversed)

def visible(+bits: U32) -> U32:
  Bool.pick(U32, U32.is_eq((bits >> 31n : U32), 0), bits, 0)

def limited(+max_out: U32, +padding: U32) -> U32 & U32:
  +bits = (max_out - padding : U32)
  (bits, visible(bits))

def reverse_using(same: Bool, reversed: +List<U32>) -> +List<U32>:
  match same:
    case True{}: List.reverse(&2, U32, reversed)
    case False{}: List.reverse(&2, U32, reversed)

def shown_prefix(bytes: +List<U32>, done: Bool, +shown: U32, reversed: +List<U32>) -> +List<U32>:
  match bytes done:
    case _ True{}: reverse_using(U32.is_eq((shown .&. 0 : U32), 0), reversed)
    case Nil{} False{}: reverse_using(U32.is_eq((shown .&. 0 : U32), 0), reversed)
    case Con{byte, rest} False{}: shown_prefix(rest, U32.is_eq(shown, 1), (shown - 1 : U32), Con{byte, reversed})

def assemble(limits: U32 & U32, bytes: +List<U32>) -> Maybe<&2, Decoded>:
  (bits, +shown) = limits
  Some{Decoded{bits, shown_prefix(List.reverse(&2, U32, groups(bytes, Nil{})), U32.is_eq(shown, 0), shown, Nil{})}}

def decoded_wide(scan: WideScan) -> Maybe<&2, Decoded>:
  match scan:
    case WideRefused{}: None{}
    case WideReady{+count, +padding, reversed}:
      assemble(limited(((count / 4 : U32) * 3 : U32), padding), List.reverse(&2, U32, reversed))

def decode_wide(text: String) -> Maybe<&2, Decoded>:
  decoded_wide(scanning(text, WideGo{}, 0, 0, Nil{}, False{}))
