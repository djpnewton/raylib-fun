#!/usr/bin/env python3
"""
Marble track tile generator.

Outputs OBJ files for WFC-compatible marble track tiles.
Pass --view to open an interactive 3D preview after generation.

Tile size: 2 x 1 x 2 (x, y, z), centered in X/Z, y from 0 to 1.
Connection faces: the 4 side faces (+X, -X, +Z, -Z).
Each connectable face gets two raised dot markers indicating where tiles join.
"""
import argparse
import json
import math
import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

# tile types
GRAVITY_TRACK = "gravity_track"
GAME_TRACK    = "game_track"

# Connector dot parameters
DOT_RADIUS   = 0.08   # radius of each dot bump
DOT_HEIGHT   = 0.06   # how much the dot is raised above the face surface
DOT_OFFSET   = 0.35   # lateral offset from face center (two dots at ±this)
DISC_SEGMENTS = 12    # polygon resolution for dots

# Wall parameters
WALL_HEIGHT    = 0.7   # wall rises this far above the base top (y=1 to y=1+WALL_HEIGHT)
WALL_THICKNESS = 0.15  # wall depth along the tile footprint


class ObjWriter:
    def __init__(self, name="tile"):
        self.name = name
        self._verts = []
        self._normals = []
        self._faces = []
        self.connectors = []

    def v(self, x, y, z):
        self._verts.append((x, y, z))
        return len(self._verts)   # 1-indexed

    def vn(self, x, y, z):
        mag = math.sqrt(x*x + y*y + z*z)
        if mag > 1e-9:
            x, y, z = x/mag, y/mag, z/mag
        self._normals.append((x, y, z))
        return len(self._normals)  # 1-indexed

    def _face(self, vis, ni):
        self._faces.append("f " + " ".join(f"{vi}//{ni}" for vi in vis))

    def quad(self, v0, v1, v2, v3, nx, ny, nz):
        self._face([v0, v1, v2, v3], self.vn(nx, ny, nz))

    def tri(self, v0, v1, v2, nx, ny, nz):
        self._face([v0, v1, v2], self.vn(nx, ny, nz))

    def write(self, filename):
        path = os.path.join(OUTPUT_DIR, filename)
        with open(path, "w") as f:
            f.write(f"# Marble track tile: {self.name}\n")
            f.write(f"o {self.name}\n")
            for x, y, z in self._verts:
                f.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
            for x, y, z in self._normals:
                f.write(f"vn {x:.6f} {y:.6f} {z:.6f}\n")
            for line in self._faces:
                f.write(line + "\n")
        print(f"Written: {path}")


# ---------------------------------------------------------------------------
# Math helpers
# ---------------------------------------------------------------------------

def cross(a, b):
    return (
        a[1]*b[2] - a[2]*b[1],
        a[2]*b[0] - a[0]*b[2],
        a[0]*b[1] - a[1]*b[0],
    )

def normalize(v):
    x, y, z = v
    mag = math.sqrt(x*x + y*y + z*z)
    return (x/mag, y/mag, z/mag)

def tangent_frame(n):
    """Return (right, up) orthonormal vectors perpendicular to n.

    right = normalize(n × world_up)
    up    = right × n
    """
    world_up = (0, 1, 0) if abs(n[1]) < 0.9 else (1, 0, 0)
    right = normalize(cross(n, world_up))
    up    = cross(right, n)  # already unit length
    return right, up


# ---------------------------------------------------------------------------
# Geometry builders
# ---------------------------------------------------------------------------

def add_box(obj, x0, y0, z0, x1, y1, z1):
    """Add a solid axis-aligned box with outward-facing normals."""
    v = [
        obj.v(x0, y0, z0),  # 0  front-bottom-left
        obj.v(x1, y0, z0),  # 1  front-bottom-right
        obj.v(x1, y1, z0),  # 2  front-top-right
        obj.v(x0, y1, z0),  # 3  front-top-left
        obj.v(x0, y0, z1),  # 4  back-bottom-left
        obj.v(x1, y0, z1),  # 5  back-bottom-right
        obj.v(x1, y1, z1),  # 6  back-top-right
        obj.v(x0, y1, z1),  # 7  back-top-left
    ]
    # Each quad listed CCW from outside (verified by cross product):
    obj.quad(v[0], v[3], v[2], v[1],  0,  0, -1)  # -Z face
    obj.quad(v[4], v[5], v[6], v[7],  0,  0, +1)  # +Z face
    obj.quad(v[0], v[1], v[5], v[4],  0, -1,  0)  # -Y face (bottom)
    obj.quad(v[3], v[7], v[6], v[2],  0, +1,  0)  # +Y face (top)
    obj.quad(v[0], v[4], v[7], v[3], -1,  0,  0)  # -X face
    obj.quad(v[1], v[2], v[6], v[5], +1,  0,  0)  # +X face


