#!/usr/bin/env python3
"""Compact queries for user://procedural_walk_course.jsonl.

Usage: python3 scripts/procedural_walk_trace.py TRACE summary
       python3 scripts/procedural_walk_trace.py TRACE worst --metric joint --n 8
       python3 scripts/procedural_walk_trace.py TRACE window --frame 245 --radius 4
       python3 scripts/procedural_walk_trace.py TRACE events

The lab writes a bounded capture whenever Spawn up + down stairs is pressed.
The raw file stays on disk; these queries print only a few diagnostic lines.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def load(path: Path) -> list[dict]:
    try:
        with path.open(encoding="utf-8") as handle:
            frames = [json.loads(line) for line in handle if line.strip()]
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"cannot read trace {path}: {error}") from error
    if not frames:
        raise SystemExit(f"empty trace: {path}")
    return frames


def distance(left: list[float] | None, right: list[float] | None) -> float:
    if left is None or right is None:
        return 0.0
    return math.dist(left, right)


def values(frames: list[dict], metric: str) -> list[tuple[float, dict, str]]:
    ranked: list[tuple[float, dict, str]] = []
    previous: dict | None = None
    for frame in frames:
        feet = frame.get("feet", {})
        if metric == "joint":
            ranked.append((float(frame.get("worst_joint_deg", 0)), frame,
                           frame.get("worst_joint", "")))
        elif metric == "root_y":
            delta = frame.get("root_delta") or [0, 0, 0]
            ranked.append((abs(float(delta[1])), frame, "root"))
        elif metric == "target_error":
            for side, foot in feet.items():
                ranked.append((float(foot.get("target_error", 0)), frame, side))
        elif previous is not None:
            for side, foot in feet.items():
                earlier = previous.get("feet", {}).get(side, {})
                key = {"ankle": "ankle", "toe": "toe", "target": "target"}[metric]
                ranked.append((distance(foot.get(key), earlier.get(key)), frame, side))
        previous = frame
    return sorted(ranked, key=lambda item: item[0], reverse=True)


def describe(frame: dict, detail: str = "") -> str:
    root = frame.get("root", [0, 0, 0])
    event = ",".join(frame.get("events", [])) or "-"
    return (f"f{frame['frame']:4d} tick={frame.get('physics_frame')} "
            f"{frame.get('section', '?'):8s} phase={frame.get('phase', 0):.3f} "
            f"root_y={root[1]:.3f} z={root[2]:.3f} "
            f"hips={frame.get('reference_hips_y', 0):.3f}+"
            f"{frame.get('floor_clearance', 0):.3f}-"
            f"{frame.get('pelvis_drop', 0):.3f} "
            f"joint={frame.get('worst_joint', '-')}:"
            f"{frame.get('worst_joint_deg', 0):.1f}deg "
            f"event={event} {detail}")


def foot_detail(frame: dict, only_side: str | None = None) -> str:
    pieces = []
    for side in ("left", "right"):
        if only_side is not None and side != only_side:
            continue
        foot = frame.get("feet", {}).get(side, {})
        ankle = foot.get("ankle") or [0, 0, 0]
        hip = foot.get("hip") or [0, 0, 0]
        knee = foot.get("knee") or [0, 0, 0]
        source_knee = foot.get("source_knee") or [0, 0, 0]
        target = foot.get("target")
        target_text = "-" if target is None else f"{target[1]:.3f}/{target[2]:.3f}"
        pieces.append(
            f"{side[0].upper()}[c={int(foot.get('contact', False))} "
            f"w={foot.get('contact_weight', 0):.2f} "
            f"hip={hip[1]:.3f}/{hip[2]:.3f} "
            f"knee={knee[1]:.3f}/{knee[2]:.3f} "
            f"src={source_knee[1]:.3f}/{source_knee[2]:.3f} "
            f"ankle={ankle[1]:.3f}/{ankle[2]:.3f} "
            f"target={target_text} err={foot.get('target_error', 0):.3f} "
            f"flex={foot.get('knee_flex_deg', 0):.1f} "
            f"shoe={foot.get('shoe_corrections', 0)}/"
            f"{foot.get('shoe_required_y', 0):.3f}]"
        )
    return " ".join(pieces)


def summary(frames: list[dict]) -> None:
    ticks = [int(frame.get("physics_frame", -1)) for frame in frames]
    gaps = sum(max(0, right - left - 1) for left, right in zip(ticks, ticks[1:]))
    sections = ", ".join(dict.fromkeys(frame.get("section", "?") for frame in frames))
    print(f"frames={len(frames)} tick_gaps={gaps} mode={frames[0].get('mode')} "
          f"sections={sections}")
    for metric in ("joint", "root_y", "ankle", "toe", "target", "target_error"):
        top = values(frames, metric)[:3]
        print(f"{metric:12s} " + " | ".join(
            f"f{frame['frame']} {side}={value:.3f}{'deg' if metric == 'joint' else 'm'}"
            for value, frame, side in top))
    event_count = sum(bool(frame.get("events")) for frame in frames)
    print(f"event_frames={event_count}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    queries = parser.add_subparsers(dest="query", required=True)
    queries.add_parser("summary")
    worst = queries.add_parser("worst")
    worst.add_argument("--metric", choices=("joint", "root_y", "ankle", "toe",
                                            "target", "target_error"), default="joint")
    worst.add_argument("--n", type=int, default=8)
    window = queries.add_parser("window")
    window.add_argument("--frame", type=int, required=True)
    window.add_argument("--radius", type=int, default=4)
    events = queries.add_parser("events")
    events.add_argument("--n", type=int, default=12)
    args = parser.parse_args()
    frames = load(args.trace)
    if args.query == "summary":
        summary(frames)
    elif args.query == "worst":
        for value, frame, side in values(frames, args.metric)[:max(0, args.n)]:
            foot_side = ("left" if side.lower().startswith("left") else
                         "right" if side.lower().startswith("right") else None)
            print(describe(frame, f"{args.metric}={value:.3f} side={side} "
                            + foot_detail(frame, foot_side)))
    elif args.query == "window":
        for frame in frames:
            if abs(int(frame["frame"]) - args.frame) <= max(0, args.radius):
                print(describe(frame, foot_detail(frame)))
    elif args.query == "events":
        matches = [frame for frame in frames if frame.get("events")]
        for frame in matches[-max(0, args.n):]:
            print(describe(frame, foot_detail(frame)))


if __name__ == "__main__":
    main()
