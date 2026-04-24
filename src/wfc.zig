const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const ut = @import("utils.zig");

//
// Types
//

const TilesetEntry = struct {
    tiles: std.ArrayList([:0]const u8),
    symmetry: std.ArrayList(u8), // symmetry char per tile: 'X', 'I', '\\', 'T', 'L', 'F'
    right_neighbors: std.ArrayList([4]u8), // [a_idx, a_rot, b_idx, b_rot]
    below_neighbors: std.ArrayList([4]u8),
};

const Manifest = std.StringHashMap(TilesetEntry);

// Typed structs for iterative JSON parsing (avoids recursive std.json.Value).
const ManifestTileJson = struct {
    path: []const u8,
    symmetry: []const u8,
};

const ManifestTilesetJson = struct {
    name: []const u8,
    tiles: []const ManifestTileJson,
    right_neighbors: []const [4]u8,
    below_neighbors: []const [4]u8,
};

const TextureInfo = struct {
    texture: rl.Texture,
    max_rotations: u8, // 1, 2, or 4
};

const Textures = std.ArrayList(TextureInfo);

const Tile = struct { texture_index: i32, rotation: u2 };

const Neighbor = struct { x: i32, y: i32 };

const Canvas = struct {
    tiles: std.ArrayList(Tile),
    possibilities: []i32, // parallel to tiles; -1 = placed, >= 0 = option count for empty tiles
    width: i32,
    height: i32,
    texture_size: i32,
    right_adj: []u32, // sorted owned slice of adjKey values for horizontal adjacency
    below_adj: []u32, // sorted owned slice of adjKey values for vertical adjacency
};

const ValidTile = struct { index: usize, rotation: u2 };

const HistoryEntry = struct {
    tile_index: usize,
    options: []ValidTile, // owned slice; freed when the entry is popped
    chosen_idx: usize,
};

//
// Functions
//