def add_dot(obj, cx, cy, cz, n):
    """Add a raised circular connector bump at (cx, cy, cz) on a face with
    outward unit normal n. The bump protrudes DOT_HEIGHT along n."""
    nx, ny, nz = n
    right, up   = tangent_frame(n)
    rx, ry, rz  = right
    ux, uy, uz  = up
    S = DISC_SEGMENTS

    # Front cap centre (raised)
    fx, fy, fz = cx + nx*DOT_HEIGHT, cy + ny*DOT_HEIGHT, cz + nz*DOT_HEIGHT

    front_ring = []
    back_ring  = []
    for i in range(S):
        a = 2 * math.pi * i / S
        ca, sa = math.cos(a), math.sin(a)
        dvx = (ca*rx + sa*ux) * DOT_RADIUS
        dvy = (ca*ry + sa*uy) * DOT_RADIUS
        dvz = (ca*rz + sa*uz) * DOT_RADIUS
        front_ring.append(obj.v(fx+dvx, fy+dvy, fz+dvz))
        back_ring .append(obj.v(cx+dvx, cy+dvy, cz+dvz))

    fc = obj.v(fx, fy, fz)   # front cap centre
    bc = obj.v(cx, cy, cz)   # back cap centre (at face surface)

    # Front cap — CCW from +n: fc, ring[j], ring[i]
    for i in range(S):
        j = (i + 1) % S
        obj.tri(fc, front_ring[j], front_ring[i], nx, ny, nz)

    # Back cap — CCW from -n: bc, ring[i], ring[j]
    for i in range(S):
        j = (i + 1) % S
        obj.tri(bc, back_ring[i], back_ring[j], -nx, -ny, -nz)

    # Side quads — CCW from outside: back[i], front[i], front[j], back[j]
    for i in range(S):
        j = (i + 1) % S
        a_mid = 2 * math.pi * (i + 0.5) / S
        ca, sa = math.cos(a_mid), math.sin(a_mid)
        snx, sny, snz = ca*rx + sa*ux, ca*ry + sa*uy, ca*rz + sa*uz
        obj.quad(back_ring[i], front_ring[i], front_ring[j], back_ring[j],
                 snx, sny, snz)


def add_connectors(obj, face_cx, face_cy, face_cz, n, count=2, socket=None):
    """Place `count` connector dots on a face, evenly spread laterally from the centre."""
    right, _ = tangent_frame(n)
    rx, ry, rz = right
    if count == 1:
        offsets = [0.0]
    else:
        offsets = [DOT_OFFSET * (2*i/(count-1) - 1) for i in range(count)]
    for off in offsets:
        add_dot(
            obj,
            face_cx + off * rx,
            face_cy + off * ry,
            face_cz + off * rz,
            n,
        )
    if socket is None:
        socket = "channel" if count == 3 else "flat"
    obj.connectors.append({
        "position": [face_cx, face_cy, face_cz],
        "normal": list(n),
        "socket": socket,
    })


def add_wall(obj, axis, sign):
    """Add a raised wall along one side face.

    axis: 'x' or 'z'
    sign: +1 or -1  (which side along that axis)
    The wall spans the full tile footprint on the other horizontal axis,
    sits at y=0 and rises to y=1+WALL_HEIGHT.
    """
    wt = WALL_THICKNESS
    wh = 1.0 + WALL_HEIGHT
    if axis == 'x':
        if sign > 0:
            add_box(obj, 1.0 - wt, 0.0, -1.0, 1.0, wh, 1.0)
        else:
            add_box(obj, -1.0, 0.0, -1.0, -1.0 + wt, wh, 1.0)
    else:  # axis == 'z'
        if sign > 0:
            add_box(obj, -1.0, 0.0, 1.0 - wt, 1.0, wh, 1.0)
        else:
            add_box(obj, -1.0, 0.0, -1.0, 1.0, wh, -1.0 + wt)


