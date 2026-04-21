#!/usr/bin/env python3
"""
examine_tiles.py  –  visually inspect a tileset directory.

For each tile it shows the tile image plus colour-coded edge-match scores
against every other tile (including rotations).

Usage:
    python3 examine_tiles.py <tileset_dir>  [--tolerance 25]

Click a tile in the top strip to select it; the grid below shows all
tiles/rotations scored against it (green = good match, red = poor).
"""

import sys
import argparse
from pathlib import Path
from PIL import Image
import tkinter as tk
from tkinter import ttk

from tile_utils import ROTATIONS, edge_score, load_tiles, make_rotated

# ── helpers ──────────────────────────────────────────────────────────────────

def score_to_colour(score: float) -> str:
    t = min(score, 1.0)
    r = int(255 * t)
    g = int(255 * (1 - t))
    return f"#{r:02x}{g:02x}00"

# ── GUI ──────────────────────────────────────────────────────────────────────

THUMB = 64   # thumbnail size in pixels
PAD   = 4

class App(tk.Tk):
    def __init__(self, tiles, tol_per_pixel: float):
        super().__init__()
        self.title("Tile Edge Examiner")
        self.configure(bg="#1a1a1a")
        self.tiles = tiles
        self.tol = tol_per_pixel
        self.selected = 0

        # Pre-compute all rotated variants
        self.variants = []
        for tile in tiles:
            for rot in ROTATIONS:
                v = make_rotated(tile, rot)
                self.variants.append(v)

        self._build_ui()
        self._select(0)

    # ── build ────────────────────────────────────────────────────────────────

    def _build_ui(self):
        style = ttk.Style(self)
        style.theme_use("clam")

        top_frame = tk.Frame(self, bg="#1a1a1a")
        top_frame.pack(side=tk.TOP, fill=tk.X, padx=PAD, pady=PAD)

        tk.Label(top_frame, text="Select tile:", fg="white", bg="#1a1a1a").pack(side=tk.LEFT)

        # Tolerance slider
        ctrl = tk.Frame(self, bg="#1a1a1a")
        ctrl.pack(side=tk.TOP, fill=tk.X, padx=PAD)
        tk.Label(ctrl, text="Tolerance/pixel:", fg="white", bg="#1a1a1a").pack(side=tk.LEFT)
        self.tol_var = tk.DoubleVar(value=self.tol)
        slider = tk.Scale(ctrl, from_=0, to=100, resolution=0.5, orient=tk.HORIZONTAL,
                          variable=self.tol_var, bg="#333", fg="white",
                          troughcolor="#555", highlightthickness=0,
                          command=lambda _: self._select(self.selected))
        slider.pack(side=tk.LEFT, fill=tk.X, expand=True)

        # Sort checkbox
        self.sort_var = tk.BooleanVar(value=False)
        tk.Checkbutton(ctrl, text="Sort by best match", variable=self.sort_var,
                       bg="#1a1a1a", fg="white", selectcolor="#333",
                       activebackground="#1a1a1a", activeforeground="white",
                       command=lambda: self._select(self.selected)).pack(side=tk.LEFT, padx=8)
        strip_outer = tk.Frame(self, bg="#1a1a1a")
        strip_outer.pack(side=tk.TOP, fill=tk.X, padx=PAD, pady=PAD)
        canvas_w = (THUMB + PAD) * len(self.tiles) + PAD
        STRIP_H = THUMB + PAD * 2 + 14  # thumbnail + padding + text label
        self.strip = tk.Canvas(strip_outer, height=STRIP_H,
                               width=canvas_w, bg="#222", highlightthickness=0)
        self.strip.pack(side=tk.LEFT)
        self._draw_strip()

        # Info label
        self.info_var = tk.StringVar()
        tk.Label(self, textvariable=self.info_var, fg="#aaa", bg="#1a1a1a",
                 anchor="w").pack(side=tk.TOP, fill=tk.X, padx=PAD)

        # Grid canvas with scrollbar
        grid_frame = tk.Frame(self, bg="#1a1a1a")
        grid_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=PAD, pady=PAD)
        self.grid_canvas = tk.Canvas(grid_frame, bg="#1a1a1a", highlightthickness=0)
        vsb = tk.Scrollbar(grid_frame, orient=tk.VERTICAL, command=self.grid_canvas.yview)
        self.grid_canvas.configure(yscrollcommand=vsb.set)
        vsb.pack(side=tk.RIGHT, fill=tk.Y)
        self.grid_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.grid_canvas.bind("<Configure>", lambda _: self._redraw_grid())
        self.grid_canvas.bind("<MouseWheel>", lambda e: self.grid_canvas.yview_scroll(-1 * (e.delta // 120), "units"))

    def _draw_strip(self):
        self.strip_photos = []
        self.strip.delete("all")
        for i, tile in enumerate(self.tiles):
            thumb = tile["img"].resize((THUMB, THUMB), Image.NEAREST)
            photo = tk.PhotoImage(data=self._to_ppm(thumb))
            self.strip_photos.append(photo)
            x = PAD + i * (THUMB + PAD)
            self.strip.create_image(x, PAD, anchor="nw", image=photo,
                                    tags=f"tile_{i}")
            self.strip.create_text(x + THUMB // 2, PAD + THUMB + 2,
                                   text=tile["name"], fill="white", font=("sans", 7),
                                   tags=f"tile_{i}")
            self.strip.tag_bind(f"tile_{i}", "<Button-1>", lambda e, idx=i: self._select(idx))

    def _select(self, idx: int):
        self.selected = idx
        self.tol = self.tol_var.get()
        tile = self.tiles[idx]
        self.info_var.set(f"Selected: {tile['name']}  ({tile['w']}×{tile['w']} px)")
        # Highlight selected
        self.strip.delete("sel_box")
        x = PAD + idx * (THUMB + PAD)
        self.strip.create_rectangle(x - 2, PAD - 2, x + THUMB + 2, PAD + THUMB + 2,
                                    outline="yellow", width=2, tags="sel_box")
        self._redraw_grid()

    def _redraw_grid(self):
        self.grid_canvas.delete("all")
        self._grid_photos = []

        sel_tile = self.tiles[self.selected]
        sel_arr = sel_tile["arr"]

        def all_scores(v):
            arr = v["arr"]
            return (
                edge_score(sel_arr, arr,  'right', self.tol),  # → sel left,  v right
                edge_score(arr,  sel_arr, 'right', self.tol),  # ← v left,   sel right
                edge_score(sel_arr, arr,  'below', self.tol),  # ↓ sel above, v below
                edge_score(arr,  sel_arr, 'below', self.tol),  # ↑ v above,  sel below
            )

        scored = [(v, *all_scores(v)) for v in self.variants]
        if self.sort_var.get():
            scored.sort(key=lambda t: sum(t[1:]))

        cols = max(1, self.grid_canvas.winfo_width() // (THUMB + PAD + 90))
        CELL_W = THUMB + PAD + 90
        CELL_H = THUMB + PAD + 20

        row = col = 0
        for v, s_right, s_left, s_below, s_above in scored:

            x = PAD + col * CELL_W
            y = PAD + row * CELL_H

            thumb = v["img"].resize((THUMB, THUMB), Image.NEAREST)
            photo = tk.PhotoImage(data=self._to_ppm(thumb))
            self._grid_photos.append(photo)

            self.grid_canvas.create_image(x, y, anchor="nw", image=photo)
            tx = x + THUMB + 4
            self.grid_canvas.create_text(tx, y + 8,  text=f"→ {s_right:.2f}", fill=score_to_colour(s_right), anchor="w", font=("mono", 8))
            self.grid_canvas.create_text(tx, y + 20, text=f"← {s_left:.2f}",  fill=score_to_colour(s_left),  anchor="w", font=("mono", 8))
            self.grid_canvas.create_text(tx, y + 32, text=f"↓ {s_below:.2f}", fill=score_to_colour(s_below), anchor="w", font=("mono", 8))
            self.grid_canvas.create_text(tx, y + 44, text=f"↑ {s_above:.2f}", fill=score_to_colour(s_above), anchor="w", font=("mono", 8))
            self.grid_canvas.create_text(
                x + THUMB // 2, y + THUMB + 2,
                text=v["name"], fill="#aaa", font=("sans", 7))

            col += 1
            if col >= cols:
                col = 0
                row += 1

        total_h = (row + (1 if col > 0 else 0)) * CELL_H + PAD
        self.grid_canvas.configure(scrollregion=(0, 0, self.grid_canvas.winfo_width(), total_h))

    @staticmethod
    def _to_ppm(img: Image.Image) -> bytes:
        """Convert PIL image to PPM bytes for tkinter PhotoImage."""
        import io
        buf = io.BytesIO()
        img.convert("RGB").save(buf, format="PPM")
        return buf.getvalue()


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", default=".",
                        help="Tileset directory (default: current dir)")
    parser.add_argument("--tolerance", type=float, default=25.0,
                        help="Per-pixel per-channel tolerance (default: 25, matches wfc.zig)")
    args = parser.parse_args()

    directory = Path(args.directory)
    if not directory.is_dir():
        print(f"Error: {directory} is not a directory", file=sys.stderr)
        sys.exit(1)

    tiles = load_tiles(directory)
    if not tiles:
        print(f"No PNG files found in {directory}", file=sys.stderr)
        sys.exit(1)

    print(f"Loaded {len(tiles)} tiles from {directory}")
    app = App(tiles, args.tolerance)
    app.mainloop()


if __name__ == "__main__":
    main()
