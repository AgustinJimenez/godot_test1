"""A compact copy of a photographed height map: a coarse swell + the traced lobes + pits and bumps added one at a time where the
error is largest, then all tuned together by gradient descent (a differentiable renderer, patches of 33 x 33 px per primitive).

  python fit_copy.py <disp png> <tile cm> <primitives> <out json>

Prints the error after each stage (mean absolute error of the 0..1 height, and the correlation of the lit height), writes the
primitives (x, y, radius, depth in tile units) and a picture of the copy beside the photograph."""
import json
import sys

import limits  # (first)

import cv2
import numpy as np
import torch
import torch.nn.functional as F

import extract_features as ef

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
SIZE = 1024
PATCH = 33
GUIDE = 32


def lit(h):
    """The height lit from the upper left (the eye's version of a height map), a (SIZE, SIZE) tensor."""
    kx = torch.tensor([[-1.0, 0.0, 1.0], [-2.0, 0.0, 2.0], [-1.0, 0.0, 1.0]], device=DEVICE).view(1, 1, 3, 3) / 8.0
    x = h.view(1, 1, SIZE, SIZE)
    gx = F.conv2d(x, kx, padding=1)
    gy = F.conv2d(x, kx.transpose(2, 3), padding=1)
    return (0.5 - 8.0 * (gx + gy)).clamp(0, 1).view(SIZE, SIZE)


def correlation(a, b):
    a = a - a.mean()
    b = b - b.mean()
    return float((a * b).sum() / (a.norm() * b.norm() + 1e-9))


def report(stage, target, copy):
    mae = float((target - copy).abs().mean())
    print(f"{stage:34s} mean abs error {mae:.4f}   lit-height correlation {correlation(lit(target), lit(copy)):.3f}", flush=True)


def swell_of(target):
    """The coarse swell: the photograph averaged to GUIDE x GUIDE cells, read back smoothly (bicubic)."""
    small = F.adaptive_avg_pool2d(target.view(1, 1, SIZE, SIZE), GUIDE)
    return F.interpolate(small, size=(SIZE, SIZE), mode="bicubic", align_corners=False).view(SIZE, SIZE), small


def lobe_layer(h_np, cm_per_px):
    """The traced lobes drawn at their own places: a smooth step (a Gaussian-blurred mask, about 1 cm) of the measured step."""
    layer = np.zeros((SIZE, SIZE), np.float32)
    for name, pts in ef.HAND_LOBES.items():
        outline = ef.resample(ef.chaikin(np.array(pts, dtype=np.float64) / ef.GRID_PX), ef.VERTS)
        poly = (outline * SIZE).astype(np.int32).reshape(-1, 1, 2)
        cell = np.zeros((SIZE, SIZE), np.uint8)
        cv2.fillPoly(cell, [poly], 1)
        inner = cv2.erode(cell, np.ones((9, 9), np.uint8))
        ring = cv2.dilate(cell, np.ones((41, 41), np.uint8)) - cv2.dilate(cell, np.ones((13, 13), np.uint8))
        step = float(np.median(h_np[inner > 0]) - np.median(h_np[ring > 0]))
        layer += cv2.GaussianBlur(cell.astype(np.float32), (0, 0), 1.0 / cm_per_px) * step
    return torch.from_numpy(layer).to(DEVICE)


