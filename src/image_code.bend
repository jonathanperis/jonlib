# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of pinned raylib ExportImageAsCode and ExportDataAsCode.
# Required upstream template/credits retained; see LICENSES/raylib.txt.
import Base

def last_dot(path: String, +position: Nat, last: Nat) -> Nat:
  match path:
    case SNil{}: last
    case SCon{character, rest}: last_dot(rest, 1n+position, Bool.pick(Nat, Char.is_eq(character, '.'), position, last))

def stem(+name: String) -> String:
  +at = last_dot(name, 0n, 0n)
  String.to_upper(Bool.pick(String, Nat.is_lt(0n, at), String.take(name, at), name))

def name.checked(valid: Bool, reversed: String) -> Maybe<&2, String>:
  match valid:
    case False{}: None{}
    case True{}: Some{stem(String.reverse(reversed))}

def name.scan(path: String, +length: Nat, reversed: String, valid: Bool) -> Maybe<&2, String>:
  match path valid:
    case _ False{}: None{}
    case SNil{} True{}: name.checked(Nat.is_lt(0n, length) && Nat.is_le(length, 200n), reversed)
    case SCon{+character, rest} True{}:
      +code = Char.to_u32(character)
      +separator = U32.is_eq(code, 47) || U32.is_eq(code, 92)
      name.scan(rest, Bool.pick(Nat, separator, 0n, 1n+length), Bool.pick(String, separator, "", SCon{character, reversed}),
        ((code > 0) && (code < 128) : U32))

def name(path: String) -> Maybe<&2, String>:
  name.scan(path, 0n, "", True{})

