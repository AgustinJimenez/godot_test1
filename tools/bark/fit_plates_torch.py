"""Gradient fit of the plates generator (torch_plates.py, the game's own bake) to a photographed height map (AGENT_TASKS/090, step 3).

  python fit_plates_torch.py <folder> <name> [steps=150] [out json]

The whole-number structure (cells per tile, stretch, the noise scales) is searched on a small grid; the nine continuous numbers
(jitter, warp amount, crack width and depth, lip, plate height spread, tilt, fine amount, ragged amount) by Adam on the
same loss the black-box fits use (VGG Gram + sliced Wasserstein of the hillshaded height, bark_perceptual.py), with the
generated height contrast-stretched like the photograph. Starts from the current plate_fits.gd numbers; writes the same json as
plate_gen.fit (params by name) so export_plate.py / pipeline.py can use it. The generator is fully procedural here (no guide map).
"""
import json
import os
import sys

import limits  # (first)

import cv2
import numpy as np
import torch

import analyze_flakes as analysis
import bark_perceptual as bp
import plate_gen as pg
import torch_plates as tp

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SIZE = 512
NU_CHOICES = [int(x) for x in os.environ.get("NU", "3,4").split(",")]  # cells per tile to try (cap them from measure_scale.py: a free choice picks big plates)
FREE = ["jit", "warp_amp", "crack_w", "crack_depth", "lip", "z_var", "tilt", "fine_amp", "rag_amp"]
KEYS = pg.KEYS  # cell_cm stretch jit warp_cm warp_amp crack_w crack_depth lip z_var tilt fine_cm fine_amp rag_cm rag_amp
LOW = {"jit": 0.3, "warp_amp": 0.0, "crack_w": 0.05, "crack_depth": 0.5, "lip": 0.02, "z_var": 0.0, "tilt": 0.0, "fine_amp": 0.0, "rag_amp": 0.0}
HIGH = {"jit": 1.0, "warp_amp": 0.6, "crack_w": 0.2, "crack_depth": 0.9, "lip": 0.5, "z_var": float(os.environ.get("ZVAR_MAX", "0.3")), "tilt": 0.8, "fine_amp": 0.15, "rag_amp": 0.2}


def stretch01(picture):
    """Contrast-stretch to the 1st..99th percentile (the generated height and the photograph's the same way)."""
    flat = picture.flatten()
    q = torch.quantile(flat[::7], torch.tensor([0.01, 0.99], device=picture.device))
    return torch.clamp((picture - q[0]) / (q[1] - q[0] + 1e-6), 0.0, 1.0)


def main():
    folder, name = sys.argv[1], sys.argv[2]
    steps = int(sys.argv[3]) if len(sys.argv) > 3 else 150
    out = sys.argv[4] if len(sys.argv) > 4 else os.path.join(ROOT, "tools", "bark", "fits", name + "_plate_torch.json")
    device = bp.DEVICE
    fit = tp.load_fit(name, os.path.join(ROOT, "systems/world_gen/plate_fits.gd"))
    tile = fit["tile_cm"]
    base = dict(zip(KEYS, fit["params"]))
    photo = analysis.load_height(f"{folder}/{name}_disp.png")
    photo = cv2.resize(photo, (SIZE, SIZE), interpolation=cv2.INTER_AREA)
    target = stretch01(torch.from_numpy(photo).to(device)).view(1, 1, SIZE, SIZE)
    net = bp.build_net()
    target_grams = bp.grams(net, target)
    target_sets = bp.feature_sets(net, target)
    dirs = bp.sw_directions(target_sets)
    target_sw = bp.sw_quantiles(target_sets, dirs)
    sw_weight = float(os.environ.get("SW_WEIGHT", "0.5"))

    def loss_of(values, nu, stretch, seeds=(1.0, 2.0)):
        p = [base[k] for k in KEYS]
        p[0] = tile / nu
        p[1] = stretch
        for k, v in zip(FREE, values):
            p[KEYS.index(k)] = v
        total = 0.0
        pictures = []
        for seed in seeds:
            # (a flat render: no pits, so the style loss sees the plates; the pits are fixed amounts in the shader)
            h = tp.render_height(p, tile, SIZE, seed, None, 0.0, (0.0, 1.0), 0.85, device, pits=False)
            pictures.append(stretch01(h).view(1, 1, SIZE, SIZE))
        batch = torch.cat(pictures)
        generated = bp.grams(net, batch)
        for gen, tar in zip(generated, target_grams):
            total = total + (((gen - tar) ** 2).sum(dim=(1, 2)) / (tar ** 2).sum()).mean()
        total = total + sw_weight * bp.sw_distance(bp.sw_quantiles(bp.feature_sets(net, batch), dirs), target_sw).mean()
        return total

    def to_values(logits):
        return [LOW[k] + (HIGH[k] - LOW[k]) * torch.sigmoid(l) for k, l in zip(FREE, logits)]

    best = None
    for nu in NU_CHOICES:
        for stretch in (1.0777,):
            start = torch.tensor([np.clip((base[k] - LOW[k]) / (HIGH[k] - LOW[k]), 0.05, 0.95) for k in FREE], dtype=torch.float32, device=device)
            logits = torch.log(start / (1 - start)).clone().requires_grad_(True)
            optimiser = torch.optim.Adam([logits], lr=0.05)
            for step in range(steps):
                optimiser.zero_grad()
                loss = loss_of(to_values(logits), nu, stretch)
                loss.backward()
                optimiser.step()
                if step % 25 == 0 or step == steps - 1:
                    print(f"nu {nu} step {step:3d} loss {float(loss):.4f}", flush=True)
            final = float(loss_of([v.detach() for v in to_values(logits)], nu, stretch))
            print(f"nu {nu} final {final:.4f}", flush=True)
            if best is None or final < best[0]:
                best = (final, nu, stretch, [float(v) for v in to_values(logits)])
    final, nu, stretch, values = best
    params = dict(base)
    params["cell_cm"] = tile / nu
    params["stretch"] = stretch
    for k, v in zip(FREE, values):
        params[k] = v
    # the range of the shader's plates() height at 1024 px, seed 1 (what the baker normalises with)
    with torch.no_grad():
        uv = (torch.arange(1024, device=device, dtype=torch.float32) + 0.5) / 1024
        at = torch.stack(torch.meshgrid(uv, uv, indexing="xy"), dim=-1) * tile
        z, _, _ = tp.plates(at, 1.0, torch.tensor([params[k] for k in KEYS], dtype=torch.float32, device=device), tile)
        height_range = (float(z.min()), float(z.max()))
    with open(out, "w") as handle:
        json.dump({"name": name, "tile_m": tile / 100.0, "cm_per_px": tile / SIZE, "loss": final, "params": params,
                   "height_range": height_range,
                   "note": "fit_plates_torch.py (gradient fit, torch_plates.py)"}, handle, indent=1)
    start_loss = float(loss_of([torch.tensor(base[k], device=device) for k in FREE], round(tile / base["cell_cm"]), base["stretch"]))
    print(f"best nu {nu}: loss {final:.4f} (the current numbers: {start_loss:.4f})  ->  {out}")


if __name__ == "__main__":
    main()
