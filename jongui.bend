# Jongui - zlib license, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raygui v5.0-dev (raygui.h as raylib 6.0's
# examples ship it; zlib/libpng, Copyright (c) 2014-2026 Ramon Santamaria
# (@raysan5)); see LICENSES/raygui.txt. Jongui is to raygui what Jonlib is to
# raylib: the controls' update and drawing code in raygui's F32 and C int
# order, with raygui's global state as an explicit Gui value.
#
# Delivered: the style table (GuiLoadStyleDefault, GuiSetStyle, GuiGetStyle),
# the global state (GuiEnable, GuiDisable, GuiLock, GuiUnlock, GuiIsLocked,
# GuiSetState, GuiGetState, GuiSetAlpha), GuiGetTextWidth, GuiLabel,
# GuiButton, GuiCheckBox, GuiToggle, GuiToggleGroup, GuiSlider and
# GuiSliderBar, with the default font,
# TEXT_WRAP_NONE and no icons. Texts with an icon prefix ("#id#") and the
# other wrap modes mark the frame undefined. See docs/GUI.md.
import Base
import ./jonlib.bend as J
import ./jonmath.bend as M
import ./src/fonts.bend as FontCore
import ./src/text.bend as TextCore

# raygui's globals: guiState, guiLocked, guiAlpha, the slider drag
# (guiControlExclusiveMode and guiControlExclusiveRec) and guiStyle, 16
# controls of 24 properties each.
type Gui is Data:
  Gui{state: U32, locked: Bool, alpha: F32, exclusive: Bool, exclusive_rec: J.Rectangle, style: +List<U32>}