fn readManifest(allocator: std.mem.Allocator) !Manifest {
    const data = @embedFile("tilesets_manifest.json");
    // Use c_allocator for the temporary parse tree so small allocations go through
    // emmalloc (not wasm page_allocator which wastes a full 64KB page per alloc).
    const parsed = try std.json.parseFromSlice(
        []const ManifestTilesetJson,
        std.heap.c_allocator,
        data,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var map = Manifest.init(allocator);
    errdefer map.deinit();

    for (parsed.value) |ts| {
        const key = try allocator.dupeZ(u8, ts.name);

        var tile_list: std.ArrayList([:0]const u8) = .empty;
        errdefer tile_list.deinit(allocator);
        var sym_list: std.ArrayList(u8) = .empty;
        errdefer sym_list.deinit(allocator);
        var rn_list: std.ArrayList([4]u8) = .empty;
        errdefer rn_list.deinit(allocator);
        var bn_list: std.ArrayList([4]u8) = .empty;
        errdefer bn_list.deinit(allocator);

        for (ts.tiles) |tile| {
            const path = try allocator.dupeZ(u8, tile.path);
            try tile_list.append(allocator, path);
            const sym_char: u8 = if (tile.symmetry.len > 0) tile.symmetry[0] else 'X';
            try sym_list.append(allocator, sym_char);
        }
        for (ts.right_neighbors) |nb| {
            try rn_list.append(allocator, nb);
        }
        for (ts.below_neighbors) |nb| {
            try bn_list.append(allocator, nb);
        }

        try map.put(key, TilesetEntry{
            .tiles = tile_list,
            .symmetry = sym_list,
            .right_neighbors = rn_list,
            .below_neighbors = bn_list,
        });
    }
    return map;
}

/// Tileset selector dropdown. Returns true when the active selection changed.
fn tilesetDropdown(manifest: *const Manifest, active: *i32, edit_mode: *bool) bool {
    const offset_x = ut.button_spacing + ut.button_height + ut.button_spacing;
    const offset_y = ut.button_spacing;
    const size_x = 90;
    const size_y = ut.button_height;
    const r = rl.Rectangle{ .x = ut.i32tof32(offset_x), .y = ut.i32tof32(offset_y), .width = ut.i32tof32(size_x), .height = ut.i32tof32(size_y) };

    var buf: [1024]u8 = undefined;
    var pos: usize = 0;
    var it = manifest.keyIterator();
    var first = true;
    while (it.next()) |key| {
        if (!first) {
            buf[pos] = ';';
            pos += 1;
        }
        const name = key.*;
        @memcpy(buf[pos..][0..name.len], name);
        pos += name.len;
        first = false;
    }
    buf[pos] = 0;
    const tilesets_str: [:0]const u8 = buf[0..pos :0];
    const prev = active.*;
    if (rg.dropdownBox(r, tilesets_str, active, edit_mode.*) != 0) {
        edit_mode.* = !edit_mode.*;
    }
    return active.* != prev;
}
const canvas_size_options = [_]i32{ 5, 10, 20 };

/// Canvas size dropdown. Returns true when the selection changed.
fn canvasSizeDropdown(active: *i32, edit_mode: *bool) bool {
    const bs = ut.button_spacing;
    const bh = ut.button_height;
    const tileset_x = bs + bh + bs;
    const tileset_w = 90;
    const offset_x = tileset_x + tileset_w + bs;
    const r = rl.Rectangle{
        .x = ut.i32tof32(offset_x),
        .y = ut.i32tof32(bs),
        .width = ut.i32tof32(80),
        .height = ut.i32tof32(bh),
    };
    const prev = active.*;
    if (rg.dropdownBox(r, "5x5;10x10;20x20", active, edit_mode.*) != 0) {
        edit_mode.* = !edit_mode.*;
    }
    return active.* != prev;
}

const steps_per_frame_options = [_]usize{ 1, 2, 5 };

/// Play/pause and reset buttons at top-right. Returns true if reset was clicked.
fn controlButtons(paused: *bool, steps_idx: *i32) bool {
    const bh = ut.button_height;
    const bs = ut.button_spacing;
    const w = rl.getRenderWidth();
    const reset_x = w - bs - bh;
    const play_x = reset_x - bs - bh;
    const y_f = ut.i32tof32(bs);
    const bh_f = ut.i32tof32(bh);
    const play_label: [:0]const u8 = if (paused.*) ">" else "||";
    if (rg.button(rl.Rectangle{ .x = ut.i32tof32(play_x), .y = y_f, .width = bh_f, .height = bh_f }, play_label)) {
        paused.* = !paused.*;
    }
    const reset_clicked = rg.button(rl.Rectangle{ .x = ut.i32tof32(reset_x), .y = y_f, .width = bh_f, .height = bh_f }, "R");
    // Steps-per-frame toggle group to the left of play/pause
    const tg_w = bh * @as(i32, @intCast(steps_per_frame_options.len));
    const tg_x = play_x - bs - tg_w;
    _ = rg.toggleGroup(
        rl.Rectangle{ .x = ut.i32tof32(tg_x), .y = y_f, .width = ut.i32tof32(bh), .height = bh_f },
        "x1;x2;x5",
        steps_idx,
    );
    return reset_clicked;
}

/// Returns the tile index under the mouse in the canvas, or null if outside.
fn canvasHitTest(canvas: *Canvas, preview_h: i32) ?usize {
    if (canvas.tiles.items.len == 0 or canvas.texture_size == 0) return null;
    const offset_x = ut.button_spacing;
    const offset_y = ut.button_spacing * 3 + ut.button_height + preview_h;
    const mouse = rl.getMousePosition();
    const mx = @as(i32, @intFromFloat(mouse.x));
    const my = @as(i32, @intFromFloat(mouse.y));
    const rel_x = mx - offset_x;
    const rel_y = my - offset_y;
    if (rel_x < 0 or rel_y < 0) return null;
    const tx = @divTrunc(rel_x, canvas.texture_size);
    const ty = @divTrunc(rel_y, canvas.texture_size);
    if (tx >= canvas.width or ty >= canvas.height) return null;
    return ut.i32tousize(ty * canvas.width + tx);
}

/// Returns the index of the preview texture under the mouse, or null if none.
fn previewHitTest(textures: *Textures) ?usize {
    const max_x = rl.getRenderWidth() - ut.button_spacing;
    var x: i32 = ut.button_spacing;
    var y: i32 = ut.button_spacing * 2 + ut.button_height;
    var row_h: i32 = 0;
    const mouse = rl.getMousePosition();
    for (textures.items, 0..) |tex_info, i| {
        const ps = previewSize(tex_info.texture);
        if (x + ps > max_x and x > ut.button_spacing) {
            x = ut.button_spacing;
            y += row_h + 3;
            row_h = 0;
        }
        row_h = @max(row_h, ps);
        const bounds = rl.Rectangle{ .x = ut.i32tof32(x - 1), .y = ut.i32tof32(y - 1), .width = ut.i32tof32(ps + 2), .height = ut.i32tof32(ps + 2) };
        if (rl.checkCollisionPointRec(mouse, bounds)) return i;
        x += ps + 3;
    }
    return null;
}

fn loadTexture(path: [:0]const u8) !rl.Texture {
    if (rl.loadImage(path)) |img| {
        defer rl.unloadImage(img);
        std.debug.print("Image loaded successfully\n", .{});
        if (rl.loadTextureFromImage(img)) |tex| {
            return tex;
        } else |err| {
            std.debug.print("Failed to load texture: {}\n", .{err});
            return err;
        }
    } else |err| {
        std.debug.print("Failed to load image: {}\n", .{err});
        return err;
    }
}

fn tilesetLoadImages(manifest: *const Manifest, active: i32, textures: *Textures, active_images: *std.ArrayList(bool), canvas: *Canvas, arena: *std.heap.ArenaAllocator) bool {
    // Unload GPU textures, then free texture/active_images memory by resetting the arena.
    for (textures.items) |tex_info| rl.unloadTexture(tex_info.texture);
    _ = arena.reset(.free_all);
    textures.* = .empty;
    active_images.* = .empty;
    // Free old adjacency slices.
    if (canvas.right_adj.len > 0) std.heap.c_allocator.free(canvas.right_adj);
    if (canvas.below_adj.len > 0) std.heap.c_allocator.free(canvas.below_adj);
    canvas.right_adj = &.{};
    canvas.below_adj = &.{};
    const alloc = arena.allocator();
    var index: i32 = 0;
    var it = manifest.keyIterator();
    while (it.next()) |key| {
        if (index == active) {
            const tileset = key.*;
            if (manifest.get(tileset)) |entry| {
                for (entry.tiles.items, 0..) |path, i| {
                    const tex = loadTexture(path) catch |err| {
                        std.debug.print("Failed to load texture for tileset image '{s}': {any}\n", .{ path, err });
                        for (textures.items) |ti| rl.unloadTexture(ti.texture);
                        _ = arena.reset(.free_all);
                        textures.* = .empty;
                        active_images.* = .empty;
                        return false;
                    };
                    const sym: u8 = if (i < entry.symmetry.items.len) entry.symmetry.items[i] else 'F';
                    const max_rot: u8 = switch (sym) {
                        'X' => 1,
                        'I', '\\' => 2,
                        else => 4, // T, L, F
                    };
                    textures.append(alloc, .{ .texture = tex, .max_rotations = max_rot }) catch |err| {
                        std.debug.print("Failed to append texture for tileset image '{s}': {any}\n", .{ path, err });
                        rl.unloadTexture(tex);
                        for (textures.items) |ti| rl.unloadTexture(ti.texture);
                        _ = arena.reset(.free_all);
                        textures.* = .empty;
                        active_images.* = .empty;
                        return false;
                    };
                    active_images.append(alloc, true) catch |err| {
                        std.debug.print("Failed to append active_image for tileset image '{s}': {any}\n", .{ path, err });
                        for (textures.items) |ti| rl.unloadTexture(ti.texture);
                        _ = arena.reset(.free_all);
                        textures.* = .empty;
                        active_images.* = .empty;
                        return false;
                    };
                }
                // Build sorted adjacency slices for O(log n) lookup.
                var right_list: std.ArrayList(u32) = .empty;
                defer right_list.deinit(std.heap.c_allocator);
                var below_list: std.ArrayList(u32) = .empty;
                defer below_list.deinit(std.heap.c_allocator);
                for (entry.right_neighbors.items) |nb| {
                    right_list.append(std.heap.c_allocator, adjKey(nb[0], @intCast(nb[1]), nb[2], @intCast(nb[3]))) catch {};
                }
                for (entry.below_neighbors.items) |nb| {
                    below_list.append(std.heap.c_allocator, adjKey(nb[0], @intCast(nb[1]), nb[2], @intCast(nb[3]))) catch {};
                }
                std.mem.sort(u32, right_list.items, {}, struct {
                    fn lt(_: void, a: u32, b: u32) bool {
                        return a < b;
                    }
                }.lt);
                std.mem.sort(u32, below_list.items, {}, struct {
                    fn lt(_: void, a: u32, b: u32) bool {
                        return a < b;
                    }
                }.lt);
                canvas.right_adj = right_list.toOwnedSlice(std.heap.c_allocator) catch &.{};
                canvas.below_adj = below_list.toOwnedSlice(std.heap.c_allocator) catch &.{};
            } else {
                std.debug.print("Failed to find tileset in manifest: {s}\n", .{tileset});
                return false;
            }
            return true;
        }
        index += 1;
    }
    return false;
}

fn canvasInit(canvas: *Canvas, textures: *Textures, active_images: *std.ArrayList(bool), max_size: i32, preview_h: i32) !void {
    // get texture size, clamped to a minimum of 32px so small tiles are still visible
    const min_tile_size = 32;
    canvas.texture_size = min_tile_size;
    for (textures.items) |tex_info| {
        if (tex_info.texture.width > canvas.texture_size) {
            canvas.texture_size = tex_info.texture.width;
        }
    }
    // get max drawing area
    const draw_width = rl.getRenderWidth() - ut.button_spacing * 2;
    const draw_height = rl.getRenderHeight() - (ut.button_spacing * 4 + ut.button_height + preview_h);
    // calculate how many tiles can fit in the drawing area
    canvas.width = @min(max_size, @divTrunc(draw_width, canvas.texture_size));
    canvas.height = @min(max_size, @divTrunc(draw_height, canvas.texture_size));
    const max_tiles = canvas.width * canvas.height;
    // free old possibilities
    if (canvas.possibilities.len > 0) {
        std.heap.c_allocator.free(canvas.possibilities);
        canvas.possibilities = &.{};
    }
    // allocate canvas
    try canvas.tiles.resize(std.heap.c_allocator, ut.i32tousize(max_tiles));
    canvas.possibilities = try std.heap.c_allocator.alloc(i32, ut.i32tousize(max_tiles));
    // fill canvas with -1 to indicate unset tile
    for (canvas.tiles.items) |*tile| {
        tile.* = Tile{ .texture_index = -1, .rotation = 0 };
    }
    // compute initial possibilities (all tiles empty, so every active texture is valid everywhere)
    recomputeAllPossibilities(canvas, textures, active_images);
}

fn canvasDraw(canvas: *Canvas, textures: *Textures, selected_tile: i32, preview_h: i32) void {
    const offset_x = ut.button_spacing;
    const offset_y = ut.button_spacing * 3 + ut.button_height + preview_h;
    for (0..ut.i32tousize(canvas.height)) |y| {
        for (0..ut.i32tousize(canvas.width)) |x| {
            const tile_idx = y * ut.i32tousize(canvas.width) + x;
            const tile = canvas.tiles.items[tile_idx];
            const tex_x = offset_x + ut.usizetoi32(x) * canvas.texture_size;
            const tex_y = offset_y + ut.usizetoi32(y) * canvas.texture_size;
            const is_selected = selected_tile >= 0 and tile_idx == ut.i32tousize(selected_tile);
            if (is_selected) {
                rl.drawRectangle(tex_x, tex_y, canvas.texture_size, canvas.texture_size, .pink);
                rl.drawRectangleLinesEx(rl.Rectangle{ .x = ut.i32tof32(tex_x), .y = ut.i32tof32(tex_y), .width = ut.i32tof32(canvas.texture_size), .height = ut.i32tof32(canvas.texture_size) }, 2, .magenta);
            } else if (tile.texture_index == -2) {
                rl.drawRectangle(tex_x, tex_y, canvas.texture_size, canvas.texture_size, .pink);
                rl.drawRectangleLinesEx(rl.Rectangle{ .x = ut.i32tof32(tex_x), .y = ut.i32tof32(tex_y), .width = ut.i32tof32(canvas.texture_size), .height = ut.i32tof32(canvas.texture_size) }, 1, .red);
            } else if (tile.texture_index == -1) {
                rl.drawRectangle(tex_x, tex_y, canvas.texture_size, canvas.texture_size, .dark_gray);
                rl.drawRectangleLinesEx(rl.Rectangle{ .x = ut.i32tof32(tex_x), .y = ut.i32tof32(tex_y), .width = ut.i32tof32(canvas.texture_size), .height = ut.i32tof32(canvas.texture_size) }, 1, .light_gray);
                // draw possibility count
                if (tile_idx < canvas.possibilities.len) {
                    const poss = canvas.possibilities[tile_idx];
                    if (poss >= 0) {
                        var buf: [8]u8 = undefined;
                        const text: [:0]const u8 = std.fmt.bufPrintZ(&buf, "{d}", .{poss}) catch "?";
                        rl.drawText(text, tex_x + 2, tex_y + 2, 8, .light_gray);
                    }
                }
            } else {
                const tex_info = textures.items[ut.i32tousize(tile.texture_index)];
                const fw = ut.i32tof32(canvas.texture_size);
                const src_w = ut.i32tof32(tex_info.texture.width);
                const cx = ut.i32tof32(tex_x) + fw / 2.0;
                const cy = ut.i32tof32(tex_y) + fw / 2.0;
                rl.drawTexturePro(
                    tex_info.texture,
                    rl.Rectangle{ .x = 0, .y = 0, .width = src_w, .height = src_w },
                    rl.Rectangle{ .x = cx, .y = cy, .width = fw, .height = fw },
                    rl.Vector2{ .x = fw / 2.0, .y = fw / 2.0 },
                    @as(f32, @floatFromInt(tile.rotation)) * -90.0, // CCW, matching reference WFC rotation convention
                    .white,
                );
            }
        }
    }
}

const preview_tile_size = 32;

fn previewSize(tex: rl.Texture) i32 {
    return @max(preview_tile_size, tex.width);
}

/// Total pixel height of the preview strip, accounting for row wrapping.
fn previewTotalHeight(textures: *Textures) i32 {
    if (textures.items.len == 0) return 0;
    const max_x = rl.getRenderWidth() - ut.button_spacing;
    var x: i32 = ut.button_spacing;
    var row_h: i32 = 0;
    var total_h: i32 = 0;
    for (textures.items) |tex_info| {
        const ps = previewSize(tex_info.texture);
        if (x + ps > max_x and x > ut.button_spacing) {
            x = ut.button_spacing;
            total_h += row_h + 3;
            row_h = 0;
        }
        row_h = @max(row_h, ps);
        x += ps + 3;
    }
    total_h += row_h;
    return total_h;
}

/// Height to reserve for the preview area. Always includes the toggle button row;
/// when images_visible also accounts for the button as an extra item in the strip.
fn previewStripHeight(textures: *Textures, images_visible: bool) i32 {
    const bh = ut.button_height;
    if (!images_visible) return bh;
    const max_x = rl.getRenderWidth() - ut.button_spacing;
    var x: i32 = ut.button_spacing;
    var row_h: i32 = 0;
    var total_h: i32 = 0;
    for (textures.items) |tex_info| {
        const ps = previewSize(tex_info.texture);
        if (x + ps > max_x and x > ut.button_spacing) {
            x = ut.button_spacing;
            total_h += row_h + 3;
            row_h = 0;
        }
        row_h = @max(row_h, ps);
        x += ps + 3;
    }
    // treat the toggle button as one extra item
    if (x + bh > max_x and x > ut.button_spacing) {
        total_h += row_h + 3;
        row_h = bh;
    } else {
        row_h = @max(row_h, bh);
    }
    total_h += row_h;
    return total_h;
}

/// Position of the toggle button when images are visible: placed after the last image.
fn previewTogglePos(textures: *Textures) struct { x: i32, y: i32 } {
    const bs = ut.button_spacing;
    const bh = ut.button_height;
    const max_x = rl.getRenderWidth() - bs;
    var x: i32 = bs;
    var y: i32 = bs * 2 + bh;
    var row_h: i32 = 0;
    for (textures.items) |tex_info| {
        const ps = previewSize(tex_info.texture);
        if (x + ps > max_x and x > bs) {
            x = bs;
            y += row_h + 3;
            row_h = 0;
        }
        row_h = @max(row_h, ps);
        x += ps + 3;
    }
    if (x + bh > max_x and x > bs) {
        x = bs;
        y += row_h + 3;
    }
    return .{ .x = x, .y = y };
}

fn drawImages(textures: *Textures, active_images: *std.ArrayList(bool), pick_mode: bool) void {
    const max_x = rl.getRenderWidth() - ut.button_spacing;
    var x: i32 = ut.button_spacing;
    var y: i32 = ut.button_spacing * 2 + ut.button_height;
    var row_h: i32 = 0;
    for (textures.items, 0..) |tex_info, i| {
        const ps = previewSize(tex_info.texture);
        if (x + ps > max_x and x > ut.button_spacing) {
            x = ut.button_spacing;
            y += row_h + 3;
            row_h = 0;
        }
        row_h = @max(row_h, ps);
        const psf = ut.i32tof32(ps);
        const srcf = ut.i32tof32(tex_info.texture.width);
        rl.drawTexturePro(
            tex_info.texture,
            rl.Rectangle{ .x = 0, .y = 0, .width = srcf, .height = srcf },
            rl.Rectangle{ .x = ut.i32tof32(x), .y = ut.i32tof32(y), .width = psf, .height = psf },
            rl.Vector2{ .x = 0, .y = 0 },
            0,
            .white,
        );
        if (active_images.items[i]) {
            const bounds = rl.Rectangle{ .x = ut.i32tof32(x), .y = ut.i32tof32(y), .width = psf, .height = psf };
            rl.drawRectangleLinesEx(bounds, 2, .sky_blue);
        }
        if (pick_mode) {
            const bounds = rl.Rectangle{ .x = ut.i32tof32(x - 2), .y = ut.i32tof32(y - 2), .width = psf + 4.0, .height = psf + 4.0 };
            rl.drawRectangleLinesEx(bounds, 2, .pink);
        }
        x += ps + 3;
    }
}

fn highlightImage(textures: *Textures) void {
    const max_x = rl.getRenderWidth() - ut.button_spacing;
    var x: i32 = ut.button_spacing;
    var y: i32 = ut.button_spacing * 2 + ut.button_height;
    var row_h: i32 = 0;
    for (textures.items) |tex_info| {
        const ps = previewSize(tex_info.texture);
        if (x + ps > max_x and x > ut.button_spacing) {
            x = ut.button_spacing;
            y += row_h + 3;
            row_h = 0;
        }
        row_h = @max(row_h, ps);
        const bounds = rl.Rectangle{ .x = ut.i32tof32(x - 1), .y = ut.i32tof32(y - 1), .width = ut.i32tof32(ps + 2), .height = ut.i32tof32(ps + 2) };
        if (rl.checkCollisionPointRec(rl.getMousePosition(), bounds)) {
            rl.drawRectangleLinesEx(bounds, 2, .yellow);
        }
        x += ps + 3;
    }
}

fn selectImage(textures: *Textures, active_images: *std.ArrayList(bool)) void {
    const max_x = rl.getRenderWidth() - ut.button_spacing;
    var x: i32 = ut.button_spacing;
    var y: i32 = ut.button_spacing * 2 + ut.button_height;
    var row_h: i32 = 0;
    for (textures.items, 0..) |tex_info, i| {
        const ps = previewSize(tex_info.texture);
        if (x + ps > max_x and x > ut.button_spacing) {
            x = ut.button_spacing;
            y += row_h + 3;
            row_h = 0;
        }
        row_h = @max(row_h, ps);
        const bounds = rl.Rectangle{ .x = ut.i32tof32(x - 1), .y = ut.i32tof32(y - 1), .width = ut.i32tof32(ps + 2), .height = ut.i32tof32(ps + 2) };
        if (rl.isMouseButtonReleased(rl.MouseButton.left) and rl.checkCollisionPointRec(rl.getMousePosition(), bounds)) {
            active_images.items[i] = !active_images.items[i];
        }
        if (rl.getTouchPointCount() > 0) {
            if (rl.checkCollisionPointRec(rl.getTouchPosition(0), bounds)) {
                active_images.items[i] = !active_images.items[i];
            }
        }
        x += ps + 3;
    }
}

/// Two edges match when every RGB channel of every pixel is within tolerance_per_pixel.
fn adjKey(a_idx: usize, a_rot: u2, b_idx: usize, b_rot: u2) u32 {
    return (@as(u32, @intCast(a_idx)) << 12) |
        (@as(u32, a_rot) << 10) |
        (@as(u32, @intCast(b_idx)) << 2) |
        @as(u32, b_rot);
}

fn adjContains(adj: []const u32, key: u32) bool {
    var lo: usize = 0;
    var hi: usize = adj.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (adj[mid] == key) return true;
        if (adj[mid] < key) lo = mid + 1 else hi = mid;
    }
    return false;
}

