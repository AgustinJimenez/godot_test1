# 013: Foot IK knee-bend selection instability (`_select_feasible_bend`)

## Status and scope

New, split out of [012](012_foot_ik_ramp_cross_slope_penetration.md) once investigation there
showed the bug is not ramp-specific. Root cause confirmed with direct evidence (see below).
Three fix attempts made, none successful (see "Fix attempts" below) - this is scoped as its
own task because the affected function (`_select_feasible_bend` in
`actors/player/foot_ik/foot_ik_leg_solver.gd`) is shared by every leg solve on every surface, a
known pre-existing test already fails against it, and the fix turned out to need more
foundational tracing (through an unidentified additional layer between bend selection and the
rendered pose) than the first three attempts assumed.

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

**Not yet identified**: what specifically sits between `solve()`'s `new_foot_pos` and the
test's measured sole position that reduces a 2.68m internal step down to ≤0.55m externally.
Likely candidates worth checking first in a future pass, in `player_foot_ik_modifier.gd`'s
per-frame pipeline: the pelvis lateral-shift/recenter logic (the exact mechanism 011 already
found to matter for a different rotation-driven pose issue), any blending between
`_final_bone_poses` and the raw per-leg solve, or a second solve pass this session never
accounted for. Finding that layer is the prerequisite for any of the three directions below to
be verifiable at all - a fix inside `_select_feasible_bend` cannot be confirmed working or
not working without first knowing what happens to its output afterward.

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
