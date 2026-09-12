# 018: IK implementation review and improvement plan

## Status and scope

**In progress.** Original review completed 2026-09-09; progress audited 2026-09-11 at
HEAD `ff05f2f`, including the existing dirty working tree. Eight commits on 2026-09-10
implement targeted fixes and initial architecture extractions; the end-to-end contracts
below are not yet complete. This status update is a code/history audit, not a runtime fix
or fresh test certification.

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
| I — runner reliability | `ec3cf35`: require all six preview results, check grouped script errors, and compare ramp failure counts/depths. | Exact-case baselines, consistent crash/completion handling, shared case manifest and behavioral CI; broad known-failure labels still hide deterioration. |
| B — time/refresh | `7f8f602`: guard specific streaks against zero-delta/duplicate ticks; preserve pelvis smoothing on refresh. | Pipeline-wide frame context and once-per-tick history contract, with refresh/rate coverage. |
| F — lifecycle | `d1104ca`: reset residual/phase-locked/native state and update native orientation history. | Supported-mode lifecycle/capability contracts and dedicated mode-switch validation. |
| C — constraint status | `a0392d5`: replace validity booleans with satisfied/violated/unchecked/inapplicable/tolerated statuses. | Complete degraded-result reporting, reasons/expiry and owner/terrain contract coverage; the enum alone does not strengthen validation. |
| D — pose result/apply | `b60173f` introduced the result type; the live-confirmed extraction adds fixed inputs, candidate-local history/diagnostics and guarded acceptance (details below). | Final-output clearance/feasibility reporting and clearance-driven candidate selection. |
| E — final snapshot | `70bea29`: prefer fresh Foot IK poses for visual consumers and frame-stamp the cache. | Publish after every enabled modifier/backend, including native IK and any later balance layer. |
| H — performance | `dfee62e`: log worst-call/worst-frame solver timing. | Query accounting, explicit work budgets and broader tail-latency measurements. |
| A — authoritative plan | `c182d17`: invalidate the validation flag when covered late target edits change the selected input. | Move all late adjustments and shared pelvis selection behind the accepted-plan boundary. |
| G — typed integration | No implementation of the proposed abstractions identified in this audit. | Support identity/local anchors, typed motion/animation context, root-request feedback and collision-layer cleanup. |

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

Next architecture priorities are validating the candidate boundary and making feet/pelvis
planning authoritative, with trustworthy per-case regression evidence. Do not treat the targeted
fixes above as completion of the broader contracts or start all proposed features as a batch.

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

Validation map (headless, sequential; live preview not opened):

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
reset, so “reset” does not clear every mode's state. This omission is confirmed statically;
the resulting reentry pose needs a dedicated test.

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

Collision contract debt: layer 5 is named `projectiles` and layer 6 `ai_perception` in
`project.godot`, but stair traversal/contact helpers repurpose those bits, and runtime probes
include them. Reserve and name actual terrain-proxy/contact layers before broader gameplay use;
area exclusion does not resolve a naming/solid-body mask collision.

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
  labels, not all poses clean. It also does not invoke `scripts/check.sh` itself.
- `check_foot_ik_fast.sh` matches the core preview's six result names with an OR expression.
  One PASS satisfies that pattern; it does not require all six. The preview prints independent
  results in `_exit_tree()` and does not aggregate those failures into a failing exit itself.
- The `_all` grouped-log helper checks PASS markers without the SCRIPT ERROR test used by its
  ordinary helper. Engine exit status/completion/error handling is inconsistent between runners.
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