# guiStyle after GuiLoadStyleDefault (printed by raygui itself).
def Gui.style.default() -> +List<U32>:
  [2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 1, 0, 10, 1, 2427172351, 4126537215, 5, 1, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 4, 1, 0, 16, 1, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 4, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 4, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 1, 0, 32, 2, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 1, 0, 16, 2, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 0, 0, 24, 2, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 1, 0, 28, 2, 12, 1, 0, 1, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 0, 1, 0, 8, 16, 8, 8, 2, 0, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 0, 0, 1, 0, 6, 0, 0, 16, 0, 12, 0, 0, 
    2206434303, 3385444863, 1751673087, 1538447871, 3387948799, 1822145791, 76728319, 2548629503, 915124223, 3049374463, 3874089471, 2931276031, 1, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

def Gui.new() -> Gui:
  Gui{0, False{}, 1.0, False{}, J.Rectangle{0.0, 0.0, 0.0, 0.0}, Gui.style.default()}

# -----------------------------------------------------------------------------
# Controls, properties, states and alignments (raygui's enums)

def Gui.DEFAULT() -> U32:
  0

def Gui.LABEL() -> U32:
  1

def Gui.BUTTON() -> U32:
  2

def Gui.TOGGLE() -> U32:
  3

def Gui.SLIDER() -> U32:
  4

def Gui.PROGRESSBAR() -> U32:
  5

def Gui.CHECKBOX() -> U32:
  6

def Gui.BORDER_WIDTH() -> U32:
  12

def Gui.TEXT_PADDING() -> U32:
  13

def Gui.TEXT_ALIGNMENT() -> U32:
  14

def Gui.TEXT_SIZE() -> U32:
  16

def Gui.TEXT_SPACING() -> U32:
  17

def Gui.TEXT_LINE_SPACING() -> U32:
  20

def Gui.TEXT_ALIGNMENT_VERTICAL() -> U32:
  21

def Gui.TEXT_WRAP_MODE() -> U32:
  22

def Gui.SLIDER_WIDTH() -> U32:
  16

def Gui.SLIDER_PADDING() -> U32:
  17

def Gui.CHECK_PADDING() -> U32:
  16

def Gui.STATE_NORMAL() -> U32:
  0

def Gui.STATE_FOCUSED() -> U32:
  1

def Gui.STATE_PRESSED() -> U32:
  2

def Gui.STATE_DISABLED() -> U32:
  3

def Gui.TEXT_ALIGN_LEFT() -> U32:
  0

def Gui.TEXT_ALIGN_CENTER() -> U32:
  1

def Gui.TEXT_ALIGN_RIGHT() -> U32:
  2

# -----------------------------------------------------------------------------
# Style and global state

def Gui.head(values: +List<U32>) -> U32:
  match values:
    case Con{value, _}: value
    case Nil{}: 0

# GuiGetStyle(control, property): 0 outside the table.
def Gui.get_style(gui: Gui, +control: U32, +property: U32) -> U32:
  Gui{_, _, _, _, _, style} = gui
  Gui.head(List.drop(&2, U32, style, U32.to_nat((control * 24 + property : U32))))

def Gui.style.put(style: +List<U32>, +i: U32, +control: U32, +property: U32, +value: U32) -> +List<U32>:
  match style:
    case Nil{}: Nil{}
    case Con{+v, rest}:
      +hit = U32.is_eq((i % 24 : U32), property) && (U32.is_eq((i / 24 : U32), control) || (U32.is_eq(control, 0) && (property < 16 : U32)))
      Con{Bool.pick(U32, hit, value, v), Gui.style.put(rest, (i + 1 : U32), control, property, value)}

# GuiSetStyle(control, property, value): a DEFAULT base property (below 16)
# reaches every control. Nothing changes outside the 16x24 table.
def Gui.set_style(gui: Gui, +control: U32, +property: U32, +value: U32) -> Gui:
  Gui{state, locked, alpha, exclusive, rec, style} = gui
  Gui{state, locked, alpha, exclusive, rec, Gui.style.put(style, 0, control, property, value)}

# GuiEnable: STATE_DISABLED becomes STATE_NORMAL.
def Gui.enable(gui: Gui) -> Gui:
  Gui{+state, locked, alpha, exclusive, rec, style} = gui
  Gui{Bool.pick(U32, U32.is_eq(state, 3), 0, state), locked, alpha, exclusive, rec, style}

# GuiDisable: STATE_NORMAL becomes STATE_DISABLED.
def Gui.disable(gui: Gui) -> Gui:
  Gui{+state, locked, alpha, exclusive, rec, style} = gui
  Gui{Bool.pick(U32, U32.is_eq(state, 0), 3, state), locked, alpha, exclusive, rec, style}

def Gui.lock(gui: Gui) -> Gui:
  Gui{state, _, alpha, exclusive, rec, style} = gui
  Gui{state, True{}, alpha, exclusive, rec, style}

def Gui.unlock(gui: Gui) -> Gui:
  Gui{state, _, alpha, exclusive, rec, style} = gui
  Gui{state, False{}, alpha, exclusive, rec, style}

def Gui.is_locked(gui: Gui) -> Bool:
  Gui{_, locked, _, _, _, _} = gui
  locked

def Gui.set_state(gui: Gui, state: U32) -> Gui:
  Gui{_, locked, alpha, exclusive, rec, style} = gui
  Gui{state, locked, alpha, exclusive, rec, style}

def Gui.get_state(gui: Gui) -> U32:
  Gui{state, _, _, _, _, _} = gui
  state

# GuiSetAlpha: clamped to [0, 1].
def Gui.set_alpha(gui: Gui, +alpha: F32) -> Gui:
  Gui{state, locked, _, exclusive, rec, style} = gui
  Gui{state, locked, Bool.pick(F32, (alpha < 0.0 : F32), 0.0, Bool.pick(F32, (alpha > 1.0 : F32), 1.0, alpha)), exclusive, rec, style}

# A style value as the C int raygui reads it, in F32 (exact below 2^24).
def Gui.style.f32(+gui: Gui, +control: U32, +property: U32) -> F32:
  U32.to_f32(Gui.get_style(gui, control, property))

def Gui.fade(+color: U32, +alpha: F32) -> U32:
  ((color .&. 4294967040) .|. (F32.to_u32(F32.trunc((U32.to_f32((color .&. 255 : U32)) * alpha : F32))) .&. 255) : U32)

# GuiFade(GetColor(style), guiAlpha): the alpha byte times guiAlpha, truncated.
def Gui.color(+gui: Gui, +control: U32, +property: U32) -> U32:
  Gui{_, _, +alpha, _, _, _} = gui
  Gui.fade(Gui.get_style(gui, control, property), alpha)

# -----------------------------------------------------------------------------
# Text: GuiGetTextWidth and GuiDrawText with the default font

# The glyph's width as raygui measures and advances it: advanceX*scale, or
# the atlas rectangle's width*scale when advanceX is 0.
def Gui.glyph.scaled(glyph: FontCore.Glyph, +scale: F32) -> F32:
  FontCore.Glyph{_, _, _, +advance, _, _, +width, _} = glyph
  Bool.pick(F32, U32.is_eq(advance, 0), (width * scale : F32), (FontCore.int.f32(advance) * scale : F32))

def Gui.glyph.width(+cp: U32, +scale: F32) -> F32:
  Gui.glyph.scaled(FontCore.Face.glyph(FontCore.default.face(), cp), scale)

def Gui.text.sum(cps: +List<U32>, +scale: F32, +spacing: F32, +acc: F32) -> F32:
  match cps:
    case Nil{}: acc
    case Con{+cp, rest}: Gui.text.sum(rest, scale, spacing, (acc + (Gui.glyph.width(cp, scale) + spacing) : F32))

# The bytes of a line: up to the first '\n' (and, when drawn, '\r').
def Gui.line.bytes(bytes: +List<U32>, +stop_cr: Bool) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: Bool.pick(+List<U32>, U32.is_eq(b, 10) || (stop_cr && U32.is_eq(b, 13)), Nil{}, Con{b, Gui.line.bytes(rest, stop_cr)})

# TEXT_SIZE/guiFont.baseSize.
def Gui.scale(+gui: Gui) -> F32:
  (Gui.style.f32(gui, 0, 16) / 10.0 : F32)

# GuiGetTextWidth of bytes without an icon prefix: the first line's glyph
# widths plus TEXT_SPACING each (at most 256 bytes), truncated to an int.
def Gui.width.bytes(+gui: Gui, bytes: +List<U32>) -> F32:
  F32.trunc(Gui.text.sum(TextCore.codepoints(List.take(&2, U32, Gui.line.bytes(bytes, False{}), 256n)), Gui.scale(gui), Gui.style.f32(gui, 0, 17), 0.0))

def Gui.first(bytes: +List<U32>) -> U32:
  match bytes:
    case Con{b, _}: b
    case Nil{}: 0

# GuiGetTextWidth(text) as a C int in F32. None for an icon prefix (a text
# starting with '#').
def Gui.get_text_width(+gui: Gui, text: String) -> Maybe<F32>:
  +bytes = TextCore.bytes(text)
  Bool.pick(Maybe<F32>, U32.is_eq(Gui.first(bytes), 35), None{}, Some{Gui.width.bytes(gui, bytes)})

def Gui.empty(bytes: +List<U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case Con{_, _}: False{}

# GetTextLines: the text split after each '\n' that is not its last byte (a
# final '\n' stays in its line, where every reader stops at it).
def Gui.lines.go(bytes: +List<U32>, +current: +List<U32>) -> +List<+List<U32>>:
  match bytes:
    case Nil{}: [List.reverse(&2, U32, current)]
    case Con{+b, +rest}:
      +split = U32.is_eq(b, 10) && Bool.not(Gui.empty(rest))
      +tail = Gui.lines.go(rest, Bool.pick(+List<U32>, split, Nil{}, Con{b, current}))
      Bool.pick(+List<+List<U32>>, split, Con{List.reverse(&2, U32, current), tail}, tail)

# DrawTextCodepoint(guiFont, codepoint, (x, y), TEXT_SIZE, tint) with the default font.
def Gui.glyph.draw(frame: J.Frame, +cp: U32, +x: F32, +y: F32, +size: F32, +tint: U32) -> J.Frame:
  J.Frame.draw(frame, FontCore.codepoint(FontCore.default.face(), 1, 128.0, 128.0, cp, x, y, size, tint))

def Gui.dot(visible: Bool, frame: J.Frame, +x: F32, +y: F32, +size: F32, +tint: U32) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: Gui.glyph.draw(frame, 46, x, y, size, tint)

# The dots of an overflowing line: at j = 0, ellipsis/3, ... while j < ellipsis
# (at most five for a positive step).
def Gui.dots(n: Nat, +j: F32, +step: F32, +ellipsis: F32, +x: F32, +y: F32, +size: F32, +tint: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: Gui.dots(p, (j + step : F32), step, ellipsis, x, y, size, tint, Gui.dot((j < ellipsis : F32), frame, (x + j : F32), y, size, tint))

# The C loop never ends for a step of 0 (an ellipsis narrower than 3).
def Gui.ellipsis(endless: Bool, +ellipsis: F32, +x: F32, +y: F32, +size: F32, +tint: U32, frame: J.Frame) -> J.Frame:
  match endless:
    case True{}: J.Frame.refuse(frame)
    case False{}: Gui.dots(6n, 0.0, F32.trunc((ellipsis / 3.0 : F32)), ellipsis, x, y, size, tint, frame)

type Gui.Line is Data:
  GuiLine{x: F32, y: F32, width: F32, text_width: F32, ellipsis: F32, scale: F32, spacing: F32, size: F32, tint: U32}

def Gui.glyphs.overflow(overflow: Bool, kind: U32) -> Bool:
  match kind:
    case 2: True{}
    case _: overflow

# kind 0: nothing; 1: the glyph; 2: the ellipsis.
def Gui.glyphs.one(kind: U32, +cp: U32, +x: F32, +y: F32, +offset: F32, +ellipsis: F32, +size: F32, +tint: U32, frame: J.Frame) -> J.Frame:
  match kind:
    case 0: frame
    case 1: Gui.glyph.draw(frame, cp, (x + offset : F32), y, size, tint)
    case _: Gui.ellipsis((F32.trunc((ellipsis / 3.0 : F32)) < 1.0 : F32), ellipsis, (x + offset : F32), y, size, tint, frame)

# One glyph of a line: drawn unless it is a space or a tab; a line wider than
# its bounds stops at the ellipsis.
def Gui.glyphs(cps: +List<U32>, +line: Gui.Line, +offset: F32, +overflow: Bool, frame: J.Frame) -> J.Frame:
  match cps:
    case Nil{}: frame
    case Con{+cp, rest}:
      GuiLine{+x, +y, +width, +text_width, +ellipsis, +scale, +spacing, +size, +tint} = line
      +glyph = Gui.glyph.width(cp, scale)
      +blank = U32.is_eq(cp, 32) || U32.is_eq(cp, 9)
      +wide = (text_width > width : F32)
      +fits = (offset <= ((width - glyph) - 0.0) - ellipsis : F32)
      +kind = Bool.pick(U32, blank, 0, Bool.pick(U32, Bool.not(wide), 1, Bool.pick(U32, fits, 1, Bool.pick(U32, overflow, 0, 2))))
      Gui.glyphs(rest, line, (offset + (glyph + spacing) : F32), Gui.glyphs.overflow(overflow, kind), Gui.glyphs.one(kind, cp, x, y, offset, ellipsis, size, tint, frame))

# The x of a line by its alignment, pixel-aligned ((float)(int)x).
def Gui.line.x(alignment: U32, +bx: F32, +bw: F32, +text_width: F32) -> F32:
  match alignment:
    case 0: bx
    case 1: (bx + bw / 2.0 - F32.trunc((text_width / 2.0 : F32)) : F32)
    case _: (bx + bw - text_width : F32)

# (int)h % 2, raygui's pixel-perfect vertical offset.
def Gui.pixel(+bh: F32) -> F32:
  (F32.trunc(bh) - 2.0 * F32.trunc((F32.trunc(bh) / 2.0 : F32)) : F32)

# The y of a line by TEXT_ALIGNMENT_VERTICAL (TOP, MIDDLE, BOTTOM).
def Gui.line.y(vertical: U32, +by: F32, +bh: F32, +offset: F32, +total: F32) -> F32:
  match vertical:
    case 0: (by + offset : F32)
    case 1: (by + offset + bh / 2.0 - total / 2.0 + Gui.pixel(bh) : F32)
    case _: (by + offset + bh - total + Gui.pixel(bh) : F32)

def Gui.text.lines(lines: +List<+List<U32>>, +gui: Gui, +bounds: J.Rectangle, +alignment: U32, +tint: U32, +offset: F32, +total: F32, frame: J.Frame) -> J.Frame:
  match lines:
    case Nil{}: frame
    case Con{+line, rest}:
      J.Rectangle{+bx, +by, +bw, +bh} = bounds
      +size = Gui.style.f32(gui, 0, 16)
      +text_width = Gui.width.bytes(gui, line)
      +empty = U32.is_eq(Gui.first(line), 0)
      +x = Bool.pick(F32, (text_width > bw : F32) && Bool.not(empty), bx, Gui.line.x(alignment, bx, bw, text_width))
      +y = Gui.line.y(Gui.get_style(gui, 0, 21), by, bh, offset, total)
      +spec = {GuiLine{F32.trunc(x), F32.trunc(y), bw, text_width, Gui.width.bytes(gui, [46, 46, 46]), Gui.scale(gui), Gui.style.f32(gui, 0, 17), size, tint} : Gui.Line}
      Gui.text.lines(rest, gui, bounds, alignment, tint, (offset + (size + Gui.style.f32(gui, 0, 20)) : F32), total,
        Gui.glyphs(TextCore.codepoints(Gui.line.bytes(line, True{})), spec, 0.0, False{}, frame))

def Gui.has_icon(lines: +List<+List<U32>>) -> Bool:
  match lines:
    case Nil{}: False{}
    case Con{+line, rest}: U32.is_eq(Gui.first(line), 35) || Gui.has_icon(rest)

def Gui.count(lines: +List<+List<U32>>, +n: F32) -> F32:
  match lines:
    case Nil{}: n
    case Con{_, rest}: Gui.count(rest, (n + 1.0 : F32))

def Gui.text.checked(refused: Bool, +lines: +List<+List<U32>>, +gui: Gui, +bounds: J.Rectangle, +alignment: U32, +tint: U32, frame: J.Frame) -> J.Frame:
  match refused:
    case True{}: J.Frame.refuse(frame)
    case False{}:
      +count = Gui.count(lines, 0.0)
      +total = (count * Gui.style.f32(gui, 0, 16) + (count - 1.0) * Gui.style.f32(gui, 0, 20) : F32)
      Gui.text.lines(lines, gui, bounds, alignment, tint, 0.0, total, frame)

def Gui.draw_text.lines(+lines: +List<+List<U32>>, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +alignment: U32, +tint: U32) -> J.Frame:
  Gui.text.checked(Gui.has_icon(lines) || U32.is_ne(Gui.get_style(gui, 0, 22), 0), lines, gui, bounds, alignment, tint, frame)

# GuiDrawText(text, bounds, alignment, tint): nothing for an empty text. The
# frame is undefined for an icon prefix or a wrap mode.
def Gui.draw_text.bytes(+bytes: +List<U32>, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +alignment: U32, +tint: U32) -> J.Frame:
  match bytes:
    case Nil{}: frame
    case Con{b, rest}: Gui.draw_text.lines(Gui.lines.go(Con{b, rest}, Nil{}), gui, frame, bounds, alignment, tint)

def Gui.draw_text(+gui: Gui, frame: J.Frame, text: String, +bounds: J.Rectangle, +alignment: U32, +tint: U32) -> J.Frame:
  Gui.draw_text.bytes(TextCore.bytes(text), gui, frame, bounds, alignment, tint)

def Gui.draw_text.maybe(+gui: Gui, frame: J.Frame, text: Maybe<String>, +bounds: J.Rectangle, +alignment: U32, +tint: U32) -> J.Frame:
  match text:
    case None{}: frame
    case Some{t}: Gui.draw_text(gui, frame, t, bounds, alignment, tint)

# -----------------------------------------------------------------------------
# GuiDrawRectangle and GetTextBounds

def Gui.border(visible: Bool, frame: J.Frame, +x: F32, +y: F32, +w: F32, +h: F32, +b: F32, +color: U32) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}:
      f1 = J.Draw.rectangle(frame, x, y, w, b, color)
      f2 = J.Draw.rectangle(f1, x, (y + b : F32), b, (h - 2.0 * b : F32), color)
      f3 = J.Draw.rectangle(f2, (x + w - b : F32), (y + b : F32), b, (h - 2.0 * b : F32), color)
      J.Draw.rectangle(f3, x, (y + h - b : F32), w, b, color)

def Gui.fill(visible: Bool, frame: J.Frame, +x: F32, +y: F32, +w: F32, +h: F32, +color: U32) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: J.Draw.rectangle(frame, x, y, w, h, color)

# GuiDrawRectangle(rec, borderWidth, borderColor, color), the colors already
# faded: the fill when its alpha is above 0, then four border rectangles, all
# with (int) coordinates.
def Gui.draw_rectangle(frame: J.Frame, +rec: J.Rectangle, +border: U32, +border_color: U32, +color: U32) -> J.Frame:
  J.Rectangle{+rx, +ry, +rw, +rh} = rec
  +x = F32.trunc(rx)
  +y = F32.trunc(ry)
  +w = F32.trunc(rw)
  +h = F32.trunc(rh)
  Gui.border((border > 0 : U32), Gui.fill(((color .&. 255) > 0 : U32), frame, x, y, w, h, color), x, y, w, h, U32.to_f32(border), border_color)

# GetTextBounds(control, bounds).
def Gui.text_bounds(+gui: Gui, +control: U32, +bounds: J.Rectangle) -> J.Rectangle:
  J.Rectangle{+x, +y, +w, +h} = bounds
  +border = Gui.style.f32(gui, control, 12)
  +padding = Gui.style.f32(gui, control, 13)
  +tx = (x + border : F32)
  J.Rectangle{Bool.pick(F32, U32.is_eq(Gui.get_style(gui, control, 14), 2), (tx - padding : F32), (tx + padding : F32)), (y + border + padding : F32),
    (w - 2.0 * border - 2.0 * padding : F32), (h - 2.0 * border - 2.0 * padding : F32)}

# -----------------------------------------------------------------------------
# Pointer (GUI_POINTER_POSITION, GUI_BUTTON_DOWN, GUI_BUTTON_RELEASED)

def Gui.pad(button: Maybe<Bool>) -> Bool:
  match button:
    case Some{b}: b
    case None{}: False{}

def Gui.down(+core: J.Core) -> Bool:
  J.Input.is_mouse_button_down(core, 0) || Gui.pad(J.Input.is_gamepad_button_down(core, 0, 7))

def Gui.released(+core: J.Core) -> Bool:
  J.Input.is_mouse_button_released(core, 0) || Gui.pad(J.Input.is_gamepad_button_released(core, 0, 7))

# Whether a control reacts: not STATE_DISABLED and not locked.
def Gui.active(+gui: Gui) -> Bool:
  Gui{+state, +locked, _, _, _, _} = gui
  U32.is_ne(state, 3) && Bool.not(locked)

def Gui.exclusive(gui: Gui) -> Bool:
  Gui{_, _, _, exclusive, _, _} = gui
  exclusive

# The state a hovered control takes: PRESSED while the button is down, else FOCUSED.
def Gui.hover(+core: J.Core) -> U32:
  Bool.pick(U32, Gui.down(core), 2, 1)

# -----------------------------------------------------------------------------
# GuiLabel, GuiButton, GuiCheckBox

# GuiLabel(bounds, text).
def Gui.label(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, text: String) -> J.Frame:
  Gui.draw_text(gui, frame, text, Gui.text_bounds(gui, 1, bounds), Gui.get_style(gui, 1, 14), Gui.color(gui, 1, (2 + Gui.get_state(gui) * 3 : U32)))

# GuiButton(bounds, text): the frame and whether the button was clicked (the
# pointer released over it).
def Gui.button(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: String) -> J.Frame & Bool:
  +over = Gui.active(gui) && Bool.not(Gui.exclusive(gui)) && J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
  +state = Bool.pick(U32, over, Gui.hover(core), Gui.get_state(gui))
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 2, 12), Gui.color(gui, 2, (state * 3 : U32)), Gui.color(gui, 2, (1 + state * 3 : U32)))
  (Gui.draw_text(gui, f1, text, Gui.text_bounds(gui, 2, bounds), Gui.get_style(gui, 2, 14), Gui.color(gui, 2, (2 + state * 3 : U32))), over && Gui.released(core))

