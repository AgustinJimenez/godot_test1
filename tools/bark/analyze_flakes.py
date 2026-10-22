"""Measures a photographed bark's height map flake by flake (Poly Haven, CC0).

Usage: python analyze_flakes.py <folder> <name> <tile metres> [out folder]
  <folder>/<name>_disp.png (height) and <name>_diff.jpg (colour). Prints the numbers a procedural
generator has to match and writes an overlay picture of the segmentation (flakes coloured).
Numbers are in centimetres on the real bark (the tile is `tile metres` wide).
"""
import json
import sys

import cv2
import numpy as np
from scipy import ndimage


def load_height(path):
    h = cv2.imread(path, cv2.IMREAD_UNCHANGED).astype(np.float32)
    if h.ndim == 3:
        h = h.mean(axis=2)
    h -= h.min()
    return h / max(h.max(), 1e-6)


def segment(height, scale_px):
    """Flakes = regions higher than their surroundings; the gaps between them are the lower lines."""
    smooth = cv2.GaussianBlur(height, (0, 0), 1.2)
    local = cv2.GaussianBlur(height, (0, 0), scale_px)
    mask = (smooth > local - 0.015).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    # split touching flakes: distance transform peaks
    dist = ndimage.distance_transform_edt(mask)
    peaks = (dist == ndimage.maximum_filter(dist, size=9)) & (dist > 2.0)
    markers, count = ndimage.label(peaks)
    labels = cv2.watershed(cv2.cvtColor((height * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR),
                           np.where(mask > 0, markers, 0).astype(np.int32) + 0)
    labels[labels < 0] = 0
    return labels, count


def flake_stats(labels, count, cm_per_px):
    areas, lengths, widths, angles = [], [], [], []
    for index in range(1, count + 1):
        ys, xs = np.nonzero(labels == index)
        if len(xs) < 25:
            continue
        coords = np.stack([xs, ys], axis=1).astype(np.float64)
        centred = coords - coords.mean(axis=0)
        cov = np.cov(centred.T)
        values, vectors = np.linalg.eigh(cov)
        long_axis = vectors[:, 1]
        areas.append(len(xs) * cm_per_px ** 2)
        lengths.append(4.0 * np.sqrt(max(values[1], 1e-9)) * cm_per_px)
        widths.append(4.0 * np.sqrt(max(values[0], 1e-9)) * cm_per_px)
        angles.append(np.degrees(np.arctan2(long_axis[1], long_axis[0])) % 180.0)
    return np.array(areas), np.array(lengths), np.array(widths), np.array(angles)


def main():
    folder, name, tile_m = sys.argv[1], sys.argv[2], float(sys.argv[3])
    out = sys.argv[4] if len(sys.argv) > 4 else folder
    height = load_height(f"{folder}/{name}_disp.png")
    size = height.shape[0]
    cm_per_px = tile_m * 100.0 / size
    scale_px = 14.0 / cm_per_px * 1.0  # a neighbourhood of about 14 cm
    labels, count = segment(height, scale_px)
    areas, lengths, widths, angles = flake_stats(labels, count, cm_per_px)
    along = np.mean(np.abs(np.cos(np.radians(angles - 90.0))))  # 1: flakes run up and down the trunk
    result = {
        "name": name,
        "tile_m": tile_m,
        "flakes": int(len(areas)),
        "flakes_per_m2": float(len(areas) / tile_m ** 2),
        "area_cm2": {"p10": float(np.percentile(areas, 10)), "median": float(np.median(areas)),
                     "p90": float(np.percentile(areas, 90))},
        "length_cm": {"median": float(np.median(lengths)), "p90": float(np.percentile(lengths, 90))},
        "width_cm": {"median": float(np.median(widths)), "p90": float(np.percentile(widths, 90))},
        "aspect_median": float(np.median(lengths / np.maximum(widths, 0.01))),
        "up_down_share": float(along),
        "height_sd": float(height.std()),
        "height_p05_p50_p95": [float(np.percentile(height, q)) for q in (5, 50, 95)],
        "covered_by_flakes": float((labels > 0).mean()),
    }
    print(json.dumps(result, indent=1))
    overlay = cv2.cvtColor((height * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    rng = np.random.default_rng(3)
    palette = rng.integers(60, 255, size=(count + 2, 3)).astype(np.uint8)
    coloured = palette[np.clip(labels, 0, count + 1)]
    coloured[labels <= 0] = 0
    overlay = cv2.addWeighted(overlay, 0.45, coloured, 0.55, 0)
    cv2.imwrite(f"{out}/{name}_segments.png", cv2.resize(overlay, (640, 640)))


if __name__ == "__main__":
    main()
