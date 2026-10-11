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
# GuiSliderBar, GuiLine and GuiGroupBox, GuiValueBox and GuiSpinner (not in
# edit mode), GuiStatusBar, GuiPanel, GuiDropdownBox and GuiTextBox, with the
# default font,
# TEXT_WRAP_NONE and raygui's icon set at scale 1 (src/gui_icons.bend). An
# icon id above 255 (raygui reads past its table) and the other wrap modes
# mark the frame undefined. See docs/GUI.md.
import Base
import ./jonlib.bend as J
import ./jonmath.bend as M
import ./src/fonts.bend as FontCore
import ./src/text.bend as TextCore
import ./src/gui_icons.bend as Icons

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
def Gui.width.sum(+gui: Gui, bytes: +List<U32>) -> F32:
  Gui.text.sum(TextCore.codepoints(List.take(&2, U32, Gui.line.bytes(bytes, False{}), 256n)), Gui.scale(gui), Gui.style.f32(gui, 0, 17), 0.0)

def Gui.width.bytes(+gui: Gui, bytes: +List<U32>) -> F32:
  F32.trunc(Gui.width.sum(gui, bytes))

def Gui.first(bytes: +List<U32>) -> U32:
  match bytes:
    case Con{b, _}: b
    case Nil{}: 0

# The index (1 to 4) of the next '#' after a leading one, or 0.
def Gui.width.offset(n: Nat, text: +List<U32>, +index: U32) -> U32:
  match n text:
    case 1n+p Con{+c, rest}: Bool.pick(U32, U32.is_eq(c, 35), index, Gui.width.offset(p, rest, (index + 1 : U32)))
    case _ _: 0

