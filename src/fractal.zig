const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const ut = @import("utils.zig");

fn interationsSlider(iterations: *usize, max: f32) void {
    // iterations slider
    const bounds = rl.Rectangle{ .x = ut.button_spacing, .y = ut.button_spacing * 2 + ut.button_height, .width = 100, .height = 15 };
    var iterations_f32: f32 = @floatFromInt(iterations.*);
    _ = rg.slider(bounds, null, "Iterations", &iterations_f32, 1, max);
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
    interationsSlider(&S.iterations, 7);
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
    interationsSlider(&S.iterations, 10);
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

fn tree(origin_x: f32, origin_y: f32, size: f32) void {
    const S = struct {
        var iterations: usize = 7;
        var angle: f32 = std.math.pi / 6.0;
    };
    const color: rl.Color = .light_gray;
    const p1 = rl.Vector2{ .x = origin_x + size / 2, .y = origin_y + size };
    const p2 = rl.Vector2{ .x = origin_x + size / 2, .y = origin_y + 2 * size / 3 };
    treeBranch(p1, p2, color, S.iterations, S.angle);
    // iterations slider
    interationsSlider(&S.iterations, 10);
    // angle slider
    const x = ut.button_spacing;
    const y = ut.button_spacing + ut.button_height + ut.button_spacing + 15 + 15;
    const bounds2 = rl.Rectangle{ .x = x, .y = y, .width = 100, .height = 15 };
    _ = rg.slider(bounds2, null, "Angle", &S.angle, 0, std.math.pi / 2.0);
}

fn addQuad(
    vertices: [*c]f32,
    normals: [*c]f32,
    texcoords: [*c]f32,
    vi: *usize,
    v0: [3]f32,
    v1: [3]f32,
    v2: [3]f32,
    v3: [3]f32,
    n: [3]f32,
) void {
    for ([6][3]f32{ v0, v1, v2, v0, v2, v3 }) |v| {
        const idx3 = vi.* * 3;
        vertices[idx3] = v[0];
        vertices[idx3 + 1] = v[1];
        vertices[idx3 + 2] = v[2];
        normals[idx3] = n[0];
        normals[idx3 + 1] = n[1];
        normals[idx3 + 2] = n[2];
        const idx2 = vi.* * 2;
        texcoords[idx2] = 0;
        texcoords[idx2 + 1] = 0;
        vi.* += 1;
    }
}

fn fillMengerMesh(vertices: [*c]f32, normals: [*c]f32, texcoords: [*c]f32, vi: *usize, pos: rl.Vector3, size: rl.Vector3, iterations: usize) void {
    if (iterations == 0) {
        const x0 = pos.x;
        const x1 = pos.x + size.x;
        const y0 = pos.y;
        const y1 = pos.y + size.y;
        const z0 = pos.z;
        const z1 = pos.z + size.z;
        // 6 faces with outward normals, CCW winding from outside
        addQuad(vertices, normals, texcoords, vi, .{ x0, y1, z0 }, .{ x0, y1, z1 }, .{ x1, y1, z1 }, .{ x1, y1, z0 }, .{ 0, 1, 0 }); // top
        addQuad(vertices, normals, texcoords, vi, .{ x0, y0, z0 }, .{ x1, y0, z0 }, .{ x1, y0, z1 }, .{ x0, y0, z1 }, .{ 0, -1, 0 }); // bottom
        addQuad(vertices, normals, texcoords, vi, .{ x0, y0, z0 }, .{ x0, y1, z0 }, .{ x1, y1, z0 }, .{ x1, y0, z0 }, .{ 0, 0, -1 }); // front
        addQuad(vertices, normals, texcoords, vi, .{ x1, y0, z1 }, .{ x1, y1, z1 }, .{ x0, y1, z1 }, .{ x0, y0, z1 }, .{ 0, 0, 1 }); // back
        addQuad(vertices, normals, texcoords, vi, .{ x0, y0, z1 }, .{ x0, y1, z1 }, .{ x0, y1, z0 }, .{ x0, y0, z0 }, .{ -1, 0, 0 }); // left
        addQuad(vertices, normals, texcoords, vi, .{ x1, y0, z0 }, .{ x1, y1, z0 }, .{ x1, y1, z1 }, .{ x1, y0, z1 }, .{ 1, 0, 0 }); // right
    } else {
        const new_size = rl.Vector3{ .x = size.x / 3.0, .y = size.y / 3.0, .z = size.z / 3.0 };
        for (0..3) |ix| {
            for (0..3) |iy| {
                for (0..3) |iz| {
                    if ((ix == 1 and iy == 1) or (ix == 1 and iz == 1) or (iy == 1 and iz == 1)) continue;
                    const fx: f32 = @floatFromInt(ix);
                    const fy: f32 = @floatFromInt(iy);
                    const fz: f32 = @floatFromInt(iz);
                    const new_pos = rl.Vector3{
                        .x = pos.x + fx * new_size.x,
                        .y = pos.y + fy * new_size.y,
                        .z = pos.z + fz * new_size.z,
                    };
                    fillMengerMesh(vertices, normals, texcoords, vi, new_pos, new_size, iterations - 1);
                }
            }
        }
    }
}

fn mengerSpongeMesh(pos: rl.Vector3, size: rl.Vector3, iterations: usize) ?rl.Mesh {
    // 20^iterations leaf cubes, each contributing 6 faces × 6 vertices = 36 verts
    var cube_count: usize = 1;
    for (0..iterations) |_| cube_count *= 20;
    const vertex_count = cube_count * 36;
    const triangle_count = cube_count * 12;
    var mesh = rl.Mesh{
        .triangleCount = @intCast(triangle_count),
        .vertexCount = @intCast(vertex_count),
        .vertices = @as([*c]f32, @ptrCast(@alignCast(rl.memAlloc(@intCast(vertex_count * 3 * @sizeOf(f32)))))),
        .texcoords = @as([*c]f32, @ptrCast(@alignCast(rl.memAlloc(@intCast(vertex_count * 2 * @sizeOf(f32)))))),
        .normals = @as([*c]f32, @ptrCast(@alignCast(rl.memAlloc(@intCast(vertex_count * 3 * @sizeOf(f32)))))),
        .texcoords2 = null,
        .tangents = null,
        .colors = null,
        .indices = null,
        .boneCount = 0,
        .boneIndices = null,
        .boneWeights = null,
        .animVertices = null,
        .animNormals = null,
        .vaoId = 0,
        .vboId = 0,
    };

    if (mesh.vertices == null or mesh.texcoords == null or mesh.normals == null) {
        rl.unloadMesh(mesh);
        return null;
    }

    var vi: usize = 0;
    fillMengerMesh(mesh.vertices, mesh.normals, mesh.texcoords, &vi, pos, size, iterations);

    rl.uploadMesh(&mesh, false);
    return mesh;
}

const builtin = @import("builtin");
const is_web = builtin.target.os.tag == .emscripten;

const menger_vs = if (is_web)
    \\#version 100
    \\precision mediump float;
    \\attribute vec3 vertexPosition;
    \\attribute vec2 vertexTexCoord;
    \\attribute vec3 vertexNormal;
    \\attribute vec4 vertexColor;
    \\uniform mat4 mvp;
    \\uniform mat4 matNormal;
    \\varying vec3 fragNormal;
    \\varying vec4 fragColor;
    \\varying vec2 fragTexCoord;
    \\void main() {
    \\    fragNormal = normalize(vec3(matNormal * vec4(vertexNormal, 0.0)));
    \\    fragColor = vertexColor;
    \\    fragTexCoord = vertexTexCoord;
    \\    gl_Position = mvp * vec4(vertexPosition, 1.0);
    \\}
else
    \\#version 330
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec3 vertexNormal;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\uniform mat4 matNormal;
    \\out vec3 fragNormal;
    \\out vec4 fragColor;
    \\out vec2 fragTexCoord;
    \\void main() {
    \\    fragNormal = normalize(vec3(matNormal * vec4(vertexNormal, 0.0)));
    \\    fragColor = vertexColor;
    \\    fragTexCoord = vertexTexCoord;
    \\    gl_Position = mvp * vec4(vertexPosition, 1.0);
    \\}
;

const menger_fs = if (is_web)
    \\#version 100
    \\precision mediump float;
    \\varying vec3 fragNormal;
    \\varying vec4 fragColor;
    \\varying vec2 fragTexCoord;
    \\uniform sampler2D texture0;
    \\uniform vec4 colDiffuse;
    \\uniform vec3 lightDir;
    \\uniform float ambient;
    \\void main() {
    \\    vec4 texelColor = texture2D(texture0, fragTexCoord);
    \\    vec4 base = texelColor * colDiffuse * fragColor;
    \\    float diff = max(dot(fragNormal, normalize(lightDir)), 0.0);
    \\    float factor = ambient + (1.0 - ambient) * diff;
    \\    gl_FragColor = vec4(base.rgb * factor, base.a);
    \\}
else
    \\#version 330
    \\in vec3 fragNormal;
    \\in vec4 fragColor;
    \\in vec2 fragTexCoord;
    \\uniform sampler2D texture0;
    \\uniform vec4 colDiffuse;
    \\uniform vec3 lightDir;
    \\uniform float ambient;
    \\out vec4 finalColor;
    \\void main() {
    \\    vec4 texelColor = texture(texture0, fragTexCoord);
    \\    vec4 base = texelColor * colDiffuse * fragColor;
    \\    float diff = max(dot(fragNormal, normalize(lightDir)), 0.0);
    \\    float factor = ambient + (1.0 - ambient) * diff;
    \\    finalColor = vec4(base.rgb * factor, base.a);
    \\}
;

fn mengerSponge(_: f32, _: f32, _: f32) void {
    const S = struct {
        var iterations: usize = 2;
        var angle: f32 = 0;
        var angle_inc: f32 = 0.01;
        var mesh: ?rl.Mesh = null;
        var mesh_iterations: usize = 0;
        var model: ?rl.Model = null;
        var shader: ?rl.Shader = null;
        var err: ?[:0]const u8 = null;
    };
    // calc mesh
    if (S.model == null or S.mesh_iterations != S.iterations) {
        if (S.model) |m| {
            rl.unloadModel(m); // also frees material shader via UnloadMaterial
            S.model = null;
            S.shader = null;
        }
        if (S.mesh) |m| {
            rl.unloadMesh(m);
            S.mesh = null;
        }
        const pos = rl.Vector3{ .x = 0, .y = 0, .z = 0 };
        const size = rl.Vector3{ .x = 9, .y = 9, .z = 9 };
        S.mesh = mengerSpongeMesh(pos, size, S.iterations);
        S.mesh_iterations = S.iterations;
        if (S.mesh) |m| {
            S.model = rl.loadModelFromMesh(m) catch |err| blk: {
                S.err = @errorName(err);
                break :blk @as(?rl.Model, null);
            };
            if (S.model != null) {
                // The model owns the mesh's CPU and GPU data now; don't free separately.
                S.mesh = null;
                // Load a simple directional-light shader and assign it to the model material.
                // unloadModel will free it via UnloadMaterial, so we recreate on each model build.
                S.shader = rl.loadShaderFromMemory(menger_vs, menger_fs) catch null;
                if (S.shader) |sh| {
                    const light_dir = [3]f32{ 1.0, 2.0, 0.5 };
                    const ambient: f32 = 0.25;
                    rl.setShaderValue(sh, rl.getShaderLocation(sh, "lightDir"), &light_dir, .vec3);
                    rl.setShaderValue(sh, rl.getShaderLocation(sh, "ambient"), &ambient, .float);
                    S.model.?.materials[0].shader = sh;
                }
            }
        }
    }
    // show errors
    if (S.err) |e| {
        ut.drawTextCentered(e, 20, .red);
        return;
    }
    // setup camera and draw cube
    const camera = rl.Camera3D{
        .position = (rl.Vector3{ .x = 15, .y = 10, .z = 15 }).rotateByAxisAngle(rl.Vector3{ .x = 0, .y = 1, .z = 0 }, S.angle),
        .target = rl.Vector3{ .x = 0, .y = 0, .z = 0 },
        .up = rl.Vector3{ .x = 0, .y = 1, .z = 0 },
        .fovy = 45,
        .projection = rl.CameraProjection.perspective,
    };
    rl.beginMode3D(camera);
    const pos = rl.Vector3{ .x = -4.5, .y = -4.5, .z = -4.5 };
    rl.drawModel(S.model.?, pos, 1.0, .light_gray);
    //rl.drawModelWires(S.model.?, pos, 1.0, .dark_gray);
    rl.endMode3D();
    // increment angle
    S.angle += S.angle_inc;
    // iterations slider
    interationsSlider(&S.iterations, 5);
    // rotation speed slider
    const x = ut.button_spacing;
    const y = ut.button_spacing + ut.button_height + ut.button_spacing + 15 + 15;
    const bounds2 = rl.Rectangle{ .x = x, .y = y, .width = 100, .height = 15 };
    _ = rg.slider(bounds2, null, "Speed", &S.angle_inc, 0.01, 0.1);
}

const Fractal = enum(i32) { kockSnowflake, sierpinskiTriangle, tree, mengerSponge };

fn fractalSelectBtns(fractalType: *Fractal, edit_mode: *bool) void {
    const offset_x = ut.button_spacing + ut.button_height + ut.button_spacing;
    const offset_y = ut.button_spacing;
    const r = rl.Rectangle{ .x = offset_x, .y = offset_y, .width = 130, .height = ut.button_height };
    var active = @intFromEnum(fractalType.*);
    if (rg.dropdownBox(r, "Kock Snowflake;Sierpinski Triangle;Tree;Menger Sponge", &active, edit_mode.*) != 0) {
        edit_mode.* = !edit_mode.*;
    }
    fractalType.* = @enumFromInt(active);
}

pub fn fractal(_: std.Io) bool {
    const S = struct {
        var fractal: Fractal = .kockSnowflake;
        var dropdown_edit: bool = false;
    };
    // get largest square that fits within the window
    const size: f32 = @floatFromInt(@min(rl.getRenderWidth(), rl.getRenderHeight()) - 50);
    const origin_x: f32 = (@as(f32, @floatFromInt(rl.getRenderWidth())) - size) / 2;
    const origin_y: f32 = (@as(f32, @floatFromInt(rl.getRenderHeight())) - size) / 2;
    // draw background
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(ut.getBackgroundColor());
    // draw debug square
    //rl.drawRectangleRec(rl.Rectangle{ .x = origin_x, .y = origin_y, .width = size, .height = size }, .yellow);
    switch (S.fractal) {
        .kockSnowflake => kockSnowflake(origin_x, origin_y, size),
        .sierpinskiTriangle => sierpinskiTriangle(origin_x, origin_y, size),
        .tree => tree(origin_x, origin_y, size),
        .mengerSponge => mengerSponge(origin_x, origin_y, size),
    }
    // draw back button
    if (ut.backBtn()) {
        return true;
    }
    // draw fractal selection buttons (drawn last for correct dropdown z-order)
    fractalSelectBtns(&S.fractal, &S.dropdown_edit);

    return false;
}
