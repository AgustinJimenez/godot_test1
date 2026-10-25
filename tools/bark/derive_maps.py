"""Normal, AO and roughness maps derived from a height map (AGENT_TASKS/090, step 5), and a check against a scan that has them.

  python derive_maps.py check <folder> <name> [relief_cm=?]   compares the derived maps with <name>_nor_gl / _ao / _rough in the folder
  python derive_maps.py make <height.png> <out prefix> <tile_cm> <relief_cm>   writes <prefix>_n.png (normal RG + roughness B) and _c-ao helper <prefix>_ao.png

The height map is 0..1; relief_cm is the real height difference of 0 -> 1 (it sets the slopes). The game's ground scans use
`<name>_c.png` = colour + AO in alpha and `<name>_n.png` = normal XY (OpenGL, y up) + roughness in B (scripts/make_scan_textures.py).
"""
import sys

import cv2
import numpy as np


def load_gray(path):
    image = cv2.imread(path, cv2.IMREAD_UNCHANGED).astype(np.float32)
    if image.ndim == 3:
        image = image.mean(axis=2)
    return image / (65535.0 if image.max() > 255 else 255.0)


def normal_from_height(height, cm_per_px, relief_cm):
    """OpenGL tangent-space normal (x right, y up in the picture, z out) from a 0..1 height; (H, W, 3) in -1..1."""
    z = cv2.GaussianBlur(height, (0, 0), 0.7) * relief_cm
    dx = cv2.Sobel(z, cv2.CV_32F, 1, 0, ksize=3) / (8.0 * cm_per_px)
    dy = cv2.Sobel(z, cv2.CV_32F, 0, 1, ksize=3) / (8.0 * cm_per_px)
    n = np.dstack([-dx, dy, np.ones_like(dx)])  # (image y runs down: OpenGL y runs up)
    return n / np.linalg.norm(n, axis=2, keepdims=True)


def ao_from_height(height, cm_per_px, relief_cm):
    """Cavity occlusion: how far a point sits below its neighbourhood, at two small radii (0.5 and 1 cm), 1 = open. Radii, weights and
    strength were searched against the boulder's scanned AO (correlation 0.62; larger radii or one radius gave 0.54 or less)."""
    z = height * relief_cm
    out = np.zeros_like(z)
    for radius_cm, weight in ((0.5, 0.5), (1.0, 0.5)):
        sigma = max(radius_cm / cm_per_px, 1.0)
        below = np.clip(cv2.GaussianBlur(z, (0, 0), sigma) - z, 0.0, None)
        out += weight * np.clip(below / (0.5 * radius_cm), 0.0, 1.0)
    return 1.0 - 1.5 * out


def roughness_from_height(height, cm_per_px, base=0.75, gain=0.0):
    """A constant (rock, bark and soil are all rough), optionally raised where the surface is busy."""
    detail = np.abs(height - cv2.GaussianBlur(height, (0, 0), 2.0))
    return np.clip(base + gain * detail, 0.0, 1.0)


def check(folder, name, relief_cm=None, tile_cm=None):
    height = load_gray(f"{folder}/{name}_disp.png")
    normal = cv2.imread(f"{folder}/{name}_nor_gl.jpg").astype(np.float32)[:, :, ::-1] / 255.0 * 2 - 1
    ao = load_gray(f"{folder}/{name}_ao.jpg")
    rough = load_gray(f"{folder}/{name}_rough.jpg")
    size = height.shape[0]
    resize = lambda a: cv2.resize(a, (size, size), interpolation=cv2.INTER_AREA)
    normal = np.dstack([resize(normal[..., i]) for i in range(3)])
    normal /= np.linalg.norm(normal, axis=2, keepdims=True) + 1e-6
    ao, rough = resize(ao), resize(rough)
    tile_cm = tile_cm or 150.0
    cm_per_px = tile_cm / size
    best = None
    for relief in ([relief_cm] if relief_cm else (2.0, 4.0, 8.0, 16.0, 32.0)):  # the real relief is unknown: scan it
        mine = normal_from_height(height, cm_per_px, relief)
        angle = np.degrees(np.arccos(np.clip((mine * normal).sum(axis=2), -1, 1)))
        corr_xy = np.corrcoef(mine[..., :2].ravel(), normal[..., :2].ravel())[0, 1]
        print("relief %5.1f cm: normal angle mean %.1f deg  median %.1f  xy correlation %.3f" % (relief, angle.mean(), np.median(angle), corr_xy))
        if best is None or corr_xy > best[0]:
            best = (corr_xy, relief)
    relief = best[1]
    mine_ao = ao_from_height(height, cm_per_px, relief)
    print("AO (relief %.0f cm): correlation %.3f, mean mine %.3f scan %.3f" % (relief, np.corrcoef(mine_ao.ravel(), ao.ravel())[0, 1], mine_ao.mean(), ao.mean()))
    print("roughness: scan mean %.3f std %.3f; constant %.2f has mean error %.3f; correlation of the 'busy' term %.3f" % (
        rough.mean(), rough.std(), rough.mean(), 0.0,
        np.corrcoef(roughness_from_height(height, cm_per_px, 0.0, 1.0).ravel(), rough.ravel())[0, 1]))
    return relief


if __name__ == "__main__":
    if sys.argv[1] == "check":
        check(sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else None)
    elif sys.argv[1] == "make":
        height = load_gray(sys.argv[2])
        tile_cm, relief_cm = float(sys.argv[4]), float(sys.argv[5])
        cm_per_px = tile_cm / height.shape[0]
        normal = normal_from_height(height, cm_per_px, relief_cm)
        rough = roughness_from_height(height, cm_per_px)
        packed = np.dstack([(normal[..., 0] * 0.5 + 0.5), (normal[..., 1] * 0.5 + 0.5), rough])
        cv2.imwrite(sys.argv[3] + "_n.png", (packed[..., ::-1] * 255).astype(np.uint8))  # (RG normal, B roughness; cv2 writes BGR)
        cv2.imwrite(sys.argv[3] + "_ao.png", (ao_from_height(height, cm_per_px, relief_cm) * 255).astype(np.uint8))
        print("wrote", sys.argv[3] + "_n.png", sys.argv[3] + "_ao.png")
    else:
        print(__doc__)
