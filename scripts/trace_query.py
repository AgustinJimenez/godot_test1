#!/usr/bin/env python3
"""Token-efficient query CLI for Foot IK JSONL traces.

Why this exists: the raw traces are 10-20 MB and pasting even one frame per line
into a chat costs thousands of tokens. This script answers the recurring
questions with a handful of compact lines so an agent never ingests raw frames.

Pure Python standard library on purpose - it must run wherever `python3` runs
(CI, pre-commit) with no pip install. Traces are small enough that line-by-line
JSON parsing is fast; DuckDB/polars would only be worthwhile above ~1 GB (see
AGENT_TASKS/archive/026_token_efficiency_workflow.md).

Usage:
  python3 scripts/trace_query.py --trace PATH [--last-n N] QUERY [args]

Queries:
  summary                 per-animation and per-foot high-level stats
  worst --metric M --n N  top-N frames for a per-foot metric (default: sole)
  clips --n N             penetration episodes grouped into runs (sole/gap proxies)
  toe-riser [--n N]       toe-tip enters the authored preview staircase boxes
  swing --from F --to F   compact per-frame swing/support state for a window
  field --path a.b.c      extract an arbitrary nested field over a window
  keys                    emit the trace schema (top-level + feet keys)

Metrics for `worst`: sole (sole_clearance), gap, toe (toe_tip_y - target.y),
                     ankle (foot_pos.y - target.y).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import deque

_NUM = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")


def _vec3(value):
    try:
        if isinstance(value, (list, tuple)):
            numbers = tuple(float(x) for x in value[:3])
        elif isinstance(value, str):
            numbers = tuple(float(x) for x in _NUM.findall(value)[:3])
        else:
            return None
    except (TypeError, ValueError):
        return None
    return numbers if len(numbers) == 3 else None


def load(path, last_n=None):
    frames = deque(maxlen=last_n) if last_n is not None else []
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    frame = json.loads(line)
                except json.JSONDecodeError as error:
                    raise SystemExit(
                        f"{path}:{line_number}: invalid JSON: {error.msg}"
                    ) from error
                if not isinstance(frame, dict):
                    raise SystemExit(f"{path}:{line_number}: frame must be a JSON object")
                if not isinstance(frame.get("frame"), (int, float)):
                    raise SystemExit(f"{path}:{line_number}: missing numeric frame field")
                frames.append(frame)
    except OSError as error:
        detail = error.strerror or str(error)
        raise SystemExit(f"cannot read trace {path}: {detail}") from error
    return list(frames)


def _f(frame, side, key, default=None):
    return frame.get("feet", {}).get(side, {}).get(key, default)


def _metric(frame, side, metric):
    foot = frame.get("feet", {}).get(side, {})
    if metric == "sole":
        return foot.get("sole_clearance")
    if metric == "gap":
        return foot.get("gap")
    target = _vec3(foot.get("smoothed_target"))
    if target is None:
        return None
    if metric == "toe":
        tip = foot.get("toe_tip_y")
        return None if tip is None else tip - target[1]
    if metric == "ankle":
        pos = _vec3(foot.get("foot_pos"))
        return None if pos is None else pos[1] - target[1]
    raise SystemExit(f"unknown metric: {metric}")


def _runs(frames, side, metric, threshold):
    """Group consecutive frames whose metric is below threshold into episodes."""
    episodes = []
    current = None
    for frame in frames:
        value = _metric(frame, side, metric)
        deep = value is not None and value < threshold
        if deep:
            if current is None:
                current = {"start": frame["frame"], "end": frame["frame"],
                           "worst": value, "worst_frame": frame["frame"]}
            elif frame["frame"] == current["end"] + 1:
                current["end"] = frame["frame"]
                if value < current["worst"]:
                    current["worst"] = value
                    current["worst_frame"] = frame["frame"]
            else:
                episodes.append(current)
                current = {"start": frame["frame"], "end": frame["frame"],
                           "worst": value, "worst_frame": frame["frame"]}
        elif current is not None:
            episodes.append(current)
            current = None
    if current is not None:
        episodes.append(current)
    return episodes


# --- preview-scene staircase geometry (foot_ik_preview.tscn _build_stairs) -----
# Origins step by PLATFORM_SPACING=2.5; tread depth 0.6, 6 steps + top landing.
_PREVIEW_STAIRS = [(10.0, 0.10), (12.5, 0.20), (15.0, 0.35), (17.5, 0.50), (20.0, 0.65)]
_FLOOR_TOP = 0.0
_TREAD_DEPTH = 0.6
_STEP_COUNT = 6
# The authored top landing ends here (FootIKStairSurfaces.build_top_landing:
# ramp_end_z + TRANSITION_LENGTH + LANDING_LENGTH = 5*0.6 + 0.1 + 1.0). Past it there is
# no foot-contact geometry, so a dangling foot there is open air, not a tread penetration.
_LANDING_END_Z = 4.1


def _preview_tread_top(x, z):
    for origin_x, rise in _PREVIEW_STAIRS:
        if origin_x - 1.5 <= x <= origin_x + 1.5:
            if z < 0.0:
                return _FLOOR_TOP
            if z > _STEP_COUNT * _TREAD_DEPTH:
                return rise * _STEP_COUNT if z <= _LANDING_END_Z else None
            return rise * (int(z // _TREAD_DEPTH) + 1)
    return _FLOOR_TOP


def _cmd_summary(frames):
    by_anim = {}
    for frame in frames:
        by_anim.setdefault(frame.get("animation"), []).append(frame)
    print(f"frames={len(frames)} span={frames[0]['frame']}..{frames[-1]['frame']}")
    for anim, group in sorted(by_anim.items(), key=lambda item: -len(item[1])):
        print(f"  anim={anim} frames={len(group)}")
    for side in ("left", "right"):
        values = [_metric(f, side, "sole") for f in frames]
        values = [v for v in values if v is not None]
        if not values:
            print(f"  {side}: sole=no-data")
            continue
        below = sum(1 for v in values if v < -0.005)
        print(f"  {side}: sole_min={min(values):.4f} mean={sum(values)/len(values):.4f} "
              f"below_5mm={below}")


def _cmd_worst(frames, metric, count):
    rows = []
    for frame in frames:
        for side in ("left", "right"):
            value = _metric(frame, side, metric)
            if value is not None:
                rows.append((value, frame["frame"], side, frame.get("animation")))
    rows.sort()
    print(f"metric={metric} shown={min(count, len(rows))}/{len(rows)}")
    for value, number, side, anim in rows[:count]:
        print(f"  f{number} {side} {value:+.4f} {anim}")


def _cmd_clips(frames, count):
    for side in ("left", "right"):
        for metric, label in (("sole", "sole"), ("gap", "gap")):
            episodes = _runs(frames, side, metric, -0.005)
            episodes.sort(key=lambda e: e["worst"])
            print(f"{side} {label}: episodes={len(episodes)}")
            for episode in episodes[:count]:
                print(f"  f{episode['start']}..{episode['end']} worst={episode['worst']:+.4f} "
                      f"at f{episode['worst_frame']}")


def _cmd_toe_riser(frames, count):
    episodes = {}
    for frame in frames:
        for side in ("left", "right"):
            foot = frame.get("feet", {}).get(side, {})
            joints = foot.get("joints", {})
            toe = _vec3(joints.get("toe", {}).get("position"))
            ankle = _vec3(foot.get("foot_pos"))
            if toe is None or ankle is None:
                continue
            dx, dy, dz = (toe[0] - ankle[0], toe[1] - ankle[1], toe[2] - ankle[2])
            length = (dx * dx + dy * dy + dz * dz) ** 0.5 or 1.0
            tip = (toe[0] + dx / length * 0.035, toe[1] + dy / length * 0.035,
                   toe[2] + dz / length * 0.035)
            top = _preview_tread_top(tip[0], tip[2])
            if top is None:
                continue
            depth = top - tip[1]
            if depth <= 0.005:
                continue
            runs = episodes.setdefault(side, [])
            if runs and frame["frame"] == runs[-1]["end"] + 1:
                runs[-1]["end"] = frame["frame"]
                if depth > runs[-1]["worst"]:
                    runs[-1]["worst"] = depth
                    runs[-1]["worst_frame"] = frame["frame"]
            else:
                runs.append({"start": frame["frame"], "end": frame["frame"],
                             "worst": depth, "worst_frame": frame["frame"]})
    for side in ("left", "right"):
        runs = episodes.get(side, [])
        runs.sort(key=lambda r: -r["worst"])
        print(f"{side} toe-in-tread: episodes={len(runs)}")
        for run in runs[:count]:
            print(f"  f{run['start']}..{run['end']} worst={run['worst']:.4f} "
                  f"at f{run['worst_frame']}")


def _cmd_swing(frames, first, last, side):
    sides = (side,) if side else ("left", "right")
    matched = 0
    for frame in frames:
        if not (first <= frame["frame"] <= last):
            continue
        matched += 1
        stair = frame.get("stair_ik", {})
        lifts = stair.get("step_lifts", {})
        line = (f"f{frame['frame']} sup={stair.get('support_side', '')!r} "
                f"pred={sorted(stair.get('predicted_targets', {}).keys())} "
                f"lift={{{','.join(f'{s[0]}:{lifts.get(s, 0.0):.3f}' for s in ('left', 'right'))}}}")
        print(line)
        for one in sides:
            foot = frame.get("feet", {}).get(one, {})
            ankle = _vec3(foot.get("foot_pos")) or (0, 0, 0)
            toe = _vec3(foot.get("joints", {}).get("toe", {}).get("position")) or (0, 0, 0)
            target = _vec3(foot.get("solve_target")) or (0, 0, 0)
            print(f"  {one} w={foot.get('ground_weight', 0.0):.2f} "
                  f"ank=({ankle[1]:.3f},{ankle[2]:.2f}) toe=({toe[1]:.3f},{toe[2]:.2f}) "
                  f"solve_t={target[1]:.3f} own={foot.get('target_owner')}")
    if matched == 0:
        print(f"frames=0 window={first}..{last}")


def _resolve(frame, path):
    node = frame
    for key in path.split("."):
        if isinstance(node, dict):
            node = node.get(key)
        else:
            return None
    return node


def _cmd_field(frames, path, first, last):
    matched = 0
    for frame in frames:
        if not (first <= frame["frame"] <= last):
            continue
        matched += 1
        print(f"f{frame['frame']} {path}={_resolve(frame, path)}")
    if matched == 0:
        print(f"frames=0 window={first}..{last}")


def _cmd_keys(frames):
    frame = frames[-1]
    print("top:", " ".join(sorted(frame.keys())))
    foot = frame.get("feet", {}).get("left", {})
    print("feet:", " ".join(sorted(foot.keys())))
    print("joints:", " ".join(sorted(foot.get("joints", {}).keys())))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--trace", required=True)
    parser.add_argument("--last-n", type=int, default=0, help="only the last N frames (0=all)")
    parser.add_argument("query", choices=["summary", "worst", "clips", "toe-riser",
                                          "swing", "field", "keys"])
    parser.add_argument("--metric", choices=["sole", "gap", "toe", "ankle"], default="sole")
    parser.add_argument("--n", type=int, default=10)
    parser.add_argument("--from", dest="first", type=int, default=0)
    parser.add_argument("--to", dest="last", type=int, default=1 << 30)
    parser.add_argument("--side", choices=["left", "right"])
    parser.add_argument("--path", default="")
    args = parser.parse_args()

    if args.trace.startswith("user://"):
        raise SystemExit("pass --trace with a real path (resolve user:// first)")
    if args.last_n < 0:
        raise SystemExit("--last-n must be 0 or greater")
    if args.n < 1:
        raise SystemExit("--n must be 1 or greater")
    if args.first > args.last:
        raise SystemExit("--from must be less than or equal to --to")
    if args.query == "field" and not args.path:
        raise SystemExit("field requires --path")
    frames = load(args.trace, args.last_n or None)
    if not frames:
        raise SystemExit("empty trace")
    if args.query == "summary":
        _cmd_summary(frames)
    elif args.query == "worst":
        _cmd_worst(frames, args.metric, args.n)
    elif args.query == "clips":
        _cmd_clips(frames, args.n)
    elif args.query == "toe-riser":
        _cmd_toe_riser(frames, args.n)
    elif args.query == "swing":
        _cmd_swing(frames, args.first, args.last, args.side)
    elif args.query == "field":
        _cmd_field(frames, args.path, args.first, args.last)
    elif args.query == "keys":
        _cmd_keys(frames)


if __name__ == "__main__":
    sys.exit(main())
