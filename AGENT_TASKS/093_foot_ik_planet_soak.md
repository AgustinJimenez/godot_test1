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
- Second batch (seeds 11 77 88 99 111 122): seeds 111 and 122 have no IK_POP at all; seeds 77/88/99 have 5-20 IK_POPs in jog/sprint_turn (6-10 cm), seed 11 (a 20-25 degree slope, the player
  jogging uphill the whole time) 160 events. A frame-by-frame look (the soak prints 9 frames before and 2 after an event, with each foot's shift, plant weight, state and skip reason):
  the remaining pops are NOT a release: the foot is "stretched"/"at_target" with the plant weight fading 0.13 a frame (PLANT_RATE / 60) while the animated ankle runs 0.5-0.7 m above the
  ground target at toe-off, so the IK-to-animation distance shrinks by rate x distance = 6-10 cm in one frame, mostly along the ground normal (ease_correction lets the "away"
  part through on purpose). It is the foot catching up with the animation at toe-off, bounded by 10 cm in a frame at 5.8 m/s; not a bug in the sense of a wrong pose, a tuning
  trade-off (a slower PLANT_RATE would lengthen the lag of the planted foot behind the animation). Left as is; decision for the user.
- Extra fix kept: ease_release() (foot_ik_core_native.cpp) also eases a `mid_swing` release; the v2 suite numbers are unchanged.
- Not the IK, for the animation owner: the gait clips snap an ankle 0.23-0.5 m in one frame at some clip changes (stop_go: run -> walk at 5.3 m/s, walk_turn_right after a jog, strafe start). CLIP_SNAP
  in the soak counts them; the animation tree changes clip without a blend there.
- Third fix (strafe_right / stop_go pops, 8-10 cm on a 20-24 degree slope; the soak now also prints each frame's animated ankle, reach check and residual): resample_and_correct()
  re-solved the foot from the LANDED foot toward the re-sampled ground, so the plant fade was applied a second time, and only on the frames the ground under the foot had moved
  5 mm or more. A toeing-off foot was pulled 6 cm below its blend for three frames, then the check fell under 5 mm and it let go in one frame (y 0.03 -> 0.16 m).
  FIX: blend from the animated ankle, as place_foot does. Seed 11 (150 s): IK_POP 118 -> ~60 (strafe_left 15 -> 3, strafe_right 7 -> 1, walk_turn_left 11 -> 2, crouch_walk 7 -> 1);
  seeds 77/88 no worse (88: stop_go/walk/back pops gone). The jog/sprint_turn pops left are the plant-fade trade-off above.
- Fourth batch (seeds 99 111 122 201 305, after the resample fix): seeds 111/122/201/305 have no IK_POP and no sink; seed 99 has 20 jog pops (the plant-fade trade-off). The
  remaining FLOATs (idle, idle_crouch, spin_in_place, up to 0.26 m) are the stop-step: spin_in_place alone (--ik-soak-only) has none, so they are the previous phase's last step finishing
  in the animation after the body stops (the clip's own foot, not the IK). Nothing new in the IK this round.
