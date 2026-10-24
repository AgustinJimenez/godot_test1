"""A differentiable version of the boulder's height (lobes that merge, rims, swells, pits, crumbly patches, fine bumps), fitted
to the photograph by gradient descent (Adam through VGG Gram + sliced Wasserstein losses on the lit height). The same layers as
`shaders/world/lump_bake.gdshader` (`rim_lobes` branch), so the fitted numbers can be handed to it.

Only the continuous numbers are fitted; the random layout (which cells hold a lobe, noise fields) is a fixed seed, so the fit
cannot copy the photograph's own layout.

  python diff_boulder.py fit <steps> <out json>      fit, write the numbers and a picture next to them
"""
import json
import sys

import limits  # (first)

import cv2
import numpy as np
import torch
import torch.nn.functional as F

import bark_perceptual as perceptual

DEVICE = perceptual.DEVICE
TILE_CM = 180.0
SIZE = 512
# name: (start, low, high)
PARAMS = {
    "lobe_cover": (0.72, 0.3, 0.95), "radius": (0.4, 0.2, 0.8), "radius_var": (0.55, 0.0, 1.0), "squash": (0.45, 0.25, 0.9),
    "warp_big": (9.0, 0.0, 20.0), "warp_small": (3.0, 0.0, 8.0), "level": (0.3, 0.1, 0.7), "edge_w": (0.1, 0.03, 0.3),
    "rim": (0.045, 0.0, 0.12), "plateau": (0.35, 0.0, 1.0), "rim_vary": (0.75, 0.0, 1.0),
    "swell": (0.072, 0.0, 0.1), "snake": (0.04, 0.0, 0.15), "snake_w": (0.014, 0.004, 0.04),
    "pit_cover": (0.12, 0.0, 0.5), "pit_amp": (0.02, 0.0, 0.08),
    "crumb": (0.1, 0.0, 0.3), "fine": (0.07, 0.0, 0.25), "mid": (0.04, 0.0, 0.15),
}
KEYS = list(PARAMS)


