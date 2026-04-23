#!/usr/bin/env python3
"""Walk the tilesets directory and write tilesets_manifest.json from XML descriptors.

Each entry contains:
  tiles           – list of tile objects {name, path, symmetry, weight}
  right_neighbors – [[a_idx, a_rot, b_idx, b_rot], ...] — b can be to the right of a
  below_neighbors – [[a_idx, a_rot, b_idx, b_rot], ...] — b can be below a

Neighbor derivation follows SimpleTiledModel.cs from the original WFC repository:
  https://github.com/mxgmn/WaveFunctionCollapse/blob/master/SimpleTiledModel.cs

For unique=False tilesets (most): XML lists minimal pairs; from each entry we
derive 4 horizontal + 4 vertical pairs using the action table (a=rotate90°CW,
b=reflect). unique=True tilesets (Summer) list all pairs explicitly → 1:1 mapping.
"""

import json
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).parent


def sym_rotations(sym: str) -> int:
    """Return the number of valid rotations for a WFC symmetry type."""
    if sym == "X":
        return 1
    if sym in ("I", "\\"):
        return 2
    return 4  # T, L, F — 4 distinct rotations in our system


def norm_rot(sym: str, rot: int) -> int:
    """Normalise a rotation index into the canonical range for this symmetry."""
    return rot % sym_rotations(sym)


def parse_ref(ref: str) -> tuple[str, int]:
    """Parse 'name' or 'name N' into (name, rotation_int)."""
    parts = ref.strip().split()
    return (parts[0], int(parts[1])) if len(parts) > 1 else (parts[0], 0)


def a_fn(sym: str, r: int) -> int:
    """90° CW rotation — the `a` function from SimpleTiledModel."""
    if sym in ("L", "T", "F"):
        return (r + 1) % 4
    if sym in ("I", "\\"):
        return 1 - r
    return 0  # X


def b_fn(sym: str, r: int) -> int:
    """Reflection — the `b` function from SimpleTiledModel.
    For F symmetry this returns rotations 4-7 (outside our 0-3 range); those
    pairs are filtered out by build_tileset."""
    if sym == "L":  return r + 1 if r % 2 == 0 else r - 1  # 0↔1, 2↔3
    if sym == "T":  return r if r % 2 == 0 else 4 - r      # 0→0, 1→3, 2→2, 3→1
    if sym == "I":  return r                                 # identity
    if sym == "\\":  return 1 - r                           # 0↔1
    if sym == "F":  return (r + 4) % 8                      # → 4-7, filtered
    return 0  # X


def apply_action(sym: str, r: int, k: int) -> int:
    """Apply action k ∈ [0, 7] to rotation r.
    k=0: identity  k=1: a  k=2: aa  k=3: aaa
    k=4: b         k=5: ba k=6: baa k=7: baaa  (matches action[t] table)"""
    def a(x): return a_fn(sym, x)
    def b(x): return b_fn(sym, x)
    if k == 0: return r
    if k == 1: return a(r)
    if k == 2: return a(a(r))
    if k == 3: return a(a(a(r)))
    if k == 4: return b(r)
    if k == 5: return b(a(r))
    if k == 6: return b(a(a(r)))
    if k == 7: return b(a(a(a(r))))
    return r


