"""Fits the FLAKE generator as a leaf-litter / needle generator: the same overlapping pointed shapes, but turned in
any direction (angle up to a full turn), small, isotropic spacing, no grooves and no swelling.

  python fit_litter.py <name> <tile metres> [generations] [folder]    (the maps must be in the folder: see fit_bark.py)
"""
import os
import sys

import limits  # (first)

import procedural_bark as pb
import bark_perceptual as perceptual
import fit_bark

name, tile_m = sys.argv[1], float(sys.argv[2])
generations = int(sys.argv[3]) if len(sys.argv) > 3 else 200
folder = sys.argv[4] if len(sys.argv) > 4 else "bark_downloads"
pb.RANGES.update({"cell_cm": (0.8, 2.2), "cell_aspect": (0.8, 2.0), "angle": (3.0, 6.3), "len": (1.0, 2.4),
                  "wid": (0.3, 0.8), "groove_w": (0.05, 0.06), "split_w": (0.03, 0.04), "cut_depth": (0.0, 0.1),
                  "fiber_amp": (0.0, 0.01), "flake_cover": (1.15, 1.25), "base_amp": (0.0, 0.02), "base_stretch": (1.0, 1.1), "split_cover": (0.0, 0.02), "groove_cover": (0.1, 0.12), "size_var": (0.0, 2.0)})
fit_bark.download(name, folder)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", f"{name}_litter.json")
perceptual.fit(folder, name, tile_m, generations, out)
print("wrote", out)
