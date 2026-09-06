# 013: Foot IK knee-bend selection instability (`_select_feasible_bend`)

## Status and scope

New, split out of [012](012_foot_ik_ramp_cross_slope_penetration.md) once investigation there
showed the bug is not ramp-specific. Bend discontinuities were observed, but their attribution
as the cause of the measured foot jump is not established; the pipeline audit below contradicts
the earlier assumption that the actual solver input stayed smooth. Three fix attempts inside
`_select_feasible_bend` failed (see "Fix attempts" below); a pipeline audit then traced the
real discontinuity to `adjust_idle_slope_target`'s own reacquisition logic instead, and a fix
there (see "Verified partial fix" below) substantially improved `spin_foot_step`. A second fix
(see "Second verified fix" below) found and fixed the exact further-upstream discontinuity the
first fix's own follow-up flagged - an animation-loop-seam pose freeze that assumed a stationary
idle leg never needs to keep tracking a rotating body. Together the two fixes clear
`spin_foot_step` on most of the 24 ramp-locomotion cases; two steep-diagonal outliers remain
unexplained, and `turn_step_m` (flat ground, where neither fix's `stationary_slope` gate can
reach) is still an open, separate instance of the same underlying bug class. This is scoped as
its own task because the affected functions are shared by every leg solve on every surface.

## The bug

`_select_feasible_bend` (`foot_ik_leg_solver.gd`) is a 145-step discrete angular search
(2.5-degree resolution) that picks, every single frame, the closest-to-`preferred` knee-bend
direction that satisfies alignment/thigh-swing/shin-limit constraints. Unlike every other
target/pose mechanism in this file, it has **no continuity or hysteresis**: no previous-frame
reference, no rate limit, no smoothing. It is called fresh each frame from `preferred`
(basically the animated or slope-adjusted pole direction).

When the true feasible region on the search circle is narrow, or has more than one disconnected
arc, small changes to `preferred` or the constraint set - the kind that happen continuously as
a character's body rotates - can flip which arc numerically wins the `score < best_score`
comparison. The result is a discontinuous jump in the chosen bend direction, which at the leg's
~0.4-0.5m length translates directly into a large, visible one-frame foot/knee pop.

## Evidence (gathered in 012, summarized here)

- Instrumented `solve()`'s own call into `_solve_bend_direction`/`_select_feasible_bend`
  (temporary, not committed) to log, on every frame, whether the search found a rotated
  candidate (`used_best`) and the angle between that candidate and `preferred`.
- **On a ramp** (`foot_ik_ramp_locomotion_check.tscn`, idle-spin-in-place phase): `used_best`
  toggles `true`/`false` frame to frame, with the angle jumping directly between 0 degrees and
  22-60 degrees. This is large enough alone to account for the up-to-0.55m `spin_foot_step`
  penetration/pop failures documented in 012.
- **On flat ground** (`foot_ik_idle_plant_stability_check.tscn`, unrelated pre-existing test,
  its turn-in-place segment): the same flip occurs, at *larger* magnitude (up to ~118 degrees)
  and higher frequency. Two consecutive log lines showed the **same physics frame number**
  producing 118 degrees then 0 degrees - two evaluations within a single tick (likely a
  `SkeletonModifier3D` zero-delta re-evaluation, see `AGENTS.md`) giving very different answers
  on near-identical inputs. That is a floating-point boundary-sensitivity symptom in the search
  itself, not merely "crossing a rotation threshold between frames."
- This likely explains `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`'s `turn_step_m=0.056851` value -
  present, unexplained, and treated as an unrelated known-red baseline case in every full-suite
  run this whole session (see [010](010_foot_ik_target_coordinator_consolidation.md) and
  [012](012_foot_ik_ramp_cross_slope_penetration.md)). Not proven to be the exact same numeric
  cause yet - the mechanism, animation, and rotation trigger all line up closely enough that
  this should be checked before assuming otherwise.
- **During ordinary walk gait too, not just rotation**: `ramp_30_uphill` (a plain straight
  walk, no turning) shows the same flip during its settle-to-move transition - 0 -> 10 -> 0 ->
  30 -> 0 degrees across a handful of frames - smaller in magnitude than the rotation-driven
  cases but the same signature (no other clamp flag active, `used_best` toggling). This is what
  was causing 012's separately-tracked `phase=move` diagonal-walk failures; they are not a
  distinct bug, just this one triggered by a gait-driven change in `preferred` instead of a
  body-rotation-driven one.

## Why not fixed yet

