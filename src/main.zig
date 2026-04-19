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

fn sierpinskiTriangleRecurse(p1: rl.Vector2, p2: rl.Vector2, p3: rl.Vector2, color: rl.Color, iterations: usize) void {
    if (iterations == 0) {
        rl.drawTriangle(p1, p2, p3, color);
    } else {
        // the inner triangle is defined by the midpoints of the edges of the outer triangle
        const mid12 = p1.lerp(p2, 0.5);
        const mid23 = p2.lerp(p3, 0.5);
        const mid31 = p3.lerp(p1, 0.5);
        sierpinskiTriangleRecurse(p1, mid12, mid31, color, iterations - 1);
        sierpinskiTriangleRecurse(mid12, p2, mid23, color, iterations - 1);
        sierpinskiTriangleRecurse(mid31, mid23, p3, color, iterations - 1);
    }
}

fn sierpinskiTriangle(origin_x: f32, origin_y: f32, size: f32) void {
    // find the initial vertexes of the initial equilateral triangle
    const height = size * 3 / 4;
    const offset_y = (size - height) / 2;
    const p1 = rl.Vector2{ .x = origin_x + size / 2, .y = origin_y + offset_y };
    const p2 = rl.Vector2{ .x = origin_x, .y = origin_y + offset_y + height };
    const p3 = p2.add(rl.Vector2{ .x = size, .y = 0 });
    // draw triangles recursively
    const iterations = 6;
    sierpinskiTriangleRecurse(p1, p2, p3, .light_gray, iterations);
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

fn kockSnowflake(origin_x: f32, origin_y: f32, size: f32) void {
    // find the initial vertexes of the equilateral triangle
    const color: rl.Color = .light_gray;
    const height = size * 3 / 4;
    const offset_y = size - height;
    const p1 = rl.Vector2{ .x = origin_x, .y = origin_y + offset_y };
    const p2 = p1.add(rl.Vector2{ .x = size, .y = 0 });
    const p3 = p1.add(rl.Vector2{ .x = size / 2, .y = height });
    // then recursively draw the snowflake pattern on each edge
    const iterations = 5;
    kockSegment(p1, p2, iterations, color);
    kockSegment(p2, p3, iterations, color);
    kockSegment(p3, p1, iterations, color);
}

const Fractal = enum(i32) { kockSnowflake, sierpinskiTriangle };

fn fractalSelectBtns(fractalType: *Fractal) void {
    const offset_x = 24 + 30 + 24;
    const offset_y = 24;
    const size_x = 120;
    const size_y = 30;
    const r = rl.Rectangle{ .x = offset_x, .y = offset_y, .width = size_x, .height = size_y };
    var active = @intFromEnum(fractalType.*);
    _ = rg.toggleGroup(r, "Kock Snowflake;Sierpinski Triangle", &active);
    fractalType.* = @enumFromInt(active);
}

fn fractal() bool {
    const S = struct {
        var fractal: Fractal = .kockSnowflake;
    };
    // get largest square that fits within the window
    const size: f32 = @floatFromInt(@min(rl.getRenderWidth(), rl.getRenderHeight()) - 50);
    const origin_x: f32 = (@as(f32, @floatFromInt(rl.getRenderWidth())) - size) / 2;
    const origin_y: f32 = (@as(f32, @floatFromInt(rl.getRenderHeight())) - size) / 2;
    // draw background
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(getBackgroundColor());
    // draw debug square
    //rl.drawRectangleRec(rl.Rectangle{ .x = origin_x, .y = origin_y, .width = size, .height = size }, .yellow);
    switch (S.fractal) {
        .kockSnowflake => kockSnowflake(origin_x, origin_y, size),
        .sierpinskiTriangle => sierpinskiTriangle(origin_x, origin_y, size),
    }
    // draw back button
    if (backBtn()) {
        return true;
    }
    // draw fractal selection buttons
    fractalSelectBtns(&S.fractal);

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
