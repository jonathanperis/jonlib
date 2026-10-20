# Original work: zlib, Copyright (c) 2026 Jonathan Peris.
# A JSON text (RFC 8259) as a value tree, for the glTF loader. Numbers and
# strings keep their bytes: a number is converted where it is used
# (src/strtod.bend) and a string is compared as written, escapes included,
# which is how cgltf matches keys against jsmn's tokens. Two folds, neither
# recursive on the nesting: the bytes become tokens, and the tokens build
# the tree on an explicit stack of open containers that also holds the
# grammar's place (a comma only after a value, a colon only after a key).
# None for anything else: an unterminated string, a control byte inside
# one, an unknown literal, a misplaced token, a second top-level value.
import Base

type Json is Data:
  JNull{}
  JBool{value: Bool}
  JNumber{text: +List<U32>}
  JString{text: +List<U32>}
  JArray{items: +List<Json>}
  JObject{members: +List<Json.Member>}

type Json.Member is Data:
  JMember{key: +List<U32>, value: Json}

# kind: 0 '{', 1 '[', 2 '}', 3 ']', 4 ':', 5 ',', 6 a string, 7 a primitive.
type Token is Data:
  Token{kind: U32, text: +List<U32>}

# mode: 0 between tokens, 1 in a string, 2 after a backslash in one, 3 in a
# primitive, 9 not JSON. current and tokens are reversed.
type Lex is Data:
  Lex{mode: U32, current: +List<U32>, tokens: +List<Token>}

