# 010: Foot IK target coordinator consolidation

## Status and scope

New. Decided direction from [009](009_foot_ik_architecture_review.md)'s review: route every
Foot IK target owner through `FootIKTargetCoordinator`/`FootIKTargetPlan` with real validation,
so the same safety checks apply regardless of circumstance (idle, landing, stairs, locomotion)
instead of each owner running its own ad-hoc logic. Goal is one enforced boundary, not ten.
Do not commit/push until the user has live-tested each migrated owner, per `AGENTS.md`.

## Current state (from 009's ownership matrix)

`foot_ik_target_coordinator.gd::_build_plan` only sends a plan through real validation
(`_finish_validation`: stance-zone + `_has_support_at` + reach) when **both**:
- `plan.owner` is one of `LIVE_CONTACT`, `IDLE_LOWER_LATCH`, `IDLE_FREEZE` (`migrated_owner`), and
- `coordinate_idle` is true: idle animation, `ground_weight >= 0.95`, flat surface
  (`dot(UP) >= 0.999`), no landing grace/commitment.

Every other owner - `LANDING_COMMITMENT`, `LANDING_UPPER`, `IDLE_LOWER_ACQUIRE`,
`IDLE_STANCE_REHOME`, `STAIR_SUPPORT`, `STAIR_SWING`, `LOCOMOTION_LOCK`,
`LOCOMOTION_STANCE` - takes the pass-through branch: `stance_valid = true`,
`support_valid = plan.valid`, `reach_valid = true`. No independent check at all. There is also
a de facto 11th owner (the "split-safe-zone" block in `foot_ik_ground_sampler.gd`, ~L850-915)
that mutates `smoothed_target`/`idle_lower_latched_target` without ever constructing a plan,
despite `FootIKTargetPlan.Owner.SPLIT_RECOVERY` existing in the enum for it.

`_finish_validation` itself is ankle-only right now: `_has_support_at` is a single raycast at
the ankle's surface point, and nothing checks the toe/leaf's forward reach. That gap is what
left the right-foot clip in 008 unfixed - `_has_lower_riser_clearance`'s finer check lives in
the ground sampler, not the coordinator, and failing it doesn't reliably stop a latch reaching
the solver as `valid=true` (confirmed live in 008's session).

## Why not big-bang this

008's own history: an earlier attempt to extend this exact validation path caused a 0.46m
landing jump. This session's narrower attempt (fixing one ground-sampler function's silent
fallback) fixed the target clip but broke a different, already-passing corner-safety case
(`idle_both_lower_legs_clear_platform_corner_live_repro`, margin 0.036m vs 0.040m minimum).
The lesson from both: this system has ~9 separately-tuned live-repro acceptance cases sharing
implicit assumptions about exactly how "unsafe" targets get handled. Migrate and validate one
owner at a time, full exhaustive suite after each, not one change trying to cover all 8
remaining owners plus the toe/leaf gap at once.

## Step 1 progress: toe/leaf-envelope validation (uncommitted)

Added `FootIKTargetPlan.toe_valid` and `FootIKTargetCoordinator._toe_envelope_valid()`
(checks the farther of the toe+margin or leaf-bone reach against a raycast, rejecting when
it lands on a surface more than `SUPPORT_HEIGHT_TOLERANCE` above the ankle's own surface -
i.e. poking into the next riser), wired into `_finish_validation` for the 3 already-migrated
owners.

Result:
- Fixes the exact right-foot clip from 008 (verified against the live settle-then-rotate
  repro: 0 clip events, was clipping every settled frame).
- `FOOT_IK_LEDGE_SAFETY_CHECK` now **passes** (was the case this session's earlier
  ground-sampler-only fix broke).
- Full fast suite otherwise clean except one pre-existing failure:
  `foot_ik_idle_plant_stability_check.tscn`'s `live_pose` sub-case was already failing before
  this change (`live_pose_joint_step_m=0.048942` vs limit `0.045`, baseline confirmed via
  `git stash`). With this change active, the same sub-case fails harder:
  `live_pose_joint_step_m=0.358452` at `right:hip`, traced to `_toe_envelope_valid` rejecting
  the injected `LIVE_POSE_RIGHT_TARGET` for ~7 consecutive physics frames mid-rotation
  (frames 1404-1410 of that scene), because the toe genuinely sweeps near real nearby
  geometry at that yaw. The check's classification is correct; the problem is what happens
  next - the coordinator's raw-recovery fallback snaps to a different candidate the instant a
  plan flips invalid, so a brief few-frame toe-envelope flicker becomes a visible pop instead
  of a held pose. No hysteresis/grace period exists for this rejection path (other owners in
  this codebase use streak counters or a grace window for exactly this reason - see
  `min_falling_streak`, `_landing_grace_time`).
- Fixed by adding `TOE_INVALID_HOLD_FRAMES` (10) debounce: the toe check must fail for 10
  consecutive frames before actually invalidating a plan, absorbing the brief mid-turn sweep
  without weakening the original fix (that clip was sustained for hundreds of frames, not a
  brief one). Applied only to the primary per-owner check (`_finish_validation`'s default
  `debounce_toe=true`); `_raw_recovery_plan`'s own call passes `debounce_toe=false` since it's
  already a fallback attempt on a different (raw) candidate and must not share/mutate the
  primary streak. After tuning: `foot_ik_idle_plant_stability_check` is back to its exact
  pre-existing baseline (`live_pose_joint_step_m=0.048942` at `340:right:foot`,
  `turn_step_m=0.056851`) - not fixed (it was already failing before this session), but not
  made worse either.
- Full fast-suite status after this fix: every check passes except the pre-existing
  `foot_ik_idle_plant_stability_check` failure (unchanged from before this task started).
  `foot_ik_idle_support_owner_check.tscn` and `foot_ik_toe_riser_check.tscn` (which
  `check_foot_ik_fast.sh` never reaches once an earlier scene fails) were run directly and
  both pass unchanged.

## Step 1, round 2: point-based check + raw-recovery exemption (verified against the full suite)

