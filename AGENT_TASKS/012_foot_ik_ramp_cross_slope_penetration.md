# 012: Foot IK ramp cross-slope/diagonal penetration

## Status and scope

Found while extending test coverage. Root-caused and partially fixed: the dominant
`foot_penetration` symptom during idle-spin-on-ramp is fixed (see "Partial fix" section below).
`spin_foot_step`'s root cause is now confirmed - `_select_feasible_bend`'s knee-bend-plane
search flips discontinuously under small input changes - but **this turns out not to be
ramp-specific**: the same flip, at larger magnitude, reproduces on flat ground and likely
explains a separate, previously-unexplained pre-existing baseline failure
(`FOOT_IK_IDLE_PLANT_STABILITY_CHECK`'s `turn_step_m`). See the dedicated section below;
fixing it is scoped as its own future task, not finished here. The `phase=move` diagonal-walk
failures were *suspected* to be the same root cause manifesting during walk gait instead of
spin (see "phase=move failures also trace to the same root cause" below) - **this did not hold
up**: with all three of 013's fixes applied, `ramp_30_uphill`'s move-phase `foot_penetration`
was still exactly, bit-for-bit unchanged from its very first measurement, proving `phase=move`
a real, distinct bug. It is now **fixed**: `_limit_correction`'s joint-rotation rate limit used
an `if/elif` chain where ordinary walking's `shared_drop > 0.001` branch (720 deg/sec) always
matched before the ramp-specific branch (3600 deg/sec, whose own comment describes this exact
"leg trails behind on steep slopes" symptom) could ever be reached - see "Fixed: `_limit_correction`'s
rate-limit branch order" near the end. `ramp_30_uphill`'s and `ramp_45_yaw_225`'s move-phase
`foot_penetration` are both completely gone after the fix, verified with no regressions via the
full exhaustive suite.
Test coverage is now runnable independently via `scripts/check_foot_ik_ramp_locomotion.sh` (see
"Wired into a runnable script" section below). After 013's three fixes closed nearly all of
`spin_foot_step`, this task's original spin-phase `foot_float`/`foot_penetration` symptom went
through four successive corrections: three disproven attribution attempts
(`adjust_idle_slope_target`'s downhill loop; the `likely_planted` lock; the turn-escape not
firing - each kept in full since each ruled out a real, plausible candidate with hard evidence)
before finding that the test's `RAMP_WIDTH=3.0` puts the ramp's physical edge exactly where an
idle stance's natural sway swings the foot at certain diagonal facings, causing a genuine
raycast miss right at that boundary. Tested directly by doubling the width: **partially
confirmed** - failures dropped from 21 to 18 with real, measurable improvement, but roughly
18 cases still fail at similar magnitude, meaning edge proximity is a real contributor but not
the sole cause, and a separate, still-unidentified mechanism (the `phase=move` bug above, and
possibly more) accounts for the rest. Not fixed this session, given its length.

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
or altered values. This coverage was not runnable from a committed script at the time of this
fix (see "Wired into a runnable script" below, done later), so this fix's improvement wasn't
visible in the committed suite's pass/fail counts until that was addressed.

**Still open**: `spin_foot_step` (root cause now found, see below - needs a more careful fix
than the one attempted, split out into [013](013_foot_ik_bend_selection_instability.md)) and
the `phase=move` diagonal-walk failures (now believed to be the same root cause as
`spin_foot_step`, see below - not separately fixed).

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

## _select_feasible_bend confirmed as the root cause - and it is not ramp-specific

Followed up on the leading suspect above with the same call-site-scoped instrumentation
(temporary, reverted after this investigation - added a `dbg` parameter threaded only through
`solve()`'s own call to `_solve_bend_direction`/`_select_feasible_bend`, gated to the right leg
and an env var, so `adjust_idle_slope_target`'s internal search calls are excluded and only the
actual per-frame solve is logged).

**Confirmed on the ramp**: re-ran the full `foot_ik_ramp_locomotion_check.tscn` and found
frequent, large discontinuities throughout the run (not just at the previously-tracked worst
cases) - `used_best` (whether the 145-step search found a rotated candidate at all) toggles
between `true`/`false` from one frame to the next, with the resulting angle-from-preferred
jumping directly between 0 degrees and 22-60 degrees. At the leg's ~0.4-0.5m length, a 30-60
degree knee-bend-plane flip alone accounts for the observed 0.3-0.55m sole displacement -
this is not a coincidental correlation, it is large enough to be the whole effect.

**Confirmed on flat ground too, and worse**: ran the same instrumentation against
`foot_ik_idle_plant_stability_check.tscn` (unrelated to ramps - the project's existing idle/turn
regression test) and found the same flip, larger (0 to ~118 degrees) and at higher frequency,
concentrated exactly around the frames of that check's turn-in-place segment. Most tellingly,
two consecutive log lines showed the *same* physics frame number with wildly different results
(118 degrees, then 0 degrees) - meaning two evaluations within a single tick, on presumably
near-identical inputs (likely a `SkeletonModifier3D` zero-delta re-evaluation, a mechanism
already documented in `AGENTS.md`), produced very different answers. That is a floating-point
boundary-sensitivity symptom, not a smoothly-varying function crossing a rotation threshold -
`_select_feasible_bend`'s valid region is apparently narrow, possibly disconnected, and small
input perturbations decide which of two very different candidates numerically wins the
`score < best_score` comparison.

**This likely explains a previously-unexplained, pre-existing baseline failure**:
`FOOT_IK_IDLE_PLANT_STABILITY_CHECK`'s `turn_step_m=0.056851` value (present in every baseline
run this whole session, never root-caused, treated throughout as an unrelated known-red case)
occurs in the same turn-in-place scenario where this instrumentation just found the flip firing
directly. Not confirmed as the same numeric cause (would need to correlate the exact frame and
side and re-derive the metric), but the mechanism, the animation, and the body-rotation trigger
all match closely enough that a future investigation should check this connection before
assuming they are unrelated - fixing `_select_feasible_bend` may turn out to fix two
independently-tracked issues, not one.

