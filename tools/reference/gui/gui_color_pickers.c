/*
 * Probe-only raygui program for tools/examples_probe.py (category gui); not a
 * raylib example. GuiColorPicker, GuiColorPickerHSV, GuiColorPanel,
 * GuiColorBarAlpha and GuiColorBarHue, enabled and disabled, under scripted
 * input (presses and drags that leave the controls); the port is
 * tests/gui/gui_color_pickers.bend. raygui.h is the pinned raylib's
 * (examples/core/raygui.h, zlib/libpng, Copyright (c) 2014-2025 Ramon
 * Santamaria (@raysan5)).
 */
#include "raylib.h"
#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

int main(void)
{
    InitWindow(500, 320, "jonlib gui - color pickers");
    SetTargetFPS(60);

    Color color = { 200, 0, 0, 255 };
    Vector3 hsv = { 120.0f, 0.5f, 0.8f };
    Color panel = { 10, 200, 100, 128 };
    float alpha = 0.5f;
    float hue = 90.0f;
    Color still = { 30, 60, 90, 255 };
    float stillAlpha = 0.25f;
    float stillHue = 200.0f;

    while (!WindowShouldClose())
    {
        BeginDrawing();
            ClearBackground(RAYWHITE);
            GuiColorPicker((Rectangle){ 10, 10, 150, 150 }, NULL, &color);
            GuiColorPickerHSV((Rectangle){ 200, 10, 150, 150 }, NULL, &hsv);
            GuiColorPanel((Rectangle){ 10, 180, 120, 100 }, NULL, &panel);
            GuiColorBarAlpha((Rectangle){ 150, 200, 150, 20 }, NULL, &alpha);
            GuiColorBarHue((Rectangle){ 320, 180, 20, 110 }, NULL, &hue);
            GuiDisable();
            GuiColorPanel((Rectangle){ 400, 10, 80, 80 }, NULL, &still);
            GuiColorBarAlpha((Rectangle){ 400, 110, 80, 16 }, NULL, &stillAlpha);
            GuiColorBarHue((Rectangle){ 400, 140, 16, 80 }, NULL, &stillHue);
            GuiEnable();
            DrawText(TextFormat("%d %d %d %d %d %d %d %.3f %.3f %.3f %.3f %.3f", color.r, color.g, color.b,
                                panel.r, panel.g, panel.b, panel.a, hsv.x, hsv.y, hsv.z, alpha, hue), 10, 300, 10, BLACK);
        EndDrawing();
    }

    CloseWindow();
    return 0;
}
