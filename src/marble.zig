const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const rg = @import("raygui");

const ut = @import("utils.zig");

const is_web = builtin.target.os.tag == .emscripten;

const vs_src: [:0]const u8 = if (is_web)
    \\#version 300 es
    \\precision mediump float;
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec3 vertexNormal;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\uniform mat4 matModel;
    \\uniform mat4 matNormal;
    \\out vec3 fragPos;
    \\out vec2 fragTexCoord;
    \\out vec4 fragColor;
    \\out vec3 fragNormal;
    \\void main() {
    \\    fragPos = vec3(matModel * vec4(vertexPosition, 1.0));
    \\    fragNormal = normalize(mat3(matNormal) * vertexNormal);
    \\    fragTexCoord = vertexTexCoord;
    \\    fragColor = vertexColor;
    \\    gl_Position = mvp * vec4(vertexPosition, 1.0);
    \\}
else
    \\#version 330
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec3 vertexNormal;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\uniform mat4 matModel;
    \\uniform mat4 matNormal;
    \\out vec3 fragPos;
    \\out vec2 fragTexCoord;
    \\out vec4 fragColor;
    \\out vec3 fragNormal;
    \\void main() {
    \\    fragPos = vec3(matModel * vec4(vertexPosition, 1.0));
    \\    fragNormal = normalize(mat3(matNormal) * vertexNormal);
    \\    fragTexCoord = vertexTexCoord;
    \\    fragColor = vertexColor;
    \\    gl_Position = mvp * vec4(vertexPosition, 1.0);
    \\}
;

const fs_src: [:0]const u8 = if (is_web)
    \\#version 300 es
    \\precision mediump float;
    \\#define NUM_LIGHTS 5
    \\in vec3 fragPos;
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\in vec3 fragNormal;
    \\uniform sampler2D texture0;
    \\uniform vec4 colDiffuse;
    \\uniform vec3 viewPos;
    \\uniform vec3 lightPositions[NUM_LIGHTS];
    \\uniform vec3 lightColors[NUM_LIGHTS];
    \\uniform vec4 ambient;
    \\out vec4 finalColor;
    \\void main() {
    \\    vec4 texelColor = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    \\    // World-space procedural marble pattern (no UVs needed)
    \\    float stripe = sin(fragPos.x * 2.0 + fragPos.z * 2.0 + sin(fragPos.x * 3.7 + fragPos.z * 1.3) * 0.8) * 0.5 + 0.5;
    \\    stripe = pow(stripe, 0.35);
    \\    vec3 col_light = vec3(0.93, 0.89, 0.82);
    \\    vec3 col_dark  = vec3(0.52, 0.38, 0.24);
    \\    vec3 marble_color = mix(col_dark, col_light, stripe);
    \\    texelColor = vec4(marble_color, 1.0) * colDiffuse * fragColor;
    \\    vec3 norm = normalize(fragNormal);
    \\    vec3 viewDir = normalize(viewPos - fragPos);
    \\    vec3 lighting = ambient.rgb * ambient.a;
    \\    for (int i = 0; i < NUM_LIGHTS; i++) {
    \\        vec3 lightDir = normalize(lightPositions[i] - fragPos);
    \\        float diff = abs(dot(norm, lightDir));
    \\        vec3 halfDir = normalize(lightDir + viewDir);
    \\        float spec = pow(max(dot(norm, halfDir), 0.0), 64.0);
    \\        float dist = length(lightPositions[i] - fragPos);
    \\        float atten = 1.0 / (1.0 + 0.08 * dist);
    \\        lighting += (diff * lightColors[i] + spec * vec3(0.5)) * atten;
    \\    }
    \\    finalColor = vec4(lighting * texelColor.rgb, texelColor.a);
    \\}
else
    \\#version 330
    \\#define NUM_LIGHTS 5
    \\in vec3 fragPos;
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\in vec3 fragNormal;
    \\uniform sampler2D texture0;
    \\uniform vec4 colDiffuse;
    \\uniform vec3 viewPos;
    \\uniform vec3 lightPositions[NUM_LIGHTS];
    \\uniform vec3 lightColors[NUM_LIGHTS];
    \\uniform vec4 ambient;
    \\out vec4 finalColor;
    \\void main() {
    \\    vec4 texelColor = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    \\    // World-space procedural marble pattern (no UVs needed)
    \\    float stripe = sin(fragPos.x * 2.0 + fragPos.z * 2.0 + sin(fragPos.x * 3.7 + fragPos.z * 1.3) * 0.8) * 0.5 + 0.5;
    \\    stripe = pow(stripe, 0.35);
    \\    vec3 col_light = vec3(0.93, 0.89, 0.82);
    \\    vec3 col_dark  = vec3(0.52, 0.38, 0.24);
    \\    vec3 marble_color = mix(col_dark, col_light, stripe);
    \\    texelColor = vec4(marble_color, 1.0) * colDiffuse * fragColor;
    \\    vec3 norm = normalize(fragNormal);
    \\    vec3 viewDir = normalize(viewPos - fragPos);
    \\    vec3 lighting = ambient.rgb * ambient.a;
    \\    for (int i = 0; i < NUM_LIGHTS; i++) {
    \\        vec3 lightDir = normalize(lightPositions[i] - fragPos);
    \\        float diff = abs(dot(norm, lightDir));
    \\        vec3 halfDir = normalize(lightDir + viewDir);
    \\        float spec = pow(max(dot(norm, halfDir), 0.0), 64.0);
    \\        float dist = length(lightPositions[i] - fragPos);
    \\        float atten = 1.0 / (1.0 + 0.08 * dist);
    \\        lighting += (diff * lightColors[i] + spec * vec3(0.5)) * atten;
    \\    }
    \\    finalColor = vec4(lighting * texelColor.rgb, texelColor.a);
    \\}