**Scope correction**: this is not a ramp-specific bug. The ramp is what made it visible (the
new diagonal-walk/spin test coverage this session), but the underlying instability is in the
core bend-direction search used by every leg solve, on any surface, whenever a rotating body
puts `preferred` near the edge of the search's feasible region. Given that scope, a fix here
should be scoped and verified as its own task (touching a shared, heavily-used function, with a
known-pre-existing dependent test) rather than folded into this ramp-specific one - not
attempted further in this task; recommend a fresh `AGENT_TASKS` entry when picked up next,
cross-linking both this file and the `IDLE_PLANT_STABILITY_CHECK` connection above.

Reverted the instrumentation (`foot_ik_leg_solver.gd` confirmed back to its last-committed
state via `git diff` and a clean lint run) - nothing committed from this investigation beyond
this write-up.

## phase=move failures also trace to the same root cause

Followed up on the still-open `phase=move` (diagonal walking) failures to check whether they
are a genuinely separate bug or another manifestation of `_select_feasible_bend`'s
instability. Picked the simplest available repro - `ramp_30_uphill`, a plain straight walk, not
even diagonal - whose worst move-phase sample (`frame=53 solve_error=0.054`) showed no active
clamp flags, matching the same "nothing tracked explains it" signature `spin_foot_step` had
before `_select_feasible_bend` was found.

Re-added the same call-site-scoped `dbg` instrumentation used above (temporary, reverted after)
and re-ran the full ramp locomotion check. Found the same flip during the settle-to-move
transition of the very first case, well before any spin phase: `used_best`/angle-from-preferred
jumps 0 -> 10 -> 0 -> 30 -> 0 degrees across frames 37-44, then holds steady afterward. Smaller
in magnitude than the spin-phase flips (10-30 degrees here vs. 22-118 degrees during
spin/turning), consistent with a gait swing changing `preferred` more gradually than a body
rotation does, but the same mechanism.

**Conclusion at the time**: `phase=move`'s failures are not a separate bug - they are
`_select_feasible_bend`'s instability (013) triggered by ordinary gait-driven changes to the
preferred bend direction instead of body rotation. No separate fix is needed here; whatever
fix 013 settles on for the rotation case should be verified against a walking case (e.g.
`ramp_30_uphill`) too, since it is a cheap, already-identified additional regression check.
Reverted the instrumentation (confirmed via `git diff` and a clean lint run) - nothing committed
from this investigation beyond this write-up and the addition of `ramp_30_uphill` to 013's
verification plan.

**This prediction did not hold up.** All three of 013's fixes are now applied and verified
(the slope-target reacquisition fix, the seam-freeze exemption, and the bend-plane hysteresis
that specifically targeted this exact instability). `ramp_30_uphill`'s `foot_penetration` is
still `0.042m` - **exactly, bit-for-bit the same value** as the very first measurement taken at
the start of this task, before any fix in either 012 or 013 was applied. `phase=move`'s
failures were not fixed as a side effect after all; whatever causes them is a genuinely
different mechanism than the bend-plane flip, not merely a smaller-magnitude instance of it.
See "phase=move is a real, distinct solve error - not explained by anything fixed today" below
for the follow-up that found this and re-scoped it correctly.

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

## Wired into a runnable script

