const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const utils = @import("utils.zig");

const grid_width = 50;
const grid_height = 50;

fn init(grid: *[grid_width * grid_height]bool) void {
    // initialize with glider pattern
    grid[1 * grid_height + 2] = true;
    grid[2 * grid_height + 3] = true;
    grid[3 * grid_height + 1] = true;
    grid[3 * grid_height + 2] = true;
    grid[3 * grid_height + 3] = true;
}

fn calc(grid: *[grid_width * grid_height]bool) void {
    var new_grid: [grid_width * grid_height]bool = .{false} ** (grid_width * grid_height);
    for (0..grid_width) |grid_x| {
        for (0..grid_height) |grid_y| {
            const idx = grid_x * grid_height + grid_y;
            const alive = grid[idx];
            var live_neighbors: u8 = 0;
            const r = [3]i32{ -1, 0, 1 };
            for (r) |dx| {
                for (r) |dy| {
                    if (dx == 0 and dy == 0) continue; // skip self
                    const neighbor_x = @as(i32, @intCast(grid_x)) + dx;
                    const neighbor_y = @as(i32, @intCast(grid_y)) + dy;
                    if (neighbor_x >= 0 and neighbor_x < grid_width and neighbor_y >= 0 and neighbor_y < grid_height) {
                        const neighbor_idx = @as(usize, @intCast(neighbor_x * grid_height + neighbor_y));
                        if (grid[neighbor_idx]) {
                            live_neighbors += 1;
                        }
                    }
                }
            }
            // apply rules of the game
            if (alive and (live_neighbors == 2 or live_neighbors == 3)) {
                new_grid[idx] = true; // stay alive
            } else if (!alive and live_neighbors == 3) {
                new_grid[idx] = true; // become alive
            } else {
                new_grid[idx] = false; // die or stay dead
            }
        }
    }
    // copy new_grid back to grid
    @memcpy(grid, &new_grid);
}

fn startStopBtn(running: *bool) void {
    const label = if (running.*) "Stop" else "Start";
    if (rg.button(.init(24 + 30 + 24, 24, 80, 30), label)) {
        running.* = !running.*;
    }
}

fn speedSlider(speed: *i64) void {
    // speed slider
    const bounds = rl.Rectangle{ .x = 24 + 30 + 24 + 80 + 24, .y = 24 + 7, .width = 100, .height = 15 };
    var speed_f32: f32 = @floatFromInt(speed.*);
    _ = rg.slider(bounds, null, "Speed", &speed_f32, 1, 10);
    speed.* = @intFromFloat(speed_f32);
}

pub fn gameOfLife(io: std.Io) bool {
    const S = struct {
        var grid: [grid_width * grid_height]bool = .{false} ** (grid_width * grid_height);
        var initialized: bool = false;
        var last_update_time: i64 = 0;
        var running: bool = true;
        var generation: u64 = 0;
        var time_step_ms: i64 = 100;
    };
    if (!S.initialized) {
        init(&S.grid);
        S.initialized = true;
        S.last_update_time = std.Io.Clock.now(.real, io).toMilliseconds();
    } else if (S.running) {
        const now = std.Io.Clock.now(.real, io).toMilliseconds();
        if (now - S.last_update_time >= S.time_step_ms) {
            calc(&S.grid);
            S.last_update_time = now;
            S.generation += 1;
        }
    }
    // start drawing
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(utils.getBackgroundColor());
    // draw bounding box for the grid
    const cell_size = @min(20, @divTrunc(rl.getRenderWidth() - 100, grid_width));
    const grid_pixel_width = grid_width * cell_size;
    const grid_pixel_height = grid_height * cell_size;
    const offset_x = @divTrunc(rl.getRenderWidth() - grid_pixel_width, 2);
    const offset_y = @divTrunc(rl.getRenderHeight() - grid_pixel_height, 2);
    if (cell_size < 3) {
        utils.drawTextCentered("Window too small to display grid", 10, .light_gray);
    } else {
        // draw grid lines
        for (0..grid_height + 1) |grid_y| {
            const y = offset_y + (@as(i32, @intCast(grid_y)) * cell_size);
            rl.drawLine(offset_x, y, offset_x + grid_pixel_width, y, .light_gray);
        }
        for (0..grid_width + 1) |grid_x| {
            const x = offset_x + (@as(i32, @intCast(grid_x)) * cell_size);
            rl.drawLine(x, offset_y, x, offset_y + grid_pixel_height, .light_gray);
        }
        // draw live cells
        for (0..grid_width) |grid_x| {
            for (0..grid_height) |grid_y| {
                if (S.grid[grid_x * grid_height + grid_y]) {
                    const x = offset_x + (@as(i32, @intCast(grid_x)) * cell_size);
                    const y = offset_y + (@as(i32, @intCast(grid_y)) * cell_size);
                    rl.drawRectangle(x, y, cell_size, cell_size, .light_gray);
                }
            }
        }
    }
    // draw generation count
    var gen_buf: [64]u8 = undefined;
    const gen_text = std.fmt.bufPrintZ(&gen_buf, "Generation: {}", .{S.generation}) catch "Generation: ???";
    rl.drawText(gen_text, offset_x, offset_y + grid_height * cell_size + 10, 10, .light_gray);
    // handle input
    const mouse_x = rl.getMouseX();
    const mouse_y = rl.getMouseY();
    var grid_x = @divTrunc(mouse_x - offset_x, cell_size);
    var grid_y = @divTrunc(mouse_y - offset_y, cell_size);
    if (grid_x >= 0 and grid_x < grid_width and grid_y >= 0 and grid_y < grid_height) {
        // highlight cell under mouse cursor
        rl.drawRectangleLines(offset_x + grid_x * cell_size, offset_y + grid_y * cell_size, cell_size, cell_size, .sky_blue);
        // toggle cell state on click
        if (rl.isMouseButtonDown(rl.MouseButton.left)) {
            const idx = @as(usize, @intCast(grid_x * grid_height + grid_y));
            S.grid[idx] = true;
            S.running = false; // pause the game when user interacts with the grid
        }
    }
    if (rl.getTouchPointCount() > 0) {
        const touch_x = rl.getTouchX();
        const touch_y = rl.getTouchY();
        grid_x = @divTrunc(touch_x - offset_x, cell_size);
        grid_y = @divTrunc(touch_y - offset_y, cell_size);
        // toggle cell state on touch
        if (grid_x >= 0 and grid_x < grid_width and grid_y >= 0 and grid_y < grid_height) {
            const idx = @as(usize, @intCast(grid_x * grid_height + grid_y));
            S.grid[idx] = true;
            S.running = false; // pause the game when user interacts with the grid
        }
    }
    // controls
    startStopBtn(&S.running);
    var speed = @divTrunc(100, S.time_step_ms); // convert to 1-10 range for slider
    speedSlider(&speed);
    S.time_step_ms = @divTrunc(100, speed); // convert back to ms
    // back button
    if (utils.backBtn()) {
        return true;
    }
    return false;
}
