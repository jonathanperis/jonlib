/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. GuiTabBar (more tabs than the window holds) and
 * GuiMessageBox, enabled and disabled, under scripted input; the port is
 * tests/gui/gui_message_tabs.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2025 Ramon
 * Santamaria (@raysan5)).
 */
#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

int main(void)
{
    InitWindow(500, 300, "jonlib gui - tab bar, message box");
    SetTargetFPS(60);

    char *tabs[] = { "First", "Second", "Third", "Fourth" };
    int active = 1, tabResult = -2, boxResult = -2;

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            int t = GuiTabBar((Rectangle){ 0, 0, 500, 24 }, tabs, 4, &active);
            if (t >= 0) tabResult = t;
            int r = GuiMessageBox((Rectangle){ 60, 60, 300, 160 }, "#191#Message", "Hello there!\nSecond line", "Yes;No;Cancel");
            if (r >= 0) boxResult = r;
            DrawText(TextFormat("%d %d %d", active, tabResult, boxResult), 380, 250, 10, BLACK);
            GuiDisable();
            GuiMessageBox((Rectangle){ 380, 60, 110, 100 }, NULL, "Off", "Ok");
            GuiEnable();
        EndDrawing();
    }

    CloseWindow();
    return 0;
}
