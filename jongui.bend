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
# edit mode), GuiStatusBar, GuiPanel, GuiDropdownBox, GuiTextBox,
# GuiScrollBar and GuiScrollPanel, with the default font,
# TEXT_WRAP_NONE and raygui's icon set (src/gui_icons.bend, GuiSetIconScale). An
# icon id above 255 (raygui reads past its table) and the other wrap modes
# mark the frame undefined. See docs/GUI.md.
import Base
import ./jonlib.bend as J
import ./jonmath.bend as M
import ./src/fonts.bend as FontCore
import ./src/text.bend as TextCore
import ./src/gui_icons.bend as Icons

# raygui's guiFont: the default font, or the font GuiSetFont set, kept as
# Data (J.Font.Shared) since the Gui is copied as C copies a Font.
type Gui.Font is Data:
  GuiFontDefault{}
  GuiFontSet{font: J.Font.Shared}

# raygui's globals: guiState, guiLocked, guiAlpha, the slider drag
# (guiControlExclusiveMode and guiControlExclusiveRec), guiStyle (16
# controls of 24 properties each), guiIconScale, guiTooltip, the tooltip's
# text (guiTooltipPtr; tipped is False for NULL), the icon table
# (guiIcons, 256 icons of eight words) and guiFont.
type Gui is Data:
  Gui{state: U32, locked: Bool, alpha: F32, exclusive: Bool, exclusive_rec: J.Rectangle, style: +List<U32>, icon_scale: U32, tips: Bool, tip: String, tipped: Bool, icons: +List<U32>, font: Gui.Font}

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
  Gui{0, False{}, 1.0, False{}, J.Rectangle{0.0, 0.0, 0.0, 0.0}, Gui.style.default(), 1, False{}, "", False{}, Icons.words(), GuiFontDefault{}}

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
  Gui{_, _, _, _, _, style, _, _, _, _, _, _} = gui
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
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font} = gui
  Gui{state, locked, alpha, exclusive, rec, Gui.style.put(style, 0, control, property, value), scale, tips, tip, tipped, icons, font}

