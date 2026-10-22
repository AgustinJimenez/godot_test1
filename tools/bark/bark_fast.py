"""The flake generator of procedural_bark.py compiled with numba, and a fit on all the CPU cores.

Same maths as `procedural_bark.flakes` (the reference of the shader), in a compiled loop over the
pixels: a few milliseconds a picture instead of half a second. The fit evaluates a whole generation of
parameter sets at once on every core.

Usage:
  python bark_fast.py check                      (compare with the numpy generator, time both)
  python bark_fast.py fit <folder> <name> <tile metres> [generations] [out json]
  python bark_fast.py show <params json> <out png> [size px] [cm per px]
"""
import json
import sys
import time
from multiprocessing import Pool

import cv2
import numpy as np
from numba import njit, prange

import procedural_bark as pb

KEYS = list(pb.PARAMS.keys())


@njit(cache=True, inline="always")
def _fract(x):
    return x - np.floor(x)


@njit(cache=True, inline="always")
def _hash(ix, iy, seed):
    return _fract(np.sin(ix * 127.1 + iy * 311.7 + seed * 74.7) * 43758.5453)


@njit(cache=True)
def _noise(x, y, seed):
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _hash(ix, iy, seed), _hash(ix + 1, iy, seed)
    c, d = _hash(ix, iy + 1, seed), _hash(ix + 1, iy + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


@njit(cache=True)
def _smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


@njit(cache=True)
def _flakes_at(px, py, q, seed):
    """q: the parameters in KEYS order."""
    cell, aspect, length, width, size_var, jit, angle, tip, soft, z_var, base, crown, slope = (
        q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], q[9], q[10], q[11], q[12])
    rag_amp, rag_cm, warp_cm, warp_scale = q[13], q[14], q[15], q[16]
    fine_amp, fine_cm = q[17], q[18]
    block = q[19]
    groove_cm, groove_w, groove_cover, split_cm, split_w, split_cover, cut_depth = (
        q[20], q[21], q[22], q[23], q[24], q[25], q[26])
    wx = (_noise(px / warp_scale, py / warp_scale, seed + 11.0) - 0.5) * 2.0
    wy = (_noise(px / warp_scale + 31.7, py / warp_scale, seed + 13.0) - 0.5) * 2.0
    x = px + wx * warp_cm
    y = py + wy * warp_cm * 1.5
    cw = cell
    ch = cell * aspect
    ix, iy = np.floor(x / cw), np.floor(y / ch)
    bite_u = _noise(x / rag_cm, y / (rag_cm * 1.8), seed + 41.0) - 0.5
    bite_v = _noise(x / rag_cm + 17.3, y / (rag_cm * 1.8), seed + 43.0) - 0.5
    best = 0.0
    for oy in range(-2, 3):
        for ox in range(-1, 2):
            cx, cy = ix + ox, iy + oy
            h0 = _hash(cx, cy, seed)
            h1 = _hash(cx, cy, seed + 5.3)
            h2 = _hash(cx, cy, seed + 10.6)
            h3 = _hash(cx, cy, seed + 15.9)
            h4 = _hash(cx, cy, seed + 21.2)
            centre_x = (cx + 0.5 + (h0 - 0.5) * jit) * cw
            centre_y = (cy + 0.5 + (h1 - 0.5) * jit) * ch
            size = 0.55 + size_var * h2 * h2
            half_l = min(ch * length * size, 2.0 * ch)
            half_w = min(cw * width * size, 1.0 * cw)
            turn = (h3 - 0.5) * angle
            dx, dy = x - centre_x, y - centre_y
            rx = dx * np.cos(turn) + dy * np.sin(turn)
            ry = -dx * np.sin(turn) + dy * np.cos(turn)
            u = rx / half_w + bite_u * rag_amp * 4.0
            v = ry / half_l + bite_v * rag_amp * 2.0
            av = min(max(abs(v), 0.0), 1.0)
            half = (1.0 - block) * (1.0 - av ** tip) + block * (1.0 - av ** 8.0)
            if abs(v) < 1.0 and abs(u) < half:
                d = 1.0 - abs(u) / max(half, 1e-3)
                rim = _smooth(0.0, soft, d)
                value = h4 * z_var + (base + crown * d + slope * v) * rim
                best = max(best, value)
    lane_u = x / groove_cm + (_noise(x / 9.0, y / 30.0, seed + 51.0) - 0.5) * 1.2
    lane = np.floor(lane_u)
    fl = lane_u - lane
    open_n = _noise(lane * 3.7 + 0.5, y / (groove_cm * 10.0), seed + 53.0)
    open_ = 1.0 - _smooth(groove_cover - 0.05, groove_cover + 0.05, open_n)
    groove = (1.0 - _smooth(0.0, groove_w, min(fl, 1.0 - fl) * 2.0)) * open_
    split_v = y / split_cm + (_noise(x / 7.0, y / 20.0, seed + 55.0) - 0.5) * 0.6
    row = np.floor(split_v)
    fv = split_v - row
    column = np.floor(x / (groove_cm * 0.8))
    on = 1.0 - _smooth(split_cover - 0.03, split_cover + 0.03, _hash(column, row, seed + 57.0))
    split = (1.0 - _smooth(0.0, split_w, min(fv, 1.0 - fv) * 2.0)) * on
    best = best * (1.0 - cut_depth * max(groove, split))
    fine = _noise(px / fine_cm, py / (fine_cm * 2.0), seed + 29.0)
    if best > 0.05:
        best += (fine - 0.5) * fine_amp
    return best


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _flakes_at((col + 0.5) * cm_per_px, py, q, seed)
    return out


