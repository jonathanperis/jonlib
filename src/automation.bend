# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rcore.c's automation event lists
# (zlib, LICENSES/raylib.txt): AutomationEvent and AutomationEventList,
# LoadAutomationEventList's text reader and ExportAutomationEventList's text
# writer. The binary .rae reader and writer are commented out in the pinned
# source, so only the text format exists. See docs/INPUT.md.
import Base

# AutomationEvent: frame, type and four int parameters (C ints as U32 words).
type AutoEvent is Data:
  AutoEvent{frame: U32, kind: U32, p0: U32, p1: U32, p2: U32, p3: U32}

# AutomationEventList: capacity and the events (count is their number).
type AutoList is Data:
  AutoList{capacity: U32, count: U32, events: +List<AutoEvent>}

def AutoEvent.kind(+e: AutoEvent) -> U32:
  AutoEvent{_, kind, _, _, _, _} = e
  kind

# LoadAutomationEventList(NULL): an empty list of MAX_AUTOMATION_EVENTS (16384).
def AutoList.new() -> AutoList:
  AutoList{16384, 0, Nil{}}

def AutoList.count(+list: AutoList) -> U32:
  AutoList{_, count, _} = list
  count

def AutoList.capacity(+list: AutoList) -> U32:
  AutoList{capacity, _, _} = list
  capacity

def AutoList.events(+list: AutoList) -> +List<AutoEvent>:
  AutoList{_, _, events} = list
  events

# Appends recorded events (the recorder bounds them by the free capacity);
# tail-recursive, as lists reach 16384 events.
def AutoList.onto(reversed: +List<AutoEvent>, +acc: +List<AutoEvent>) -> +List<AutoEvent>:
  match reversed:
    case Nil{}: acc
    case Con{+e, rest}: AutoList.onto(rest, Con{e, acc})

def AutoList.append(list: AutoList, +added: +List<AutoEvent>, +n: U32) -> AutoList:
  AutoList{capacity, +count, events} = list
  AutoList{capacity, (count + n : U32), AutoList.onto(List.reverse(&2, AutoEvent, events), added)}

# -----------------------------------------------------------------------------
# ExportAutomationEventList (text)

def names(+kind: U32) -> String:
  match kind:
    case 0: "EVENT_NONE"
    case 1: "INPUT_KEY_UP"
    case 2: "INPUT_KEY_DOWN"
    case 3: "INPUT_KEY_PRESSED"
    case 4: "INPUT_KEY_RELEASED"
    case 5: "INPUT_MOUSE_BUTTON_UP"
    case 6: "INPUT_MOUSE_BUTTON_DOWN"
    case 7: "INPUT_MOUSE_POSITION"
    case 8: "INPUT_MOUSE_WHEEL_MOTION"
    case 9: "INPUT_GAMEPAD_CONNECT"
    case 10: "INPUT_GAMEPAD_DISCONNECT"
    case 11: "INPUT_GAMEPAD_BUTTON_UP"
    case 12: "INPUT_GAMEPAD_BUTTON_DOWN"
    case 13: "INPUT_GAMEPAD_AXIS_MOTION"
    case 14: "INPUT_TOUCH_UP"
    case 15: "INPUT_TOUCH_DOWN"
    case 16: "INPUT_TOUCH_POSITION"
    case 17: "INPUT_GESTURE"
    case 18: "WINDOW_CLOSE"
    case 19: "WINDOW_MAXIMIZE"
    case 20: "WINDOW_MINIMIZE"
    case 21: "WINDOW_RESIZE"
    case 22: "ACTION_TAKE_SCREENSHOT"
    case _: "ACTION_SETTARGETFPS"

# printf %i of an int word.
def int.show(+word: U32) -> String:
  Bool.pick(String, (word >= 2147483648 : U32), "-" ++ U32.show((0 - word : U32)), U32.show(word))

