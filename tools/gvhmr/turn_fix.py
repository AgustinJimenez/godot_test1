"""Measures how far a clip turns (the pelvis yaw, hip axis unwrapped over the clip) and optionally rescales it to a nominal angle.

Usage: python tools/gvhmr/turn_fix.py <clip.json>                  prints the total turn in degrees (+ = to the character's left)
       python tools/gvhmr/turn_fix.py <clip.json> <target_degrees>  rewrites the clip so it turns exactly that much (sign included)
The correction is a yaw added to the pelvis rotation, growing with the clip's progress, so the pose and the timing are kept.
"""
import json
import sys

import numpy as np
from scipy.spatial.transform import Rotation

sys.path.insert(0, __file__.rsplit("/", 1)[0].rsplit("\\", 1)[0])
import foot_report  # noqa: E402


def measured_turn(clip):
    world = foot_report.joints_world(clip)
    axis = world[:, 2] - world[:, 1]  # left hip -> right hip
    # facing = axis x up; the yaw of that direction around +Y, unwrapped
    facing = np.stack([axis[:, 2] * 0 + (-axis[:, 2]), axis[:, 0]], axis=1)  # x = -axis.z, z = axis.x  (up = +Y)
    yaw = np.unwrap(np.arctan2(facing[:, 0], facing[:, 1]))
    return float(np.degrees(yaw[-1] - yaw[0])), yaw


def fix(path, target_degrees):
    clip = json.load(open(path))
    measured, _ = measured_turn(clip)
    frames = clip["frames"]
    rot = np.array(clip["rotations"]).reshape(frames, -1, 3)
    progress = np.linspace(0.0, 1.0, frames)
    extra = np.radians(target_degrees - measured) * progress  # yaw to add at each frame
    pelvis = Rotation.from_rotvec(rot[:, 0])
    corrected = Rotation.from_rotvec(np.stack([np.zeros(frames), extra, np.zeros(frames)], axis=1)) * pelvis
    rot[:, 0] = corrected.as_rotvec()
    clip["rotations"] = np.round(rot.reshape(frames, -1), 5).tolist()
    # the translation is not turned (a turn in place has none)
    json.dump(clip, open(path, "w"), separators=(",", ":"))
    return measured, measured_turn(clip)[0]


def crop_to(path, target_degrees):
    """The AI videos rarely turn a clean quarter or half turn (one came back to the start, one spun a full circle): keep the
    window that starts facing front (within 5 deg of frame 0) and turns closest to `target_degrees` (signed, - = left here) in
    0.8-3 s, crop the clip to it, then fix() the angle exactly. For a half turn the sign follows the clip's biggest excursion."""
    clip = json.load(open(path))
    measured, yaw = measured_turn(clip)
    fps = clip["fps"]
    deg = np.degrees(yaw - yaw[0])
    target = target_degrees
    if abs(target_degrees) >= 170:
        target = 180.0 if abs(deg.max()) >= abs(deg.min()) else -180.0
    best = None
    for a in range(len(deg) - int(0.8 * fps)):
        if abs(deg[a]) > 5.0:
            continue
        for b in range(a + int(0.8 * fps), min(a + int(3.0 * fps), len(deg))):
            score = abs((deg[b] - deg[a]) - target) + 0.05 * a
            if best is None or score < best[0]:
                best = (score, a, b)
    if best is None:
        return None
    _, a, b = best
    frames = b - a + 1
    rot = np.array(clip["rotations"]).reshape(clip["frames"], -1, 3)[a:b + 1]
    clip["rotations"] = np.round(rot.reshape(frames, -1), 5).tolist()
    clip["transl"] = clip["transl"][a:b + 1]
    clip["frames"] = frames
    json.dump(clip, open(path, "w"), separators=(",", ":"))
    return fix(path, target) + (a, b)


if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[3] == "crop":
        print(crop_to(sys.argv[1], float(sys.argv[2])))
    elif len(sys.argv) > 2:
        before, after = fix(sys.argv[1], float(sys.argv[2]))
        print("turn %.1f -> %.1f deg" % (before, after))
    else:
        print("turn %.1f deg" % measured_turn(json.load(open(sys.argv[1])))[0])
