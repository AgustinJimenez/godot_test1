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
idle leg never needs to keep tracking a rotating body. A third fix (see "Third verified fix"
below) re-applied one of the three originally-abandoned `_select_feasible_bend` hysteresis
attempts - it had shown zero effect in isolation, but turned out to be correct all along, just
masked by the first two discontinuities; re-tested after fixing those, it closed both remaining
steep-diagonal outliers (one fully, one to within 0.001m of the limit) and even nudged
`turn_step_m` (flat ground) for the first time all session. `spin_foot_step` now fails on only
one of 24 ramp-locomotion cases, by a hair. `foot_ik_idle_plant_stability_check`'s overall
`FAIL` is driven by two other fields (`live_pose_joint_step_m`, `min_sole_clearance_m`), not
`turn_step_m` - traced `live_pose_joint_step_m` to a *second*, independent call site into
`_select_feasible_bend` (inside `_limit_negative_rendered_knee`, gated to flat ground) that none
of the three fixes above ever reached; a fix attempt there made the metric worse and was
reverted (see "turn_step_m's stalled fields explained" below). This is scoped as its own task
because the affected functions are shared by every leg solve on every surface.

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

## The two remaining outliers: swing-clamp hypothesis ruled out, back to the bend-plane search

Checked directly whether the swing clamp toggles frame-to-frame at these two cases
(`ramp_45_yaw_045` around its worst sample, frame 300 in the test's own per-case counter).
It does not: `swing_deg` moves smoothly (99.34 -> 99.12 -> 99.42 -> 99.58 -> 99.63 across
frames 294-302) and `swing_clamped` stays `false` throughout - no toggle, no discontinuity in
the swing angle itself. The "right at `max_hip_swing_degrees`" observation was a real but
coincidental proximity, not the cause. **Ruled out.**

Added `debug_final_foot_position` to the same per-frame trace and found the actual signature:
at frame 298 specifically, `solver_foot` jumps to a clear one-sample outlier -
`(12.78705, 0.752629, 0.903028)` - visibly off the smooth trajectory both its neighbors sit on
(frame 296: `(12.867, 0.905, 0.770)`; frame 300: `(12.877, 0.886, 0.750)`) - then snaps back
next sample. This happens *while* `swing_deg` stays smooth, meaning the discontinuity is not in
how far the leg swings from vertical but in *which direction around the swing cone* it points -
i.e., the bend-plane azimuthal choice, not the swing magnitude. This is the original
`_select_feasible_bend` instability from this task's first three (reverted) fix attempts,
reappearing here specifically because near a ~100-degree swing the foot sweeps a much larger
physical radius per degree of azimuthal change than it does hanging mostly straight down - the
same small flip that was invisible or negligible elsewhere becomes large exactly at this
sustained near-max-swing geometry.

This explains why the two verified fixes in this task (the slope-target reacquisition fix and
the seam-freeze exemption) did not touch these two cases: neither addresses the bend-plane
search itself, and this is apparently the one geometric regime extreme enough to make that
search's flip visible again after both real upstream-target discontinuities were removed.
**Not fixed** - this task's three earlier attempts at fixing `_select_feasible_bend` directly
were abandoned after failing to move any externally-measured metric (see "Fix attempts"
above), and it is unclear from this finding alone whether a hysteresis fix there would now
actually reach the render pipeline (the same "verify the fix's effect survives to the
externally measured metric" caution from that section applies again). Given the narrow scope
(2 of 24 cases, both at an extreme, arguably rare geometry), and this task's own repeated
experience that this specific function resists incremental fixes, this is left open rather than
attempting a fourth `_select_feasible_bend` change without first re-confirming attempt 2's rate
limiter now has a measurable effect in isolation (it may, now that the two masking
discontinuities upstream of it are gone).

## Third verified fix: attempt 2's rate limiter, re-applied after the masking fixes above

Re-confirmed the "it may" above directly rather than leaving it as a guess. Re-applied attempt
2 exactly (`_previous_bend: Dictionary`, always ease `_select_feasible_bend`'s result toward
the fresh search result at a bounded 240 deg/sec rate instead of snapping, with the same
zero-delta-reuse and `side`/`delta`-gated opt-in as before). This is the identical code that
previously moved *nothing* when tried in isolation (see "Fix attempts" above) - the only
difference this time is that both upstream discontinuities found afterward (the
`adjust_idle_slope_target` reacquisition bug and the seam-freeze override) are already fixed.

**Result: it now works.** `ramp_45_yaw_315` fully passes `spin_foot_step` (was 0.312m,
previously untouched by either other fix). `ramp_45_yaw_045` dropped from 0.222m to 0.041m -
right at the 0.040m limit, from a case that was similarly untouched before. Ramp locomotion
failures: 22 (session start) -> 21 (after the two earlier fixes) -> still 21, but `spin_foot_step`
no longer appears in the failure list for *any* of the 24 cases except the single
`ramp_45_yaw_045` line, and there only by 0.001m. The remaining 21 failures are entirely
`foot_float`/`foot_penetration`/`spin_unplanted` now - a materially different, smaller-scoped
problem than the one this task started with.

**Unexpected bonus**: `foot_ik_idle_plant_stability_check.tscn`'s `turn_step_m` moved for the
first time all session - 0.056851 -> 0.054227. Small, and the check's overall `FAIL` is driven
by a different field (not yet identified which), but this is the first fix in this task's
entire history to reach the flat-ground case at all, since `_select_feasible_bend` runs on
every surface unlike the two `stationary_slope`-gated fixes above. Not investigated further
this pass - worth returning to given this now-confirmed real effect.

Verified no regressions via the full exhaustive suite: matches the previous fix's run
byte-for-byte in its diff, `FOOT_IK_POSE_CONTINUITY_CHECK` unchanged at `max_jump_m=0.012522`.

**Lesson for next time this pattern comes up**: a fix that shows zero effect when first tried
is not necessarily wrong - it can be correct but masked by a *different*, larger discontinuity
elsewhere in the same pipeline that dominates the measurement. This session's own established
discipline (revert on a null result, don't stack more changes blind) was still the right call
each time it happened - the difference here is that after fixing the two upstream issues
separately and *then* re-testing the earlier reverted attempt with fresh evidence, it turned
out to be correct all along.

**`ramp_45_yaw_045`'s last 0.001m is not rate-sensitive**: tried `BEND_HYSTERESIS_SPEED_DEGREES`
at 200 and 100 (down from 240) to see if simply slowing the ease-in further would close this
case's final `spin_foot_step=0.041` (limit 0.040). Both produced the exact same value as 240 -
zero sensitivity across a 2.4x range. This case's residual is not being limited by this rate at
all; whatever produces its worst frame must be dominated by something else (its `foot_float`/
`foot_penetration` failures on the same case suggest a related but distinct contributor, per
012's still-open item). Reverted to 240 (confirmed via `git diff`, no change).

## turn_step_m's stalled fields explained - and a second call site found, fix attempt reverted

Followed up on `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`'s overall `FAIL` directly, since `turn_step_m`
itself (0.054227) is well under its own limit (`turn_limit_m=0.120`) and was never the actual
blocker. Found the real failing fields in `_finish_check()`'s pass/fail list:
`live_pose_joint_step_m=0.049733` exceeds `MAX_LIVE_POSE_JOINT_STEP=0.045`, and
`min_sole_clearance_m=-0.015562` exceeds `MIN_COORDINATOR_SOLE_CLEARANCE=-0.015` - both
present, and both at *exactly* the same value, across every fix applied in this task so far.

`live_pose_joint_step_m`'s invariance had a concrete cause: `foot_ik_idle_plant_stability_check`'s
"live pose" phase forces a split-height stance on flat ground and spins the body - a scenario
that engages `_limit_negative_rendered_knee` (`foot_ik_leg_solver.gd`), a wrong-side/negative-knee
correction gated to flat ground (`normal.dot(Vector3.UP) >= 0.999`) that has its own, second,
independent call into `_select_feasible_bend` - one none of this task's three fixes ever
touched, since it doesn't pass `side`/`delta` and so always took the early-return branch,
bypassing the hysteresis entirely. This is why the metric never moved: it was never reached.

**Fix attempted and reverted**: threaded `delta` through `_limit_negative_rendered_knee` and
gave its `_select_feasible_bend` call a namespaced hysteresis key (`"<side>:negknee"`, distinct
from the main path's `_previous_bend[side]`, since the two calls serve different purposes
within the same frame and sharing a key would let one silently overwrite the other's memory).
**Result: made it worse**, not better - `live_pose_joint_step_m` rose from 0.049733 to
0.083064, and the worst sample moved to a different joint entirely (`320:left:foot` ->
`129:right:knee`). Reverted immediately (confirmed via `git diff` and re-measuring back to the
exact original 0.049733) rather than trying a different rate or gating blind.

**Why this one made it worse where the main-path fix helped**: not confirmed, but the likely
difference is what this correction is *for* - `_limit_negative_rendered_knee` exists
specifically to snap a wrong-side knee back across a hard sign boundary
(`signed_flexion < 0.0`) quickly, before it renders as a visibly inverted joint. Adding
hysteresis there means the correction itself now lags, potentially rendering a partially-wrong
knee pose for several frames while easing toward the corrected one, which could read as a
larger positional discontinuity once it completes than an instant snap would have produced.
This is a real hypothesis, not verified - the general lesson from this task's "Third verified
fix" above (masking discontinuities can make a fix look like it does nothing) does not
generalize to "hysteresis is always safe to add here too."

**Still open**: `live_pose_joint_step_m` and `min_sole_clearance_m`, and by extension
`FOOT_IK_IDLE_PLANT_STABILITY_CHECK`'s overall `FAIL`. Given this specific correction resists
the same treatment that fixed the main path, a future attempt should look at
`_limit_negative_rendered_knee` on its own terms (e.g. a much faster hysteresis rate reserved
for a genuine sign-boundary crossing, or hysteresis only on the *magnitude* of the correction
rather than the bend-plane search inside it) rather than reusing the main path's fix verbatim.

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
