# Active Task: Stair Foot IK

**Date:** 2026-08-03

**Checkpoint branch:** `experiment/native-foot-ik`

**Status:** Two threads. (1) The swing foot still bumps stair risers instead of clearing each step
cleanly — still open, next debugging target below. (2) Idle step-down planting for a stationary foot
hovering over a lower surface is implemented (Option A below), passes all automated checks, but is
**not yet manually confirmed and not committed** — see "Resume here".

## Resume here (uncommitted work, mid-verification)

All of the following is uncommitted and represents the current session's work. Do not assume any of
it is finished or committed:

- Idle step-down (Option A) in `player_foot_ik_modifier.gd`: exports `idle_step_down_speed = 0.06`,
  `step_down_max_drop = 0.4`, `step_down_pelvis_drop = 0.35`; `_step_down_eligible()`, the
  `_step_down_static_streak` gate, `debug_step_down`, and `debug_contact_distance`/`debug_contact_hit`
  provenance fields. Gait tracker `update()` and stair predictor `update_swing_lift()` gained a
  `step_down` bool. Debug overlay gained a `StepDown` readout column and a per-physics-frame probe
  JSONL (`_capture_controlled_foot_frame()` → `user://foot_ik_controlled.jsonl`).
- Provenance fix: the overlay's `Foot→Lower` (and the harness CPU-skinning) now read the controlled
  character's own `debug_contact_*` / `_final_bone_poses` snapshot, not the 0.35m walker's state.
  The overlay now follows `../Player` and no longer auto-enables stair-follow. This is what turned
  the body-penetration check from XFAIL into PASS.
- `scripts/check_foot_ik.sh` now requires the penetration check to literally PASS (was XFAIL|XPASS).
- Full state: `git status` shows modifications to AGENTS.md, CURRENT_TASK_IK_FOOT.md,
  actors/player/foot_ik/foot_ik_gait_tracker.gd, actors/player/foot_ik/foot_ik_stair_predictor.gd,
  actors/player/player_foot_ik_modifier.gd, scripts/check_foot_ik.sh,
  tests/manual/foot_ik/foot_ik_debug_overlay.gd, tests/manual/foot_ik/foot_ik_preview.gd.
- **What is left:** the user manually verifies Option A in `foot_ik_preview.tscn` (straddle the bottom
  riser of the 0.35 stair → foot plants with a ~0.33 sink; 0.50/0.65 bottom risers stay floating by
  design), confirms it, then commits. After that, the user wants to try Options B and C below.

## Native IK experiment decision

The current custom implementation is being preserved as the first checkpoint on
`experiment/native-foot-ik`. The next attempt will compare it with Godot 4.6.2's native
`TwoBoneIK3D`, configured with two settings: one target and anatomical knee pole per leg.

- Do not run custom and native solvers on the same bones simultaneously.
- Keep collision, ray/contact sampling, gait classification, stair prediction, support transfer,
  target trajectory, the debug overlay, and the acceptance harness independent of the solver.
- Initially expose an explicit Custom/Native backend switch in the manual harness. Gameplay stays on
  the custom checkpoint until the native path passes basic comparison.
- Use `TwoBoneIK3D`, not `FABRIK3D`: each leg is an analytic hip → knee → ankle chain. FABRIK adds
  iteration without solving the actual lift/cross/land target-timing problem.
- Timebox the comparison to idle, flat walking, the normal-speed 0.35 m stairs, jumping/airborne
  release, and anatomical knee direction.
- Adopt native IK only if it is visibly at least as stable, preserves the animation better, and lets
  us delete meaningful custom bone-solving code. Otherwise retain the checkpoint and continue fixing
  the explicit stair target trajectory.

Native IK is a solver replacement, not a complete stair solution. Regardless of backend, the target
must still lift above the riser, cross its plane, and then descend onto the tread.

Current prototype status:

- `foot_ik_native_backend.gd` configures one native `TwoBoneIK3D` with two settings, separate
  target nodes, and separate anatomical knee poles.
- The Foot IK modifier retains target generation and switches exclusively between the custom and
  native output backends.
- The Foot IK debug panel has a `Solver Backend` dropdown for immediate Custom/Native comparison.
- Interactive launches default the focused 0.35 m stair character to Native TwoBone while leaving
  the general controllable player and other references on Custom. Automated checks stay Custom by
  default; add `--native-foot-ik` to force the native focused run.
- The automated custom and native runs currently produce effectively identical ankle endpoints and
  the same penetration metrics. This confirms the native backend is wired to the shared targets; it
  does **not** demonstrate a visible improvement, so the normal-speed manual comparison is decisive.
- The native prototype has anatomical pole targets, but it does not yet apply the custom solver's
  `max_knee_flexion_degrees` limit. Before adopting it for gameplay, verify knee direction throughout
  idle, walking, stair contact, and landing, then add a native `BoneConstraint3D` if the pole alone is
  insufficient.

