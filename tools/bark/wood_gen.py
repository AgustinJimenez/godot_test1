"""A procedural wooden board surface (numba) and its fit to a photographed one (Poly Haven planks, CC0).

Horizontal boards (x along the board, y across): each board has its own width share, tone and grain offset;
the seams between boards are low lines; the grain is thin parallel lines that wave slowly along the board
and bend round knots (growth-ring ovals); a few knots and scratches. Fitted with the same loop and loss as
the bark (rock_gen.fit with this module's parameters).

  python wood_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import json
import sys

import limits  # (first)

import cv2
import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "board_cm": 17.0, "board_var": 0.3, "seam_w": 0.05, "seam_depth": 0.5, "board_tone": 0.25,
    "grain_cm": 0.9, "grain_amp": 0.2, "grain_wave_cm": 30.0, "grain_wave": 0.8, "grain_sharp": 1.5,
    "knot_cm": 60.0, "knot_cover": 0.3, "knot_rings": 8.0, "knot_amp": 0.2,
    "fine_amp": 0.05, "fine_cm": 0.6, "swell_amp": 0.2, "swell_cm": 40.0, "pore_amp": 0.1, "pore_cm": 0.25,
}
RANGES = {
    "board_cm": (6.0, 40.0), "board_var": (0.0, 0.6), "seam_w": (0.01, 0.15), "seam_depth": (0.0, 1.0),
    "board_tone": (0.0, 0.6), "grain_cm": (0.3, 3.0), "grain_amp": (0.0, 0.6), "grain_wave_cm": (10.0, 90.0),
    "grain_wave": (0.0, 3.0), "grain_sharp": (0.5, 4.0), "knot_cm": (25.0, 70.0), "knot_cover": (0.0, 0.5),
    "knot_rings": (3.0, 9.0), "knot_amp": (0.0, 0.12), "fine_amp": (0.0, 0.2), "fine_cm": (0.2, 2.0),
    "swell_amp": (0.0, 0.08), "swell_cm": (10.0, 40.0), "pore_amp": (0.0, 0.4), "pore_cm": (0.1, 0.8),
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
def _wood_at(px, py, q, seed):
    board_cm, board_var, seam_w, seam_depth, board_tone = q[0], q[1], q[2], q[3], q[4]
    grain_cm, grain_amp, wave_cm, wave, sharp = q[5], q[6], q[7], q[8], q[9]
    knot_cm, knot_cover, knot_rings, knot_amp = q[10], q[11], q[12], q[13]
    fine_amp, fine_cm, swell_amp, swell_cm, pore_amp, pore_cm = q[14], q[15], q[16], q[17], q[18], q[19]
    # boards: rows across y; each row has its own width factor (a jittered row edge)
    row_f = py / board_cm
    row = np.floor(row_f)
    edge_jit = (_hash(row, 0.0, seed + 1.0) - 0.5) * board_var
    local = row_f - row - edge_jit
    seam = 1.0 - _smooth(0.0, seam_w, min(local, 1.0 - local) * 2.0) if (local > -0.5 and local < 1.5) else 0.0
    row_id = _hash(np.floor(row_f - edge_jit), 0.0, seed + 3.0)
    tone = (row_id - 0.5) * board_tone
    shift = _hash(np.floor(row_f - edge_jit), 0.0, seed + 5.0) * 1000.0
    # knots: points on a coarse grid, rings of growth round them bend the grain
    kcx, kcy = np.floor(px / knot_cm), np.floor(py / knot_cm)
    bend = 0.0
    ring = 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = kcx + ox, kcy + oy
            if _hash(cx, cy, seed + 11.0) < knot_cover:
                kx = (cx + 0.2 + 0.6 * _hash(cx, cy, seed + 13.0)) * knot_cm
                ky = (cy + 0.2 + 0.6 * _hash(cx, cy, seed + 15.0)) * knot_cm
                dx, dy = (px - kx) / 2.2, py - ky
                d = np.sqrt(dx * dx + dy * dy)
                r = knot_cm * 0.28
                w = 1.0 - _smooth(0.0, r, d)
                bend += w * 6.0
                ring += w * np.sin(d / r * knot_rings * 3.14159)
    # grain: thin lines across y, waving along x, bent by knots
    wob = (_noise(px / wave_cm, py / (wave_cm * 0.5), seed + 21.0) - 0.5) * wave * grain_cm * 4.0
    u = (py + wob + bend + shift) / grain_cm
    line = np.abs(_fract(u) - 0.5) * 2.0
    grain = (line ** sharp - 0.4) * grain_amp
    swell = swell_amp * (_noise(px / swell_cm, py / (swell_cm * 0.4), seed + 31.0) - 0.5)
    fine = fine_amp * (_noise(px / fine_cm, py / (fine_cm * 0.5), seed + 41.0) - 0.5)
    pores = pore_amp * (_noise(px / pore_cm, py / (pore_cm * 3.0), seed + 51.0) - 0.5)
    h = 0.5 + tone + grain + swell + fine + pores + knot_amp * ring * 0.2
    return h * (1.0 - seam_depth * seam)


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _wood_at((col + 0.5) * cm_per_px, py, q, seed)
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
    # the rock fit with this module's generator: its globals are swapped (the loop is the same)
    rg.PARAMS, rg.RANGES, rg.KEYS = PARAMS, RANGES, KEYS
    rg.render, rg.vector, rg.decode = render, vector, decode
    rg.fit(folder, name, tile_m, generations, out)


if __name__ == "__main__":
    if sys.argv[1] == "fit":
        fit(sys.argv[2], sys.argv[3], float(sys.argv[4]), int(sys.argv[5]) if len(sys.argv) > 5 else 250,
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_wood.json")
