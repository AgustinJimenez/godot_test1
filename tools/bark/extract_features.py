"""Extracts the sparse features of a photographed height map: the raised lobes (plates) as smooth polygons with a step height,
and the small pits and bumps as points, so a shader can draw them at the photograph's own places (deterministic, a few KB).

  python extract_features.py <disp png> <tile cm> <out gd> <overlay png>

Writes a generated GDScript file (class BoulderFeatures: LOBES = rows of [cx, cy, step, soft, then 48 x,y vertices], SPECKS = rows of
[x, y, radius, depth]; all positions in tile units 0..1, radii in tile units, heights in the picture's own 0..1)."""
import sys

import limits  # (first)

import cv2
import numpy as np
from scipy import ndimage

VERTS = 48
FOURIER = 14


def load(path):
    image = cv2.imread(path, cv2.IMREAD_UNCHANGED).astype(np.float32)
    if image.ndim == 3:
        image = image.mean(axis=2)
    image = cv2.resize(image, (1024, 1024), interpolation=cv2.INTER_AREA)
    # the photograph's height map has flat patches (a clipped value over whole areas): fill them in from their surroundings
    flat = (np.abs(cv2.Laplacian(image, cv2.CV_32F)) < 1e-4 * (image.max() - image.min())).astype(np.uint8)
    flat = cv2.morphologyEx(flat, cv2.MORPH_OPEN, np.ones((7, 7), np.uint8))
    flat = cv2.dilate(flat, np.ones((5, 5), np.uint8))
    if flat.any():
        scale = image.max() - image.min()
        as16 = ((image - image.min()) / scale * 65535.0).astype(np.uint16)
        image = cv2.inpaint(as16, flat, 7, cv2.INPAINT_TELEA).astype(np.float32) / 65535.0 * scale + image.min()
    return (image - image.min()) / (image.max() - image.min())  # (no clipping: the brightest spots must not go flat)


def smooth_outline(contour):
    """Closed contour (N, 2) -> VERTS points of its low-pass Fourier version (smooth, no corners)."""
    pts = contour.reshape(-1, 2).astype(np.float64)
    seg = np.hypot(*np.diff(np.vstack([pts, pts[:1]]), axis=0).T)
    t = np.concatenate([[0.0], np.cumsum(seg)])[:-1]
    t = t / (t[-1] + seg[-1])
    even = np.linspace(0.0, 1.0, 256, endpoint=False)
    x = np.interp(even, t, pts[:, 0], period=1.0)
    y = np.interp(even, t, pts[:, 1], period=1.0)
    z = np.fft.fft(x + 1j * y) / len(even)
    keep = np.zeros_like(z)
    keep[:FOURIER + 1] = z[:FOURIER + 1]
    keep[-FOURIER:] = z[-FOURIER:]
    smooth = np.fft.ifft(keep * len(even))
    idx = np.linspace(0, len(even), VERTS, endpoint=False).astype(int)
    return np.stack([smooth.real[idx], smooth.imag[idx]], axis=1)


# Lobes traced by hand on fits/trace_grid.png (1536 px picture of the lit height): outline points in that picture's pixels.
GRID_PX = 1536.0
HAND_LOBES = {
    "pill": [(770, 430), (800, 400), (840, 398), (860, 430), (868, 500), (872, 540), (860, 590), (835, 620), (800, 628), (760, 610),
             (730, 595), (722, 570), (740, 545), (752, 510), (755, 460)],
    "snake": [(1085, 315), (1110, 280), (1150, 262), (1220, 255), (1265, 262), (1295, 235), (1315, 205), (1325, 235), (1355, 275),
              (1372, 320), (1355, 345), (1320, 358), (1270, 355), (1200, 347), (1150, 350), (1140, 380), (1135, 440), (1138, 500),
              (1125, 545), (1100, 555), (1085, 530), (1088, 470), (1098, 415), (1100, 365), (1088, 340)],
    "right": [(1135, 520), (1160, 502), (1200, 508), (1235, 530), (1252, 570), (1248, 610), (1225, 632), (1190, 632), (1165, 615),
              (1150, 590), (1140, 550)],
    "left_big": [(105, 585), (150, 580), (200, 585), (250, 600), (290, 585), (330, 585), (352, 610), (350, 660), (335, 700), (345, 780),
                 (300, 790), (240, 795), (190, 780), (150, 750), (135, 700), (130, 650), (110, 625)],
    "arch": [(710, 880), (730, 845), (765, 835), (770, 880), (790, 930), (780, 985), (720, 985), (705, 940)],
    "small_mid": [(820, 715), (835, 685), (880, 675), (925, 690), (935, 730), (900, 750), (850, 745)],
    "left_low": [(40, 1000), (120, 985), (200, 960), (280, 950), (310, 985), (305, 1040), (250, 1070), (130, 1080), (40, 1040)],
}


