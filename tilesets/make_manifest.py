#!/usr/bin/env python3
"""Walk the tilesets directory and write tilesets_manifest.json.

Each entry contains:
  tiles            – sorted list of PNG filenames in that folder
  should_rotate    – false if files already encode rotations via numeric/alpha suffixes
  pixel_tolerance  – 0 for pixel-art (exact match); auto-detected for natural-art tilesets
"""

import json
import math
import re
from pathlib import Path

import numpy as np

from tile_utils import load_tiles

# Matches a rotation suffix at the end of a tile stem: "cliff 0", "cliff_1", "tileA" etc.
ROTATION_SUFFIX_RE = re.compile(r'[\s_]([0-9]|[A-Da-d])$')


def detect_should_rotate(pngs: list[Path]) -> bool:
    """Return False if filenames already encode all rotations via numeric/alpha suffixes."""
    stems = [p.stem for p in pngs]
    if not any(ROTATION_SUFFIX_RE.search(s) for s in stems):
        return True
    groups: dict[str, int] = {}
    for s in stems:
        m = ROTATION_SUFFIX_RE.search(s)
        if m:
            base = s[:m.start()]
            groups[base] = groups.get(base, 0) + 1
    return not any(count >= 2 for count in groups.values())


def _get_edges(arr: np.ndarray) -> tuple:
    """Extract the 4 edges matching wfc.zig's calcTextureId convention.
    Returns (top, right, bottom, left) each as a (w, 3) int64 array.
      top/bottom: L→R,  left/right: T→B
    """
    return (
        arr[ 0,  :, :3].astype(np.int64),   # top row    L→R
        arr[ :, -1, :3].astype(np.int64),   # right col  T→B
        arr[-1,  :, :3].astype(np.int64),   # bottom row L→R
        arr[ :,  0, :3].astype(np.int64),   # left col   T→B
    )


def _rotate_edges(top, right, bottom, left, rot: int) -> tuple:
    """Apply wfc.zig's rotation formula (same as calcAllRotations in wfc.zig)."""
    def rev(e):
        return e[::-1]
    if rot == 0:
        return top, right, bottom, left
    if rot == 1:  # 90° CW
        return rev(left), top, rev(right), bottom
    if rot == 2:  # 180°
        return rev(bottom), rev(left), rev(top), rev(right)
    # rot == 3: 270° CW
    return right, rev(bottom), left, rev(top)


def _edge_diff(ea: np.ndarray, eb: np.ndarray) -> int:
    """Max per-pixel per-channel diff — mirrors wfc.zig edgeMatches."""
    return int(np.abs(ea - eb).max()) if ea.size > 0 else 0


def compute_tolerance(tiles: list[dict]) -> int:
    """
    Find the minimum per-pixel tolerance so that every edge of every tile (across
    all 4 rotations) has at least one matching partner somewhere in the tileset.
    Returns 0 if all edges have exact matches, otherwise rounds up to nearest 5.
    Edge extraction and rotation exactly mirror wfc.zig's calcTextureId / calcAllRotations.
    """
    # Build all (top, right, bottom, left) edge-tuples for every tile × rotation.
    all_edge_sets = [
        _rotate_edges(*_get_edges(t['arr']), rot)
        for t in tiles
        for rot in range(4)
    ]

    max_min_cost = 0
    for (top, right, bottom, left) in all_edge_sets:
        # right must match some left
        best_r = min(_edge_diff(right, es[3]) for es in all_edge_sets)
        # bottom must match some top
        best_b = min(_edge_diff(bottom, es[0]) for es in all_edge_sets)
        max_min_cost = max(max_min_cost, best_r, best_b)

    return int(math.ceil(max_min_cost / 5)) * 5


root = Path(__file__).parent
manifest = {}

for d in sorted(root.iterdir()):
    if not d.is_dir() or d.name.startswith((".", "_")):
        continue
    pngs = sorted(d.glob("*.png"))
    if not pngs:
        continue

    should_rotate = detect_should_rotate(pngs)
    pixel_tolerance = compute_tolerance(load_tiles(d))

    manifest[d.name] = {
        "tiles": [p.name for p in pngs],
        "should_rotate": should_rotate,
        "pixel_tolerance": pixel_tolerance,
    }

output = root.parent / "src" / "tilesets_manifest.json"
output.write_text(json.dumps(manifest, indent=2) + "\n")
total_tiles = sum(len(v["tiles"]) for v in manifest.values())
print(f"Wrote {output} ({total_tiles} tiles across {len(manifest)} tilesets)")
