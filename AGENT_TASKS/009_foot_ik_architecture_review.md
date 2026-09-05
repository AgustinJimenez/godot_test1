# 009: Foot IK architecture review and consolidation plan

## Status and scope

New, planning-phase. Goal: review the entire Foot IK system for competing/duplicated state
ownership and produce a concrete consolidation plan, not to write refactor code yet. This
task ends with a decision presented to the user, not a merged rewrite. Task 008 continues to
own live platform-edge bug fixing in parallel; do not fold its in-flight uncommitted work
into a rewrite without the user's explicit go-ahead.

## Why this task exists

Task 008 already diagnosed the recurring bug pattern: "the core problem is competing target
owners, not simply insufficient smoothing." `FootIKTargetPlan`/`FootIKTargetCoordinator` were
built to arbitrate this, but only for the stationary-idle path; landing, active lower
acquisition, stair swing, and locomotion still go through older ad-hoc flag logic. That is one
axis of duplication. There are at least two more:

- `solver_backend` (`CUSTOM` vs `NATIVE_TWO_BONE`, `foot_ik_native_backend.gd`) — an
  entirely separate bone-output path selectable per player, opt-in via `--native-foot-ik`.
- `locomotion_mode` (`LEGACY` vs `RESIDUAL_STAIR` vs `PHASE_LOCKED`) — three independently
  written correction pipelines in `player_foot_ik_modifier.gd`,
  `foot_ik_residual_corrector.gd`, and `foot_ik_phase_locked_corrector.gd`, switchable by
  enum. The latter two exist specifically because `docs/foot_ik_industry_review.md` found
  no real/shipped system attempts full-height IK climbing on an unmodified flat-ground walk
  cycle the way `LEGACY` does, and that the project's homegrown pieces — the velocity-based
  gait tracker, predictive next-tread swing lift, and support-leg transfer state machine —
  are exactly the pieces most implicated in the bug history (freeze/unfreeze regressions,
  support-latch drift, swing-lift/pelvis-sink interactions).

Three switchable pipelines, plus a partially-migrated arbitration layer inside the pipeline
still marked default, is a reasonable place for state to fight itself. This task exists to
map that precisely and decide which parts to keep before writing more patches on top.

## Current architecture inventory

`actors/player/foot_ik/` (~4,900 lines total) plus `actors/player/player_foot_ik_modifier.gd`
(~1,000 lines, the `SkeletonModifier3D` entry point):

| File | Lines | Stated ownership |
|---|---|---|
| `player_foot_ik_modifier.gd` | ~1000 | Contact/gait policy, shared-pelvis coordination, final bone apply, dispatch to whichever `locomotion_mode`/`solver_backend` is active |
| `foot_ik_ground_sampler.gd` | 998 | Collision sampling, target/normal smoothing, landing-lower-support latching |
| `foot_ik_leg_solver.gd` | 782 | Closed-form bone output only — no raycasts or support policy |
| `foot_ik_stair_predictor.gd` | 609 | Tread prediction, swing clearance, support-leg transfer. Self-documented as "TEMPORARY / EXPERIMENTAL... not an assertion that its visible stair gait is production-ready" |
| `foot_ik_gait_tracker.gd` | 596 | Animated vertical velocity, weights, phase edges, target locks — "owns no geometry decisions and writes no bones" |
| `foot_ik_target_coordinator.gd` | 190 | Final arbitration boundary for the stationary-idle path only; doc comment: "Existing feature modules still produce candidates during migration" |
| `foot_ik_residual_corrector.gd` | 151 | Alternative `locomotion_mode`: raycast + one symmetric pelvis lerp, explicitly no idle-freeze/prediction/transfer machinery, built to test whether that machinery is needed |
| `foot_ik_phase_locked_corrector.gd` | 134 | Alternative `locomotion_mode`: samples once per footfall, holds for a stance window, eases out — reuses gait tracker's `landed` event only |
| `foot_ik_native_backend.gd` | 129 | Adapter to Godot 4.6's native `TwoBoneIK3D`, alternative `solver_backend` |
| `foot_ik_landing_planner.gd` | 223 | Chooses one supported footprint while airborne, retains it to touchdown |
| `foot_ik_target_plan.gd` | 48 | Immutable per-leg-per-frame arbitration result; `Owner` enum has 13 values (`ANIMATION`, `LIVE_CONTACT`, `LANDING_COMMITMENT`, `LANDING_UPPER`, `IDLE_LOWER_ACQUIRE`, `IDLE_LOWER_LATCH`, `IDLE_STANCE_REHOME`, `IDLE_FREEZE`, `STAIR_SUPPORT`, `STAIR_SWING`, `LOCOMOTION_LOCK`, `LOCOMOTION_STANCE`, `SPLIT_RECOVERY`) |
| `foot_ik_runtime_settings.gd` | 39 | Feature-flag toggles shared by collaborators (8 `*_enabled` bools) |

