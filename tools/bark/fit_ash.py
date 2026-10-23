"""Ash: a lattice of diagonal ridges: the flake generator with flakes turned both ways (angle up to 1.6), short and wide."""
import os
import sys

import limits  # (first)

import procedural_bark as pb
import bark_perceptual as perceptual

pb.RANGES.update({"cell_cm": (0.6, 3.0), "cell_aspect": (1.0, 3.0), "len": (0.7, 1.6), "wid": (0.4, 1.0),
                  "angle": (0.6, 1.6), "tip": (1.0, 2.5), "fiber_amp": (0.0, 0.01), "cut_depth": (0.0, 0.2),
                  "base_amp": (0.0, 0.3), "flake_cover": (1.1, 1.2)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "tree_bark_03_ridges.json")
perceptual.fit(sys.argv[1], "tree_bark_03", 1.0, int(sys.argv[2]) if len(sys.argv) > 2 else 220, out)
print("wrote", out)
