"""One command from a Poly Haven bark name to a fitted generator and a picture to judge it by.

  python fit_bark.py <polyhaven name> [generations=220] [folder for the downloads]

Downloads the 1k diffuse and displacement maps (CC0) and the real size, fits the generator
(bark_perceptual.py: CMA-ES on the neural style loss), saves fits/<name>.json and writes
<folder>/<name>_vs.png: the photo's height map on the left, the generator's on the right, and
<folder>/<name>_colour.png. Then add the bark to the export (export_fit.py name:tile_m:kind).
"""
import json
import os
import sys
import urllib.request

import limits  # (first)

import cv2
import numpy as np

import bark_fast as fast
import bark_perceptual as perceptual


def open_url(url):
    request = urllib.request.Request(url, headers={"User-Agent": "godot-test1-bark-tools/1.0"})
    return urllib.request.urlopen(request)


def fetch(url, path):
    if not os.path.exists(path):
        with open_url(url) as response, open(path, "wb") as handle:
            handle.write(response.read())


def download(name, folder):
    files = json.load(open_url(f"https://api.polyhaven.com/files/{name}"))
    info = json.load(open_url(f"https://api.polyhaven.com/info/{name}"))
    tile_m = float(info["dimensions"][0]) / 1000.0
    os.makedirs(folder, exist_ok=True)
    diff = files["Diffuse"]["1k"]["jpg"]["url"]
    disp = files["Displacement"]["1k"]
    disp_url = (disp.get("png") or disp.get("jpg"))["url"]
    fetch(diff, f"{folder}/{name}_diff.jpg")
    fetch(disp_url, f"{folder}/{name}_disp.png")
    return tile_m


def main():
    name = sys.argv[1]
    generations = int(sys.argv[2]) if len(sys.argv) > 2 else 220
    folder = sys.argv[3] if len(sys.argv) > 3 else "bark_downloads"
    tile_m = download(name, folder)
    print(f"{name}: tile {tile_m:.2f} m")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fits", f"{name}.json")
    perceptual.fit(folder, name, tile_m, generations, out)
    data = json.load(open(out))
    height = fast.render(data["params"], 512, data["cm_per_px"])
    photo = cv2.imread(f"{folder}/{name}_disp.png", cv2.IMREAD_UNCHANGED).astype(np.float32)
    if photo.ndim == 3:
        photo = photo.mean(axis=2)
    photo = (photo - photo.min()) / (photo.max() - photo.min())
    side = np.hstack([photo[:512, :512], height])
    cv2.imwrite(f"{folder}/{name}_vs.png", (side * 255).astype(np.uint8))
    print(f"wrote {folder}/{name}_vs.png; add `{name}:{tile_m:.2f}:<kind>` to export_fit.py")


if __name__ == "__main__":
    main()
