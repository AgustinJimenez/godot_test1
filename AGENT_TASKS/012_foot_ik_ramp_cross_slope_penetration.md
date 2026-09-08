# 012: Foot IK ramp clearance

## Current status

Open. Implementing the user-approved **measurement-only prototype**, not a pose correction.
The new evaluator is test-only and does not change bones, targets, ownership, or movement.
The remaining ramp clipping is not fixed by this work.

Historical experiments and exact prior traces are preserved in
[the archived investigation](archive/012_ramp_cross_slope_investigation_20260908.md).
Do not repeat its rejected gate/limit changes without new evidence. Architecture work remains
linked to [015](015_foot_ik_architecture_direction.md); bend/pose continuity to
[013](013_foot_ik_bend_selection_instability.md).

## Established findings and limits of the evidence

- Prior fixes addressed flat-stance fallback on slopes, correction-rate priority, and inward
  recovery after a near-edge raycast miss. Residual ball/toe mesh penetration remains.
- The last documented ramp baseline was 40 named matrix failures, 18/168 sweep failures,
  and 13 locomotion failures. These are prior measurements, not results from this prototype.
- Merely enabling coordinator validation on ramps did not resolve those failures. Enabling
  shin/knee direction guards likewise did not establish ground clearance.
- The multi-point toe experiment stayed behind a flat-only gate: it did not actually test
  multi-point clearance on ramps.
- Contrary to the archive's final explanation, a failed stance predicate does not short-circuit
  the toe check once `_finish_validation()` runs. It changes rejection/fallback selection.
- Missing clearance guarantees are a design gap, not proof that every residual case has one
  identical cause. Joint-direction checks and foot-surface clearance are different contracts.

## Severity triage and a fixed wall-conform bug (measured, separate from the prototype)

Re-measured the standing baseline by depth rather than failure count, which changes the
picture materially: **most reported ramp "failures" are not visible clipping at all.**

| depth | matrix (40 failures) | sweep (18 failures) |
|---|---|---|
| <=1 micrometre | 33 | 14 |
| 1-3 mm | 1 | 0 |
| 22-88 mm (visible) | 6 | ~4 |

Only ~10 of 58 reported failures are real. This also invalidates the metric every prior
attempt was judged by: a count dominated by 47 micrometre grazes cannot detect a fix that
changes real depth, so "the count did not move" was never evidence of no effect. Judge ramp
work by deep-case depth/vertices, not failure count.

The six real matrix cases were all 15 degrees, `top_*`, facing `uphill`/`uphill_cross`.
Diagnosed with `foot_ik_ramp_sole_alignment_diag.tscn` (measurement only, no bone writes),
comparing the rendered sole normal against the ramp plane per foot:

- `uphill_cross` (88/76/31 mm, worst of all): the sampled support normal was
  `(0, +0.26, +0.97)`, `dot_up = 0.259` - the ramp slab's own **~75-degree end cap**. The foot
  was being conformed to a near-vertical wall as if it were floor, 90 degrees off the real
  surface, driving the foot 6.6-7.2 cm inside the slab. `raycast_ground()` had **no
  walkability filter of any kind**: `intersect_ray` results were accepted whatever the normal.
- `uphill` (22-23 mm): `hit=false`, and the foot bone measured `footprint_z = +2.151` against
  a half-length of `2.000` - **15 cm past the end of the slab, over empty space**. No ground
  exists, IK correctly disengages, and the raw animation pose (flat, ~15/30 degrees off the
  slope) grazes the slab's top corner.

**Fixed** (`foot_ik_ground_sampler.gd`, `foot_ik_runtime_settings.gd`): `raycast_ground()`
takes an opt-in `require_walkable`, and the primary contact sample plus its recovery/toe probes
use it. `FootIKRuntimeSettings.is_walkable_normal()` mirrors the character's own
`floor_max_angle` (tolerance absorbs a normal exactly on the limit, so a 45-degree ramp stays
walkable under a 45-degree limit). An unwalkable hit reports a miss so existing recovery probes
run instead of conforming to a wall. Riser/stair probes deliberately keep the raw call - they
must still see vertical faces. The no-hit normal fallback also now prefers the other foot's
live slope over flat, since this side's stored normal is the stale flat one.

Measured effect: `uphill_cross` fully resolved (both feet `over_slab=true`, sole misalignment
90 -> 0 degrees), worst real depth 87.9 -> 62.6 mm, matrix failures 40 -> 26.
`check_foot_ik_fast.sh` fully PASS, including stair locomotion/settle, ledge safety, edge
landing sweep, idle plant stability and the new clearance geometry fixtures - no behavioral
regression.

**Residual, and why it is not correctable in this fixture:** every remaining deep case measures
`over_slab=false` - the sampled foot is past the end of a *floating* slab. The matrix fixture
builds a bare rotated `CSGBox3D` with no end landings, while real ramps get them from
`FootIKStairSurfaces.build_traversal_slope()`. Those cases therefore ask IK to stand at the lip
of a floating ramp with a foot over the void, which has no correct answer. Their numbers got
worse than baseline (30-degree `uphill` 62 mm, `cross_left` 13 mm) precisely because the
previous, better-looking depth came from accidentally conforming to that wall - right number
for the wrong reason. Fixture end landings were deliberately NOT added: widening/altering the
ramp fixture is the option already rejected in favour of fixing recovery behaviour, so this is
left as a documented fixture limit rather than a silent baseline edit.

