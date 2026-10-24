"""Sakura bark as many thin stacked ledges (ledge_gen turned fine), LOW contrast, with vertical splits from smooth_gen.

  python fit_sakura_ledge.py <folder> [generations]
The ledge layer is fitted (contrast capped); the splits are added afterwards by smooth_gen's own split layer (see compare).
"""
import os
import sys

import limits  # (first)

import ledge_gen as lg

lg.RANGES.update({"ledge_cm": (0.6, 1.6), "ledge_var": (0.3, 0.9), "tilt": (0.0, 0.2), "lip_w": (0.1, 0.4),
                  "lip_depth": (0.03, 0.12), "block_cm": (2.0, 8.0), "joint_cover": (0.3, 1.0), "joint_depth": (0.03, 0.15),
                  "rag_cm": (2.0, 5.0), "rag_amp": (0.3, 0.8), "warp_amp": (0.0, 0.3), "tone_amp": (0.0, 0.05),
                  "rub_amp": (0.0, 0.03), "grain_amp": (0.0, 0.03)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "sakura_bark_ledge.json")
lg.fit(sys.argv[1], "sakura_bark", 1.6, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
