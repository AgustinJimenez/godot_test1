"""Cedar as thin long overlapping flakes: the flake generator with very small, very elongated cells (see fit_litter.py)."""
import os
import sys

import limits  # (first)

import procedural_bark as pb
import bark_perceptual as perceptual

pb.RANGES.update({"cell_cm": (0.4, 1.6), "cell_aspect": (3.0, 9.0), "len": (1.0, 2.5), "wid": (0.5, 1.4),
                  "angle": (0.0, 0.3), "fiber_amp": (0.0, 0.01), "groove_w": (0.05, 0.06), "split_w": (0.03, 0.04),
                  "cut_depth": (0.0, 0.2), "base_amp": (0.0, 0.3), "size_var": (0.0, 2.0), "flake_cover": (1.1, 1.2), "flake_amp": (0.6, 1.2)})
folder = sys.argv[1]
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "japanese_cedar_bark_flakes.json")
perceptual.fit(folder, "japanese_cedar_bark", 1.0, int(sys.argv[2]) if len(sys.argv) > 2 else 220, out)
print("wrote", out)
