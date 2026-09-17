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

## Live trace (2026-09-16, user walking floor-then-stairs)

`/tmp/live_20260916_082858.jsonl` (1203 frames, span 1517..2719; walk 743, idle 214, torch_idle
213). `trace_query.py angular`: 68 leg-joint jumps >35 deg/frame; peak 74 deg hip, 54 deg knee,
53 deg foot/ankle, ~20 deg body hips. Two one-frame handoff patterns, both during walking
(owners `stair_swing_prediction` / `stair_support` / `live_contact`):

1. Swing->planted snap (left, f1770->1771): weight 0.00->1.00, owner
   `stair_swing_prediction`->`stair_support`; `foot 27.4->80.2`, `leaf 54.0->106.8` (foot pitches
   ~53 deg in one frame), `thigh 48.0->11.5`, `sole_clearance 0.110->-0.098` (9.8 cm through the
   ground that frame).
2. Rejected->accepted target flip (right, f1788->1789): solver action
   `reject_invalid...`->`solve_to_support`; `knee 29.8->4.9` (snaps straight), hip twists 74 deg,
   `sole 0.226->0.029`.

So the visible jank is hard one-frame handoffs (weight/target/owner swaps), not a smooth rate -
the fix target is to blend the swing->support weight+target handoff and give the stair predictor's
accept/reject decision continuity, plus rate-limit the foot pitch across it. Confirms the earlier
finding but adds that the *unplanted* handoff (pattern 1) and the reject/accept flip (pattern 2)
are the dominant live offenders, not only the planted constraint-regime flip (which the synthetic
stair marker captured).

## Root cause (identified)

Every violent pop frame is exactly a frame with `plan_final_adjustment = pose_toe_clearance` - the
**instant toe-clearance retry** in `FootIKTargetCoordinator.solve_leg_candidate()`
(`foot_ik_target_coordinator.gd:101`, `retry_options[&"instant"] = true`). That flag makes
`FootIKLegPoseEvaluator._limit_correction()` return the desired joint pose un-limited
(`foot_ik_leg_pose_evaluator.gd:661`), so the whole leg can change 40-180 deg in a single frame.
Confirmed on both the synthetic stair trace (f508/f722/...) and the live trace (f1771/f1789/f2598):
the offending frames all carry `adj=pose_toe_clearance`.

The "foot/toe/leaf" pops are not independent ankle snaps - those joints are children of the leg,
so they move with the thigh/shin (that is why foot/toe/leaf all changed by the same ~52 deg). The
foot's own correction is *already* unlimited for non-crouch animations by design
(`foot_ik_leg_pose_evaluator.gd:667`), so `instant` only actually bypasses the hip/knee limiter.

## Measured tradeoff (the retry is load-bearing)

Removing `retry_options[&"instant"] = true` (temporary experiment, reverted):

| metric | with instant | without |
|---|---|---|
| R/L hip max deg/frame | 95 / 107 | 20 / 75 |
| R/L knee max deg/frame | 168 / 179 | 20 / 74 |
| leg-joint frames >15 deg | 101-140 | 41-160 |
| 025 walk-contact clip depth | 0.0125 m | **0.0955 m** |

So `instant` clears the toe by snapping the whole leg; removing it trades the pop for a much worse
toe clip. Neither direction alone is acceptable - the retry's rate must be *bounded*, not unlimited.

## Bounded-rate attempt (reverted)

Replaced `instant=true` with a bounded joint-speed override (`correction_speed_override = 1440`
deg/s ~ 24 deg/frame) via a new evaluator option. Result is a monotonic tradeoff - any finite cap
costs toe-clearance clip:

| retry rate | R/L knee max deg | R/L hip max deg | 025 clip depth |
|---|---|---|---|
| instant (unlimited) | 168 / 179 | 95 / 107 | 0.0125 m |
| 1440 deg/s (bounded) | 37 / 70 | 45 / 71 | 0.0522 m |
| default rate (no override) | 20 / 74 | 20 / 75 | 0.0955 m |

The bounded version also made the foot/toe pitch jank *worse* (max 53->87 deg, jerk 12->22):
with the leg lagging, the unlimited foot correction has to cover more. No acceptable point on this
curve, and the leg-snap is apparently required for the 025 clip - so the retry is not the place to
fix it. Reverted.

## Next steps (not done)

0. Preferred: fix the 025 toe clip at its **source** (why the swing foot's toe enters the tread at
   all) so the retry can be gentler or removed entirely. Trying to smooth the retry trades directly
   against the clip (table above) because the leg snap is what clears the toe.

