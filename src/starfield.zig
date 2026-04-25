const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const ut = @import("utils.zig");

const Star = struct {
    x: f32,
    y: f32,
    z: f32,
};

fn numStarsSlider(numStars: *f32) void {
    const bounds = rl.Rectangle{ .x = ut.button_spacing, .y = ut.button_spacing * 2 + ut.button_height, .width = 100, .height = 15 };
    _ = rg.slider(bounds, null, "Num. Stars", numStars, 10, 1000);
}

fn speedSlider(speed: *f32) void {
    const bounds = rl.Rectangle{ .x = ut.button_spacing, .y = ut.button_spacing * 3 + ut.button_height + 15, .width = 100, .height = 15 };
    _ = rg.slider(bounds, null, "Speed", speed, 0.1, 50.0);
}

fn maxScreenDimension() i32 {
    const width = rl.getScreenWidth();
    const height = rl.getScreenHeight();
    return if (width > height) width else height;
}

fn makeStar() Star {
    return Star{
        .x = ut.i32tof32(rl.getRandomValue(-rl.getScreenWidth(), rl.getScreenWidth())),
        .y = ut.i32tof32(rl.getRandomValue(-rl.getScreenHeight(), rl.getScreenHeight())),
        .z = ut.i32tof32(rl.getRandomValue(1, maxScreenDimension())),
    };
}

pub fn starfield(_: std.Io) bool {
    const S = struct {
        var num_stars: usize = 300;
        var speed: f32 = 10.0;
        var stars: std.ArrayList(Star) = .empty;
        var initialized: bool = false;
        var err: ?[:0]const u8 = null;
    };
    if (!S.initialized) {
        for (0..S.num_stars) |_| {
            const star = makeStar();
            S.stars.append(std.heap.c_allocator, star) catch |err| {
                std.debug.print("Failed to append star: {}\n", .{err});
                S.err = @errorName(err);
                break;
            };
        }
        S.initialized = true;
    }
    if (S.err) |err| {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(ut.getBackgroundColor());
        ut.drawTextCentered(err, 20, .red);
        return false;
    }
    // Draw stars
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(.black);
    const camera = rl.Camera2D{
        .offset = rl.Vector2{ .x = ut.i32tof32(rl.getScreenWidth()) / 2, .y = ut.i32tof32(rl.getScreenHeight()) / 2 },
        .target = rl.Vector2{ .x = 0, .y = 0 },
        .rotation = 0,
        .zoom = 1,
    };
    rl.beginMode2D(camera);
    for (S.stars.items) |*star| {
        const sx = ut.map(star.x / star.z, 0, 1, 0, ut.i32tof32(rl.getScreenWidth()));
        const sy = ut.map(star.y / star.z, 0, 1, 0, ut.i32tof32(rl.getScreenHeight()));
        const r = ut.map(star.z, 0, ut.i32tof32(maxScreenDimension()), 5, 0);
        rl.drawCircleV(rl.Vector2{ .x = sx, .y = sy }, r, .white);
        star.z -= S.speed;
        if (star.z <= 1) {
            const new_star = makeStar();
            star.x = new_star.x;
            star.y = new_star.y;
            star.z = new_star.z;
        }
    }
    rl.endMode2D();
    // draw ui
    var num_stars_f32 = ut.usizetof32(S.num_stars);
    numStarsSlider(&num_stars_f32);
    if (num_stars_f32 != ut.usizetof32(S.num_stars)) {
        S.num_stars = ut.f32tousize(num_stars_f32);
        S.stars.clearAndFree(std.heap.c_allocator);
        S.initialized = false; // reinitialize stars with new count
    }
    speedSlider(&S.speed);
    // draw back button
    if (ut.backBtn()) {
        return true;
    }
    return false;
}