`_process_modification_with_delta()` in the modifier (the `LEGACY` path, still the default)
computes and threads together, per leg, per frame: `frozen`, `stationary_slope`,
`landing_lower_support`, `unreachable_drop`, `straddling_riser`, `step_down`,
`is_retracted`, `over_void`, `void_dangle`, `flat_contact`,
`stationary_in_place_locomotion`, `flat_idle_clearance`, `stationary_noop`,
`preserve_idle_pose`, `is_stance_crossed`, `releasing_previous_support`,
`is_flat_level_ground`, `preserve_flat_pose` — each computed from the previous ones in
sequence, several capable of overriding an earlier one's decision for the same leg in the
same frame. This is the concrete shape of "competing owners."

## Review goals (what "done" looks like)

1. **Ownership matrix.** For every piece of frame-to-frame state (freeze flags, latches,
   locks, smoothed targets/normals/weights), list every writer and every clearer, across
   all three `locomotion_mode`s and both `solver_backend`s. Read-only — no code changes in
   this step. `AGENT_TASKS/007`'s "Stateful ownership rules" section and 008's target-owner
   framing are the starting vocabulary; extend, don't restate them.
2. **A direction decision, made with the user, among:**
   - (a) Finish what 008 started: migrate landing, active lower acquisition, stair swing,
     and locomotion behind `FootIKTargetCoordinator`/`FootIKTargetPlan`, retiring the legacy
     ad-hoc flags in `player_foot_ik_modifier.gd` once each path migrates.
   - (b) Commit to `docs/foot_ik_industry_review.md`'s recommended alternative: demote IK to
     a residual correction pass (`RESIDUAL_STAIR`/`PHASE_LOCKED`-shaped) and retire the
     predictive swing-lift/support-transfer machinery — contingent on first building
     stair-aware base motion, which that document scopes as its own separate milestone, not
     part of this review.
   - (c) An explicit hybrid, documented well enough that a future session doesn't have to
     re-derive why three pipelines coexist.
   Whichever is chosen, the losing pipeline(s) get retired, not left as a permanently
   maintained alternate mode — three parallel implementations is the problem being reviewed,
   not a feature to preserve.
3. **Regression contract.** Any consolidation must keep passing (or knowingly, explicitly
   update) every acceptance scene under `tests/manual/foot_ik/` and the invariants already
   codified in `AGENT_TASKS/007` and `AGENTS.md`'s "Foot IK and movement" section — flat-idle
   pose preservation, rotated stance-rectangle validity, side-key latch clearing on release,
   directional contact clearance sign convention. Treat these as the spec, not
   implementation details to relearn from scratch.

## Ownership matrix: the idle-lower-support family (first slice, from 008's dead-end fixes)

Scoped to the state cluster behind the still-open right-foot clip in 008: whether a foot may
plant on a *lower* tread while idle (e.g. straddling a stair riser). All in
`foot_ik_ground_sampler.gd` unless noted.

