"""Rock face as smooth lumps with creased valleys and rubble in the creases (lump_gen).

  python fit_rock_lump.py <folder> <name> <tile m> [generations] [plain]

`plain`: mottled rock with no crease (boulders): creases and rubble nearly off, lumps and grain free.
"""
import os
import sys

import limits  # (first)

import fit_bark
import lump_gen as lg

lg.RANGES.update({"crease_depth": (0.4, 1.0), "crease_w": (0.03, 0.09), "lump_amp": (0.1, 0.4),
                  "rub_amp": (0.2, 0.6), "rub_reach": (0.3, 0.8), "crease_cm": (22.0, 45.0),
                  "grain_cm": (1.5, 3.0), "grain_amp": (0.0, 0.03)})
if "plain" in sys.argv[5:]:
    lg.RANGES.update({"crease_depth": (0.0, 0.08), "crease_w": (0.02, 0.05), "rub_amp": (0.0, 0.05),
                      "lump_amp": (0.2, 0.9), "lump_cm": (15.0, 60.0), "grain_cm": (1.5, 4.0),
                      "grain_amp": (0.02, 0.1), "warp_amp": (0.3, 1.0)})
folder, name, tile_m = sys.argv[1], sys.argv[2], float(sys.argv[3])
fit_bark.download(name, folder)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", f"{name}_lump.json")
lg.fit(folder, name, tile_m, int(sys.argv[4]) if len(sys.argv) > 4 else 200, out)