def Gui.width.tail(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Con{_, +rest}: rest
    case Nil{}: Nil{}

# GuiGetTextWidth of bytes: a text starting with '#' that has another '#'
# within its next four bytes is measured from that second '#' (it included),
# plus 20 for the icon and its padding.
def Gui.width.text(+gui: Gui, +bytes: +List<U32>) -> F32:
  +offset = Bool.pick(U32, U32.is_eq(Gui.first(bytes), 35), Gui.width.offset(4n, Gui.width.tail(bytes), 1), 0)
  Bool.pick(F32, U32.is_eq(offset, 0), Gui.width.bytes(gui, bytes), F32.trunc((Gui.width.sum(gui, List.drop(&2, U32, bytes, U32.to_nat(offset))) + 20.0 : F32)))

# GuiGetTextWidth(text) as a C int in F32.
def Gui.get_text_width(+gui: Gui, text: String) -> Maybe<F32>:
  Some{Gui.width.text(gui, TextCore.bytes(text))}

# GetTextIcon: a line starting with '#', up to three digits and '#' names an
# icon, and its text follows; id is 4294967295 for a line without one.
type Gui.Icon is Data:
  GuiIcon{id: U32, text: +List<U32>}

def Gui.icon.digits(n: Nat, text: +List<U32>, +value: U32) -> Gui.Icon:
  match n text:
    case 0n Nil{}: GuiIcon{value, Nil{}}
    case 0n Con{+c, +rest}: GuiIcon{value, Con{c, rest}}
    case 1n+p Nil{}: GuiIcon{value, Nil{}}
    case 1n+p Con{+c, +rest}: Bool.pick(Gui.Icon, (c >= 48 : U32) && (c <= 57 : U32), Gui.icon.digits(p, rest, (value * 10 + (c - 48) : U32)), GuiIcon{value, Con{c, rest}})

def Gui.icon.after(text: +List<U32>, +id: U32, +whole: +List<U32>) -> Gui.Icon:
  match text:
    case Con{+c, +rest}: Bool.pick(Gui.Icon, U32.is_eq(c, 35), GuiIcon{id, rest}, GuiIcon{4294967295, whole})
    case Nil{}: GuiIcon{4294967295, whole}

def Gui.icon.closed(+scan: Gui.Icon, +whole: +List<U32>) -> Gui.Icon:
  GuiIcon{+id, +text} = scan
  Gui.icon.after(text, id, whole)

def Gui.icon.of(line: +List<U32>) -> Gui.Icon:
  match line:
    case Con{+c, +rest}: Bool.pick(Gui.Icon, U32.is_eq(c, 35), Gui.icon.closed(Gui.icon.digits(3n, rest, 0), Con{c, rest}), GuiIcon{4294967295, Con{c, rest}})
    case Nil{}: GuiIcon{4294967295, Nil{}}

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

# inset is what an icon takes from the line's width (20, or 0).
type Gui.Line is Data:
  GuiLine{x: F32, y: F32, width: F32, text_width: F32, ellipsis: F32, scale: F32, spacing: F32, size: F32, tint: U32, inset: F32}

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
      GuiLine{+x, +y, +width, +text_width, +ellipsis, +scale, +spacing, +size, +tint, +inset} = line
      +glyph = Gui.glyph.width(cp, scale)
      +blank = U32.is_eq(cp, 32) || U32.is_eq(cp, 9)
      +wide = (text_width > width : F32)
      +fits = (offset <= ((width - glyph) - inset) - ellipsis : F32)
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

# -----------------------------------------------------------------------------
# GuiDrawRectangle

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

# -----------------------------------------------------------------------------
# GuiDrawIcon and GuiDrawText

def Gui.icon.bit(visible: Bool, frame: J.Frame, +x: F32, +y: F32, +color: U32) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: Gui.draw_rectangle(frame, J.Rectangle{x, y, 1.0, 1.0}, 0, 0, color)

# The 32 bits of one word: two rows of 16 pixels, the low bit first.
def Gui.icon.word(n: Nat, +bits: U32, +k: U32, +x: F32, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: Gui.icon.word(p, (bits >> 1n : U32), (k + 1 : U32), x, y, color,
      Gui.icon.bit(U32.is_eq((bits .&. 1 : U32), 1), frame, (x + U32.to_f32((k % 16 : U32)) : F32), (y + U32.to_f32((k / 16 : U32)) : F32), color))

def Gui.icon.rows(n: Nat, +id: U32, +index: U32, +x: F32, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: Gui.icon.rows(p, id, (index + 1 : U32), x, y, color, Gui.icon.word(32n, Icons.word(id, index), 0, x, (y + U32.to_f32((2 * index : U32)) : F32), color, frame))

# GuiDrawIcon(iconId, x, y, 1, color), the color already faded: one
# GuiDrawRectangle of a pixel for each set bit.
def Gui.icon.drawn(has: Bool, +id: U32, +x: F32, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match has:
    case False{}: frame
    case True{}: Gui.icon.rows(8n, id, 0, x, y, color, frame)

# One line: its icon, if any, at the line's x and centered on the bounds'
# height, then the text 20 pixels further. Only the text's last line can be
# empty for raygui (the others still have their '\n' to read).
def Gui.text.line(+icon: Gui.Icon, +last: Bool, +gui: Gui, +bounds: J.Rectangle, +alignment: U32, +tint: U32, +offset: F32, +total: F32, frame: J.Frame) -> J.Frame:
  GuiIcon{+id, +text} = icon
  J.Rectangle{+bx, +by, +bw, +bh} = bounds
  +has = (id < 256 : U32)
  +size = Gui.style.f32(gui, 0, 16)
  +empty = last && Gui.empty(text)
  +text_width = (Gui.width.text(gui, text) + Bool.pick(F32, has, Bool.pick(F32, empty, 16.0, 20.0), 0.0) : F32)
  +x = F32.trunc(Bool.pick(F32, (text_width > bw : F32) && Bool.not(empty), bx, Gui.line.x(alignment, bx, bw, text_width)))
  +y = F32.trunc(Gui.line.y(Gui.get_style(gui, 0, 21), by, bh, offset, total))
  +inset = Bool.pick(F32, has, 20.0, 0.0)
  +spec = {GuiLine{(x + inset : F32), y, bw, text_width, Gui.width.bytes(gui, [46, 46, 46]), Gui.scale(gui), Gui.style.f32(gui, 0, 17), size, tint, inset} : Gui.Line}
  Gui.glyphs(TextCore.codepoints(Gui.line.bytes(text, True{})), spec, 0.0, False{},
    Gui.icon.drawn(has, id, x, F32.trunc((((by + bh / 2.0 : F32) - 8.0 : F32) + Gui.pixel(bh) : F32)), tint, frame))

def Gui.lines.last(rest: +List<+List<U32>>) -> Bool:
  match rest:
    case Nil{}: True{}
    case Con{_, _}: False{}

def Gui.text.lines(lines: +List<+List<U32>>, +gui: Gui, +bounds: J.Rectangle, +alignment: U32, +tint: U32, +offset: F32, +total: F32, frame: J.Frame) -> J.Frame:
  match lines:
    case Nil{}: frame
    case Con{+line, +rest}:
      Gui.text.lines(rest, gui, bounds, alignment, tint, (offset + (Gui.style.f32(gui, 0, 16) + Gui.style.f32(gui, 0, 20)) : F32), total,
        Gui.text.line(Gui.icon.of(line), Gui.lines.last(rest), gui, bounds, alignment, tint, offset, total, frame))

# Fewer than n bytes, none of them a '#'.
def Gui.icon.short(n: Nat, text: +List<U32>) -> Bool:
  match n text:
    case 0n Nil{}: False{}
    case 0n Con{_, _}: False{}
    case 1n+p Nil{}: True{}
    case 1n+p Con{+c, rest}: U32.is_ne(c, 35) && Gui.icon.short(p, rest)

# A line raygui does not draw from its own bytes: an icon id above 255 is
# outside its table, and a '#' right after the icon (or first in a line
# without one) with fewer than four bytes after it and no second '#' makes
# GuiGetTextWidth look for that '#' in the lines that follow.
def Gui.icon.out(+icon: Gui.Icon, +last: Bool) -> Bool:
  GuiIcon{+id, +text} = icon
  ((id >= 256 : U32) && U32.is_ne(id, 4294967295)) || (Bool.not(last) && U32.is_eq(Gui.first(text), 35) && Gui.icon.short(4n, Gui.width.tail(text)))

def Gui.has_icon(lines: +List<+List<U32>>) -> Bool:
  match lines:
    case Nil{}: False{}
    case Con{+line, +rest}: Gui.icon.out(Gui.icon.of(line), Gui.lines.last(rest)) || Gui.has_icon(rest)

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
# frame is undefined for a line Gui.icon.out names or a wrap mode.
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
# GetTextBounds

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

# The color of GuiLine and GuiGroupBox: DEFAULT's LINE_COLOR (18), or its
# BORDER_COLOR_DISABLED (9) in STATE_DISABLED.
def Gui.line.property(+state: U32) -> U32:
  Bool.pick(U32, U32.is_eq(state, 3), 9, 18)

# GuiLine with a text, "--- text ------": a rule of 8 pixels, the text from
# x + 12 in a box of its width + 2, and the rule again from 4 pixels after
# it to the right edge. A text with an icon prefix marks the frame undefined.
def Gui.line.text(width: Maybe<F32>, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, text: String, +color: U32) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+w}:
      J.Rectangle{+x, +y, +bw, +bh} = bounds
      +tw = (w + 2.0 : F32)
      +middle = (y + bh / 2.0 : F32)
      f1 = Gui.draw_rectangle(frame, J.Rectangle{x, middle, 8.0, 1.0}, 0, 0, color)
      f2 = Gui.draw_text(gui, f1, text, J.Rectangle{(x + 12.0 : F32), y, tw, bh}, 0, color)
      Gui.draw_rectangle(f2, J.Rectangle{(((x + 12.0 : F32) + tw : F32) + 4.0 : F32), middle, (((bw - tw : F32) - 12.0 : F32) - 4.0 : F32), 1.0}, 0, 0, color)

def Gui.line.rule(frame: J.Frame, +bounds: J.Rectangle, +color: U32) -> J.Frame:
  J.Rectangle{+x, +y, +w, +h} = bounds
  Gui.draw_rectangle(frame, J.Rectangle{x, (y + h / 2.0 : F32), w, 1.0}, 0, 0, color)

def Gui.line.colored(text: Maybe<String>, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +color: U32) -> J.Frame:
  match text:
    case None{}: Gui.line.rule(frame, bounds, color)
    case Some{+t}: Gui.line.text(Gui.get_text_width(gui, t), gui, frame, bounds, t, color)

# GuiLine(bounds, text): a one-pixel rule at the middle of the bounds, with
# the text set into it when one is given (NULL is None).
def Gui.line(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>) -> J.Frame:
  Gui.line.colored(text, gui, frame, bounds, Gui.color(gui, 0, Gui.line.property(Gui.get_state(gui))))

# GuiGroupBox(bounds, text): the left, bottom and right edges, one pixel
# thick, and GuiLine across the top, TEXT_SIZE high and half of it (an
# integer division) above the bounds.
def Gui.group_box(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>) -> J.Frame:
  J.Rectangle{+x, +y, +w, +h} = bounds
  +color = Gui.color(gui, 0, Gui.line.property(Gui.get_state(gui)))
  +size = Gui.get_style(gui, 0, 16)
  f1 = Gui.draw_rectangle(frame, J.Rectangle{x, y, 1.0, h}, 0, 0, color)
  f2 = Gui.draw_rectangle(f1, J.Rectangle{x, ((y + h : F32) - 1.0 : F32), w, 1.0}, 0, 0, color)
  f3 = Gui.draw_rectangle(f2, J.Rectangle{((x + w : F32) - 1.0 : F32), y, 1.0, h}, 0, 0, color)
  Gui.line(gui, f3, J.Rectangle{x, (y - U32.to_f32((size / 2 : U32)) : F32), w, U32.to_f32(size)}, text)

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

# -----------------------------------------------------------------------------
# GuiValueBox and GuiSpinner (not in edit mode)

# GUI_BUTTON_PRESSED.
def Gui.pressed(+core: J.Core) -> Bool:
  J.Input.is_mouse_button_pressed(core, 0) || Gui.pad(J.Input.is_gamepad_button_pressed(core, 0, 7))

# a < b for C ints held as two's-complement words.
def Gui.int.less(+a: U32, +b: U32) -> Bool:
  ((a + 2147483648 : U32) < (b + 2147483648 : U32) : U32)

# GuiValueBox's clamp: max when above it, else min when below it.
def Gui.int.clamp(+value: U32, +min: U32, +max: U32) -> U32:
  Bool.pick(U32, Gui.int.less(max, value), max, Bool.pick(U32, Gui.int.less(value, min), min, value))

# The label beside the control: after it, or before it for TEXT_ALIGN_LEFT.
def Gui.value.text(width: Maybe<F32>, +gui: Gui, frame: J.Frame, text: String, +bounds: J.Rectangle, +state: U32) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+measured}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +padding = Gui.style.f32(gui, 10, 13)
      +tw = (measured + 2.0 : F32)
      +ty = (y + h / 2.0 - F32.trunc((Gui.style.f32(gui, 0, 16) / 2.0 : F32)) : F32)
      Gui.draw_text(gui, frame, text, J.Rectangle{Bool.pick(F32, U32.is_eq(Gui.get_style(gui, 10, 14), 0), (x - tw - padding : F32), (x + w + padding : F32)), ty, tw, Gui.style.f32(gui, 0, 16)},
        Bool.pick(U32, U32.is_eq(Gui.get_style(gui, 10, 14), 2), 0, 2), Gui.color(gui, 1, (2 + state * 3 : U32)))

def Gui.value.label(+gui: Gui, frame: J.Frame, text: Maybe<String>, +bounds: J.Rectangle, +state: U32) -> J.Frame:
  match text:
    case None{}: frame
    case Some{+t}: Gui.value.text(Gui.get_text_width(gui, t), gui, frame, t, bounds, state)

# The box's fill: BASE_COLOR_PRESSED, BASE_COLOR_DISABLED or BLANK.
def Gui.value.fill(state: U32, +gui: Gui) -> U32:
  match state:
    case 2: Gui.color(gui, 10, 7)
    case 3: Gui.color(gui, 10, 10)
    case _: 0

# GuiValueBox(bounds, text, &value, minValue, maxValue, editMode) with ints as
# two's-complement words: the frame, the value and whether the box was
# pressed. The text drawn is the value as it came; an enabled, unlocked box
# returns it clamped. Edit mode marks the frame undefined.
def Gui.value_box(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +value: U32, +min: U32, +max: U32, edit: Bool) -> J.Frame & (U32 & Bool):
  match edit:
    case True{}: (J.Frame.refuse(frame), (value, False{}))
    case False{}:
      +live = Gui.active(gui) && Bool.not(Gui.exclusive(gui))
      +over = live && J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
      +state = Bool.pick(U32, over, 1, Gui.get_state(gui))
      f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 10, 12), Gui.color(gui, 10, (state * 3 : U32)), Gui.value.fill(state, gui))
      f2 = Gui.draw_text.bytes(TextCore.integer.field(True{}, 10, False{}, value, 0, 0, False{}, 0), gui, f1, Gui.text_bounds(gui, 10, bounds), 1, Gui.color(gui, 10, (2 + state * 3 : U32)))
      (Gui.value.label(gui, f2, text, bounds, state), (Bool.pick(U32, live, Gui.int.clamp(value, min, max), value), over && Gui.pressed(core)))

