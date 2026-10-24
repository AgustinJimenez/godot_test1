"""Oak boards with a coarser grain, fewer knots, softer seams (judged on the plain-square sheet)."""
import os
import sys

import limits  # (first)

import wood_gen as wg

wg.RANGES.update({"grain_cm": (0.9, 1.5), "knot_cover": (0.0, 0.12), "seam_depth": (0.0, 0.25), "seam_w": (0.01, 0.05),
                  "board_var": (0.2, 0.6), "board_tone": (0.05, 0.3)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "oak_wood_planks_wood2.json")
wg.fit(sys.argv[1], "oak_wood_planks", 1.2, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
