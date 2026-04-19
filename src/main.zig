const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const utils = @import("utils.zig");
const fractal = @import("fractal.zig");

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true });
    rl.initWindow(screenWidth, screenHeight, "raylib-fun");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var demo: ?*const fn () bool = null;

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // run demo if selected
        if (demo) |demo_fn| {
            if (demo_fn()) {
                demo = null;
            }
            continue;
        }

        // Draw main menu
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(utils.getBackgroundColor());

        if (rg.button(.init(24, 24, 120, 30), "Fractal"))
            demo = fractal.fractal;

        const offset_x = @divTrunc(rl.getRenderWidth(), 2);
        const offset_y = @divTrunc(rl.getRenderHeight(), 2);
        const font_size = 20;
        const text_width = rl.measureText("raylib-fun", font_size);
        rl.drawText("raylib-fun", offset_x - @divTrunc(text_width, 2), offset_y - @divTrunc(font_size, 2), font_size, .light_gray);
        //----------------------------------------------------------------------------------
    }
}
