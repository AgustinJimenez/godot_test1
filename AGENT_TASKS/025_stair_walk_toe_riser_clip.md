# 025: Recurring toe clip — startup fixed, walking fix revised after failed live test

## Status

**The startup clip is fixed, live-confirmed by the user (2026-09-13), verified against the full
fast suite (no regressions beyond the pre-existing task-019 baseline), and committed**
(`cd2a398` on `experiment/native-foot-ik`). Task 024 is fixed and committed separately.

### 2026-09-14 live-test failure and current continuation handoff

The user walked and turned on the stairs. The live instrumentation confirmed real clipping, so the
earlier ascent-only walking result below is superseded and must not be treated as accepted:

- preserved live trace: `/tmp/foot_ik_live_20260914_180604.jsonl` (860 frames, 17..876);
- 38 `[FOOT_IK_CLIP]` episodes in `godot.log`; representative direct events include right toe
  6.81 cm (frame 357), left ankle 3.43 cm (503), left toe 4.02 cm (554), and right toe 5.50 cm
  (559);
- schema-aware `toe-riser` analysis found deeper sustained episodes, up to about 25.35 cm left and
  27.46 cm right. The worst history was descent/turning, which the former one-way ascent regression
  never exercised.

The untracked walking regression now performs one uninterrupted **ascent -> natural 60-frame turn +
20-frame settle -> descent**, without teleporting or resetting IK. Its original round-trip result
was `FAIL depth_m=0.239155`. The test was also moved to `_process()` and requires
`has_fresh_final_bone_poses()` so it cannot combine the current root with stale prior-frame bones.

Implemented, still uncommitted and awaiting validation/live confirmation:

1. Descending locomotion is treated as discrete-tread traversal even when no higher-tread swing latch
   exists; its real destination surface is validated instead of an unsupported interpolation point.
2. The approximate pre-solve toe envelope no longer releases a descending locomotion leg before the
   actual evaluated-pose correction can run.
3. A toe-clearance retry may bypass the upright-shin limiter only for that measured retry; the limiter
   was otherwise forcing the corrected ankle back below the tread.
4. Residual clearance retries now resample the collider under the new deepest point. Pitch can move
   the deepest point from a lower box into the neighboring higher tread; reusing the first tread's
   height made all retries identical. Three vertical corrections are now actually evaluated.
5. Candidate clearance remains active during translation because the predictor can release before the
   trailing toe clears the final top tread.

These layers reduced the round-trip failure from 23.92 cm to 2.27 cm, then 1.25 cm. The remaining
top-transition case was traced to `preserve_flat_pose`: it released the walking leg to authored
animation before candidate safety ran, even while that preserved toe was already inside the riser.
The current attempt adds `preserved_pose_needs_clearance()`, a narrow
measured escape from preservation only when the current toe/foot/leaf is more than 2 mm inside a
horizontal box collider. Ordinary unobstructed flat walking should retain the authored-pose fast path.

Latest rerun after fixing the type annotation: the former 1.25 cm top-transition failure is gone,
but the expanded test now reaches a later bottom-transition case:
`FAIL depth_m=0.028407 frame=285 side=left joint=toe_tip`, point
`(14.87917, 0.321593, 0.339009)`, root `(15.0, 0.319111, -0.150733)`. Continue from that compact
case; do not undo the preserved-pose escape merely because the next uncovered episode is now worst.

Immediate next action: inspect the frame-285 bottom-transition episode above, then rerun
`foot_ik_walk_contact_check.tscn`. If it passes, confirm absence of every `FOOT_IK_025_*` temporary
print, run the candidate check,
`scripts/check.sh`, and `scripts/check_foot_ik_fast.sh`, then ask the user for a live stair retest.
Do not commit gameplay/animation changes until that live result is confirmed. No scene should be
autoplayed for the user.

### 2026-09-15 state after pulling main (987c885) — top-transition fixed, bottom remains

- Merged `origin/main` (`987c885 "Optimize flat-ground foot IK"`, which adds `_can_skip_flat_ik`).
  That pushed `player_foot_ik_modifier.gd` over the 1000-line cap; trimmed back under it by
  condensing comments only (no behavior change). `scripts/check.sh` is green.