def noise_fields(seed=7):
    """Fixed smooth noise fields (SIZE x SIZE), one per scale in cm: bilinear upsampling of random grids."""
    generator = torch.Generator().manual_seed(seed)
    fields = {}
    for name, cm in (("w17", 17.0), ("w6", 6.0), ("s38", 38.0), ("s17", 17.0), ("n62", 62.0), ("n85", 85.0), ("n28", 28.0),
                     ("n45", 45.0), ("c35", 3.5), ("c16", 1.6), ("f9", 9.0), ("f45", 4.5), ("f22", 2.2), ("m10", 10.0),
                     ("m7", 7.0), ("rim", 28.0), ("w17b", 17.0), ("w6b", 6.0)):
        n = max(int(TILE_CM / cm), 2)
        grid = torch.rand(1, 1, n, n, generator=generator)
        padded = F.pad(grid, (1, 1, 1, 1), mode="circular")
        up = F.interpolate(padded, size=(SIZE + 2 * SIZE // n, SIZE + 2 * SIZE // n), mode="bicubic", align_corners=False)
        pad_px = SIZE // n
        fields[name] = up[:, :, pad_px:pad_px + SIZE, pad_px:pad_px + SIZE].clamp(0, 1).to(DEVICE)
    return fields


def lobe_layout(seed=11):
    """The fixed random numbers of the lobe cells: a grid of ln x ln cells, each with six hashes."""
    ln = max(int(TILE_CM / 40.0 + 0.5), 1)
    generator = torch.Generator().manual_seed(seed)
    return ln, torch.rand(ln, ln, 6, generator=generator).to(DEVICE)


def warp_sample(field, dx, dy):
    """Read `field` at the pixel grid moved by (dx, dy) px (differentiable)."""
    ys, xs = torch.meshgrid(torch.linspace(-1, 1, SIZE, device=DEVICE), torch.linspace(-1, 1, SIZE, device=DEVICE), indexing="ij")
    grid = torch.stack([xs + dx * 2.0 / SIZE, ys + dy * 2.0 / SIZE], dim=-1).unsqueeze(0)
    return F.grid_sample(field, grid, mode="bilinear", padding_mode="border", align_corners=True)


def render(values, fields, layout):
    """The height picture (1, 1, SIZE, SIZE) from a dict of the PARAMS values."""
    px_cm = TILE_CM / SIZE
    ys, xs = torch.meshgrid(torch.arange(SIZE, device=DEVICE) * px_cm, torch.arange(SIZE, device=DEVICE) * px_cm, indexing="ij")
    wx = (values["warp_big"] * (fields["w17"][0, 0] - 0.5) * 2.0 + values["warp_small"] * (fields["w6"][0, 0] - 0.5) * 2.0)
    wy = (values["warp_big"] * (fields["w17b"][0, 0] - 0.5) * 2.0 + values["warp_small"] * (fields["w6b"][0, 0] - 0.5) * 2.0)
    lx, ly = xs + wx, ys + wy
    ln, hashes = layout
    cs = TILE_CM / ln
    field = torch.zeros_like(lx)
    cell_x = torch.floor(lx / cs)
    cell_y = torch.floor(ly / cs)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            gx = cell_x + ox
            gy = cell_y + oy
            h = hashes[(gy.long() % ln), (gx.long() % ln)]  # (SIZE, SIZE, 6)
            present = torch.sigmoid((values["lobe_cover"] - h[..., 0]) * 25.0)
            cx = (gx + 0.15 + 0.7 * h[..., 1]) * cs
            cy = (gy + 0.15 + 0.7 * h[..., 2]) * cs
            radius = cs * (values["radius"] * 0.85 + values["radius_var"] * 0.6 * h[..., 3] * h[..., 4])
            squash = values["squash"] + 0.8 * h[..., 5]
            turn = 6.2832 * h[..., 4]
            dx, dy = lx - cx, ly - cy
            rx = torch.cos(turn) * dx + torch.sin(turn) * dy
            ry = (-torch.sin(turn) * dx + torch.cos(turn) * dy) / squash
            q = torch.clamp(1.0 - (rx * rx + ry * ry) / (radius * radius + 1e-6), 0.0, 1.0)
            field = field + present * q * q
    edge = (field - values["level"]) / values["edge_w"]
    rim_strength = (1.0 - values["rim_vary"]) + values["rim_vary"] * torch.clamp((fields["rim"][0, 0] - 0.3) / 0.4, 0, 1)
    plateau = torch.clamp((field - values["level"]) / 0.3, 0, 1)
    h = values["rim"] * (values["plateau"] * plateau + rim_strength * torch.exp(-edge * edge))
    h = h + values["swell"] * ((fields["s38"][0, 0] - 0.5) + 0.6 * (fields["s17"][0, 0] - 0.5))
    snake = torch.abs(warp_sample(fields["n62"], wx / px_cm, wy / px_cm)[0, 0] - 0.5) / values["snake_w"]
    h = h + values["snake"] * torch.exp(-snake * snake) * torch.clamp((fields["n85"][0, 0] - 0.5) / 0.18, 0, 1)
    crumb = torch.clamp((fields["n45"][0, 0] - 0.5) / 0.2, 0, 1)
    h = h + values["crumb"] * crumb * ((fields["c35"][0, 0] - 0.5) + 0.7 * (fields["c16"][0, 0] - 0.5))
    h = h + values["fine"] * ((fields["f9"][0, 0] - 0.5) * 0.5 + (fields["f45"][0, 0] - 0.5) * 0.4 + (fields["f22"][0, 0] - 0.5) * 0.3)
    h = h + values["mid"] * ((fields["m10"][0, 0] - 0.5) + (fields["m7"][0, 0] - 0.5))
    pits = torch.clamp((fields["f22"][0, 0] - (1.0 - values["pit_cover"] * 0.3)) / 0.03, 0, 1)
    h = h - values["pit_amp"] * pits
    return h.view(1, 1, SIZE, SIZE)


def normalise(h):
    low = torch.quantile(h.flatten(), 0.005)
    high = torch.quantile(h.flatten(), 0.995)
    return torch.clamp((h - low) / (high - low + 1e-6), 0, 1)


def edge_stats(picture):
    """How sharp and how many the edges are: the gradient magnitude's mean, its soft share above two levels, and its top 1 %."""
    kx = torch.tensor([[-1.0, 0.0, 1.0], [-2.0, 0.0, 2.0], [-1.0, 0.0, 1.0]], device=DEVICE).view(1, 1, 3, 3) / 8.0
    gx = F.conv2d(picture, kx, padding=1)
    gy = F.conv2d(picture, kx.transpose(2, 3), padding=1)
    g = torch.sqrt(gx * gx + gy * gy + 1e-8) * SIZE / 100.0
    return torch.stack([g.mean(), torch.sigmoid((g - 0.15) * 30).mean(), torch.sigmoid((g - 0.4) * 30).mean(), torch.quantile(g.flatten(), 0.99)])


def decode(raw):
    return {k: lo + (hi - lo) * torch.sigmoid(raw[i]) for i, (k, (start, lo, hi)) in enumerate(PARAMS.items())}


def encode_start():
    out = []
    for start, lo, hi in PARAMS.values():
        p = min(max((start - lo) / (hi - lo), 0.02), 0.98)
        out.append(float(np.log(p / (1 - p))))
    return torch.tensor(out, device=DEVICE, requires_grad=True)


def fit(steps, out):
    net = perceptual.build_net()
    photo = cv2.imread("bark_downloads/rock_boulder_dry_disp.png", cv2.IMREAD_UNCHANGED).astype(np.float32)
    photo = photo.mean(axis=2) if photo.ndim == 3 else photo
    photo = cv2.resize(photo, (SIZE, SIZE), interpolation=cv2.INTER_AREA)
    photo = (photo - photo.min()) / (photo.max() - photo.min())
    target = torch.from_numpy(photo).to(DEVICE).view(1, 1, SIZE, SIZE)
    target = normalise(target)
    target_grams = perceptual.grams(net, target)
    target_sets = perceptual.feature_sets(net, target)
    dirs = perceptual.sw_directions(target_sets)
    target_sw = perceptual.sw_quantiles(target_sets, dirs)
    target_edges = edge_stats(target).detach()
    print("target edge stats", target_edges.tolist())
    fields = noise_fields()
    layout = lobe_layout()
    raw = encode_start()
    optimiser = torch.optim.Adam([raw], lr=0.05)
    best = (1e9, None)
    for step in range(steps):
        optimiser.zero_grad()
        picture = normalise(render(decode(raw), fields, layout))
        grams = perceptual.grams(net, picture)
        loss = sum(((g - t) ** 2).sum() / (t ** 2).sum() for g, t in zip(grams, target_grams))
        sw = perceptual.sw_distance(perceptual.sw_quantiles(perceptual.feature_sets(net, picture), dirs), target_sw).sum()
        # the strength of the relief (std of the lit height) and the size of its features (std of the blurred picture)
        shaded_p = perceptual.shaded(picture)[:, :2]
        shaded_t = perceptual.shaded(target)[:, :2]
        stat = (shaded_p.std() / shaded_t.std() - 1.0).abs() + (picture.std() / target.std() - 1.0).abs()
        edges = ((edge_stats(picture) - target_edges).abs() / (target_edges + 1e-3)).mean()
        total = loss + sw + 0.5 * stat + 3.0 * edges
        total.backward()
        optimiser.step()
        if float(total.detach()) < best[0]:
            best = (float(total.detach()), raw.detach().clone(), picture.detach())
        if step % 20 == 0:
            print(f"step {step:4d} total {float(total):.4f} gram {float(loss):.4f} sw {float(sw):.4f} stat {float(stat):.3f} edges {float(edges):.3f}", flush=True)
    values = {k: float(v) for k, v in decode(best[1]).items()}
    with open(out, "w") as handle:
        json.dump({"loss": best[0], "values": values}, handle, indent=1)
    shot = lambda t: (shaded_view(t) * 255).astype(np.uint8)
    both = np.concatenate([shot(target), shot(best[2])], axis=1)
    cv2.imwrite(out.replace(".json", "_vs.png"), both)
    print("best", best[0], values)


def shaded_view(picture):
    s = perceptual.shaded(picture)[0, 0]
    return s.detach().cpu().numpy()


if __name__ == "__main__":
    if sys.argv[1] == "fit":
        fit(int(sys.argv[2]), sys.argv[3])
