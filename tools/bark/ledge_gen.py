"""A procedural rock height field (numba): stacked horizontal ledges with overhanging lips and vertical joints (layered rock).

Ledges: rows of jittered thickness, each tilted a little (its top rises), ending below in a sharp step (the lip
overhangs the ledge under it); blocks: vertical joints at jittered spacing inside each ledge; rubble in the joints;
the whole wavers sideways (domain warp). Grain: fine speckle.
Same loop and loss as the bark (rock_gen.fit with this module's parameters).

  python ledge_gen.py fit <folder> <name> <tile metres> [generations] [out json]
"""
import sys

import limits  # (first)

import numpy as np
from numba import njit, prange

import rock_gen as rg

PARAMS = {
    "ledge_cm": 18.0, "ledge_var": 0.5, "tilt": 0.3, "lip_w": 0.12, "lip_depth": 0.4, "block_cm": 30.0,
    "block_var": 0.5, "joint_w": 0.05, "joint_depth": 0.4, "joint_cover": 0.6, "warp_cm": 40.0,
    "warp_amp": 0.4, "rub_cm": 2.5, "rub_amp": 0.2, "grain_cm": 2.0, "grain_amp": 0.03, "tone_amp": 0.15,
}
RANGES = {
    "ledge_cm": (8.0, 40.0), "ledge_var": (0.1, 0.9), "tilt": (0.0, 0.8), "lip_w": (0.03, 0.3),
    "lip_depth": (0.1, 0.8), "block_cm": (15.0, 70.0), "block_var": (0.1, 0.9), "joint_w": (0.02, 0.12),
    "joint_depth": (0.1, 0.8), "joint_cover": (0.1, 1.0), "warp_cm": (15.0, 90.0), "warp_amp": (0.0, 1.0),
    "rub_cm": (1.2, 5.0), "rub_amp": (0.0, 0.5), "grain_cm": (1.5, 5.0), "grain_amp": (0.0, 0.08),
    "tone_amp": (0.0, 0.4),
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
def _ledge_at(px, py, q, seed):
    ledge_cm, ledge_var, tilt, lip_w, lip_depth, block_cm, block_var = q[0], q[1], q[2], q[3], q[4], q[5], q[6]
    joint_w, joint_depth, joint_cover, warp_cm, warp_amp, rub_cm, rub_amp = q[7], q[8], q[9], q[10], q[11], q[12], q[13]
    grain_cm, grain_amp, tone_amp = q[14], q[15], q[16]
    x = px + warp_amp * warp_cm * (_noise(px / warp_cm, py / warp_cm, seed + 1.0) - 0.5)
    y = py + warp_amp * warp_cm * 0.6 * (_noise(px / warp_cm + 9.0, py / warp_cm, seed + 2.0) - 0.5)
    row_f = y / ledge_cm
    row = np.floor(row_f)
    edge = (_hash(row, 0.0, seed + 3.0) - 0.5) * ledge_var
    local = row_f - row - edge          # 0 at the ledge's lower edge, 1 at its top
    rid = np.floor(row_f - edge)
    top = min(max(local, 0.0), 1.0)
    # the top face rises with the tilt; the lip is the sharp step at the lower edge
    z = 0.45 + tilt * 0.4 * top + (_hash(rid, 0.0, seed + 4.0) - 0.5) * tone_amp
    lip = _smooth(0.0, lip_w, top)
    z = z - lip_depth * (1.0 - lip)
    # vertical joints between blocks (each ledge its own spacing offset)
    bx = x / block_cm + _hash(rid, 1.0, seed + 5.0) * 7.0
    bi = np.floor(bx)
    bedge = abs(bx - bi - 0.5) * 2.0   # 1 at the joint
    jx = (_hash(bi, rid, seed + 6.0) - 0.5) * block_var
    has_joint = 1.0 if _hash(bi, rid, seed + 7.0) < joint_cover else 0.0
    joint = has_joint * (1.0 - _smooth(0.0, joint_w * 8.0, (1.0 - bedge) + jx * 0.0))
    z = z - joint_depth * joint
    # rubble in the joints and under the lips
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
    pocket = max(joint, 1.0 - lip)
    z += rub_amp * (best_id - 0.5) * pocket
    z += grain_amp * (_noise(px / grain_cm, py / grain_cm, seed + 17.0) - 0.5)
    return z


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _ledge_at((col + 0.5) * cm_per_px, py, q, seed)
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
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_ledge.json")
