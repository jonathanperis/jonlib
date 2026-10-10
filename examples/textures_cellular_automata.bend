# raylib [textures] example - cellular automata, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_cellular_automata.c
# (zlib/libpng, Copyright (c) 2025 Jordi Santonja (@JordSant)); see
# LICENSES/raylib.txt.
#
# An elementary cellular automaton drawn four lines a frame into an 800x400
# image whose texture is updated each time; the mouse toggles the rule's
# eight bits or picks one of ten presets, which restarts the image. The
# example reads the line above with GetImageColor; here the last computed
# line is kept as a list (1 for a cell the image holds black, where the red
# channel is below 5), which is what those reads return. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# previous: the cells of line - 1; cell: mouseInCell (0-7 rule cells, 8+ presets, 99 outside).
type State is Type:
  State{image: Maybe<J.Surface>, texture: Maybe<J.Texture>, rule: U32, line: U32, previous: +List<U32>, cell: U32}

def preset(index: U32) -> U32:
  match index:
    case 0: 18
    case 1: 30
    case 2: 60
    case 3: 86
    case 4: 102
    case 5: 124
    case 6: 126
    case 7: 150
    case 8: 182
    case _: 225

# Line 0: one black pixel at imageWidth/2.
def seed(n: Nat, +i: U32) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{Bool.pick(U32, U32.is_eq(i, 400), 1, 0), seed(p, (i + 1 : U32))}

def inside(+mouse: M.Vector2, +x: U32, +y: U32, +w: U32, +h: U32) -> Bool:
  M.Vector2{+mx, +my} = mouse
  (mx >= U32.to_f32(x) : F32) && (mx <= U32.to_f32((x + w : U32)) : F32) && (my >= U32.to_f32(y) : F32) && (my <= U32.to_f32((y + h : U32)) : F32)

# The first rule cell under the mouse: (drawRuleStartX - drawRuleGroupSpacing*i + drawRuleSpacing, 25), 14 wide.
def rule.cell(n: Nat, +i: U32, +mouse: M.Vector2) -> U32:
  match n:
    case 0n: 99
    case 1n+p: Bool.pick(U32, inside(mouse, (585 + 15 - 50 * i : U32), 25, 14, 14), i, rule.cell(p, (i + 1 : U32), mouse))

# The first preset under the mouse: (4 + 44*(i/2), 2 + 24*(i%2)), 42 by 22.
def preset.cell(n: Nat, +i: U32, +mouse: M.Vector2) -> U32:
  match n:
    case 0n: 99
    case 1n+p: Bool.pick(U32, inside(mouse, (4 + 44 * (i / 2) : U32), (2 + 24 * (i % 2) : U32), 42, 22), (i + 8 : U32), preset.cell(p, (i + 1 : U32), mouse))

def power(index: U32) -> U32:
  match index:
    case 0: 1
    case 1: 2
    case 2: 4
    case 3: 8
    case 4: 16
    case 5: 32
    case 6: 64
    case _: 128

# rule & (1 << index), as 0 or 1.
def bit(+rule: U32, +index: U32) -> U32:
  ((rule / power(index)) % 2 : U32)

# rule & (1 << (4*left + 2*center + right)).
def alive(+rule: U32, +left: U32, +center: U32, +right: U32) -> U32:
  bit(rule, (4 * left + 2 * center + right : U32))

# The cells 1..imageWidth - 2 of the next line from the three above each; the last cell stays white.
def next.cells(rest: +List<U32>, +rule: U32, +left: U32, +center: U32) -> +List<U32>:
  match rest:
    case Nil{}: Con{0, Nil{}}
    case Con{+right, more}: Con{alive(rule, left, center, right), next.cells(more, rule, center, right)}

# ComputeLine's values: the first cell stays white.
def next(previous: +List<U32>, +rule: U32) -> +List<U32>:
  match previous:
    case Con{+a, Con{+b, rest}}: Con{0, next.cells(rest, rule, a, b)}
    case _: Nil{}

def painted(inner: Bool, +value: U32, +i: U32, +line: U32, image: J.Surface) -> J.Surface:
  match inner:
    case False{}: image
    case True{}: J.Surface.draw_pixel(image, U32.to_f32(i), U32.to_f32(line), Bool.pick(U32, U32.is_eq(value, 1), J.Color.BLACK(), J.Color.RAYWHITE()))

