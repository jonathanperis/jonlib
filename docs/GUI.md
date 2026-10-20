# Jongui: raygui controls

`jongui.bend` adapts raygui (v5.1-dev, `RAYGUI_VERSION` 5.1, as raylib 6.2
ships it beside its examples) the way Jonlib adapts raylib: the controls'
update and drawing code in raygui's F32 and C `int` order, over Jonlib's
frame and input. raygui's globals (`guiState`, `guiLocked`, `guiAlpha`, the
slider drag and the style table) are one explicit `G.Gui` value.

```bend
import ./jonlib.bend as J
import ./jongui.bend as G
```

A control takes the `Gui`, the `Core` (pointer position and buttons) and the
`Frame`, and returns the frame with what raygui returns or writes through its
pointers. A control that keeps state between frames (a slider's drag) returns
the `Gui` too. Controls run inside the frame, between `BeginDrawing` and
`EndDrawing`, as in raygui.

## Delivered

| raygui | Jongui | Returns |
|---|---|---|
| `GuiLoadStyleDefault` | `Gui.new()`, `Gui.style.default()` | the default 16x24 style table (as raygui fills it) |
| `GuiSetStyle` / `GuiGetStyle` | `Gui.set_style(gui, control, property, value)` / `Gui.get_style(gui, control, property)` | `Gui` / `U32`; the table entry control*24 + property (a property of 24 or more is the next rows', as in raygui); a DEFAULT base property (below 16) reaches every control |
| `GuiLoadStyle` | `Gui.load_style(gui, frame, path)` | `IO(Frame & Gui)` (text and binary .rgs files, their fonts loaded into the frame; a binary style's white rectangle sets the shapes texture when its atlas loads) |
| `GuiLoadStyleFromMemory` | `Gui.load_style_from_memory(gui, frame, bytes)` | `Frame & Gui` (the binary format of `GuiLoadStyle`, public since raygui 5.1-dev) |
| `GuiEnable` / `GuiDisable` | `Gui.enable(gui)` / `Gui.disable(gui)` | `Gui` |
| `GuiLock` / `GuiUnlock` / `GuiIsLocked` | `Gui.lock`, `Gui.unlock`, `Gui.is_locked` | `Gui` / `Bool` |
| `GuiSetState` / `GuiGetState` | `Gui.set_state(gui, state)` / `Gui.get_state(gui)` | `Gui` / `U32` |
| `GuiSetAlpha` | `Gui.set_alpha(gui, alpha)` | `Gui` (alpha clamped to [0, 1]) |
| `GuiSetIconScale` | `Gui.set_icon_scale(gui, scale)` | `Gui` (a scale below 1 is ignored) |
| `GuiGetTextWidth` | `Gui.get_text_width(gui, text)` | `Maybe<F32>` (the C int, always `Some`: the widest line, an icon marker counted as raygui counts it) |
| `GuiLabel` | `Gui.label(gui, frame, bounds, text)` | `Frame` |
| `GuiButton` | `Gui.button(gui, core, frame, bounds, text)` | `Frame & Bool` (clicked) |
| `GuiCheckBox` | `Gui.check_box(gui, core, frame, bounds, text, checked)` | `Frame & (Bool & Bool)` (checked, changed) |
| `GuiToggle` | `Gui.toggle(gui, core, frame, bounds, text, active)` | `Frame & Bool` (active) |
| `GuiToggleGroup` | `Gui.toggle_group(gui, core, frame, bounds, text, active)` | `Frame & U32` (the active index; TOGGLE's `GROUP_WIDTH_FULL` divides the width among a row's items) |
| `GuiSlider` | `Gui.slider(gui, core, frame, bounds, left, right, value, min, max)` | `Frame & (Gui & (F32 & Bool))` (value, changed) |
| `GuiSliderBar` | `Gui.slider_bar(...)` | the same |
| `GuiLine` | `Gui.line(gui, frame, bounds, text)` | `Frame` (`text` is `Maybe<String>`: `None` for NULL) |
| `GuiGroupBox` | `Gui.group_box(gui, frame, bounds, text)` | `Frame` |
| `GuiValueBox` | `Gui.value_box(gui, core, frame, bounds, text, value, min, max, edit)` | `Frame & (U32 & Bool)` (the int as a word, pressed) |
| `GuiSpinner` | `Gui.spinner(gui, core, frame, bounds, text, value, min, max, edit)` | `Frame & (U32 & Bool)` (the int as a word, the value box pressed) |
| `GuiStatusBar` | `Gui.status_bar(gui, frame, bounds, text)` | `Frame` (`text` is `Maybe<String>`) |
| `GuiPanel` | `Gui.panel(gui, frame, bounds, text)` | `Frame` (a status bar heads it when a text is given) |
| `GuiDropdownBox` | `Gui.dropdown_box(gui, core, frame, bounds, text, active, edit)` | `Frame & (U32 & Bool)` (the active item, raygui's result) |
| `GuiScrollPanel` | `Gui.scroll_panel(gui, core, frame, bounds, text, content, scroll)` | `Frame & (Gui & (Vector2 & Rectangle))` (the scroll offset and the view) |
| `GuiProgressBar` | `Gui.progress_bar(gui, frame, bounds, left, right, value, min, max)` | `Frame & F32` (the value, which one above `max` becomes; a value is always given) |
| `GuiListViewEx` | `Gui.list_view_ex(gui, core, frame, bounds, items, scroll, active, focus)` | `Frame & (Gui & Gui.Listed)` (`GuiListed{scroll, active, focus}`: the three ints as words, -1 being 4294967295) |
| `GuiSetFont` | `Gui.set_font(gui, font)` | `Gui & Font` (the gui keeps a copy, `J.Font.Shared`, when the font's texture id is above 0; the font comes back) |
| `GuiGetFont` | `Gui.get_font(gui)`, `Gui.font_base_size(gui)` | `Font` (the default font, or one equal to the font set) / `U32` (its base size) |
| `GuiScrollBar` (static in raygui) | `Gui.scroll_bar(gui, core, frame, bounds, value, min, max)` | `Frame & (Gui & U32)` (the int value as a word) |
| `GuiTextBox` | `Gui.text_box(gui, core, frame, bounds, text, size, edit, editing)` | `Frame & (Core & (String & (Gui.Editing & Bool)))` (the text, raygui's two text box globals, its result) |
| `GuiWindowBox` | `Gui.window_box(gui, core, frame, bounds, title)` | `Frame & Bool` (the close button clicked; `title` is `Maybe<String>`) |
| `GuiLabelButton` | `Gui.label_button(gui, core, frame, bounds, text)` | `Frame & Bool` (clicked; the bounds widened to the text) |
| `GuiDummyRec` | `Gui.dummy_rec(gui, frame, bounds, text)` | `Frame` |
| `GuiGrid` | `Gui.grid(gui, core, frame, bounds, text, spacing, subdivs)` | `Frame & Vector2` (the cell under the pointer, or (-1, -1); `subdivs` is a C int as a word) |
| `GuiToggleSlider` | `Gui.toggle_slider(gui, core, frame, bounds, text, active)` | `Frame & (U32 & Bool)` (the active item, moved on by a release, and whether raygui's result is not 0: a release, or an index that changed) |
| `GuiComboBox` | `Gui.combo_box(gui, core, frame, bounds, text, active)` | `Frame & U32` (the active item, moved on by a press over the box or its button) |
| `GuiTabBar` | `Gui.tab_bar(gui, core, frame, bounds, text, hscroll, active)` | `Frame & (U32 & U32)` (`GuiTabBarEx` over the `';'`-separated tabs of `text`, `None` for NULL: the active tab and the result) |
| `GuiTabBarEx` | `Gui.tab_bar_ex(gui, core, frame, bounds, items, hscroll, active, focus)` | `Frame & (U32 & U32)` (the active tab, and the result: `RESULT_TAB_CLOSE` (4) for a close button or a middle press over a tab, else `RESULT_CHANGED` (2) when the active tab changed, else 0; raygui 5.1-dev neither reads nor writes `hscroll` and `focus`) |
| `GuiMessageBox` | `Gui.message_box(gui, core, frame, bounds, title, message, buttons, active)` | `Frame & Gui.Reply` (`GuiReply{active, result}`: `btnActive`, 0 for the close button or a button's number from 1 when one was clicked, else as given, and the result, 1 when one was, else 0) |
| `GuiValueBoxFloat` | `Gui.value_box_float(gui, core, frame, bounds, text, text_value, value, edit)` | `Frame & (F32 & Bool)` (the value, unchanged outside edit mode, and whether the box was pressed; `text_value` is the buffer raygui shows) |
| `GuiTextInputBox` | `Gui.text_input_box(gui, core, frame, bounds, title, message, size, buttons, active, input)` | `Frame & (Core & (Gui.Input & Gui.Reply))` (`GuiInput{text, secret, edit, editing}`: the text, the secret view (0 off, 1 on, 2 for NULL), raygui's static edit mode and the text box globals, which a program passes from one input box to the next; the reply as `GuiMessageBox`'s) |
| `GuiListView` | `Gui.list_view(gui, core, frame, bounds, text, scroll, active)` | `Frame & (Gui & (U32 & U32))` (`GuiListViewEx` over the items of `text`, `None` for NULL; the scroll index and active item as words) |
| `GuiEnableTooltip` / `GuiDisableTooltip` | `Gui.enable_tooltip(gui)` / `Gui.disable_tooltip(gui)` | `Gui` (tooltips are off in a new gui) |
| `GuiSetTooltip` | `Gui.set_tooltip(gui, tooltip)` | `Gui` (`tooltip` is `Maybe<String>`: `None` for NULL, which shows none); a focused button, toggle or text box out of edit mode draws it below itself, moved left or above where it would leave the screen |
| `GuiDrawIcon` | `Gui.draw_icon(gui, frame, id, x, y, pixel_size, color)` | `Frame` (the ints as words; the gui's icon table, faded by its alpha) |
| `GuiIconText` | `Gui.icon_text(id, text)` | `Maybe<String>` (`"#%03i#"` then the text from the sixth byte; `text` `None` for NULL gives the prefix alone; `None` for a text raygui's buffer cannot terminate) |
| `GuiGetIcons` | `Gui.get_icons(gui)` | `+List<U32>` (the gui's icon table: 4096 words at start, the words of the last signed `GuiLoadIcons` after it) |
| `GuiColorPanelHSV` | `Gui.color_panel_hsv(gui, core, frame, bounds, text, hsv)` | `Frame & (Gui & Vector3)` (the HSV; the drag in the gui; the text is not drawn, as in raygui) |
| `GuiColorPanel` | `Gui.color_panel(gui, core, frame, bounds, text, color)` | `Frame & (Gui & U32)` (the color, changed only when the panel changes its HSV) |
| `GuiColorBarAlpha` | `Gui.color_bar_alpha(gui, core, frame, bounds, text, alpha)` | `Frame & (Gui & F32)` (the alpha in [0, 1]) |
| `GuiColorBarHue` | `Gui.color_bar_hue(gui, core, frame, bounds, text, hue)` | `Frame & (Gui & F32)` (the hue in [0, 359]) |
| `GuiColorPicker` | `Gui.color_picker(gui, core, frame, bounds, text, color)` | `Frame & (Gui & U32)` (the panel, then the hue bar beside it; the color rebuilt from the HSV every frame, as raygui does) |
| `GuiColorPickerHSV` | `Gui.color_picker_hsv(gui, core, frame, bounds, text, hsv)` | `Frame & (Gui & Vector3)` |
| `GuiLoadIcons` | `Gui.load_icons(gui, path, names)` | `IO(Gui & Gui.Names)` (the file through `GuiLoadIconsFromMemory`; `GuiNamesNull{}` for a file that does not open or is empty) |
| `GuiLoadIconsFromMemory` | `Gui.load_icons_from_memory(gui, bytes, names)` | `Gui & Gui.Names` (the table replaced by the data's count*(size*size/32) words; `GuiNames{names}` with each name id's 32 bytes, `GuiNamesNull{}` for NULL, `GuiNamesUndefined{}` for a load raygui does not define) |

Two additions have no raygui counterpart. They run a row of controls in order
for programs that keep their values in lists (Bend has no pointers to write
through): `Gui.slider_bars(gui, core, frame, bars, values)` (one
`GuiSliderBar` per `G.GuiBar{bounds, left, format, low, high}`, the right
text being the value formatted by the bar's `format`) and `Gui.check_boxes(gui, core, frame, boxes,
checked)` (one `GuiCheckBox` per `G.GuiBox{bounds, text}`).

The enums are functions (`G.Gui.SLIDER()`, `G.Gui.TEXT_SIZE()`,
`G.Gui.STATE_DISABLED()`, `G.Gui.TEXT_ALIGN_RIGHT()` and so on). `api/jongui.json`
lists every raygui function with its status; `tools/examples_plan.py` keeps an
example waiting on each raygui function it calls that is not delivered.

## How it follows raygui

- **Style.** `guiStyle` is 16 controls of 24 properties (16 base, 8
  extended). `Gui.new()` holds the table `GuiLoadStyleDefault` builds, taken
  from raygui's own output (raygui 5.1-dev: `TEXT_LINE_SPACING` 12 between
  a text's lines, and `TABBAR`, the control in `CONTROL11`'s row, with
  `TAB_ITEMS_WIDTH` 160). Colors are `0xRRGGBBAA` words, Jonlib's colors.
- **Drawing.** `GuiDrawRectangle` is up to five `DrawRectangle` calls with
  `(int)` coordinates (the fill when its alpha is above 0, then the border).
  `GuiDrawText` splits the text at `'\n'`, places each line by the horizontal
  and vertical alignment with raygui's int divisions and `(int)h % 2` offset,
  truncates the position to whole pixels and draws each glyph with
  `DrawTextCodepoint` in the default font, advancing by the glyph's width
  times `TEXT_SIZE/baseSize` plus `TEXT_SPACING`. A line wider than its
  bounds stops at an ellipsis. Every color is faded by `guiAlpha`.
- **Icons.** A line that starts with `#`, up to three digits and `#`
  (`GetTextIcon`; `"##"` is icon 0) draws that icon of raygui's set before
  its text: 16x16 squares of the icon scale (`GuiSetIconScale`, 1 at start),
  one `GuiDrawRectangle` a set bit, at the line's x and centered on the
  bounds' height, with the text 4 pixels after the icon and that much less
  room before the ellipsis. The line's width for the alignment is the
  text's plus the icon's, plus 4 more unless the whole text ends there.
  raygui 5.1-dev has 512 icons (the ones past its initializers are zeros);
  a marker of 512 or more is not an icon, and the line is drawn whole. A
  line's text width is `GetLineWidth`'s, with its own rule, kept as it is:
  a line starting with a marker (`#`, up to three digits and `#`, whatever
  the number) is measured after it plus 20, whatever the scale, even after
  the icon `GetTextIcon` took. `GuiGetTextWidth` is the widest line starting
  in the text's first 256 bytes. The set is `src/gui_icons.bend`, generated
  from the pinned raygui.h (`tools/gui_icons.py`), until `GuiLoadIcons`
  replaces the table: raygui then reads an icon's words in the new table,
  of the loaded size.
- **Pointer.** `GetMousePosition`, and for the button the left mouse button or
  gamepad 0's `GAMEPAD_BUTTON_RIGHT_FACE_DOWN`, as raygui's defaults.
- **Sliders.** A press inside the bounds starts a drag: the Gui remembers
  the slider's bounds (`guiControlExclusiveRec`, compared as ints) and the
  value keeps following the pointer outside them until the button is
  released. While a drag is on, buttons and check boxes do not react. The
  value is `(max - min)*((mouse.x - x - sliderWidth/2)/(width - sliderWidth)) +
  min`, then clamped.
- **Toggle groups.** raygui 5.1-dev reads the text itself: `';'` moves to the
  next column, `'\n'` to the next row's first, and item n+1 is at x +
  column*(width + `GROUP_PADDING`), y + row*(height + `GROUP_PADDING`).
  With TOGGLE's `GROUP_WIDTH_FULL` the width is divided by the text's `';'`s
  plus one. Each item is a `GuiToggle`; switching one on makes it the active
  index, and the active item cannot be switched off.
- **Value boxes and spinners.** C ints are two's-complement `U32` words,
  compared as signed. `GuiValueBox` draws the value as it came (`"%i"`,
  centered) and returns it clamped (`max` when above it, else `min` when
  below it) when the control is enabled, unlocked and no slider is being
  dragged; a press over it returns true. Its fill is `BLANK` unless the
  state is pressed or disabled. `GuiSpinner` is two `GuiButton`s with the
  texts `"#118#"` and `"#119#"` (`ICON_ARROW_LEFT_FILL`,
  `ICON_ARROW_RIGHT_FILL`), `SPINNER_BUTTON_WIDTH` wide, drawn first; a
  release over one steps the value by one, which is then clamped (`min`
  first) and handed to the value box between them. The label is drawn last,
  in the spinner's own state (pressed while the button is down over it).
- **Dropdown boxes.** The caller keeps the edit mode, as with raygui, and
  flips it when the result is true. Closed, the box shows the active item
  and an arrow icon (`"#120#"`, or `"#121#"` with `DROPDOWN_ROLL_UP`) and
  answers true to a press over it. Open (edit mode), a `GuiPanel` covers the
  box and one row an item (each `height + DROPDOWN_ITEMS_SPACING` further,
  added row by row as raygui does), the active item boxed in the pressed
  colors and the one under the pointer in the focused colors; a release over
  an item makes it the active one and answers true, as do a press over the
  box and a press or a release outside the open bounds. An open box reacts
  even when the gui is locked; a text with a single item never reacts.
- **Text boxes.** raygui keeps the cursor index and the held-key counter in
  two globals shared by every text box; they are a `G.Gui.Editing` value
  (`Gui.editing()` at start) that the caller passes to each box and takes
  back, with the edit mode kept by the caller as in raygui. Out of edit
  mode a box is focused under the pointer and a press there answers true
  and puts the cursor at the text's end. In edit mode, in raygui's order:
  a typed codepoint (`GetCharPressed`, taken from the Core's queue) or the
  clipboard text on Ctrl+V goes in at the cursor while the text stays
  shorter than `textSize`; HOME and END; DELETE and BACKSPACE remove a
  codepoint; LEFT and RIGHT move by one; a key held for more than 20 frames
  repeats every frame; a press over the text puts the cursor at the glyph
  under the pointer (drawn as a 1-pixel mouse cursor); ENTER or a press
  outside the box answers true and resets both globals. A text wider than
  the box is drawn from the codepoint that brings the cursor back inside.
  The box does not react when `TEXT_READONLY` is set, the gui is disabled or
  locked, a slider is dragged or a wrap mode is on.
- **Scroll panels.** The panel is at least 48 high (below a status bar when
  a text is given, 23 pixels lower and less high; the vertical scroll stops
  at `-BORDER_WIDTH`, as in raygui 5.1-dev). An axis whose content does not fit inside the border
  gets a scroll bar (`SCROLLBAR_WIDTH` wide, on LISTVIEW's
  `SCROLLBAR_SIDE`), and a bar's room can make the other axis need one. The
  view is the inside less the bars, no larger than the content. Under the
  pointer the wheel (`GUI_SCROLL_DELTA`: the wheel plus the gamepad
  triggers) scrolls vertically, or horizontally with LEFT_CONTROL or
  LEFT_SHIFT down, by the content/bounds ratio or 20 pixels a notch at
  least. Each bar's slider is sized by the bounds/content ratio through
  `SCROLL_SLIDER_SIZE`, which is put back afterwards; an axis without a bar
  has offset 0, and the other offsets are the negatives of the bars' int
  values. A scroll bar is horizontal when wider than high; a press starts a
  drag (the slider drag's exclusive mode), an arrow steps by
  `range/SCROLL_SPEED` and a press on the track jumps there. The slider is
  drawn where the value was on entry, as raygui does.
- **List views.** `items` is the list of texts (`text` and `count`); the
  three ints go in and come back in a `G.Gui.Listed`. As many items as fit
  the height are shown from the scroll index (0 when it is negative or past
  the last full page), each `LIST_ITEMS_HEIGHT` high and
  `LIST_ITEMS_SPACING` apart, their rectangles placed by repeated addition
  as raygui places them. With more items than fit, the items are
  `SCROLLBAR_WIDTH` narrower, a `GuiScrollBar` stands at the right with a
  slider of the visible share of the height (`SCROLL_SLIDER_SIZE` and
  `SCROLL_SPEED` are set for it and put back), and the wheel moves the
  list an item a notch while the pointer is over the list view. The item
  under the pointer is focused and a press selects it, or clears the
  selection when it was the selected one; the focus is -1 with the pointer
  outside and stays as given with it between two items. raygui works out
  the focus and the selection with the scroll index it entered with and
  then draws from the index the wheel left: for one frame after a wheel
  movement the highlighted item is not the one under the pointer. That is
  kept. The selected item is drawn in the pressed colors, the focused one
  in the focused colors (the selection first).
- **Shapes texture.** raygui's first style load calls `SetShapesTexture` with
  the default font's white rectangle, the value `InitWindow` already set, so
  nothing changes.

## Gaps

- `GuiLoadStyle` marks the frame undefined for what raygui leaves
  undefined: a `GuiSetStyle` index outside the table, an `sscanf` value
  outside its type, reads past the file, compressed data that does not
  inflate to what is read next, a font with no glyphs or a base size below
  1. Gaps: an `f` line without a charmap name (raygui reads the style's
  directory as a text file), a sign or a second `0x` in a property's hex
  value, image formats above 13 and samples Jonlib's images refuse, and a
  style path past `GetDirectoryPath`'s buffer are refused too; a directory
  is a file that does not open. `GuiSetStyle` changes nothing for an index
  outside the table.
- A gui with a font set rebuilds the font from its copy for each text it
  draws (a word list to an array, a word a pixel of the atlas): correct,
  and slower than raygui's shared pointers for a large atlas.
- The color controls take their value, not a pointer: raygui's NULL color
  (its temporary 200, 0, 0) has no counterpart. They mark the frame
  undefined where raygui's conversions are: an HSV whose RGB is not a byte
  ((unsigned char) of a value outside (-1, 256)), a hue whose `(long)(hue/60)`
  is outside long's range or NaN, a selector or bar outside int's range.
- `GuiLoadIconsFromMemory` (and `GuiLoadIcons` through it) answers
  undefined (the gui unchanged) for data shorter than the 12-byte header
  (raygui copies it first), name ids or words past the data, more than 512
  name ids asked (raygui's name array), a table whose byte size overflows an
  int, and a negative icon count (a gap where no word is read). A directory
  is a file that does not open. `GuiDrawIcon` marks the frame undefined for
  an id whose words are not in the icon table (a negative one, 512 or more
  at start, past the loaded icons after `GuiLoadIcons`) and coordinates that
  may leave int's range (|x| or |y| at 2^30 or more, |pixel size| at 2^26 or
  more); `GuiIconText` answers `None` for a text of 1019 bytes or more.
- An icon whose words are not in the icon table reads past it and marks the
  frame undefined, and so does an icon drawn at a scale above 65536.
- `GuiToggleGroup` marks the frame undefined for an item of 256 bytes or
  more (raygui's static `itemText` buffer).
- raygui 5.1-dev's int results of `GuiStatusBar`, `GuiPanel`,
  `GuiScrollPanel`, `GuiDummyRec` and `GuiGrid` (`RESULT_PRESSED` for a
  release over them) are not returned; `GuiTabBarEx`'s `hscroll` and
  `focus` are taken for the signature only (raygui does not use them), and
  an offset whose int arithmetic overflows wraps.
- The `TEXT_WRAP_CHAR` and `TEXT_WRAP_WORD` modes mark the frame undefined.
- `GuiToggleSlider`, `GuiComboBox` and `GuiListView` mark the frame
  undefined for a text of 1024 bytes or more or 128 items or more
  (`GuiTextSplit`'s static buffers), and `GuiToggleSlider` for an active
  index below 0 (it indexes the items with it) and a text whose width raygui
  cannot measure.
- `GuiGrid` marks the frame undefined where C cannot convert its line counts,
  `(int)(size / (spacing / subdivs))`: a NaN or a count outside the int range.
- `GuiListViewEx` marks the frame undefined for an item height or spacing
  above 32767 or more than 32767 items (raygui multiplies them as ints), a
  height and spacing that add up to 0 (its division), a list view's height
  that is negative or not a C int, and a wheel movement that is not one. A
  NULL text or int pointer has no counterpart.
- `GuiDropdownBox` marks the frame undefined for an active index outside the
  items (raygui reads a stale pointer), a text of 1024 bytes or more and 128
  items or more (`GuiTextSplit`'s static buffers).
- `GuiTextBox` marks the frame undefined for the Ctrl word operations
  (Ctrl+DELETE, BACKSPACE, LEFT and RIGHT), a box too narrow for the glyph
  before the cursor (raygui's offset loop leaves the text) and a cursor
  inside a UTF-8 sequence. Typed characters, a paste and the drawing offset
  of a text wider than its box are compared with raygui by reading only: the
  reference's replayed events never reach `GetCharPressed`, and its
  clipboard is empty.
- `GuiScrollBar` marks the frame undefined where C's int conversions or
  arithmetic are (a range that overflows, a `SCROLL_SPEED` of 0 on an arrow
  press, a position that is not an int). No ported example's content
  overflows its scroll panel: the bars and scrolling are compared with
  raygui by reading only.
- `GuiValueBox`, `GuiValueBoxFloat` and `GuiSpinner` in edit mode (keyboard
  entry) mark the frame undefined. A spinner step below `INT_MIN` or above `INT_MAX` overflows in C
  and marks the frame undefined.
- An ellipsis narrower than 3 pixels makes raygui's dot loop endless; Jongui
  marks the frame undefined.
- Targets: CPU-1, CPU-2 and JavaScript lanes; the Metal lane is not verified.

## Verification

The controls are replayed inside the examples that use them: the `examples-*`
gates compare every frame with the unmodified native example, which compiles
the pinned raygui.h ([DRIVER.md](DRIVER.md)). `shapes_circle_sector_drawing`
covers four slider bars: normal, focused and pressed states, a press that
sets the value, a drag that leaves the bounds, the release, and both side
texts. `shapes_ring_drawing` and `shapes_rounded_rectangle_drawing` add
check boxes: hover, press, a toggle over the box and over its label, and a
release outside that toggles nothing. `shapes_kaleidoscope` covers buttons:
normal, focused, pressed and disabled (`GuiDisable`/`GuiEnable` around a
button), and a click that takes effect on the next frame.
`shapes_hilbert_curve` covers the spinner and the icons: the arrow buttons
hovered, pressed and released (the order steps up and down), the value box
hovered and pressed, a plain `GuiSlider` with a left text only, and the
label in each state. `shapes_splines_drawing` covers the dropdown box: hovered, opened by a
press, an item hovered and chosen by a release, opened again and closed by
a press outside, with the rest of the gui locked while it is open (and
while a point is dragged). `core_compute_hash` covers the text box: hovered, entered by a press,
BACKSPACE, LEFT, DELETE, HOME, END and RIGHT, the cursor placed by a press
over the text, BACKSPACE held past the repeat cooldown, ENTER, a press
outside, and read-only boxes; a label in `TEXT_SIZE` 20 with
`TEXT_SPACING` 2 and one drawn as focused. `core_clipboard_text` covers the icon scale: five buttons with icons at
scale 2 beside their texts in `TEXT_SIZE` 20, a text box emptied and
refilled, and disabled labels. `shapes_pie_chart` covers the scroll panel without bars (its content
fits), with text boxes (raylib 6.2 hands them `TextFormat`'s buffer, so an edit lasts one frame) and slider bars drawn inside its view under a
scissor, a spinner that changes the rows, and a slider bar disabled and
enabled again. `shaders_color_correction` covers the toggle group: an item hovered, pressed
and switched on, and a click on the active item that changes nothing. `models_animation_timing` covers the progress bar: a bar partly filled over
a range of keyframes, its border in two colors split at the bar's end, with
a dropdown box of fourteen items opened over the scene, an item chosen and
a slider dragged beside it. `models_animation_blending` adds an empty bar,
one whose value passed its maximum (capped and full), one filling from the
right (`PROGRESS_SIDE` 1), bars with both side texts, a slider disabled
while its dropdown box is open, and a label centered in
`TEXT_SIZE` twice the font's base size, the styles set back after it. The bar's own disabled state is not
compared with raygui yet. `LAWS.bend` states the default text size, the propagation of a DEFAULT
property, the enable/disable rules, how an icon prefix is read and which
lines are refused. The `gui-icons` gate compares the icon set with every
raygui.h of the pinned checkout.

The controls no raylib example calls are replayed the same way in probe-only
raygui programs: C sources in `tools/reference/gui/`, built and driven as the
examples are (raygui.h is the pinned examples' own), against their ports in
`tests/gui/` (gate `examples-gui`; they are not counted as raylib examples).
`gui_window_grid` covers `GuiWindowBox` (its close button hovered, pressed and
clicked), `GuiLabelButton` (a label wider than its bounds, hovered and
clicked), `GuiDummyRec` (hovered and pressed, which draw nothing different,
and disabled) and `GuiGrid` (the cell under the pointer at the corners, on an
edge and outside, and a disabled grid that answers no cell).
`gui_toggle_combo_list` covers `GuiToggleSlider` (hovered, pressed and
released three times, to its last item and back to the first; its text
centered over the whole text's width), `GuiComboBox` (pressed on its box and
on its selector button, which draws as a button of its own), `GuiListView`
(an item chosen, the list scrolled by the wheel, another chosen) and the
three disabled, the list view with a NULL text, and a `GuiToggleGroup` of
two rows with `GROUP_WIDTH_FULL` (an item of each row clicked).
`gui_message_tabs` covers `GuiTabBar` with more tabs than the window holds
(the bar moved right by its active tab, a tab clicked, another, a middle
press over one), `GuiTabBarEx` with `TAB_ITEMS_WIDTH` 100, close buttons and
the border line on top (a close button clicked over its tab, a tab clicked),
and `GuiMessageBox` (its buttons and its close button through `btnActive`, a
two-line message, an icon in the title, and a disabled box with a NULL
title). `gui_value_input` covers `GuiValueBoxFloat` (hovered, pressed,
disabled) and two `GuiTextInputBox`es sharing raygui's static edit mode
(their `btnActive` and the frames their result was 1): the secret view
switched on and off, a box entered and left by a button, the other box
entered (which shows the first one's text, its stars gone, while edit mode is
on), and the close button. `gui_tooltip_icons` covers tooltips: a button's
below it (with a `GuiIconText` label), a toggle's moved left from the right
edge, a text box's two lines moved above it near the bottom, none for a NULL
tooltip and none with tooltips off, none while the button is pressed; and
`GuiDrawIcon` at pixel sizes 1, 2, 3 (at half alpha) and -2 and icons 256
and 511, labels of `GuiIconText` with a negative id, a four-digit id and a
NULL text, and buttons with a marker of 600 (drawn as text, measured as a
marker) and an icon followed by a second marker.
`gui_color_pickers` covers the color controls: a `GuiColorPicker`'s panel
hovered, pressed and dragged out of it (the selector held at its edge), its
hue bar dragged above itself (the hue held at 0); a `GuiColorPickerHSV`'s
panel and hue bar pressed; a `GuiColorPanel` with a translucent color
dragged; a `GuiColorBarAlpha` dragged past its end and pressed on the
selector's overflow; a `GuiColorBarHue` dragged; the three disabled; and
the values printed each frame. `gui_font` covers `GuiSetFont` with an image
font (the text examples' `custom_alagard.png` through `LoadFont`, its
resources borrowed by the scene): labels, a button with an icon, a toggle
and a text box hovered and clicked, a label cut by its ellipsis, a label at
`TEXT_SIZE` 20, a tooltip measured and drawn in the font, and
`GuiGetFont().baseSize` printed. `gui_style` covers `GuiLoadStyle` with a
style file in each script's directory, then a label, a button, a check box,
a slider bar, a text box, a line and a status bar drawn in it and its
values printed: a text style (DEFAULT properties that reach every control,
a line `sscanf` matches only in part, which sets the previous line's values
again, a property index past a control's row, a line longer than `fgets`'s
buffer whose second part starts a property, a last line without `\n` that
is not read, and pixantiqua.ttf at 16), one with a charmap, one whose font
does not load (the default font with `TEXT_SIZE` 10 and `TEXT_SPACING` 1),
binary styles with a 95-glyph font raw (version 200) and DEFLATE-compressed
(version 400) whose white rectangle (gray) tints every shape, one whose
font image has width 0 (the default font, and no shapes texture since
raygui 5.1-dev), raygui 5.1-dev's forms (a text style of version 600 whose
`f` line names the font first, a font name past the 31 bytes `sscanf`
reads, whose first 31 name the font that loads, and a binary style of
version 600 with the font file's name), and two undefined from the start
(an index outside the table, a binary file cut inside its font).

The `gui-icon-files` gate (`tools/gui_icon_files_probe.py`) compares
`GuiLoadIcons` (raygui 5.1-dev's, through `GuiLoadIconsFromMemory`),
`GuiGetIcons` and `GuiIconText` with raygui without a window: a corpus of
.rgi files (icon sizes 16, 32, 0 and -16, with and without name ids, one 32
bytes long without a terminator, tables of 256 and 512 icons, 513 icons
without names, a header without icons, an empty file, a wrong signature, a
missing file and a directory; and as contracts data and names cut short,
files shorter than the header, 513 names asked, an overflowing and a
negative count) loaded in order, the names, the table's length (the
script knows it) and a hash of its words after each load, then
`GuiIconText` for eighteen ids (negative ones, four digits and more) and
six texts.