def Gui.spin.refused(refused: Bool, frame: J.Frame) -> J.Frame:
  match refused:
    case True{}: J.Frame.refuse(frame)
    case False{}: frame

def Gui.spin.label(r: J.Frame & (U32 & Bool), +gui: Gui, text: Maybe<String>, +bounds: J.Rectangle, +state: U32, +refused: Bool) -> J.Frame & (U32 & Bool):
  (frame, result) = r
  (Gui.spin.refused(refused, Gui.value.label(gui, frame, text, bounds, state)), result)

# The value after the buttons, clamped min first: tempValue--, tempValue++.
# INT_MIN - 1 and INT_MAX + 1 overflow in C and mark the frame undefined.
def Gui.spin.box(r: J.Frame & Bool, +down: Bool, +gui: Gui, +core: J.Core, +bounds: J.Rectangle, text: Maybe<String>, +value: U32, +min: U32, +max: U32, +edit: Bool, +state: U32) -> J.Frame & (U32 & Bool):
  (frame, +up) = r
  J.Rectangle{+x, +y, +w, +h} = bounds
  +width = Gui.style.f32(gui, 10, 16)
  +gap = Gui.style.f32(gui, 10, 17)
  +lowered = Bool.pick(U32, down, (value - 1 : U32), value)
  +raised = Bool.pick(U32, up, (lowered + 1 : U32), lowered)
  +floored = Bool.pick(U32, Gui.int.less(raised, min), min, raised)
  +temp = Bool.pick(U32, edit, raised, Bool.pick(U32, Gui.int.less(max, floored), max, floored))
  Gui.spin.label(Gui.value_box(gui, core, frame, J.Rectangle{(x + width + gap : F32), y, (w - 2.0 * (width + gap) : F32), h}, None{}, temp, min, max, edit),
    gui, text, bounds, state, (down && U32.is_eq(value, 2147483648)) || (up && U32.is_eq(lowered, 2147483647)))