A first attempt at a *related* mechanism this session (removing `adjust_idle_slope_target`'s
0.25m escape hatch, see 012's "Partial fix" history) fixed the targeted symptom but broke a
different, previously-passing case that relied on the old behavior's fast response to a
genuinely large state change. `_select_feasible_bend` has the same shape of risk: any fix that
adds hysteresis/continuity must not prevent the search from correctly finding a very different
bend plane on a real large state change (e.g. right after a landing, a platform-height change,
or an animation switch) - it needs to distinguish "the target barely moved but the search
result flipped anyway" (the bug) from "the target genuinely needs a very different bend now"
(correct, must stay fast).

## Fix attempts (three tried, all reverted)

All three were instrumented and tested directly against `foot_ik_ramp_locomotion_check.tscn`'s
`spin_foot_step` metric and `foot_ik_idle_plant_stability_check.tscn`'s `turn_step_m`, following
this task's own verification plan below. Each change was confirmed lint-clean and reverted
cleanly (`git diff`/`git checkout --`) before the next attempt - nothing from this round was
left in the tree.

1. **Seed from the previous frame's chosen bend, only jump when it becomes infeasible.** Added
   `_previous_bend: Dictionary` (side -> Vector3) and a shared `_is_bend_feasible` helper reused
   both inside the 145-step search and to re-check the previous frame's choice. **Result:
   ineffective.** Direct instrumentation showed the previous bend genuinely becomes infeasible
   under the current frame's constraints very often during a spin (787 times in one 13,000-frame
   run, with "legitimate" jumps up to 93 degrees measured at the moment of transition) - so the
   "stay put if still feasible" gate barely reduced how often the unrestricted fast-jump path
   fired. The bug is not really about the previous choice losing feasibility; it is about how
   easily it does.
2. **Always ease toward the fresh result at a bounded angular rate (240 deg/sec), dropping the
   feasibility gate entirely** - closest to direction 3 below. Confirmed via debug print that
   the rate limit was computing and applying correctly frame to frame (e.g. capping a 30 degree
   raw jump down to a ~4 degree per-frame step, converging over several frames). **Result: no
   measurable change** in `spin_foot_step` or `turn_step_m` - values were bit-for-bit identical
   to the unfixed baseline across every case checked, despite the smoothing demonstrably running
   and computing different (smaller) per-frame values internally.
3. **Ruled out a stale-state explanation and a multi-call-per-tick explanation for attempt 2's
   null result**, rather than guessing a fourth fix blind:
   - Suspected `release(side)` (which the first attempt had added `_previous_bend.erase(side)`
     to) might be wiping the hysteresis memory right before the critical frame. Checked: `
     release(side)` has **zero callers anywhere in the codebase** - dead code, not the cause.
   - Suspected `solve()` runs more than once per physics tick (a documented `SkeletonModifier3D`
     behavior, see `AGENTS.md`) and a later zero-delta call might be overwriting the smoothed
     result with a freshly unsmoothed one. Checked directly: `solve()` runs **exactly once per
     frame** with a consistent nonzero `delta` and `instant=false` throughout the failing
     window (1493/1493 calls checked, 0 with `instant=true`) - not the cause either.
   - Instrumented `new_foot_pos` (the position computed at the very end of `solve()`, right
     before `debug_final_foot_position[side]` is set) directly and found single-frame steps as
     large as **2.68m** internally - far larger than the externally-measured `spin_foot_step`
     ceiling of ~0.55m. This means something *between* `solve()`'s own output and the
     externally-measured rendered sole position is already substantially damping the raw signal
     - the bend-selection fix's effect (or lack of one) is getting mixed in with whatever that
     other layer does, and was not isolated before this pass ran out of budget.

### Pipeline audit (2026-09-06): no hidden post-solve damping at the worst spin event

Two diagnostic-only runs of the existing 24-case ramp-locomotion harness compared the
right leg's solver diagnostic, immediate skeleton write, post-modifier cache, and the
test's own sampling callback. Logs: `/tmp/foot_ik_013_pipeline_audit.log` and
`/tmp/foot_ik_013_target_audit.log`. Temporary inherited harness/solver probes were removed;
no gameplay behavior changed. Both runs retain the failing ramp test, not a claimed fix.

The pelvis is shifted **before** `solve()`. The solver writes `new_foot_pos` directly into
the foot bone; toe writes affect descendants only. The modifier then copies skeleton poses
directly into `_final_bone_poses`. At the worst spin event (case 18, `ramp_45_yaw_045`,
sample frames 422→424, physics ticks 9494→9496), solver output and cached ankle both move
0.548498m, and the actual solver target moves 0.548499m. There is no attenuation here.
Of 12,062 right-leg solve calls, 12,061 match their immediate bone within 0.00002m;
those also match the post-modifier cache within 0.000011m. Release paths can leave stale
solver diagnostics; they are not evidence of post-solve smoothing.