# GuiEnable: STATE_DISABLED becomes STATE_NORMAL.
def Gui.enable(gui: Gui) -> Gui:
  Gui{+state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font} = gui
  Gui{Bool.pick(U32, U32.is_eq(state, 3), 0, state), locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

# GuiDisable: STATE_NORMAL becomes STATE_DISABLED.
def Gui.disable(gui: Gui) -> Gui:
  Gui{+state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font} = gui
  Gui{Bool.pick(U32, U32.is_eq(state, 0), 3, state), locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

def Gui.lock(gui: Gui) -> Gui:
  Gui{state, _, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font} = gui
  Gui{state, True{}, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

def Gui.unlock(gui: Gui) -> Gui:
  Gui{state, _, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font} = gui
  Gui{state, False{}, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

def Gui.is_locked(gui: Gui) -> Bool:
  Gui{_, locked, _, _, _, _, _, _, _, _, _, _} = gui
  locked

def Gui.set_state(gui: Gui, state: U32) -> Gui:
  Gui{_, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font} = gui
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

def Gui.get_state(gui: Gui) -> U32:
  Gui{state, _, _, _, _, _, _, _, _, _, _, _} = gui
  state

# GuiSetAlpha: clamped to [0, 1].
def Gui.set_alpha(gui: Gui, +alpha: F32) -> Gui:
  Gui{state, locked, _, exclusive, rec, style, scale, tips, tip, tipped, icons, font} = gui
  Gui{state, locked, Bool.pick(F32, (alpha < 0.0 : F32), 0.0, Bool.pick(F32, (alpha > 1.0 : F32), 1.0, alpha)), exclusive, rec, style, scale, tips, tip, tipped, icons, font}

# A style value as the C int raygui reads it, in F32 (exact below 2^24).
# GuiSetIconScale: scales below 1 are ignored (a C int as a word).
def Gui.set_icon_scale(gui: Gui, +scale: U32) -> Gui:
  Gui{state, locked, alpha, exclusive, rec, style, old, tips, tip, tipped, icons, font} = gui
  Gui{state, locked, alpha, exclusive, rec, style, Bool.pick(U32, (scale >= 1 : U32) && (scale < 2147483648 : U32), scale, old), tips, tip, tipped, icons, font}

# GuiGetIcons: the icon table, 2048 words (eight an icon, two rows of 16
# pixels a word, the low bit first).
def Gui.icons(gui: Gui) -> +List<U32>:
  Gui{_, _, _, _, _, _, _, _, _, _, icons, _} = gui
  icons

def Gui.get_icons(gui: Gui) -> +List<U32>:
  Gui.icons(gui)

def Gui.icons.put(gui: Gui, +icons: +List<U32>) -> Gui:
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, _, font} = gui
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

# GuiEnableTooltip, GuiDisableTooltip: guiTooltip (off in a new gui).
def Gui.enable_tooltip(gui: Gui) -> Gui:
  Gui{state, locked, alpha, exclusive, rec, style, scale, _, tip, tipped, icons, font} = gui
  Gui{state, locked, alpha, exclusive, rec, style, scale, True{}, tip, tipped, icons, font}

def Gui.disable_tooltip(gui: Gui) -> Gui:
  Gui{state, locked, alpha, exclusive, rec, style, scale, _, tip, tipped, icons, font} = gui
  Gui{state, locked, alpha, exclusive, rec, style, scale, False{}, tip, tipped, icons, font}

def Gui.tip.put(gui: Gui, tip: String, +tipped: Bool) -> Gui:
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, _, _, icons, font} = gui
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

def Gui.tip.of(tooltip: Maybe<String>, gui: Gui) -> Gui:
  match tooltip:
    case None{}: Gui.tip.put(gui, "", False{})
    case Some{t}: Gui.tip.put(gui, t, True{})

# GuiSetTooltip(tooltip): the text tooltips show from now on (raygui keeps
# the pointer); None is NULL, which shows none.
def Gui.set_tooltip(gui: Gui, tooltip: Maybe<String>) -> Gui:
  Gui.tip.of(tooltip, gui)

def Gui.font(gui: Gui) -> Gui.Font:
  Gui{_, _, _, _, _, _, _, _, _, _, _, font} = gui
  font

def Gui.font.face(font: Gui.Font) -> FontCore.Face:
  match font:
    case GuiFontDefault{}: FontCore.default.face()
    case GuiFontSet{J.FontShared{+base, +padding, +glyphs, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: FontCore.Face.new(glyphs, base, padding)

# The gui font's glyphs, base size and padding.
def Gui.face(gui: Gui) -> FontCore.Face:
  Gui.font.face(Gui.font(gui))

def Gui.font.base(font: Gui.Font) -> U32:
  match font:
    case GuiFontDefault{}: 10
    case GuiFontSet{J.FontShared{+base, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: base

# GuiGetFont().baseSize.
def Gui.font_base_size(gui: Gui) -> U32:
  Gui.font.base(Gui.font(gui))

def Gui.font.put(gui: Gui, +font: Gui.Font) -> Gui:
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, _} = gui
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

def Gui.font.shared(+gui: Gui, r: J.Font & J.Font.Shared) -> Gui & J.Font:
  (font, +shared) = r
  (Gui.font.put(gui, GuiFontSet{shared}), font)

def Gui.font.chosen(+set: Bool, +gui: Gui, font: J.Font) -> Gui & J.Font:
  match set:
    case False{}: (gui, font)
    case True{}: Gui.font.shared(gui, J.Font.shared(font))

def Gui.font.informed(+gui: Gui, r: J.Font & J.FontInfo) -> Gui & J.Font:
  (font, info) = r
  J.FontInfo{_, _, _, +id} = info
  Gui.font.chosen((id > 0 : U32), gui, font)

# GuiSetFont(font): the gui draws and measures its texts with the font from
# now on, when its texture id is above 0 (raygui ignores it otherwise). The
# gui keeps a copy (raygui keeps the struct, whose pointers the caller
# owns); the font comes back.
def Gui.set_font(gui: Gui, font: J.Font) -> Gui & J.Font:
  Gui.font.informed(gui, J.Font.info(font))

def Gui.font.made(font: Gui.Font) -> J.Font:
  match font:
    case GuiFontDefault{}: J.Font.default()
    case GuiFontSet{+shared}: J.Font.of_shared(shared)

# GuiGetFont: GetFontDefault for a new gui, or a font equal to the one
# GuiSetFont set.
def Gui.get_font(gui: Gui) -> J.Font:
  Gui.font.made(Gui.font(gui))

def Gui.icon_scale(gui: Gui) -> U32:
  Gui{_, _, _, _, _, _, scale, _, _, _, _, _} = gui
  scale

def Gui.style.f32(+gui: Gui, +control: U32, +property: U32) -> F32:
  U32.to_f32(Gui.get_style(gui, control, property))

def Gui.fade(+color: U32, +alpha: F32) -> U32:
  ((color .&. 4294967040) .|. (F32.to_u32(F32.trunc((U32.to_f32((color .&. 255 : U32)) * alpha : F32))) .&. 255) : U32)

# GuiFade(GetColor(style), guiAlpha): the alpha byte times guiAlpha, truncated.
def Gui.color(+gui: Gui, +control: U32, +property: U32) -> U32:
  Gui{_, _, +alpha, _, _, _, _, _, _, _, _, _} = gui
  Gui.fade(Gui.get_style(gui, control, property), alpha)

def Gui.alpha.of(gui: Gui) -> F32:
  Gui{_, _, alpha, _, _, _, _, _, _, _, _, _} = gui
  alpha

def Gui.refused(refused: Bool, frame: J.Frame) -> J.Frame:
  match refused:
    case True{}: J.Frame.refuse(frame)
    case False{}: frame

# -----------------------------------------------------------------------------
# Text: GuiGetTextWidth and GuiDrawText with the gui's font

# The glyph's width as raygui measures and advances it: advanceX*scale, or
# the atlas rectangle's width*scale when advanceX is 0.
def Gui.glyph.scaled(glyph: FontCore.Glyph, +scale: F32) -> F32:
  FontCore.Glyph{_, _, _, +advance, _, _, +width, _} = glyph
  Bool.pick(F32, U32.is_eq(advance, 0), (width * scale : F32), (FontCore.int.f32(advance) * scale : F32))

def Gui.glyph.width(+face: FontCore.Face, +cp: U32, +scale: F32) -> F32:
  Gui.glyph.scaled(FontCore.Face.glyph(face, cp), scale)

def Gui.text.sum(+face: FontCore.Face, cps: +List<U32>, +scale: F32, +spacing: F32, +acc: F32) -> F32:
  match cps:
    case Nil{}: acc
    case Con{+cp, rest}: Gui.text.sum(face, rest, scale, spacing, (acc + (Gui.glyph.width(face, cp, scale) + spacing) : F32))

# The bytes of a line: up to the first '\n' (and, when drawn, '\r').
def Gui.line.bytes(bytes: +List<U32>, +stop_cr: Bool) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: Bool.pick(+List<U32>, U32.is_eq(b, 10) || (stop_cr && U32.is_eq(b, 13)), Nil{}, Con{b, Gui.line.bytes(rest, stop_cr)})

# TEXT_SIZE/guiFont.baseSize.
def Gui.scale(+gui: Gui) -> F32:
  (Gui.style.f32(gui, 0, 16) / U32.to_f32(Gui.font_base_size(gui)) : F32)

# GuiGetTextWidth of bytes without an icon prefix: the first line's glyph
# widths plus TEXT_SPACING each (at most 256 bytes), truncated to an int.
def Gui.width.sum(+gui: Gui, bytes: +List<U32>) -> F32:
  Gui.text.sum(Gui.face(gui), TextCore.codepoints(List.take(&2, U32, Gui.line.bytes(bytes, False{}), 256n)), Gui.scale(gui), Gui.style.f32(gui, 0, 17), 0.0)

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

# The frame a text is drawn on, with the gui's font when GuiSetFont set one
# (built from the gui's copy once for the whole text).
type Gui.Pen is Type:
  GuiPenDefault{frame: J.Frame}
  GuiPenFont{frame: J.Frame, font: J.Font}

def Gui.pen.of(font: Gui.Font, frame: J.Frame) -> Gui.Pen:
  match font:
    case GuiFontDefault{}: GuiPenDefault{frame}
    case GuiFontSet{+shared}: GuiPenFont{frame, J.Font.of_shared(shared)}

def Gui.pen.open(+gui: Gui, frame: J.Frame) -> Gui.Pen:
  Gui.pen.of(Gui.font(gui), frame)

def Gui.pen.close(pen: Gui.Pen) -> J.Frame:
  match pen:
    case GuiPenDefault{frame}: frame
    case GuiPenFont{frame, _}: frame

def Gui.pen.refuse(pen: Gui.Pen) -> Gui.Pen:
  match pen:
    case GuiPenDefault{frame}: GuiPenDefault{J.Frame.refuse(frame)}
    case GuiPenFont{frame, font}: GuiPenFont{J.Frame.refuse(frame), font}

def Gui.pen.drawn(r: J.Frame & J.Font) -> Gui.Pen:
  (frame, font) = r
  GuiPenFont{frame, font}

# DrawTextCodepoint(guiFont, codepoint, (x, y), TEXT_SIZE, tint).
def Gui.glyph.draw(pen: Gui.Pen, +cp: U32, +x: F32, +y: F32, +size: F32, +tint: U32) -> Gui.Pen:
  match pen:
    case GuiPenDefault{frame}: GuiPenDefault{J.Frame.draw(frame, FontCore.codepoint(FontCore.default.face(), 1, 128.0, 128.0, cp, x, y, size, tint))}
    case GuiPenFont{frame, font}: Gui.pen.drawn(J.Draw.text_codepoint(frame, font, cp, M.Vector2{x, y}, size, tint))

def Gui.dot(visible: Bool, pen: Gui.Pen, +x: F32, +y: F32, +size: F32, +tint: U32) -> Gui.Pen:
  match visible:
    case False{}: pen
    case True{}: Gui.glyph.draw(pen, 46, x, y, size, tint)

# The dots of an overflowing line: at j = 0, ellipsis/3, ... while j < ellipsis
# (at most five for a positive step).
def Gui.dots(n: Nat, +j: F32, +step: F32, +ellipsis: F32, +x: F32, +y: F32, +size: F32, +tint: U32, pen: Gui.Pen) -> Gui.Pen:
  match n:
    case 0n: pen
    case 1n+p: Gui.dots(p, (j + step : F32), step, ellipsis, x, y, size, tint, Gui.dot((j < ellipsis : F32), pen, (x + j : F32), y, size, tint))

# The C loop never ends for a step of 0 (an ellipsis narrower than 3).
def Gui.ellipsis(endless: Bool, +ellipsis: F32, +x: F32, +y: F32, +size: F32, +tint: U32, pen: Gui.Pen) -> Gui.Pen:
  match endless:
    case True{}: Gui.pen.refuse(pen)
    case False{}: Gui.dots(6n, 0.0, F32.trunc((ellipsis / 3.0 : F32)), ellipsis, x, y, size, tint, pen)

# inset is what an icon takes from the line's width (16 times the icon scale, plus 4), or 0.
type Gui.Line is Data:
  GuiLine{face: FontCore.Face, x: F32, y: F32, width: F32, text_width: F32, ellipsis: F32, scale: F32, spacing: F32, size: F32, tint: U32, inset: F32}

def Gui.glyphs.overflow(overflow: Bool, kind: U32) -> Bool:
  match kind:
    case 2: True{}
    case _: overflow

# kind 0: nothing; 1: the glyph; 2: the ellipsis.
def Gui.glyphs.one(kind: U32, +cp: U32, +x: F32, +y: F32, +offset: F32, +ellipsis: F32, +size: F32, +tint: U32, pen: Gui.Pen) -> Gui.Pen:
  match kind:
    case 0: pen
    case 1: Gui.glyph.draw(pen, cp, (x + offset : F32), y, size, tint)
    case _: Gui.ellipsis((F32.trunc((ellipsis / 3.0 : F32)) < 1.0 : F32), ellipsis, (x + offset : F32), y, size, tint, pen)

# One glyph of a line: drawn unless it is a space or a tab; a line wider than
# its bounds stops at the ellipsis.
def Gui.glyphs(cps: +List<U32>, +line: Gui.Line, +offset: F32, +overflow: Bool, pen: Gui.Pen) -> Gui.Pen:
  match cps:
    case Nil{}: pen
    case Con{+cp, rest}:
      GuiLine{+face, +x, +y, +width, +text_width, +ellipsis, +scale, +spacing, +size, +tint, +inset} = line
      +glyph = Gui.glyph.width(face, cp, scale)
      +blank = U32.is_eq(cp, 32) || U32.is_eq(cp, 9)
      +wide = (text_width > width : F32)
      +fits = (offset <= ((width - glyph) - inset) - ellipsis : F32)
      +kind = Bool.pick(U32, blank, 0, Bool.pick(U32, Bool.not(wide), 1, Bool.pick(U32, fits, 1, Bool.pick(U32, overflow, 0, 2))))
      Gui.glyphs(rest, line, (offset + (glyph + spacing) : F32), Gui.glyphs.overflow(overflow, kind), Gui.glyphs.one(kind, cp, x, y, offset, ellipsis, size, tint, pen))

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

def Gui.icon.bit(visible: Bool, frame: J.Frame, +x: F32, +y: F32, +pixel: F32, +color: U32) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}: Gui.draw_rectangle(frame, J.Rectangle{x, y, pixel, pixel}, 0, 0, color)

# The 32 bits of one word: two rows of 16 pixels, the low bit first. The
# offsets are C's int products (scale may be negative), then floats.
def Gui.icon.word(n: Nat, +bits: U32, +k: U32, +x: F32, +y: F32, +row: U32, +scale: U32, +color: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: Gui.icon.word(p, (bits >> 1n : U32), (k + 1 : U32), x, y, row, scale, color,
      Gui.icon.bit(U32.is_eq((bits .&. 1 : U32), 1), frame, (x + FontCore.int.f32(((k % 16) * scale : U32)) : F32), (y + FontCore.int.f32(((row + k / 16) * scale : U32)) : F32), FontCore.int.f32(scale), color))

def Gui.icon.rows(n: Nat, words: +List<U32>, +index: U32, +x: F32, +y: F32, +scale: U32, +color: U32, frame: J.Frame) -> J.Frame:
  match n words:
    case 0n _: frame
    case 1n+p Nil{}: frame
    case 1n+p Con{+bits, +rest}: Gui.icon.rows(p, rest, (index + 1 : U32), x, y, scale, color, Gui.icon.word(32n, bits, 0, x, y, (2 * index : U32), scale, color, frame))

# GuiDrawIcon(iconId, x, y, scale, color) over the gui's icon table, the
# color already faded: one GuiDrawRectangle of scale x scale pixels for each
# set bit.
def Gui.icon.drawn(has: Bool, +icons: +List<U32>, +id: U32, +x: F32, +y: F32, +scale: U32, +color: U32, frame: J.Frame) -> J.Frame:
  match has:
    case False{}: frame
    case True{}: Gui.icon.rows(8n, List.drop(&2, U32, icons, U32.to_nat((8 * id : U32))), 0, x, y, scale, color, frame)

def Gui.pen.icon(has: Bool, +icons: +List<U32>, +id: U32, +x: F32, +y: F32, +scale: U32, +color: U32, pen: Gui.Pen) -> Gui.Pen:
  match pen:
    case GuiPenDefault{frame}: GuiPenDefault{Gui.icon.drawn(has, icons, id, x, y, scale, color, frame)}
    case GuiPenFont{frame, font}: GuiPenFont{Gui.icon.drawn(has, icons, id, x, y, scale, color, frame), font}

# One line: its icon, if any, at the line's x and centered on the bounds'
# height (16 pixels times the icon scale), then the text 4 pixels after it. Only the text's last line can be
# empty for raygui (the others still have their '\n' to read).
def Gui.text.line(+icon: Gui.Icon, +last: Bool, +gui: Gui, +bounds: J.Rectangle, +alignment: U32, +tint: U32, +offset: F32, +total: F32, pen: Gui.Pen) -> Gui.Pen:
  GuiIcon{+id, +text} = icon
  J.Rectangle{+bx, +by, +bw, +bh} = bounds
  +has = (id < 256 : U32)
  +size = Gui.style.f32(gui, 0, 16)
  +empty = last && Gui.empty(text)
  +scale = Gui.icon_scale(gui)
  +wide = U32.to_f32((16 * scale : U32))
  +text_width = (Gui.width.text(gui, text) + Bool.pick(F32, has, Bool.pick(F32, empty, wide, (wide + 4.0 : F32)), 0.0) : F32)
  +x = F32.trunc(Bool.pick(F32, (text_width > bw : F32) && Bool.not(empty), bx, Gui.line.x(alignment, bx, bw, text_width)))
  +y = F32.trunc(Gui.line.y(Gui.get_style(gui, 0, 21), by, bh, offset, total))
  +inset = Bool.pick(F32, has, (wide + 4.0 : F32), 0.0)
  +spec = {GuiLine{Gui.face(gui), (x + inset : F32), y, bw, text_width, Gui.width.bytes(gui, [46, 46, 46]), Gui.scale(gui), Gui.style.f32(gui, 0, 17), size, tint, inset} : Gui.Line}
  Gui.glyphs(TextCore.codepoints(Gui.line.bytes(text, True{})), spec, 0.0, False{},
    Gui.pen.icon(has, Gui.icons(gui), id, x, F32.trunc((((by + bh / 2.0 : F32) - U32.to_f32((8 * scale : U32)) : F32) + Gui.pixel(bh) : F32)), scale, tint, pen))

def Gui.lines.last(rest: +List<+List<U32>>) -> Bool:
  match rest:
    case Nil{}: True{}
    case Con{_, _}: False{}

def Gui.text.lines(lines: +List<+List<U32>>, +gui: Gui, +bounds: J.Rectangle, +alignment: U32, +tint: U32, +offset: F32, +total: F32, pen: Gui.Pen) -> Gui.Pen:
  match lines:
    case Nil{}: pen
    case Con{+line, +rest}:
      Gui.text.lines(rest, gui, bounds, alignment, tint, (offset + (Gui.style.f32(gui, 0, 16) + Gui.style.f32(gui, 0, 20)) : F32), total,
        Gui.text.line(Gui.icon.of(line), Gui.lines.last(rest), gui, bounds, alignment, tint, offset, total, pen))

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
def Gui.icon.in(icon: Gui.Icon) -> Bool:
  GuiIcon{id, _} = icon
  (id < 256 : U32)

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
      Gui.pen.close(Gui.text.lines(lines, gui, bounds, alignment, tint, 0.0, total, Gui.pen.open(gui, frame)))

def Gui.icon.some(lines: +List<+List<U32>>) -> Bool:
  match lines:
    case Nil{}: False{}
    case Con{+line, rest}: Gui.icon.in(Gui.icon.of(line)) || Gui.icon.some(rest)

def Gui.draw_text.lines(+lines: +List<+List<U32>>, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +alignment: U32, +tint: U32) -> J.Frame:
  Gui.text.checked(Gui.has_icon(lines) || U32.is_ne(Gui.get_style(gui, 0, 22), 0) || ((Gui.icon_scale(gui) > 65536 : U32) && Gui.icon.some(lines)),
    lines, gui, bounds, alignment, tint, frame)

# GuiDrawText(text, bounds, alignment, tint): nothing for an empty text. The
# frame is undefined for a line Gui.icon.out names, a wrap mode, or an icon
# drawn at a scale above 65536.
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
  Gui{+state, +locked, _, _, _, _, _, _, _, _, _, _} = gui
  U32.is_ne(state, 3) && Bool.not(locked)

def Gui.exclusive(gui: Gui) -> Bool:
  Gui{_, _, _, exclusive, _, _, _, _, _, _, _, _} = gui
  exclusive

# The state a hovered control takes: PRESSED while the button is down, else FOCUSED.
def Gui.hover(+core: J.Core) -> U32:
  Bool.pick(U32, Gui.down(core), 2, 1)

# -----------------------------------------------------------------------------
# GuiDrawIcon, GuiIconText, GuiLoadIcons

# Whether C's int stays in range for an icon at x, y of pixel size: |x| and
# |y| below 2^30 and |size| below 2^26 (15 times the size added to either).
def Gui.icon.near(+v: U32, +limit: U32) -> Bool:
  (v < limit : U32) || ((0 - v : U32) < limit : U32)

# GuiDrawIcon(iconId, posX, posY, pixelSize, color): a GuiDrawRectangle of
# pixelSize square at (posX + (k%16)*pixelSize, posY + row*pixelSize) for
# each set bit of the icon in the gui's table, faded by guiAlpha. Ints are
# given as their bits. An id outside 0..255 (raygui reads past its table)
# and coordinates that may leave int's range (see Gui.icon.near) mark the
# frame undefined.
def Gui.draw_icon(+gui: Gui, frame: J.Frame, +id: U32, +x: U32, +y: U32, +size: U32, +color: U32) -> J.Frame:
  +fine = (id < 256 : U32) && Gui.icon.near(x, 1073741824) && Gui.icon.near(y, 1073741824) && Gui.icon.near(size, 67108864)
  Gui.refused(Bool.not(fine), Gui.icon.drawn(fine, Gui.icons(gui), id, FontCore.int.f32(x), FontCore.int.f32(y), size, Gui.fade(color, Gui.alpha.of(gui)), frame))

def Gui.icon_text.cut(+long: Bool, +bytes: +List<U32>) -> Maybe<String>:
  match long:
    case True{}: None{}
    case False{}: Some{TextCore.string(bytes)}

def Gui.icon_text.with(text: Maybe<String>, +prefix: +List<U32>) -> Maybe<String>:
  match text:
    case None{}: Some{TextCore.string(prefix)}
    case Some{t}:
      +bytes = TextCore.bytes(t)
      Gui.icon_text.cut((TextCore.len(bytes) >= 1019 : U32), TextCore.glue(TextCore.take(prefix, 5), bytes))

# GuiIconText(iconId, text): "#%03i#" (the id as C's int, at least three
# digits after any sign), then the text from the prefix's sixth byte, so a
# prefix of six or more bytes loses its last ones; a NULL text (None) gives
# the whole prefix. A text of 1019 bytes or more leaves raygui's buffer
# without its terminator: None.
def Gui.icon_text(+id: U32, text: Maybe<String>) -> Maybe<String>:
  Gui.icon_text.with(text, TextCore.glue([35], TextCore.glue(TextCore.integer.field(True{}, 10, False{}, id, 16, 3, False{}, 0), [35])))

# What GuiLoadIcons returns: NULL, the name ids (32 bytes each, as read,
# zeros past the end of the file), or a load raygui does not define.
type Gui.Names is Data:
  GuiNamesNull{}
  GuiNames{names: +List<+List<U32>>}
  GuiNamesUndefined{}

def Gui.byte(bytes: +List<U32>, +i: U32) -> U32:
  Icons.head(TextCore.drop(bytes, i))

def Gui.icons.word(+bytes: +List<U32>) -> U32:
  (Gui.byte(bytes, 0) .|. (Gui.byte(bytes, 1) << 8n) .|. (Gui.byte(bytes, 2) << 16n) .|. (Gui.byte(bytes, 3) << 24n) : U32)

# The first n words of the bytes (little-endian) over the old table.
def Gui.icons.words(n: Nat, +bytes: +List<U32>, +old: +List<U32>) -> +List<U32>:
  match n:
    case 0n: old
    case 1n+p: Con{Gui.icons.word(bytes), Gui.icons.words(p, TextCore.drop(bytes, 4), List.drop(&2, U32, old, 1n))}

def Gui.icons.name(n: Nat, +bytes: +List<U32>) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{Icons.head(bytes), Gui.icons.name(p, TextCore.drop(bytes, 1))}

def Gui.icons.names(n: Nat, +bytes: +List<U32>) -> +List<+List<U32>>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{Gui.icons.name(32n, bytes), Gui.icons.names(p, TextCore.drop(bytes, 32))}

def Gui.icons.named(names: Bool, +count: U32, +bytes: +List<U32>) -> Gui.Names:
  match names:
    case False{}: GuiNamesNull{}
    case True{}: GuiNames{Gui.icons.names(U32.to_nat(count), TextCore.drop(bytes, 12))}

def Gui.icons.fine(bad: Bool, +gui: Gui, +bytes: +List<U32>, +names: Bool, +count: U32, +read: U32) -> Gui & Gui.Names:
  match bad:
    case True{}: (gui, GuiNamesUndefined{})
    case False{}: (Gui.icons.put(gui, Gui.icons.words(U32.to_nat(read), TextCore.drop(bytes, (12 + 32 * count : U32)), Gui.icons(gui))), Gui.icons.named(names, count, bytes))

def Gui.icons.signed(signed: Bool, +gui: Gui, +bytes: +List<U32>, +names: Bool) -> Gui & Gui.Names:
  match signed:
    case False{}: (gui, GuiNamesNull{})
    case True{}:
      +n = TextCore.len(bytes)
      +count = (Gui.byte(bytes, 8) .|. (Gui.byte(bytes, 9) << 8n) : U32)
      +side = (Gui.byte(bytes, 10) .|. (Gui.byte(bytes, 11) << 8n) : U32)
      +m = Bool.pick(U32, (side >= 32768 : U32), (65536 - side : U32), side)
      +k = ((m * m : U32) / 32 : U32)
      +over = (count > 0 : U32) && (k > (2147483647 / Bool.pick(U32, U32.is_eq(count, 0), 1, count) : U32) : U32)
      +total = Bool.pick(U32, over, 0, (count * k : U32))
      +start = (12 + 32 * (count .&. 32767 : U32) : U32)
      +avail = Bool.pick(U32, (n > start : U32), (n - start : U32), 0)
      +read = U32.min(total, (avail / 4 : U32))
      +bad = (count >= 32768 : U32) || U32.is_eq(n, 9) || U32.is_eq(n, 11) || over || (read > 2048 : U32) || (((avail / 4 : U32) < total : U32) && U32.is_ne((avail % 4 : U32), 0))
      Gui.icons.fine(bad, gui, bytes, names, count, read)

def Gui.icons.loaded(r: Result<&1, &1, J.Surface.IOError, +List<U32>>, +gui: Gui, +names: Bool) -> Gui & Gui.Names:
  match r:
    case Fail{_}: (gui, GuiNamesNull{})
    case Done{+bytes}: Gui.icons.signed(U32.is_eq(Gui.byte(bytes, 0), 114) && U32.is_eq(Gui.byte(bytes, 1), 71) && U32.is_eq(Gui.byte(bytes, 2), 73) && U32.is_eq(Gui.byte(bytes, 3), 32), gui, bytes, names)

# GuiLoadIcons(fileName, loadIconsName) over a .rgi file ("rGI ", version,
# reserved, icon count and size as little-endian shorts, a 32-byte name id
# an icon, then the icons' words): the icon count times size*size/32 words
# (C's int division), as many as the file holds, are read over the table
# from its start, whatever the icon size. The gui and the name ids
# (GuiNames, when asked) or NULL (GuiNamesNull: a file that does not open
# or read, a wrong signature, or names not asked). Undefined
# (GuiNamesUndefined, the gui unchanged): a negative icon count (a gap), a
# count of words past int's range, data that would pass the 2048 words of
# the table, a file that ends inside the count, the size or a word.
def Gui.load_icons(gui: Gui, path: String, +names: Bool) -> IO(Gui & Gui.Names):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Gui & Gui.Names, J.Files.load_data(path), r => IO.pure(Gui & Gui.Names, Gui.icons.loaded(r, gui, names)))

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

# -----------------------------------------------------------------------------
# GuiTooltip

# The panel's rectangle: a border of 1 in LINE_COLOR over BACKGROUND_COLOR
# (BORDER_COLOR_DISABLED over BASE_COLOR_DISABLED when disabled).
def Gui.panel.body(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle) -> J.Frame:
  +disabled = U32.is_eq(Gui.get_state(gui), 3)
  Gui.draw_rectangle(frame, bounds, 1, Gui.color(gui, 0, Bool.pick(U32, disabled, 9, 18)), Gui.color(gui, 0, Bool.pick(U32, disabled, 10, 19)))

# Whether raygui draws a tooltip: unlocked, tooltips on, a tooltip set and no
# slider dragged.
def Gui.tip.shown(gui: Gui) -> Bool:
  Gui{_, locked, _, exclusive, _, _, _, tips, _, tipped, _, _} = gui
  Bool.not(locked) && tips && tipped && Bool.not(exclusive)

def Gui.tip.text(gui: Gui) -> String:
  Gui{_, _, _, _, _, _, _, _, tip, _, _, _} = gui
  tip

# GetTextLines's count: the lines, at most 128.
def Gui.tip.count(lines: +List<+List<U32>>, +n: U32) -> U32:
  match lines:
    case Nil{}: n
    case Con{_, rest}: Gui.tip.count(rest, U32.min((n + 1 : U32), 128))

# The tooltip's GuiPanel (no text) and its text centered in it as a GuiLabel
# without padding.
def Gui.tip.boxed(+gui: Gui, frame: J.Frame, +rec: J.Rectangle) -> J.Frame:
  Gui.label(Gui.set_style(Gui.set_style(gui, 1, 13, 0), 1, 14, 1), Gui.panel.body(gui, frame, rec), rec, Gui.tip.text(gui))

def Gui.tip.placed(e: FontCore.Extent, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +lines: U32) -> J.Frame:
  FontCore.Extent{+tx, +ty} = e
  J.Rectangle{+x, +y, +w, +h} = bounds
  +extra = U32.to_f32((8 * lines : U32))
  +px = Bool.pick(F32, (((x + tx : F32) + 16.0 : F32) > FontCore.int.f32(J.Core.get_screen_width(core)) : F32), (x - ((tx + 16.0 : F32) - w : F32) : F32), x)
  +py = Bool.pick(F32, (((((y + h : F32) + ty : F32) + 4.0 : F32) + extra : F32) > FontCore.int.f32(J.Core.get_screen_height(core)) : F32), (y - (((h + ty : F32) + 4.0 : F32) + extra : F32) : F32), y)
  Gui.tip.boxed(gui, frame, J.Rectangle{px, ((py + h : F32) + 4.0 : F32), (tx + 16.0 : F32), (ty + (8.0 * U32.to_f32(lines) : F32) : F32)})

# GuiTooltip(controlRec): the tooltip measured with MeasureTextEx (TEXT_SIZE,
# TEXT_SPACING), moved left to end at the control's right edge when it would
# pass the screen's width and above the control when it would pass its
# height; a GuiPanel 4 pixels below the control, 16 pixels wider than the
# text and 8 higher a line, and the text centered in it as a GuiLabel
# without padding.
def Gui.tip.drawn(on: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle) -> J.Frame:
  match on:
    case False{}: frame
    case True{}:
      +tip = Gui.tip.text(gui)
      Gui.tip.placed(FontCore.measure(J.Font.codepoints(tip), Gui.face(gui), Gui.style.f32(gui, 0, 16), Gui.style.f32(gui, 0, 17), 2.0),
        gui, core, frame, bounds, Gui.tip.count(Gui.lines.go(TextCore.bytes(tip), Nil{}), 0))

# GuiButton(bounds, text): the frame and whether the button was clicked (the
# pointer released over it). A focused button shows the tooltip.
def Gui.button(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: String) -> J.Frame & Bool:
  +over = Gui.active(gui) && Bool.not(Gui.exclusive(gui)) && J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
  +state = Bool.pick(U32, over, Gui.hover(core), Gui.get_state(gui))
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 2, 12), Gui.color(gui, 2, (state * 3 : U32)), Gui.color(gui, 2, (1 + state * 3 : U32)))
  f2 = Gui.draw_text(gui, f1, text, Gui.text_bounds(gui, 2, bounds), Gui.get_style(gui, 2, 14), Gui.color(gui, 2, (2 + state * 3 : U32)))
  (Gui.tip.drawn(U32.is_eq(state, 1) && Gui.tip.shown(gui), gui, core, f2, bounds), over && Gui.released(core))

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
  f2 = Gui.draw_text.bytes(bytes, gui, f1, Gui.text_bounds(gui, 3, bounds), Gui.get_style(gui, 3, 14), Gui.color(gui, 3, Gui.toggle.property(2, state, now)))
  (Gui.tip.drawn(U32.is_eq(state, 1) && Gui.tip.shown(gui), gui, core, f2, bounds), now)

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
  Gui{state, locked, alpha, _, _, style, scale, tips, tip, tipped, icons, font} = gui
  Gui{state, locked, alpha, exclusive, rec, style, scale, tips, tip, tipped, icons, font}

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
  Gui{_, _, _, +exclusive, +rec, _, _, _, _, _, _, _} = gui
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
def Gui.box.walk(n: Nat, +face: FontCore.Face, +bytes: +List<U32>, +i: U32, +length: U32, +mx: F32, +tbx: F32, +acc: F32, +scale: F32, +spacing: F32, +glyph: F32) -> Gui.Hit:
  match n:
    case 0n: GuiHit{F32.neg(1.0), 0, glyph}
    case 1n+p:
      +code = TextCore.next(TextCore.drop(bytes, i))
      +width = Gui.glyph.width(face, TextCore.pair.value(code), scale)
      Bool.pick(Gui.Hit, (i >= length : U32), GuiHit{F32.neg(1.0), 0, glyph},
        Bool.pick(Gui.Hit, (mx <= tbx + (acc + width / 2.0) : F32), GuiHit{(tbx + acc : F32), i, width},
          Gui.box.walk(p, face, bytes, (i + TextCore.pair.size(code) : U32), length, mx, tbx, (acc + (width + spacing) : F32), scale, spacing, width)))

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
  +hit = Gui.box.hit(Gui.box.walk(U32.to_nat((length3 + 1 : U32)), Gui.face(gui), bytes3, offset, length3, Gui.mouse.x(mouse), tbx, 0.0, Gui.scale(gui), Gui.style.f32(gui, 0, 17), 0.0), Gui.mouse.x(mouse), tbx, end, length3)
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
  +cursor_drawn = editing && U32.is_eq(Gui.get_style(gui, 9, 16), 0)
  f3 = Gui.box.cursors(cursor_drawn, gui, bounds, tb, cx, mouse, f2)
  f4 = Gui.tip.drawn(Bool.not(cursor_drawn) && U32.is_eq(state, 1) && Gui.tip.shown(gui), gui, core, f3, bounds)
  (Gui.refused(refused, f4), (core, (TextCore.string(bytes), (GuiEditing{cursor, counter}, result))))

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

# -----------------------------------------------------------------------------
# GuiScrollBar and GuiScrollPanel

def Gui.rec.y(rec: J.Rectangle) -> F32:
  J.Rectangle{_, y, _, _} = rec
  y

def Gui.rec.height(rec: J.Rectangle) -> F32:
  J.Rectangle{_, _, _, h} = rec
  h

def Gui.exclusive_rec(gui: Gui) -> J.Rectangle:
  Gui{_, _, _, _, rec, _, _, _, _, _, _, _} = gui
  rec

# (int)x as a word, 0 where C's conversion is undefined (the callers refuse there).
def Gui.int.of(+x: F32) -> U32:
  Bool.pick(U32, FontCore.int.valid(x), FontCore.int.of(x), 0)

# a/b for C ints with a >= 1 and b not 0, truncated toward zero.
def Gui.int.div(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, FontCore.negative(b), (0 - (a / (0 - b)) : U32), (a / b : U32))

def Gui.scroll.floor(+value: U32, +min: U32) -> U32:
  Bool.pick(U32, Gui.int.less(value, min), min, value)

# GuiScrollBar's normalization: max when above it, then min when below it.
def Gui.scroll.clamp(+value: U32, +min: U32, +max: U32) -> U32:
  Gui.scroll.floor(Bool.pick(U32, Gui.int.less(max, value), max, value), min)

def Gui.scroll.axis(axis: Maybe<F32>) -> F32:
  match axis:
    case None{}: F32.neg(1.0)
    case Some{value}: value

# GUI_SCROLL_DELTA: the wheel, plus the right trigger less the left one.
def Gui.scroll.delta(+core: J.Core) -> F32:
  ((J.Input.get_mouse_wheel_move(core) + (Gui.scroll.axis(J.Input.get_gamepad_axis_movement(core, 0, 5)) + 1.0) : F32) - (Gui.scroll.axis(J.Input.get_gamepad_axis_movement(core, 0, 4)) + 1.0) : F32)

# The scroll bar's parts: the two arrow buttons, the track between them and
# the slider on it. bad: the slider's place is not a C int.
type Gui.Scroll is Data:
  GuiScroll{first: J.Rectangle, second: J.Rectangle, track: J.Rectangle, slider: J.Rectangle, bad: Bool}

# ratio is (value - min)/range; the arrows are squares of the bar's inner
# thickness when ARROWS_VISIBLE, else empty.
def Gui.scroll.layout(vertical: Bool, +gui: Gui, +bounds: J.Rectangle, +ratio: F32) -> Gui.Scroll:
  match vertical:
    case True{}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +border = Gui.style.f32(gui, 14, 12)
      +spinner = Bool.pick(F32, U32.is_ne(Gui.get_style(gui, 14, 17), 0), (F32.trunc(w) - 2.0 * border : F32), 0.0)
      +size0 = FontCore.int.f32(Gui.scroll.floor(Gui.get_style(gui, 14, 19), 1))
      +ty = ((y + border : F32) + spinner : F32)
      +th = (((h - spinner : F32) - spinner : F32) - 2.0 * border : F32)
      +size = Bool.pick(F32, (size0 >= th : F32), (F32.trunc(th) - 2.0 : F32), size0)
      +raw = (ratio * (th - size) : F32)
      GuiScroll{J.Rectangle{(x + border : F32), (y + border : F32), spinner, spinner}, J.Rectangle{(x + border : F32), (((y + h : F32) - spinner : F32) - border : F32), spinner, spinner},
        J.Rectangle{((x + border : F32) + Gui.style.f32(gui, 14, 20) : F32), ty, (w - 2.0 * (border + Gui.style.f32(gui, 14, 20)) : F32), th},
        J.Rectangle{((x + border : F32) + Gui.style.f32(gui, 14, 18) : F32), (ty + F32.trunc(raw) : F32), (w - 2.0 * (border + Gui.style.f32(gui, 14, 18)) : F32), size},
        Bool.not(FontCore.int.valid(raw)) || Bool.not(FontCore.int.valid(th))}
    case False{}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +border = Gui.style.f32(gui, 14, 12)
      +spinner = Bool.pick(F32, U32.is_ne(Gui.get_style(gui, 14, 17), 0), (F32.trunc(h) - 2.0 * border : F32), 0.0)
      +size0 = FontCore.int.f32(Gui.scroll.floor(Gui.get_style(gui, 14, 19), 1))
      +tx = ((x + border : F32) + spinner : F32)
      +tw = (((w - spinner : F32) - spinner : F32) - 2.0 * border : F32)
      +size = Bool.pick(F32, (size0 >= tw : F32), (F32.trunc(tw) - 2.0 : F32), size0)
      +raw = (ratio * (tw - size) : F32)
      GuiScroll{J.Rectangle{(x + border : F32), (y + border : F32), spinner, spinner}, J.Rectangle{(((x + w : F32) - spinner : F32) - border : F32), (y + border : F32), spinner, spinner},
        J.Rectangle{tx, ((y + border : F32) + Gui.style.f32(gui, 14, 20) : F32), tw, (h - 2.0 * (border + Gui.style.f32(gui, 14, 20)) : F32)},
        J.Rectangle{(tx + F32.trunc(raw) : F32), ((y + border : F32) + Gui.style.f32(gui, 14, 18) : F32), size, (h - 2.0 * (border + Gui.style.f32(gui, 14, 18)) : F32)},
        Bool.not(FontCore.int.valid(raw)) || Bool.not(FontCore.int.valid(tw))}

# The value under the pointer: ((pointer - track - slider/2)*range)/(track length - slider length) + min.
def Gui.scroll.pointed(+vertical: Bool, +mouse: M.Vector2, +track: J.Rectangle, +slider: J.Rectangle, +range: U32, +min: U32) -> F32:
  M.Vector2{+mx, +my} = mouse
  +at = Bool.pick(F32, vertical, (my - Gui.rec.y(track) : F32), (mx - Gui.rec.x(track) : F32))
  +thumb = Bool.pick(F32, vertical, Gui.rec.height(slider), Gui.rec.width(slider))
  +length = Bool.pick(F32, vertical, Gui.rec.height(track), Gui.rec.width(track))
  ((((at - thumb / 2.0 : F32) * FontCore.int.f32(range) : F32) / (length - thumb) : F32) + FontCore.int.f32(min) : F32)

def Gui.scroll.arrows(visible: Bool, +gui: Gui, +vertical: Bool, +first: J.Rectangle, +second: J.Rectangle, +side: F32, +tint: U32, frame: J.Frame) -> J.Frame:
  match visible:
    case False{}: frame
    case True{}:
      Gui.draw_text(gui, Gui.draw_text(gui, frame, Bool.pick(String, vertical, "#121#", "#118#"), J.Rectangle{Gui.rec.x(first), Gui.rec.y(first), side, side}, 1, tint),
        Bool.pick(String, vertical, "#120#", "#119#"), J.Rectangle{Gui.rec.x(second), Gui.rec.y(second), side, side}, 1, tint)

def Gui.scroll.run(parts: Gui.Scroll, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +vertical: Bool, +value: U32, +min: U32, +max: U32, +range: U32, +wrong: Bool) -> J.Frame & (Gui & U32):
  GuiScroll{+first, +second, +track, +slider, +bad} = parts
  +mouse = J.Input.get_mouse_position(core)
  +live = Gui.active(gui)
  +held = Gui.exclusive(gui)
  +on_first = J.Collision.point_rec(mouse, first)
  +on_second = J.Collision.point_rec(mouse, second)
  +dragging = live && held && Gui.down(core) && Bool.not(on_first) && Bool.not(on_second)
  +mine = dragging && Gui.same(bounds, Gui.exclusive_rec(gui))
  +dropped = live && held && Bool.not(dragging)
  +over = live && Bool.not(held) && J.Collision.point_rec(mouse, bounds)
  +delta = Gui.scroll.delta(core)
  +wheeled = over && F32.is_ne(delta, 0.0)
  +pressed = over && Gui.pressed(core)
  +pointed = Gui.scroll.pointed(vertical, mouse, track, slider, range, min)
  +speed = Gui.get_style(gui, 14, 21)
  +jump = pressed && Bool.not(on_first) && Bool.not(on_second) && Bool.not(J.Collision.point_rec(mouse, slider))
  +stepped = pressed && (on_first || on_second)
  +step = Bool.pick(U32, stepped && U32.is_ne(speed, 0), Gui.int.div(range, speed), 0)
  +value1 = Bool.pick(U32, mine, Gui.int.of(pointed), Bool.pick(U32, wheeled, (value + Gui.int.of(delta) : U32), value))
  +value2 = Bool.pick(U32, jump, Gui.int.of(pointed), Bool.pick(U32, pressed && on_first, (value1 - step : U32), Bool.pick(U32, pressed && on_second, (value1 + step : U32), value1)))
  +state = Bool.pick(U32, mine, 2, Bool.pick(U32, pressed, 2, Bool.pick(U32, over, 1, Gui.get_state(gui))))
  +side = Bool.pick(F32, vertical, Gui.rec.width(bounds), Gui.rec.height(bounds))
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 14, 12), Gui.color(gui, 12, (state * 3 : U32)), Gui.color(gui, 0, 9))
  f2 = Gui.draw_rectangle(f1, track, 0, 0, Gui.color(gui, 2, 1))
  f3 = Gui.draw_rectangle(f2, slider, 0, 0, Gui.color(gui, 4, (state * 3 : U32)))
  f4 = Gui.scroll.arrows(U32.is_ne(Gui.get_style(gui, 14, 17), 0), gui, vertical, first, second, side, Gui.color(gui, 14, (2 + state * 3 : U32)), f3)
  (Gui.refused(wrong || bad || ((mine || jump) && Bool.not(FontCore.int.valid(pointed))) || (wheeled && Bool.not(FontCore.int.valid(delta))) || (stepped && U32.is_eq(speed, 0)), f4),
    (Bool.pick(Gui, dropped, Gui.with_drag(gui, False{}, J.Rectangle{0.0, 0.0, 0.0, 0.0}), Bool.pick(Gui, pressed, Gui.with_drag(gui, True{}, bounds), gui)),
      Bool.pick(U32, live, Gui.scroll.clamp(value2, min, max), value2)))

