"""The plates height field of shaders/world/plate_bake.gdshader in PyTorch, so it can be fitted with gradients (AGENT_TASKS/090, step 3).

It mirrors the shader line by line (plates(), the pits, the final height in alpha), with the same integer hash, so for the same
parameters, tile and seed it draws the same picture as the game's bake (checked by torch_plates_parity.py).

  render_height(p, tile_cm, size, seed, guide, guide_mix, height_range, flat_rock) -> (size, size) tensor, the baked alpha (0..1)

`p` is the shader's 14 numbers (PlateFits params: cell_cm stretch jit warp_cm warp_amp crack_w crack_depth lip z_var tilt fine_cm
fine_amp rag_cm rag_amp). The ones that set a whole number of cells or noise cells (cell_cm, stretch, warp_cm, fine_cm, rag_cm) are
read as numbers, not differentiated; the others carry gradients.
"""
import math
import re

import torch

M32 = 0xFFFFFFFF


def ihash(ix, iy, s):
    """The shader's hash2: ints (int64 tensors) -> floats in [0, 1)."""
    x = ((ix & M32) * 0x9E3779B1) ^ ((iy & M32) * 0x85EBCA77) ^ ((s & M32) * 0xC2B2AE3D)
    x = x & M32
    x = x ^ (x >> 16)
    x = (x * 0x7FEB352D) & M32
    x = x ^ (x >> 15)
    x = (x * 0x846CA68B) & M32
    x = x ^ (x >> 16)
    return (x >> 8).to(torch.float32) / 16777216.0


def hash2(ix, iy, s):
    ixi = torch.floor(ix + 0.5).to(torch.int64)
    iyi = torch.floor(iy + 0.5).to(torch.int64)
    si = torch.full_like(ixi, int(math.floor(float(s) * 64.0 + 0.5)))
    return ihash(ixi, iyi, si)


def hashw(ix, iy, s, per_x, per_y):
    return hash2(ix - per_x * torch.floor(ix / per_x + 0.001), iy - per_y * torch.floor(iy / per_y + 0.001), s)


def smoothstep(e0, e1, x):
    t = torch.clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


def vnoise(at, scale, s, tile):
    n = max(math.floor(tile / float(scale) + 0.5), 1)
    q = at / tile * n
    i = torch.floor(q)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)
    ix, iy = i[..., 0], i[..., 1]
    fx, fy = f[..., 0], f[..., 1]
    a = hashw(ix, iy, s, n, n)
    b = hashw(ix + 1.0, iy, s, n, n)
    c = hashw(ix, iy + 1.0, s, n, n)
    d = hashw(ix + 1.0, iy + 1.0, s, n, n)
    return mix(mix(a, b, fx), mix(c, d, fx), fy)


