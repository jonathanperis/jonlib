/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. GuiWindowBox, GuiLabelButton, GuiDummyRec and GuiGrid,
 * enabled and disabled, under scripted input; the port is
 * tests/gui/gui_window_grid.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2025 Ramon
 * Santamaria (@raysan5)).
 */
#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

int main(void)
{
    InitWindow(400, 300, "jonlib gui - window box, label button, dummy rec, grid");
    SetTargetFPS(60);

    Vector2 cell = { 0 };
    int closes = 0;
    int clicks = 0;

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            if (GuiWindowBox((Rectangle){ 10, 10, 200, 120 }, "#198#Window")) closes++;
            if (GuiLabelButton((Rectangle){ 20, 50, 40, 20 }, "Click me please")) clicks++;
            GuiDummyRec((Rectangle){ 220, 10, 160, 60 }, "Dummy");
            GuiGrid((Rectangle){ 10, 140, 380, 150 }, NULL, 40, 4, &cell);
            DrawText(TextFormat("%d %d %.0f %.0f", closes, clicks, cell.x, cell.y), 230, 100, 10, BLACK);
            GuiDisable();
            GuiDummyRec((Rectangle){ 220, 75, 70, 20 }, "Off");
            GuiGrid((Rectangle){ 300, 75, 80, 20 }, NULL, 10, 2, NULL);
            GuiEnable();
        EndDrawing();
    }

    CloseWindow();
    return 0;
}
