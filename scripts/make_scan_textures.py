"""Packs the ambientCG scans (CC0, https://ambientcg.com) the ground shader uses up close into two textures each:
  <name>_c.png  RGB the colour, A the ambient occlusion
  <name>_n.png  RG the normal (OpenGL, y up), B the roughness
The sets are read from E:/Temp/claude/refs/ground_sets/<set>/ (outside the project). Run: python -I scripts/make_scan_textures.py
It also prints each colour map's mean, which goes in planet_ground.gdshader (the scans change the detail, not the soil's own colour)."""
from PIL import Image
import numpy as np

SETS = {"gravel": "Ground110", "red": "Ground111", "leaf": "Ground106"}
SOURCE = "E:/Temp/claude/refs/ground_sets/{0}/{0}_1K-JPG_{1}.jpg"
OUT = "assets/textures/ground/scans/"

for name, asset in SETS.items():
    colour = Image.open(SOURCE.format(asset, "Color")).convert("RGB")
    occlusion = Image.open(SOURCE.format(asset, "AmbientOcclusion")).convert("L")
    normal = Image.open(SOURCE.format(asset, "NormalGL")).convert("RGB")
    rough = Image.open(SOURCE.format(asset, "Roughness")).convert("L")
    c = np.dstack([np.asarray(colour), np.asarray(occlusion)])
    n = np.dstack([np.asarray(normal)[:, :, 0], np.asarray(normal)[:, :, 1], np.asarray(rough), np.full(c.shape[:2], 255, np.uint8)])
    Image.fromarray(c, "RGBA").save(OUT + name + "_c.png", optimize=True)
    Image.fromarray(n, "RGBA").save(OUT + name + "_n.png", optimize=True)
    linear = (np.asarray(colour).astype(float) / 255.0) ** 2.2
    print(name, asset, "mean linear colour", [round(float(v), 4) for v in linear.reshape(-1, 3).mean(0)])
