# 019: Toe/leaf clips through a stair riser during idle rotation

## Status and scope

**Open, unfixed.** A real, reproducible bug with working regression coverage that now correctly
fails, documenting the gap rather than hiding it. Three fix attempts tried, none resolved it;
the second was reverted after it introduced a separate regression, the third was reverted
clean (no regression, but no fix either). Live-reported by the user while testing unrelated
017/018 follow-up work (the balance counter-lean modifier): rotating in place on a split stair
stance visibly slides a foot with a clip through the step's edge.

## The concrete symptom

Standing on a stair split stance (two feet on treads at different heights) and rotating in
place: a foot's toe/leaf swings into the riser of a nearby tread as the body's yaw changes,
penetrating up to ~11cm deep, building up gradually over many consecutive frames rather than a
one-frame snap. This is distinct from - and NOT fixed by - the ankle-target repositioning slide
that prompted this investigation (see "What was actually fixed" below).

## Root cause, confirmed by direct investigation (not guessed)

1. The clipping foot's target during the clip is NOT owned by the idle-lower-latch/acquire
   system this session initially suspected - it is owned by `LANDING_UPPER`
   (`straighten_compressed_upper_target` in `foot_ik_ground_sampler.gd`), a separate mechanism.
2. `foot_ik_target_coordinator.gd` already has a toe/leaf envelope safety check
   (`_toe_envelope_valid`, from [archived task 008](archive/008_foot_ik_platform_edge_safety.md))
   that exists specifically for "a valid ankle
   latch with the toe poking into the next riser" - exactly this symptom. But it never runs for
   this owner during this scenario: `legacy_transition_active` (true whenever *either* foot is
   mid lower-tread transition) disables coordinator validation for every owner except the three
   lower-transition owners themselves (`IDLE_LOWER_LATCH`, `IDLE_LOWER_ACQUIRE`,
   `IDLE_STANCE_REHOME`) - `LANDING_UPPER` is not among them, even though it is an already-settled,
   non-transitioning foot on the *other* leg.
3. Confirmed via a temporary debug print reading `_target_coordinator.get_plan(side)` at the
   exact failing frame: `owner=LANDING_UPPER`, `toe_status=NOT_CHECKED`, `reason=
   selected_legacy_candidate` (the untouched pass-through default) - proving `_finish_validation`
   never ran for this leg at all during the clip.

## Fix attempts tried this session

### Attempt 1: collision-aware hold for ankle repositioning (kept, real fix, different bug)

Replaced the idle-reposition straight-line `move_toward` (which only checked its two endpoints
against geometry, never the path) with `_move_toward_held` in `foot_ik_ground_sampler.gd` -
raycasts the intended path each frame and holds at any blocking geometry instead of pushing
through. Verified clean against the full suite. This is real, working, and stays - but it does
not touch the toe/leaf-clip symptom above, since that clip is orientation-driven (the toe swings
as the body rotates), not caused by the ankle target's own repositioning path.

### Attempt 2: extend toe-envelope validation to LANDING_UPPER (reverted)

Added `FootIKTargetPlan.Owner.LANDING_UPPER` to the `owner_is_lower_transition` exemption list in
`foot_ik_target_coordinator.gd`, so it stays validated even while the other foot transitions, and
added `_retreat_for_toe_clearance()` - a small search that shrinks the ankle target toward the
hip in 2cm steps (up to 12cm) until the toe/leaf envelope check passes, re-validating stance/
support/reach at each candidate.