def vector(params):
    return np.array([params[k] for k in KEYS], dtype=np.float64)


def render(params, size, cm_per_px, seed=1.0):
    h = _render(size, cm_per_px, vector(params), seed)
    h = h - h.min()
    return h / max(float(h.max()), 1e-6)


def _score(job):
    params, size, cm_per_px, target = job
    m = pb.measure(render(params, size, cm_per_px), cm_per_px)
    return pb.loss(m, target), m


def fit(folder, name, tile_m, generations, out):
    target, cm_per_px = pb.target_of(folder, name, tile_m)
    print("target", {k: round(v, 3) for k, v in target.items()})
    size = 384
    rng = np.random.default_rng(11)
    best_p, best_loss = dict(pb.PARAMS), 1e9
    workers = 6
    batch = 24
    with Pool(workers) as pool:
        for generation in range(generations):
            candidates = []
            for _ in range(batch):
                if generation < generations * 0.3 or best_loss > 1e8:
                    candidates.append({k: float(rng.uniform(*pb.RANGES[k])) for k in KEYS})
                else:
                    spread = 0.22 * (1.0 - generation / generations) + 0.02
                    p = {}
                    for k, v in best_p.items():
                        lo, hi = pb.RANGES[k]
                        p[k] = float(np.clip(v + rng.normal(0, spread * (hi - lo)), lo, hi))
                    candidates.append(p)
            results = pool.map(_score, [(p, size, cm_per_px, target) for p in candidates])
            for p, (score, m) in zip(candidates, results):
                if score < best_loss:
                    best_loss, best_p = score, p
                    print(f"gen {generation:3d} loss {score:.3f}", {k: round(v, 2) for k, v in m.items()},
                          flush=True)
    with open(out, "w") as handle:
        json.dump({"name": name, "tile_m": tile_m, "cm_per_px": cm_per_px, "loss": best_loss,
                   "params": best_p}, handle, indent=1)
    print("best", best_loss)


def show(params_json, out, size, cm_per_px):
    with open(params_json) as handle:
        data = json.load(handle)
    cm = cm_per_px if cm_per_px > 0 else data["cm_per_px"]
    cv2.imwrite(out, (render(data["params"], size, cm) * 255).astype(np.uint8))


def check():
    p = dict(pb.PARAMS)
    render(p, 64, 0.2)  # (compile)
    started = time.time()
    fast = render(p, 384, 0.21)
    fast_time = time.time() - started
    started = time.time()
    slow = pb.render(p, 384, 0.21)
    slow_time = time.time() - started
    print("fast %.3f s, numpy %.3f s, x%.0f; mean abs difference %.5f, max %.4f" % (
        fast_time, slow_time, slow_time / max(fast_time, 1e-6), np.abs(fast - slow).mean(),
        np.abs(fast - slow).max()))


if __name__ == "__main__":
    if sys.argv[1] == "check":
        check()
    elif sys.argv[1] == "fit":
        fit(sys.argv[2], sys.argv[3], float(sys.argv[4]), int(sys.argv[5]) if len(sys.argv) > 5 else 60,
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_params.json")
    elif sys.argv[1] == "show":
        show(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 512,
             float(sys.argv[5]) if len(sys.argv) > 5 else 0.0)
