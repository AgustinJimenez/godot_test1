"""GVHMR motion (extract_motion.py's .npz) + the SMPL-X body model -> one small JSON a Godot script can read, no Blender.

Usage: python tools/gvhmr/smplx_motion_to_json.py <SMPLX_NEUTRAL.npz> <motion.npz> <out.json> [fps]

The JSON holds the 55 SMPL-X joints (names, parents, rest positions from the clip's betas) and per frame the 22 body
rotations (axis-angle, local to the parent, rest rotations are identity) and the pelvis translation.
"""
import json
import sys

import numpy as np

NAMES = [
    "pelvis", "left_hip", "right_hip", "spine1", "left_knee", "right_knee", "spine2",
    "left_ankle", "right_ankle", "spine3", "left_foot", "right_foot", "neck",
    "left_collar", "right_collar", "head", "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow", "left_wrist", "right_wrist", "jaw",
    "left_eye_smplhf", "right_eye_smplhf",
] + ["left_hand_%d" % i for i in range(15)] + ["right_hand_%d" % i for i in range(15)]

model = np.load(sys.argv[1], allow_pickle=True)
motion = np.load(sys.argv[2])
fps = float(sys.argv[4]) if len(sys.argv) > 4 else 30.0

betas = motion["betas"].astype(np.float64)
shaped = model["v_template"].astype(np.float64) + model["shapedirs"][:, :, :10].astype(np.float64) @ betas
joints = model["J_regressor"].astype(np.float64) @ shaped  # (55, 3), the rest joints
parents = model["kintree_table"][0].astype(np.int64)
parents[0] = -1

orient = motion["global_orient"].astype(np.float64)  # (T, 3)
pose = motion["body_pose"].astype(np.float64)  # (T, 63)
transl = motion["transl"].astype(np.float64)  # (T, 3)
frames = orient.shape[0]
rotations = np.concatenate([orient[:, None, :], pose.reshape(frames, 21, 3)], axis=1)  # (T, 22, 3)

out = {
    "fps": fps,
    "frames": int(frames),
    "names": NAMES,
    "parents": [int(p) for p in parents],
    "rest": np.round(joints, 5).tolist(),
    "rotations": np.round(rotations, 5).reshape(frames, -1).tolist(),
    "transl": np.round(transl, 5).tolist(),
}
with open(sys.argv[3], "w") as handle:
    json.dump(out, handle, separators=(",", ":"))
print("wrote", sys.argv[3], "frames", frames, "pelvis rest", joints[0].round(3))
