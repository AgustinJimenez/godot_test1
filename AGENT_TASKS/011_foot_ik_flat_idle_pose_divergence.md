# 011: Foot IK flat-idle pose divergence

## Status and scope

Fixed (uncommitted, awaiting live confirmation per `AGENTS.md`). Two hypotheses were
disproven before finding the real mechanism below - kept for the record so they aren't
re-tried blind.

## The bug

`foot_ik_animation_comparison.gd`'s `FOOT_IK_ANIMATION_COMPARISON_CHECK` (run via
`scripts/check_foot_ik.sh`) fails on the `IDLE IK ON` case: a dummy standing on a perfectly
flat pad, playing plain `unarmed_idle` with Foot IK enabled, diverges from the pure-animation
reference by ~9-18 degrees of hip/knee rotation, persistently, every run. No stairs, no
platform edges, no motion involved - this is the most basic possible IK scenario. Confirmed
pre-existing (via `git stash` to a clean baseline) before any work this session touched it.

## Two hypotheses tried and disproven

1. **Idle stance-crossing flicker.** `is_idle_stance_crossed()` (`foot_ik_leg_solver.gd`,
   `IDLE_STANCE_MIN_SIDE_CLEARANCE=0.04`, added in commit `78ba538` for platform-edge-recovery
   retraction, per git blame) forces a hard 12cm lateral snap whenever a foot's lateral offset
   from center drops under 4cm during idle. Theory: this flickers on/off during the idle
   animation's own sway, and the leg solver's rate-limited rotation can't keep up, causing a
   repeating pop. Added Schmitt-trigger hysteresis (engage at 0.04, release only past 0.08) -
   **no measurable effect** on the failing case's numbers.
2. **Over-broad scope.** Theory: `is_idle_stance_crossed` should only matter for a
   retracted/edge-recovery foot, not one already flat-preserved. Gated it to skip entirely
   when `preserve_idle_pose or is_flat_level_ground` is true - **no measurable effect**
   either, and direct instrumentation proved why: for the failing dummy,
   `is_stance_crossed=false` the *entire time*, `flat_ok=true`, `animated_contact_distance=0.0`.
   The system is already selecting `target = foot_pos` (the exact animated position, zero
   blend) via `preserve_flat_pose`. Stance-crossing was never the cause; both fixes were
   reverted (`git checkout --` on `player_foot_ik_modifier.gd` and
   `foot_ik_leg_solver.gd`, confirmed clean via `git diff`).

## Where this actually points (untested)

