"""
batch_generate.py — Generate a video for every entry in a manifest JSON,
recording the exact prompt/params/output used for each. Resumable: entries
already marked "done" are skipped, so a crashed/interrupted batch can just
be re-run.

Run: python batch_generate.py <manifest.json>

Manifest format (list of entries; see manifest_idle_pilot.json for a
worked example):
[
  {
    "name": "Idle",
    "category": "Idle",
    "prompt": "...",
    "frames": 73,
    "steps": 8,
    "resolution": "832x448",
    "seed": -1,
    "status": "pending"        # set to "done" or "failed" by this script
  },
  ...
]

Each entry gets its own settings JSON (written to the OS temp dir, never into
the Wan2GP repo -- see generate_video.py's docstring for why) built from
settings_template.json, run through `wgp.py --process`, and its output
written to generated/videos/anim_<name>.mp4 in this project (override with
--output-dir). Progress (status, output_file, generation_time_s, error) is
written back into the manifest after every single entry, not just at the
end, so interrupting the batch never loses already-completed work. An entry
can optionally set "image" to a start-image path for consistent character
appearance across the batch.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

REPO = os.environ.get("WAN2GP_REPO", r"E:\repo\wan2.1gp")
VENV_PYTHON = os.environ.get("WAN2GP_VENV_PYTHON", os.path.join(REPO, ".venv", "Scripts", "python.exe"))
TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "settings_ltx25.json")
DEFAULT_OUTPUT_DIR = "E:/repo/gvhmr_work/videos"

parser = argparse.ArgumentParser()
parser.add_argument("manifest", help="Path to manifest JSON")
parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR,
                     help="Output directory; defaults to Pipeline/wan2gp/generated/videos")
args = parser.parse_args()
manifest_path = args.manifest
os.makedirs(args.output_dir, exist_ok=True)

with open(TEMPLATE) as f:
    template = json.load(f)

with open(manifest_path, encoding="utf-8") as f:
    manifest = json.load(f)

total = len(manifest)
done_count = sum(1 for e in manifest if e.get("status") == "done")
print(f"[batch_generate] {done_count}/{total} already done, {total - done_count} to run")

for i, entry in enumerate(manifest):
    if entry.get("status") == "done":
        continue

    name = entry["name"]
    output_filename = f"anim_{name}"
    settings = dict(template)
    settings["prompt"] = entry["prompt"]
    settings["output_filename"] = output_filename
    settings["video_length"] = entry.get("frames", template["video_length"])
    settings["resolution"] = entry.get("resolution", template["resolution"])
    settings["num_inference_steps"] = entry.get("steps", template["num_inference_steps"])
    settings["seed"] = entry.get("seed", -1)
    if entry.get("image"):
        settings["image_prompt_type"] = "S"
        settings["image_start"] = os.path.abspath(entry["image"])

    settings_path = os.path.join(tempfile.gettempdir(), f"wan2gp_batch_settings_{output_filename}.json")
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)

    print(f"\n[batch_generate] ({i+1}/{total}) {name}: {entry['prompt'][:70]}...")
    start = time.time()
    result = subprocess.run([VENV_PYTHON, "wgp.py", "--process", settings_path, "--output-dir", args.output_dir], cwd=REPO)
    elapsed = time.time() - start

    try:
        os.remove(settings_path)
    except OSError:
        pass

    out_path = os.path.join(args.output_dir, f"{output_filename}.mp4")
    if result.returncode == 0 and os.path.isfile(out_path):
        entry["status"] = "done"
        entry["output_file"] = out_path
        entry["generation_time_s"] = round(elapsed, 1)
        entry.pop("error", None)
        print(f"[batch_generate] OK ({elapsed:.1f}s): {out_path}")
    else:
        entry["status"] = "failed"
        entry["error"] = f"returncode={result.returncode}, expected output missing: {out_path}"
        print(f"[batch_generate] FAILED: {entry['error']}")

    # Write progress back after every entry, not just at the end.
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

done_count = sum(1 for e in manifest if e.get("status") == "done")
failed_count = sum(1 for e in manifest if e.get("status") == "failed")
print(f"\n[batch_generate] Finished: {done_count}/{total} done, {failed_count} failed")