# GuiScrollBar(bounds, value, minValue, maxValue) with ints as
# two's-complement words: the frame, the Gui (a press starts a drag that
# follows the pointer outside the bounds until the button is released) and
# the value. A bar wider than high is horizontal. The wheel adds its notches;
# a press on an arrow steps by range/SCROLL_SPEED, one on the track jumps
# there. The slider is drawn where the value was on entry, as raygui does.
# A range that overflows an int, a division by a SCROLL_SPEED of 0 and a
# position that is not a C int mark the frame undefined.
def Gui.scroll_bar(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +value: U32, +min: U32, +max: U32) -> J.Frame & (Gui & U32):
  +vertical = Bool.not((Gui.rec.width(bounds) > Gui.rec.height(bounds) : F32))
  +start = Gui.scroll.clamp(value, min, max)
  +span = (max - min : U32)
  +range = Bool.pick(U32, Gui.int.less(0, span), span, 1)
  Gui.scroll.run(Gui.scroll.layout(vertical, gui, bounds, (FontCore.int.f32((start - min : U32)) / FontCore.int.f32(range) : F32)), gui, core, frame, bounds, vertical, start, min, max, range,
    Bool.pick(Bool, Gui.int.less(max, min), Bool.not(FontCore.negative(span)), FontCore.negative(span)))

# What GuiScrollPanel works out before its bars: the panel's bounds (below a
# header), the view, the two bars, the corner between them, the state, the
# vertical bar's slider size and arguments, and whether C's conversions hold.
type Gui.Pane is Data:
  GuiPane{bounds: J.Rectangle, view: J.Rectangle, across: J.Rectangle, down: J.Rectangle, corner: J.Rectangle, has_h: Bool, has_v: Bool, state: U32, slider: U32, size_v: U32, at_v: U32, min_v: U32, max_v: U32, refused: Bool}

def Gui.pane.bar(has: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bar: J.Rectangle, +size: U32, +value: U32, +min: U32, +max: U32) -> J.Frame & (Gui & U32):
  match has:
    case False{}: (frame, (gui, 0))
    case True{}: Gui.scroll_bar(Gui.set_style(gui, 14, 19, size), core, frame, bar, value, min, max)

def Gui.pane.cornered(both: Bool, +gui: Gui, +corner: J.Rectangle, +state: U32, frame: J.Frame) -> J.Frame:
  match both:
    case False{}: frame
    case True{}: Gui.draw_rectangle(frame, corner, 0, 0, Gui.color(gui, 12, (2 + state * 3 : U32)))

# The corner between the bars, the panel's border and SCROLL_SLIDER_SIZE put back.
def Gui.pane.end(rest: Gui & U32, frame: J.Frame, +pane: Gui.Pane, +sx: F32) -> J.Frame & (Gui & (M.Vector2 & J.Rectangle)):
  (+gui, +value) = rest
  GuiPane{+bounds, +view, _, _, +corner, +has_h, +has_v, +state, +slider, _, _, _, _, +refused} = pane
  f1 = Gui.pane.cornered(has_h && has_v, gui, corner, state, frame)
  (Gui.refused(refused, Gui.draw_rectangle(f1, bounds, Gui.get_style(gui, 12, 12), Gui.color(gui, 12, (state * 3 : U32)), 0)),
    (Gui.set_style(gui, 14, 19, slider), (M.Vector2{sx, Bool.pick(F32, has_v, FontCore.int.f32((0 - value : U32)), 0.0)}, view)))

def Gui.pane.last(r: J.Frame & (Gui & U32), +pane: Gui.Pane, +sx: F32) -> J.Frame & (Gui & (M.Vector2 & J.Rectangle)):
  (frame, rest) = r
  Gui.pane.end(rest, frame, pane, sx)

def Gui.pane.down(rest: Gui & U32, frame: J.Frame, +core: J.Core, +pane: Gui.Pane) -> J.Frame & (Gui & (M.Vector2 & J.Rectangle)):
  (+gui, +value) = rest
  GuiPane{_, _, _, +down, _, +has_h, +has_v, _, _, +size_v, +at_v, +min_v, +max_v, _} = pane
  Gui.pane.last(Gui.pane.bar(has_v, gui, core, frame, down, size_v, at_v, min_v, max_v), pane, Bool.pick(F32, has_h, FontCore.int.f32((0 - value : U32)), 0.0))

def Gui.pane.next(r: J.Frame & (Gui & U32), +core: J.Core, +pane: Gui.Pane) -> J.Frame & (Gui & (M.Vector2 & J.Rectangle)):
  (frame, rest) = r
  Gui.pane.down(rest, frame, core, pane)

def Gui.pane.y(scroll: M.Vector2) -> F32:
  M.Vector2{_, y} = scroll
  y

def Gui.pane.least(+value: F32, +least: F32) -> F32:
  Bool.pick(F32, (value < least : F32), least, value)

# The body below an optional header (headed: the status bar is drawn).
def Gui.pane.body(+headed: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +content: J.Rectangle, +scroll: M.Vector2) -> J.Frame & (Gui & (M.Vector2 & J.Rectangle)):
  J.Rectangle{+x, +y0, +w, +h0} = bounds
  +cw = Gui.rec.width(content)
  +ch = Gui.rec.height(content)
  +sx = Gui.mouse.x(scroll)
  +sy = Gui.pane.y(scroll)
  +y = Bool.pick(F32, headed, (y0 + 23.0 : F32), y0)
  +h = Bool.pick(F32, headed, (Gui.pane.least(h0, 48.0) - 25.0 : F32), Gui.pane.least(h0, 48.0))
  +b = Gui.style.f32(gui, 0, 12)
  +bar = Gui.style.f32(gui, 12, 18)
  +left = U32.is_eq(Gui.get_style(gui, 12, 19), 0)
  +wide = (cw > w - 2.0 * b : F32)
  +tall = (ch > h - 2.0 * b : F32)
  +has_h = wide || (tall && (cw > (w - 2.0 * b) - bar : F32))
  +has_v = tall || (has_h && (ch > (h - 2.0 * b) - bar : F32))
  +hw = Bool.pick(F32, has_h, bar, 0.0)
  +vw = Bool.pick(F32, has_v, bar, 0.0)
  +ax = (Bool.pick(F32, left, (x + vw : F32), x) + b : F32)
  +aw = Gui.pane.least(((w - vw : F32) - 2.0 * b : F32), 40.0)
  +dy = (y + b : F32)
  +dh = Gui.pane.least(((h - hw : F32) - 2.0 * b : F32), 40.0)
  +view_w = ((w - 2.0 * b : F32) - vw : F32)
  +view_h = ((h - 2.0 * b : F32) - hw : F32)
  +hmin = (Bool.pick(F32, left, (0.0 - vw : F32), 0.0) - b : F32)
  +hmax = Bool.pick(F32, has_h, ((((cw - w : F32) + vw : F32) + b : F32) - Bool.pick(F32, left, vw, 0.0) : F32), (0.0 - b : F32))
  +vmin = Bool.pick(F32, has_v, 0.0, F32.neg(1.0))
  +vmax = Bool.pick(F32, has_v, (((ch - h : F32) + hw : F32) + b : F32), (0.0 - b : F32))
  +place = {J.Rectangle{x, y, w, h} : J.Rectangle}
  +inside = Gui.active(gui) && J.Collision.point_rec(J.Input.get_mouse_position(core), place)
  +state = Bool.pick(U32, inside, Gui.hover(core), Gui.get_state(gui))
  +delta = Gui.scroll.delta(core)
  +sideways = has_h && (J.Input.is_key_down(core, 341) || J.Input.is_key_down(core, 340))
  +sx1 = Bool.pick(F32, inside && sideways, (sx + delta * Gui.pane.least((cw / w : F32), 20.0) : F32), sx)
  +sy1 = Bool.pick(F32, inside && Bool.not(sideways), (sy + delta * Gui.pane.least((ch / h : F32), 20.0) : F32), sy)
  +sx2 = Gui.pane.least(Bool.pick(F32, (sx1 > F32.neg(hmin) : F32), F32.neg(hmin), sx1), F32.neg(hmax))
  +sy2 = Gui.pane.least(Bool.pick(F32, (sy1 > F32.neg(vmin) : F32), F32.neg(vmin), sy1), F32.neg(vmax))
  +size_h = ((((w - 2.0 * b : F32) - vw : F32) / F32.trunc(cw) : F32) * ((F32.trunc(w) - 2.0 * b : F32) - vw) : F32)
  +size_v = ((((h - 2.0 * b : F32) - hw : F32) / F32.trunc(ch) : F32) * ((F32.trunc(h) - 2.0 * b : F32) - hw) : F32)
  +bad_h = has_h && Bool.not(FontCore.int.valid(size_h) && FontCore.int.valid(F32.neg(sx2)) && FontCore.int.valid(hmin) && FontCore.int.valid(hmax))
  +bad_v = has_v && Bool.not(FontCore.int.valid(size_v) && FontCore.int.valid(F32.neg(sy2)) && FontCore.int.valid(vmin) && FontCore.int.valid(vmax))
  +pane = {GuiPane{place, J.Rectangle{Bool.pick(F32, left, ((x + vw : F32) + b : F32), (x + b : F32)), dy, Bool.pick(F32, (view_w > cw : F32), cw, view_w), Bool.pick(F32, (view_h > ch : F32), ch, view_h)},
    J.Rectangle{ax, (((y + h : F32) - hw : F32) - b : F32), aw, hw}, J.Rectangle{Bool.pick(F32, left, (x + b : F32), (((x + w : F32) - vw : F32) - b : F32)), dy, vw, dh},
    J.Rectangle{Bool.pick(F32, left, ((x + b : F32) + 2.0 : F32), ((ax + aw : F32) + 2.0 : F32)), ((dy + dh : F32) + 2.0 : F32), (hw - 4.0 : F32), (vw - 4.0 : F32)},
    has_h, has_v, state, Gui.get_style(gui, 14, 19), Gui.int.of(size_v), Gui.int.of(F32.neg(sy2)), Gui.int.of(vmin), Gui.int.of(vmax), bad_h || bad_v} : Gui.Pane}
  Gui.pane.next(Gui.pane.bar(has_h, gui, core, Gui.draw_rectangle(frame, place, 0, 0, Gui.color(gui, 0, 19)), J.Rectangle{ax, (((y + h : F32) - hw : F32) - b : F32), aw, hw},
    Gui.int.of(size_h), Gui.int.of(F32.neg(sx2)), Gui.int.of(hmin), Gui.int.of(hmax)), core, pane)

