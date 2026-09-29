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