class Primitives:
    """Round pits and bumps: position (px), radius (px) and depth, drawn as depth * (1 - smoothstep(0.4, 1, distance / radius))."""

    def __init__(self):
        self.pos = torch.zeros(0, 2, device=DEVICE)
        self.radius = torch.zeros(0, device=DEVICE)
        self.depth = torch.zeros(0, device=DEVICE)

    def add(self, x, y, radius, depth):
        self.pos = torch.cat([self.pos, torch.tensor([[x, y]], device=DEVICE, dtype=torch.float32)])
        self.radius = torch.cat([self.radius, torch.tensor([radius], device=DEVICE, dtype=torch.float32)])
        self.depth = torch.cat([self.depth, torch.tensor([depth], device=DEVICE, dtype=torch.float32)])

    def render(self):
        canvas = torch.zeros(SIZE * SIZE, device=DEVICE)
        if self.pos.shape[0] == 0:
            return canvas.view(SIZE, SIZE)
        half = PATCH // 2
        offsets = torch.arange(-half, half + 1, device=DEVICE)
        oy, ox = torch.meshgrid(offsets, offsets, indexing="ij")
        cx = self.pos[:, 0].detach().round().long().clamp(half, SIZE - 1 - half)
        cy = self.pos[:, 1].detach().round().long().clamp(half, SIZE - 1 - half)
        gx = cx.view(-1, 1, 1) + ox.view(1, PATCH, PATCH)
        gy = cy.view(-1, 1, 1) + oy.view(1, PATCH, PATCH)
        dist = torch.sqrt((gx - self.pos[:, 0].view(-1, 1, 1)) ** 2 + (gy - self.pos[:, 1].view(-1, 1, 1)) ** 2 + 1e-6)
        t = ((dist / self.radius.abs().clamp(min=1.0).view(-1, 1, 1) - 0.4) / 0.6).clamp(0, 1)
        shape = 1.0 - t * t * (3.0 - 2.0 * t)
        values = (self.depth.view(-1, 1, 1) * shape).reshape(-1)
        index = (gy * SIZE + gx).reshape(-1)
        return canvas.index_put((index,), values, accumulate=True).view(SIZE, SIZE)

    def parameters(self):
        for t in (self.pos, self.radius, self.depth):
            t.requires_grad_(True)
        return [self.pos, self.radius, self.depth]


def main():
    h_np = ef.load(sys.argv[1])
    tile_cm = float(sys.argv[2])
    count = int(sys.argv[3])
    cm = tile_cm / SIZE
    target = torch.from_numpy(h_np).to(DEVICE)
    # the stages
    swell, small = swell_of(target)
    report("coarse swell (%d x %d)" % (GUIDE, GUIDE), target, swell)
    lobes = lobe_layer(h_np, cm)
    base = swell + lobes
    report("+ traced lobes", target, base)
    prims = Primitives()
    residual = (target - base).detach()
    for step in range(count):
        smooth = F.avg_pool2d(residual.abs().view(1, 1, SIZE, SIZE), 5, 1, 2).view(SIZE, SIZE)
        smooth[:20] = 0
        smooth[-20:] = 0
        smooth[:, :20] = 0
        smooth[:, -20:] = 0
        index = int(torch.argmax(smooth))
        y, x = divmod(index, SIZE)
        prims.add(float(x), float(y), 3.0, float(residual[y, x]))
        if (step + 1) % 50 == 0 or step == count - 1:
            params = prims.parameters()
            optimiser = torch.optim.Adam([{"params": [prims.pos], "lr": 0.15}, {"params": [prims.radius], "lr": 0.05}, {"params": [prims.depth], "lr": 0.004}])
            for _ in range(60):
                optimiser.zero_grad()
                copy = base + prims.render()
                loss = (copy - target).abs().mean() + 0.5 * (lit(copy) - lit(target)).abs().mean()
                loss.backward()
                optimiser.step()
            for t in params:
                t.requires_grad_(False)
            copy = base + prims.render()
            report("+ %d pits and bumps" % (step + 1), target, copy)
        residual = (target - base - prims.render()).detach()
    copy = (base + prims.render()).clamp(0, 1)
    with open(sys.argv[4], "w") as handle:
        json.dump({"primitives": [[float(prims.pos[i, 0]) / SIZE, float(prims.pos[i, 1]) / SIZE, float(prims.radius[i]) / SIZE,
                                   float(prims.depth[i])] for i in range(prims.pos.shape[0])]}, handle)
    both = torch.cat([lit(target), lit(copy)], dim=1).cpu().numpy()
    cv2.imwrite(sys.argv[4].replace(".json", "_vs.png"), (both * 255).astype(np.uint8))
    cv2.imwrite(sys.argv[4].replace(".json", "_height.png"), (copy.cpu().numpy() * 255).astype(np.uint8))


if __name__ == "__main__":
    main()
