# 019: Toe/leaf clips through a stair riser during idle rotation

## Status and scope

**Open, unfixed.** A real, reproducible bug with working regression coverage that now correctly
fails, documenting the gap rather than hiding it. Two fix attempts tried, both did not resolve
it; the second was reverted after it introduced a separate regression. Live-reported by the user
while testing unrelated 017/018 follow-up work (the balance counter-lean modifier): rotating in
place on a split stair stance visibly slides a foot with a clip through the step's edge.

## The concrete symptom

Standing on a stair split stance (two feet on treads at different heights) and rotating in
place: a foot's toe/leaf swings into the riser of a nearby tread as the body's yaw changes,
penetrating up to ~11cm deep, building up gradually over many consecutive frames rather than a
one-frame snap. This is distinct from - and NOT fixed by - the ankle-target repositioning slide
that prompted this investigation (see "What was actually fixed" below).

## Root cause, confirmed by direct investigation (not guessed)

1. The clipping foot's target during the clip is NOT owned by the idle-lower-latch/acquire
   system this session initially suspected - it is owned by `LANDING_UPPER`
   (`straighten_compressed_upper_target` in `foot_ik_ground_sampler.gd`), a separate mechanism.
2. `foot_ik_target_coordinator.gd` already has a toe/leaf envelope safety check
   (`_toe_envelope_valid`, from `AGENT_TASKS/008`) that exists specifically for "a valid ankle
   latch with the toe poking into the next riser" - exactly this symptom. But it never runs for
   this owner during this scenario: `legacy_transition_active` (true whenever *either* foot is
   mid lower-tread transition) disables coordinator validation for every owner except the three
   lower-transition owners themselves (`IDLE_LOWER_LATCH`, `IDLE_LOWER_ACQUIRE`,
   `IDLE_STANCE_REHOME`) - `LANDING_UPPER` is not among them, even though it is an already-settled,
   non-transitioning foot on the *other* leg.
3. Confirmed via a temporary debug print reading `_target_coordinator.get_plan(side)` at the
   exact failing frame: `owner=LANDING_UPPER`, `toe_status=NOT_CHECKED`, `reason=
   selected_legacy_candidate` (the untouched pass-through default) - proving `_finish_validation`
   never ran for this leg at all during the clip.

## Fix attempts tried this session

### Attempt 1: collision-aware hold for ankle repositioning (kept, real fix, different bug)

Replaced the idle-reposition straight-line `move_toward` (which only checked its two endpoints
against geometry, never the path) with `_move_toward_held` in `foot_ik_ground_sampler.gd` -
raycasts the intended path each frame and holds at any blocking geometry instead of pushing
through. Verified clean against the full suite. This is real, working, and stays - but it does
not touch the toe/leaf-clip symptom above, since that clip is orientation-driven (the toe swings
as the body rotates), not caused by the ankle target's own repositioning path.

### Attempt 2: extend toe-envelope validation to LANDING_UPPER (reverted)

Added `FootIKTargetPlan.Owner.LANDING_UPPER` to the `owner_is_lower_transition` exemption list in
`foot_ik_target_coordinator.gd`, so it stays validated even while the other foot transitions, and
added `_retreat_for_toe_clearance()` - a small search that shrinks the ankle target toward the
hip in 2cm steps (up to 12cm) until the toe/leaf envelope check passes, re-validating stance/
support/reach at each candidate.

**Result: did not fix the clip** (penetration stayed ~0.11m, same order of magnitude) and
**introduced a new regression**: `foot_ik_idle_plant_stability_check`'s own separate live-pose
sub-check went from `live_pose_joint_step_m=0.043` (pass) to `0.062` (fail against its
`MAX_LIVE_POSE_JOINT_STEP=0.045` budget) - some other owner's target computation also runs
through this same gate and got disturbed by the widened exemption. Full-suite confirmed the wider
blast radius: `Passed: 39` (down from the established 41), and one *other* previously-passing
check also newly failed while coincidentally matching an already-`KNOWN_BASELINE_FAILURES`
label - which would have silently masked that second regression had the harness not been checked
carefully (018's own finding I, playing out live). **Reverted.**

Why the retreat likely wasn't enough: the clip's own depth (~11cm and still growing across the
sampled window) may already exceed what a 12cm hip-ward retreat budget can clear without also
failing reach/stance, especially since retreat only pulls the ankle *toward the hip*, not away
from the specific wall direction - the toe offset is a rotated rigid vector from the ankle, not
something a same-side retreat necessarily un-rotates away from the obstruction.

## Regression coverage added (kept, working)

Extended `foot_ik_idle_plant_stability_check.gd`'s existing repeated-rotation sweep
(`LIVE_TURN_POSITION`/`LIVE_TURN_YAWS_DEG`, already on a real "Stairs 0.35m" fixture) to sample
real box-collider penetration every frame at the ankle and toe, using
`FootClearanceEvaluator.evaluate_box()` against whatever tread/riser box collider(s) are actually
near each sample point (found generically via a small-sphere `intersect_shape` query, not
hardcoded tread coordinates - see the `_sample_turn_penetration`/`_find` pattern in that file).
Reports `turn_penetration_m`/`turn_penetration_side`/`turn_penetration_frame` and gates on
`MAX_TURN_PENETRATION_M := 0.001`. This is the first check in the suite that samples *during* a
transition rather than only the settled end state, and it is currently, correctly, red.

## What to try next (not attempted, needs a fresh investigation)

- A retreat direction informed by the actual penetration exit vector (`FootClearanceEvaluator`'s
  `Result.deepest_point_exit`), not a fixed hip-ward direction - retreat *away from the wall*,
  not just *toward the hip*.
- Constraining the foot's yaw/orientation directly (limit how far the toe is allowed to swing
  relative to the ankle when a nearby riser is detected) rather than moving the ankle at all.
- Investigating what *other* owner's target computation shares the gate widened in attempt 2, to
  understand the live-pose-joint-step side effect before trying a similar widening again.
- Confirming whether this reproduces for owners other than `LANDING_UPPER` too (the two other
  non-exempted "coordinate_idle" owners - `LIVE_CONTACT`, `IDLE_FREEZE` - could have the same gap).

## References

- `foot_ik_target_coordinator.gd::_toe_envelope_valid`/`_toe_envelope_valid_at` -
  the existing, correctly-scoped check this bug slips past.
- `foot_ik_target_coordinator.gd::owner_is_lower_transition` - the exemption list; `LANDING_UPPER`
  was added then reverted here.
- `foot_ik_ground_sampler.gd::straighten_compressed_upper_target` - owns the clipping foot's
  target during this exact scenario.
- `tests/manual/foot_ik/foot_ik_idle_plant_stability_check.gd::_sample_turn_penetration` - the new
  regression coverage.
- `AGENT_TASKS/008` - the original toe-envelope check this gap was found in.
- `AGENTS.md`'s Foot IK section - durable lessons from this investigation are recorded there
  (the `legacy_transition_active` gap, the `FootClearanceEvaluator` per-frame pattern, and the
  "confirm which owner governs the target before assuming which validation path is responsible"
  lesson).
