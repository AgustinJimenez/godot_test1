"""A procedural plated bark height field (numba): flat plates side by side with thin cracks (pine, Poly Haven).

Voronoi cells stretched along the trunk; each plate has its own height, tilt and a rounded lip; the
cell edges are warped by noise so they are ragged; cracks are the gaps between plates. Same loop and loss
as the bark (rock_gen.fit with this module's parameters).

  python plate_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "cell_cm": 8.0, "stretch": 2.0, "jit": 0.8, "warp_cm": 6.0, "warp_amp": 0.25, "crack_w": 0.08,
    "crack_depth": 0.6, "lip": 0.2, "z_var": 0.3, "tilt": 0.3, "fine_cm": 1.0, "fine_amp": 0.05,
    "rag_cm": 1.5, "rag_amp": 0.05,
}
RANGES = {
    "cell_cm": (3.0, 14.0), "stretch": (1.0, 3.5), "jit": (0.3, 1.0), "warp_cm": (2.0, 20.0),
    "warp_amp": (0.0, 0.6), "crack_w": (0.02, 0.2), "crack_depth": (0.2, 0.9), "lip": (0.02, 0.5),
    "z_var": (0.0, 0.6), "tilt": (0.0, 0.8), "fine_cm": (0.4, 3.0), "fine_amp": (0.0, 0.15),
    "rag_cm": (0.6, 3.0), "rag_amp": (0.0, 0.2),
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
def _plate_at(px, py, q, seed, guide, guide_mix, tile_cm):
    cell_cm, stretch, jit, warp_cm, warp_amp, crack_w, crack_depth = q[0], q[1], q[2], q[3], q[4], q[5], q[6]
    lip, z_var, tilt, fine_cm, fine_amp, rag_cm, rag_amp = q[7], q[8], q[9], q[10], q[11], q[12], q[13]
    # ragged, warped lookup position; cells are cell_cm wide and cell_cm * stretch tall
    wx = px + cell_cm * warp_amp * 2.0 * (_noise(px / warp_cm, py / warp_cm, seed + 1.0) - 0.5)
    wy = py + cell_cm * warp_amp * 2.0 * (_noise(px / warp_cm + 9.0, py / warp_cm, seed + 2.0) - 0.5)
    wx += cell_cm * rag_amp * 2.0 * (_noise(px / rag_cm, py / rag_cm, seed + 3.0) - 0.5)
    u = wx / cell_cm
    v = wy / (cell_cm * stretch)
    iu, iv = np.floor(u), np.floor(v)
    d1 = 1e9
    d2 = 1e9
    best_id_u, best_id_v = 0.0, 0.0
    best_dx, best_dy = 0.0, 0.0
    best_fx, best_fy = 0.0, 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = iu + ox, iv + oy
            fx = cx + 0.5 + (_hash(cx, cy, seed + 5.0) - 0.5) * jit
            fy = cy + 0.5 + (_hash(cx, cy, seed + 7.0) - 0.5) * jit
            dx, dy = u - fx, (v - fy) * stretch * 0.6 + 0.0
            d = np.sqrt(dx * dx + dy * dy)
            if d < d1:
                d2 = d1
                d1 = d
                best_id_u, best_id_v = cx, cy
                best_dx, best_dy = dx, dy
                best_fx, best_fy = fx, fy
            elif d < d2:
                d2 = d
    edge = d2 - d1
    crack = 1.0 - _smooth(0.0, crack_w, edge)
    lipf = _smooth(0.0, lip, edge)
    # the guide: the photograph's own height at the plate's centre (a small picture), mixed into the plate's height
    gx = (best_fx * cell_cm) / tile_cm * guide.shape[1]
    gy = (best_fy * cell_cm * stretch) / tile_cm * guide.shape[0]
    gi = int(gy) % guide.shape[0]
    gj = int(gx) % guide.shape[1]
    g = guide[gi, gj]
    z = 0.7 + z_var * (_hash(best_id_u, best_id_v, seed + 11.0) - 0.5)
    z = z * (1.0 - guide_mix) + (0.35 + 0.7 * g) * guide_mix
    z += tilt * (best_dx * (_hash(best_id_u, best_id_v, seed + 13.0) - 0.5)
                 + best_dy * (_hash(best_id_u, best_id_v, seed + 15.0) - 0.5))
    z += fine_amp * (_noise(px / fine_cm, py / fine_cm, seed + 17.0) - 0.5)
    h = z * (0.7 + 0.3 * lipf)
    return h * (1.0 - crack_depth * crack)


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed, guide, guide_mix, tile_cm):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _plate_at((col + 0.5) * cm_per_px, py, q, seed, guide, guide_mix, tile_cm)
    return out


def vector(params):
    return np.array([params.get(k, PARAMS[k]) for k in KEYS], dtype=np.float64)


def render(params, size, cm_per_px, seed=1.0, guide=None, guide_mix=0.0, tile_cm=200.0):
    if guide is None:
        guide = np.zeros((1, 1), np.float32)
    h = _render(size, cm_per_px, vector(params), seed, guide.astype(np.float32), guide_mix, tile_cm)
    h = h - h.min()
    return h / max(float(h.max()), 1e-6)


def decode(v):
    return {k: float(RANGES[k][0] + np.clip(x, 0, 1) * (RANGES[k][1] - RANGES[k][0]))
            for k, x in zip(KEYS, v)}


