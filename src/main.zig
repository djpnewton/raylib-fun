const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

/// `rl.getColor` only accepts a `u32`. Performing `@intCast` on the return value
/// of `rg.getStyle` invokes checked undefined behavior from Zig when passed to
/// `rl.getColor`, hence the custom implementation here...
fn getColor(hex: i32) rl.Color {
    var color: rl.Color = .black;
    // zig fmt: off
    color.r = @intCast((hex >> 24) & 0xFF);
    color.g = @intCast((hex >> 16) & 0xFF);
    color.b = @intCast((hex >>  8) & 0xFF);
    color.a = @intCast((hex >>  0) & 0xFF);
    // zig fmt: on
    return color;
}

fn getBackgroundColor() rl.Color {
    return getColor(rg.getStyle(.default, .{ .default = .background_color }));
}

fn backBtn() bool {
    const size = 30;
    return rg.button(.init(24, 24, size, size), "<");
}

fn kockSegment(p1: rl.Vector2, p2: rl.Vector2, iterations: usize, color: rl.Color) void {
    // divide the line segment into thirds
    const third_x = (p2.x - p1.x) / 3;
    const third_y = (p2.y - p1.y) / 3;
    const p1a = rl.Vector2{ .x = p1.x + third_x, .y = p1.y + third_y };
    const p2a = rl.Vector2{ .x = p1.x + 2 * third_x, .y = p1.y + 2 * third_y };
    // calculate the coordinates of the outward point of the triangle
    // rotate the middle segment direction by -60 deg around p1a to get the apex
    const p_mid = (rl.Vector2{ .x = p2a.x - p1a.x, .y = p2a.y - p1a.y }).rotate(-std.math.pi / 3.0).add(p1a);
    // recursively draw the pattern on each of the four new segments
    if (iterations > 0) {
        kockSegment(p1, p1a, iterations - 1, color);
        kockSegment(p1a, p_mid, iterations - 1, color);
        kockSegment(p_mid, p2a, iterations - 1, color);
        kockSegment(p2a, p2, iterations - 1, color);
    } else {
        // draw the final line segments
        rl.drawLineV(p1, p1a, color);
        rl.drawLineV(p1a, p_mid, color);
        rl.drawLineV(p_mid, p2a, color);
        rl.drawLineV(p2a, p2, color);
    }
}

fn kockSnowflake(origin_x: i32, origin_y: i32, size: i32) void {
    // find the initial vertexes of the equilateral triangle
    const color: rl.Color = .light_gray;
    const height = @divTrunc(size * 3, 4);
    const offset_y = @as(f32, @floatFromInt(size - height));
    const p1 = rl.Vector2{ .x = @floatFromInt(origin_x), .y = @as(f32, @floatFromInt(origin_y)) + offset_y };
    const p2 = p1.add(rl.Vector2{ .x = @floatFromInt(size), .y = 0 });
    const p3 = p1.add(rl.Vector2{ .x = @floatFromInt(@divTrunc(size, 2)), .y = @floatFromInt(height) });
    // then recursively draw the snowflake pattern on each edge
    const iterations = 5;
    kockSegment(p1, p2, iterations, color);
    kockSegment(p2, p3, iterations, color);
    kockSegment(p3, p1, iterations, color);
}

fn fractal() bool {
    // get largest square that fits within the window
    const size = @min(rl.getRenderWidth(), rl.getRenderHeight()) - 50;
    const origin_x = @divTrunc(rl.getRenderWidth() - size, 2);
    const origin_y = @divTrunc(rl.getRenderHeight() - size, 2);
    // draw background
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(getBackgroundColor());
    // draw debug square
    //rl.drawRectangle(origin_x, origin_y, size, size, .yellow);
    // draw snowflake
    kockSnowflake(origin_x, origin_y, size);
    // draw back button
    if (backBtn()) {
        return true;
    }
    return false;
}

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
        rl.clearBackground(getBackgroundColor());

        if (rg.button(.init(24, 24, 120, 30), "Fractal"))
            demo = fractal;

        const offset_x = @divTrunc(rl.getRenderWidth(), 2);
        const offset_y = @divTrunc(rl.getRenderHeight(), 2);
        const font_size = 20;
        const text_width = rl.measureText("raylib-fun", font_size);
        rl.drawText("raylib-fun", offset_x - @divTrunc(text_width, 2), offset_y - @divTrunc(font_size, 2), font_size, .light_gray);
        //----------------------------------------------------------------------------------
    }
}
