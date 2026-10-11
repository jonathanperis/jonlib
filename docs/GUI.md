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
  its text: 16x16 pixels at scale 1, one `GuiDrawRectangle` a set bit, at
  the line's x and centered on the bounds' height, with the text 20 pixels
  further and 20 pixels less room before the ellipsis. The line's width for
  the alignment is the text's plus 16, plus 4 more unless the whole text
  ends there. `GuiGetTextWidth` has its own rule, kept as it is: a text
  starting with `#` that has another `#` within its next four bytes is
  measured from that second `#` (the `#` included) plus 20. The set is
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
- **Shapes texture.** raygui's first style load calls `SetShapesTexture` with
  the default font's white rectangle, the value `InitWindow` already set, so
  nothing changes.

## Gaps

- Not delivered yet: `GuiToggleSlider`,
  `GuiComboBox`, `GuiTextBox`, `GuiValueBoxFloat`,
  `GuiProgressBar`, `GuiDummyRec`, `GuiGrid`,
  `GuiTabBar`, `GuiScrollPanel`, `GuiListView(Ex)`,
  `GuiColor*`, `GuiMessageBox`, `GuiTextInputBox`, `GuiWindowBox`,
  `GuiLabelButton`, the style file loaders, `GuiSetFont`/`GuiGetFont`,
  `GuiDrawIcon`/`GuiIconText` as functions, `GuiSetIconScale` (icons draw at
  scale 1), `GuiLoadIcons` and tooltips.
- An icon id above 255 reads past raygui's table and marks the frame
  undefined. So does a line that is not the text's last, starts with `#`
  (after its icon, if it has one), and has fewer than four bytes after that
  `#` with no second `#`: raygui's `GuiGetTextWidth` would look for it in the
  lines that follow.
- The `TEXT_WRAP_CHAR` and `TEXT_WRAP_WORD` modes mark the frame undefined.
- `GuiDropdownBox` marks the frame undefined for an active index outside the
  items (raygui reads a stale pointer), a text of 1024 bytes or more and 128
  items or more (`GuiTextSplit`'s static buffers).
- `GuiValueBox` and `GuiSpinner` in edit mode (keyboard entry) mark the frame
  undefined. A spinner step below `INT_MIN` or above `INT_MAX` overflows in C
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
label in each state. `shaders_color_correction` covers the toggle group: an item hovered, pressed
and switched on, and a click on the active item that changes nothing. `LAWS.bend` states the default text size, the propagation of a DEFAULT
property, the enable/disable rules, how an icon prefix is read and which
lines are refused. The `gui-icons` gate compares the icon set with every
raygui.h of the pinned checkout.
