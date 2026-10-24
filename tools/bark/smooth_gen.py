"""A procedural smooth bark height field (numba): a nearly flat sheet with short horizontal dashes and long vertical splits (cherry, birch).

Sheet: stretched low-frequency noise (the swell of the stem); dashes: jittered cells, a dash is a thin horizontal
lens (raised or sunken), more of them in bands round the stem; splits: thin vertical cracks of random length that run
along the trunk, with a raised lip; grain: fine horizontal streaks.
Same loop and loss as the bark (rock_gen.fit with this module's parameters).

  python smooth_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "swell_cm": 40.0, "swell_amp": 0.15, "dash_w_cm": 1.8, "dash_h_cm": 0.18, "dash_cover": 0.4, "dash_depth": 0.3,
    "dash_cell_cm": 6.0, "dash_band_cm": 14.0, "split_cm": 18.0, "split_len": 3.0, "split_w": 0.12,
    "split_depth": 0.6, "split_cover": 0.3, "lip": 0.2, "grain_cm": 0.5, "grain_amp": 0.04,
}
RANGES = {
    "swell_cm": (15.0, 100.0), "swell_amp": (0.0, 0.4), "dash_w_cm": (0.8, 4.0), "dash_h_cm": (0.08, 0.4),
    "dash_cover": (0.1, 0.9), "dash_depth": (0.1, 0.8), "dash_cell_cm": (2.5, 12.0), "dash_band_cm": (5.0, 30.0),
    "split_cm": (8.0, 40.0), "split_len": (1.0, 8.0), "split_w": (0.05, 0.3), "split_depth": (0.2, 1.0),
    "split_cover": (0.05, 0.7), "lip": (0.0, 0.5), "grain_cm": (0.3, 1.2), "grain_amp": (0.0, 0.1),
}
KEYS = list(PARAMS.keys())


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
def _smooth_at(px, py, q, seed):
    swell_cm, swell_amp, dash_w, dash_h, dash_cover, dash_depth = q[0], q[1], q[2], q[3], q[4], q[5]
    dash_cell, dash_band, split_cm, split_len, split_w, split_depth = q[6], q[7], q[8], q[9], q[10], q[11]
    split_cover, lip, grain_cm, grain_amp = q[12], q[13], q[14], q[15]
    h = 0.5 + swell_amp * (_noise(px / swell_cm, py / (swell_cm * 2.0), seed + 1.0) - 0.5)
    # dashes: one candidate per cell, a thin horizontal lens; the cover follows horizontal bands round the stem
    cx0, cy0 = np.floor(px / dash_cell), np.floor(py / dash_cell)
    band = _noise(px / (dash_band * 4.0), py / dash_band, seed + 3.0)
    dash = 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = cx0 + ox, cy0 + oy
            if _hash(cx, cy, seed + 5.0) < dash_cover * (0.3 + 1.4 * band):
                kx = (cx + 0.15 + 0.7 * _hash(cx, cy, seed + 7.0)) * dash_cell
                ky = (cy + 0.15 + 0.7 * _hash(cx, cy, seed + 9.0)) * dash_cell
                lx = dash_w * (0.5 + _hash(cx, cy, seed + 11.0))
                u = (px - kx) / lx
                v = (py - ky) / dash_h
                d = u * u + v * v
                dash = max(dash, 1.0 - _smooth(0.5, 1.0, d))
    h -= dash_depth * dash
    # splits: thin vertical cracks of random length, a raised lip beside each
    sx0 = np.floor(px / split_cm)
    split = 0.0
    lipv = 0.0
    for ox in range(-1, 2):
        cx = sx0 + ox
        for k in range(3):
            sid = cx * 3.0 + k
            if _hash(sid, 0.0, seed + 21.0) < split_cover:
                sx = (cx + _hash(sid, 0.0, seed + 23.0)) * split_cm
                length = split_cm * split_len * (0.4 + _hash(sid, 0.0, seed + 25.0))
                y0 = _hash(sid, 0.0, seed + 27.0) * 1000.0
                wob = (_noise(py / 20.0, sid, seed + 29.0) - 0.5) * 2.0
                dy = py - y0
                across = abs(px - sx - wob)
                along = _smooth(0.0, 0.1 * length, dy) * (1.0 - _smooth(0.9 * length, length, dy)) if 0.0 < dy < length else 0.0
                w = split_w * (0.4 + 0.6 * along)
                split = max(split, along * (1.0 - _smooth(0.0, w, across)))
                lipv = max(lipv, along * (1.0 - _smooth(w, w + 0.6, across)) * _smooth(0.0, w, across))
    h = h - split_depth * split + lip * lipv
    h += grain_amp * (_noise(px / (grain_cm * 8.0), py / grain_cm, seed + 31.0) - 0.5)
    return h


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _smooth_at((col + 0.5) * cm_per_px, py, q, seed)
    return out


def vector(params):
    return np.array([params.get(k, PARAMS[k]) for k in KEYS], dtype=np.float64)


def render(params, size, cm_per_px, seed=1.0):
    h = _render(size, cm_per_px, vector(params), seed)
    h = h - h.min()
    return h / max(float(h.max()), 1e-6)


def decode(v):
    return {k: float(RANGES[k][0] + np.clip(x, 0, 1) * (RANGES[k][1] - RANGES[k][0]))
            for k, x in zip(KEYS, v)}


def fit(folder, name, tile_m, generations, out):
    rg.PARAMS, rg.RANGES, rg.KEYS = PARAMS, RANGES, KEYS
    rg.render, rg.vector, rg.decode = render, vector, decode
    rg.fit(folder, name, tile_m, generations, out)


if __name__ == "__main__":
    if sys.argv[1] == "fit":
        fit(sys.argv[2], sys.argv[3], float(sys.argv[4]), int(sys.argv[5]) if len(sys.argv) > 5 else 250,
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_smooth.json")