fn canPlaceTexture(canvas: *Canvas, tile_index: usize, texture_index: usize, rotation: u2) bool {
    const x = ut.usizetoi32(tile_index % ut.i32tousize(canvas.width));
    const y = ut.usizetoi32(tile_index / ut.i32tousize(canvas.width));
    // right neighbor: (texture_index, rotation) must be a valid left tile of the right neighbor
    if (x + 1 < canvas.width) {
        const ni = ut.i32tousize(y) * ut.i32tousize(canvas.width) + ut.i32tousize(x + 1);
        const nb = canvas.tiles.items[ni];
        if (nb.texture_index >= 0) {
            if (!adjContains(canvas.right_adj, adjKey(texture_index, rotation, @intCast(nb.texture_index), nb.rotation))) return false;
        }
    }
    // left neighbor: the left neighbor must be a valid left tile of (texture_index, rotation)
    if (x > 0) {
        const ni = ut.i32tousize(y) * ut.i32tousize(canvas.width) + ut.i32tousize(x - 1);
        const nb = canvas.tiles.items[ni];
        if (nb.texture_index >= 0) {
            if (!adjContains(canvas.right_adj, adjKey(@intCast(nb.texture_index), nb.rotation, texture_index, rotation))) return false;
        }
    }
    // below neighbor: (texture_index, rotation) must be a valid top tile of the below neighbor
    if (y + 1 < canvas.height) {
        const ni = ut.i32tousize(y + 1) * ut.i32tousize(canvas.width) + ut.i32tousize(x);
        const nb = canvas.tiles.items[ni];
        if (nb.texture_index >= 0) {
            if (!adjContains(canvas.below_adj, adjKey(texture_index, rotation, @intCast(nb.texture_index), nb.rotation))) return false;
        }
    }
    // above neighbor: the above neighbor must be a valid top tile of (texture_index, rotation)
    if (y > 0) {
        const ni = ut.i32tousize(y - 1) * ut.i32tousize(canvas.width) + ut.i32tousize(x);
        const nb = canvas.tiles.items[ni];
        if (nb.texture_index >= 0) {
            if (!adjContains(canvas.below_adj, adjKey(@intCast(nb.texture_index), nb.rotation, texture_index, rotation))) return false;
        }
    }
    return true;
}

