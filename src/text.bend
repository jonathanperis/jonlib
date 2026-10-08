# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rtext.c; LICENSES/raylib.txt.
# The text strings management and UTF-8 codepoint functions over byte lists.
# A C string is the list of its bytes before the first NUL; C ints are U32
# two's-complement words. Each function reproduces raylib's loops, static
# buffer limits (MAX_TEXT_BUFFER_LENGTH 1024, MAX_TEXTSPLIT_COUNT 128) and
# quirks; inputs for which the C code reads or writes outside its strings or
# buffers, or overflows an int, are None.
import Base
import ./decimal.bend as Decimal

# -----------------------------------------------------------------------------
# Bytes

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

def head(bytes: +List<U32>) -> U32:
  match bytes:
    case Nil{}: 0
    case Con{b, _}: b

def at(+bytes: +List<U32>, +index: Nat) -> U32:
  head(List.drop(&2, U32, bytes, index))

def len(bytes: +List<U32>) -> U32:
  match bytes:
    case Nil{}: 0
    case Con{_, rest}: (1 + len(rest) : U32)

def take(+bytes: +List<U32>, +n: U32) -> +List<U32>:
  List.take(&2, U32, bytes, U32.to_nat(n))

def drop(+bytes: +List<U32>, +n: U32) -> +List<U32>:
  List.drop(&2, U32, bytes, U32.to_nat(n))

def glue(+a: +List<U32>, +b: +List<U32>) -> +List<U32>:
  List.append(&2, U32, a, b)

def cut(+b: U32, rest: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(b, 0), Nil{}, Con{b, rest})

# The bytes of a C string: the character codes before the first NUL.
def bytes(text: String) -> +List<U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{c, rest}: cut(Char.to_u32(c), bytes(rest))

# Every character code of a buffer, NULs included.
def codes(text: String) -> +List<U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{c, rest}: Con{Char.to_u32(c), codes(rest)}

