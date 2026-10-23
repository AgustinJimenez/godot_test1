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


def triangle_grid(u, v):
    """Three cells and their barycentric weights for texture coordinates (u, v), on a skewed grid."""
    x = u + v * 0.5773503
    y = v * 1.1547005
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    upper = (fx + fy) > 1.0
    w1 = np.where(upper, 1.0 - fx, 1.0 - fy - fx * 0.0)
    # (a simple barycentric split of the square into two triangles)
    wa = np.where(upper, 1.0 - fy, 1.0 - fx - fy)
    wb = np.where(upper, fx + fy - 1.0, fx)
    wc = np.where(upper, 1.0 - fx, fy)
    cells = np.where(upper[..., None], np.stack([ix + 1, iy + 1], -1), np.stack([ix, iy], -1))
    return ix, iy, upper, wa, wb, wc


def hash2(ix, iy, k):
    return (np.sin(ix * 127.1 + iy * 311.7 + k * 74.7) * 43758.5453) % 1.0


def synthesize(g, size, scale=1.0):
    h, w = g.shape
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    u, v = xs / (w * scale), ys / (h * scale)  # the texture coordinate: the photograph at its real size
    grid = 2.0                                 # triangle cells per photograph
    x = (u + v * 0.5773503) * grid
    y = (v * 1.1547005) * grid
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    upper = (fx + fy) > 1.0
    corners = [
        (np.where(upper, ix + 1, ix), np.where(upper, iy + 1, iy), np.where(upper, 1.0 - fy, 1.0 - fx - fy)),
        (np.where(upper, ix + 1, ix + 1), np.where(upper, iy, iy), np.where(upper, fx + fy - 1.0, fx)),
        (np.where(upper, ix, ix), np.where(upper, iy + 1, iy + 1), np.where(upper, 1.0 - fx, fy)),
    ]
    # (corner 1 and 2 positions differ between the two triangles: lower uses (ix+1,iy) and (ix,iy+1); upper (ix+1,iy) and (ix,iy+1))
    total = np.zeros((size, size), np.float32)
    norm = np.zeros((size, size), np.float32)
    for k, (cx, cy, wgt) in enumerate(corners):
        ox, oy = hash2(cx, cy, 1.0), hash2(cx, cy, 2.0)
        px = (u + ox) % 1.0 * w
        py = (v + oy) % 1.0 * h
        sample = cv2.remap(g, px.astype(np.float32), py.astype(np.float32), cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)
        total += wgt * sample
        norm += wgt * wgt
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
