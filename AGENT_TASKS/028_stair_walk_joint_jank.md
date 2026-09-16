# 028 - Stair walk joint jank (flat vs stair smoothness)

Status: diagnosed, NOT fixed. Root cause localized to a constraint-regime flip on the planted
leg; one proposed fix attempted and reverted (null result). Needs a live-verified fix.

## Symptom

Walking up/down the 0.35 m stairs looks janky: the legs pop. Flat walking on the same character,
same clip (`moves/unarmed_walk`), same 3.2 m/s looks smooth.

## Measurement (repeatable)

`scripts/trace_query.py angular --compare B.jsonl` (added this session) reports per-joint
per-frame rotation change in deg/frame. Capture both sides with the marker recipes:

```sh
U="$HOME/Library/Application Support/Godot/app_userdata/SurvivalHorrorFps"
touch "$U/foot_ik_flat_forward_marker"
godot --headless --fixed-fps 60 --path . res://tests/manual/foot_ik/foot_ik_preview.tscn \
  --quit-after 700 >/tmp/flat_walk.log 2>&1 || true
rm "$U/foot_ik_flat_forward_marker"; cp "$U/foot_ik_controlled.jsonl" /tmp/flat_walk.jsonl
touch "$U/foot_ik_stair_walk_marker"
godot --headless --fixed-fps 60 --path . res://tests/manual/foot_ik/foot_ik_preview.tscn \
  --quit-after 2000 >/tmp/stair_walk.log 2>&1 || true
rm "$U/foot_ik_stair_walk_marker"; cp "$U/foot_ik_controlled.jsonl" /tmp/stair_walk.jsonl
python3 scripts/trace_query.py --trace /tmp/flat_walk.jsonl --compare /tmp/stair_walk.jsonl angular
```

Result (deg/frame, planted + swing legs):

| joint | flat p95 / max | stair p95 / max | stair jerk p95 |
|---|---|---|---|
| hip | 8 / 9 | 18-20 / 107 | up to 36 |
| knee | 7 / 13 | 16-18 / 178 | up to 16 |
| foot/toe/leaf | 17 / 18 | 18 / 53 | up to 20 |

Flat's ~18 max is normal foot swing. Stairs had **155 frames with a >40 deg single-frame leg
jump**. A single-frame 45 deg thigh change on a locked planted foot is what the user sees.

## Localized cause

Top offenders are all `target_owner=live_contact`, `ground_weight=1.0` (planted foot), with
solver actions `clamp_negative_knee` -> `constrain_knee_direction` -> `solve_to_support`. Around
one spike (left leg, frames 336-339):

```
f336 kneeflx=64.7 negclamp=True  kneedir=True  poleal=0.70  thigh=56.4 shin=97.2
f337 kneeflx=67.6 negclamp=True  kneedir=True  poleal=0.70  thigh=69.1 shin=89.2
f338 kneeflx=70.4 negclamp=False kneedir=True  poleal=0.70  thigh=114.9 shin=45.5   <-- 46 deg snap
f339 kneeflx=72.9 negclamp=False kneedir=False poleal=0.994 thigh=117.3 shin=45.0
```

`FootIKLegPoseEvaluator._limit_negative_rendered_knee()` (`foot_ik_leg_pose_evaluator.gd:446`)
overwrites `hip_delta`/`knee_delta` directly (bypassing `_limit_correction`'s rate limiter) when
the knee is wrong-side or its pole alignment is under `minimum_knee_pole_alignment`. Its internal
`_select_feasible_bend(...)` call (evaluator ~`:494`) is passed **only 7 args**, so `side` defaults
to `&""` and the function returns before its `_previous_bend` hysteresis branch - i.e. the
constrained plane is chosen with **no temporal continuity** and can flip between two feasible
planes frame to frame. The snap is between two *full-strength* constrained poses, not a gradual
drift. This is the same family as 013 (bend-selection instability) but reached via the
negative-knee constraint path.

## Attempts

- Proportional "engagement" ramp on the correction (zero at the alignment/flexion boundary, full
  past it): **zero measurable effect** - the offending frames are deep inside the invalid region
  (full correction), so the flip is between two full-strength poses. Reverted.
- Stair walk slow-down (`Player.stair_walk_speed_scale`, default now 0.6; automated preview
  walkers and the 025 walk-contact fixture pinned to 1.0): did **not** reduce the jank - confirms
  it is not cadence/speed. Kept only as a feel option; needs a live verdict.

## Next steps (not done)

1. Give the constrained bend plane temporal continuity: keep the previous plane while it is still
   feasible (stick-if-feasible), or give it its own hysteresis state distinct from the general
   solve's `_previous_bend` (do NOT share `_previous_bend` between the two call sites). Avoid plain
   rate-limiting - AGENTS.md warns lag on a wrong-side knee flip can be worse than the snap.
2. Re-measure with `trace_query.py angular` and run `scripts/check_foot_ik_fast.sh` plus
   `scripts/check_foot_ik_all.sh`; this is load-bearing 013 territory - live confirmation required.
