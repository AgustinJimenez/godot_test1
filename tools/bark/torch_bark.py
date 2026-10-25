"""The flake bark height field of shaders/world/bark_bake.gdshader in PyTorch (AGENT_TASKS/090, step 7): flakes(), cuts(), fibres(),
bark() and the stored height (alpha), line by line, with the shader's integer-hash mode (uniform int_hash, set by the environment
variable PLANET_BARK_INT_HASH in BarkBaker) so the same numbers draw the same picture. Checked by torch_bark_parity.py.

  render_height(p, tile_cm, size, seed, height_range, alpha, spread, soft) -> (size, size) tensor 0..1
p: the 37 numbers of BarkFits (index meanings are in procedural_bark.py / bark_fast.KEYS).
soft = None: the shader's hard flake mask (exact). soft = k (e.g. 40): the mask is a steep sigmoid, so the flake shape numbers get
gradients (a fit uses it, then the result is checked with the hard mask).
"""
import math
import re

import numpy as np
import torch

import torch_plates as tp


F = np.float32  # the shader counts whole cells in float32: tile / scale + 0.5 can sit exactly on an integer (200 / 133.33 + 0.5), where
# float32 and float64 round differently, so the cell counts are computed in float32 here too


def gdiv(a, b):
    """A division as the GPU does it: a * (1 / b), each step rounded to float32 (the shader's comment: mod(75.0, 75.0) can come out 75)."""
    return F(float(a)) * (F(1.0) / F(float(b)))


def cells(tile, scale):
    """The shader's max(floor(tile / scale + 0.5), 1). tile / scale + 0.5 can sit exactly on an integer (200 / 133.33 + 0.5 = 2);
    float32 with the GPU's division decides which way it falls (found by parity on pine's cuts)."""
    return max(int(np.floor(gdiv(tile, scale) + F(0.5))), 1)


def vnoise_xy(at, scale_x, scale_y, s, tile):
    px = cells(tile, scale_x)
    py = cells(tile, scale_y)
    qx = at[..., 0] / tile * px
    qy = at[..., 1] / tile * py
    ix, iy = torch.floor(qx), torch.floor(qy)
    fx, fy = qx - ix, qy - iy
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    a = tp.hashw(ix, iy, s, px, py)
    b = tp.hashw(ix + 1.0, iy, s, px, py)
    c = tp.hashw(ix, iy + 1.0, s, px, py)
    d = tp.hashw(ix + 1.0, iy + 1.0, s, px, py)
    return tp.mix(tp.mix(a, b, fx), tp.mix(c, d, fx), fy)


def whole(scale, tile):
    return gdiv(tile, cells(tile, scale))