def Gui.pane.headed(text: Maybe<String>, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +content: J.Rectangle, +scroll: M.Vector2) -> J.Frame & (Gui & (M.Vector2 & J.Rectangle)):
  match text:
    case None{}: Gui.pane.body(False{}, gui, core, frame, bounds, content, scroll)
    case Some{t}: Gui.pane.body(True{}, gui, core, Gui.status_bar(gui, frame, J.Rectangle{Gui.rec.x(bounds), Gui.rec.y(bounds), Gui.rec.width(bounds), 24.0}, Some{t}), bounds, content, scroll)

# GuiScrollPanel(bounds, text, content, &scroll, &view): a panel at least 48
# high (below a status bar when a text is given) over a content larger than
# it, with a scroll bar for each axis that does not fit (SCROLLBAR_WIDTH
# wide, on LISTVIEW's SCROLLBAR_SIDE). The frame, the Gui (a bar's drag),
# the scroll offset and the view: the panel's inside less the bars, no
# larger than the content. Under the pointer the wheel scrolls vertically,
# or horizontally with LEFT_CONTROL or LEFT_SHIFT down, by at least 20
# pixels a notch. Each offset is the negative of its bar's int value.
def Gui.scroll_panel(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +content: J.Rectangle, +scroll: M.Vector2) -> J.Frame & (Gui & (M.Vector2 & J.Rectangle)):
  Gui.pane.headed(text, gui, core, frame, bounds, content, scroll)

# -----------------------------------------------------------------------------
# GuiProgressBar

def Gui.progress.text(width: Maybe<F32>, +gui: Gui, frame: J.Frame, text: String, +right: Bool, +bounds: J.Rectangle, +state: U32) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+tw}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +padding = Gui.style.f32(gui, 5, 13)
      +ty = (y + h / 2.0 - F32.trunc((Gui.style.f32(gui, 0, 16) / 2.0 : F32)) : F32)
      Gui.draw_text(gui, frame, text, J.Rectangle{Bool.pick(F32, right, (x + w + padding : F32), (x - tw - padding : F32)), ty, tw, Gui.style.f32(gui, 0, 16)},
        Bool.pick(U32, right, 0, 2), Gui.color(gui, 1, (2 + state * 3 : U32)))

# The text beside the bar, TEXT_PADDING away, in the label's color.
def Gui.progress.label(+gui: Gui, frame: J.Frame, text: Maybe<String>, +right: Bool, +bounds: J.Rectangle, +state: U32) -> J.Frame:
  match text:
    case None{}: frame
    case Some{+t}: Gui.progress.text(Gui.get_text_width(gui, t), gui, frame, t, right, bounds, state)

# The left and bottom borders the value has reached.
def Gui.progress.behind(started: Bool, frame: J.Frame, +left: J.Rectangle, +bottom: J.Rectangle, +color: U32) -> J.Frame:
  match started:
    case False{}: frame
    case True{}: Gui.draw_rectangle(Gui.draw_rectangle(frame, left, 0, 0, color), bottom, 0, 0, color)

# The bottom and right borders it has not.
def Gui.progress.ahead(full: Bool, frame: J.Frame, +bottom: J.Rectangle, +right: J.Rectangle, +color: U32) -> J.Frame:
  match full:
    case True{}: frame
    case False{}: Gui.draw_rectangle(Gui.draw_rectangle(frame, bottom, 0, 0, color), right, 0, 0, color)

# Disabled: the border alone. Else the border in two colors, split at
# (int) of the bar's width, and the bar inside it; refused where that int
# conversion is undefined.
def Gui.progress.drawn(disabled: Bool, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +value: F32, +min: F32, +max: F32, +state: U32) -> J.Frame:
  match disabled:
    case True{}: Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 5, 12), Gui.color(gui, 5, (state * 3 : U32)), 0)
    case False{}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +bw = Gui.style.f32(gui, 5, 12)
      +pp = Gui.style.f32(gui, 5, 16)
      +pw = ((value / (max - min)) * (w - 2.0 * bw) : F32)
      +ipw = (F32.trunc(pw) + 0.0 : F32)
      +focused = Gui.color(gui, 5, 3)
      +normal = Gui.color(gui, 5, 0)
      +started = (value > min : F32)
      +full = (value >= max : F32)
      +tall = ((h + bw : F32) - 1.0 : F32)
      +rest = (((w - bw : F32) - ipw : F32) - 1.0 : F32)
      f1 = Gui.draw_rectangle(frame, Bool.pick(J.Rectangle, started, J.Rectangle{x, y, (ipw + bw : F32), bw}, J.Rectangle{x, y, bw, tall}), 0, 0, Bool.pick(U32, started, focused, normal))
      f2 = Gui.progress.behind(started, f1, J.Rectangle{x, (y + 1.0 : F32), bw, (h - 2.0 : F32)}, J.Rectangle{x, ((y + h : F32) - 1.0 : F32), (ipw + bw : F32), bw}, focused)
      f3 = Gui.draw_rectangle(f2, Bool.pick(J.Rectangle, full, J.Rectangle{((x + pw : F32) + bw : F32), y, bw, tall}, J.Rectangle{((x + ipw : F32) + bw : F32), y, rest, bw}), 0, 0, Bool.pick(U32, full, focused, normal))
      f4 = Gui.progress.ahead(full, f3, J.Rectangle{((x + ipw : F32) + bw : F32), ((y + h : F32) - 1.0 : F32), rest, bw}, J.Rectangle{((x + w : F32) - bw : F32), y, bw, tall}, normal)
      Gui.refused(Bool.not(FontCore.int.valid(pw)), Gui.draw_rectangle(f4, J.Rectangle{Bool.pick(F32, U32.is_eq(Gui.get_style(gui, 5, 17), 0), (x + bw : F32), (((x + w : F32) - pw : F32) - bw : F32)),
        ((y + bw : F32) + pp : F32), pw, (((h - bw : F32) - 2.0 * pp : F32) - 1.0 : F32)}, 0, 0, Gui.color(gui, 5, 7)))

# GuiProgressBar(bounds, textLeft, textRight, &value, minValue, maxValue):
# the frame and the value, which a larger one than maxValue becomes. The
# bar is value/(maxValue - minValue) of the inside wide (from the right
# with PROGRESS_SIDE 1); the border is BORDER_COLOR_FOCUSED along it and
# BORDER_COLOR_NORMAL past it. The control takes no input. A value is
# always given (the native NULL shows half the range).
def Gui.progress_bar(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, left: Maybe<String>, right: Maybe<String>, +value: F32, +min: F32, +max: F32) -> J.Frame & F32:
  +capped = Bool.pick(F32, (value > max : F32), max, value)
  +state = Gui.get_state(gui)
  (Gui.progress.label(gui, Gui.progress.label(gui, Gui.progress.drawn(U32.is_eq(state, 3), gui, frame, bounds, capped, min, max, state), left, False{}, bounds, state), right, True{}, bounds, state), capped)

# -----------------------------------------------------------------------------
# GuiListViewEx

# scrollIndex, active and focus after the control: C ints as words (-1 is
# 4294967295).
type Gui.Listed is Data:
  GuiListed{scroll: U32, active: U32, focus: U32}

def Gui.list.count(items: +List<String>, +n: U32) -> U32:
  match items:
    case Nil{}: n
    case Con{_, +rest}: Gui.list.count(rest, (n + 1 : U32))

# The first item shown on entry: scrollIndex, or 0 where it is negative or
# past the last full page.
def Gui.list.start(+scroll: U32, +count: U32, +visible: U32) -> U32:
  Bool.pick(U32, Gui.int.less(scroll, 0) || Gui.int.less((count - visible : U32), scroll), 0, scroll)

# startIndex -= (int)scrollDelta, kept from 0 to the last full page.
def Gui.list.wheeled(+start: U32, +notches: U32, +count: U32, +visible: U32) -> U32:
  +moved = (start - notches : U32)
  Bool.pick(U32, Gui.int.less(moved, 0), 0, Bool.pick(U32, Gui.int.less((count - visible : U32), moved), (count - visible : U32), moved))

# A press on an item selects it, or clears the selection where it was the
# selected one.
def Gui.list.pressed(+active: U32, +item: U32) -> U32:
  Bool.pick(U32, U32.is_eq(active, item), 4294967295, item)

# How an item is drawn: 0 normal, 1 focused, 2 selected, 3 disabled, 4
# disabled and selected. The selection goes before the focus.
def Gui.list.kind(+disabled: Bool, +index: U32, +selected: U32, +focused: U32) -> U32:
  Bool.pick(U32, disabled, Bool.pick(U32, U32.is_eq(index, selected), 4, 3), Bool.pick(U32, U32.is_eq(index, selected), 2, Bool.pick(U32, U32.is_eq(index, focused), 1, 0)))

# The place of the first visible item under the pointer, `none` where there
# is none: the item rectangles go down by `step` from y.
def Gui.list.hit(n: Nat, +i: U32, +mouse: M.Vector2, +x: F32, +y: F32, +w: F32, +h: F32, +step: F32, +none: U32, +found: U32) -> U32:
  match n:
    case 0n: found
    case 1n+k:
      Gui.list.hit(k, (i + 1 : U32), mouse, x, (y + step : F32), w, h, step, none, Bool.pick(U32, U32.is_eq(found, none) && J.Collision.point_rec(mouse, J.Rectangle{x, y, w, h}), i, found))

def Gui.list.bordered(shown: Bool, +gui: Gui, frame: J.Frame, +item: J.Rectangle) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: Gui.draw_rectangle(frame, item, Gui.get_style(gui, 12, 21), Gui.color(gui, 12, 0), 0)

# An item: its rectangle where it is selected or focused, and its text in
# the state's color.
def Gui.list.item(kind: U32, +gui: Gui, frame: J.Frame, +item: J.Rectangle, text: String) -> J.Frame:
  match kind:
    case 0: Gui.draw_text(gui, frame, text, Gui.text_bounds(gui, 12, item), Gui.get_style(gui, 12, 14), Gui.color(gui, 12, 2))
    case 1: Gui.draw_text(gui, Gui.draw_rectangle(frame, item, Gui.get_style(gui, 12, 21), Gui.color(gui, 12, 3), Gui.color(gui, 12, 4)), text, Gui.text_bounds(gui, 12, item), Gui.get_style(gui, 12, 14), Gui.color(gui, 12, 5))
    case 2: Gui.draw_text(gui, Gui.draw_rectangle(frame, item, Gui.get_style(gui, 12, 21), Gui.color(gui, 12, 6), Gui.color(gui, 12, 7)), text, Gui.text_bounds(gui, 12, item), Gui.get_style(gui, 12, 14), Gui.color(gui, 12, 8))
    case 3: Gui.draw_text(gui, frame, text, Gui.text_bounds(gui, 12, item), Gui.get_style(gui, 12, 14), Gui.color(gui, 12, 11))
    case _: Gui.draw_text(gui, Gui.draw_rectangle(frame, item, Gui.get_style(gui, 12, 21), Gui.color(gui, 12, 9), Gui.color(gui, 12, 10)), text, Gui.text_bounds(gui, 12, item), Gui.get_style(gui, 12, 14), Gui.color(gui, 12, 11))

# The visible items, from `index` down the list view.
def Gui.list.items(n: Nat, items: +List<String>, +gui: Gui, +index: U32, +selected: U32, +focused: U32, +disabled: Bool, +x: F32, +y: F32, +w: F32, +h: F32, +step: F32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+k:
      match items:
        case Nil{}: frame
        case Con{+text, +rest}:
          Gui.list.items(k, rest, gui, (index + 1 : U32), selected, focused, disabled, x, (y + step : F32), w, h, step,
            Gui.list.item(Gui.list.kind(disabled, index, selected, focused), gui, Gui.list.bordered(U32.is_ne(Gui.get_style(gui, 12, 20), 0), gui, frame, J.Rectangle{x, y, w, h}), J.Rectangle{x, y, w, h}, text))

# SCROLL_SLIDER_SIZE and SCROLL_SPEED put back after the bar.
def Gui.list.restored(rest: Gui & U32, frame: J.Frame, +slider: U32, +speed: U32, +selected: U32, +focused: U32, +bad: Bool) -> J.Frame & (Gui & Gui.Listed):
  (+gui, +value) = rest
  (Gui.refused(bad, frame), (Gui.set_style(Gui.set_style(gui, 14, 21, speed), 14, 19, slider), GuiListed{value, selected, focused}))

def Gui.list.scrolled(r: J.Frame & (Gui & U32), +slider: U32, +speed: U32, +selected: U32, +focused: U32, +bad: Bool) -> J.Frame & (Gui & Gui.Listed):
  (frame, rest) = r
  Gui.list.restored(rest, frame, slider, speed, selected, focused, bad)

# The bar at the right, inside the border: its slider is the share of the
# items that is visible, and its arrows step a page of the hidden ones.
def Gui.list.barred(use: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +start: U32, +end: U32, +count: U32, +visible: U32, +selected: U32, +focused: U32) -> J.Frame & (Gui & Gui.Listed):
  match use:
    case False{}: (frame, (gui, GuiListed{start, selected, focused}))
    case True{}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +border = Gui.style.f32(gui, 12, 12)
      +width = Gui.style.f32(gui, 12, 18)
      +size = (h * (U32.to_f32((end - start : U32)) / U32.to_f32(count)) : F32)
      Gui.list.scrolled(Gui.scroll_bar(Gui.set_style(Gui.set_style(gui, 14, 19, Gui.int.of(size)), 14, 21, (count - visible : U32)), core, frame,
        J.Rectangle{(((x + w : F32) - border : F32) - width : F32), (y + border : F32), width, (h - 2.0 * Gui.style.f32(gui, 0, 12) : F32)}, start, 0, (count - visible : U32)),
        Gui.get_style(gui, 14, 19), Gui.get_style(gui, 14, 21), selected, focused, Bool.not(FontCore.int.valid(size)))

# GuiListViewEx(bounds, text, count, &scrollIndex, &active, &focus) for the
# list of items: the frame, the Gui (the scroll bar's drag) and the three
# ints. As many items as fit are shown from scrollIndex, each
# LIST_ITEMS_HEIGHT high and LIST_ITEMS_SPACING apart; with more items than
# fit, a scroll bar SCROLLBAR_WIDTH wide stands at the right and the wheel
# moves the list an item a notch. Under the pointer an item is focused, and
# a press selects it or clears its selection; the focus is -1 with the
# pointer outside the list, and stays as given with it between items. The
# items are drawn from the index the wheel left, the focus and the selection
# being those of the index on entry, as raygui does. The frame is undefined
# for an item height or spacing above 32767 or more than 32767 items (the
# int product), a height and spacing that add up to 0 (the division), a
# list view's height that is negative or not a C int, and a wheel movement
# that is not one.
def Gui.list_view_ex(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +items: +List<String>, +scroll: U32, +active: U32, +focus: U32) -> J.Frame & (Gui & Gui.Listed):
  J.Rectangle{+bx, +by, +bw, +bh} = bounds
  +count = Gui.list.count(items, 0)
  +height = Gui.get_style(gui, 12, 16)
  +spacing = Gui.get_style(gui, 12, 17)
  +pitch = (height + spacing : U32)
  +sound = (height <= 32767 : U32) && (spacing <= 32767 : U32) && (count <= 32767 : U32) && (pitch >= 1 : U32) && (bh >= 0.0 : F32) && FontCore.int.valid(bh)
  +step = U32.to_f32(pitch)
  +use = (U32.to_f32((pitch * count : U32)) > bh : F32)
  +border = Gui.style.f32(gui, 0, 12)
  +ix = (bx + U32.to_f32(spacing) : F32)
  +iy = ((by + U32.to_f32(spacing) : F32) + border : F32)
  +iw0 = ((bw - U32.to_f32((2 * spacing : U32)) : F32) - border : F32)
  +iw = Bool.pick(F32, use, (iw0 - Gui.style.f32(gui, 12, 18) : F32), iw0)
  +ih = U32.to_f32(height)
  +visible = U32.min((Gui.int.of(bh) / U32.max(1, pitch) : U32), count)
  +start0 = Gui.list.start(scroll, count, visible)
  +live = Gui.active(gui) && Bool.not(Gui.exclusive(gui))
  +mouse = J.Input.get_mouse_position(core)
  +inside = live && J.Collision.point_rec(mouse, bounds)
  +place = Gui.list.hit(U32.to_nat(visible), 0, mouse, ix, iy, iw, ih, step, visible, visible)
  +hit = inside && (place < visible : U32)
  +over = (start0 + place : U32)
  +focused = Bool.pick(U32, live, Bool.pick(U32, inside, Bool.pick(U32, hit, over, focus), 4294967295), focus)
  +selected = Bool.pick(U32, hit && Gui.pressed(core), Gui.list.pressed(active, over), active)
  +delta = Gui.scroll.delta(core)
  +wheel = inside && use
  +start1 = Bool.pick(U32, wheel, Gui.list.wheeled(start0, Gui.int.of(delta), count, visible), start0)
  +state = Bool.pick(U32, inside, 1, Gui.get_state(gui))
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 12, 12), Gui.color(gui, 12, (state * 3 : U32)), Gui.color(gui, 0, 19))
  f2 = Gui.list.items(U32.to_nat(visible), List.drop(&2, String, items, U32.to_nat(U32.min(start1, count))), gui, start1, selected, focused, U32.is_eq(state, 3), ix, iy, iw, ih, step, f1)
  Gui.list.barred(use, gui, core, Gui.refused(Bool.not(sound) || (wheel && Bool.not(FontCore.int.valid(delta))), f2), bounds, start1, U32.min((start1 + visible : U32), count), count, visible, selected,
    focused)