def Gui.check.mark(checked: Bool, +gui: Gui, +state: U32, +bounds: J.Rectangle, frame: J.Frame) -> J.Frame:
  match checked:
    case False{}: frame
    case True{}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +inset = (Gui.style.f32(gui, 6, 12) + Gui.style.f32(gui, 6, 16) : F32)
      Gui.draw_rectangle(frame, J.Rectangle{(x + Gui.style.f32(gui, 6, 12) + Gui.style.f32(gui, 6, 16) : F32), (y + Gui.style.f32(gui, 6, 12) + Gui.style.f32(gui, 6, 16) : F32),
        (w - 2.0 * inset : F32), (h - 2.0 * inset : F32)}, 0, 0, Gui.color(gui, 6, (2 + state * 3 : U32)))

def Gui.check.text(width: Maybe<F32>, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: String, +checked: Bool) -> J.Frame & (Bool & Bool):
  match width:
    case None{}: (J.Frame.refuse(frame), (checked, False{}))
    case Some{+measured}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +padding = Gui.style.f32(gui, 6, 13)
      +left = U32.is_eq(Gui.get_style(gui, 6, 14), 0)
      +tw = (measured + 2.0 : F32)
      +tx = Bool.pick(F32, left, (x - tw - padding : F32), (x + w + padding : F32))
      +ty = (y + h / 2.0 - F32.trunc((Gui.style.f32(gui, 0, 16) / 2.0 : F32)) : F32)
      +total = {J.Rectangle{Bool.pick(F32, left, tx, x), y, (w + tw + padding : F32), h} : J.Rectangle}
      +over = Gui.active(gui) && Bool.not(Gui.exclusive(gui)) && J.Collision.point_rec(J.Input.get_mouse_position(core), total)
      +state = Bool.pick(U32, over, Gui.hover(core), Gui.get_state(gui))
      +clicked = over && Gui.released(core)
      +now = Bool.pick(Bool, clicked, Bool.not(checked), checked)
      f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 6, 12), Gui.color(gui, 6, (state * 3 : U32)), 0)
      (Gui.draw_text(gui, Gui.check.mark(now, gui, state, bounds, f1), text, J.Rectangle{tx, ty, tw, Gui.style.f32(gui, 0, 16)},
        Bool.pick(U32, U32.is_eq(Gui.get_style(gui, 6, 14), 2), 0, 2), Gui.color(gui, 1, (2 + state * 3 : U32))), (now, clicked))