fn freeHistory(history: *std.ArrayList(HistoryEntry)) void {
    for (history.items) |entry| {
        std.heap.c_allocator.free(entry.options);
    }
    history.clearAndFree(std.heap.c_allocator);
}

fn countValidPlacements(canvas: *Canvas, textures: *Textures, active_images: *std.ArrayList(bool), tile_index: usize) usize {
    var count: usize = 0;
    for (0..active_images.items.len) |i| {
        if (!active_images.items[i]) continue;
        const num_rotations: usize = textures.items[i].max_rotations;
        for (0..num_rotations) |r| {
            if (canPlaceTexture(canvas, tile_index, i, @intCast(r))) count += 1;
        }
    }
    return count;
}

fn collectValidTiles(canvas: *Canvas, textures: *Textures, active_images: *std.ArrayList(bool), tile_index: usize) ![]ValidTile {
    var list: std.ArrayList(ValidTile) = .empty;
    errdefer list.deinit(std.heap.c_allocator);
    const num_images = active_images.items.len;
    for (0..num_images) |i| {
        if (!active_images.items[i]) continue;
        const num_rotations: usize = textures.items[i].max_rotations;
        for (0..num_rotations) |r| {
            const rot: u2 = @intCast(r);
            if (canPlaceTexture(canvas, tile_index, i, rot)) {
                try list.append(std.heap.c_allocator, .{ .index = i, .rotation = rot });
            }
        }
    }
    return list.toOwnedSlice(std.heap.c_allocator);
}