def plates(at, s, p, tile, guide=None, guide_mix=0.0):
    """The shader's plates(): returns (z, edge, rim) for every pixel. at: (H, W, 2) centimetres."""
    cell = float(p[0])
    stretch = float(p[1])
    nu = max(math.floor(tile / cell + 0.5), 1)
    nv = max(math.floor(tile / (cell * stretch) + 0.5), 1)
    cell = tile / nu
    cell_v = tile / nv
    st = cell_v / cell
    off9 = at.new_tensor([9.0, 0.0])
    wx = at[..., 0] + cell * p[4] * 2.0 * (vnoise(at, p[3], s + 1.0, tile) - 0.5)
    wy = at[..., 1] + cell * p[4] * 2.0 * (vnoise(at + off9, p[3], s + 2.0, tile) - 0.5)
    wx = wx + cell * p[13] * 2.0 * (vnoise(at, p[12], s + 3.0, tile) - 0.5)
    u = wx / cell
    v = wy / cell_v
    iu = torch.floor(u)
    iv = torch.floor(v)
    d1 = torch.full_like(u, 1e9)
    d2 = torch.full_like(u, 1e9)
    best_cx = torch.zeros_like(u)
    best_cy = torch.zeros_like(u)
    best_dx = torch.zeros_like(u)
    best_dy = torch.zeros_like(u)
    best_fx = torch.zeros_like(u)
    best_fy = torch.zeros_like(u)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx = iu + ox
            cy = iv + oy
            fx = cx + 0.5 + (hashw(cx, cy, s + 5.0, nu, nv) - 0.5) * p[2]
            fy = cy + 0.5 + (hashw(cx, cy, s + 7.0, nu, nv) - 0.5) * p[2]
            dx = u - fx
            dy = (v - fy) * st * 0.6
            d = torch.sqrt(dx * dx + dy * dy + 1e-12)
            closer = d < d1
            second = (~closer) & (d < d2)
            d2 = torch.where(closer, d1, torch.where(second, d, d2))
            d1 = torch.where(closer, d, d1)
            best_cx = torch.where(closer, cx, best_cx)
            best_cy = torch.where(closer, cy, best_cy)
            best_dx = torch.where(closer, dx, best_dx)
            best_dy = torch.where(closer, dy, best_dy)
            best_fx = torch.where(closer, fx, best_fx)
            best_fy = torch.where(closer, fy, best_fy)
    edge = d2 - d1
    rim = 1.0 - smoothstep(0.0, p[7] * 0.14, edge)
    open_edge = mix(0.12, 1.0, smoothstep(0.35, 0.62, vnoise(at + at.new_tensor([31.0, 7.0]), 14.0, s + 301.0, tile) * 0.6
                                          + vnoise(at + at.new_tensor([3.0, 41.0]), 6.0, s + 303.0, tile) * 0.4))
    crack = (1.0 - smoothstep(0.0, p[5] * 0.12, edge)) * open_edge
    rim = rim * mix(0.3, 1.0, open_edge)
    lipf = smoothstep(0.0, p[7] * 0.3, edge)
    z = 0.7 + p[8] * (hashw(best_cx, best_cy, s + 11.0, nu, nv) - 0.5)
    if guide is not None and guide_mix > 0.0:
        centre_x = torch.remainder(best_fx * cell / tile, 1.0)
        centre_y = torch.remainder(best_fy * cell_v / tile, 1.0)
        gi = torch.clamp((centre_y * 16.0).to(torch.int64), 0, 15)
        gj = torch.clamp((centre_x * 16.0).to(torch.int64), 0, 15)
        z = mix(z, 0.35 + 0.7 * guide.reshape(-1)[gi * 16 + gj], guide_mix)
    z = z + p[9] * (best_dx * (hashw(best_cx, best_cy, s + 13.0, nu, nv) - 0.5)
                    + best_dy * (hashw(best_cx, best_cy, s + 15.0, nu, nv) - 0.5))
    z = z + p[11] * (vnoise(at, max(float(p[10]), 1.6), s + 17.0, tile) - 0.5)
    dome = 1.0 - torch.clamp(torch.sqrt(best_dx * best_dx + best_dy * best_dy + 1e-12) * 0.9, 0.0, 1.0)
    weather = ((vnoise(at, 5.0, s + 121.0, tile) - 0.5) * 0.5 + (vnoise(at, 2.4, s + 123.0, tile) - 0.5) * 0.4
               + (vnoise(at, 1.3, s + 125.0, tile) - 0.5) * 0.25)
    z = mix(0.7, z, 0.55)
    swell = (vnoise(at, 14.0, s + 127.0, tile) - 0.5) * 0.6 + (vnoise(at, 7.0, s + 129.0, tile) - 0.5) * 0.4
    cushion = smoothstep(0.0, 0.7, edge)
    z = z + 0.06 * dome + 0.12 * weather + 0.12 * swell + 0.1 * cushion
    return z * (0.8 + 0.2 * lipf) * (1.0 - 0.8 * p[6] * crack), edge, rim


