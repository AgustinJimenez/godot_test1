"""Colour contrast at the 52 stored pit positions: mean luminance in a 2 px disc minus the mean in a 6 to 10 px ring, photograph and bake.
  python pit_contrast_check.py <bake png>"""
import re
import sys

import limits  # (first)

import cv2
import numpy as np

D = "bark_downloads/rock_boulder_dry_"
col = cv2.resize(cv2.imread(D + "diff.jpg"), (1024, 1024), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
ph = col.mean(axis=2)
bk = cv2.imread(sys.argv[1], cv2.IMREAD_UNCHANGED)[..., :3].astype(np.float32).mean(axis=2) / 255.0
text = open("../../systems/world_gen/boulder_features.gd", encoding="utf8").read()
arr = np.array([float(v) for v in re.findall(r"-?\d+\.\d+", text[text.index("func specks"):text.index("func swell")])]).reshape(-1, 4)
yy, xx = np.mgrid[0:1024, 0:1024]


def contrast(img, x, y):
    r = np.hypot(xx[max(y - 12, 0):y + 13, max(x - 12, 0):x + 13] - x, yy[max(y - 12, 0):y + 13, max(x - 12, 0):x + 13] - y)
    patch = img[max(y - 12, 0):y + 13, max(x - 12, 0):x + 13]
    return patch[r <= 2].mean() - patch[(r >= 6) & (r <= 10)].mean()


cp, cb = [], []
for x, y, rad, depth in arr:
    ix, iy = int(x * 1024), int(y * 1024)
    if 12 <= ix < 1012 and 12 <= iy < 1012:
        cp.append(contrast(ph, ix, iy))
        cb.append(contrast(bk, ix, iy))
cp, cb = np.array(cp), np.array(cb)
print("%d pits: colour contrast (disc minus ring, luminance 0..1): photograph mean %+.3f (p10 %+.3f, p90 %+.3f) | bake mean %+.3f (p10 %+.3f, p90 %+.3f) | ratio %.1fx"
      % (len(cp), cp.mean(), np.percentile(cp, 10), np.percentile(cp, 90), cb.mean(), np.percentile(cb, 10), np.percentile(cb, 90), cb.mean() / cp.mean()))
