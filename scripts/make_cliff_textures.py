"""Bakes a tileable stack of sandstone slabs, the look of a stylised cliff face (terraced slabs with hard bright lips and deep shadow under
them, sandy shelves with scattered rubble, vertical cracks, ledge lines, painted tone patches), as the maps the ground shader can use: a
height map, the colour, the normal (OpenGL) and occlusion/roughness/metal. Entirely procedural (no photograph).
    python -I scripts/make_cliff_textures.py OUT_DIR [seed] [size]
It also writes a sheet of the four maps for looking at. Every map wraps at its edges.
"""
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 5
N = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
rng = np.random.default_rng(SEED)
yy, xx = np.mgrid[0:N, 0:N].astype(float)


def tiled_noise(scale, octaves=4, stretch=(1.0, 1.0)):
    """Value noise that wraps: `scale` cells across, the octaves doubling, `stretch` the cells' width and height factors."""
    total = np.zeros((N, N))
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        cx = max(int(scale * stretch[0]) * 2 ** o, 1)
        cy = max(int(scale * stretch[1]) * 2 ** o, 1)
        grid = rng.random((cy, cx))
        big = np.kron(grid, np.ones((N // cy + 1, N // cx + 1)))[:N, :N]
        total += amp * gaussian_filter(big, sigma=N / (max(cx, cy) * 2.2), mode="wrap")
        norm += amp
        amp *= 0.5
    total /= norm
    return (total - total.min()) / (total.max() - total.min())


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def slabs(columns, rows, tall_scale, warp_x, warp_y):
    """Cells in rows (wide and low, the rows offset), measured in a warped field so no border is straight. Returns the distance to the
    border (0 on it, growing inward), each pixel's cell, the cells (x, y, height, tilt x, tilt y) and the warped coordinates."""
    cells = []
    for row in range(rows):
        offset = rng.uniform(0.0, 1.0)
        count = columns + int(rng.integers(-1, 2))
        for column in range(count):
            cells.append((((column + rng.uniform(0.25, 0.75)) / count + offset) % 1.0 * N, (row + rng.uniform(0.3, 0.7)) / rows * N,
                          rng.uniform(0.3, 1.0), rng.uniform(-0.16, 0.16), rng.uniform(-0.12, 0.12)))
    cells = np.array(cells)
    px = xx + (tiled_noise(4, 4) - 0.5) * warp_x
    py = yy + (tiled_noise(6, 4) - 0.5) * warp_y
    nearest = np.full((N, N), 1e9)
    second = np.full((N, N), 1e9)
    owner = np.zeros((N, N), dtype=int)
    for index, (cx, cy, _, _, _) in enumerate(cells):
        d = np.hypot(np.abs(((px - cx + N / 2) % N) - N / 2), np.abs(((py - cy + N / 2) % N) - N / 2) * tall_scale)
        closer = d < nearest
        second = np.where(closer, nearest, np.minimum(second, d))
        owner = np.where(closer, index, owner)
        nearest = np.where(closer, d, nearest)
    return second - nearest, owner, cells, px, py


# ---- two sets of slabs: big ones, and small ones in patches (a cliff has beds of different grain)
border_a, owner_a, cells_a, px, py = slabs(3, 7, 3.4, 150.0, 45.0)
border_b, owner_b, cells_b, px_b, py_b = slabs(6, 15, 3.0, 90.0, 30.0)
use_small = smooth(0.52, 0.62, tiled_noise(3, 3))


def terraces(border, owner, cells, px, py):
    """The height of one set of slabs: a flat tilted top with a steep lip (a quick rise at the border), the top stepping by cell."""
    top = cells[owner, 2]
    tilt = cells[owner, 3] * ((px - cells[owner, 0]) / N) + cells[owner, 4] * ((py - cells[owner, 1]) / N)
    lip = smooth(0.0, 0.035 * N, border)  # the steep part
    roll = smooth(0.0, 0.16 * N, border)  # the gentle roundness of the top
    step = np.round(top * 6.0) / 6.0 * 0.5 + top * 0.5  # heights half way to whole terraces
    return (0.1 + 0.9 * step) * (0.3 + 0.55 * lip + 0.15 * roll) + tilt * 4.0


# each set is finished before they are blended (blending the cells themselves would leave hairline steps where the two meet)
height = terraces(border_a, owner_a, cells_a, px, py) * (1 - use_small) + terraces(border_b * 0.8, owner_b, cells_b, px_b, py_b) * use_small
gap = (1.0 - smooth(0.0, 0.016 * N, border_a)) * (1 - use_small) + (1.0 - smooth(0.0, 0.016 * N, border_b * 0.8)) * use_small

# ---- cracks inside some slabs (a wandering vertical line), and the level lines of the beds
cracks = np.zeros((N, N))
wobble = (tiled_noise(8, 2)[:, 0] - 0.5) * 14.0
for index, (cx, cy, _, _, _) in enumerate(cells_a):
    if rng.random() < 0.55:
        line_x = cx + rng.uniform(-0.35, 0.35) * N / 3
        near = np.abs(((px - line_x - wobble[:, None] + N / 2) % N) - N / 2) < 2.0
        cracks = np.maximum(cracks, (near & (owner_a == index) & (use_small < 0.05)).astype(float))
cracks = np.clip(gaussian_filter(cracks, 0.9, mode="wrap") * 2.0, 0.0, 1.0)
beds = tiled_noise(3, 3, stretch=(0.25, 6.0))
ledge = (np.abs(beds - 0.5) < 0.006).astype(float) * (1.0 - gap) * smooth(0.5, 0.62, tiled_noise(6, 3))  # (broken into pieces)
ledge = gaussian_filter(ledge, 0.7, mode="wrap")

# ---- sandy shelves: in the low places between slabs sand lies, flat, with pebbles on it
low_place = smooth(0.6, 0.3, height) * smooth(0.25, 0.55, tiled_noise(7, 4))
sand = np.clip(low_place * 1.6, 0.0, 1.0)
sand = gaussian_filter(sand, 1.5, mode="wrap")
pebble_noise = rng.random((N // 8, N // 8))
pebbles = np.kron(pebble_noise, np.ones((8, 8)))[:N, :N]
pebbles = gaussian_filter((pebbles > 0.993).astype(float), 1.5, mode="wrap")
pebbles = np.clip(pebbles * 14.0, 0.0, 1.0) * (sand > 0.35) * (0.5 + 0.5 * tiled_noise(9, 3))
height = height * (1 - sand * 0.55) + sand * 0.22 + pebbles * 0.12
height -= 0.2 * cracks
height = gaussian_filter(height, 1.0, mode="wrap")
height += (tiled_noise(45, 3) - 0.5) * 0.03  # the surface of the stone is not clean
height = np.clip(height, 0.0, 1.0)
gap = np.clip(gaussian_filter(gap, 2.0, mode="wrap"), 0.0, 1.0) * (1.0 - 0.6 * sand)

# ---- the normal: the slope of the height
strength = 26.0
gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
normal = np.dstack([-gx, gy, np.ones_like(gx)])  # (OpenGL: y up in the picture means the surface faces up)
normal /= np.linalg.norm(normal, axis=2, keepdims=True)

# ---- the shadow under a lip: where something higher stands a little above (towards the top of the picture), the light does not reach
overhang = np.zeros((N, N))
for reach in range(3, int(0.04 * N), 3):
    drop = np.roll(height, reach, axis=0) - height  # how much higher the ground is `reach` pixels above
    overhang = np.maximum(overhang, np.clip((drop - 0.12) * 4.0, 0.0, 1.0) * (1.0 - reach / (0.04 * N)))
overhang = np.clip(gaussian_filter(overhang, 2.0, mode="wrap"), 0.0, 1.0) * (1.0 - sand)

# ---- the colour: light from above (tops bright, the steep lips lit on top and dark under), painted tone patches, stains, sand
sun = np.clip(0.55 + 1.5 * (gy * 0.9 - gx * 0.25) / 4.0, 0.0, 1.4)
streak = tiled_noise(5, 4, stretch=(6.0, 0.4))  # long vertical runs: water stains
patches = tiled_noise(4, 4)
blotch = tiled_noise(12, 3)
low = np.array([0.5, 0.2, 0.08])
high = np.array([0.98, 0.6, 0.28])
t = np.clip(0.15 + 0.95 * height + 0.35 * (patches - 0.5), 0.0, 1.0)[..., None]
colour = low * (1 - t) + high * t
colour *= (0.62 + 0.55 * sun)[..., None] * (1.0 - 0.4 * overhang)[..., None]
colour *= (1.0 - 0.22 * streak - 0.12 * blotch + 0.08)[..., None]
sand_colour = np.array([0.95, 0.6, 0.3]) * (0.75 + 0.35 * sun)[..., None]
colour = colour * (1 - sand[..., None]) + sand_colour * sand[..., None]
colour = colour * (1.0 - 0.55 * np.maximum(gap, cracks * 0.8))[..., None]
colour = np.clip(colour + 0.14 * ledge[..., None] * np.array([1.0, 0.8, 0.6]), 0.0, 1.0)
colour = np.where(pebbles[..., None] > 0.3, colour * np.array([0.6, 0.5, 0.45]), colour)

# ---- occlusion (red), roughness (green), metal (blue)
occlusion = 1.0 - 0.65 * np.maximum(gap, cracks) - 0.25 * overhang - 0.2 * (1.0 - np.clip(height * 1.4, 0.0, 1.0))
roughness = np.clip(0.8 + 0.12 * patches - 0.2 * ledge - 0.12 * np.clip(sun - 0.9, 0.0, 1.0) + 0.1 * sand, 0.3, 1.0)
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
print("cliff maps", N, "seed", SEED, "cells", len(cells_a), len(cells_b))

# ---- packed for the ground shader (when a fourth argument, the assets folder, is given): colour + occlusion, normal + roughness
if len(sys.argv) > 4:
    c = np.dstack([colour, occlusion])
    n = np.dstack([normal[:, :, 0] * 0.5 + 0.5, normal[:, :, 1] * 0.5 + 0.5, roughness, np.ones_like(roughness)])
    Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8)).save(sys.argv[4] + "/cliff_c.png", optimize=True)
    Image.fromarray((np.clip(n, 0, 1) * 255).astype(np.uint8)).save(sys.argv[4] + "/cliff_n.png", optimize=True)
    print("mean linear colour", [round(float(v), 4) for v in (colour ** 2.2).reshape(-1, 3).mean(0)])