| State | Written by | Cleared by | Consumed by |
|---|---|---|---|
| `idle_lower_latched_target[side]` | `_update_idle_lower_transition` (acquire completes), `_validate_idle_lower_support` (retain), `validate_and_latch_landing_lower_support` (carry jump_land->idle), split-safe-zone block (~L906, as part of switching to split recovery, despite the name) | 9 separate call sites across `_update_idle_lower_transition`, `_validate_idle_lower_support`, `validate_and_latch_landing_lower_support`, `_latch_idle_lower_support` (should-release/upper-confirmed branches), split-safe block, `foot_ik_target_coordinator.gd::_apply_raw_recovery` | `player_foot_ik_modifier.gd` (`unreachable_drop`, plant-classification overrides), `foot_ik_target_coordinator.gd::_legacy_owner` (assigns `IDLE_LOWER_LATCH`), split-height consistency check (~L861) |
| `idle_lower_acquiring[side]` | `_update_idle_lower_transition`, `_validate_idle_lower_support` (both its "move toward" branches) | 8 call sites, same functions plus `_apply_raw_recovery` | `player_foot_ik_modifier.gd` (3 classification reads), `_legacy_owner` (`IDLE_LOWER_ACQUIRE`) |
| `lower_riser_away[side]` / `lower_riser_away_surface_y[side]` | `_rehome_lower_surface_from_riser` only, when an escape direction is found | `_clear_lower_riser_away` (called from 6 sites across the same functions above) | `foot_ik_leg_solver.gd` (bends the pose away from the riser while mid-escape) |
| `lower_riser_cleared_target[side]` | `_rehome_lower_surface_from_riser` (cache of the last-proven-clear surface) | 9 sites, same functions | Only `_rehome_lower_surface_from_riser` itself (fast-path cache check) |

Key findings from actually tracing this, not just listing it:

1. **The toe/leaf reach is validated nowhere in this chain.** `foot_ik_target_coordinator.gd`'s
   `_finish_validation` checks `stance_valid` (ankle in the rotated stance rectangle),
   `support_valid` (`_has_support_at`, a single raycast at the ankle surface point), and
   `reach_valid` (hip-to-ankle distance) - all ankle-only. `_has_lower_riser_clearance`'s
   16-direction ring is the closest thing to a toe-aware check that exists, but it fires
   inside the ground sampler's own latch acquisition, not the coordinator, and (per the
   dead-end fix above) failing it does not reliably stop a latch from reaching the solver as
   `valid=true`. This confirms 008's "Next work" item 2 as the real gap, not a guess.
2. **The coordinator only governs a fraction of this family.** `resolve_stationary`'s
   `coordinate_idle` gate requires `ground_weight >= 0.95`, a flat surface, idle animation,
   no landing grace/commitment, and (per `legacy_transition_active`) no in-progress
   `idle_lower_acquiring`/`idle_lower_latched_target` transition on *either* foot unless the
   owner is already `IDLE_LOWER_LATCH`. Most of this table's actual state changes
   (acquisition, landing-upper confirmation, the split-safe-zone switch) happen *before* or
   *around* that gate, in the ground sampler, invisible to the coordinator until a latch is
   already fully formed. The coordinator validates the destination, not the path there.
3. **One block does three unrelated things under one name.** The "split-safe-zone" code
   (~L850-915) both erases `idle_lower_latched_target`/`idle_lower_acquiring` *and* installs
   an entirely different target source (`split_safe_held_upper_target`) when both feet's
   latched heights diverge by more than 0.03m - a fifth de facto owner
   (`FootIKTargetPlan.Owner.SPLIT_RECOVERY` exists in the enum but nothing here constructs a
   plan for it) layered on top of the four dictionaries above.
