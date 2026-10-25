"""Foot contact and sliding of a tools/gvhmr/smplx_motion_to_json.py clip (forward kinematics in numpy).

Usage: python tools/gvhmr/foot_report.py <clip.json> [contacts.json]
A foot counts as planted on a frame when its ankle and toe are low and slow; the report is how far the planted foot still
travels over the frames it stays planted (cm) and the share of planted frames per foot.
"""
import json
import sys

import numpy as np


def rodrigues(v):
    t = np.linalg.norm(v)
    if t < 1e-8:
        return np.eye(3)
    k = v / t
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + np.sin(t) * K + (1 - np.cos(t)) * K @ K


def joints_world(clip):
    rest = np.array(clip["rest"])
    parents = clip["parents"]
    rot = np.array(clip["rotations"]).reshape(clip["frames"], -1, 3)
    transl = np.array(clip["transl"])
    out = np.zeros((clip["frames"], 55, 3))
    for t in range(clip["frames"]):
        rg = [None] * 55
        pos = [None] * 55
        for j in range(55):
            local = rodrigues(rot[t, j]) if j < rot.shape[1] else np.eye(3)
            if parents[j] < 0:
                rg[j] = local
                pos[j] = transl[t] + rest[0]
            else:
                p = parents[j]
                rg[j] = rg[p] @ local
                pos[j] = pos[p] + rg[p] @ (rest[j] - rest[p])
        out[t] = np.array(pos)
    return out


def ground_clip(path):
    """Shifts the clip's translation so the lowest feet (2nd percentile over the clip) stand on y = 0: GVHMR's height drifts
    (a walk came out 12 cm under the floor). Rewrites the json; returns the shift in metres."""
    clip = json.load(open(path))
    world = joints_world(clip)
    low = np.minimum(world[:, [7, 8, 10, 11], 1].min(axis=1), 1e9)
    floor = float(np.percentile(low, 2))
    transl = np.array(clip["transl"])
    transl[:, 1] -= floor
    clip["transl"] = np.round(transl, 5).tolist()
    json.dump(clip, open(path, "w"), separators=(",", ":"))
    return floor


def ground_low(path, sigma=4.0):
    """For low bodies (crawls, a fall): GVHMR's height drifts so the body floats over or sinks under the floor. Per frame, the lowest of
    the ankles, toes, knees, elbows and wrists is put on y = 0 (smoothed over `sigma` frames). Not for jumps: they must leave the floor."""
    from scipy.ndimage import gaussian_filter1d
    clip = json.load(open(path))
    world = joints_world(clip)
    low = world[:, [7, 8, 10, 11, 4, 5, 18, 19, 20, 21], 1].min(axis=1)
    shift = gaussian_filter1d(low, sigma, mode="nearest")
    transl = np.array(clip["transl"])
    transl[:, 1] -= shift
    clip["transl"] = np.round(transl, 5).tolist()
    json.dump(clip, open(path, "w"), separators=(",", ":"))
    return float(np.abs(shift).mean())


def contacts(world, fps):
    """planted[t, side]: low and slow ankle and toe. side 0 = left, 1 = right."""
    ankle = world[:, [7, 8]]
    toe = world[:, [10, 11]]
    low = np.minimum(ankle[:, :, 1], toe[:, :, 1])
    floor = np.percentile(low, 2)
    speed = np.zeros_like(low)
    speed[1:] = np.linalg.norm(np.diff(toe[:, :, [0, 2]], axis=0), axis=2) * fps
    speed[0] = speed[1]
    # the speed limit follows how fast the feet swing in this clip (a run's stance foot is faster than a idle's)
    limit = np.clip(0.2 * np.percentile(speed, 95), 0.2, 0.6)
    return (low < floor + 0.05) & (speed < limit), floor


def report(world, fps):
    planted, floor = contacts(world, fps)
    toe = world[:, [10, 11]]
    print("floor (lowest foot) %.3f m" % floor)
    for side, name in enumerate(["left", "right"]):
        frames = planted[:, side]
        slide = 0.0
        run = 0.0
        runs = 0
        t = 0
        while t < len(frames):
            if frames[t]:
                start = t
                while t + 1 < len(frames) and frames[t + 1]:
                    t += 1
                d = np.linalg.norm(toe[t, side, [0, 2]] - toe[start, side, [0, 2]])
                slide += d
                runs += 1
            t += 1
        print("%s foot: planted %d%% of frames in %d stretches, drifts %.1f cm per stretch while planted" % (
            name, 100 * frames.mean(), runs, 100 * slide / max(runs, 1)))
    return planted


if __name__ == "__main__":
    clip = json.load(open(sys.argv[1]))
    planted = report(joints_world(clip), clip["fps"])
    if len(sys.argv) > 2:  # a third argument writes the contacts: [[left, right] per frame] for the Godot checks
        json.dump({"fps": clip["fps"], "planted": planted.astype(int).tolist()}, open(sys.argv[2], "w"))
