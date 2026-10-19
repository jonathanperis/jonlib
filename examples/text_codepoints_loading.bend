# raylib [text] example - codepoints loading, ported to Jonlib.
# Adapted from raylib 6.2 examples/text/text_codepoints_loading.c
# (zlib/libpng, Copyright (c) 2022-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A Japanese text scanned for its codepoints (LoadCodepoints), the repeated
# ones removed (the example's CodepointRemoveDuplicates: the first of each,
# in order) and a font loaded from a TTF at size 36 with the rest, its atlas
# filtered bilinearly; the text is drawn with it (line spacing 20), or, while
# SPACE has toggled it on, the atlas. raylib 6.2 fixed the duplicate
# removal's shift, which in 6.0 read one int past its array before the first
# frame (that version of the port refused every frame).
#
# RIGHT and LEFT move a pointer through the text by GetCodepointNext and
# GetCodepointPrevious; nothing is drawn from it. Stepping before the text,
# or reading past the byte after its NUL, is undefined in C: that frame and
# every later one are refused. See docs/TEXT.md, docs/FONTS.md and
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# font: the loaded font (none where it did not load); atlas: showFontAtlas;
# at: the pointer's offset in the text; ok: no undefined step so far; total
# and unique: codepointCount and codepointsNoDupsCount.
type State is Type:
  State{font: Maybe<J.Font>, atlas: Bool, at: U32, ok: Bool, total: U32, unique: U32}

# The text, as its UTF-8 bytes: the Iroha poem's four lines, their halves
# separated by an ideographic space.
def text() -> String:
  "\u{e3}\u{81}\u{84}\u{e3}\u{82}\u{8d}\u{e3}\u{81}\u{af}\u{e3}\u{81}\u{ab}\u{e3}\u{81}\u{bb}\u{e3}\u{81}\u{b8}\u{e3}\u{81}\u{a8}\u{e3}\u{80}\u{80}\u{e3}\u{81}\u{a1}\u{e3}\u{82}\u{8a}\u{e3}\u{81}\u{ac}\u{e3}\u{82}\u{8b}\u{e3}\u{82}\u{92}\n\u{e3}\u{82}\u{8f}\u{e3}\u{81}\u{8b}\u{e3}\u{82}\u{88}\u{e3}\u{81}\u{9f}\u{e3}\u{82}\u{8c}\u{e3}\u{81}\u{9d}\u{e3}\u{80}\u{80}\u{e3}\u{81}\u{a4}\u{e3}\u{81}\u{ad}\u{e3}\u{81}\u{aa}\u{e3}\u{82}\u{89}\u{e3}\u{82}\u{80}\n\u{e3}\u{81}\u{86}\u{e3}\u{82}\u{90}\u{e3}\u{81}\u{ae}\u{e3}\u{81}\u{8a}\u{e3}\u{81}\u{8f}\u{e3}\u{82}\u{84}\u{e3}\u{81}\u{be}\u{e3}\u{80}\u{80}\u{e3}\u{81}\u{91}\u{e3}\u{81}\u{b5}\u{e3}\u{81}\u{93}\u{e3}\u{81}\u{88}\u{e3}\u{81}\u{a6}\n\u{e3}\u{81}\u{82}\u{e3}\u{81}\u{95}\u{e3}\u{81}\u{8d}\u{e3}\u{82}\u{86}\u{e3}\u{82}\u{81}\u{e3}\u{81}\u{bf}\u{e3}\u{81}\u{97}\u{e3}\u{80}\u{80}\u{e3}\u{82}\u{91}\u{e3}\u{81}\u{b2}\u{e3}\u{82}\u{82}\u{e3}\u{81}\u{9b}\u{e3}\u{81}\u{99}"

def repeated(+value: U32, rest: +List<U32>) -> Bool:
  match rest:
    case Nil{}: False{}
    case Con{+other, more}: U32.is_eq(value, other) || repeated(value, more)

# CodepointRemoveDuplicates: each codepoint once, at its first place (`kept`
# is the result so far, the newest first).
def deduplicated(list: +List<U32>, +kept: +List<U32>) -> +List<U32>:
  match list:
    case Nil{}: List.reverse(&2, U32, kept)
    case Con{+value, +rest}: deduplicated(rest, Bool.pick(+List<U32>, repeated(value, kept), kept, Con{value, kept}))

def counted(list: +List<U32>, +n: U32) -> U32:
  match list:
    case Nil{}: n
    case Con{_, +rest}: counted(rest, (n + 1 : U32))

def deduped() -> +List<U32>:
  deduplicated(J.Codepoint.load(text()), Nil{})

def toggled(pressed: Bool, +on: Bool) -> Bool:
  match pressed:
    case True{}: Bool.not(on)
    case False{}: on

def forward.sized(+at: U32, r: U32 & U32) -> Maybe<U32>:
  (_, +size) = r
  Some{(at + size : U32)}

# GetCodepointNext(ptr, &codepointSize); ptr += codepointSize. It reads
# ptr[0]: past the byte after the NUL (an offset above the length) that is
# outside the text.
def forward(past: Bool, +at: U32) -> Maybe<U32>:
  match past:
    case True{}: None{}
    case False{}: forward.sized(at, J.Codepoint.next(String.drop(text(), U32.to_nat(at))))

def back.sized(+at: U32, r: U32 & U32) -> Maybe<U32>:
  (_, +size) = r
  Some{(at - size : U32)}