;
const Lighting = struct {
    shader: rl.Shader,
    loc_view_pos: i32,
    loc_light_positions: i32,
    loc_light_colors: i32,
    loc_ambient: i32,
};

const Socket = enum { flat, channel };

const Connector = struct {
    pos: rl.Vector3,
    normal: rl.Vector3,
    socket: Socket,
};
const Connectors = std.ArrayList(Connector);

const MAX_TILE_NAME_LEN = 32;

const Tile = struct {
    name: [MAX_TILE_NAME_LEN]u8,
    weight: u32,
    model: rl.Model,
    connectors: Connectors,
};

const Tiles = std.ArrayList(Tile);

const TilePlaced = struct {
    tile: Tile,
    pos: rl.Vector3,
    rotation_y_deg: f32,
};

const TilesPlaced = std.ArrayList(TilePlaced);

const ConnectorJson = struct {
    position: [3]f32,
    normal: [3]f32,
    socket: []const u8,
};

const TileJson = struct {
    name: []const u8,
    file: []const u8,
    type: []const u8,
    weight: u32,
    connectors: []const ConnectorJson,
};

const TilesJson = struct {
    tiles: []const TileJson,
};

fn initLighting() !Lighting {
    const shader = try rl.loadShaderFromMemory(vs_src, fs_src);
    return .{
        .shader = shader,
        .loc_view_pos = rl.getShaderLocation(shader, "viewPos"),
        .loc_light_positions = rl.getShaderLocation(shader, "lightPositions[0]"),
        .loc_light_colors = rl.getShaderLocation(shader, "lightColors[0]"),
        .loc_ambient = rl.getShaderLocation(shader, "ambient"),
    };
}

fn applyShaderToModel(model: *rl.Model, shader: rl.Shader) void {
    var i: c_int = 0;
    while (i < model.materialCount) : (i += 1) {
        model.materials[@intCast(i)].shader = shader;
    }
}

fn loadTiles(io: std.Io, allocator: std.mem.Allocator) !Tiles {
    const json_data = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "marble_tiles/tiles.json",
        std.heap.c_allocator,
        std.Io.Limit.limited(1024 * 1024),
    );
    defer std.heap.c_allocator.free(json_data);
    const parsed = try std.json.parseFromSlice(
        TilesJson,
        std.heap.c_allocator,
        json_data,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var tiles: Tiles = .empty;
    errdefer {
        for (tiles.items) |*t| {
            rl.unloadModel(t.model);
            t.connectors.deinit(allocator);
        }
        tiles.deinit(allocator);
    }

    for (parsed.value.tiles) |tile| {
        if (!std.mem.eql(u8, tile.type, "gravity_track")) continue;

        const path = try std.fmt.allocPrintSentinel(std.heap.c_allocator, "marble_tiles/{s}", .{tile.file}, 0);
        defer std.heap.c_allocator.free(path);

        const model = try rl.loadModel(path);

        var connectors: Connectors = .empty;
        errdefer connectors.deinit(allocator);

        for (tile.connectors) |c| {
            const socket: Socket = if (std.mem.eql(u8, c.socket, "channel")) .channel else .flat;
            try connectors.append(allocator, .{
                .pos = .{ .x = c.position[0], .y = c.position[1], .z = c.position[2] },
                .normal = .{ .x = c.normal[0], .y = c.normal[1], .z = c.normal[2] },
                .socket = socket,
            });
        }

        var name_buf = std.mem.zeroes([MAX_TILE_NAME_LEN]u8);
        const copy_len = @min(tile.name.len, MAX_TILE_NAME_LEN);
        @memcpy(name_buf[0..copy_len], tile.name[0..copy_len]);

        try tiles.append(allocator, .{
            .name = name_buf,
            .weight = tile.weight,
            .model = model,
            .connectors = connectors,
        });
        std.debug.print("Loaded model: {s} with {d} connectors\n", .{ tile.name, connectors.items.len });
    }

    return tiles;
}

fn initTrack(tiles: Tiles, bounds_pos: rl.Vector3, bounds_width: f32, bounds_height: f32, bounds_length: f32) !TilesPlaced {
    const bw_half = bounds_width / 2.0;
    const bh_half = bounds_height / 2.0;
    const bl_half = bounds_length / 2.0;
    var tiles_placed: TilesPlaced = .empty;
    for (tiles.items) |*tile| {
        if (std.mem.startsWith(u8, &tile.name, "start")) {
            // place start at top of box facing inward
            tiles_placed.append(std.heap.c_allocator, .{
                .tile = tile.*,
                .pos = .{ .x = bounds_pos.x - bw_half + 1, .y = bounds_pos.y + bh_half - 1, .z = bounds_pos.z + bl_half + 1 },
                .rotation_y_deg = 0,
            }) catch |err| {
                std.debug.print("Failed to place start tile: {}\n", .{err});
                return err;
            };
        } else if (std.mem.startsWith(u8, &tile.name, "end")) {
            // place end at bottom-right of box facing inward
            tiles_placed.append(std.heap.c_allocator, .{
                .tile = tile.*,
                .pos = .{ .x = bounds_pos.x + bw_half - 1, .y = bounds_pos.y - bh_half, .z = bounds_pos.z - bl_half - 1 },
                .rotation_y_deg = 180,
            }) catch |err| {
                std.debug.print("Failed to place end tile: {}\n", .{err});
                return err;
            };
        }
    }
    return tiles_placed;
}

