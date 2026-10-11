# raylib [text] example - codepoints loading, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_codepoints_loading.c
# (zlib/libpng, Copyright (c) 2022-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# The example scans a Japanese text for its codepoints (LoadCodepoints),
# removes the repeated ones and loads a font with the rest. Its
# CodepointRemoveDuplicates copies the list into codepointCount ints and, at
# the first repeated codepoint, shifts the tail down with
# codepointsNoDups[k] = codepointsNoDups[k + 1] up to k = count - 1: the last
# step reads one int past the allocation. The text repeats its ideographic
# space (U+3000) and its line break, so that read happens before the first
# frame and the example's behavior is undefined from there
# (docs/COMPATIBILITY.md): this port refuses every frame, and nothing after
# that point (LoadFontEx with the codepoints, the atlas, DrawTextEx, the
# GetCodepointNext/GetCodepointPrevious test keys) is ported. The reference
# is not run.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# repeats: the text has a codepoint twice (CodepointRemoveDuplicates then
# reads past its array).
type State is Data:
  State{repeats: Bool}

# The text, as its UTF-8 bytes: the Iroha poem's four lines, their halves
# separated by an ideographic space.
def text() -> String:
  "\u{e3}\u{81}\u{84}\u{e3}\u{82}\u{8d}\u{e3}\u{81}\u{af}\u{e3}\u{81}\u{ab}\u{e3}\u{81}\u{bb}\u{e3}\u{81}\u{b8}\u{e3}\u{81}\u{a8}\u{e3}\u{80}\u{80}\u{e3}\u{81}\u{a1}\u{e3}\u{82}\u{8a}\u{e3}\u{81}\u{ac}\u{e3}\u{82}\u{8b}\u{e3}\u{82}\u{92}\n\u{e3}\u{82}\u{8f}\u{e3}\u{81}\u{8b}\u{e3}\u{82}\u{88}\u{e3}\u{81}\u{9f}\u{e3}\u{82}\u{8c}\u{e3}\u{81}\u{9d}\u{e3}\u{80}\u{80}\u{e3}\u{81}\u{a4}\u{e3}\u{81}\u{ad}\u{e3}\u{81}\u{aa}\u{e3}\u{82}\u{89}\u{e3}\u{82}\u{80}\n\u{e3}\u{81}\u{86}\u{e3}\u{82}\u{90}\u{e3}\u{81}\u{ae}\u{e3}\u{81}\u{8a}\u{e3}\u{81}\u{8f}\u{e3}\u{82}\u{84}\u{e3}\u{81}\u{be}\u{e3}\u{80}\u{80}\u{e3}\u{81}\u{91}\u{e3}\u{81}\u{b5}\u{e3}\u{81}\u{93}\u{e3}\u{81}\u{88}\u{e3}\u{81}\u{a6}\n\u{e3}\u{81}\u{82}\u{e3}\u{81}\u{95}\u{e3}\u{81}\u{8d}\u{e3}\u{82}\u{86}\u{e3}\u{82}\u{81}\u{e3}\u{81}\u{bf}\u{e3}\u{81}\u{97}\u{e3}\u{80}\u{80}\u{e3}\u{82}\u{91}\u{e3}\u{81}\u{b2}\u{e3}\u{82}\u{82}\u{e3}\u{81}\u{9b}\u{e3}\u{81}\u{99}"

def repeated(+value: U32, rest: +List<U32>) -> Bool:
  match rest:
    case Nil{}: False{}
    case Con{+other, more}: U32.is_eq(value, other) || repeated(value, more)

# Whether codepointsNoDups[i] == codepointsNoDups[j] for some i < j.
def duplicated(list: +List<U32>) -> Bool:
  match list:
    case Nil{}: False{}
    case Con{+value, +rest}: repeated(value, rest) || duplicated(rest)

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

# With a repeated codepoint the native behavior is undefined; without one the rest of the example would run, which is not ported.
def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, (state, J.Frame.refuse(frame)))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): codepoints = LoadCodepoints(text, &codepointCount); CodepointRemoveDuplicates(codepoints, codepointCount, &codepointsNoDupsCount).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{duplicated(J.Codepoint.load(text()))}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - codepoints loading", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
