const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const ut = @import("utils.zig");

//
// Types
//

const TilesetEntry = struct {
    tiles: std.ArrayList([:0]const u8),
    should_rotate: bool,
    pixel_tolerance: u64,
};

const Manifest = std.StringHashMap(TilesetEntry);

// Per-pixel RGB data for one edge: len = edge_pixels * 3
const EdgeId = []const u8;

const TextureId = struct {
    top: EdgeId,
    right: EdgeId,
    bottom: EdgeId,
    left: EdgeId,
    edge_pixels: usize, // number of pixels per edge (= texture width)
};

const TextureInfo = struct {
    ids: [4]TextureId, // ids[r] = TextureId for rotation r (0=0°, 1=90°CW, 2=180°, 3=270°CW)
    texture: rl.Texture,
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
    pixel_tolerance: u64,
    should_rotate: bool,
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
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();

    var map = Manifest.init(allocator);
    errdefer map.deinit();

    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        const key = try allocator.dupeZ(u8, entry.key_ptr.*);
        const obj = entry.value_ptr.object;
        var list: std.ArrayList([:0]const u8) = .empty;
        errdefer list.deinit(allocator);
        for (obj.get("tiles").?.array.items) |item| {
            const path = try std.fmt.allocPrintSentinel(allocator, "tilesets/{s}/{s}", .{ entry.key_ptr.*, item.string }, 0);
            try list.append(allocator, path);
        }
        const should_rotate = obj.get("should_rotate").?.bool;
        const pixel_tolerance: u64 = @intCast(obj.get("pixel_tolerance").?.integer);
        try map.put(key, TilesetEntry{
            .tiles = list,
            .should_rotate = should_rotate,
            .pixel_tolerance = pixel_tolerance,
        });
    }
    return map;
}

fn tilesetSelectButtons(manifest: *const Manifest, active: *i32) void {
    const offset_x = ut.button_spacing + ut.button_height + ut.button_spacing;
    const offset_y = ut.button_spacing;
    const size_x = 60;
    const size_y = ut.button_height;
    const r = rl.Rectangle{ .x = offset_x, .y = offset_y, .width = size_x, .height = size_y };

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
    _ = rg.toggleGroup(r, tilesets_str, active);
}

/// Play/pause and reset buttons at top-right. Returns true if reset was clicked.
fn controlButtons(paused: *bool) bool {
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
    return rg.button(rl.Rectangle{ .x = ut.i32tof32(reset_x), .y = y_f, .width = bh_f, .height = bh_f }, "R");
}

