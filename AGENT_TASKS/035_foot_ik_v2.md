# 035 - Foot IK v2 from scratch (flat / ramp / step / stairs)

Status: v2 baseline exists and its own suite runs; the user's live verdict is "no visible
improvement" over v1. The ramp cross-slope case is red. Isolated work under
`tests/manual/foot_ik_v2/` - `actors/player/foot_ik/` (v1) stays intact as the reference.

## Why

v1 grew to 20 runtime modules / ~6.8k lines and could not be tuned into a clean stair walk
(025/028/030/031). v2 restarts the problem with one responsibility per file, one behaviour per
check, and every acceptance test written as the behaviour is added.

## Current handoff

**What works.** v2 drives the real player: per-foot ground ray + analytic two-bone solve +
sole-to-surface alignment. Its own checks pass walking flat / ramps 15-30-45 / stairs
0.10-0.20-0.35 forward (`FOOT_IK_V2_CHECK PASS`, worst ankle-to-target 0.0003 m, sole tilt 0.0).

**What does not.** The user's scenario - stand on the closest ramp, strafe left <-> right - is
red: `FOOT_IK_V2_RAMP_CHECK FAIL  float_max=0.87  toe_clip_max=0.117`. A/B of the worst frames
shows they are on feet v2 **releases to the animation** (`out_of_reach` / `mid_swing`), not on
feet it corrects - so the current corrections are not where the visible defect is.

The user reports no visible improvement over v1 live, and that is the correct reading: the mask,
walkable gate, edge probe, resample and toe-clearance passes added this session did not change
the live result.

## Suite

```sh
scripts/check_foot_ik_v2.sh
#  PASS project checks
#  PASS FOOT_IK_V2_SOLVER_CHECK   pure two-bone maths, 6 assertions, no scene
#  PASS FOOT_IK_V2_CHECK          forward walk over all 7 surfaces
#  FAIL FOOT_IK_V2_RAMP_CHECK     the user's strafe-on-the-ramp scenario (see above)
```

The ramp check is independent of the modifier: the harness casts its own ray from above the body
so it finds the **real ramp** (not the floor beneath it) and compares the sole/toe points against
that surface. Trace: `user://foot_ik_v2.jsonl` (v1's writer and schema, readable by
`scripts/trace_query.py`).

## Harness traps found this session (do not re-discover)

Each of these produced a confident, wrong number before being found:

- `Skeleton3D.get_bone_global_pose()` is **relative to the skeleton, not the world** - convert with
  `skeleton.global_transform` for every ray/target/measurement. Casting a ray at the raw pose
  samples the wrong place as soon as the character is off the origin.
- A `SkeletonModifier3D` publishes in the skeleton's **deferred** update, after a node's
  `_physics_process`. Sample the pose in `_process` (or after publication), or you measure the
  pre-correction pose.
- A harness that **recomputes** world-space values can disagree with the modifier's skeleton-space
  result and report a perfectly aligned foot as 60-127 deg off. Grade the modifier's own
  authoritative values (`residual`, `align.after_deg`) instead of restating the logic.
- The sole contact point is `bone_origin + sole_dir * ankle_height` (the sole is **below** the
  bone). Subtracting puts it above and inflates every "float" by `2 * ankle_height`.
- Grade only **grounded** feet (either the animation or the result is near the surface). Grading a
  swing foot's distance-to-ground is meaningless and produced false floats.
- `ankle_height` is the **measured sole depth** from the skinned foot mesh in the rest pose
  (0.0960), not the foot bone's rest height (0.0865). The mesh read needs the
  `find_bone(skin.get_bind_name(bind))` fallback because the bind bone index comes back -1.

## Next steps

1. **A/B v1 through the identical ramp-strafe scenario** and diff the two runs - v1 works on ramps
   in its own preview, so the difference is the answer, not more reasoning.
2. **Fix the released-foot path**: a foot v2 leaves to the animation (`out_of_reach`/`mid_swing`)
   is where the remaining toe clip and float live. Decide whether v2 should correct it, or why the
   animation clips there.
3. The ground ray can still sample the floor instead of the ramp near edges; an inward edge probe
   (v1's) was added but is unverified.

## Known-kept in v2

mask `1 | (1<<5)` + walkable-normal gate (v1's), out-of-reach release, per-frame pose snapshot,
`round`-free per-foot state (`released`/`at_target`/`stretched`), the pure solver split, and the
v1-format trace.