/// Recompute possibility counts for every empty tile.
/// Any empty tile with 0 valid placements is marked -2 (contradiction).
fn recomputeAllPossibilities(canvas: *Canvas, textures: *Textures, active_images: *std.ArrayList(bool)) void {
    if (canvas.possibilities.len != canvas.tiles.items.len) return;
    for (canvas.tiles.items, 0..) |*tile, i| {
        if (tile.texture_index >= 0) {
            canvas.possibilities[i] = -1; // placed
            continue;
        }
        if (tile.texture_index == -2) {
            canvas.possibilities[i] = 0;
            continue;
        }
        const count = countValidPlacements(canvas, textures, active_images, i);
        canvas.possibilities[i] = ut.usizetoi32(count);
        if (count == 0) {
            tile.* = Tile{ .texture_index = -2, .rotation = 0 };
        }
    }
}

/// Recompute possibility counts only for the 4 orthogonal neighbours of a just-placed tile.
/// Since canPlaceTexture only queries direct neighbours, only those cells can change.
fn recomputeNeighborPossibilities(canvas: *Canvas, textures: *Textures, active_images: *std.ArrayList(bool), placed_index: usize) void {
    if (canvas.possibilities.len != canvas.tiles.items.len) return;
    const w = ut.i32tousize(canvas.width);
    const px: i32 = @intCast(placed_index % w);
    const py: i32 = @intCast(placed_index / w);
    const offsets = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
    for (offsets) |off| {
        const nx = px + off[0];
        const ny = py + off[1];
        if (nx < 0 or ny < 0 or nx >= canvas.width or ny >= canvas.height) continue;
        const ni = @as(usize, @intCast(ny)) * w + @as(usize, @intCast(nx));
        const tile = &canvas.tiles.items[ni];
        if (tile.texture_index >= 0 or tile.texture_index == -2) continue;
        const count = countValidPlacements(canvas, textures, active_images, ni);
        canvas.possibilities[ni] = ut.usizetoi32(count);
        if (count == 0) tile.* = Tile{ .texture_index = -2, .rotation = 0 };
    }
}