def chaikin(points, rounds=3):
    pts = np.array(points, dtype=np.float64)
    for _ in range(rounds):
        nxt = np.roll(pts, -1, axis=0)
        pts = np.concatenate([0.75 * pts + 0.25 * nxt, 0.25 * pts + 0.75 * nxt])
        pts = pts.reshape(2, -1, 2).transpose(1, 0, 2).reshape(-1, 2)
    return pts


def resample(points, count):
    seg = np.hypot(*np.diff(np.vstack([points, points[:1]]), axis=0).T)
    t = np.concatenate([[0.0], np.cumsum(seg)])
    total = t[-1]
    even = np.linspace(0.0, total, count, endpoint=False)
    closed = np.vstack([points, points[:1]])
    return np.stack([np.interp(even, t, closed[:, 0]), np.interp(even, t, closed[:, 1])], axis=1)


def snap_to_edges(contour, h, reach=10, smooth_rounds=6):
    """Moves each outline point along its normal to the strongest height gradient within `reach` px (the segmentation outline
    sits a few pixels off the real step), then smooths the offsets so the outline stays a clean curve."""
    sm = cv2.GaussianBlur(h, (0, 0), 1.5)
    gx = cv2.Sobel(sm, cv2.CV_32F, 1, 0) / 8.0
    gy = cv2.Sobel(sm, cv2.CV_32F, 0, 1) / 8.0
    mag = np.hypot(gx, gy)
    pts = contour.reshape(-1, 2).astype(np.float64)
    n = len(pts)
    tangent = np.roll(pts, -3, axis=0) - np.roll(pts, 3, axis=0)
    normal = np.stack([-tangent[:, 1], tangent[:, 0]], axis=1)
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-6)
    offsets = np.zeros(n)
    steps = np.arange(-reach, reach + 1)
    for i in range(n):
        xs = np.clip(np.round(pts[i, 0] + normal[i, 0] * steps).astype(int), 0, 1023)
        ys = np.clip(np.round(pts[i, 1] + normal[i, 1] * steps).astype(int), 0, 1023)
        along = mag[ys, xs] * (1.0 - 0.03 * np.abs(steps))  # (a small preference for staying close)
        offsets[i] = steps[int(np.argmax(along))]
    for _ in range(smooth_rounds):
        offsets = (np.roll(offsets, 1) + 2 * offsets + np.roll(offsets, -1)) / 4.0
    snapped = pts + normal * offsets[:, None]
    return np.round(snapped).astype(np.int32).reshape(-1, 1, 2)


def mean_edge(contour, h):
    sm = cv2.GaussianBlur(h, (0, 0), 1.5)
    mag = np.hypot(cv2.Sobel(sm, cv2.CV_32F, 1, 0), cv2.Sobel(sm, cv2.CV_32F, 0, 1)) / 8.0
    pts = contour.reshape(-1, 2)
    return float(mag[np.clip(pts[:, 1], 0, 1023), np.clip(pts[:, 0], 0, 1023)].mean())


