"""Layered rock slab (dark_rock_02): a nearly flat slab with a few big diagonal cracks and horizontal seams: lump_gen with
the straight-crack layer and a flat sheet, scale from the plain square. Uses the lump family: lumps tiny, cracks free."""
import os
import sys

import limits  # (first)

import fit_bark
import lump_gen as lg

lg.RANGES.update({"lump_amp": (0.02, 0.25), "crease_depth": (0.0, 0.3), "vor_depth": (0.15, 0.7), "vor_cm": (40.0, 120.0),
                  "vor_w": (0.01, 0.04), "mid_amp": (0.05, 0.3), "rub_amp": (0.0, 0.2), "grain_cm": (1.5, 3.0),
                  "grain_amp": (0.0, 0.05)})
folder, name, tile_m = sys.argv[1], sys.argv[2], float(sys.argv[3])
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", f"{name}_slab.json")
lg.fit(folder, name, tile_m, int(sys.argv[4]) if len(sys.argv) > 4 else 200, out)
