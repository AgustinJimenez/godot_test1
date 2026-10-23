"""Prototype of histogram-preserving randomized tiling (Heitz and Neyret 2018; Burley and Heitz 2019), written from the idea.

  python stochastic_tile.py <folder> <name> <out png> [crop px]

Takes a photograph's diffuse map (a crop), Gaussianizes each channel (a rank transform: the 1D case of the paper's 3D
optimal transport), blends three randomly shifted copies on a triangle grid with weights normalised to keep the variance
(w / |w|), then maps back through the channel's own histogram. Writes: the plain repeat 3x3 next to the blended 3x3.
"""
import sys

import cv2
import numpy as np
from scipy.special import ndtri


def gaussianize(channel):
    flat = channel.ravel()
    order = np.argsort(flat)
    ranks = np.empty_like(order)
    ranks[order] = np.arange(flat.size)
    g = ndtri((ranks + 0.5) / flat.size).reshape(channel.shape)
    return g.astype(np.float32), np.sort(flat)


def inverse(g, sorted_values):
    from scipy.special import ndtr
    u = np.clip(ndtr(g), 0.0, 1.0 - 1e-6)
    return np.interp(u * (sorted_values.size - 1), np.arange(sorted_values.size), sorted_values)


def hash2(ix, iy, k):
    return (np.sin(ix * 127.1 + iy * 311.7 + k * 74.7) * 43758.5453) % 1.0


def synthesize(g, size, scale=1.0):
    """Blend three randomly shifted copies of the Gaussianised photograph on a skewed triangle grid."""
    h, w = g.shape
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    u, v = xs / (w * scale), ys / (h * scale)  # the texture coordinate: the photograph at its real size
    grid = 2.0                                 # triangle cells per photograph
    sx = (u - v * 0.57735027) * grid
    sy = (v * 1.15470054) * grid
    bx, by = np.floor(sx), np.floor(sy)
    tx, ty = sx - bx, sy - by
    s_sum = tx + ty
    lower = s_sum < 1.0
    corners = [
        (np.where(lower, bx, bx + 1), np.where(lower, by, by + 1), np.where(lower, 1.0 - s_sum, s_sum - 1.0)),
        (np.where(lower, bx, bx + 1), np.where(lower, by + 1, by), np.where(lower, ty, 1.0 - ty)),
        (np.where(lower, bx + 1, bx), np.where(lower, by, by + 1), np.where(lower, tx, 1.0 - tx)),
    ]
    total = np.zeros((size, size), np.float32)
    norm = np.zeros((size, size), np.float32)
    for cx, cy, weight in corners:
        ox, oy = hash2(cx, cy, 1.0), hash2(cx, cy, 2.0)
        px = (u + ox) % 1.0 * w
        py = (v + oy) % 1.0 * h
        sample = cv2.remap(g, px.astype(np.float32), py.astype(np.float32), cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)
        total += weight * sample
        norm += weight * weight
    return total / np.sqrt(np.maximum(norm, 1e-6))


def main():
    folder, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
    crop = int(sys.argv[4]) if len(sys.argv) > 4 else 256
    image = cv2.imread(f"{folder}/{name}_diff.jpg").astype(np.float32)[:crop, :crop] / 255.0
    size = 512
    blended = np.zeros((size, size, 3), np.float32)
    for c in range(3):
        g, sorted_values = gaussianize(image[:, :, c])
        blended[:, :, c] = inverse(synthesize(g, size), sorted_values)
    plain = np.tile(image, (size // crop + 1, size // crop + 1, 1))[:size, :size]
    cv2.imwrite(out, (np.hstack([plain, blended]) * 255).astype(np.uint8))
    print("wrote", out)


if __name__ == "__main__":
    main()