/// Rotate a local connector normal/position by rotation_y_deg (0/90/180/270).
fn rotateY(v: rl.Vector3, deg: f32) rl.Vector3 {
    // Only 0/90/180/270 degrees are used, so we snap to exact integer arithmetic.
    const d: i32 = @intFromFloat(@mod(deg + 0.5, 360.0));
    return switch (@mod(d, 360)) {
        90 => .{ .x = v.z, .y = v.y, .z = -v.x },
        180 => .{ .x = -v.x, .y = v.y, .z = -v.z },
        270 => .{ .x = -v.z, .y = v.y, .z = v.x },
        else => v,
    };
}

/// World-space connector position for a placed tile.
fn worldConnectorPos(tp: TilePlaced, c: Connector) rl.Vector3 {
    const rp = rotateY(c.pos, tp.rotation_y_deg);
    return .{ .x = tp.pos.x + rp.x, .y = tp.pos.y + rp.y, .z = tp.pos.z + rp.z };
}

/// World-space connector normal for a placed tile.
fn worldConnectorNormal(tp: TilePlaced, c: Connector) rl.Vector3 {
    return rotateY(c.normal, tp.rotation_y_deg);
}

/// True if two world-space normals are opposite (to within rounding).
fn normalsOpposite(a: rl.Vector3, b: rl.Vector3) bool {
    return @abs(a.x + b.x) < 0.1 and @abs(a.y + b.y) < 0.1 and @abs(a.z + b.z) < 0.1;
}

/// True if two world-space positions are close enough to be the same connection point.
fn posClose(a: rl.Vector3, b: rl.Vector3) bool {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    const dz = a.z - b.z;
    return (dx * dx + dy * dy + dz * dz) < 0.1;
}

/// An open connector in world space: where it is, which direction it faces, what socket it is.
const OpenConnector = struct {
    pos: rl.Vector3,
    normal: rl.Vector3,
    socket: Socket,
};

const MAX_DECISIONS = 256;

const CandidateEntry = struct {
    tile_idx: usize,
    rot: f32,
    pos: rl.Vector3,
};

const Decision = struct {
    candidates: [64]CandidateEntry,
    n_candidates: usize,
    chosen_idx: usize,
    tiles_placed_len_before: usize,
};

/// Collect all connectors on already-placed tiles that are not connected to anything.
fn collectOpenConnectors(tiles_placed: TilesPlaced, allocator: std.mem.Allocator) !std.ArrayList(OpenConnector) {
    var open: std.ArrayList(OpenConnector) = .empty;
    errdefer open.deinit(allocator);

    // For each connector on each placed tile, check if another placed tile has a connector
    // at the same world position facing the opposite direction. If not — it's open.
    for (tiles_placed.items) |tp| {
        connector_loop: for (tp.tile.connectors.items) |c| {
            const wpos = worldConnectorPos(tp, c);
            const wnorm = worldConnectorNormal(tp, c);
            for (tiles_placed.items) |other_tp| {
                for (other_tp.tile.connectors.items) |oc| {
                    const owpos = worldConnectorPos(other_tp, oc);
                    const ownorm = worldConnectorNormal(other_tp, oc);
                    if (posClose(wpos, owpos) and normalsOpposite(wnorm, ownorm)) {
                        continue :connector_loop;
                    }
                }
            }
            try open.append(allocator, .{ .pos = wpos, .normal = wnorm, .socket = c.socket });
        }
    }
    return open;
}

/// Check if placing `candidate` tile at `candidate_pos` with `rot_deg` rotation
/// would satisfy the `open` connector (i.e. one of the candidate's connectors plugs into it).
/// Returns the world-space tile origin that makes the connector match, or null if impossible.
fn findMatchingPlacement(
    candidate: *Tile,
    open: OpenConnector,
    rot_deg: f32,
) ?rl.Vector3 {
    // The open connector expects something with the OPPOSITE normal and SAME socket.
    for (candidate.connectors.items) |cc| {
        const rotated_normal = rotateY(cc.normal, rot_deg);
        if (!normalsOpposite(rotated_normal, open.normal)) continue;
        if (cc.socket != open.socket) continue;
        // The candidate's connector would sit at (tile_origin + rotated(cc.pos)).
        // We want that to equal open.pos. So tile_origin = open.pos - rotated(cc.pos).
        const rp = rotateY(cc.pos, rot_deg);
        return .{
            .x = open.pos.x - rp.x,
            .y = open.pos.y - rp.y,
            .z = open.pos.z - rp.z,
        };
    }
    return null;
}

