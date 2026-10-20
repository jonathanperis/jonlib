# raylib [core] example - compute hash, ported to Jonlib.
# Adapted from raylib 6.2 examples/core/core_compute_hash.c (zlib/libpng,
# Copyright (c) 2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A raygui text box (Jongui) edits a text of up to 94 bytes; a button
# computes its CRC32, MD5, SHA-1 and SHA-256 and its Base64 encoding on the
# next frame, shown in read-only text boxes. See docs/GUI.md,
# docs/CHECKSUMS.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# md5, sha1 and sha256 are empty until computed (NULL); base64 too. failed: a
# hash or the encoding refused its input.
type State is Data:
  State{gui: G.Gui, editing: G.Gui.Editing, text: String, edit: Bool, compute: Bool, crc: U32, md5: +List<U32>, sha1: +List<U32>, sha256: +List<U32>, base64: String, failed: Bool}

def bytes(text: String) -> +List<U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{c, rest}: Con{Char.to_u32(c), bytes(rest)}

def word(result: Maybe<&2, U32>) -> U32:
  match result:
    case None{}: 0
    case Some{value}: value

def words(result: Maybe<&2, +List<U32>>) -> +List<U32>:
  match result:
    case None{}: Nil{}
    case Some{values}: values

def encoded.text(encoded: J.Base64.Encoded) -> String:
  J.Base64Encoded{_, text} = encoded
  text

def encoded(result: Maybe<&2, J.Base64.Encoded>) -> String:
  match result:
    case None{}: ""
    case Some{value}: encoded.text(value)