# ---------------------------------------------------------------------------
# Viewer
# ---------------------------------------------------------------------------

def view_tiles(tile_paths):
    """Show all tiles in a single interactive window with Prev/Next buttons."""
    import vedo

    state = {"idx": 0}

    def load_mesh(path):
        m = vedo.load(path)
        m.flat()                    # per-face shading — reveals groove facets clearly
        m.color("#b0c4de")
        m.lw(1.0).lc("#1a3a5c")    # visible dark edges
        # add a second copy as a slightly darker ambient shadow mesh
        return m

    names = [os.path.basename(p).replace(".obj", "") for p in tile_paths]
    meshes = [load_mesh(p) for p in tile_paths]

    lights = [
        vedo.Light(pos=( 3,  5,  3), focal_point=(0, 0, 0), c="white",   intensity=1.0),
        vedo.Light(pos=(-3,  2, -2), focal_point=(0, 0, 0), c="#aaccff", intensity=0.4),
        vedo.Light(pos=( 0, -3,  0), focal_point=(0, 0, 0), c="#334455", intensity=0.2),
    ]

    plt = vedo.Plotter(title=names[0], axes=1, bg="#1a1a2e", bg2="#16213e")
    plt.show(meshes[0], *lights, viewup="y", interactive=False)

    label = vedo.Text2D(names[0], pos="top-center", s=1.4, c="white", bg="k5")
    plt.add(label)

    def update(new_idx):
        state["idx"] = new_idx % len(meshes)
        i = state["idx"]
        for m in meshes:
            plt.remove(m)
        plt.add(meshes[i])
        label.text(names[i])
        plt.render()

    def on_next(obj, _):
        update(state["idx"] + 1)

    def on_prev(obj, _):
        update(state["idx"] - 1)

    btn_next = plt.add_button(on_next, pos=(0.92, 0.06), states=["Next ▶"],
                              c=["white"], bc=["#3a7ebf"], size=18)
    btn_prev = plt.add_button(on_prev, pos=(0.08, 0.06), states=["◀ Prev"],
                              c=["white"], bc=["#3a7ebf"], size=18)

    # Also support left/right arrow keys
    def on_key(evt):
        if evt.keypress == "Right":
            update(state["idx"] + 1)
        elif evt.keypress == "Left":
            update(state["idx"] - 1)

    plt.add_callback("KeyPress", on_key)
    plt.interactive().close()


def view_obj(path, title="tile"):
    """Render a single OBJ file interactively using vedo."""
    import vedo
    mesh = vedo.load(path)
    mesh.color("#b0c4de").alpha(0.95).lw(0.5)
    vedo.show(mesh, title=title, axes=1, viewup="y", new=True)


# ---------------------------------------------------------------------------
# Tile definitions
# ---------------------------------------------------------------------------

def generate_base_tile():
    """Straight tile: 2×1×2 box, connectable on all 4 side faces."""
    obj = ObjWriter("base")
    add_box(obj, -1.0, 0.0, -1.0, 1.0, 1.0, 1.0)
    # All four side faces are connectable
    add_connectors(obj, +1.0, 0.5, 0.0, (+1,  0,  0))  # +X
    add_connectors(obj, -1.0, 0.5, 0.0, (-1,  0,  0))  # -X
    add_connectors(obj,  0.0, 0.5, +1.0, ( 0,  0, +1))  # +Z
    add_connectors(obj,  0.0, 0.5, -1.0, ( 0,  0, -1))  # -Z
    obj.write("base_tile.obj")
    return obj


def generate_wall_tile():
    """One-wall tile: base + raised wall on the +Z side.

    The +Z face is closed (wall); the other three sides are connectable.
    """
    obj = ObjWriter("wall")
    add_box(obj, -1.0, 0.0, -1.0, 1.0, 1.0, 1.0)
    add_wall(obj, 'z', +1)
    # Connectable faces: +X, -X, -Z
    add_connectors(obj, +1.0, 0.5,  0.0, (+1,  0,  0))
    add_connectors(obj, -1.0, 0.5,  0.0, (-1,  0,  0))
    add_connectors(obj,  0.0, 0.5, -1.0, ( 0,  0, -1))
    obj.write("wall_tile.obj")
    return obj