Checked the claim that this coverage was "not wired into a committed check script" before
acting on it, and found it was only half true: `foot_ik_ramp_locomotion_check.tscn` was already
invoked from inside `scripts/check_foot_ik.sh` (added alongside this task's test changes) - but
that script exits immediately on its first failing check (`set -eu` plus an explicit `exit 1`
per check), and a pre-existing failure earlier in the sequence (`FOOT_IK_KNEE_FLEX_CHECK`, not
even the previously-assumed `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`) already stops the script
before it ever reaches the ramp locomotion block. The same problem already affected the two
scripts chained after it (`check_foot_ik_stair_repeat.sh`, `check_foot_ik_locomotion.sh`) - none
of the three run in a normal `check_foot_ik.sh` invocation today. `check_foot_ik.sh` is also not
part of any active CI workflow (`.github/workflows/project-checks.yml` is manual-trigger-only
and runs `scripts/check.sh` - lint only), so this is purely a local/agent developer-workflow gap,
not a CI regression.

Rather than change `check_foot_ik.sh`'s fail-fast behavior (a bigger, cross-cutting redesign -
39 `exit 1` sites - that also affects the two pre-existing sibling checks and is out of this
task's scope), extracted the ramp locomotion check into its own standalone script,
`scripts/check_foot_ik_ramp_locomotion.sh`, matching the exact pattern already used by
`check_foot_ik_stair_repeat.sh`/`check_foot_ik_locomotion.sh` (independently invocable,
`mktemp` log file, `|| true` on the Godot call, `rg`-based pass/fail). `check_foot_ik.sh` now
calls it the same way it calls those two siblings, instead of inlining the same Godot
invocation as dead code after an unreachable point. Verified: the new script alone correctly
reports the current known failure (exit 1, matching 012/013's open bugs - not something this
change fixes); `check_foot_ik.sh` still fails at the exact same pre-existing point it did
before this change (`FOOT_IK_KNEE_FLEX_CHECK`), confirming no behavior change to the rest of
the script.

**Still open, not attempted**: `check_foot_ik.sh`'s (and its now-three unreachable-in-practice
sibling scripts') fail-fast design means none of them run to completion locally while any
earlier pre-existing failure exists - this session's own `/tmp/check_foot_ik_run_all.sh`
workaround (a modified copy with all `exit 1`s suppressed) exists precisely because of this,
and had to be hand-rolled for every full-suite verification this session. Turning that
workaround into a permanent, committed mode (e.g. a `FOOT_IK_CONTINUE=1` env var that changes
whether each check's failure stops the script) would be a meaningfully larger, separate change
and was not attempted here.

## The remaining foot_float/foot_penetration failures - stale-target measurement hypothesis ruled out

After [013](013_foot_ik_bend_selection_instability.md)'s three fixes closed nearly all of
`spin_foot_step`, this task's original `foot_float`/`foot_penetration` failures are the last
open item, still present on most ramp cases. They have a distinctive signature: the magnitude
tracks ramp steepness almost exactly by `sin(angle)` (15 degrees stays under the 0.04m
threshold, 30 degrees clusters around 0.055m, 45 degrees around 0.078m), and the same value
frequently appears as `+float` on one leg and `-penetration` on the other at the *exact same
frame*, with `hip_target` differing sharply from `hip_raw` on only the affected leg -
suggesting one leg's target was nudged (likely `adjust_idle_slope_target`'s downhill push) while
the other wasn't, at that instant.

That pattern raised a hypothesis worth checking before assuming a real pose bug: the test's own
`clearance := (sole_point - target).dot(normal)` measures against `_ik._smoothed_target[side]`
(the ground sampler's raw smoothed target) - but `adjust_idle_slope_target`'s nudge is applied
to a local copy in `player_foot_ik_modifier.gd` and never written back into
`_smoothed_target`. If the rendered sole is correctly following the *nudged* target, comparing
it against the *stale, pre-nudge* one would produce exactly this kind of `float`/`penetration`
reading on an otherwise correctly-grounded foot - a harness measurement gap, not a real bug.

**Ruled out**: added a temporary diagnostic (not committed) comparing `clearance` against
`_leg_solver.debug_solve_target[side]` (the real value passed to `solve()`) instead of the
stale `_smoothed_target[side]`. The discrepancy did not go away - it stayed a similar magnitude
and in some samples flipped sign, meaning the sole is not simply displaced relative to a stale
reference; it does not land where `solve()` was actually told to put it either. This is a
genuine small pose discrepancy, not a test-harness measurement artifact. Reverted the
diagnostic (confirmed via `git diff`).

**Not yet investigated further**: whether the gap between `sole_point` and
`debug_solve_target` is explained by foot-orientation-vs-surface-normal misalignment (the
`sole_depth` offset is applied along the foot's own local `sole_direction`, not necessarily
exactly along the surface normal - `sole_align` was 1.000 in one manually-checked sample, but
not re-verified for the flagged frames specifically), by `_limit_correction`'s own rate-limiting
lagging behind a target that legitimately moved, or by something else in the per-leg pipeline
between `solve()`'s procedural output and the final rendered bone pose. Given the `sin(angle)`
scaling and the asymmetric-nudge correlation, the next step should instrument
`sole_align`/`debug_final_foot_position` vs. `sole_point` directly at a flagged frame, the same
"instrument the exact boundary, don't guess" approach that worked for 013's three fixes.

## First root-cause attempt (wrong, corrected below): adjust_idle_slope_target extrapolation

Followed the recommended next step and read every field already captured in the existing detail
string (`solve_target`, `raw`, `actual_solve_target`, `solver_foot`) for the same
`ramp_45_yaw_270` sample pair used above, rather than adding new instrumentation. `sole_align`
confirmed 1.000 on both legs (foot-orientation misalignment ruled out, as suspected). The real
chain, for the affected (right) leg:

- `raw` (`debug_raw_target[side]`, the fresh raycast hit) = `(15.527, 2.320, 1.833)`.
- `actual_solve_target` (`debug_solve_target[side]`, what `solve()` actually received this
  frame) = `(15.352, 2.420, 2.175)` - **~0.4m away from the raycast hit**.
- `solver_foot` (`debug_final_foot_position[side]`, the solved ankle) matches
  `actual_solve_target` to 5 decimal places - `solve()` reached its given target essentially
  exactly. `solve_error=0.000` is correct; it is not measuring against the raycast hit.

Originally attributed the ~0.4m gap to `adjust_idle_slope_target`'s own downhill push (the `for
_step in 13: ... candidate += downhill * 0.05` loop), reasoning that its purely geometric
extrapolation along the ramp's known normal, never re-raycast against real collision, could
drift off the ramp's real finite surface over a large push. **This attribution was wrong -
confirmed and corrected below.**

### Fix attempt based on that attribution - reverted, and the attribution itself disproven

Implemented the natural fix: after the 13-step loop, if `candidate` had actually moved from
`target`, cast one ray straight down at the candidate's XZ and snap it back onto whatever real
surface that ray hit, within a small tolerance (to avoid overcorrecting onto a genuinely
different, unrelated surface). Threading a `PhysicsDirectSpaceState3D` parameter through
required updating `adjust_idle_slope_target`'s single call site.

First attempt broke the whole script's compilation (`var probe := ...raycast_ground(...)`
couldn't infer a type through the untyped `_owner._ground_sampler` reference, a GDScript static
typing gap, not a logic error) - every one of the 24 ramp cases failed with
`no_planted_foot_samples`, an unrelated-looking catastrophic symptom that was actually just the
compile error breaking the entire player script. Fixed the type annotation
(`var probe: Dictionary = ...`) and re-ran: **zero change**, byte-identical to the pre-fix
output on every case.

Instrumented directly rather than accepting a second null result blind (per this task's own
established lesson about null results needing verification, not assumption): logged every time
the reverification branch actually ran. Result: **only 6 times in a full 13,000-frame run**,
and all 6 were raycast misses. The downhill-push loop essentially never triggers for these
residual cases at all - meaning the original ~0.4m gap between `debug_raw_target` and
`debug_solve_target` was never coming from this loop in the first place. The attribution was
wrong; the loop was the wrong target for this fix. Reverted both files completely (confirmed
via `git diff`).

## Real root cause found: `likely_planted` freezes `smoothed_target` through rotation

Followed the corrected task's own advice: instrumented `_smoothed_target[side]` and
`debug_raw_target[side]` together across consecutive frames (not single-frame snapshots) for
`ramp_45_yaw_270`'s right leg. Result, frames 326 through 342 (spin phase, body continuously
rotating, `plan_owner=live_contact plan_valid=true` unchanged throughout, no owner/latch
transition of any kind):

```
frame=326 smoothed=(15.49867, 2.375652, 2.375652) raw=(15.57283, 2.321099, 1.906896) gap=0.478
frame=328 smoothed=(15.49867, 2.375652, 2.375652) raw=(15.56544, 2.320827, 1.893552) gap=0.490
...
frame=342 smoothed=(15.49867, 2.375652, 2.375652) raw=(15.50873, 2.320106, 1.810453) gap=0.568
frame=344 smoothed=(15.49888, 1.799846, 1.799846) raw=(15.49888, 1.799846, 1.799846) gap=0.000
```

`smoothed_target[side]` is **bit-for-bit frozen** for at least 8 consecutive samples (16
physics ticks) while `raw` drifts continuously and smoothly (tracking the body's rotation, as
expected - the raycast's hit point shifts as the ankle's world position orbits during a spin) -
then snaps to exactly match `raw` in a single frame, a 0.5m instant jump. None of the known
latch/freeze dictionaries were active (`_idle_frozen`, `idle_lower_latched_target`,
`idle_lower_acquiring`, `idle_stance_rehoming` all `false`/empty throughout), and the
coordinator's own plan was valid and unchanged the whole time - ruling out every mechanism this
session had already touched.

The actual cause is `foot_ik_ground_sampler.gd`'s own target-smoothing gate
(`sample()`, ~L344-368): `smoothed_target[side]` is only ever eased toward `raw_target` inside
one `elif` branch, guarded by `not likely_planted` (`likely_planted` = ground weight at or
above `PLANT_LOCK_WEIGHT`, i.e. a normal fully-planted idle foot, which is exactly the state
every leg is in throughout an idle spin). Once a leg is "likely planted," **this is the only
code path in the entire function that updates `smoothed_target` toward the raw ground point at
all** - so the target is frozen solid the instant the leg plants, for as long as it stays
planted, no matter how far the real ground contact point (correctly) moves underneath it due to
body rotation. This is correct and desirable on flat ground (a planted foot should not
re-chase a jittering raycast) but wrong here: rotation is a legitimate reason for a planted
idle foot's ground-relative target to change, and the lock does not distinguish "the raycast is
just noisy" from "the body is turning and the true contact point has genuinely moved." The
eventual multi-decimeter snap happens whenever some other event (case boundary, a landing-grace
tick, a brief weight dip) breaks `likely_planted` for one frame and lets the frozen value
resync all at once.

This is now confirmed as the real source of the residual `foot_float`/`foot_penetration` (the
render follows the frozen `smoothed_target`, which drifts arbitrarily far from where the ramp
actually is as rotation continues) and very plausibly of `spin_foot_step`'s own remaining
outlier too, once the "unfreeze" snap happens to land inside the sampled window - the two
sections above chased *how the leg reacts* to a stale target; this is *why the target goes
stale* in the first place.

**Not fixed this session.** A fix needs to teach `likely_planted`'s lock about rotation - e.g.
re-project `smoothed_target[side]` to track the body's yaw delta each frame while still
suppressing pure raycast noise, or extend the `not likely_planted` condition with an
allowance keyed to accumulated yaw change since the last update, similar in spirit to
`adjust_idle_slope_target`'s own frame-gap-based reacquisition logic from 013. Given this
touches the ground sampler's core planted-foot smoothing (a function this session has not
otherwise modified, so lower risk of compounding with 013's changes, but the mechanism itself -
"a lock with no allowance for legitimate change" - is exactly the pattern that produced
surprises in every other fix attempted today), this is left as a precisely diagnosed,
ready-to-fix item, not attempted here given the length of this session.

**A likely-relevant clue for that fix**: `sample()` already has a purpose-built escape for
almost exactly this situation, a few lines above the `likely_planted` gate -
`if hit["hit"] and likely_idle and raw_normal.dot(Vector3.UP) < 0.999: ... if body_turning:
smoothed_target[side] = raw_target` (~L339-343, comment: "A gradual turn supplies smoothing; a
stale ramp target becomes unreachable"). This escape clearly exists to solve exactly this class
of bug, yet it evidently does not fire during the frozen window found above.

Checked both candidate explanations directly (test-script-side instrumentation of
`_gait_tracker.is_body_turning(side)` and `_ik._velocity_suppressed` across the same frozen
window) and **both are ruled out**: `turning=true` and `velocity_suppressed=false` on every
single sample across the entire frozen window, frames 326 through 346. `body_turning` is
correctly detected throughout, and `likely_idle`'s other dependency is inactive - so line 339's
condition should be satisfied on every frame, yet `smoothed_target` still does not move. No
overwrite after L343 was found by reading the rest of the function either (the idle-stance-rehome
block a few lines below reads `smoothed_target` but does not appear to write it back when the
target is already valid, and the `likely_planted`-gated branch is an `elif` off a
`landing_grace_time` check that shouldn't apply here).

This means either one of `hit["hit"]` / `raw_normal.dot(Vector3.UP) < 0.999` is unexpectedly
false at this exact point in the function (not yet checked directly), or there is a second
overwrite path not yet identified by reading the code. Both test-script-side instrumentation
options are now exhausted - the next step needs a temporary print placed directly inside
`foot_ik_ground_sampler.gd`'s `sample()` (not the test script) immediately after L343, showing
whether the assignment actually executes and what `smoothed_target[side]` holds one line later,
before anything else in the function can touch it. That was not attempted this session, since
it means directly modifying the ground sampler's most central function rather than a test
harness, and this session had already made three other changes to code this fragile today.

### Resolved: the print inside `sample()` found the real answer

Went ahead with that exact next step (temporary prints in `sample()` itself, reverted after -
`git diff` confirmed clean). Aligned physics-frame numbers directly between a test-script
marker and the in-`sample()` print rather than guessing at case boundaries again. Result for
`ramp_45_yaw_270`'s right leg, physics ticks 11416-11436:

```
tick 11416-11430 (8 samples): hit=false likely_idle=true normal_dot=1.0000 body_turning=(true/false alternating)
tick 11431:                   hit=true  normal_dot=0.7071 body_turning=true  -> ESCAPE FIRED
tick 11433, 11435:            hit=true  normal_dot=0.7071 body_turning=true  -> ESCAPE FIRED
```

`hit["hit"]` is **false** for the entire "frozen" window - the raw ground raycast for this leg
genuinely misses for 8 consecutive samples (15 physics ticks). `normal_dot=1.0000` during the
miss is the raycast function's own no-hit fallback (`Vector3.UP`), not a real reading. The
moment the raycast starts hitting again (tick 11431), the turn-escape fires exactly as designed
and `smoothed_target` immediately resyncs. **The freeze is not a bug in the escape or the
lock - `smoothed_target` is correctly holding the last known-good value while there is no valid
fresh ground sample to replace it with**, which is defensible, intentional behavior (better
than snapping to a fallback on a single missed ray). The earlier "false" `body_turning` counts
seen in the un-filtered aggregate check were from other phases/cases mixed into that count, not
a real contradiction - filtering by the exact physics-tick window resolved it.

### Final answer: the animated foot naturally sits at the ramp's physical edge, not a drift bug

Checked directly rather than leaving the "downhill-push drifted the raycast origin" theory
above as a guess: `sample()`'s raycast uses `foot_pos`, the **animated** foot bone position
transformed to world - not the nudged/pushed target at all, so that theory was wrong too.
Logged `foot_pos` itself during the exact miss window (physics ticks 11416-11430, same
alignment technique as before): X ranged `15.50873` to `15.56489`.

`ramp_45_yaw_270`'s ramp origin is at `X = 14.0` (`RAMP_SPACING=7.0 * angle_index=2`), and
`RAMP_WIDTH=3.0` means the ramp's physical edge sits at `X = 15.5`. The animated foot position
during the miss sits essentially **exactly on that edge line** (`15.51` to `15.56`, i.e. at or
a few centimeters past it) - not a symptom of any drift/nudge bug at all. At this diagonal
facing, the idle animation's natural stance width swings this foot laterally right up against
the ramp's finite boundary; a few millimeters of pose jitter frame to frame (visible in the
tiny X fluctuations above) is enough to flip the raycast between landing just inside the ramp
and just past its edge, into empty space.

**This reframes the whole remaining item**: it is arguably not a Foot IK bug at all, but a test
configuration limit - `RAMP_WIDTH=3.0` (1.5m half-width) does not leave enough lateral
clearance for a normal idle stance's natural sway once the character is centered and facing
diagonally, at least for the leg geometry this character uses.

**Tested directly** (temporary local edit, reverted after - `git diff` confirmed clean):
doubled `RAMP_WIDTH` to `6.0` and re-ran the full 24-case check. Result: **partial
confirmation, not total**. Failures dropped from 21 to 18, and several cases that were failing
disappeared from the list entirely (e.g. `ramp_15_yaw_270`) - real, measurable improvement,
consistent with edge proximity being a genuine contributing factor. But 18 cases still fail at
a similar magnitude (`foot_float`/`foot_penetration` still 0.04-0.10m, `spin_foot_step` still
clustered around 0.042-0.045m on most cases), and a few cases that were clean at 3.0m width now
show small new `foot_float`/`foot_penetration` readings at 6.0m width (e.g. `ramp_45_yaw_090`,
`ramp_45_yaw_270`) - likely because widening the ramp moved *where* the edge is, not eliminated
edge effects altogether, or because a second, independent, smaller-magnitude source (not yet
identified) persists regardless of ramp width. `ramp_45_yaw_225`'s `foot_penetration=0.103` in
particular did not move at all between the two widths, suggesting that specific case's cause is
unrelated to the edge theory entirely - **confirmed correct**: that case's `foot_penetration`
turned out to be the `_limit_correction` rate-limit branch-order bug fixed further below, a
completely different, non-edge-related mechanism, exactly as this observation predicted.

**Also confirms `ramp_15_yaw_225`'s separate `spin_unplanted=9` symptom is the same edge
phenomenon**: that case's `spin_unplanted` count was `0` in this same wide-ramp test run
(recorded in the raw log, not called out at the time) versus `9` at the normal 3.0m width - the
foot fully losing ground contact and weight during the spin, not just floating/penetrating, is
the same underlying raycast-miss-at-the-edge cause manifesting through a different downstream
consequence (`_gait_tracker.update`'s `contact_lost` derivation drops weight to zero when
`contact_hit` is false and no exemption applies, rather than the target-clearance path holding a
stale value). No separate investigation needed for this one - same cause, confirmed by the same
experiment.

**Conclusion**: edge proximity is a real, confirmed, but partial contributor - not the sole
explanation. A permanent fix should not simply widen the test ramp and declare victory; roughly
half the remaining magnitude comes from something else, not yet identified. Whoever picks this
up next should re-run the same "log `foot_pos` vs. known geometry" technique used above,
this time on one of the cases that *stayed* essentially unchanged between 3.0m and 6.0m width
(`ramp_45_yaw_225` is the cleanest candidate, given its penetration value was identical at both
widths), rather than re-investigating a case already explained by edge proximity.

## phase=move is a real, distinct solve error - not explained by anything fixed today

Followed the recommendation above and checked `ramp_45_yaw_225`'s worst `foot_penetration`
sample directly. It is `phase=move` (`anim=unarmed_walk`, `body_speed=3.200`), not `phase=spin`
at all - a genuinely different symptom class from everything fixed in 013 today, which only
ever touched idle/rotation-driven cases. `solve_error=0.117` at that sample - a real, sizable
gap between what `solve()` was asked to reach and what it actually rendered - while
comfortably inside both the anatomical reach (`hip_target=0.790` vs. `reach=0.888`) and swing
(`swing_deg=44.4`, nowhere near `max_hip_swing_degrees=100`) limits, and with every tracked
clamp flag (`swing_clamped`, `shin_clamped`, `neg_knee_clamped`, `stance_limited`) false.

Cross-checked against the simplest available case, `ramp_30_uphill` (a plain straight walk, not
even diagonal), whose own move-phase `foot_penetration=0.042` was flagged as early as this
task's very first measurements. **That value is exactly, bit-for-bit unchanged today** despite
all three of 013's fixes now being applied and verified - directly contradicting the earlier
"no separate fix is needed, 013 will cover it" prediction two sections above.
`actual_solve_target` matches `solve_target`/`_solved_target_smoothed` exactly for this case
(unlike the spin-phase cases, where those two diverged sharply) - ruling out the
smoothing-cache mismatch found for the spin failures. `_limit_correction`'s ramp-specific rate
override (3600 deg/sec, specifically documented in that function as existing to prevent a
planted target from outrunning a traveling body on a ramp) should be generous enough to avoid a
lag of this magnitude during ordinary gait, but the persistent, unchanged 0.042-0.117m gap
suggests either that override isn't reaching this case, or the real cause is upstream of the
joint-rotation rate limiter entirely (e.g. in the reach/shin-flexion clamp math, or a
bend-plane effect distinct from the discontinuous flip 013 fixed).

**Not investigated further this session**, given its length - this is confirmed to be its own,
previously-mis-scoped item (not a smaller instance of 013's bug, and not resolved by any fix
applied today), worth a fresh, dedicated instrumentation pass rather than another guess appended
to an already very long investigation. The clean starting point for that pass is
`ramp_30_uphill`'s move phase specifically - it is the simplest reproduction (straight walk, no
diagonal facing, no body rotation) of a bug that has now been independently confirmed present in
at least three different cases across two ramp angles.

## Fixed: `_limit_correction`'s rate-limit branch order was shadowing the ramp override

The "not investigated further" note above undersold how close the diagnosis already was -
followed it through directly. `_limit_correction`'s angular-speed selection was an `if/elif`
chain: `shared_drop > 0.001 and not idle` (720 deg/sec, meant for stairs) was checked *before*
`normal.dot(UP) < 0.999` (3600 deg/sec, meant for ramps - that branch's own comment: "the
ordinary 120-degree budget lets the leg trail far behind that target on steeper slopes,
visibly floating or cutting through the ramp", describing this exact symptom). During ordinary
walking on a ramp, `shared_drop` is essentially always slightly positive (`0.088` in
`ramp_30_uphill`'s flagged sample) and the animation is not idle, so the first branch always
won - the ramp's own 3600 deg/sec allowance, specifically built to prevent this failure, was
never reached at all whenever a leg was also walking with any pelvis sink.

**Fix**: changed from `if/elif` (first match wins) to two independent `if`s combined via
`angular_speed = maxf(angular_speed, ...)` - each condition's own rate is still applied when it
holds, but the two are no longer mutually exclusive, since a ramp with pelvis sink is a real
combination that should get the more generous of the two allowances, not whichever check
happened to come first in the source.

**Result**: `ramp_30_uphill`'s `foot_penetration` (present since this task's very first
measurement) and `ramp_45_yaw_225`'s `foot_penetration=0.103` (the case that motivated this
whole investigation) are both **completely gone** - not reduced, eliminated. Verified via the
full exhaustive suite: no regressions, byte-for-byte identical to the previous baseline, with
every stair/pelvis-drop-sensitive check (`FOOT_IK_STAIR_LOCOMOTION_CHECK`,
`FOOT_IK_STAIR_SETTLE_CHECK`, `FOOT_IK_LANDING_STABILITY_CHECK`) unchanged at identical values -
confirming the stairs branch's own original behavior is preserved everywhere it used to apply
alone.

**Still open**: overall ramp-locomotion failures remain at 21 (unchanged in count, since the
edge-proximity-driven spin failures and other `spin_foot_step` cases are untouched by this fix)
- but this specific symptom class, present since the very start of this task, is resolved.

## Preview-scene FPS drop near ramps/stairs (not a Foot IK regression)

**Superseded by [014](014_foot_ik_preview_scene_fps_collapse.md)**: the fix below turned out to
be real but insufficient - the crash still reproduces after it. Task 014 has the full,
up-to-date investigation trail; this section is kept as the historical record of the first
(partial) fix found here.

User manually played `foot_ik_preview.tscn` and observed severe FPS drops (60 -> single
digits) specifically near the ramp/stair platforms, reproducible on repeat visits and fully
recovering when standing elsewhere. Added two throwaway-but-kept-for-reuse diagnostics to
chase it: `[FOOT_IK_PERF]` (per-leg-solver `solve()` cost, in
`actors/player/foot_ik/foot_ik_leg_solver.gd`, gated behind `FOOT_IK_PERF_LOG=1` so it's a
no-op otherwise) and `tests/manual/foot_ik/foot_ik_perf_probe.gd` (engine-wide
`Performance.get_monitor()` counters plus a node-tree diff, same env-var gate, attached as a
child node in `foot_ik_preview.tscn`).

**Ruled out**: Foot IK's own `solve()` cost (2-9ms total per second, across every active
leg-solver instance combined - negligible). Node/object count growth (bounded; the one real
node-count spike found, `ui/hud.gd`'s debug Animation panel building ~105 buttons in one frame,
is old (2026-07-16) unrelated code and cost ~3fps, not the crash). Static memory growth
(plateaus after initial load). Rendered-primitive growth alone (climbed identically whether
standing still or not, and standing still never dropped below 60fps despite primitives
climbing the same amount - proves it's not by itself the cause).

**Root cause**: every authored tread/riser/platform box on ramps and stairs is a `CSGBox3D`
with `use_collision = true`. `CSGShape3D` always bakes its own collision as a concave
`ConcavePolygonShape3D` trimesh - even for a plain box - which is markedly more expensive to
query than a convex primitive shape. Foot IK's ground sampler raycasts the ground every
physics frame for every foot of every nearby idle/walking character in the scene (this preview
scene runs ~25 of them simultaneously), so every box near a ramp/stairs is repeatedly
raycast-queried against a concave shape instead of a cheap convex one. `physics_ms` spiked to
3-5x baseline (up to 53ms vs ~10ms normal) exactly during the crash windows while `process_ms`
(script/logic cost, including Foot IK's own solve time) stayed flat and tiny - the cost is
inside the physics engine's own collision query, invisible to any Foot IK-side timer. This is
distinct from (and does not affect) the ramp/stair *traversal* surface the character capsule
actually walks on, which was already correctly built as its own `ConcavePolygonShape3D` on a
separate `StaticBody3D` in `foot_ik_stair_surfaces.gd`'s `_build_profile_surface` - that one is
inherently non-box-shaped and can't be simplified. The fix only touches the authored
tread/riser/platform *contact* boxes Foot IK raycasts against for foot placement.

**Fix**: added `FootIKStairSurfaces.finalize_authored_box(parent, box)` - adds the `CSGBox3D`
under `parent`, gives it a sibling `StaticBody3D` + `CollisionShape3D(BoxShape3D)` matching its
transform/size, and sets `box.use_collision = false` so the CSG node no longer bakes its own
concave collision. Wired into all four authored-box call sites: `_build_flat`, `_build_ramp`,
the per-step riser box in `_build_stairs` (all in `foot_ik_preview.gd`), and
`build_top_landing` (in `foot_ik_stair_surfaces.gd`). Verified against the full exhaustive
suite with the fix stashed vs. applied: byte-for-byte identical failure set both ways (the
same pre-existing `FOOT_IK_KNEE_FLEX_CHECK` / `FOOT_IK_LOCOMOTION_CHECK` /
`FOOT_IK_IDLE_PLANT_STABILITY_CHECK` / `FOOT_IK_RAMP_LOCOMOTION_CHECK` /
`FOOT_IK_WALK_IDLE_STANCE_CHECK` failures, unchanged) - confirms the collider swap is
behavior-neutral for every Foot IK correctness check, as expected since foot placement only
reads the box's raycast hit point/normal, not its collision shape's internal representation.

**Scope**: test-scene-only. No file under `actors/player/foot_ik/` was touched by the fix
itself (only the perf-log timing wrapper, gated off by default, was added to
`foot_ik_leg_solver.gd`). The actual game levels (`levels/*.tscn`) have no ramps or stairs yet
and their existing CSG geometry is flat, unsegmented boxes (floor/walls/ceiling) - cheap
either way. This does not change Foot IK behavior anywhere, in this scene or the real game.

**Regression test**: `tests/manual/foot_ik/foot_ik_authored_collider_shape_check.gd`/`.tscn`
calls `finalize_authored_box()` and `build_top_landing()` directly against synthetic CSG boxes
and asserts the resulting collider is a convex `BoxShape3D` on a sibling `StaticBody3D` (never
a `ConcavePolygonShape3D`), with matching size/transform, and that the CSG node's own
`use_collision` ends up `false`. Verified it actually catches the regression: reverting
`foot_ik_stair_surfaces.gd` alone makes it fail to even parse (the method no longer exists).
Wired into both `scripts/check_foot_ik.sh` and `scripts/check_foot_ik_fast.sh`.

**Still open**: two secondary findings surfaced during this investigation, neither fixed:
`ui/hud.gd`'s debug Animation panel (~105 buttons built in one synchronous burst on first
open) is old, unrelated code that could be paginated/lazily-populated for a smoother one-time
cost, but only costs ~3fps and isn't a Foot IK concern. Rendered-primitive count climbing
continuously and unboundedly for the life of the scene (proven harmless up to the levels
observed here, but not explained) - likely just more of the ~25 simultaneous IK-solving
dummies entering view as the camera moves, never confirmed further since it didn't correlate
with the actual crash.

## Ramp-edge raycast-miss: recovery implemented (option 2, user's choice), partial improvement

Per the user's explicit choice between the two options this task's "raycast-miss" finding left
open (widen the test ramp vs. make the raycast itself more robust near an edge) - chose the
"more complete/smart" option: teach `foot_ik_ground_sampler.gd`'s primary raycast to recover
from a near-miss instead of only widening the test geometry.

**Fix**: in `sample()`, when the primary `raycast_ground(space, foot_pos)` misses and
`likely_idle` is true, try a small number of steps (`0.03/0.06/0.10/0.15m`) back toward the
character's own root before giving up. This is deliberately a *small*, inward-biased search -
not an arbitrary-direction one - so a genuine void/ledge drop is never masked as still-standing
ground; it only recovers the specific case this task already confirmed (idle sway putting a
foot a few cm past a platform's physical edge, where the true surface is a few cm back toward
the body the character is actually standing on).

**Verified, precise before/after** (re-measured directly, not assumed):

| Script | Failures before | Failures after |
| --- | --- | --- |
| `check_foot_ik_ramp_locomotion.sh` | 16 | 13 |
| `check_foot_ik_ramps.sh` | 43 | 40 |
| `check_foot_ik_ramp_sweep.sh` | 22 | 18 |

(`check_foot_ik_ramps.sh`'s count above is its named-case `FOOT_IK_RAMP_CASE FAIL` total - its
own `failed_cases` summary field is sweep-mode-only and misleading outside sweep mode, already
documented in `check_foot_ik.sh`'s status table.)

A real, consistent improvement (3-4 fewer failures per script) - **not a full fix**. Most
remaining failures show deeper, sustained penetration (up to `0.088m`, some with dozens of
penetrating vertices) rather than a brief raycast miss - consistent with this task's own
earlier finding that not every ramp failure is edge-proximity-driven; some are a separate,
larger-magnitude mechanism this fix was never meant to address. Full comprehensive suite
(`scripts/check_foot_ik_all.sh`) re-run clean: exit 0, identical known-baseline failure set
(the three ramp scripts are all still known-failing overall, correctly - only their internal
failure *counts* improved), no new/unexpected regressions.

**Still open**: the remaining ~40/13/18 failures in each script are a different, larger-scale
problem than the near-miss this fix targets - not investigated further this pass. A future
session should check whether these correspond to genuinely steep/complex ramp geometry
(cross-slope stances at 30-45 degrees, several `_cross_`/`_yaw_` case names) where the leg
solver itself needs more slack, rather than another ground-sampling fix.

**Live confirmation: done.** User played the preview scene (ramp cases included) for a long
session (~47 seconds of physics frames). Session log stayed clean throughout: steady 59-60fps
the entire time, no `SCRIPT ERROR`, no `[ANIM_DIFF_INSTANT]` sync failures, no anomalous
`[FOOT_IK_PERF]`/`[FOOT_IK_ENGINE_PERF]` readings - consistent with the fix behaving correctly
during real play near the ramps, with no observable regression on ordinary flat-floor
characters either.

## Real root cause of the remaining ~40/18/13 failures found - first fix attempt disproven

Continued past the raycast-miss fix into the remaining `check_foot_ik_ramps.sh`/
`check_foot_ik_ramp_sweep.sh`/`check_foot_ik_ramp_locomotion.sh` failures. These are not
intermittent misses: `FOOT_IK_RAMP_MATRIX_CHECK`'s worst cases fail on every single one of
their 15 samples, with hundreds of penetrating toe/ball-bone vertices - a persistent, not
occasional, mesh clip. Checked first whether this duplicates 008's already-documented,
four-times-failed right-foot toe clip - it doesn't: that one is stair-riser geometry, a
different mechanism from this ramp-surface one.

**Root cause, confirmed live (not assumed from reading code alone).** Added a temporary print
of `plan.owner_name()`/`plan.surface_normal.dot(Vector3.UP)` inside `_build_plan` and ran the
exact failing case (`foot_ik_ramp_matrix_check.tscn -- case=top_left`): every single sample -
`idle_freeze` and `live_contact` owners alike, across all three ramp angles - showed
`normal_dot` between `0.2588` and `0.9659`, never once reaching `FLAT_SUPPORT_DOT`'s `0.999`
threshold (even the shallowest 15-degree ramp only reaches `0.966`). Every coordinator gate
(`coordinate_idle`/`coordinate_landing`/`coordinate_locomotion`) requires that near-perfectly-
flat threshold before `_finish_validation` ever runs - meaning **the toe/leaf envelope check
that exists specifically to prevent this exact class of clip has never once been reachable
for an idle character standing on any ramp**, regardless of anything else in this task. Not a
regression from today's session; this is how `FLAT_SUPPORT_DOT` has always gated things -
ramps were simply never in the coordinator's scope until this investigation.

Read `_toe_envelope_valid` and `is_target_inside_stance_zone` in full before assuming a fix
was safe: both are already normal-agnostic (`_toe_envelope_valid` orients its check basis
using `plan.surface_normal` directly; the stance-zone check projects onto the character's own
horizontal forward/outward axes, never touching the ground normal at all) - so in principle
only the *gate* condition and `_has_support_at`'s own hardcoded `dot(Vector3.UP)` needed to
loosen for ramps, a small, bounded-looking change.

**First fix attempt, tested, disproven - reverted.** Added `WALKABLE_RAMP_DOT := 0.7071`
(`cos(45deg)`, this project's steepest tested ramp) and used it in `coordinate_idle`'s gate
instead of `FLAT_SUPPORT_DOT`; gave `_has_support_at` an `expected_normal` parameter
(defaulting to `Vector3.UP`, preserving every existing flat-ground caller's behavior
unchanged) and passed `plan.surface_normal` from `_finish_validation`. Verified with a direct
before/after on the exact same filtered case (`case=top_left`, all three ramp angles/all
yaws) rather than assuming from the broader suite: baseline (unpatched) **13** failing
sub-cases; with the fix, **15** - two new failures (`downhill` at one angle, one additional
`uphill_cross` instance) that were not failing before. **This makes things worse, not
better** - reverted immediately (confirmed via `git status`/`git diff`, no residual changes).

**Why, not yet determined.** The gate/normal changes themselves matched the read-first
verification (both downstream checks are genuinely normal-agnostic), so the regression likely
comes from somewhere not yet identified: possibly the raw-recovery fallback
(`_raw_recovery_plan`, which deliberately skips toe validation) now activating on ramps for
the first time and producing a worse pose than the previously-unvalidated original when the
primary plan gets rejected, or a joint-limit/reach interaction specific to a tilted stance
this task hasn't traced yet. Not investigated further this session - this is a confirmed
root cause with a confirmed-bad first fix, not yet a safe path forward.

**Still open**: the actual fix needs to trace *why* enabling validation makes two specific
cases worse before trying a second attempt - likely by comparing the rejected plan's `reason`
field and the resulting rendered pose for exactly the `downhill`/`uphill_cross` cases that
newly failed, the same technique that found every other root cause this session. This is
real, scoped follow-on work, not a dead end - the actual mechanism (`FLAT_SUPPORT_DOT` gating
out all ramp validation) is now understood precisely, which the next attempt can build on
directly instead of re-deriving.

## Second fix attempt: regression traced and fixed, but the toe/leaf gate still doesn't help

Traced the exact cause of the first attempt's two-case regression by printing every plan's
`owner`/`reason`/`stance_valid`/`support_valid`/`toe_valid` for the two failing normal-dot
values live: the newly-rejected plans showed `reason=reject_invalid_stationary_outside_stance`,
`stance=false` - **`is_target_inside_stance_zone`**, not the toe/leaf check, was the actual
culprit. Earlier reasoning that this check was "already normal-agnostic, therefore safe" was
correct about the geometry but incomplete about the *magnitude*: a ramp's own slope genuinely
rests an idle foot further out (in whichever direction the ground drops away) than the
flat-ground-calibrated `STANCE_ZONE_MAX_LONGITUDINAL`/`STANCE_ZONE_MAX_LATERAL` bounds allow -
the same shape of problem `LOCOMOTION_LOCK`/`STAIR_SUPPORT` already needed their own exemption
for, just not yet extended to ramps.

**Fix**: exempted `LIVE_CONTACT`/`IDLE_FREEZE` from `require_stance` specifically when
`plan.surface_normal.dot(Vector3.UP) < FLAT_SUPPORT_DOT` (a genuinely tilted surface) - flat
ground for these two owners keeps the exact same zone check as before. Verified: the two
previously-regressed cases (`downhill` at 15 degrees, one `uphill_cross` instance at 45
degrees) are gone - back to the original baseline's exact 13 failures for the `top_left` case
filter, confirmed via a byte-for-byte diff against the pre-change baseline list, not just a
count match.

**But this now-safe fix doesn't help either.** Full re-measurement: `check_foot_ik_ramps.sh`
unchanged at 43 named-case failures (zero improvement), `check_foot_ik_ramp_locomotion.sh`
unchanged at 13 (zero improvement, same as after the earlier raycast-miss fix alone), and
`check_foot_ik_ramp_sweep.sh` **regressed slightly, 18 -> 19** (one new failing sweep sample) -
confirmed via a direct, isolated before/after with the fix stashed out and reapplied, not
inferred from `check_foot_ik_all.sh`'s pass/fail-only tracking (which cannot see a same-status,
different-count change). Reverted this attempt too - real complexity added to a widely-shared
validation function, for zero measured benefit and one small measured regression.

**The real, valuable conclusion from both attempts**: enabling the toe/leaf/support/stance
validation gate on ramps - correctly, without regressing anything - changes essentially
nothing about the actual failing cases. `_toe_envelope_valid`'s single-tip-point
`space.intersect_point` check evidently isn't what's catching whatever is producing hundreds
of penetrating vertices across the whole foot mesh in these cases (recall: `bones={&"ball_r":
495}` and similar - a bulk mesh clip, not a toe-tip poke). **The `FLAT_SUPPORT_DOT` gate was a
real, confirmed architectural gap, but it is not the cause of these specific test failures.**
This directly confirms the "Still open" note from this task's own earlier section: these
remaining failures likely need the *leg solver itself* to have more slack at extreme
ramp-angle/facing combinations (max hip swing, knee flexion, or shin-swing limits), not a
coordinator-level target validation fix - a materially different, unexplored direction. Not
attempted this session; needs its own investigation into which specific joint-limit constant
is binding for the `top_left`/steep-facing cases before any further fix attempt.

## References

- `tests/manual/foot_ik/foot_ik_ramp_locomotion_check.gd` - the extended check.
- [011](011_foot_ik_flat_idle_pose_divergence.md) - a related pole-vector-adjacent finding
  from the same session, possibly connected (both are rotation/heading-dependent divergences
  in the same closed-form IK solve).
- [013](013_foot_ik_bend_selection_instability.md) - `spin_foot_step`'s root cause
  (`_select_feasible_bend`'s discontinuous bend-plane search), split out into its own task once
  investigation showed it is not ramp-specific and is likely also the cause of a separate,
  pre-existing `FOOT_IK_IDLE_PLANT_STABILITY_CHECK` baseline failure.