def local_step(contour, h):
    """Median height just inside the outline minus just outside, along the whole border (robust to the soft swells)."""
    hs = cv2.GaussianBlur(h, (0, 0), 1.5)
    m = np.zeros(h.shape, np.uint8)
    cv2.fillPoly(m, [contour.reshape(-1, 1, 2).astype(np.int32)], 1)
    e = np.ones((11, 11), np.uint8)
    inner = m - cv2.erode(m, e)
    outer = cv2.dilate(m, e) - m
    pts = contour.reshape(-1, 2)
    steps = []
    for i in range(0, len(pts), 6):
        x, y = pts[i]
        y0, y1, x0, x1 = max(y - 14, 0), min(y + 15, 1024), max(x - 14, 0), min(x + 15, 1024)
        a_ = hs[y0:y1, x0:x1][inner[y0:y1, x0:x1] > 0]
        b_ = hs[y0:y1, x0:x1][outer[y0:y1, x0:x1] > 0]
        if len(a_) > 5 and len(b_) > 5:
            steps.append(np.median(a_) - np.median(b_))
    return float(np.median(steps)) if steps else 0.0


def lobes_from_json(path, h):
    """Lobes found by sam_lobes.py: contour (px of the 1024 picture) -> smooth 48-vertex outline, with the local step along the border."""
    import json
    rows = []
    kept = []
    for item in json.load(open(path)):
        contour = np.array(item["contour"], dtype=np.float64).reshape(-1, 1, 2).astype(np.int32)
        before = mean_edge(contour, h)
        if SNAP:
            contour = snap_to_edges(contour, h)
        print(f"  outline gradient before {before:.4f}, now {mean_edge(contour, h):.4f}")
        item["local_step"] = local_step(contour, h)
        outline = smooth_outline(contour) / 1024.0
        centre = outline.mean(axis=0)
        low, high = outline.min(axis=0), outline.max(axis=0)
        print(f"  sam lobe: area {item['area_cm2']:.0f} cm2, local step {item['local_step']:+.3f}")
        rows.append([centre[0], centre[1], item["local_step"], 0.0, low[0], low[1], high[0], high[1]] + outline.reshape(-1).tolist())
        kept.append(outline)
    return rows, kept


def lobe_layer_of(rows):
    """The lobes drawn the way the shader draws them (smooth step), as a height layer, for the swell subtraction."""
    layer = np.zeros((1024, 1024), np.float32)
    for row in rows:
        outline = np.array(row[8:], dtype=np.float64).reshape(-1, 2) * 1024.0
        cell = np.zeros((1024, 1024), np.uint8)
        cv2.fillPoly(cell, [outline.astype(np.int32).reshape(-1, 1, 2)], 1)
        layer += cv2.GaussianBlur(cell.astype(np.float32), (0, 0), 3.0) * row[2]
    return layer


SAM_JSON = None
SNAP = True


def lobes_of(h, cm_per_px):
    """The hand-traced lobes; the step of each is measured from the height: inside minus a ring just outside."""
    rows = []
    kept = []
    for name, pts in HAND_LOBES.items():
        outline = resample(chaikin(np.array(pts, dtype=np.float64) / GRID_PX), VERTS)
        poly = (outline * 1024.0).astype(np.int32).reshape(-1, 1, 2)
        cell = np.zeros(h.shape, np.uint8)
        cv2.fillPoly(cell, [poly], 1)
        inner = cv2.erode(cell, np.ones((9, 9), np.uint8))
        ring = cv2.dilate(cell, np.ones((41, 41), np.uint8)) - cv2.dilate(cell, np.ones((13, 13), np.uint8))
        step = float(np.median(h[inner > 0]) - np.median(h[ring > 0]))
        print(f"  lobe {name}: area {cell.sum() * cm_per_px ** 2:.0f} cm2, step {step:+.3f}")
        centre = outline.mean(axis=0)
        low, high = outline.min(axis=0), outline.max(axis=0)
        rows.append([centre[0], centre[1], step, 0.0, low[0], low[1], high[0], high[1]] + outline.reshape(-1).tolist())
        kept.append(outline)
    return rows, kept


