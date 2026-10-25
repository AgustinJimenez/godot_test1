"""Side-by-side picture of a photographed height map and a torch generator fitted to it (the judge picture of the new-family loop,
AGENT_TASKS/090 step 6): top row the heights (photo | generated), bottom row the same lit from the upper left.

  python compare_torch.py <name> <fit json> <out png> [tile_cm]
The json is from fit_plates_torch.py (has "cell_cm") or fit_courses_torch.py (has "course_cm").
"""
import json
import os
import sys

import limits  # (first)

import cv2
import numpy as np
import torch

import analyze_flakes as analysis
import plate_gen as pg
import procedural_bark as pb
import torch_bark as tb
import torch_courses as tc
import torch_plates as tp

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SIZE = 512


def shade(h):
    gx = cv2.Sobel(h, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(h, cv2.CV_32F, 0, 1, ksize=3)
    return np.clip(0.5 - 3.0 * gx - 3.0 * gy, 0, 1)


def main():
    name, jpath, out = sys.argv[1], sys.argv[2], sys.argv[3]
    data = json.load(open(jpath))
    photo = cv2.resize(analysis.load_height(f"{ROOT}/tools/bark/bark_downloads/{name}_disp.png"), (SIZE, SIZE), interpolation=cv2.INTER_AREA)
    with torch.no_grad():
        if "cell_aspect" in data["params"]:  # a flake bark: photo | the bark_fits.gd numbers | the fitted numbers
            current = tb.load_fit(name, f"{ROOT}/systems/world_gen/bark_fits.gd")
            tile = current["tile_cm"]
            spread = {"pine_bark": 2.2, "japanese_cedar_bark": 1.6}.get(name, 1.0)
            keys = list(pb.PARAMS.keys())
            old = tb.render_height(current["params"], tile, SIZE, 1.0, current["height_range"], current["alpha"], spread).cpu().numpy()
            low, high = data.get("height_range", current["height_range"])
            new = tb.render_height([data["params"][k] for k in keys], tile, SIZE, 1.0, (low, high), current["alpha"], spread).cpu().numpy()
            top = np.concatenate([photo, old, new], axis=1)
            bottom = np.concatenate([shade(photo), shade(old), shade(new)], axis=1)
            cv2.imwrite(out, (np.concatenate([top, bottom], axis=0) * 255).astype(np.uint8))
            print("wrote", out)
            return
        if "course_cm" in data["params"]:
            tile = float(sys.argv[4]) if len(sys.argv) > 4 else data["tile_cm"]
            generated = tc.render_height(data["params"], tile, SIZE, 1.0).cpu().numpy()
        else:
            tile = float(sys.argv[4]) if len(sys.argv) > 4 else data["tile_m"] * 100.0
            low, high = data["height_range"]
            width = high - low
            generated = tp.render_height([data["params"][k] for k in pg.KEYS], tile, SIZE, 1.0, None, 0.0,
                                         (low - 0.5 * width, high + 0.7 * width), 0.85).cpu().numpy()
    top = np.concatenate([photo, generated], axis=1)
    bottom = np.concatenate([shade(photo), shade(generated)], axis=1)
    cv2.imwrite(out, (np.concatenate([top, bottom], axis=0) * 255).astype(np.uint8))
    print("wrote", out)


if __name__ == "__main__":
    main()
