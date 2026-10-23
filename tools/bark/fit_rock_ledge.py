"""Layered rock as stacked ledges with lips and vertical joints (ledge_gen).

  python fit_rock_ledge.py <folder> <name> <tile m> [generations]
"""
import os
import sys

import limits  # (first)

import ledge_gen as lg

lg.RANGES.update({"ledge_cm": (8.0, 22.0), "tilt": (0.0, 0.3), "tone_amp": (0.0, 0.2), "warp_amp": (0.0, 0.5)})
folder, name, tile_m = sys.argv[1], sys.argv[2], float(sys.argv[3])
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", f"{name}_ledge.json")
lg.fit(folder, name, tile_m, int(sys.argv[4]) if len(sys.argv) > 4 else 200, out)