def generate_corner_tile():
    """Corner tile: base + raised walls on the +Z and +X sides.

    Two closed faces form a corner; the remaining two (-X, -Z) are connectable.
    """
    obj = ObjWriter("corner")
    add_box(obj, -1.0, 0.0, -1.0, 1.0, 1.0, 1.0)
    add_wall(obj, 'z', +1)
    add_wall(obj, 'x', +1)
    # Connectable faces: -X, -Z
    add_connectors(obj, -1.0, 0.5,  0.0, (-1,  0,  0))
    add_connectors(obj,  0.0, 0.5, -1.0, ( 0,  0, -1))
    obj.write("corner_tile.obj")
    return obj


# ---------------------------------------------------------------------------
# Channel geometry helpers
# ---------------------------------------------------------------------------

MARBLE_RADIUS  = 1.0
CHANNEL_DEPTH  = MARBLE_RADIUS / 3.0   # = 1/3
CHANNEL_SEGS   = 16   # semicircle resolution


def channel_cross_section(t=1.0):
    """Return a list of (x, y) points describing one cross-section of the
    channel top surface, running across the X axis.

    t=1.0  -> full semicircular groove of radius MARBLE_RADIUS
    t=0.0  -> flat (no groove), but same number of points

    Always returns 2 + (CHANNEL_SEGS+1) + 2 = CHANNEL_SEGS+5 points,
    left-to-right so the top face normal is +Y.
    """
    r = MARBLE_RADIUS * t        # effective groove radius
    depth = CHANNEL_DEPTH * t    # groove depth

    pts = []
    # left flat rim point
    pts.append((-1.0, 1.0))
    # left groove edge (blends from -1 → -r as t→1, stays at 0 when t=0)
    pts.append((-r, 1.0))
    # semicircle from left rim to right rim (CHANNEL_SEGS+1 points)
    for i in range(CHANNEL_SEGS + 1):
        a = math.pi - math.pi * i / CHANNEL_SEGS   # π → 0
        if t > 1e-9:
            x = r * math.cos(a)
            y = 1.0 - depth * math.sin(a)
        else:
            x = 0.0
            y = 1.0
        pts.append((x, y))
    # right groove edge
    pts.append((r, 1.0))
    # right flat rim point
    pts.append((1.0, 1.0))
    return pts