def reversed(values: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: reversed(rest, Con{v, acc})

def space(+byte: U32) -> Bool:
  U32.is_eq(byte, 32) || U32.is_eq(byte, 9) || U32.is_eq(byte, 10) || U32.is_eq(byte, 13)

# The token kind of a structural byte, or 8.
def structural(+byte: U32) -> U32:
  Bool.pick(U32, U32.is_eq(byte, 123), 0, Bool.pick(U32, U32.is_eq(byte, 91), 1, Bool.pick(U32, U32.is_eq(byte, 125), 2,
    Bool.pick(U32, U32.is_eq(byte, 93), 3, Bool.pick(U32, U32.is_eq(byte, 58), 4, Bool.pick(U32, U32.is_eq(byte, 44), 5, 8))))))

def lex.between(+byte: U32, +tokens: +List<Token>) -> Lex:
  +kind = structural(byte)
  Bool.pick(Lex, space(byte), Lex{0, Nil{}, tokens},
    Bool.pick(Lex, (kind < 8 : U32), Lex{0, Nil{}, Con{Token{kind, Nil{}}, tokens}},
      Bool.pick(Lex, U32.is_eq(byte, 34), Lex{1, Nil{}, tokens}, Lex{Bool.pick(U32, (byte < 32 : U32), 9, 3), [byte], tokens})))

def lex.step(mode: U32, +byte: U32, +current: +List<U32>, +tokens: +List<Token>) -> Lex:
  match mode:
    case 0: lex.between(byte, tokens)
    case 1: Bool.pick(Lex, U32.is_eq(byte, 34), Lex{0, Nil{}, Con{Token{6, reversed(current, Nil{})}, tokens}},
      Bool.pick(Lex, (byte < 32 : U32), Lex{9, Nil{}, tokens}, Lex{Bool.pick(U32, U32.is_eq(byte, 92), 2, 1), Con{byte, current}, tokens}))
    case 2: Lex{1, Con{byte, current}, tokens}
    case 3: Bool.pick(Lex, space(byte) || (structural(byte) < 8 : U32), lex.between(byte, Con{Token{7, reversed(current, Nil{})}, tokens}),
      Bool.pick(Lex, U32.is_eq(byte, 34) || (byte < 32 : U32), Lex{9, Nil{}, tokens}, Lex{3, Con{byte, current}, tokens}))
    case _: Lex{9, Nil{}, tokens}

def lex(bytes: +List<U32>, +state: Lex) -> Lex:
  match bytes:
    case Nil{}: state
    case Con{+byte, rest}:
      Lex{+mode, +current, +tokens} = state
      lex(rest, lex.step(mode, byte, current, tokens))

def tokens.reversed(values: +List<Token>, acc: +List<Token>) -> +List<Token>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: tokens.reversed(rest, Con{v, acc})

# The tokens in order; a text ending inside a string is not JSON.
def lexed(+state: Lex) -> Maybe<+List<Token>>:
  Lex{+mode, +current, +tokens} = state
  Bool.pick(Maybe<+List<Token>>, U32.is_eq(mode, 0), Some{tokens.reversed(tokens, Nil{})},
    Bool.pick(Maybe<+List<Token>>, U32.is_eq(mode, 3), Some{tokens.reversed(Con{Token{7, reversed(current, Nil{})}, tokens}, Nil{})}, None{}))

# An open container: object (0) or array (1); state 0 before its first item,
# 1 after a value, 2 after a comma, 3 after a key, 4 after the colon; items
# and members reversed.
type Open is Data:
  Open{kind: U32, state: U32, items: +List<Json>, members: +List<Json.Member>, key: +List<U32>}

type Build is Data:
  Build{stack: +List<Open>, root: +Maybe<Json>, ok: Bool}

def same(a: +List<U32>, b: +List<U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{+x, xs} Con{+y, ys}: U32.is_eq(x, y) && same(xs, ys)
    case _ _: False{}

def first(text: +List<U32>) -> U32:
  match text:
    case Con{byte, _}: byte
    case Nil{}: 0

# true, false, null, or a number (it starts with a digit or a minus).
def primitive(+text: +List<U32>) -> Maybe<Json>:
  +start = first(text)
  Bool.pick(Maybe<Json>, same(text, [116, 114, 117, 101]), Some{JBool{True{}}},
    Bool.pick(Maybe<Json>, same(text, [102, 97, 108, 115, 101]), Some{JBool{False{}}},
      Bool.pick(Maybe<Json>, same(text, [110, 117, 108, 108]), Some{JNull{}},
        Bool.pick(Maybe<Json>, U32.is_eq(start, 45) || ((start >= 48 : U32) && (start <= 57 : U32)), Some{JNumber{text}}, None{}))))

def items.reversed(values: +List<Json>, acc: +List<Json>) -> +List<Json>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: items.reversed(rest, Con{v, acc})

def members.reversed(values: +List<Json.Member>, acc: +List<Json.Member>) -> +List<Json.Member>:
  match values:
    case Nil{}: acc
    case Con{+v, rest}: members.reversed(rest, Con{v, acc})

def failed() -> Build:
  Build{Nil{}, None{}, False{}}

# A complete value goes to the container on top, where one may come, or is the root.
def placed.in(+top: Open, +rest: +List<Open>, +value: Json, +root: +Maybe<Json>) -> Build:
  Open{+kind, +state, +items, +members, +key} = top
  +array = U32.is_eq(kind, 1) && (U32.is_eq(state, 0) || U32.is_eq(state, 2))
  +object = U32.is_eq(kind, 0) && U32.is_eq(state, 4)
  Bool.pick(Build, array, Build{Con{Open{1, 1, Con{value, items}, members, Nil{}}, rest}, root, True{}},
    Bool.pick(Build, object, Build{Con{Open{0, 1, items, Con{JMember{key, value}, members}, Nil{}}, rest}, root, True{}}, failed()))

def placed.root(root: +Maybe<Json>, +value: Json) -> Build:
  match root:
    case None{}: Build{Nil{}, Some{value}, True{}}
    case Some{_}: failed()

def placed(stack: +List<Open>, +value: Json, +root: +Maybe<Json>) -> Build:
  match stack:
    case Nil{}: placed.root(root, value)
    case Con{+top, +rest}: placed.in(top, rest, value, root)

def placed.maybe(value: Maybe<Json>, +stack: +List<Open>, +root: +Maybe<Json>) -> Build:
  match value:
    case None{}: failed()
    case Some{+v}: placed(stack, v, root)

# A string where an object expects a key is the key; elsewhere it is a value.
def string(stack: +List<Open>, +text: +List<U32>, +root: +Maybe<Json>) -> Build:
  match stack:
    case Nil{}: placed.root(root, JString{text})
    case Con{+top, +rest}:
      Open{+kind, +state, +items, +members, _} = top
      Bool.pick(Build, U32.is_eq(kind, 0) && (U32.is_eq(state, 0) || U32.is_eq(state, 2)), Build{Con{Open{0, 3, items, members, text}, rest}, root, True{}},
        placed.in(top, rest, JString{text}, root))

# ':' after a key, ',' after a value.
def moved(stack: +List<Open>, +from: U32, +to: U32, +object: Bool, +root: +Maybe<Json>) -> Build:
  match stack:
    case Nil{}: failed()
    case Con{+top, +rest}:
      Open{+kind, +state, +items, +members, +key} = top
      Bool.pick(Build, U32.is_eq(state, from) && (Bool.not(object) || U32.is_eq(kind, 0)), Build{Con{Open{kind, to, items, members, key}, rest}, root, True{}}, failed())

# A closing bracket of the open container's kind, before any item or after a value.
def closed(stack: +List<Open>, +kind: U32, +root: +Maybe<Json>) -> Build:
  match stack:
    case Nil{}: failed()
    case Con{+top, +rest}:
      Open{+open, +state, +items, +members, _} = top
      Bool.pick(Build, U32.is_eq(open, kind) && (U32.is_eq(state, 0) || U32.is_eq(state, 1)),
        placed(rest, Bool.pick(Json, U32.is_eq(kind, 1), JArray{items.reversed(items, Nil{})}, JObject{members.reversed(members, Nil{})}), root), failed())

def build.step(kind: U32, +text: +List<U32>, +stack: +List<Open>, +root: +Maybe<Json>) -> Build:
  match kind:
    case 0: Build{Con{Open{0, 0, Nil{}, Nil{}, Nil{}}, stack}, root, True{}}
    case 1: Build{Con{Open{1, 0, Nil{}, Nil{}, Nil{}}, stack}, root, True{}}
    case 2: closed(stack, 0, root)
    case 3: closed(stack, 1, root)
    case 4: moved(stack, 3, 4, True{}, root)
    case 5: moved(stack, 1, 2, False{}, root)
    case 6: string(stack, text, root)
    case _: placed.maybe(primitive(text), stack, root)

# An opening bracket is itself a value's start: it may only come where a value may.
def opens(stack: +List<Open>, +root: +Maybe<Json>) -> Bool:
  match stack:
    case Nil{}: True{}
    case Con{Open{+kind, +state, _, _, _}, _}: (U32.is_eq(kind, 1) && (U32.is_eq(state, 0) || U32.is_eq(state, 2))) || (U32.is_eq(kind, 0) && U32.is_eq(state, 4))

def build(tokens: +List<Token>, +state: Build) -> Build:
  match tokens:
    case Nil{}: state
    case Con{Token{+kind, +text}, rest}:
      Build{+stack, +root, +ok} = state
      build(rest, Bool.pick(Build, ok && ((kind > 1 : U32) || opens(stack, root)), build.step(kind, text, stack, root), failed()))

def built(+state: Build) -> +Maybe<Json>:
  Build{+stack, +root, +ok} = state
  match stack:
    case Nil{}: Bool.pick(+Maybe<Json>, ok, root, None{})
    case Con{_, _}: None{}

def parse.tokens(tokens: Maybe<+List<Token>>) -> +Maybe<Json>:
  match tokens:
    case None{}: None{}
    case Some{+t}: built(build(t, Build{Nil{}, None{}, True{}}))

# The value of a JSON text.
def parse(bytes: +List<U32>) -> +Maybe<Json>:
  parse.tokens(lexed(lex(bytes, Lex{0, Nil{}, Nil{}})))

# The value of a key in an object's members (the first of that name).
def member(members: +List<Json.Member>, +key: +List<U32>) -> Maybe<Json>:
  match members:
    case Nil{}: None{}
    case Con{JMember{+name, +value}, rest}: Bool.pick(Maybe<Json>, same(name, key), Some{value}, member(rest, key))

def get(value: Json, +key: +List<U32>) -> Maybe<Json>:
  match value:
    case JObject{+members}: member(members, key)
    case _: None{}