def flakes(at, s, p, tile, soft=None):
    cw = whole(p[0], tile)
    rows = cells(tile, F(cw) * F(float(p[1])))
    ch = gdiv(tile, rows)
    per_x, per_y = gdiv(tile, cw), rows
    ix = torch.floor(at[..., 0] / cw)
    iy = torch.floor(at[..., 1] / ch)
    rag_cm = float(p[14])
    bite_u = vnoise_xy(at, rag_cm, rag_cm * 1.8, s + 41.0, tile) - 0.5
    bite_v = vnoise_xy(at + at.new_tensor([17.3, 0.0]), rag_cm, rag_cm * 1.8, s + 43.0, tile) - 0.5
    best = torch.zeros_like(ix)
    tone = torch.full_like(ix, 0.5)
    for oy in range(-2, 3):
        for ox in range(-1, 2):
            cx = ix + ox
            cy = iy + oy
            h0 = tp.hashw(cx, cy, s, per_x, per_y)
            h1 = tp.hashw(cx, cy, s + 5.3, per_x, per_y)
            h2 = tp.hashw(cx, cy, s + 10.6, per_x, per_y)
            h3 = tp.hashw(cx, cy, s + 15.9, per_x, per_y)
            h4 = tp.hashw(cx, cy, s + 21.2, per_x, per_y)
            centre_x = (cx + 0.5 + (h0 - 0.5) * p[5]) * cw
            centre_y = (cy + 0.5 + (h1 - 0.5) * p[5]) * ch
            size = 0.55 + p[4] * h2 * h2
            half_l = torch.clamp(ch * p[2] * size, max=2.0 * ch)
            half_w = torch.clamp(cw * p[3] * size, max=cw)
            turn = (h3 - 0.5) * p[6]
            dx = at[..., 0] - centre_x
            dy = at[..., 1] - centre_y
            rx = dx * torch.cos(turn) + dy * torch.sin(turn)
            ry = -dx * torch.sin(turn) + dy * torch.cos(turn)
            u = rx / half_w + bite_u * p[13] * 4.0
            v = ry / half_l + bite_v * p[13] * 2.0
            av = torch.clamp(torch.abs(v), 0.0, 1.0)
            half = (1.0 - p[19]) * (1.0 - torch.pow(av, p[7])) + p[19] * (1.0 - torch.pow(av, 8.0))
            dd = 1.0 - torch.abs(u) / torch.clamp(half, min=0.001)
            rim = tp.smoothstep(0.0, p[8], dd)
            value = h4 * p[9] + (p[10] + p[11] * dd + p[12] * v) * rim
            if soft is None:
                inside = (torch.abs(v) < 1.0) & (torch.abs(u) < half)
                value = torch.where(inside, value, torch.full_like(value, -1.0))
            else:
                mask = torch.sigmoid(soft * (1.0 - torch.abs(v))) * torch.sigmoid(soft * (half - torch.abs(u)))
                value = value * mask - (1.0 - mask)  # (outside: -1 at the extreme, so it never wins)
            better = value > best
            best = torch.where(better, value, best)
            tone = torch.where(better, h2, tone)
    return best, tone


def cuts(at, s, p, tile):
    groove_cm = whole(p[20], tile)
    lanes = gdiv(tile, groove_cm)
    lane_u = at[..., 0] / groove_cm + (vnoise_xy(at, 9.0, 30.0, s + 51.0, tile) - 0.5) * 1.2
    lane = torch.floor(lane_u)
    f = lane_u - lane
    lane_wrapped = lane - lanes * torch.floor(lane / lanes)
    at_open = torch.stack([lane_wrapped * groove_cm, at[..., 1]], dim=-1)
    open_n = vnoise_xy(at_open, groove_cm, F(groove_cm) * F(10.0), s + 53.0, tile)
    open_ = 1.0 - tp.smoothstep(p[22] - 0.05, p[22] + 0.05, open_n)
    groove = (1.0 - tp.smoothstep(0.0, p[21], torch.minimum(f, 1.0 - f) * 2.0)) * open_
    split_cm = whole(p[23], tile)
    rows = gdiv(tile, split_cm)
    split_v = at[..., 1] / split_cm + (vnoise_xy(at, 7.0, 20.0, s + 55.0, tile) - 0.5) * 0.6
    row = torch.floor(split_v)
    fv = split_v - row
    columns = cells(tile, F(groove_cm) * F(0.8))
    column = torch.floor(at[..., 0] / gdiv(tile, columns))
    on = 1.0 - tp.smoothstep(p[25] - 0.03, p[25] + 0.03, tp.hashw(column, row, s + 57.0, columns, rows))
    split = (1.0 - tp.smoothstep(0.0, p[24], torch.minimum(fv, 1.0 - fv) * 2.0)) * on
    return 1.0 - p[26] * torch.maximum(groove, split)


