"""Ash as long narrow ridged flakes (the flake generator, flakes tall and thin, blunt ends), judged on the plain square."""
import os
import sys

import limits  # (first)

import procedural_bark as pb
import bark_perceptual as perceptual

pb.RANGES.update({"cell_cm": (0.65, 1.0), "cell_aspect": (2.0, 3.5), "len": (0.9, 1.8), "wid": (0.5, 0.9),
                  "tip": (1.4, 2.4), "block": (0.0, 0.1), "angle": (0.2, 0.8), "warp_cm": (0.5, 1.2), "warp_scale_cm": (3.0, 9.0), "flake_cover": (1.0, 1.2),
                  "groove_cover": (0.5, 0.9), "groove_w": (0.12, 0.4), "cut_depth": (0.15, 0.3),
                  "rag_amp": (0.1, 0.3), "base_amp": (0.0, 0.2)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "tree_bark_03_long.json")
perceptual.fit(sys.argv[1], "tree_bark_03", 1.0, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
