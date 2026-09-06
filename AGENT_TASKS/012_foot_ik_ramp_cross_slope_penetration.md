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

**Still open**: `spin_foot_step` (likely a rate-of-rotation or pole-vector issue, unrelated to
the stance-crossing mechanism just fixed - needs its own root-cause pass), the `phase=move`
diagonal-walk failures (separate, smaller-magnitude, not yet investigated), and wiring
`foot_ik_ramp_locomotion_check.tscn` into a committed check script so this coverage isn't only
run manually.

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