1. Give the constrained bend plane temporal continuity: keep the previous plane while it is still
   feasible (stick-if-feasible), or give it its own hysteresis state distinct from the general
   solve's `_previous_bend` (do NOT share `_previous_bend` between the two call sites). Avoid plain
   rate-limiting - AGENTS.md warns lag on a wrong-side knee flip can be worse than the snap.
2. Re-measure with `trace_query.py angular` and run `scripts/check_foot_ik_fast.sh` plus
   `scripts/check_foot_ik_all.sh`; this is load-bearing 013 territory - live confirmation required.

## 2026-09-17 continuation: constrained-plane continuity (right diagnosis, unacceptable trade)

Implemented the fix from "Next steps": gave `_limit_negative_rendered_knee`'s constrained bend plane
its own per-side continuity (`state._previous_constrained_bend`, added to `FIELDS`), easing the
plane at a bounded rate instead of letting its internal `_select_feasible_bend` (called without a
side, so it skips the `_previous_bend` branch) pick a plane with no temporal continuity.

Measured:

| metric | before | with continuity |
| --- | --- | --- |
| preview stair trace knee max | 168 / 178 deg | 8.0 / 8.0 |
| preview stair trace hip max | 95 / 107 deg | 8.3 / 8.3 |
| preview stair frames >15 deg | 69 / 93 | 0 / 0 |
| lab stair joint p95 / max | 26.81 / 50.12 | 17.18 / 22.03 |
| lab stair clip | 0.0000 m | **0.2956 m** (49 frames) |

So the mechanism is right for the jank - the spikes are essentially eliminated - but retaining the
wrong-side/constrained plane lets the foot poke up to 29.6 cm into the geometry. Ease rate
(720/1440/2880 deg/s) gave **byte-identical** output, so the rate is not the lever; merely retaining
the plane is.

**Conclusion - the jank and the clip are the same mechanism.** The constraint flip that prevents the
clip is exactly what spikes the joints. Suppress the flip -> smooth but clips; allow it -> clips-free
but jerks. To get both, the FREE solve must stop producing the clip-worthy pose so the flip is not
needed - a targeting/solver-quality fix, not a rate/continuity knob. Reverted (evaluator/state back
to the pre-experiment state); no gameplay change remains.

## 2026-09-17 continuation 2: the spike is an abrupt step-up plant, not the swing

Traced the baseline spike frame (lab f102, 50.1 deg) per foot from the corrected recorder:

```
f100 right (live_contact) ankle y=0.233   target y=0.332
f101 right (live_contact) ankle y=0.264   target y=0.488
f102 right (live_contact) ankle y=0.594   target y=0.594   <- ankle +0.33 m in one frame
f103 right (live_contact) ankle y=0.491   target y=0.658
```

The planted right foot's ankle rises ~0.33 m in a single frame - a full step height - as its solve
target jumps 0.488 -> 0.594 (onto the next tread). That is the stair **step-up plant transition**,
not the swing (the left leg is a released `stair_swing_prediction` at the same frames), and the
constrained-plane flip is the solver reacting to that abrupt pose change.

So the free solve is not "wrong" in isolation: it is chasing a target that steps up by 0.33 m in one
frame, which produces a wrong-side/poorly-aligned rendered knee that the constraint then has to snap.
The lever is making the step-up plant gradual - but that trades against tracking the tread (the same
clip coupling), so it is a design choice, not a rate knob. The modifier already smooths the target at
`delta * 24.0` (~0.4/frame); the raw jump is ~0.26 m.

## 2026-09-17 continuation 3: the spike IS the 025 retry, firing on the step-up plant

The f102 spike frame's right leg carries `adj = pose_toe_clearance` - the **025 toe-clearance retry
fired** (the left leg is a released `stair_swing_prediction`). So the 028 joint spike is the 025
retry itself, firing because the support foot's target jumps a full step (0.488 -> 0.594) as the
predictor re-targets it onto the next tread while it is still the support.

This closes the loop precisely: **the retry is the jank (028) and the clip-fix (025) at once**, and
it fires on the stair step-up plant, not the swing (the swing leg is released throughout). The
whole chain:
1. the support foot re-targets a full step up in one frame,
2. its planted toe/leaf then sits inside the riser, so the 025 retry fires,
3. the retry re-solves the whole leg (bounded/instant) -> the 40-180 deg joint spike.

So the fix is the same single place as 030: stop the free solve/target from producing the clip-worthy
pose on the step-up plant (the support foot re-targeting a full step in one frame). Nothing else in
the pipeline is at fault, and every downstream symptom (clip, jank, planned-swing instability)
follows from it.
