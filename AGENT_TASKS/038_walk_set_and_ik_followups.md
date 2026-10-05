# 038 - Walk set experiments and Foot IK v2 follow-ups (handoff, 2026-10-05)

Branch `experiment/native-foot-ik` (pushed). The user judges by how it looks; explain in plain words.
Suite: `scripts/check_foot_ik_v2.sh` (green except the old ramp-strafe check). Notes: AGENTS.md (retargeting,
stair cadence, IK jerk, Mixamo hips axis), `037` (plant-once design), `035`/`036` (older rounds).

## State of the walk set (all in `actors/player/player_temp_walk.gd`, called from `PlayerStairClips.add_to`)
- Forward walk = Action Pack Mixamo `walking.fbx` (`CHOICE 4`, `PLAYBACK_SCALE` 0.575, the user's pick).
  Other CHOICEs: 0 ALS `Walk_F` (needs the `head` bone fix, done), 1 UAL1 `Walk_Formal`, 2 UAL2 `Walk_Carry`,
  3 zombie, 5 Human Basic Motions walk (also liked); -1 / `ENABLED=false` = the original UAL1 `Walk`.
- Headless checks deliberately use the ORIGINAL walk (`DisplayServer` headless guard). When a walk becomes
  permanent: move it into the animation library build properly, delete the experiment file and its calls
  (`PlayerStairClips.add_to`, `PlayerBody` ref speed line, `PlayerDirectionalLocomotionLibrary.walk_animation`),
  re-baseline the vibration + comparison limits in the suite.
- Experiment, OFF by default (`DIRECTIONAL := false`): ALS `LF/RF/B/LB/RB` for W+A/W+D/S/S+A/S+D, played at the
  forward walk's step rate; `SIDEWAYS` (0 old strafes, 1 LF/LB blend = legs cross, 2 = ALS LF/RF with the hips
  turned `SIDE_YAW_DEG` 45 so diagonal steps become sideways steps). Mode 2 was just fixed (turn axis must
  account for the rotated `root` bone parent; headless check: pure 45 deg yaw about up) and NOT yet seen live.
  To try: set `DIRECTIONAL := true`, run the lab, press A / D / W+A / S. Judge: body upright and turned toward
  the move side, legs step sideways without crossing, arms OK, steps in sync with forward.
  The user said W+A / W+D with ALS LF/RF "rotate the body well".

## Update 2026-10-05 (later)
- Side walks (`player_temp_walk.gd`): `BACK_BODY_TURN` (S+A/S+D turn the body 45 deg, reverse forward walk)
  is the confirmed look. A/D alone: `SIDE_BODY_TURN` (90 deg turn + forward walk) is off; `SIDE_SET` 3 = ALS
  `N_Walk_LF/RF` with the hips turned 45 deg (not yet judged live). 1 = ALS `CLF_Walk_L/R` are CROUCH walks,
  2 = `walk_strafe_left/right` deform the limbs, 0 = old strafes. `apply_side` runs AFTER
  `add_directional_crouch_clips` (it used to be overwritten, so earlier side tests all showed the old strafe).
- Foot IK v2 on level floor now keeps the animation's foot rotation (walk and rest) and skips the redundant
  `_clear_toe` while `_keep_pitch`: foot turn 6 deg -> 0.01 deg, ankle/bone diff down. Ankle still up to
  2-3 cm raised on walks; idle keeps a 1.4 cm sink onto the floor and a ~3 cm calf (knee hint) difference.
- Tests: comparison scene reports foot turn and ankle/ball height; `scripts/check_foot_ik_v2.sh` has foot-turn
  checks (0.2 deg) for the UAL walks and for the player's walks (`--temp-walk`). The comparison row is also
  inside the lab (`foot_ik_v2_lab_row.gd`, F7 toggles, windowed only).

## Done this session (all pushed)
Knee follows the animation at idle on flat floor (comparison idle 9.3 -> 3.4 cm), eased walk blend for knee hint
and solver `bend_free`, landing reaches the floor + no bobbing, no foot into stair edges, far floors not surfaces,
squat release, stair cadence `stair_cadence_match` (Body node, 0.5), IK-jerk vibration checks (floor, stairs
up/down/back/45/sideways incl. live-log replays `--stairs-walk=0:sideup|sidedown|back|diagl...`), comparison
scene in the suite with per-animation limits, ground filter + knee hint helpers moved out of the modifier.

## Open, in priority order
1. Live-check the ALS directional/sideways experiment above; decide the final walk set; make it permanent.
2. Stairs sideways climb (`sideup`): foot hops 8-23 cm at tread changes (IK jerk 9/23 cm vs flat 3 cm).
   Three look-ahead variants failed (see `037`); real options: sample the animation's FUTURE foot path, or the
   plant-once rework. Live log numbers: strafe-left on stairs jerk p95 10.7 cm.
3. Still-open jolts from the last live logs: walk->idle snap on stairs (foot 26 cm, knee 36 deg), right-strafe
   lunge on flat floor (left foot 21-27 cm/frame for 4 frames), foot pitch snaps (foot_rot 35-54 deg, foot barely
   moving). Same class as the mode switches already eased: look for remaining `_is_moving` hard switches
   (joint limiter 0 vs 60 deg, pelvis cap/rate, correction easing, foot lock, stretch-hold reset).
4. `037` plant-once rework (contact decided once, pelvis from final targets, delete the stretch-hold ratchet).
5. Ramp-strafe check still red; v2 not the game default (game runs v1, cause of the earlier in-game failure
   unknown); delete v1 deferred.
6. Idle on STAIRS still uses the old rest-pole knee bend (the animation-faithful bend is only for flat floor,
   because stairs-turn checks are very sensitive to knee/foot yaw); a robust riser-retreat would let it go.

## Gotchas hit this session
BSD sed: no `\n`/`&` in replacements, `c\` needs a newline; never run `python3 -` (hangs on stdin; no inline
Python anyway). `get_slice` echoes the whole string when the delimiter is absent. AnimationPlayer names live in
the `moves/` library. Lint: 1000 lines / 100 cols (modifier now ~960, `player_body.gd` and `player.gd` AT the cap).
