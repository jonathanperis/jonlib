/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. GuiLoadStyle of the script directory's style.rgs (text and
 * binary styles, with and without fonts) before the loop, then a label, a
 * button, a check box, a slider bar, a text box, a line and a status bar
 * drawn in the style, and its values printed; the port is
 * tests/gui/gui_style.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2025 Ramon
 * Santamaria (@raysan5)).
 */
#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

int main(void)
{
    InitWindow(420, 300, "jonlib gui - load style");

    GuiLoadStyle("style.rgs");
    SetTargetFPS(60);

    int clicks = 0;
    bool checked = false;
    float value = 40.0f;
    char text[32] = "styled";

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            GuiLabel((Rectangle){ 10, 10, 300, 30 }, "Styled label");
            if (GuiButton((Rectangle){ 10, 50, 140, 30 }, "Button")) clicks++;
            GuiCheckBox((Rectangle){ 10, 100, 24, 24 }, "Check", &checked);
            GuiSliderBar((Rectangle){ 60, 140, 200, 20 }, "Min", "Max", &value, 0, 100);
            GuiTextBox((Rectangle){ 10, 175, 200, 30 }, text, 32, false);
            GuiLine((Rectangle){ 10, 215, 300, 10 }, "Line");
            GuiStatusBar((Rectangle){ 0, 270, 420, 30 }, "Status");
            DrawText(TextFormat("%d %d %d %d %d %d", clicks, (int)checked, GuiGetStyle(DEFAULT, TEXT_SIZE), GuiGetStyle(DEFAULT, TEXT_SPACING),
                                GuiGetStyle(BUTTON, BORDER_WIDTH), GuiGetFont().baseSize), 230, 240, 10, BLACK);
        EndDrawing();
    }

    CloseWindow();
    return 0;
}
