# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of pinned raylib ExportImageAsCode.
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