# ImageDrawPixel(image, i, line, value? BLACK : RAYWHITE) for i = 1..imageWidth - 2.
def paint(cells: +List<U32>, +i: U32, +line: U32, image: J.Surface) -> J.Surface:
  match cells:
    case Nil{}: image
    case Con{+value, rest}: paint(rest, (i + 1 : U32), line, painted((i >= 1 : U32) && (i <= 798 : U32), value, i, line, image))

type Lines is Type:
  Lines{image: J.Surface, previous: +List<U32>}

# ComputeLine(&image, line + i, rule) for the n lines of this frame.
def lines(n: Nat, +rule: U32, +line: U32, image: J.Surface, +previous: +List<U32>) -> Lines:
  match n:
    case 0n: Lines{image, previous}
    case 1n+p: lines(p, rule, (line + 1 : U32), paint(next(previous, rule), 0, line, image), next(previous, rule))

def updated(result: Result<&1, &1, J.Texture & J.Surface.Error, J.Texture>) -> Maybe<J.Texture>:
  match result:
    case Fail{_}: None{}
    case Done{texture}: Some{texture}

def step.uploaded(+rule: U32, +line: U32, +previous: +List<U32>, +cell: U32, texture: J.Texture, pair: J.Surface & J.Surface) -> State:
  (image, copy) = pair
  State{Some{image}, updated(J.Texture.update(texture, copy)), rule, line, previous, cell}

# UpdateTexture(texture, image.data); line += linesUpdatedPerFrame.
def step.lines(+rule: U32, +line: U32, +cell: U32, texture: J.Texture, drawn: Lines) -> State:
  Lines{image, +previous} = drawn
  step.uploaded(rule, (line + 4 : U32), previous, cell, texture, J.Surface.copy(image))

# if (line < imageHeight): up to four lines, as long as line + i < imageHeight.
def step.at(growing: Bool, +rule: U32, +line: U32, +previous: +List<U32>, +cell: U32, image: J.Surface, texture: J.Texture) -> State:
  match growing:
    case False{}: State{Some{image}, Some{texture}, rule, line, previous, cell}
    case True{}: step.lines(rule, line, cell, texture, lines(U32.to_nat(U32.min(4, (400 - line : U32))), rule, line, image, previous))

# A click on a cell: ImageClearBackground(&image, RAYWHITE); ImageDrawPixel(&image, imageWidth/2, 0, BLACK).
def cleared(click: Bool, image: J.Surface) -> J.Surface:
  match click:
    case False{}: image
    case True{}: J.Surface.draw_pixel(J.Surface.clear(image, J.Color.RAYWHITE()), 400.0, 0.0, J.Color.BLACK())

def step(+click: Bool, +rule: U32, +line: U32, +previous: +List<U32>, +cell: U32, image: Maybe<J.Surface>, texture: Maybe<J.Texture>) -> State:
  match image texture:
    case Some{i} Some{t}: step.at((line < 400 : U32), rule, line, previous, cell, cleared(click, i), t)
    case _ _: State{None{}, None{}, rule, line, previous, cell}

# The mouse's cell; a left click on a rule cell flips that bit of the rule, on a preset takes its rule; both restart at line 1.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{image, texture, +rule, +line, +previous, _} = state
  +mouse = J.Input.get_mouse_position(core)
  +in_rule = rule.cell(8n, 0, mouse)
  +cell = Bool.pick(U32, (in_rule < 99 : U32), in_rule, preset.cell(10n, 0, mouse))
  +click = J.Input.is_mouse_button_pressed(core, 0) && (cell < 99 : U32)
  +flipped = Bool.pick(U32, U32.is_eq(bit(rule, U32.min(cell, 7)), 1), (rule - power(U32.min(cell, 7)) : U32), (rule + power(U32.min(cell, 7)) : U32))
  +picked = Bool.pick(U32, click, Bool.pick(U32, (cell < 8 : U32), flipped, preset((cell - 8 : U32))), rule)
  (core, step(click, picked, Bool.pick(U32, click, 1, line), Bool.pick(+List<U32>, click, seed(800n, 0), previous), cell, image, texture))

def label(text: Maybe<String>, +x: F32, +y: F32, +size: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, size, J.Color.GRAY())