def Gui.spin.right(r: J.Frame & Bool, +gui: Gui, +core: J.Core, +bounds: J.Rectangle, text: Maybe<String>, +value: U32, +min: U32, +max: U32, +edit: Bool, +state: U32) -> J.Frame & (U32 & Bool):
  (frame, down) = r
  J.Rectangle{+x, +y, +w, +h} = bounds
  +width = Gui.style.f32(gui, 10, 16)
  Gui.spin.box(Gui.button(gui, core, frame, J.Rectangle{(x + w - width : F32), y, width, h}, "#119#"), down, gui, core, bounds, text, value, min, max, edit, state)

# GuiSpinner(bounds, text, &value, minValue, maxValue, editMode): the left
# and right buttons (ICON_ARROW_LEFT_FILL, ICON_ARROW_RIGHT_FILL), the value
# box between them and the label. The frame, the value and GuiValueBox's
# result.
def Gui.spinner(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +value: U32, +min: U32, +max: U32, +edit: Bool) -> J.Frame & (U32 & Bool):
  J.Rectangle{+x, +y, _, +h} = bounds
  +over = Gui.active(gui) && Bool.not(Gui.exclusive(gui)) && J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
  Gui.spin.right(Gui.button(gui, core, frame, J.Rectangle{x, y, Gui.style.f32(gui, 10, 16), h}, "#118#"), gui, core, bounds, text, value, min, max, edit,
    Bool.pick(U32, over, Gui.hover(core), Gui.get_state(gui)))

# -----------------------------------------------------------------------------
# GuiStatusBar, GuiPanel and GuiDropdownBox

# GuiStatusBar(bounds, text).
def Gui.status_bar(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>) -> J.Frame:
  +state = Gui.get_state(gui)
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 15, 12), Gui.color(gui, 15, (state * 3 : U32)), Gui.color(gui, 15, (1 + state * 3 : U32)))
  Gui.draw_text.maybe(gui, f1, text, Gui.text_bounds(gui, 15, bounds), Gui.get_style(gui, 15, 14), Gui.color(gui, 15, (2 + state * 3 : U32)))

# The panel's rectangle: a border of 1 in LINE_COLOR over BACKGROUND_COLOR
# (BORDER_COLOR_DISABLED over BASE_COLOR_DISABLED when disabled).
def Gui.panel.body(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle) -> J.Frame:
  +disabled = U32.is_eq(Gui.get_state(gui), 3)
  Gui.draw_rectangle(frame, bounds, 1, Gui.color(gui, 0, Bool.pick(U32, disabled, 9, 18)), Gui.color(gui, 0, Bool.pick(U32, disabled, 10, 19)))

def Gui.panel.headed(text: Maybe<String>, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle) -> J.Frame:
  match text:
    case None{}: Gui.panel.body(gui, frame, bounds)
    case Some{t}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      Gui.panel.body(gui, Gui.status_bar(gui, frame, J.Rectangle{x, y, w, 24.0}, Some{t}), J.Rectangle{x, (y + 23.0 : F32), w, (Bool.pick(F32, (h < 48.0 : F32), 48.0, h) - 23.0 : F32)})

# GuiPanel(bounds, text): with a text, a status bar of 24 pixels heads the
# panel, which starts 23 pixels lower and is at least 48 high.
def Gui.panel(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>) -> J.Frame:
  Gui.panel.headed(text, gui, frame, bounds)

def Gui.refused(refused: Bool, frame: J.Frame) -> J.Frame:
  match refused:
    case True{}: J.Frame.refuse(frame)
    case False{}: frame

def Gui.drop.count(items: +List<Gui.Item>, +n: U32) -> U32:
  match items:
    case Nil{}: n
    case Con{_, rest}: Gui.drop.count(rest, (n + 1 : U32))

def Gui.drop.bytes(items: +List<Gui.Item>) -> +List<U32>:
  match items:
    case Con{item, _}: Gui.item.bytes(item)
    case Nil{}: Nil{}

# An item's y from the one before it: a row further down, or up when rolled up.
def Gui.drop.next(+up: Bool, +y: F32, +pitch: F32) -> F32:
  Bool.pick(F32, up, (y - pitch : F32), (y + pitch : F32))

# The first item under the pointer, or 4294967295.
def Gui.drop.focus(n: Nat, +i: U32, +mouse: M.Vector2, +x: F32, +y: F32, +w: F32, +h: F32, +pitch: F32, +up: Bool) -> U32:
  match n:
    case 0n: 4294967295
    case 1n+p:
      Bool.pick(U32, J.Collision.point_rec(mouse, J.Rectangle{x, Gui.drop.next(up, y, pitch), w, h}), i,
        Gui.drop.focus(p, (i + 1 : U32), mouse, x, Gui.drop.next(up, y, pitch), w, h, pitch, up))

def Gui.drop.boxed(boxed: Bool, +gui: Gui, +place: J.Rectangle, +kind: U32, frame: J.Frame) -> J.Frame:
  match boxed:
    case False{}: frame
    case True{}: Gui.draw_rectangle(frame, place, Gui.get_style(gui, 8, 12), Gui.color(gui, 8, (kind * 3 : U32)), Gui.color(gui, 8, (1 + kind * 3 : U32)))

