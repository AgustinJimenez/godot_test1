# 008: Foot IK platform-edge safety

## Status and scope

Active, awaiting live confirmation. Stabilize stair/edge foot placement without repeated
idle adjustments, clipping, unnatural knees, or body slides. Current work is uncommitted;
do not commit visual/gameplay changes until the user confirms them. Do not auto-play the
preview; the user starts and stops it.

Keep this document a current handoff, not an append-only journal. Replace superseded
status/evidence; code and acceptance scenes hold detailed behavior. Earlier captures,
rejected experiments, and results are preserved in the
[investigation archive](archive/008_foot_ik_platform_edge_safety_history.md).

## Architecture and remaining work

The core problem is competing target owners, not simply insufficient smoothing.
`FootIKTargetPlan` and `FootIKTargetCoordinator` now arbitrate stationary live contact,
idle freeze, and fully acquired lower-support latches before pelvis/leg solving.
They validate support, rotated stance bounds, reach, and height continuity. Recovery
updates compatibility caches together and clears incompatible freeze/latch history.
Validated plans bypass the solver's legacy late stance correction.

Landing, active lower acquisition, stair swing, and locomotion still use legacy adapters.
Do not migrate them by just enabling the stationary validator: an earlier attempt caused
a 0.46m landing jump. A valid plan currently does **not** prove full rendered-leg clearance.

Next work:

1. Get live confirmation of stationary coordinator, knee, and toe-clearance changes.
2. Extend plan validity to the rendered footprint/leg envelope; keep collision policy in
   the sampler/coordinator and bone output in the solver.
3. Move remaining target writers behind explicit owner transitions, retiring redundant
   freeze/lock caches as each path migrates.
4. Check intermediate final poses and zero-delta modifier refreshes, not only final
   contact/weight summaries. Preserve authored flat-ground animations.

## Current fixes awaiting live confirmation

- Stationary coordination and stale-lock release: `foot_ik_idle_plant_stability_check.tscn`.
- Joint-feasible primary bend selection. The negative-knee fallback no longer overwrites
  rate-limiter history and traps the leg near straight. Captured replay settles above
  26 degrees with approximately 0.000001m target error.
- Shared 0.001m numerical tolerance at the configured split-height limit prevents
  lower-latch/safe-zone oscillation. The 0.35m limit is unchanged; 0.36m remains rejected.
  Covered by `foot_ik_idle_support_owner_check.tscn`.
- Lower-riser clearance distinguishes obstacles from support. The old radius-0.32m ring
  required same-height support everywhere, impossible on a 0.60m-deep tread. Lower/empty
  neighbors no longer reject escape candidates; separate ankle-support and stance checks
  remain. No solver or ramp policy changed for this fix.

## Latest toe-clipping evidence and regression

Capture: `/tmp/foot_ik_live_20260905_014001.jsonl`, frames 14483–14522.
Root `(13.92332, 1.040266, 1.042998)`, yaw `-151.260741` degrees. Left retained
surface `(14.22776, 0.7, 1.146203)`. Toe z=1.277106 and leaf z=1.349701 at y≈0.725
are inside the next stair (starts z=1.20, top y=1.05), despite a valid ankle-support plan.

`foot_ik_toe_riser_check.tscn` reproduces that pose and stale lower latch. Before the fix,
all 600 settled toe/leaf observations clipped. Afterward: zero clipping over 300 settled
frames, effectively zero sole error, maximum recovery foot step 0.026476m (limit 0.035m).
It permits 60 recovery frames, then samples multiple idle loops. Both fast and main
runners include it. This checks final toe bones, not the complete skinned mesh. It only
covers the **left** foot at this pose; see below for a right-foot instance of the same
category that this scene does not exercise.

## Right-foot clip and shin-swing regressions from a broader idle/rotation/move sweep

A one-off stress harness (spawn at the exact latest-log root/yaw above, then 8 cycles of a
full 360-degree, 30-degree-step idle rotation sweep plus a short forward/backward walk
burst, sampling every frame) found two further real regressions at/near this same
staircase, not covered by any existing acceptance scene:

