"""Writes the fitted bark generators as a GDScript file the game bakes its bark from.

Usage: python export_fit.py <folder with the photos> <out .gd> <name:tile_m:godot_kind> ...
For each bark: the fitted parameters (fits/<name>.json), the range of the heights the generator makes
(to bring them to 0..1) and a colour ramp of 8 colours taken from the photo by height.
"""
import json
import sys

import cv2
import numpy as np

import bark_fast as fast
import procedural_bark as pb


def palette_of(folder, name, height_norm):
    colour = cv2.imread(f"{folder}/{name}_diff.jpg").astype(np.float32)[:, :, ::-1] / 255.0
    colour = cv2.resize(colour, (height_norm.shape[1], height_norm.shape[0]), interpolation=cv2.INTER_AREA)
    order = np.argsort(height_norm.ravel())
    flat = colour.reshape(-1, 3)[order]
    bins = np.array_split(flat, 8)
    return [list(map(float, b.mean(axis=0))) for b in bins]


def colour_model(folder, name, height_norm, cm_per_px):
    """Colour = mean x (1 + gain x cavity) x (1 + mottle x noise): gain from how the photo's brightness follows how
    far a point sits below its surroundings, mottle from what is left (the slow variation of the albedo)."""
    colour = cv2.imread(f"{folder}/{name}_diff.jpg").astype(np.float32)[:, :, ::-1] / 255.0
    colour = cv2.resize(colour, (height_norm.shape[1], height_norm.shape[0]), interpolation=cv2.INTER_AREA)
    lum = colour @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    sigma = max(2.0 / cm_per_px, 1.0)
    cavity = height_norm - cv2.GaussianBlur(height_norm, (0, 0), sigma)
    mean_lum = float(lum.mean())
    var = float(cavity.var())
    gain = float(np.cov(lum.ravel(), cavity.ravel())[0, 1] / max(var, 1e-9) / max(mean_lum, 1e-6))
    residual = lum / max(mean_lum, 1e-6) - (1.0 + gain * cavity)
    mottle = float(cv2.GaussianBlur(residual, (0, 0), 6.0 / cm_per_px).std())
    mean_colour = [float(c) for c in colour.reshape(-1, 3).mean(axis=0)]
    return mean_colour, gain, mottle, float(lum.std() / max(mean_lum, 1e-6))


def lifted(colour, factor):
    """A colour (sRGB) with its linear brightness multiplied: a dark photograph is brought to a bark albedo."""
    linear = np.power(np.clip(np.array(colour, dtype=np.float64), 0.0, 1.0), 2.2) * factor
    return list(np.power(np.clip(linear, 0.0, 1.0), 1.0 / 2.2))


def lift_of(mean_colour, target=0.1):
    """The factor that brings the mean linear luminance to `target` (never darkens, at most 2.6, as the atlas)."""
    linear = np.power(np.array(mean_colour, dtype=np.float64), 2.2)
    lum = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    return float(np.clip(target / max(lum, 1e-4), 1.0, 2.6))


NL = chr(10)
T = chr(9)


def entry(name, kind, tile_m, params, keys, h, ramp, mean_colour, gain, mottle, alpha_gamma=1.0, stats=(0.5, 0.5), centres=None, shares=None):
    """The lines of one bark (every line short: the project's lint)."""
    out = [T * 2 + '"%s": {' % name, T * 3 + '"kind": %s, "tile_cm": %.1f,' % (kind, float(tile_m) * 100)]
    out.append(T * 3 + '"params": PackedFloat32Array([')
    for i in range(0, len(keys), 7):
        out.append(T * 4 + ", ".join("%.5f" % params.get(k, pb.PARAMS[k]) for k in keys[i:i + 7]) + ",")
    out.append(T * 3 + "]),")
    out.append(T * 3 + '"height_range": Vector2(%.4f, %.4f),' % (float(h.min()), float(h.max())))
    out.append(T * 3 + '"ramp": [')
    for c in ramp:
        out.append(T * 4 + "Color(%.4f, %.4f, %.4f)," % tuple(c))
    out.append(T * 3 + "],")
    out.append(T * 3 + '"mean": Color(%.4f, %.4f, %.4f),' % tuple(mean_colour))
    out.append(T * 3 + '"gain": %.3f, "mottle": %.3f,' % (gain, mottle))
    out.append(T * 3 + '"alpha_scale": %.3f, "alpha_from": %.3f, "alpha_to": %.3f,' % (alpha_gamma, stats[0], stats[1]))
    out.append(T * 3 + '"palette": [')
    for c in centres:
        out.append(T * 4 + "Color(%.4f, %.4f, %.4f)," % tuple(c))
    out.append(T * 3 + "],")
    out.append(T * 3 + '"palette_shares": [%s]},' % ", ".join("%.3f" % x for x in shares))
    return out


