# 018: IK implementation review and improvement plan

## Status and scope

**In progress.** Current implementation audited at `926874e` on 2026-09-12. Spacing,
selection, seam holding and the shared-pelvis restructuring are committed; the full accepted
feet/pelvis contract remains open. Current work closes post-validation adjustment and cached
pelvis-reference lifetime gaps. Historical validation below is not certification of this slice.

The original review inspected the working tree, including uncommitted changes to the modifier, sampler,
landing planner, runtime settings, and idle acceptance scene. HEAD at review: `c0e74ba`.
Those existing changes were preserved. No scene, regression suite, or fresh performance
benchmark was run; historical test results below are attributed to their task, not re-certified.

Scope: all 11 `actors/player/foot_ik/*.gd` modules and the main modifier, their movement/body
integration, native/experimental paths, clearance tools, regression runners and representative
acceptance scenes. Also inspected look/grip modifiers and the ALS prototype's mantle-hand IK
and body facade at their integration boundaries. This is not a full audit of retargeting,
the character editor, or all ALS gameplay code.

### Current implementation progress

This table supersedes the original findings' descriptions of missing code; their remaining
design goals and acceptance requirements still apply.

| Finding | Implemented evidence | Remaining work |
| --- | --- | --- |
| I — runner reliability | `ec3cf35`: require all six preview results, check grouped script errors, and compare ramp failure counts/depths; `dc1871c`: `check_foot_ik.sh`/`check_foot_ik_all.sh` now also run `scripts/check.sh` itself; 2026-09-12 follow-up: `check_foot_ik_ramp_locomotion.sh` and "Foot IK stationary planted-foot stability check" moved out of the plain label list into quantitative grading (see below) - a 13->14 ramp-locomotion regression hid behind the bare label during this same session. | Exact-case baselines, behavioral CI, deduplicating fast/main/all lists. |
| B — time/refresh | `7f8f602`: guard specific streaks against zero-delta/duplicate ticks; preserve pelvis smoothing on refresh. | Pipeline-wide frame context and once-per-tick history contract, with refresh/rate coverage. |
| F — lifecycle | `d1104ca`: reset residual/phase-locked/native state and update native orientation history; a dedicated white-box reset-clearing test now guards it (below). | Explicit `reset`/`enter`/`exit`/capability contracts per mode; a full scene-level pose-continuity test (mode A -> B -> A with a real skeleton) remains open. |
| C — constraint status | `a0392d5`: replace validity booleans with satisfied/violated/unchecked/inapplicable/tolerated statuses; general per-constraint `constraint_reasons`/`constraint_expiry_frames` mechanism added and wired for toe (below). | Owner/terrain contract coverage; the enum plus reason/expiry still does not strengthen validation by itself - only toe uses tolerance today. |
| D — pose result/apply | `b60173f` introduced the result type; the live-confirmed extraction adds fixed inputs, candidate-local history/diagnostics and guarded acceptance (details below). | Final-output clearance/feasibility reporting and clearance-driven candidate selection. |
| E — final snapshot | `70bea29`: prefer fresh Foot IK poses for visual consumers and frame-stamp the cache. | Publish after every enabled modifier/backend, including native IK and any later balance layer. |
| H — performance | `dfee62e`: log worst-call/worst-frame solver timing. | Query accounting, explicit work budgets and broader tail-latency measurements. |
| A — authoritative plan | `b0f804b` moves spacing/ground priority before validation; `60b0fa5` moves seam holding; live-confirmed `88884a2` moves upper/slope generation before pelvis. | Upper/slope output still needs final acceptance after initial validation; shared-pelvis reach, native parity and the existing locomotion failures remain open. |
| G — typed integration | `1653a61` corrects physics-layer names to stair traversal/contact surfaces. | Support identity/local anchors, typed motion/animation context and root-request feedback. |

Feature status: torso counter-lean (`56d0222`) is implemented but **parked, disabled by
default**, and not accepted as natural-looking. The checkpoint includes a recovery-arc helper
(`tools/foot_ik/foot_step_arc.gd`) and landing confirmation changes; these remain experimental
task 019 work, not a complete deliberate lift-move-plant system. Contact curves, heel/toe
support modes, stride warping, moving-support anchors and portable replay bundles remain proposals.

Validation caveat: several September 10 commits report 41 passing checks and 5 known failures;
these are historical results, not the current tree's baseline. The later
[019 toe/riser investigation](019_foot_ik_toe_riser_clip_during_rotation.md) remains open with
failing rotation coverage; `ff05f2f` documents a backed-out fix. No tests or scenes were run
for the status audit. The subsequent extraction's validation is recorded separately below.
Other agents' runtime/test edits are preserved, including the task 019 acquisition-speed override
now carried through the evaluator's input snapshot.

Next architecture priorities are migrating the remaining late adjustments and making feet/pelvis
planning authoritative, with trustworthy per-case regression evidence. Do not treat the targeted
fixes above as completion of the broader contracts or start all proposed features as a batch.

### Final adjustment / pelvis-reference lifetime — fix applied, awaiting live confirmation, uncommitted

A second agent picked this up after the handoff above and found the actual root cause of
the ramp-spin regression, still uncommitted pending the user's live test.

**Root cause:** `_accept_final_target()`'s support check computed its check point via a
generic vector translation of the OLD surface by `candidate - plan.ankle_target`. On a
continuous slope, a slope-adjustment nudge's own downhill/sideways component is not aligned
with the surface normal, so that translated estimate drifts laterally off the real ramp
surface as the candidate keeps moving frame to frame - `_has_contact_support`'s existing
0.03 m distance-to-estimate tolerance then correctly (by its own contract) rejects an
estimate that has drifted meters away from any real ground, for several consecutive frames
in a row, each rejection snapping the foot back to that frame's un-adjusted base solve and
producing the visible spin-step pop.

**Fix (two parts):**
1. New `_sample_contact_support(space, estimate, normal) -> Dictionary` re-derives the
   check point by projecting the candidate back along the surface normal by this leg's own
   known ankle-to-surface offset (`candidate - surface_normal * offset_len`) instead of the
   drifting linear translation, then self-corrects: accept whenever a real raycast under
   that estimate exists with a matching normal, using the raycast's own hit position as the
   accepted surface point rather than requiring it to land within 3 cm of the estimate.
   `_has_contact_support`'s original strict distance-to-estimate check is untouched and
   still used as-is by `pelvis_reference_target()`'s lease-staleness check - a genuinely
   different use case (verifying an already-accepted, should-be-static cached point, not a
   fresh per-frame candidate).
2. A short `FINAL_HOLD_FRAMES` (2-frame) hold: when a candidate genuinely has no support at
   all (e.g. a downhill search briefly walking a candidate past the ramp's own finite edge -
   a real, correctly-rejected case, confirmed via raycasts up to 3 m finding no geometry at
   all), the coordinator holds the last accepted output rather than snapping straight to
   this frame's un-adjusted base solve, so a single genuine one-frame outlier does not pop
   visibly against neighboring adjusted frames.

The 20-case final-target contract scene encodes the previous design's exact internals
(mock `Coordinator` overrides `_has_contact_support`); it now also overrides the new
`_sample_contact_support` the same way and still passes all 20 cases unmodified in intent.