def fibres(at, s, p, tile):
    fc = whole(p[33], tile)
    lanes = gdiv(tile, fc)
    fs = whole(p[34], tile)
    rows = gdiv(tile, fs)
    u = at[..., 0] / fc + (vnoise_xy(at, 7.0, 40.0, s + 81.0, tile) - 0.5) * 0.8
    lane = torch.floor(u)
    f = u - lane
    profile = torch.pow(torch.sin(3.14159265 * f), 0.7)
    piece = torch.floor(at[..., 1] / fs + tp.hashw(lane, torch.zeros_like(lane), s + 83.0, lanes, 1))
    present = (tp.hashw(lane, piece, s + 85.0, lanes, rows) >= p[35]).to(torch.float32)
    tone = tp.hashw(lane, piece, s + 87.0, lanes, rows)
    return present * profile * (1.0 - p[36] + p[36] * tone)


def bark(at, s, p, tile, soft=None):
    wx = (vnoise_xy(at, p[16], p[16], s + 11.0, tile) - 0.5) * 2.0
    wy = (vnoise_xy(at + at.new_tensor([31.7, 0.0]), p[16], p[16], s + 13.0, tile) - 0.5) * 2.0
    w = at + torch.stack([wx * p[15], wy * p[15] * 1.5], dim=-1)
    best, tone = flakes(w, s, p, tile, soft)
    cover = 1.0 - tp.smoothstep(p[30] - 0.08, p[30] + 0.08, vnoise_xy(at, 18.0, 40.0, s + 71.0, tile))
    base = p[27] * (vnoise_xy(at, p[28], p[28] * p[29], s + 73.0, tile) + 0.5 * vnoise_xy(at, p[28] * 0.4, p[28] * 0.4 * p[29], s + 75.0, tile))
    h = base + p[31] * best * cuts(w, s, p, tile) * cover + p[32] * fibres(at, s, p, tile)
    fine = vnoise_xy(at, p[18], p[18] * 2.0, s + 29.0, tile)
    return h + (fine - 0.5) * p[17] * (h > 0.05).to(torch.float32), tone


def render_height(p, tile_cm, size, seed=1.0, height_range=(0.0, 1.0), alpha=(1.0, 0.5, 0.5), spread=1.0, soft=None, device=None):
    """The baked alpha. alpha = (alpha_scale, alpha_from, alpha_to) from the fit; spread = BarkBaker.HEIGHT_SPREAD of the bark."""
    device = device or ("cuda" if torch.cuda.is_available() else "cpu")
    if not torch.is_tensor(p):
        p = torch.stack([torch.as_tensor(v, dtype=torch.float32, device=device) for v in p])
    p = p.to(device)
    uv = (torch.arange(size, device=device, dtype=torch.float32) + 0.5) / size
    at = torch.stack(torch.meshgrid(uv, uv, indexing="xy"), dim=-1) * tile_cm
    h, _ = bark(at, seed, p, tile_cm, soft)
    lo, hi = height_range
    h = torch.clamp((h - lo) / max(hi - lo, 0.001), 0.0, 1.0)
    scale, a_from, a_to = alpha
    return torch.clamp(a_to + (h - a_from) * scale * spread, 0.0, 1.0)


def load_fit(name, path="systems/world_gen/bark_fits.gd"):
    text = open(path, encoding="utf-8").read()
    start = text.index('"%s": {' % name)
    nxt = re.search(r'\n\t\t"[a-z_0-9]+": \{', text[start + 5:])
    body = text[start:start + 5 + nxt.start()] if nxt else text[start:]
    numbers = lambda block: [float(x) for x in re.findall(r"-?\d+\.\d+|-?\d+", block)]
    params = numbers(re.search(r'"params": PackedFloat32Array\(\[(.*?)\]\)', body, re.S).group(1))
    lo, hi = [float(x) for x in re.search(r'"height_range": Vector2\(([^,]+), ([^)]+)\)', body).groups()]
    alpha = tuple(float(x) for x in re.search(r'"alpha_scale": ([0-9.]+), "alpha_from": ([0-9.]+), "alpha_to": ([0-9.]+)', body).groups())
    tile = float(re.search(r'"tile_cm": ([0-9.]+)', body).group(1))
    return {"params": params, "tile_cm": tile, "height_range": (lo, hi), "alpha": alpha}