# GuiCheckBox(bounds, text, &checked): the frame, the checked flag and
# whether it changed.
def Gui.check_box(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +text: String, +checked: Bool) -> J.Frame & (Bool & Bool):
  Gui.check.text(Gui.get_text_width(gui, text), gui, core, frame, bounds, text, checked)

# -----------------------------------------------------------------------------
# GuiToggle and GuiToggleGroup

# The toggle's update: 0 untouched, 1 pressed, 2 released over it (it flips
# and draws as STATE_NORMAL), 3 hovered.
def Gui.toggle.kind(+gui: Gui, +core: J.Core, +bounds: J.Rectangle) -> U32:
  +over = Gui.active(gui) && Bool.not(Gui.exclusive(gui)) && J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
  Bool.pick(U32, over, Bool.pick(U32, Gui.down(core), 1, Bool.pick(U32, Gui.released(core), 2, 3)), 0)

def Gui.toggle.state(kind: U32, +state: U32) -> U32:
  match kind:
    case 0: state
    case 1: 2
    case 2: 0
    case _: 1

# The style property of a toggle part (0 border, 1 base, 2 text): the pressed
# colors for an active toggle in STATE_NORMAL, else the state's.
def Gui.toggle.property(+part: U32, +state: U32, +active: Bool) -> U32:
  Bool.pick(U32, U32.is_eq(state, 0) && active, (6 + part : U32), (part + state * 3 : U32))