def clusters_of(folder, name, k=3):
    """The photograph's main colours (k-means in linear RGB), brightest first, with their shares: the per-flake palette."""
    colour = cv2.imread(f"{folder}/{name}_diff.jpg").astype(np.float32)[:, :, ::-1] / 255.0
    small = cv2.resize(colour, (128, 128), interpolation=cv2.INTER_AREA).reshape(-1, 3)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.01)
    chroma = (small.max(axis=1) - small.min(axis=1))[:, None]
    features = np.hstack([small, 2.5 * chroma]).astype(np.float32)  # (saturated colours form their own cluster)
    _, labels, _ = cv2.kmeans(features, k, None, criteria, 4, cv2.KMEANS_PP_CENTERS)
    labels = labels.ravel()
    centres = np.array([small[labels == i].mean(axis=0) if (labels == i).any() else small.mean(axis=0) for i in range(k)])
    shares = np.bincount(labels, minlength=k) / labels.size
    order = np.argsort(-centres @ np.array([0.2126, 0.7152, 0.0722]))
    return [list(map(float, centres[i])) for i in order], [float(shares[i]) for i in order]


def main():
    folder, out = sys.argv[1], sys.argv[2]
    lines = ["# Generated by tools/bark/export_fit.py from the fits in tools/bark/fits: do not edit.",
             "class_name BarkFits", "extends RefCounted", "",
             "## The fitted generators of the photographed barks (parameters, height range, colour model)",
             "static func fits() -> Dictionary:", "	return {"]
    keys = fast.KEYS
    for spec in sys.argv[3:]:
        name, tile_m, kind = spec.split(":")
        data = json.load(open(f"tools/bark/fits/{name}.json"))
        params = {**pb.PARAMS, **data["params"]}
        cm = data["cm_per_px"]
        h = fast._render(512, cm, fast.vector(params), 1.0)
        photo = cv2.imread(f"{folder}/{name}_disp.png", cv2.IMREAD_UNCHANGED).astype(np.float32)
        if photo.ndim == 3:
            photo = photo.mean(axis=2)
        photo = (photo - photo.min()) / (photo.max() - photo.min())
        ramp = palette_of(folder, name, photo)
        mean_colour, gain, mottle, contrast = colour_model(folder, name, photo, cm)
        lift = lift_of(mean_colour)
        ramp = [lifted(c, lift) for c in ramp]
        mean_colour = lifted(mean_colour, lift)
        print(name, "albedo lift x%.2f" % lift)
        print(name, "gain %.2f mottle %.3f contrast %.3f" % (gain, mottle, contrast))
        norm = (h - h.min()) / max(float(h.max() - h.min()), 1e-6)
        # the stored height gets the photograph's mean and spread (the plant shader's masks read it: lichen on
        # the high parts, the cavity ambient occlusion)
        k = float(np.clip(photo.std() / max(float(norm.std()), 1e-3), 0.2, 1.5))
        alpha_gamma = k
        print(name, "height mean %.2f/%.2f std %.2f/%.2f -> scale %.2f" % (norm.mean(), photo.mean(), norm.std(), photo.std(), k))
        print("   (the exporter writes scale and the mean pair)")
        stats = (float(norm.mean()), float(photo.mean()))
        centres, shares = clusters_of(folder, name)
        centres = [lifted(c, lift) for c in centres]
        lines += entry(name, kind, tile_m, params, keys, h, ramp, mean_colour, gain, mottle, alpha_gamma, stats, centres, shares)
    lines += [T + "}", "", "", "const KEYS := ["] + [T + '"%s",' % k for k in keys] + ["]", ""]
    open(out, "w").write("\n".join(lines))
    print("wrote", out)


if __name__ == "__main__":
    main()
