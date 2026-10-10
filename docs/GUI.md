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
| `GuiGetTextWidth` | `Gui.get_text_width(gui, text)` | `Maybe<F32>` (the C int; `None` for an icon prefix) |
| `GuiLabel` | `Gui.label(gui, frame, bounds, text)` | `Frame` |
| `GuiButton` | `Gui.button(gui, core, frame, bounds, text)` | `Frame & Bool` (clicked) |
| `GuiCheckBox` | `Gui.check_box(gui, core, frame, bounds, text, checked)` | `Frame & (Bool & Bool)` (checked, changed) |
| `GuiSlider` | `Gui.slider(gui, core, frame, bounds, left, right, value, min, max)` | `Frame & (Gui & (F32 & Bool))` (value, changed) |
| `GuiSliderBar` | `Gui.slider_bar(...)` | the same |

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
- **Pointer.** `GetMousePosition`, and for the button the left mouse button or
  gamepad 0's `GAMEPAD_BUTTON_RIGHT_FACE_DOWN`, as raygui's defaults.
- **Sliders.** A press inside the bounds starts a drag: the Gui remembers
  the slider's bounds (`guiControlExclusiveRec`, compared as ints) and the
  value keeps following the pointer outside them until the button is
  released. While a drag is on, buttons and check boxes do not react. The
  value is `(max - min)*((mouse.x - x - sliderWidth/2)/(width - sliderWidth)) +
  min`, then clamped.
- **Shapes texture.** raygui's first style load calls `SetShapesTexture` with
  the default font's white rectangle, the value `InitWindow` already set, so
  nothing changes.

## Gaps

- Not delivered yet: `GuiToggle`, `GuiToggleGroup`, `GuiToggleSlider`,
  `GuiComboBox`, `GuiDropdownBox`, `GuiTextBox`, `GuiValueBox`, `GuiSpinner`,
  `GuiProgressBar`, `GuiStatusBar`, `GuiDummyRec`, `GuiGrid`, `GuiLine`,
  `GuiGroupBox`, `GuiPanel`, `GuiTabBar`, `GuiScrollPanel`, `GuiListView(Ex)`,
  `GuiColor*`, `GuiMessageBox`, `GuiTextInputBox`, `GuiWindowBox`,
  `GuiLabelButton`, the style file loaders, `GuiSetFont`/`GuiGetFont`, icons
  and tooltips.
- A text with an icon prefix (`"#id#"`), and the `TEXT_WRAP_CHAR` and
  `TEXT_WRAP_WORD` modes, mark the frame undefined.
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
texts. `LAWS.bend` states the default text size, the propagation of a DEFAULT
property and the enable/disable rules.
