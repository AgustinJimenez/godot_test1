"""A procedural ringed trunk height field (numba): soft horizontal ring bands over vertical fibre streaks (palm, Poly Haven).

Rings: raised or sunken bands across the trunk at jittered spacing, each with a soft edge and its own tone,
wavering along the trunk; fibres: thin vertical streaks of random strength; blotches and fine speckle.
Same loop and loss as the bark (rock_gen.fit with this module's parameters).

  python ring_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "ring_cm": 25.0, "ring_var": 0.4, "ring_w": 0.25, "ring_amp": 0.3, "ring_wave_cm": 40.0, "ring_wave": 0.3,
    "tone_amp": 0.15, "fibre_cm": 1.5, "fibre_amp": 0.1, "fibre_len_cm": 40.0, "blotch_cm": 12.0,
    "blotch_amp": 0.15, "fine_cm": 0.6, "fine_amp": 0.03,
}
RANGES = {
    "ring_cm": (8.0, 60.0), "ring_var": (0.0, 0.9), "ring_w": (0.05, 0.5), "ring_amp": (0.0, 0.6),
    "ring_wave_cm": (15.0, 120.0), "ring_wave": (0.0, 1.0), "tone_amp": (0.0, 0.4), "fibre_cm": (0.5, 4.0),
    "fibre_amp": (0.0, 0.3), "fibre_len_cm": (15.0, 120.0), "blotch_cm": (4.0, 40.0), "blotch_amp": (0.0, 0.4),
    "fine_cm": (0.3, 2.0), "fine_amp": (0.0, 0.1),
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
def _ring_at(px, py, q, seed):
    ring_cm, ring_var, ring_w, ring_amp, wave_cm, wave, tone_amp = q[0], q[1], q[2], q[3], q[4], q[5], q[6]
    fibre_cm, fibre_amp, fibre_len, blotch_cm, blotch_amp, fine_cm, fine_amp = (
        q[7], q[8], q[9], q[10], q[11], q[12], q[13])
    # rings: the band row is found on a y that wavers with x; each band has a jittered centre, width and tone
    y = py + wave * ring_cm * 2.0 * (_noise(px / wave_cm, py / (wave_cm * 2.0), seed + 1.0) - 0.5)
    row = np.floor(y / ring_cm)
    centre = (row + 0.5 + (_hash(row, 0.0, seed + 2.0) - 0.5) * ring_var) * ring_cm
    width = ring_cm * ring_w * (0.6 + 0.8 * _hash(row, 0.0, seed + 3.0))
    band = 1.0 - _smooth(0.0, width, abs(y - centre))
    sign = 1.0 if _hash(row, 0.0, seed + 4.0) < 0.5 else -0.6
    tone = (_hash(row, 0.0, seed + 5.0) - 0.5) * tone_amp
    # fibres: vertical streaks, each column with its own strength, long along y
    fib = _noise(px / fibre_cm, py / fibre_len, seed + 6.0) - 0.5
    blotch = _noise(px / blotch_cm, py / blotch_cm, seed + 7.0) - 0.5
    fine = _noise(px / fine_cm, py / fine_cm, seed + 8.0) - 0.5
    return 0.5 + ring_amp * sign * band + tone + fibre_amp * fib + blotch_amp * blotch + fine_amp * fine


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _ring_at((col + 0.5) * cm_per_px, py, q, seed)
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
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_ring.json")