def header() -> String:
  "#\n# Automation events exporter v1.0 - raylib automation events list\n#\n#    c <events_count>\n"
    ++ "#    e <frame> <event_type> <param0> <param1> <param2> <param3> // <event_type_name>\n#\n"
    ++ "# more info and bugs-report:  github.com/raysan5/raylib\n# feedback and support:       ray[at]raylib.com\n#\n"
    ++ "# Copyright (c) 2023-2026 Ramon Santamaria (@raysan5)\n#\n\n"

def line(+e: AutoEvent) -> String:
  AutoEvent{frame, +kind, p0, p1, p2, p3} = e
  "e " ++ int.show(frame) ++ " " ++ int.show(kind) ++ " " ++ int.show(p0) ++ " " ++ int.show(p1) ++ " " ++ int.show(p2) ++ " "
    ++ int.show(p3) ++ " // Event: " ++ names(kind) ++ "\n"

def lines(events: +List<AutoEvent>, +acc: String) -> String:
  match events:
    case Nil{}: acc
    case Con{+e, rest}: lines(rest, acc ++ line(e))

def named(events: +List<AutoEvent>, +ok: Bool) -> Bool:
  match events:
    case Nil{}: ok
    case Con{+e, rest}: named(rest, ok && (AutoEvent.kind(e) <= 23 : U32))

def export.checked(valid: Bool, +list: AutoList) -> Maybe<String>:
  match valid:
    case False{}: None{}
    case True{}: Some{header() ++ "c " ++ int.show(AutoList.count(list)) ++ "\n" ++ lines(AutoList.events(list), "")}

# The exported text; None when an event type has no name (raylib would read
# autoEventTypeName out of bounds).
def export(+list: AutoList) -> Maybe<String>:
  export.checked(named(AutoList.events(list), True{}), list)

# -----------------------------------------------------------------------------
# LoadAutomationEventList (text): fgets into a 256-byte buffer, then
# sscanf(buffer, "c %i") or sscanf(buffer, "e %d %d %d %d %d %d %[^\n]s").

# fgets(buffer, 256, file): the next chunk (up to 255 bytes, through the first
# newline) and whether reading it reached the end of the file.
type Chunk is Data:
  Chunk{bytes: +List<U32>, rest: +List<U32>, eof: Bool}

def chunk.go(n: Nat, bytes: +List<U32>, stop: Bool, +acc: +List<U32>) -> Chunk:
  match n bytes stop:
    case _ rest True{}: Chunk{List.reverse(&2, U32, acc), rest, False{}}
    case 0n rest False{}: Chunk{List.reverse(&2, U32, acc), rest, False{}}
    case 1n+_ Nil{} False{}: Chunk{List.reverse(&2, U32, acc), Nil{}, True{}}
    case 1n+k Con{+b, rest} False{}: chunk.go(k, rest, U32.is_eq(b, 10), Con{b, acc})

def chunk(bytes: +List<U32>) -> Chunk:
  chunk.go(255n, bytes, False{}, Nil{})

def item(bytes: +List<U32>) -> U32:
  match bytes:
    case Nil{}: 256
    case Con{+b, _}: b

def space(+b: U32) -> Bool:
  U32.is_eq(b, 32) || ((b >= 9) && (b <= 13) : U32)

def skip.go(bytes: +List<U32>, go: Bool) -> +List<U32>:
  match bytes go:
    case Con{_, +rest} True{}: skip.go(rest, space(item(rest)))
    case other _: other

def skip(+bytes: +List<U32>) -> +List<U32>:
  skip.go(bytes, space(item(bytes)))

