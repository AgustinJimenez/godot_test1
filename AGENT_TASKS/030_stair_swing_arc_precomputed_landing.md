# 030 - Stair swing arc: precompute each step's landing for one smooth swing

Status: progressing. The "predict the landing early" half is proven; the "drive the swing to it"
half is not yet effective because the target injection point was wrong. Gated experiment reverted;
plan below is ready to resume. Companion to 025 (the stair toe clip) and 028 (the joint jank).

## Goal

Plan each stair step: choose the landing point on the next tread up-front and swing the foot to it
in one smooth arc (lift + forward together), instead of today's reactive "lift, then shift".

## How we can see it (new lab tooling)

`tests/manual/foot_ik/foot_ik_stair_lab.tscn` is the focused scene for this stair work (also noted
in AGENTS.md's Foot IK section), alongside the broad multi-character preview. It records the real
Player walking floor -> stairs -> top, with per-foot ankle trails (right blue / left purple), toe
spheres rigged via `BoneAttachment3D`, a red clip sphere, scrub/step/reverse/speed, editable step
height, and a per-frame JSONL log at `user://foot_ik_stair_lab.jsonl`. This is what made the step
motion visible at all.

Observed over the steps (right toe, log): the path is "up then forward" in near-right-angle
segments - e.g. f108-116 rises vertically at z~0.76, then f117-140 travels forward with the lift
already done. No sideways wiggle, no backward slip (checked). So the foot lifts, then shifts.

## Diagnosis

- The vertical lift is **reactive**: `_desired_swing_lift()` (`foot_ik_stair_predictor.gd`)
  computes clearance against the *animated* foot's lowest point and drops to 0 once the foot is over
  the surface. The horizontal target just follows the ground sampler. Two uncoordinated motions.
- The landing latch (`LegState.has_latched_target`, `latched_target`) is set only once the animated
  foot's forward probe (`foot_pos + forward * step_prediction_distance`) sees a surface above the
  swing base. Measured with the lab log's `swing` field: the latch happens **0-11 frames into the
  swing, sometimes never**.
- **Proven half:** predicting the landing at swing *start* with a forward scan (walking the probe
  further ahead until it finds a surface above the base) makes the latch fire at **frame 0 of every
  swing**. This is achievable and was verified via the log.

## Where the swing target actually comes from (the missing hook)

Overriding the per-leg `leg["target"]` and `leg["ground_target"]` had **zero effect** on the
rendered foot. The real path is:

`_propose_spacing()` sets `leg["solve_candidate"]` from `target`/`ground_target`
(`foot_ik_target_coordinator.gd:506/510/524`) -> `_build_plan()` sets
`plan.ankle_target = leg["solve_candidate"]` (`:554`) -> `finalize_leg_targets()` writes
`leg["final_target"]` -> the modifier's solve reads `leg["final_target"]`.

**Hypothesis for the null:** an arc target whose **y** is interpolated between two tread heights is
in the air mid-swing, so the coordinator's support/reach validation rejects it and falls back to the
sampled ground target. Conclusion: the arc should drive **x/z only**; keep **y** from the sampled
surface (the existing lift already supplies the vertical clearance and the arc look).

## What was tried and reverted (do not re-try as-is)

1. Arc with time-based progress, late latch -> inert (no landing until 0-11 frames in).
2. Early latch at swing start, no arc -> changed latch timing only; rendered pose unchanged.
3. Early latch + arc + override `target` (then also `ground_target`) -> still inert (this is what
   exposed the `solve_candidate` path above).

All three are null results and were reverted per the repo's rule. The gated flag
(`FootIKDebug.settings.stair_swing_arc`) and the lab checkbox were reverted too; re-add them when
resuming.

## Attempt 4 (reverted): horizontal-only override - still inert

Re-added gated: early latch (forward scan) + override of **only x/z** of `target` and
`ground_target` from the arc, leaving y on the sampled surface. Result:

- The arc **was active**: the lab log's `swing.latched` shows the latch at **frame 0 of every**
  swing, so the prediction half is solid.
- The rendered toe trail was **byte-identical** again. So the x/z override still does not reach the
  solve.

Refined conclusion: `ground_target` -> `solve_candidate` -> `plan.ankle_target` is *a* path, but the
coordinator's accept/validate step almost certainly **rejects** the resulting point - a forward x/z
with the *sampled* y is not a consistent surface point (the forward x/z is over a different tread
than that y), so it reverts to a validated target. Driving the foot from here needs either:
(a) an arc point that is a **consistent surface point** (x/z *and* the surface height at that x/z,
re-sampled each frame), placed where the coordinator accepts it; or
(b) moving the landing/takeoff the predictor hands to the plan, rather than the per-leg target.

Next step: try (a) - raycast the arc's own x/z for its y so the candidate is a real ground point -
and re-measure the toe trail.

## Attempt 5 + DECISIVE finding (reverted): the stair swing leg is RELEASED to the animation

Instrumented the modifier's solve loop: during stair climbs its release branch fires for
`plan.owner == Owner.STAIR_SWING` with `leg["hit"] == false` and `has_target == false` - **56
releases in one lab run**. So the stair swing foot is published straight from the authored
`unarmed_walk` animation (the leg is released), and:

- every per-leg `target`/`ground_target` override is ignored - the leg never reaches the solve;
- the plan/log show `adj=unchanged`/`not_finalized` with **no** `rejected_*`, i.e. the plan is built
  and accepted but the leg is then released anyway.

This is the answer to "why was every target-side attempt inert even though the wiring was correct":
the swing is an **animated, released** leg, not a solved one. The "up then forward" toe trail is the
animation's own swing shape plus the stair system's release/lift timing - the per-leg target does
nothing while airborne.

### Consequence (the real fix, scoped)

To shape the stair swing, the swing leg must be a **solved** owner while airborne rather than
released. A first attempt - gate the `not leg["hit"]`/`not has_target` release on
`plan.owner == STAIR_SWING` while the feature is on - hit a runtime error: the solve path assumes a
populated per-leg entry for an unsupported leg (`ground_weight` read from a dict that lacked it).
So this is an **ownership/pipeline change** (replace the released animation swing with a solved
swing carrying its own target/weight/reach/validation), not a target tweak. It deserves its own
focused task with live validation, and a decision on whether losing the authored swing upper-leg
motion is acceptable.

## Next step (ready to implement)

Re-add the experiment gated behind `FootIKDebug.settings.stair_swing_arc` (off by default) and:
1. Latch the landing at swing start via the forward scan (proven).
2. In the modifier's per-leg loop, when the arc is active, override **only x/z** of the target (and
   `ground_target`/`solve_candidate`) from `takeoff.lerp(landing, eased_progress)`, leaving y as the
   sampled surface.
3. Measure in the lab: the toe trail should become a diagonal arc and `clip`/`worst_deg` should not
   regress; then run `scripts/check_foot_ik_fast.sh` and hand to the user for a live test.

## Keep (already committed)

- `FootIKStairPredictor.get_swing_state(side)` (active/latched/descending) and the lab log's
  per-foot `swing` field (`312d028`) - the diagnostic that found the late latch.
- The lab's toe spheres/trails and clip sphere.
