#!/usr/bin/env python3
"""Compares the pictures of `visual_check.sh` with the accepted ones.

usage: visual_compare.py CURRENT_DIR BASELINE_DIR DIFF_DIR [--accept]
Every PNG in CURRENT_DIR is shrunk to 640 x 360 and compared with the one of the same name in BASELINE_DIR:
the mean difference (0..255) and the share of pixels that differ by more than 24. A picture is a FAIL over MEAN_LIMIT or
SHARE_LIMIT; the difference is written to DIFF_DIR as a picture (the difference tripled). `--accept` stores the shrunk current
pictures as the new baseline. Prints one line a picture and VISUAL_CHECK PASS/FAIL; exit 1 on a failure.
"""
import os
import sys

import numpy as np
from PIL import Image

MEAN_LIMIT = 4.0
SHARE_LIMIT = 0.08
SIZE = (640, 360)


def load(path):
    return Image.open(path).convert("RGB").resize(SIZE, Image.LANCZOS)


def main():
    current, baseline, diffs = sys.argv[1:4]
    accept = "--accept" in sys.argv
    os.makedirs(baseline, exist_ok=True)
    os.makedirs(diffs, exist_ok=True)
    failed = 0
    for name in sorted(os.listdir(current)):
        if not name.endswith(".png"):
            continue
        picture = load(os.path.join(current, name))
        target = os.path.join(baseline, name)
        if accept or not os.path.exists(target):
            picture.save(target)
            print("ACCEPT %s" % name)
            continue
        old = load(target)
        delta = np.abs(np.asarray(picture, dtype=np.int16) - np.asarray(old, dtype=np.int16))
        mean = float(delta.mean())
        share = float((delta.max(axis=2) > 24).mean())
        bad = mean > MEAN_LIMIT or share > SHARE_LIMIT
        if bad:
            failed += 1
            Image.fromarray(np.clip(delta * 3, 0, 255).astype(np.uint8)).save(os.path.join(diffs, name))
        print("%s %s mean=%.2f differing=%.1f%%" % ("FAIL" if bad else "PASS", name, mean, share * 100.0))
    print("VISUAL_CHECK %s" % ("FAIL (%d)" % failed if failed else "PASS"))
    sys.exit(1 if failed else 0)


main()
