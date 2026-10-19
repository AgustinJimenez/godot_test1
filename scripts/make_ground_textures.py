"""Makes the tileable ground detail textures (no downloads: all generated here).

Each file is RGBA: RGB = a normal map (z up), A = a brightness detail (0.5 = no change).
Run: python scripts/make_ground_textures.py   (needs numpy and PIL)
"""
import numpy as np
from PIL import Image

SIZE = 512
OUT = "assets/textures/ground/"


def band_noise(rng, cutoff_low, cutoff_high, power=1.0):
    """Periodic noise: random phases filtered to a band of frequencies (tiles by construction)."""
    freq = np.fft.fftfreq(SIZE) * SIZE
    fx, fy = np.meshgrid(freq, freq)
    radius = np.sqrt(fx * fx + fy * fy)
    amp = np.where((radius >= cutoff_low) & (radius <= cutoff_high), 1.0 / np.maximum(radius, 1.0) ** power, 0.0)
    spectrum = amp * np.exp(2j * np.pi * rng.random((SIZE, SIZE)))
    field = np.real(np.fft.ifft2(spectrum))
    field -= field.min()
    return field / max(field.max(), 1e-9)


def cells(rng, count):
    """Periodic cell noise: distance to the nearest of `count` points (edges of stones, cracks)."""
    points = rng.random((count, 2)) * SIZE
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    best = np.full((SIZE, SIZE), 1e9)
    second = np.full((SIZE, SIZE), 1e9)
    for px, py in points:
        dx = np.abs(xs - px)
        dy = np.abs(ys - py)
        dx = np.minimum(dx, SIZE - dx)
        dy = np.minimum(dy, SIZE - dy)
        dist = np.sqrt(dx * dx + dy * dy)
        second = np.minimum(second, np.maximum(best, dist))
        best = np.minimum(best, dist)
    return best, second


def pack(height, strength, name):
    h = height - height.min()
    h /= max(h.max(), 1e-9)
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * SIZE / 64.0 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * SIZE / 64.0 * strength
    normal = np.stack([-gx, -gy, np.ones_like(h)], -1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    rgb = (normal * 0.5 + 0.5)
    # the brightness: the high parts lighter, the low parts (crevices, hollows) darker
    light = np.clip(0.5 + (h - 0.5) * 0.9, 0.0, 1.0)
    image = np.dstack([rgb, light])
    Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT + name)


def main():
    rng = np.random.default_rng(7)
    # rock: broken stone faces with cracks between them and a rough grain on top
    best, second = cells(rng, 26)
    crack = np.clip((second - best) / 7.0, 0.0, 1.0)
    rock = crack * 0.55 + band_noise(rng, 2, 40, 1.2) * 0.3 + band_noise(rng, 30, 160, 0.8) * 0.15
    pack(rock, 2.4, "rock.png")
    # soil: crumbs and small clods
    soil = band_noise(rng, 3, 60, 1.0) * 0.45 + band_noise(rng, 40, 200, 0.6) * 0.55
    pack(soil, 1.6, "soil.png")
    # sand: fine grain over long soft ripples
    ys = np.arange(SIZE)[:, None]
    ripples = (np.sin((ys + band_noise(rng, 1, 6, 1.0) * 60.0) * 2 * np.pi * 8 / SIZE) * 0.5 + 0.5)
    sand = ripples * 0.4 + band_noise(rng, 60, 220, 0.4) * 0.6
    pack(sand, 1.0, "sand.png")


main()