def Gui.toggle.bytes(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +bytes: +List<U32>, +active: Bool) -> J.Frame & Bool:
  +kind = Gui.toggle.kind(gui, core, bounds)
  +state = Gui.toggle.state(kind, Gui.get_state(gui))
  +now = Bool.pick(Bool, U32.is_eq(kind, 2), Bool.not(active), active)
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 3, 12), Gui.color(gui, 3, Gui.toggle.property(0, state, now)), Gui.color(gui, 3, Gui.toggle.property(1, state, now)))
  (Gui.draw_text.bytes(bytes, gui, f1, Gui.text_bounds(gui, 3, bounds), Gui.get_style(gui, 3, 14), Gui.color(gui, 3, Gui.toggle.property(2, state, now))), now)

# GuiToggle(bounds, text, &active): the frame and the active flag (flipped
# when the pointer is released over the toggle).
def Gui.toggle(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: String, +active: Bool) -> J.Frame & Bool:
  Gui.toggle.bytes(gui, core, frame, bounds, TextCore.bytes(text), active)

# GuiTextSplit: one item per ';' (the delimiter) or '\n', which also starts a new row.
type Gui.Item is Data:
  GuiItem{row: U32, bytes: +List<U32>}

def Gui.split(bytes: +List<U32>, +delimiter: U32, +row: U32, +current: +List<U32>) -> +List<Gui.Item>:
  match bytes:
    case Nil{}: [GuiItem{row, List.reverse(&2, U32, current)}]
    case Con{+b, +rest}:
      +newline = U32.is_eq(b, 10)
      +cut = newline || U32.is_eq(b, delimiter)
      +tail = Gui.split(rest, delimiter, Bool.pick(U32, newline, (row + 1 : U32), row), Bool.pick(+List<U32>, cut, Nil{}, Con{b, current}))
      Bool.pick(+List<Gui.Item>, cut, Con{GuiItem{row, List.reverse(&2, U32, current)}, tail}, tail)