def add_channel_surface(obj, z0, z1, t0=1.0, t1=1.0, y_base0=1.0, y_base1=1.0):
    """Add a ruled quad-strip top surface between two Z positions.

    The cross-section at z=z0 has blend factor t0 and at z=z1 has blend t1.
    y_base0/y_base1 shift the cross-section vertically (default 1.0 = normal height).
    Also adds the bottom face, the four side faces (+X/-X at each end if needed).
    """
    sec0 = [(x, y - 1.0 + y_base0) for x, y in channel_cross_section(t0)]
    sec1 = [(x, y - 1.0 + y_base1) for x, y in channel_cross_section(t1)]
    # Both sections must have the same number of points (they do because
    # CHANNEL_SEGS is fixed; t only scales radius/depth).

    n = len(sec0)
    assert len(sec1) == n

    # Build vertex indices for both rings
    row0 = [obj.v(x, y, z0) for x, y in sec0]
    row1 = [obj.v(x, y, z1) for x, y in sec1]

    # Top surface strip (normal roughly +Y)
    for i in range(n - 1):
        x0a, y0a = sec0[i];   x0b, y0b = sec0[i+1]
        x1a, y1a = sec1[i];   x1b, y1b = sec1[i+1]
        # Compute face normal via cross product of the two diagonal edges
        ex = (x0b - x0a + x1b - x1a) * 0.5
        ey = (y0b - y0a + y1b - y1a) * 0.5
        # second edge along z
        nx, ny, nz = cross((ex, ey, 0), (0, 0, z1 - z0))
        mag = math.sqrt(nx*nx + ny*ny + nz*nz)
        if mag < 1e-9:
            nx, ny, nz = 0.0, 1.0, 0.0  # flat segment fallback
        else:
            nx, ny, nz = nx/mag, ny/mag, nz/mag
        # CCW from +Y side: row0[i], row1[i], row1[i+1], row0[i+1]
        obj.quad(row0[i], row1[i], row1[i+1], row0[i+1], nx, ny, nz)

    # Bottom face (flat, normal -Y)
    bv0 = [obj.v(sec0[0][0], 0.0, z0), obj.v(sec0[-1][0], 0.0, z0)]
    bv1 = [obj.v(sec1[0][0], 0.0, z1), obj.v(sec1[-1][0], 0.0, z1)]
    obj.quad(bv0[0], bv0[1], bv1[1], bv1[0], 0, -1, 0)

    # -X side wall
    obj.quad(bv0[0], bv1[0], row1[0], row0[0], -1, 0, 0)
    # +X side wall
    obj.quad(bv0[1], row0[-1], row1[-1], bv1[1], +1, 0, 0)

    # -Z end cap
    end0_bot_l = obj.v(sec0[0][0],  0.0, z0)
    end0_bot_r = obj.v(sec0[-1][0], 0.0, z0)
    for i in range(n - 1):
        # triangle fan from bottom-left for simplicity
        pass
    # build the -Z end cap as a polygon face (works for convex sections)
    end0_verts = [obj.v(x, y, z0) for x, y in reversed(sec0)]
    end0_bot   = [obj.v(-1.0, 0.0, z0), obj.v(1.0, 0.0, z0)]
    # Fan from bottom centre
    bcv = obj.v(0.0, 0.0, z0)
    obj.tri(bcv, end0_bot[0], end0_verts[-1], 0, 0, -1)
    for i in range(len(end0_verts) - 1):
        obj.tri(bcv, end0_verts[i+1], end0_verts[i], 0, 0, -1)
    obj.tri(bcv, end0_bot[1], end0_verts[0], 0, 0, -1)

    # +Z end cap
    end1_verts = [obj.v(x, y, z1) for x, y in sec1]
    bcv1 = obj.v(0.0, 0.0, z1)
    obj.tri(bcv1, obj.v(-1.0, 0.0, z1), end1_verts[0], 0, 0, +1)
    for i in range(len(end1_verts) - 1):
        obj.tri(bcv1, end1_verts[i], end1_verts[i+1], 0, 0, +1)
    obj.tri(bcv1, end1_verts[-1], obj.v(1.0, 0.0, z1), 0, 0, +1)


def generate_ramp_tile():
    """Ramp tile: 2-unit-tall tile with channel rising from y=1 (-Z) to y=2 (+Z).

    The low end connects to standard ground-level channel tiles (channel socket).
    The high end connects to elevated channel tiles sitting on a y=1..2 base
    (channel_high socket).
    """
    obj = ObjWriter("ramp")
    LOW  = 1.0   # channel height at -Z end (matches standard tiles at y=0..1)
    HIGH = 2.0   # channel height at +Z end (matches elevated tiles at y=1..2)
    add_channel_surface(obj, z0=-1.0, z1=1.0, t0=1.0, t1=1.0,
                        y_base0=LOW, y_base1=HIGH)
    # Low (-Z) end: face spans y=0..1, center at y=0.5 — standard channel socket
    add_connectors(obj,  0.0, 0.5, -1.0, (0, 0, -1), count=3)
    # High (+Z) end: face spans y=0..2, connector dot at y=1.5
    add_connectors(obj,  0.0, 1.5, +1.0, (0, 0, +1), count=3)
    obj.write("ramp_tile.obj")
    return obj


CURVE_SEGS = 24   # arc resolution for the channel curve tile


