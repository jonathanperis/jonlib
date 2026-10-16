/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. GuiValueBoxFloat (outside edit mode) and GuiTextInputBox
 * (with and without a secret view; both share raygui's static edit mode and
 * text box state) under scripted input; the port is
 * tests/gui/gui_value_input.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2025 Ramon
 * Santamaria (@raysan5)).
 */
#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

int main(void)
{
    InitWindow(500, 360, "jonlib gui - value box float, text input box");
    SetTargetFPS(60);

    float value = 2.5f;
    char valueText[32] = "2.5";
    int presses = 0;
    char secretText[64] = "secret";
    bool secretView = false;
    int secretResult = -2;
    char plainText[64] = "hello";
    int plainResult = -2;

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            if (GuiValueBoxFloat((Rectangle){ 60, 10, 100, 24 }, "Value", valueText, &value, false)) presses++;
            int r = GuiTextInputBox((Rectangle){ 10, 50, 300, 150 }, "#191#Login", "Password:", "Ok;Cancel", secretText, 64, &secretView);
            if (r >= 0) secretResult = r;
            int p = GuiTextInputBox((Rectangle){ 10, 210, 300, 130 }, NULL, NULL, "Done", plainText, 64, NULL);
            if (p >= 0) plainResult = p;
            DrawText(TextFormat("%d %d %d %d", presses, secretResult, plainResult, (int)secretView), 330, 340, 10, BLACK);
            GuiDisable();
            GuiValueBoxFloat((Rectangle){ 380, 10, 100, 24 }, NULL, "1.0", &value, false);
            GuiEnable();
        EndDrawing();
    }

    CloseWindow();
    return 0;
}