# GetCodepointPrevious(ptr, &codepointSize); ptr -= codepointSize: none
# where it steps before the text.
def back(+at: U32, found: Maybe<(U32 & U32)>) -> Maybe<U32>:
  match found:
    case None{}: None{}
    case Some{r}: back.sized(at, r)

def stepped(left: Bool, +at: U32) -> Maybe<U32>:
  match left:
    case False{}: Some{at}
    case True{}: back(at, J.Codepoint.previous(text(), at))

# RIGHT, else LEFT.
def step(right: Bool, +left: Bool, +at: U32) -> Maybe<U32>:
  match right:
    case True{}: forward((at > J.Text.length(text()) : U32), at)
    case False{}: stepped(left, at)

def update.moved(font: Maybe<J.Font>, +atlas: Bool, +at: U32, +ok: Bool, +total: U32, +unique: U32, moved: Maybe<U32>) -> State:
  match moved:
    case None{}: State{font, atlas, at, False{}, total, unique}
    case Some{+next}: State{font, atlas, next, ok, total, unique}

# SPACE toggles the atlas; RIGHT or LEFT move the pointer (once the program
# is undefined it stays where it was).
def update(+core: J.Core, state: State) -> J.Core & State:
  State{font, +atlas, +at, +ok, +total, +unique} = state
  +right = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())
  +left = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT())
  (core, update.moved(font, toggled(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), atlas), at, ok, total, unique,
    Bool.pick(Maybe<U32>, ok, step(right, left, at), Some{at})))

def label(text: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, J.Color.GREEN())

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# DrawRectangle(0, 0, GetScreenWidth(), 70, BLACK) and the two counts.
def header(+total: U32, +unique: U32, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle(J.Frame.clear_background(frame, J.Color.RAYWHITE()), 0.0, 0.0, 800.0, 70.0, J.Color.BLACK())
  f2 = label(J.Text.format("Total codepoints contained in provided text: %i", [J.TextInt{total}]), 10.0, f1)
  label(J.Text.format("Total codepoints required for font atlas (duplicates excluded): %i", [J.TextInt{unique}]), 40.0, f2)

def draw.done(+core: J.Core, +atlas: Bool, +at: U32, +ok: Bool, +total: U32, +unique: U32, r: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  (frame, font) = r
  (core, (State{Some{font}, atlas, at, ok, total, unique}, J.Draw.text(frame, "Press SPACE to toggle font atlas view!", 10.0, (450.0 - 30.0 : F32), 20.0, J.Color.GRAY())))

def draw.lined(+w: U32, +h: U32, r: J.Frame & J.Font) -> J.Frame & J.Font:
  (frame, font) = r
  (J.Draw.rectangle_lines(frame, 150.0, 100.0, U32.to_f32(w), U32.to_f32(h), J.Color.BLACK()), font)

# DrawTexture(font.texture, 150, 100, BLACK); DrawRectangleLines(150, 100, font.texture.width, font.texture.height, BLACK).
def draw.atlas.sized(frame: J.Frame, font: J.Font, size: U32 & U32) -> J.Frame & J.Font:
  (+w, +h) = size
  draw.lined(w, h, J.Draw.font_texture(frame, font, 150.0, 100.0, J.Color.BLACK()))

def draw.atlas(frame: J.Frame, r: J.Font & (U32 & U32)) -> J.Frame & J.Font:
  (font, size) = r
  draw.atlas.sized(frame, font, size)

# The atlas, or DrawTextEx(font, text, (160, 110), 48, 5, BLACK) with SetTextLineSpacing(20).
def draw.shown(atlas: Bool, frame: J.Frame, font: J.Font) -> J.Frame & J.Font:
  match atlas:
    case True{}: draw.atlas(frame, J.Font.texture_size(font))
    case False{}: J.Draw.text_ex_spaced(20, frame, font, text(), M.Vector2{160.0, 110.0}, 48.0, 5.0, J.Color.BLACK())

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{font, +atlas, +at, +ok, +total, +unique} = state
  match font:
    case None{}: (core, (State{None{}, atlas, at, ok, total, unique}, J.Frame.refuse(frame)))
    case Some{f}: draw.done(core, atlas, at, ok, total, unique, draw.shown(atlas, header(total, unique, checked(ok, frame)), f))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# SetTextureFilter(font.texture, TEXTURE_FILTER_BILINEAR).
def filtered(result: Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> Maybe<J.Font>:
  match result:
    case Done{Some{f}}: Some{J.Font.set_filter(f, J.TextureFilter.TEXTURE_FILTER_BILINEAR())}
    case _: None{}

def setup.done(+core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> J.Core & (J.Frame & State):
  (frame, result) = r
  (J.Core.set_target_fps(core, 60), (frame, State{filtered(result), False{}, 0, True{}, counted(J.Codepoint.load(text()), 0), counted(deduped(), 0)}))

# After InitWindow(800, 450): LoadCodepoints(text), CodepointRemoveDuplicates,
# LoadFontEx("resources/DotGothic16-Regular.ttf", 36, codepointsNoDups,
# codepointsNoDupsCount), the filter, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State),
    J.Font.load_ex(frame, dir ++ "resources/DotGothic16-Regular.ttf", 36, deduped(), counted(deduped(), 0)), r => IO.pure(J.Core & (J.Frame & State), setup.done(core, r)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - codepoints loading", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
