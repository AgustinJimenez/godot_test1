"""Palm as the flake generator with long thin flakes laid in horizontal bands is not possible: rings stay with ring_gen.
This tries ring_gen with the sliced loss and the measured ring spacing, judged on the sheet."""
import os
import sys

import limits  # (first)

import ring_gen as rgn

rgn.RANGES.update({"ring_cm": (20.0, 32.0), "ring_var": (0.0, 0.4), "ring_w": (0.1, 0.4), "ring_amp": (0.25, 0.6),
                   "fibre_amp": (0.1, 0.3), "fibre_cm": (0.5, 1.5), "fibre_len_cm": (15.0, 60.0)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "palm_tree_bark_ring.json")
rgn.fit(sys.argv[1], "palm_tree_bark", 2.6, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
