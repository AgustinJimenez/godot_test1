"""Gradient fit of the flake bark generator (torch_bark.py, the game's own bake) to a photographed height map (AGENT_TASKS/090, step 7).

  python fit_bark_torch.py <folder> <name> [steps=150] [out json]       e.g. pine_bark, tree_bark_03

Starts from the current bark_fits.gd numbers. The scale numbers that set whole cell counts (cell width and aspect, ragged and warp scales,
groove / split / fibre / swelling sizes) stay as they are; the other 27 are fitted with Adam inside each parameter's range
(procedural_bark.RANGES, narrowed per bark like fit_pine_long.py), on the same loss as fit_plates_torch.py (VGG Gram + sliced Wasserstein of the
hillshaded, contrast-stretched height, two seeds). The flake mask is a steep sigmoid while fitting (torch_bark `soft`), so the flake shape
numbers get gradients; the result is written with its loss under the hard mask too. Writes the same json as bark_perceptual.fit.
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
import fit_plates_torch as fp
import procedural_bark as pb
import torch_bark as tb

KEYS = list(pb.PARAMS.keys())
FIXED = {"cell_cm", "cell_aspect", "rag_cm", "warp_scale_cm", "fine_cm", "groove_cm", "split_cm", "base_cm", "base_stretch", "fiber_cm", "fiber_seg_cm"}
FREE = [k for k in KEYS if k not in FIXED]
NARROW = {
    "pine_bark": {"len": (1.0, 2.2), "wid": (0.5, 1.0), "tip": (2.0, 3.5), "block": (0.2, 0.8), "angle": (0.0, 0.25), "flake_cover": (1.0, 1.2),
                  "groove_cover": (0.5, 0.9), "groove_w": (0.12, 0.4), "cut_depth": (0.15, 0.3), "rag_amp": (0.15, 0.3), "base_amp": (0.0, 0.2)},
}
SIZE = 512
SOFT = float(os.environ.get("SOFT", "40"))
BARK_SPREAD = {"pine_bark": 2.2, "japanese_cedar_bark": 1.6}


def main():
    folder, name = sys.argv[1], sys.argv[2]
    steps = int(sys.argv[3]) if len(sys.argv) > 3 else 150
    out = sys.argv[4] if len(sys.argv) > 4 else os.path.join(fp.ROOT, "tools", "bark", "fits", name + "_torch.json")
    device = bp.DEVICE
    fit = tb.load_fit(name, os.path.join(fp.ROOT, "systems/world_gen/bark_fits.gd"))
    tile = fit["tile_cm"]
    base = dict(zip(KEYS, fit["params"]))
    ranges = {k: pb.RANGES[k] for k in KEYS}
    ranges.update(NARROW.get(name, {}))
    photo = cv2.resize(analysis.load_height(f"{folder}/{name}_disp.png"), (SIZE, SIZE), interpolation=cv2.INTER_AREA)
    target = fp.stretch01(torch.from_numpy(photo).to(device)).view(1, 1, SIZE, SIZE)
    net = bp.build_net()
    target_grams = bp.grams(net, target)
    target_sets = bp.feature_sets(net, target)
    dirs = bp.sw_directions(target_sets)
    target_sw = bp.sw_quantiles(target_sets, dirs)
    target_edges = fp.edge_stats(target)
    target_low = fp.low_stats(target)
    edge_weight = float(os.environ.get("EDGE_WEIGHT", "0"))
    low_weight = float(os.environ.get("LOW_WEIGHT", "0"))
    sw_weight = float(os.environ.get("SW_WEIGHT", "0.5"))

    def params_of(values):
        p = [base[k] for k in KEYS]
        for k, v in zip(FREE, values):
            p[KEYS.index(k)] = v
        return p

    def loss_of(values, soft=SOFT):
        p = params_of(values)
        pictures = []
        for seed in (1.0, 2.0):
            h = tb.render_height(p, tile, SIZE, seed, (0.0, 1.0), (1.0, 0.5, 0.5), 1.0, soft, device)
            pictures.append(fp.stretch01(h).view(1, 1, SIZE, SIZE))
        batch = torch.cat(pictures)
        total = 0.0
        for gen, tar in zip(bp.grams(net, batch), target_grams):
            total = total + (((gen - tar) ** 2).sum(dim=(1, 2)) / (tar ** 2).sum()).mean()
        total = total + sw_weight * bp.sw_distance(bp.sw_quantiles(bp.feature_sets(net, batch), dirs), target_sw).mean()
        if edge_weight > 0:
            total = total + edge_weight * (torch.abs(fp.edge_stats(batch) - target_edges) / (target_edges + 1e-4)).mean()
        if low_weight > 0:
            total = total + low_weight * (torch.abs(fp.low_stats(batch) - target_low) / (target_low + 1e-4)).mean()
        return total

    lo = torch.tensor([ranges[k][0] for k in FREE], dtype=torch.float32, device=device)
    hi = torch.tensor([ranges[k][1] for k in FREE], dtype=torch.float32, device=device)
    start = torch.tensor([base[k] for k in FREE], dtype=torch.float32, device=device)
    unit = torch.clamp((start - lo) / (hi - lo), 0.03, 0.97)
    logits = torch.log(unit / (1 - unit)).clone().requires_grad_(True)
    optimiser = torch.optim.Adam([logits], lr=0.05)
    start_loss = float(loss_of(list(torch.unbind(lo + (hi - lo) * torch.sigmoid(logits.detach())))))
    best = (start_loss, logits.detach().clone())
    for step in range(steps):
        optimiser.zero_grad()
        loss = loss_of(list(torch.unbind(lo + (hi - lo) * torch.sigmoid(logits))))
        loss.backward()
        optimiser.step()
        if float(loss) < best[0]:
            best = (float(loss), logits.detach().clone())
        if step % 25 == 0 or step == steps - 1:
            print(f"step {step:3d} loss {float(loss):.4f}", flush=True)
    values = list(torch.unbind(lo + (hi - lo) * torch.sigmoid(best[1])))
    with torch.no_grad():
        hard = float(loss_of(values, None))
        hard_start = float(loss_of(list(torch.unbind(lo + (hi - lo) * torch.sigmoid(torch.log(unit / (1 - unit))))), None))
    params = dict(base)
    params.update({k: float(v) for k, v in zip(FREE, values)})
    p = [params[k] for k in KEYS]
    with torch.no_grad():
        uv = (torch.arange(1024, device=device, dtype=torch.float32) + 0.5) / 1024
        at = torch.stack(torch.meshgrid(uv, uv, indexing="xy"), dim=-1) * tile
        h, _ = tb.bark(at, 1.0, torch.tensor(p, dtype=torch.float32, device=device), tile, None)
        height_range = (float(h.min()), float(h.max()))
    json.dump({"name": name, "tile_m": tile / 100.0, "cm_per_px": tile / 1024, "loss_soft": best[0], "loss_hard": hard, "params": params,
               "height_range": height_range, "note": "fit_bark_torch.py (gradient fit, torch_bark.py)"}, open(out, "w"), indent=1)
    print(f"start soft {start_loss:.3f} hard {hard_start:.3f} -> best soft {best[0]:.3f} hard {hard:.3f}; wrote {out}")


if __name__ == "__main__":
    main()