4. **Acceptance coverage is real but is a stack of point samples, not a boundary test.**
   `foot_ik_idle_plant_stability_check.gd` alone carries 9 separate hardcoded
   live-position/yaw scenarios (turn, rehome, knee-guard, live-pose, right-stale, left-stale,
   coordinator, straight-knee) each with its own tight numeric limit (e.g.
   `MAX_TURN_FOOT_STEP=0.12`, `MAX_COORDINATOR_FOOT_STEP=0.055`). `foot_ik_ledge_safety_check.gd`
   adds corner-clearance cases with their own limits (e.g. the `idle_both_lower_legs_clear_platform_corner_live_repro`
   case's 0.040m minimum this session's fix attempt broke by 0.004m).
   `foot_ik_toe_riser_check.gd` covers one specific left-foot clip. None of these share a
   single validation boundary; each is a separately-tuned regression pinned to one exact
   historical repro. That is *why* the escape-search fix in this session broke a different
   case instead of just fixing the one it targeted: there is no single place that all of
   these funnel through where a fix could be verified once.

Implication for the earlier three-option choice: this evidence favors option (a) - finish
routing this family through `FootIKTargetCoordinator`/`FootIKTargetPlan` with a toe/leaf-aware
validation, so there is one boundary to fix and re-verify - over patching
`_rehome_lower_surface_from_riser` (or any other individual ground-sampler function) in
isolation again. This is a recommendation to weigh, not a decision made on the user's behalf.

## Ownership matrix: landing/airborne and stair-support/locomotion families

| State | Written by | Cleared by | Consumed by |
|---|---|---|---|
| `landing_committed_target[side]` (ground sampler) | `_committed_landing_hit` (~L284-290) | same function (rejection branch), `_latch_idle_lower_support` should-release path | `player_foot_ik_modifier.gd` (`coordinate_idle` gate, classification), `_legacy_owner` -> `LANDING_COMMITMENT` (highest-priority owner) |
| `FootIKLandingPlanner.safe_root_target` / `committed_surface_y` / `decision` | `predict()`, `reject_grounded_mismatch()` | `reset()`, `reject_grounded_mismatch()` | `player_foot_ik_modifier.gd` airborne path; snapshotted/restored across `set_character_grounded` via `landing_commitment_snapshot`/`restore_landing_commitment` |
| `FootIKStairPredictor._support_side` + `_support_ground_target`/`_support_surface_target`/`_support_normal` | `_choose_support_side` + `_latch_support_target` | set to `&""` on release (shared-drop collapse, swing clearance loss, reset) | `player_foot_ik_modifier.gd::_forced_support_side` (read-only property), `_legacy_owner` -> `STAIR_SUPPORT` |
| `LegState.has_latched_target` / `latched_target` (per-leg, stair predictor) | swing/prediction update methods | explicit `false` on swing end/reset | leg solver's swing-lift blending, `_legacy_owner` -> `STAIR_SWING` via `predicted_step_targets` |
| `FootIKGaitTracker._locomotion_lock_active` / `_locomotion_lock_released` / `_locomotion_stance_active` | `_update_locomotion_stance` + the lock-active block (~L505-524) | `reset_runtime_state()`, same functions | `is_locomotion_target_locked`/`is_locomotion_stance_active` -> `_legacy_owner`'s two lowest-priority branches (`LOCOMOTION_LOCK`, `LOCOMOTION_STANCE`) |

Findings:

1. **`_legacy_owner`'s priority chain is the de facto arbitration for the whole system**, not
   just the idle-lower family: `LANDING_COMMITMENT` > `LANDING_UPPER` > `IDLE_LOWER_ACQUIRE` >
   `IDLE_LOWER_LATCH` > `IDLE_STANCE_REHOME` > `IDLE_FREEZE` > `STAIR_SUPPORT` > `STAIR_SWING`
   > `LOCOMOTION_LOCK` > `LOCOMOTION_STANCE`. This ordering exists in exactly one place
   (`foot_ik_target_coordinator.gd::_legacy_owner`) but only *labels* the winner after the
   fact - it does not stop a lower-priority system from having already mutated shared state
   (`smoothed_target`, `smoothed_normal`) before the label is read. Landing and stair-support
   owners still write `smoothed_target` directly from their own modules.