- Upper/slope candidates now pass a final acceptance boundary before use: finite coordinates,
  existing crouch-budget reach, applicable stance/toe checks and slope-aware point support.
  Upper acquisition checks its destination instead of requiring ground at its interpolated waypoint.
  A rejected optional adjustment retains the previously accepted plan; it cannot veto that fallback.
  Accepted target/support are written back to the plan. A later override cannot inherit validation.
- Rejected upper interpolation restores sampler surface/normal, and rejected slope output restores
  the accepted smoothing target. Producer search policy is otherwise unchanged; this is not a pure
  candidate-generation extraction. Existing solver-guard behavior is preserved for changed targets.
- Pelvis recovery references expire after 12 physics ticks (0.2 s at 60 Hz), do not renew during
  recovery/refresh, and are cleared on contact loss, animation release and reset. Reuse checks
  current stance/reach and actual support; a removed collider cannot retain its reference.
- New bounded trace fields: `plan_adjusted_target`, `plan_final_adjustment`,
  `plan_pelvis_reference`. No additional search loops: changed-target and recovery-reference
  checks each add at most one support ray per leg/pass, plus an applicable toe point query.
- New final-target contract scene: 20 cases, including real finite-ramp and disappearing-support
  geometry, wired into fast/main/all runners. Fresh `926874e` baseline: 44 pass / 7 known failures;
  ramp matrices: 19 and 16 failing cases, worst depths 0.013232 / 0.105375 m.
- Evidence: `/tmp/foot-ik-018-final.DXvpJ1/`: `live-before.jsonl`, `baseline-all.log`,
  `contract.log`, `fast.log`, `after-all.log`, `ramp-rejection.log`, `ramp-support.log`.

Validation after the fix:

| Check | Result |
| --- | --- |
| Project lint/import/parse | PASS (fast/full runners' first step). |
| New final-target contract scene | PASS, 20 cases, unmodified expectations. |
| Fast suite | Stops at the pre-existing "Foot IK stationary planted-foot stability check" known baseline failure (documented 2026-09-10, real unfixed toe/riser clip, task 019); all preceding checks pass. |
| Full runner (`scripts/check_foot_ik_all.sh`) | Passed: 45, Known baseline failures: 7, "No new/unexpected failures", exit 0. |
| Ramp locomotion, independent child of full | Failure count back to the pre-existing baseline of **13**; neither `ramp_15_yaw_135` nor `ramp_15_yaw_225` appear. `ramp_45_yaw_135` still fails (it was already a known baseline failure), now via `foot_float=0.042` instead of `foot_penetration=0.045` - same case, different measured metric, not a new one. |
| Stair repeat, independent child of full | PASS. |
| Locomotion, independent child of full | Existing `walk_left`/`walk_right` FAIL lines unchanged. |
| Ramp matrices, independent children of full | 19/20 and 16/16 failing cases, worst depths 0.013232 / 0.105375 m - within the existing `RAMPS_MAX_*`/`RAMP_SWEEP_MAX_*` quantitative baselines. |

Live-confirmed by the user; committed.

Limits: this validates adjusted **targets**, not final skinned clearance or exact reach after the
current frame's pelvis smoothing. Existing owner exemptions, native-backend differences and the
broader joint feet/pelvis contract remain open. A supported replacement collider is not distinguished
from the previous collider yet; support identity/local anchors remain finding G work.

### Idle-preview spawn edge / leg over-reach — root-caused and fixed 2026-09-12, committed

While live-testing the ramp fix above, the user reported the left leg visibly moving alone
once per idle animation cycle, at `foot_ik_preview.tscn`'s default manual-inspection spawn
point (not the ramp fix's own code path - confirmed via `plan_final_adjustment=unchanged`
and `plan_pelvis_reference=current` on every frame of the live trace).

Root cause, confirmed by direct headless reproduction and git bisection: that default spawn
(`z=4.068937`) sat 0.07 m past the far edge (`z=4.0`) of its 4 m test platform. A raycast grid
around the animated left foot bone found no ground at all under it (mask 33, the sampler's own
`GROUND_COLLISION_MASK`), while the right foot's raycast hit directly below itself - the idle
stance's natural sway put the left foot ~0.16 m past the platform edge with nothing under it,
so the ground sampler's fallback search grabbed real ground ~17 cm away on an adjacent surface,
stretching that leg to (and slightly past) its max reach. Bisected against clean `926874e` and
`60b0fa5` (before the shared-pelvis redesign) with byte-identical reach-margin numbers, proving
this predates all of today's work and is not a foot IK regression - it is the debug/preview
tool's own default spawn coordinate.

Fix: moved that default spawn to `z=2.0` (centered on the platform). Verified over a full
900-frame idle window: minimum reach margin stays positive throughout (+0.008 m left,
+0.006 m right; previously dipped to about -0.01 m on the left). Full suite unaffected:
45 passed / 7 known baseline failures, no new failures.

### Idle reach-margin regression coverage — added 2026-09-12, committed

No existing test asserted hip-to-target reach margin during ordinary idle standing, which is
why the bug above only ever surfaced live. Added `_track_reach_margin()` to
`foot_ik_idle_plant_stability_check.gd`, called every physics frame across all of that file's
idle-pose phases (initial settle, turn sweep, rehome, knee guard, live pose, left/right stale,
coordinator recovery, straight-knee). Scoped to genuine settled-standing owners
(`LIVE_CONTACT`/`IDLE_FREEZE`) only - transitional/predictive owners (stair-swing prediction,
idle-lower-latch, etc.) legitimately target a point the current static geometry does not yet
satisfy, so including them produced false positives during development. Uses the same reach
budget as `_accept_final_target` (`upper + lower + step_down_max_crouch`), so a real stair-top
stance is not flagged either. New `MIN_REACH_MARGIN := -0.005` gate plus
`reach_margin_left/right` and `_at` fields in the printed report. Full suite unaffected:
45 passed / 7 known baseline failures, no new failures.

### Runner known-failure blind spot closed — 2026-09-12, committed (018 finding I)

`check_foot_ik_ramp_locomotion.sh` and "Foot IK stationary planted-foot stability check" sat
in `check_foot_ik_all.sh`'s plain `KNOWN_BASELINE_FAILURES` label list - a worse run inside
either already-red check could hide behind the same "FAIL known" line forever. This is exactly
what happened during this session: the ramp-locomotion regression above went from the
documented baseline of 13 failing cases to 14 while the bare label stayed "FAIL known"
throughout, only caught because the ramp script was checked by hand.

Both now grade quantitatively instead, same idea as the two ramp-matrix scripts already did:
`run_ramp_locomotion_check()` compares the scene's own `failures=N` count against
`RAMP_LOCOMOTION_MAX_FAILED_CASES=13`; `run_idle_plant_stability_check()` compares
`drift_left_m`/`turn_penetration_m`/`live_pose_joint_step_m` against their own ceilings
(0.13/0.11/0.11 m respectively). Verified the gate actually catches a regression by
temporarily lowering `RAMP_LOCOMOTION_MAX_FAILED_CASES` to 5 and confirming the run flips to
`FAIL NEW` and exit 1, then restored it. Full suite unaffected: 45 passed / 7 known baseline
failures, no new failures, both new checks reporting their quantitative detail.

### Target-selection slice — 2026-09-12, committed `b0f804b`

Spacing was live-tested: user reports "not much diff", the expected result. The next
slice moves custom idle/landing-brace `ground_target` priority before plan validation:

- The modifier snapshots bracing/preference before arbitration. Coordinator selects the actual
  initial solve candidate once; custom solve reads `plan.ankle_target`, not a second field-priority
  expression. Ground selection cancels spacing for that solve candidate and derives its support
  point from the selected ankle, normal and effective offset. Invalid selections use the existing
  raw-support fallback/release. `plan_target_source` logs `target`, `ground_target` or `raw_recovery`.
- **Pelvis inputs remain separate legacy proposals.** The first attempt replaced those too and
  introduced body penetration (8 samples, 0.335562 m). Keeping the accepted solve candidate separate
  restores the core preview to zero penetrating samples. A fixture now asserts this separation;
  migrating shared pelvis still needs a joint reach/contact design, not target substitution.
- Native selection, upper-foot correction, slope adjustment and seam override remain unchanged.
  This removes the initial selection bypass, not every late override or the full-plan authority gap.
- Spacing/selection fixture expanded from 34 to **39 cases**, adding priority/fallback combinations,
  rejected ground-target provenance, and the pelvis-proposal isolation invariant.
- Evidence: `/tmp/foot-ik-018-selection.6lwKMn/`, including preserved live trace and rejected
  integration attempt. Superseded by the later seam/shared-pelvis validation below.

### Spacing authority slice — 2026-09-12, live-confirmed

- The 22 cm stationary-spacing proposal now runs in `FootIKTargetCoordinator` before
  `_build_plan()` validates either leg. Its formula, rotated hip axis, flat-idle exemption,
  missing-contact gate and moving-animation exemption are preserved. The modifier no longer
  widens the pair after validation; the subsequent shared-drop reach check sees the accepted targets.
- A shifted ankle proposal carries the same displacement into its candidate support point.
  Existing owner-specific acquisition/support-transfer destination rules remain intact. An
  unsupported proposal uses existing raw-support recovery or release; spacing is not reapplied
  to undo that decision. Sampler caches remain producer-owned, not rewritten by proposal generation.
- `record_solve_target()` observes the actual custom-solver input without changing the accepted
  target. For a spacing proposal, a mismatch beyond 1 µm removes its inherited validation flag.
  Ground-target priority and later upper/slope/seam overrides can still change the input; this
  slice diagnoses/downgrades them rather than pretending the complete pipeline is authoritative.
  Non-spacing paths retain their previous validation behavior; native output is not newly certified.
- Trace fields: `plan_spacing_requested`, `plan_ankle_target`, `plan_proposed_target`,
  `plan_solve_observed`, `plan_solve_reason` (`accepted_plan` / `late_target_override` /
  `not_solved`) and `plan_solve_validated`. Target agreement alone is not a final-pose
  clearance guarantee; existing per-constraint statuses still describe skipped/tolerated checks.
- New [spacing-plan acceptance scene](../tests/manual/foot_ik/foot_ik_spacing_plan_check.gd),
  wired into fast/main/all runners: **34 deterministic cases pass**, including supported
  widening, unsupported/rejected proposals, raw fallback, split-height surfaces, 24 yaw angles,
  flat/moving/missing-contact pass-through, and the ground-target priority bypass. Geometry
  callbacks are controlled to isolate the coordinator contract; terrain replays remain necessary.
- Full comparison against committed `e243fc0`: **40 passed / 7 known failures before ->
  41 passed / the same 7 known failures after**. All six raw `FOOT_IK_* FAIL` metric lines
  match exactly; both ramp matrices retain their counts/depths. No fixture or baseline was widened.
  Evidence and preserved live trace: `/tmp/foot-ik-018-spacing.Txfj0X/`.
  No live preview opened and no commit made for this slice; subsequently live-confirmed by user.

Spacing-slice validation map (2026-09-12, sequential headless runs):

| Entrypoint | Result |
| --- | --- |
| `scripts/check.sh` | PASS: lint/import/parse. Final expanded spacing fixture also passes lint and scene execution. |
| Spacing-plan scene | PASS: 34 cases, also reached through the all/main runners. |
| `scripts/check_foot_ik_fast.sh` | Stops at existing planted-idle failure; other checks before it pass. |
| `scripts/check_foot_ik.sh` | Independent run stopped at the existing unreachable lower-support acquisition failure, including the baseline `_update_idle_lower_transition` argument-count error; spacing regression passed all 34 cases. |
| `scripts/check_foot_ik_all.sh` | 41 pass / 7 known failures / no unexpected failures. Core failures remain unreachable acquisition, walk-to-idle stance and planted-idle stability. |
| `scripts/check_foot_ik_ramp_locomotion.sh` (independent child of all) | Existing failure; metrics unchanged. |
| `scripts/check_foot_ik_stair_repeat.sh` (independent child of all) | PASS. |
| `scripts/check_foot_ik_locomotion.sh` (independent child of all) | Existing failure; metrics unchanged. |
| `scripts/check_foot_ik_ramps.sh` (independent child of all) | 20 failing cases; worst depth 0.013232 m, unchanged. |
| `scripts/check_foot_ik_ramp_sweep.sh` (independent child of all) | 16 failing cases; worst depth 0.105375 m, unchanged. |

Spacing and target-selection slices committed as `b0f804b`.

### Seam-hold slice — 2026-09-12, automated validation, committed `60b0fa5`

The idle-loop-reset seam hold (`_velocity_suppressed` freezing the ankle at last frame's actual
solve to avoid a pop) used to run after validation, silently overriding upper-foot/slope
adjustment with no check that the frozen position still made sense. It now resolves into
`solve_candidate` inside `resolve_stationary()`, after spacing and ground-target selection,
taking the same final priority it always had - upper-foot/slope adjustment are skipped for a
seam-held leg instead of computing output that would previously have been discarded anyway.

- The modifier computes the hold value itself (`_leg_solver.debug_solve_target[side]`, last
  frame's actual solve) before calling `resolve_stationary()`, using the exact original
  condition (`_velocity_suppressed`, idle animation, not translating, not `stationary_slope`,
  history present). The coordinator's new `_apply_seam_hold()` applies it as `target_source =
  "seam_hold"`, overriding any spacing/ground-target selection for that leg.
- A frozen ankle validated against this frame's *fresh* raw surface could fail on a stale/
  current mismatch that never existed before (seam used to bypass validation entirely) -
  `surface_target` is derived from the frozen ankle itself for `seam_hold`, same fix already
  applied for `ground_target`.
- No new fixture: the existing dedicated
  [idle-loop seam acceptance test](../tests/manual/foot_ik/foot_ik_idle_seam_check.gd) (already
  wired into fast/main/all runners) is the acceptance test for this exact mechanism and passed
  with byte-identical metrics (`max_left_step_m=0.0020`, `max_knee_step_m=0.0015`,
  `max_knee_flex_step_deg=0.18`, same frames). The spacing-plan fixture (39 cases) and full
  suite (41 pass / 7 known failures / no unexpected failures) also confirmed unchanged.
- **Not live-tested.** This path only triggers during a rare idle-loop-reset velocity-
  suppression window, not something readily reproducible by manual play; automated coverage
  is the practical acceptance bar here, same as the target-selection slice before it.

### Shared-pelvis/reach design — proposed and implemented 2026-09-12, live-confirmed, committed `88884a2`

Upper-foot correction and slope adjustment (finding A's two remaining late overrides) both
consume `solve_hip`, which depends on `shared_drop` and `_pelvis_lateral_shift`. Those pelvis
values are computed from each leg's *raw* `target`/`ground_target` dict fields, deliberately
still pre-spacing/pre-selection - a prior attempt to feed them the coordinator's accepted
(spacing-shifted) target caused body penetration (8 samples, 0.335562 m); `foot_ik_spacing_plan_
check.gd`'s `_check_target_priority` now asserts `leg["target"]` is left untouched by selection.

Root-caused two separate things, not one:

1. **Why full substitution regressed:** spacing adds a *symmetric* +/-11 cm offset around the
   two feet's midpoint. An unweighted midpoint of the post-spacing targets equals the
   pre-spacing midpoint exactly, but pelvis centering is `ground_weight`-*weighted* when the
   two feet's weights differ - a weighted average of asymmetrically-weighted, symmetrically-
   offset points does not equal the original weighted average. That mismatch is the likely
   source of the regression, not "using the accepted target" in general.
2. **A separate, real, pre-existing gap, predating every slice above:** pelvis centering and
   the post-`resolve_stationary()` reach-recompute both read
   `leg.get("target", leg.get("ground_target", ...))` - but `target` and `ground_target` are
   *both always set* on every leg every frame
   ([player_foot_ik_modifier.gd:686-687](../actors/player/player_foot_ik_modifier.gd)), so that
   fallback chain always resolves to `target` and silently ignores `prefer_ground_target`,
   which the actual leg solve has honored (via the coordinator) since the target-selection
   slice. Pelvis has quietly never respected that preference, in old code or new.

Three approaches were discussed with the user:

- **A - tried 2026-09-12, reverted, regressed.** Added `plan.pelvis_reference_target` = the
  fully-selected target (respects `ground_target`/`seam_hold`) minus its `spacing_delta`; pelvis
  centering and the reach-recompute read this instead of the raw dict fields. Sidestepped
  finding 1 by excluding the spacing offset as designed, but missed a second inheritance path:
  when the coordinator's plan fails its own validation (support/reach), `_raw_recovery_plan`
  supplies a fallback target meant for the *leg solve* to have something reasonable that frame -
  not a stable reference. `pelvis_reference_target` inherited that per-frame recovery churn,
  which the old code never saw (it read the stable `leg["target"]` field directly, untouched by
  coordinator validation state). Full suite: **2 new unexpected failures** (`Foot IK animation
  comparison check`, `Foot IK rendered-body stair penetration check`); `walk_right` showed
  `worst_added_deg=8.296` against a 4.5 deg allowance and `edge_ratio=1.499` against a 1.25
  limit - a real, visible pose distortion during ordinary walk locomotion (not just the
  idle/stationary paths this slice was scoped around). Reverted cleanly; suite back to 41
  passed / 7 known failures / no unexpected failures.
- **B:** skipped - user chose to go straight to C.
- **C - tried 2026-09-12, implemented via three sub-sections, automated suite clean.** User
  approved all three sections in chat before implementation (brainstorming skill's
  architectural path); user also explicitly asked to see automated-regression findings and test
  live before any revert, changing the iterate-then-revert workflow used for A.

  1. *Joint restructuring:* `FootIKTargetCoordinator.finalize_leg_targets()` now runs upper-
     foot/slope adjustment right after `resolve_stationary()`, before the modifier derives
     pelvis - previously these ran after pelvis was already fixed for the frame, so pelvis
     never reflected their output. Uses last frame's stable `_smoothed_shared_drop`/
     `_pelvis_lateral_shift` as an estimate hip for this math (bounded one-frame lag, since
     those values are already rate-limited/smoothed). The modifier's final per-leg solve loop
     now just reads `leg[&"final_target"]` instead of recomputing upper-foot/slope a second time.
  2. *Spacing/weighted-midpoint reconciliation:* pelvis centering uses spacing's own plain-
     midpoint basis (not a `ground_weight`-weighted one) for a pair with `spacing_requested`,
     avoiding the original approach-A regression mechanism. Never actually implicated in any
     regression this round - included from the start, unchanged throughout.
  3. *Raw-recovery staleness:* `pelvis_reference_target()` holds each leg's last known-good
     final target (`_last_good_final_target`) while that leg's plan is in `"raw_recovery"`,
     instead of reading the fresh per-frame fallback. Also unchanged throughout, not the actual
     cause of either regression found this round (see below) - `_apply_raw_recovery` already
     mutated the legacy `leg["target"]` field directly in the pre-existing code, so pelvis was
     never actually protected from raw-recovery churn in the old code either; this section's
     value is real but was not the source of new instability.

  Two regressions found and fixed during implementation, both around a third mechanism outside
  the original three-section design:

  - **First finding (identical to approach A's regression, now root-caused precisely):** not
    spacing, not raw-recovery - `preserve_flat_pose`/`prefer_ground_target` can be true during
    ordinary flat-ground walking, not just idle (`is_flat_level_ground`, no animation-state
    gate). When true, `target` and `ground_target` are genuinely different values (animated
    foot position vs. a terrain-follow candidate). Both approach A and this first C draft made
    pelvis honor that preference unconditionally, distorting ordinary walk pose - two
    independently-built fixes hit the exact same 8.296-degree `walk_right` failure because they
    shared this one unexamined assumption ("respecting `ground_target` preference is a strict
    bugfix"), not because of anything either fix actually changed on purpose. Fix: pelvis reads
    a `pelvis_basis_target` that excludes the `ground_target` substitution.
  - **Second finding (introduced by the first fix):** applying that exclusion unconditionally
    made a *different*, narrower metric worse - the idle-loop seam check's `max_knee_step_m`
    rose from `0.0111` (passing) to `0.0124` (failing a `0.0120` limit), because the same
    exclusion was now also touching the non-seam-held leg during ordinary idle standing, where
    `target`/`ground_target` rarely diverge and pelvis had actually been fine using
    `ground_target` there. Fix: gate the exclusion on `not stationary` - only avoid
    `ground_target` for pelvis during actual locomotion, not idle.

  Final full suite: **41 passed / 7 known failures / no unexpected failures** - matches the
  pre-work baseline exactly. `walk_right`/`walk_left`'s raw `FOOT_IK_LOCOMOTION_CHECK` lines
  still show `FAIL` with `worst_added_deg` around 4.57/1.585 (down from 8.296/uninvestigated
  pre-existing), but both are inside the already-known-failing `check_foot_ik_locomotion.sh`
  script, so the harness does not (and did not, at any point in this investigation) flag them
  as new - this pre-existing walk-locomotion gap was not fully closed, only measurably improved
  as an incidental side effect of chasing the two regressions above. Idle-loop seam check:
  `max_knee_step_m=0.0111`, matching the very first (unrefined) C draft exactly.
  **Live-confirmed by the user** (idle, walk, stair/split-stance) - no visible issues found;
  committed as `88884a2`.

### Constraint reason/expiry mechanism — implemented 2026-09-12, committed

Finding C's remaining completion-criteria gap ("reasons/expiry ... the enum alone does not
strengthen validation"). Brainstormed as a bounded change; user chose a general per-constraint
mechanism over scoping to just the one existing user (the toe/leaf envelope's streak tolerance).

- `FootIKTargetPlan` gained `constraint_reasons`/`constraint_expiry_frames` (`Dictionary`, keyed
  by constraint name - `"stance"`/`"support"`/`"reach"`/`"toe"`), populated only while that
  constraint is actually degraded; absence means "not currently degrading," not "fine forever."
  No change to the four existing `_status` enum fields or their call sites - purely additive.
- Wired for `"toe"` in `_finish_validation`: while `TEMPORARILY_TOLERATED`, records
  `"toe_envelope_blocked"` and a live countdown (`TOE_INVALID_HOLD_FRAMES` minus the current
  streak) toward the frame the tolerance actually expires. No other constraint has a tolerance
  mechanism yet, so their dictionaries stay empty - a future one can adopt this by name with no
  schema change.
- Exposed in `foot_ik_trace_writer.gd` (`plan_constraint_reasons`/`plan_constraint_expiry_frames`)
  so this is observable in a live trace, not just internal state.
- New [constraint-expiry regression check](../tests/manual/foot_ik/foot_ik_constraint_expiry_check.gd),
  wired into fast/all runners: drives the toe streak through a full tolerance window with a
  lightweight coordinator stub, asserting the countdown decreases monotonically to the exact
  expected value each frame, then that both the reason and expiry entries disappear once the
  tolerance genuinely expires (`_raw_recovery_plan`'s own `NOT_APPLICABLE` toe status takes
  over - discovered live while writing this test, not a pre-existing assumption) and again once
  the toe becomes valid again. Verified to actually fail when the expiry computation was
  deliberately broken, then restored to confirm a clean pass.
- Full suite: 44 passed (up from 43) / 7 known failures / no unexpected failures.

### Candidate-evaluation extraction — implemented 2026-09-11, live-confirmed 2026-09-12

User live confirmation: "i see no diff", the expected outcome for this extraction. The
requested commit/push checkpoints the tested Foot IK tree, including the earlier task 019
changes it depends on. This confirms visual equivalence, not resolution of the known failures.

- `FootIKLegSolveInput` captures values, animation poses, settings, contact context and history;
  evaluation does not read live nodes, physics time, settings resources or owner callbacks.
- `FootIKLegPoseEvaluator` computes hip-through-leaf output and release-to-animation output
  using its own history/diagnostics copy. Existing intra-evaluation read-after-write order is
  preserved; this is an output-preserving extraction, not new knee/contact policy.
- `FootIKLegSolver.capture_input()` / `evaluate_candidate()` allow several target candidates
  against the same snapshot. `commit_candidate()` alone publishes the selected history/debug
  state and writes bones; wrong-solver/skeleton, stale-frame/revision and duplicate commits
  are rejected. Existing `solve()` and release callers evaluate and accept immediately.
- This is **once per accepted candidate**, not a new once-per-physics-tick policy. Existing
  repeated accepted-call timing remains unchanged. The revision is currently solver-wide;
  independently evaluated left/right results cannot both commit from one old revision.
  Joint feet/pelvis acceptance, full constraint reports and final skin clearance remain future work.
- Existing target-policy queries and direct guard probes retain explicit publishing adapters;
  they are outside candidate evaluation. Do not route candidate searches through those adapters.
- Durable coverage:
  [candidate evaluation scene](../tests/manual/foot_ik/foot_ik_candidate_evaluation_check.gd),
  wired into fast/main/all runners. It checks snapshot isolation, rejected-candidate isolation,
  repeatability, wrong-skeleton/stale/duplicate/reset invalidation, and solve-path equivalence.
  Its 720 samples cover both legs, idle/walk/crouch/landing, slopes, loop holds, acquisition,
  release/degenerate targets, 30/60/120-Hz-sized deltas, zero-delta and repeated same-tick calls.
  Different delta sizes are not a full live physics-rate validation.
- Local A/B against the saved pre-extraction dirty-tree solver passed all 720 samples:
  bone transforms agree within Godot's approximate transform comparison; history and diagnostics
  agree exactly. The optional `FOOT_IK_REFERENCE_SOLVER` environment variable selects that
  historical script; ordinary regression runs need no external reference file.
- Full comparison: **39 passed / 7 known failures before -> 40 passed / the same 7 known
  failures after**. The extra pass is the new regression. All six emitted raw
  `FOOT_IK_* FAIL` metric lines match the baseline exactly; the two ramp matrices also
  retain their failure counts and worst depths. No baseline limits or fixtures were widened.
  Logs and saved reference: `/tmp/foot-ik-018-evaluation.GZg8ik/`.
- Local scene-based A/B microbenchmark (240 solves): **79.5 µs new vs 43.6 µs old per solve**.
  Snapshot isolation adds about 0.036 ms/solve in this fixture; do not describe the extraction
  as performance-neutral. This is not a one-player or stress-preview frame budget. Profile
  snapshot reuse/allocation costs as the plan boundary is consolidated; finding H remains open.

Candidate-extraction validation map (2026-09-11, headless, sequential; live preview not opened):

| Entrypoint | Result |
| --- | --- |
| `scripts/check.sh` (through fast) | PASS: project lint/import/parse. |
| New candidate scene, normal and saved-old-solver A/B | PASS: 720 samples each; no script errors. |
| `scripts/check_foot_ik_fast.sh` | Stops at existing planted-idle failure; `turn_penetration_m=0.109297`, unchanged. |
| `scripts/check_foot_ik.sh` | Independently stops at the existing unreachable lower-support acquisition failure; all-runner map covers the later checks. |
| `scripts/check_foot_ik_all.sh` | 40 pass / 7 known failures / no unexpected failures; core failures: unreachable acquisition, walk-to-idle stance, planted-idle stability. |
| `scripts/check_foot_ik_ramp_locomotion.sh` (independent child of all) | Existing failure, raw failure metrics unchanged. |
| `scripts/check_foot_ik_stair_repeat.sh` (independent child of all) | PASS. |
| `scripts/check_foot_ik_locomotion.sh` (independent child of all) | Existing failure, raw failure metrics unchanged. |
| `scripts/check_foot_ik_ramps.sh` (independent child of all) | 20 failing cases; worst depth 0.013232 m, unchanged. |
| `scripts/check_foot_ik_ramp_sweep.sh` (independent child of all) | 16 failing cases; worst depth 0.105375 m, unchanged. |

## Overall assessment

Original 2026-09-09 assessment and evidence follow; use the progress table above for current status.

**A capable, well-instrumented prototype with valuable production building blocks, but not yet
a consistently enforced IK architecture. Improve its boundaries incrementally; do not rewrite
the whole system or keep adding independent corrective layers.**

The Foot IK core is about 5,195 lines across 12 files, including comments and experimental
paths. Size alone is not the problem. The expensive complexity is implicit state shared across
modules, validation that does not necessarily describe the solved pose, and several places
where the same decision can be changed. Splitting a 1,000-line file without changing those
contracts would not solve that problem.

Important changes since the earlier review:

- [010](010_foot_ik_target_coordinator_consolidation.md) now concludes migration of the 11
  ground-anchored owner categories. `STAIR_SWING` is intentionally exempt from planted-ground
  validation. Do not describe these owners as still waiting to be migrated.
- That is routing coverage, not universal validation coverage: gates, exemptions and later
  target changes still exist in current code.
- [012](012_foot_ik_ramp_cross_slope_penetration.md) records actual wall-normal and slope-recovery
  fixes, and classifies remaining floating-slab edge cases as accepted fixture limitations.
  Its older “no ramp fix yet” measurement notes are not the latest runtime status. The general
  clearance evaluator remains diagnostic, not a production pose guarantee.
- At the original review, uncommitted work included successful-search cooldowns, landing-search failure
  cooldown, compressed-upper-foot handling, and weighted pelvis centering from
  [014](014_foot_ik_preview_scene_fps_collapse.md)/[017](017_foot_ik_balanced_weight_bearing_pose.md).
  Account for these improvements; do not propose their already-present fixes again.

## What is good and should stay

1. **Correct basic layering.** Bone writes live in `SkeletonModifier3D`; movement stays in the
   character controller. Sampling, gait, landing, stair prediction, and bone solving have
   identifiable modules. The coordinator and `FootIKTargetPlan` are useful seams to strengthen.
2. **Animation-first behavior.** Flat-ground pass-through, explicit release-to-animation,
   loop-seam handling, and pre-pelvis animation snapshots protect authored motion. The release
   reference-frame regression from 013 is a particularly useful small contract test.
3. **Rig-derived geometry.** Rest lengths, sole direction, a two-vector foot orientation frame,
   toe/leaf offsets, and measured skin depth are substantially better than asset-specific ankle
   constants alone. Weighted/rate-limited joint positions are rebuilt from rigid segments.
4. **Terrain-specific semantics.** Continuous ramps and discrete stair treads are distinguished;
   acquisition destinations are not confused with unsupported intermediate waypoints. An
   airborne swing should not be required to satisfy a planted-foot support test.
5. **Strong debugging assets.** Raw/smoothed/solved values, ownership reasons, final-joint
   quaternions, skin-volume checks, exact live replays, edge sweeps, and bounded trace storage
   are worth preserving. The cached clearance sampler retains exact geometry; 012 documents
   its agreement against the full reference rather than assuming a few toe points suffice.
6. **Useful performance lessons already applied.** Primitive authored collision and retry
   cooldowns address query cost rather than only timing the arithmetic solver. Keep the
   multi-character stress scene distinct from the one-player performance budget.

## Findings, ordered by leverage

### A. High: the validated plan is still not the authoritative solve input

Evidence: [modifier](../actors/player/player_foot_ik_modifier.gd),
`_apply_support_pelvis_and_legs()` (approximately lines 858-1000).
After `resolve_stationary()`, the modifier can change foot spacing, choose `ground_target`
instead of `target`, call `straighten_compressed_upper_target()`, call
`adjust_idle_slope_target()`, or substitute `debug_solve_target` across a seam. It still passes
`target_plan_validated` to the solver. The solver uses that flag to bypass a late stance guard.
The slope adjustment searches along a plane without checking the finite support underneath
the resulting point. These are confirmed call paths, not a newly reproduced clip.

The new post-coordinator reach recomputation is useful, but still precedes spacing changes,
pelvis lateral movement and the final target adjustments. It also only increases the earlier
`shared_drop`; it is not a fresh solve of the final pair of targets. Its horizontal-distance
term is capped at 0.09 m², so it is a heuristic, not proof of anatomical reach at larger offsets.

Improve: generate candidates first, jointly select feet and pelvis, then freeze the actual
solve inputs. Record both proposed and accepted targets. Move each late target adjustment
behind this boundary one at a time; do not remove its behavior blindly.
Acceptance: actual solve target equals the accepted plan; final pelvis/feet satisfy the
declared reach contract, or explicitly report a degraded outcome.

### B. High: evaluation and state advancement are not consistently separated

Evidence: modifier `_step_down_classification()` increments its streak without a delta/tick
guard (lines 763-770); coordinator `_finish_validation()` increments `_toe_invalid_streak`
without one (lines 196-200). Both are reachable from a zero-delta modifier evaluation.
Modifier line 934 also selects the full `target_shift` at zero delta rather than preserving
the previously smoothed pelvis shift. In contrast, solver `_limit_correction()` guards both
zero delta and repeated physics-frame advancement.

This is inconsistent refresh behavior visible in code. Whether a particular scene manifests
a snap still needs a replay; do not label every zero-delta recalculation a bug. Paused editing
must still be able to refresh a changed pose/settings value.

Improve: introduce an explicit frame context (`physics_tick`, `dt`, pose/settings revision),
separate state advancement from output evaluation, and commit history once per tick. A refresh
can reevaluate new inputs, but must not consume time/streak/rate budgets.
Acceptance: compare `tick -> refresh -> refresh` with `tick` alone; include paused settings
changes, loop resets, landing, and 30/60/120 Hz physics. Retain existing zero-delta recovery tests.

### C. High: “valid” conflates checked, skipped, tolerated and degraded

Evidence: [coordinator](../actors/player/foot_ik/foot_ik_target_coordinator.gd), `_build_plan()`
sets stance/reach true on pass-through (lines 124-127). `_finish_validation()` sets `toe_valid`
true for an exemption or a short failing streak. `_raw_recovery_plan()` intentionally skips
toe validation. A lower transition on either leg disables migration validation for unrelated
owner types through `legacy_transition_active` (lines 42-43, 119-120). Most ground gates and
`_has_support_at()` are still flat-only; `STAIR_SUPPORT` has a separate gate and toe exemption.

Improve: each constraint should report `satisfied`, `violated`, `not_checked/not_applicable`,
or `temporarily_tolerated`, with reason and expiry where relevant. Keep fallback behavior,
but identify it as degraded instead of granting a guarantee it did not establish. Document a
small owner/terrain/transition contract matrix; joint planning should explain cross-leg gates.
Acceptance: a skipped check cannot report “checked and satisfied”; swing paths still validate
their own reach/continuity/collision contract without requiring ground at the waypoint.

### D. High: no candidate-pose/result boundary or final clearance guarantee

Evidence: [solver](../actors/player/foot_ik/foot_ik_leg_solver.gd), `_solve_impl()` combines
selection, blending, rate limiting, history mutation, anatomical corrections and bone writes;
`_solve_toes()` adds the remaining chain. `_select_feasible_bend()` can return the preferred
bend when no feasible sample exists, and its temporal interpolation is not itself a proof
that every constraint remains satisfied. There are useful downstream guards, but no complete
post-output constraint report. The box/skin clearance tools are not invoked by the runtime.

Improve: extract a `LegPoseResult` containing hip-through-leaf output, diagnostics, feasibility
and tentative history. Evaluate candidates against the same immutable input/history, then
apply and commit the selected result once. Preserve current output before introducing any
clearance-driven candidate changes. Bound correction attempts and define the outcome when
contact, anatomy and continuity cannot all be satisfied; do not hide that conflict with a clamp.
Acceptance: extraction is pose-equivalent; rejected candidates do not alter history; validation
measures the final blended/rate-limited skin, not only the ideal ankle target.

### E. High for diagnostics: “final pose” has multiple incompatible sources

Evidence: `PlayerBody._build_character_visuals()` adds the look modifier before Foot IK
([player_body.gd](../actors/player/player_body.gd), lines 353-360). The look modifier caches
pelvis/spine/head/arms during its own pass. `get_visual_bone_global_pose()` (lines 694-697)
always prefers that look cache, although later Foot IK may move the pelvis and inherited body.
`FootIkTraceWriter.capture_body_chain()` consumes this accessor. Foot IK also caches all bones
at the end of its own pass; with the native backend, a separate `TwoBoneIK3D` applies afterward.

The code therefore does not establish that all “visual/final” consumers observe the same
post-modifier pose. Exact visible error depends on modifier scheduling and needs live validation.
Improve: publish one explicitly ordered final-pose snapshot after all enabled modifiers, tagged
with frame/revision/backend; traces and attachments should select that snapshot intentionally.
Acceptance: pelvis, head, feet, toe/leaf and skin probes agree with the actually rendered chain
under pelvis shift, native IK, look/grip and mantle transitions.

### F. Medium: experimental modes do not share a complete lifecycle contract

Evidence: common `reset_runtime_state()` resets solver/gait/sampler/coordinator/stairs, but not
the residual or phase-locked correctors. Those objects retain pelvis offset, weights, and
(phase-locked) world targets/timers. The feature panel changes modes and calls that common
reset, so “reset” does not clear every mode's state.

**Dedicated test added 2026-09-12** (`d1104ca`'s residual/phase-locked/native reset wiring
already fixed the code; this closes the "needs a dedicated test" gap):
[foot_ik_mode_switch_check.gd](../tests/manual/foot_ik/foot_ik_mode_switch_check.gd), wired into
fast/all runners. Directly pokes both correctors' full declared state, calls
`reset_runtime_state()`, and asserts every field is back to its default - verified to actually
fail (all four residual fields flagged) when one reset call was temporarily disabled, then
restored. This is a white-box state-clearing check, not the full pose-continuity acceptance bar
below (mode A -> B -> A with a real skeleton/animation, teleport, rig replacement) - that
broader scene-level test remains open. `feature panel changes modes and calls that common
reset` is confirmed to be the only reachable runtime mode-switch path (no gameplay code sets
`locomotion_mode` directly), so this check covers the actually-exercised route.

The native adapter also has no common reset. `_smoothed_bases` is assigned in the preserve-idle
branch but not updated after ordinary target calculation, so its interpolation can repeatedly
use an old idle orientation rather than the last output. Native input preparation clamps its
own targets/poles, while custom-only adjustments run after the native dispatch: comparisons
are not purely different solvers consuming identical final inputs.

Improve: explicitly label production/default versus experimental paths; give every mode/backend
`reset`, `enter`, `exit`, capabilities and output contracts. Hide unsupported feature combinations
in the panel. Do not delete the alternatives until their comparative value is assessed.
Acceptance: mode A -> B -> A, airborne/grounded, enable/disable, teleport and rig replacement
leave no stale target, correction, timer or debug output.

### G. Medium: support identity, motion and query policy are missing abstractions

Evidence: sampler `raycast_ground()` (lines 808-824) discards collider/RID/shape identity and
returns only hit/position/normal. Locks primarily retain world points and surface heights.
`Player` reaches through `body._foot_ik_modifier._ground_sampler` to read/reject root nudges and
run airborne planning (lines 519-529, 920 onward). Animation classification is spread across
substring checks and exact clip aliases; `PrototypeBodyFacade` must subclass `PlayerBody` to
reuse Foot IK even when its animation source is different.

Improve: typed `ContactObservation` with surface identity/local anchor/normal/walkability;
typed movement and animation context instead of clip-name inference; versioned, expiring root
correction requests consumed by movement with accept/reject feedback. Keep body translation
under the movement controller. Moving/disappearing supports are future coverage requirements,
not claimed regressions in today's static fixtures.

Collision contract debt, naming - **fixed 2026-09-12**: layer 5 and 6 were named `projectiles`/
`ai_perception` in `project.godot` while actually holding `CONTINUOUS_TRAVERSAL_LAYER` (stair
traversal) and `CONTACT_SURFACE_COLLISION_MASK` (foot IK ground contact) respectively - a pure
label change (no bitmask/behavior touched, confirmed no code references the old name strings),
renamed to `stair_traversal`/`foot_contact_surface`. `scripts/check.sh` clean. The underlying
typed-abstraction/root-request-feedback work below remains open; area exclusion still does not
resolve a naming/solid-body mask collision on its own.

### H. Medium: cooldowns help averages, but do not establish a per-frame budget

The success/failure cooldown additions are worthwhile. However, candidate loops still execute
synchronously: split-safe ring searches, 36 compressed-upper candidates with nested support
queries, retraction, and landing footprint searches. Some non-split failure searches have no
cooldown. Solver bend selection also scans 145 candidates and can be queried repeatedly by
target searches. No central query counter/budget makes the maximum work explicit.

Improve: measure queries and time by owner, cache observations within a tick, invalidate on
meaningful movement/support changes, and amortize only the expensive optional searches. Keep
immediate essential contact queries separate from deferred recovery work. Measure p95/p99 and
worst-frame physics/solver time, not only average FPS; preserve supported targets during deferral.
Do not assume a native rewrite is necessary before profiling these boundaries.

### I. High for confidence: extensive tests, but the runner can hide deterioration

- `check_foot_ik_all.sh` recognizes known failures by whole check/script label. A new or much
  deeper failure inside an already-red ramp script is still “known”; exit 0 means no new
  labels, not all poses clean. **Fixed 2026-09-12:** it and `check_foot_ik.sh` now both run
  `scripts/check.sh` as their first step (`run_subscript`/a direct call respectively), so a
  clean run of either now does guarantee a clean lint/import/parse too - previously only
  `check_foot_ik_fast.sh` caught that gap. Full suite: 43 passed (up from 42) / 7 known
  failures / no unexpected failures; `check_foot_ik.sh` run standalone now completes with
  exit 0 (a side effect of this session's other fixes, not independently investigated).
- ~~`check_foot_ik_fast.sh` matches the core preview's six result names with an OR expression~~
  - **already fixed by `ec3cf35`** (see progress table): `run_scene_all` loops every expected
  pattern and fails on the first missing one, real AND semantics; the fast runner's call site
  passes all six. This bullet was stale, not a remaining gap - verified 2026-09-12.
- ~~The `_all` grouped-log helper checks PASS markers without the SCRIPT ERROR test~~ - **also
  already fixed by `ec3cf35`**: `run_check_in_log` checks `SCRIPT ERROR` identically to
  `run_check`. Also stale, verified 2026-09-12. Engine exit status/completion handling across
  the three runners was not otherwise re-audited.
- `.github/workflows/project-checks.yml` is manual-only and runs project lint/import/parse,
  not the behavioral IK suites. Lists are duplicated across fast/main/all scripts.

Improve: one case manifest; all required outcomes and clean process completion must pass.
Separate harness errors from behavioral failures. Store expected failures by exact case and
metric bound, with reason and expiry/review date; preserve raw per-case artifacts. Test the
runner with synthetic mixed PASS/FAIL output and crashes. Then add cheap contracts/fast checks
to CI, keeping exhaustive terrain replays sequential. Do not “fix” red cases by widening fixtures.

Coverage to add at new seams: repeated refresh/state advancement, reset across every supported
mode, final-plan/solve equality, per-constraint status, final-pose cache agreement, invalidated
support, and query budgets on successful as well as failed recovery. Existing exact live replays
remain acceptance tests; replace neither them nor meaningful edge/diagonal coverage with mocks.

## Balance and the other procedural layers

017's weighted midpoint is a reasonable small heuristic. In current code `ground_weight` comes
from gait/contact blending; it is **not measured load**. When both weights are 1, the new formula
is identical to the old midpoint, so it cannot by itself resolve every fully planted awkward
stance. Define the desired stance/weight-transfer behavior before adding torso counter-lean.
Keep preferred balance separate from hard reach/clearance constraints and account for the
existing look/stair-balance layer and its ordering. Do not equate a pelvis proxy with a proof
of physically balanced dynamic motion.

The small look/grip/mantle components have useful bounded responsibilities; they need not be
absorbed into a giant full-body solver. Mantle IK currently reuses private retargeter math and
aims the forearm using a hand position captured before the upper-arm write. Review that
pre/post-parent-frame combination and repeated evaluations before promoting it beyond the
prototype; a post-parent hand re-read and a rigid-chain fixture can test it. Give shared
two-bone math a public pure utility only when extracting it preserves both callers' semantics.

## Recommended implementation order

Proposed data flow (not an instruction to rewrite everything at once):

`animation/frame snapshot -> contact observations -> feet + pelvis plan -> candidate pose`
`-> final constraint report -> apply pose + commit history once -> published final snapshot`

1. **Make evidence trustworthy first.** Fix mixed-result/exit handling, granular baselines and
   authoritative final-pose measurement. Establish the current dirty-tree baseline before
   changing behavior. Keep known fixture limitations explicitly separate from regressions.
2. **Make lifecycle/time explicit.** Add reset/refresh contracts and mode-switch tests. Repair
   confirmed omissions in isolated changes; do not simultaneously retune smoothing constants.
3. **Extract solve/evaluate/apply without changing output.** Preserve current custom behavior,
   solve/release coordinate frames and full-chain poses. Add tentative history and result types.
4. **Make the plan authoritative.** Migrate spacing, upper-foot adjustment, slope adjustment,
   seam selection and shared pelvis calculation individually. Introduce constraint status and
   explicit fallback precedence; keep contact acquisition and swing contracts distinct.
5. **Then choose the next feature.** Decide whether real gameplay needs 012's general clearance
   correction, 017's stronger balance policy, or moving supports. Add bounded candidate
   evaluation only for a measured need; specify behavior when no acceptable solution exists.

Use static typing at the boundaries first (`FrameContext`, `ContactObservation`,
`FeetPelvisPlan`, `LegPoseResult`, `ConstraintReport`), not a mass conversion of every dictionary.
Reduce direct `_owner` access as each boundary is extracted. Keep the 1,000-line lint ceiling;
extract coherent responsibilities rather than compressing comments/functions to fit it.

For behavior-changing stages, run the fast suite during iteration and the complete independent
entrypoint map before acceptance; compare metrics inside known-red labels as well. Require the
user's live confirmation before committing. Do not auto-play the preview.

## Feature candidates and focused online research

Proposals, not approved as a batch; see current progress above for parked/prototype work.
The architectural contracts above come
first. A focused primary-documentation check was performed on 2026-09-09; this was not an
exhaustive investigation or a source-code port. Research each selected feature's blending,
coordinate spaces, failure behavior and runtime cost before implementing it here.

1. **Animation-authored contact timing.** Per-foot curves express intended plant/roll/release
   phases, supplementing the existing velocity/threshold inference. Physics still confirms
   support; a curve must never invent ground. Epic's Foot Placement supports per-foot speed
   curves for plant decisions, a useful reference rather than an identical contact-phase API.
   [Foot Placement](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/AnimationWarpingRuntime/FAnimNode_FootPlacement?lang=en-US)
2. **Deliberate recovery steps.** Replace repeated sliding readjustments with one supported
   destination and a bounded lift-move-plant action with completion/cancellation conditions.
   Consolidate existing repositioning and connect to existing turn-in-place work, rather than
   adding a competing target owner. This is our design proposal, not a claimed Unreal feature.
3. **Heel/toe contact modes.** Permit controlled heel lift while maintaining supported toe/ball
   contact, with explicit contact-area and full-foot clearance validation. Coordinate this
   with pelvis movement rather than always flattening the whole foot or dropping the hips.
   Epic exposes heel-lift preference and separate planting controls.
   [Pelvis settings](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/AnimationWarpingRuntime/FFootPlacementPelvisSettings?lang=en-US),
   [plant settings](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/FootPlacementPlantSettings?application_version=5.6)
4. **Stride-length adjustment.** Conservatively match animated stride to actual travel speed
   to reduce skating. Place it in locomotion before terrain correction, not in a late planted-
   foot override. Evaluate it alongside current playback-rate/directional animation behavior.
   [Pose/stride warping](https://dev.epicgames.com/documentation/unreal-engine/pose-warping-in-unreal-engine?lang=en-US)
5. **Moving-support anchors, if gameplay needs them.** Retain foot contacts in platform-local
   space with support identity; release on disappearance or excessive reach. World-space locks
   alone are insufficient for this design. Test translating/rotating platforms and support
   changes before claiming moving-platform support.
6. **Portable bug-replay bundles.** Save input history, settings, animation/rig and scene
   identity, starting state or sufficient warm-up, and expected constraints together. Reuse
   the existing trace/replay infrastructure to reproduce bugs and promote them to regressions.

Suggested feature order after the contracts: **contact curves -> deliberate recovery steps
-> heel/toe behavior**. Portable replay tooling can accompany the validation work immediately;
stride adjustment and moving supports follow demonstrated gameplay need. Stronger balance
remains in [017](017_foot_ik_balanced_weight_bearing_pose.md). Defer full-body IK, automatic
torso compensation and more smoothing controls until ownership/time contracts are reliable.

## Completion criteria for the follow-on work

These are end-to-end acceptance gates, not a count of commits. They remain open where only
a targeted fix or extraction is implemented; see the extraction's current validation above.

- [ ] All required checks are reported; a worsening known case cannot be hidden by its label.
- [ ] Every supported mode resets fully; refreshes do not advance temporal state twice.
- [ ] Accepted plan and actual solve inputs agree, including shared pelvis and support identity.
- [x] Custom leg candidate evaluation is non-mutating; only the accepted output commits
  history/bones (headless comparison passed; user confirmed no visible difference on 2026-09-12).
- [ ] Constraint reports distinguish satisfied, skipped, tolerated and degraded results.
- [ ] Final published poses match rendered output across enabled modifier/backend combinations.
- [ ] Worst-frame query/correction work has an explicit measured budget.
- [ ] Existing live replays and authored flat-ground behavior remain intact.
