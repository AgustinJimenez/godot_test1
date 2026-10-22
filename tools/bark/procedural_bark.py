"""A procedural bark height field, and its fit to a photographed bark (Poly Haven, CC0).

The generator is the reference of the shader (shaders/world/flora_wind.gdshader, `flake_height`): the
same maths, written so that it ports to GLSL one to one (hash from sin, value noise, a 3 x 3 Voronoi).
Coordinates are in centimetres on the real bark: x across the trunk, y along it.

Usage:
  python procedural_bark.py fit <folder> <name> <tile metres> [samples] [out json]
  python procedural_bark.py show <params json> <out png> [size px] [cm per px]
"""
import json
import sys

import cv2
import numpy as np

import analyze_flakes as analysis

PARAMS = {
    "cell_cm": 3.0,       # spacing of flake centres across the trunk
    "cell_aspect": 2.0,   # spacing along over across
    "len": 1.6,           # half length of a flake over the spacing along (more than 0.5: they overlap)
    "wid": 0.8,           # half width of a flake over the spacing across
    "size_var": 1.2,      # how much bigger some flakes are than others (heavy tail)
    "jit": 0.9,           # how far a flake sits from its grid place
    "angle": 0.25,        # random turn of a flake from the vertical (radians, total spread)
    "tip": 1.6,           # pointedness of the ends (1: a diamond, 2: a lens, 3: nearly a rectangle)
    "soft": 0.35,         # how wide the soft rim at a flake's edge is
    "z_var": 0.7,         # how much the flakes lie over one another (heights)
    "base": 0.5,          # a flake's own height over the gap
    "crown": 0.3,         # how much a flake swells along its middle
    "slope": 0.3,         # a flake rises along its length (the shingle)
    "rag_amp": 0.15,      # ragged edges
    "rag_cm": 1.0,
    "warp_cm": 1.5,       # the whole pattern bends a little
    "warp_scale_cm": 20.0,
    "fine_amp": 0.05,
    "fine_cm": 0.6,
    "block": 0.3,         # 0: a lens with pointed ends, 1: a block with square ends
    "groove_cm": 5.0,     # spacing of the long grooves across the trunk
    "groove_w": 0.25,     # their width (share of the spacing)
    "groove_cover": 0.5,  # how much of each groove's length is open (the rest is bridged)
    "split_cm": 12.0,     # spacing of the short transverse splits along the trunk
    "split_w": 0.12,      # their width
    "split_cover": 0.3,   # share of the places that split
    "cut_depth": 0.6,     # how deep grooves and splits cut into the flakes
}
RANGES = {
    "cell_cm": (0.5, 12.0), "cell_aspect": (1.0, 4.0), "len": (0.7, 3.0), "wid": (0.4, 1.6),
    "size_var": (0.0, 3.0), "jit": (0.4, 1.0), "angle": (0.0, 0.8), "tip": (1.0, 3.5),
    "soft": (0.03, 0.3), "z_var": (0.1, 1.2), "base": (0.2, 1.0), "crown": (0.0, 0.2),
    "slope": (-0.25, 0.25), "rag_amp": (0.03, 0.09), "rag_cm": (0.8, 3.0), "warp_cm": (0.0, 1.2),
    "warp_scale_cm": (10.0, 40.0), "fine_amp": (0.0, 0.03), "fine_cm": (0.4, 2.0), "block": (0.0, 1.0),
    "groove_cm": (1.5, 14.0), "groove_w": (0.05, 0.5), "groove_cover": (0.1, 0.9), "split_cm": (4.0, 40.0),
    "split_w": (0.03, 0.3), "split_cover": (0.0, 0.7), "cut_depth": (0.0, 1.0),
}


def fract(x):
    return x - np.floor(x)


def hash2(ix, iy, seed):
    return fract(np.sin(ix * 127.1 + iy * 311.7 + seed * 74.7) * 43758.5453)