Crucial measurement mismatch: the harness's `spin_target_step` uses `_smoothed_target`
(surface sampling), and its `solve_target` string uses `_solved_target_smoothed`
(another upstream stage), **not** `debug_solve_target`, the actual `solve()` argument.
At ticks 9493→9494, `adjust_idle_slope_target`'s input already jumps 0.327683m; its output
jumps 0.533783m and the solved/cached ankle follows. Its >0.25m reset is therefore still
involved, but removing it alone remains the rejected attempt documented above.

The harness samples spin every second tick and resets per-case history, whereas a global
consecutive-output scan also includes explicit root teleports between cases (observed
5.66m jumps). The original 2.68m claim cannot be assigned a cause without its matching
case/frame pair; comparing that global maximum with a phase-filtered maximum proves no
damping layer. Also, `release(side)` is not dead code: `release_to_animation()` calls it.

**Next action:** trace the 0.327683m discontinuity upstream of slope adjustment at ticks
9493→9494: per-leg target construction/stance-crossing, coordinator selection, pelvis target
separation, and compressed-upper adjustment. Identify the first changing owner/value before
trying another bend-plane smoothing fix. A pole flip alone does not prove ankle displacement:
an unconstrained two-bone solve can change knee plane while reaching the same ankle target.

## Verified partial fix: `adjust_idle_slope_target`'s reacquisition logic (2026-09-06)

Fixed the mechanism identified in the pipeline audit above without yet tracing the further
upstream 0.327683m discontinuity. `adjust_idle_slope_target`'s old reset condition -
`if previous.distance_to(candidate) > 0.25: previous = candidate` - conflated two different
situations using the wrong signal (distance moved): a leg reacquiring this owner after a
different owner held it (genuinely needs to snap, no valid history to ease from) and this same
owner running every single frame while a rotating body legitimately moves the raw candidate
a lot in one frame (must stay smooth, since there *is* valid history). Distance alone cannot
tell these apart - the fix instead tracks whether this function was called on the immediately
preceding physics frame (`_idle_slope_target_frames: Dictionary`, side -> last-called frame):
only reset when there's an actual gap (reacquisition), never merely because the candidate moved
far in one frame. A same-tick repeat call (a `SkeletonModifier3D` zero-delta re-evaluation, or
any other same-frame re-entry) now returns the already-computed value instead of double-stepping
the smoothing.

Verified in isolation first with a new dedicated unit test,
`tests/manual/foot_ik/foot_ik_slope_target_lifecycle_check.gd/.tscn` (wired into both
`check_foot_ik.sh` and `check_foot_ik_fast.sh`) - it drives `adjust_idle_slope_target` directly
against a stub owner/solver with every candidate forced feasible, covering: fresh acquisition,
continuous-owner smoothing under a large per-frame candidate move, a same-tick repeat call,
reacquisition after a different owner held the leg for one tick, and `reset_runtime_state()`.
All five pass.

Verified against the real symptom: re-ran `foot_ik_ramp_locomotion_check.tscn`'s `spin_foot_step`
across all 24 cases. Most cases dropped from the 0.31-0.55m range down to 0.04-0.07m - close to
the 0.040m limit, a roughly 5-10x reduction, though not yet passing. Two outliers remain
significantly worse than the rest: `ramp_45_yaw_045` (0.548m -> 0.222m) and `ramp_45_yaw_315`
(0.443m -> 0.312m) - both steep-ramp, diagonal-facing cases, suggesting a secondary contributor
specific to that combination not yet identified. `foot_ik_idle_plant_stability_check.tscn`'s
`turn_step_m` is unchanged (0.056851) as expected - that check exercises flat ground, where
`stationary_slope` (and therefore `adjust_idle_slope_target`) never activates, so this fix
cannot reach it; whatever causes `turn_step_m`'s failure is a related but distinct instance of
the same underlying "no reacquisition-vs-continuity signal" class of bug, not yet found.