# -----------------------------------------------------------------------------
# GuiWindowBox, GuiLabelButton, GuiDummyRec, GuiGrid

# GuiWindowBox(bounds, title): a panel below a status bar 24 pixels high (the
# window at least 48 high), and a close button 18 pixels square, 3 from the
# bar's top and right border, drawn with BUTTON's BORDER_WIDTH 1 and centered
# text for its ICON_CROSS_SMALL (#128#). The frame and whether the button was
# clicked. NULL titles are None.
def Gui.window_box(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, title: Maybe<String>) -> J.Frame & Bool:
  J.Rectangle{+x, +y, +w, +h} = bounds
  +sbw = Gui.style.f32(gui, 15, 12)
  +height = Bool.pick(F32, (h < 48.0 : F32), 48.0, h)
  f1 = Gui.panel(gui, frame, J.Rectangle{x, ((y + 24.0 : F32) - sbw : F32), w, ((height - 24.0 : F32) + sbw : F32)}, None{})
  f2 = Gui.status_bar(gui, f1, J.Rectangle{x, y, w, 24.0}, title)
  Gui.button(Gui.set_style(Gui.set_style(gui, 2, 12, 1), 2, 14, 1), core, f2, J.Rectangle{((((x + w : F32) - sbw : F32) - 18.0 : F32) - 3.0 : F32), (y + 3.0 : F32), 18.0, 18.0}, "#128#")

def Gui.label_button.at(+gui: Gui, +core: J.Core, frame: J.Frame, +wide: J.Rectangle, text: String) -> J.Frame & Bool:
  +over = Gui.active(gui) && Bool.not(Gui.exclusive(gui)) && J.Collision.point_rec(J.Input.get_mouse_position(core), wide)
  +state = Bool.pick(U32, over, Gui.hover(core), Gui.get_state(gui))
  (Gui.draw_text(gui, frame, text, Gui.text_bounds(gui, 1, wide), Gui.get_style(gui, 1, 14), Gui.color(gui, 1, (2 + state * 3 : U32))), over && Gui.released(core))

def Gui.label_button.drawn(width: Maybe<F32>, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: String) -> J.Frame & Bool:
  match width:
    case None{}: (J.Frame.refuse(frame), False{})
    case Some{+tw}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +pad = U32.to_f32((2 * Gui.get_style(gui, 1, 12) + 2 * Gui.get_style(gui, 1, 13) : U32))
      Gui.label_button.at(gui, core, frame, J.Rectangle{x, y, Bool.pick(F32, ((w - pad : F32) < tw : F32), ((tw + pad : F32) + 2.0 : F32), w), h}, text)

# GuiLabelButton(bounds, text): the bounds widened to the text (its width,
# LABEL's borders and paddings and 2 more pixels) when it does not fit, the
# text in LABEL's color of the state (focused over it, pressed while the
# button is down), and whether it was clicked (released over it). A text
# whose width raygui cannot measure marks the frame undefined.
def Gui.label_button(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +text: String) -> J.Frame & Bool:
  Gui.label_button.drawn(Gui.get_text_width(gui, text), gui, core, frame, bounds, text)

# GuiDummyRec(bounds, text): DEFAULT's base color (disabled or not; focus and
# press change nothing drawn) and the text centered in BUTTON's text color.
def Gui.dummy_rec(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, text: String) -> J.Frame:
  +disabled = U32.is_eq(Gui.get_state(gui), 3)
  f1 = Gui.draw_rectangle(frame, bounds, 0, 0, Gui.color(gui, 0, Bool.pick(U32, disabled, 10, 1)))
  Gui.draw_text(gui, f1, text, Gui.text_bounds(gui, 0, bounds), 1, Gui.color(gui, 2, Bool.pick(U32, disabled, 11, 2)))

# A grid line: alpha 0.6 every subdivs lines, 0.15 between, then guiAlpha.
def Gui.grid.color(+gui: Gui, +raw: U32, +major: Bool) -> U32:
  Gui{_, _, +alpha, _, _, _, _, _, _, _, _, _} = gui
  Gui.fade(Gui.fade(raw, Bool.pick(F32, major, (0.15 * 4.0 : F32), 0.15)), alpha)

def Gui.grid.vertical(n: Nat, +gui: Gui, frame: J.Frame, +x: F32, +y: F32, +h: F32, +spacing: F32, +subdivs: U32, +raw: U32, +i: U32) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+k:
      +at = ((x + ((spacing * U32.to_f32(i) : F32) / U32.to_f32(subdivs) : F32) : F32))
      Gui.grid.vertical(k, gui, Gui.draw_rectangle(frame, J.Rectangle{at, y, 1.0, (h + 1.0 : F32)}, 0, 0, Gui.grid.color(gui, raw, U32.is_eq((i % subdivs : U32), 0))),
        x, y, h, spacing, subdivs, raw, (i + 1 : U32))

def Gui.grid.horizontal(n: Nat, +gui: Gui, frame: J.Frame, +x: F32, +y: F32, +w: F32, +spacing: F32, +subdivs: U32, +raw: U32, +i: U32) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+k:
      +at = ((y + ((spacing * U32.to_f32(i) : F32) / U32.to_f32(subdivs) : F32) : F32))
      Gui.grid.horizontal(k, gui, Gui.draw_rectangle(frame, J.Rectangle{x, at, (w + 1.0 : F32), 1.0}, 0, 0, Gui.grid.color(gui, raw, U32.is_eq((i % subdivs : U32), 0))),
        x, y, w, spacing, subdivs, raw, (i + 1 : U32))

# C's (int) of a float as the int's U32 bits: truncation toward zero; None
# where the conversion is undefined (NaN, or outside the int range).
def Gui.c_int(+value: F32) -> Maybe<U32>:
  +t = F32.trunc(value)
  Bool.pick(Maybe<U32>, (t >= F32.neg(2147483648.0) : F32) && (t < 2147483648.0 : F32),
    Some{Bool.pick(U32, (t < 0.0 : F32), (0 - F32.to_u32(F32.neg(t)) : U32), F32.to_u32(t))}, None{})

# A count of lines as an int: none from 0 down.
def Gui.grid.n(+count: U32) -> Nat:
  Bool.pick(Nat, (count >= 2147483648 : U32) || U32.is_eq(count, 0), 0n, U32.to_nat(count))

def Gui.grid.when(draws: Bool, +v: U32, +h: U32, +gui: Gui, frame: J.Frame, +x: F32, +y: F32, +w: F32, +bh: F32, +spacing: F32, +subdivs: U32, +raw: U32) -> J.Frame:
  match draws:
    case False{}: frame
    case True{}: Gui.grid.horizontal(Gui.grid.n((h + 1 : U32)), gui, Gui.grid.vertical(Gui.grid.n((v + 1 : U32)), gui, frame, x, y, bh, spacing, subdivs, raw, 0), x, y, w, spacing, subdivs, raw, 0)

def Gui.grid.drawn(major: Maybe<U32>, minor: Maybe<U32>, +gui: Gui, frame: J.Frame, +x: F32, +y: F32, +w: F32, +bh: F32, +spacing: F32, +subdivs: U32, +raw: U32) -> J.Frame:
  match major minor:
    case Some{+v} Some{+h}: Gui.grid.when((subdivs >= 1 : U32) && (subdivs < 2147483648 : U32), v, h, gui, frame, x, y, w, bh, spacing, subdivs, raw)
    case _ _: J.Frame.refuse(frame)

def Gui.grid.cell(over: Bool, mouse: M.Vector2, +x: F32, +y: F32, +spacing: F32) -> M.Vector2:
  match over:
    case False{}: M.Vector2{F32.neg(1.0), F32.neg(1.0)}
    case True{}:
      M.Vector2{+mx, +my} = mouse
      M.Vector2{F32.floor(((mx - x : F32) / spacing : F32)), F32.floor(((my - y : F32) / spacing : F32))}

# GuiGrid(bounds, text, spacing, subdivs, &mouseCell): with subdivs above 0,
# vertical lines every spacing/subdivs from the left edge, 1 wide and
# height + 1 high, and horizontal ones the same way, in DEFAULT's LINE_COLOR
# (BORDER_COLOR_DISABLED when disabled) faded to 0.6 on every subdivs-th line
# and 0.15 between; the frame and the cell under the pointer (the cell's
# column and row, floor((point - corner) / spacing)), or (-1, -1) outside
# or when the gui is disabled, locked or in an exclusive control. The text
# is not drawn. subdivs is a C int as its U32 bits; a line count C cannot
# convert ((int) of a NaN or out of range) marks the frame undefined.
def Gui.grid(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +spacing: F32, +subdivs: U32) -> J.Frame & M.Vector2:
  J.Rectangle{+x, +y, +w, +h} = bounds
  +space = (spacing / Bool.pick(F32, (subdivs >= 2147483648 : U32), F32.neg(U32.to_f32((0 - subdivs : U32))), U32.to_f32(subdivs)) : F32)
  +over = Gui.active(gui) && Bool.not(Gui.exclusive(gui)) && J.Collision.point_rec(J.Input.get_mouse_position(core), J.Rectangle{x, y, w, h})
  +raw = Gui.get_style(gui, 0, Bool.pick(U32, U32.is_eq(Gui.get_state(gui), 3), 9, 18))
  (Gui.grid.drawn(Gui.c_int((w / space : F32)), Gui.c_int((h / space : F32)), gui, frame, x, y, w, h, spacing, subdivs, raw),
    Gui.grid.cell(over, J.Input.get_mouse_position(core), x, y, spacing))

# -----------------------------------------------------------------------------
# GuiToggleSlider, GuiComboBox, GuiListView

# guiAlpha.
# The bytes of item `index` (GuiTextSplit's), none past the last.
def Gui.item.at(items: +List<Gui.Item>, +index: U32) -> +List<U32>:
  match items:
    case Nil{}: Nil{}
    case Con{+item, rest}: Bool.pick(+List<U32>, U32.is_eq(index, 0), Gui.item.bytes(item), Gui.item.at(rest, (index - 1 : U32)))

# The knob of GuiToggleSlider and its state: SLIDER's base color pressed for
# the normal and pressed states, focused for the focused one; none disabled.
def Gui.toggle_slider.knob(+gui: Gui, +state: U32, frame: J.Frame, +knob: J.Rectangle) -> J.Frame:
  match state:
    case 3: frame
    case 1: Gui.draw_rectangle(frame, knob, 0, 0, Gui.color(gui, 4, 4))
    case _: Gui.draw_rectangle(frame, knob, 0, 0, Gui.color(gui, 4, 7))

def Gui.toggle_slider.drawn(width: Maybe<F32>, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +items: +List<Gui.Item>, +count: U32, +active: U32, +state: U32) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+tw}:
      J.Rectangle{+x, +y, +w, +h} = bounds
      +border = Gui.get_style(gui, 4, 12)
      +pad = Gui.get_style(gui, 4, 17)
      +kw = ((((w - U32.to_f32((2 * border : U32)) : F32) - U32.to_f32(((count + 1) * pad : U32)) : F32)) / U32.to_f32(count) : F32)
      +kx = (((x + U32.to_f32(border) : F32) + U32.to_f32(((active + 1) * pad : U32)) : F32) + (U32.to_f32(active) * kw : F32) : F32)
      +ky = ((y + U32.to_f32(border) : F32) + U32.to_f32(pad) : F32)
      +kh = ((h - U32.to_f32((2 * border : U32)) : F32) - U32.to_f32((2 * pad : U32)) : F32)
      +alpha = Gui.alpha.of(gui)
      +size = Gui.get_style(gui, 0, 16)
      f1 = Gui.draw_rectangle(frame, J.Rectangle{x, y, w, h}, border, Gui.color(gui, 3, (state * 3 : U32)), Gui.color(gui, 3, 1))
      f2 = Gui.toggle_slider.knob(gui, state, f1, J.Rectangle{kx, ky, kw, kh})
      Gui.draw_text.bytes(Gui.item.at(items, active), gui, f2,
        J.Rectangle{(((kx + (kw / 2.0 : F32)) : F32) - (tw / 2.0 : F32) : F32), ((y + (h / 2.0 : F32) : F32) - U32.to_f32((size / 2 : U32)) : F32), tw, U32.to_f32(size)},
        Gui.get_style(gui, 3, 14), Gui.fade(J.Color.with_alpha(Gui.get_style(gui, 3, (2 + state * 3 : U32)), alpha), alpha))

def Gui.toggle_slider.run(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +text: String, +items: +List<Gui.Item>, +count: U32, +active: U32) -> J.Frame & (U32 & Bool):
  +live = U32.is_ne(Gui.get_state(gui), 3) && Bool.not(Gui.is_locked(gui))
  +over = live && J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
  +down = Gui.down(core)
  +clicked = over && Bool.not(down) && Gui.released(core)
  +moved = Bool.pick(U32, clicked, (active + 1 : U32), active)
  +touched = Bool.pick(U32, over, Bool.pick(U32, down || clicked, 2, 1), Gui.get_state(gui))
  +state = Bool.pick(U32, live && U32.is_ne(moved, 0) && U32.is_ne(touched, 1), 2, touched)
  +shown = Bool.pick(U32, (moved >= count : U32), 0, moved)
  (Gui.toggle_slider.drawn(Gui.get_text_width(gui, text), gui, frame, bounds, items, count, shown, state), (shown, clicked))

def Gui.toggle_slider.of(fine: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +text: String, +items: +List<Gui.Item>, +count: U32, +active: U32) -> J.Frame & (U32 & Bool):
  match fine:
    case False{}: (J.Frame.refuse(frame), (active, False{}))
    case True{}: Gui.toggle_slider.run(gui, core, frame, bounds, text, items, count, active)

# GuiToggleSlider(bounds, text, &active): the items of `text` (';'
# separated), a knob (width - 2 border - (count + 1) padding) / count wide at
# the active item, the pointer's release over the bounds moving it on (back
# to the first past the last), the item's text centered on the knob over the
# width of the whole text, as raygui measures it. The frame, the active index
# and whether it moved. An active index below 0 (raygui indexes the items
# with it), a text of 1024 bytes or more or 128 items or more (GuiTextSplit's
# static buffers), and a text raygui cannot measure mark the frame undefined.
def Gui.toggle_slider(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +text: String, +active: U32) -> J.Frame & (U32 & Bool):
  +items = Gui.split(TextCore.bytes(text), 59, 0, Nil{})
  +count = Gui.drop.count(items, 0)
  Gui.toggle_slider.of((active < 2147483648 : U32) && (count < 128 : U32) && (TextCore.len(TextCore.bytes(text)) < 1024 : U32), gui, core, frame, bounds, text, items, count, active)

def Gui.combo.first(r: J.Frame & Bool) -> J.Frame:
  (frame, _) = r
  frame

def Gui.combo.drawn(+gui: Gui, +core: J.Core, frame: J.Frame, +box: J.Rectangle, +selector: J.Rectangle, +items: +List<Gui.Item>, +count: U32, +active: U32, +state: U32) -> J.Frame & U32:
  f1 = Gui.draw_rectangle(frame, box, Gui.get_style(gui, 7, 12), Gui.color(gui, 7, (state * 3 : U32)), Gui.color(gui, 7, (1 + state * 3 : U32)))
  f2 = Gui.draw_text.bytes(Gui.item.at(items, active), gui, f1, Gui.text_bounds(gui, 7, box), Gui.get_style(gui, 7, 14), Gui.color(gui, 7, (2 + state * 3 : U32)))
  (Gui.combo.first(Gui.button(Gui.set_style(Gui.set_style(gui, 2, 12, 1), 2, 14, 1), core, f2, selector, U32.show((active + 1 : U32)) ++ "/" ++ U32.show(count))), active)

def Gui.combo.run(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +items: +List<Gui.Item>, +count: U32, +active: U32) -> J.Frame & U32:
  J.Rectangle{+x, +y, +w, +h} = bounds
  +bw = U32.to_f32(Gui.get_style(gui, 7, 16))
  +spacing = U32.to_f32(Gui.get_style(gui, 7, 17))
  +width = (w - U32.to_f32((Gui.get_style(gui, 7, 16) + Gui.get_style(gui, 7, 17) : U32)) : F32)
  +clamped = Bool.pick(U32, (active >= 2147483648 : U32), 0, Bool.pick(U32, (active > (count - 1 : U32) : U32), (count - 1 : U32), active))
  +live = U32.is_ne(Gui.get_state(gui), 3) && Bool.not(Gui.is_locked(gui)) && (count > 1 : U32) && Bool.not(Gui.exclusive(gui))
  +mouse = J.Input.get_mouse_position(core)
  +over = live && (J.Collision.point_rec(mouse, J.Rectangle{x, y, width, h}) || J.Collision.point_rec(mouse, J.Rectangle{((x + width : F32) + spacing : F32), y, bw, h}))
  +next = Bool.pick(U32, over && Gui.pressed(core), Bool.pick(U32, ((clamped + 1 : U32) >= count : U32), 0, (clamped + 1 : U32)), clamped)
  Gui.combo.drawn(gui, core, frame, J.Rectangle{x, y, width, h}, J.Rectangle{((x + width : F32) + spacing : F32), y, bw, h}, items, count, next,
    Bool.pick(U32, over, Bool.pick(U32, Gui.down(core), 2, 1), Gui.get_state(gui)))

def Gui.combo.of(fine: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +items: +List<Gui.Item>, +count: U32, +active: U32) -> J.Frame & U32:
  match fine:
    case False{}: (J.Frame.refuse(frame), active)
    case True{}: Gui.combo.run(gui, core, frame, bounds, items, count, active)

