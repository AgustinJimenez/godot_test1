"""Rock face as smooth lumps with creased valleys and rubble in the creases (lump_gen), scaled from the photograph."""
import os
import sys

import limits  # (first)

import lump_gen as lg

lg.RANGES.update({"crease_depth": (0.4, 1.0), "crease_w": (0.03, 0.09), "lump_amp": (0.1, 0.4), "rub_amp": (0.2, 0.6), "rub_reach": (0.3, 0.8), "crease_cm": (22.0, 45.0), "grain_cm": (1.5, 3.0), "grain_amp": (0.0, 0.03)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "rock_face_04_lump.json")
lg.fit(sys.argv[1], "rock_face_04", 2.0, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