/// True if a tile placed at `pos` with `rot_deg` is entirely inside the bounding box.
/// Uses connector positions to determine the tile's lateral (XZ) footprint.
/// Tile floor is at pos.y; ceiling is 0.5 above the highest connector y.
fn withinBounds(pos: rl.Vector3, rot_deg: f32, tile: *Tile, bounds_pos: rl.Vector3, bounds_width: f32, bounds_height: f32, bounds_length: f32) bool {
    const hw = bounds_width / 2.0;
    const hh = bounds_height / 2.0;
    const hl = bounds_length / 2.0;

    // Tile floor is at pos.y (local y=0).
    if (pos.y < bounds_pos.y - hh) return false;

    var max_local_y: f32 = 0.5; // at least one unit tall
    for (tile.connectors.items) |c| {
        const rp = rotateY(c.pos, rot_deg);
        // Lateral bounds: connector position IS the tile face boundary.
        if (pos.x + rp.x < bounds_pos.x - hw or pos.x + rp.x > bounds_pos.x + hw) return false;
        if (pos.z + rp.z < bounds_pos.z - hl or pos.z + rp.z > bounds_pos.z + hl) return false;
        // Track max local y (rotation around Y doesn't change y).
        if (c.pos.y > max_local_y) max_local_y = c.pos.y;
    }
    // Tile ceiling = pos.y + max_local_y + 0.5 (connector is at face midpoint).
    if (pos.y + max_local_y + 0.5 > bounds_pos.y + hh) return false;

    return true;
}

/// True if any already-placed tile occupies approximately the same origin.
fn alreadyOccupied(tiles_placed: TilesPlaced, pos: rl.Vector3) bool {
    for (tiles_placed.items) |tp| {
        if (posClose(tp.pos, pos)) return true;
    }
    return false;
}

/// Local (tile-relative) axis-aligned bounding box derived from connector positions.
///
/// Logic per connector, after applying rotation:
///   ±Z face (|rn.z| ≈ 1): defines z boundary; tile spans ±1 in x around the connector x.
///   ±X face (|rn.x| ≈ 1): defines x boundary; tile spans ±1 in z around the connector z.
/// Y extent: [0, max_connector_y + 0.5].
const TileBB = struct { x_min: f32, x_max: f32, z_min: f32, z_max: f32, y_max: f32 };

fn tileBBLocal(tile: *const Tile, rot_deg: f32) TileBB {
    var bb = TileBB{
        .x_min = std.math.floatMax(f32),
        .x_max = -std.math.floatMax(f32),
        .z_min = std.math.floatMax(f32),
        .z_max = -std.math.floatMax(f32),
        .y_max = 0.0,
    };
    for (tile.connectors.items) |c| {
        const rp = rotateY(c.pos, rot_deg);
        const rn = rotateY(c.normal, rot_deg);
        if (rp.y > bb.y_max) bb.y_max = rp.y;
        if (rn.z < -0.9) { // -Z face: z boundary, x spans ±1 around connector x
            bb.z_min = @min(bb.z_min, rp.z);
            bb.x_min = @min(bb.x_min, rp.x - 1.0);
            bb.x_max = @max(bb.x_max, rp.x + 1.0);
        } else if (rn.z > 0.9) { // +Z face
            bb.z_max = @max(bb.z_max, rp.z);
            bb.x_min = @min(bb.x_min, rp.x - 1.0);
            bb.x_max = @max(bb.x_max, rp.x + 1.0);
        } else if (rn.x < -0.9) { // -X face: x boundary, z spans ±1 around connector z
            bb.x_min = @min(bb.x_min, rp.x);
            bb.z_min = @min(bb.z_min, rp.z - 1.0);
            bb.z_max = @max(bb.z_max, rp.z + 1.0);
        } else if (rn.x > 0.9) { // +X face
            bb.x_max = @max(bb.x_max, rp.x);
            bb.z_min = @min(bb.z_min, rp.z - 1.0);
            bb.z_max = @max(bb.z_max, rp.z + 1.0);
        }
    }
    return bb;
}

/// Returns true if a candidate tile at world `pos` with `rot_deg` would have its
/// body AABB overlap with any already-placed tile's body AABB.
/// Uses strict inequality so tiles sharing a face (touching) are NOT flagged.
fn overlapsAnyTile(tiles_placed: TilesPlaced, pos: rl.Vector3, tile: *const Tile, rot_deg: f32) bool {
    const nb = tileBBLocal(tile, rot_deg);
    const na_x0 = pos.x + nb.x_min;
    const na_x1 = pos.x + nb.x_max;
    const na_z0 = pos.z + nb.z_min;
    const na_z1 = pos.z + nb.z_max;
    const na_y0 = pos.y;
    const na_y1 = pos.y + nb.y_max + 0.5;
    for (tiles_placed.items) |tp| {
        const tb = tileBBLocal(&tp.tile, tp.rotation_y_deg);
        const ta_x0 = tp.pos.x + tb.x_min;
        const ta_x1 = tp.pos.x + tb.x_max;
        const ta_z0 = tp.pos.z + tb.z_min;
        const ta_z1 = tp.pos.z + tb.z_max;
        const ta_y0 = tp.pos.y;
        const ta_y1 = tp.pos.y + tb.y_max + 0.5;
        // X and Z use strict overlap (touching faces are fine).
        // Y adds a marble-clearance margin: a tile sitting exactly on another tile's
        // ceiling would block the marble rolling in the groove below.
        const marble_margin: f32 = 0.3;
        if (na_x0 < ta_x1 and na_x1 > ta_x0 and
            na_z0 < ta_z1 and na_z1 > ta_z0 and
            na_y0 < ta_y1 + marble_margin and na_y1 > ta_y0 - marble_margin)
        {
            return true;
        }
    }
    return false;
}

