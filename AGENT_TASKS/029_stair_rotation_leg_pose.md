# 029 - Weird leg pose when rotating in place on stairs

Status: reported by the user, NOT yet reproduced/isolated. Related to 019 (idle rotation
toe/riser clip) and the still-open `FOOT_IK_IDLE_PLANT_STABILITY_CHECK` failure.

## Report

"On the stair, I rotate the character a little bit a couple of times, and the legs are positioned
in weird ways... don't open the legs too much, or rotate too much, in a not-so-flexible weird way;
try to remain straight/still, not with unnecessary leg angles that defy the centre of gravity."

So: small in-place yaw bursts while standing on a stair tread splay/cross the legs into
unnecessary angles instead of the feet staying planted and the body staying upright over its
support.

## What already exists

- `foot_ik_idle_plant_stability_check.gd` is the closest acceptance check and is currently RED
  (task 019): its own turn-phase numbers were `turn_penetration_m=0.0987` (limit 0.001) and
  `live_pose_joint_failure=stair_rotation right shin swing 46.4 exceeds 45.0 degrees` on this same
  build - i.e. rotating on stairs already measurably drives an over-swung shin and a toe/leaf
  penetration. See `AGENTS.md` and 019 for the pinned limits.
- `foot_ik_preview.gd:157` `_auto_spin` (`user://foot_ik_spin_marker`) does 70 deg yaw bursts with
  2 s pauses, but at the default spawn - not on the stairs. A stair-rotation repro likely needs a
  small scene that places the player on a tread and applies the same burst, then samples
  `feet.*.leg_angles_deg` / `joints` with the existing trace.

## Next steps

1. Build the stair-rotation repro (reuse the spin burst + `STAIR_WALK_TEST_SPAWN`) and capture a
   trace; inspect `leg_angles_deg` (thigh/shin/knee/foot/leaf) and `knee_pole_alignment` during the
   bursts to see whether the splay is lateral foot offset (stance zone) or the knee pole bending
   outward.
2. Likely owners: idle stance-zone lateral limits (`STANCE_ZONE_MAX_LATERAL`) during yaw,
   `_limit_idle_stance_crossing`, and the knee pole/alignment constraint on rotation. Constrain the
   idle turn to keep the feet inside a tighter lateral envelope and the knee pole facing forward,
   rather than letting the target follow the yaw.
3. This overlaps 019 and 013/023 - fix one measured symptom at a time and re-run
   `scripts/check_foot_ik_fast.sh` (which includes the idle-plant and seam checks).
