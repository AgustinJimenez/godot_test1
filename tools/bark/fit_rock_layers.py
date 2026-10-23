"""Layered rock (horizontal ledges and joints): the blocks-and-cracks generator with the strata forced horizontal and strong, no pits.

  python fit_rock_layers.py <folder> <name> <tile m> [generations]
"""
import os
import sys

import limits  # (first)

import rock_gen as rg

rg.RANGES.update({"strata_angle": (0.0, 0.12), "strata_amp": (0.12, 0.4), "strata_cm": (8.0, 30.0),
                  "pit_cover": (0.0, 0.01), "pit_depth": (0.0, 0.05), "block_var": (0.2, 0.6),
                  "cell_cm": (15.0, 50.0), "crack_depth": (0.2, 0.7)})
folder, name, tile_m = sys.argv[1], sys.argv[2], float(sys.argv[3])
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", f"{name}_layers.json")
rg.fit(folder, name, tile_m, int(sys.argv[4]) if len(sys.argv) > 4 else 200, out)