Once `check_foot_ik.sh`'s silent-exit bug was fixed (see "Exhaustive suite health" below), a
full run found a second regression the fast suite missed: `foot_ik_knee_flex_check.tscn`'s
"mirrored upper-leg deformation" case (`start=8.758182,0.600149,4.085211 yaw=73.7044620505809
time=1.86666666666666`) went from PASS to FAIL (0.512m sole clearance, 0.519m one-frame joint
pop). Isolated via `git stash` bisection: caused by the toe-envelope check, not 011's pelvis fix.

Root cause: `_toe_envelope_valid`'s raycast-down-from-above approach treated any surface higher
than the ankle's own surface as an obstruction - correct for 008's riser clip (solid ground
extending down), wrong for a split-height stance where a foot's toe legitimately reaches back
under the body toward a *different*, real, higher platform with open space beneath it. The
check never verified the toe's own actual position against real geometry, only inferred
clipping from a blind column raycast. Replaced with a direct
`PhysicsDirectSpaceState3D.intersect_point` test at the toe's candidate 3D position
(`ankle_target + tip_offset`) - the same precise technique already used to confirm the original
clip.

That alone didn't fix the case: instrumentation showed the toe genuinely is inside solid
geometry there for *both* the primary `IDLE_LOWER_LATCH` candidate and the `LIVE_CONTACT`
raw-recovery fallback - rejecting both left the leg with no target at all (full release to raw
animation, which floats badly on the split-height surface). Fixed by exempting the raw-recovery
plan from the toe check entirely (`_finish_validation`'s `check_toe` parameter) - a fallback
vetoed by the same check that rejected the primary defeats its own purpose.

Verified: the mirrored-upper-leg case now passes, the original 008 clip stays fixed, the fast
suite is unchanged, and a full `check_foot_ik.sh` run now matches the pre-existing baseline
exactly except `FOOT_IK_ANIMATION_COMPARISON_CHECK` (011's fix, PASS instead of FAIL) - no other
regressions found across ~40 checks. Not yet run: `check_foot_ik_ramps.sh` (separate from
`check_foot_ik.sh`) or a live playtest - required before this is committable per `AGENTS.md`.

## Exhaustive suite health (found while investigating "is the suite slow")

`scripts/check_foot_ik.sh` and `scripts/check_foot_ik_stair_repeat.sh` had a systemic bug:
every bare `godot ... >"$log_file" 2>&1` line (33 in the former) was not guarded against a
nonzero process exit, so `set -e` killed the whole script silently the instant any one check
failed - before its own `cat "$log_file"; exit 1` diagnostic block ever ran. Fixed by
appending `|| true` to all of them (both files) so the intended log-content-based pass/fail
logic actually executes. This is why nobody has seen this suite's real status recently -
008's Sept 5 "38 seconds... FAIL" note was this exact silent-exit, not a real 38-second
result.

With the fix, the suite is not fundamentally slow (12 checks including full project
import completed in 56s) - it was hiding a backlog of **pre-existing failures**, at least two
found so far, both confirmed via `git stash` to predate this session:
- `FOOT_IK_ANIMATION_COMPARISON_CHECK` (flat-ground idle pose divergence) - parked as
  [011](011_foot_ik_flat_idle_pose_divergence.md).
- `FOOT_IK_KNEE_FLEX_CHECK`'s default case: "left sole clearance 0.123m (limit 0.080m)" on a
  split-height idle/landing pose - not yet investigated.

Full suite completion (past both of these) has not been measured yet. Neither failure is
caused by this task's toe-envelope coordinator change (confirmed via baseline comparison).

## Step 2 attempted and reverted: migrating IDLE_LOWER_ACQUIRE and IDLE_STANCE_REHOME

Tried expanding `migrated_owner` to include these two (closest siblings of the already-safe
`IDLE_LOWER_LATCH`). Result: fixed a pre-existing failure
(`FOOT_IK_KNEE_FLEX_CHECK`'s default case, sole clearance 0.123m -> 0.029m, under the
0.080m limit) but caused a new regression - `FOOT_IK_LEDGE_SAFETY_CHECK`'s
`idle_split_height_turn_pause_no_leg_snap_live_repro` (a case named specifically to catch leg
pops) now snaps the rendered foot 0.528m at frame 82 (limit 0.150m). Reverted to the 3-owner
scope (`LIVE_CONTACT`, `IDLE_LOWER_LATCH`, `IDLE_FREEZE`); confirmed via the fast suite that
this returns to the exact same baseline as after step 1 (only the pre-existing
`foot_ik_idle_plant_stability_check` failure remains, unchanged).

## Step 2, isolated: IDLE_STANCE_REHOME migrated, IDLE_LOWER_ACQUIRE deferred

Bisected by migrating each owner alone: `IDLE_LOWER_ACQUIRE` alone reproduces the exact same
leg-snap regression (0.518m); `IDLE_STANCE_REHOME` alone is clean (matches the safe baseline
exactly, confirmed against the fast suite plus `foot_ik_idle_support_owner_check.tscn` and
`foot_ik_toe_riser_check.tscn` directly). `IDLE_STANCE_REHOME` is now migrated
(`migrated_owner` + `owner_is_lower_transition` in `_build_plan`).

Root cause for `IDLE_LOWER_ACQUIRE` (confirmed via direct instrumentation, not guessed):
`_has_support_at` checks whether real ground exists exactly at `plan.surface_target` - correct
for `IDLE_LOWER_LATCH`/`LIVE_CONTACT`, whose surface is a settled, raycast-confirmed point. For
`IDLE_LOWER_ACQUIRE`, `surface_target` is a `move_toward`-interpolated waypoint between the
previous and the acquire destination (see `_update_idle_lower_transition` in
`foot_ik_ground_sampler.gd`) - mid-transition, that interpolated 3D point does not necessarily
correspond to any real ground height at its XZ, so `_has_support_at` can legitimately report
`unsupported` even while the transition is correctly heading toward a valid destination
(confirmed live: `reason=unsupported support=false` while `stance=true reach=true toe=true`,
9 occurrences in `foot_ik_ledge_safety_check.tscn`'s repro).

Applied that fix (`_finish_validation` now checks `idle_lower_acquiring[side]` for
`IDLE_LOWER_ACQUIRE`'s support test) and re-added the owner. It closed the leg-snap regression
(`FOOT_IK_LEDGE_SAFETY_CHECK` back to `cases=16 PASS`) - but a full exhaustive run then found a
**second, different** regression from the same owner: `FOOT_IK_POSE_CONTINUITY_CHECK` jumped
from `max_jump_m=0.0125` to `0.0402` (limit `0.025`), confirmed via direct reproduction
(`foot_ik_preview.tscn -- --foot-ik-check`).

Two distinct regressions in a row from the same owner is the signal to stop patching symptoms
one at a time (per this session's own debugging discipline) rather than attempt a third fix
blind. Reverted `IDLE_LOWER_ACQUIRE` from `migrated_owner` again; kept the support-target fix
in `_finish_validation` (still correct, just unreachable until this owner is re-added).
`IDLE_LOWER_ACQUIRE` needs a more fundamental look before the next attempt: it is fundamentally
a *moving* target validated every frame with a binary accept/reject model built for settled
surfaces - this may need validating once at acquisition start and trusting the interpolation
through completion, rather than re-validating the in-flight waypoint every frame.

## Process failure: IDLE_STANCE_REHOME's migration was itself the POSE_CONTINUITY cause

What I initially attributed to `IDLE_LOWER_ACQUIRE` above was wrong. After reverting
`IDLE_LOWER_ACQUIRE` and separately attempting `LANDING_COMMITMENT` (see below), the same
`FOOT_IK_POSE_CONTINUITY_CHECK` failure (`max_jump_m=0.040223`, identical value both times)
persisted even with *both* of those reverted - proving it was neither. Bisected with `git
checkout <commit> -- <files>` against the actual git history: PASS at `ed8061b` (toe-envelope +
011 fix only), FAIL at `498d818` (adds only `IDLE_STANCE_REHOME`). **`IDLE_STANCE_REHOME`'s
migration - already committed and pushed in `498d818` - was the real cause all along.**

Root process failure: `498d818` was verified with the fast suite plus two directly-run scenes,
matching this session's earlier pattern for safe changes - but was never checked against the
full exhaustive suite before committing, unlike every other change in this task. The fast suite
does not run `--foot-ik-check`'s pose-continuity sub-check as part of its early exit path the
same way the full suite's sequencing does; whatever specific animation transition
`FOOT_IK_POSE_CONTINUITY_CHECK` exercises was never touched by any of the individually-verified
fast-suite scenes. Reverted `IDLE_STANCE_REHOME` from `migrated_owner` (back to the exact
`ed8061b` scope: `LIVE_CONTACT`, `IDLE_LOWER_LATCH`, `IDLE_FREEZE`) and confirmed via a full
`bash /tmp/...run_all` pass: every result now shows exactly once (no duplicate-print
artifacts from an early exit) and matches the known pre-existing failure set exactly - this is
the actual clean baseline.

**Lesson for every future owner migration in this task**: verify a new migration against the
full exhaustive suite (`check_foot_ik.sh` at minimum) before committing, not just the fast
suite - a change that looks clean on the fast suite can still regress a check the fast suite
never reaches or never fully exercises. This was already the intent of "Migrate ... one owner
at a time" above; the miss was skipping the *exhaustive* verification step for one commit, not
the one-at-a-time discipline itself.

## LANDING_COMMITMENT re-attempted fresh, verified, and safe

Re-added `LANDING_COMMITMENT` with its purpose-built parallel gate (`coordinate_landing`,
since it structurally fails `coordinate_idle`'s `landing_committed_target.is_empty()` check by
definition) reusing `_committed_landing_hit`'s already-reconfirmed support - this time verified
against the full exhaustive suite *before* committing, per the lesson above. Result: every
check matches the confirmed clean baseline exactly (fast suite, both directly-run scenes, and a
full `check_foot_ik.sh`-equivalent pass all show the same pre-existing failure set with nothing
new). `FOOT_IK_POSE_CONTINUITY_CHECK` in particular - the exact check `IDLE_STANCE_REHOME`
regressed - stays at `max_jump_m=0.012522`, confirming the earlier failure really was
`IDLE_STANCE_REHOME` alone, not an interaction with `LANDING_COMMITMENT`.

## LANDING_UPPER migrated - no special gate needed

Unlike `LANDING_COMMITMENT`, `coordinate_idle` does not structurally exclude `LANDING_UPPER`
(nothing in it checks `landing_upper_confirmed`), and its surface is likewise a freshly
reconfirmed real ground contact (`LANDING_UPPER_CONFIRM_FRAMES=4` consecutive agreeing frames
in `foot_ik_ground_sampler.gd`, not an in-flight interpolation like `IDLE_LOWER_ACQUIRE`). Added
directly to `migrated_owner` with no new gate. Verified against the full exhaustive suite
before committing (per the process lesson above): exact match to the confirmed clean baseline,
including `FOOT_IK_POSE_CONTINUITY_CHECK` at `max_jump_m=0.012522`.

## IDLE_LOWER_ACQUIRE re-attempted fresh, verified, and safe - the earlier regression was IDLE_STANCE_REHOME, not this owner

Re-added `IDLE_LOWER_ACQUIRE` with its destination-based support fix (already in
`_finish_validation` since the earlier attempt, just unreachable while the owner was reverted)
and verified against the full exhaustive suite *before* committing. Result: exact match to the
confirmed clean baseline, including `FOOT_IK_POSE_CONTINUITY_CHECK` at `max_jump_m=0.012522` -
the same check this owner was earlier blamed for regressing.

This confirms what the "Process failure" section above worked out after the fact: that
regression was `IDLE_STANCE_REHOME` (migrated at the same time in the original attempt), not
`IDLE_LOWER_ACQUIRE`. The destination-based support fix was correct all along; it just never
got a clean, isolated re-verification until now.

## IDLE_STANCE_REHOME re-attempted with its actual root cause fixed - verified and safe

Root-caused (rather than leaving deferred) why `IDLE_STANCE_REHOME` failed
`FOOT_IK_POSE_CONTINUITY_CHECK` the first time: `_rehome_idle_stance_target` in
`foot_ik_ground_sampler.gd` only ever activates when the existing smoothed target is *already*
outside the stance zone (its own early-out: `if delta <= 0.0 or not current.is_finite() or
is_target_inside_stance_zone(side, current): return false`). That means this owner's
`surface_target` is outside the stance zone by definition, every single time it is active -
structurally incompatible with `_finish_validation`'s `require_stance=true`, which was
rejecting every rehome candidate on its first frame and forcing a fallback jump. Confirmed via
a temporary debug print showing `reason=outside_stance stance=false` on every sample before the
fix.

Fix: `_build_plan` now passes `require_stance := plan.owner !=
FootIKTargetPlan.Owner.IDLE_STANCE_REHOME` into `_finish_validation` instead of a hardcoded
`true` - support/reach/toe checks still apply, only the stance-zone check is skipped for this
owner, since correcting an out-of-zone target is exactly its job.

Verified against the full exhaustive suite before committing (per the process lesson above):
`FOOT_IK_POSE_CONTINUITY_CHECK PASS samples=448 max_jump_m=0.012522` (was `FAIL` at `0.040223`
under the old hardcoded-`true` migration), and every other check matches the confirmed
pre-existing baseline failure set exactly (`FOOT_IK_IDLE_PLANT_STABILITY_CHECK`, 5x
`FOOT_IK_KNEE_FLEX_CHECK`, `FOOT_IK_LOCOMOTION_CHECK` `walk_left`/`walk_right`,
`FOOT_IK_WALK_IDLE_STANCE_CHECK`) with nothing new. `IDLE_STANCE_REHOME` is migrated for real
this time, bringing the coordinator migration to 8 of 10 target owners (`STAIR_SUPPORT`,
`STAIR_SWING`, `LOCOMOTION_LOCK`, `LOCOMOTION_STANCE` remain, scoped separately above as a
riskier follow-up pass; `SPLIT_RECOVERY` still has no `FootIKTargetPlan` at all).

Current scope: 7 owners migrated (`LIVE_CONTACT`, `IDLE_LOWER_LATCH`, `IDLE_LOWER_ACQUIRE`,
`LANDING_COMMITMENT`, `LANDING_UPPER`, `IDLE_FREEZE`, plus toe-envelope validation on all of
them). `IDLE_STANCE_REHOME` remains deferred - its actual root cause was never isolated (only
detected and reverted); worth a fresh, properly-instrumented attempt rather than assuming it's
unsafe forever. Remaining unattempted: `STAIR_SUPPORT`, `STAIR_SWING`, `LOCOMOTION_LOCK`,
`LOCOMOTION_STANCE` - scoped as their own dedicated pass in the section below.

## SPLIT_RECOVERY given a real owner label (proposed order step 3, partial)

`FootIKTargetPlan.Owner.SPLIT_RECOVERY` already existed in the enum but `_legacy_owner()` never
assigned it, so whenever `prepare_overheight_split_safe_zone` (in `foot_ik_ground_sampler.gd`)
placed a leg's target directly - bypassing the plan system entirely, writing `leg["target"]`,
`smoothed_target`, etc. straight from the split-safe-zone recovery logic - the coordinator
mislabeled that leg as plain `LIVE_CONTACT` in `_legacy_owner()`. Confirmed this was
label-only, not a live bug: `SPLIT_RECOVERY` is not in `migrated_owner`, so the mislabeled plan
already took the pass-through branch (`stance_valid = true`, `support_valid = plan.valid`,
`reach_valid = true`, no rejection/override logic runs) - identical to what a correctly-labeled
but still-unmigrated `SPLIT_RECOVERY` plan would do. The only consumers of `plan.owner` are
`foot_ik_trace_writer.gd` (diagnostics) and one exact-owner check in
`foot_ik_idle_plant_stability_check.gd` gated on `IDLE_LOWER_LATCH` for the right leg, which was
already false whenever split-recovery holds a side (that path erases
`idle_lower_latched_target` for held sides) - so this is a pure visibility fix with no
behavior change.

Fix: added `elif sampler.split_safe_held_upper_target.has(side): result =
FootIKTargetPlan.Owner.SPLIT_RECOVERY` to `_legacy_owner()`, placed after the landing checks
(preserving existing precedence - split-safe-zone can theoretically run alongside landing
state and previously-checked owners must keep winning) and before the idle-lower checks.

Verified against the full exhaustive suite before committing: output is byte-for-byte
identical to the confirmed clean baseline (empty diff on the per-check PASS/FAIL/count
summary), including `FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=16` and
`FOOT_IK_SPLIT_STANCE_WALK_CHECK PASS` - the two checks that actually exercise this code path -
and `FOOT_IK_POSE_CONTINUITY_CHECK PASS max_jump_m=0.012522` unchanged.

This is only the labeling half of proposed-order step 3 ("define a real plan for
SPLIT_RECOVERY"). `prepare_overheight_split_safe_zone` still mutates `smoothed_target`/`leg`
directly rather than producing a `FootIKTargetPlan` the coordinator validates, and is not yet
in `migrated_owner` - actually validating it (deciding what "valid" means for a target chosen
by a 4-corner-raycast safe-zone search rather than a single-point raycast) is follow-up work,
not attempted here to keep this change reviewable and low-risk on its own.

## SPLIT_RECOVERY migrated for real - added to migrated_owner

Added `SPLIT_RECOVERY` to `migrated_owner` and to the `require_stance` exclusion (alongside
`IDLE_STANCE_REHOME`): `prepare_overheight_split_safe_zone` holds a foot at a fixed world point
while nudging the root toward `split_safe_root_target` (`preferred_root_nudge`), so the held
foot can legitimately drift outside the per-side stance zone mid-nudge - same shape of conflict
`IDLE_STANCE_REHOME` has with its own stance-zone check. Support/reach/toe checks still apply.

Two things made this safer than a typical new owner: (1) `prepare_overheight_split_safe_zone`
already writes into the exact same `smoothed_target`/`leg["target"]` fields the coordinator
reads for every other owner (unlike the stair predictor's continuous-transfer state), so
`_build_plan` picks up the real held surface/ankle target with no extra plumbing; (2) it
re-asserts its cached held target unconditionally every frame it runs, before the coordinator
even runs - so a single frame where the coordinator's own reconfirmation disagreed and
substituted raw recovery would just get overwritten back the next frame, bounding the
blast radius of any disagreement to a one-frame flicker rather than a stuck bad state.

Verified against the full exhaustive suite before committing: byte-for-byte identical to the
labeling-only baseline above, including `FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=16` and
`FOOT_IK_SPLIT_STANCE_WALK_CHECK PASS` (the two checks exercising this path) and
`FOOT_IK_POSE_CONTINUITY_CHECK` unchanged at `max_jump_m=0.012522` - no flicker observed in
either check across their full run. Brings the coordinator migration to 9 owners (all except
`STAIR_SUPPORT`/`STAIR_SWING`/`LOCOMOTION_LOCK`/`LOCOMOTION_STANCE`, still scoped separately
below as the project's riskiest remaining piece).

## Step 5 scoping: STAIR_SUPPORT/STAIR_SWING/LOCOMOTION_LOCK/LOCOMOTION_STANCE - not started

Investigated before attempting, given every owner migrated so far needed its own individual
understanding and this group is architecturally the most different yet. Findings:

- `resolve_stationary` (`player_foot_ik_modifier.gd`, ~L890-893) runs unconditionally every
  frame regardless of animation, so `_legacy_owner()` already labels these owners today (009's
  "labels the winner but doesn't validate" finding, confirmed in code) - but `stationary` is
  only true for `unarmed_idle`/`unarmed_torch_idle`/`unarmed_crouch_idle`, and `coordinate_idle`
  requires `stationary` as its first condition. During stair walking or general locomotion,
  `coordinate_idle` is unconditionally false, and no other gate currently covers these four
  owners - simply adding them to `migrated_owner` under the existing gates would be a silent
  no-op, never actually validated, exactly like `LANDING_COMMITMENT` needed its own
  `coordinate_landing` gate rather than reusing `coordinate_idle`.
- Unlike `LANDING_COMMITMENT`/`LANDING_UPPER` (both settled, independently reconfirmed
  surfaces - `_committed_landing_hit` and the 4-frame upper-confirm loop each do their own
  raycast agreement check before the owner is ever reported), `STAIR_SUPPORT`'s target comes
  from `foot_ik_stair_predictor.gd`'s `_choose_support_side`/`_latch_support_target` - part of
  an actively continuous support-transfer state machine that runs every frame during dynamic
  stair locomotion, tightly coupled to shared pelvis drop (`ensure_support`) and swing
  prediction (`LegState.swing_active`, `_try_transfer_support`). There is no single settled
  moment to validate against; the "target" is continuously re-chosen and re-latched as the
  character climbs, by design.
- This is also the area with the most documented fragility already: 009's ownership review
  flagged `foot_ik_stair_predictor.gd` as explicitly self-documented "TEMPORARY /
  EXPERIMENTAL... not an assertion that its visible stair gait is production-ready", and 008's
  own history includes fixes to support-latch drift and swing-lift/pelvis-sink interaction in
  this exact code.

Given the pattern this session established - even structurally similar-looking owners
(`IDLE_LOWER_ACQUIRE` vs. the safe `IDLE_LOWER_LATCH`/`IDLE_STANCE_REHOME`) produced two
distinct regressions each - migrating four owners that don't even produce a plan yet, in code
already flagged as the project's most fragile, is a materially bigger and riskier step than
anything attempted so far. Recommend treating it as its own dedicated pass: first define what
"valid" should mean for a continuously-transferring support target (likely: confirm the
*current* chosen support foot's contact is real, not that some fixed point remains valid
across the whole climb), before writing any gate, rather than reusing the landing-owner
pattern by analogy.

## LOCOMOTION_LOCK/LOCOMOTION_STANCE migrated (option 2 implemented)

Implemented direction (2) from the design finding below. Turned out simpler than expected:
`_finish_validation`'s existing `support_valid` check (`_has_support_at` - a fresh raycast
confirming real, flat ground within height tolerance at the target) is already exactly the
stance-agnostic "is this actually real ground" reconfirmation direction (2) called for; it
makes no idle-specific assumption at all. The only piece actually missing was a gate, since
`coordinate_idle` structurally can never be true for these owners (requires `stationary`).

Added a parallel `coordinate_locomotion` gate (mirrors `coordinate_idle`'s landing-grace/
plant-weight/flat-normal conditions, without the `stationary`/animation-name requirement, since
`_legacy_owner()` only ever reports these two owners while
`foot_ik_gait_tracker.gd` has already confirmed the body is translating). Added both owners to
`migrated_owner` and to the `require_stance := false` exemption list alongside
`IDLE_STANCE_REHOME`/`SPLIT_RECOVERY`, for the same reason given in the design finding: the
idle-sized stance zone would reject legitimate mid-stride targets outright. No new check
function was needed - `support_valid`/`reach_valid`/`toe_valid` from the existing
`_finish_validation` path cover it once `stance_valid` is exempted.

**Verified**: full exhaustive suite (`/tmp/check_foot_ik_run_all2.sh`-equivalent continue-past-
failures run) produces byte-for-byte the same failure set as the pre-change baseline
(`FOOT_IK_KNEE_FLEX_CHECK` x5, `FOOT_IK_LOCOMOTION_CHECK` x2, `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`,
`FOOT_IK_RAMP_LOCOMOTION_CHECK`, `FOOT_IK_WALK_IDLE_STANCE_CHECK` - all pre-existing, all
unchanged). No regression detected by automated coverage, including
`FOOT_IK_STAIR_LOCOMOTION_CHECK` and `FOOT_IK_LOCOMOTION_CHECK`'s walk/run cases, which
exercise the exact `LOCOMOTION_LOCK`/`LOCOMOTION_STANCE` code paths this change touches.

**Live manual confirmation: done.** User walked/ran the character in-editor after this change
and confirmed it "seems to be working fine" - no reported foot-skating, snapping, or floating.
Coordinator migration is now 11 of 12 owners; `STAIR_SUPPORT`/`STAIR_SWING` remain, per the
caution above - this only covers ordinary flat-ground walk/run stance, not stair climbing.

## See also: architecture direction (015)

[015](015_foot_ik_architecture_direction.md) records an outside architectural assessment of
the whole Foot IK system, largely corroborating this task's own findings from an outside
angle: the coordinator is not actually the final authority (the modifier can still change a
target after validation - lateral-shift re-centering, slope-target adjustment, seam-freeze
substitution), and the remaining `STAIR_SUPPORT`/`STAIR_SWING` migration below is exactly where
that concern lives (a continuously-transferring target mutated outside the plan system
entirely). Read 015 before designing that migration's gate.

## Locomotion-owner design finding (later session, no code changed)

Followed the "dedicated pass" recommendation above by looking closer at all four remaining
owners before writing any gate, per its own advice. Two concrete findings:

**`LOCOMOTION_LOCK`/`LOCOMOTION_STANCE` are structurally simpler than `STAIR_SUPPORT`/
`STAIR_SWING` and should likely migrate *first*, not last as currently ordered.**
`foot_ik_gait_tracker.gd`'s `_update_locomotion_stance`/`target_lock_allows_latch` implement
almost exactly the same shape as the already-migrated `IDLE_LOWER_LATCH`: "this foot is
currently planted and should hold its real ground contact instead of skating with the moving
body," just gated on `_body_horizontal_speed() > IDLE_TRANSLATION_EPSILON` instead of idle
stillness. There is no continuous-transfer state machine here, unlike `STAIR_SUPPORT`'s
`_choose_support_side`/`_latch_support_target` (part of `foot_ik_stair_predictor.gd`'s
actively-transferring support state, which 009/010 already flagged as the project's most
fragile Foot IK code and which this task correctly recommends *not* rushing).

**The blocker for `LOCOMOTION_LOCK`/`LOCOMOTION_STANCE` even so: neither `coordinate_idle` nor
its stance-zone check (`is_target_inside_stance_zone`) can be reused as-is.** `coordinate_idle`
requires `stationary` (only true for idle animations), which by construction excludes every
locomotion owner - adding them to `migrated_owner` under the existing gate is the exact silent
no-op already identified for the other two owners. A parallel `coordinate_locomotion` gate is
needed. More importantly, `is_target_inside_stance_zone`'s tolerances
(`STANCE_ZONE_MAX_LONGITUDINAL` etc.) are sized for an idle foot sitting nearly directly
under/beside the root - a real walking stride plants the stance foot meaningfully ahead of or
behind the root at different points in the gait cycle, well outside that zone. Reusing the
existing check unmodified would very likely reject legitimate mid-stride stance targets outright
(rejecting exactly what it's supposed to validate), not merely be a no-op like the wrong-gate
mistake would be. This needs one of:

1. A separate, locomotion-sized stance-zone tolerance (wider longitudinal bound, tuned against
   live walk/run/sprint footage - not a number to guess from code alone), or
2. A stance-agnostic validation for these two owners instead of a zone check: reconfirm the
   *current* foot position's ground contact is real (a fresh raycast agreement check, same
   spirit as `LANDING_COMMITMENT`'s `_committed_landing_hit()`), without requiring the target be
   within any fixed zone relative to the root at all.

Direction (2) also generalizes better to `STAIR_SUPPORT` later (matching this doc's own
suggestion above: "confirm the *current* chosen support foot's contact is real, not that some
fixed point remains valid across the whole climb") - the same validation *shape* could end up
serving three of the four remaining owners, differing mainly in which raycast layer/tolerance
applies. Not implemented or tuned this session - it needs live walk/run footage to calibrate,
and per this project's standing rule, gameplay/animation changes are committed only after the
user's own manual confirmation, not automated checks alone. Recommend this becomes the actual
first step of the "dedicated pass," ahead of writing any gate.

## Proposed order (safest/highest-value first)

1. **Add toe/leaf-envelope validation to `_finish_validation`**, scoped only to the 3
   already-migrated owners first (no new owners yet). This directly targets the still-open
   right-foot clip, but now as a coordinator-level check that every future owner will
   automatically inherit, instead of one more ad-hoc function in the ground sampler. Run the
   full exhaustive suite (`check.sh`, `check_foot_ik.sh`, `check_foot_ik_locomotion.sh`,
   `check_foot_ik_ramps.sh`, `check_foot_ik_ramp_sweep.sh`) plus a live-tested repro at the
   exact clip location from 008 before calling this step done.
2. **Migrate `IDLE_LOWER_ACQUIRE` and `IDLE_STANCE_REHOME`** into `migrated_owner` next -
   they're the closest siblings of the already-migrated `IDLE_LOWER_LATCH`, sharing most of
   its validation shape. Re-run the full suite after.
3. **Define a real plan for `SPLIT_RECOVERY`** (the split-safe-zone block) so it stops
   mutating shared state outside the plan system entirely.
4. **Migrate `LANDING_COMMITMENT` and `LANDING_UPPER`** - higher risk, since landing already
   has its own two-tier commitment (`FootIKLandingPlanner` + `landing_committed_target`) that
   must keep working across the grounded/ungrounded snapshot/restore path. This is the pairing
   most likely to resemble the 0.46m landing-jump regression's original conditions - extra
   care and explicit live confirmation before merging.
5. **Migrate `STAIR_SUPPORT`/`STAIR_SWING`**, then `LOCOMOTION_LOCK`/`LOCOMOTION_STANCE` last -
   these currently write `smoothed_target` directly from `foot_ik_stair_predictor.gd`/
   `foot_ik_gait_tracker.gd` rather than through a plan at all, so this is more than adding a
   validation gate; it's the first time these owners produce a `FootIKTargetPlan` in the first
   place.
6. Once every owner is migrated and validated, retire the now-redundant ad-hoc checks it
   replaces (`_has_lower_riser_clearance`'s role folds into the coordinator's toe/leaf check,
   etc.) so there is exactly one enforcement point left, per 009's stated goal.

## `foot_ik_idle_plant_stability_check`'s coordinator-generations failure, traced (not fixed)

`_coordinator_generations.size() <= 3` has been failing (currently `5`) throughout this
session, blocking `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`'s overall pass even after 013's
`live_pose_joint_step_m`/acquire-speed fixes landed. Traced it by dumping every new
`plan.generation`'s owner/reason (via `_store_plan`'s own bump rule: a new generation each time
`owner` or `reason` changes) across the check's 240-frame, ~90-degree body-turn phase (left leg
holding a forced-stale target, expected to recover once and then stay stable through the whole
turn): `live_contact/selected_legacy_candidate` (initial) -> `live_contact/
replace_invalid_with_raw_support` (the expected recovery) -> `idle_lower_latched/
validated_lower_support` (settles) -> `idle_lower_acquiring/selected_legacy_candidate` (a
transient extra flip, ~23 degrees into the turn) -> `idle_lower_latched/
validated_lower_support` again (re-settles, permanently, for the remaining ~95% of the turn).

**First hypothesis (stance-zone geometry), disproven.** Suspected the latched target - fixed in
world space - might briefly exit the root-relative stance zone as the body kept rotating.
Instrumented `is_target_inside_stance_zone`'s own lateral/longitudinal values and the `inside`
result at the exact flip: it stays `true` throughout, on both sides of the flip. This is not a
stance-zone rejection.

**Actual cause, confirmed**: the latched target's world position itself changes by a full
`0.32m` in Z (`(11.91627, 0.6, 1.799071)` -> `(11.91627, 0.6, 1.479071)`) at the exact frame of
the flip. That size and direction of change matches `_rehome_lower_surface_from_riser()`'s own
documented purpose ("move a lower plant away when its shin would still cross the riser") in
`foot_ik_ground_sampler.gd`'s `_validate_idle_lower_support`: when the rehomed (`cleared`)
surface differs from the raw raycast surface by more than `TARGET_NOISE_DEADBAND` (`0.01m`),
the function deliberately erases the latch and re-enters `idle_lower_acquiring` targeting the
surface, rather than smoothly nudging the existing latched target toward the cleared one. Since
the character keeps rotating throughout this phase, the geometry relative to nearby risers
continuously changes, and at some point crosses the threshold where the riser-clearance check's
answer changes - triggering exactly one such re-acquire-then-relatch cycle. This is a real,
working safety mechanism (preventing a shin from visibly crossing into riser geometry) doing
its job correctly, just producing more `plan.generation` bumps than this specific check's
`<= 3` assumption expected for a real, continuous 90-degree turn.

**Not fixed - genuinely unclear whether it should be.** Two directions, both real work, neither
attempted:
1. Loosen the check's generations threshold (this is check calibration, the same shape as
   013's acquire-speed finding - a real, working mechanism whose natural frequency the check's
   assumption didn't originally account for).
2. Change `_rehome_lower_surface_from_riser`'s erase-and-reacquire response to a continuous
   nudge instead, so a shin-clearance correction doesn't need a full ownership-generation flip
   at all - directly relevant to 015's point 1/2 concerns (the coordinator's plan getting
   silently superseded by a downstream module's own state changes), but real behavioral surgery
   on a documented, currently-working safety mechanism, not something to attempt speculatively
   without the user's steer on direction and without a live in-editor confirmation afterward.

**Fixed (user chose direction 2, "now that we are fresh with this").**
`_validate_idle_lower_support` (`foot_ik_ground_sampler.gd`): when the riser-clearance check
finds the cleared surface differs from the raw one, an already-latched foot
(`had_latch == true`) now stays in `IDLE_LOWER_LATCH` - updating `idle_lower_latched_target`
directly and nudging `smoothed_target` toward it via the existing `move_toward` call - instead
of erasing the latch and re-entering `IDLE_LOWER_ACQUIRE`. A foot with no existing latch still
goes through the ordinary acquire flow unchanged, since there's no existing plant to preserve
continuity with.

Checked before changing: the only place that reads the acquire-vs-latch distinction downstream
(`player_foot_ik_modifier.gd`'s classification gate) already treats both states identically
(`if (contact.get("idle_lower_latched", false)) or _ground_sampler.idle_lower_acquiring.has(side))
-> classification = {"plant": true, "settle": false}`), and the acquire-path's
`invalidate_idle_freeze()` side effect only matters for a different resampling path this
riser-nudge case already bypasses regardless of freeze state - so skipping it changes nothing
observable elsewhere.

**Verified**: `foot_ik_idle_plant_stability_check` (whose `_coordinator_generations.size() <= 3`
failure this fix directly targets) now fully **passes** - `generations=3` (was `5`) - the first
time this specific check has passed all session. Full comprehensive suite
(`scripts/check_foot_ik_all.sh`) re-run clean: exit 0, one *fewer* known-baseline failure than
before (`Foot IK stationary planted-foot stability check` moved from known-failing to passing),
no new/unexpected failures anywhere else. `KNOWN_BASELINE_FAILURES` updated to remove it.

**Live confirmation: done.** User tested in-editor; reported the difference was too subtle to
see clearly either way ("hard to see too much diff") - no regression or visible problem
reported. Consistent with the fix's own nature (smoothing an already-narrow, one-time riser
nudge into an even less noticeable continuous motion) rather than a change expected to be
visually obvious.

## Regression contract

Every step must keep passing (or knowingly update, with the user's live confirmation) the
full acceptance surface 009 catalogued for this area: `foot_ik_idle_plant_stability_check.gd`'s
9 hardcoded live-position scenarios, `foot_ik_ledge_safety_check.gd`'s corner cases,
`foot_ik_toe_riser_check.gd`, `foot_ik_idle_support_owner_check.gd`, plus the fast/exhaustive
suites in `AGENTS.md`. A step that requires loosening one of these numeric limits needs the
user's explicit sign-off, not a quiet widening.

## STAIR_SUPPORT/STAIR_SWING validation design proposal (later session, no code changed)

Read `ensure_support`/`_try_transfer_support`/`_latch_support_target`/`_apply_support_contact`
(`foot_ik_stair_predictor.gd`) in full before writing anything, per this task's own standing
caution. Every one of these functions carries an inline comment documenting a specific,
previously-shipped-then-reverted regression from an earlier "reasonable-looking" fix attempt
(a stale-target pelvis-sink drag, a ~20cm-per-climb-frame target-height drift, a support-swap
pelvis/foot pop, an idle stair-edge toe clip, a solve-weight/chain-weight desync) - this
confirms the fragility already flagged is real and specific, not a vague caution.

**Structural finding**: `_apply_support_pelvis_and_legs` calls `_stair_predictor.ensure_support`
*before* `_target_coordinator.resolve_stationary` each frame, and `ensure_support` (via
`_apply_support_contact`) already writes `per_leg[side]["target"]`/`["ground_target"]` directly.
So the coordinator technically already observes whatever the stair predictor decided this frame
- it is currently excluded from `migrated_owner`, so `_build_plan` short-circuits to trivially
`plan.valid = leg["hit"]` with no reconfirmation of any kind, exactly as the "labels the winner
but doesn't validate" gap 009 originally identified.

**The one real design problem found, not yet resolved**: the `LOCOMOTION_LOCK`/`SPLIT_RECOVERY`/
`IDLE_STANCE_REHOME` precedent for validation (`_has_support_at`'s stance-agnostic raycast
reconfirmation, without a stance-zone check) does not translate cleanly here, because
`_apply_support_contact` deliberately **blends** the target between two real support surfaces
across `_support_transfer_elapsed`/`support_transfer_blend_time` whenever the support foot
switches (this is what `_latch_support_target`'s doc comment calls "a discrete handoff between
two already-latched targets," specifically added to remove a once-per-step pelvis/foot pop). At
an intermediate blend fraction, the resulting `blended_target` is a lerp between two real
points and may not itself sit on solid ground at every frame - a straight `_has_support_at`-style
raycast at the *current* target would very plausibly reject the plan during every single support
transfer, not just genuine failures. This needs an explicit answer before any gate is written,
not an assumption: either (a) skip validation entirely while `blend < 1.0` (only reconfirm once
a support target is fully settled, mirroring how `IDLE_STANCE_REHOME`/`SPLIT_RECOVERY` are
already exempted from the stance-zone check for their own "legitimately mid-transition" reason),
or (b) validate against the two blend endpoints (`_support_transfer_from_pos` and the fresh
`full_target`) rather than the interpolated point itself. Neither has been tried or tested.

Toe/leaf envelope validation (`_toe_envelope_valid`) is a second, smaller open question:
`_toe_probe_reaches_higher_surface` already does stair-specific toe/riser reasoning inside
`_latch_support_target`'s own surface-choice logic, so applying the coordinator's generic toe
check unqualified on top could duplicate or conflict with it - unverified either way, would need
live testing before deciding whether to gate it, exempt it (`check_toe=false`, matching the
raw-recovery precedent), or leave it for a later pass.

**Not implemented.** Given the density of prior live-only regressions in this exact code and
that this design question needs an explicit answer (not a guess) before any gate is safe to
write, this is presented as a design proposal for direction, not a finished plan - the two
options above (skip validation during blend vs. validate against blend endpoints) are a real
fork the user should weigh in on before implementation begins.

## STAIR_SUPPORT migrated (user chose "skip validation during blend")

Implemented the recommended direction from the design proposal above. Reused the exact pattern
already established for `IDLE_LOWER_ACQUIRE`'s in-flight waypoint rather than inventing a new
"settled" concept: added `FootIKStairPredictor.get_current_support_surface_target()`, returning
`_support_surface_target` directly (the real surface the predictor is actually converging
toward, independent of `_apply_support_contact`'s own transfer-blend/smoothing state). `_finish_
validation` now validates against that value for `STAIR_SUPPORT` instead of the possibly-
smoothed `plan.surface_target` - the same "validate the destination, not the smoothing" fix
already used for `IDLE_LOWER_ACQUIRE`.

Added a `coordinate_stair` gate (`plan.owner == STAIR_SUPPORT`, no animation/stationary/ground-
weight requirement - it can occur while idle or while actively climbing, and its own weight/
normal are managed entirely by `_apply_support_contact`, not the general per-leg path those
fields elsewhere reflect). Added `STAIR_SUPPORT` to `migrated_owner` and to the `require_stance`
exemption list (same reasoning as `LOCOMOTION_LOCK`: a support foot sits on whichever tread the
climb is currently on, arbitrarily far from the root). Per the design proposal's still-open toe
question, exempted `STAIR_SUPPORT` from the generic toe/leaf envelope check too
(`check_toe := plan.owner != STAIR_SUPPORT`), since `_toe_probe_reaches_higher_surface` already
does its own stair-specific toe/riser reasoning and stacking an unverified second check on top
was exactly the kind of guess this task's own caution says not to make.

`STAIR_SWING` (the swinging, non-support leg during a climb - a separate mechanism entirely,
driven by `update_swing_lift`/predicted targets) was explicitly **not** touched this pass; the
design proposal's analysis was scoped to `STAIR_SUPPORT` only.

**Verified**: `check_foot_ik_stair_repeat.sh` (the dedicated live stair-climb regression, not
just a synthetic case) passes unchanged. Full comprehensive suite
(`scripts/check_foot_ik_all.sh`) re-run clean: exit 0, identical known-baseline failure set, no
new/unexpected failures anywhere - the migration is behavior-neutral against every automated
check. Coordinator migration is now 12 of 12 owners *labeled and gated* for `STAIR_SUPPORT`
specifically (`STAIR_SWING`/`LOCOMOTION_LOCK`/`LOCOMOTION_STANCE` already done earlier this
session; `STAIR_SWING` remains the one genuinely unmigrated owner).

**Live confirmation: done.** User walked a real staircase in-editor; no foot pop/snap reported.
The session's Godot log stayed clean throughout (steady 60fps, no `SCRIPT ERROR`, no anomaly in
the always-on `[FOOT_IK_PERF]`/`[FOOT_IK_ENGINE_PERF]` diagnostics, `[ANIM_COMPARE]` cases still
synced) - though note the log itself only distinguishes a crash/script-error class of problem,
not a subtle visual pop, so the user's own observation is still the primary signal here.

## References

- [009](009_foot_ik_architecture_review.md) - ownership matrix and decision record.
- [008](008_foot_ik_platform_edge_safety.md) - the still-open right-foot clip this task's
  step 1 targets, and the four dead-end fix attempts already tried on it.
