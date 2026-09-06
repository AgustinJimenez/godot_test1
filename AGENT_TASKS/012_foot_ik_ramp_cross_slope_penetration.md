# 012: Foot IK ramp cross-slope/diagonal penetration

## Status and scope

Found while extending test coverage. Root-caused and partially fixed: the dominant
`foot_penetration` symptom during idle-spin-on-ramp is fixed (see "Partial fix" section below).
Two smaller, distinct symptoms remain open: `spin_foot_step` (large frame-to-frame foot jump
during spin) and the `phase=move` diagonal-walk failures. Test coverage change
(`tests/manual/foot_ik/foot_ik_ramp_locomotion_check.gd`) is still not wired into any committed
check script.

## What changed and why

`foot_ik_ramp_locomotion_check.gd` previously only walked straight uphill and straight downhill
per ramp angle (2 cases), then did a stationary 360-degree spin-in-place. Diagonal or
cross-slope *walking* was never tested, even though the stationary spin already covers every
facing angle. Added 6 more cases per ramp angle (yaw 45/90/135/225/270/315 degrees), walking
from ramp center rather than adding spawn positions - mirrors the same "position barely
matters on a uniform incline, angle is what finds bugs" reasoning validated in
`foot_ik_ramp_matrix_check.gd`'s sweep reduction (6240 -> 168 cases, same session). Runtime
impact is small (24 cases total vs. 6, still well under a minute).

## What it found

22 of 24 cases now fail (`FOOT_IK_RAMP_LOCOMOTION_CHECK`). Not a test-harness artifact: travel
and floor-contact checks all pass (character stays properly grounded on the ramp the whole
time), so the failures are genuine `foot_float`/`foot_penetration`/`spin_foot_step` violations
during move and spin phases.

| Ramp angle | Worst case | foot_penetration (limit 0.030m) |
|---|---|---|
| 15 deg | yaw_135 | 0.146m |
| 30 deg | yaw_045 | 0.282m |
| 45 deg | yaw_045 | 0.413m |

Penetration scales sharply with ramp steepness and is worst at diagonal (45/135/225/315)
headings, not pure cross-slope (90/270) - though those still fail too. The two original
uphill/downhill cases mostly only miss the new, tighter `spin_foot_step` threshold (0.040m) by
a small margin (0.044-0.060m); `ramp_30_uphill` and `ramp_45_downhill` also show real
penetration (0.042m, 0.069m), meaning even the previously "passing" straight cases weren't
fully clean once spin-step tracking was added - though that's a much smaller issue than the
diagonal cases' failures.

## Why not investigated further this session

This looks structural (the ramp-support/contact logic likely assumes or is tuned for facing
along the slope direction) and the penetration magnitudes are large enough that root-causing
it needs its own focused pass, not a continuation of an already long session. Given this
session's repeated pattern (each fix needs full-suite verification, several attempts have
caused new regressions elsewhere), this should get the same discipline: understand the
mechanism before touching ramp contact/support code, likely starting in
`foot_ik_ground_sampler.gd`'s ramp/slope contact sampling and `foot_ik_leg_solver.gd`'s
pole-vector/bend-plane selection (a facing-dependent computation, per 011's finding that pole
vector choice matters more than expected).

## Root cause found for the `phase=spin` (idle-on-ramp) failures - the worst-magnitude cases

Reproduced directly (`foot_ik_ramp_locomotion_check.tscn --quit-after 13000`) and traced via
the check's own rich per-frame diagnostic (`solve_target`/`solver_foot`/`solve_error` fields).
Splitting the 22 failures by phase shows two structurally different bugs, not one:

- **`phase=move` failures** (diagonal *walking* on a ramp): small solve errors (~0.05-0.08m),
  `stance_limited=false` always. Root cause not yet identified - separate from the finding
  below.
- **`phase=spin` failures** (idle, spinning in place on a ramp): large solve errors (up to
  0.39m) and, in every case checked, `stance_limited=true`. This is the dominant contributor to
  the worst-case penetration numbers in the table above (0.146m/0.282m/0.413m are all spin-phase
  cases at diagonal yaws). Root cause identified below.

**Mechanism**: three independently-written corrections stack without any of them being aware
of the other two's assumptions, on a facing (not position) that a flat-idle test never
exercises:

1. `stationary_slope` (`player_foot_ik_modifier.gd` ~L560) goes true whenever a leg has ground
   contact, the surface isn't flat (`raw_normal.dot(UP) < 0.999`), the body isn't translating,
   and the animation contains "idle" - exactly the ramp-idle-spin scenario.
