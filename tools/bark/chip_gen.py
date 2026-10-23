"""A procedural gravel height field (numba): angular chips of three size classes lying on fine grit (ambientCG gravel).

Each size class is a jittered Voronoi grid; a cell holds a chip with some probability; the chip is the cell shrunk by a
gap, flat-topped with its own height and tilt, so its outline is a convex polygon (angular), its top lit like a plate.
Chips of the larger class lie over the smaller ones (max height). The ground is soft noise.
Same loop and loss as the bark (rock_gen.fit with this module's parameters).

  python chip_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import json
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "big_cm": 14.0, "big_cover": 0.25, "mid_cm": 6.0, "mid_cover": 0.5, "small_cm": 2.5, "small_cover": 0.7,
    "gap": 0.12, "jit": 0.8, "tilt": 0.4, "z_var": 0.4, "base_amp": 0.15, "base_cm": 25.0,
    "grit_cm": 0.6, "grit_amp": 0.08,
}
RANGES = {
    "big_cm": (8.0, 30.0), "big_cover": (0.0, 0.6), "mid_cm": (3.0, 12.0), "mid_cover": (0.1, 0.9),
    "small_cm": (1.2, 5.0), "small_cover": (0.2, 1.0), "gap": (0.03, 0.3), "jit": (0.3, 1.0),
    "tilt": (0.0, 0.8), "z_var": (0.1, 0.8), "base_amp": (0.0, 0.4), "base_cm": (10.0, 60.0),
    "grit_cm": (0.4, 2.0), "grit_amp": (0.0, 0.2),
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
def _layer(px, py, cell_cm, cover, gap, jit, tilt, z_var, seed):
    """Height of the chip under (px, py) in one size class, or -1 when there is none."""
    u, v = px / cell_cm, py / cell_cm
    iu, iv = np.floor(u), np.floor(v)
    d1, d2 = 1e9, 1e9
    bid = 0.0
    bdx, bdy = 0.0, 0.0
    bcx, bcy = 0.0, 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = iu + ox, iv + oy
            fx = cx + 0.5 + (_hash(cx, cy, seed + 1.0) - 0.5) * jit
            fy = cy + 0.5 + (_hash(cx, cy, seed + 2.0) - 0.5) * jit
            dx, dy = u - fx, v - fy
            d = np.sqrt(dx * dx + dy * dy)
            if d < d1:
                d2 = d1
                d1 = d
                bcx, bcy = cx, cy
                bdx, bdy = dx, dy
            elif d < d2:
                d2 = d
    if _hash(bcx, bcy, seed + 3.0) > cover:
        return -1.0
    inside = _smooth(0.0, gap, d2 - d1)
    if inside < 0.5:
        return -1.0
    z = 0.6 + z_var * (_hash(bcx, bcy, seed + 4.0) - 0.5)
    z += tilt * (bdx * (_hash(bcx, bcy, seed + 5.0) - 0.5) + bdy * (_hash(bcx, bcy, seed + 6.0) - 0.5))
    return z


@njit(cache=True)
def _chip_at(px, py, q, seed):
    big_cm, big_cover, mid_cm, mid_cover, small_cm, small_cover = q[0], q[1], q[2], q[3], q[4], q[5]
    gap, jit, tilt, z_var, base_amp, base_cm, grit_cm, grit_amp = q[6], q[7], q[8], q[9], q[10], q[11], q[12], q[13]
    h = 0.25 + base_amp * (_noise(px / base_cm, py / base_cm, seed + 1.0) - 0.5)
    h += grit_amp * (_noise(px / grit_cm, py / grit_cm, seed + 2.0) - 0.5)
    z = _layer(px, py, small_cm, small_cover, gap, jit, tilt, z_var, seed + 10.0)
    if z > 0.0:
        h = max(h, 0.3 + 0.3 * z)
    z = _layer(px, py, mid_cm, mid_cover, gap, jit, tilt, z_var, seed + 20.0)
    if z > 0.0:
        h = max(h, 0.45 + 0.3 * z)
    z = _layer(px, py, big_cm, big_cover, gap, jit, tilt, z_var, seed + 30.0)
    if z > 0.0:
        h = max(h, 0.6 + 0.3 * z)
    return h


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _chip_at((col + 0.5) * cm_per_px, py, q, seed)
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
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_chips.json")
