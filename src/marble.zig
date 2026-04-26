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
    \\    vec3 norm = normalize(fragNormal);
    \\    vec3 viewDir = normalize(viewPos - fragPos);
    \\    vec3 lighting = ambient.rgb * ambient.a;
    \\    for (int i = 0; i < NUM_LIGHTS; i++) {
    \\        vec3 lightDir = normalize(lightPositions[i] - fragPos);
    \\        float diff = max(dot(norm, lightDir), 0.0);
    \\        vec3 halfDir = normalize(lightDir + viewDir);
    \\        float spec = pow(max(dot(norm, halfDir), 0.0), 32.0);
    \\        float dist = length(lightPositions[i] - fragPos);
    \\        float atten = 1.0 / (1.0 + 0.08 * dist);
    \\        lighting += (diff * lightColors[i] + spec * vec3(0.3)) * atten;
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
    \\    vec3 norm = normalize(fragNormal);
    \\    vec3 viewDir = normalize(viewPos - fragPos);
    \\    vec3 lighting = ambient.rgb * ambient.a;
    \\    for (int i = 0; i < NUM_LIGHTS; i++) {
    \\        vec3 lightDir = normalize(lightPositions[i] - fragPos);
    \\        float diff = max(dot(norm, lightDir), 0.0);
    \\        vec3 halfDir = normalize(lightDir + viewDir);
    \\        float spec = pow(max(dot(norm, halfDir), 0.0), 32.0);
    \\        float dist = length(lightPositions[i] - fragPos);
    \\        float atten = 1.0 / (1.0 + 0.08 * dist);
    \\        lighting += (diff * lightColors[i] + spec * vec3(0.3)) * atten;
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

fn createTrack(tiles: Tiles, bounds_pos: rl.Vector3, bounds_width: f32, bounds_height: f32, bounds_length: f32) !TilesPlaced {
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

fn drawTrack(tiles_placed: TilesPlaced, lighting: Lighting, bounds_pos: rl.Vector3, bounds_width: f32, bounds_height: f32, bounds_length: f32) void {
    const S = struct {
        var angle: f32 = 0;
    };
    S.angle += 0.005;
    const camera_pos = rl.Vector3{
        .x = 15 * std.math.cos(S.angle),
        .y = 5,
        .z = 15 * std.math.sin(S.angle),
    };
    const camera = rl.Camera{
        .position = camera_pos,
        .target = rl.Vector3{ .x = -0.5, .y = 1, .z = 0 },
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
        //rl.drawModelWiresEx(tp.tile.model, tp.pos, rot_axis, tp.rotation_y_deg, scale, .light_gray);
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
    };
    // bounds for track generation and display
    const bounds_pos = rl.Vector3{ .x = 0, .y = 3, .z = 0 };
    const bounds_width = 10.0;
    const bounds_height = 6.0;
    const bounds_length = 10.0;
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
            S.tiles_placed = createTrack(tiles, bounds_pos, bounds_width, bounds_height, bounds_length) catch |err| {
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
    // draw
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(ut.getBackgroundColor());
    if (S.tiles_placed) |tiles_placed| {
        if (S.lighting) |lt| {
            drawTrack(tiles_placed, lt, bounds_pos, bounds_width, bounds_height, bounds_length);
        } else {
            ut.drawTextCentered("Lighting failed to initialize", 20, .red);
        }
    } else {
        ut.drawTextCentered("No tiles to display", 20, .light_gray);
    }
    // back button
    if (ut.backBtn()) {
        return true;
    }
    return false;
}