**Follow-up fix - `_retract_to_reachable`'s own recovery was itself flat-ground-only**:
traced why several of the residual 15-degree `uphill`/`uphill_cross` cases (23-88 mm) didn't
recover via the idle retraction fallback, even after the walkability fix stopped them
wall-conforming. `_retract_to_reachable`'s candidate search calls `has_support_patch()` to
confirm a landing spot has real ground on all sides - but that check hardcoded
`Vector3.UP`/raw-Y-difference, rejecting *any* candidate on a slope (a 15-degree surface's
`dot_up = 0.966 < STAIR_TREAD_UP_DOT (0.999)`, and points 0.12 m apart on a slope differ in
raw Y by more than the 0.03 m tolerance). Confirmed directly with a temporary debug print
(reverted after use): candidates that passed every other check (reachable, correct stance
lateral/longitudinal) were rejected here on every single attempt, on every ramp, always.

**Fixed**: `has_support_patch()` takes an opt-in `expected_normal` (default `Vector3.UP`,
so the third caller - `straighten_compressed_upper_target`'s intentionally-flat-only check -
is unaffected). `_retract_to_reachable`'s two call sites now pass the normal they already
sampled from their own candidate raycast, checking flatness/height relative to that surface
instead of world-up.

Measured effect (matrix): all six original deep cases *and* the walkability fix's own
30-degree regression are gone - failures 40 -> 20, deep(>3 mm) cases 6 -> 3, worst depth
87.9 -> 13.2 mm, deep-case vertex count 2706 -> 580. `check_foot_ik_fast.sh` fully PASS (19/19
checks), no regression.

Also widened `is_walkable_normal`'s tolerance from a flat `-0.01` dot-product epsilon to a
`+2 degree` angular tolerance (`cos(limit + 2deg)` instead of `cos(limit) - 0.01`) after
finding a ramp built at *exactly* the character's own `floor_max_angle` (both 45 degrees here,
and never configured elsewhere in the project) sits right on the old boundary, where raycast
normal sampling noise could tip either way. A fixed dot-product epsilon shrinks in angular
terms as the limit gets steeper, which is backwards.

**Residual (matrix), confirmed NOT a new regression**: the 3 remaining deep cases (12-13 mm,
30-degree `cross_left`) are the same `over_slab=false` past-the-void limit as above, just
smaller. Separately, `check_foot_ik_ramp_sweep.sh` (a denser, different case grid) surfaced one
case *deeper* than its own original baseline (105 mm at `sweep_bottom_left`, vs 84 mm before) -
traced this directly with a temporary diagnostic replicating its exact spawn parameters
(reverted after use): the failing foot is genuinely `over_slab=true` (unlike the top-edge
cases) yet its primary raycast still misses even with `require_walkable` fully disabled,
proving this specific miss is pre-existing and unrelated to any fix here - a different,
not-yet-investigated raycast-miss-near-a-ramp's-own-bottom-edge category that this session's
fixes changed the pose-feedback dynamics around (which exact case surfaces as "worst") without
being its cause. Left open, not a regression to chase further right now.

## Prototype contract

`tools/foot_ik/foot_clearance_evaluator.gd` takes final world-space foot points and the transform/
size of one known finite box collider. It reports:

- Availability/reason (empty, invalid, or unsupported input is not reported as clear).
- Top-surface signed clearance along the transformed surface normal, limited to the finite
  footprint; points underneath a separate slab are not treated as top-surface penetration.
- Embedded point count, nearest-boundary penetration depth, worst point, and normal.
- A deepest-point exit vector, explicitly NOT a reachable whole-foot correction.
- Per-point depths and numerical-boundary flags for independent comparison.

Scope is orthogonal boxes with scale, including rotated ramp slabs; shear is rejected.
This is not an arbitrary-mesh collision implementation or a guarantee between sampled vertices.
The reference adapter skins every foot-influenced vertex (including heel, ball, width and leaf)
using final post-modifier poses. It reuses the existing oracle's skinning helpers, but the
evaluator's box-distance calculation is separate. Full-mesh capture is intentionally a
diagnostic reference, not an approved runtime cost.

`tools/foot_ik/foot_clearance_skin_samples.gd` now bakes the selected vertices and their
nonzero influences once. It evaluates explicit world-space skin matrices without consulting
nodes, advancing history, or changing a pose. This is a sparse, exact representation, **not a
reduced-point envelope**: all 896 reference points remain. The test adapter explicitly rebuilds
per actor; changing mesh geometry, skin bindings, or the selection requires another rebuild.
Automatic runtime invalidation and arbitrary collider support are not implemented.