# The open list: the selected item boxed in the pressed colors, the focused
# one in the focused colors, the others as plain text.
def Gui.drop.items(items: +List<Gui.Item>, +i: U32, +gui: Gui, +selected: U32, +focused: U32, +x: F32, +y: F32, +w: F32, +h: F32, +pitch: F32, +up: Bool, frame: J.Frame) -> J.Frame:
  match items:
    case Nil{}: frame
    case Con{+item, rest}:
      +kind = Bool.pick(U32, U32.is_eq(i, selected), 2, Bool.pick(U32, U32.is_eq(i, focused), 1, 0))
      +place = {J.Rectangle{x, Gui.drop.next(up, y, pitch), w, h} : J.Rectangle}
      Gui.drop.items(rest, (i + 1 : U32), gui, selected, focused, x, Gui.drop.next(up, y, pitch), w, h, pitch, up,
        Gui.draw_text.bytes(Gui.item.bytes(item), gui, Gui.drop.boxed((kind > 0 : U32), gui, place, kind, frame), Gui.text_bounds(gui, 8, place), Gui.get_style(gui, 8, 14), Gui.color(gui, 8, (2 + kind * 3 : U32))))

def Gui.drop.listed(edit: Bool, +items: +List<Gui.Item>, +gui: Gui, +selected: U32, +focused: U32, +bounds: J.Rectangle, +pitch: F32, +up: Bool, frame: J.Frame) -> J.Frame:
  match edit:
    case False{}: frame
    case True{}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      Gui.drop.items(items, 0, gui, selected, focused, x, y, w, h, pitch, up, frame)

def Gui.drop.panel(edit: Bool, +gui: Gui, +open: J.Rectangle, frame: J.Frame) -> J.Frame:
  match edit:
    case False{}: frame
    case True{}: Gui.panel(gui, frame, open, None{})

