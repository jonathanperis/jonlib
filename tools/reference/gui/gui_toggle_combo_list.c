/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. GuiToggleSlider, GuiComboBox and GuiListView, enabled and
 * disabled, under scripted input; the port is
 * tests/gui/gui_toggle_combo_list.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2025 Ramon
 * Santamaria (@raysan5)).
 */
#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

int main(void)
{
    InitWindow(400, 300, "jonlib gui - toggle slider, combo box, list view");
    SetTargetFPS(60);

    int toggle = 0, toggles = 0, combo = 0, scroll = 0, active = -1;
    int toggleOff = 1, comboOff = 3, scrollOff = 0, activeOff = 0;

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            if (GuiToggleSlider((Rectangle){ 10, 10, 200, 30 }, "One;Two;Three", &toggle)) toggles++;
            GuiComboBox((Rectangle){ 10, 60, 200, 30 }, "Red;Green;Blue;White", &combo);
            GuiListView((Rectangle){ 220, 10, 170, 120 }, "Alpha;Beta;Gamma;Delta;Epsilon;Zeta;Eta;Theta;Iota", &scroll, &active);
            DrawText(TextFormat("%d %d %d %d %d", toggles, toggle, combo, scroll, active), 10, 110, 10, BLACK);
            GuiDisable();
            GuiToggleSlider((Rectangle){ 10, 140, 120, 24 }, "A;B", &toggleOff);
            GuiComboBox((Rectangle){ 10, 180, 120, 24 }, "Only;Two", &comboOff);
            GuiListView((Rectangle){ 220, 150, 170, 60 }, NULL, &scrollOff, &activeOff);
            GuiEnable();
        EndDrawing();
    }

    CloseWindow();
    return 0;
}