If the target position is already exactly the animated foot position, but the *rendered* hip
and knee rotation still differs from the authored pose by double digits, the divergence isn't
in target selection at all - it's downstream, inside the closed-form IK solve itself
(`foot_ik_leg_solver.gd`'s bone-output phase). The strongest untested candidate:
`_solve_bend_direction()` defaults to `_owner._knee_pole_local[side]` - a **rest-pose**
reference vector captured once at rig setup (`player_foot_ik_modifier.gd`'s `_ready()`) - not
the animation's own live knee-bend plane for the current frame. `AGENTS.md` itself documents
the general principle this would violate: "Use the animated knee bend plane for the pole. A
fixed forward pole twists strafes and crouches." Even solving to the exact same end-effector
(foot) position, a two-bone IK reconstruction with the wrong pole vector can produce a
different hip/knee rotation than the authored pose that reached the same point by other means
(natural secondary motion, twist, etc.) - which would explain reaching the right position with
the wrong rotation, invisible to any target/distance-based check and only visible when
directly comparing rendered rotations against the animation baseline, exactly what this one
check (and no other) does.

**Superseded by a confirmed mechanism found by reading further downstream instead of guessing
a third fix** (see next section). The pole-vector idea above is not ruled out as a contributor
but is no longer the leading theory.

## Confirmed root cause (verified live, not yet fixed)

Live-tested by the user: visible in `foot_ik_animation_comparison.gd`'s row of paired dummies,
the `IDLE IK ON` pair visibly shows `DIFF`, matching this check exactly.

Traced with direct instrumentation (`PELVIS_DEBUG` print, removed after use) on the exact
failing case: `preserve_idle_pose=true` for the left leg every single frame, but
`has_pelvis_motion=true` continuously too, with `_pelvis_lateral_shift` sawtoothing
(~0.05m down to ~0.014m and jumping back, repeating every several frames - the same
oscillation period seen in the raw hip/knee angle diffs from the start of this
investigation).

In `player_foot_ik_modifier.gd::_apply_support_pelvis_and_legs`, a leg only takes the cheap
`_leg_solver.release_to_animation()` path (exactly reproduce the authored pose) when
`preserve_idle and not has_pelvis_motion`. Whenever `has_pelvis_motion` is true - defined as
`shared_drop > 0.0 or not _pelvis_lateral_shift.is_zero_approx()` - every leg instead goes
through a full closed-form two-bone IK re-solve at full weight toward `ground_target`, even
though the intent was to preserve the pose. A full IK re-solve can reach nearly the same
end-effector (foot) position with a different hip/knee rotation than the animation's own
(different pole vector / bend-plane choice), which is exactly what the check measures.

`_pelvis_lateral_shift` itself comes from a pelvis-recentering block (same function, feet
merge/recenter logic, roughly the `stationary and (l_tgt - r_tgt).dot(left_dir) < 0.22` and
the `target_shift` computation that follows it) that runs **unconditionally whenever the
character is idling** (`stationary` true), not only for a genuinely crossed/misaligned
stance - so on a plain, symmetric idle animation it still computes a small nonzero
recentering shift every frame, which is what keeps `has_pelvis_motion` true forever and
forces the full re-solve path to never release.

**Initial concern, tested empirically rather than left as a blocker**: naively calling
`release_to_animation()` whenever `has_pelvis_motion` is true looked like it should be wrong,
since that function writes the hip's absolute pre-shift animated position, seemingly ignoring
the pelvis bone's already-applied shift. Tested directly instead of reasoning further: gated
the release path on `shared_drop <= 0.0` (only the vertical-crouch case still forces a full
re-solve; a pure lateral shift no longer does) and measured the actual result rather than
predicting it.

## Fix applied and verified

`player_foot_ik_modifier.gd`, `_apply_support_pelvis_and_legs`:

```
- if not leg["hit"] or not has_target or (preserve_idle and not has_pelvis_motion) or seam_acquire:
+ if not leg["hit"] or not has_target or (preserve_idle and shared_drop <= 0.0) or seam_acquire:
```

Verified:
- `FOOT_IK_ANIMATION_COMPARISON_CHECK`: `IDLE IK ON` now reads `SYNCED` (was `DIFF` every
  frame); all 8 cases pass, confirmed live by the user in `foot_ik_animation_comparison.gd`'s
  dummy row.
- Fast suite: identical to the pre-fix baseline on every other check, including
  `foot_ik_toe_riser_check.tscn` and `foot_ik_idle_support_owner_check.tscn` (run directly,
  since the suite doesn't reach them past the next check).
  `FOOT_IK_POSE_CONTINUITY_CHECK` improved (`max_jump_m` 0.0222 -> 0.0125).
  `foot_ik_idle_plant_stability_check` remains its one pre-existing failure, materially
  unchanged (`live_pose_joint_step_m` 0.0497 vs baseline 0.0489 - noise, not a regression).
- Not yet run: the full exhaustive suite (`check_foot_ik.sh` and friends) or a broader live
  playtest beyond the comparison dummies - do before treating this as final, per `AGENTS.md`.

## Why parked instead of fixed now

Unrelated to 010's stair/coordinator scope - this is the base flat-ground solve, not target
arbitration. Real severity is unclear: `stance_lateral_offset()` uses
`player_body.get_parent().global_position` as center, which for the real `Player` scene is
the actual `CharacterBody3D` root, so the same mechanism (whatever it turns out to be) likely
also affects live gameplay idling on ordinary flat ground, not just this comparison harness -
worth confirming with a live playtest before assuming it's cosmetic-only.

## References

- `tests/manual/foot_ik/foot_ik_animation_comparison.gd` - the failing check.
- `actors/player/foot_ik/foot_ik_leg_solver.gd` - `_solve_bend_direction`, `_knee_pole_local` usage.
- [010](010_foot_ik_target_coordinator_consolidation.md) - current active task, unaffected by this.