def generate_curve_tile():
    """Curve tile: 4×4 footprint (x/z: -2..2), channel curves 90° from -Z face to +X face.

    Arc centre is at the inner corner (+2, -2).  R=3 places the centreline
    at the outer half of each open face: (-1,-2) on -Z, (+2,+1) on +X.
    At u=-1 (outer groove edge) the channel is flush with the tile boundary.

    Parametrise by angle a going from 180° down to 90°:
      path P(a) = (CX + R*cos(a),  CZ + R*sin(a))  with CX=2, CZ=-2
      radial inward = toward centre = (-cos(a), -sin(a))
      cross-section u=-1 is outer edge, u=+1 is inner edge
    """
    obj = ObjWriter("curve")
    FOOT  = 2.0
    R     = 3.0
    CX    = FOOT    # arc centre x = +2
    CZ    = -FOOT   # arc centre z = -2
    Y_TOP = 1.0

    cs  = channel_cross_section(1.0)   # (u, v): u in [-1,1] left→right, v in [0,1] bottom→top
    ncs = len(cs)

    def arc_ring(a):
        """Cross-section ring at arc angle a.

        Cross-section u axis = radially inward (-cos a, -sin a) in XZ.
        So u=-1 is the outer rim, u=+1 is the inner rim.
        """
        cos_a, sin_a = math.cos(a), math.sin(a)
        px = CX + R * cos_a   # path centre x
        pz = CZ + R * sin_a   # path centre z
        # radially inward unit vector in XZ
        rx, rz = -cos_a, -sin_a
        verts = []
        for u, v in cs:
            x = px + u * rx
            y = v * Y_TOP
            z = pz + u * rz
            verts.append(obj.v(x, y, z))
        return verts

    # Arc from a=180° to a=90° (decreasing angle)
    a_start = math.pi          # 180° → path at (0, -2): -Z face centre
    a_end   = math.pi * 0.5   # 90°  → path at (2,  0): +X face centre
    steps   = CURVE_SEGS

    angles = [a_start + (a_end - a_start) * i / steps for i in range(steps + 1)]
    rings  = [arc_ring(a) for a in angles]

    # Top surface quads — travel goes from a_start to a_end (decreasing a)
    # At a=180° cross-section right=(+1,0) so u=-1 is outer (-X), u=+1 inner (+X)
    # Wind CCW from above: r0[i], r0[i+1], r1[i+1], r1[i]
    for s in range(steps):
        r0, r1 = rings[s], rings[s + 1]
        a_mid  = (angles[s] + angles[s + 1]) * 0.5
        cos_a, sin_a = math.cos(a_mid), math.sin(a_mid)
        rx_mid, rz_mid = -cos_a, -sin_a   # inward radial
        for i in range(ncs - 1):
            p00 = obj._verts[r0[i]   - 1]
            p01 = obj._verts[r0[i+1] - 1]
            p10 = obj._verts[r1[i]   - 1]
            e1 = (p01[0]-p00[0], p01[1]-p00[1], p01[2]-p00[2])
            e2 = (p10[0]-p00[0], p10[1]-p00[1], p10[2]-p00[2])
            nx, ny, nz = cross(e2, e1)
            mag = math.sqrt(nx*nx + ny*ny + nz*nz)
            if mag < 1e-9:
                nx, ny, nz = 0.0, 1.0, 0.0
            else:
                nx, ny, nz = nx/mag, ny/mag, nz/mag
            obj.quad(r0[i], r1[i], r1[i+1], r0[i+1], nx, ny, nz)

    # Bottom face (normal -Y)
    bvs = [
        obj.v(-FOOT, 0, -FOOT), obj.v( FOOT, 0, -FOOT),
        obj.v( FOOT, 0,  FOOT), obj.v(-FOOT, 0,  FOOT),
    ]
    obj.quad(bvs[0], bvs[3], bvs[2], bvs[1], 0, -1, 0)

    # Closed side walls on the two non-opening faces
    # -X face (x=-2): full wall, no channel opening
    obj.quad(obj.v(-FOOT,0,-FOOT), obj.v(-FOOT,0, FOOT),
             obj.v(-FOOT,Y_TOP,FOOT), obj.v(-FOOT,Y_TOP,-FOOT), -1,0,0)
    # +Z face (z=+2): full wall, no channel opening
    obj.quad(obj.v(-FOOT,0,FOOT), obj.v(FOOT,0,FOOT),
             obj.v(FOOT,Y_TOP,FOOT), obj.v(-FOOT,Y_TOP,FOOT), 0,0,+1)

    # -Z end cap: groove at x=-2..0 (outer half), z=-2  (a=180°: path x=-1, rx=(+1,0))
    # x = path_x + u*rx = -1+u, so u=-1→x=-2 (tile edge), u=+1→x=0
    # Right fill panel covers the inner half (x=0..+2)
    obj.quad(obj.v(0.0,0,-FOOT), obj.v(0.0,Y_TOP,-FOOT),
             obj.v(FOOT,Y_TOP,-FOOT), obj.v(FOOT,0,-FOOT), 0,0,-1)
    # Groove profile: quads from y=0 up to cross-section
    cs_z = [(u - 1.0, v * Y_TOP) for u, v in cs]   # x = u-1, range [-2, 0]
    for i in range(len(cs_z) - 1, 0, -1):
        x1, y1 = cs_z[i];   x0, y0 = cs_z[i-1]
        obj.quad(obj.v(x0,0,-FOOT), obj.v(x0,y0,-FOOT),
                 obj.v(x1,y1,-FOOT), obj.v(x1,0,-FOOT), 0,0,-1)

    # +X end cap: groove at z=0..+2 (outer half), x=+2  (a=90°: path z=+1, rx=(0,-1))
    # z = path_z + u*rz = 1-u, so u=-1→z=+2 (tile edge), u=+1→z=0
    # Near fill panel covers the inner half (z=-2..0)
    obj.quad(obj.v(FOOT,0,-FOOT), obj.v(FOOT,Y_TOP,-FOOT),
             obj.v(FOOT,Y_TOP, 0.0), obj.v(FOOT,0, 0.0), +1,0,0)
    # Groove profile: z decreases 2→0 as i increases; use (A,B,C,D)=(F,0,z0),(F,0,z1),(F,y1,z1),(F,y0,z0)
    # so that (B-A)×(C-A) = +X with z0>z1
    cs_x = [(1.0 - u, v * Y_TOP) for u, v in cs]   # (z, y), z descends 2→0
    for i in range(len(cs_x) - 1):
        z0, y0 = cs_x[i];   z1, y1 = cs_x[i+1]   # z0 > z1
        obj.quad(obj.v(FOOT,0,z0), obj.v(FOOT,0,z1),
                 obj.v(FOOT,y1,z1), obj.v(FOOT,y0,z0), +1,0,0)

    # Connectors — channel on outer half of open faces; flat on all other half-face slots
    add_connectors(obj, -1.0, 0.5, -FOOT, (0, 0, -1), count=3)   # -Z outer half (channel)
    add_connectors(obj, FOOT, 0.5,  +1.0, (+1, 0,  0), count=3)  # +X outer half (channel)
    add_connectors(obj, +1.0, 0.5, -FOOT, (0, 0, -1))             # -Z inner half (flat)
    add_connectors(obj, FOOT, 0.5,  -1.0, (+1, 0,  0))            # +X inner half (flat)
    add_connectors(obj, -FOOT, 0.5, -1.0, (-1, 0,  0))            # -X near half (flat)
    add_connectors(obj, -FOOT, 0.5, +1.0, (-1, 0,  0))            # -X far half (flat)
    add_connectors(obj, -1.0, 0.5, +FOOT, (0, 0, +1))             # +Z left half (flat)
    add_connectors(obj, +1.0, 0.5, +FOOT, (0, 0, +1))             # +Z right half (flat)

    obj.write("curve_tile.obj")
    return obj

