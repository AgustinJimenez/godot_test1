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
runners include it. This checks final toe bones, not the complete skinned mesh.

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
