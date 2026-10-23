"""Pine as long grooved ridges broken by short cross cracks (ridge_gen): the photograph's grooves run along the trunk."""
import os
import sys

import limits  # (first)

import ridge_gen as rgn

rgn.RANGES.update({"ridge_cm": (2.5, 6.0), "groove_w": (0.1, 0.35), "groove_depth": (0.5, 0.95), "wander_amp": (0.5, 2.0),
                   "cut_cm": (4.0, 14.0), "cut_cover": (0.2, 0.7), "cut_depth": (0.3, 0.9), "fine_amp": (0.0, 0.05)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "pine_bark_ridge.json")
rgn.fit(sys.argv[1], "pine_bark", 2.0, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