# A byte list up to its first 0, as raylib's char pointer reads it.
def until(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: cut(b, until(rest))

def string(bytes: +List<U32>) -> String:
  match bytes:
    case Nil{}: SNil{}
    case Con{b, rest}: SCon{Char.from_u32(b), string(rest)}

def cstring(+bytes: +List<U32>) -> String:
  string(until(bytes))

def same(a: +List<U32>, b: +List<U32>, equal: Bool) -> Bool:
  match a b equal:
    case _ _ False{}: False{}
    case Nil{} Nil{} True{}: True{}
    case Con{+x, ra} Con{+y, rb} True{}: same(ra, rb, U32.is_eq(x, y))
    case _ _ True{}: False{}

# strcmp(a, b) == 0.
def equal(+a: +List<U32>, +b: +List<U32>) -> Bool:
  same(a, b, True{})

# Whether search starts text.
def prefix(text: +List<U32>, search: +List<U32>, ok: Bool) -> Bool:
  match text search ok:
    case _ _ False{}: False{}
    case _ Nil{} True{}: True{}
    case Nil{} Con{_, _} True{}: False{}
    case Con{+t, rt} Con{+s, rs} True{}: prefix(rt, rs, U32.is_eq(t, s))

def find.go(text: +List<U32>, found: Bool, +search: +List<U32>, +index: U32) -> Maybe<U32>:
  match text found:
    case _ True{}: Some{index}
    case Nil{} False{}: None{}
    case Con{_, +rest} False{}: find.go(rest, prefix(rest, search, True{}), search, (index + 1 : U32))

# strstr: the index of search's first occurrence (an empty search is at 0).
def find(+text: +List<U32>, +search: +List<U32>) -> Maybe<U32>:
  find.go(text, prefix(text, search, True{}), search, 0)

def ascii.upper(+c: U32) -> U32:
  Bool.pick(U32, ((c >= 97) && (c <= 122) : U32), (c - 32 : U32), c)

def ascii.lower(+c: U32) -> U32:
  Bool.pick(U32, ((c >= 65) && (c <= 90) : U32), (c + 32 : U32), c)

def map.upper(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{c, rest}: Con{ascii.upper(c), map.upper(rest)}

def map.lower(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{c, rest}: Con{ascii.lower(c), map.lower(rest)}

def digit(+c: U32) -> Bool:
  ((c >= 48) && (c <= 57) : U32)

# -----------------------------------------------------------------------------
# Lines and splitting

def lines.current(newline: Bool, +b: U32, current: +List<U32>) -> +List<U32>:
  match newline:
    case True{}: Nil{}
    case False{}: Con{b, current}

def lines.done(newline: Bool, current: +List<U32>, done: +List<String>) -> +List<String>:
  match newline:
    case True{}: Con{string(List.reverse(&2, U32, current)), done}
    case False{}: done

def lines.go(bytes: +List<U32>, +current: +List<U32>, +done: +List<String>) -> +List<String>:
  match bytes:
    case Nil{}: List.reverse(&2, String, Con{string(List.reverse(&2, U32, current)), done})
    case Con{+b, rest}: lines.go(rest, lines.current(U32.is_eq(b, 10), b, current), lines.done(U32.is_eq(b, 10), current, done))

# LoadTextLines: the text cut at every '\n' (one more line than newlines).
def lines(+text: +List<U32>) -> +List<String>:
  lines.go(text, Nil{}, Nil{})

# TextSplit's loop: i is the byte index, counter the substrings started so far.
# status 0: scanning; 1: stopped at MAX_TEXTSPLIT_COUNT; 2: undefined.
type Split is Data:
  Split{i: U32, counter: U32, current: +List<U32>, done: +List<String>, status: U32}

def split.kind(+state: Split, +b: U32, +delimiter: U32) -> U32:
  Split{+i, +counter, _, _, +status} = state
  Bool.pick(U32, U32.is_ne(status, 0), 0,
    Bool.pick(U32, (i >= 1024 : U32), 1,
      Bool.pick(U32, U32.is_ne(b, delimiter), 2,
        Bool.pick(U32, ((counter + 1) < 128 : U32), 3, Bool.pick(U32, ((i + 1) < 1024 : U32), 4, 1)))))

def split.step(kind: U32, +b: U32, state: Split) -> Split:
  match kind state:
    case 1 Split{i, counter, current, done, _}: Split{i, counter, current, done, 2}
    case 2 Split{i, counter, current, done, status}: Split{(i + 1 : U32), counter, Con{b, current}, done, status}
    case 3 Split{i, counter, current, done, status}: Split{(i + 1 : U32), (counter + 1 : U32), Nil{}, Con{string(List.reverse(&2, U32, current)), done}, status}
    case 4 Split{i, _, current, done, _}: Split{(i + 1 : U32), 128, Nil{}, Con{"", Con{string(List.reverse(&2, U32, current)), done}}, 1}
    case _ other: other

def split.status(status: U32, +i: U32, current: +List<U32>, done: +List<String>) -> Maybe<+List<String>>:
  match status:
    case 0: Bool.pick(Maybe<+List<String>>, (i >= 1024 : U32), None{}, Some{List.reverse(&2, String, Con{string(List.reverse(&2, U32, current)), done})})
    case 1: Some{List.reverse(&2, String, done)}
    case _: None{}

def split.end(state: Split) -> Maybe<+List<String>>:
  match state:
    case Split{i, _, current, done, status}: split.status(status, i, current, done)

def split.go(bytes: +List<U32>, +delimiter: U32, +state: Split) -> Maybe<+List<String>>:
  match bytes:
    case Nil{}: split.end(state)
    case Con{+b, rest}: split.go(rest, delimiter, split.step(split.kind(state, b, delimiter), b, state))

# TextSplit: the text copied into a 1024-byte buffer with every delimiter
# replaced by a NUL. At the 127th delimiter the loop stops and the 128th
# substring is the empty rest of the buffer. A text that fills the buffer
# without a NUL leaves its last substring unterminated: None.
def split(+text: +List<U32>, +delimiter: U32) -> Maybe<+List<String>>:
  split.go(text, delimiter, Split{0, 1, Nil{}, Nil{}, 0})

# -----------------------------------------------------------------------------
# Static-buffer string functions

def nonempty(list: +List<String>) -> Bool:
  match list:
    case Nil{}: False{}
    case Con{_, _}: True{}

def revappend(bytes: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: acc
    case Con{b, rest}: revappend(rest, Con{b, acc})

def join.text(fits: Bool, +item: +List<U32>, out: +List<U32>) -> +List<U32>:
  match fits:
    case True{}: revappend(item, out)
    case False{}: out

# TextJoin: each text that fits (total + length < 1024) is copied, followed by
# the delimiter unless it is the last item; raylib does not check the
# delimiter, so one ending past index 1022 overflows or leaves the buffer
# unterminated: None.
def join.go(items: +List<String>, +delimiter: +List<U32>, +total: U32, +out: +List<U32>, +ok: Bool) -> Maybe<String>:
  match items:
    case Nil{}: Bool.pick(Maybe<String>, ok, Some{string(List.reverse(&2, U32, out))}, None{})
    case Con{item, +rest}:
      +text = bytes(item)
      +length = len(text)
      +fits = ((total + length) < 1024 : U32)
      +separated = fits && (len(delimiter) > 0 : U32) && nonempty(rest)
      +copied = Bool.pick(U32, fits, (total + length : U32), total)
      +after = Bool.pick(U32, separated, (copied + len(delimiter) : U32), copied)
      join.go(rest, delimiter, after, join.text(separated, delimiter, join.text(fits, text, out)), ok && Bool.not(separated && (after > 1023 : U32)))

def join(+items: +List<String>, +delimiter: +List<U32>) -> Maybe<String>:
  join.go(items, delimiter, 0, Nil{}, True{})

def spaces(bytes: +List<U32>) -> U32:
  match bytes:
    case Nil{}: 0
    case Con{b, rest}: (Bool.to_u32(U32.is_eq(b, 32)) + spaces(rest) : U32)

def unspaced.keep(+b: U32, +rest: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(b, 32), rest, Con{b, rest})

def unspaced(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: unspaced.keep(b, unspaced(rest))

# TextRemoveSpaces. Its loop tests text[j] (the output index) but copies
# text[i], so after the NUL it keeps reading while j has not reached it: two or
# more spaces in a text of up to 1021 bytes read past the string (None).
def remove_spaces(+text: +List<U32>) -> Maybe<String>:
  +length = len(text)
  Bool.pick(Maybe<String>, (length >= 1023 : U32), Some{string(unspaced(take(text, 1023)))},
    Bool.pick(Maybe<String>, (spaces(text) >= 2 : U32) && (length <= 1021 : U32), None{}, Some{string(unspaced(text))}))

# TextSubtext: bytes position..position+length-1 clamped to the text and 1023
# bytes. A negative length writes before the buffer and a negative position
# reads before the text (None), except for an empty request whose
# textLength - position does not overflow.
def subtext.kind(+total: U32, +position: U32, +length: U32) -> U32:
  Bool.pick(U32, Bool.not(negative(position) || (position < total : U32)), 0,
    Bool.pick(U32, negative(length), 1,
      Bool.pick(U32, negative(position), Bool.pick(U32, U32.is_eq(length, 0) && ((total + (0 - position)) <= 2147483647 : U32), 0, 1), 2)))

def subtext.run(kind: U32, +text: +List<U32>, +total: U32, +position: U32, +length: U32) -> Maybe<String>:
  match kind:
    case 0: Some{""}
    case 2:
      +count = Bool.pick(U32, (length > (total - position) : U32), (total - position : U32), length)
      Some{string(take(drop(text, position), Bool.pick(U32, (count > 1023 : U32), 1023, count)))}
    case _: None{}

def subtext(+text: +List<U32>, +position: U32, +length: U32) -> Maybe<String>:
  +total = len(text)
  subtext.run(subtext.kind(total, position, length), text, total, position, length)

# The text around a begin/end pair: through the first begin, the bytes before
# the first end after it, and the rest from that end.
type Span is Data:
  Span{head: +List<U32>, middle: +List<U32>, tail: +List<U32>}

def span.end(found: Maybe<U32>, +head: +List<U32>, +after: +List<U32>) -> Maybe<Span>:
  match found:
    case None{}: None{}
    case Some{+index}: Some{Span{head, take(after, index), drop(after, index)}}

def span.begin(found: Maybe<U32>, +text: +List<U32>, +begin: U32, +end: +List<U32>) -> Maybe<Span>:
  match found:
    case None{}: None{}
    case Some{+index}: span.end(find(drop(text, (index + begin : U32)), end), take(text, (index + begin : U32)), drop(text, (index + begin : U32)))

def span(+text: +List<U32>, +begin: +List<U32>, +end: +List<U32>) -> Maybe<Span>:
  span.begin(find(text, begin), text, len(begin), end)

# GetTextBetween: the bytes between begin and the following end, at most 1023.
def between(found: Maybe<Span>) -> String:
  match found:
    case None{}: ""
    case Some{Span{_, middle, _}}: string(take(middle, 1023))

# TextReplaceBetween(Alloc): the text through begin, the replacement, then the
# text from end. The static form is None when that needs 1024 or more bytes.
def replace_between(found: Maybe<Span>, +replacement: +List<U32>, +limited: Bool) -> Maybe<String>:
  match found:
    case None{}: Bool.pick(Maybe<String>, limited, Some{""}, None{})
    case Some{Span{head, _, tail}}:
      +result = glue(head, glue(replacement, tail))
      Bool.pick(Maybe<String>, limited && (len(result) > 1023 : U32), None{}, Some{string(result)})

# TextReplace's non-overlapping left-to-right occurrences and the replaced text.
type Replaced is Data:
  Replaced{count: U32, out: +List<U32>}

def replace.next(hit: Bool, +text: +List<U32>, +skip: Nat, rest: +List<U32>) -> +List<U32>:
  match hit:
    case True{}: List.drop(&2, U32, text, skip)
    case False{}: rest

def replace.out(hit: Bool, +reversed: +List<U32>, +b: U32, out: +List<U32>) -> +List<U32>:
  match hit:
    case True{}: List.append(&2, U32, reversed, out)
    case False{}: Con{b, out}

def replace.go(n: Nat, text: +List<U32>, +search: +List<U32>, +reversed: +List<U32>, +skip: Nat, +count: U32, out: +List<U32>) -> Replaced:
  match n text:
    case 0n _: Replaced{count, List.reverse(&2, U32, out)}
    case _ Nil{}: Replaced{count, List.reverse(&2, U32, out)}
    case 1n+k Con{+b, +rest}:
      +hit = prefix(Con{b, rest}, search, True{})
      replace.go(k, replace.next(hit, Con{b, rest}, skip, rest), search, reversed, skip, Bool.pick(U32, hit, (count + 1 : U32), count),
        replace.out(hit, reversed, b, out))

def replaced(+text: +List<U32>, +search: +List<U32>, +replacement: +List<U32>) -> Replaced:
  replace.go(1n+List.length(&2, U32, text), text, search, List.reverse(&2, U32, replacement), List.length(&2, U32, search), 0, Nil{})

# textLen + count*(replaceLen - searchLen) (+ extra) as C ints: whether it
# overflows.
def replace.overflows(+text: U32, +count: U32, +search: U32, +replacement: U32, +extra: U32) -> Bool:
  (replacement > search : U32) && U32.is_ne(count, 0) && ((replacement - search) > ((2147483647 - extra - text) / Bool.pick(U32, U32.is_eq(count, 0), 1, count)) : U32)

def replace.counted(result: Replaced, +text: U32, +search: U32, +replacement: U32, +limited: Bool) -> Maybe<String>:
  match result:
    case Replaced{+count, out}:
      +total = (text + count * (replacement - search) : U32)
      Bool.pick(Maybe<String>, replace.overflows(text, count, search, replacement, Bool.to_u32(Bool.not(limited))), None{},
        Bool.pick(Maybe<String>, limited && (total >= 1023 : U32), Some{""}, Some{string(out)}))

# TextReplace (limited: a result of at most 1022 bytes, else "") and
# TextReplaceAlloc. An empty search returns "" (TextReplace) or NULL (None).
def replace(+text: +List<U32>, +search: +List<U32>, +replacement: +List<U32>, +limited: Bool) -> Maybe<String>:
  Bool.pick(Maybe<String>, U32.is_eq(len(search), 0), Bool.pick(Maybe<String>, limited, Some{""}, None{}),
    replace.counted(replaced(text, search, replacement), len(text), len(search), len(replacement), limited))

# TextInsert(Alloc). raylib copies the text after the insertion from text[i]
# instead of text[i - insertLen], so only these are defined: position == length
# (append), position == length + 1 (the text, its NUL copied first), and
# positions inside the text for inserts of at most one byte (the byte replaces
# the text's byte). Other positions read past the text or write before the
# buffer: None. The static form returns "" for 1023 or more bytes.
def insert.kind(+length: U32, +size: U32, +position: U32, +limited: Bool) -> U32:
  Bool.pick(U32, limited && ((length + size) >= 1023 : U32), 0,
    Bool.pick(U32, negative(position) || (position >= (length + 2) : U32) || ((size >= 2) && (position < length) : U32), 1,
      Bool.pick(U32, U32.is_eq(position, length), 2, Bool.pick(U32, U32.is_eq(position, (length + 1 : U32)) || U32.is_eq(size, 0), 3, 4))))

def insert.run(kind: U32, +text: +List<U32>, +insert: +List<U32>, +position: U32) -> Maybe<String>:
  match kind:
    case 0: Some{""}
    case 2: Some{string(glue(text, insert))}
    case 3: Some{string(text)}
    case 4: Some{string(glue(take(text, position), glue(insert, drop(text, (position + 1 : U32)))))}
    case _: None{}

def insert(+text: +List<U32>, +insert: +List<U32>, +position: U32, +limited: Bool) -> Maybe<String>:
  insert.run(insert.kind(len(text), len(insert), position, limited), text, insert, position)

# TextCopy/TextAppend into a buffer of fixed size: text and its NUL written at
# position. A write outside the buffer is None.
def write.run(ok: Bool, +buffer: +List<U32>, +text: +List<U32>, +position: U32, +end: U32) -> Maybe<String>:
  match ok:
    case False{}: None{}
    case True{}: Some{string(glue(take(buffer, position), glue(text, Con{0, drop(buffer, end)})))}

def write(+buffer: +List<U32>, +text: +List<U32>, +position: U32) -> Maybe<String>:
  +end = (position + len(text) + 1 : U32)
  write.run(Bool.not(negative(position) || (end > len(buffer) : U32)), buffer, text, position, end)

# -----------------------------------------------------------------------------
# Case conversion

# TextToPascal/TextToCamel after the first byte: i is the output index; a '_'
# takes the next byte (Pascal: a-z upper-cased or 0-9 kept, Camel: a-z
# upper-cased) and any other byte leaves a NUL. status 0: scanning; 1: stopped
# at index 1023.
type Cased is Data:
  Cased{i: U32, out: +List<U32>, pending: Bool, status: U32}

def cased.after(+pascal: Bool, +c: U32) -> U32:
  Bool.pick(U32, ((c >= 97) && (c <= 122) : U32), (c - 32 : U32), Bool.pick(U32, pascal && digit(c), c, 0))

def cased.kind(+state: Cased, +c: U32) -> U32:
  Cased{+i, _, +pending, +status} = state
  Bool.pick(U32, U32.is_ne(status, 0), 0, Bool.pick(U32, pending, 1, Bool.pick(U32, (i >= 1023 : U32), 2, Bool.pick(U32, U32.is_eq(c, 95), 3, 4))))

def cased.step(kind: U32, +pascal: Bool, +c: U32, state: Cased) -> Cased:
  match kind state:
    case 1 Cased{i, out, _, status}: Cased{(i + 1 : U32), Con{cased.after(pascal, c), out}, False{}, status}
    case 2 Cased{i, out, pending, _}: Cased{i, out, pending, 1}
    case 3 Cased{i, out, _, status}: Cased{i, out, True{}, status}
    case 4 Cased{i, out, pending, status}: Cased{(i + 1 : U32), Con{c, out}, pending, status}
    case _ other: other

def cased.go(bytes: +List<U32>, +pascal: Bool, +state: Cased) -> Cased:
  match bytes:
    case Nil{}: state
    case Con{+c, rest}: cased.go(rest, pascal, cased.step(cased.kind(state, c), pascal, c, state))

# A '_' before the NUL takes the NUL and the next test reads past the string,
# unless index 1023 stops the loop first.
def cased.end(state: Cased, +first: U32) -> Maybe<String>:
  match state:
    case Cased{i, out, pending, _}:
      Bool.pick(Maybe<String>, pending && ((i + 1) < 1023 : U32), None{}, Some{cstring(Con{first, List.reverse(&2, U32, out)})})

def cased(text: +List<U32>, +pascal: Bool) -> Maybe<String>:
  match text:
    case Nil{}: None{}
    case Con{+first, rest}:
      cased.end(cased.go(rest, pascal, Cased{1, Nil{}, False{}, 0}), Bool.pick(U32, pascal, ascii.upper(first), ascii.lower(first)))

# TextToSnake: i is the output index; status 0: scanning; 1: stopped at index
# 1023; 2: an upper-case letter at index 1022 fills the buffer without a NUL.
type Snake is Data:
  Snake{i: U32, out: +List<U32>, status: U32}

def snake.kind(+state: Snake, +c: U32) -> U32:
  Snake{+i, _, +status} = state
  Bool.pick(U32, U32.is_ne(status, 0), 0, Bool.pick(U32, (i >= 1023 : U32), 1,
    Bool.pick(U32, ((c >= 65) && (c <= 90) : U32), Bool.pick(U32, U32.is_eq(i, 0), 2, Bool.pick(U32, U32.is_eq(i, 1022), 3, 4)), 5)))

def snake.step(kind: U32, +c: U32, state: Snake) -> Snake:
  match kind state:
    case 1 Snake{i, out, _}: Snake{i, out, 1}
    case 2 Snake{i, out, status}: Snake{(i + 1 : U32), Con{(c + 32 : U32), out}, status}
    case 3 Snake{i, out, _}: Snake{i, out, 2}
    case 4 Snake{i, out, status}: Snake{(i + 2 : U32), Con{(c + 32 : U32), Con{95, out}}, status}
    case 5 Snake{i, out, status}: Snake{(i + 1 : U32), Con{c, out}, status}
    case _ other: other

def snake.go(bytes: +List<U32>, +state: Snake) -> Snake:
  match bytes:
    case Nil{}: state
    case Con{+c, rest}: snake.go(rest, snake.step(snake.kind(state, c), c, state))

def snake.end(state: Snake) -> Maybe<String>:
  match state:
    case Snake{_, out, status}: Bool.pick(Maybe<String>, U32.is_eq(status, 2), None{}, Some{string(List.reverse(&2, U32, out))})

def snake(+text: +List<U32>) -> Maybe<String>:
  snake.end(snake.go(text, Snake{0, Nil{}, 0}))

# -----------------------------------------------------------------------------
# Numbers

# TextToInteger's digits; overflow marks the signed int overflow (None).
type Integer is Data:
  Integer{value: U32, active: Bool, overflow: Bool}

def integer.go(bytes: +List<U32>, +state: Integer) -> Integer:
  match bytes state:
    case Nil{} other: other
    case Con{+c, rest} Integer{+value, +active, +overflow}:
      +d = (c - 48 : U32)
      +more = active && digit(c)
      integer.go(rest, Integer{Bool.pick(U32, more, (value * 10 + d : U32), value), more,
        overflow || (more && ((value > 214748364 : U32) || (U32.is_eq(value, 214748364) && (d > 7 : U32))))})

def integer.end(result: Integer, +minus: Bool) -> Maybe<U32>:
  match result:
    case Integer{+value, _, overflow}: Bool.pick(Maybe<U32>, overflow, None{}, Some{Bool.pick(U32, minus, (0 - value : U32), value)})

# TextToInteger: an optional sign and the leading decimal digits.
def integer(+text: +List<U32>) -> Maybe<U32>:
  +first = head(text)
  +signed = U32.is_eq(first, 43) || U32.is_eq(first, 45)
  integer.end(integer.go(Bool.pick(+List<U32>, signed, List.drop(&2, U32, text, 1n), text), Integer{0, True{}, False{}}), U32.is_eq(first, 45))

def f32(+w: U32) -> F32:
  U32{b} = w
  F32{b}

# fma(value, 10, digit) for TextToFloat's integer part: value is 0, an
# integral F32 or infinity, so value*10 + digit is an integer y * 2^k with y
# below 2^32 (the low digit bits of large values only decide rounding, as a
# sticky bit), rounded once.
def multiply_add.fused(+value: F32, +d: U32) -> F32:
  +bits = F32.bits(value)
  +exponent = ((bits >> 23n) .&. 255 : U32)
  +large = (exponent >= 151 : U32)
  +scale = Bool.pick(U32, large, (exponent - 150 : U32), 0)
  +shift = Bool.pick(U32, (scale >= 4 : U32), 4, scale)
  +mantissa = (((bits .&. 8388607) .|. 8388608) * 10 : U32)
  +y = Bool.pick(U32, (scale >= 4 : U32), ((mantissa << 4n) .|. Bool.to_u32(U32.is_ne(d, 0)) : U32), ((mantissa << U32.to_nat(shift)) + d : U32))
  +small = U32.to_f32((F32.to_u32(Bool.pick(F32, large, 0.0, value)) * 10 + d : U32))
  Bool.pick(F32, U32.is_eq(exponent, 255), value,
    Bool.pick(F32, large, (U32.to_f32(y) * f32(((127 + scale - shift) << 23n : U32)) : F32), small))

def multiply_add(+fused: Bool, +value: F32, +d: U32) -> F32:
  Bool.pick(F32, fused, multiply_add.fused(value, d), (value * 10.0 + U32.to_f32(d) : F32))

# TextToFloat's scan. phase 0: integer digits; 1: fraction digits; 2: done.
type Float is Data:
  Float{value: F32, divisor: F32, phase: U32}

def float.go(bytes: +List<U32>, +fused: Bool, +state: Float) -> Float:
  match bytes state:
    case Nil{} other: other
    case Con{+c, rest} Float{+value, +divisor, +phase}:
      +d = (c - 48 : U32)
      +integral = U32.is_eq(phase, 0) && digit(c)
      +fraction = U32.is_eq(phase, 1) && digit(c)
      float.go(rest, fused, Float{
        Bool.pick(F32, integral, multiply_add(fused, value, d), Bool.pick(F32, fraction, (value + (U32.to_f32(d) / divisor) : F32), value)),
        Bool.pick(F32, fraction, (divisor * 10.0 : F32), divisor),
        Bool.pick(U32, integral || fraction, phase, Bool.pick(U32, U32.is_eq(phase, 0) && U32.is_eq(c, 46), 1, 2))})

def float.end(result: Float, +sign: F32) -> F32:
  match result:
    case Float{value, _, _}: (value * sign : F32)

# TextToFloat: an optional sign, digits accumulated as value*10 + digit (one
# fused multiply-add when the reference contracts it), then after a '.' each
# digit/divisor added with the divisor multiplied by 10, all in F32.
def float(+fused: Bool, +text: +List<U32>) -> F32:
  +first = head(text)
  +signed = U32.is_eq(first, 43) || U32.is_eq(first, 45)
  float.end(float.go(Bool.pick(+List<U32>, signed, List.drop(&2, U32, text, 1n), text), fused, Float{0.0, 10.0, 0}),
    Bool.pick(F32, U32.is_eq(first, 45), F32.neg(1.0), 1.0))

# -----------------------------------------------------------------------------
# UTF-8 codepoints

# A decoded codepoint and its byte size.
type Code is Data:
  Code{value: U32, size: U32}

def within(+x: U32, +low: U32, +high: U32) -> Bool:
  ((x >= low) && (x <= high) : U32)

def continuation(+b: U32) -> Bool:
  U32.is_eq((b .&. 192 : U32), 128)

# GetCodepointNext: the codepoint and its byte size, '?' (size 1) for an
# invalid sequence; it does not reject overlong or out-of-range sequences.
def next(+text: +List<U32>) -> Code:
  +p0 = at(text, 0n)
  +p1 = at(text, 1n)
  +p2 = at(text, 2n)
  +p3 = at(text, 3n)
  +c4 = (((p0 .&. 7) << 18n) .|. ((p1 .&. 63) << 12n) .|. ((p2 .&. 63) << 6n) .|. (p3 .&. 63) : U32)
  +c3 = (((p0 .&. 15) << 12n) .|. ((p1 .&. 63) << 6n) .|. (p2 .&. 63) : U32)
  +c2 = (((p0 .&. 31) << 6n) .|. (p1 .&. 63) : U32)
  Bool.pick(Code, U32.is_eq((p0 .&. 248 : U32), 240),
    Bool.pick(Code, continuation(p1) && continuation(p2) && continuation(p3), Code{c4, 4}, Code{63, 1}),
  Bool.pick(Code, U32.is_eq((p0 .&. 240 : U32), 224),
    Bool.pick(Code, continuation(p1) && continuation(p2), Code{c3, 3}, Code{63, 1}),
  Bool.pick(Code, U32.is_eq((p0 .&. 224 : U32), 192),
    Bool.pick(Code, continuation(p1), Code{c2, 2}, Code{63, 1}),
  Bool.pick(Code, (p0 < 128 : U32), Code{p0, 1}, Code{63, 1}))))

def get.three(+o: U32, +o1: U32, +o2: U32) -> Code:
  Bool.pick(Code, U32.is_eq(o1, 0) || Bool.not(continuation(o1)), Code{63, 2},
    Bool.pick(Code, U32.is_eq(o2, 0) || Bool.not(continuation(o2)), Code{63, 3},
      Bool.pick(Code, (U32.is_eq(o, 224) && Bool.not(within(o1, 160, 191))) || (U32.is_eq(o, 237) && Bool.not(within(o1, 128, 159))), Code{63, 2},
        Code{(((o .&. 15) << 12n) .|. ((o1 .&. 63) << 6n) .|. (o2 .&. 63) : U32), 3})))

def get.four(+o: U32, +o1: U32, +o2: U32, +o3: U32) -> Code:
  +value = (((o .&. 7) << 18n) .|. ((o1 .&. 63) << 12n) .|. ((o2 .&. 63) << 6n) .|. (o3 .&. 63) : U32)
  Bool.pick(Code, (o > 244 : U32), Code{63, 1},
    Bool.pick(Code, U32.is_eq(o1, 0) || Bool.not(continuation(o1)), Code{63, 2},
      Bool.pick(Code, U32.is_eq(o2, 0) || Bool.not(continuation(o2)), Code{63, 3},
        Bool.pick(Code, U32.is_eq(o3, 0) || Bool.not(continuation(o3)), Code{63, 4},
          Bool.pick(Code, (U32.is_eq(o, 240) && Bool.not(within(o1, 144, 191))) || (U32.is_eq(o, 244) && Bool.not(within(o1, 128, 143))), Code{63, 2},
            Code{Bool.pick(U32, (value > 1114111 : U32), 63, value), 4})))))

# GetCodepoint: RFC 3629 validation; on an error the size counts the bytes
# examined, as raylib returns it.
def get(+text: +List<U32>) -> Code:
  +o = at(text, 0n)
  +o1 = at(text, 1n)
  Bool.pick(Code, (o <= 127 : U32), Code{o, 1},
    Bool.pick(Code, U32.is_eq((o .&. 224 : U32), 192),
      Bool.pick(Code, U32.is_eq(o1, 0) || Bool.not(continuation(o1)), Code{63, 2},
        Bool.pick(Code, (o >= 194 : U32), Code{(((o .&. 31) << 6n) .|. (o1 .&. 63) : U32), 2}, Code{63, 1})),
    Bool.pick(Code, U32.is_eq((o .&. 240 : U32), 224), get.three(o, o1, at(text, 2n)),
      Bool.pick(Code, U32.is_eq((o .&. 248 : U32), 240), get.four(o, o1, at(text, 2n), at(text, 3n)), Code{63, 1}))))

def pair.size(+pair: Code) -> U32:
  Code{_, size} = pair
  size

def pair.value(+pair: Code) -> U32:
  Code{value, _} = pair
  value

def counted(n: Nat, text: +List<U32>, +count: U32) -> U32:
  match n text:
    case 0n _: count
    case _ Nil{}: count
    case 1n+k Con{+b, +rest}: counted(k, drop(Con{b, rest}, pair.size(next(Con{b, rest}))), (count + 1 : U32))

# GetCodepointCount: GetCodepointNext steps up to the NUL.
def count(+text: +List<U32>) -> U32:
  counted(1n+List.length(&2, U32, text), text, 0)

def decoded(n: Nat, text: +List<U32>) -> +List<U32>:
  match n text:
    case 0n _: Nil{}
    case _ Nil{}: Nil{}
    case 1n+k Con{+b, +rest}:
      +pair = next(Con{b, rest})
      Con{pair.value(pair), decoded(k, drop(Con{b, rest}, pair.size(pair)))}

# LoadCodepoints: each GetCodepointNext codepoint up to the NUL.
def codepoints(+text: +List<U32>) -> +List<U32>:
  decoded(1n+List.length(&2, U32, text), text)

def leading(bytes: +List<U32>) -> U32:
  match bytes:
    case Nil{}: 0
    case Con{+b, rest}: Bool.pick(U32, continuation(b), (1 + leading(rest) : U32), 0)

def previous.found(outside: Bool, +text: +List<U32>, +index: U32) -> Maybe<Code>:
  match outside:
    case True{}: None{}
    case False{}:
      +pair = next(drop(text, index))
      Some{Code{pair.value(pair), Bool.pick(U32, U32.is_eq(pair.value(pair), 0), 1, pair.size(pair))}}

def previous.run(kind: U32, +text: +List<U32>, +position: U32) -> Maybe<Code>:
  match kind:
    case 0: None{}
    case 1: Some{Code{0, 1}}
    case _:
      +back = leading(List.reverse(&2, U32, take(text, position)))
      previous.found((back >= position : U32), text, (position - 1 - back : U32))

# GetCodepointPrevious(text + position): steps back over continuation bytes and
# decodes with GetCodepointNext. Stepping before the text or starting past
# its NUL is None; position length + 1 reads the NUL: (0, 1).
def previous(+text: +List<U32>, +position: U32) -> Maybe<Code>:
  +length = len(text)
  previous.run(Bool.pick(U32, negative(position) || (position > (length + 1) : U32), 0, Bool.pick(U32, U32.is_eq(position, (length + 1 : U32)), 1, 2)), text, position)

# CodepointToUTF8: 1 to 4 bytes; negative codepoints are one byte (their low
# byte) and codepoints above 0x10ffff none.
def utf8(+c: U32) -> +List<U32>:
  Bool.pick(+List<U32>, negative(c) || (c <= 127 : U32), [(c .&. 255 : U32)],
  Bool.pick(+List<U32>, (c <= 2047 : U32), [(((c >> 6n) .&. 31) .|. 192 : U32), ((c .&. 63) .|. 128 : U32)],
  Bool.pick(+List<U32>, (c <= 65535 : U32), [(((c >> 12n) .&. 15) .|. 224 : U32), (((c >> 6n) .&. 63) .|. 128 : U32), ((c .&. 63) .|. 128 : U32)],
  Bool.pick(+List<U32>, (c <= 1114111 : U32), [(((c >> 18n) .&. 7) .|. 240 : U32), (((c >> 12n) .&. 63) .|. 128 : U32), (((c >> 6n) .&. 63) .|. 128 : U32), ((c .&. 63) .|. 128 : U32)],
    []))))

# LoadUTF8: the concatenated encodings.
def encode(codepoints: +List<U32>) -> +List<U32>:
  match codepoints:
    case Nil{}: Nil{}
    case Con{c, rest}: glue(utf8(c), encode(rest))

# -----------------------------------------------------------------------------
# TextFormat: a typed vsnprintf subset

# A printf argument: a 32-bit int word (an int for d and i, an unsigned int
# for u, x, X and o, an int converted to unsigned char for c), a string for s
# or a float (promoted to double) for f and F.
type Arg is Data:
  ArgInt{value: U32}
  ArgString{text: String}
  ArgFloat{value: F32}

# A conversion specification: flags ('-' 1, '+' 2, ' ' 4, '#' 8, '0' 16),
# field width and optional precision.
type Spec is Data:
  Spec{flags: U32, minimum: U32, dot: Bool, precision: U32}

# mode 0: literal text; 1: flags; 2: width; 3: precision.
type Format is Data:
  Format{mode: U32, spec: Spec, args: +List<Arg>, out: +List<U32>, ok: Bool}

def repeat(n: Nat, +b: U32) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{b, repeat(k, b)}

def digits.go(n: Nat, more: Bool, +value: U32, +base: U32, +upper: Bool, acc: +List<U32>) -> +List<U32>:
  match n more:
    case _ False{}: acc
    case 0n True{}: acc
    case 1n+k True{}:
      +d = (value % base : U32)
      +q = (value / base : U32)
      digits.go(k, U32.is_ne(q, 0), q, base, upper,
        Con{Bool.pick(U32, (d < 10 : U32), (48 + d : U32), Bool.pick(U32, upper, (55 + d : U32), (87 + d : U32))), acc})

def digits(+value: U32, +base: U32, +upper: Bool) -> +List<U32>:
  digits.go(32n, True{}, value, base, upper, Nil{})

def has(+flags: U32, +bit: U32) -> Bool:
  U32.is_ne((flags .&. bit : U32), 0)

# The field: '-' pads on the right, '0' (when allowed) between the sign or
# base prefix and the digits, otherwise spaces on the left.
def pad(+flags: U32, +minimum: U32, +zero: Bool, +prefix: +List<U32>, +body: +List<U32>) -> +List<U32>:
  +length = (len(prefix) + len(body) : U32)
  +fill = U32.to_nat(Bool.pick(U32, (minimum > length : U32), (minimum - length : U32), 0))
  Bool.pick(+List<U32>, has(flags, 1), glue(prefix, glue(body, repeat(fill, 32))),
    Bool.pick(+List<U32>, zero && has(flags, 16), glue(prefix, glue(repeat(fill, 48), body)), glue(repeat(fill, 32), glue(prefix, body))))

def integer.field(+signed: Bool, +base: U32, +upper: Bool, +value: U32, +flags: U32, +minimum: U32, +dot: Bool, +precision: U32) -> +List<U32>:
  +minus = signed && negative(value)
  +magnitude = Bool.pick(U32, minus, (0 - value : U32), value)
  +raw = Bool.pick(+List<U32>, dot && U32.is_eq(magnitude, 0) && U32.is_eq(precision, 0), [], digits(magnitude, base, upper))
  +zeroed = Bool.pick(+List<U32>, dot && (precision > len(raw) : U32), glue(repeat(U32.to_nat(Bool.pick(U32, (precision > len(raw) : U32), (precision - len(raw) : U32), 0)), 48), raw), raw)
  +body = Bool.pick(+List<U32>, has(flags, 8) && U32.is_eq(base, 8) && U32.is_ne(head(zeroed), 48), Con{48, zeroed}, zeroed)
  +prefix = Bool.pick(+List<U32>, minus, [45], Bool.pick(+List<U32>, signed && has(flags, 2), [43], Bool.pick(+List<U32>, signed && has(flags, 4), [32],
    Bool.pick(+List<U32>, has(flags, 8) && U32.is_eq(base, 16) && U32.is_ne(magnitude, 0), [48, Bool.pick(U32, upper, 88, 120)], []))))
  pad(flags, minimum, Bool.not(dot), prefix, body)

def float.text(text: Maybe<String>, +upper: Bool, +infinite: Bool, +flags: U32, +minimum: U32) -> Maybe<+List<U32>>:
  match text:
    case None{}: None{}
    case Some{t}:
      +raw = codes(t)
      +minus = U32.is_eq(head(raw), 45)
      +body = Bool.pick(+List<U32>, minus, List.drop(&2, U32, raw, 1n), raw)
      +prefix = Bool.pick(+List<U32>, minus, [45], Bool.pick(+List<U32>, has(flags, 2), [43], Bool.pick(+List<U32>, has(flags, 4), [32], [])))
      Some{pad(flags, minimum, Bool.not(infinite), prefix, Bool.pick(+List<U32>, upper && infinite, [73, 78, 70], body))}

# "%f" text from src/decimal.bend (exact, half to even); NaN is None.
def float.field(+upper: Bool, +value: F32, +flags: U32, +minimum: U32, +dot: Bool, +precision: U32) -> Maybe<+List<U32>>:
  +bits = F32.bits(value)
  float.text(Decimal.fixed(bits, U32.to_nat(Bool.pick(U32, dot, precision, 6))), upper, U32.is_eq((bits .&. 2147483647 : U32), 2139095040), flags, minimum)

def field.of(kind: U32, +flags: U32, +minimum: U32, +dot: Bool, +precision: U32, arg: Maybe<&2, Arg>) -> Maybe<+List<U32>>:
  match kind arg:
    case 10 _: Some{[37]}
    case 1 Some{ArgInt{v}}: Some{integer.field(True{}, 10, False{}, v, flags, minimum, dot, precision)}
    case 2 Some{ArgInt{v}}: Some{integer.field(False{}, 10, False{}, v, flags, minimum, dot, precision)}
    case 3 Some{ArgInt{v}}: Some{integer.field(False{}, 16, False{}, v, flags, minimum, dot, precision)}
    case 4 Some{ArgInt{v}}: Some{integer.field(False{}, 16, True{}, v, flags, minimum, dot, precision)}
    case 5 Some{ArgInt{v}}: Some{integer.field(False{}, 8, False{}, v, flags, minimum, dot, precision)}
    case 6 Some{ArgInt{v}}: Some{pad(flags, minimum, False{}, [], [(v .&. 255 : U32)])}
    case 7 Some{ArgString{+t}}: Some{pad(flags, minimum, False{}, [], Bool.pick(+List<U32>, dot, take(bytes(t), precision), bytes(t)))}
    case 8 Some{ArgFloat{x}}: float.field(False{}, x, flags, minimum, dot, precision)
    case 9 Some{ArgFloat{x}}: float.field(True{}, x, flags, minimum, dot, precision)
    case _ _: None{}

# Conversion kinds: 1 d/i, 2 u, 3 x, 4 X, 5 o, 6 c, 7 s, 8 f, 9 F, 10 %%; 0 is
# outside the subset (other conversions, length modifiers, '*').
def conversion(+c: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, 100) || U32.is_eq(c, 105), 1, Bool.pick(U32, U32.is_eq(c, 117), 2, Bool.pick(U32, U32.is_eq(c, 120), 3,
  Bool.pick(U32, U32.is_eq(c, 88), 4, Bool.pick(U32, U32.is_eq(c, 111), 5, Bool.pick(U32, U32.is_eq(c, 99), 6, Bool.pick(U32, U32.is_eq(c, 115), 7,
  Bool.pick(U32, U32.is_eq(c, 102), 8, Bool.pick(U32, U32.is_eq(c, 70), 9, Bool.pick(U32, U32.is_eq(c, 37), 10, 0))))))))))

# The flags each conversion accepts in the subset; C leaves '#' with d, i, u,
# c and s and '0' with c and s undefined, and the subset also refuses '+' and
# ' ' where they have no effect.
def allowed(kind: U32) -> U32:
  match kind:
    case 1: 23
    case 2: 17
    case 3: 25
    case 4: 25
    case 5: 25
    case 6: 1
    case 7: 1
    case 8: 23
    case 9: 23
    case _: 0

def field(+c: U32, +spec: Spec, arg: Maybe<&2, Arg>) -> Maybe<+List<U32>>:
  Spec{+flags, +minimum, +dot, +precision} = spec
  +kind = conversion(c)
  +valid = U32.is_eq((flags .&. (4294967295 - allowed(kind)) : U32), 0) && (minimum <= 4096 : U32) && (precision <= 4096 : U32)
    && Bool.not(U32.is_eq(kind, 6) && dot) && Bool.not((kind >= 8 : U32) && (kind <= 9 : U32) && (precision > 9 : U32))
    && Bool.not(U32.is_eq(kind, 10) && (dot || U32.is_ne(minimum, 0)))
  field.of(Bool.pick(U32, valid, kind, 0), flags, minimum, dot, precision, arg)

def flag(+c: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, 45), 1, Bool.pick(U32, U32.is_eq(c, 43), 2, Bool.pick(U32, U32.is_eq(c, 32), 4,
    Bool.pick(U32, U32.is_eq(c, 35), 8, Bool.pick(U32, U32.is_eq(c, 48), 16, 0)))))

def grow(+value: U32, +c: U32) -> U32:
  Bool.pick(U32, (value > 9999 : U32), 100000, (value * 10 + (c - 48) : U32))

def format.fresh() -> Spec:
  Spec{0, 0, False{}, 0}

def format.converted(field: Maybe<+List<U32>>, +percent: Bool, +args: +List<Arg>, +out: +List<U32>) -> Format:
  match field:
    case None{}: Format{0, format.fresh(), args, out, False{}}
    case Some{bytes}: Format{0, format.fresh(), Bool.pick(+List<Arg>, percent, args, List.drop(&2, Arg, args, 1n)), revappend(bytes, out), True{}}

def format.convert(+c: U32, +spec: Spec, +args: +List<Arg>, +out: +List<U32>) -> Format:
  format.converted(field(c, spec, List.head(&2, Arg, args)), U32.is_eq(c, 37), args, out)

# 0: no-op after an error; 1: literal; 2: '%'; 3: flag; 4: width digit;
# 5: '.'; 6: precision digit; 7: conversion.
def format.kind(+state: Format, +c: U32) -> U32:
  Format{+mode, _, _, _, +ok} = state
  Bool.pick(U32, Bool.not(ok), 0,
    Bool.pick(U32, U32.is_eq(mode, 0), Bool.pick(U32, U32.is_eq(c, 37), 2, 1),
      Bool.pick(U32, U32.is_eq(mode, 1) && U32.is_ne(flag(c), 0), 3,
        Bool.pick(U32, (mode <= 2 : U32) && digit(c), 4,
          Bool.pick(U32, (mode <= 2 : U32) && U32.is_eq(c, 46), 5,
            Bool.pick(U32, U32.is_eq(mode, 3) && digit(c), 6, 7))))))

def format.step(kind: U32, +c: U32, state: Format) -> Format:
  match kind state:
    case 1 Format{mode, spec, args, out, ok}: Format{mode, spec, args, Con{c, out}, ok}
    case 2 Format{_, _, args, out, ok}: Format{1, format.fresh(), args, out, ok}
    case 3 Format{_, Spec{flags, minimum, dot, precision}, args, out, ok}: Format{1, Spec{(flags .|. flag(c) : U32), minimum, dot, precision}, args, out, ok}
    case 4 Format{_, Spec{flags, minimum, dot, precision}, args, out, ok}: Format{2, Spec{flags, grow(minimum, c), dot, precision}, args, out, ok}
    case 5 Format{_, Spec{flags, minimum, _, _}, args, out, ok}: Format{3, Spec{flags, minimum, True{}, 0}, args, out, ok}
    case 6 Format{mode, Spec{flags, minimum, dot, precision}, args, out, ok}: Format{mode, Spec{flags, minimum, dot, grow(precision, c)}, args, out, ok}
    case 7 Format{_, spec, args, out, _}: format.convert(c, spec, args, out)
    case _ other: other

def format.go(bytes: +List<U32>, +state: Format) -> Format:
  match bytes:
    case Nil{}: state
    case Con{+c, rest}: format.go(rest, format.step(format.kind(state, c), c, state))

def format.end(state: Format) -> Maybe<+List<U32>>:
  match state:
    case Format{mode, _, _, out, ok}: Bool.pick(Maybe<+List<U32>>, ok && U32.is_eq(mode, 0), Some{List.reverse(&2, U32, out)}, None{})

def format.result(found: Maybe<+List<U32>>) -> Maybe<String>:
  match found:
    case None{}: None{}
    case Some{+bytes}: Some{cstring(Bool.pick(+List<U32>, (len(bytes) >= 1024 : U32), glue(take(bytes, 1020), [46, 46, 46]), bytes))}

# TextFormat: vsnprintf into the 1024-byte buffer; output of 1024 or more
# bytes keeps 1020 and ends with "...". The result is read up to its first
# NUL (a %c of 0). Unsupported or undefined specifications, missing or
# mismatched arguments and NaN floats are None; extra arguments are ignored.
def format(+text: +List<U32>, +args: +List<Arg>) -> Maybe<String>:
  format.result(format.end(format.go(text, Format{0, format.fresh(), args, Nil{}, True{}})))