def value_noise(x, y, seed):
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hash2(ix, iy, seed), hash2(ix + 1, iy, seed)
    c, d = hash2(ix, iy + 1, seed), hash2(ix + 1, iy + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def flakes(x_cm, y_cm, p, seed):
    """The flakes lying over one another: pointed lenses, each with its own size, turn and height; the
    highest at a point wins; 0 where there is none (a gap). 3 x 5 cells are asked for each point."""
    cw = p["cell_cm"]
    ch = cw * p["cell_aspect"]
    ix, iy = np.floor(x_cm / cw), np.floor(y_cm / ch)
    best = np.zeros(x_cm.shape)
    bite_u = value_noise(x_cm / p["rag_cm"], y_cm / (p["rag_cm"] * 1.8), seed + 41.0) - 0.5
    bite_v = value_noise(x_cm / p["rag_cm"] + 17.3, y_cm / (p["rag_cm"] * 1.8), seed + 43.0) - 0.5
    for oy in (-2, -1, 0, 1, 2):
        for ox in (-1, 0, 1):
            cx, cy = ix + ox, iy + oy
            h = [hash2(cx, cy, seed + k * 5.3) for k in range(5)]
            centre_x = (cx + 0.5 + (h[0] - 0.5) * p["jit"]) * cw
            centre_y = (cy + 0.5 + (h[1] - 0.5) * p["jit"]) * ch
            size = 0.55 + p["size_var"] * h[2] * h[2]
            half_l = np.minimum(ch * p["len"] * size, 2.0 * ch)
            half_w = np.minimum(cw * p["wid"] * size, 1.0 * cw)
            turn = (h[3] - 0.5) * p["angle"]
            dx, dy = x_cm - centre_x, y_cm - centre_y
            rx = dx * np.cos(turn) + dy * np.sin(turn)
            ry = -dx * np.sin(turn) + dy * np.cos(turn)
            u = rx / half_w + bite_u * p["rag_amp"] * 4.0
            v = ry / half_l + bite_v * p["rag_amp"] * 2.0
            av = np.clip(np.abs(v), 0.0, 1.0)
            half = (1.0 - p["block"]) * (1.0 - av ** p["tip"]) + p["block"] * (1.0 - av ** 8.0)
            inside = (np.abs(v) < 1.0) & (np.abs(u) < half)
            d = 1.0 - np.abs(u) / np.maximum(half, 1e-3)
            rim = smooth(0.0, p["soft"], d)
            body = p["base"] + p["crown"] * d + p["slope"] * v
            value = h[4] * p["z_var"] + body * rim
            best = np.maximum(best, np.where(inside, value, 0.0))
    return best


def cuts(x, y, p, seed):
    """1 on the flakes, lower where a long groove or a short transverse split cuts them."""
    lane_u = x / p["groove_cm"] + (value_noise(x / 9.0, y / 30.0, seed + 51.0) - 0.5) * 1.2
    lane = np.floor(lane_u)
    f = lane_u - lane
    open_n = value_noise(lane * 3.7 + 0.5, y / (p["groove_cm"] * 10.0), seed + 53.0)
    open_ = 1.0 - smooth(p["groove_cover"] - 0.05, p["groove_cover"] + 0.05, open_n)
    groove = (1.0 - smooth(0.0, p["groove_w"], np.minimum(f, 1.0 - f) * 2.0)) * open_
    split_v = y / p["split_cm"] + (value_noise(x / 7.0, y / 20.0, seed + 55.0) - 0.5) * 0.6
    row = np.floor(split_v)
    fv = split_v - row
    column = np.floor(x / (p["groove_cm"] * 0.8))
    on = 1.0 - smooth(p["split_cover"] - 0.03, p["split_cover"] + 0.03, hash2(column, row, seed + 57.0))
    split = (1.0 - smooth(0.0, p["split_w"], np.minimum(fv, 1.0 - fv) * 2.0)) * on
    return 1.0 - p["cut_depth"] * np.maximum(groove, split)


def bark_height(x_cm, y_cm, p, seed=1.0):
    wx = (value_noise(x_cm / p["warp_scale_cm"], y_cm / p["warp_scale_cm"], seed + 11.0) - 0.5) * 2.0
    wy = (value_noise(x_cm / p["warp_scale_cm"] + 31.7, y_cm / p["warp_scale_cm"], seed + 13.0) - 0.5) * 2.0
    x = x_cm + wx * p["warp_cm"]
    y = y_cm + wy * p["warp_cm"] * 1.5
    height = flakes(x, y, p, seed) * cuts(x, y, p, seed)
    fine = value_noise(x_cm / p["fine_cm"], y_cm / (p["fine_cm"] * 2.0), seed + 29.0)
    return height + (fine - 0.5) * p["fine_amp"] * (height > 0.05)


def render(p, size, cm_per_px, seed=1.0):
    xs = (np.arange(size) + 0.5) * cm_per_px
    x_cm, y_cm = np.meshgrid(xs, xs)
    h = bark_height(x_cm, y_cm, p, seed).astype(np.float32)
    h -= h.min()
    return h / max(h.max(), 1e-6)


def autocorrelation_lengths(height, cm_per_px):
    """Distance (cm) at which the correlation across and along the trunk falls under one half."""
    h = height - height.mean()
    power = np.abs(np.fft.rfft2(h)) ** 2
    ac = np.fft.irfft2(power, s=h.shape)
    ac = ac / max(ac[0, 0], 1e-9)
    along = ac[1:80, 0]
    across = ac[0, 1:80]
    lag_y = np.argmax(along < 0.5) + 1 if (along < 0.5).any() else 80
    lag_x = np.argmax(across < 0.5) + 1 if (across < 0.5).any() else 80
    return lag_x * cm_per_px, lag_y * cm_per_px


def measure(height, cm_per_px):
    scale_px = 14.0 / cm_per_px
    labels, count = analysis.segment(height, scale_px)
    areas, lengths, widths, angles = analysis.flake_stats(labels, count, cm_per_px)
    if len(areas) < 20:
        return None
    area_m2 = (height.shape[0] * cm_per_px / 100.0) ** 2
    up = float(np.mean(np.abs(np.cos(np.radians(angles - 90.0)))))
    lag_x, lag_y = autocorrelation_lengths(height, cm_per_px)
    gx = cv2.Sobel(height, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(height, cv2.CV_32F, 0, 1, ksize=3)
    steep = np.hypot(gx, gy) / (8.0 * cm_per_px)  # per cm
    high = height - cv2.GaussianBlur(height, (0, 0), 1.5)
    return {
        "flat": float((steep < 0.03).mean()), "edge_ratio": float(np.percentile(steep, 99) / max(np.percentile(steep, 50), 1e-3)),
        "ac_x": float(lag_x), "ac_y": float(lag_y), "grad_mean": float(steep.mean()),
        "grad_p95": float(np.percentile(steep, 95)), "hp_sd": float(high.std()),
        "per_m2": len(areas) / area_m2, "area_med": float(np.median(areas)),
        "area_p10": float(np.percentile(areas, 10)), "area_p90": float(np.percentile(areas, 90)),
        "aspect": float(np.median(lengths / np.maximum(widths, 0.01))), "up": up,
        "covered": float((labels > 0).mean()), "sd": float(height.std()),
        "p05": float(np.percentile(height, 5)), "p95": float(np.percentile(height, 95)),
    }


def loss(m, target):
    if m is None:
        return 1e6
    total = 0.0
    for key, weight in (("per_m2", 1.0), ("area_med", 1.0), ("area_p10", 0.5), ("area_p90", 0.7),
                        ("aspect", 1.0)):
        total += weight * abs(np.log(max(m[key], 1e-3) / max(target[key], 1e-3)))
    for key, weight in (("ac_x", 1.0), ("ac_y", 1.0), ("grad_mean", 0.8), ("grad_p95", 0.6), ("hp_sd", 0.4),
                        ("edge_ratio", 0.8)):
        total += weight * abs(np.log(max(m[key], 1e-4) / max(target[key], 1e-4)))
    total += 3.0 * abs(m["flat"] - target["flat"])
    for key, weight in (("up", 2.0), ("covered", 2.0), ("sd", 4.0), ("p05", 2.0), ("p95", 2.0)):
        total += weight * abs(m[key] - target[key])
    return total


def target_of(folder, name, tile_m):
    height = analysis.load_height(f"{folder}/{name}_disp.png")
    cm_per_px = tile_m * 100.0 / height.shape[0]
    return measure(height, cm_per_px), cm_per_px


def fit(folder, name, tile_m, samples, out):
    target, cm_per_px = target_of(folder, name, tile_m)
    print("target", {k: round(v, 3) for k, v in target.items()})
    size = 384
    rng = np.random.default_rng(7)
    best_p, best_loss = dict(PARAMS), 1e9
    for step in range(samples):
        if step < samples * 0.4 or best_loss > 1e8:
            p = {k: float(rng.uniform(*RANGES[k])) for k in PARAMS}
        else:
            spread = 0.25 * (1.0 - step / samples) + 0.03
            p = {}
            for k, v in best_p.items():
                lo, hi = RANGES[k]
                p[k] = float(np.clip(v + rng.normal(0, spread * (hi - lo)), lo, hi))
        m = measure(render(p, size, cm_per_px), cm_per_px)
        score = loss(m, target)
        if score < best_loss:
            best_loss, best_p = score, p
            print(f"{step:4d} loss {score:.3f}", {k: round(v, 3) for k, v in m.items()})
    with open(out, "w") as handle:
        json.dump({"name": name, "tile_m": tile_m, "cm_per_px": cm_per_px, "loss": best_loss,
                   "params": best_p}, handle, indent=1)
    print("best", best_loss, json.dumps(best_p))


def show(params_json, out, size, cm_per_px):
    with open(params_json) as handle:
        data = json.load(handle)
    cm = cm_per_px if cm_per_px > 0 else data["cm_per_px"]
    h = render(data["params"], size, cm)
    cv2.imwrite(out, (h * 255).astype(np.uint8))


if __name__ == "__main__":
    if sys.argv[1] == "fit":
        fit(sys.argv[2], sys.argv[3], float(sys.argv[4]), int(sys.argv[5]) if len(sys.argv) > 5 else 400,
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_params.json")
    elif sys.argv[1] == "show":
        show(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 512,
             float(sys.argv[5]) if len(sys.argv) > 5 else 0.0)
