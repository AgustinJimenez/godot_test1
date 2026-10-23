"""Rock face: smooth lumps with crevices and pockets of rubble (no polka-dot pits): pits off, rubble forced on."""
import os
import sys

import limits  # (first)

import rock_gen as rg

rg.RANGES.update({"pit_cover": (0.0, 0.02), "rub_cover": (0.3, 1.2), "rub_amp": (0.2, 0.8), "crack_depth": (0.3, 1.0)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "rock_face_04_rubble.json")
rg.fit(sys.argv[1], "rock_face_04", 2.0, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