/// Returns false if the new tile's XZ footprint overlaps any already-placed tile's footprint
/// AND the two tile bodies are not separated vertically by at least `clearance` units.
/// Uses proper AABB XZ overlap rather than origin-proximity, so large tiles (e.g. curve)
/// are checked correctly regardless of where their origin lands.
fn hasVerticalClearance(tiles_placed: TilesPlaced, pos: rl.Vector3, tile: *const Tile, rot_deg: f32) bool {
    const clearance: f32 = 0.5;
    const nb = tileBBLocal(tile, rot_deg);
    const na_x0 = pos.x + nb.x_min;
    const na_x1 = pos.x + nb.x_max;
    const na_z0 = pos.z + nb.z_min;
    const na_z1 = pos.z + nb.z_max;
    const na_y0 = pos.y;
    const na_y1 = pos.y + nb.y_max + 0.5;
    for (tiles_placed.items) |tp| {
        const tb = tileBBLocal(&tp.tile, tp.rotation_y_deg);
        const ta_x0 = tp.pos.x + tb.x_min;
        const ta_x1 = tp.pos.x + tb.x_max;
        const ta_z0 = tp.pos.z + tb.z_min;
        const ta_z1 = tp.pos.z + tb.z_max;
        // Skip tiles whose XZ footprints don't strictly overlap.
        if (na_x0 >= ta_x1 or na_x1 <= ta_x0 or na_z0 >= ta_z1 or na_z1 <= ta_z0) continue;
        // XZ footprints overlap — require a vertical clearance gap between tile bodies.
        const ta_y0 = tp.pos.y;
        const ta_y1 = tp.pos.y + tb.y_max + 0.5;
        if (na_y0 < ta_y1 + clearance and na_y1 > ta_y0 - clearance) return false;
    }
    return true;
}

/// All connectors at `pos` that already have a partner placed.
fn allConnectorsSatisfied(tiles_placed: TilesPlaced, new_tp: TilePlaced) bool {
    // Every connector on new_tp that faces TOWARD an existing tile must match exactly.
    for (new_tp.tile.connectors.items) |c| {
        const wpos = worldConnectorPos(new_tp, c);
        const wnorm = worldConnectorNormal(new_tp, c);
        // Is there a placed tile that has a connector at this world position?
        for (tiles_placed.items) |other| {
            for (other.tile.connectors.items) |oc| {
                const owpos = worldConnectorPos(other, oc);
                if (!posClose(wpos, owpos)) continue;
                // There IS a connector here. It must match.
                const ownorm = worldConnectorNormal(other, oc);
                if (!normalsOpposite(wnorm, ownorm)) return false;
                if (c.socket != oc.socket) return false;
            }
        }
    }
    return true;
}

/// Like canFillConnector but also treats `extra_pos` as an occupied position.
fn canFillConnectorWith(tiles: Tiles, tiles_placed: TilesPlaced, extra_pos: rl.Vector3, oc: OpenConnector, bounds_pos: rl.Vector3, bounds_width: f32, bounds_height: f32, bounds_length: f32) bool {
    const rotations = [_]f32{ 0, 90, 180, 270 };
    for (tiles.items, 0..) |_, ti| {
        const candidate_ptr = &tiles.items[ti];
        if (std.mem.startsWith(u8, &candidate_ptr.name, "start") or
            std.mem.startsWith(u8, &candidate_ptr.name, "end")) continue;
        for (rotations) |rot| {
            const maybe_pos = findMatchingPlacement(candidate_ptr, oc, rot);
            if (maybe_pos == null) continue;
            const cpos = maybe_pos.?;
            if (!withinBounds(cpos, rot, candidate_ptr, bounds_pos, bounds_width, bounds_height, bounds_length)) continue;
            if (alreadyOccupied(tiles_placed, cpos)) continue;
            if (posClose(cpos, extra_pos)) continue;
            if (overlapsAnyTile(tiles_placed, cpos, candidate_ptr, rot)) continue;
            if (!hasVerticalClearance(tiles_placed, cpos, candidate_ptr, rot)) continue;
            const new_tp = TilePlaced{ .tile = candidate_ptr.*, .pos = cpos, .rotation_y_deg = rot };
            if (!allConnectorsSatisfied(tiles_placed, new_tp)) continue;
            return true;
        }
    }
    return false;
}

/// After placing `new_tp`, check that every newly-opened connector on it can still be filled.
fn forwardCheck(tiles: Tiles, tiles_placed: TilesPlaced, new_tp: TilePlaced, bounds_pos: rl.Vector3, bounds_width: f32, bounds_height: f32, bounds_length: f32) bool {
    for (new_tp.tile.connectors.items) |c| {
        const wpos = worldConnectorPos(new_tp, c);
        const wnorm = worldConnectorNormal(new_tp, c);
        // Already matched by an existing placed tile?
        var matched = false;
        for (tiles_placed.items) |other| {
            for (other.tile.connectors.items) |oc| {
                if (posClose(wpos, worldConnectorPos(other, oc)) and
                    normalsOpposite(wnorm, worldConnectorNormal(other, oc)))
                {
                    matched = true;
                    break;
                }
            }
            if (matched) break;
        }
        if (matched) continue;
        // This connector will be open — verify it can be filled.
        const open_c = OpenConnector{ .pos = wpos, .normal = wnorm, .socket = c.socket };
        if (!canFillConnectorWith(tiles, tiles_placed, new_tp.pos, open_c, bounds_pos, bounds_width, bounds_height, bounds_length)) {
            return false;
        }
    }
    return true;
}

