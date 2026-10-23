"""Pine as plates side by side (plate_gen): plates the size of the photo's (about 8 x 20 cm), flat, with thin cracks."""
import os
import sys

import limits  # (first)

import plate_gen as pg
import bark_perceptual as perceptual
import rock_gen as rg

pg.RANGES.update({"cell_cm": (3.0, 6.0), "stretch": (1.8, 3.5), "tilt": (0.0, 0.25), "z_var": (0.15, 0.6),
                  "lip": (0.02, 0.15), "crack_w": (0.02, 0.1), "fine_amp": (0.0, 0.08)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "pine_bark_plate.json")
pg.fit(sys.argv[1], "pine_bark", 2.0, int(sys.argv[2]) if len(sys.argv) > 2 else 220, out)
