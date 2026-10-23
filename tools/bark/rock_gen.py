"""A procedural rock height field (numba) and its fit to a photographed rock (Poly Haven, CC0).

Same loop as the bark (see AGENTS.md "Procedural surfaces fitted to photographs"): a generator with a
few parameters that span the real variety, a fit by the neural style loss, a picture to judge it by.
Coordinates are centimetres on the real rock, isotropic (a rock has no up and down).
Layers: warp, angular blocks cut by cracks (Voronoi), strata, a smooth swelling, grain, pits.

  python rock_gen.py fit <folder> <name> <tile metres> [generations] [out json]
  python rock_gen.py show <json> <png> [size px]
"""
import json
import os
import sys

import limits  # (first)

import cv2
import numpy as np
from numba import njit, prange

import bark_perceptual as perceptual

PARAMS = {
    "cell_cm": 14.0, "jit": 0.8, "crack_w": 0.12, "crack_depth": 0.5, "crack_cover": 0.6,
    "block_var": 0.35, "tilt": 0.3,
    "strata_cm": 10.0, "strata_amp": 0.1, "strata_angle": 0.4, "strata_warp": 0.6,
    "base_amp": 0.35, "base_cm": 30.0, "grain_amp": 0.05, "grain_cm": 1.2,
    "pit_cm": 5.0, "pit_cover": 0.2, "pit_depth": 0.25, "warp_cm": 4.0, "warp_scale_cm": 25.0,
    "rub_cm": 2.5, "rub_amp": 0.3, "rub_cover": 0.4, "rub_edge": 0.5,
}
RANGES = {
    "cell_cm": (4.0, 60.0), "jit": (0.3, 1.0), "crack_w": (0.03, 0.3), "crack_depth": (0.0, 1.0),
    "crack_cover": (0.0, 1.2), "block_var": (0.0, 0.8), "tilt": (0.0, 0.8),
    "strata_cm": (3.0, 40.0), "strata_amp": (0.0, 0.4), "strata_angle": (0.0, 3.14),
    "strata_warp": (0.0, 1.5), "base_amp": (0.0, 1.0), "base_cm": (8.0, 80.0), "grain_amp": (0.0, 0.2),
    "grain_cm": (0.4, 4.0), "pit_cm": (2.0, 14.0), "pit_cover": (0.0, 0.6), "pit_depth": (0.0, 0.8),
    "warp_cm": (0.0, 10.0), "warp_scale_cm": (8.0, 60.0),
    "rub_cm": (0.8, 6.0), "rub_amp": (0.0, 0.8), "rub_cover": (0.0, 1.2), "rub_edge": (0.0, 1.0),
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
def _rock_at(px, py, q, seed):
    cell, jit, crack_w, crack_depth, crack_cover = q[0], q[1], q[2], q[3], q[4]
    block_var, tilt = q[5], q[6]
    strata_cm, strata_amp, strata_angle, strata_warp = q[7], q[8], q[9], q[10]
    base_amp, base_cm, grain_amp, grain_cm = q[11], q[12], q[13], q[14]
    pit_cm, pit_cover, pit_depth, warp_cm, warp_scale = q[15], q[16], q[17], q[18], q[19]
    rub_cm, rub_amp, rub_cover, rub_edge = q[20], q[21], q[22], q[23]
    wx = (_noise(px / warp_scale, py / warp_scale, seed + 11.0) - 0.5) * 2.0
    wy = (_noise(px / warp_scale + 31.7, py / warp_scale, seed + 13.0) - 0.5) * 2.0
    x = px + wx * warp_cm
    y = py + wy * warp_cm
    # blocks and cracks: a jittered Voronoi
    ix, iy = np.floor(x / cell), np.floor(y / cell)
    fx, fy = x / cell - ix, y / cell - iy
    d1, d2 = 9.0, 9.0
    cid = 0.0
    rel_x, rel_y = 0.0, 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = ix + ox, iy + oy
            ax = ox + 0.5 + (_hash(cx, cy, seed) - 0.5) * jit - fx
            ay = oy + 0.5 + (_hash(cx, cy, seed + 3.1) - 0.5) * jit - fy
            d = np.sqrt(ax * ax + ay * ay)
            if d < d1:
                d2 = d1
                d1 = d
                cid = _hash(cx, cy, seed + 7.7)
                rel_x, rel_y = -ax, -ay
            elif d < d2:
                d2 = d
    edge = _smooth(0.0, crack_w, d2 - d1)
    cover = 1.0 - _smooth(crack_cover - 0.08, crack_cover + 0.08, _noise(x / 40.0, y / 40.0, seed + 71.0))
    cracks = 1.0 - crack_depth * (1.0 - edge) * cover
    block = block_var * (cid - 0.5) + tilt * (rel_x * 0.6 + rel_y * 0.4)
    # strata
    ca, sa = np.cos(strata_angle), np.sin(strata_angle)
    along = (x * ca + y * sa) / strata_cm + strata_warp * (_noise(x / 35.0, y / 35.0, seed + 21.0) - 0.5)
    strata = strata_amp * np.sin(6.2831853 * along)
    base = base_amp * (_noise(x / base_cm, y / base_cm, seed + 31.0)
                       + 0.5 * _noise(x / (base_cm * 0.4), y / (base_cm * 0.4), seed + 33.0))
    grain = grain_amp * (_noise(px / grain_cm, py / grain_cm, seed + 41.0) - 0.5)
    # pits
    pcx, pcy = np.floor(px / pit_cm), np.floor(py / pit_cm)
    pits = 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = pcx + ox, pcy + oy
            if _hash(cx, cy, seed + 51.0) < pit_cover:
                ax = (cx + 0.2 + 0.6 * _hash(cx, cy, seed + 53.0)) * pit_cm - px
                ay = (cy + 0.2 + 0.6 * _hash(cx, cy, seed + 55.0)) * pit_cm - py
                r = pit_cm * (0.12 + 0.2 * _hash(cx, cy, seed + 57.0))
                pits = max(pits, 1.0 - _smooth(0.0, r, np.sqrt(ax * ax + ay * ay)))
    # rubble: small sharp fragments (a second, finer Voronoi) in patches
    rx, ry = np.floor(px / rub_cm), np.floor(py / rub_cm)
    rfx, rfy = px / rub_cm - rx, py / rub_cm - ry
    r1 = 9.0
    rid = 0.0
    rrx, rry = 0.0, 0.0
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx, cy = rx + ox, ry + oy
            ax = ox + 0.5 + (_hash(cx, cy, seed + 61.0) - 0.5) * 0.9 - rfx
            ay = oy + 0.5 + (_hash(cx, cy, seed + 63.0) - 0.5) * 0.9 - rfy
            d = np.sqrt(ax * ax + ay * ay)
            if d < r1:
                r1 = d
                rid = _hash(cx, cy, seed + 65.0)
                rrx, rry = -ax, -ay
    rub_mask = 1.0 - _smooth(rub_cover - 0.1, rub_cover + 0.1, _noise(px / 22.0, py / 22.0, seed + 67.0))
    near_crack = 1.0 - _smooth(0.0, crack_w * 4.0, d2 - d1)  # the rubble collects along the cracks
    rub_mask = max(rub_mask * (1.0 - rub_edge), near_crack * cover * rub_edge * 2.0)
    rub_mask = min(rub_mask, 1.0)
    rubble = rub_amp * ((rid - 0.5) + 0.8 * (rrx * 0.7 + rry * 0.5)) * rub_mask
    return (0.5 + block + base + strata + grain) * cracks - pit_depth * pits + rubble


@njit(cache=True, parallel=True)
def _render(size, cm_per_px, q, seed):
    out = np.empty((size, size), dtype=np.float32)
    for row in prange(size):
        py = (row + 0.5) * cm_per_px
        for col in range(size):
            out[row, col] = _rock_at((col + 0.5) * cm_per_px, py, q, seed)
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
    import cma
    import torch
    import analyze_flakes as analysis
    import procedural_bark as pb
    net = perceptual.build_net()
    height = analysis.load_height(f"{folder}/{name}_disp.png")
    cm_per_px = tile_m * 100.0 / height.shape[0]
    size = 384
    target = torch.from_numpy(height).to(perceptual.DEVICE).view(1, 1, *height.shape)
    rng = np.random.default_rng(5)
    crops = []
    for _ in range(6):
        y0 = int(rng.integers(0, height.shape[0] - size))
        x0 = int(rng.integers(0, height.shape[1] - size))
        crops.append(target[:, :, y0:y0 + size, x0:x0 + size])
    target_grams = [g.mean(dim=0, keepdim=True) for g in perceptual.grams(net, torch.cat(crops))]
    target_q = np.percentile(height, [5, 50, 99.0, 99.8])
    target_profile = perceptual.detail_profile(torch.cat(crops)).mean(dim=0, keepdim=True)
    target_ac = pb.autocorrelation_lengths(height, cm_per_px)
    sw_weight = float(os.environ.get("SW_WEIGHT", "0"))  # > 0: a sliced Wasserstein term next to the Gram term
    if sw_weight > 0:
        target_sets = perceptual.feature_sets(net, torch.cat(crops))
        target_sets = [t.permute(1, 0, 2).reshape(1, t.shape[1], -1) for t in target_sets]
        sw_dirs = perceptual.sw_directions(target_sets)
        target_sw = perceptual.sw_quantiles(target_sets, sw_dirs)

    def evaluate(vectors):
        pictures, extra = [], []
        for v in vectors:
            picture = render(decode(v), size, cm_per_px)
            pictures.append(torch.from_numpy(picture))
            ax, ay = pb.autocorrelation_lengths(picture, cm_per_px)
            q = np.percentile(picture, [5, 50, 99.0, 99.8])
            size_term = (abs(np.log(max(ax, 1e-3) / max(target_ac[0], 1e-3)))
                         + abs(np.log(max(ay, 1e-3) / max(target_ac[1], 1e-3))))
            extra.append(size_term + 2.0 * float(np.abs(q - target_q).sum()))
        batch = torch.stack(pictures).to(perceptual.DEVICE).unsqueeze(1)
        total = torch.zeros(len(vectors), device=perceptual.DEVICE)
        for gen, tar in zip(perceptual.grams(net, batch), target_grams):
            total += ((gen - tar) ** 2).sum(dim=(1, 2)) / (tar ** 2).sum()
        if sw_weight > 0:
            with torch.no_grad():
                total = total + sw_weight * perceptual.sw_distance(
                        perceptual.sw_quantiles(perceptual.feature_sets(net, batch), sw_dirs), target_sw)
        profile = perceptual.detail_profile(batch)
        scale = torch.clamp(target_profile.abs(), min=0.01)
        detail = (torch.abs(profile - target_profile) / scale).mean(dim=1)
        return [float(t) + 0.3 * e + 0.6 * float(d) for t, e, d in zip(total.cpu().numpy(), extra, detail.cpu().numpy())]

    start = np.clip(np.array([(PARAMS[k] - RANGES[k][0]) / (RANGES[k][1] - RANGES[k][0]) for k in KEYS]),
                    0.01, 0.99)
    torch.set_num_threads(limits.CORES)
    es = cma.CMAEvolutionStrategy(start, 0.25, {"bounds": [0, 1], "popsize": 20, "verbose": -9, "seed": 3})
    best_value, best_vector = 1e9, start
    for generation in range(generations):
        candidates = es.ask()
        values = evaluate(candidates)
        es.tell(candidates, values)
        index = int(np.argmin(values))
        if values[index] < best_value:
            best_value, best_vector = values[index], candidates[index]
            print(f"gen {generation:3d} loss {best_value:.4f}", flush=True)
    params = decode(best_vector)
    with open(out, "w") as handle:
        json.dump({"name": name, "tile_m": tile_m, "cm_per_px": cm_per_px, "loss": best_value,
                   "params": params}, handle, indent=1)
    picture = render(params, 512, cm_per_px)
    photo = (height[:512, :512] * 255).astype(np.uint8)
    cv2.imwrite(out.replace(".json", "_vs.png"), np.hstack([photo, (picture * 255).astype(np.uint8)]))
    print("best", best_value, "wrote", out)


if __name__ == "__main__":
    if sys.argv[1] == "fit":
        fit(sys.argv[2], sys.argv[3], float(sys.argv[4]), int(sys.argv[5]) if len(sys.argv) > 5 else 250,
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_rock.json")
    elif sys.argv[1] == "show":
        data = json.load(open(sys.argv[2]))
        cv2.imwrite(sys.argv[3], (render(data["params"], int(sys.argv[4]) if len(sys.argv) > 4 else 512,
                                         data["cm_per_px"]) * 255).astype(np.uint8))