Verified no regressions: full exhaustive suite re-run (regenerated the session's ad-hoc
continue-past-failures wrapper from the current `check_foot_ik.sh`, since it had gone stale
after the ramp-locomotion-script extraction and this task's new lifecycle check) matches the
established baseline exactly, plus the two expected new entries
(`FOOT_IK_RAMP_LOCOMOTION_CHECK FAIL` - the still-open remainder of this bug, now included in
the suite for the first time since [012](012_foot_ik_ramp_cross_slope_penetration.md)'s own
wiring fix; `FOOT_IK_SLOPE_TARGET_LIFECYCLE_CHECK PASS` - the new unit test).

**Still open**: the two steep-diagonal outlier cases above; the further-upstream 0.327683m
discontinuity noted in the pipeline audit (not yet required for this fix's improvement, but
likely the source of the remaining ~0.04-0.07m residual and the two outliers); and
`turn_step_m`'s flat-ground counterpart mechanism, wherever it lives.

## Second verified fix: the animation-loop-seam freeze was the 0.327683m discontinuity

Traced the pipeline audit's own "next action" (find the 0.327683m jump upstream of
`adjust_idle_slope_target`) directly. `player_foot_ik_modifier.gd`'s per-leg loop has a second,
unrelated mechanism right after the slope adjustment call:

```gdscript
if (_velocity_suppressed and cur_anim.contains("idle")
        and not _gait_tracker.is_body_translating()
        and _leg_solver.debug_solve_target.has(side)):
    target = _leg_solver.debug_solve_target[side]
```