2. For such a leg, `adjust_idle_slope_target` (`foot_ik_leg_solver.gd` L87) pushes the ankle
   target downhill, step by step, until it is within `max_hip_swing_degrees` reach - this is
   the ramp's own accommodation for idle stance, and it *does* apply an
   `IDLE_STANCE_MIN_SIDE_CLEARANCE` nudge to the candidate target using a flattened
   (`y=0`) hip-to-hip axis as its notion of "left".
3. `solve()` (`foot_ik_leg_solver.gd` L333) then does the actual two-bone IK against that
   already-adjusted target. Confirmed via the diagnostic that on steep ramps at diagonal
   headings the adjusted target still ends up beyond simple reach (`hip_target=0.987` /
   `hip_target=1.001` distance vs. `reach=0.888` max extension in two captured examples) - the
   13-iteration downhill nudge in step 2 does not always converge inside reach. `solve()`'s own
   hip-swing clamp (L405-412) then rotates the thigh direction back toward straight-down,
   pulling the *solved* foot position away from where step 2 placed the target - in a direction
   step 2 never accounted for.
4. `_limit_idle_stance_crossing` (`foot_ik_leg_solver.gd` L632) then re-checks stance clearance
   a *third* time, but against `new_foot_pos` (the position after step 3's reach/swing
   clamping), using the same flattened hip-axis notion of "left" as step 2. Because step 3 can
   have moved the foot laterally in a way step 2 didn't predict, this check now sees crossed
   legs where none of the earlier steps did, and blends the pose back toward the *animated*
   foot position (`base_foot`, tuned for flat ground) to restore clearance. On a 30-45 degree
   ramp that animated fallback pose sits far from the real slanted surface, producing the
   observed 0.1-0.41m penetration. `debug_stance_limited[side] = true` in every large-magnitude
   spin-phase failure sample checked confirms this is the active path, not a coincidence.

None of steps 2-4 use the ramp's surface normal when deciding what "crossed legs" means - all
three treat "left" as a purely horizontal (`y=0`) direction, which is a reasonable
simplification on flat ground but not on a slope, and none of the three is aware that another
of the three already moved the foot for a different reason. This is the same shape of problem
009's original review flagged (multiple independent per-leg corrections with no shared model of
what's already been decided), now concretely observed rather than theorized.

**Not attempted this session**: an actual fix. The three-stage interaction above needs a
design decision (e.g., should `_limit_idle_stance_crossing`'s clearance check project onto the
slope plane instead of using a flat axis, should step 2's downhill nudge and step 4's
stance-crossing check share one clearance decision instead of computing it twice, or should
step 3's hip-swing clamp preserve step 2's already-negotiated lateral position instead of
re-deriving thigh direction from scratch) rather than a quick patch - especially given this
session's own repeated experience that touching one of several interacting corrections tends to
surface a new failure elsewhere. The `phase=move` (walking) failures also still need their own
root-cause pass; they are confirmed distinct from this mechanism, not the same bug.

## Partial fix: exempt stationary_slope legs from the flat-ground stance-crossing fallback