def none(values: +List<U32>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{_, _}: False{}

# EncodeDataBase64, ComputeCRC32, ComputeMD5, ComputeSHA1 and ComputeSHA256 of the text's bytes.
def computed(+gui: G.Gui, +editing: G.Gui.Editing, +text: String, +edit: Bool, +data: +List<U32>) -> State:
  State{gui, editing, text, edit, True{}, word(J.Checksum.crc32(data)), words(J.Checksum.md5(data)), words(J.Checksum.sha1(data)), words(J.Checksum.sha256(data)),
    encoded(J.Base64.encode(data)), none(words(J.Checksum.md5(data))) || none(words(J.Checksum.sha1(data))) || none(words(J.Checksum.sha256(data)))}

def update.at(compute: Bool, +state: State) -> State:
  match compute:
    case False{}: state
    case True{}:
      State{+gui, +editing, +text, +edit, _, _, _, _, _, _, _} = state
      computed(gui, editing, text, edit, bytes(text))

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{_, _, _, _, +compute, _, _, _, _, _, _} = state
  (core, update.at(compute, state))

def hex.cat(word: Maybe<String>, rest: Maybe<String>) -> Maybe<String>:
  match word rest:
    case Some{a} Some{b}: Some{a ++ b}
    case _ _: None{}

def hex.go(values: +List<U32>) -> Maybe<String>:
  match values:
    case Nil{}: Some{""}
    case Con{+value, rest}: hex.cat(J.Text.format("%08X", [J.TextInt{value}]), hex.go(rest))

def count(values: +List<U32>, +n: U32) -> U32:
  match values:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

# GetDataAsHexText: "%08X" of each word, or "00000000" for NULL, no words, or 15 words or more.
def hex(+values: +List<U32>) -> Maybe<String>:
  Bool.pick(Maybe<String>, U32.is_eq(count(values, 0), 0) || (count(values, 0) >= 15 : U32), Some{"00000000"}, hex.go(values))

def frame.of(r: J.Frame & (J.Core & (String & (G.Gui.Editing & Bool)))) -> J.Frame:
  (frame, _) = r
  frame

# A label and, beside it, a read-only text box (it reads no input and leaves the text box globals alone).
def row(text: Maybe<String>, +gui: G.Gui, +core: J.Core, +editing: G.Gui.Editing, +y: F32, label: String, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{+t}: frame.of(G.Gui.text_box(gui, core, G.Gui.label(gui, frame, J.Rectangle{40.0, y, 120.0, 32.0}, label), J.Rectangle{160.0, y, 600.0, 32.0}, t, 120, False{}, editing))

def refused(failed: Bool, frame: J.Frame) -> J.Frame:
  match failed:
    case False{}: frame
    case True{}: J.Frame.refuse(frame)

# The hash rows with TEXT_READONLY set, the bonus label drawn as focused.
def rows(+state: State, +core: J.Core, +big: G.Gui, frame: J.Frame) -> J.Frame:
  State{+gui, +editing, _, _, _, +crc, +md5, +sha1, +sha256, +base64, +failed} = state
  +read = G.Gui.set_style(gui, 9, 16, 1)
  f1 = G.Gui.label(big, frame, J.Rectangle{40.0, 160.0, 720.0, 32.0}, "INPUT DATA HASH VALUES:")
  f2 = row(hex([crc]), read, core, editing, 200.0, "CRC32 [32 bit]:", f1)
  f3 = row(hex(md5), read, core, editing, 236.0, "MD5 [128 bit]:", f2)
  f4 = row(hex(sha1), read, core, editing, 272.0, "SHA1 [160 bit]:", f3)
  f5 = row(hex(sha256), read, core, editing, 308.0, "SHA256 [256 bit]:", f4)
  f6 = G.Gui.label(G.Gui.set_state(read, 1), f5, J.Rectangle{40.0, 350.0, 320.0, 32.0}, "BONUS - BAS64 ENCODED STRING:")
  refused(failed, row(Some{base64}, G.Gui.set_state(read, 0), core, editing, 380.0, "BASE64 ENCODING:", f6))

def ui.button(r: J.Frame & Bool, +core: J.Core, +state: State, +big: G.Gui) -> J.Core & (State & J.Frame):
  (frame, +clicked) = r
  State{+gui, +editing, +text, +edit, _, +crc, +md5, +sha1, +sha256, +base64, +failed} = state
  (core, (State{gui, editing, text, edit, clicked, crc, md5, sha1, sha256, base64, failed}, rows(state, core, big, frame)))

def ui.typed(pair: G.Gui.Editing & Bool, +core: J.Core, +state: State, +big: G.Gui, frame: J.Frame, +text: String) -> J.Core & (State & J.Frame):
  (+editing, +toggled) = pair
  State{+gui, _, _, +edit, +compute, +crc, +md5, +sha1, +sha256, +base64, +failed} = state
  ui.button(G.Gui.button(gui, core, frame, J.Rectangle{40.0, 104.0, 720.0, 32.0}, "COMPUTE INPUT DATA HASHES"), core,
    State{gui, editing, text, Bool.pick(Bool, toggled, Bool.not(edit), edit), compute, crc, md5, sha1, sha256, base64, failed}, big)

def ui.text(+core: J.Core, +state: State, +big: G.Gui, frame: J.Frame, rest: String & (G.Gui.Editing & Bool)) -> J.Core & (State & J.Frame):
  (+text, pair) = rest
  ui.typed(pair, core, state, big, frame, text)

def ui.core(+state: State, +big: G.Gui, frame: J.Frame, rest: J.Core & (String & (G.Gui.Editing & Bool))) -> J.Core & (State & J.Frame):
  (+core, more) = rest
  ui.text(core, state, big, frame, more)

def ui.box(+state: State, +big: G.Gui, r: J.Frame & (J.Core & (String & (G.Gui.Editing & Bool)))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  ui.core(state, big, frame, rest)

# The title in TEXT_SIZE 20 with TEXT_SPACING 2, then the text box (its
# result flips the edit mode), the button and the hash rows.
def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +editing, +text, +edit, _, _, _, _, _, _, _} = state
  +big = G.Gui.set_style(G.Gui.set_style(gui, 0, 16, 20), 0, 17, 2)
  ui.box(state, big, G.Gui.text_box(gui, core, G.Gui.label(big, J.Frame.clear_background(frame, J.Color.RAYWHITE()), J.Rectangle{40.0, 26.0, 720.0, 32.0}, "INPUT DATA (TEXT):"),
    J.Rectangle{40.0, 64.0, 720.0, 32.0}, text, 95, edit, editing))

# The main loop's body; nothing in it follows the libm profile.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): the pangram, nothing computed yet, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), G.Gui.editing(), "The quick brown fox jumps over the lazy dog.", False{}, False{}, 0, Nil{}, Nil{}, Nil{}, "", False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - compute hash", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
