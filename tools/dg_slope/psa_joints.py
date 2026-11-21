"""DG PSA walk clip -> per-frame joint positions (metres), for the project's direction-based retarget (AGENT_TASKS/095).

Game-derived output: assets/models/dg_slope/ stays uncommitted. Usage: python psa_joints.py <skeleton.json> <clip.psa> <out.json>
The PSA keys are parent-local pos (cm) + quat (UE is left-handed: xyz negated). Forward kinematics from the Hips gives a right-handed,
Y-up space with x = the character's left and z = its forward. Joint positions only: no rest pose is needed downstream.
"""
import json
import struct
import sys

import numpy as np

FPS = 31.0  # the baked clips' lengths are (frames - 1) / 31
JOINTS = ["Hips", "spine", "spine2", "spine4", "Neck", "Head"]
for side in ("Left", "Right"):
    JOINTS += [side + n for n in ("Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "Heel", "ToeBase")]


def quat_matrix(q):
    x, y, z, w = -q[0], -q[1], -q[2], q[3]
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def main(skeleton_path, psa_path, out_path):
    parents = {b["name"]: b["parent"] for b in json.load(open(skeleton_path))["bones"]}
    data = open(psa_path, "rb").read()
    names_at = data.find(b"BONENAMES")
    record, count = struct.unpack_from("<ii", data, names_at + 24)
    names = [data[names_at + 32 + i * record:names_at + 32 + i * record + 64].split(b"\0")[0].decode("latin1") for i in range(count)]
    keys_at = data.find(b"ANIMKEYS")
    key_size, key_count = struct.unpack_from("<ii", data, keys_at + 24)
    frames = key_count // count
    index = {n: i for i, n in enumerate(names)}

    def key(bone, frame):
        offset = keys_at + 32 + (frame * count + index[bone]) * key_size
        return struct.unpack_from("<3f", data, offset), struct.unpack_from("<4f", data, offset + 12)

    out = {j: [] for j in JOINTS}
    for frame in range(frames):
        cache = {}

        def world(bone):
            if bone in cache:
                return cache[bone]
            position, rotation = key(bone, frame)
            local = np.eye(4)
            local[:3, :3] = quat_matrix(rotation)
            local[:3, 3] = np.array(position) * 0.01
            parent = parents[bone]
            result = local if bone == "Hips" or parent is None or parent == "Align" else world(parent) @ local
            cache[bone] = result
            return result

        for joint in JOINTS:
            out[joint].append([round(float(v), 5) for v in world(joint)[:3, 3]])
    json.dump({"fps": FPS, "frames": frames, "joints": out}, open(out_path, "w"))
    print(out_path, frames, "frames")


main(*sys.argv[1:4])
