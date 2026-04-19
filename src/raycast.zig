const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const utils = @import("utils.zig");

fn init_walls() []const []const rl.Vector2 {
    const S = struct {
        const seg0 = [_]rl.Vector2{ // a line segment
            .{ .x = 100, .y = 100 },
            .{ .x = 300, .y = 100 },
            .{ .x = 300, .y = 300 },
        };
        const seg1 = [_]rl.Vector2{ // a triangle
            .{ .x = 500, .y = 200 },
            .{ .x = 600, .y = 100 },
            .{ .x = 700, .y = 200 },
            .{ .x = 500, .y = 200 },
        };
        const seg2 = blk: { // a circle approximated by a 10-sided polygon
            const cx = 700.0;
            const cy = 700.0;
            const r = 80.0;
            const n = 10;
            var pts: [n + 1]rl.Vector2 = undefined;
            for (0..n) |i| {
                const a = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / n;
                pts[i] = .{ .x = cx + r * @cos(a), .y = cy + r * @sin(a) };
            }
            pts[n] = pts[0]; // close the polygon
            break :blk pts;
        };
        const seg3 = [_]rl.Vector2{ // a closed loop with a gap
            .{ .x = 200, .y = 400 },
            .{ .x = 300, .y = 400 },
            .{ .x = 300, .y = 500 },
            .{ .x = 200, .y = 500 },
        };
        const walls: []const []const rl.Vector2 = &[_][]const rl.Vector2{
            &seg0,
            &seg1,
            &seg2,
            &seg3,
        };
    };
    return S.walls;
}

pub fn raycast(_: std.Io) bool {
    const S = struct {
        var pos: rl.Vector2 = .{ .x = 0, .y = 0 };
        var angle: f32 = 0;
        var fov: f32 = std.math.pi / 3.0;
        var num_rays: usize = 120;
        var max_depth: f32 = 1000;
        const walls = init_walls();
        var initialized: bool = false;
        // controls config
        var left_btn: bool = false;
        var right_btn: bool = false;
        var up_btn: bool = false;
        var down_btn: bool = false;
        // debug config
        var show_all_walls: bool = false;
        var cast_rays: bool = true;
    };
    if (!S.initialized) {
        S.pos = rl.Vector2{ .x = utils.i32tof32(rl.getRenderWidth()) / 2, .y = utils.i32tof32(rl.getRenderHeight()) / 2 };
        S.initialized = true;
    }
    // start drawing
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(.black);
    // draw walls
    if (S.show_all_walls) {
        for (S.walls) |wall| {
            rl.drawLineStrip(@constCast(wall), .light_gray);
        }
    }
    // cast rays
    if (S.cast_rays) {
        for (0..S.num_rays) |i| {
            const ray_angle = S.angle - S.fov / 2 + (S.fov / utils.usizetof32(S.num_rays)) * utils.usizetof32(i);
            const ray_dir = rl.Vector2{ .x = std.math.cos(ray_angle), .y = std.math.sin(ray_angle) };
            const ray_end = rl.Vector2{ .x = S.pos.x + ray_dir.x * S.max_depth, .y = S.pos.y + ray_dir.y * S.max_depth };
            // draw collisions with white blob
            var closest_collision: ?rl.Vector2 = null;
            for (S.walls) |wall| {
                for (0..wall.len - 1) |j| {
                    // ray-line segment intersection
                    const p1 = wall[j];
                    const p2 = wall[j + 1];
                    const denom = (p2.y - p1.y) * ray_dir.x - (p2.x - p1.x) * ray_dir.y;
                    if (denom == 0) continue; // parallel lines
                    const t = ((p2.x - p1.x) * (S.pos.y - p1.y) - (p2.y - p1.y) * (S.pos.x - p1.x)) / denom;
                    const u = (ray_dir.x * (S.pos.y - p1.y) - ray_dir.y * (S.pos.x - p1.x)) / denom;
                    if (t >= 0 and u >= 0 and u <= 1) {
                        const collision = rl.Vector2{ .x = S.pos.x + ray_dir.x * t, .y = S.pos.y + ray_dir.y * t };
                        if (closest_collision == null) {
                            closest_collision = collision;
                        } else {
                            const dist_to_collision = std.math.sqrt(std.math.pow(f32, collision.x - S.pos.x, 2) + std.math.pow(f32, collision.y - S.pos.y, 2));
                            const dist_to_closest = std.math.sqrt(std.math.pow(f32, closest_collision.?.x - S.pos.x, 2) + std.math.pow(f32, closest_collision.?.y - S.pos.y, 2));
                            if (dist_to_collision < dist_to_closest) {
                                closest_collision = collision;
                            }
                        }
                    }
                }
            }
            if (closest_collision != null) {
                rl.drawLineV(S.pos, closest_collision.?, .white);
                rl.drawCircleV(closest_collision.?, 5, .white);
            } else {
                rl.drawLineV(S.pos, ray_end, .white);
            }
        }
    }
    // draw location
    rl.drawCircleV(S.pos, 5, .red);
    // controls
    S.left_btn = utils.btnDown(24 + 30 + 24, 24, 50, 30, "Left");
    S.right_btn = utils.btnDown(24 + 30 + 24 + 50 + 24, 24, 50, 30, "Right");
    S.up_btn = utils.btnDown(24 + 30 + 24 + 50 + 24 + 50 + 24, 24, 50, 30, "Fwd");
    S.down_btn = utils.btnDown(24 + 30 + 24 + 50 + 24 + 50 + 24 + 50 + 24, 24, 50, 30, "Back");
    utils.checkbox(24, 24 + 30 + 24, 20, 20, "Show All Walls", &S.show_all_walls);
    utils.checkbox(24, 24 + 30 + 24 + 20 + 24, 20, 20, "Cast Rays", &S.cast_rays);
    // input handling
    if (rl.isKeyDown(rl.KeyboardKey.left) or S.left_btn) {
        S.angle -= 0.05;
        S.left_btn = false; // reset button state until next frame
    } else if (rl.isKeyDown(rl.KeyboardKey.right) or S.right_btn) {
        S.angle += 0.05;
        S.right_btn = false; // reset button state until next frame
    }
    if (rl.isKeyDown(rl.KeyboardKey.up) or S.up_btn) {
        S.pos.x += std.math.cos(S.angle) * 2;
        S.pos.y += std.math.sin(S.angle) * 2;
        S.up_btn = false; // reset button state until next frame
    } else if (rl.isKeyDown(rl.KeyboardKey.down) or S.down_btn) {
        S.pos.x -= std.math.cos(S.angle) * 2;
        S.pos.y -= std.math.sin(S.angle) * 2;
        S.down_btn = false; // reset button state until next frame
    }
    // back button
    if (utils.backBtn()) {
        return true;
    }
    return false;
}
