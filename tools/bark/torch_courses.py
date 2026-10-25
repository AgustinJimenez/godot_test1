"""A "courses" height field in PyTorch: rectilinear blocks laid in rows (a dry-stone course, or a layered and jointed rock), a thin
crack along the block edges, a step in height from block to block and a few broad ledges. Written to see whether a family the plates
generator cannot make (dark_rock_02: horizontal courses with offset vertical joints, AGENT_TASKS/090 step 6) can be fitted.
Torch only for now (no shader yet): the same integer hash and value noise as torch_plates.py / plate_bake.gdshader.

  render_height(p, tile_cm, size, seed) -> (size, size) tensor 0..1
p (dict or 12 numbers in KEYS order): course_cm joint_cm offset warp_amp crack_cm crack_depth open z_var tilt ledge fine_amp bevel
"""
import torch

import torch_plates as tp

KEYS = ["course_cm", "joint_cm", "offset", "warp_amp", "crack_cm", "crack_depth", "open", "z_var", "tilt", "ledge", "fine_amp", "bevel"]
DEFAULT = {"course_cm": 12.0, "joint_cm": 35.0, "offset": 1.0, "warp_amp": 0.25, "crack_cm": 0.8, "crack_depth": 0.6, "open": 0.6,
           "z_var": 0.15, "tilt": 0.2, "ledge": 0.3, "fine_amp": 0.05, "bevel": 1.5}


def render_height(p, tile_cm, size, seed=1.0, device=None):
    device = device or ("cuda" if torch.cuda.is_available() else "cpu")
    if isinstance(p, dict):
        p = [p[k] for k in KEYS]
    p = torch.stack([torch.as_tensor(v, dtype=torch.float32, device=device) for v in p])
    course_cm, joint_cm = float(p[0]), float(p[1])
    rows = max(round(tile_cm / course_cm), 1)
    cols = max(round(tile_cm / joint_cm), 1)
    ch = tile_cm / rows
    jw = tile_cm / cols
    uv = (torch.arange(size, device=device, dtype=torch.float32) + 0.5) / size
    at = torch.stack(torch.meshgrid(uv, uv, indexing="xy"), dim=-1) * tile_cm
    warp_y = (tp.vnoise(at, 45.0, seed + 1.0, tile_cm) - 0.5) * 2.0 * p[3] * ch
    warp_x = (tp.vnoise(at + at.new_tensor([13.0, 5.0]), 30.0, seed + 2.0, tile_cm) - 0.5) * 2.0 * p[3] * jw * 0.5
    wy = at[..., 1] + warp_y
    wx = at[..., 0] + warp_x
    v = wy / ch + 0.5 * (tp.vnoise(at + at.new_tensor([5.0, 60.0]), 28.0, seed + 6.0, tile_cm) - 0.5)  # (the course lines wander and the courses differ in thickness)
    row = torch.floor(v)
    fy = v - row
    off = tp.hashw(row, torch.zeros_like(row), seed + 3.0, rows, 1) * p[2]
    row_scale = 0.55 + 0.9 * tp.hashw(row, torch.zeros_like(row), seed + 4.0, rows, 1)  # (each course its own block width: no running-bond wall; the tile only repeats vertically)
    u = wx / (jw * row_scale) + off
    col = torch.floor(u)
    fx = u - col
    zr = tp.hashw(col, row, seed + 5.0, cols, rows) - 0.5
    t1 = tp.hashw(col, row, seed + 7.0, cols, rows) - 0.5
    t2 = tp.hashw(col, row, seed + 9.0, cols, rows) - 0.5
    ex = torch.minimum(fx, 1.0 - fx) * jw * row_scale  # centimetres to the nearest vertical joint
    ey = torch.minimum(fy, 1.0 - fy) * ch  # to the nearest course line
    # a joint is open only where noise says so (cracks come and go along the lines)
    gate_y = tp.smoothstep(p[6] - 0.15, p[6] + 0.15, tp.vnoise(at + at.new_tensor([7.0, 21.0]), 35.0, seed + 11.0, tile_cm))
    gate_x = tp.smoothstep(p[6] - 0.15, p[6] + 0.15, tp.vnoise(at + at.new_tensor([27.0, 3.0]), 20.0, seed + 13.0, tile_cm))
    crack = torch.maximum((1.0 - tp.smoothstep(0.0, p[4], ey)) * gate_y, (1.0 - tp.smoothstep(0.0, p[4], ex)) * gate_x)
    bevel = tp.smoothstep(0.0, p[11] * 2.0, torch.minimum(ex, ey))  # blocks fall away a little at the edges
    z = 0.7 + p[7] * zr + p[8] * ((fx - 0.5) * t1 + (fy - 0.5) * t2)
    big = tp.smoothstep(0.4, 0.6, tp.vnoise(at, 110.0, seed + 15.0, tile_cm) * 0.6 + tp.vnoise(at + at.new_tensor([40.0, 0.0]), 55.0, seed + 17.0, tile_cm) * 0.4)
    z = z + p[9] * big + p[10] * (tp.vnoise(at, 1.6, seed + 19.0, tile_cm) - 0.5) + 0.05 * (bevel - 1.0)
    h = z * (1.0 - p[5] * crack)
    return torch.clamp((h - 0.2) / 1.0, 0.0, 1.0)
