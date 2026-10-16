# Jongui: raygui controls

`jongui.bend` ports raygui (v5.0-dev, `RAYGUI_VERSION` 4.5.0, as raylib 6.0
ships it beside its examples) the way Jonlib ports raylib: the controls'
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
| `GuiSetStyle` / `GuiGetStyle` | `Gui.set_style(gui, control, property, value)` / `Gui.get_style(gui, control, property)` | `Gui` / `U32`; a DEFAULT base property (below 16) reaches every control |
| `GuiEnable` / `GuiDisable` | `Gui.enable(gui)` / `Gui.disable(gui)` | `Gui` |
| `GuiLock` / `GuiUnlock` / `GuiIsLocked` | `Gui.lock`, `Gui.unlock`, `Gui.is_locked` | `Gui` / `Bool` |
| `GuiSetState` / `GuiGetState` | `Gui.set_state(gui, state)` / `Gui.get_state(gui)` | `Gui` / `U32` |
| `GuiSetAlpha` | `Gui.set_alpha(gui, alpha)` | `Gui` (alpha clamped to [0, 1]) |
| `GuiSetIconScale` | `Gui.set_icon_scale(gui, scale)` | `Gui` (a scale below 1 is ignored) |
| `GuiGetTextWidth` | `Gui.get_text_width(gui, text)` | `Maybe<F32>` (the C int, always `Some`; an icon prefix counts as raygui counts it) |
| `GuiLabel` | `Gui.label(gui, frame, bounds, text)` | `Frame` |
| `GuiButton` | `Gui.button(gui, core, frame, bounds, text)` | `Frame & Bool` (clicked) |
| `GuiCheckBox` | `Gui.check_box(gui, core, frame, bounds, text, checked)` | `Frame & (Bool & Bool)` (checked, changed) |
| `GuiToggle` | `Gui.toggle(gui, core, frame, bounds, text, active)` | `Frame & Bool` (active) |
| `GuiToggleGroup` | `Gui.toggle_group(gui, core, frame, bounds, text, active)` | `Frame & U32` (the active index) |
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
| `GuiGetFont().baseSize` | `Gui.font_base_size(gui)` | `U32` (the default font's 10) |
| `GuiScrollBar` (static in raygui) | `Gui.scroll_bar(gui, core, frame, bounds, value, min, max)` | `Frame & (Gui & U32)` (the int value as a word) |
| `GuiTextBox` | `Gui.text_box(gui, core, frame, bounds, text, size, edit, editing)` | `Frame & (Core & (String & (Gui.Editing & Bool)))` (the text, raygui's two text box globals, its result) |
| `GuiWindowBox` | `Gui.window_box(gui, core, frame, bounds, title)` | `Frame & Bool` (the close button clicked; `title` is `Maybe<String>`) |
| `GuiLabelButton` | `Gui.label_button(gui, core, frame, bounds, text)` | `Frame & Bool` (clicked; the bounds widened to the text) |
| `GuiDummyRec` | `Gui.dummy_rec(gui, frame, bounds, text)` | `Frame` |
| `GuiGrid` | `Gui.grid(gui, core, frame, bounds, text, spacing, subdivs)` | `Frame & Vector2` (the cell under the pointer, or (-1, -1); `subdivs` is a C int as a word) |
| `GuiToggleSlider` | `Gui.toggle_slider(gui, core, frame, bounds, text, active)` | `Frame & (U32 & Bool)` (the active item, moved on by a release) |
| `GuiComboBox` | `Gui.combo_box(gui, core, frame, bounds, text, active)` | `Frame & U32` (the active item, moved on by a press over the box or its button) |
| `GuiTabBar` | `Gui.tab_bar(gui, core, frame, bounds, items, active)` | `Frame & (U32 & U32)` (the active tab, and the tab whose close button was clicked or that a middle press is over, or -1, as int bits) |
| `GuiMessageBox` | `Gui.message_box(gui, core, frame, bounds, title, message, buttons)` | `Frame & U32` (0 for the close button, a button's number from 1, or -1 as 4294967295) |
| `GuiValueBoxFloat` | `Gui.value_box_float(gui, core, frame, bounds, text, text_value, value, edit)` | `Frame & (F32 & Bool)` (the value, unchanged outside edit mode, and whether the box was pressed; `text_value` is the buffer raygui shows) |
| `GuiTextInputBox` | `Gui.text_input_box(gui, core, frame, bounds, title, message, buttons, size, input)` | `Frame & (Core & (Gui.Input & U32))` (`GuiInput{text, secret, edit, editing}`: the text, the secret view (0 off, 1 on, 2 for NULL), raygui's static edit mode and the text box globals, which a program passes from one input box to the next; the result: 0 closed, a button's number, or -1) |
| `GuiListView` | `Gui.list_view(gui, core, frame, bounds, text, scroll, active)` | `Frame & (Gui & (U32 & U32))` (`GuiListViewEx` over the items of `text`, `None` for NULL; the scroll index and active item as words) |
| `GuiEnableTooltip` / `GuiDisableTooltip` | `Gui.enable_tooltip(gui)` / `Gui.disable_tooltip(gui)` | `Gui` (tooltips are off in a new gui) |
| `GuiSetTooltip` | `Gui.set_tooltip(gui, tooltip)` | `Gui` (`tooltip` is `Maybe<String>`: `None` for NULL, which shows none); a focused button, toggle or text box out of edit mode draws it below itself, moved left or above where it would leave the screen |
| `GuiDrawIcon` | `Gui.draw_icon(gui, frame, id, x, y, pixel_size, color)` | `Frame` (the ints as words; the gui's icon table, faded by its alpha) |
| `GuiIconText` | `Gui.icon_text(id, text)` | `Maybe<String>` (`"#%03i#"` then the text from the sixth byte; `text` `None` for NULL gives the prefix alone; `None` for a text raygui's buffer cannot terminate) |
| `GuiGetIcons` | `Gui.get_icons(gui)` | `+List<U32>` (the 2048 words of the gui's icon table) |
| `GuiLoadIcons` | `Gui.load_icons(gui, path, names)` | `IO(Gui & Gui.Names)` (`GuiNames{names}` with each name id's 32 bytes, `GuiNamesNull{}` for NULL, `GuiNamesUndefined{}` for a load raygui does not define) |

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
  from raygui's own output. Colors are `0xRRGGBBAA` words, Jonlib's colors.
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
  `GuiGetTextWidth` has its own rule, kept as it is: a text starting with
  `#` that has another `#` within its next four bytes is measured from that
  second `#` (the `#` included) plus 20, whatever the scale. The set is
  `src/gui_icons.bend`, generated from the pinned raygui.h
  (`tools/gui_icons.py`).
- **Pointer.** `GetMousePosition`, and for the button the left mouse button or
  gamepad 0's `GAMEPAD_BUTTON_RIGHT_FACE_DOWN`, as raygui's defaults.
- **Sliders.** A press inside the bounds starts a drag: the Gui remembers
  the slider's bounds (`guiControlExclusiveRec`, compared as ints) and the
  value keeps following the pointer outside them until the button is
  released. While a drag is on, buttons and check boxes do not react. The
  value is `(max - min)*((mouse.x - x - sliderWidth/2)/(width - sliderWidth)) +
  min`, then clamped.
- **Toggle groups.** The text splits at `';'` and `'\n'` (`GuiTextSplit`); a
  `'\n'` starts a new row. Each item is a `GuiToggle`; switching one on makes
  it the active index, and the active item cannot be switched off.
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
  a text is given). An axis whose content does not fit inside the border
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

- Not delivered yet: `GuiColor*`, `GuiLoadStyle`, `GuiSetFont` and `GuiGetFont`'s
  Font (its base size is `Gui.font_base_size`).
- `GuiLoadIcons` answers undefined (the gui unchanged) for a negative icon
  count (a gap: raygui's `fseek` and `calloc` of a negative count are
  host-dependent), a count of words past int's range, data that would pass
  the 2048 words of the table, and a file that ends inside the icon count,
  the icon size or a word (`fread`'s partial element is indeterminate).
  `GuiDrawIcon` marks the frame undefined for an id outside 0..255 and
  coordinates that may leave int's range (|x| or |y| at 2^30 or more,
  |pixel size| at 2^26 or more); `GuiIconText` answers `None` for a text of
  1019 bytes or more.
- An icon id above 255 reads past raygui's table and marks the frame
  undefined, and so does an icon drawn at a scale above 65536. So does a line that is not the text's last, starts with `#`
  (after its icon, if it has one), and has fewer than four bytes after that
  `#` with no second `#`: raygui's `GuiGetTextWidth` would look for it in the
  lines that follow.
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
- The default font only.
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
fits), with text boxes and slider bars drawn inside its view under a
scissor, a spinner that changes the rows, and a slider bar disabled and
enabled again. `shaders_color_correction` covers the toggle group: an item hovered, pressed
and switched on, and a click on the active item that changes nothing. `models_animation_timing` covers the progress bar: a bar partly filled over
a range of keyframes, its border in two colors split at the bar's end, with
a dropdown box of fourteen items opened over the scene, an item chosen and
a slider dragged beside it. `models_animation_blending` adds an empty bar,
one whose value passed its maximum (capped and full), one filling from the
right (`PROGRESS_SIDE` 1), bars with both side texts, and a slider disabled
while its dropdown box is open. The bar's own disabled state is not
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
three disabled, the list view with a NULL text. `gui_message_tabs` covers
`GuiTabBar` with more tabs than the window holds (a tab clicked, the last one
clicked so that the bar moves left, a tab's close button and a middle press)
and `GuiMessageBox` (its buttons and its close button, a two-line message, an
icon in the title, and a disabled box with a NULL title). `gui_value_input`
covers `GuiValueBoxFloat` (hovered, pressed, disabled) and two
`GuiTextInputBox`es sharing raygui's static edit mode: the secret view
switched on and off, a box entered and left by a button, the other box
entered (which shows the first one's text, its stars gone, while edit mode is
on), and the close button. `gui_tooltip_icons` covers tooltips: a button's
below it (with a `GuiIconText` label), a toggle's moved left from the right
edge, a text box's two lines moved above it near the bottom, none for a NULL
tooltip and none with tooltips off, none while the button is pressed; and
`GuiDrawIcon` at pixel sizes 1, 2, 3 (at half alpha) and -2, and labels of
`GuiIconText` with a negative id, a four-digit id and a NULL text.

The `gui-icon-files` gate (`tools/gui_icon_files_probe.py`) compares
`GuiLoadIcons`, `GuiGetIcons` and `GuiIconText` with raygui without a
window: a corpus of .rgi files (icon sizes 16, 32, 0 and -16, with and
without name ids, one 32 bytes long without a terminator, a full table,
data and names cut short, headers cut before and at the count and size, a
wrong signature, a missing file, a directory, and headers asking for more
than the table holds over data that does not) loaded in order, the names
and a hash of the 2048 table words after each load, then `GuiIconText` for
eighteen ids (negative ones, four digits and more) and six texts.