def generate_start_tile():
    """Start tile: 2-unit-tall tile, channel slopes from HIGH=2 (+Z back) down to LOW=1 (-Z front).

    Gravity feeds the marble down the slope toward -Z.
    Open only on -Z with a standard channel connector.
    Walled on +X, -X, and +Z; the +Z end cap is a solid wall at the HIGH face.
    """
    obj = ObjWriter("start")
    LOW  = 1.0   # channel height at -Z exit (standard channel height)
    HIGH = 2.0   # channel height at +Z back (elevated start)

    # Sloped channel surface
    add_channel_surface(obj, z0=-1.0, z1=1.0, t0=1.0, t1=1.0,
                        y_base0=LOW, y_base1=HIGH)

    # +X and -X walls span the full 2-unit height
    add_wall(obj, 'x', +1)
    add_wall(obj, 'x', -1)

    # +Z back wall: solid quad from y=0 to HIGH (the channel end cap from
    # add_channel_surface already covers the profile; add the rectangular
    # filler below the cross-section flat rim)
    obj.quad(
        obj.v(-1.0, 0.0, 1.0), obj.v( 1.0, 0.0, 1.0),
        obj.v( 1.0, HIGH, 1.0), obj.v(-1.0, HIGH, 1.0),
        0, 0, +1,
    )

    # -Z open face: standard channel connector at LOW height
    add_connectors(obj, 0.0, LOW - 0.5, -1.0, (0, 0, -1), count=3)
    obj.write("start_tile.obj")
    return obj

