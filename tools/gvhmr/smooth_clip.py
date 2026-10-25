"""Smooths a smplx_motion_to_json.py clip: gaussian filter over the joint rotations (as quaternions, sign-aligned) and the
translation. GVHMR's per-frame output jitters on fast limbs (a run spiked on 11% of frames).

Usage: python tools/gvhmr/smooth_clip.py <clip.json> [sigma_frames=1.0]   (rewrites the file)
"""
import json
import sys

import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.spatial.transform import Rotation


def smooth(path, sigma=1.0):
    clip = json.load(open(path))
    frames = clip["frames"]
    rot = np.array(clip["rotations"]).reshape(frames, -1, 3)
    out = np.empty_like(rot)
    for joint in range(rot.shape[1]):
        quat = Rotation.from_rotvec(rot[:, joint]).as_quat()
        for t in range(1, frames):  # one hemisphere, so the filter does not average across the flip
            if np.dot(quat[t], quat[t - 1]) < 0:
                quat[t] = -quat[t]
        quat = gaussian_filter1d(quat, sigma, axis=0, mode="nearest")
        quat /= np.linalg.norm(quat, axis=1, keepdims=True)
        out[:, joint] = Rotation.from_quat(quat).as_rotvec()
    transl = gaussian_filter1d(np.array(clip["transl"]), sigma * 1.5, axis=0, mode="nearest")
    clip["rotations"] = np.round(out.reshape(frames, -1), 5).tolist()
    clip["transl"] = np.round(transl, 5).tolist()
    json.dump(clip, open(path, "w"), separators=(",", ":"))


if __name__ == "__main__":
    smooth(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 1.0)
