"""Fits ambient occlusion to the photograph's AO map from (a) the multi-scale cavity of the height and (b) the stored layout:
the lobe outlines (inside and outside distance profiles), the edge layer, the pits. Prints the correlation of each model.

  python ao_fit.py [out npy]"""
import sys

import limits  # (first)

import cv2
import numpy as np

import extract_features as ef

D = "bark_downloads/rock_boulder_dry_"
N = 1024
h = ef.load(D + "disp.png").astype(np.float32)
ao = cv2.resize(cv2.imread(D + "ao.jpg", 0), (N, N), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
ys, xs = np.mgrid[0:N, 0:N]
ys = ys.astype(np.float32)
xs = xs.astype(np.float32)


def ring(img, r):
    acc = img.copy()
    for i in range(12):
        a = 2 * np.pi * (i + 0.5 * (i % 2)) / 12
        rr = r * (1.0 if i % 2 == 0 else 0.55)
        acc += cv2.remap(img, (xs + np.float32(np.cos(a) * rr)).astype(np.float32),
                         (ys + np.float32(np.sin(a) * rr)).astype(np.float32), cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)
    return acc / 13.0


def edge_field():
    """The edge layer as LumpBaker._edge_texture draws it."""
    data = np.fromfile("../../systems/world_gen/boulder_edges.bin", dtype=np.uint8).reshape(-1, 6)
    field = np.zeros((N, N), np.float32)
    norm = 3.0 / (2.0 * np.sqrt(2.0 * np.pi))
    r = np.arange(-7, 8)
    dy, dx = np.meshgrid(r, r, indexing="ij")
    for row in data:
        cx = int(row[0]) | (int(row[1]) << 8)
        cy = int(row[2]) | (int(row[3]) << 8)
        amp = row[4] / 255.0 * 0.25
        ang = row[5] / 255.0 * 2 * np.pi
        nx, ny = np.cos(ang), np.sin(ang)
        across = dx * nx + dy * ny
        along = -dx * ny + dy * nx
        prof = 0.5 * amp * np.tanh(across / 1.6) * np.exp(-(across / 7.0) ** 2) * np.exp(-0.5 * (along / 2.0) ** 2) * norm
        y0, y1, x0, x1 = cy - 7, cy + 8, cx - 7, cx + 8
        if y0 < 0 or x0 < 0 or y1 > N or x1 > N:
            continue
        field[y0:y1, x0:x1] += prof.astype(np.float32)
    return field


def lobe_distances():
    """Signed distance (px, negative inside) to the nearest of the 8 lobe outlines."""
    rows, _ = ef.lobes_from_json("fits/sam_boulder_kept.json", h)
    best = np.full((N, N), 1e9, np.float32)
    for row in rows:
        outline = np.array(row[8:104], dtype=np.float64).reshape(-1, 2) * N
        m = np.zeros((N, N), np.uint8)
        cv2.fillPoly(m, [outline.astype(np.int32).reshape(-1, 1, 2)], 1)
        din = cv2.distanceTransform(m, cv2.DIST_L2, 5)
        dout = cv2.distanceTransform(1 - m, cv2.DIST_L2, 5)
        sd = np.where(m > 0, -din, dout).astype(np.float32)
        best = np.where(np.abs(sd) < np.abs(best), sd, best)
    return best


def pit_field():
    from_gd = open("../../systems/world_gen/boulder_features.gd", encoding="utf8").read()
    import re
    block = from_gd[from_gd.index("func specks"):]
    values = [float(v) for v in re.findall(r"-?\d+\.\d+", block)]
    arr = np.array(values).reshape(-1, 4)
    field = np.zeros((N, N), np.float32)
    for x, y, r, d in arr:
        cv2.circle(field, (int(x * N), int(y * N)), max(int(r * N * 1.3), 2), float(abs(d)), -1)
    return cv2.GaussianBlur(field, (0, 0), 1.5)


def main():
    cav = []
    names = []
    for r in (1.5, 3.0, 6.0, 12.0, 24.0):
        c = h - ring(h, r)
        cav += [c.ravel(), np.minimum(c, 0).ravel()]
        names += ["cav%g" % r, "neg%g" % r]
    E = edge_field()
    sd = lobe_distances()
    P = pit_field()
    layout = [E.ravel(), np.minimum(E, 0).ravel(), np.maximum(E, 0).ravel(), P.ravel()]
    lnames = ["edge", "edge-", "edge+", "pits"]
    for s in (2.0, 5.0, 12.0):
        layout += [np.exp(-(np.maximum(-sd, 0) / s) ** 2).ravel(), np.exp(-(np.maximum(sd, 0) / s) ** 2).ravel()]
        lnames += ["lobe_in%g" % s, "lobe_out%g" % s]
    y = ao.ravel()
    ones = np.ones(y.size, np.float32)

    def fit(label, cols, nm):
        X = np.stack(cols + [ones], axis=1)
        w, *_ = np.linalg.lstsq(X, y, rcond=None)
        p = X @ w
        print("%-44s correlation %.3f (rms %.4f)" % (label, np.corrcoef(p, y)[0, 1], np.sqrt(((p - y) ** 2).mean())))
        return w, p

    fit("height cavities only (the current model)", cav, names)
    fit("layout only (edge layer, lobes, pits)", layout, lnames)
    w, p = fit("height cavities + layout", cav + layout, names + lnames)
    print("weights:", {n: round(float(v), 4) for n, v in zip(names + lnames + ["bias"], w)})
    np.save(sys.argv[1] if len(sys.argv) > 1 else "E:/Temp/ao_layout_weights.npy", w)
    cv2.imwrite("fits/ao_fit_vs.png", np.hstack([ao, p.reshape(N, N).clip(0, 1)]) * 255)


if __name__ == "__main__":
    main()