## Current user-visible result

- The controllable player and the focused 0.35 m reference character use the same shared stair
  collision and Foot IK implementation.
- The earlier whole-body penetration is no longer visible in manual testing.
- The remaining obvious problem is during the swing phase: a foot travels toward the next tread and
  contacts the vertical step edge before it has lifted above that edge. The gait therefore reads as
  bumping or catching the foot rather than taking a deliberate step.
- Do not mark the task complete until normal-speed manual traversal shows the foot lifting above the
  predicted riser, moving across it, and then descending onto the tread without a knee inversion,
  body stretch, floating plant, or visible collision.

## Architecture to preserve

The former 1,000-line modifier was split by responsibility. Do not collapse these phases back into
one function:

- `actors/player/player_foot_ik_modifier.gd`: orchestration, ground-contact sampling, shared pelvis
  application, and public/debug state.
- `actors/player/foot_ik/foot_ik_gait_tracker.gd`: animated vertical velocity, contact weight,
  falling streak, and landing events.
- `actors/player/foot_ik/foot_ik_stair_predictor.gd`: travel direction, predicted tread, swing lift,
  and single-support-foot ownership/transfer.
- `actors/player/foot_ik/foot_ik_leg_solver.gd`: the final closed-form anatomical leg solve and bone
  angle limits. It must not perform raycasts or choose gait state.
- `actors/player/player.gd`: authoritative `CharacterBody3D` stair ascent/descent and collision-root
  movement. This is shared gameplay code, not test-only behavior.

Godot evaluates `SkeletonModifier3D` after animation and restores the base pose afterward. Continue
applying recurring IK there; direct persistent bone writes from an ordinary node can feed a corrected
pose into the next frame.

## Fixes already retained

- Stair collision probes the horizontal tread beyond the blocking riser instead of treating a
  rounded capsule/riser-corner collision as the tread.
- Upward collision moves the capsule and complete rendered body to the tread immediately. Only the
  third-person camera retains inverse-height easing on ascent; leaving the body below the collision
  root caused the complete mesh to pass through the riser.
- Short descent presentation may ease above the destination tread.
- Forced support is retained only while its rendered sole/toe probe remains within real contact
  distance and its latched target remains anatomically reachable. A stale ray hit alone is not
  support; it previously pulled the pelvis through several steps.
- A fixed anatomical knee pole and flexion limits prevent the procedural solve from bending knees
  through the front of the leg.
- IK releases while airborne so jumps do not remain attracted to stair targets.
- The static split-tread inspection pose freezes only `Player`'s physics callback. Animation and
  `SkeletonModifier3D` processing continue, avoiding capsule depenetration that moves the hips while
  the feet remain planted.
- Stair reference characters run at normal gameplay speed. Slow motion hid timing failures.

## Harness and diagnostics

Persistent scene:

```text
tests/manual/foot_ik/foot_ik_preview.tscn
```

The scene includes multiple stair heights. The 0.35 m character is the focused traversable case and
uses the real `Player` physics callback. The 0.50 m and 0.65 m stairs are pose-limit references only;
gameplay `Player.step_height` remains 0.40 m.

The debug panel provides animation pause/scrubbing, IK tunables, a close foot camera, step/riser
colors, contact rays and impact points, predicted landing markers, foot/bone overlays, and copied
frame data. The focused trace logs animation time, root/tread state, support owner, animated vertical
velocity, contact distance, ground weight, predicted target, and swing lift.

Run both checks after every stair movement or Foot IK change:

```sh
scripts/check_foot_ik.sh
scripts/check.sh
```

Current automated result (as of the uncommitted provenance fix):

```text
FOOT_IK_STRETCH_CHECK PASS samples=138 max_error_m=0.0 limit_m=0.005
FOOT_IK_AIRBORNE_CHECK PASS samples=62
FOOT_IK_BODY_PENETRATION_CHECK PASS samples=138 attempts=138 unavailable=0
missing_mesh=0 penetrating_samples=0 penetrating_vertices=0 max_depth_m=0.0
tolerance_m=0.005
```

The mesh check CPU-skins every current `MeshInstance3D` from mesh weights, live `Skin` bind poses,
and final skeleton transforms. `bake_mesh_from_current_skeleton_pose()` does not work with this
gameplay import. The penetration check used to report XFAIL with 39 penetrating samples (2202
vertices, 0.051 m max depth) purely because the harness was skinning the *pre-IK animated pose*: at
the harness's idle/deferred sample time the skeleton still held the last animation pose, not the
modifier's output. Reading the modifier's post-solve `_final_bone_poses` snapshot instead (the
provenance fix) made it PASS with zero penetrations.

## Next debugging target: clear the riser before advancing