fn buildTrack(
    tiles: Tiles,
    tiles_placed: *TilesPlaced,
    stack: []Decision,
    stack_depth: *usize,
    bounds_pos: rl.Vector3,
    bounds_width: f32,
    bounds_height: f32,
    bounds_length: f32,
) !bool {
    const allocator = std.heap.c_allocator;
    var open = try collectOpenConnectors(tiles_placed.*, allocator);
    defer open.deinit(allocator);

    if (open.items.len == 0) return false; // done

    var prng = std.Random.DefaultPrng.init(@as(u64, @intFromFloat(rl.getTime() * 1000.0)) ^ stack_depth.*);
    const rand = prng.random();

    // Shuffle open connectors for variety.
    for (0..open.items.len) |i| {
        const j = rand.intRangeLessThan(usize, 0, open.items.len);
        const tmp = open.items[i];
        open.items[i] = open.items[j];
        open.items[j] = tmp;
    }

    const rotations = [_]f32{ 0, 90, 180, 270 };

    // Find an open connector to fill using MRV (Minimum Remaining Values):
    // pick the connector with the FEWEST valid candidates. This prevents one side
    // of the track from monopolising growth while the other side quietly runs out
    // of options and causes a cascade of backtracks.
    // If ANY open connector has zero candidates, the current placement is a dead end.
    var chosen_conn: ?OpenConnector = null;
    var chosen_candidates: [64]CandidateEntry = undefined;
    var n_chosen: usize = std.math.maxInt(usize);
    var need_backtrack = false;

    for (open.items) |oc| {
        var cands: [64]CandidateEntry = undefined;
        var n_cands: usize = 0;

        for (tiles.items, 0..) |_, ti| {
            const candidate_ptr = &tiles.items[ti];
            if (std.mem.startsWith(u8, &candidate_ptr.name, "start") or
                std.mem.startsWith(u8, &candidate_ptr.name, "end")) continue;
            for (rotations) |rot| {
                const maybe_pos = findMatchingPlacement(candidate_ptr, oc, rot);
                if (maybe_pos == null) continue;
                const cpos = maybe_pos.?;
                if (!withinBounds(cpos, rot, candidate_ptr, bounds_pos, bounds_width, bounds_height, bounds_length)) continue;
                if (alreadyOccupied(tiles_placed.*, cpos)) continue;
                if (overlapsAnyTile(tiles_placed.*, cpos, candidate_ptr, rot)) continue;
                if (!hasVerticalClearance(tiles_placed.*, cpos, candidate_ptr, rot)) continue;
                const new_tp = TilePlaced{ .tile = candidate_ptr.*, .pos = cpos, .rotation_y_deg = rot };
                if (!allConnectorsSatisfied(tiles_placed.*, new_tp)) continue;
                if (!forwardCheck(tiles, tiles_placed.*, new_tp, bounds_pos, bounds_width, bounds_height, bounds_length)) continue;
                if (n_cands < cands.len) {
                    cands[n_cands] = .{ .tile_idx = ti, .rot = rot, .pos = cpos };
                    n_cands += 1;
                }
            }
        }

        if (n_cands == 0) {
            need_backtrack = true;
            break;
        }

        // MRV: prefer the connector with the fewest valid candidates.
        if (n_cands < n_chosen) {
            chosen_conn = oc;
            chosen_candidates = cands;
            n_chosen = n_cands;
        }
    }

    if (need_backtrack) {
        // Walk back up the decision stack looking for an untried alternative.
        while (stack_depth.* > 0) {
            const sd = stack_depth.* - 1;
            const frame = &stack[sd];
            const next_idx = frame.chosen_idx + 1;
            if (next_idx < frame.n_candidates) {
                // Restore tiles to the state before this decision and try next candidate.
                tiles_placed.items = tiles_placed.items[0..frame.tiles_placed_len_before];
                frame.chosen_idx = next_idx;
                const c = frame.candidates[next_idx];
                try tiles_placed.append(allocator, .{
                    .tile = tiles.items[c.tile_idx],
                    .pos = c.pos,
                    .rotation_y_deg = c.rot,
                });
                return true;
            } else {
                // No alternatives at this level; pop the frame and go deeper.
                tiles_placed.items = tiles_placed.items[0..frame.tiles_placed_len_before];
                stack_depth.* = sd;
            }
        }
        // Stack exhausted — generation failed for these fixed anchor tiles.
        return error.GenerationFailed;
    }

    // Shuffle candidates for randomness, push a decision frame, place the first candidate.
    for (0..n_chosen) |i| {
        const j = rand.intRangeLessThan(usize, 0, n_chosen);
        const tmp = chosen_candidates[i];
        chosen_candidates[i] = chosen_candidates[j];
        chosen_candidates[j] = tmp;
    }

    const c = chosen_candidates[0];
    if (stack_depth.* < stack.len) {
        stack[stack_depth.*] = .{
            .candidates = chosen_candidates,
            .n_candidates = n_chosen,
            .chosen_idx = 0,
            .tiles_placed_len_before = tiles_placed.items.len,
        };
        stack_depth.* += 1;
    }
    try tiles_placed.append(allocator, .{
        .tile = tiles.items[c.tile_idx],
        .pos = c.pos,
        .rotation_y_deg = c.rot,
    });
    return true;
}

