"""Finds the plates and lobes of a photographed height map with Segment Anything (automatic masks), to replace hand tracing.

  python sam_lobes.py <disp png> <tile cm> <checkpoint> <out png> [out json]

The height is shown to the model as a hillshade (lit from two sides) so that step edges are visible; masks are kept when they are
a plausible lobe (area, solidity) and their step against a ring round them is measured from the height data."""
import json
import sys

import limits  # (first)

import cv2
import numpy as np
import torch
from segment_anything import SamAutomaticMaskGenerator, sam_model_registry

import extract_features as ef


def shade(h):
    sm = cv2.GaussianBlur(h, (0, 0), 1.0)
    gx = cv2.Sobel(sm, cv2.CV_32F, 1, 0) * 14.0
    gy = cv2.Sobel(sm, cv2.CV_32F, 0, 1) * 14.0
    a = np.clip(0.5 - 0.7 * gx - 0.7 * gy, 0, 1)
    b = np.clip(0.5 + 0.7 * gx - 0.7 * gy, 0, 1)
    return (np.dstack([a, b, h]) * 255).astype(np.uint8)


def main():
    h = ef.load(sys.argv[1])
    cm = float(sys.argv[2]) / 1024.0
    image = shade(h)
    sam = sam_model_registry["vit_b"](checkpoint=sys.argv[3]).to("cuda")
    gen = SamAutomaticMaskGenerator(sam, points_per_side=48, pred_iou_thresh=0.80, stability_score_thresh=0.85,
                                    min_mask_region_area=300, crop_n_layers=0)
    masks = gen.generate(image)
    print(len(masks), "raw masks")
    kept = []
    for m in masks:
        seg = m["segmentation"].astype(np.uint8)
        area_cm2 = seg.sum() * cm * cm
        if area_cm2 < 40.0 or area_cm2 > 0.35 * (1024 * cm) ** 2:
            continue
        contours, _ = cv2.findContours(seg, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        c = max(contours, key=len)
        hull = cv2.contourArea(cv2.convexHull(c))
        solidity = cv2.contourArea(c) / max(hull, 1.0)
        inner = cv2.erode(seg, np.ones((9, 9), np.uint8))
        ring = cv2.dilate(seg, np.ones((41, 41), np.uint8)) - cv2.dilate(seg, np.ones((13, 13), np.uint8))
        if inner.sum() < 30 or ring.sum() < 100 or solidity < 0.7:
            continue
        step = float(np.median(h[inner > 0]) - np.median(h[ring > 0]))
        # edge contrast: how strong the gradient is along the outline, against the gradient inside
        sm = cv2.GaussianBlur(h, (0, 0), 1.5)
        mag = np.hypot(cv2.Sobel(sm, cv2.CV_32F, 1, 0), cv2.Sobel(sm, cv2.CV_32F, 0, 1))
        edge = np.ascontiguousarray(np.zeros(seg.shape, np.uint8))
        cv2.drawContours(edge, [c], -1, 1, 3)
        contrast = float(mag[edge > 0].mean() / max(mag[inner > 0].mean(), 1e-6))
        kept.append({"area_cm2": float(area_cm2), "solidity": float(solidity), "step": step, "edge_contrast": contrast,
                     "iou": float(m["predicted_iou"]), "contour": c.reshape(-1, 2)})
    print(len(kept), "candidate lobes (area, solidity)")
    kept.sort(key=lambda k: -k["edge_contrast"])
    overlay = cv2.cvtColor(image[..., 0], cv2.COLOR_GRAY2BGR)
    for i, k in enumerate(kept):
        good = abs(k["step"]) > 0.03 and k["edge_contrast"] > 1.6
        color = (0, 0, 255) if good else (255, 160, 0)
        cv2.polylines(overlay, [k["contour"].reshape(-1, 1, 2)], True, color, 2)
    cv2.imwrite(sys.argv[4], overlay)
    strong = [k for k in kept if abs(k["step"]) > 0.03 and k["edge_contrast"] > 1.6]
    print(len(strong), "strong lobes (red): |step| > 0.03 and outline gradient 1.6x the inside")
    for k in strong[:12]:
        print("  area %.0f cm2  solidity %.2f  step %+.3f  edge contrast %.1f" % (k["area_cm2"], k["solidity"], k["step"], k["edge_contrast"]))
    if len(sys.argv) > 5:
        json.dump([{**k, "contour": k["contour"].tolist()} for k in kept], open(sys.argv[5], "w"))


if __name__ == "__main__":
    main()