def generate_end_tile():
    """End tile: channel groove open on -Z only, walled on +X, -X, and +Z.

    The -Z face has a channel connector; all other sides are closed walls.
    The tile acts as a terminus/cap for a marble track.
    """
    obj = ObjWriter("end")
    add_channel_surface(obj, z0=-1.0, z1=1.0, t0=1.0, t1=1.0)
    add_wall(obj, 'x', +1)   # +X wall
    add_wall(obj, 'x', -1)   # -X wall
    add_wall(obj, 'z', +1)   # +Z back wall
    add_connectors(obj,  0.0, 0.5, -1.0, ( 0,  0, -1), count=3)  # channel end
    obj.write("end_tile.obj")
    return obj


def generate_channel_tile():
    """Channel tile: full semicircular groove running along Z, open on ±Z."""
    obj = ObjWriter("channel")
    add_channel_surface(obj, z0=-1.0, z1=1.0, t0=1.0, t1=1.0)
    add_connectors(obj, +1.0, 0.5, 0.0, (+1,  0,  0))          # flat side
    add_connectors(obj, -1.0, 0.5, 0.0, (-1,  0,  0))          # flat side
    add_connectors(obj,  0.0, 0.5, +1.0, ( 0,  0, +1), count=3)  # channel end
    add_connectors(obj,  0.0, 0.5, -1.0, ( 0,  0, -1), count=3)  # channel end
    obj.write("channel_tile.obj")
    return obj


def generate_bridge_tile():
    """Bridge tile: flat on -Z end, full channel on +Z end, smoothly interpolated."""
    obj = ObjWriter("bridge")
    add_channel_surface(obj, z0=-1.0, z1=1.0, t0=0.0, t1=1.0)
    add_connectors(obj, +1.0, 0.5, 0.0, (+1,  0,  0))          # flat side
    add_connectors(obj, -1.0, 0.5, 0.0, (-1,  0,  0))          # flat side
    add_connectors(obj,  0.0, 0.5, +1.0, ( 0,  0, +1), count=3)  # channel end
    add_connectors(obj,  0.0, 0.5, -1.0, ( 0,  0, -1))          # flat end
    obj.write("bridge_tile.obj")
    return obj


TILES = [
    ("base_tile.obj",    generate_base_tile,    "game_track"),
    ("wall_tile.obj",    generate_wall_tile,    "game_track"),
    ("corner_tile.obj",  generate_corner_tile,  "game_track"),
    ("channel_tile.obj", generate_channel_tile, "gravity_track"),
    ("bridge_tile.obj",  generate_bridge_tile,  "game_track"),
    ("ramp_tile.obj",    generate_ramp_tile,    "gravity_track"),
    ("curve_tile.obj",   generate_curve_tile,   "gravity_track"),
    ("start_tile.obj",   generate_start_tile,   "gravity_track"),
    ("end_tile.obj",     generate_end_tile,     "gravity_track"),
]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate marble track tiles.")
    parser.add_argument("--view", action="store_true", help="Open an interactive 3D viewer after generation.")
    parser.add_argument("--tile", choices=[t[0] for t in TILES], default=None,
                        help="Limit viewer to a single tile.")
    args = parser.parse_args()

    tile_meta = []
    for filename, gen_fn, tile_type in TILES:
        obj = gen_fn()
        tile_meta.append({
            "name": obj.name,
            "file": filename,
            "type": tile_type,
            "weight": 1,
            "connectors": obj.connectors,
        })

    meta_path = os.path.join(OUTPUT_DIR, "tiles.json")
    with open(meta_path, "w") as f:
        json.dump({"tiles": tile_meta}, f, indent=2)
    print(f"Written: {meta_path}")

    if args.view:
        paths = [os.path.join(OUTPUT_DIR, f) for f, _, __ in TILES]
        if args.tile:
            paths = [os.path.join(OUTPUT_DIR, args.tile)]
        view_tiles(paths)

    print("Done.")
