"""Bakes a tileable stack of sandstone slabs, the look of a stylised cliff face (soft bevelled slabs, vertical cracks, ledge lines, dark gaps,
warm gradients), as the maps the ground shader can use: a height map, the colour, the normal (OpenGL) and occlusion/roughness/metal.
Entirely procedural (no photograph): run `python -I scripts/make_cliff_textures.py OUT_DIR [seed] [size]`; it also writes a sheet of the four
maps for looking at. Every map wraps at its edges.
"""
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 3
N = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
rng = np.random.default_rng(SEED)


def tiled_noise(scale, octaves=4, stretch=(1.0, 1.0)):
    """Value noise that wraps: `scale` cells across, the octaves doubling, `stretch` the cells' width and height factors."""
    total = np.zeros((N, N))
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        cx = max(int(scale * stretch[0]) * 2 ** o, 1)
        cy = max(int(scale * stretch[1]) * 2 ** o, 1)
        grid = rng.random((cy, cx))
        big = np.kron(grid, np.ones((N // cy + 1, N // cx + 1)))[: N, : N]
        total += amp * gaussian_filter(big, sigma=N / (max(cx, cy) * 2.2), mode="wrap")
        norm += amp
        amp *= 0.5
    total /= norm
    return (total - total.min()) / (total.max() - total.min())


def warp(image, strength, scale=6):
    """The picture pushed about by a wrapping noise, so no edge is a ruler line."""
    dx = (tiled_noise(scale, 3) - 0.5) * strength
    dy = (tiled_noise(scale, 3) - 0.5) * strength
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    return map_coordinates(image, [(yy + dy) % N, (xx + dx) % N], order=1, mode="wrap")


# ---- the slabs: jittered cells in rows (wide and low, the rows offset), the borders warped hard so no edge is straight; every cell its own
# height and tilt, its top pillowed by the distance to its border
COLUMNS, ROWS = 3, 7
cells = []
for row in range(ROWS):
    offset = rng.uniform(0.0, 1.0)
    count = COLUMNS + int(rng.integers(-1, 2))
    for column in range(count):
        cx = ((column + rng.uniform(0.25, 0.75)) / count + offset) % 1.0
        cy = (row + rng.uniform(0.3, 0.7)) / ROWS
        cells.append((cx * N, cy * N, rng.uniform(0.45, 1.0), rng.uniform(-0.14, 0.14), rng.uniform(-0.1, 0.1)))
cells = np.array(cells)
yy, xx = np.mgrid[0:N, 0:N].astype(float)
# the field the cells are measured in is warped (the slabs get their wobbling, slanted edges)
wx = (tiled_noise(4, 4) - 0.5) * 150.0
wy = (tiled_noise(6, 4) - 0.5) * 45.0
px = xx + wx
py = yy + wy
nearest = np.full((N, N), 1e9)
second = np.full((N, N), 1e9)
owner = np.zeros((N, N), dtype=int)
for index, (cx, cy, _, _, _) in enumerate(cells):
    dx = np.abs(((px - cx + N / 2) % N) - N / 2) / 1.0
    dy = np.abs(((py - cy + N / 2) % N) - N / 2) * 3.4  # the cells are wide and low
    d = np.hypot(dx, dy)
    closer = d < nearest
    second = np.where(closer, nearest, np.minimum(second, d))
    owner = np.where(closer, index, owner)
    nearest = np.where(closer, d, nearest)
border = second - nearest  # 0 on the border between two cells, growing inward
top = cells[owner, 2]
tilt_x = cells[owner, 3]
tilt_y = cells[owner, 4]
edge = np.clip(border / (0.14 * N), 0.0, 1.0)
edge = edge * edge * (3.0 - 2.0 * edge)
height = top * (0.18 + 0.82 * edge)
height += tilt_x * ((px - cells[owner, 0]) / N) * 4.0 + tilt_y * ((py - cells[owner, 1]) / N) * 4.0
gap = 1.0 - np.clip(border / (0.025 * N), 0.0, 1.0)
# thin vertical cracks through some of the slabs (a line inside the cell, running its height), and the level lines of the beds
cracks = np.zeros((N, N))
for index, (cx, cy, _, _, _) in enumerate(cells):
    if rng.random() < 0.5:
        line_x = cx + rng.uniform(-0.35, 0.35) * N / COLUMNS
        wobble = (tiled_noise(8, 2)[:, 0] - 0.5) * 14.0  # (the crack wanders as it goes down)
        near = np.abs(((px - line_x - wobble[:, None] + N / 2) % N) - N / 2) < 2.0
        cracks = np.maximum(cracks, (near & (owner == index)).astype(float))
cracks = np.clip(gaussian_filter(cracks, 0.9, mode="wrap") * 2.0, 0.0, 1.0)
beds = tiled_noise(3, 3, stretch=(0.25, 6.0))
ledge = (np.abs(beds - 0.5) < 0.008).astype(float) * (1.0 - gap)
ledge = gaussian_filter(ledge, 0.7, mode="wrap")
height = gaussian_filter(height, 1.0, mode="wrap")
height -= 0.18 * cracks
height += (tiled_noise(45, 3) - 0.5) * 0.035  # the surface of the stone is not clean
height = np.clip(height, 0.0, 1.0)
gap = np.clip(gaussian_filter(gap, 2.5, mode="wrap"), 0.0, 1.0)

# ---- the normal: the slope of the height
strength = 22.0
gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
normal = np.dstack([-gx, gy, np.ones_like(gx)])  # (OpenGL: y up in the picture means the surface faces up)
normal /= np.linalg.norm(normal, axis=2, keepdims=True)

# ---- the colour: a warm ramp by height, the gaps dark, the top-facing bevels lit, vertical streaks and stains
light = np.clip(0.5 + 0.9 * (-gx * 0.3 + gy * 0.9) / 3.0, 0.0, 1.2)
streak = tiled_noise(5, 4, stretch=(6.0, 0.4))  # long vertical runs: water stains
stain = tiled_noise(9, 4)
low = np.array([0.6, 0.32, 0.17])
high = np.array([1.0, 0.7, 0.42])
t = np.clip(0.2 + 0.85 * height, 0.0, 1.0)[..., None]
colour = low * (1 - t) + high * t
colour *= (0.82 + 0.3 * light)[..., None]
colour *= (1.0 - 0.45 * streak * 0.5 - 0.2 * stain * 0.5)[..., None]
colour = colour * (1.0 - 0.6 * np.maximum(gap, cracks * 0.8))[..., None]
colour = np.clip(colour + 0.12 * ledge[..., None] * np.array([1.0, 0.8, 0.6]), 0.0, 1.0)

# ---- occlusion (red), roughness (green), metal (blue)
occlusion = 1.0 - 0.6 * np.maximum(gap, cracks) - 0.25 * (1.0 - np.clip(height * 1.4, 0.0, 1.0))
roughness = np.clip(0.78 + 0.12 * stain - 0.2 * ledge - 0.12 * np.clip(light - 0.8, 0.0, 1.0), 0.3, 1.0)
orm = np.dstack([occlusion, roughness, np.zeros_like(roughness)])


def save(array, name):
    Image.fromarray((np.clip(array, 0.0, 1.0) * 255).astype(np.uint8)).save(f"{OUT}/{name}.png", optimize=True)


save(np.dstack([height] * 3), "cliff_height")
save(colour, "cliff_albedo")
save(normal * 0.5 + 0.5, "cliff_normal")
save(orm, "cliff_orm")
sheet = Image.new("RGB", (1200, 1200))
for i, name in enumerate(["cliff_albedo", "cliff_height", "cliff_normal", "cliff_orm"]):
    sheet.paste(Image.open(f"{OUT}/{name}.png").convert("RGB").resize((600, 600)), ((i % 2) * 600, (i // 2) * 600))
sheet.save(f"{OUT}/cliff_sheet.png")
print("cliff maps", N, "seed", SEED, "cells", len(cells))
