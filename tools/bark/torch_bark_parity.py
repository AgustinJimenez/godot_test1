"""Checks torch_bark.py against the game's bake: the alpha (height) of a flake bark baked by Godot with the integer hash
(PLANET_BARK_INT_HASH=1) vs the PyTorch render.

  python torch_bark_parity.py [bark name=tree_bark_03] [square_compare index=3] [height spread=1.0]
Needs Godot (GODOT env var). Prints the mean/max difference and the correlation; writes E:/Temp/tx/parity_bark.png (baked | torch | diff x8).
"""
import os
import subprocess
import sys

import limits  # (first)

import numpy as np
import torch
from PIL import Image

import torch_bark as tb

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GODOT = os.environ.get("GODOT", "E:/Godot/4.7.2/Godot_v4.7.2-stable_win64.exe")
name = sys.argv[1] if len(sys.argv) > 1 else "tree_bark_03"
index = int(sys.argv[2]) if len(sys.argv) > 2 else 3
spread = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
out = "E:/Temp/tx/parity_bark_bake.png"
env = dict(os.environ, PLANET_BARK_INT_HASH="1")
subprocess.run([GODOT, "--path", ROOT, "res://tests/manual/world/square_compare.tscn", "--", "--surface=%d" % index, "--no-match",
                "--save-bake=" + out, "--shot=E:/Temp/tx/parity_bark_shot.png"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
               check=True, timeout=300, env=env)
baked = np.asarray(Image.open(out).convert("RGBA"), dtype=np.float32)[..., 3] / 255.0
fit = tb.load_fit(name, os.path.join(ROOT, "systems/world_gen/bark_fits.gd"))
with torch.no_grad():
    mine = tb.render_height(fit["params"], fit["tile_cm"], baked.shape[0], 1.0, fit["height_range"], fit["alpha"], spread).cpu().numpy()
diff = np.abs(baked - mine)
print("size", baked.shape, "mean abs diff %.5f  max %.4f  share above 0.02: %.4f  correlation %.5f" % (
    diff.mean(), diff.max(), float((diff > 0.02).mean()), float(np.corrcoef(baked.ravel(), mine.ravel())[0, 1])))
side = np.concatenate([baked, mine, np.clip(diff * 8, 0, 1)], axis=1)
Image.fromarray((side * 255).astype(np.uint8)).save("E:/Temp/tx/parity_bark.png")