- **Right toe/leaf clipping - root cause confirmed, not yet fixed.** The right leaf bone
  repeatedly lands inside stair collision geometry at approximately
  `(13.5685, 0.7247, 1.2037)` - about 3-4mm past the riser edge at `z=1.20` (tread top
  `y=1.05`). Reproduced deterministically by replaying the exact settle-then-rotate history
  (200-frame settle at the live yaw, then one 45-frame hold, then +30 degrees) rather than
  jumping straight to the suspect yaw - the latch/plan state at the moment of rotation
  matters, a fresh reset from the target yaw alone does **not** reproduce it.
  - The plan is `IDLE_LOWER_LATCH`, `reason=validated_lower_support` - the coordinator
    considers this ankle target fully valid. It is: the ankle sits mid-tread. The clip is
    the toe/leaf tip, ~0.21m ahead of the ankle at this foot yaw, poking into the *next*
    riser - a target-plan/toe-envelope gap, matching 008's own "Next work" item 2.
  - `foot_ik_ground_sampler.gd`'s `_has_lower_riser_clearance()` (the check meant to catch
    exactly this) correctly returns `false` for this exact surface once queried after
    collision is fully registered - it is not the bug. (An earlier pass here wrongly
    blamed its probe height; that was an artifact of a diagnostic script querying physics
    on the very first tick, before CSG collision shapes registered. No fix was needed or
    kept there.)
  - The real gap is one level up, in `_rehome_lower_surface_from_riser()`: when clearance
    fails, it computes an escape direction from only 4 world-cardinal probes (not the finer
    16-direction ring `_has_lower_riser_clearance` itself uses) and searches up to 24 steps
    of 0.02m (0.48m total) along it for a same-height, in-zone, clear candidate. When nothing
    in that budget qualifies, it gives up **silently** and returns the original, still-unsafe
    surface unchanged (`foot_ik_ground_sampler.gd` around the `lower_riser_cleared_target.erase(side); return surface`
    fallback) - no unlatch, no weight reduction, no wider search. That fallback is what lets
    the invalid plan reach the solver as `valid=true`.
  - Caveat before generalizing this fix: this exact reproduction sits in the narrow x-range
    where the preview scene's "Stairs 0.20m" and "Stairs 0.35m" platforms physically overlap
    (`PLATFORM_WIDTH=3.0` > `PLATFORM_SPACING=2.5` in `foot_ik_preview.gd`, an authoring
    quirk, confirmed by dumping both platforms' `CSGBox3D` collision boxes - both staircases'
    geometry coexists at this exact XZ, which no single real staircase would present). Some
    of the 4/16-direction probe misses here are an artifact of that overlap, not proof the
    escape search would fail the same way on a normal single staircase. Verify the silent-fallback
    gap reproduces away from the platform seam (or fix the preview scene's spacing) before
    treating the escape-search fix as validated.
  - Tried narrowing `PLATFORM_WIDTH` (3.0 -> 2.4, keeping it under `PLATFORM_SPACING`) in
    `foot_ik_preview.gd` to remove the overlap without moving any platform's origin (so
    existing hardcoded live-repro coordinates would keep pointing at the same case). This
    broke `foot_ik_idle_plant_stability_check` (`turn_step_m=0.169` vs limit `0.12`, plus a
    joint-step overage) - some of its hardcoded positions sit near the old wider edge and
    lost the geometry they depended on. Reverted; both `foot_ik_preview.gd` and
    `foot_ik_ground_sampler.gd` are back to their pre-investigation state (confirmed via
    `git diff`, no residual changes).
  - No fix applied. Four explored options, none landed:
    1. Probe-height fix in `_has_lower_riser_clearance` - dead end, not the real bug (an
       artifact of a diagnostic script querying physics before CSG collision registered).
    2. Narrow the preview platforms so they stop overlapping - broke
       `foot_ik_idle_plant_stability_check` (`turn_step_m=0.169` vs limit `0.12`), since its
       hardcoded live-repro positions depend on the old, wider geometry.
    3. An isolated single-staircase repro (own geometry, far from every CASES platform, no
       overlap) to check whether the escape-search gap reproduces outside the preview's
       overlap artifact - inconclusive: `latch_observed=1` out of 24 attempted corner
       samples, meaning a cold spawn at a "corner-like" position mostly never reached the
       `IDLE_LOWER_LATCH` state at all within the settle window. Needs the same
       settle-then-rotate replay the original repro required, not a cold spawn; not
       attempted due to time already spent.
    4. Made `_rehome_lower_surface_from_riser` return `{surface, safe}` and had
       `_validate_idle_lower_support` refuse to latch (`_reject_idle_lower_support`) when
       `safe=false`, instead of silently keeping the unclear surface. Fixed the original
       clip in isolation, passed `scripts/check.sh` and most of
       `scripts/check_foot_ik_fast.sh`, but **broke** `FOOT_IK_LEDGE_SAFETY_CHECK` on
       `idle_both_lower_legs_clear_platform_corner_live_repro` (knee corner clearance
       0.036m vs the 0.040m minimum) - a different corner-safety regression case in the
       same family. Reverted; `foot_ik_ground_sampler.gd` is back to its committed state
       (confirmed via `git diff`).
  - Net conclusion so far: this validation path is tightly tuned across several
    marginally-passing live-repro cases, and rejecting a previously-silently-accepted
    surface shifts enough fallback behavior to shave margin off a *different*,
    already-passing corner case. A real fix here likely needs to jointly re-check every
    `foot_ik_toe_riser_check`/`foot_ik_ledge_safety_check`/`foot_ik_idle_plant_stability_check`
    corner case together, not patch `_rehome_lower_surface_from_riser` in isolation and
    hope the margins hold. Treat this as input to task 009's ownership-consolidation
    review rather than another one-line patch attempt.
