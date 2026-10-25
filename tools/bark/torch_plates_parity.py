"""Checks torch_plates.py against the game's bake: the alpha (height) of the pitted rock baked by Godot vs the PyTorch render.

  python torch_plates_parity.py [surface name=rock_pitted_mossy] [square_compare index=13]
Needs Godot (GODOT env var). Prints the mean/max absolute difference and the correlation, writes a side-by-side picture to E:/Temp/tx.
"""
import os
import subprocess
import sys

import limits  # (first)

import numpy as np
import torch
from PIL import Image

import torch_plates as tp

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GODOT = os.environ.get("GODOT", "E:/Godot/4.7.2/Godot_v4.7.2-stable_win64.exe")
name = sys.argv[1] if len(sys.argv) > 1 else "rock_pitted_mossy"
index = int(sys.argv[2]) if len(sys.argv) > 2 else 13
out = "E:/Temp/tx/parity_bake.png"
subprocess.run([GODOT, "--path", ROOT, "res://tests/manual/world/square_compare.tscn", "--", "--surface=%d" % index, "--no-match",
                "--save-bake=" + out, "--shot=E:/Temp/tx/parity_shot.png"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=300)
baked = np.asarray(Image.open(out).convert("RGBA"), dtype=np.float32)[..., 3] / 255.0
fit = tp.load_fit(name, os.path.join(ROOT, "systems/world_gen/plate_fits.gd"))
with torch.no_grad():
    mine = tp.render_height(fit["params"], fit["tile_cm"], baked.shape[0], 1.0, fit["guide"], 0.55, fit["height_range"]).cpu().numpy()
diff = np.abs(baked - mine)
print("size", baked.shape, "mean abs diff %.5f  max %.4f  share above 0.02: %.4f  correlation %.5f" % (
    diff.mean(), diff.max(), float((diff > 0.02).mean()), float(np.corrcoef(baked.ravel(), mine.ravel())[0, 1])))
side = np.concatenate([baked, mine, np.clip(diff * 8, 0, 1)], axis=1)
Image.fromarray((side * 255).astype(np.uint8)).save("E:/Temp/tx/parity.png")
