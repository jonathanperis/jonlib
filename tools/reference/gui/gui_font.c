/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. GuiSetFont with an image font (the text examples'
 * custom_alagard.png, through LoadFont) and GuiGetFont: labels, a button with
 * an icon, a toggle, a text box, a label cut by its ellipsis, a larger
 * TEXT_SIZE and a tooltip, under scripted input; the port is
 * tests/gui/gui_font.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2025 Ramon
 * Santamaria (@raysan5)).
 */
#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

int main(void)
{
    InitWindow(400, 260, "jonlib gui - custom font");

    Font font = LoadFont("resources/custom_alagard.png");
    GuiSetFont(font);
    SetTargetFPS(60);

    int clicks = 0;
    bool on = false;
    char text[32] = "alagard";

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            GuiLabel((Rectangle){ 10, 10, 200, 30 }, "Custom font label");
            if (GuiButton((Rectangle){ 10, 50, 140, 30 }, "#6#Save")) clicks++;
            GuiToggle((Rectangle){ 160, 50, 140, 30 }, "Toggle", &on);
            GuiTextBox((Rectangle){ 10, 90, 200, 30 }, text, 32, false);
            GuiLabel((Rectangle){ 10, 130, 60, 30 }, "A label wider than its bounds");
            GuiSetStyle(DEFAULT, TEXT_SIZE, 20);
            GuiLabel((Rectangle){ 10, 165, 300, 30 }, "Twenty");
            GuiSetStyle(DEFAULT, TEXT_SIZE, 10);
            GuiEnableTooltip();
            GuiSetTooltip("A tip in the font");
            GuiButton((Rectangle){ 220, 90, 100, 30 }, "Tip");
            GuiDisableTooltip();
            DrawText(TextFormat("%d %d %d", clicks, (int)on, GuiGetFont().baseSize), 300, 240, 10, BLACK);
        EndDrawing();
    }

    UnloadFont(font);
    CloseWindow();
    return 0;
}
