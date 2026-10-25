"""Gradient fit of torch_courses.py to a photographed height map (the first iteration of the new-family loop, AGENT_TASKS/090 step 6).

  python fit_courses_torch.py <folder> <name> <tile_cm> [steps=100] [out json]      env: COURSES=10,16 JOINTS=30 EDGE_WEIGHT LOW_WEIGHT
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
import torch_courses as tc

FREE = ["offset", "warp_amp", "crack_cm", "crack_depth", "open", "z_var", "tilt", "ledge", "fine_amp", "bevel"]
LOW = {"offset": 0.0, "warp_amp": 0.0, "crack_cm": 0.3, "crack_depth": 0.3, "open": 0.2, "z_var": 0.0, "tilt": 0.0, "ledge": 0.0, "fine_amp": 0.0, "bevel": 0.3}
HIGH = {"offset": 1.0, "warp_amp": 1.0, "crack_cm": 3.0, "crack_depth": 0.95, "open": 0.8, "z_var": 0.4, "tilt": 0.6, "ledge": 0.8, "fine_amp": 0.12, "bevel": 4.0}
SIZE = 512


def main():
    folder, name, tile = sys.argv[1], sys.argv[2], float(sys.argv[3])
    steps = int(sys.argv[4]) if len(sys.argv) > 4 else 100
    out = sys.argv[5] if len(sys.argv) > 5 else os.path.join(fp.ROOT, "tools", "bark", "fits", name + "_courses.json")
    device = bp.DEVICE
    photo = cv2.resize(analysis.load_height(f"{folder}/{name}_disp.png"), (SIZE, SIZE), interpolation=cv2.INTER_AREA)
    target = fp.stretch01(torch.from_numpy(photo).to(device)).view(1, 1, SIZE, SIZE)
    net = bp.build_net()
    target_grams = bp.grams(net, target)
    target_sets = bp.feature_sets(net, target)
    dirs = bp.sw_directions(target_sets)
    target_sw = bp.sw_quantiles(target_sets, dirs)
    target_edges = fp.edge_stats(target)
    target_low = fp.low_stats(target)
    edge_weight = float(os.environ.get("EDGE_WEIGHT", "1.0"))
    low_weight = float(os.environ.get("LOW_WEIGHT", "1.0"))

    def loss_of(values, course_cm, joint_cm):
        p = dict(tc.DEFAULT)
        p["course_cm"], p["joint_cm"] = course_cm, joint_cm
        for k, v in zip(FREE, values):
            p[k] = v
        pictures = [fp.stretch01(tc.render_height(p, tile, SIZE, seed, device)).view(1, 1, SIZE, SIZE) for seed in (1.0, 2.0)]
        batch = torch.cat(pictures)
        total = 0.0
        for gen, tar in zip(bp.grams(net, batch), target_grams):
            total = total + (((gen - tar) ** 2).sum(dim=(1, 2)) / (tar ** 2).sum()).mean()
        total = total + 0.5 * bp.sw_distance(bp.sw_quantiles(bp.feature_sets(net, batch), dirs), target_sw).mean()
        total = total + edge_weight * (torch.abs(fp.edge_stats(batch) - target_edges) / (target_edges + 1e-4)).mean()
        total = total + low_weight * (torch.abs(fp.low_stats(batch) - target_low) / (target_low + 1e-4)).mean()
        return total

    to_values = lambda logits: [LOW[k] + (HIGH[k] - LOW[k]) * torch.sigmoid(l) for k, l in zip(FREE, logits)]
    best = None
    for course in [float(x) for x in os.environ.get("COURSES", "10,16").split(",")]:
        for joint in [float(x) for x in os.environ.get("JOINTS", "30").split(",")]:
            start = torch.tensor([np.clip((tc.DEFAULT[k] - LOW[k]) / (HIGH[k] - LOW[k]), 0.05, 0.95) for k in FREE], dtype=torch.float32, device=device)
            logits = torch.log(start / (1 - start)).clone().requires_grad_(True)
            optimiser = torch.optim.Adam([logits], lr=0.05)
            for step in range(steps):
                optimiser.zero_grad()
                loss = loss_of(to_values(logits), course, joint)
                loss.backward()
                optimiser.step()
            final = float(loss_of([v.detach() for v in to_values(logits)], course, joint))
            print(f"course {course} joint {joint}: final {final:.3f}", flush=True)
            if best is None or final < best[0]:
                best = (final, course, joint, [float(v) for v in to_values(logits)])
    final, course, joint, values = best
    params = dict(tc.DEFAULT)
    params["course_cm"], params["joint_cm"] = course, joint
    params.update(dict(zip(FREE, values)))
    json.dump({"name": name, "tile_cm": tile, "loss": final, "params": params, "note": "fit_courses_torch.py (torch only, no shader yet)"}, open(out, "w"), indent=1)
    print("best", final, {k: round(v, 3) for k, v in params.items()}, "->", out)


if __name__ == "__main__":
    main()
