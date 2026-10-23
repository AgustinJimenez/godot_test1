"""One comparison sheet per material, on plain squares (no object, no projection): the photograph beside the procedural
render, the same size, the same light.

  python compare_sheet.py <folder> <name> <family> <fit json> <tile m> <out png> [baked colour png]

family: plate, lump, chip, ring, ledge (the generators in this folder), bark (bark_fast).
Rows: colour (photograph | the baked colour if a picture is given), height lit from the upper left (whole tile, 512 px),
1:1 crops (256 px, the same place), and under it the measured feature sizes of both (measure_scale) as text.
"""
import importlib
import json
import sys

import limits  # (first)

import cv2
import numpy as np

import measure_scale as ms

MODULES = {"plate": "plate_gen", "lump": "lump_gen", "chip": "chip_gen", "ring": "ring_gen",
           "ledge": "ledge_gen", "bark": "bark_fast"}


def load_height(path):
    image = cv2.imread(path, cv2.IMREAD_UNCHANGED).astype(np.float32)
    if image.ndim == 3:
        image = image.mean(axis=2)
    return (image - image.min()) / max(float(image.max() - image.min()), 1e-6)


def lit(height, strength=14.0):
    """Hillshade from the upper left, the same on both pictures (0..1)."""
    gy, gx = np.gradient(cv2.GaussianBlur(height, (0, 0), 0.8))
    shade = 0.5 - strength * 2.0 * (gx + gy) * 2.0
    return np.clip(shade, 0.0, 1.0)


def sizes(height, cm_per_px):
    detrended = height - cv2.GaussianBlur(height, (0, 0), 40)
    return (ms.correlation_length(detrended, 1) * cm_per_px, ms.correlation_length(detrended, 0) * cm_per_px)


def label(image, text):
    image = image.copy()
    cv2.putText(image, text, (6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)
    cv2.putText(image, text, (6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1)
    return image


def main():
    folder, name, family, fit_path, tile_m, out = sys.argv[1:7]
    baked = sys.argv[7] if len(sys.argv) > 7 else ""
    tile_m = float(tile_m)
    data = json.load(open(fit_path))
    module = importlib.import_module(MODULES[family])
    photo = load_height(f"{folder}/{name}_disp.png")
    long_side = max(photo.shape)
    cm_per_px = tile_m * 100.0 / long_side
    side = 512
    # the procedural height over the same tile, at the photograph's own resolution (so both are the same pixels)
    params = {**getattr(module, "PARAMS", {}), **data["params"]} if family != "bark" else data["params"]
    procedural = module.render(params, photo.shape[1], cm_per_px) if photo.shape[0] == photo.shape[1] else \
        module.render(params, long_side, cm_per_px)[:photo.shape[0], :photo.shape[1]]
    photo_color = cv2.imread(f"{folder}/{name}_diff.jpg")
    photo_color = cv2.resize(photo_color, (side, side)) if photo_color is not None else np.zeros((side, side, 3), np.uint8)
    proc_color = np.zeros((side, side, 3), np.uint8)
    if baked:
        proc_color = cv2.resize(cv2.imread(baked), (side, side))
    row1 = np.hstack([label(photo_color, "photograph (colour)"), label(proc_color, "baked colour" if baked else "(no baked colour)")])
    ph = cv2.resize(lit(photo), (side, side))
    pr = cv2.resize(lit(procedural), (side, side))
    row2 = np.hstack([label((np.dstack([ph] * 3) * 255).astype(np.uint8), "photograph, height lit"),
                      label((np.dstack([pr] * 3) * 255).astype(np.uint8), "procedural, height lit")])
    c = min(256, photo.shape[0], photo.shape[1])
    y0, x0 = photo.shape[0] // 3, photo.shape[1] // 3
    crop_p = (np.dstack([lit(photo[y0:y0 + c, x0:x0 + c])] * 3) * 255).astype(np.uint8)
    crop_r = (np.dstack([lit(procedural[y0:y0 + c, x0:x0 + c])] * 3) * 255).astype(np.uint8)
    crops = np.hstack([cv2.resize(label(crop_p, "photo 1:1"), (side // 2, side // 2)),
                       cv2.resize(label(crop_r, "procedural 1:1"), (side // 2, side // 2))])
    sp, sr = sizes(photo, cm_per_px), sizes(procedural, cm_per_px)
    text = np.full((side // 2, side * 2 - side, 3), 30, np.uint8)
    lines = [f"{name}  ({family}, {tile_m} m tile, {cm_per_px:.3f} cm/px)",
             f"feature size (cm) photo {sp[0]:.1f} / {sp[1]:.1f}",
             f"                   procedural {sr[0]:.1f} / {sr[1]:.1f}",
             f"ratio procedural/photo: {sr[0] / max(sp[0], 1e-6):.2f} / {sr[1] / max(sp[1], 1e-6):.2f}  (1.0 = same scale)",
             f"fit loss {data.get('loss', float('nan')):.3f}   (a lower loss is not a better picture)"]
    for i, line in enumerate(lines):
        cv2.putText(text, line, (8, 24 + 26 * i), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
    row3 = np.hstack([crops, text[:, :side * 2 - crops.shape[1]]])
    sheet = np.vstack([row1, row2, row3[:, :row1.shape[1]]])
    cv2.imwrite(out, sheet)
    print("wrote", out, "ratios %.2f %.2f" % (sr[0] / max(sp[0], 1e-6), sr[1] / max(sp[1], 1e-6)))


if __name__ == "__main__":
    main()
