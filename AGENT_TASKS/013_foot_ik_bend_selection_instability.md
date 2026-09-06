# 013: Foot IK knee-bend selection instability (`_select_feasible_bend`)

## Status and scope

New, split out of [012](012_foot_ik_ramp_cross_slope_penetration.md) once investigation there
showed the bug is not ramp-specific. Root cause confirmed with direct evidence (see below); no
fix attempted yet. This is scoped as its own task because the affected function
(`_select_feasible_bend` in `actors/player/foot_ik/foot_ik_leg_solver.gd`) is shared by every
leg solve on every surface, and a known pre-existing test already fails against it.

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

## Directions worth trying (none implemented)

1. **Seed the search from the previous frame's chosen bend direction** (add a
   `_previous_bend: Dictionary` keyed by side) instead of always starting fresh from
   `preferred`. If the previous bend is still feasible, keep it (or blend toward `preferred`
   slowly); only jump immediately to a new region when the previous bend has become truly
   infeasible under the current constraints.
2. **Add epsilon margins to the constraint comparisons** (`candidate.dot(positive) <
   required_alignment`, thigh-swing/shin-limit checks) so a candidate does not enter or leave
   feasibility from floating-point noise alone - this would address the same-tick,
   same-frame-different-result symptom specifically, though probably not the larger
   frame-to-frame drift-driven flips.
3. **Rate-limit the output bend direction** the same way `_limit_correction` already
   rate-limits hip/knee rotation deltas downstream in `solve()` - simplest to implement, but
   risks double-damping (the downstream rate limiter already exists) and needs care not to
   introduce lag during legitimate fast bend changes (a real large state change, or normal
   gait's natural bend swing during a stride).

## Verification plan for whichever direction is chosen

Both of these must be checked together, not just the one the fix targets - the escape-hatch
attempt failed by only checking the first:

- **Fixes the bug**: re-run `foot_ik_ramp_locomotion_check.tscn`'s `spin_foot_step` metric
  (currently failing up to 0.548m, limit 0.040m), its `phase=move` cases (e.g. `ramp_30_uphill`,
  the same mechanism at smaller magnitude), and `foot_ik_idle_plant_stability_check.tscn`'s
  `turn_step_m` (currently 0.056851, check its specific limit) - all should improve/pass.
- **Does not regress genuine large state changes**: re-run `ramp_15_uphill`'s `hold` phase
  (the case that broke when the *different*, related escape-hatch fix was tried) and the full
  exhaustive suite (`bash /tmp/check_foot_ik_run_all.sh`-equivalent) to confirm the established
  pre-existing baseline failure set doesn't grow or change in kind.

## References

- [012](012_foot_ik_ramp_cross_slope_penetration.md) - where this was first found, via ramp
  diagonal-walk/spin test coverage; contains the fuller investigation trail and the related
  (reverted) `adjust_idle_slope_target` escape-hatch fix attempt.
- [010](010_foot_ik_target_coordinator_consolidation.md) - documents
  `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`'s `turn_step_m` as a known pre-existing baseline failure,
  never previously root-caused.
- `actors/player/foot_ik/foot_ik_leg_solver.gd` - `_select_feasible_bend`,
  `_solve_bend_direction`, `solve()`.