# GuiComboBox(bounds, text, &active): the box less COMBO_BUTTON_WIDTH and
# COMBO_BUTTON_SPACING, the active item (clamped to the items) in it, and a
# GuiButton beside it, BUTTON's border 1 and centered, showing "active/count";
# a press over either (with more than one item) moves to the next item, back
# to the first past the last. The frame and the active index. A text of 1024
# bytes or more or 128 items or more marks the frame undefined.
def Gui.combo_box(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +text: String, +active: U32) -> J.Frame & U32:
  +items = Gui.split(TextCore.bytes(text), 59, 0, Nil{})
  +count = Gui.drop.count(items, 0)
  Gui.combo.of((count < 128 : U32) && (TextCore.len(TextCore.bytes(text)) < 1024 : U32), gui, core, frame, bounds, items, count, active)

def Gui.list.strings(items: +List<Gui.Item>, acc: +List<String>) -> +List<String>:
  match items:
    case Nil{}: List.reverse(&2, String, acc)
    case Con{+item, rest}: Gui.list.strings(rest, Con{TextCore.string(Gui.item.bytes(item)), acc})

def Gui.list_view.words(frame: J.Frame, +gui: Gui, listed: Gui.Listed) -> J.Frame & (Gui & (U32 & U32)):
  GuiListed{+scroll, +active, _} = listed
  (frame, (gui, (scroll, active)))

def Gui.list_view.listed(frame: J.Frame, rest: Gui & Gui.Listed) -> J.Frame & (Gui & (U32 & U32)):
  (gui, listed) = rest
  Gui.list_view.words(frame, gui, listed)

def Gui.list_view.done(r: J.Frame & (Gui & Gui.Listed)) -> J.Frame & (Gui & (U32 & U32)):
  (frame, rest) = r
  Gui.list_view.listed(frame, rest)

def Gui.list_view.of(fine: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +items: +List<String>, +scroll: U32, +active: U32) -> J.Frame & (Gui & (U32 & U32)):
  match fine:
    case False{}: (J.Frame.refuse(frame), (gui, (scroll, active)))
    case True{}: Gui.list_view.done(Gui.list_view_ex(gui, core, frame, bounds, items, scroll, active, 4294967295))

# GuiListView(bounds, text, &scrollIndex, &active): GuiListViewEx over the
# items of `text` (none for a NULL text, None) with no focus pointer (-1).
# The frame, the gui and the scroll index and active item as words. A text of
# 1024 bytes or more or 128 items or more marks the frame undefined.
def Gui.list_view(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +scroll: U32, +active: U32) -> J.Frame & (Gui & (U32 & U32)):
  match text:
    case None{}: Gui.list_view.of(True{}, gui, core, frame, bounds, Nil{}, scroll, active)
    case Some{+t}:
      +items = Gui.split(TextCore.bytes(t), 59, 0, Nil{})
      Gui.list_view.of((Gui.drop.count(items, 0) < 128 : U32) && (TextCore.len(TextCore.bytes(t)) < 1024 : U32), gui, core, frame, bounds, Gui.list.strings(items, Nil{}), scroll, active)

# -----------------------------------------------------------------------------
# GuiMessageBox, GuiTabBar

# A row of controls drawn so far: the frame and an int result (as its bits).
type Gui.Buttons is Type:
  GuiButtons{frame: J.Frame, result: U32}

def Gui.buttons.pair(row: Gui.Buttons) -> J.Frame & U32:
  GuiButtons{frame, +result} = row
  (frame, result)

def Gui.message.step(+i: U32, +result: U32, r: J.Frame & Bool) -> Gui.Buttons:
  (frame, +clicked) = r
  GuiButtons{frame, Bool.pick(U32, clicked, (i + 1 : U32), result)}

# The message box's buttons in a row, each `w` wide and 12 apart: the clicked
# one's number (from 1), or the result so far.
def Gui.message.buttons(items: +List<Gui.Item>, +gui: Gui, +core: J.Core, +x: F32, +y: F32, +w: F32, +i: U32, row: Gui.Buttons) -> Gui.Buttons:
  match items:
    case Nil{}: row
    case Con{+item, rest}:
      GuiButtons{frame, +result} = row
      Gui.message.buttons(rest, gui, core, ((x + w : F32) + 12.0 : F32), y, w, (i + 1 : U32),
        Gui.message.step(i, result, Gui.button(gui, core, frame, J.Rectangle{x, y, w, 24.0}, TextCore.string(Gui.item.bytes(item)))))

def Gui.message.closed(+gui: Gui, +core: J.Core, +x: F32, +y: F32, +w: F32, +h: F32, +message: String, +items: +List<Gui.Item>, +bw: F32, r: J.Frame & Bool) -> J.Frame & U32:
  (frame, +closed) = r
  f1 = Gui.label(Gui.set_style(gui, 1, 14, 1), frame, J.Rectangle{(x + 12.0 : F32), ((y + 24.0 : F32) + 12.0 : F32), (w - 24.0 : F32), (((h - 24.0 : F32) - 36.0 : F32) - 24.0 : F32)}, message)
  Gui.buttons.pair(Gui.message.buttons(items, Gui.set_style(gui, 2, 14, 1), core, (x + 12.0 : F32), (((y + h : F32) - 24.0 : F32) - 12.0 : F32), bw, 0,
    GuiButtons{f1, Bool.pick(U32, closed, 0, 4294967295)}))

def Gui.message.run(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, title: Maybe<String>, +message: String, +items: +List<Gui.Item>, +count: U32) -> J.Frame & U32:
  J.Rectangle{+x, +y, +w, +h} = bounds
  +bw = ((w - U32.to_f32((12 * (count + 1) : U32)) : F32) / U32.to_f32(count) : F32)
  Gui.message.closed(gui, core, x, y, w, h, message, items, bw, Gui.window_box(gui, core, frame, J.Rectangle{x, y, w, h}, title))

def Gui.message.of(fine: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, title: Maybe<String>, +message: String, +items: +List<Gui.Item>, +count: U32) -> J.Frame & U32:
  match fine:
    case False{}: (J.Frame.refuse(frame), 4294967295)
    case True{}: Gui.message.run(gui, core, frame, bounds, title, message, items, count)

# GuiMessageBox(bounds, title, message, buttons): a GuiWindowBox, the message
# centered in a label below its bar (12 pixels in, 24 + 36 + 24 pixels less
# high than the box), and the ';'-separated buttons in a row along the
# bottom, centered, 24 high and 12 apart. The frame and raygui's result: 0
# for the close button, a button's number from 1, or -1 (4294967295). A
# buttons text of 1024 bytes or more or 128 items or more marks the frame
# undefined.
def Gui.message_box(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, title: Maybe<String>, +message: String, +buttons: String) -> J.Frame & U32:
  +items = Gui.split(TextCore.bytes(buttons), 59, 0, Nil{})
  +count = Gui.drop.count(items, 0)
  Gui.message.of((count < 128 : U32) && (TextCore.len(TextCore.bytes(buttons)) < 1024 : U32), gui, core, frame, bounds, title, message, items, count)

# The tab bar so far: the frame, the active tab and raygui's result.
type Gui.Tabs is Type:
  GuiTabs{frame: J.Frame, active: U32, result: U32}

def Gui.tabs.closed(+i: U32, +active: U32, +result: U32, r: J.Frame & Bool) -> Gui.Tabs:
  (frame, +clicked) = r
  GuiTabs{frame, active, Bool.pick(U32, clicked, i, result)}

# After the tab's toggle: a middle press over it, then its close button (14
# pixels, BUTTON's border 1 and centered, #128#), each request the result.
def Gui.tabs.toggled(+gui: Gui, +core: J.Core, +x: F32, +y: F32, +w: F32, +h: F32, +i: U32, +active: U32, +result: U32, r: J.Frame & Bool) -> Gui.Tabs:
  (frame, +on) = r
  +now = Bool.pick(U32, on && U32.is_ne(i, active), i, active)
  +middle = J.Collision.point_rec(J.Input.get_mouse_position(core), J.Rectangle{x, y, w, h}) && J.Input.is_mouse_button_pressed(core, 2)
  Gui.tabs.closed(i, now, Bool.pick(U32, middle, i, result),
    Gui.button(Gui.set_style(Gui.set_style(gui, 2, 12, 1), 2, 14, 1), core, frame, J.Rectangle{(((x + w : F32) - 14.0 : F32) - 5.0 : F32), (y + 5.0 : F32), 14.0, 14.0}, "#128#"))

# A tab left of the screen's right edge: its GuiToggle (TOGGLE's text left
# aligned with a padding of 8), on for the active tab; an off tab switched
# on becomes the active one.
def Gui.tabs.step(visible: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +tab: J.Rectangle, +text: String, +i: U32, +active: U32, +result: U32) -> Gui.Tabs:
  match visible:
    case False{}: GuiTabs{frame, active, result}
    case True{}:
      J.Rectangle{+x, +y, +w, +h} = tab
      Gui.tabs.toggled(gui, core, x, y, w, h, i, active, result, Gui.toggle(Gui.set_style(Gui.set_style(gui, 3, 14, 0), 3, 13, 8), core, frame, J.Rectangle{x, y, w, h}, text, U32.is_eq(i, active)))

def Gui.tabs.run(items: +List<String>, +gui: Gui, +core: J.Core, +x: F32, +y: F32, +h: F32, +offset: U32, +screen: U32, +i: U32, tabs: Gui.Tabs) -> Gui.Tabs:
  match items:
    case Nil{}: tabs
    case Con{+text, rest}:
      GuiTabs{frame, +active, +result} = tabs
      +tx = ((x + U32.to_f32((152 * i : U32)) : F32) - U32.to_f32(offset) : F32)
      Gui.tabs.run(rest, gui, core, x, y, h, offset, screen, (i + 1 : U32),
        Gui.tabs.step((tx < U32.to_f32(screen) : F32), gui, core, frame, J.Rectangle{tx, y, 148.0, h}, text, i, active, result))

def Gui.tabs.done(+gui: Gui, +bounds: J.Rectangle, tabs: Gui.Tabs) -> J.Frame & (U32 & U32):
  J.Rectangle{+x, +y, +w, +h} = bounds
  GuiTabs{frame, +active, +result} = tabs
  (Gui.draw_rectangle(frame, J.Rectangle{x, ((y + h : F32) - 1.0 : F32), w, 1.0}, 0, 0, Gui.color(gui, 3, 0)), (active, result))

# GuiTabBar(bounds, text, count, &active): the active tab clamped to the
# tabs (-1 without any), the bar moved left by (active + 2) * 148 - the
# screen's width when that is positive, then each tab 148 wide and 152
# apart, the ones left of the screen's right edge drawn and live, and a line
# along the bottom in TOGGLE's border color. The frame, the active tab and
# raygui's result: the tab whose close button was clicked or that a middle
# press is over (the last such tab), or -1, as int bits.
def Gui.tab_bar(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +items: +List<String>, +active: U32) -> J.Frame & (U32 & U32):
  J.Rectangle{+x, +y, +w, +h} = bounds
  +count = U32.from_nat(List.length(&2, String, items))
  +low = Bool.pick(U32, Gui.int.less(active, 0), 0, active)
  +clamped = Bool.pick(U32, Gui.int.less((count - 1 : U32), low), (count - 1 : U32), low)
  +screen = J.Core.get_screen_width(core)
  +offset = (((clamped + 2 : U32) * 148 : U32) - screen : U32)
  Gui.tabs.done(gui, J.Rectangle{x, y, w, h}, Gui.tabs.run(items, gui, core, x, y, h, Bool.pick(U32, Gui.int.less(offset, 0), 0, offset), screen, 0, GuiTabs{frame, clamped, 4294967295}))

# -----------------------------------------------------------------------------
# GuiValueBoxFloat (not in edit mode)

# GuiValueBoxFloat(bounds, text, textValue, &value, editMode): the box as
# GuiValueBox draws it with the text buffer `text_value` in it (the value is
# not formatted: raygui shows the buffer the caller keeps), focused under the
# pointer; the frame, the value, unchanged outside edit mode, and whether the
# box was pressed. Edit mode (keyboard entry) marks the frame undefined.
def Gui.value_box_float(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, text_value: String, +value: F32, edit: Bool) -> J.Frame & (F32 & Bool):
  match edit:
    case True{}: (J.Frame.refuse(frame), (value, False{}))
    case False{}:
      +over = Gui.active(gui) && Bool.not(Gui.exclusive(gui)) && J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)
      +state = Bool.pick(U32, over, 1, Gui.get_state(gui))
      f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 10, 12), Gui.color(gui, 10, (state * 3 : U32)), Gui.value.fill(state, gui))
      f2 = Gui.draw_text(gui, f1, text_value, Gui.text_bounds(gui, 10, bounds), 1, Gui.color(gui, 10, (2 + state * 3 : U32)))
      (Gui.value.label(gui, f2, text, bounds, state), (value, over && Gui.pressed(core)))

# -----------------------------------------------------------------------------
# GuiTextInputBox

# What GuiTextInputBox keeps between frames: the text, the secret view (0
# off, 1 on, 2 for a NULL pointer: no secret view), raygui's static
# textEditMode and the text box globals.
type Gui.Input is Data:
  GuiInput{text: String, secret: U32, edit: Bool, editing: Gui.Editing}

def Gui.input.result(+i: U32, +result: U32, r: J.Frame & Bool) -> Gui.Buttons:
  (frame, +clicked) = r
  GuiButtons{frame, Bool.pick(U32, clicked, (i + 1 : U32), result)}

# The buttons in a row along the bottom (as GuiMessageBox's), centered.
def Gui.input.buttons(items: +List<Gui.Item>, +gui: Gui, +core: J.Core, +x: F32, +y: F32, +w: F32, +i: U32, row: Gui.Buttons) -> Gui.Buttons:
  match items:
    case Nil{}: row
    case Con{+item, rest}:
      GuiButtons{frame, +result} = row
      Gui.input.buttons(rest, gui, core, ((x + w : F32) + 12.0 : F32), y, w, (i + 1 : U32),
        Gui.input.result(i, result, Gui.button(gui, core, frame, J.Rectangle{x, y, w, 24.0}, TextCore.string(Gui.item.bytes(item)))))

def Gui.input.ended(+core: J.Core, +text: String, +secret: U32, +edit: Bool, +editing: Gui.Editing, row: Gui.Buttons) -> J.Frame & (J.Core & (Gui.Input & U32)):
  GuiButtons{frame, +result} = row
  (frame, (core, (GuiInput{text, secret, edit && (result >= 2147483648 : U32), editing}, result)))

# After the text box (and the secret view's toggle): the buttons, and
# textEditMode cleared by any result.
def Gui.input.finished(+gui: Gui, +core: J.Core, frame: J.Frame, +x: F32, +y: F32, +w: F32, +h: F32, +items: +List<Gui.Item>, +count: U32, +closed: Bool, +text: String, +secret: U32, +edit: Bool, +editing: Gui.Editing) -> J.Frame & (J.Core & (Gui.Input & U32)):
  +bw = ((w - U32.to_f32((12 * (count + 1) : U32)) : F32) / U32.to_f32(count) : F32)
  Gui.input.ended(core, text, secret, edit, editing,
    Gui.input.buttons(items, Gui.set_style(gui, 2, 14, 1), core, (x + 12.0 : F32), (((y + h : F32) - 24.0 : F32) - 12.0 : F32), bw, 0, GuiButtons{frame, Bool.pick(U32, closed, 0, 4294967295)}))

def Gui.input.viewed(+gui: Gui, +core: J.Core, +text: String, +edit: Bool, +editing: Gui.Editing, +x: F32, +y: F32, +w: F32, +h: F32, +items: +List<Gui.Item>, +count: U32, +closed: Bool, r: J.Frame & Bool) -> J.Frame & (J.Core & (Gui.Input & U32)):
  (frame, +on) = r
  Gui.input.finished(gui, core, frame, x, y, w, h, items, count, closed, text, Bool.pick(U32, on, 1, 0), edit, editing)

# The secret view's GuiToggle (#44# when on, #45# when off) beside the box,
# 26 pixels square; none without a secret pointer.
def Gui.input.toggled(secret: U32, +gui: Gui, +core: J.Core, +text: String, +edit: Bool, +editing: Gui.Editing, +x: F32, +y: F32, +w: F32, +h: F32, +bx: F32, +by: F32, +bw: F32, +items: +List<Gui.Item>, +count: U32, +closed: Bool, frame: J.Frame) -> J.Frame & (J.Core & (Gui.Input & U32)):
  match secret:
    case 2: Gui.input.finished(gui, core, frame, x, y, w, h, items, count, closed, text, 2, edit, editing)
    case _:
      +on = U32.is_eq(secret, 1)
      Gui.input.viewed(gui, core, text, edit, editing, x, y, w, h, items, count, closed,
        Gui.toggle(gui, core, frame, J.Rectangle{((bx + bw : F32) - 26.0 : F32), by, 26.0, 26.0}, Bool.pick(String, on, "#44#", "#45#"), on))

def Gui.input.boxed.state(+gui: Gui, +core: J.Core, +text: String, +edit: Bool, +secret: U32, +x: F32, +y: F32, +w: F32, +h: F32, +bx: F32, +by: F32, +bw: F32, +items: +List<Gui.Item>, +count: U32, +closed: Bool,
    frame: J.Frame, state: Gui.Editing & Bool) -> J.Frame & (J.Core & (Gui.Input & U32)):
  (+editing, +switched) = state
  +now = Bool.pick(Bool, switched, Bool.not(edit), edit)
  Gui.input.toggled(secret, gui, core, text, now, editing, x, y, w, h, bx, by, bw, items, count, closed, frame)

def Gui.input.boxed.text(+gui: Gui, +core: J.Core, +shown: Bool, +text: String, +edit: Bool, +secret: U32, +x: F32, +y: F32, +w: F32, +h: F32, +bx: F32, +by: F32, +bw: F32, +items: +List<Gui.Item>, +count: U32, +closed: Bool,
    frame: J.Frame, boxed: String & (Gui.Editing & Bool)) -> J.Frame & (J.Core & (Gui.Input & U32)):
  (+typed, state) = boxed
  Gui.input.boxed.state(gui, core, Bool.pick(String, shown, typed, text), edit, secret, x, y, w, h, bx, by, bw, items, count, closed, frame, state)

def Gui.input.boxed.rest(+gui: Gui, +shown: Bool, +text: String, +edit: Bool, +secret: U32, +x: F32, +y: F32, +w: F32, +h: F32, +bx: F32, +by: F32, +bw: F32, +items: +List<Gui.Item>, +count: U32, +closed: Bool,
    frame: J.Frame, rest: J.Core & (String & (Gui.Editing & Bool))) -> J.Frame & (J.Core & (Gui.Input & U32)):
  (+core, boxed) = rest
  Gui.input.boxed.text(gui, core, shown, text, edit, secret, x, y, w, h, bx, by, bw, items, count, closed, frame, boxed)

