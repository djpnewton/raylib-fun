#!/usr/bin/env python3
"""Shared tile utilities used by examine_tiles.py and make_tileset_meta.py."""

from pathlib import Path

import numpy as np
from PIL import Image

ROTATIONS = [0, 90, 180, 270]  # degrees CW


def edge_score(arr_a: np.ndarray, arr_b: np.ndarray, direction: str, tol_per_pixel: float) -> float:
    """
    Per-pixel per-channel RGB comparison — mirrors wfc.zig edgeMatches exactly.
      direction='right'  → compare arr_a's right column vs arr_b's left column
      direction='below'  → compare arr_a's bottom row  vs arr_b's top row
    Score = max_over_pixels(max(|dR|, |dG|, |dB|)) / tol_per_pixel.
    Returns 0.0 = perfect, 1.0 = exactly at tolerance, >1.0 = no match.
    Calling with tol_per_pixel=1.0 returns the raw worst per-pixel diff.
    """
    if direction == 'right':
        ea = arr_a[:, -1, :3].astype(np.int64)   # (h, 3) – RGB only
        eb = arr_b[:,  0, :3].astype(np.int64)
    else:  # 'below'
        ea = arr_a[-1, :, :3].astype(np.int64)   # (w, 3)
        eb = arr_b[ 0, :, :3].astype(np.int64)
    worst = int(np.abs(ea - eb).max()) if ea.size > 0 else 0
    return worst / tol_per_pixel if tol_per_pixel > 0 else (0.0 if worst == 0 else float('inf'))


def load_tiles(directory: Path) -> list[dict]:
    """Load all PNGs in *directory* as RGBA numpy arrays."""
    pngs = sorted(directory.glob("*.png"))
    tiles = []
    for p in pngs:
        img = Image.open(p).convert("RGBA")
        arr = np.array(img)
        tiles.append({"path": p, "name": p.stem, "img": img, "arr": arr, "w": arr.shape[1]})
    return tiles


def make_rotated(tile: dict, rotation: int) -> dict:
    """Return a new tile dict with the image rotated *rotation* degrees CW."""
    img = tile["img"].rotate(-rotation, expand=False)  # PIL rotates CCW
    arr = np.array(img)
    return {"path": tile["path"], "name": f"{tile['name']} {rotation}°",
            "img": img, "arr": arr, "w": arr.shape[1]}
