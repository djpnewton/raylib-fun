#!/usr/bin/env python3
"""
examine_tiles.py  –  visually inspect a tileset's neighbour constraints.

Reads the tileset manifest (src/tilesets_manifest.json) and renders which
tile/rotation pairs are declared valid neighbours of the selected tile.

Usage:
    python3 examine_tiles.py <TilesetName>   e.g. Knots, Summer, Castle

Click a tile/rotation in the top strip to select it.
The grid below shows all tile/rotation pairs: ✓ = declared valid neighbour.
"""

import sys
import json
import io
from pathlib import Path
from PIL import Image
import tkinter as tk

# ── paths ─────────────────────────────────────────────────────────────────────

REPO   = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "src" / "tilesets_manifest.json"

# ── symmetry helpers ──────────────────────────────────────────────────────────

def sym_rotations(sym: str) -> int:
    if sym == "X":   return 1
    if sym in ("I", "\\"): return 2
    return 4  # T, L, F

# ── data loading ──────────────────────────────────────────────────────────────

def load_tileset(name: str):
    """Return (tiles, variants, right_set, below_set) for the named tileset."""
    manifest = json.loads(MANIFEST.read_text())
    # Array format: [{"name": ..., "tiles": ..., ...}, ...]
    by_name = {ts["name"]: ts for ts in manifest}
    if name not in by_name:
        # Try case-insensitive
        matches = [k for k in by_name if k.lower() == name.lower()]
        if not matches:
            raise SystemExit(f"Tileset '{name}' not found. Available: {', '.join(by_name)}")
        name = matches[0]
    entry = by_name[name]

    tiles = []
    for t in entry["tiles"]:
        img_path = REPO / t["path"]
        img = Image.open(img_path).convert("RGBA")
        tiles.append({
            "name":     t["name"],
            "path":     img_path,
            "symmetry": t["symmetry"],
            "weight":   t["weight"],
            "img":      img,
        })

    # All (tile_idx, rotation) pairs, using only symmetry-valid rotations.
    variants = []
    for i, tile in enumerate(tiles):
        n_rot = sym_rotations(tile["symmetry"])
        for rot in range(n_rot):
            img = tile["img"].rotate(rot * 90, expand=False)  # CCW, matching reference WFC
            label = f"{tile['name']}" if n_rot == 1 else f"{tile['name']} r{rot}"
            variants.append({"tile_idx": i, "rot": rot, "name": label, "img": img})

    right_set = {tuple(nb) for nb in entry["right_neighbors"]}
    below_set = {tuple(nb) for nb in entry["below_neighbors"]}

    return tiles, variants, right_set, below_set

# ── GUI ───────────────────────────────────────────────────────────────────────

THUMB  = 64
PAD    = 4
GREEN  = "#00dd44"
RED    = "#cc2200"
DIM    = "#444444"

