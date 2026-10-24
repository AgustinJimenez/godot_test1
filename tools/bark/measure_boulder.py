"""Measures what a procedural height map should share with the photographed one, from the height data (no style loss).

  python measure_boulder.py <photo disp png> <bake png (alpha = height)> <tile cm>

Prints, for both: the relief at each size (band-pass std by wavelength), the height and slope quantiles, the edge density and the
mean height profile across the strongest edges (the step height, the width of the ramp, whether there is a rim)."""
import sys

import limits  # (first)

import cv2
import numpy as np
from scipy.ndimage import map_coordinates


def load(path, alpha):
    image = cv2.imread(path, cv2.IMREAD_UNCHANGED).astype(np.float32)
    if alpha:
        image = image[..., 3]
    elif image.ndim == 3:
        image = image.mean(axis=2)
    image = cv2.resize(image, (1024, 1024), interpolation=cv2.INTER_AREA)
    return (image - np.percentile(image, 0.5)) / (np.percentile(image, 99.5) - np.percentile(image, 0.5))


def bands(h, cm_per_px):
    """std of the band-pass picture (difference of Gaussians) for wavelengths doubling from 1.4 cm to 90 cm."""
    out = []
    for wavelength in (1.4, 2.8, 5.6, 11.0, 22.0, 45.0, 90.0):
        sigma = wavelength / cm_per_px / 4.0
        low = cv2.GaussianBlur(h, (0, 0), sigma)
        high = cv2.GaussianBlur(h, (0, 0), sigma * 2.0)
        out.append((wavelength, float((low - high).std())))
    return out


