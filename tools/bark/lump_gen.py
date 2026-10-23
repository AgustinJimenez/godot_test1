"""A procedural rock height field (numba): smooth lumps cut by creased valleys, with pockets of rubble (Poly Haven rock faces).

Lumps: a domain-warped low-frequency noise; creases: 1 - |noise| of a second warped noise, cut into the lumps
as narrow valleys; rubble: a small Voronoi of sharp fragments inside the deepest creases; grain: fine speckle.
Same loop and loss as the bark (rock_gen.fit with this module's parameters).

  python lump_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "lump_cm": 40.0, "lump_amp": 0.5, "warp_cm": 30.0, "warp_amp": 0.5, "crease_cm": 35.0, "crease_w": 0.08,
    "crease_depth": 0.5, "crease_warp": 0.4, "rub_cm": 2.5, "rub_amp": 0.3, "rub_reach": 0.5,
    "grain_cm": 3.0, "grain_amp": 0.04, "mid_cm": 9.0, "mid_amp": 0.0,
}
RANGES = {
    "lump_cm": (15.0, 90.0), "lump_amp": (0.1, 0.8), "warp_cm": (10.0, 80.0), "warp_amp": (0.0, 1.0),
    "crease_cm": (15.0, 80.0), "crease_w": (0.02, 0.2), "crease_depth": (0.1, 1.0), "crease_warp": (0.0, 1.0),
    "rub_cm": (1.2, 5.0), "rub_amp": (0.0, 0.6), "rub_reach": (0.1, 1.0), "grain_cm": (1.5, 8.0),
    "grain_amp": (0.0, 0.1), "mid_cm": (4.0, 16.0), "mid_amp": (0.0, 0.5),
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
def _lump_at(px, py, q, seed):
    lump_cm, lump_amp, warp_cm, warp_amp, crease_cm, crease_w, crease_depth = q[0], q[1], q[2], q[3], q[4], q[5], q[6]
    crease_warp, rub_cm, rub_amp, rub_reach, grain_cm, grain_amp = q[7], q[8], q[9], q[10], q[11], q[12]
    mid_cm, mid_amp = q[13], q[14]
    wx = px + warp_amp * warp_cm * (_noise(px / warp_cm, py / warp_cm, seed + 1.0) - 0.5)
    wy = py + warp_amp * warp_cm * (_noise(px / warp_cm + 7.0, py / warp_cm, seed + 2.0) - 0.5)
    lumps = _noise(wx / lump_cm, wy / lump_cm, seed + 3.0) + 0.5 * _noise(wx / (lump_cm * 0.5), wy / (lump_cm * 0.5), seed + 4.0)
    lumps = lumps / 1.5
    cx = px + crease_warp * crease_cm * (_noise(px / crease_cm, py / crease_cm, seed + 5.0) - 0.5)
    cy = py + crease_warp * crease_cm * (_noise(px / crease_cm + 3.0, py / crease_cm, seed + 6.0) - 0.5)
    line = abs(_noise(cx / crease_cm, cy / crease_cm, seed + 7.0) - 0.5) * 2.0  # 0 on a crease
    crease = 1.0 - _smooth(0.0, crease_w * 2.0, line)
    h = 0.5 + lump_amp * (lumps - 0.5) - crease_depth * crease
    # rubble: sharp fragments (Voronoi) inside and next to the creases
    ux, uy = px / rub_cm, py / rub_cm
    iu, iv = np.floor(ux), np.floor(uy)
    best = 1e9
    best_id = 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            gx, gy = iu + ox, iv + oy
            fx = gx + _hash(gx, gy, seed + 11.0)
            fy = gy + _hash(gx, gy, seed + 13.0)
            d = (ux - fx) ** 2 + (uy - fy) ** 2
            if d < best:
                best = d
                best_id = _hash(gx, gy, seed + 15.0)
    reach = _smooth(1.0 - rub_reach, 1.0, crease)
    h += rub_amp * (best_id - 0.5) * reach
    h += grain_amp * (_noise(px / grain_cm, py / grain_cm, seed + 17.0) - 0.5)
    # a middle octave: the cloudy mottling of weathered stone (two noises, the second turned, so it has no grid)
    h += mid_amp * (0.5 * _noise(wx / mid_cm, wy / mid_cm, seed + 19.0) + 0.5 * _noise(wy / mid_cm * 1.3 + 5.0, wx / mid_cm * 0.8, seed + 21.0) - 0.5)
    return h


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _lump_at((col + 0.5) * cm_per_px, py, q, seed)
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
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_lump.json")