def lobe_layer(h, cm_per_px):
    """The traced lobes as a height layer: each one a Gaussian-blurred (about 1 cm) mask times its measured step."""
    layer = np.zeros(h.shape, np.float32)
    for name, pts in HAND_LOBES.items():
        outline = resample(chaikin(np.array(pts, dtype=np.float64) / GRID_PX), VERTS)
        cell = np.zeros(h.shape, np.uint8)
        cv2.fillPoly(cell, [(outline * 1024.0).astype(np.int32).reshape(-1, 1, 2)], 1)
        inner = cv2.erode(cell, np.ones((9, 9), np.uint8))
        ring = cv2.dilate(cell, np.ones((41, 41), np.uint8)) - cv2.dilate(cell, np.ones((13, 13), np.uint8))
        step = float(np.median(h[inner > 0]) - np.median(h[ring > 0]))
        layer += cv2.GaussianBlur(cell.astype(np.float32), (0, 0), 1.0 / cm_per_px) * step
    return layer


SWELL = 64
COLOUR_GRID = int(__import__("os").environ.get("COLOUR_GRID", "128"))  # the colour grid is finer than the height grid: colour holds the lichen and the patch edges


def swell_grid(h, cm_per_px, rows=None):
    """What the lobes and pits do not carry: the photograph minus the traced lobes, averaged to SWELL x SWELL cells."""
    layer = lobe_layer_of(rows) if rows is not None else lobe_layer(h, cm_per_px)
    return cv2.resize(h - layer, (SWELL, SWELL), interpolation=cv2.INTER_AREA)


def specks_of(h, cm_per_px, limit=200):
    """Small round pits and bumps: local extrema of the fine height (a difference of Gaussians), the strongest `limit` of them."""
    fine = cv2.GaussianBlur(h, (0, 0), 0.8) - cv2.GaussianBlur(h, (0, 0), 5.0)
    found = []
    for kind in (-1.0, 1.0):  # -1: a pit (lower than around it), 1: a bump
        d = fine * -kind
        peak = (d == cv2.dilate(d, np.ones((9, 9), np.uint8))) & (d > 0.06)
        for y, x in zip(*np.nonzero(peak)):
            depth = float(d[y, x])
            r = 1
            while r < 7 and d[max(y - r, 0):y + r + 1, max(x - r, 0):x + r + 1].mean() > depth * 0.35:
                r += 1
            found.append([x / 1024.0, y / 1024.0, r / 1024.0, kind * depth])
    found.sort(key=lambda row: -abs(row[3]))
    return found[:limit]


def wrapped(rows, digits):
    """All values of the rows as GDScript array text, 8 to a line (the project's line limit)."""
    values = [("%." + str(digits) + "f") % v for row in rows for v in row]
    return ("," + chr(10)).join(chr(9) + chr(9) + ", ".join(values[i:i + 8]) for i in range(0, len(values), 8))


