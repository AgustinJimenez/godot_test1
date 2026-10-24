"""Extracts the strong edge curves of a photographed height map as sparse points: x, y (px of the 1024 tile), the direction of the
uphill normal, and the height step across the edge. The bake draws each point as a small step profile along its normal, which gives
the arcs, ridges and plate borders their own crispness.

  python extract_edges.py <disp png> <out bin> <preview png> [lobes json to leave out]

Binary layout (6 bytes a point): x u16, y u16, step u8 (0..255 = 0..STEP_MAX of the normalised height), angle u8 (0..255 = 0..2 pi)."""
import json
import struct
import sys

import limits  # (first)

import cv2
import numpy as np

import extract_features as ef

STEP_MAX = 0.25
CELL = 3          # one point per CELL x CELL cell: about CELL px between points along a curve
KEEP_PERCENT = 94.0
WEAK_PERCENT = 86.0
MIN_LENGTH = 40   # px of edge in a joined chain: shorter ones are pits and pixel noise (the pits are their own feature)


def main():
    h = ef.load(sys.argv[1])
    # only the sharp detail: the soft swells are carried by the coarse grid, taking them again would double them
    sharp = h - cv2.GaussianBlur(h, (0, 0), 7.0)
    sm = cv2.GaussianBlur(sharp, (0, 0), 1.0)
    gx = cv2.Sobel(sm, cv2.CV_32F, 1, 0) / 8.0
    gy = cv2.Sobel(sm, cv2.CV_32F, 0, 1) / 8.0
    mag = np.hypot(gx, gy)
    # non-maximum suppression across the gradient direction (4 quantised directions)
    angle = (np.degrees(np.arctan2(gy, gx)) + 180.0) % 180.0
    nms = np.zeros_like(mag, bool)
    shifts = {0: (0, 1), 45: (-1, 1), 90: (-1, 0), 135: (-1, -1)}
    for centre, (dy, dx) in shifts.items():
        sel = (np.abs(((angle - centre + 90.0) % 180.0) - 90.0) < 22.5)
        a = np.roll(mag, (dy, dx), axis=(0, 1))
        b = np.roll(mag, (-dy, -dx), axis=(0, 1))
        nms |= sel & (mag >= a) & (mag >= b)
    strong = nms & (mag > np.percentile(mag, KEEP_PERCENT))
    weak = nms & (mag > np.percentile(mag, WEAK_PERCENT))
    # join fragments: chains are labelled on a dilated copy (gaps of up to 3 px close), the edge pixels themselves are what is kept
    joined = cv2.dilate(weak.astype(np.uint8), np.ones((5, 5), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(joined, connectivity=8)
    keep = np.zeros_like(weak)
    has_strong = np.zeros(count, bool)
    has_strong[np.unique(labels[strong])] = True
    edge_pixels = np.bincount(labels[weak], minlength=count)
    for i in range(1, count):
        if has_strong[i] and edge_pixels[i] >= MIN_LENGTH:
            keep |= (labels == i) & weak
    # leave out the edges already drawn by the lobe outlines
    if len(sys.argv) > 4:
        mask = np.zeros(h.shape, np.uint8)
        for lobe in json.load(open(sys.argv[4])):
            contour = ef.snap_to_edges(np.array(lobe["contour"], np.int32).reshape(-1, 1, 2), h)
            cv2.polylines(mask, [contour], True, 1, 13)
        keep &= mask == 0
    # leave out the thin cracks (extract_cracks.py draws those as their own crisp line; as edges they made a fuzzy band)
    if len(sys.argv) > 5:
        data = np.fromfile(sys.argv[5], dtype=np.uint8).reshape(-1, 6)
        crack = np.zeros(h.shape, np.uint8)
        for row in data:
            crack[int(row[2]) | (int(row[3]) << 8), int(row[0]) | (int(row[1]) << 8)] = 1
        keep &= cv2.dilate(crack, np.ones((13, 13), np.uint8)) == 0
    # thin to one point a cell, take the step across the edge (smoothed height 6 px either side of it, along the uphill normal)
    wide = cv2.GaussianBlur(sharp, (0, 0), 1.5)
    points = []
    taken = set()
    ys, xs = np.nonzero(keep)
    for y, x in zip(ys, xs):
        cell = (x // CELL, y // CELL)
        if cell in taken:
            continue
        taken.add(cell)
        n = np.array([gx[y, x], gy[y, x]])
        norm = np.linalg.norm(n)
        if norm < 1e-9:
            continue
        n /= norm
        px, py = np.clip(np.round([x + 4 * n[0], y + 4 * n[1]]).astype(int), 0, 1023)
        qx, qy = np.clip(np.round([x - 4 * n[0], y - 4 * n[1]]).astype(int), 0, 1023)
        step = float(wide[py, px] - wide[qy, qx])
        if step <= 0.004:
            continue
        theta = (np.arctan2(n[1], n[0]) + 2.0 * np.pi) % (2.0 * np.pi)
        points.append((int(x), int(y), int(min(step / STEP_MAX, 1.0) * 255), int(theta / (2.0 * np.pi) * 255) & 255))
    print(f"{len(points)} edge points ({6 * len(points) / 1024:.0f} KB), steps median {np.median([p[2] for p in points]) / 255 * STEP_MAX:.3f}")
    with open(sys.argv[2], "wb") as handle:
        for x, y, step, theta in points:
            handle.write(struct.pack("<HHBB", x, y, step, theta))
    preview = cv2.cvtColor((np.clip(h, 0, 1) * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    for x, y, step, theta in points:
        cv2.circle(preview, (x, y), 1, (0, 0, 255), -1)
    cv2.imwrite(sys.argv[3], preview)


if __name__ == "__main__":
    main()