- **Anatomical shin-swing violations during the walk bursts.** `FootIkJointLimitCheck`
  (the shared post-modifier safety check) flagged 37 instances of shin swing exceeding the
  configured 45-degree upright limit (`FootIKRuntimeSettings.max_upright_shin_swing_degrees`),
  on both legs, specifically during the forward/backward walk bursts at this location, not
  during pure idle rotation. The check only fires when the contact normal is classified
  flat (`dot(UP) >= 0.999`) and the animation is idle/walk (not crouch/jump), so this is IK
  planting the foot as if flat while the leg swings well past the upright preferred cone.
- A third signal - roughly 12-15mm/tick foot/knee movement on ~590 sampled frames right
  after some rotation steps, while the leg reported full ground weight and no active
  swing - was also flagged but is **not confirmed**: it may be genuine residual IK
  convergence continuing past the harness's 20-frame post-rotation settle window rather
  than real jitter/oscillation. Re-check with a longer settle window and a
  monotonic-decay test before treating it as a bug.

The one-off harness (`tests/manual/foot_ik/_last_log_idle_stress_demo.gd/.tscn`) was a
temporary capture scene per this repo's convention and has been removed; reproduce with a
similar spawn-and-sweep setup (see `foot_ik_idle_plant_stability_check.gd`'s pattern) before
fixing, and consider promoting it to a permanent acceptance scene once the fix lands, since
it is the only harness so far that exercises the right foot and multi-angle idle rotation at
a stair edge together.

## Validation and handoff

Latest toe-fix validation map:

- `scripts/check.sh`: PASS (44 seconds).
- Toe replay: PASS; support-owner replay: PASS, no support switches.
- `scripts/check_foot_ik.sh`: FAIL (38 seconds), after the support-owner replay.
  Its animation-comparison command suppressed the failing output; rerun that scene
  directly before classifying the failure. Later cases did not run.
- `scripts/check_foot_ik_locomotion.sh`: FAIL (16 seconds), documented
  `walk_left`/`walk_right` failures.
- `scripts/check_foot_ik_ramps.sh`: FAIL (195 seconds), 42 failing cases, matching
  the documented failure count; not proof of identical per-case metrics.
- `scripts/check_foot_ik_ramp_sweep.sh`: interrupted at the user's request after
  about 11 minutes. No complete sweep result; do not report it as passed.

User explicitly requested an unverified checkpoint commit/push after being reminded of
the live-confirmation requirement. This checkpoint is not a claim of live acceptance;
the latest visual changes and incomplete/failed validation still need follow-up.

The previous fast suite passed in 117 seconds before this clearance change. Historical
exhaustive runs were not all green: lateral locomotion and ramp penetrations were known
failures (dense ramp baseline 257/6240). Compare cases and metrics before calling a new
failure pre-existing. Preserve live traces before harnesses overwrite shared logs. No
temporary walk/spin/stair markers were present. No interactive scene was launched.

Earlier context: [task 007](007_foot_ik_stair_contact_and_locomotion.md).