type Gui.Group is Type:
  GuiGroup{frame: J.Frame, active: U32}

def Gui.group.toggled(+i: U32, +active: U32, +selected: Bool, r: J.Frame & Bool) -> Gui.Group:
  (frame, +on) = r
  GuiGroup{frame, Bool.pick(U32, Bool.not(selected) && on, i, active)}

def Gui.group.next(+place: J.Rectangle, +padding: F32) -> J.Rectangle:
  J.Rectangle{+x, +y, +w, +h} = place
  J.Rectangle{(x + (w + padding) : F32), y, w, h}

def Gui.item.row(item: Gui.Item) -> U32:
  GuiItem{row, _} = item
  row

def Gui.item.bytes(item: Gui.Item) -> +List<U32>:
  GuiItem{_, bytes} = item
  bytes

# A new row returns to the first column, one height and GROUP_PADDING lower.
def Gui.group.place(+bounds: J.Rectangle, +first_x: F32, +padding: F32, +moved: Bool) -> J.Rectangle:
  J.Rectangle{+x, +y, +w, +h} = bounds
  J.Rectangle{Bool.pick(F32, moved, first_x, x), Bool.pick(F32, moved, (y + (h + padding) : F32), y), w, h}

# One item as a toggle, active when its index is; a toggle switched on takes the index.
def Gui.group.one(+bytes: +List<U32>, +gui: Gui, +core: J.Core, +place: J.Rectangle, +i: U32, group: Gui.Group) -> Gui.Group:
  GuiGroup{frame, +active} = group
  Gui.group.toggled(i, active, U32.is_eq(i, active), Gui.toggle.bytes(gui, core, frame, place, bytes, U32.is_eq(i, active)))

def Gui.group.items(items: +List<Gui.Item>, +gui: Gui, +core: J.Core, +first_x: F32, +bounds: J.Rectangle, +previous: U32, +i: U32, group: Gui.Group) -> Gui.Group:
  match items:
    case Nil{}: group
    case Con{+item, rest}:
      +row = Gui.item.row(item)
      +padding = Gui.style.f32(gui, 3, 16)
      +place = Gui.group.place(bounds, first_x, padding, U32.is_ne(previous, row))
      Gui.group.items(rest, gui, core, first_x, Gui.group.next(place, padding), row, (i + 1 : U32), Gui.group.one(Gui.item.bytes(item), gui, core, place, i, group))

def Gui.group.done(group: Gui.Group) -> J.Frame & U32:
  GuiGroup{frame, active} = group
  (frame, active)

# GuiToggleGroup(bounds, text, &active): the items of text (split at ';',
# a '\n' starting a new row) as toggles; the frame and the active index.
def Gui.toggle_group(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: String, +active: U32) -> J.Frame & U32:
  J.Rectangle{+x, _, _, _} = bounds
  Gui.group.done(Gui.group.items(Gui.split(TextCore.bytes(text), 59, 0, Nil{}), gui, core, x, bounds, 0, 0, GuiGroup{frame, active}))

# -----------------------------------------------------------------------------
# GuiSlider and GuiSliderBar

type Gui.Slide is Data:
  GuiSlide{gui: Gui, state: U32, value: F32}

# CHECK_BOUNDS_ID(bounds, guiControlExclusiveRec): equal as C ints.
def Gui.same(+a: J.Rectangle, +b: J.Rectangle) -> Bool:
  J.Rectangle{ax, ay, aw, ah} = a
  J.Rectangle{bx, by, bw, bh} = b
  F32.is_eq(F32.trunc(ax), F32.trunc(bx)) && F32.is_eq(F32.trunc(ay), F32.trunc(by)) && F32.is_eq(F32.trunc(aw), F32.trunc(bw)) && F32.is_eq(F32.trunc(ah), F32.trunc(bh))

def Gui.with_drag(+gui: Gui, +exclusive: Bool, +rec: J.Rectangle) -> Gui:
  Gui{state, locked, alpha, _, _, style} = gui
  Gui{state, locked, alpha, exclusive, rec, style}

# The value under the pointer: (max - min)*((mouse.x - bounds.x - sliderWidth/2)/(bounds.width - sliderWidth)) + min.
def Gui.slide.value(+mx: F32, +bx: F32, +bw: F32, +sw: U32, +min: F32, +max: F32) -> F32:
  ((max - min) * ((mx - bx - U32.to_f32((sw / 2 : U32))) / (bw - U32.to_f32(sw))) + min : F32)

def Gui.slide.clamp(+v: F32, +min: F32, +max: F32) -> F32:
  Bool.pick(F32, (v > max : F32), max, Bool.pick(F32, (v < min : F32), min, v))

# The update: dragging keeps following the pointer outside the bounds while
# the button stays down; a press inside starts a drag.
def Gui.slide.update(kind: U32, +gui: Gui, +pointed: F32, +bounds: J.Rectangle, +value: F32) -> Gui.Slide:
  match kind:
    case 0: GuiSlide{gui, Gui.get_state(gui), value}
    case 1: GuiSlide{gui, 2, pointed}
    case 2: GuiSlide{Gui.with_drag(gui, False{}, J.Rectangle{0.0, 0.0, 0.0, 0.0}), Gui.get_state(gui), value}
    case 3: GuiSlide{Gui.with_drag(gui, True{}, bounds), 2, pointed}
    case _: GuiSlide{gui, 1, value}

