# 093 Foot IK soak on the planet

Request (user, mid-port of 092): once the C++ port is done, test the IK on the planet as many times as possible: load the planet scene, walk for a
while, read the IK logs; when something is off in the logs, find the bug and fix it. Same 4-minute loop. Run windows on screen 1, in the background.

## Plan
- Use the planet lab grounded (`--grounded --walk-check` / `--forest-walk`, FootIKV2Debug logs, scripts/trace_v2.sh) and read the logs.
- Record each finding and fix below.

## Log
- Finding 0: the planet lab did NOT run Foot IK v2 at all (only the flat procedural world installs it); the planet player ran v1. The lab now installs v2 with
  `--foot-ik-v2` and always for the soak. Decision for the user: whether PlanetWorld should install v2 for its player by default.
- Harness: tests/manual/planet/planet_ik_soak.gd (class PlanetIKSoak), driven by the lab: `--ik-soak=SECONDS [--ik-soak-only=PHASE] [--ik-soak-log=PATH] [--seed=N]`, headless
  `godot --headless --path . --fixed-fps 60 res://tests/manual/planet/planet_lab.tscn -- --ik-soak=120`. It walks a script of moves and reads the pose after every skeleton update.
  Events: SNAP (ankle moved more than the body in a frame), CLIP_SNAP (the same for the animation alone: a clip snap, not the IK), IK_POP (the IK-to-animation distance
  changing by 6 cm in a frame), PELVIS_POP, SINK, FLOAT (standing). Summary lines IK_SOAK_COUNTS / IK_SOAK_WORST / IK_SOAK.
- Run 1 (seed default, 120 s, 51 m): no sink (ankles never lower than 9.6 cm over the ground), no pelvis pop (max 5 mm a frame). SNAPs all coincide with CLIP_SNAPs: the animation
  itself jumps 0.23-0.30 m in one frame when the gait clip changes (jog -> walk, strafe start): not the IK. FLOATs: a foot finishing its step for 3 frames after the body stops
  (the clip's own step), not a bug. IK_POP 6-7 cm once per stride while sprint-turning (a stance foot held "stretched" until the leg is at full reach, then released).
- Soak of 6 seeds (150 s each, /e/Temp/ik_many.sh): seed 11 (slopes of 13-25 degrees) had 162 events, 39 IK_POP while jogging, up to 16 cm; the other seeds 40-76 events (the same
  clip snaps and stop-step FLOATs). Cause of the IK_POP (foot frame data: skip=out_of_reach, state released, plant weight ~0.25): when the animation's own leg is straight
  (hip to ankle > reach) place_foot gave the foot up at once, so the correction the foot had until then (6-16 cm at toe-off, more uphill) vanished in one frame.
  FIX (foot_ik_core_native.cpp, place_foot, out_of_reach branch): while moving, the held correction (corr_last) eases out at CORRECTION_STEP (3 cm) a frame, the leg solved
  to animation + eased. Seed 11 jog: IK_POP count 39 -> 3 in 60 s. scripts/check_foot_ik_v2.sh: same numbers as before (known fails unchanged: floor-walk jerk 0.209/0.20,
  ramp strafe, project checks).
