const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const utils = @import("utils.zig");
const fractal = @import("fractal.zig");
const life = @import("life.zig");
const raycast = @import("raycast.zig");

pub fn main(init: std.process.Init) !void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true });
    rl.initWindow(screenWidth, screenHeight, "raylib-fun");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var demo: ?*const fn (io: std.Io) bool = null; // default demo to run on startup

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // run demo if selected
        if (demo) |demo_fn| {
            if (demo_fn(init.io)) {
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
        if (rg.button(.init(24, 24 + 30 + 24, 120, 30), "Game of Life"))
            demo = life.gameOfLife;
        if (rg.button(.init(24, 24 + 2 * (30 + 24), 120, 30), "Raycast"))
            demo = raycast.raycast;

        utils.drawTextCentered("raylib-fun", 20, .light_gray);
        //----------------------------------------------------------------------------------
    }
}
