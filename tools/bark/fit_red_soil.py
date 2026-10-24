"""Red gravelly soil as fine crumbled earth: no twigs, a few pebbles; the red lumps are colour, not relief."""
import os
import sys

import limits  # (first)

import soil_gen as sg

sg.RANGES.update({"twig_cover": (0.0, 0.001), "twig_amp": (0.0, 0.01), "pebble_cover": (0.05, 0.4),
                  "pebble_size": (0.1, 0.3), "clod_amp": (0.1, 0.4), "clod_cm": (8.0, 25.0), "crumb_amp": (0.0, 0.005), "dust_amp": (0.05, 0.25), "grain_amp": (0.1, 0.3)})
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", "red_soil_soilgen.json")
sg.fit(sys.argv[1], "red_soil", 1.0, int(sys.argv[2]) if len(sys.argv) > 2 else 200, out)
