"""Finds the thin dark cracks of a photographed rock: a multi-scale Hessian valley detector on the colour's luminance and on the
ambient-occlusion map (cracks are thin dark lines in both), hysteresis, thinning, long chains only. Stores the crack pixels as
(x u16, y u16, strength u8, width u8) and writes an overlay.

  python extract_cracks.py <folder/name prefix> <out bin> <overlay png>"""
import struct
import sys

import limits  # (first)

import cv2
import numpy as np

import extract_features as ef

N = 1024
SIGMAS = (0.9, 1.4, 2.0)
MIN_EXTENT = 38  # px (7 cm): shorter pieces are lichen texture, not cracks
THIN = 13.0  # at most this many pixels of (dilated) area per pixel of extent: a line, not a patch


def valley(img):
    """Strength of thin dark lines: the large positive Hessian eigenvalue, kept where the other eigenvalue is small."""
    best = np.zeros_like(img)
    width = np.zeros_like(img)
    for s in SIGMAS:
        g = cv2.GaussianBlur(img, (0, 0), s)
        hxx = cv2.Sobel(g, cv2.CV_32F, 2, 0, ksize=3)
        hyy = cv2.Sobel(g, cv2.CV_32F, 0, 2, ksize=3)
        hxy = cv2.Sobel(g, cv2.CV_32F, 1, 1, ksize=3)
        tmp = np.sqrt(((hxx - hyy) / 2) ** 2 + hxy ** 2)
        l1 = (hxx + hyy) / 2 + tmp  # larger eigenvalue: positive across a dark line
        l2 = (hxx + hyy) / 2 - tmp
        r = np.maximum(l1, 0) * s * s * np.exp(-((np.abs(l2) / np.maximum(l1, 1e-6)) ** 2) / (2 * 0.45 ** 2))
        upd = r > best
        best = np.where(upd, r, best)
        width = np.where(upd, s, width)
    return best, width


def zscore(x):
    return (x - np.median(x)) / (1.4826 * np.median(np.abs(x - np.median(x))) + 1e-9)


def main():
    prefix = sys.argv[1]
    col = cv2.resize(cv2.imread(prefix + "_diff.jpg"), (N, N), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
    lum = col.mean(axis=2)
    ao = cv2.resize(cv2.imread(prefix + "_ao.jpg", 0), (N, N), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
    vl, wl = valley(lum)
    va, wa = valley(ao)
    score = np.minimum(zscore(vl), zscore(va)) * 0.5 + 0.5 * np.maximum(zscore(vl), zscore(va))  # (both agree, one may be stronger)
    width = np.where(va > vl * 0.3, wa, wl)
    hi, lo = np.percentile(score, 99.0), np.percentile(score, 94.0)
    strong = score > hi
    weak = score > lo
    joined = cv2.dilate(weak.astype(np.uint8), np.ones((3, 3), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(joined, connectivity=8)
    has_strong = np.zeros(count, bool)
    has_strong[np.unique(labels[strong])] = True
    keep = np.zeros((N, N), np.uint8)
    for i in range(1, count):
        if not has_strong[i]:
            continue
        x, y, w, h, area = stats[i]
        extent = max(w, h)
        if extent >= MIN_EXTENT and area >= 60 and area <= THIN * extent and area / (w * h + 1) < 0.4:  # long and thin, not a blob
            keep[(labels == i) & weak] = 1
    # leave out the lobe outlines (the lobes and the edge layer draw those)
    hgt = ef.load(prefix + "_disp.png")
    rows, _ = ef.lobes_from_json("fits/sam_boulder_kept.json", hgt)
    outline = np.zeros((N, N), np.uint8)
    for row in rows:
        pts = (np.array(row[8:104], dtype=np.float64).reshape(-1, 2) * N).astype(np.int32).reshape(-1, 1, 2)
        cv2.polylines(outline, [pts], True, 1, 17)
    keep[outline > 0] = 0
    # after removing the outlines short pieces remain: keep only chains that are still long
    n2, l2, st2, _ = cv2.connectedComponentsWithStats(cv2.dilate(keep, np.ones((3, 3), np.uint8)), connectivity=8)
    for i in range(1, n2):
        if max(st2[i, 2], st2[i, 3]) < MIN_EXTENT:
            keep[(l2 == i)] = 0
    # thin to a one pixel skeleton by non-maximum suppression across the ridge
    thin = keep.copy()
    sm = cv2.GaussianBlur(score, (0, 0), 0.8)
    gx = cv2.Sobel(sm, cv2.CV_32F, 1, 0)
    gy = cv2.Sobel(sm, cv2.CV_32F, 0, 1)
    ang = (np.degrees(np.arctan2(gy, gx)) + 180) % 180
    nms = np.zeros((N, N), bool)
    for centre, (dy, dx) in {0: (0, 1), 45: (-1, 1), 90: (-1, 0), 135: (-1, -1)}.items():
        sel = np.abs(((ang - centre + 90) % 180) - 90) < 22.5
        nms |= sel & (sm >= np.roll(sm, (dy, dx), (0, 1))) & (sm >= np.roll(sm, (-dy, -dx), (0, 1)))
    thin = (keep > 0) & nms
    thin = cv2.dilate(thin.astype(np.uint8), np.ones((2, 2), np.uint8)) > 0  # (close the one pixel gaps)
    ys, xs = np.nonzero(thin)
    pts = []
    for y, x in zip(ys, xs):
        pts.append((int(x), int(y), int(np.clip(score[y, x] / 12.0, 0, 1) * 255), int(np.clip(width[y, x] / 2.0, 0, 1) * 255)))
    with open(sys.argv[2], "wb") as handle:
        for x, y, s, w in pts:
            handle.write(struct.pack("<HHBB", x, y, s, w))
    over = (col * 255).astype(np.uint8)
    over[thin] = (0, 0, 255)
    cv2.imwrite(sys.argv[3], np.hstack([(col * 255).astype(np.uint8), over]))
    print("%d crack pixels (%d KB), %.2f %% of the tile; strength median %.0f" % (len(pts), len(pts) * 6 // 1024, 100 * thin.mean(), np.median([p[2] for p in pts])))


if __name__ == "__main__":
    main()
