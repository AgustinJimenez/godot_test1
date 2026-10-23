"""Rock face with the straight-crack network: like fit_rock_lump.py but the Voronoi cracks are free and the creases weaker.

  python fit_rock_lump_big.py <folder> <name> <tile m> [generations]
"""
import os
import sys

import limits  # (first)

import fit_bark
import lump_gen as lg

lg.RANGES.update({"crease_depth": (0.1, 0.6), "crease_w": (0.03, 0.09), "lump_amp": (0.1, 0.5),
                  "rub_amp": (0.1, 0.6), "rub_reach": (0.3, 0.8), "crease_cm": (22.0, 60.0),
                  "grain_cm": (1.5, 3.0), "grain_amp": (0.0, 0.03), "vor_depth": (0.2, 0.7),
                  "vor_cm": (30.0, 90.0), "mid_amp": (0.1, 0.5)})
folder, name, tile_m = sys.argv[1], sys.argv[2], float(sys.argv[3])
fit_bark.download(name, folder)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", f"{name}_lump.json")
lg.fit(folder, name, tile_m, int(sys.argv[4]) if len(sys.argv) > 4 else 200, out)
