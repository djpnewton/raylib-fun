//! Minimal sphere-on-mesh physics for the marble demo.
//!
//! Assumptions:
//!   * One dynamic body: a sphere of fixed `radius`.
//!   * All static geometry is provided as a flat slice of `Tri` (world-space).
//!   * `step` is called once per rendered frame with the raw frame-time delta.
//!
//! The integrator is semi-implicit Euler with 4 substeps per frame.
//! Collision resolution uses closest-point-on-triangle tests with a single-pass
//! position correction and an impulse-based velocity response (restitution + friction).

const std = @import("std");

// ── tunables ──────────────────────────────────────────────────────────────────

pub const radius: f32 = 0.5;
const gravity: f32 = -12.0; // m/s²
const restitution: f32 = 0.08;
const friction: f32 = 0.02;
const linear_damping: f32 = 0.01; // e-fold decay constant (per second)
const substeps: u32 = 6;

// ── public types ─────────────────────────────────────────────────────────────

pub const State = struct {
    pos: [3]f32,
    vel: [3]f32,

    pub fn init(start_pos: [3]f32) State {
        return .{ .pos = start_pos, .vel = .{ 0, 0, 0 } };
    }
};

/// One world-space triangle.
pub const Tri = struct {
    v: [3][3]f32,
};

// ── public API ────────────────────────────────────────────────────────────────

/// Advance the simulation by `dt` seconds against the provided triangle soup.
pub fn step(state: *State, dt: f32, tris: []const Tri) void {
    const sdt = dt / @as(f32, @floatFromInt(substeps));
    for (0..substeps) |_| substep(state, sdt, tris);
}

// ── internals ────────────────────────────────────────────────────────────────

fn substep(state: *State, dt: f32, tris: []const Tri) void {
    // Gravity + exponential damping applied to velocity.
    state.vel[1] += gravity * dt;
    const d = std.math.exp(-linear_damping * dt);
    for (&state.vel) |*v| v.* *= d;

    // Integrate position.
    for (0..3) |i| state.pos[i] += state.vel[i] * dt;

    // Resolve sphere-triangle penetrations (two passes for stability).
    for (0..2) |_| {
        for (tris) |tri| resolveSphereTri(state, tri);
    }
}

fn resolveSphereTri(state: *State, tri: Tri) void {
    const cp = closestPointOnTri(state.pos, tri.v);

    const d = sub3(state.pos, cp);
    const dist2 = dot3(d, d);
    if (dist2 >= radius * radius or dist2 < 1e-12) return;

    const dist = @sqrt(dist2);
    const n = scale3(d, 1.0 / dist); // unit normal: surface → sphere center

    // Position correction: push sphere out of penetration.
    const pen = radius - dist;
    for (0..3) |i| state.pos[i] += n[i] * pen;

    // Velocity response.
    const vn = dot3(state.vel, n);
    if (vn >= 0.0) return; // already separating

    // Normal impulse (coefficient of restitution).
    const j = -(1.0 + restitution) * vn;
    var vel = state.vel;
    for (0..3) |i| vel[i] += j * n[i];

    // Friction impulse along tangential velocity.
    const vt = sub3(vel, scale3(n, dot3(vel, n)));
    const vt_len = @sqrt(dot3(vt, vt));
    if (vt_len > 1e-6) {
        const fi = @min(friction * j, vt_len);
        for (0..3) |i| vel[i] -= (vt[i] / vt_len) * fi;
    }

    state.vel = vel;
}

/// Closest point on triangle `v` to point `p`.
/// Algorithm: Christer Ericson, "Real-Time Collision Detection" §5.1.5.
fn closestPointOnTri(p: [3]f32, v: [3][3]f32) [3]f32 {
    const a = v[0];
    const b = v[1];
    const c = v[2];

    const ab = sub3(b, a);
    const ac = sub3(c, a);
    const ap = sub3(p, a);

    const d1 = dot3(ab, ap);
    const d2 = dot3(ac, ap);
    if (d1 <= 0.0 and d2 <= 0.0) return a;

    const bp = sub3(p, b);
    const d3 = dot3(ab, bp);
    const d4 = dot3(ac, bp);
    if (d3 >= 0.0 and d4 <= d3) return b;

    const vc = d1 * d4 - d3 * d2;
    if (vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0) {
        const w = d1 / (d1 - d3);
        return add3(a, scale3(ab, w));
    }

    const cp = sub3(p, c);
    const d5 = dot3(ab, cp);
    const d6 = dot3(ac, cp);
    if (d6 >= 0.0 and d5 <= d6) return c;

    const vb = d5 * d2 - d1 * d6;
    if (vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0) {
        const w = d2 / (d2 - d6);
        return add3(a, scale3(ac, w));
    }

    const va = d3 * d6 - d5 * d4;
    if (va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0) {
        const w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
        return add3(b, scale3(sub3(c, b), w));
    }

    const denom = 1.0 / (va + vb + vc);
    const vw = vb * denom;
    const ww = vc * denom;
    return add3(a, add3(scale3(ab, vw), scale3(ac, ww)));
}

// ── Vec3 helpers ─────────────────────────────────────────────────────────────

inline fn add3(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
inline fn sub3(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
inline fn scale3(a: [3]f32, s: f32) [3]f32 {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}
inline fn dot3(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
