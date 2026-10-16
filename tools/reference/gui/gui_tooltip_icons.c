/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. Tooltips (GuiEnableTooltip, GuiDisableTooltip,
 * GuiSetTooltip) over a button, a toggle near the right edge and a text box
 * near the bottom, and GuiDrawIcon and GuiIconText, under scripted input; the
 * port is tests/gui/gui_tooltip_icons.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2025 Ramon
 * Santamaria (@raysan5)).
 */
#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

int main(void)
{
    InitWindow(500, 300, "jonlib gui - tooltips and icons");
    SetTargetFPS(60);

    int clicks = 0;
    bool on = false;
    char text[64] = "box";

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            GuiEnableTooltip();
            GuiSetTooltip("Saves the file");
            if (GuiButton((Rectangle){ 10, 10, 120, 30 }, GuiIconText(6, "Save"))) clicks++;
            GuiSetTooltip("A tooltip longer than the space left");
            GuiToggle((Rectangle){ 380, 10, 110, 30 }, "Toggle", &on);
            GuiSetTooltip("two\nlines");
            GuiTextBox((Rectangle){ 10, 255, 150, 30 }, text, 64, false);
            GuiSetTooltip(NULL);
            GuiButton((Rectangle){ 10, 60, 120, 30 }, "No tooltip");
            GuiSetTooltip("Hidden");
            GuiDisableTooltip();
            GuiButton((Rectangle){ 10, 110, 120, 30 }, "Tooltips off");
            GuiDrawIcon(6, 200, 60, 1, BLACK);
            GuiDrawIcon(121, 230, 60, 2, RED);
            GuiSetAlpha(0.5f);
            GuiDrawIcon(200, 280, 60, 3, BLUE);
            GuiSetAlpha(1.0f);
            GuiDrawIcon(1, 400, 150, -2, DARKGREEN);
            GuiLabel((Rectangle){ 200, 160, 150, 20 }, GuiIconText(-5, "negative"));
            GuiLabel((Rectangle){ 200, 190, 150, 20 }, GuiIconText(1000, "four digits"));
            GuiLabel((Rectangle){ 200, 220, 150, 20 }, GuiIconText(121, NULL));
            DrawText(TextFormat("%d %d", clicks, (int)on), 440, 285, 10, BLACK);
        EndDrawing();
    }

    CloseWindow();
    return 0;
}
