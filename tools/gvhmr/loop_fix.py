"""Turns a clip into a seamless loop: picks the window whose first and last pose (and the poses beside them, so the motion phase
matches too) are closest, crops to it, closes the small remaining gap by blending the last frames toward the first pose, and keeps the
clip in place (no horizontal travel: the controller moves the character; the speed stays in catalog.json).

Usage: python tools/gvhmr/loop_fix.py <clip.json> [min_seconds=1.0] [max_seconds=3.5]   (rewrites the file; prints the window)
"""
import json
import sys

import numpy as np
from scipy.spatial.transform import Rotation, Slerp


def _quats(clip):
    rot = np.array(clip["rotations"]).reshape(clip["frames"], -1, 3)
    return np.stack([Rotation.from_rotvec(rot[:, j]).as_quat() for j in range(rot.shape[1])], axis=1)  # (T, J, 4)


def _distance(q, a, b):
    """Mean angle (rad) between the same joints of frames a and b."""
    dots = np.abs(np.sum(q[a] * q[b], axis=1)).clip(0.0, 1.0)
    return float(np.mean(2.0 * np.arccos(dots)))


def make_loop(path, min_seconds=1.0, max_seconds=3.5):
    clip = json.load(open(path))
    fps = clip["fps"]
    q = _quats(clip)
    frames = clip["frames"]
    lo, hi = int(min_seconds * fps), min(int(max_seconds * fps), frames - 3)
    best = None
    for a in range(1, max(2, frames - lo - 1)):
        for b in range(a + lo, min(a + hi, frames - 1)):
            score = _distance(q, a, b) + 0.5 * (_distance(q, a - 1, b - 1) + _distance(q, a + 1, min(b + 1, frames - 1)))
            score += 0.002 * a  # prefer an early start (the clip's first frames are the video model's settling)
            if best is None or score < best[0]:
                best = (score, a, b)
    if best is None:
        return None
    _, a, b = best
    n = b - a  # the window a .. b-1 loops back to a
    q = q[a:b]
    transl = np.array(clip["transl"])[a:b]
    # close the gap: blend the last frames toward the first pose
    blend = min(8, n // 4)
    for k in range(blend):
        weight = (k + 1) / (blend + 1)
        for j in range(q.shape[1]):
            keys = Rotation.from_quat([q[n - blend + k, j], q[0, j]])
            q[n - blend + k, j] = Slerp([0.0, 1.0], keys)(weight).as_quat()
    transl = transl.copy()
    transl[:, 0] = transl[0, 0]  # in place: no horizontal travel at all
    transl[:, 2] = transl[0, 2]
    # the vertical bob must close too
    drift = transl[-1, 1] - transl[0, 1]
    transl[:, 1] -= drift * np.linspace(0.0, 1.0, n)
    rot = np.stack([Rotation.from_quat(q[:, j]).as_rotvec() for j in range(q.shape[1])], axis=1)
    clip["rotations"] = np.round(rot.reshape(n, -1), 5).tolist()
    clip["transl"] = np.round(transl, 5).tolist()
    clip["frames"] = n
    json.dump(clip, open(path, "w"), separators=(",", ":"))
    return {"window": (int(a), int(b)), "seconds": round(n / fps, 2), "score": round(float(best[0]), 3), "blend": blend}


if __name__ == "__main__":
    print(make_loop(sys.argv[1], *(float(x) for x in sys.argv[2:4])))