def framed(shown: Bool, +rec: J.Rectangle, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: J.Draw.rectangle_lines_ex(frame, rec, 3.0, J.Color.RED())

def filled(shown: Bool, +x: U32, +y: U32, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: J.Draw.rectangle(frame, U32.to_f32(x), U32.to_f32(y), 10.0, 10.0, J.Color.BLACK())

# The presets: their number, a blue box and a red frame under the mouse.
def presets(n: Nat, +i: U32, +cell: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +x = (44 * (i / 2) : U32)
      +y = (24 * (i % 2) : U32)
      f1 = label(J.Text.format("%i", [J.TextInt{preset(i)}]), U32.to_f32((8 + x : U32)), U32.to_f32((4 + y : U32)), 20.0, frame)
      f2 = J.Draw.rectangle_lines(f1, U32.to_f32((4 + x : U32)), U32.to_f32((2 + y : U32)), 42.0, 22.0, J.Color.BLUE())
      presets(p, (i + 1 : U32), cell, framed(U32.is_eq(cell, (i + 8 : U32)), J.Rectangle{(2.0 + (42.0 + 2.0) * U32.to_f32((i / 2 : U32)) : F32), ((22.0 + 2.0) * U32.to_f32((i % 2 : U32)) : F32), (42.0 + 4.0 : F32), (22.0 + 4.0 : F32)}, f2))

# The three cells of a neighbourhood: bit 4 >> j of i.
def pattern(n: Nat, +i: U32, +j: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +x = (585 + 15 * j - 50 * i : U32)
      pattern(p, i, (j + 1 : U32), filled(U32.is_eq(bit(i, (2 - j : U32)), 1), (x + 2 : U32), 12, J.Draw.rectangle_lines(frame, U32.to_f32(x), 10.0, 14.0, 14.0, J.Color.GRAY())))

# The eight neighbourhoods with the rule's bit under each and a red frame under the mouse.
def rules(n: Nat, +i: U32, +rule: U32, +cell: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +x = (585 + 15 - 50 * i : U32)
      f1 = J.Draw.rectangle_lines(pattern(3n, i, 0, frame), U32.to_f32(x), 25.0, 14.0, 14.0, J.Color.BLUE())
      f2 = filled(U32.is_eq(bit(rule, i), 1), (x + 2 : U32), 27, f1)
      rules(p, (i + 1 : U32), rule, cell, framed(U32.is_eq(cell, i), J.Rectangle{(U32.to_f32(x) - 2.0 : F32), (25.0 - 2.0 : F32), (14.0 + 4.0 : F32), (14.0 + 4.0 : F32)}, f2))

def draw.shown(+core: J.Core, image: Maybe<J.Surface>, +rule: U32, +line: U32, +previous: +List<U32>, +cell: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{image, Some{texture}, rule, line, previous, cell},
    label(J.Text.format("RULE: %i", [J.TextInt{rule}]), (585.0 + 15.0 * 4.0 : F32), 11.0, 30.0, rules(8n, 0, rule, cell, presets(10n, 0, cell, frame)))))

# DrawTexture(texture, 0, screenHeight - imageHeight, WHITE).
def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{image, texture, +rule, +line, +previous, +cell} = state
  match texture:
    case None{}: (core, (State{image, None{}, rule, line, previous, cell}, J.Frame.refuse(frame)))
    case Some{t}: draw.shown(core, image, rule, line, previous, cell, J.Draw.texture(J.Frame.clear_background(frame, J.Color.RAYWHITE()), t, 0.0, (450.0 - 400.0 : F32), J.Color.WHITE()))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.uploaded(+core: J.Core, image: J.Surface, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{Some{image}, texture, 30, 1, seed(800n, 0), 99}))

def setup.copied(+core: J.Core, frame: J.Frame, pair: J.Surface & J.Surface) -> J.Core & (J.Frame & State):
  (image, copy) = pair
  setup.uploaded(core, image, J.Texture.load_from_image(frame, copy))

def setup.image(+core: J.Core, frame: J.Frame, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  match image:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, None{}, 30, 1, Nil{}, 99}))
    case Some{i}: setup.copied(core, frame, J.Surface.copy(J.Surface.draw_pixel(i, 400.0, 0.0, J.Color.BLACK())))

# After InitWindow(800, 450): GenImageColor(800, 400, RAYWHITE) with its seed pixel, its texture, rule 30, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.image(core, frame, J.Surface.create(800, 400, J.Color.RAYWHITE()))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - cellular automata", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