/// Returns true if at least one tile can be placed to fill the given open connector.
fn canFillConnector(tiles: Tiles, tiles_placed: TilesPlaced, oc: OpenConnector, bounds_pos: rl.Vector3, bounds_width: f32, bounds_height: f32, bounds_length: f32) bool {
    const rotations = [_]f32{ 0, 90, 180, 270 };
    for (tiles.items, 0..) |_, ti| {
        const candidate_ptr = &tiles.items[ti];
        if (std.mem.startsWith(u8, &candidate_ptr.name, "start") or
            std.mem.startsWith(u8, &candidate_ptr.name, "end")) continue;
        for (rotations) |rot| {
            const maybe_pos = findMatchingPlacement(candidate_ptr, oc, rot);
            if (maybe_pos == null) continue;
            const cpos = maybe_pos.?;
            if (!withinBounds(cpos, rot, candidate_ptr, bounds_pos, bounds_width, bounds_height, bounds_length)) continue;
            if (alreadyOccupied(tiles_placed, cpos)) continue;
            if (overlapsAnyTile(tiles_placed, cpos, candidate_ptr, rot)) continue;
            if (!hasVerticalClearance(tiles_placed, cpos, candidate_ptr, rot)) continue;
            const new_tp = TilePlaced{ .tile = candidate_ptr.*, .pos = cpos, .rotation_y_deg = rot };
            if (!allConnectorsSatisfied(tiles_placed, new_tp)) continue;
            return true;
        }
    }
    return false;
}

fn drawTrack(tiles: Tiles, tiles_placed: TilesPlaced, lighting: Lighting, bounds_pos: rl.Vector3, bounds_width: f32, bounds_height: f32, bounds_length: f32) void {
    const S = struct {
        var yaw: f32 = 0.0; // horizontal angle (radians)
        var pitch: f32 = 0.3; // vertical angle (radians, clamped)
        var radius: f32 = 15.0; // distance from target
        var prev_two_touch_mid_y: f32 = -1.0; // previous two-finger midpoint Y (-1 = inactive)
    };

    const touch_count = rl.getTouchPointCount();

    if (touch_count == 1) {
        // Single touch — rotate
        const delta = rl.getMouseDelta();
        S.yaw -= delta.x * 0.005;
        S.pitch -= delta.y * 0.005;
        S.pitch = std.math.clamp(S.pitch, -1.4, 1.4);
        S.prev_two_touch_mid_y = -1.0;
    } else if (touch_count >= 2) {
        // Two fingers moving up/down together — zoom
        const p0 = rl.getTouchPosition(0);
        const p1 = rl.getTouchPosition(1);
        const mid_y = (p0.y + p1.y) * 0.5;
        if (S.prev_two_touch_mid_y >= 0.0) {
            // moving fingers up (decreasing Y) → zoom in (decrease radius)
            S.radius += (mid_y - S.prev_two_touch_mid_y) * 0.02;
            S.radius = std.math.clamp(S.radius, 3.0, 50.0);
        }
        S.prev_two_touch_mid_y = mid_y;
    } else {
        S.prev_two_touch_mid_y = -1.0;
        // Mouse drag to rotate
        if (rl.isMouseButtonDown(.left)) {
            const delta = rl.getMouseDelta();
            S.yaw -= delta.x * 0.005;
            S.pitch -= delta.y * 0.005;
            S.pitch = std.math.clamp(S.pitch, -1.4, 1.4);
        }
        // Scroll wheel to zoom
        const scroll = rl.getMouseWheelMove();
        S.radius -= scroll * 0.8;
        S.radius = std.math.clamp(S.radius, 3.0, 50.0);
    }

    const cam_target = rl.Vector3{ .x = bounds_pos.x, .y = bounds_pos.y, .z = bounds_pos.z };
    const camera_pos = rl.Vector3{
        .x = cam_target.x + S.radius * std.math.cos(S.pitch) * std.math.cos(S.yaw),
        .y = cam_target.y + S.radius * std.math.sin(S.pitch),
        .z = cam_target.z + S.radius * std.math.cos(S.pitch) * std.math.sin(S.yaw),
    };
    const camera = rl.Camera{
        .position = camera_pos,
        .target = cam_target,
        .up = rl.Vector3{ .x = 0, .y = 1, .z = 0 },
        .fovy = 45,
        .projection = rl.CameraProjection.perspective,
    };
    rl.beginMode3D(camera);

    // update lighting uniforms
    const view_pos = [3]f32{ camera_pos.x, camera_pos.y, camera_pos.z };
    rl.setShaderValue(lighting.shader, lighting.loc_view_pos, &view_pos, .vec3);
    // 4 point lights at the top corners of the bounding box
    const offset = 5.0; // offset from box edges
    const light_height = 5.0; // height of lights above box center
    const hw = bounds_width / 2.0;
    const hh = bounds_height / 2.0;
    const hl = bounds_length / 2.0;
    const ly = bounds_pos.y + hh + light_height;
    const light_positions = [15]f32{
        bounds_pos.x - hw - offset, ly, bounds_pos.z - hl - offset,
        bounds_pos.x + hw + offset, ly, bounds_pos.z - hl - offset,
        bounds_pos.x - hw - offset, ly, bounds_pos.z + hl + offset,
        bounds_pos.x + hw + offset, ly, bounds_pos.z + hl + offset,
        bounds_pos.x, ly, bounds_pos.z, // center light
    };
    rl.setShaderValueV(lighting.shader, lighting.loc_light_positions, &light_positions, .vec3, 5);
    const light_colors = [15]f32{
        1.0, 0.95, 0.8,
        1.0, 0.95, 0.8,
        1.0, 0.95, 0.8,
        1.0, 0.95, 0.8,
        0.8, 0.8, 1.0, // bluish center light
    };
    rl.setShaderValueV(lighting.shader, lighting.loc_light_colors, &light_colors, .vec3, 4);
    const ambient = [4]f32{ 0.4, 0.4, 0.4, 1.0 };
    rl.setShaderValue(lighting.shader, lighting.loc_ambient, &ambient, .vec4);

    rl.drawGrid(20, 1.0);
    rl.drawCubeWires(bounds_pos, bounds_width, bounds_height, bounds_length, .red);

    // draw tiles
    const rot_axis = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
    const scale = rl.Vector3{ .x = 1, .y = 1, .z = 1 };
    for (tiles_placed.items) |*tp| {
        rl.drawModelEx(tp.tile.model, tp.pos, rot_axis, tp.rotation_y_deg, scale, .white);
        //rl.drawModelWiresEx(tp.tile.model, tp.pos, rot_axis, tp.rotation_y_deg, scale, rl.Color{ .r = 60, .g = 40, .b = 20, .a = 120 });
    }

    // draw dead-end open connectors as red spheres
    var open = collectOpenConnectors(tiles_placed, std.heap.c_allocator) catch null;
    if (open) |*o| {
        defer o.deinit(std.heap.c_allocator);
        for (o.items) |oc| {
            if (!canFillConnector(tiles, tiles_placed, oc, bounds_pos, bounds_width, bounds_height, bounds_length)) {
                rl.drawSphere(oc.pos, 0.15, .red);
            }
        }
    }

    rl.endMode3D();
}