Applied the smallest of the design options above rather than the more invasive slope-plane
projection or shared-clearance-decision redesigns: `_limit_idle_stance_crossing` (step 4) is
now skipped entirely for a leg already flagged `stationary_slope` (the same flag that gates
step 2's ramp-aware `adjust_idle_slope_target`). Rationale: step 2 already negotiated stance
clearance for this leg using slope-aware knowledge; step 4's fallback - blending toward the
raw *animated* pose - assumes flat ground, which is false by construction for a
`stationary_slope` leg and is exactly what produced the deep penetration (the animated pose
sits well below/above a steep ramp's real surface). Implementation: threaded `stationary_slope`
(already computed per-leg in `player_foot_ik_modifier.gd`) through to `solve()`'s options
dict, and changed the guard from `if not target_plan_validated:` to
`if not target_plan_validated and not stationary_slope:`.

**Result (re-ran `foot_ik_ramp_locomotion_check.tscn` directly)**: fixes the mechanism traced
above but only partially fixes the test - `foot_penetration` cleared entirely on the 15-degree
ramp's 6 diagonal cases (previously up to 0.146m) and dropped substantially on 45 degrees
(worst case 0.413m -> 0.202m), confirmed via `stance_limited=false` and `solve_error=0.000` at
the same sample point that previously showed `stance_limited=true solve_error=0.360`. Still 22
of 24 cases fail overall - a second, apparently unrelated symptom (`spin_foot_step`: a large
frame-to-frame foot position jump during the spin phase, up to 0.548m, limit 0.040m) is
essentially unchanged by this fix and is not yet root-caused. The `phase=move` failures
(diagonal walking) are likewise untouched, as expected (`_limit_idle_stance_crossing` never
ran for them - the animation is not idle).

Verified against the full exhaustive suite before committing: output is byte-for-byte identical
to the pre-fix baseline (`FOOT_IK_POSE_CONTINUITY_CHECK`, `FOOT_IK_LEDGE_SAFETY_CHECK`,
`FOOT_IK_SPLIT_STANCE_WALK_CHECK` and the full pre-existing failure set all unchanged) - this
change only affects legs where `stationary_slope` was already true, and the exhaustive suite's
own idle-on-slope coverage (`FOOT_IK_KNEE_FLEX_CHECK`'s ramp cases, etc.) shows no new failures
or altered values. `foot_ik_ramp_locomotion_check.tscn`/`.gd` are not wired into any of the
committed check scripts yet (still standalone, per the "What changed and why" section above),
so this fix's improvement isn't visible in the committed suite's pass/fail counts.

**Still open**: `spin_foot_step` (root cause now found, see below - needs a more careful fix
than the one attempted), the `phase=move` diagonal-walk failures (separate, smaller-magnitude,
not yet investigated), and wiring `foot_ik_ramp_locomotion_check.tscn` into a committed check
script so this coverage isn't only run manually.

## spin_foot_step root cause found - naive fix regressed a different case, reverted

Instrumented the check further (temporary fields added directly to
`foot_ik_ramp_locomotion_check.gd`'s existing per-frame `detail` string, kept committed since
they're generically useful: `pole_align`, `shin_clamped`, `neg_knee_clamped`, and new
`spin_target_step`/`spin_ankle_step` fields tracking frame-to-frame deltas of the *input*
target vs. the *solved* ankle position separately). Result at every worst-`spin_foot_step`
sample checked: `spin_target_step` stays a smooth ~0.014-0.018m/frame (the requested target
barely moves) while `spin_ankle_step` matches `spin_foot_step` almost exactly (0.3-0.55m) -
the solved *ankle* jumps even though the requested surface target does not. None of the
existing clamp-tracking debug fields (`stance_limited`, `swing_clamped`, `shin_clamped`,
`neg_knee_clamped`) are active at these frames, and `solve_error` is ~0.000, ruling out every
previously-instrumented clamp path.

**Root cause**: `adjust_idle_slope_target` (`foot_ik_leg_solver.gd` L87, the same
`stationary_slope`-only function from the earlier fix above) pushes its `candidate` downhill in
fixed 0.05m steps, up to 13 times, stopping once `_target_thigh_swing(candidate)` is within
`max_hip_swing_degrees`. As the body rotates during an idle spin, that swing angle for a given
candidate changes with facing, so the number of 0.05m steps needed to satisfy the threshold can
change discretely from one frame to the next - and near certain yaws this was observed to jump
by several steps at once (not just one), producing a `candidate` that moves by several tenths
of a meter in a single frame. The result is smoothed via `previous.move_toward(candidate,
0.015)` (L105) - a slow, gradual filter - *except* for an escape hatch: `if
previous.distance_to(candidate) > 0.25: previous = candidate` (L103), which throws away the
smoothing and jumps straight to the new candidate whenever the raw discontinuity exceeds
0.25m. That escape hatch is exactly what turns the discrete iteration-count jump into a visible
one-frame foot pop.

**Fix attempted and reverted**: removed the `>0.25` escape hatch entirely, relying on
`move_toward` alone regardless of how large the mismatch is. This fully addressed the traced
mechanism (spin-phase pops disappeared) but broke a different, previously-passing case:
`ramp_15_uphill` newly failed with `foot_float=0.452m` during the `hold` phase
(`solve_error=1.336` at that sample) - a large, genuine mismatch (e.g. right after an
animation/phase transition) that used to snap correctly via the escape hatch now converges at
only 0.015m/frame, leaving the foot floating far from the real target for many frames. Total
failures went from 22 to 24 - a net regression, not a fix. Reverted immediately (one hypothesis,
one test, revert on the first new regression - per this session's established discipline)
rather than attempting a second patch on top.

**What a real fix needs**: the escape hatch's fast-snap behavior is genuinely necessary for a
true large state change (phase transitions, animation switches) but actively harmful for the
gradual, purely-rotational drift a spin produces. Two directions worth trying in a future pass,
neither attempted here: (a) make the downhill search itself continuous instead of discrete
fixed-0.05m steps (e.g. binary-search or analytically solve for the exact downhill distance
that makes the swing angle equal the limit), removing the discontinuity at its source rather
than smoothing over it; or (b) keep the escape hatch's fast path but bound its per-frame
movement to something closer to the test's own tolerance (e.g. clamp the snap itself to the
current frame's actual need rather than a full teleport) so a real large-mismatch case still
converges quickly without a single-frame pop bigger than a few centimeters. Either needs the
same two-case verification this attempt lacked: confirm it fixes the spin case *and* re-check
`ramp_15_uphill`-style large-mismatch cases before considering it done.

## adjust_idle_slope_target's own candidate ruled out; _select_feasible_bend is the new suspect

Followed up on direction (a) above by first checking whether the downhill-search's discrete
0.05m steps were really the source of the discontinuity, rather than assuming it and jumping
straight to a fix. Added temporary debug instrumentation (not committed - reverted after this
investigation) printing, on every `adjust_idle_slope_target` call for the right leg, the
physics-frame number, iteration count consumed, and resulting candidate distance. Ran the full
13,000-frame `foot_ik_ramp_locomotion_check.tscn` and checked every consecutive pair of calls
during a spin for a jump: **none found** - iteration count never changed by more than a few
steps between adjacent frames, and candidate distance never jumped more than 0.1m. This
disproves the "coarse discrete step size in the downhill search" mechanism entirely; the
function's own output is smooth throughout. (This also confirms the earlier revert - restoring
the `>0.25` escape hatch - was the right call for the right reason: the mismatch it needs to
handle really is about genuine large state changes, not the pattern hypothesized here.)

Since `adjust_idle_slope_target`'s returned target is smooth, the pop must originate later, in
`solve()`'s own bend-direction selection for that (smooth) target. Traced the call chain:
`_solve_bend_direction` -> `_select_feasible_bend` (`foot_ik_leg_solver.gd`, the 145-step,
2.5-degree-resolution angular search that picks the closest-to-preferred knee-bend direction
satisfying alignment/thigh-swing/shin-limit constraints). This function is the new leading
suspect because, unlike every other mechanism in this file, **it has no continuity or
hysteresis at all** - no previous-frame reference, no rate limit, no smoothing. If the
previously-valid bend direction crosses out of the constrained region as the body rotates, the
nearest-candidate search can jump to a different valid region of the circle in a single frame:
the classic
"IK pole vector flip" discontinuity. (`_limit_upright_shin`, checked as a second candidate in
the same call chain, was ruled out by inspection: it early-returns unmodified whenever
`normal.dot(Vector3.UP) < 0.999`, i.e. on any of these ramps, so it cannot be involved.)

Added one more temporary debug probe inside `_select_feasible_bend` (also reverted, not
committed) to print whether the search used a rotated `best` candidate or fell through to
`preferred`, and the angle between them - but did not get to correlate it against the known
failing frames before stopping this pass. **Not confirmed yet**, only the leading hypothesis.

Reverted both temporary debug additions (`foot_ik_leg_solver.gd` is back to its last-committed
state, confirmed via `git diff` and a clean lint run) rather than leaving throwaway
instrumentation in a committed file, or attempting a third speculative fix without first
confirming this hypothesis the same way the second one was confirmed and ruled out.

**Next step for a future pass**: confirm `_select_feasible_bend` is really the source (repeat
the same "instrument and check for a discontinuity" approach used above, this time on its
output angle rather than the target). If confirmed, the fix needs to add some form of
continuity to that search - e.g. seed it from the previous frame's chosen bend direction rather
than always restarting from `preferred`, or blend across a boundary crossing instead of jumping
- without breaking the property that makes it valuable in the first place (finding a genuinely
feasible bend plane on demand, including for legitimate large state changes). Any fix must be
verified against the same two categories that caught the previous attempt's regression: does it
fix `spin_foot_step`, and does it leave large-genuine-state-change cases
(`ramp_15_uphill`-style) working.

## Same bug found again via a different harness

`scripts/check_foot_ik_ramps.sh` (245 fixed idle-pose cases, unrelated to this task's
locomotion changes) independently shows real penetration at the same kind of position: on the
45-degree ramp, `top_left`/`top_center`/`top_right` facing `uphill` all show ~10.5cm
penetration (`foot_ik_ramp_matrix_check.tscn`), confirmed via `git stash` to be identical to
the pre-existing baseline (`max_depth_m=0.105989` unchanged). Same category as this task's
locomotion-driven finding: steep ramp, extreme (near-edge or heading-dependent) case, not
caused by today's session's changes. Two independent harnesses agreeing strengthens the case
that this is a real, structural gap rather than a harness artifact.

(Separately, `FOOT_IK_RAMP_MATRIX_CHECK`'s own summary line miscounts -
`failed_cases=0 worst_depth_m=0.0` even when individual `FOOT_IK_RAMP_CASE FAIL` lines show
real failures and depths - a pre-existing cosmetic bug in the check's own aggregation, not
investigated.)

## References

- `tests/manual/foot_ik/foot_ik_ramp_locomotion_check.gd` - the extended check.
- [011](011_foot_ik_flat_idle_pose_divergence.md) - a related pole-vector-adjacent finding
  from the same session, possibly connected (both are rotation/heading-dependent divergences
  in the same closed-form IK solve).