# The text box's answer: the Core, the text (kept when the stars were shown),
# the globals, and textEditMode switched by raygui's result.
def Gui.input.boxed(+gui: Gui, +shown: Bool, +text: String, +edit: Bool, +secret: U32, +x: F32, +y: F32, +w: F32, +h: F32, +bx: F32, +by: F32, +bw: F32, +items: +List<Gui.Item>, +count: U32, +closed: Bool,
    r: J.Frame & (J.Core & (String & (Gui.Editing & Bool)))) -> J.Frame & (J.Core & (Gui.Input & U32)):
  (frame, rest) = r
  Gui.input.boxed.rest(gui, shown, text, edit, secret, x, y, w, h, bx, by, bw, items, count, closed, frame, rest)

def Gui.int.f(+v: U32) -> F32:
  Bool.pick(F32, (v >= 2147483648 : U32), F32.neg(U32.to_f32((0 - v : U32))), U32.to_f32(v))

# a/b for a C int a and b above 0, truncated toward zero.
def Gui.int.over(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, (a >= 2147483648 : U32), (0 - ((0 - a : U32) / b) : U32), (a / b : U32))

# The message centered over the box: GuiGetTextWidth + 2 wide (an int), at
# y + 24 + height/4 - TEXT_SIZE/2.
def Gui.input.label(width: Maybe<F32>, +gui: Gui, frame: J.Frame, +m: String, +x: F32, +y: F32, +w: F32, +height: U32) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+tw}:
      +size = (F32.to_u32(tw) + 2 : U32)
      +ts = Gui.style.f32(gui, 0, 16)
      Gui.label(Gui.set_style(gui, 1, 14, 1), frame,
        J.Rectangle{((x + (w / 2.0 : F32) : F32) - U32.to_f32((size / 2 : U32)) : F32), (((y + 24.0 : F32) + Gui.int.f(Gui.int.over(height, 4)) : F32) - (ts / 2.0 : F32) : F32), U32.to_f32(size), ts}, m)

# The frame with the message drawn, and whether there was one.
def Gui.input.message(+gui: Gui, frame: J.Frame, message: Maybe<String>, +x: F32, +y: F32, +w: F32, +height: U32) -> J.Frame & Bool:
  match message:
    case None{}: (frame, False{})
    case Some{+m}: (Gui.input.label(Gui.get_text_width(gui, m), gui, frame, m, x, y, w, height), True{})

def Gui.input.labeled(+gui: Gui, +core: J.Core, +x: F32, +y: F32, +w: F32, +h: F32, +height: U32, +items: +List<Gui.Item>, +count: U32, +size: U32,
    +text: String, +secret: U32, +edit: Bool, +editing: Gui.Editing, +closed: Bool, r: J.Frame & Bool) -> J.Frame & (J.Core & (Gui.Input & U32)):
  (f1, +messaged) = r
  +plain = U32.is_eq(secret, 2)
  +shown = plain || U32.is_eq(secret, 1) || edit
  +bx = (x + 12.0 : F32)
  +bw = (w - 24.0 : F32)
  +by = Bool.pick(F32, messaged, (((y + 24.0 : F32) - 13.0 : F32) + Gui.int.f((Gui.int.over(height, 2) + Gui.int.over(height, 4) : U32)) : F32), ((y + 24.0 : F32) + 12.0 : F32))
  Gui.input.boxed(gui, shown, text, edit, secret, x, y, w, h, bx, by, bw, items, count, closed,
    Gui.text_box(Gui.set_style(gui, 9, 14, 0), core, f1, J.Rectangle{bx, by, Bool.pick(F32, plain, bw, ((bw - 4.0 : F32) - 26.0 : F32)), 26.0},
      Bool.pick(String, shown, text, "****************"), size, edit, editing))

# The window, the message, then the text box (TEXTBOX's text left aligned):
# the whole width less 24 without a secret view, 30 less with one, the stars
# "****************" shown in it unless the view is on or the box is being
# edited.
def Gui.input.windowed(+gui: Gui, +core: J.Core, message: Maybe<String>, +x: F32, +y: F32, +w: F32, +h: F32, +height: U32, +items: +List<Gui.Item>, +count: U32, +size: U32,
    +text: String, +secret: U32, +edit: Bool, +editing: Gui.Editing, r: J.Frame & Bool) -> J.Frame & (J.Core & (Gui.Input & U32)):
  (frame, +closed) = r
  Gui.input.labeled(gui, core, x, y, w, h, height, items, count, size, text, secret, edit, editing, closed, Gui.input.message(gui, frame, message, x, y, w, height))

def Gui.input.run(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, title: Maybe<String>, message: Maybe<String>, +items: +List<Gui.Item>, +count: U32, +size: U32, input: Gui.Input) -> J.Frame & (J.Core & (Gui.Input & U32)):
  J.Rectangle{+x, +y, +w, +h} = bounds
  GuiInput{+text, +secret, +edit, +editing} = input
  +height = ((((Gui.int.of(h) - 24 : U32) - Gui.get_style(gui, 15, 12) : U32) - 24 : U32) - 24 : U32)
  Gui.input.windowed(gui, core, message, x, y, w, h, height, items, count, size, text, secret, edit, editing, Gui.window_box(gui, core, frame, J.Rectangle{x, y, w, h}, title))

def Gui.input.of(fine: Bool, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, title: Maybe<String>, message: Maybe<String>, +items: +List<Gui.Item>, +count: U32, +size: U32, input: Gui.Input) -> J.Frame & (J.Core & (Gui.Input & U32)):
  match fine:
    case False{}: (J.Frame.refuse(frame), (core, (input, 4294967295)))
    case True{}: Gui.input.run(gui, core, frame, bounds, title, message, items, count, size, input)

# GuiTextInputBox(bounds, title, message, buttons, text, textMaxSize,
# secretViewActive): a GuiWindowBox, the message centered below its bar, a
# GuiTextBox (with a toggle that shows or hides the text as stars when the
# input has a secret view), and the ';'-separated buttons along the bottom;
# the box enters and leaves edit mode as raygui's static textEditMode does,
# which any result clears. The frame, the Core, the input as it is now and
# the result: 0 for the close button, a button's number from 1, or -1
# (4294967295). The text box's own refusals apply; a buttons text of 1024
# bytes or more or 128 items or more marks the frame undefined.
def Gui.text_input_box(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, title: Maybe<String>, message: Maybe<String>, +buttons: String, +size: U32, input: Gui.Input) -> J.Frame & (J.Core & (Gui.Input & U32)):
  +items = Gui.split(TextCore.bytes(buttons), 59, 0, Nil{})
  +count = Gui.drop.count(items, 0)
  Gui.input.of((count < 128 : U32) && (TextCore.len(TextCore.bytes(buttons)) < 1024 : U32), gui, core, frame, bounds, title, message, items, count, size, input)

# -----------------------------------------------------------------------------
# GuiColorPanel, GuiColorBarAlpha, GuiColorBarHue, GuiColorPicker and their
# HSV forms

# ConvertRGBtoHSV (raygui's static): the hue in degrees, saturation and value
# in [0, 1]; a gray (a spread below 0.00001) or a value at or below 0 has hue
# and saturation 0.
def Gui.hsv.of(+r: F32, +g: F32, +b: F32) -> M.Vector3:
  +low = Bool.pick(F32, (r < g : F32), r, g)
  +min = Bool.pick(F32, (low < b : F32), low, b)
  +high = Bool.pick(F32, (r > g : F32), r, g)
  +max = Bool.pick(F32, (high > b : F32), high, b)
  +delta = (max - min : F32)
  +sixth = Bool.pick(F32, (r >= max : F32), ((g - b : F32) / delta : F32),
    Bool.pick(F32, (g >= max : F32), (2.0 + ((b - r : F32) / delta : F32) : F32), (4.0 + ((r - g : F32) / delta : F32) : F32)))
  +degrees = (sixth * 60.0 : F32)
  Bool.pick(M.Vector3, (delta < 0.00001 : F32) || Bool.not((max > 0.0 : F32)), M.Vector3{0.0, 0.0, max},
    M.Vector3{Bool.pick(F32, (degrees < 0.0 : F32), (degrees + 360.0 : F32), degrees), (delta / max : F32), max})

def Gui.hsv.hue(hsv: M.Vector3) -> F32:
  M.Vector3{h, _, _} = hsv
  h

def Gui.hsv.same(a: M.Vector3, b: M.Vector3) -> Bool:
  M.Vector3{+h0, +s0, +v0} = a
  M.Vector3{+h1, +s1, +v1} = b
  F32.is_eq(h0, h1) && F32.is_eq(s0, s1) && F32.is_eq(v0, v1)

# A color's channels over 255, its HSV.
def Gui.hsv.of_color(+color: U32) -> M.Vector3:
  Gui.hsv.of((U32.to_f32(J.Color.red(color)) / 255.0 : F32), (U32.to_f32(J.Color.green(color)) / 255.0 : F32), (U32.to_f32(J.Color.blue(color)) / 255.0 : F32))

def Gui.rgb.sector(i: U32, +v: F32, +p: F32, +q: F32, +t: F32) -> M.Vector3:
  match i:
    case 0: M.Vector3{v, t, p}
    case 1: M.Vector3{q, v, p}
    case 2: M.Vector3{p, v, t}
    case 3: M.Vector3{p, q, v}
    case 4: M.Vector3{t, p, v}
    case _: M.Vector3{v, p, q}

# The sixth of the hue ConvertHSVtoRGB takes ((long)(hue/60), a hue of 360
# or more being 0).
def Gui.rgb.sixth(+h: F32) -> F32:
  (Bool.pick(F32, (h >= 360.0 : F32), 0.0, h) / 60.0 : F32)

# ConvertHSVtoRGB (raygui's static): a saturation at or below 0 is the value
# in gray; sectors 0 to 4 by (long)(hue/60), any other the last.
def Gui.rgb.of(hsv: M.Vector3) -> M.Vector3:
  M.Vector3{+h, +s, +v} = hsv
  +hh = Gui.rgb.sixth(h)
  +i = F32.trunc(hh)
  +ff = (hh - i : F32)
  +p = (v * (1.0 - s : F32) : F32)
  +q = (v * (1.0 - (s * ff : F32) : F32) : F32)
  +t = (v * (1.0 - (s * (1.0 - ff : F32) : F32) : F32) : F32)
  Bool.pick(M.Vector3, (s <= 0.0 : F32), M.Vector3{v, v, v},
    Gui.rgb.sector(Bool.pick(U32, (hh > F32.neg(1.0) : F32) && (hh < 5.0 : F32), F32.to_u32(F32.abs(i)), 5), v, p, q, t))

# Whether ConvertHSVtoRGB is defined: (long)(hue/60) needs a hue/60 in
# long's range (no NaN), unless the saturation returns first.
def Gui.rgb.fine(hsv: M.Vector3) -> Bool:
  M.Vector3{+h, +s, _} = hsv
  +hh = Gui.rgb.sixth(h)
  (s <= 0.0 : F32) || ((hh > F32.neg(9.2e18) : F32) && (hh < 9.2e18 : F32))

# (unsigned char)x: defined for x above -1 and below 256.
def Gui.uchar.fine(+x: F32) -> Bool:
  (x > F32.neg(1.0) : F32) && (x < 256.0 : F32)

def Gui.uchar(+x: F32) -> U32:
  Bool.pick(U32, (x > 0.0 : F32), F32.to_u32(F32.trunc(x)), 0)

# (unsigned char)(255*channel) of each channel, and whether all are defined.
def Gui.rgb.bytes(rgb: M.Vector3, +alpha: U32) -> U32 & Bool:
  M.Vector3{+r, +g, +b} = rgb
  +r1 = (255.0 * r : F32)
  +g1 = (255.0 * g : F32)
  +b1 = (255.0 * b : F32)
  (J.Color.rgba(Gui.uchar(r1), Gui.uchar(g1), Gui.uchar(b1), alpha), Gui.uchar.fine(r1) && Gui.uchar.fine(g1) && Gui.uchar.fine(b1))

# roundf, half away from zero.
def Gui.roundf(+x: F32) -> F32:
  +t = F32.trunc(x)
  Bool.pick(F32, (F32.abs((x - t : F32)) >= 0.5 : F32), Bool.pick(F32, (x < 0.0 : F32), (t - 1.0 : F32), (t + 1.0 : F32)), t)

# (unsigned char)roundf(255*channel) of each channel (GuiColorPicker's), and
# whether all are defined.
def Gui.rgb.rounded(rgb: M.Vector3, +alpha: U32) -> U32 & Bool:
  M.Vector3{+r, +g, +b} = rgb
  +r1 = Gui.roundf((r * 255.0 : F32))
  +g1 = Gui.roundf((g * 255.0 : F32))
  +b1 = Gui.roundf((b * 255.0 : F32))
  (J.Color.rgba(Gui.uchar(r1), Gui.uchar(g1), Gui.uchar(b1), alpha), Gui.uchar.fine(r1) && Gui.uchar.fine(g1) && Gui.uchar.fine(b1))

def Gui.vec.x(v: M.Vector2) -> F32:
  M.Vector2{x, _} = v
  x

def Gui.vec.y(v: M.Vector2) -> F32:
  M.Vector2{_, y} = v
  y

# The update of a color control: 0 untouched (or disabled, locked, or
# another control's drag), 1 this control's drag with the button down, 2
# the drag ended, 3 a press over the control (`hit`), 4 hovered.
def Gui.pick.kind(+gui: Gui, +core: J.Core, +bounds: J.Rectangle, +hit: Bool) -> U32:
  +down = Gui.down(core)
  +dragging = Bool.pick(U32, down, Bool.pick(U32, Gui.same(bounds, Gui.exclusive_rec(gui)), 1, 0), 2)
  +free = Bool.pick(U32, hit, Bool.pick(U32, down, 3, 4), 0)
  Bool.pick(U32, Gui.active(gui), Bool.pick(U32, Gui.exclusive(gui), dragging, free), 0)

# The drag after an update: started by a press, ended when the button is up.
def Gui.pick.drag(+kind: U32, +gui: Gui, +bounds: J.Rectangle) -> Gui:
  Bool.pick(Gui, U32.is_eq(kind, 3), Gui.with_drag(gui, True{}, bounds), Bool.pick(Gui, U32.is_eq(kind, 2), Gui.with_drag(gui, False{}, J.Rectangle{0.0, 0.0, 0.0, 0.0}), gui))

def Gui.pick.clamp(+v: F32, +low: F32, +high: F32) -> F32:
  Bool.pick(F32, (v < low : F32), low, Bool.pick(F32, (v > high : F32), high, v))

# The panel after its update: the gui, the state, the HSV and the selector's
# center.
type Gui.Panel is Data:
  GuiPanel{gui: Gui, state: U32, hsv: M.Vector3, x: F32, y: F32}

# A drag clamps the selector to the bounds; a press puts it at the pointer;
# either sets the saturation and value from it. Only a press makes the
# state PRESSED.
def Gui.panel_hsv.update(+kind: U32, +gui: Gui, +bounds: J.Rectangle, +mouse: M.Vector2, +hsv: M.Vector3) -> Gui.Panel:
  J.Rectangle{+bx, +by, +bw, +bh} = bounds
  M.Vector2{+mx, +my} = mouse
  M.Vector3{+h, +s, +v} = hsv
  +dragged = U32.is_eq(kind, 1)
  +pressed = U32.is_eq(kind, 3)
  +px = Bool.pick(F32, dragged, Gui.pick.clamp(mx, bx, (bx + bw : F32)), Bool.pick(F32, pressed, mx, (bx + (s * bw : F32) : F32)))
  +py = Bool.pick(F32, dragged, Gui.pick.clamp(my, by, (by + bh : F32)), Bool.pick(F32, pressed, my, (by + ((1.0 - v : F32) * bh : F32) : F32)))
  GuiPanel{Gui.pick.drag(kind, gui, bounds), Bool.pick(U32, pressed, 2, Bool.pick(U32, U32.is_eq(kind, 4), 1, Gui.get_state(gui))),
    Bool.pick(M.Vector3, dragged || pressed, M.Vector3{h, ((px - bx : F32) / bw : F32), (1.0 - ((py - by : F32) / bh : F32) : F32)}, M.Vector3{h, s, v}), px, py}

def Gui.panel_hsv.surface(disabled: Bool, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +hue: U32, +sx: F32, +sy: F32) -> J.Frame:
  match disabled:
    case True{}:
      +alpha = Gui.alpha.of(gui)
      J.Draw.rectangle_gradient_ex(frame, bounds, J.Color.with_alpha(J.Color.with_alpha(Gui.get_style(gui, 13, 10), 0.1), alpha), J.Color.with_alpha(J.Color.with_alpha(255, 0.6), alpha),
        J.Color.with_alpha(J.Color.with_alpha(255, 0.6), alpha), J.Color.with_alpha(J.Color.with_alpha(Gui.get_style(gui, 13, 9), 0.6), alpha))
    case False{}:
      +alpha = Gui.alpha.of(gui)
      f1 = J.Draw.rectangle_gradient_ex(frame, bounds, J.Color.with_alpha(4294967295, alpha), J.Color.with_alpha(4294967295, alpha), J.Color.with_alpha(hue, alpha), J.Color.with_alpha(hue, alpha))
      f2 = J.Draw.rectangle_gradient_ex(f1, bounds, J.Color.with_alpha(255, 0.0), J.Color.with_alpha(255, alpha), J.Color.with_alpha(255, alpha), J.Color.with_alpha(255, 0.0))
      +size = Gui.get_style(gui, 13, 16)
      +half = FontCore.int.f32(Gui.int.over(size, 2))
      Gui.draw_rectangle(f2, J.Rectangle{(sx - half : F32), (sy - half : F32), FontCore.int.f32(size), FontCore.int.f32(size)}, 0, 0, Gui.fade(4294967295, alpha))

def Gui.panel_hsv.drawn(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +converts: Bool, hue: U32 & Bool, panel: Gui.Panel) -> J.Frame & (Gui & M.Vector3):
  (+top, +top_bytes) = hue
  GuiPanel{+after, +state, +hsv, +sx, +sy} = panel
  +top_fine = converts && top_bytes
  +size = Gui.get_style(gui, 13, 16)
  +half = FontCore.int.f32(Gui.int.over(size, 2))
  +disabled = U32.is_eq(state, 3)
  +fine = top_fine && (disabled || (FontCore.int.valid((sx - half : F32)) && FontCore.int.valid((sy - half : F32))))
  f1 = Gui.panel_hsv.surface(disabled, gui, frame, bounds, top, sx, sy)
  f2 = Gui.draw_rectangle(f1, bounds, Gui.get_style(gui, 13, 12), Gui.color(gui, 13, (state * 3 : U32)), 0)
  (Gui.refused(Bool.not(fine), f2), (after, hsv))

