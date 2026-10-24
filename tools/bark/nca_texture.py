"""A neural cellular automaton texture (after Mordvintsev et al., "Self-organising textures", Distill 2021) trained on a photographed height map.

Every pixel holds 12 numbers; each step it looks at itself and its neighbours (identity, Sobel x and y, Laplacian), a tiny two-layer
network (about 6 K weights) proposes a change, and a random half of the pixels take it. The grid wraps, so the result tiles and can
be run at any size. Channel 0 is the height. The weights are the whole "recipe" (a few KB).

  python nca_texture.py train <disp png> <steps> <out pt>       train (style loss on the lit height through VGG)
  python nca_texture.py make <pt> <size> <seed> <out png>       run it on a size x size grid; RGBA png, alpha = height (for measure_boulder.py)
"""
import sys

import limits  # (first)

import cv2
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

import bark_perceptual as perceptual
import extract_features as ef

DEVICE = perceptual.DEVICE
CH = 12
HIDDEN = 128


class NCA(nn.Module):
    def __init__(self):
        super().__init__()
        sobel = torch.tensor([[-1.0, 0.0, 1.0], [-2.0, 0.0, 2.0], [-1.0, 0.0, 1.0]]) / 8.0
        lap = torch.tensor([[1.0, 2.0, 1.0], [2.0, -12.0, 2.0], [1.0, 2.0, 1.0]]) / 16.0
        ident = torch.zeros(3, 3)
        ident[1, 1] = 1.0
        kernels = torch.stack([ident, sobel, sobel.t(), lap])  # (4, 3, 3)
        self.register_buffer("kernels", kernels.repeat(CH, 1, 1).unsqueeze(1))  # depthwise: 4 filters per channel
        self.w1 = nn.Conv2d(CH * 4, HIDDEN, 1)
        self.w2 = nn.Conv2d(HIDDEN, CH, 1)
        nn.init.zeros_(self.w2.weight)
        nn.init.zeros_(self.w2.bias)

    def perceive(self, x):
        return F.conv2d(F.pad(x, (1, 1, 1, 1), mode="circular"), self.kernels, groups=CH)

    def step(self, x, fire=0.5):
        dx = self.w2(F.relu(self.w1(self.perceive(x))))
        mask = (torch.rand(x.shape[0], 1, x.shape[2], x.shape[3], device=x.device) < fire).float()
        return x + dx * mask

    def forward(self, x, steps):
        for _ in range(steps):
            x = self.step(x)
        return x


def height_of(state):
    return (0.5 + 0.5 * torch.tanh(state[:, :1]))


def train(path, steps, out):
    net = perceptual.build_net()
    photo = torch.from_numpy(ef.load(path)).to(DEVICE).view(1, 1, 1024, 1024)
    model = NCA().to(DEVICE)
    optimiser = torch.optim.Adam(model.parameters(), lr=2e-3)
    schedule = torch.optim.lr_scheduler.MultiStepLR(optimiser, [int(steps * 0.6), int(steps * 0.85)], 0.3)
    size = 192
    generator = torch.Generator(device="cpu").manual_seed(3)
    for it in range(steps):
        # the style target: Gram matrices of a few random crops of the photograph, at the same scale
        crops = []
        for _ in range(4):
            y0, x0 = [int(v) for v in torch.randint(0, 1024 - size, (2,), generator=generator)]
            crops.append(photo[:, :, y0:y0 + size, x0:x0 + size])
        target_grams = [g.mean(dim=0, keepdim=True) for g in perceptual.grams(net, torch.cat(crops))]
        x = torch.rand(4, CH, size, size, device=DEVICE) * 0.2
        x = model(x, int(torch.randint(48, 96, (1,), generator=generator)))
        picture = height_of(x)
        grams = perceptual.grams(net, picture)
        style = sum(((g - t) ** 2).sum() / (t ** 2).sum() for g, t in zip(grams, target_grams)) / len(grams)
        # keep the range and the spread of the photograph (the Gram matrices barely see them)
        stat = (picture.mean() - photo.mean()).abs() + (picture.std() / photo.std() - 1.0).abs()
        loss = style + 0.5 * stat
        optimiser.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimiser.step()
        schedule.step()
        if it % 100 == 0 or it == steps - 1:
            print(f"step {it:5d} loss {float(loss):.4f} style {float(style):.4f} stat {float(stat):.3f}", flush=True)
    torch.save(model.state_dict(), out)
    print("weights:", sum(p.numel() for p in model.parameters()))


def make(pt, size, seed, out, steps=96):
    model = NCA().to(DEVICE)
    model.load_state_dict(torch.load(pt))
    torch.manual_seed(seed)
    with torch.no_grad():
        x = torch.rand(1, CH, size, size, device=DEVICE) * 0.2
        x = model(x, steps)
        h = height_of(x)[0, 0].cpu().numpy()
    h8 = np.clip((h - h.min()) / (h.max() - h.min()) * 255.0, 0, 255).astype(np.uint8)
    rgba = np.dstack([h8, h8, h8, h8])
    cv2.imwrite(out, rgba)
    shaded = perceptual.shaded(torch.from_numpy(h).view(1, 1, size, size).to(DEVICE))[0, 0].cpu().numpy()
    cv2.imwrite(out.replace(".png", "_lit.png"), (np.clip(shaded, 0, 1) * 255).astype(np.uint8))


if __name__ == "__main__":
    if sys.argv[1] == "train":
        train(sys.argv[2], int(sys.argv[3]), sys.argv[4])
    else:
        make(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5])
