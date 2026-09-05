# 012: Foot IK ramp cross-slope/diagonal penetration

## Status and scope

New, found while extending test coverage - not yet investigated for root cause. Test coverage
change is implemented and uncommitted (`tests/manual/foot_ik/foot_ik_ramp_locomotion_check.gd`);
the bug it found is not fixed.

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