pub fn marble(io: std.Io) bool {
    const S = struct {
        var tiles: ?Tiles = null;
        var tiles_placed: ?TilesPlaced = null;
        var lighting: ?Lighting = null;
        var err: ?[:0]const u8 = null;
        var initialized: bool = false;
        var stack: [MAX_DECISIONS]Decision = undefined;
        var stack_depth: usize = 0;
        var track_done: bool = false;
        var track_failed: bool = false;
    };
    // bounds for track generation and display
    const bounds_pos = rl.Vector3{ .x = 0, .y = 3, .z = 0 };
    const bounds_width = 16.0;
    const bounds_height = 8.0;
    const bounds_length = 16.0;
    // init
    if (!S.initialized) {
        S.lighting = initLighting() catch |err| {
            std.debug.print("Failed to init lighting: {}\n", .{err});
            S.err = @errorName(err);
            return false;
        };
        S.tiles = loadTiles(io, std.heap.c_allocator) catch |err| {
            std.debug.print("Failed to load models: {}\n", .{err});
            S.err = @errorName(err);
            return false;
        };
        if (S.tiles) |tiles| {
            // apply lighting shader to all tile models
            if (S.lighting) |lt| {
                for (tiles.items) |*tile| {
                    applyShaderToModel(&tile.model, lt.shader);
                }
            }
            // create track
            S.tiles_placed = initTrack(tiles, bounds_pos, bounds_width, bounds_height, bounds_length) catch |err| {
                std.debug.print("Failed to create track: {}\n", .{err});
                S.err = @errorName(err);
                return false;
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
    // iterate track — one step per frame until done or failed
    if (!S.track_done and !S.track_failed) {
        if (S.tiles) |tiles| {
            if (S.tiles_placed) |*tiles_placed| {
                const placed = buildTrack(tiles, tiles_placed, &S.stack, &S.stack_depth, bounds_pos, bounds_width, bounds_height, bounds_length) catch |err| blk: {
                    if (err == error.GenerationFailed) {
                        S.track_failed = true;
                        break :blk false;
                    }
                    std.debug.print("buildTrack error: {}\n", .{err});
                    S.err = @errorName(err);
                    break :blk false;
                };
                if (!placed) S.track_done = true;
            }
        }
    }
    // draw
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(ut.getBackgroundColor());
    if (S.tiles_placed) |tiles_placed| {
        if (S.lighting) |lt| {
            if (S.tiles) |tiles| {
                drawTrack(tiles, tiles_placed, lt, bounds_pos, bounds_width, bounds_height, bounds_length);
            }
        } else {
            ut.drawTextCentered("Lighting failed to initialize", 20, .red);
        }
    } else {
        ut.drawTextCentered("No tiles to display", 20, .light_gray);
    }
    if (S.track_failed) {
        const msg: [:0]const u8 = "Stuck - press Reset";
        const msg_width = rl.measureText(msg, 16);
        rl.drawText(msg, @divTrunc(rl.getRenderWidth() - msg_width, 2), rl.getRenderHeight() - 34, 16, .orange);
    }
    // back button
    if (ut.backBtn()) {
        return true;
    }
    // reset button
    const reset_x = ut.button_spacing * 2 + ut.button_height;
    if (ut.btn(reset_x, ut.button_spacing, 60, ut.button_height, "Reset")) {
        if (S.tiles_placed) |*old| {
            old.deinit(std.heap.c_allocator);
            S.tiles_placed = null;
        }
        S.stack_depth = 0;
        S.track_done = false;
        S.track_failed = false;
        if (S.tiles) |tiles| {
            S.tiles_placed = initTrack(tiles, bounds_pos, bounds_width, bounds_height, bounds_length) catch |err| blk: {
                std.debug.print("Failed to reset track: {}\n", .{err});
                S.err = @errorName(err);
                break :blk null;
            };
        }
    }
    return false;
}
