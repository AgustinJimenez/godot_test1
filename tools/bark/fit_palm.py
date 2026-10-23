"""Palm: soft horizontal ring bands (one or two per 40 cm, gently wavy) over vertical streaks; the rings forced up."""
import os
import sys

import limits  # (first)

import ring_gen as rg_

rg_.RANGES.update({"ring_cm": (25.0, 50.0), "ring_var": (0.0, 0.5), "ring_w": (0.08, 0.3), "ring_amp": (0.25, 0.6),
                   "ring_wave": (0.0, 0.25), "ring_wave_cm": (40.0, 120.0), "blotch_amp": (0.0, 0.15),
                   "fibre_amp": (0.0, 0.2), "blotch_cm": (10.0, 40.0)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "palm_tree_bark_ring.json")
rg_.fit(sys.argv[1], "palm_tree_bark", 1.3, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
