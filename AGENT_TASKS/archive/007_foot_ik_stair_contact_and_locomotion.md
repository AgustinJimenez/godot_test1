# 007: Foot IK stair contact and locomotion

## Status

Completed/parked foundation. Current platform-edge and split-height work continues in
[`008_foot_ik_platform_edge_safety.md`](008_foot_ik_platform_edge_safety.md). Git history contains the
former chronological 1,700-line investigation; this file keeps only durable architecture and
acceptance rules.

## Architecture

- `PlayerFootIKModifier` coordinates contact policy, gait state, shared pelvis, and final application.
- `FootIKGroundSampler` owns rays, rendered sole/toe probes, and target/normal smoothing.
- `FootIKGaitTracker` owns animated vertical velocity, weights, phase edges, and target locks.
- `FootIKStairPredictor` owns tread prediction, swing clearance, and support-foot transfer.
- `FootIKLegSolver` receives target + weight and writes the closed-form hip/knee/foot/toe chain. It
  must not raycast or choose support.
- `PlayerStairController` owns physical capsule traversal. Collision/root motion and rendered
  presentation are separate, but presentation must never leave the whole body inside a riser.

## Durable behavior

- Preserve authored flat-ground locomotion. Blend IK from animated vertical foot motion; full plant
  every frame destroys swing lift.
- `SkeletonModifier3D` can run multiple times per tick, including zero-delta refreshes. Advance
  histories only on positive delta, but still solve/reapply output on refresh calls.
- Use exact rest-pose foot axes and an explicit down + forward basis. Cardinal-axis quantization and a
  shortest-arc quaternion leave unstable twist.
- Use the animated knee bend plane for the pole. A fixed forward pole twists strafes and crouches.
- Keep joint positions and rotations on the same weighted chain. Mixing full-solve positions with
  partially blended rotations stretches the rendered skin despite correct bone lengths.
- Use signed clearance. A surface above a foot is penetration, not lost contact.
- Preserve source gait phase across compatible loop transitions; controller locomotion clips must be
  in-place. Do not phase-match unrelated animation packs.

## Stairs, ramps, and ledges

- Flat stair treads may retain a world-space support target; continuous ramps must follow current
  contact. Surface normal is a more reliable structural discriminator than a transient gait flag.
- Predict one tread per swing and nudge predicted landing points before contact. Reacting only after a
  bad plant creates a harder reach/ownership problem.
- A shared pelvis drop affects both legs. Swing clearance and preserved support must compensate for
  ancestor motion; a pass-through child is not preserved when its pelvis moves.
- Toe/sole footprint probes are required near risers and platform ends. An ankle ray alone can approve
  a toe inside a vertical wall or hanging over the void.
- Seamless traversal proxies exclusively own their collision frames. Discrete riser stepping and its
  balance/hover offsets must be bypassed and cleared.
- Preserve horizontal root travel while smoothing vertical traversal; gating XZ on partial-height
  collision causes a visible stop/catch-up stutter.
- Unreachable unsupported feet return to animation with zero IK. A shortened or full-reach invented
  target still reads as an invisible floor.

## Stateful ownership rules

- Idle freeze, lower-support latch, stair support, landing support, and locomotion stance locks can
  override one another. Every owner must define acquisition, validation, and release explicitly.
- Retained targets must stay supported, reachable, on the intended surface, and inside the rotated
  colored stance zone. Revalidate them after body yaw changes.
- A foot reported as released must not retain the side-key yaw/plant latch. Target-lock code must
  agree with the public frozen state.
- Marginal animation noise should decay streak counters instead of resetting them; real swing reversal
  still resets immediately.
- Landing claims are provisional when repeated direct contact proves a different surface. Preserve a
  newly proven surface through short animation probe misses, but do not let stale lower ownership pull
  a leg down after landing.

## Diagnostics and regressions

Read the modifier's `_final_bone_poses` or trace final-pose fields; deferred
`Skeleton3D.get_bone_global_pose()` can show the restored animation pose. Compare quaternions rather
than Euler angles.

Preserve `user://foot_ik_controlled.jsonl` before starting a harness. Analyze the complete relevant
range, not only the final 40 frames. Compare raw target, smoothed target, solved target, contact,
weight, ownership flags, and final joint/mesh geometry. A clean final frame can hide a transient
center-line crossing, target reversal, clip, or snap.

Every escaped live defect becomes the smallest persistent regression that captures its real symptom.
Include intermediate frames, final CPU-skinned geometry where needed, both feet independently, and
performance for support searches. Headless success never replaces live user confirmation.

Run the complete battery independently:

```sh
scripts/check.sh
scripts/check_foot_ik.sh
scripts/check_foot_ik_locomotion.sh
scripts/check_foot_ik_ramps.sh
scripts/check_foot_ik_ramp_sweep.sh
```

Redirect noisy output and report every PASS/FAIL. Do not run Godot harnesses concurrently because
they can share import state, marker files, and rolling traces.
