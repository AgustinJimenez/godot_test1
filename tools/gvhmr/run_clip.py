"""One command per clip: video -> native Windows GVHMR (static camera) -> motion json -> foot report -> retarget -> sheet.

Usage: python tools/gvhmr/run_clip.py <video.mp4> [--name Name] [--targets brute,motusman] [--no-sheet]
Outputs (under assets/animation/gvhmr_pack/): json/<Name>.json, json/<Name>_contacts.json, out/<Name>_<target>.res,
sheets/<Name>_<target>.png (four frames of the retargeted clip), metrics/<Name>.json. Prints a one-line verdict hint.
Needs: E:/repo/gvhmr_win/.venv (gvhmr.exe), the body models in E:/repo/gvhmr/inputs/checkpoints, Godot 4.7.2, anaconda python.
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
GVHMR_PY = r"E:\repo\gvhmr_win\.venv\Scripts\python.exe"
GVHMR_EXE = r"E:\repo\gvhmr_win\.venv\Scripts\gvhmr.exe"
EXTRACT = r"E:\repo\gvhmr\extract_motion.py"
SMPLX = r"E:\repo\gvhmr\inputs\checkpoints\body_models\smplx\SMPLX_NEUTRAL.npz"
GODOT = r"E:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
WORK = r"E:\repo\gvhmr_work\gvhmr_out"
PACK = os.path.join(PROJECT, "assets", "animation", "gvhmr_pack")
TARGETS = {
    "brute": ("res://assets/models/mixamo_characters/Brute.character.json", "res://assets/models/mixamo_characters/Brute.fbx"),
    "motusman": ("res://assets/models/pistol_starter/MotusMan/MotusMan_v55.character.json",
                 "res://assets/models/pistol_starter/MotusMan/MotusMan_v55.fbx"),
}

parser = argparse.ArgumentParser()
parser.add_argument("video")
parser.add_argument("--name")
parser.add_argument("--targets", default="brute,motusman")
parser.add_argument("--no-sheet", action="store_true")
parser.add_argument("--speed", default="auto", help="target root speed m/s, auto (by clip name), or 0 to keep GVHMR's")
parser.add_argument("--smooth", type=float, default=1.0, help="gaussian sigma in frames over the rotations (0 = off)")
parser.add_argument("--no-loop", action="store_true", help="keep looping clips as they are (no loop window / in place)")
parser.add_argument("--inplace", action="store_true", help="remove the horizontal travel (idles, turns, jumps in place)")
parser.add_argument("--hands", default="relaxed", help="hand preset written into the finger tracks (relaxed|fist|none)")
args = parser.parse_args()
name = args.name or os.path.splitext(os.path.basename(args.video))[0].replace("anim_", "")
for sub in ("json", "out", "sheets", "metrics"):
    os.makedirs(os.path.join(PACK, sub), exist_ok=True)

env = dict(os.environ, GVHMR_CHECKPOINTS="E:/repo/gvhmr/inputs/checkpoints",
           GVHMR_BODY_MODELS="E:/repo/gvhmr/inputs/checkpoints/body_models")
stem = os.path.splitext(os.path.basename(args.video))[0]
result_dir = os.path.join(WORK, stem)
if not os.path.exists(os.path.join(result_dir, "hmr4d_results.pt")):
    code = subprocess.run([GVHMR_EXE, "demo", args.video, "-s", "-o", WORK], env=env).returncode
    if code != 0 or not os.path.exists(os.path.join(result_dir, "hmr4d_results.pt")):
        print("VERDICT %s: failed (GVHMR produced no motion, exit %d)" % (name, code))
        sys.exit(1)
motion = os.path.join(result_dir, "motion.npz")
subprocess.run([GVHMR_PY, EXTRACT, os.path.join(result_dir, "hmr4d_results.pt"), motion], check=True,
               stdout=subprocess.DEVNULL)
clip_json = os.path.join(PACK, "json", name + ".json")
subprocess.run([sys.executable, os.path.join(HERE, "smplx_motion_to_json.py"), SMPLX, motion, clip_json, "30"],
               check=True, stdout=subprocess.DEVNULL)
sys.path.insert(0, HERE)
import foot_report  # noqa: E402

if args.smooth > 0:
    import smooth_clip
    smooth_clip.smooth(clip_json, args.smooth)
LOOPING = ("Idle", "Walk", "Run", "Crouch_Idle", "Crouch_Walk", "Crawl")
loop_note = None
if name.startswith(LOOPING) and not args.no_loop:  # a seamless in-place cycle (the speed stays in catalog.json for the controller)
    import loop_fix
    loop_note = loop_fix.make_loop(clip_json, 2.5 if name.startswith(("Idle", "Crouch_Idle")) else (1.5 if name.startswith(("Crouch_Walk", "Crawl")) else 1.0), 3.9)
    args.inplace = True
turn_note = None
if name.startswith("Turn_"):  # the video rarely turns a clean angle: crop to the best window and rescale to the nominal one
    import turn_fix
    nominal = {"Turn_Left": -90.0, "Turn_Right": 90.0, "Turn_Around": 180.0}.get(name)
    if nominal:
        turn_note = turn_fix.crop_to(clip_json, nominal)
floor_shift = foot_report.ground_clip(clip_json)
low_note = None
if name.startswith(("Crawl", "Hurt_Fall", "GetUp")):  # low bodies: ground every frame by the lowest limb (not for jumps)
    low_note = round(foot_report.ground_low(clip_json), 3)
  # (GVHMR's height drifts: put the lowest feet on y = 0)
contacts = os.path.join(PACK, "json", name + "_contacts.json")
foot = subprocess.run([sys.executable, os.path.join(HERE, "foot_report.py"), clip_json, contacts],
                      capture_output=True, text=True).stdout.strip().splitlines()

clip = json.load(open(clip_json))
world = foot_report.joints_world(clip)
fps = clip["fps"]
root = world[:, 0]
travel = float(np.linalg.norm(root[-1, [0, 2]] - root[0, [0, 2]]))
accel = np.linalg.norm(np.diff(world[:, [20, 21, 7, 8]], n=2, axis=0), axis=2) * fps * fps  # wrists and ankles, m/s^2
jitter = float(np.median(accel))
spikes = float(np.mean(accel > 60.0))
height = world[:, 15, 1] - np.percentile(np.minimum(world[:, 10, 1], world[:, 11, 1]), 2)  # head above the lowest toe
metrics = {"frames": clip["frames"], "seconds": round(clip["frames"] / fps, 2), "root_travel_m": round(travel, 2),
           "head_height_min_m": round(float(height.min()), 2), "head_height_max_m": round(float(height.max()), 2),
           "limb_accel_median": round(jitter, 1), "limb_accel_spikes": round(spikes, 3), "floor_shift_m": round(floor_shift, 3), "turn_crop": str(turn_note), "loop": str(loop_note), "ground_low_mean_shift_m": low_note, "feet": foot}
json.dump(metrics, open(os.path.join(PACK, "metrics", name + ".json"), "w"), indent=1)

mapping = {"relaxed": "relaxed", "fist": "fist", "none": ""}
SPEEDS = [("Walk_Slow", 0.9), ("Walk_Sneak", 0.9), ("Walk_Heavy", 1.0), ("Walk_Limp", 1.1), ("Run_Tired", 3.0), ("Crouch_Walk", 0.9), ("Crawl", 0.5), ("Walk", 1.4), ("Run_Fast", 5.0), ("Run", 3.6), ("Sprint", 5.0)]
speed = 0.0
if args.speed == "auto":
    speed = next((v for prefix, v in SPEEDS if name.startswith(prefix)), 0.0)
else:
    speed = float(args.speed)
for target in args.targets.split(","):
    manifest, model = TARGETS[target]
    out_res = "res://assets/animation/gvhmr_pack/out/%s_%s.res" % (name, target)
    subprocess.run([GODOT, "--headless", "--path", PROJECT, "res://tests/manual/animation/gvhmr_retarget.tscn", "--",
                    "source_json=res://assets/animation/gvhmr_pack/json/%s.json" % name, "target_manifest=" + manifest,
                    "output=" + out_res, "contacts=res://assets/animation/gvhmr_pack/json/%s_contacts.json" % name,
                    "hands=" + mapping[args.hands], "inplace=" + ("true" if args.inplace else "false"), "speed=%.2f" % (0.0 if args.inplace else speed)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if args.no_sheet:
        continue
    from PIL import Image
    shots = []
    length = clip["frames"] / fps
    for k, frac in enumerate((0.1, 0.35, 0.6, 0.85)):
        shot = os.path.join(WORK, "%s_%s_%d.png" % (name, target, k))
        subprocess.run([GODOT, "--path", PROJECT, "res://tests/manual/animation/gvhmr_preview.tscn", "--",
                        "target_model=" + model, "clip=" + out_res, "at=%.2f" % (length * frac), "shot=" + shot],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if os.path.exists(shot):
            shots.append(Image.open(shot).crop((560, 200, 1360, 760)).resize((400, 280)))
    if shots:
        sheet = Image.new("RGB", (400 * len(shots), 280))
        for k, image in enumerate(shots):
            sheet.paste(image, (400 * k, 0))
        sheet.save(os.path.join(PACK, "sheets", "%s_%s.png" % (name, target)))

print("METRICS %s: %s" % (name, json.dumps({k: v for k, v in metrics.items() if k != "feet"})))
