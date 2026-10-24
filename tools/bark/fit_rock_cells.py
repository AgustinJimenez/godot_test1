"""Rock broken into rounded cells by a crack network (pitted mossy rock): plate_gen with round cells and thin cracks.

  python fit_rock_cells.py <folder> <name> <tile m> [generations]
"""
import os
import sys

import limits  # (first)

import fit_bark
import plate_gen as pg

pg.RANGES.update({"cell_cm": (9.0, 14.0), "stretch": (1.0, 1.1), "crack_w": (0.02, 0.07), "crack_depth": (0.2, 0.45),
                  "lip": (0.05, 0.25), "z_var": (0.05, 0.25), "tilt": (0.0, 0.1), "warp_amp": (0.1, 0.4),
                  "warp_cm": (6.0, 20.0), "fine_amp": (0.03, 0.12), "fine_cm": (1.0, 2.2), "rag_amp": (0.05, 0.3)})
folder, name, tile_m = sys.argv[1], sys.argv[2], float(sys.argv[3])
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", f"{name}_cells.json")
pg.fit(folder, name, tile_m, int(sys.argv[4]) if len(sys.argv) > 4 else 200, out)