def prepend(text: String, reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{character, rest}: prepend(rest, SCon{character, reversed})

def digit(+value: U32) -> Char:
  Char.from_u32(Bool.pick(U32, (value < 10 : U32), (value + 48 : U32), (value + 87 : U32)))

def hex_byte(+value: U32) -> String:
  +low = {SCon{digit((value % 16 : U32)), SNil{}} : String}
  Bool.pick(String, (value < 16 : U32), low, SCon{digit((value / 16 : U32)), low})

def body(~q: Quant, bytes: List<q, U32>, +index: U32, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case Con{byte, Nil{}}: String.reverse(prepend("0x" ++ hex_byte(byte) ++ " };\n", reversed))
    case Con{byte, rest}:
      body(~q, rest, (index + 1 : U32), prepend("0x" ++ hex_byte(byte) ++ Bool.pick(String, U32.is_eq((index % 20 : U32), 0), ",\n", ", "), reversed))

def banner() -> String:
  "////////////////////////////////////////////////////////////////////////////////////////\n"
    ++ "//                                                                                    //\n"
    ++ "// ImageAsCode exporter v1.0 - Image pixel data exported as an array of bytes         //\n"
    ++ "//                                                                                    //\n"
    ++ "// more info and bugs-report:  github.com/raysan5/raylib                              //\n"
    ++ "// feedback and support:       ray[at]raylib.com                                      //\n"
    ++ "//                                                                                    //\n"
    ++ "// Copyright (c) 2018-2026 Ramon Santamaria (@raysan5)                                //\n"
    ++ "//                                                                                    //\n"
    ++ "////////////////////////////////////////////////////////////////////////////////////////\n\n"

def encode(~q: Quant, +name: String, width: U32, height: U32, format: U32, size: U32, bytes: List<q, U32>) -> String:
  header = banner() ++ "// Image data information\n"
    ++ "#define " ++ name ++ "_WIDTH    " ++ U32.show(width) ++ "\n"
    ++ "#define " ++ name ++ "_HEIGHT   " ++ U32.show(height) ++ "\n"
    ++ "#define " ++ name ++ "_FORMAT   " ++ U32.show(format) ++ "          // raylib internal pixel format\n\n"
    ++ "static unsigned char " ++ name ++ "_DATA[" ++ U32.show(size) ++ "] = { "
  body(~q, bytes, 0, prepend(header, ""))

# ExportDataAsCode: the basename without its last extension, a-z upper-cased and
# '.', '-', '?', '!', '+' replaced by '_'; ASCII basenames of 1..200 characters.
def data.symbol(+character: Char) -> Char:
  +code = Char.to_u32(character)
  Bool.pick(Char, ((code >= 97) && (code <= 122) : U32), Char.from_u32((code - 32 : U32)),
    Bool.pick(Char, U32.is_eq(code, 46) || U32.is_eq(code, 45) || U32.is_eq(code, 63) || U32.is_eq(code, 33) || U32.is_eq(code, 43), '_', character))

def data.symbols(name: String, reversed: String) -> String:
  match name:
    case SNil{}: String.reverse(reversed)
    case SCon{character, rest}: data.symbols(rest, SCon{data.symbol(character), reversed})

def data.stem(+name: String) -> String:
  +at = last_dot(name, 0n, 0n)
  data.symbols(Bool.pick(String, Nat.is_lt(0n, at), String.take(name, at), name), "")

def data.checked(valid: Bool, reversed: String) -> Maybe<&2, String>:
  match valid:
    case False{}: None{}
    case True{}: Some{data.stem(String.reverse(reversed))}

def data.scan(path: String, +length: Nat, reversed: String, valid: Bool) -> Maybe<&2, String>:
  match path valid:
    case _ False{}: None{}
    case SNil{} True{}: data.checked(Nat.is_lt(0n, length) && Nat.is_le(length, 200n), reversed)
    case SCon{+character, rest} True{}:
      +code = Char.to_u32(character)
      +separator = U32.is_eq(code, 47) || U32.is_eq(code, 92)
      data.scan(rest, Bool.pick(Nat, separator, 0n, 1n+length), Bool.pick(String, separator, "", SCon{character, reversed}),
        ((code > 0) && (code < 128) : U32))

def data.name(path: String) -> Maybe<&2, String>:
  data.scan(path, 0n, "", True{})

def data.banner() -> String:
  "////////////////////////////////////////////////////////////////////////////////////////\n"
    ++ "//                                                                                    //\n"
    ++ "// DataAsCode exporter v1.0 - Raw data exported as an array of bytes                  //\n"
    ++ "//                                                                                    //\n"
    ++ "// more info and bugs-report:  github.com/raysan5/raylib                              //\n"
    ++ "// feedback and support:       ray[at]raylib.com                                      //\n"
    ++ "//                                                                                    //\n"
    ++ "// Copyright (c) 2022-2026 Ramon Santamaria (@raysan5)                                //\n"
    ++ "//                                                                                    //\n"
    ++ "////////////////////////////////////////////////////////////////////////////////////////\n\n"

def data.encode(~q: Quant, +name: String, size: U32, bytes: List<q, U32>) -> String:
  header = data.banner() ++ "#define " ++ name ++ "_DATA_SIZE     " ++ U32.show(size) ++ "\n\n"
    ++ "static unsigned char " ++ name ++ "_DATA[" ++ name ++ "_DATA_SIZE] = { "
  body(~q, bytes, 0, prepend(header, ""))

# ExportDataAsCode's basename: stop at the first NUL, keep bytes 1..255, reset at
# '/' or '\\', then keep the first 255 bytes (snprintf into the 256-byte name).
type NamePrep is Data:
  NameGo{}
  NameDone{}
  NameBad{}

def data.done_prep(fits: Bool) -> NamePrep:
  match fits:
    case True{}: NameDone{}
    case False{}: NameDone{}

def data.next_prep(zero: Bool, fits: Bool) -> NamePrep:
  match zero:
    case True{}: data.done_prep(fits)
    case False{}:
      match fits:
        case False{}: NameBad{}
        case True{}: NameGo{}

def data.same_length(a: Bool, b: Bool, c: Bool, +length: Nat) -> Nat:
  match a b c:
    case _ _ _: length

def data.next_length(zero: Bool, sep: Bool, fits: Bool, room: Bool, +length: Nat) -> Nat:
  match zero:
    case True{}: data.same_length(sep, fits, room, length)
    case False{}:
      match sep:
        case True{}: data.same_length(fits, room, False{}, 0n)
        case False{}:
          match fits:
            case False{}: data.same_length(room, False{}, False{}, length)
            case True{}:
              match room:
                case True{}: 1n+length
                case False{}: length

def data.hold(a: Bool, b: Bool, c: Bool, +character: Char, reversed: String) -> String:
  match a b c character:
    case _ _ _ _: reversed

def data.clear_name(a: Bool, b: Bool, +character: Char, reversed: String) -> String:
  match a b character reversed:
    case _ _ _ _: ""

def data.push_name(zero: Bool, sep: Bool, fits: Bool, room: Bool, +character: Char, reversed: String) -> String:
  match zero:
    case True{}: data.hold(sep, fits, room, character, reversed)
    case False{}:
      match sep:
        case True{}: data.clear_name(fits, room, character, reversed)
        case False{}:
          match fits:
            case False{}: data.hold(room, False{}, False{}, character, reversed)
            case True{}:
              match room:
                case False{}: data.hold(False{}, False{}, False{}, character, reversed)
                case True{}: SCon{character, reversed}

def data.sized(ok: Bool, reversed: String) -> String:
  match ok:
    case True{}: reversed
    case False{}: reversed

def data.finish(path: String, +length: Nat, reversed: String) -> Maybe<&2, String>:
  match path:
    case _: Some{data.stem(String.reverse(data.sized(Nat.is_le(length, 255n), reversed)))}

def data.none_length(ok: Bool) -> Maybe<&2, String>:
  match ok:
    case True{}: None{}
    case False{}: None{}

def data.abandon(path: String, +length: Nat, reversed: String) -> Maybe<&2, String>:
  match path reversed:
    case _ _: data.none_length(Nat.is_le(length, 255n))

def data.wide(path: String, prep: NamePrep, +length: Nat, reversed: String) -> Maybe<&2, String>:
  match path prep:
    case leftover NameDone{}: data.finish(leftover, length, reversed)
    case leftover NameBad{}: data.abandon(leftover, length, reversed)
    case SNil{} NameGo{}: data.finish("", length, reversed)
    case SCon{+character, rest} NameGo{}:
      +code = Char.to_u32(character)
      +zero = U32.is_eq(code, 0)
      +sep = U32.is_eq(code, 47) || U32.is_eq(code, 92)
      +fits = (code <= 255 : U32)
      +room = Nat.is_lt(length, 255n)
      data.wide(rest, data.next_prep(zero, fits), data.next_length(zero, sep, fits, room, length), data.push_name(zero, sep, fits, room, character, reversed))

# File.open encodes the Bend path as UTF-8. ExportDataAsCode scans those bytes.
def data.utf8_of(+code: U32) -> +List<U32>:
  Bool.pick(+List<U32>, (code <= 127 : U32), [(code .&. 255 : U32)],
  Bool.pick(+List<U32>, (code <= 2047 : U32), [(((code >> 6n) .&. 31) .|. 192 : U32), ((code .&. 63) .|. 128 : U32)],
  Bool.pick(+List<U32>, (code <= 65535 : U32), [(((code >> 12n) .&. 15) .|. 224 : U32), (((code >> 6n) .&. 63) .|. 128 : U32), ((code .&. 63) .|. 128 : U32)],
  Bool.pick(+List<U32>, (code <= 1114111 : U32), [(((code >> 18n) .&. 7) .|. 240 : U32), (((code >> 12n) .&. 63) .|. 128 : U32), (((code >> 6n) .&. 63) .|. 128 : U32), ((code .&. 63) .|. 128 : U32)],
    []))))

def data.append(left: +List<U32>, right: +List<U32>) -> +List<U32>:
  match left:
    case Nil{}: right
    case Con{byte, rest}: Con{byte, data.append(rest, right)}

def data.utf8_bytes(path: String) -> +List<U32>:
  match path:
    case SNil{}: Nil{}
    case SCon{character, rest}: data.append(data.utf8_of(Char.to_u32(character)), data.utf8_bytes(rest))

def data.utf8_chars(bytes: +List<U32>) -> String:
  match bytes:
    case Nil{}: ""
    case Con{byte, rest}: SCon{Char.from_u32(byte), data.utf8_chars(rest)}

def data.name_wide(path: String) -> Maybe<&2, String>:
  data.wide(data.utf8_chars(data.utf8_bytes(path)), NameGo{}, 0n, "")