/// Undo the most recent placement and try its next available option.
/// Returns the tile_index that was re-placed, or null if history is exhausted.
fn backtrack(canvas: *Canvas, history: *std.ArrayList(HistoryEntry)) ?usize {
    while (history.items.len > 0) {
        const entry = &history.items[history.items.len - 1];
        // undo this placement
        canvas.tiles.items[entry.tile_index] = Tile{ .texture_index = -1, .rotation = 0 };
        entry.chosen_idx += 1;
        if (entry.chosen_idx < entry.options.len) {
            // place the next available option at this level
            const next = entry.options[entry.chosen_idx];
            canvas.tiles.items[entry.tile_index] = Tile{
                .texture_index = ut.usizetoi32(next.index),
                .rotation = next.rotation,
            };
            return entry.tile_index;
        }
        // all options at this level exhausted — pop and keep backing up
        std.heap.c_allocator.free(entry.options);
        _ = history.pop();
    }
    // history empty: no solution possible with current active tiles
    return null;
}

fn calc(canvas: *Canvas, history: *std.ArrayList(HistoryEntry), textures: *Textures, active_images: *std.ArrayList(bool), rnd: *std.Random) void {
    // abort if there are no tiles free
    if (canvas.tiles.items.len == 0) {
        return;
    }
    // if any tiles are marked as contradictions (-2), clear ALL of them then backtrack once
    var has_contradiction = false;
    for (canvas.tiles.items) |*tile| {
        if (tile.texture_index == -2) {
            tile.* = Tile{ .texture_index = -1, .rotation = 0 };
            has_contradiction = true;
        }
    }
    if (has_contradiction) {
        _ = backtrack(canvas, history);
        recomputeAllPossibilities(canvas, textures, active_images);
        return;
    }
    var num_tiles_free: i32 = 0;
    var has_filled_tile = false;
    for (canvas.tiles.items) |tile| {
        if (tile.texture_index < 0) {
            num_tiles_free += 1;
        } else {
            has_filled_tile = true;
        }
    }
    if (num_tiles_free == 0) {
        return;
    }
    // abort if no active images to draw
    if (active_images.items.len == 0) {
        return;
    }
    var num_active_images: i32 = 0;
    for (active_images.items) |active| {
        if (active) {
            num_active_images += 1;
        }
    }
    if (num_active_images == 0) {
        return;
    }
    // if no tile placed yet, seed with a random one
    if (!has_filled_tile) {
        const num_images = active_images.items.len;
        const num_tiles = canvas.tiles.items.len;
        var target_tile = @mod(std.Random.int(rnd.*, usize), num_tiles);
        while (canvas.tiles.items[target_tile].texture_index >= 0) {
            target_tile = @mod(std.Random.int(rnd.*, usize), num_tiles);
        }
        var source_texure_index = @mod(std.Random.int(rnd.*, usize), num_images);
        while (!active_images.items[source_texure_index]) {
            source_texure_index = @mod(std.Random.int(rnd.*, usize), num_images);
        }
        canvas.tiles.items[target_tile] = Tile{ .texture_index = ut.usizetoi32(source_texure_index), .rotation = 0 };
        recomputeNeighborPossibilities(canvas, textures, active_images, target_tile);
        return;
    }
    // find tile indexes around filled area
    var candidate_tiles = std.ArrayList(usize).empty;
    defer candidate_tiles.deinit(std.heap.c_allocator);
    for (canvas.tiles.items, 0..) |tile, i| {
        if (tile.texture_index >= 0) {
            const x = ut.usizetoi32(i % ut.i32tousize(canvas.width));
            const y = ut.usizetoi32(i / ut.i32tousize(canvas.width));
            const neighbors = [4]Neighbor{
                .{ .x = x + 1, .y = y },
                .{ .x = x, .y = y + 1 },
                .{ .x = x - 1, .y = y },
                .{ .x = x, .y = y - 1 },
            };
            for (neighbors) |neighbor| {
                if (neighbor.x >= 0 and neighbor.x < canvas.width and neighbor.y >= 0 and neighbor.y < canvas.height) {
                    const neighbor_index = ut.i32tousize(neighbor.y) * ut.i32tousize(canvas.width) + ut.i32tousize(neighbor.x);
                    if (canvas.tiles.items[neighbor_index].texture_index < 0) {
                        // this tile is a candidate for placing a new tile
                        if (!std.mem.containsAtLeast(usize, candidate_tiles.items, 1, &.{neighbor_index})) {
                            candidate_tiles.append(std.heap.c_allocator, neighbor_index) catch |err| {
                                std.debug.print("Failed to append candidate tile index: {any}\n", .{err});
                                return;
                            };
                        }
                    }
                }
            }
        }
    }
    // choose the candidate with fewest possibilities (minimum entropy); break ties via reservoir sampling
    if (candidate_tiles.items.len > 0) {
        var min_poss: i32 = std.math.maxInt(i32);
        for (candidate_tiles.items) |ci| {
            const p = canvas.possibilities[ci];
            if (p >= 0 and p < min_poss) min_poss = p;
        }
        var target_tile = candidate_tiles.items[0];
        var n_tied: usize = 0;
        for (candidate_tiles.items) |ci| {
            if (canvas.possibilities[ci] == min_poss) {
                n_tied += 1;
                if (@mod(std.Random.int(rnd.*, usize), n_tied) == 0) target_tile = ci;
            }
        }
        // collect valid placements for the chosen tile
        const valid_tiles = collectValidTiles(canvas, textures, active_images, target_tile) catch return;
        if (valid_tiles.len == 0) {
            // safety guard: mark and backtrack next frame
            std.heap.c_allocator.free(valid_tiles);
            canvas.tiles.items[target_tile] = Tile{ .texture_index = -2, .rotation = 0 };
            return;
        }
        const chosen_idx = @mod(std.Random.int(rnd.*, usize), valid_tiles.len);
        const chosen = valid_tiles[chosen_idx];
        history.append(std.heap.c_allocator, .{
            .tile_index = target_tile,
            .options = valid_tiles,
            .chosen_idx = chosen_idx,
        }) catch {
            std.heap.c_allocator.free(valid_tiles);
            return;
        };
        canvas.tiles.items[target_tile] = Tile{ .texture_index = ut.usizetoi32(chosen.index), .rotation = chosen.rotation };
        // propagate constraints: only the 4 neighbours of the placed tile can change
        recomputeNeighborPossibilities(canvas, textures, active_images, target_tile);
    }
}