# GuiColorPanelHSV(bounds, text, &colorHsv): a white-to-hue gradient under a
# clear-to-black one, a selector of COLOR_SELECTOR_SIZE (white) at the
# saturation and value, and the border. A press over the panel or a drag
# that started there sets the saturation and value from the pointer (a drag
# keeps the selector inside the bounds). The frame, the gui (the drag) and
# the HSV. The text is not drawn (raygui does not). A hue whose RGB raygui
# cannot convert, or a selector outside int's range, marks the frame
# undefined.
def Gui.panel_hsv.topped(+top: M.Vector3, +gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +hsv: M.Vector3) -> J.Frame & (Gui & M.Vector3):
  Gui.panel_hsv.drawn(gui, frame, bounds, Gui.rgb.fine(top), Gui.rgb.bytes(Gui.rgb.of(top), 255),
    Gui.panel_hsv.update(Gui.pick.kind(gui, core, bounds, J.Collision.point_rec(J.Input.get_mouse_position(core), bounds)), gui, bounds, J.Input.get_mouse_position(core), hsv))

def Gui.color_panel_hsv(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +hsv: M.Vector3) -> J.Frame & (Gui & M.Vector3):
  Gui.panel_hsv.topped(M.Vector3{Gui.hsv.hue(hsv), 1.0, 1.0}, gui, core, frame, bounds, hsv)

def Gui.color_panel.set(+changed: Bool, +converts: Bool, +color: U32, frame: J.Frame, +gui: Gui, rgb: U32 & Bool) -> J.Frame & (Gui & U32):
  (+bytes, +fine) = rgb
  (Gui.refused(changed && Bool.not(fine && converts), frame), (gui, Bool.pick(U32, changed, bytes, color)))

def Gui.color_panel.of(+before: M.Vector3, +color: U32, frame: J.Frame, rest: Gui & M.Vector3) -> J.Frame & (Gui & U32):
  (+gui, +hsv) = rest
  Gui.color_panel.set(Bool.not(Gui.hsv.same(before, hsv)), Gui.rgb.fine(hsv), color, frame, gui, Gui.rgb.bytes(Gui.rgb.of(hsv), J.Color.alpha(color)))

def Gui.color_panel.changed(+before: M.Vector3, +color: U32, r: J.Frame & (Gui & M.Vector3)) -> J.Frame & (Gui & U32):
  (frame, rest) = r
  Gui.color_panel.of(before, color, frame, rest)

# GuiColorPanel(bounds, text, &color): GuiColorPanelHSV over the color's
# HSV; when the panel changes it, the color becomes (unsigned
# char)(255*channel) of its RGB, the alpha kept. A changed HSV raygui cannot
# convert marks the frame undefined.
def Gui.color_panel(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +color: U32) -> J.Frame & (Gui & U32):
  +hsv = Gui.hsv.of_color(color)
  Gui.color_panel.changed(hsv, color, Gui.color_panel_hsv(gui, core, frame, bounds, text, hsv))

# A bar's update: the gui, the state and the value.
type Gui.Picked is Data:
  GuiPicked{gui: Gui, state: U32, value: F32}

def Gui.bar.update(+kind: U32, +gui: Gui, +bounds: J.Rectangle, +value: F32, +pointed: F32) -> Gui.Picked:
  +moved = U32.is_eq(kind, 1) || U32.is_eq(kind, 3)
  GuiPicked{Gui.pick.drag(kind, gui, bounds), Bool.pick(U32, moved, 2, Bool.pick(U32, U32.is_eq(kind, 4), 1, Gui.get_state(gui))), Bool.pick(F32, moved, pointed, value)}

# The bar's border and its selector, in BORDER + state*3.
def Gui.bar.edges(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +selector: J.Rectangle, +state: U32) -> J.Frame:
  f1 = Gui.draw_rectangle(frame, bounds, Gui.get_style(gui, 13, 12), Gui.color(gui, 13, (state * 3 : U32)), 0)
  Gui.draw_rectangle(f1, selector, 0, 0, Gui.color(gui, 13, (state * 3 : U32)))

def Gui.rec.ints(rec: J.Rectangle) -> Bool:
  J.Rectangle{+x, +y, +w, +h} = rec
  FontCore.int.valid(x) && FontCore.int.valid(y) && FontCore.int.valid(w) && FontCore.int.valid(h)

# The alpha bar's checkerboard: RAYGUI_COLORBARALPHA_CHECKED_SIZE (10)
# squares, columns outside and rows inside, BORDER_COLOR_DISABLED on odd
# squares and BASE_COLOR_DISABLED on even ones, each faded to 0.4.
def Gui.alpha.checks.column(n: Nat, +gui: Gui, +bx: F32, +by: F32, +x: U32, +y: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: Gui.alpha.checks.column(p, gui, bx, by, x, (y + 1 : U32),
      Gui.draw_rectangle(frame, J.Rectangle{(bx + U32.to_f32((x * 10 : U32)) : F32), (by + U32.to_f32((y * 10 : U32)) : F32), 10.0, 10.0}, 0, 0,
        Gui.fade(J.Color.with_alpha(Gui.get_style(gui, 13, Bool.pick(U32, U32.is_eq(((x + y) % 2 : U32), 1), 9, 10)), 0.4), Gui.alpha.of(gui))))

def Gui.alpha.checks(n: Nat, +rows: U32, +gui: Gui, +bx: F32, +by: F32, +x: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: Gui.alpha.checks(p, rows, gui, bx, by, (x + 1 : U32), Gui.alpha.checks.column(U32.to_nat(rows), gui, bx, by, x, 0, frame))

# (int)width/10 as a count: 0 for a width below 10 (negative ones too).
def Gui.alpha.count(+w: F32) -> U32:
  Bool.pick(U32, (w >= 10.0 : F32), (F32.to_u32(F32.trunc(w)) / 10 : U32), 0)

def Gui.alpha.surface(disabled: Bool, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle) -> J.Frame:
  match disabled:
    case True{}:
      J.Draw.rectangle_gradient_ex(frame, bounds, J.Color.with_alpha(Gui.get_style(gui, 13, 10), 0.1), J.Color.with_alpha(Gui.get_style(gui, 13, 10), 0.1),
        J.Color.with_alpha(Gui.get_style(gui, 13, 9), Gui.alpha.of(gui)), J.Color.with_alpha(Gui.get_style(gui, 13, 9), Gui.alpha.of(gui)))
    case False{}:
      J.Rectangle{+bx, +by, +bw, +bh} = bounds
      +alpha = Gui.alpha.of(gui)
      f1 = Gui.alpha.checks(U32.to_nat(Gui.alpha.count(bw)), Gui.alpha.count(bh), gui, bx, by, 0, frame)
      J.Draw.rectangle_gradient_ex(f1, J.Rectangle{bx, by, bw, bh}, 4294967040, 4294967040, J.Color.with_alpha(255, alpha), J.Color.with_alpha(255, alpha))

def Gui.alpha.drawn(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +selector: J.Rectangle, bar: Gui.Picked) -> J.Frame & (Gui & F32):
  GuiPicked{+after, +state, +value} = bar
  +disabled = U32.is_eq(state, 3)
  +fine = Gui.rec.ints(selector) && (disabled || Gui.rec.ints(J.Rectangle{0.0, 0.0, Gui.rec.width(bounds), Gui.rec.height(bounds)}))
  (Gui.refused(Bool.not(fine), Gui.bar.edges(gui, Gui.alpha.surface(disabled, gui, frame, bounds), bounds, selector, state)), (after, value))

# The alpha bar's selector, placed by the alpha before the update.
def Gui.alpha.selector(+gui: Gui, +bounds: J.Rectangle, +alpha: F32) -> J.Rectangle:
  J.Rectangle{+bx, +by, +bw, +bh} = bounds
  +height = Gui.get_style(gui, 13, 19)
  +over = Gui.get_style(gui, 13, 20)
  J.Rectangle{((bx + (alpha * bw : F32) : F32) - FontCore.int.f32(Gui.int.over(height, 2)) : F32), (by - FontCore.int.f32(over) : F32), FontCore.int.f32(height), (bh + FontCore.int.f32((over * 2 : U32)) : F32)}

def Gui.alpha.run(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +selector: J.Rectangle, +alpha: F32) -> J.Frame & (Gui & F32):
  +mouse = J.Input.get_mouse_position(core)
  +pointed = ((Gui.vec.x(mouse) - Gui.rec.x(bounds) : F32) / Gui.rec.width(bounds) : F32)
  Gui.alpha.drawn(gui, frame, bounds, selector,
    Gui.bar.update(Gui.pick.kind(gui, core, bounds, J.Collision.point_rec(mouse, bounds) || J.Collision.point_rec(mouse, selector)),
      gui, bounds, alpha, Bool.pick(F32, (pointed <= 0.0 : F32), 0.0, Bool.pick(F32, (pointed >= 1.0 : F32), 1.0, pointed))))

# GuiColorBarAlpha(bounds, text, &alpha): a checkerboard under a clear-to-
# black gradient, the border, and a selector HUEBAR_SELECTOR_HEIGHT wide
# (placed by the alpha before the update) passing the bar by
# HUEBAR_SELECTOR_OVERFLOW. A press over the bar or the selector, or a drag
# that started there, sets the alpha from the pointer, clamped to [0, 1].
# The frame, the gui (the drag) and the alpha. A bar or selector outside
# int's range marks the frame undefined.
def Gui.color_bar_alpha(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +alpha: F32) -> J.Frame & (Gui & F32):
  Gui.alpha.run(gui, core, frame, bounds, Gui.alpha.selector(gui, bounds, alpha), alpha)

# One sixth of the hue bar: DrawRectangleGradientV with C int arguments.
def Gui.hue.band(frame: J.Frame, +bx: F32, +y: F32, +bw: F32, +h: F32, +top: U32, +bottom: U32, +alpha: F32) -> J.Frame:
  J.Draw.rectangle_gradient_v(frame, F32.trunc(bx), F32.trunc(y), F32.trunc(bw), F32.trunc(h), J.Color.with_alpha(top, alpha), J.Color.with_alpha(bottom, alpha))

def Gui.hue.surface(disabled: Bool, +gui: Gui, frame: J.Frame, +bounds: J.Rectangle) -> J.Frame:
  match disabled:
    case True{}:
      J.Rectangle{+bx, +by, +bw, +bh} = bounds
      Gui.hue.band(frame, bx, by, bw, bh, J.Color.with_alpha(Gui.get_style(gui, 13, 10), 0.1), Gui.get_style(gui, 13, 9), Gui.alpha.of(gui))
    case False{}:
      J.Rectangle{+bx, +by, +bw, +bh} = bounds
      +alpha = Gui.alpha.of(gui)
      +sixth = (bh / 6.0 : F32)
      +tall = F32.ceil(sixth)
      f1 = Gui.hue.band(frame, bx, by, bw, tall, 4278190335, 4294902015, alpha)
      f2 = Gui.hue.band(f1, bx, (by + sixth : F32), bw, tall, 4294902015, 16711935, alpha)
      f3 = Gui.hue.band(f2, bx, (by + (2.0 * sixth : F32) : F32), bw, tall, 16711935, 16777215, alpha)
      f4 = Gui.hue.band(f3, bx, (by + (3.0 * sixth : F32) : F32), bw, tall, 16777215, 65535, alpha)
      f5 = Gui.hue.band(f4, bx, (by + (4.0 * sixth : F32) : F32), bw, tall, 65535, 4278255615, alpha)
      Gui.hue.band(f5, bx, (by + (5.0 * sixth : F32) : F32), bw, sixth, 4278255615, 4278190335, alpha)

def Gui.hue.drawn(+gui: Gui, frame: J.Frame, +bounds: J.Rectangle, +selector: J.Rectangle, bar: Gui.Picked) -> J.Frame & (Gui & F32):
  GuiPicked{+after, +state, +value} = bar
  +disabled = U32.is_eq(state, 3)
  (Gui.refused(Bool.not(Gui.rec.ints(selector)), Gui.bar.edges(gui, Gui.hue.surface(disabled, gui, frame, bounds), bounds, selector, state)), (after, value))

# The hue bar's selector, placed by the hue before the update.
def Gui.hue.selector(+gui: Gui, +bounds: J.Rectangle, +hue: F32) -> J.Rectangle:
  J.Rectangle{+bx, +by, +bw, +bh} = bounds
  +height = Gui.get_style(gui, 13, 19)
  +over = Gui.get_style(gui, 13, 20)
  J.Rectangle{(bx - FontCore.int.f32(over) : F32), ((by + ((hue / 360.0 : F32) * bh : F32) : F32) - FontCore.int.f32(Gui.int.over(height, 2)) : F32), (bw + FontCore.int.f32((over * 2 : U32)) : F32), FontCore.int.f32(height)}

def Gui.hue.run(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, +selector: J.Rectangle, +hue: F32) -> J.Frame & (Gui & F32):
  +mouse = J.Input.get_mouse_position(core)
  +pointed = (((Gui.vec.y(mouse) - Gui.rec.y(bounds) : F32) * 360.0 : F32) / Gui.rec.height(bounds) : F32)
  Gui.hue.drawn(gui, frame, bounds, selector,
    Gui.bar.update(Gui.pick.kind(gui, core, bounds, J.Collision.point_rec(mouse, bounds) || J.Collision.point_rec(mouse, selector)),
      gui, bounds, hue, Bool.pick(F32, (pointed <= 0.0 : F32), 0.0, Bool.pick(F32, (pointed >= 359.0 : F32), 359.0, pointed))))

# GuiColorBarHue(bounds, text, &hue): six vertical gradients through red,
# yellow, green, cyan, blue, magenta and back to red (ceil(height/6) high but
# the last), the border, and a selector HUEBAR_SELECTOR_HEIGHT high (placed
# by the hue before the update) passing the bar by HUEBAR_SELECTOR_OVERFLOW
# on each side. A press over the bar or the selector, or a drag that started
# there, sets the hue from the pointer, clamped to [0, 359]. The frame, the
# gui (the drag) and the hue. A selector outside int's range marks the frame
# undefined, and so does a band (DrawRectangleGradientV's ints).
def Gui.color_bar_hue(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +hue: F32) -> J.Frame & (Gui & F32):
  Gui.hue.run(gui, core, frame, bounds, Gui.hue.selector(gui, bounds, hue), hue)

# The hue bar beside a picker: HUEBAR_PADDING to its right, HUEBAR_WIDTH
# wide, as high as the panel.
def Gui.picker.hue_bounds(+gui: Gui, +bounds: J.Rectangle) -> J.Rectangle:
  J.Rectangle{+bx, +by, +bw, +bh} = bounds
  J.Rectangle{((bx + bw : F32) + FontCore.int.f32(Gui.get_style(gui, 13, 18)) : F32), by, FontCore.int.f32(Gui.get_style(gui, 13, 17)), bh}

def Gui.picker.set(+converts: Bool, frame: J.Frame, +gui: Gui, rgb: U32 & Bool) -> J.Frame & (Gui & U32):
  (+bytes, +fine) = rgb
  (Gui.refused(Bool.not(fine && converts), frame), (gui, bytes))

def Gui.picker.after(+after: M.Vector3, +color: U32, frame: J.Frame, +gui: Gui) -> J.Frame & (Gui & U32):
  Gui.picker.set(Gui.rgb.fine(after), frame, gui, Gui.rgb.rounded(Gui.rgb.of(after), J.Color.alpha(color)))

def Gui.picker.done(+color: U32, +hsv: M.Vector3, frame: J.Frame, rest: Gui & F32) -> J.Frame & (Gui & U32):
  M.Vector3{_, +s, +v} = hsv
  (+gui, +hue) = rest
  Gui.picker.after(M.Vector3{hue, s, v}, color, frame, gui)

def Gui.picker.hued(+color: U32, +hsv: M.Vector3, r: J.Frame & (Gui & F32)) -> J.Frame & (Gui & U32):
  (frame, rest) = r
  Gui.picker.done(color, hsv, frame, rest)

def Gui.picker.panel_done(+core: J.Core, +bounds: J.Rectangle, frame: J.Frame, rest: Gui & U32) -> J.Frame & (Gui & U32):
  (+gui, +color) = rest
  +hsv = Gui.hsv.of_color(color)
  Gui.picker.hued(color, hsv, Gui.color_bar_hue(gui, core, frame, Gui.picker.hue_bounds(gui, bounds), None{}, Gui.hsv.hue(hsv)))

def Gui.picker.paneled(+core: J.Core, +bounds: J.Rectangle, r: J.Frame & (Gui & U32)) -> J.Frame & (Gui & U32):
  (frame, rest) = r
  Gui.picker.panel_done(core, bounds, frame, rest)

# GuiColorPicker(bounds, text, &color): GuiColorPanel, then GuiColorBarHue
# beside it over the (new) color's hue; the color becomes (unsigned
# char)roundf(255*channel) of the HSV with the bar's hue, every frame, the
# alpha kept. The frame, the gui and the color. The panel's and the bar's
# refusals apply, and an HSV raygui cannot convert marks the frame undefined.
def Gui.color_picker(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +color: U32) -> J.Frame & (Gui & U32):
  Gui.picker.paneled(core, bounds, Gui.color_panel(gui, core, frame, bounds, None{}, color))

def Gui.picker_hsv.done(+hsv: M.Vector3, frame: J.Frame, rest: Gui & F32) -> J.Frame & (Gui & M.Vector3):
  M.Vector3{_, +s, +v} = hsv
  (+gui, +hue) = rest
  (frame, (gui, M.Vector3{hue, s, v}))

def Gui.picker_hsv.hued(+hsv: M.Vector3, r: J.Frame & (Gui & F32)) -> J.Frame & (Gui & M.Vector3):
  (frame, rest) = r
  Gui.picker_hsv.done(hsv, frame, rest)

def Gui.picker_hsv.panel_done(+core: J.Core, +bounds: J.Rectangle, frame: J.Frame, rest: Gui & M.Vector3) -> J.Frame & (Gui & M.Vector3):
  (+gui, +hsv) = rest
  Gui.picker_hsv.hued(hsv, Gui.color_bar_hue(gui, core, frame, Gui.picker.hue_bounds(gui, bounds), None{}, Gui.hsv.hue(hsv)))

def Gui.picker_hsv.paneled(+core: J.Core, +bounds: J.Rectangle, r: J.Frame & (Gui & M.Vector3)) -> J.Frame & (Gui & M.Vector3):
  (frame, rest) = r
  Gui.picker_hsv.panel_done(core, bounds, frame, rest)

# GuiColorPickerHSV(bounds, text, &colorHsv): GuiColorPanelHSV, then
# GuiColorBarHue beside it over the HSV's hue. The frame, the gui and the
# HSV. The panel's and the bar's refusals apply.
def Gui.color_picker_hsv(+gui: Gui, +core: J.Core, frame: J.Frame, +bounds: J.Rectangle, text: Maybe<String>, +hsv: M.Vector3) -> J.Frame & (Gui & M.Vector3):
  Gui.picker_hsv.paneled(core, bounds, Gui.color_panel_hsv(gui, core, frame, bounds, None{}, hsv))
