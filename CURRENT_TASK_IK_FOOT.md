# Active Task: Stair Foot IK

**Date:** 2026-08-03

**Checkpoint branch:** `experiment/native-foot-ik`

**Status:** Experimental and behaviorally incomplete. The refactor and the shared gameplay
integration are in place. Latest manual testing reports no visible body/stair clipping, but the feet
still bump into stair risers instead of clearing each step cleanly.

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

Current automated result:

```text
FOOT_IK_STRETCH_CHECK PASS samples=138 max_error_m=0.0 limit_m=0.005
FOOT_IK_AIRBORNE_CHECK PASS samples=62
FOOT_IK_BODY_PENETRATION_CHECK XFAIL samples=138 attempts=138 unavailable=0
missing_mesh=0 penetrating_samples=39 penetrating_vertices=2202
max_depth_m=0.051448 tolerance_m=0.005
```

The mesh check CPU-skins every current `MeshInstance3D` from mesh weights, live `Skin` bind poses,
and final skeleton transforms. `bake_mesh_from_current_skeleton_pose()` does not work with this
gameplay import. Before the latest fixes it measured 195,786 penetrating vertices and 0.582 m maximum
depth. The latest manual test reports no visible clipping, while the numerical check still finds
mostly `ball_l`/`foot_l` toe-edge intersections. Keep that mismatch visible: determine whether these
are visible riser bumps, expected boundary contact, or a tolerance/contact-model issue before turning
XFAIL into PASS.

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

## Manual acceptance checklist

- Walk the controllable player up and down the 0.35 m stairs at normal speed.
- Confirm each swing foot clears the vertical riser before crossing it.
- Inspect front, side, rear, and close foot-camera views.
- Confirm feet land on tread tops without floating or penetrating.
- Confirm the body and pants do not stretch below the steps.
- Jump and land on/near stairs; knees must not invert and airborne IK must release.
- Compare idle and walk poses with IK on/off for unrelated deformation.
- After any automated scene run, leave the Godot scene stopped; the user starts manual tests.