/// Returns the tile index under the mouse in the canvas, or null if outside.
fn canvasHitTest(canvas: *Canvas, textures: *Textures) ?usize {
    if (canvas.tiles.items.len == 0 or canvas.texture_size == 0) return null;
    const offset_x = ut.button_spacing;
    const offset_y = ut.button_spacing * 3 + ut.button_height + previewTotalHeight(textures);
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

/// Store the RGB values for each pixel along one edge. `start` and `step` are in pixel units.
fn calcEdge(allocator: std.mem.Allocator, data: [*]const u8, start: usize, step: usize, len: usize) !EdgeId {
    const buf = try allocator.alloc(u8, len * 3);
    for (0..len) |i| {
        const base = (start + i * step) * 4;
        buf[i * 3 + 0] = data[base + 0];
        buf[i * 3 + 1] = data[base + 1];
        buf[i * 3 + 2] = data[base + 2];
    }
    return buf;
}

fn calcTextureId(allocator: std.mem.Allocator, tex: rl.Texture, filepath: [:0]const u8) !TextureId {
    const w = @as(usize, @intCast(tex.width));
    std.debug.assert(w == tex.height); // all our textures are square
    var img = try rl.loadImageFromTexture(tex);
    defer rl.unloadImage(img);
    // Normalise to RGBA8 so we can always assume 4 bytes per pixel.
    img.setFormat(.uncompressed_r8g8b8a8);
    const data = @as([*]const u8, @ptrCast(img.data));

    const top = try calcEdge(allocator, data, 0, 1, w);
    errdefer allocator.free(top);
    const bottom = try calcEdge(allocator, data, (w - 1) * w, 1, w);
    errdefer allocator.free(bottom);
    const left = try calcEdge(allocator, data, 0, w, w);
    errdefer allocator.free(left);
    const right = try calcEdge(allocator, data, w - 1, w, w);

    // print texture id for debugging
    std.debug.print("Texture ID {s}:\n", .{filepath});
    std.debug.print("  width = {d}, height = {d}\n", .{ tex.width, tex.height });
    std.debug.print("  format = {any}\n", .{tex.format});
    std.debug.print("  top   [0..10] = {any}\n", .{top[0..@min(10, top.len)]});
    std.debug.print("  right [0..10] = {any}\n", .{right[0..@min(10, right.len)]});
    std.debug.print("  bottom[0..10] = {any}\n", .{bottom[0..@min(10, bottom.len)]});
    std.debug.print("  left  [0..10] = {any}\n", .{left[0..@min(10, left.len)]});

    return TextureId{
        .top = top,
        .bottom = bottom,
        .left = left,
        .right = right,
        .edge_pixels = w,
    };
}

fn reverseEdge(allocator: std.mem.Allocator, edge: EdgeId) !EdgeId {
    const n = edge.len / 3;
    const buf = try allocator.alloc(u8, edge.len);
    for (0..n) |i| {
        buf[i * 3 + 0] = edge[(n - 1 - i) * 3 + 0];
        buf[i * 3 + 1] = edge[(n - 1 - i) * 3 + 1];
        buf[i * 3 + 2] = edge[(n - 1 - i) * 3 + 2];
    }
    return buf;
}

/// Compute all 4 rotations from a base TextureId (rotation 0).
///
/// Edge storage: top/bottom are L→R (pixel 0 = left side), left/right are T→B (pixel 0 = top).
/// Matching convention: A.right[i] == B.left[i] and A.bottom[i] == B.top[i].
///
/// 90° CW:  top=rev(left), right=top,         bottom=rev(right), left=bottom
/// 180°:    top=rev(bot),  right=rev(left),    bottom=rev(top),   left=rev(right)
/// 270° CW: top=right,     right=rev(bottom),  bottom=left,       left=rev(top)
fn calcAllRotations(allocator: std.mem.Allocator, base: TextureId) ![4]TextureId {
    const px = base.edge_pixels;

    // rot1 (90° CW): top=rev(left), right=top, bottom=rev(right), left=bottom
    const r1_top = try reverseEdge(allocator, base.left);
    errdefer allocator.free(r1_top);
    const r1_right = try allocator.dupe(u8, base.top);
    errdefer allocator.free(r1_right);
    const r1_bottom = try reverseEdge(allocator, base.right);
    errdefer allocator.free(r1_bottom);
    const r1_left = try allocator.dupe(u8, base.bottom);
    errdefer allocator.free(r1_left);

    // rot2 (180°): top=rev(bottom), right=rev(left), bottom=rev(top), left=rev(right)
    const r2_top = try reverseEdge(allocator, base.bottom);
    errdefer allocator.free(r2_top);
    const r2_right = try reverseEdge(allocator, base.left);
    errdefer allocator.free(r2_right);
    const r2_bottom = try reverseEdge(allocator, base.top);
    errdefer allocator.free(r2_bottom);
    const r2_left = try reverseEdge(allocator, base.right);
    errdefer allocator.free(r2_left);

    // rot3 (270° CW): top=right, right=rev(bottom), bottom=left, left=rev(top)
    const r3_top = try allocator.dupe(u8, base.right);
    errdefer allocator.free(r3_top);
    const r3_right = try reverseEdge(allocator, base.bottom);
    errdefer allocator.free(r3_right);
    const r3_bottom = try allocator.dupe(u8, base.left);
    errdefer allocator.free(r3_bottom);
    const r3_left = try reverseEdge(allocator, base.top);

    return [4]TextureId{
        base,
        .{ .top = r1_top, .right = r1_right, .bottom = r1_bottom, .left = r1_left, .edge_pixels = px },
        .{ .top = r2_top, .right = r2_right, .bottom = r2_bottom, .left = r2_left, .edge_pixels = px },
        .{ .top = r3_top, .right = r3_right, .bottom = r3_bottom, .left = r3_left, .edge_pixels = px },
    };
}

fn tilesetLoadImages(manifest: *const Manifest, active: i32, textures: *Textures, active_images: *std.ArrayList(bool), canvas: *Canvas, arena: *std.heap.ArenaAllocator) bool {
    // Unload GPU textures, then free all edge/list memory by resetting the arena.
    for (textures.items) |tex_info| rl.unloadTexture(tex_info.texture);
    _ = arena.reset(.free_all);
    textures.* = .empty;
    active_images.* = .empty;
    const alloc = arena.allocator();
    var index: i32 = 0;
    var it = manifest.keyIterator();
    while (it.next()) |key| {
        if (index == active) {
            const tileset = key.*;
            if (manifest.get(tileset)) |entry| {
                canvas.pixel_tolerance = entry.pixel_tolerance;
                canvas.should_rotate = entry.should_rotate;
                for (entry.tiles.items) |path| {
                    const tex = loadTexture(path) catch |err| {
                        std.debug.print("Failed to load texture for tileset image '{s}': {any}\n", .{ path, err });
                        for (textures.items) |ti| rl.unloadTexture(ti.texture);
                        _ = arena.reset(.free_all);
                        textures.* = .empty;
                        active_images.* = .empty;
                        return false;
                    };
                    const base_id = calcTextureId(alloc, tex, path) catch |err| {
                        std.debug.print("Failed to calculate texture ID for '{s}': {any}\n", .{ path, err });
                        rl.unloadTexture(tex);
                        for (textures.items) |ti| rl.unloadTexture(ti.texture);
                        _ = arena.reset(.free_all);
                        textures.* = .empty;
                        active_images.* = .empty;
                        return false;
                    };
                    const all_ids = calcAllRotations(alloc, base_id) catch |err| {
                        std.debug.print("Failed to compute rotations for '{s}': {any}\n", .{ path, err });
                        rl.unloadTexture(tex);
                        for (textures.items) |ti| rl.unloadTexture(ti.texture);
                        _ = arena.reset(.free_all);
                        textures.* = .empty;
                        active_images.* = .empty;
                        return false;
                    };
                    textures.append(alloc, .{ .ids = all_ids, .texture = tex }) catch |err| {
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

fn canvasInit(canvas: *Canvas, textures: *Textures, active_images: *std.ArrayList(bool)) !void {
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
    const preview_h = previewTotalHeight(textures);
    const draw_height = rl.getRenderHeight() - (ut.button_spacing * 4 + ut.button_height + preview_h);
    // calculate how many tiles can fit in the drawing area
    canvas.width = @min(20, @divTrunc(draw_width, canvas.texture_size));
    canvas.height = @min(20, @divTrunc(draw_height, canvas.texture_size));
    const max_tiles = canvas.width * canvas.height;
    // free old possibilities
    if (canvas.possibilities.len > 0) {
        std.heap.page_allocator.free(canvas.possibilities);
        canvas.possibilities = &.{};
    }
    // allocate canvas
    try canvas.tiles.resize(std.heap.page_allocator, ut.i32tousize(max_tiles));
    canvas.possibilities = try std.heap.page_allocator.alloc(i32, ut.i32tousize(max_tiles));
    // fill canvas with -1 to indicate unset tile
    for (canvas.tiles.items) |*tile| {
        tile.* = Tile{ .texture_index = -1, .rotation = 0 };
    }
    // compute initial possibilities (all tiles empty, so every active texture is valid everywhere)
    recomputeAllPossibilities(canvas, textures, active_images);
}

fn canvasDraw(canvas: *Canvas, textures: *Textures, selected_tile: i32) void {
    const offset_x = ut.button_spacing;
    const offset_y = ut.button_spacing * 3 + ut.button_height + previewTotalHeight(textures);
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
                    @as(f32, @floatFromInt(tile.rotation)) * 90.0,
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
fn edgeMatches(a: EdgeId, b: EdgeId, tolerance_per_pixel: u64) bool {
    std.debug.assert(a.len == b.len);
    const n = a.len / 3;
    for (0..n) |i| {
        const ar: u64 = a[i * 3 + 0];
        const ag: u64 = a[i * 3 + 1];
        const ab: u64 = a[i * 3 + 2];
        const br: u64 = b[i * 3 + 0];
        const bg: u64 = b[i * 3 + 1];
        const bb: u64 = b[i * 3 + 2];
        const dr = if (ar > br) ar - br else br - ar;
        const dg = if (ag > bg) ag - bg else bg - ag;
        const db = if (ab > bb) ab - bb else bb - ab;
        if (dr > tolerance_per_pixel or dg > tolerance_per_pixel or db > tolerance_per_pixel) return false;
    }
    return true;
}

fn canPlaceTexture(canvas: *Canvas, tile_index: usize, textures: *Textures, texture_index: usize, rotation: u2) bool {
    const tex_id = textures.items[texture_index].ids[rotation];
    const tol = canvas.pixel_tolerance;
    const x = ut.usizetoi32(tile_index % ut.i32tousize(canvas.width));
    const y = ut.usizetoi32(tile_index / ut.i32tousize(canvas.width));
    // right neighbor: my right edge must match their left edge
    if (x + 1 < canvas.width) {
        const ni = ut.i32tousize(y) * ut.i32tousize(canvas.width) + ut.i32tousize(x + 1);
        const neighbor = canvas.tiles.items[ni];
        if (neighbor.texture_index >= 0) {
            const nid = textures.items[ut.i32tousize(neighbor.texture_index)].ids[neighbor.rotation];
            if (!edgeMatches(tex_id.right, nid.left, tol)) {
                //std.debug.print("FAIL right: tex={d} rot={d} at ({d},{d}) vs tex={d} rot={d} at ({d},{d})\n  my_right[0..6]={any}\n  nb_left [0..6]={any}\n", .{ texture_index, rotation, x, y, neighbor.texture_index, neighbor.rotation, x + 1, y, tex_id.right[0..@min(6, tex_id.right.len)], nid.left[0..@min(6, nid.left.len)] });
                return false;
            }
        }
    }
    // left neighbor: my left edge must match their right edge
    if (x > 0) {
        const ni = ut.i32tousize(y) * ut.i32tousize(canvas.width) + ut.i32tousize(x - 1);
        const neighbor = canvas.tiles.items[ni];
        if (neighbor.texture_index >= 0) {
            const nid = textures.items[ut.i32tousize(neighbor.texture_index)].ids[neighbor.rotation];
            if (!edgeMatches(tex_id.left, nid.right, tol)) {
                //std.debug.print("FAIL left: tex={d} rot={d} at ({d},{d}) vs tex={d} rot={d} at ({d},{d})\n  my_left [0..6]={any}\n  nb_right[0..6]={any}\n", .{ texture_index, rotation, x, y, neighbor.texture_index, neighbor.rotation, x - 1, y, tex_id.left[0..@min(6, tex_id.left.len)], nid.right[0..@min(6, nid.right.len)] });
                return false;
            }
        }
    }
    // bottom neighbor: my bottom edge must match their top edge
    if (y + 1 < canvas.height) {
        const ni = ut.i32tousize(y + 1) * ut.i32tousize(canvas.width) + ut.i32tousize(x);
        const neighbor = canvas.tiles.items[ni];
        if (neighbor.texture_index >= 0) {
            const nid = textures.items[ut.i32tousize(neighbor.texture_index)].ids[neighbor.rotation];
            if (!edgeMatches(tex_id.bottom, nid.top, tol)) return false;
        }
    }
    // top neighbor: my top edge must match their bottom edge
    if (y > 0) {
        const ni = ut.i32tousize(y - 1) * ut.i32tousize(canvas.width) + ut.i32tousize(x);
        const neighbor = canvas.tiles.items[ni];
        if (neighbor.texture_index >= 0) {
            const nid = textures.items[ut.i32tousize(neighbor.texture_index)].ids[neighbor.rotation];
            if (!edgeMatches(tex_id.top, nid.bottom, tol)) return false;
        }
    }
    return true;
}

fn freeHistory(history: *std.ArrayList(HistoryEntry)) void {
    for (history.items) |entry| {
        std.heap.page_allocator.free(entry.options);
    }
    history.clearAndFree(std.heap.page_allocator);
}

fn collectValidTiles(canvas: *Canvas, textures: *Textures, active_images: *std.ArrayList(bool), tile_index: usize) ![]ValidTile {
    var list: std.ArrayList(ValidTile) = .empty;
    errdefer list.deinit(std.heap.page_allocator);
    const num_images = active_images.items.len;
    for (0..num_images) |i| {
        if (!active_images.items[i]) continue;
        const num_rotations: usize = if (canvas.should_rotate) 4 else 1;
        for (0..num_rotations) |r| {
            const rot: u2 = @intCast(r);
            if (canPlaceTexture(canvas, tile_index, textures, i, rot)) {
                try list.append(std.heap.page_allocator, .{ .index = i, .rotation = rot });
            }
        }
    }
    return list.toOwnedSlice(std.heap.page_allocator);
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
        const valid = collectValidTiles(canvas, textures, active_images, i) catch {
            canvas.possibilities[i] = 0;
            tile.* = Tile{ .texture_index = -2, .rotation = 0 };
            continue;
        };
        defer std.heap.page_allocator.free(valid);
        canvas.possibilities[i] = ut.usizetoi32(valid.len);
        if (valid.len == 0) {
            tile.* = Tile{ .texture_index = -2, .rotation = 0 };
        }
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
        std.heap.page_allocator.free(entry.options);
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
        recomputeAllPossibilities(canvas, textures, active_images);
        return;
    }
    // find tile indexes around filled area
    var candidate_tiles = std.ArrayList(usize).empty;
    defer candidate_tiles.deinit(std.heap.page_allocator);
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
                            candidate_tiles.append(std.heap.page_allocator, neighbor_index) catch |err| {
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
            std.heap.page_allocator.free(valid_tiles);
            canvas.tiles.items[target_tile] = Tile{ .texture_index = -2, .rotation = 0 };
            return;
        }
        const chosen_idx = @mod(std.Random.int(rnd.*, usize), valid_tiles.len);
        const chosen = valid_tiles[chosen_idx];
        history.append(std.heap.page_allocator, .{
            .tile_index = target_tile,
            .options = valid_tiles,
            .chosen_idx = chosen_idx,
        }) catch {
            std.heap.page_allocator.free(valid_tiles);
            return;
        };
        canvas.tiles.items[target_tile] = Tile{ .texture_index = ut.usizetoi32(chosen.index), .rotation = chosen.rotation };
        // propagate constraints: recompute possibilities for all empty tiles
        recomputeAllPossibilities(canvas, textures, active_images);
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
        var canvas: Canvas = .{ .tiles = .empty, .possibilities = &.{}, .width = 0, .height = 0, .texture_size = 0, .pixel_tolerance = 0, .should_rotate = true };
        var history: std.ArrayList(HistoryEntry) = .empty;
        var texture_arena: std.heap.ArenaAllocator = undefined;
        var time_step_ms: i64 = 10;
        var last_update_time: i64 = 0;
        var rnd: std.Random = undefined;
        var paused: bool = false;
        var selected_tile: i32 = -1; // >= 0 means pick mode: user is manually choosing a texture for this tile
    };
    if (!S.initialised) {
        S.texture_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        S.manifest = readManifest(std.heap.page_allocator) catch |err| blk: {
            S.err = @errorName(err);
            break :blk null;
        };
        if (S.manifest) |manifest| {
            if (!tilesetLoadImages(&manifest, S.active_tileset, &S.textures, &S.active_images, &S.canvas, &S.texture_arena)) {
                S.err = "Failed to load tileset images";
            } else {
                freeHistory(&S.history);
                canvasInit(&S.canvas, &S.textures, &S.active_images) catch |err| {
                    S.err = @errorName(err);
                };
            }
        }
        var prng = std.Random.DefaultPrng.init(@intCast(std.Io.Clock.now(.real, io).toMicroseconds()));
        S.rnd = prng.random();
        S.initialised = true;
    }
    // advance WFC only when playing and not in pick mode
    const now = std.Io.Clock.now(.real, io).toMilliseconds();
    if (!S.paused and S.selected_tile < 0 and now - S.last_update_time >= S.time_step_ms) {
        calc(&S.canvas, &S.history, &S.textures, &S.active_images, &S.rnd);
        S.last_update_time = now;
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
        tilesetSelectButtons(manifest, &S.active_tileset);
        if (prev_active != S.active_tileset) {
            S.selected_tile = -1;
            if (!tilesetLoadImages(manifest, S.active_tileset, &S.textures, &S.active_images, &S.canvas, &S.texture_arena)) {
                S.err = "Failed to load tileset images";
            } else {
                freeHistory(&S.history);
                canvasInit(&S.canvas, &S.textures, &S.active_images) catch |err| {
                    S.err = @errorName(err);
                };
            }
        }
        // Control buttons: play/pause and reset
        if (controlButtons(&S.paused)) {
            S.selected_tile = -1;
            freeHistory(&S.history);
            canvasInit(&S.canvas, &S.textures, &S.active_images) catch |err| {
                S.err = @errorName(err);
            };
        }
        drawImages(&S.textures, &S.active_images, S.selected_tile >= 0);
        highlightImage(&S.textures);
        if (S.selected_tile >= 0) {
            // Pick mode: left click places the hovered preview texture on the selected tile;
            // clicking anywhere else cancels pick mode.
            if (rl.isMouseButtonReleased(rl.MouseButton.left)) {
                if (previewHitTest(&S.textures)) |tex_idx| {
                    const ti = ut.i32tousize(S.selected_tile);
                    S.canvas.tiles.items[ti] = Tile{ .texture_index = ut.usizetoi32(tex_idx), .rotation = 0 };
                    freeHistory(&S.history);
                    recomputeAllPossibilities(&S.canvas, &S.textures, &S.active_images);
                }
                S.selected_tile = -1;
            }
        } else {
            // Normal mode: toggle active images and detect canvas clicks.
            var prev_active_images = S.active_images.clone(std.heap.page_allocator) catch |err| {
                S.err = @errorName(err);
                return false;
            };
            defer prev_active_images.deinit(std.heap.page_allocator);
            selectImage(&S.textures, &S.active_images);
            for (S.active_images.items, 0..) |active, i| {
                if (active != prev_active_images.items[i]) {
                    // image was toggled
                    freeHistory(&S.history);
                    canvasInit(&S.canvas, &S.textures, &S.active_images) catch |err| {
                        S.err = @errorName(err);
                    };
                    break;
                }
            }
            // Click on a canvas tile → enter pick mode and pause
            if (rl.isMouseButtonReleased(rl.MouseButton.left)) {
                if (canvasHitTest(&S.canvas, &S.textures)) |ti| {
                    S.selected_tile = ut.usizetoi32(ti);
                    S.paused = true;
                }
            }
        }
        canvasDraw(&S.canvas, &S.textures, S.selected_tile);
    }
    if (ut.backBtn()) {
        return true;
    }
    return false;
}