def build_tileset(xml_path: Path, tile_dir: Path) -> dict | None:
    tree = ET.parse(xml_path)
    root_el = tree.getroot()

    tiles_el = root_el.find("tiles")
    if tiles_el is None:
        return None

    # unique=True: every tile entry is already a specific pre-rotated bitmap.
    # Each maps 1:1 to a file and must not be rotated further → treat as symmetry X.
    unique = root_el.get("unique", "False").lower() == "true"

    names: list[str] = []
    syms: dict[str, str] = {}
    weights_map: dict[str, float] = {}
    # unique=True only: original tile symmetry and start index for each base name.
    first_occ: dict[str, int] = {}
    sym_orig: dict[str, str] = {}

    if unique:
        # unique=True: each XML tile has pre-rendered variant files "name N.png".
        # Expand each into its rotation variants as separate flat entries (symmetry X each).
        # We keep first_occ/sym_orig so the neighbor derivation can still use the
        # original symmetry action table (matching SimpleTiledModel.cs).
        for t in tiles_el.findall("tile"):
            base = t.get("name")
            sym = t.get("symmetry", "X")
            card = sym_rotations(sym)
            weight = float(t.get("weight", "1.0"))
            first_occ[base] = len(names)
            sym_orig[base] = sym
            for r in range(card):
                variant = f"{base} {r}"
                names.append(variant)
                syms[variant] = "X"
                weights_map[variant] = weight
    else:
        for t in tiles_el.findall("tile"):
            name = t.get("name")
            syms[name] = t.get("symmetry", "X")
            weights_map[name] = float(t.get("weight", "1.0"))
            names.append(name)

    idx = {name: i for i, name in enumerate(names)}

    # Paths relative to the repo root (parent of tilesets/).
    def tile_path(name: str) -> str:
        p = tile_dir / f"{name}.png"       # covers "cliff 0.png" (unique) or "corner.png"
        if not p.exists():
            p = tile_dir / f"{name} 0.png" # fallback for non-unique tilesets with numbered files
        return str(p.relative_to(root.parent))

    tiles = [
        {
            "name": n,
            "path": tile_path(n),
            "symmetry": syms[n],
            "weight": weights_map[n],
        }
        for n in names
    ]

    right_nb: set[tuple] = set()
    below_nb: set[tuple] = set()

    def add_right(ti_a: int, ra: int, sym_a: str, ti_b: int, rb: int, sym_b: str) -> None:
        if ra < sym_rotations(sym_a) and rb < sym_rotations(sym_b):
            right_nb.add((ti_a, ra, ti_b, rb))

    def add_below(ti_a: int, ra: int, sym_a: str, ti_b: int, rb: int, sym_b: str) -> None:
        if ra < sym_rotations(sym_a) and rb < sym_rotations(sym_b):
            below_nb.add((ti_a, ra, ti_b, rb))

    # Unique-tileset helpers: each variant is its own flat entry at rotation 0.
    n_tiles = len(names)

    def add_right_u(a_global: int, b_global: int) -> None:
        if 0 <= a_global < n_tiles and 0 <= b_global < n_tiles:
            right_nb.add((a_global, 0, b_global, 0))

    def add_below_u(a_global: int, b_global: int) -> None:
        if 0 <= a_global < n_tiles and 0 <= b_global < n_tiles:
            below_nb.add((a_global, 0, b_global, 0))

    neighbors_el = root_el.find("neighbors")
    if neighbors_el is not None:
        for nb in neighbors_el.findall("neighbor"):
            ln, lr = parse_ref(nb.get("left", ""))
            rn, rr = parse_ref(nb.get("right", ""))

            if unique:
                # Use original tile symmetry + action table to derive which variant
                # indices are involved — matching SimpleTiledModel.cs exactly.
                if ln not in sym_orig or rn not in sym_orig:
                    print(f"  Warning: unknown tile in neighbor: '{ln}' / '{rn}'")
                    continue
                ls, rs = sym_orig[ln], sym_orig[rn]
                lr_n, rr_n = norm_rot(ls, lr), norm_rot(rs, rr)

                def _ag(name: str, rot: int, k: int) -> int:
                    return first_occ[name] + apply_action(sym_orig[name], rot, k)

                # 4 horizontal pairs
                add_right_u(_ag(ln, lr_n, 0), _ag(rn, rr_n, 0))
                add_right_u(_ag(ln, lr_n, 6), _ag(rn, rr_n, 6))
                add_right_u(_ag(rn, rr_n, 4), _ag(ln, lr_n, 4))
                add_right_u(_ag(rn, rr_n, 2), _ag(ln, lr_n, 2))

                # 4 vertical pairs
                add_below_u(_ag(rn, rr_n, 1), _ag(ln, lr_n, 1))
                add_below_u(_ag(ln, lr_n, 7), _ag(rn, rr_n, 7))
                add_below_u(_ag(rn, rr_n, 5), _ag(ln, lr_n, 5))
                add_below_u(_ag(ln, lr_n, 3), _ag(rn, rr_n, 3))
                continue  # skip the non-unique shared path below
            else:
                if ln not in idx or rn not in idx:
                    print(f"  Warning: unknown tile in neighbor: '{ln}' / '{rn}'")
                    continue
                li, ri = idx[ln], idx[rn]
                ls, rs = syms[ln], syms[rn]
                lr_n = norm_rot(ls, lr)
                rr_n = norm_rot(rs, rr)

            # Derive all 4 horizontal + 4 vertical pairs using the action table,
            # matching SimpleTiledModel.cs. For X symmetry all actions collapse to
            # identity, giving 1 deduped H-pair and 1 V-pair per XML entry.
            #
            # D = action[L][1] (left tile rotated → BELOW after 90° CW world rotation)
            # U = action[R][1] (right tile rotated → ABOVE after 90° CW world rotation)

            # 4 horizontal pairs (LEFT_tile, LEFT_rot, RIGHT_tile, RIGHT_rot)
            add_right(li, lr_n, ls, ri, rr_n, rs)
            add_right(li, apply_action(ls, lr_n, 6), ls,
                      ri, apply_action(rs, rr_n, 6), rs)
            add_right(ri, apply_action(rs, rr_n, 4), rs,
                      li, apply_action(ls, lr_n, 4), ls)
            add_right(ri, apply_action(rs, rr_n, 2), rs,
                      li, apply_action(ls, lr_n, 2), ls)

            # 4 vertical pairs (ABOVE_tile, ABOVE_rot, BELOW_tile, BELOW_rot)
            add_below(ri, apply_action(rs, rr_n, 1), rs,
                      li, apply_action(ls, lr_n, 1), ls)
            add_below(li, apply_action(ls, lr_n, 7), ls,
                      ri, apply_action(rs, rr_n, 7), rs)
            add_below(ri, apply_action(rs, rr_n, 5), rs,
                      li, apply_action(ls, lr_n, 5), ls)
            add_below(li, apply_action(ls, lr_n, 3), ls,
                      ri, apply_action(rs, rr_n, 3), rs)

    return {
        "tiles": tiles,
        "right_neighbors": [list(p) for p in sorted(right_nb)],
        "below_neighbors": [list(p) for p in sorted(below_nb)],
    }


manifest = {}

for d in sorted(root.iterdir()):
    if not d.is_dir() or d.name.startswith((".", "_")):
        continue
    xml_path = root / f"{d.name}.xml"
    if not xml_path.exists():
        print(f"Skipping {d.name}: no XML found")
        continue
    print(f"Processing {d.name}...")
    entry = build_tileset(xml_path, d)
    if entry:
        manifest[d.name] = entry
        print(f"  {len(entry['tiles'])} tiles, "
              f"{len(entry['right_neighbors'])} right-pairs, "
              f"{len(entry['below_neighbors'])} below-pairs")

output_path = root.parent / "src" / "tilesets_manifest.json"
output_path.write_text(json.dumps(manifest, indent=2) + "\n")
total = sum(len(v["tiles"]) for v in manifest.values())
print(f"\nWrote {output_path} ({total} tiles across {len(manifest)} tilesets)")

