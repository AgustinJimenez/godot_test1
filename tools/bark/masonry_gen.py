"""A procedural dry-stone / masonry wall height field (numba) and its fit (Poly Haven rock walls, CC0).

Courses (rows) of stones: each course has its own height, each stone its own width, height above the mortar,
rounded corners and a slight tilt; the mortar between them is low; the stone's face is a soft swell with grain.
Same loop and loss as the bark (rock_gen.fit with this module's parameters).

  python masonry_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import json
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "course_cm": 22.0, "course_var": 0.35, "stone_cm": 32.0, "stone_var": 0.5, "gap_cm": 3.0, "gap_depth": 0.5,
    "round": 0.35, "face_var": 0.25, "tilt": 0.2, "swell": 0.2, "grain_cm": 2.0, "grain_amp": 0.06,
    "skew": 0.3, "chip_cover": 0.15, "chip_depth": 0.2,
}
RANGES = {
    "course_cm": (8.0, 22.0), "course_var": (0.2, 0.7), "stone_cm": (10.0, 38.0), "stone_var": (0.3, 0.9),
    "gap_cm": (0.5, 8.0), "gap_depth": (0.1, 1.0), "round": (0.05, 0.9), "face_var": (0.0, 0.6),
    "tilt": (0.0, 0.5), "swell": (0.0, 0.5), "grain_cm": (0.5, 6.0), "grain_amp": (0.0, 0.2),
    "skew": (0.0, 1.0), "chip_cover": (0.0, 0.5), "chip_depth": (0.0, 0.5),
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
def _wall_at(px, py, q, seed):
    course_cm, course_var, stone_cm, stone_var, gap_cm, gap_depth = q[0], q[1], q[2], q[3], q[4], q[5]
    rnd, face_var, tilt, swell, grain_cm, grain_amp, skew, chip_cover, chip_depth = (
        q[6], q[7], q[8], q[9], q[10], q[11], q[12], q[13], q[14])
    # the course: rows of jittered height (the edges between rows move with the x position a little: skew)
    ycur = py + skew * 6.0 * (_noise(px / 60.0, py / 60.0, seed + 5.0) - 0.5)
    row = np.floor(ycur / course_cm)
    row_h = course_cm * (1.0 + (_hash(row, 0.0, seed + 1.0) - 0.5) * course_var)
    row0 = row * course_cm
    # inside the row: stones of random widths, laid by cumulative sum from a row offset
    xoff = _hash(row, 0.0, seed + 3.0) * stone_cm
    xs = px + xoff
    cell = np.floor(xs / stone_cm)
    # a stone boundary inside a cell is placed at a random place; the stone is the nearer of two neighbours' widths
    b0 = (cell + 0.5 + (_hash(cell, row, seed + 7.0) - 0.5) * stone_var) * stone_cm
    b1 = (cell + 1.5 + (_hash(cell + 1.0, row, seed + 7.0) - 0.5) * stone_var) * stone_cm
    bm1 = (cell - 0.5 + (_hash(cell - 1.0, row, seed + 7.0) - 0.5) * stone_var) * stone_cm
    if xs < b0:
        left, right, sid = bm1, b0, cell - 1.0 + 100.0 * row
    else:
        left, right, sid = b0, b1, cell + 100.0 * row
    width = max(right - left, 1.0)
    u = (xs - left) / width
    v = (ycur - row0) / row_h
    # distance to the stone's edge (rounded rectangle) in cm
    dx = min(u, 1.0 - u) * width
    dy = min(v, 1.0 - v) * row_h
    edge = min(dx, dy)
    corner = min(dx, dy) if (dx < rnd * 12.0 and dy < rnd * 12.0) else edge
    mortar = 1.0 - _smooth(0.0, gap_cm, edge * 0.5 + 0.5 * corner)
    tone = _hash(sid, 0.0, seed + 11.0)
    face = 0.62 + face_var * (tone - 0.5)
    face += tilt * ((u - 0.5) * (_hash(sid, 1.0, seed + 13.0) - 0.5) + (v - 0.5) * (_hash(sid, 2.0, seed + 15.0) - 0.5))
    face += swell * (1.0 - 4.0 * ((u - 0.5) ** 2 + (v - 0.5) ** 2)) * 0.5
    face += grain_amp * (_noise(px / grain_cm, py / grain_cm, seed + 17.0) - 0.5)
    chip = chip_depth * (1.0 if _hash(sid, 3.0, seed + 19.0) < chip_cover and u < 0.25 and v > 0.7 else 0.0)
    return face * (1.0 - gap_depth * mortar) - chip


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _wall_at((col + 0.5) * cm_per_px, py, q, seed)
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
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_wall.json")