class App(tk.Tk):
    def __init__(self, tileset_name: str):
        super().__init__()
        self.title(f"Tile Neighbour Examiner – {tileset_name}")
        self.configure(bg="#1a1a1a")

        self.tiles, self.variants, self.right_set, self.below_set = load_tileset(tileset_name)
        self.selected = 0  # index into self.variants

        self._build_ui()
        self._select(0)

    # ── build ─────────────────────────────────────────────────────────────────

    def _build_ui(self):
        # ---- strip (all variants) -------------------------------------------
        strip_outer = tk.Frame(self, bg="#1a1a1a")
        strip_outer.pack(side=tk.TOP, fill=tk.X, padx=PAD, pady=PAD)

        canvas_w = (THUMB + PAD) * len(self.variants) + PAD
        STRIP_H  = THUMB + PAD * 2 + 14
        self.strip = tk.Canvas(strip_outer, height=STRIP_H, width=canvas_w,
                               bg="#222", highlightthickness=0)
        self.strip.pack(side=tk.LEFT)
        self._draw_strip()

        # ---- controls -------------------------------------------------------
        ctrl = tk.Frame(self, bg="#1a1a1a")
        ctrl.pack(side=tk.TOP, fill=tk.X, padx=PAD, pady=(0, PAD))

        self.sort_var = tk.BooleanVar(value=False)
        tk.Checkbutton(ctrl, text="Sort: matches first", variable=self.sort_var,
                       bg="#1a1a1a", fg="white", selectcolor="#333",
                       activebackground="#1a1a1a", activeforeground="white",
                       command=lambda: self._select(self.selected)).pack(side=tk.LEFT, padx=4)

        self.hide_var = tk.BooleanVar(value=False)
        tk.Checkbutton(ctrl, text="Hide non-matches", variable=self.hide_var,
                       bg="#1a1a1a", fg="white", selectcolor="#333",
                       activebackground="#1a1a1a", activeforeground="white",
                       command=lambda: self._select(self.selected)).pack(side=tk.LEFT, padx=4)

        # ---- info label -----------------------------------------------------
        self.info_var = tk.StringVar()
        tk.Label(self, textvariable=self.info_var, fg="#aaa", bg="#1a1a1a",
                 anchor="w").pack(side=tk.TOP, fill=tk.X, padx=PAD)

        # ---- grid with scrollbar --------------------------------------------
        grid_frame = tk.Frame(self, bg="#1a1a1a")
        grid_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=PAD, pady=PAD)
        self.grid_canvas = tk.Canvas(grid_frame, bg="#1a1a1a", highlightthickness=0)
        vsb = tk.Scrollbar(grid_frame, orient=tk.VERTICAL, command=self.grid_canvas.yview)
        self.grid_canvas.configure(yscrollcommand=vsb.set)
        vsb.pack(side=tk.RIGHT, fill=tk.Y)
        self.grid_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.grid_canvas.bind("<Configure>",  lambda _: self._redraw_grid())
        self.grid_canvas.bind("<MouseWheel>",
            lambda e: self.grid_canvas.yview_scroll(-1 * (e.delta // 120), "units"))

    def _draw_strip(self):
        self.strip_photos = []
        self.strip.delete("all")
        for i, v in enumerate(self.variants):
            thumb = v["img"].resize((THUMB, THUMB), Image.NEAREST)
            photo = tk.PhotoImage(data=_to_ppm(thumb))
            self.strip_photos.append(photo)
            x = PAD + i * (THUMB + PAD)
            self.strip.create_image(x, PAD, anchor="nw", image=photo, tags=f"v_{i}")
            self.strip.create_text(x + THUMB // 2, PAD + THUMB + 2,
                                   text=v["name"], fill="white", font=("sans", 7),
                                   tags=f"v_{i}")
            self.strip.tag_bind(f"v_{i}", "<Button-1>", lambda e, idx=i: self._select(idx))

    # ── interaction ───────────────────────────────────────────────────────────

    def _select(self, idx: int):
        self.selected = idx
        v   = self.variants[idx]
        t   = self.tiles[v["tile_idx"]]
        sym = t["symmetry"]
        self.info_var.set(
            f"Selected: {v['name']}  symmetry={sym}  weight={t['weight']}"
        )
        # Highlight selection in strip
        self.strip.delete("sel_box")
        x = PAD + idx * (THUMB + PAD)
        self.strip.create_rectangle(x - 2, PAD - 2, x + THUMB + 2, PAD + THUMB + 2,
                                    outline="yellow", width=2, tags="sel_box")
        self._redraw_grid()

    def _redraw_grid(self):
        self.grid_canvas.delete("all")
        self._grid_photos = []

        sv  = self.variants[self.selected]
        si  = sv["tile_idx"]
        sr  = sv["rot"]

        def matches(v):
            vi, vr = v["tile_idx"], v["rot"]
            r = (si, sr, vi, vr) in self.right_set   # sel LEFT  of v
            l = (vi, vr, si, sr) in self.right_set   # sel RIGHT of v
            d = (si, sr, vi, vr) in self.below_set   # sel ABOVE v
            u = (vi, vr, si, sr) in self.below_set   # sel BELOW v
            return r, l, d, u

        scored = [(v, *matches(v)) for v in self.variants]

        if self.sort_var.get():
            scored.sort(key=lambda t: -sum(t[1:]))

        if self.hide_var.get():
            scored = [t for t in scored if any(t[1:])]

        CELL_W = THUMB + PAD + 56
        CELL_H = THUMB + PAD + 18
        cols   = max(1, self.grid_canvas.winfo_width() // CELL_W)

        row = col = 0
        for v, mr, ml, md, mu in scored:
            x = PAD + col * CELL_W
            y = PAD + row * CELL_H

            thumb = v["img"].resize((THUMB, THUMB), Image.NEAREST)
            photo = tk.PhotoImage(data=_to_ppm(thumb))
            self._grid_photos.append(photo)
            self.grid_canvas.create_image(x, y, anchor="nw", image=photo)

            tx = x + THUMB + 4
            for dy, symbol, flag in [
                (6,  "→", mr),
                (18, "←", ml),
                (30, "↓", md),
                (42, "↑", mu),
            ]:
                mark  = "✓" if flag else "✗"
                color = GREEN if flag else DIM
                self.grid_canvas.create_text(
                    tx, y + dy,
                    text=f"{symbol} {mark}", fill=color, anchor="w", font=("mono", 9))

            self.grid_canvas.create_text(
                x + THUMB // 2, y + THUMB + 4,
                text=v["name"], fill="#aaa", font=("sans", 7))

            col += 1
            if col >= cols:
                col = 0
                row += 1

        total_h = (row + (1 if col > 0 else 0)) * CELL_H + PAD
        self.grid_canvas.configure(
            scrollregion=(0, 0, self.grid_canvas.winfo_width(), total_h))


# ── helpers ───────────────────────────────────────────────────────────────────

def _to_ppm(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.convert("RGB").save(buf, format="PPM")
    return buf.getvalue()


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("tileset", help="Tileset name, e.g. Knots, Summer, Castle")
    args = parser.parse_args()
    App(args.tileset).mainloop()

if __name__ == "__main__":
    main()

