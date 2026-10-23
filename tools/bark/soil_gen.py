"""A procedural fine soil height field (numba) and its fit to a photographed one (Poly Haven forest ground, CC0).

Fine soil is flat with speckle: noise at three scales, sparse small pebbles and hair-thin twigs, soft clods.
Same loop and loss as the bark (rock_gen.fit with this module's parameters).

  python soil_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import json
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "clod_cm": 12.0, "clod_amp": 0.25, "grain_cm": 1.2, "grain_amp": 0.12, "dust_cm": 0.35, "dust_amp": 0.08,
    "pebble_cm": 4.0, "pebble_cover": 0.2, "pebble_size": 0.25, "pebble_amp": 0.35,
    "twig_cm": 16.0, "twig_cover": 0.2, "twig_w": 0.05, "twig_amp": 0.3, "crumb_cm": 3.0, "crumb_amp": 0.1,
}
RANGES = {
    "clod_cm": (4.0, 40.0), "clod_amp": (0.0, 0.5), "grain_cm": (0.5, 4.0), "grain_amp": (0.0, 0.3),
    "dust_cm": (0.15, 1.0), "dust_amp": (0.0, 0.25), "pebble_cm": (1.5, 10.0), "pebble_cover": (0.0, 0.6),
    "pebble_size": (0.1, 0.45), "pebble_amp": (0.0, 0.5), "twig_cm": (6.0, 40.0), "twig_cover": (0.0, 0.3),
    "twig_w": (0.01, 0.05), "twig_amp": (0.0, 0.2), "crumb_cm": (1.0, 8.0), "crumb_amp": (0.0, 0.3),
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
def _soil_at(px, py, q, seed):
    clod_cm, clod_amp, grain_cm, grain_amp, dust_cm, dust_amp = q[0], q[1], q[2], q[3], q[4], q[5]
    pebble_cm, pebble_cover, pebble_size, pebble_amp = q[6], q[7], q[8], q[9]
    twig_cm, twig_cover, twig_w, twig_amp, crumb_cm, crumb_amp = q[10], q[11], q[12], q[13], q[14], q[15]
    h = 0.5
    h += clod_amp * (_noise(px / clod_cm, py / clod_cm, seed + 1.0) - 0.5)
    h += grain_amp * (_noise(px / grain_cm, py / grain_cm, seed + 2.0) - 0.5)
    h += dust_amp * (_noise(px / dust_cm, py / dust_cm, seed + 3.0) - 0.5)
    h += crumb_amp * (abs(_noise(px / crumb_cm, py / crumb_cm, seed + 4.0) - 0.5) * 2.0 - 0.5)
    # pebbles
    cx0, cy0 = np.floor(px / pebble_cm), np.floor(py / pebble_cm)
    best = 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = cx0 + ox, cy0 + oy
            if _hash(cx, cy, seed + 11.0) < pebble_cover:
                kx = (cx + 0.2 + 0.6 * _hash(cx, cy, seed + 13.0)) * pebble_cm
                ky = (cy + 0.2 + 0.6 * _hash(cx, cy, seed + 15.0)) * pebble_cm
                r = pebble_cm * pebble_size * (0.5 + _hash(cx, cy, seed + 17.0))
                d = np.sqrt((px - kx) ** 2 + (py - ky) ** 2)
                best = max(best, 1.0 - _smooth(r * 0.5, r, d))
    h += pebble_amp * best
    # twigs: thin straight segments, each in a cell with its own direction
    tx0, ty0 = np.floor(px / twig_cm), np.floor(py / twig_cm)
    tw = 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = tx0 + ox, ty0 + oy
            if _hash(cx, cy, seed + 21.0) < twig_cover:
                kx = (cx + _hash(cx, cy, seed + 23.0)) * twig_cm
                ky = (cy + _hash(cx, cy, seed + 25.0)) * twig_cm
                ang = _hash(cx, cy, seed + 27.0) * 3.14159
                length = twig_cm * (0.3 + 0.5 * _hash(cx, cy, seed + 29.0))
                dx, dy = px - kx, py - ky
                along = dx * np.cos(ang) + dy * np.sin(ang)
                across = -dx * np.sin(ang) + dy * np.cos(ang)
                if abs(along) < length:
                    tw = max(tw, 1.0 - _smooth(0.0, twig_w * twig_cm, abs(across)))
    h += twig_amp * tw
    return h


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _soil_at((col + 0.5) * cm_per_px, py, q, seed)
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
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_soil.json")