`_velocity_suppressed` goes true for exactly `VELOCITY_SUPPRESS_FRAMES` (2) frames every time
the current animation's loop position resets (`foot_ik_gait_tracker.gd`'s
`update_animation_discontinuity`) - a **recurring, periodic event throughout an idle loop**,
unrelated to body rotation. When it fires, this block throws away the freshly computed `target`
(already past `adjust_idle_slope_target`'s slope adjustment) and substitutes
`debug_solve_target[side]`, whatever was actually passed to `solve()` on some earlier frame -
built to hold a genuinely static idle pose steady across the animation seam rather than read a
spurious velocity spike from it (see the mechanism's own doc comment, and
`FOOT_IK_POSE_CONTINUITY_CHECK`, the regression test that shape of fix was built against).

For a `stationary_slope` leg on a rotating body, that assumption doesn't hold: the correct
target keeps changing every frame as the body turns, so substituting a several-frame-old value
reintroduces exactly the kind of jump this task has been chasing. Instrumented directly and
confirmed: this override alone was producing 0.33-0.38m discontinuities (matching the pipeline
audit's 0.327683m almost exactly) at multiple points throughout a run, on both legs.

**Fix**: added `and not leg.get("stationary_slope", false)` to the override's guard - the same
exemption pattern used earlier in this task's history for `_limit_idle_stance_crossing` (see
012's "Partial fix" section) and consistent with the general rule this session keeps
re-confirming: a flat-ground-assuming correction must not run on a leg that has already been
placed by its own slope-aware logic.

**Result**: `spin_foot_step` now fully passes on several previously-failing cases
(`ramp_15_yaw_045/090/315`, `ramp_30_yaw_045/315`, `ramp_45_yaw_270`, and more); overall ramp
locomotion failures dropped from 22 to 21 (remaining failures are now almost entirely
`foot_float`/`foot_penetration`, not `spin_foot_step`). Two outliers remain **completely
unaffected** by this fix - `ramp_45_yaw_045` (still 0.222m) and `ramp_45_yaw_315` (still
0.312m) - meaning they have a distinct, not-yet-found cause; both are 45-degree-ramp, extreme
diagonal-yaw cases, and one sample point showed `swing_deg=99.6`, suggesting they may be
right at or beyond `max_hip_swing_degrees` and hitting the anatomical swing clamp
(`solve()`'s `Vector3.DOWN.rotated(swing_axis, max_swing)` branch) rather than this mechanism.
`turn_step_m` is unaffected as expected (flat ground never sets `stationary_slope`, so this
exemption cannot reach it - it needs its own investigation, per the still-open item above).

Verified no regressions via the full exhaustive suite (regenerated version of the session's
continue-past-failures wrapper, matching the previous fix's run byte-for-byte in its
diff) - in particular `FOOT_IK_POSE_CONTINUITY_CHECK` (the check this seam-freeze mechanism
exists to protect) is unchanged at `max_jump_m=0.012522`, confirming the exemption is scoped
tightly enough to leave the original flat-ground behavior untouched.

## The two remaining outliers: right at the anatomical hip-swing limit, not the same bug class

Checked directly: both outliers' worst `spin_foot_step` samples show `swing_deg` of 99.6 and
99.8 degrees - within a fraction of a degree of `max_hip_swing_degrees` (100.0, the exported
default in `player_foot_ik_modifier.gd`), with `swing_clamped=false` at the captured sample
(the raw compute stayed just under the clamp threshold that frame). This is a third instance of
the same general "hard boundary with no continuity" architecture pattern already fixed twice in
this task (the bend-plane search's own instability, and the seam-freeze override) - but a
distinct mechanism from either: the anatomical swing clamp in `solve()`
(`Vector3.DOWN.rotated(swing_axis, max_swing)`) has no hysteresis either, so a leg whose
required swing angle sits within a degree of the limit could plausibly flip in and out of
clamping between adjacent frames, each transition producing a discontinuity the same way the
other two mechanisms did.

However, unlike the two fixed mechanisms, there is a real possibility this combination
(45-degree ramp, extreme diagonal facing, `shared_drop=0.576` - a large pelvis sink observed at
the same sample) is a genuinely hard anatomical pose rather than a bug: `hip_target=0.504` in
the first outlier is well within reach (`reach=0.888`), yet still demands ~100 degrees of hip
swing - meaning the target sits nearly level with or above the hip, off to the side, which is
plausible geometry for a steep ramp with a large pelvis drop rather than a symptom of drift.
**Not confirmed either way and no fix attempted** - the next step, before touching the swing
clamp itself, is to check whether `swing_clamped` genuinely toggles frame-to-frame at these two
cases specifically (the same "instrument the exact boundary, don't guess" discipline applied to
both fixes above), and separately, whether a real human pose would actually need to plant that
foot at all at this facing/pelvis-drop combination, or whether the fix belongs in the
pelvis-drop/lean logic rather than in IK correction. Given this task already required two
levels of re-diagnosis to find its first two fixes, this third mechanism should get the same
direct-instrumentation treatment rather than another guess.

## Directions worth trying (attempt 1 and 3 tried and did not work as hoped; not fully ruled out)

1. ~~Seed the search from the previous frame's chosen bend direction, only jump when it becomes
   infeasible.~~ Tried - see "Fix attempts" above. Does not meaningfully reduce how often the
   fast path fires, since infeasibility transitions are frequent and often legitimate.
2. **Add epsilon margins to the constraint comparisons** (`candidate.dot(positive) <
   required_alignment`, thigh-swing/shin-limit checks) so a candidate does not enter or leave
   feasibility from floating-point noise alone - not tried. Would address the same-tick,
   same-frame-different-result symptom specifically (the 118-degree-then-0-degree case), though
   probably not the larger frame-to-frame drift-driven flips attempt 1 measured.
3. ~~Rate-limit the output bend direction unconditionally.~~ Tried - see "Fix attempts" above.
   The rate limit itself worked as designed at the point it was applied, but produced no
   measurable change in the externally observed metrics - strongly suggesting the real fix (or
   at least the real verification) needs to happen after identifying the untraced layer noted
   above, not purely inside `_select_feasible_bend`.

## Verification plan for whichever direction is chosen

Both of these must be checked together, not just the one the fix targets - the escape-hatch
attempt in 012 failed by only checking the first:

- **Fixes the bug**: re-run `foot_ik_ramp_locomotion_check.tscn`'s `spin_foot_step` metric
  (currently failing up to 0.548m, limit 0.040m), its `phase=move` cases (e.g. `ramp_30_uphill`,
  the same mechanism at smaller magnitude), and `foot_ik_idle_plant_stability_check.tscn`'s
  `turn_step_m` (currently 0.056851, check its specific limit) - all should improve/pass.
- **Does not regress genuine large state changes**: re-run `ramp_15_uphill`'s `hold` phase
  (the case that broke when the *different*, related escape-hatch fix was tried in 012) and the
  full exhaustive suite (`bash /tmp/check_foot_ik_run_all.sh`-equivalent) to confirm the
  established pre-existing baseline failure set doesn't grow or change in kind.
- **New, given this pass's finding**: before trusting either check above, confirm the fix's
  effect is actually visible at the point it's applied *and* survives to the externally measured
  metric - attempt 2 passed the first half of this silently and it took extra, unplanned
  instrumentation to notice the second half never happened.

## References

- [012](012_foot_ik_ramp_cross_slope_penetration.md) - where this was first found, via ramp
  diagonal-walk/spin test coverage; contains the fuller investigation trail and the related
  (reverted) `adjust_idle_slope_target` escape-hatch fix attempt.
- [010](010_foot_ik_target_coordinator_consolidation.md) - documents
  `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`'s `turn_step_m` as a known pre-existing baseline failure,
  never previously root-caused.
- `actors/player/foot_ik/foot_ik_leg_solver.gd` - `_select_feasible_bend`,
  `_solve_bend_direction`, `solve()`.
