const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const utils = @import("utils.zig");

fn interationsSlider(iterations: *usize) void {
    // iterations slider
    const bounds = rl.Rectangle{ .x = 24, .y = 24 + 30 + 24, .width = 100, .height = 15 };
    var iterations_f32: f32 = @floatFromInt(iterations.*);
    _ = rg.slider(bounds, null, "Iterations", &iterations_f32, 1, 10);
    iterations.* = @intFromFloat(iterations_f32);
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
    if (iterations > 0 and p1.distance(p1a) > 2) {
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
    const S = struct {
        var iterations: usize = 5;
    };
    interationsSlider(&S.iterations);
    // find the initial vertexes of the equilateral triangle
    const color: rl.Color = .light_gray;
    const height = size * 3 / 4;
    const offset_y = size - height;
    const p1 = rl.Vector2{ .x = origin_x, .y = origin_y + offset_y };
    const p2 = p1.add(rl.Vector2{ .x = size, .y = 0 });
    const p3 = p1.add(rl.Vector2{ .x = size / 2, .y = height });
    // then recursively draw the snowflake pattern on each edge
    kockSegment(p1, p2, S.iterations, color);
    kockSegment(p2, p3, S.iterations, color);
    kockSegment(p3, p1, S.iterations, color);
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
    const S = struct {
        var iterations: usize = 6;
    };
    interationsSlider(&S.iterations);
    // find the initial vertexes of the initial equilateral triangle
    const height = size * 3 / 4;
    const offset_y = (size - height) / 2;
    const p1 = rl.Vector2{ .x = origin_x + size / 2, .y = origin_y + offset_y };
    const p2 = rl.Vector2{ .x = origin_x, .y = origin_y + offset_y + height };
    const p3 = p2.add(rl.Vector2{ .x = size, .y = 0 });
    // draw triangles recursively
    sierpinskiTriangleRecurse(p1, p2, p3, .light_gray, S.iterations);
}

fn treeBranch(p1: rl.Vector2, p2: rl.Vector2, color: rl.Color, iterations: usize, angle: f32) void {
    rl.drawLineV(p1, p2, color);
    if (iterations > 0) {
        // two new branches starting at the end of the previous branch
        // 2/3 the length and rotated by 30 degrees in either direction
        const p3 = p1.lerp(p2, 1.666);
        const p4 = p3.subtract(p2).rotate(angle).add(p2);
        const p5 = p3.subtract(p2).rotate(-angle).add(p2);
        treeBranch(p2, p4, color, iterations - 1, angle);
        treeBranch(p2, p5, color, iterations - 1, angle);
    }
}

fn treeUi(iterations: *usize, angle: *f32) void {
    // iterations slider
    interationsSlider(iterations);
    // angle slider
    const bounds2 = rl.Rectangle{ .x = 24, .y = 24 + 30 + 24 + 15 + 15, .width = 100, .height = 15 };
    _ = rg.slider(bounds2, null, "Angle", angle, 0, std.math.pi / 2.0);
}

fn tree(origin_x: f32, origin_y: f32, size: f32) void {
    const S = struct {
        var iterations: usize = 7;
        var angle: f32 = std.math.pi / 6.0;
    };
    treeUi(&S.iterations, &S.angle);
    const color: rl.Color = .light_gray;
    const p1 = rl.Vector2{ .x = origin_x + size / 2, .y = origin_y + size };
    const p2 = rl.Vector2{ .x = origin_x + size / 2, .y = origin_y + 2 * size / 3 };
    treeBranch(p1, p2, color, S.iterations, S.angle);
}

const Fractal = enum(i32) { kockSnowflake, sierpinskiTriangle, tree };

fn fractalSelectBtns(fractalType: *Fractal) void {
    const offset_x = 24 + 30 + 24;
    const offset_y = 24;
    const size_x = 100;
    const size_y = 30;
    const r = rl.Rectangle{ .x = offset_x, .y = offset_y, .width = size_x, .height = size_y };
    var active = @intFromEnum(fractalType.*);
    _ = rg.toggleGroup(r, "Kock Snowflake;Sierpinski Triangle;Tree", &active);
    fractalType.* = @enumFromInt(active);
}

pub fn fractal(_: std.Io) bool {
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
    rl.clearBackground(utils.getBackgroundColor());
    // draw debug square
    //rl.drawRectangleRec(rl.Rectangle{ .x = origin_x, .y = origin_y, .width = size, .height = size }, .yellow);
    switch (S.fractal) {
        .kockSnowflake => kockSnowflake(origin_x, origin_y, size),
        .sierpinskiTriangle => sierpinskiTriangle(origin_x, origin_y, size),
        .tree => tree(origin_x, origin_y, size),
    }
    // draw back button
    if (utils.backBtn()) {
        return true;
    }
    // draw fractal selection buttons
    fractalSelectBtns(&S.fractal);

    return false;
}