def edge_profile(h, cm_per_px, half_cm=10.0):
    """Mean height along the gradient direction across the strongest edges, high side first, with the step and the ramp width."""
    smooth = cv2.GaussianBlur(h, (0, 0), 2.0)
    gx = cv2.Sobel(smooth, cv2.CV_32F, 1, 0, ksize=3) / 8.0
    gy = cv2.Sobel(smooth, cv2.CV_32F, 0, 1, ksize=3) / 8.0
    mag = np.hypot(gx, gy)
    threshold = np.percentile(mag, 97.0)
    local_max = (mag == cv2.dilate(mag, np.ones((5, 5), np.uint8))) & (mag > threshold)
    ys, xs = np.nonzero(local_max)
    n = int(half_cm / cm_per_px)
    steps = np.arange(-n, n + 1)
    profiles = []
    for y, x in zip(ys[::3], xs[::3]):
        dx, dy = gx[y, x] / (mag[y, x] + 1e-9), gy[y, x] / (mag[y, x] + 1e-9)
        line = map_coordinates(smooth, [y + steps * dy, x + steps * dx], order=1, mode="nearest")
        profiles.append(line - line[n])
    profiles = np.array(profiles)
    mean = profiles.mean(axis=0)
    step = float(mean[-1] - mean[0])
    ramp = float(np.abs(np.diff(mean)).sum())
    # width over which 80 % of the step happens (px -> cm)
    centre = mean[n]
    lo, hi = mean[0], mean[-1]
    inside = np.nonzero((mean > lo + 0.1 * (hi - lo)) & (mean < lo + 0.9 * (hi - lo)))[0]
    width = (inside.max() - inside.min() + 1) * cm_per_px if inside.size else 0.0
    rim = float(max(profiles.mean(axis=0)[n - n // 3:n + n // 3].max() - hi, 0.0))
    return mean, step, width, rim, len(profiles), float(local_max.sum()) / local_max.size * 1e4


def report(name, h, cm_per_px):
    print(f"== {name}")
    print("relief by wavelength (cm: std):", "  ".join(f"{w:g}: {s:.4f}" for w, s in bands(h, cm_per_px)))
    print("height quantiles 5/25/50/75/95:", np.percentile(h, [5, 25, 50, 75, 95]).round(3))
    gx = cv2.Sobel(cv2.GaussianBlur(h, (0, 0), 1.0), cv2.CV_32F, 1, 0) / 8.0 / cm_per_px
    gy = cv2.Sobel(cv2.GaussianBlur(h, (0, 0), 1.0), cv2.CV_32F, 0, 1) / 8.0 / cm_per_px
    print("slope quantiles 50/90/99 (height per cm):", np.percentile(np.hypot(gx, gy), [50, 90, 99]).round(4))
    mean, step, width, rim, count, density = edge_profile(h, cm_per_px)
    print(f"edges: strong-edge points per 10k px {density:.1f}; mean profile step {step:+.3f}, 10-90 % width {width:.2f} cm, rim over the high side {rim:.3f}")
    print("profile (every 2nd sample, -10 cm .. +10 cm):", mean[::2].round(3))


if __name__ == "__main__":
    tile = float(sys.argv[3])
    cm = tile / 1024.0
    report("photograph", load(sys.argv[1], False), cm)
    report("procedural", load(sys.argv[2], True), cm)


def unevenness(name, h, cm_per_px):
    """Where the roughness sits: the local std of the fine relief (< 11 cm) in 64 px blocks, its percentiles, and the share of blocks that are smooth."""
    fine = h - cv2.GaussianBlur(h, (0, 0), 11.0 / cm_per_px / 4.0)
    blocks = fine.reshape(16, 64, 16, 64).std(axis=(1, 3)).ravel()
    q = np.percentile(blocks, [10, 50, 90])
    print(f"{name}: fine-relief std per 64 px block 10/50/90 %: {q.round(4)}, spread p90/p10 {q[2] / q[0]:.2f}, smooth blocks (< half the median) {np.mean(blocks < 0.5 * q[1]) * 100:.0f} %")
    slope = np.hypot(cv2.Sobel(h, cv2.CV_32F, 1, 0) / 8.0, cv2.Sobel(h, cv2.CV_32F, 0, 1) / 8.0)
    big = slope.reshape(16, 64, 16, 64).max(axis=(1, 3)).ravel()
    print(f"{name}: steepest slope per block 10/50/90 %: {np.percentile(big, [10, 50, 90]).round(3)}")


if __name__ == "__main__":
    unevenness("photograph", load(sys.argv[1], False), cm)
    unevenness("procedural", load(sys.argv[2], True), cm)


def outlines(name, h, cm_per_px):
    """The long edges (lobe outlines, cracks): non-maximum-suppressed gradient ridges above a level, joined into chains.
    Prints the total length per square metre, the chain count, and the lengths of the chains (cm) at percentiles."""
    smooth = cv2.GaussianBlur(h, (0, 0), 2.5)
    gx = cv2.Sobel(smooth, cv2.CV_32F, 1, 0, ksize=3) / 8.0 / cm_per_px
    gy = cv2.Sobel(smooth, cv2.CV_32F, 0, 1, ksize=3) / 8.0 / cm_per_px
    mag = np.hypot(gx, gy)
    out = []
    for level in (0.025, 0.04):
        ridge = (mag == cv2.dilate(mag, np.ones((3, 3), np.uint8))) & (mag > level)
        ridge = cv2.dilate(ridge.astype(np.uint8), np.ones((7, 7), np.uint8))
        count, labels, stats, _ = cv2.connectedComponentsWithStats(ridge)
        skeleton_len = stats[1:, 4] / 7.0 * cm_per_px  # (a 3 px wide ridge: area / 3 is about the length in px)
        long_chains = skeleton_len[skeleton_len > 4.0]
        out.append((level, float(skeleton_len.sum()) / (1024 * cm_per_px / 100.0) ** 2, len(long_chains),
                    np.percentile(long_chains, [50, 90]).round(0) if len(long_chains) else [0, 0], float(long_chains.sum()) / (1024 * cm_per_px / 100.0) ** 2))
    for level, per_m2, n_long, pct, long_per_m2 in out:
        print(f"{name}: edges above slope {level}: total {per_m2:.0f} cm per m2, chains longer than 4 cm: {n_long} (median / p90 length {pct} cm), their length {long_per_m2:.0f} cm per m2")


if __name__ == "__main__":
    outlines("photograph", load(sys.argv[1], False), cm)
    outlines("procedural", load(sys.argv[2], True), cm)


def copy_error(photo_path, bake_path):
    """For a bake that copies the photograph's layout: the pixel correlation of the heights and of the heights lit from the upper left."""
    a = load(photo_path, False)
    b = load(bake_path, True)
    def lit(h):
        sm = cv2.GaussianBlur(h, (0, 0), 0.7)
        return 0.5 - 8.0 * (cv2.Sobel(sm, cv2.CV_32F, 1, 0) + cv2.Sobel(sm, cv2.CV_32F, 0, 1)) / 8.0
    def corr(x, y):
        x = x - x.mean()
        y = y - y.mean()
        return float((x * y).sum() / np.sqrt((x * x).sum() * (y * y).sum()))
    print(f"copy: height correlation {corr(a, b):.3f}, lit-height correlation {corr(lit(a), lit(b)):.3f}, mean abs height error {np.abs(a - b).mean():.4f}")


if __name__ == "__main__":
    copy_error(sys.argv[1], sys.argv[2])
