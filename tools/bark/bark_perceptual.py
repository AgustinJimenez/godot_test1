"""Fits the flake generator to a photographed bark by how it LOOKS to a neural network.

The statistics loss of bark_fast.py cannot see edges, gaps or the way flakes lift away, so it picks shapes
that score well and look wrong. Here the loss is the style loss of Gatys et al.: the Gram matrices of
VGG19 features (relu1_1 .. relu5_1) of the generated height picture against the photo's height map;
two pictures with the same Gram matrices have the same texture. The search is CMA-ES over the 27 parameters
(gradient free: the generator has floors and hashes); the pictures come from the numba renderer, the
loss from the GPU.

Usage:
  python bark_perceptual.py fit <folder> <name> <tile metres> [generations] [out json]
(then `python bark_fast.py show <json> <png>` draws it)
"""
import json
import sys

import limits  # (first: the core limit must be set before numba and torch load)

import cma
import numpy as np
import torch
import torchvision

import bark_fast as fast
import procedural_bark as pb

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
LAYERS = {1: 1.0, 6: 1.0, 11: 1.0, 20: 1.0, 29: 1.0}  # relu1_1 relu2_1 relu3_1 relu4_1 relu5_1 in vgg19.features
KEYS = fast.KEYS


def build_net():
    net = torchvision.models.vgg19(weights=torchvision.models.VGG19_Weights.IMAGENET1K_V1).features
    net = net.to(DEVICE).eval()
    for p in net.parameters():
        p.requires_grad_(False)
    return net


def grams(net, pictures):
    """pictures: (N, 1, H, W) in 0..1. Returns a list of (N, C, C) Gram matrices, one for each layer."""
    mean = torch.tensor([0.485, 0.456, 0.406], device=DEVICE).view(1, 3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225], device=DEVICE).view(1, 3, 1, 1)
    x = (pictures.repeat(1, 3, 1, 1) - mean) / std
    out = []
    for index, layer in enumerate(net):
        x = layer(x)
        if index in LAYERS:
            n, c, h, w = x.shape
            flat = x.reshape(n, c, h * w)
            out.append(torch.bmm(flat, flat.transpose(1, 2)) / (c * h * w))
        if index >= max(LAYERS):
            break
    return out


def decode(vector):
    return {k: float(pb.RANGES[k][0] + np.clip(v, 0.0, 1.0) * (pb.RANGES[k][1] - pb.RANGES[k][0]))
            for k, v in zip(KEYS, vector)}


def encode(params):
    return np.clip(np.array([(params.get(k, pb.PARAMS[k]) - pb.RANGES[k][0]) / (pb.RANGES[k][1] - pb.RANGES[k][0]) for k in KEYS]), 0.001, 0.999)


def fit(folder, name, tile_m, generations, out):
    import analyze_flakes as analysis
    net = build_net()
    height = analysis.load_height(f"{folder}/{name}_disp.png")
    cm_per_px = tile_m * 100.0 / height.shape[0]
    size = 384
    target_picture = torch.from_numpy(height).to(DEVICE).view(1, 1, *height.shape)
    # the photo at the same scale as the pictures: crops of `size` px
    crops = []
    rng = np.random.default_rng(5)
    for _ in range(6):
        y0 = int(rng.integers(0, height.shape[0] - size))
        x0 = int(rng.integers(0, height.shape[1] - size))
        crops.append(target_picture[:, :, y0:y0 + size, x0:x0 + size])
    target_grams = [g.mean(dim=0, keepdim=True) for g in grams(net, torch.cat(crops))]
    target_ac = pb.autocorrelation_lengths(height, cm_per_px)

    def evaluate(vectors):
        pictures = []
        stat_loss = []
        for vector in vectors:
            params = decode(vector)
            picture = fast.render(params, size, cm_per_px)
            pictures.append(torch.from_numpy(picture))
            ax, ay = pb.autocorrelation_lengths(picture, cm_per_px)  # (cheap: the size of the pattern; the Gram matrices barely see scale)
            stat_loss.append(abs(np.log(max(ax, 1e-3) / max(target_ac[0], 1e-3))) + abs(np.log(max(ay, 1e-3) / max(target_ac[1], 1e-3))))
        batch = torch.stack(pictures).to(DEVICE).unsqueeze(1)
        generated = grams(net, batch)
        total = torch.zeros(len(vectors), device=DEVICE)
        for gen, tar in zip(generated, target_grams):
            total += ((gen - tar) ** 2).sum(dim=(1, 2)) / (tar ** 2).sum()
        return [float(t) + 0.35 * s for t, s in zip(total.cpu().numpy(), stat_loss)]

    start = encode(pb.PARAMS)
    torch.set_num_threads(limits.CORES)
    es = cma.CMAEvolutionStrategy(start, 0.25, {"bounds": [0, 1], "popsize": 20, "verbose": -9, "seed": 3})
    best_value, best_vector = 1e9, start
    for generation in range(generations):
        candidates = es.ask()
        values = evaluate(candidates)
        es.tell(candidates, values)
        index = int(np.argmin(values))
        if values[index] < best_value:
            best_value, best_vector = values[index], candidates[index]
            print(f"gen {generation:3d} style loss {best_value:.4f}", flush=True)
    with open(out, "w") as handle:
        json.dump({"name": name, "tile_m": tile_m, "cm_per_px": cm_per_px, "loss": best_value,
                   "params": decode(best_vector)}, handle, indent=1)
    print("best", best_value)


if __name__ == "__main__":
    if sys.argv[1] == "fit":
        fit(sys.argv[2], sys.argv[3], float(sys.argv[4]), int(sys.argv[5]) if len(sys.argv) > 5 else 120,
            sys.argv[6] if len(sys.argv) > 6 else f"{sys.argv[3]}_params.json")
