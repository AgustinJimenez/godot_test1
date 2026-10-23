"""Pine as long narrow flakes (the flake generator with the flakes forced tall and thin, blunt ends, no pits)."""
import os
import sys

import limits  # (first)

import procedural_bark as pb
import bark_perceptual as perceptual

pb.RANGES.update({"cell_cm": (1.4, 2.4), "cell_aspect": (2.0, 3.2), "len": (1.0, 2.2), "wid": (0.5, 1.0),
                  "tip": (2.0, 3.5), "block": (0.2, 0.8), "angle": (0.0, 0.25), "flake_cover": (1.0, 1.2),
                  "groove_cover": (0.5, 0.9), "groove_w": (0.12, 0.4), "cut_depth": (0.15, 0.3),
                  "rag_amp": (0.15, 0.3), "base_amp": (0.0, 0.2)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "pine_bark_long.json")
perceptual.fit(sys.argv[1], "pine_bark", 2.0, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
