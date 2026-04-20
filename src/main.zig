const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const ut = @import("utils.zig");
const fractal = @import("fractal.zig");
const life = @import("life.zig");
const raycast = @import("raycast.zig");

pub fn main(init: std.process.Init) !void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true, .msaa_4x_hint = true });
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
        rl.clearBackground(ut.getBackgroundColor());

        const x = ut.button_spacing;
        var y: i32 = ut.button_spacing;
        const btn_width = 120;
        if (ut.btn(x, y, btn_width, ut.button_height, "Fractal"))
            demo = fractal.fractal;
        y += ut.button_height + ut.button_spacing;
        if (ut.btn(x, y, btn_width, ut.button_height, "Game of Life"))
            demo = life.gameOfLife;
        y += ut.button_height + ut.button_spacing;
        if (ut.btn(x, y, btn_width, ut.button_height, "Raycast"))
            demo = raycast.raycast;

        ut.drawTextCentered("raylib-fun", 20, .light_gray);
        //----------------------------------------------------------------------------------
    }
}
