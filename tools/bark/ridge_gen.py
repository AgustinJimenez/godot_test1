"""A procedural ridged bark height field (numba) and its fit (Poly Haven ash bark, CC0).

Long vertical ridges that wander sideways, split by grooves; short cross cuts break the ridges into
segments; each ridge swells and thins along its length. Same loop and loss as the bark
(rock_gen.fit with this module's parameters).

  python ridge_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "ridge_cm": 3.0, "ridge_var": 0.4, "groove_w": 0.3, "groove_depth": 0.5, "wander_cm": 25.0,
    "wander_amp": 1.0, "swell_cm": 14.0, "swell_amp": 0.25, "cut_cm": 6.0, "cut_cover": 0.3,
    "cut_w": 0.12, "cut_depth": 0.4, "fine_cm": 1.0, "fine_amp": 0.1, "tone_amp": 0.15,
}
RANGES = {
    "ridge_cm": (1.5, 6.0), "ridge_var": (0.0, 0.8), "groove_w": (0.1, 0.6), "groove_depth": (0.2, 0.9),
    "wander_cm": (8.0, 60.0), "wander_amp": (0.0, 2.5), "swell_cm": (6.0, 40.0), "swell_amp": (0.0, 0.5),
    "cut_cm": (3.0, 14.0), "cut_cover": (0.0, 0.6), "cut_w": (0.05, 0.3), "cut_depth": (0.0, 0.7),
    "fine_cm": (0.4, 3.0), "fine_amp": (0.0, 0.25), "tone_amp": (0.0, 0.4),
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
def _ridge_at(px, py, q, seed):
    ridge_cm, ridge_var, groove_w, groove_depth, wander_cm, wander_amp = q[0], q[1], q[2], q[3], q[4], q[5]
    swell_cm, swell_amp, cut_cm, cut_cover, cut_w, cut_depth = q[6], q[7], q[8], q[9], q[10], q[11]
    fine_cm, fine_amp, tone_amp = q[12], q[13], q[14]
    x = px + wander_amp * ridge_cm * 2.0 * (_noise(px / ridge_cm * 0.0 + py / wander_cm, px / wander_cm, seed + 1.0) - 0.5)
    col_f = x / ridge_cm
    col = np.floor(col_f)
    jit = (_hash(col, 0.0, seed + 2.0) - 0.5) * ridge_var
    local = col_f - col - jit
    across = min(max(local, 0.0), 1.0)
    ridge_id = np.floor(col_f - jit)
    groove = 1.0 - _smooth(0.0, groove_w, min(across, 1.0 - across))
    tone = (_hash(ridge_id, 0.0, seed + 3.0) - 0.5) * tone_amp
    along = swell_amp * (_noise(py / swell_cm, ridge_id * 3.7, seed + 4.0) - 0.5)
    # cross cuts: a segment boundary per ridge every cut_cm along y, only in some places
    seg = py / cut_cm + _hash(ridge_id, 0.0, seed + 5.0) * 7.0
    seg_i = np.floor(seg)
    cut = 0.0
    if _hash(ridge_id, seg_i, seed + 6.0) < cut_cover:
        cut = 1.0 - _smooth(0.0, cut_w, min(seg - seg_i, 1.0 - (seg - seg_i)))
    fine = fine_amp * (_noise(px / fine_cm, py / fine_cm, seed + 7.0) - 0.5)
    h = 0.6 + tone + along + fine
    return h * (1.0 - groove_depth * groove) * (1.0 - cut_depth * cut)


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _ridge_at((col + 0.5) * cm_per_px, py, q, seed)
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
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_ridge.json")