**Result: did not fix the clip** (penetration stayed ~0.11m, same order of magnitude) and
**introduced a new regression**: `foot_ik_idle_plant_stability_check`'s own separate live-pose
sub-check went from `live_pose_joint_step_m=0.043` (pass) to `0.062` (fail against its
`MAX_LIVE_POSE_JOINT_STEP=0.045` budget) - some other owner's target computation also runs
through this same gate and got disturbed by the widened exemption. Full-suite confirmed the wider
blast radius: `Passed: 39` (down from the established 41), and one *other* previously-passing
check also newly failed while coincidentally matching an already-`KNOWN_BASELINE_FAILURES`
label - which would have silently masked that second regression had the harness not been checked
carefully (018's own finding I, playing out live). **Reverted.**

Why the retreat likely wasn't enough: the clip's own depth (~11cm and still growing across the
sampled window) may already exceed what a 12cm hip-ward retreat budget can clear without also
failing reach/stance, especially since retreat only pulls the ankle *toward the hip*, not away
from the specific wall direction - the toe offset is a rotated rigid vector from the ankle, not
something a same-side retreat necessarily un-rotates away from the obstruction.

### Attempt 3: hold the foot's world orientation during legacy_transition_active (reverted clean)

Hypothesis going in: the toe sweeps because `FootIKLegSolveInput.capture()`'s `ground_foot_basis`
on flat ground is computed fresh every frame as `to_world.basis * foot_pose.basis` - i.e. the
foot's orientation is 100% re-derived from the body's *current* world yaw, with no independent
limiting, unlike hip/knee which go through `_limit_correction`'s per-frame degree budget.

Implementation (2026-09-12, session continuing 018): added `foot_yaw_hold_basis(side,
fresh_basis)` to `foot_ik_leg_solver.gd` - a per-side cached `Basis`, gated on exactly
`plan.owner == LANDING_UPPER and legacy_transition_active` (recomputed from
`idle_lower_acquiring`/`idle_lower_latched_target`, same formula as the coordinator's own
`legacy_transition_active`), with the same "reset only on an actual gap in consecutive calls"
pattern as `_idle_slope_targets`. Wired into `FootIKLegSolveInput.capture()`'s `ground_foot_basis`
assignment. Deliberately did NOT touch `_compute_new_foot_basis_world` itself (5 call sites,
too wide a blast radius after attempt 2's lesson) or `_limit_correction`'s unconditional
foot-joint bypass (line ~615, `if joint == &"foot" and not is_crouch_animation: ... return
desired` - deliberately unthrottled elsewhere, real risk to touch broadly).

**Result: no regression, but no fix either** (`turn_penetration_m` 0.102786 -> 0.102649,
noise-level). Confirmed via targeted debug instrumentation (frame/skeleton-id-matched, since
the shared preview scene runs several unrelated characters whose diagnostic prints interleave
with the real test player's) that the hold mechanism correctly engaged every frame, for the
right leg, exactly matching `owner=landing_upper` at the measured `turn_penetration_frame`.

**Why it didn't work - the actual finding:** `LIVE_TURN_YAWS_DEG` has only 20 entries;
`_process_turn_check()` stops updating `_player.rotation.y` once `turn_index` exceeds that
(`if turn_index < LIVE_TURN_YAWS_DEG.size(): ...`). `turn_penetration_frame=34` is well past
that boundary - **the body is not actively rotating anymore at the moment deepest penetration
is measured.** A fix that only stops the foot's orientation from tracking *live* body yaw has
nothing to counteract there, which is why it had zero effect. This invalidates the working
assumption behind all three attempts so far (continuous yaw-coupling during rotation) and
points at a genuinely different mechanism instead: `_limit_correction` explicitly and
unconditionally exempts the foot joint from all rate-limiting (returns `desired` immediately,
non-crouch animations), while hip and knee go through a real per-frame degree budget
(`joint_correction_speed_degrees` et al.) and visibly lag behind after a big discrete yaw step.
The toe's swept position during that hip/knee catch-up window - while the foot's own rotation
has already snapped ahead - is the new, unconfirmed suspect. Reverted cleanly (no other files
touched, no regression).

## Regression coverage added (kept, working)

Extended `foot_ik_idle_plant_stability_check.gd`'s existing repeated-rotation sweep
(`LIVE_TURN_POSITION`/`LIVE_TURN_YAWS_DEG`, already on a real "Stairs 0.35m" fixture) to sample
real box-collider penetration every frame at the ankle and toe, using
`FootClearanceEvaluator.evaluate_box()` against whatever tread/riser box collider(s) are actually
near each sample point (found generically via a small-sphere `intersect_shape` query, not
hardcoded tread coordinates - see the `_sample_turn_penetration`/`_find` pattern in that file).
Reports `turn_penetration_m`/`turn_penetration_side`/`turn_penetration_frame` and gates on
`MAX_TURN_PENETRATION_M := 0.001`. This is the first check in the suite that samples *during* a
transition rather than only the settled end state, and it is currently, correctly, red.

## 2026-09-14 continuation: live idle STEP-DOWN clip (no rotation), same family

User live report after the 025 walking fix: "left foot is clipping". Preserved trace
`/tmp/foot_ik_controlled_live_20260914_112634.jsonl` (776 frames, mostly `moves/unarmed_idle`).
Checked against the **real** preview box colliders (same oracle as the live `[FOOT_IK_CLIP]`
monitor, not the simplified `trace_query.py toe-riser` preset): **left foot 0.2948 m at frame 607**,
428 frames > 5 mm; right 0.2009 m.

- **Pre-existing, not from the 025 walking fix.** A trace preserved *before* that fix
  (`/tmp/foot_ik_controlled_session_20260914_000613.jsonl`) shows the same class on real colliders:
  left 0.2087 m, right 0.1826 m.
- **Not rotation** (unlike this task's original case): frame 607 is idle, `movement_input=0`,
  constant `root_yaw`. Owner `idle_lower_latched`, `step_down=true`, `solver_action=
  constrain_knee_direction`.
- The target is **reachable and was validated**: hip (14.61,1.63,1.34) -> solve_target
  (14.87,1.146,1.62), distance 0.62 < leg reach 0.887, `plan_solve_validated=true`, `ground_weight`
  and `raw_weight` both 1.0. Yet the rendered ankle (`foot_pos` == `solved_foot_pos` ==
  `joints.foot.position`) sits at 0.842 - **0.30 m below its own target**.

### Deterministic headless repro (throwaway, recipe)

Instance `foot_ik_preview.tscn`, walk the real Player up the 0.35m stairs to `root.z >= 1.35`, then
idle, sampling `FootIKLivePenetrationMonitor.check` on both feet every physics frame:

```
godot --headless --fixed-fps 60 --path . res://tests/manual/foot_ik/_idle_step_repro.tscn --quit-after 800
# -> IDLE_STEP_REPRO max=0.183097 frame=119 side=left (deterministic; 0.182462 at frame 120 with
#    the 025 fix stashed, i.e. unchanged by it)
```

At repro f119 the player's left foot has `plan_final_adjustment=accepted_adjustment`,
`plan_solve_validated=false`, target (15.276,1.496,1.937), rendered ankle ~(15.276,1.302,1.81) -
~0.19 m low with `ground_weight=1.0`, `diff_pos_m=0`.

### Causes ruled out by direct experiment (do not re-try blind)

- The 025 toe-clearance retry: A/B unchanged.
- `_limit_idle_stance_crossing`: forcing `target_plan_validated=true` in `evaluate_pose` (limiter
  disabled) left the penetration identical (0.183097).
- Gating that limiter by `absf(target.y - foot_pos.y)`: no effect (animated foot height is near the
  target here).
- Reach (0.62 vs 0.887 m) and hip-swing clamp (`max_hip_swing_degrees=100`, measured thigh 42).
- Teleport / scene contamination (single idle, fresh run).

### Remaining suspect (confirmed by runtime instrumentation of the repro)

Temporary `DBG_EVAL` print in `evaluate_pose` (after the limiters, with `to_world.origin` to
separate the repro player from the preview's other characters) at the failing frames:

```
f=45 x=15.00 z=0.62 err=0.134 tgt=(15.114,0.856,0.557) anim_foot_y=0.936 new_foot_y=0.732
  hip_y=1.617 dist=0.764 reach=0.764 max=0.888 swing_clamped=false
f=58 x=15.00 z=1.14 err=0.153 tgt=(15.113,1.157,1.006) anim_foot_y=1.196 new_foot_y=1.026
  hip_y=1.898 dist=0.755 reach=0.755 max=0.888 swing_clamped=false
f=75 x=15.05 z=1.80 err=0.203 tgt=(14.949,1.265,1.935) anim_foot_y=1.307 new_foot_y=1.125
  hip_y=1.994 dist=0.743 reach=0.743 max=0.888 swing_clamped=false
```

Key readings: `dist == reach` (the target distance is used as-is, **not clamped by reach**
`max=0.888`), `ground_weight = chain_weight = rotation_weight = 1`, `swing_clamped=false`, yet
`new_foot_pos.y` lands 0.12-0.20 m **below** `target.y` (and even below `anim_foot_y` at f45). So
the shortfall is **not reach, weight, or the hip-swing clamp** - it is inside the solver's
orientation/limit chain that turns the two-bone result into the rendered pose:
`_limit_rendered_upright_shin` (`knee_delta = _limit_rendered_upright_shin(...)`, evaluator
~line 119), `_limit_negative_rendered_knee`, or the `rotation_weight` slerp. At f=38 the target is
genuinely over-reach (`reach=1.006 > max=0.888`, `dist` clamped to 0.887), which is a separate,
correct fall-short case.

### Root cause NOT the rate limiter speed (hypothesis refuted; earlier instrumentation suspect)

An instrumentation pass staged `new_foot_pos.y` (`ideal` = two-bone result, `rl` = after
`_limit_correction`, `recompute` = line-128 value, then stance/knee limiters) and separately logged
`_limit_correction`'s angle/budget. It appeared to show the whole drop in `_limit_correction`
(`ideal == target`, budget 1.5 deg/frame at `standing_joint_speed_degrees=90`, correction
perpetually 6-9 deg behind).

**That conclusion did not survive its own test.** Raising the idle flat-surface joint speed:

| idle flat-surface speed | repro max depth | `FOOT_IK_TOE_RISER_CHECK` step |
| --- | --- | --- |
| 90 (current) | 0.183 | PASS (0.0265) |
| 260 | 0.179 | PASS (0.0318) |
| 480 | **0.196 (worse)** | **FAIL (0.0357 > 0.035)** |

A higher speed did **not** reduce the repro clip and regressed the toe-riser step. So the clip is
not a simple rate-limiter speed limit.

**Instrumentation caveat:** the preview scene runs several stair walkers that spawn at essentially
the same `x` as the repro player (both `x ~15.0`), and the `to_world.origin.x in (14.8, 15.3)`
filter did not separate them - the frames analyzed may have been a walker, not the repro player.
Any future instrumentation here must key on skeleton/instance identity (AGENTS.md's warning about
the multi-character preview), not root position.

Blanket `instant_correction` for grounded flat feet also reduced the repro to 0.082 but regressed
`FOOT_IK_TOE_RISER_CHECK` step to 0.039 - same blocker, so both the speed bump and the blanket
instant variants are refuted. Do not re-try either.

Next concrete step: redo the staged instrumentation keyed on the repro player's actual skeleton/
instance id, at the exact frame where the harness reports its max depth (not a hand-picked frame),
to find which stage drops the foot for *that* character.

## What to try next (not attempted, needs a fresh investigation)

- **Most promising, from attempt 3's finding:** trace the hip/knee-vs-foot rate-limiting
  asymmetry directly. Confirm (not assume) that the toe's penetration actually correlates with
  the hip/knee still converging via `_limit_correction`'s degree budget after the last big yaw
  step, by sampling `state.debug_swing_degrees`/the hip-knee correction angle alongside
  `turn_penetration_m` per frame. If confirmed, the fix is likely either (a) applying the same
  per-frame degree budget to the foot joint during this specific gap instead of its blanket
  exemption, or (b) holding the toe/leaf's *position relative to the ankle* (not the foot's
  world orientation) until hip/knee finish converging - attempt 3's orientation-hold was too
  indirect a lever for a lag that isn't about live body-yaw tracking at all.
- A retreat direction informed by the actual penetration exit vector (`FootClearanceEvaluator`'s
  `Result.deepest_point_exit`), not a fixed hip-ward direction - retreat *away from the wall*,
  not just *toward the hip*.
- Investigating what *other* owner's target computation shares the gate widened in attempt 2, to
  understand the live-pose-joint-step side effect before trying a similar widening again.
- Confirming whether this reproduces for owners other than `LANDING_UPPER` too (the two other
  non-exempted "coordinate_idle" owners - `LIVE_CONTACT`, `IDLE_FREEZE` - could have the same gap).

## References

- `foot_ik_target_coordinator.gd::_toe_envelope_valid`/`_toe_envelope_valid_at` -
  the existing, correctly-scoped check this bug slips past.
- `foot_ik_target_coordinator.gd::owner_is_lower_transition` - the exemption list; `LANDING_UPPER`
  was added then reverted here.
- `foot_ik_ground_sampler.gd::straighten_compressed_upper_target` - owns the clipping foot's
  target during this exact scenario.
- `tests/manual/foot_ik/foot_ik_idle_plant_stability_check.gd::_sample_turn_penetration` - the new
  regression coverage.
- [Archived task 008](archive/008_foot_ik_platform_edge_safety.md) - the original toe-envelope
  check this gap was found in.
- `AGENTS.md`'s Foot IK section - durable lessons from this investigation are recorded there
  (the `legacy_transition_active` gap, the `FootClearanceEvaluator` per-frame pattern, and the
  "confirm which owner governs the target before assuming which validation path is responsible"
  lesson).