The legacy oracle applies its tolerance to the top face only, counting arbitrarily shallow
side/end penetration. The evaluator preserves that convention for comparison and explicitly
reports a 2-micrometre boundary uncertainty. Any differing vertex classification must be at
such a boundary; depth error and material-penetration detection are checked separately.

## Acceptance and commands

- `foot_ik_clearance_geometry_check.tscn`: analytic depths on flat/15/30/45-degree surfaces
  at multiple world yaws, finite side/end entry, outside/under/above cases, scaled geometry,
  embedded ball with clear tips, empty input, and unsupported shear.
- `foot_ik_clearance_replay_check.tscn`: inherits the original ramp matrix's settle/idle
  history; by default samples middle-center and top-left across all ramp angles/headings.
  Compares the existing full-mesh oracle and the evaluator, including point-by-point checks.
  Requires both clipped and clear samples and checks that evaluation does not mutate the
  final bone cache or player transform. PASS means measurement agreement, NOT a clean pose.
- `scripts/check_foot_ik_clearance.sh`: runs both; accepts e.g. `case=top_left`.
  Geometry checks are registered in fast/main suites; the complete measurement check in
  `check_foot_ik_all.sh`. No baseline exemptions were added.

Verified 2026-09-08:

- `scripts/check_foot_ik_clearance.sh`: PASS; analytic fixtures plus 810 replay samples
  (54 cases), 123 oracle-flagged/687 clear. Zero material mismatches, maximum depth error
  0.00000024 m. All 52 differing point-count samples were verified point-by-point to differ
  only at numerical boundaries. Worst penetration 0.091048 m, dominant bone `ball_l`.
- Capture: 896 foot-influenced vertices, averaging 5651 us for mesh capture/skinning and
  271 us for evaluation on this run. These are diagnostic costs, not a production budget;
  require a cheaper cached/envelope representation before runtime integration.
- `scripts/check.sh`: PASS (lint/import/parse); `scripts/check_foot_ik_fast.sh`: PASS, 132 s.
  Final changed-script lint and shell syntax checks also pass.
- Exhaustive behavioral suite not rerun: no production modifier, solver, sampler or pose
  behavior changed. The measurement replay includes existing bad poses intentionally, and
  its PASS must not be reported as fixing the ramp baseline.
- Logs: `/tmp/foot_ik_012_clearance_replay_final.log`,
  `/tmp/foot_ik_012_clearance_project.log`, `/tmp/foot_ik_012_clearance_fast.log`.
  No preview was auto-played for the user; verification processes finished. No commit made.

Continuation, cached representation:

- `/tmp/foot_ik_012_cached_replay.log`: PASS across the same 810 samples; cached versus original
  positions and region labels match exactly (maximum point error 0). Oracle comparisons remain
  unchanged: 123 flagged/687 clear, zero mismatches, 0.00000024 m maximum depth error.
- On that run, original capture averaged 5940.5 us, cached capture 225.5 us (about 26x faster),
  evaluator 279.5 us, one-time build 5329 us. These are measured diagnostic timings, not a
  frame-time guarantee. No reduced sampling or missed-penetration allowance was introduced.
- Analytic cache fixtures cover four/eight influences, rotation/scale, invalid binds,
  renormalization, zero-weight fallback, immutable baked inputs, repeated refresh, changed
  pose input, and atomic rejection of invalid selection.
- Project check PASS (`/tmp/foot_ik_012_cached_project.log`); fast suite PASS in 136 s,
  including the new cache fixtures (`/tmp/foot_ik_012_cached_fast.log`). Changed-script lint
  and whitespace checks pass. Exhaustive behavioral suite remains deferred until runtime
  behavior changes. No preview launched or commit made.

## Next design boundary (not implemented)

1. Cached exact skinning is validated; choose a production sample/query budget and explicit
   mesh/skin invalidation lifecycle. Only reduce geometry if reference comparison proves it safe.
2. Extend surface observations beyond known boxes; retain collider identity and finite support
   so ramp edges and neighboring/overhead platforms cannot invent ground.
3. Feed clearance constraints into the authoritative feet/pelvis plan, with bounded candidate
   correction and explicit unreachable/degraded outcomes. Do not add another late bone writer.
4. Re-evaluate the final weighted/rate-limited pose. Test continuous rotation, support changes,
   slope/flat transitions, and zero-delta refreshes before enabling correction live.
5. Run the complete suite and require user live confirmation for that behavior-changing stage.

Immediate integration prerequisite: `foot_ik_leg_solver.gd::_solve_impl()` writes hip/knee/foot
and `_solve_toes()` writes the remaining chain, while `_limit_correction()` commits history
and returns the previous correction on a repeated physics frame. Do NOT evaluate candidates by
calling `solve()` repeatedly or by lifting rendered bones afterward. Extract a candidate-pose
result with tentative history, evaluate its skinned clearance, then apply/commit only the chosen
result once. Preserve solve/release pelvis frames and zero-delta refresh behavior in that seam.
The cached skin sample evaluator is ready to consume explicit candidate skin matrices, but this
solve/apply separation and bounded correction are not implemented yet.