# 0: untouched; 1: dragging this slider; 2: the drag ended; 3: pressed
# inside; 4: hovered.
def Gui.slide.kind(+gui: Gui, +core: J.Core, +bounds: J.Rectangle, +slider: J.Rectangle) -> U32:
  Gui{_, _, _, +exclusive, +rec, _} = gui
  +down = Gui.down(core)
  +inside = J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
  +dragging = Bool.pick(U32, down, Bool.pick(U32, Gui.same(bounds, rec), 1, 0), 2)
  +free = Bool.pick(U32, inside, Bool.pick(U32, down, 3, 4), 0)
  Bool.pick(U32, exclusive, dragging, free)

def Gui.slide.text(width: Maybe<F32>, +gui: Gui, frame: J.Frame, text: String, +right: Bool, +bounds: J.Rectangle, +state: U32) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+tw}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +padding = Gui.style.f32(gui, 4, 13)
      +ty = (y + h / 2.0 - F32.trunc((Gui.style.f32(gui, 0, 16) / 2.0 : F32)) : F32)
      Gui.draw_text(gui, frame, text, J.Rectangle{Bool.pick(F32, right, (x + w + padding : F32), (x - tw - padding : F32)), ty, tw, Gui.style.f32(gui, 0, 16)},
        Bool.pick(U32, right, 0, 2), Gui.color(gui, 1, (2 + state * 3 : U32)))

def Gui.slide.label(+gui: Gui, frame: J.Frame, text: Maybe<String>, +right: Bool, +bounds: J.Rectangle, +state: U32) -> J.Frame:
  match text:
    case None{}: frame
    case Some{+t}: Gui.slide.text(Gui.get_text_width(gui, t), gui, frame, t, right, bounds, state)

# The inner bar's color by state: BASE_COLOR_PRESSED, TEXT_COLOR_FOCUSED,
# TEXT_COLOR_PRESSED, TEXT_COLOR_DISABLED.
def Gui.slide.color(state: U32) -> U32:
  match state:
    case 0: 7
    case 1: 5
    case 2: 8
    case _: 11

# The inner rectangle: a knob of sliderWidth kept inside the borders, or
# (sliderWidth 0) a bar from the left border.
def Gui.slide.bar(+sw: U32, +bounds: J.Rectangle, +border: F32, +sy: F32, +sh: F32, +amount: F32) -> J.Rectangle:
  J.Rectangle{+x, _, +w, _} = bounds
  +knob = (x + amount : F32)
  +kx = Bool.pick(F32, (knob <= x + border : F32), (x + border : F32), Bool.pick(F32, (knob + U32.to_f32(sw) >= x + w : F32), (x + w - U32.to_f32(sw) - border : F32), knob))
  Bool.pick(J.Rectangle, (sw > 0 : U32), J.Rectangle{kx, sy, U32.to_f32(sw), sh},
    J.Rectangle{(x + border : F32), sy, Bool.pick(F32, (amount > w : F32), (w - 2.0 * border : F32), amount), sh})

def Gui.slide.draw(+slide: Gui.Slide, frame: J.Frame, +bounds: J.Rectangle, left: Maybe<String>, right: Maybe<String>, +old: F32, +min: F32, +max: F32, +sw: U32) -> J.Frame & (Gui & (F32 & Bool)):
  GuiSlide{+gui, +state, +value} = slide
  J.Rectangle{+x, +y, +w, +h} = bounds
  +border = Gui.style.f32(gui, 4, 12)
  +padding = Gui.style.f32(gui, 4, 17)
  +amount = (((value - min) / (max - min)) * (w - U32.to_f32(sw) - 2.0 * border) : F32)
  +bar = Gui.slide.bar(sw, bounds, border, (y + border + padding : F32), (h - 2.0 * border - 2.0 * padding : F32), amount)
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 4, 12), Gui.color(gui, 4, (state * 3 : U32)), Gui.color(gui, 4, Bool.pick(U32, U32.is_ne(state, 3), 1, 10)))
  f2 = Gui.draw_rectangle(f1, bar, 0, 0, Gui.color(gui, 4, Gui.slide.color(state)))
  (Gui.slide.label(gui, Gui.slide.label(gui, f2, left, False{}, bounds, state), right, True{}, bounds, state), (gui, (value, Bool.not(F32.is_eq(old, value)))))

def Gui.slide.clamped(active: Bool, +slide: Gui.Slide, +min: F32, +max: F32) -> Gui.Slide:
  match active:
    case False{}: slide
    case True{}:
      GuiSlide{gui, state, +value} = slide
      GuiSlide{gui, state, Gui.slide.clamp(value, min, max)}

def Gui.mouse.x(position: M.Vector2) -> F32:
  M.Vector2{x, _} = position
  x

def Gui.slide(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, left: Maybe<String>, right: Maybe<String>, +value: F32, +min: F32, +max: F32, +sw: U32) -> J.Frame & (Gui & (F32 & Bool)):
  J.Rectangle{+x, +y, +w, +h} = bounds
  +mx = Gui.mouse.x(J.Input.get_mouse_position(core))
  +slider = {J.Rectangle{x, (y + Gui.style.f32(gui, 4, 12) + Gui.style.f32(gui, 4, 17) : F32), 0.0, (h - 2.0 * Gui.style.f32(gui, 4, 12) - 2.0 * Gui.style.f32(gui, 4, 17) : F32)} : J.Rectangle}
  +kind = Bool.pick(U32, Gui.active(gui), Gui.slide.kind(gui, core, bounds, slider), 0)
  +moved = Gui.slide.update(kind, gui, Gui.slide.value(mx, x, w, sw, min, max), bounds, value)
  Gui.slide.draw(Gui.slide.clamped(Gui.active(gui), moved, min, max), frame, bounds, left, right, value, min, max, sw)

