/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. GuiTabBar (its text form, more tabs than the window holds,
 * the bar moved by the active tab) and GuiTabBarEx (TABBAR's close buttons,
 * the border line on top, narrower tabs), and GuiMessageBox, enabled and
 * disabled, with raygui 5.1-dev's signatures, under scripted input; the port
 * is tests/gui/gui_message_tabs.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2026 Ramon
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
    int hscroll = 0, active = 5, tabResult = -2, activeEx = 9, exResult = -2;
    int boxActive = -2, boxResult = -2;

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            int t = GuiTabBar((Rectangle){ 0, 0, 500, 24 }, "One;Two;Three;Four;Five;Six", &hscroll, &active);
            if (t != 0) tabResult = t;
            GuiSetStyle(TABBAR, TAB_ITEMS_WIDTH, 100);
            GuiSetStyle(TABBAR, TAB_CLOSE_BUTTON, 1);
            GuiSetStyle(TABBAR, TAB_LINE_SIDE, 1);
            int e = GuiTabBarEx((Rectangle){ 0, 30, 500, 24 }, tabs, 4, &hscroll, &activeEx, NULL);
            if (e != 0) exResult = e;
            GuiSetStyle(TABBAR, TAB_ITEMS_WIDTH, 160);
            GuiSetStyle(TABBAR, TAB_CLOSE_BUTTON, 0);
            GuiSetStyle(TABBAR, TAB_LINE_SIDE, 0);
            int r = GuiMessageBox((Rectangle){ 60, 60, 300, 160 }, "#191#Message", "Hello there!\nSecond line", "Yes;No;Cancel", &boxActive);
            if (r != 0) boxResult = r;
            DrawText(TextFormat("%d %d %d %d %d %d", active, tabResult, activeEx, exResult, boxActive, boxResult), 330, 250, 10, BLACK);
            GuiDisable();
            GuiMessageBox((Rectangle){ 380, 60, 110, 100 }, NULL, "Off", "Ok", &boxActive);
            GuiEnable();
        EndDrawing();
    }

    CloseWindow();
    return 0;
}
