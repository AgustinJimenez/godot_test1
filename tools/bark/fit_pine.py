"""Pine: blunt, square-topped plates (not pointed flakes): the block share forced up, tips blunt, plates taller than wide."""
import os
import sys

import limits  # (first)

import procedural_bark as pb
import bark_perceptual as perceptual

pb.RANGES.update({"cell_cm": (3.0, 8.0), "cell_aspect": (1.3, 3.0), "len": (0.8, 1.6), "wid": (0.5, 1.1),
                  "tip": (2.5, 3.5), "block": (0.5, 1.0), "angle": (0.0, 0.4), "flake_cover": (1.0, 1.2),
                  "base_amp": (0.0, 0.3)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "pine_bark_square.json")
perceptual.fit(sys.argv[1], "pine_bark", 2.0, int(sys.argv[2]) if len(sys.argv) > 2 else 220, out)