pub fn wfc(io: std.Io) bool {
    const S = struct {
        var initialised = false;
        var err: ?[:0]const u8 = null;
        var manifest: ?Manifest = null;
        var active_tileset: i32 = 0;
        var textures: Textures = .empty;
        var active_images: std.ArrayList(bool) = .empty;
        var canvas: Canvas = .{ .tiles = .empty, .possibilities = &.{}, .width = 0, .height = 0, .texture_size = 0, .right_adj = &.{}, .below_adj = &.{} };
        var history: std.ArrayList(HistoryEntry) = .empty;
        var texture_arena: std.heap.ArenaAllocator = undefined;
        var prng: std.Random.DefaultPrng = undefined;
        var rnd: std.Random = undefined;
        var paused: bool = false;
        var selected_tile: i32 = -1; // >= 0 means pick mode: user is manually choosing a texture for this tile
        var steps_idx: i32 = 0; // index into steps_per_frame_options
        var tileset_dropdown_edit: bool = false;
        var canvas_size_idx: i32 = 2; // default 20x20
        var canvas_size_dropdown_edit: bool = false;
        var preview_visible: bool = false;
    };
    if (!S.initialised) {
        S.texture_arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
        S.manifest = readManifest(std.heap.c_allocator) catch |err| blk: {
            S.err = @errorName(err);
            break :blk null;
        };
        if (S.manifest) |manifest| {
            if (!tilesetLoadImages(&manifest, S.active_tileset, &S.textures, &S.active_images, &S.canvas, &S.texture_arena)) {
                S.err = "Failed to load tileset images";
            } else {
                freeHistory(&S.history);
                canvasInit(&S.canvas, &S.textures, &S.active_images, canvas_size_options[@intCast(S.canvas_size_idx)], previewStripHeight(&S.textures, S.preview_visible)) catch |err| {
                    S.err = @errorName(err);
                };
            }
        }
        S.prng = std.Random.DefaultPrng.init(@intCast(std.Io.Clock.now(.real, io).toMicroseconds()));
        S.rnd = S.prng.random();
        S.initialised = true;
    }
    // advance WFC only when playing and not in pick mode
    if (!S.paused and S.selected_tile < 0) {
        const idx = @min(@as(usize, @intCast(S.steps_idx)), steps_per_frame_options.len - 1);
        const steps = steps_per_frame_options[idx];
        for (0..steps) |_| {
            calc(&S.canvas, &S.history, &S.textures, &S.active_images, &S.rnd);
        }
    }
    // draw everything
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(ut.getBackgroundColor());
    if (S.err) |err| {
        ut.drawTextCentered(err, 20, .red);
        return false;
    }
    if (S.manifest) |*manifest| {
        const prev_active = S.active_tileset;
        // (dropdown drawn last, after canvas, so its open list renders on top)
        _ = prev_active; // change detection done below after draw
        const ph: i32 = previewStripHeight(&S.textures, S.preview_visible);
        // Control buttons: play/pause and reset
        if (controlButtons(&S.paused, &S.steps_idx)) {
            S.selected_tile = -1;
            freeHistory(&S.history);
            canvasInit(&S.canvas, &S.textures, &S.active_images, canvas_size_options[@intCast(S.canvas_size_idx)], ph) catch |err| {
                S.err = @errorName(err);
            };
        }
        if (S.preview_visible) {
            drawImages(&S.textures, &S.active_images, S.selected_tile >= 0);
            highlightImage(&S.textures);
        }
        // Toggle button: after all images when visible, at left edge when hidden
        var preview_toggle_clicked = false;
        {
            const bh = ut.button_height;
            const bs = ut.button_spacing;
            const tp = previewTogglePos(&S.textures);
            const btn_x: i32 = if (S.preview_visible) tp.x else bs;
            const btn_y: i32 = if (S.preview_visible) tp.y else bs * 2 + bh;
            const label: [:0]const u8 = if (S.preview_visible) "<" else ">";
            if (rg.button(rl.Rectangle{ .x = ut.i32tof32(btn_x), .y = ut.i32tof32(btn_y), .width = ut.i32tof32(bh), .height = ut.i32tof32(bh) }, label)) {
                S.preview_visible = !S.preview_visible;
                preview_toggle_clicked = true;
            }
        }
        if (S.selected_tile >= 0) {
            // Pick mode: left click places the hovered preview texture on the selected tile;
            // clicking anywhere else cancels pick mode.
            if (rl.isMouseButtonReleased(rl.MouseButton.left) and !S.tileset_dropdown_edit and !S.canvas_size_dropdown_edit and !preview_toggle_clicked) {
                if (S.preview_visible) {
                    if (previewHitTest(&S.textures)) |tex_idx| {
                        const ti = ut.i32tousize(S.selected_tile);
                        S.canvas.tiles.items[ti] = Tile{ .texture_index = ut.usizetoi32(tex_idx), .rotation = 0 };
                        freeHistory(&S.history);
                        recomputeAllPossibilities(&S.canvas, &S.textures, &S.active_images);
                    }
                }
                S.selected_tile = -1;
            }
        } else {
            // Normal mode: toggle active images and detect canvas clicks.
            var prev_active_images = S.active_images.clone(std.heap.c_allocator) catch |err| {
                S.err = @errorName(err);
                return false;
            };
            defer prev_active_images.deinit(std.heap.c_allocator);
            if (S.preview_visible and !preview_toggle_clicked) selectImage(&S.textures, &S.active_images);
            for (S.active_images.items, 0..) |active, i| {
                if (active != prev_active_images.items[i]) {
                    // image was toggled
                    freeHistory(&S.history);
                    canvasInit(&S.canvas, &S.textures, &S.active_images, canvas_size_options[@intCast(S.canvas_size_idx)], ph) catch |err| {
                        S.err = @errorName(err);
                    };
                    break;
                }
            }
            // Click on a canvas tile → enter pick mode and pause
            if (rl.isMouseButtonReleased(rl.MouseButton.left) and !S.tileset_dropdown_edit and !S.canvas_size_dropdown_edit) {
                if (canvasHitTest(&S.canvas, ph)) |ti| {
                    S.selected_tile = ut.usizetoi32(ti);
                    S.paused = true;
                }
            }
        }
        canvasDraw(&S.canvas, &S.textures, S.selected_tile, ph);
        // Draw dropdowns on top so their open lists aren't obscured by the canvas.
        if (tilesetDropdown(manifest, &S.active_tileset, &S.tileset_dropdown_edit)) {
            S.selected_tile = -1;
            if (!tilesetLoadImages(manifest, S.active_tileset, &S.textures, &S.active_images, &S.canvas, &S.texture_arena)) {
                S.err = "Failed to load tileset images";
            } else {
                freeHistory(&S.history);
                canvasInit(&S.canvas, &S.textures, &S.active_images, canvas_size_options[@intCast(S.canvas_size_idx)], ph) catch |err| {
                    S.err = @errorName(err);
                };
            }
        }
        if (canvasSizeDropdown(&S.canvas_size_idx, &S.canvas_size_dropdown_edit)) {
            S.selected_tile = -1;
            freeHistory(&S.history);
            canvasInit(&S.canvas, &S.textures, &S.active_images, canvas_size_options[@intCast(S.canvas_size_idx)], ph) catch |err| {
                S.err = @errorName(err);
            };
        }
    }
    if (ut.backBtn()) {
        return true;
    }
    return false;
}
