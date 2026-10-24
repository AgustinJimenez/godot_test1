"""How strong the lobe borders are in a bake against the photograph: mean height-gradient along each snapped lobe outline (the lobes
come from sam_lobes.py and extract_features.py), plus the height step across the border measured the same way in both.

  python lobe_edge_check.py <photo disp png> <bake png (alpha = height)> <boulder_features-style json from sam_lobes>"""
import json
import sys

import limits  # (first)

import cv2
import numpy as np

import extract_features as ef
import measure_boulder as mb


def main():
    photo = ef.load(sys.argv[1])
    bake = mb.load(sys.argv[2], True)
    lobes = json.load(open(sys.argv[3]))
    sigma = float(sys.argv[4]) if len(sys.argv) > 4 else 1.5
    sm = lambda h: cv2.GaussianBlur(h, (0, 0), sigma)
    gp = np.hypot(cv2.Sobel(sm(photo), cv2.CV_32F, 1, 0), cv2.Sobel(sm(photo), cv2.CV_32F, 0, 1)) / 8.0
    gb = np.hypot(cv2.Sobel(sm(bake), cv2.CV_32F, 1, 0), cv2.Sobel(sm(bake), cv2.CV_32F, 0, 1)) / 8.0
    ratios = []
    for lobe in lobes:
        c = np.array(lobe["contour"], np.int32).reshape(-1, 1, 2)
        c = ef.snap_to_edges(c, photo)
        pts = c.reshape(-1, 2)
        a = gp[np.clip(pts[:, 1], 0, 1023), np.clip(pts[:, 0], 0, 1023)].mean()
        b = gb[np.clip(pts[:, 1], 0, 1023), np.clip(pts[:, 0], 0, 1023)].mean()
        ratios.append(b / max(a, 1e-9))
        print(f"  lobe area {lobe['area_cm2']:.0f} cm2: gradient on the outline photo {a:.4f}  bake {b:.4f}  (bake is {100 * b / a:.0f} % of the photo)")
    print(f"sigma {sigma}: the bake's lobe borders are {100 * np.mean(ratios):.0f} % as strong as the photograph's")


if __name__ == "__main__":
    main()
