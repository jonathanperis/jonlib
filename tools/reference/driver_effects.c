// Reference loop for the driver's Effects programs (tools/effects_probe.py):
// a file written and read before BeginDrawing and written after EndDrawing,
// as an example's loop does (SaveStorageValue, TakeScreenshot). Compiled with
// tools/reference/example_driver.h like a raylib example.
#include "raylib.h"
#include <stdlib.h>

int main(void)
{
    InitWindow(160, 90, "driver effects");

    int counter = 0;    // Frames so far
    int saved = 0;      // The counter S wrote
    int loaded = 0;     // The number L read
    int late = 0;       // The counter of the last write after EndDrawing

    SetTargetFPS(60);

    while (!WindowShouldClose())
    {
        counter++;
        if (IsKeyPressed(KEY_S))
        {
            SaveFileText("effects.txt", TextFormat("%i", counter));
            saved = counter;
        }
        if (IsKeyPressed(KEY_L))
        {
            char *text = LoadFileText("effects.txt");
            loaded = (text != NULL)? atoi(text) : 0;
            UnloadFileText(text);
        }

        BeginDrawing();
            ClearBackground(RAYWHITE);
            DrawText(TextFormat("%i %i %i %i", counter, saved, loaded, late), 10, 10, 20, DARKGRAY);
        EndDrawing();

        // EndDrawing polled the input: a key still down is seen here, a press is not
        if (IsKeyDown(KEY_F))
        {
            SaveFileText("effects.txt", TextFormat("%i", counter + 1000));
            late = counter;
        }
    }

    CloseWindow();
    return 0;
}