Work on the remaining foot bump as a swing-path problem, not by globally enlarging the ankle offset
or blindly increasing the toe margin. A larger toe margin was tested and worsened the numerical
penetration result.

Recommended next pass:

1. For the swing foot, identify the next vertical riser plane and its top height from the already
   predicted tread.
2. Log the rendered toe/sole's signed horizontal distance to that riser and vertical clearance above
   its top on every normal-speed frame.
3. Divide the predicted step into explicit clearance phases:
   lift above `riser_top + step_clearance_margin`, then allow forward crossing, then release lift and
   descend toward the tread.
4. Do not consider the predicted foot ready to descend merely because its downward ground ray sees
   the higher tread; require the rendered toe/sole to have crossed the riser plane with positive
   clearance first.
5. If the collision root reaches successive treads faster than the animation can produce valid
   alternating contacts, synchronize stair traversal speed/advance with the step phase rather than
   stretching a planted leg or retaining an old support target.
6. Compare the same animation frame with IK enabled and disabled after each change. Idle poses should
   remain equivalent, and the authored swing arc should not collapse.

## Approaches that were insufficient or harmful

- Applying full plant IK on every frame flattened the authored walk swing.
- Height-only gait classification confused a high static correction with an active swing.
- A hard rising/falling velocity sign gate twitched around zero; the current dead zone and continuous
  weighting are intentional.
- Allowing both legs to make independent support decisions produced frames with no reliable support.
- Retaining support from any ray hit, even when the rendered contact was far away, pulled the pelvis
  and body through the staircase.
- Smoothing the complete body below an upward collision snap created guaranteed mesh penetration.
- Manually translating the focused test character through risers created a harness-only penetration
  failure and did not validate the controllable player.
- Increasing `toe_tip_margin` from 0.035 m to 0.09 m worsened the measured maximum penetration and was
  reverted.
- Slow motion made the behavior appear better while the normal-speed timing remained broken.

## Idle step-down envelope (big-drop policy) — three options to try

The idle step-down feature plants a stationary foot that hovers over a lower surface by sinking the
shared pelvis. The standing leg has only ~4cm of reach slack (hip-to-foot ≈ 0.84 of the 0.887 max
reach), so planting a foot one riser below costs the pelvis roughly the full step height minus that
slack. The two exported caps in `player_foot_ik_modifier.gd` define the "step" envelope:

| Step drop | Pelvis must sink | Verdict |
|---|---|---|
| 0.20 | ~0.18 | natural settle (user-approved) |
| 0.35 | ~0.33 | borderline crouch |
| 0.50 | ~0.46 | obvious crouch |
| 0.65 | ~0.61 | basically sitting |

**Option A — envelope + accept float (currently implemented).** `step_down_max_drop = 0.4`,
`step_down_pelvis_drop = 0.35`. Anything within the envelope plants and never floats; drops beyond it
are ledges the standing leg physically cannot reach, so the foot stays at its animated pose (floats)
instead of bending the body into a squat. Gameplay stairs stay ≤ 0.40m and the focused 0.35m harness
case fits with a ~0.33 sink; the 0.50/0.65m pose-limit references are ledges. Note that middle-riser
straddles on tall stairs still plant, because the hip sits high up the staircase and the needed sink
is only ~0.5·step − 0.02; only a low hip straddling the bottom riser needs the full-step sink.

**Option B — envelope + auto settle-step.** Keep the same caps, but when the dangling foot's needed
pelvis drop exceeds `step_down_pelvis_drop`, the idle character eases the whole body down to the lower
surface so both feet plant there (upright, never floats, never crouches). Requires a new eased capsule
descent with collision and input-cancel handling; reuse the stair predictor's step-down support
transfer rather than writing a second descent path.

**Option C — envelope + partial reach.** Keep the sink capped but still ramp the ground weight so the
foot is pulled to its lowest reachable point (max extension) even when it cannot touch, shrinking the
visible gap while leaving it hovering above the lower surface — a half-measure that may still read as
floating.

How to toggle: A only changes the two exports. B and C change `_step_down_eligible()` /
`_apply_support_pelvis_and_legs()`. After any switch, re-run `scripts/check_foot_ik.sh` +
`scripts/check.sh` and manually straddle the bottom riser of the 0.35/0.50/0.65 rows with the
controllable player.

## Manual acceptance checklist

- Walk the controllable player up and down the 0.35 m stairs at normal speed.
- Confirm each swing foot clears the vertical riser before crossing it.
- Inspect front, side, rear, and close foot-camera views.
- Confirm feet land on tread tops without floating or penetrating.
- Confirm the body and pants do not stretch below the steps.
- Jump and land on/near stairs; knees must not invert and airborne IK must release.
- Compare idle and walk poses with IK on/off for unrelated deformation.
- After any automated scene run, leave the Godot scene stopped; the user starts manual tests.