# GuiSlider(bounds, textLeft, textRight, &value, minValue, maxValue): the
# frame, the Gui (a drag is its state), the value and whether it changed.
def Gui.slider(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, left: Maybe<String>, right: Maybe<String>, +value: F32, +min: F32, +max: F32) -> J.Frame & (Gui & (F32 & Bool)):
  Gui.slide(gui, core, frame, bounds, left, right, value, min, max, Gui.get_style(gui, 4, 16))

# GuiSliderBar: GuiSlider with SLIDER_WIDTH 0 for the call.
def Gui.slider_bar(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, left: Maybe<String>, right: Maybe<String>, +value: F32, +min: F32, +max: F32) -> J.Frame & (Gui & (F32 & Bool)):
  Gui.slide(gui, core, frame, bounds, left, right, value, min, max, 0)

# -----------------------------------------------------------------------------
# Jongui additions (no raygui counterpart): rows of controls run in order,
# for programs that keep their values in lists (Bend has no pointers to write
# through).

# GuiSliderBar(bounds, left, TextFormat(format, value), &value, low, high).
type Gui.Bar is Data:
  GuiBar{bounds: J.Rectangle, left: String, format: String, low: F32, high: F32}

# GuiCheckBox(bounds, text, &checked).
type Gui.Box is Data:
  GuiBox{bounds: J.Rectangle, text: String}

type Gui.Row is Type:
  GuiRow{frame: J.Frame, gui: Gui, values: +List<F32>}

type Gui.Checks is Type:
  GuiChecks{frame: J.Frame, values: +List<Bool>}

def Gui.bars.valued(acc: +List<F32>, frame: J.Frame, gui: Gui, pair: F32 & Bool) -> Gui.Row:
  (value, _) = pair
  GuiRow{frame, gui, Con{value, acc}}

def Gui.bars.pushed(acc: +List<F32>, frame: J.Frame, rest: Gui & (F32 & Bool)) -> Gui.Row:
  (gui, pair) = rest
  Gui.bars.valued(acc, frame, gui, pair)

def Gui.bars.take(acc: +List<F32>, r: J.Frame & (Gui & (F32 & Bool))) -> Gui.Row:
  (frame, rest) = r
  Gui.bars.pushed(acc, frame, rest)

def Gui.bars.text(text: Maybe<String>, +gui: Gui, +core: J.Core, frame: J.Frame, +bar: Gui.Bar, +value: F32, acc: +List<F32>) -> Gui.Row:
  match text:
    case None{}: GuiRow{J.Frame.refuse(frame), gui, Con{value, acc}}
    case Some{t}:
      GuiBar{+bounds, +left, _, +low, +high} = bar
      Gui.bars.take(acc, Gui.slider_bar(gui, core, frame, bounds, Some{left}, Some{t}, value, low, high))

def Gui.bar.format(+bar: Gui.Bar) -> String:
  GuiBar{_, _, format, _, _} = bar
  format

def Gui.bars.one(+bar: Gui.Bar, +value: F32, +core: J.Core, row: Gui.Row) -> Gui.Row:
  GuiRow{frame, +gui, acc} = row
  Gui.bars.text(J.Text.format(Gui.bar.format(bar), [J.TextFloat{value}]), gui, core, frame, bar, value, acc)

def Gui.bars.go(bars: +List<Gui.Bar>, values: +List<F32>, +core: J.Core, row: Gui.Row) -> Gui.Row:
  match bars values:
    case Con{+bar, rest} Con{+value, more}: Gui.bars.go(rest, more, core, Gui.bars.one(bar, value, core, row))
    case _ _: row

def Gui.bars.done(row: Gui.Row) -> J.Frame & (Gui & +List<F32>):
  GuiRow{frame, gui, acc} = row
  (frame, (gui, List.reverse(&2, F32, acc)))

# One GuiSliderBar per bar, in order, each with its value formatted by the
# bar's format (one float specification) as the right text: the frame, the
# Gui and the new values. A format Text.format refuses marks the frame
# undefined.
def Gui.slider_bars(+gui: Gui, +core: J.Core, frame: J.Frame, bars: +List<Gui.Bar>, values: +List<F32>) -> J.Frame & (Gui & +List<F32>):
  Gui.bars.done(Gui.bars.go(bars, values, core, GuiRow{frame, gui, Nil{}}))

def Gui.boxes.taken(acc: +List<Bool>, frame: J.Frame, pair: Bool & Bool) -> Gui.Checks:
  (checked, _) = pair
  GuiChecks{frame, Con{checked, acc}}

def Gui.boxes.take(acc: +List<Bool>, r: J.Frame & (Bool & Bool)) -> Gui.Checks:
  (frame, pair) = r
  Gui.boxes.taken(acc, frame, pair)

def Gui.boxes.one(+box: Gui.Box, +on: Bool, +gui: Gui, +core: J.Core, state: Gui.Checks) -> Gui.Checks:
  GuiBox{+bounds, +text} = box
  GuiChecks{frame, acc} = state
  Gui.boxes.take(acc, Gui.check_box(gui, core, frame, bounds, text, on))

def Gui.boxes.go(boxes: +List<Gui.Box>, checked: +List<Bool>, +gui: Gui, +core: J.Core, state: Gui.Checks) -> Gui.Checks:
  match boxes checked:
    case Con{+box, rest} Con{+on, more}: Gui.boxes.go(rest, more, gui, core, Gui.boxes.one(box, on, gui, core, state))
    case _ _: state

def Gui.boxes.done(state: Gui.Checks) -> J.Frame & +List<Bool>:
  GuiChecks{frame, acc} = state
  (frame, List.reverse(&2, Bool, acc))

# One GuiCheckBox per box, in order: the frame and the new checked flags.
def Gui.check_boxes(+gui: Gui, +core: J.Core, frame: J.Frame, boxes: +List<Gui.Box>, checked: +List<Bool>) -> J.Frame & +List<Bool>:
  Gui.boxes.done(Gui.boxes.go(boxes, checked, gui, core, GuiChecks{frame, Nil{}}))
