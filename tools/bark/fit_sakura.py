"""Sakura bark as smooth bark with DENSE short horizontal dashes and vertical splits (smooth_gen), scale capped."""
import os
import sys

import limits  # (first)

import smooth_gen as sg

sg.RANGES.update({"swell_amp": (0.0, 0.08), "dash_cell_cm": (2.5, 4.5), "dash_cover": (0.6, 0.95),
                  "dash_w_cm": (1.0, 2.6), "dash_h_cm": (0.08, 0.2), "dash_depth": (0.3, 0.8),
                  "grain_amp": (0.05, 0.2), "grain_cm": (0.3, 0.6), "split_cm": (10.0, 25.0),
                  "split_cover": (0.2, 0.7), "split_depth": (0.3, 0.9), "split_w": (0.1, 0.3)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "sakura_bark_smooth.json")
sg.fit(sys.argv[1], "sakura_bark", 1.6, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