def until_nul(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: Bool.pick(+List<U32>, U32.is_eq(b, 0), Nil{}, Con{b, until_nul(rest)})

# A scanned number: None{} no conversion (matching failure), Bad{} undefined
# (out of int range or an ambiguous prefix), Number{value, rest}.
type Scan is Data:
  NoMatch{}
  Bad{}
  Number{value: U32, rest: +List<U32>}

def digit(+b: U32, +base: U32) -> U32:
  +d = Bool.pick(U32, ((b >= 48) && (b <= 57) : U32), (b - 48 : U32),
    Bool.pick(U32, ((b >= 97) && (b <= 102) : U32), (b - 87 : U32), Bool.pick(U32, ((b >= 65) && (b <= 70) : U32), (b - 55 : U32), 99)))
  Bool.pick(U32, (d < base : U32), d, 99)

def is_digit(+b: U32, +base: U32) -> Bool:
  (digit(b, base) < 99 : U32)

type Digits is Data:
  Digits{value: U32, over: Bool, count: U32, rest: +List<U32>}

# strtol-style digits while go (the next byte is a digit): the magnitude is kept
# while at most 2^31 (enough to decide int overflow for either sign); `over`
# marks a larger value.
def digits(bytes: +List<U32>, go: Bool, +base: U32, +value: U32, +over: Bool, +count: U32) -> Digits:
  match bytes go:
    case Con{+b, +rest} True{}:
      +d = digit(b, base)
      +big = over || (value > ((2147483648 - d) / base) : U32)
      digits(rest, is_digit(item(rest), base), base, Bool.pick(U32, big, 0, (value * base + d : U32)), big, (count + 1 : U32))
    case other _: Digits{value, over, count, other}

def digits.from(+bytes: +List<U32>, +base: U32) -> Digits:
  digits(bytes, is_digit(item(bytes), base), base, 0, False{}, 0)

def number.signed(+negative: Bool, +magnitude: U32) -> U32:
  Bool.pick(U32, negative, (0 - magnitude : U32), magnitude)

def number.finish(+negative: Bool, scanned: Digits) -> Scan:
  Digits{+value, +over, +count, rest} = scanned
  Bool.pick(Scan, U32.is_eq(count, 0), NoMatch{},
    Bool.pick(Scan, over || (value > Bool.pick(U32, negative, 2147483648, 2147483647) : U32), Bad{}, Number{number.signed(negative, value), rest}))

# %i after a leading 0: 0x/0X hexadecimal (a prefix without a hex digit is
# refused, as C libraries disagree on it), else octal.
def number.after_zero(hex: Bool, +negative: Bool, +x: U32, +rest: +List<U32>) -> Scan:
  match hex:
    case True{}: Bool.pick(Scan, is_digit(item(rest), 16), number.finish(negative, digits.from(rest, 16)), Bad{})
    case False{}: number.finish(negative, digits.from(Con{48, Con{x, rest}}, 8))

def number.zero(+negative: Bool, bytes: +List<U32>) -> Scan:
  match bytes:
    case Nil{}: Number{0, Nil{}}
    case Con{+x, rest}: number.after_zero(U32.is_eq(x, 120) || U32.is_eq(x, 88), negative, x, rest)

def number.prefixed(+negative: Bool, bytes: +List<U32>) -> Scan:
  match bytes:
    case Nil{}: NoMatch{}
    case Con{+b, +rest}: Bool.pick(Scan, U32.is_eq(b, 48), number.zero(negative, rest), number.finish(negative, digits.from(Con{b, rest}, 10)))

def number.sign(+integer: Bool, +negative: Bool, +bytes: +List<U32>) -> Scan:
  Bool.pick(Scan, integer, number.prefixed(negative, bytes), number.finish(negative, digits.from(bytes, 10)))

def number.skipped(+integer: Bool, bytes: +List<U32>) -> Scan:
  match bytes:
    case Nil{}: NoMatch{}
    case Con{+b, +rest}:
      Bool.pick(Scan, U32.is_eq(b, 45), number.sign(integer, True{}, rest),
        Bool.pick(Scan, U32.is_eq(b, 43), number.sign(integer, False{}, rest), number.sign(integer, False{}, Con{b, rest})))

# %d (integer False) or %i (True): white space, an optional sign and digits.
def number(+integer: Bool, bytes: +List<U32>) -> Scan:
  number.skipped(integer, skip(bytes))

# " %[^\n]" into char eventDesc[64]: more than 63 characters overflow it.
def description.length(bytes: +List<U32>) -> U32:
  match bytes:
    case Nil{}: 0
    case Con{+b, rest}: Bool.pick(U32, U32.is_eq(b, 10), 0, (1 + description.length(rest) : U32))

# The fields of an "e" line: up to six numbers, then the description check.
type Fields is Data:
  Fields{values: +List<U32>, bad: Bool}

# Six %d conversions (n counts those left after this one), then " %[^\n]".
def fields.go(n: Nat, scan: Scan, +values: +List<U32>) -> Fields:
  match n scan:
    case _ NoMatch{}: Fields{values, False{}}
    case _ Bad{}: Fields{values, True{}}
    case 0n Number{+v, rest}: Fields{List.append(&2, U32, values, [v]), (description.length(skip(rest)) > 63 : U32)}
    case 1n+k Number{+v, rest}: fields.go(k, number(False{}, rest), List.append(&2, U32, values, [v]))

def fields(+bytes: +List<U32>) -> Fields:
  fields.go(5n, number(False{}, bytes), Nil{})

def value(+values: +List<U32>, n: Nat) -> U32:
  item(List.drop(&2, U32, values, n))

def event.of(+values: +List<U32>) -> AutoEvent:
  +padded = List.append(&2, U32, values, [0, 0, 0, 0, 0, 0])
  AutoEvent{value(padded, 0n), value(padded, 1n), value(padded, 2n), value(padded, 3n), value(padded, 4n), value(padded, 5n)}

type Loading is Data:
  Loading{count: U32, events: +List<AutoEvent>, bad: Bool}

# "e" line: the next slot gets the scanned fields (others stay 0, as the list is
# calloc'ed); a 16385th event would be written past MAX_AUTOMATION_EVENTS.
def scan.e(state: Loading, scanned: Fields) -> Loading:
  Loading{+count, events, bad} = state
  Fields{+values, wrong} = scanned
  Loading{(count + 1 : U32), Con{event.of(values), events}, bad || wrong || (count >= 16384 : U32)}

# "c" line: the count is replaced by the number of "e" lines at the end; only an
# undefined %i conversion matters.
def scan.c.scanned(scan: Scan) -> Bool:
  match scan:
    case Bad{}: True{}
    case _: False{}

def scan.c(state: Loading, wrong: Bool) -> Loading:
  Loading{count, events, bad} = state
  Loading{count, events, bad || wrong}

def scan.line(+state: Loading, content: +List<U32>) -> Loading:
  match content:
    case Nil{}: state
    case Con{+b, +rest}:
      Bool.pick(Loading, U32.is_eq(b, 101), scan.e(state, fields(rest)),
        Bool.pick(Loading, U32.is_eq(b, 99), scan.c(state, scan.c.scanned(number(True{}, rest))), state))

# The read loop: a chunk is processed only when reading it did not reach the end
# of the file (so a last line without a newline is ignored).
def load.go(n: Nat, read: Chunk, +state: Loading) -> Loading:
  match n read:
    case 0n _: state
    case 1n+k Chunk{bytes, rest, eof}:
      match eof:
        case True{}: state
        case False{}: load.go(k, chunk(rest), scan.line(state, until_nul(bytes)))

def loaded(state: Loading) -> Maybe<AutoList>:
  Loading{count, events, bad} = state
  match bad:
    case True{}: None{}
    case False{}: Some{AutoList{16384, count, List.reverse(&2, AutoEvent, events)}}

def length(bytes: +List<U32>, +acc: Nat) -> Nat:
  match bytes:
    case Nil{}: acc
    case Con{_, rest}: length(rest, 1n+acc)

# The list LoadAutomationEventList reads from these file bytes; None when the
# C reader is undefined (an int conversion out of range, a description longer
# than its 64-byte buffer, more than 16384 events) or for an ambiguous "0x".
def parse(+bytes: +List<U32>) -> Maybe<AutoList>:
  loaded(load.go(1n+length(bytes, 0n), chunk(bytes), Loading{0, Nil{}, False{}}))