def main():
    h = load(sys.argv[1])
    cm = float(sys.argv[2]) / 1024.0
    global SAM_JSON
    if len(sys.argv) > 5:
        SAM_JSON = sys.argv[5]
    lobes, outlines = lobes_from_json(SAM_JSON, h) if SAM_JSON else lobes_of(h, cm)
    specks = specks_of(h, cm)
    swell = swell_grid(h, cm, lobes if SAM_JSON else None)
    tints = write_colour(sys.argv[1], sys.argv[1], lobes, sys.argv[3].replace('boulder_features.gd', 'boulder_colour.bin'))
    for row, tint in zip(lobes, tints):
        row.extend(float(v) for v in tint)
    print(f"{len(lobes)} lobes, {len(specks)} specks")
    gx_ = cv2.Sobel(cv2.GaussianBlur(h, (0, 0), 1.0), cv2.CV_32F, 1, 0) * 12.0
    gy_ = cv2.Sobel(cv2.GaussianBlur(h, (0, 0), 1.0), cv2.CV_32F, 0, 1) * 12.0
    shade = np.clip(0.5 - 0.7 * gx_ - 0.7 * gy_, 0, 1)
    overlay = cv2.cvtColor((shade * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    for o in outlines:
        cv2.polylines(overlay, [(o * 1024.0).astype(np.int32).reshape(-1, 1, 2)], True, (0, 0, 255), 2)
    for x, y, r, d in specks:
        cv2.circle(overlay, (int(x * 1024), int(y * 1024)), max(int(r * 1024), 2), (0, 255, 0) if d < 0 else (255, 160, 0), 1)
    cv2.imwrite(sys.argv[4], overlay)
    with open(sys.argv[3], "w", encoding="utf8") as handle:
        handle.write("class_name BoulderFeatures\nextends RefCounted\n## Generated by tools/bark/extract_features.py: never edit.\n"
                     "## LOBES rows: cx, cy, step, soft, bbox (4), then %d x,y vertices (tile units).\n"
                     "## SPECKS rows: x, y, radius, depth (negative: a pit). SWELL: a coarse grid.\n\n" % VERTS)
        handle.write("const SWELL_SIZE := %d\n" % SWELL)
        handle.write("const LOBE_STRIDE := %d\nconst SPECK_STRIDE := 4\n" % (8 + 2 * VERTS + 3))
        handle.write("\nstatic func lobes() -> PackedFloat32Array:\n\treturn PackedFloat32Array([\n" + wrapped(lobes, 5) + ",\n\t])\n")
        handle.write("\n\nstatic func specks() -> PackedFloat32Array:\n\treturn PackedFloat32Array([\n" + wrapped(specks, 5) + ",\n\t])\n")
        handle.write("\n\nstatic func swell() -> PackedFloat32Array:\n\treturn PackedFloat32Array([\n" + wrapped(swell, 4) + ",\n\t])\n")


def lobe_tints(rows, colour):
    """Per lobe, the colour inside against just outside along the border (a ratio per channel), and the tint layer they make together."""
    layer = np.ones(colour.shape, np.float32)
    tints = []
    blurred = cv2.GaussianBlur(colour, (0, 0), 1.5)
    for row in rows:
        outline = np.array(row[8:8 + 96], dtype=np.float64).reshape(-1, 2) * 1024.0
        m = np.zeros(colour.shape[:2], np.uint8)
        cv2.fillPoly(m, [outline.astype(np.int32).reshape(-1, 1, 2)], 1)
        inner = m - cv2.erode(m, np.ones((21, 21), np.uint8))
        outer = cv2.dilate(m, np.ones((21, 21), np.uint8)) - m
        a = np.median(blurred[inner > 0], axis=0)
        b = np.median(blurred[outer > 0], axis=0)
        tint = np.clip(a / np.maximum(b, 1e-3), 0.6, 1.6)
        tints.append(tint)
        soft = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 3.0)
        layer *= 1.0 + soft[..., None] * (tint[None, None, :] - 1.0)
    return tints, layer


def write_colour(path, photo_path, rows, bin_path):
    """The photograph's colour divided by the lobe tints, as a 64 x 64 RGB grid in a binary file (8 bit)."""
    colour = cv2.imread(photo_path.replace("_disp.png", "_diff.jpg")).astype(np.float32) / 255.0
    colour = cv2.resize(colour, (1024, 1024), interpolation=cv2.INTER_AREA)
    tints, layer = lobe_tints(rows, colour)
    grid = cv2.resize(colour / layer, (COLOUR_GRID, COLOUR_GRID), interpolation=cv2.INTER_AREA)
    rgb = np.clip(grid[..., ::-1] * 255.0 + 0.5, 0, 255).astype(np.uint8)
    open(bin_path, "wb").write(rgb.tobytes())
    mean = colour.reshape(-1, 3).mean(axis=0)[::-1]
    print("colour grid %d bytes; photograph mean RGB %s; lobe tints (R G B): %s" % (rgb.size, mean.round(3), [t[::-1].round(2).tolist() for t in tints]))
    return [t[::-1] for t in tints]


if __name__ == "__main__":
    main()