- **Top-transition clip (1.25 cm at frame 214) fixed.** Root cause: `preserved_pose_blocked` in
  `player_foot_ik_modifier.gd` required `_gait_tracker.is_body_translating()`, which is
  **velocity-based** and reads 0 while the stair controller moves the root by writing position. So
  the "preserved authored pose is already inside a box" escape never fired during stair travel, the
  leg was released to the authored pose, and the trailing toe clipped the top landing. Removing that
  velocity gate (keeping `preserved_pose_needs_clearance`'s own measured check) fixes it. Confirmed
  with a staged print: candidate and committed bone positions match exactly, and the controlled
  player simply never reached `solve_leg_candidate` (no `pos=(15.0,...)` entry) until the gate was
  removed.
- **Remaining failure is the documented bottom transition:** `FAIL depth_m=0.028407 frame=285
  side=left joint=toe_tip`, point `(14.87917, 0.321593, 0.339009)` — a 2.84 cm left-toe clip into
  step 0 while the body walks off the stairs onto the floor. Instrumenting the leg loop at f285
  shows the deciding pass has `leg["hit"]=false` -> the `not leg["hit"]` release branch fires, and
  that branch has **no** clearance escape (unlike `preserved_pose_blocked`'s `preserve_idle` path).
- **Tried "release with clearance" and reverted (does not work yet).** Added a coordinator
  `release_or_correct()` that, when the sampler finds no support, runs a clearance-only candidate
  with the current foot as target, instead of releasing to the authored pose. At f285 it returned
  `needs=false`: `preserved_pose_needs_clearance()` read the pose as **clean** at that call while
  the harness reads 2.84 cm at the same engine frame. Instrumenting both pose sources at f285 for
  the controlled player (`pos=(15.0, 0.319, -0.10)`):
  - `preserved_pose_needs_clearance` (reads `skel.get_bone_global_pose` at gate time): toe/leaf y
    `~0.41`, `pen=false`;
  - the captured animated pose (`capture_input(..., release_only=true).poses["toe"]`): toe y
    `~0.48`, also clean;
  - the harness (`get_final_bone_global_pose`, i.e. the modifier's `_final_bone_poses` snapshot):
    toe tip y `0.322`, 2.84 cm inside step 0.

  So there are **three different poses** and the published one (`_final_bone_poses`) matches
  neither the skeleton at gate time nor the captured animation.
- **Pass-count observation - NEEDS character-keyed confirmation (likely not two passes).** A
  per-instance pass counter printed two entries at f285 with left toe y `1.0747` and `0.3566`.
  Both filtered on `x ~ 15.0`, but the preview's own 0.35m stair walker also spawns at `x = 15.0`,
  and each printed counter value tracks its own frame number (~one call per frame per character).
  So these are probably **two different characters**, not two passes of the controlled player's
  modifier - a third instance of the multi-character trap. Do not conclude multi-pass from this;
  re-run with the actor path/skeleton instance id printed (as `foot_ik_clip_indicator` does) and a
  counter keyed per skeleton before trusting it.
- **What is solid regardless:** the clearance gate runs *before* its leg writes that frame, so it
  reads the pre-write skeleton pose, while the harness reads the post-write `_final_bone_poses`;
  those differ (monitor toe `~0.41` / captured animation `~0.48` vs published toe joint `0.3566`,
  tip `~0.322`). Any clearance decision keyed on the pre-write pose cannot see the pose that gets
  published. Preferred fix (chosen, not yet implemented): evaluate the pose the release itself
  would produce (solver release candidate) and, if its toe/leaf is inside a box, run the existing
  toe-clearance solve instead of releasing - option (1) from the two options considered, over a new
  global post-pass modifier (option (2)), because it reuses the proven `solve_leg_candidate` path
  and does not add a new correction stage to the chain.
- Tried and reverted as unnecessary: a position-derived `is_root_traveling()` added to the
  clearance gate and predictor (the gate was never the blocker once the velocity gate was removed);
  plus the earlier `is_descending_treads`/`is_body_translating` gate-widening attempts. Do not
  re-try gate widening - the real gate is the release path, not `stair_clearance_active`.

### 2026-09-15 blockers found while attempting the release-path fix

- **Started from a false premise (corrected):** removing the velocity gate on `preserved_pose_blocked`
  does **not** fix the top-transition 1.25cm; it only un-masks the larger bottom 2.84cm as the new
  max. Reverted - it also changed ledge behaviour. The top 1.25cm was present before and after.
- **`correct_released_pose` (release-path clearance) fixed the bottom transition but regressed
  `FOOT_IK_LEDGE_SAFETY_CHECK`**: the harness dropped the bottom 2.84cm, but ledge safety then failed
  (`idle_split_height_turn_pause_no_leg_snap_live_repro rendered foot snapped 0.581m`). Reverted.
  The chosen approach (measure the released pose, then clearance-solve with the released foot as
  target) works for its target case but needs a much gentler correction - a full-weight
  `solve_leg_candidate` to the released foot snaps the leg. Do not re-add it as-is.
- **Mock contract checks were broken by the uncommitted `descending_locomotion` guard**
  (`_build_plan` reads `_owner._stair_predictor.is_descending_treads()` unconditionally; the
  pure-function fixtures' mock `Owner` has no `_stair_predictor`). Fixed here: added a
  `_stair_predictor` stub to `foot_ik_spacing_plan_check.gd`, `foot_ik_constraint_expiry_check.gd`
  and `foot_ik_release_pose_check.gd`, and null-guarded the `_build_plan` access
  (`_owner.get("_stair_predictor") != null`). Fast suite now runs with **0 script errors**.
- **BLOCKER: the uncommitted fix currently regresses `FOOT_IK_LEDGE_SAFETY_CHECK`.** A/B: with
  every uncommitted change stashed (committed `HEAD`), `FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=16`;
  with them restored it FAILs `parallel_to_edge right shin swing 51.07 exceeds 45.00 degrees` and
  `idle_split_height_turn_pause_no_leg_snap_live_repro rendered foot snapped 0.581m at frame 123`.
- **Isolated by reverting file groups against that check:**
  - predictor alone -> 20 ledge failures (files are interdependent; not a valid isolation).
  - `foot_ik_leg_pose_evaluator.gd` + `foot_ik_leg_solve_input.gd` -> shin-swing failure gone,
    0.581m snap remains. So the **toe-pitch** (`_apply_toe_clearance_pitch`) causes the shin swing.
  - coordinator + solver + modifier -> ledge PASS. In the modifier, the exact hunk is the
    `_target_coordinator.solve_leg_candidate(...)` call (reverting just it -> PASS).
  - In the coordinator's retry, `retry_options[&"instant"] = true` causes the 0.581m snap:
    setting it to `false` removed the snap (leaving only the pitch's shin swing) but **broke the
    walking harness** (`depth_m` 0.012 -> 0.0956 at frame 244). So `instant` is load-bearing for
    the 025 fix and also the ledge-snap cause - a direct conflict, not a one-line bug.
- **Resolution applied (partial): option (b) - scope the retry to walking.** `solve_leg_candidate`'s
  `stair_clearance_active` is now `(is_active() or is_descending_treads() or is_body_translating())
  and _walking_animation()` (walk/sprint `current_animation`). Effect: `FOOT_IK_LEDGE_SAFETY_CHECK`
  drops from 2 failures to 1 (the 0.581m foot snap is gone), the walking harness is unchanged
  (`FAIL 0.012458`), and the fast suite has 0 script errors. So the `instant=true` snap is fixed by
  gating to walking.
- **RESOLVED (option b, extended): the ledge regression is gone.** The retry gate no longer uses
  the loose `_owner._gait_tracker.is_body_translating()` trigger - it is now
  `(is_active() or is_descending_treads()) and _walking_animation()`, i.e. only on real stair
  contact during a walk/sprint clip. `parallel_to_edge` is a *flat-ground* strafe near an edge, so
  it no longer triggers the retry and its shin over-swing is gone:
  `FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=16`. The walking harness is unchanged
  (`FAIL 0.012458`, top-transition), and `scripts/check_foot_ik_fast.sh` is back to its
  pre-existing baseline (only the known task-019 `FOOT_IK_IDLE_PLANT_STABILITY_CHECK` failure;
  0 script errors).
- **Rejected along the way (do not re-try):** lowering the toe-pitch cap (no effect); original
  `chain_weight` in the retry (worse); applying the upright-shin limiter during the retry (ledge
  passes, walking harness breaks to 0.092m); a surface-height heuristic (does not separate the
  cases); and disabling the foot-angle correction entirely - the walk fix was unaffected but the
  ledge over-swing *stayed*, proving it comes from the retry re-solving the leg at all, not from the
  foot angle. That last result also means the foot-angle pitch is not needed for the stairs and can
  be dropped as a simplification.
- Resolution options (context): (a) limit the retry pitch and/or route it through
  `_limit_correction`; (b) scope the whole retry away from idle ledge scenarios (done); (c) rate-limit
  only the pitch component.
- Current harness status unchanged: `FAIL depth_m=0.012458 frame=214` (top-transition 1.25cm); the
  bottom 2.84cm is only masked, not fixed.

### 2026-09-14 continuation checkpoint — walking fix implemented, awaiting live confirmation

The walking regression now passes headlessly. Do not commit yet: repository policy requires the
user to test gameplay/animation changes live first. No scene was opened or autoplayed.

The earlier 3-ascent claim below was invalid. The harness teleported a live Player back to the
bottom while retaining world-space IK locks; resetting IK after teleport created a different but
equally artificial discontinuity. The durable regression now performs **one uninterrupted ascent**,
waits for 10 consecutive grounded/active-IK frames before moving, and samples only after the player
reaches the staircase (`root.z >= -0.25`). The excluded 8.7 mm event was on the flat approach at
`root.z=-0.706`, not a stair/riser event. Baseline current-HEAD gameplay without this fix still
failed the real stair traversal at 7.33 cm.

Minimal implementation retained after isolating each experimental layer:

1. A discrete flat stair support owns chain weight at `1.0` during support handoff because its
   target position is already blended. Blending both target and weight let the low authored flat
   pose win twice and pull the toe into the higher tread. Slopes retain the existing weight blend.
2. A predicted swing latch is not discarded merely because it reaches the current support tread
   while contact weight is below `0.8`; releasing clearance before credible contact caused another
   late toe drop.
3. The target coordinator evaluates one immutable candidate, measures the **actual final** ankle,
   extrapolated toe tip, and leaf against nearby authored box colliders, and only on active stairs
   retries the same candidate when penetration exceeds 2 mm. The retry applies a bounded ankle-
   pivot toe clearance correction (maximum 35 degrees), full chain strength, and at most three
   vertical residual corrections, then commits exactly once. Ordinary flat gait and ramps do not
   enter this path. Performance timing now brackets the full candidate/check/retry sequence rather
   than being silently bypassed by the new evaluation route.

Removed after isolation because they were unnecessary and broadened the visible pose change:

- proactive toe pitching from predicted/support surfaces;
- disabling the standing shin-direction constraint for all discrete-stair frames;
- retaining stair ownership until every latch cleared (no measurable effect);
- candidate checks below ordinary flat support (did not fix the separate approach-floor event);
- instant-up swing lift and unreachable-support retention (earlier attempts; the latter produced
  catastrophic roughly 0.6 m clips).

Current targeted result:

```text
FOOT_IK_WALK_CONTACT_CHECK PASS samples=88 ascents=1 depth_m=0.001449
frame=91 side=right joint=toe_tip ascended_z=3.356
```

The check is now registered in `scripts/foot_ik_checks.inc.sh`, so main/all runners cannot omit it.
The candidate snapshot fixture was updated with the newly captured `toe_tip_margin`; its initial
omission caused explicit script errors and is fixed (`PASS samples=720`). The modifier remains below
the lint ceiling at 999 lines. `FOOT_IK_025_DIAG` temporary logging is absent.

### 2026-09-14 follow-up: all-suite "4 NEW failures" are false positives (user:// contamination + stale list)

`scripts/check_foot_ik_all.sh` on the checkpoint code reported four NEW (unexpected) failures, all
`foot_ik_knee_flex_check.tscn` scenarios. They are **not** caused by this fix:

- "Foot IK turning corner knee flexion check" fails on a **fresh clone of committed `HEAD`** too
  (`one-frame joint movement 0.553m`, limit 0.250m) - the all-suite's `KNOWN_BASELINE_FAILURES` list
  is stale for this scenario.
- "Foot IK landing contact-clearance check", "Foot IK late-input predictive landing check" and
  "Foot IK predictive landing safe-zone check" fail **only because of accumulated `user://`
  state**, not code. Method that proved it: clone the tree to a scratch dir, rename
  `application/config/name` in `project.godot` so Godot uses a fresh `user://`, `--import`, then run
  each scenario. On a fresh `user://`, both committed `HEAD` and the fix PASS all three (4/4 runs
  each); in the shared, long-lived `user://` they fail deterministically. This is AGENTS.md's
  "marker files under `user://` can alter later headless runs" warning, generalized: the trace
  files the suite writes (`foot_ik_controlled.jsonl`, the regression matrices, etc.) contaminate
  later scenes run against the same shared user dir.
- Reconfirming attribution with `git stash` inside the shared user dir gives **misleading** results
  (the stashed baseline passed once, then failed 4/4) - do not trust A/B knee_flex runs in the
  shared user dir; use the renamed-project clean-room above.

No code change was needed. An intermediate attempt (reverting the flat-tread weight, gating the
toe-clearance retry to walk/sprint clips) was reverted after the clean-room test showed the
original fix already passes the three landing scenarios (`PASS` x3) and the walking regression
(`depth_m=0.000765` on a fresh `user://`). The task file's checkpoint implementation stands as the
other agent wrote it.

Validation completed at this checkpoint:

- `scripts/check.sh`: PASS (lint/import/GDScript parse).
- targeted stair-walk check: PASS repeatedly; 1.449 mm worst depth versus 5 mm limit.
- candidate-evaluation check: PASS, 720 samples.
- `scripts/check_foot_ik.sh`: new stair check PASS; runner later stops at the pre-existing
  unreachable lower-support acquisition failure recorded by task 018.
- `scripts/check_foot_ik_locomotion.sh`: reaches the pre-existing `walk_left`/`walk_right`
  failures; preceding cases pass. No stair-specific new failure observed.
- `scripts/check_foot_ik_ramps.sh`: existing ramp-oracle failure remains; summary reports
  `FAIL cases=245 failed_cases=0 worst_depth_m=0.0` while several zero-depth toe contacts are
  still labeled per-case FAIL. The stair-only correction does not run on ramps.
- `scripts/check_foot_ik_ramp_sweep.sh`: existing task-018 baseline reproduced exactly:
  16 failing cases, worst depth 0.105375 m.

Performance smoke test (`FOOT_IK_PERF_LOG=1`) on the multi-character preview: after warm-up the
headless stress scene reported about 68 FPS, with complete per-leg sequences around 78–116 us
average. The user still needs to judge stair pose smoothness live, especially the bounded retry's
same-frame correction. Latest focused logs are `/tmp/foot_ik_025_minimal_candidate_predictor_v2.log`,
`/tmp/foot_ik_025_targeted_perf.log`, `/tmp/foot_ik_025_check_foot_ik_v2.log`, and
`/tmp/foot_ik_025_locomotion.log`.

Bookkeeping note: `CURRENT_TASK.md` is absent from this working tree even though `AGENTS.md` says it
selects the active task. This continuation followed task 025 directly and did not invent a pointer.

Historical walking symptom, separate from the startup bug: the same live session also logged 39
clip events during
genuine walking, most small (5-10mm) but one real: **11.3cm**, right foot toe, mid-walk
(`moves/unarmed_walk`, frame 469). **This is now reproduced headlessly on current `HEAD` - see
"Walking clip reproduced" below—and the continuation fix now passes that regression.** It is not
the startup bug, 019 (stationary rotation), or 020 (ramp corner). Tasks 019/020 remain separately
open and are not declared fixed by this work.

## Walking clip reproduced headlessly (2026-09-14)

No live play needed: `foot_ik_preview.tscn`'s overlay logs `[FOOT_IK_CLIP]` itself, and the
existing stair-walk marker already drives the real Player straight up the 0.35m stairs and loops.

```sh
U="$HOME/Library/Application Support/Godot/app_userdata/SurvivalHorrorFps"
touch "$U/foot_ik_stair_walk_marker"
godot --headless --path . res://tests/manual/foot_ik/foot_ik_preview.tscn --quit-after 1400 \
  > /tmp/walk_repro.log 2>&1
rm "$U/foot_ik_stair_walk_marker"   # remove before trusting any later run
```

Result on `46f196a`: **90 clip events**, all `moves/unarmed_walk`, both feet, every ascent
(frames ~72-1150). Largest logged `depth_m=0.1961` (right toe, frame 804, point
`(14.799, 0.499, 0.796)` - inside the 0.35m step-1 box, top 0.7). One event is
`depth_m=0.1135` (left toe, frame 344) - the same magnitude as the live 11.3cm report. The
signature is a **step-up toe/riser penetration**: the swing foot's toe enters the next tread
box. The authored treads run through `finalize_authored_box`, so each has a real
`StaticBody3D` + `BoxShape3D(BoxShape3D)` collider and the live monitor's convex-box math is
exact, not a CSG-trimesh miss.

Two measurement caveats found while reproducing:

- The live indicator only prints the **first** frame of each penetration episode
  (`_active[side]` throttle), so a logged depth is that episode's shallowest, not its worst.
  The saved trace (`feet.*.joints.toe`, final post-modifier pose) shows the same episodes
  deepening past the logged value (e.g. left toe ~0.42m below the tread top at frame 685), so
  0.1135m is a floor, not a ceiling.
- No existing check catches this: the spawn regression covers startup only, and no walking
  check asserts toe clearance against the authored treads. The walking-clip regression is
  missing and must be added with the fix.

## Walking-clip regression (added 2026-09-14)

`tests/manual/foot_ik/foot_ik_walk_contact_check.tscn` (+ `.gd`) walks the real Player up the
0.35m stairs in **one uninterrupted ascent** and asserts neither foot's ankle or toe tip enters an
authored tread box (the boxes are real `StaticBody3D + BoxShape3D` via `finalize_authored_box`, so
the math is exact). It is registered in `scripts/foot_ik_checks.inc.sh`:

```sh
godot --headless --path . res://tests/manual/foot_ik/foot_ik_walk_contact_check.tscn --quit-after 1500
```

The former multi-ascent loop was invalid because teleporting retained or abruptly reset live IK
history. The valid single-ascent baseline on `46f196a` was **FAIL, depth 0.073334 m**, matching the
same toe/riser mechanism without a teleport artifact. The harness samples every stair frame (unlike
the live `[FOOT_IK_CLIP]` throttle), so it is the authoritative geometry measure.

## Fix investigation (2026-09-14) — historical, superseded by continuation checkpoint

Three distinct mechanisms produce "rendered foot below the tread", all during the step-up:

1. **Support-transfer weight ramp (frame 72, 7.3cm).** At the handoff the foot drops from
   y=1.635 (swing) to 1.420 while the correct target is 1.496. `_apply_support_contact` ramps
   `ground_weight` from the swing's ~0 over `support_transfer_blend_time`, so for the first
   frames the low flat-ground animated pose dominates the solve. The swing foot is transferred
   onto a higher tread, so that animated pose is *below* the tread.
2. **Swing-lift lag / toe pitch (frames ~79-83, ~5cm).** A swinging foot's toe tip sits ~0.16m
   below its ankle (toe-down walk-clip pitch). The lift raises the ankle, but `smoothed_lift` is
   rate-limited at `step_lift_rate=4.0` (0.067m/frame) and is still ramping while the foot moves
   over the next tread, so the toe dips in first. Raising `step_lift_rate` to 16 measured *worse*
   (6.09cm), so this is not simply "lift faster".
3. **`STAIR_SUPPORT` toe-envelope exemption.** `foot_ik_target_coordinator.gd:520` sets
   `check_toe = owner != STAIR_SUPPORT`, and `legacy_transition_active` early-returns STAIR_SUPPORT
   validation entirely (`:478`). A landing support toe is therefore never checked against the
   tread during a climb. This validates *targets*, not the rendered weighted pose, so it alone
   would not close mechanism 1.

Candidates tested (each reverted; none shipped):

| Change | Harness result |
| --- | --- |
| baseline | FAIL 0.0733 (f72 right toe) |
| force support-transfer `weight_from = 1.0` (all flat treads) | FAIL 0.0498 (f81 left) |
| force full weight only for non-straddling flat-tread transfers (`not _toe_probe_reaches_higher_surface`) | FAIL 0.0498 (same) |
| harness-only `step_lift_rate = 16.0` | FAIL 0.0609 (worse) |
| **swing lift applied instantly upward** (rate-limit release only) | combined below |
| **step-up-scoped transfer weight** (`_support_surface_target.y > previous + step_min_rise`) + instant-up lift | FAIL 0.0357 (f92 left) |
| + force `gw=cw=1` for a flat-tread stair support foot (`is_flat_support`) | FAIL 0.0290 (f68 left) |

Interpretation: at least three independent mechanisms stack, all "a rendered foot point below a
tread during the step-up":

1. **Support/contact weight < 1** lets the low flat-ground animated pose pull the foot through the
   tread at handoff and during release. This is the dominant one and recurs across owners
   (`stair_support`, `live_contact`). Forcing/keeping weight at 1 for a grounded flat-tread foot
   closes it (7.3 → 5.0 → 3.6 → 2.9 cm as each variant is added).
2. **Swing-lift lag**: `smoothed_lift` ramps at `step_lift_rate` and is still climbing while the
   foot moves over the next tread. Applying the up-lift instantly removes it (safe: the release
   stays rate-limited).
3. **Toe-down foot pitch** (the final 2.9 cm at f68): with the ankle *above* its target, the
   extended toe tip still dips into the next tread because the flat-ground walk clip keeps the
   foot pitched toe-down through the step-up. This is an orientation problem - raising the ankle
   or the weight does not fix it, and forcing weight on this frame would push the toe down
   further. It needs the foot oriented toward the landing tread during a step-up (the solver's
   foot-basis path), which is the real remaining work.
4. **INVALID TELEPORT-HARNESS ARTIFACT — target sampled under the animated foot while the rendered
   foot is far ahead** (formerly thought dominant in
   the 3-ascent harness, ~0.12-0.24m at frames 131/173/192/239/256/281/316 - steady state, not a
   cold-start artifact). At f133 the rendered/animated `foot_pos` is z=0.569 but `raw_target` is
   `(15.113, -0.0, -0.034)`: the ground sampler's ray was cast under the *animated* foot pose at
   z=-0.034 (the floor), 0.6m behind the rendered foot, so it targets the wrong surface and the
   far-forward toe digs into the next tread. This is an animation-vs-solve coordinate/time
   mismatch in `FootIKGroundSampler.sample()` (its `foot_pos` argument is the raw animated pose,
   not the rendered one), not any of the weight/lift mechanisms above. Mechanisms 1+2 were
   re-applied and re-measured against this 3-ascent harness: **no improvement** (0.117 -> 0.122),
   confirming #4 dominates and is independent.

`scripts/trace_query.py toe-riser` (geometry-based) lists the recurring episodes; `clips` uses
the `sole_clearance` proxy and is noisy during swing (ignore its multi-metre `sole_min` values).

Historical decision before the continuation checkpoint: no partial gameplay change shipped. The
four mechanisms were recorded with the
exact numbers and frame/point evidence so the next session can implement 1+2 (small, scoped,
already measured) together with a targeted fix for 3 (swing/landing foot pitch) and 4 (sample
under the rendered foot) and then verify on the full suite. All experimental edits were reverted
(`git checkout`); the only kept changes are the regression, `scripts/trace_query.py`, and docs.

Earlier investigation is preserved in
[the archive](archive/025_walking_hypothesis_investigation.md). Its identification of the recurring
event as walking/turning was incorrect; do not resume target-path patches from that assumption.

## Exact event match (2026-09-13 continuation)

Matched **ankle/toe positions**, not the nearest root, in all three preserved live captures:

- `/tmp/foot_ik_controlled_third.jsonl`
- `/tmp/foot_ik_controlled_livewalk_20260913.jsonl`
- `/tmp/foot_ik_controlled_liveafter.jsonl`

The repeated `(15.37852, 1.117114, 1.958677)` point matches the **left toe tip at frame 17**
within 0.000005 m in all three. Animation is `moves/unarmed_idle`, root yaw is constant
`100.977250312091` degrees; this is startup, before the user walks. The ankle's actual position
is far below its valid 1.496 m solve target. This is not an ankle target crossing a wall.

## Confirmed initialization failures

1. `AnimationPlayer.play()` selected idle but had not applied it before the first zero-delta
   modifier evaluation. At physics frame 1, the imported pose's left foot was
   `(15.17172, 1.618629, 0.211004)`, sampling the wrong tread at y=0.35. The true idle foot is
   around `(15.52421, 1.505602, 1.975434)`, supported at y=1.4. The first real pass reused the
   zero-pass pose cache; later frames smoothed from that unrelated support.
2. `_shape_shared_drop()` could advance pelvis-drop history on a zero-delta refresh.
3. Startup borrowed the animation-loop seam-acquisition bypass: it released the upper leg while
   the shared pelvis lowered to reach the lower tread. The upper leg then rate-limited its way
   back out of the stair. Initial placement is not an already-visible movement to interpolate.
4. Upper-foot extension also needs its destination established in that initial placement;
   initializing only the bones left a brief ~2.4 cm toe clip during delayed upper acquisition.

## Changes

- Gameplay autoplay applies its chosen idle pose with `advance(0.0)` before the first skeleton
  refresh. Character Editor's `autoplay_default_animation=false` path remains untouched.
- Zero-delta pelvis refreshes reapply current drop without advancing history.
- The modifier's spawn-frame-only initialization establishes shared drop and leg corrections
  together and does not take the loop-seam acquisition bypass. Normal later turns, landings,
  runtime resets and idle loops retain their existing interpolation/rate limits.
- Coordinator passes an explicit `initialize_pose` flag to upper-foot placement. Its existing
  support/stance/reach search chooses the initial destination without an acquisition animation;
  normal calls retain their speed-limited motion.
- Clip messages retain episode throttling and now include frame, ankle/toe-tip identity, actor
  path, animation/time, root and yaw. Future reports can match the trace directly.
- Moved the unchanged horizontal target-path hold into `tools/foot_ik/foot_target_motion.gd`
  to keep the sampler below 1000 lines. It is explicitly **not** a swept-foot-volume check.

## Regression and evidence

```sh
godot --headless --fixed-fps 60 --path . \
  res://tests/manual/foot_ik/foot_ik_spawn_contact_check.tscn --quit-after 140
```

Unlike task 024's settled-idle test, this checks the **startup frames**, at fixed spawn/yaw.
Ankle and toe-tip points are sampled every frame 3–120. Final skinned foot/toe/leaf vertices are
also checked against all eight nearby real box colliders during frames 3–40 (304 mesh samples).
Both depth limits are 0.005 m. Registered in shared and fast runners. No expensive live marker
is created or left enabled.

- Fixed: **PASS**, 118 point frames, point depth `0`, mesh depth `0`, 304 mesh samples;
  stationary and moving zero-delta pelvis invariants both pass.
- Mutation, initial-placement path disabled: **FAIL**, point depth `0.239558 m`, mesh depth
  `0.274809 m`. Mutation restored before broader tests.
- A subtle oracle gap: the older precise `sample()` checks only the collider under the root.
  It returned zero while the toe entered a *neighboring higher tread*. The new fixture uses
  `sample_box_transform()` against nearby box colliders; the existing CSG-box method delegates
  to the same mesh oracle. Do not use root-only ray results to certify adjacent-riser clearance.

Evidence: `/tmp/foot-ik-025.bCAdqv/`, including preserved current trace, targeted diagnostics,
intermediate/final startup runs, mutation and fast/full-suite logs. No preview autoplay.

## Pending

1. ~~Finish fast/full verification~~ - done, no regressions beyond the known task-019 baseline.
2. ~~User live confirmation~~ - done: startup clip no longer appears in a fresh live session.
   ~~Commit~~ - done, `cd2a398`.
3. Walking toe/riser fix: implemented and headless regression PASS. **Pending user live test** of
   stair traversal and visual smoothness; do not commit until confirmed. Tasks 019/020 and task
   024's previously noted other-stance clearance side effect remain separate work.

## 2026-09-16 finding: the current harness worst frame is on the landing, not a stair transition

Current harness worst (frame 214, right toe tip, `depth_m=0.012458`, root
`(15.0, 2.100761, 3.572408)`) is **not** a transition clip: at that frame the plan shows
`adj=unchanged` (the toe-clearance retry never fired) and the stair predictor reports
`is_active()=false`, `is_descending_treads()=false`, and the stair controller reports
`recent_transition=false`. Root y is 2.10 = the top landing height, so the player is already
standing/walking on the landing and the stair clearance gate cannot apply. Adding
`recent_transition` to `stair_clearance_active` had **zero effect** (it is false at that frame) -
reverted, no change to `depth_m`. So this residual is a "walking onto/along the top landing" clip,
a different mechanism from the earlier transition clips. Gate widening is explicitly discouraged
here, and the instant retry that fixes the transition clips is the task-028 jank source - do not
widen the gate without a geometry-scoped signal plus a full ledge/stair suite A/B.

