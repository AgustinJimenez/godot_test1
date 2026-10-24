"""Gravel with many chips: the fit chose few (big_cover 0, mid 0.12); the photograph is mostly stones (cover forced up)."""
import os
import sys

import limits  # (first)

import chip_gen as cg

cg.RANGES.update({"mid_cover": (0.45, 0.9), "small_cover": (0.6, 1.0), "mid_cm": (3.0, 6.0), "small_cm": (1.2, 2.6),
                  "big_cm": (8.0, 16.0), "big_cover": (0.05, 0.3), "gap": (0.06, 0.18)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "gravel_soil_chips.json")
cg.fit(sys.argv[1], "gravel_soil", 1.0, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
