const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const ut = @import("utils.zig");

const grid_width = 50;
const grid_height = 50;

fn set(grid: *[grid_width * grid_height]bool, x: usize, y: usize) void {
    if (x < grid_width and y < grid_height)
        grid[x * grid_height + y] = true;
}

fn clearGrid(grid: *[grid_width * grid_height]bool) void {
    @memset(grid, false);
}

fn loadGlider(grid: *[grid_width * grid_height]bool) void {
    clearGrid(grid);
    // Glider pattern - 3x3 - placed at offset (1,1)
    grid[1 * grid_height + 2] = true;
    grid[2 * grid_height + 3] = true;
    grid[3 * grid_height + 1] = true;
    grid[3 * grid_height + 2] = true;
    grid[3 * grid_height + 3] = true;
}

fn loadGliderGun(grid: *[grid_width * grid_height]bool) void {
    // Gosper Glider Gun - 36x9 - placed at offset (1,1)
    clearGrid(grid);
    const ox = 1;
    const oy = 1;
    const cells = [_][2]usize{
        .{ 24, 0 },
        .{ 22, 1 },
        .{ 24, 1 },
        .{ 12, 2 },
        .{ 13, 2 },
        .{ 20, 2 },
        .{ 21, 2 },
        .{ 34, 2 },
        .{ 35, 2 },
        .{ 11, 3 },
        .{ 15, 3 },
        .{ 20, 3 },
        .{ 21, 3 },
        .{ 34, 3 },
        .{ 35, 3 },
        .{ 0, 4 },
        .{ 1, 4 },
        .{ 10, 4 },
        .{ 16, 4 },
        .{ 20, 4 },
        .{ 21, 4 },
        .{ 0, 5 },
        .{ 1, 5 },
        .{ 10, 5 },
        .{ 14, 5 },
        .{ 16, 5 },
        .{ 17, 5 },
        .{ 22, 5 },
        .{ 24, 5 },
        .{ 10, 6 },
        .{ 16, 6 },
        .{ 24, 6 },
        .{ 11, 7 },
        .{ 15, 7 },
        .{ 12, 8 },
        .{ 13, 8 },
    };
    for (cells) |c| set(grid, c[0] + ox, c[1] + oy);
}

fn loadPulsar(grid: *[grid_width * grid_height]bool) void {
    // Pulsar (period 3) - 13x13 - centered in the grid
    clearGrid(grid);
    const ox = grid_width / 2 - 6;
    const oy = grid_height / 2 - 6;
    const cells = [_][2]usize{
        .{ 2, 0 },  .{ 3, 0 },  .{ 4, 0 },  .{ 8, 0 },  .{ 9, 0 },  .{ 10, 0 },
        .{ 0, 2 },  .{ 5, 2 },  .{ 7, 2 },  .{ 12, 2 }, .{ 0, 3 },  .{ 5, 3 },
        .{ 7, 3 },  .{ 12, 3 }, .{ 0, 4 },  .{ 5, 4 },  .{ 7, 4 },  .{ 12, 4 },
        .{ 2, 5 },  .{ 3, 5 },  .{ 4, 5 },  .{ 8, 5 },  .{ 9, 5 },  .{ 10, 5 },
        .{ 2, 7 },  .{ 3, 7 },  .{ 4, 7 },  .{ 8, 7 },  .{ 9, 7 },  .{ 10, 7 },
        .{ 0, 8 },  .{ 5, 8 },  .{ 7, 8 },  .{ 12, 8 }, .{ 0, 9 },  .{ 5, 9 },
        .{ 7, 9 },  .{ 12, 9 }, .{ 0, 10 }, .{ 5, 10 }, .{ 7, 10 }, .{ 12, 10 },
        .{ 2, 12 }, .{ 3, 12 }, .{ 4, 12 }, .{ 8, 12 }, .{ 9, 12 }, .{ 10, 12 },
    };
    for (cells) |c| set(grid, c[0] + ox, c[1] + oy);
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
        loadGlider(&S.grid);
        S.last_update_time = std.Io.Clock.now(.real, io).toMilliseconds();
        S.initialized = true;
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
    rl.clearBackground(ut.getBackgroundColor());
    // draw bounding box for the grid
    const btn_width_scenes = 65;
    const margin_x = ut.button_spacing + btn_width_scenes;
    const margin_y = ut.button_spacing + ut.button_height;
    const cell_size = @min(@min(20, @divTrunc(rl.getRenderWidth() - margin_x, grid_width)), @min(20, @divTrunc(rl.getRenderHeight() - margin_y, grid_height)));
    const grid_pixel_width = grid_width * cell_size;
    const grid_pixel_height = grid_height * cell_size;
    const offset_x = @divTrunc(rl.getRenderWidth() - margin_x - grid_pixel_width, 2) + margin_x;
    const offset_y = @divTrunc(rl.getRenderHeight() - margin_y - grid_pixel_height, 2) + margin_y;
    if (cell_size < 3) {
        ut.drawTextCentered("Window too small to display grid", 10, .light_gray);
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
    const btn_width_stop_start: i32 = 80;
    var x: i32 = ut.button_spacing * 2 + btn_width_stop_start;
    var y: i32 = ut.button_spacing;
    if (ut.btn(x, y, btn_width_stop_start, ut.button_height, if (S.running) "Stop" else "Start")) {
        S.running = !S.running;
    }
    x += btn_width_stop_start + ut.button_spacing;
    const bounds = rl.Rectangle{ .x = ut.i32tof32(x), .y = ut.i32tof32(y), .width = ut.i32tof32(btn_width_stop_start), .height = ut.i32tof32(ut.button_height) };
    var speed_f32: f32 = @floatFromInt(@divTrunc(100, S.time_step_ms));
    _ = rg.slider(bounds, null, "Speed", &speed_f32, 1, 10);
    S.time_step_ms = @divTrunc(100, @as(i32, @intFromFloat(speed_f32))); // convert back to ms
    // scene buttons
    x = ut.button_spacing;
    y += ut.button_height + ut.button_spacing;
    if (ut.btn(x, y, btn_width_scenes, ut.button_height, "Glider")) {
        loadGlider(&S.grid);
        S.generation = 0;
        S.running = true;
    }
    y += ut.button_height + ut.button_spacing;
    if (ut.btn(x, y, btn_width_scenes, ut.button_height, "Glider Gun")) {
        loadGliderGun(&S.grid);
        S.generation = 0;
        S.running = true;
    }
    y += ut.button_height + ut.button_spacing;
    if (ut.btn(x, y, btn_width_scenes, ut.button_height, "Pulsar")) {
        loadPulsar(&S.grid);
        S.generation = 0;
        S.running = true;
    }
    // draw generation count
    y += ut.button_height + ut.button_spacing;
    var gen_buf: [64]u8 = undefined;
    const gen_text = std.fmt.bufPrintZ(&gen_buf, "Gen.: {}", .{S.generation}) catch "Generation: ???";
    rl.drawText(gen_text, x, y, 10, .light_gray);
    // back button
    if (ut.backBtn()) {
        return true;
    }
    return false;
}