2. **The stair-support and locomotion-lock families are entirely unvalidated by the
   coordinator.** `_build_plan`'s `coordinate_idle` gate requires idle animation, so
   `STAIR_SUPPORT`, `STAIR_SWING`, `LOCOMOTION_LOCK`, and `LOCOMOTION_STANCE` plans always
   take the `not coordinate_idle` early return (`stance_valid = true; support_valid = plan.valid; reach_valid = true`)
   - i.e. whatever `leg["hit"]` already says, no independent check at all. This matches 008's
   "Landing, active lower acquisition, stair swing, and locomotion still use legacy adapters"
   literally: those four owners get no coordinator validation whatsoever today.
3. **Landing has its own separate two-tier commitment** (`FootIKLandingPlanner`'s airborne
   commitment vs. the ground sampler's `landing_committed_target`) that is snapshotted across
   grounded/ungrounded transitions independently of everything else in this table - a sixth
   distinct persistence mechanism, on top of the four in the idle-lower table and the
   split-safe-zone block.

Net picture across both slices: this system has at least **10 independent pieces of
per-side state** (4 idle-lower + `landing_committed_target` + 3 landing-planner fields +
stair-support target + per-leg latch + 3 locomotion-lock fields) mutated by nine different
functions across three files, arbitrated after the fact by one priority list
(`_legacy_owner`). Of that list's 10 owners, `_build_plan`'s `migrated_owner` check admits
only 3 (`LIVE_CONTACT`, `IDLE_LOWER_LATCH`, `IDLE_FREEZE`) into real validation
(`_finish_validation`'s stance/support/reach checks) - and even those only when
`coordinate_idle` is also true (idle animation, `ground_weight >= 0.95`, flat surface, no
landing grace/commitment). The other 7 owners always take the pass-through branch
(`stance_valid = true; support_valid = plan.valid; reach_valid = true`) - whatever
`leg["hit"]` already says, unchecked. This is a precise, code-verified version of what 008
called "competing target owners" - not a rhetorical description.

## Decision

User chose option (a): consolidate through `FootIKTargetCoordinator`/`FootIKTargetPlan`.
Implementation scoped in [010](010_foot_ik_target_coordinator_consolidation.md); this file
stays the review/decision record.

## Suggested process

1. Build the ownership matrix (step 1 above) before touching any code.
2. Capture a current baseline: run `scripts/check_foot_ik_fast.sh` and the exhaustive suite
   listed in `AGENTS.md` (`check.sh`, `check_foot_ik.sh`, `check_foot_ik_locomotion.sh`,
   `check_foot_ik_ramps.sh`, `check_foot_ik_ramp_sweep.sh`). Task 008's Sept 5 validation map
   is recent but had failing/incomplete entries and uncommitted changes since — don't assume
   it's still current.
3. Present the matrix and the (a)/(b)/(c) tradeoff to the user before writing any refactor
   code. This is an architecture decision, not a bug fix, and 008's own history includes an
   earlier migration attempt causing a 0.46m landing jump — undersized steps here are
   expensive to get wrong.
4. Once the user picks a direction, open a new numbered task scoping the actual
   implementation. This file stays the review/decision record, not a running refactor log.

## Non-goals for this task file

- Not for fixing individual platform-edge/stair bugs — that stays in `008` (or its
  successor) until this review's direction lands.
- Not for implementing stair-aware base motion — `docs/foot_ik_industry_review.md` already
  scopes that as its own milestone if option (b) is chosen.
- Not for producing a full rewrite unilaterally. Do not commit or push architecture changes
  from this task without the user's live-tested confirmation, per `AGENTS.md`.

## References

- [`docs/foot_ik_industry_review.md`](../docs/foot_ik_industry_review.md) — real-system
  comparison (Unity Final IK, a shipped Godot addon, Unreal Motion Warping, Perlin's
  phase-shift technique) and the "concretely scoped alternative" this task's option (b) cites.
- [`007_foot_ik_stair_contact_and_locomotion.md`](007_foot_ik_stair_contact_and_locomotion.md) —
  durable architecture and stateful-ownership rules.
- [`008_foot_ik_platform_edge_safety.md`](008_foot_ik_platform_edge_safety.md) — active bug
  fixing and the target-coordinator migration this review's option (a) would complete.