def pit_hole(at, seed, tile):
    """The shader's round weathering pits (fragment()): 0..1 hole depth."""
    n1 = (vnoise(at, 1.6, seed + 151.0, tile) - 0.5) * 2.0 * 0.5
    n2 = (vnoise(at, 1.8, seed + 153.0, tile) - 0.5) * 2.0 * 0.5
    warped = at + torch.stack([n1, n2], dim=-1)
    w1 = 0.9 * (vnoise(at, 1.1, seed + 209.0, tile) - 0.5)
    w2 = 0.9 * (vnoise(at, 1.3, seed + 211.0, tile) - 0.5)
    pit_n = max(math.floor(tile / 3.0), 1)
    pit_u = (warped + torch.stack([w1, w2], dim=-1)) / tile * pit_n
    pi = torch.floor(pit_u)
    hole = torch.zeros_like(n1)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx = pi[..., 0] + ox
            cy = pi[..., 1] + oy
            on = hashw(cx, cy, seed + 201.0, pit_n, pit_n) < 0.13
            kx = cx + 0.2 + 0.6 * hashw(cx, cy, seed + 203.0, pit_n, pit_n)
            ky = cy + 0.2 + 0.6 * hashw(cx, cy, seed + 205.0, pit_n, pit_n)
            r = 0.12 + 0.3 * hashw(cx, cy, seed + 207.0, pit_n, pit_n)
            d = torch.sqrt((pit_u[..., 0] - kx) ** 2 + (pit_u[..., 1] - ky) ** 2 + 1e-12)
            hole = torch.maximum(hole, torch.where(on, 1.0 - smoothstep(r * 0.7, r, d), torch.zeros_like(d)))
    return hole


def render_height(p, tile_cm, size, seed=1.0, guide=None, guide_mix=0.0, height_range=(0.0, 1.0), flat_rock=0.85, device=None, pits=True):
    """The baked alpha (0..1) of the pitted-rock plates, size x size, tiling over tile_cm."""
    device = device or ("cuda" if torch.cuda.is_available() else "cpu")
    if not torch.is_tensor(p):  # (a list may mix floats and tensors that carry gradients: stack, do not copy)
        p = torch.stack([torch.as_tensor(v, dtype=torch.float32, device=device) for v in p])
    p = p.to(device)
    uv = (torch.arange(size, device=device, dtype=torch.float32) + 0.5) / size
    at = torch.stack(torch.meshgrid(uv, uv, indexing="xy"), dim=-1) * tile_cm  # (row, col) -> (x, y)
    if guide is not None:
        guide = torch.as_tensor(guide, dtype=torch.float32, device=device)
    z, _, _ = plates(at, seed, p, tile_cm, guide, guide_mix)
    lo, hi = height_range
    h = torch.clamp((z - lo) / max(hi - lo, 0.001), 0.0, 1.0)
    if pits:
        h = h - 0.12 * pit_hole(at, seed, tile_cm) * flat_rock
    return torch.clamp(0.5 + (h - 0.5) * 2.0, 0.0, 1.0)


def load_fit(name, path="systems/world_gen/plate_fits.gd"):
    """The numbers of one entry of plate_fits.gd: params, tile_cm, height_range (as the baker widens it), guide."""
    text = open(path, encoding="utf-8").read()
    start = text.index('"%s": {' % name)
    nxt = re.search(r'\n\t\t"[a-z_0-9]+": \{', text[start + 5:])
    body = text[start:start + 5 + nxt.start()] if nxt else text[start:]
    floats = lambda block: [float(x) for x in re.findall(r"-?\d+\.\d+|-?\d+", block)]
    params = floats(re.search(r'"params": PackedFloat32Array\(\[(.*?)\]\)', body, re.S).group(1))
    guide = floats(re.search(r'"guide": PackedFloat32Array\(\[(.*?)\]\)', body, re.S).group(1))
    lo, hi = [float(x) for x in re.search(r'"height_range": Vector2\(([^,]+), ([^)]+)\)', body).groups()]
    tile = float(re.search(r'"tile_cm": ([0-9.]+)', body).group(1))
    return {"params": params, "guide": guide, "tile_cm": tile, "height_range": (lo - 0.5 * (hi - lo), hi + 0.7 * (hi - lo))}