# The arrow: ICON_ARROW_DOWN_FILL (120), or ICON_ARROW_UP_FILL (121) when rolled up.
def Gui.drop.arrow(visible: Bool, +gui: Gui, +bounds: J.Rectangle, +up: Bool, +state: U32, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      Gui.draw_text(gui, frame, Bool.pick(String, up, "#121#", "#120#"), J.Rectangle{(x + w - Gui.style.f32(gui, 8, 16) : F32), (y + h / 2.0 - 6.0 : F32), 10.0, 10.0}, 1, Gui.color(gui, 8, (2 + state * 3 : U32)))

def Gui.drop.drawn(+items: +List<Gui.Item>, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +open: J.Rectangle, +state: U32, +selected: U32, +focused: U32, +edit: Bool, +pitch: F32, +up: Bool) -> J.Frame:
  f1 = Gui.draw_rectangle(Gui.drop.panel(edit, gui, open, frame), bounds, Gui.get_style(gui, 8, 12), Gui.color(gui, 8, (state * 3 : U32)), Gui.color(gui, 8, (1 + state * 3 : U32)))
  f2 = Gui.draw_text.bytes(Gui.drop.bytes(List.drop(&2, Gui.Item, items, U32.to_nat(selected))), gui, f1, Gui.text_bounds(gui, 8, bounds), Gui.get_style(gui, 8, 14), Gui.color(gui, 8, (2 + state * 3 : U32)))
  Gui.drop.arrow(U32.is_eq(Gui.get_style(gui, 8, 18), 0), gui, bounds, up, state, Gui.drop.listed(edit, items, gui, selected, focused, bounds, pitch, up, f2))

# The update and the drawing over the split items. long: the text does not
# fit GuiTextSplit's buffer of 1024 bytes.
def Gui.drop.run(+items: +List<Gui.Item>, +long: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +active: U32, +edit: Bool) -> J.Frame & (U32 & Bool):
  J.Rectangle{+x, +y, +w, +h} = bounds
  +count = Gui.drop.count(items, 0)
  +spacing = Gui.style.f32(gui, 8, 17)
  +up = U32.is_eq(Gui.get_style(gui, 8, 19), 1)
  +pitch = (h + spacing : F32)
  +open = {J.Rectangle{x, Bool.pick(F32, up, (y - (U32.to_f32(count) * pitch + spacing) : F32), y), w, (U32.to_f32((count + 1 : U32)) * pitch : F32)} : J.Rectangle}
  +mouse = J.Input.get_mouse_position(core)
  +live = U32.is_ne(Gui.get_state(gui), 3) && (edit || Bool.not(Gui.is_locked(gui))) && (count > 1 : U32) && Bool.not(Gui.exclusive(gui))
  +over = J.Collision.point_rec(mouse, bounds)
  +pressed = Gui.pressed(core)
  +released = Gui.released(core)
  +focused = Bool.pick(U32, live && edit, Gui.drop.focus(U32.to_nat(count), 0, mouse, x, y, w, h, pitch, up), 4294967295)
  +picked = U32.is_ne(focused, 4294967295) && released
  +selected = Bool.pick(U32, picked, focused, active)
  +result = live && Bool.pick(Bool, edit, (Bool.not(J.Collision.point_rec(mouse, open)) && (pressed || released)) || (over && pressed) || picked, over && pressed)
  +state = Bool.pick(U32, live, Bool.pick(U32, edit, 2, Bool.pick(U32, over, Bool.pick(U32, pressed, 2, 1), Gui.get_state(gui))), Gui.get_state(gui))
  +refused = long || (count >= 128 : U32) || (selected >= count : U32)
  (Gui.refused(refused, Gui.drop.drawn(items, gui, frame, bounds, open, state, selected, focused, edit, pitch, up)), (selected, result))

# GuiDropdownBox(bounds, text, &active, editMode): the box with the active
# item and an arrow, and in edit mode a panel with every item below it (above
# it for DROPDOWN_ROLL_UP). The text splits at ';' and '\n'. The frame, the
# active item and raygui's result: a press over the closed box; in edit mode
# a press or a release outside the open bounds, a press over the box, or a
# release over an item, which becomes the active one. An active index
# outside the items (raygui reads a stale pointer), a text of 1024 bytes or
# more, and 128 items or more mark the frame undefined.
def Gui.dropdown_box(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +text: String, +active: U32, +edit: Bool) -> J.Frame & (U32 & Bool):
  Gui.drop.run(Gui.split(TextCore.bytes(text), 59, 0, Nil{}), (TextCore.len(TextCore.bytes(text)) >= 1024 : U32), gui, core, frame, bounds, active, edit)

# -----------------------------------------------------------------------------
# GuiTextBox

# raygui's text box globals, shared by every text box: textBoxCursorIndex (a
# byte index into the edited text) and autoCursorCounter (the frames a cursor
# key has been held).
type Gui.Editing is Data:
  GuiEditing{cursor: U32, counter: U32}

def Gui.editing() -> Gui.Editing:
  GuiEditing{0, 0}

# What one text box update leaves: the text, the two globals, the index the
# drawn text starts at, raygui's result, the state, the cursor's x and the
# mouse cursor's (below 0 for none), and whether raygui's own code is left.
type Gui.Edit is Data:
  GuiEdit{bytes: +List<U32>, cursor: U32, counter: U32, offset: U32, result: Bool, state: U32, cx: F32, mouse: F32, refused: Bool}

type Gui.Hit is Data:
  GuiHit{x: F32, index: U32, glyph: F32}

def Gui.hit.x(hit: Gui.Hit) -> F32:
  GuiHit{x, _, _} = hit
  x

def Gui.hit.index(hit: Gui.Hit) -> U32:
  GuiHit{_, index, _} = hit
  index

def Gui.rec.x(rec: J.Rectangle) -> F32:
  J.Rectangle{x, _, _, _} = rec
  x

def Gui.rec.width(rec: J.Rectangle) -> F32:
  J.Rectangle{_, _, w, _} = rec
  w

def Gui.box.insert(+bytes: +List<U32>, +at: U32, +piece: +List<U32>) -> +List<U32>:
  TextCore.glue(TextCore.take(bytes, at), TextCore.glue(piece, TextCore.drop(bytes, at)))

def Gui.box.remove(+bytes: +List<U32>, +from: U32, +count: U32) -> +List<U32>:
  TextCore.glue(TextCore.take(bytes, from), TextCore.drop(bytes, (from + count : U32)))

# GuiGetTextWidth(text + from) - GuiGetTextWidth(text + to), two C ints.
def Gui.box.span(+gui: Gui, +bytes: +List<U32>, +from: U32, +to: U32) -> F32:
  (Gui.width.text(gui, TextCore.drop(bytes, from)) - Gui.width.text(gui, TextCore.drop(bytes, to)) : F32)

# The index the drawn text starts at: one codepoint further while the text
# from there to the cursor is as wide as the box or wider.
def Gui.box.offset(n: Nat, +gui: Gui, +bytes: +List<U32>, +offset: U32, +cursor: U32, +width: F32) -> U32:
  match n:
    case 0n: offset
    case 1n+p:
      Bool.pick(U32, (Gui.box.span(gui, bytes, offset, cursor) >= width : F32),
        Gui.box.offset(p, gui, bytes, (offset + TextCore.pair.size(TextCore.next(TextCore.drop(bytes, offset))) : U32), cursor, width), offset)

# The bytes of the clipboard text that fit: whole codepoints of 32 or more
# while the text stays shorter than textSize.
def Gui.box.paste(n: Nat, +paste: +List<U32>, +count: U32, +length: U32, +size: U32) -> U32:
  match n:
    case 0n: count
    case 1n+p:
      +code = TextCore.next(TextCore.drop(paste, count))
      +stop = Bool.not(Gui.int.less((length + count + TextCore.pair.size(code) : U32), size)) || (TextCore.pair.value(code) < 32 : U32)
      Bool.pick(U32, stop, count, Gui.box.paste(p, paste, (count + TextCore.pair.size(code) : U32), length, size))

def Gui.box.clip(clip: Maybe<String>) -> +List<U32>:
  match clip:
    case None{}: Nil{}
    case Some{t}: TextCore.bytes(t)

def Gui.box.back.of(code: Maybe<TextCore.Code>) -> U32:
  match code:
    case None{}: 0
    case Some{c}: TextCore.pair.size(c)

# The byte size GetCodepointPrevious(text + position) answers, or 0 where it
# would read before the text.
def Gui.box.back(+bytes: +List<U32>, +position: U32) -> U32:
  Gui.box.back.of(TextCore.previous(bytes, position))

# The glyph whose first half holds the pointer: its x and byte index, and the
# width of the last glyph measured.
def Gui.box.walk(n: Nat, +bytes: +List<U32>, +i: U32, +length: U32, +mx: F32, +tbx: F32, +acc: F32, +scale: F32, +spacing: F32, +glyph: F32) -> Gui.Hit:
  match n:
    case 0n: GuiHit{F32.neg(1.0), 0, glyph}
    case 1n+p:
      +code = TextCore.next(TextCore.drop(bytes, i))
      +width = Gui.glyph.width(TextCore.pair.value(code), scale)
      Bool.pick(Gui.Hit, (i >= length : U32), GuiHit{F32.neg(1.0), 0, glyph},
        Bool.pick(Gui.Hit, (mx <= tbx + (acc + width / 2.0) : F32), GuiHit{(tbx + acc : F32), i, width},
          Gui.box.walk(p, bytes, (i + TextCore.pair.size(code) : U32), length, mx, tbx, (acc + (width + spacing) : F32), scale, spacing, width)))

# A pointer at or past the text's end less half the last glyph is at the end.
def Gui.box.hit(hit: Gui.Hit, +mx: F32, +tbx: F32, +end: F32, +length: U32) -> Gui.Hit:
  GuiHit{+x, +index, +glyph} = hit
  Bool.pick(Gui.Hit, (mx >= (tbx + end) - glyph / 2.0 : F32), GuiHit{(tbx + end : F32), length, glyph}, GuiHit{x, index, glyph})

# The update in edit mode, in raygui's order: the held-key counter, the draw
# offset, a paste (Ctrl+V) or the typed codepoint, HOME and END, DELETE,
# BACKSPACE, LEFT or RIGHT, the pointer, and ENTER or a press outside.
def Gui.box.edit(typed: J.Core & U32, +gui: Gui, +bounds: J.Rectangle, +tb: J.Rectangle, +bytes: +List<U32>, +size: U32, +editing: Gui.Editing) -> J.Core & Gui.Edit:
  (+core, +cp) = typed
  GuiEditing{+index, +count} = editing
  +bx = Gui.rec.x(bounds)
  +tbx = Gui.rec.x(tb)
  +tbw = Gui.rec.width(tb)
  +length = TextCore.len(bytes)
  +ctrl = J.Input.is_key_down(core, 341) || J.Input.is_key_down(core, 345)
  +held = J.Input.is_key_down(core, 263) || J.Input.is_key_down(core, 262) || J.Input.is_key_down(core, 265) || J.Input.is_key_down(core, 264) || J.Input.is_key_down(core, 259) || J.Input.is_key_down(core, 261)
  +counter = Bool.pick(U32, held, (count + 1 : U32), 0)
  +trigger = (counter > 20 : U32)
  +cursor0 = Bool.pick(U32, (index > length : U32), length, index)
  +offset = Gui.box.offset(U32.to_nat((length + 1 : U32)), gui, bytes, 0, cursor0, tbw)
  +stuck = (Gui.box.span(gui, bytes, offset, cursor0) >= tbw : F32)
  +clip = Gui.box.clip(J.Core.get_clipboard_text(core))
  +piece = Bool.pick(+List<U32>, J.Input.is_key_pressed(core, 86) && ctrl, TextCore.take(clip, Gui.box.paste(U32.to_nat((TextCore.len(clip) + 1 : U32)), clip, 0, length, size)),
    Bool.pick(+List<U32>, Bool.not(Gui.int.less(cp, 32)) && Gui.int.less((length + TextCore.len(TextCore.utf8(cp)) : U32), size), TextCore.utf8(cp), Nil{}))
  +bytes1 = Gui.box.insert(bytes, cursor0, piece)
  +length1 = (length + TextCore.len(piece) : U32)
  +cursor1 = (cursor0 + TextCore.len(piece) : U32)
  +cursor2 = Bool.pick(U32, (length1 > 0 : U32) && J.Input.is_key_pressed(core, 268), 0, cursor1)
  +cursor3 = Bool.pick(U32, (length1 > cursor2 : U32) && J.Input.is_key_pressed(core, 269), length1, cursor2)
  +word_delete = (length1 > cursor3 : U32) && J.Input.is_key_pressed(core, 261) && ctrl
  +delete = Bool.not(word_delete) && (length1 > cursor3 : U32) && (J.Input.is_key_pressed(core, 261) || (J.Input.is_key_down(core, 261) && trigger))
  +deleted = Bool.pick(U32, delete, TextCore.pair.size(TextCore.next(TextCore.drop(bytes1, cursor3))), 0)
  +bytes2 = Gui.box.remove(bytes1, cursor3, deleted)
  +length2 = (length1 - deleted : U32)
  +word_back = (cursor3 > 0 : U32) && J.Input.is_key_pressed(core, 259) && ctrl
  +back = Bool.not(word_back) && (cursor3 > 0 : U32) && (J.Input.is_key_pressed(core, 259) || (J.Input.is_key_down(core, 259) && trigger))
  +back_size = Gui.box.back(bytes2, cursor3)
  +bad_back = back && (U32.is_eq(back_size, 0) || (back_size > cursor3 : U32))
  +backed = Bool.pick(U32, back && Bool.not(bad_back), back_size, 0)
  +bytes3 = Gui.box.remove(bytes2, (cursor3 - backed : U32), backed)
  +length3 = (length2 - backed : U32)
  +cursor4 = (cursor3 - backed : U32)
  +word_left = (cursor4 > 0 : U32) && J.Input.is_key_pressed(core, 263) && ctrl
  +left = Bool.not(word_left) && (cursor4 > 0 : U32) && (J.Input.is_key_pressed(core, 263) || (J.Input.is_key_down(core, 263) && trigger))
  +left_size = Gui.box.back(bytes3, cursor4)
  +bad_left = left && (U32.is_eq(left_size, 0) || (left_size > cursor4 : U32))
  +word_right = Bool.not(word_left) && Bool.not(left) && (length3 > cursor4 : U32) && J.Input.is_key_pressed(core, 262) && ctrl
  +right = Bool.not(word_left) && Bool.not(left) && Bool.not(word_right) && (length3 > cursor4 : U32) && (J.Input.is_key_pressed(core, 262) || (J.Input.is_key_down(core, 262) && trigger))
  +cursor5 = Bool.pick(U32, left && Bool.not(bad_left), (cursor4 - left_size : U32), Bool.pick(U32, right, (cursor4 + TextCore.pair.size(TextCore.next(TextCore.drop(bytes3, cursor4))) : U32), cursor4))
  +mouse = J.Input.get_mouse_position(core)
  +pressed = Gui.pressed(core)
  +lost = (offset > length3 : U32)
  +end = Gui.width.text(gui, TextCore.drop(bytes3, offset))
  +hit = Gui.box.hit(Gui.box.walk(U32.to_nat((length3 + 1 : U32)), bytes3, offset, length3, Gui.mouse.x(mouse), tbx, 0.0, Gui.scale(gui), Gui.style.f32(gui, 0, 17), 0.0), Gui.mouse.x(mouse), tbx, end, length3)
  +hx = Bool.pick(F32, J.Collision.point_rec(mouse, tb), Gui.hit.x(hit), F32.neg(1.0))
  +cursor6 = Bool.pick(U32, (hx >= 0.0 : F32) && pressed, Gui.hit.index(hit), cursor5)
  +cx = ((((bx + Gui.style.f32(gui, 9, 13) : F32) + end : F32) - Gui.width.text(gui, TextCore.drop(bytes3, cursor6)) : F32) + Gui.style.f32(gui, 0, 17) : F32)
  +done = J.Input.is_key_pressed(core, 257) || (Bool.not(J.Collision.point_rec(mouse, bounds)) && pressed)
  (core, GuiEdit{bytes3, Bool.pick(U32, done, 0, cursor6), Bool.pick(U32, done, 0, counter), offset, done, 2, cx, hx,
    stuck || word_delete || word_back || bad_back || word_left || bad_left || word_right || lost})

# The cursor's x before any update: after the text up to the cursor index.
def Gui.box.start(+gui: Gui, +tb: J.Rectangle, +bytes: +List<U32>, +index: U32) -> F32:
  J.Rectangle{+tbx, _, _, _} = tb
  +length = TextCore.len(bytes)
  ((tbx + Gui.box.span(gui, bytes, 0, Bool.pick(U32, (index > length : U32), length, index)) : F32) + Gui.style.f32(gui, 0, 17) : F32)

# mode 0: the box does not react; 1: not in edit mode (focused under the
# pointer, and a press there puts the cursor at the text's end); 2: edit mode.
def Gui.box.updated(mode: U32, +gui: Gui, +core: J.Core, +bounds: J.Rectangle, +tb: J.Rectangle, +bytes: +List<U32>, +size: U32, +editing: Gui.Editing) -> J.Core & Gui.Edit:
  match mode:
    case 0:
      GuiEditing{+index, +count} = editing
      (core, GuiEdit{bytes, index, count, 0, False{}, Gui.get_state(gui), Gui.box.start(gui, tb, bytes, index), F32.neg(1.0), False{}})
    case 1:
      GuiEditing{+index, +count} = editing
      +over = J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
      +clicked = over && Gui.pressed(core)
      (core, GuiEdit{bytes, Bool.pick(U32, clicked, TextCore.len(bytes), index), Bool.pick(U32, clicked, 0, count), 0, clicked, Bool.pick(U32, over, 1, Gui.get_state(gui)),
        Gui.box.start(gui, tb, bytes, index), F32.neg(1.0), False{}})
    case _: Gui.box.edit(J.Input.get_char_pressed(core), gui, bounds, tb, bytes, size, editing)

# The box's fill: BASE_COLOR_PRESSED, BASE_COLOR_DISABLED or BLANK.
def Gui.box.fill(state: U32, +gui: Gui) -> U32:
  match state:
    case 2: Gui.color(gui, 9, 7)
    case 3: Gui.color(gui, 9, 10)
    case _: 0

def Gui.box.pointer(shown: Bool, +gui: Gui, +x: F32, +y: F32, +h: F32, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: Gui.draw_rectangle(frame, J.Rectangle{x, y, 1.0, h}, 0, 0, Gui.color(gui, 9, 6))

# The cursor, 2 pixels wide and twice TEXT_SIZE high (kept inside the box),
# and a 1-pixel mouse cursor where a press would put it.
def Gui.box.cursors(shown: Bool, +gui: Gui, +bounds: J.Rectangle, +tb: J.Rectangle, +cx: F32, +mouse: F32, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}:
      J.Rectangle{_, +by, _, +bh} = bounds
      J.Rectangle{_, +tby, _, +tbh} = tb
      +size = Gui.style.f32(gui, 0, 16)
      +border = Gui.get_style(gui, 9, 12)
      +high = Bool.pick(F32, ((size * 2.0 : F32) >= bh : F32), (bh - U32.to_f32((border * 2 : U32)) : F32), (size * 2.0 : F32))
      +edge = (by + U32.to_f32(border) : F32)
      +y = Bool.pick(F32, (((tby + tbh / 2.0 : F32) - size : F32) < edge : F32), edge, ((tby + tbh / 2.0 : F32) - size : F32))
      Gui.box.pointer((mouse >= 0.0 : F32), gui, mouse, y, high, Gui.draw_rectangle(frame, J.Rectangle{cx, y, 2.0, high}, 0, 0, Gui.color(gui, 9, 6)))

def Gui.box.out(edit: Gui.Edit, +core: J.Core, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +tb: J.Rectangle, +editing: Bool) -> J.Frame & (J.Core & (String & (Gui.Editing & Bool))):
  GuiEdit{+bytes, +cursor, +counter, +offset, +result, +state, +cx, +mouse, +refused} = edit
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 9, 12), Gui.color(gui, 9, (state * 3 : U32)), Gui.box.fill(state, gui))
  f2 = Gui.draw_text.bytes(TextCore.drop(bytes, offset), gui, f1, tb, Gui.get_style(gui, 9, 14), Gui.color(gui, 9, (2 + state * 3 : U32)))
  f3 = Gui.box.cursors(editing && U32.is_eq(Gui.get_style(gui, 9, 16), 0), gui, bounds, tb, cx, mouse, f2)
  (Gui.refused(refused, f3), (core, (TextCore.string(bytes), (GuiEditing{cursor, counter}, result))))

