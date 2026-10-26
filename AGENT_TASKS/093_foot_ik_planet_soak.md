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
