"""Sakura bark with the flake generator turned wide and flat (short horizontal strips), SW 0.5, judged on the sheet."""
import os
import sys

import limits  # (first)

import procedural_bark as pb
import bark_perceptual as perceptual

pb.RANGES.update({"cell_cm": (0.8, 2.0), "cell_aspect": (0.25, 0.6), "len": (0.8, 2.0), "wid": (0.6, 1.4),
                  "tip": (1.5, 3.0), "angle": (0.0, 0.2), "flake_cover": (1.0, 1.2), "groove_cover": (0.3, 0.8),
                  "base_amp": (0.0, 0.1), "cut_depth": (0.1, 0.3)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "sakura_bark_flakes.json")
perceptual.fit(sys.argv[1], "sakura_bark", 1.6, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