def Gui.box.done(r: J.Core & Gui.Edit, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +tb: J.Rectangle, +editing: Bool) -> J.Frame & (J.Core & (String & (Gui.Editing & Bool))):
  (+core, edit) = r
  Gui.box.out(edit, core, gui, frame, bounds, tb, editing)

# GuiTextBox(bounds, text, textSize, editMode) over raygui's two text box
# globals (Gui.Editing): the frame, the Core (a typed codepoint is taken
# from its queue), the text, the globals and raygui's result (a press over
# the box out of edit mode; ENTER or a press outside it in edit mode). The
# box reacts when the gui is enabled and unlocked, no slider is dragged,
# TEXT_READONLY is 0 and the wrap mode is TEXT_WRAP_NONE. The Ctrl word
# operations (Ctrl+DELETE, BACKSPACE, LEFT, RIGHT), a box too narrow for the
# glyph before the cursor, and a cursor inside a UTF-8 sequence mark the
# frame undefined.
def Gui.text_box(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +text: String, +size: U32, +edit: Bool, +editing: Gui.Editing) -> J.Frame & (J.Core & (String & (Gui.Editing & Bool))):
  +live = Gui.active(gui) && U32.is_eq(Gui.get_style(gui, 9, 16), 0) && Bool.not(Gui.exclusive(gui)) && U32.is_eq(Gui.get_style(gui, 0, 22), 0)
  Gui.box.done(Gui.box.updated(Bool.pick(U32, live, Bool.pick(U32, edit, 2, 1), 0), gui, core, bounds, Gui.text_bounds(gui, 9, bounds), TextCore.bytes(text), size, editing),
    gui, frame, bounds, Gui.text_bounds(gui, 9, bounds), edit)
