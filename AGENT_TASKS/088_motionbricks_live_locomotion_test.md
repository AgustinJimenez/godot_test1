# 088: MotionBricks (NVIDIA) as live locomotion: test results and what is left

Written 2026-10-24. Everything here is a TEST: nothing is in the game, nothing is committed. The temporary scenes live in
`tests/manual/_tmp/` (delete before any commit, together with `tools/g1_retarget.gd` if the idea is dropped).

## What it is
MotionBricks (NVIDIA, SIGGRAPH 2026, arXiv 2604.24833): a real-time motion model driven by direction, facing, speed and a style.
The paper's headline demo is a UE5 game character, but the released code and weights are only for the Unitree G1 robot (34 joints).
Preview release (1 May 2026, nothing newer in `NVlabs/GR00T-WholeBodyControl/motionbricks` when checked on 2026-10-24); the weights licence is the NVIDIA
Open Model License (commercial use with attribution, read the live terms), the code is Apache-2.0.
The C++/GGML port `localai-org/motion-bricks.cpp` runs it on CPU (and Vulkan); weights `LocalAI-io/MotionBricks-G1-GGML` (0.73 GB + 15 styles).

## What was built and measured (all outside the repo except the scenes and tools below)
- Built the port with MinGW (one line in ggml's `ggml-cpu.c` disabled: `THREAD_POWER_THROTTLING_STATE` is missing from the MinGW headers).
  Use 2 to 4 threads on a 6-thread CPU: 8 or 16 threads made a plan take 35 to 150 s instead of 40 to 80 ms.
- A pipe server (`mb_server.exe`, in the scratchpad `...\scratchpad\mbcpp`) lets Godot drive it live: Godot sends `P style move face speed seed advance`,
  gets back the frames. Plan of 3 frames in about 50 ms; steering delay about 0.15 to 0.25 s. Replan every 3 to 8 frames: asking for the whole plan
  (44 frames) made the walk slow to 0.3 m/s every 1.47 s (it heads for the style's standing pose at each plan's end).
- 15 styles: idle, walk, slow, two stealth walks (one crouched), happy dance, injured, zombie, scared, gun, boxing, left, right, hand crawl, elbow crawl.
  Sprint = the walk style at a high target speed (asked 3.5 m/s gives about 4.3 m/s). NO jump, vault or climb (no style, and the port's constraint
  input and style conversion are not implemented).
- To hold a crouch or crawl while standing still, ask for that style at speed 0 (asking for `idle` stands up).
- Scenes: `g1_robot_viewer` (the robot meshes, looping clips), `g1_robot_play` (live WASD on the robot), `g1_human_play` (live, robot beside the MotusMan).
  `g1_viewer` / `g1_pose_demo` are the earlier offline MotusMan players.

## Findings
- The gait is the robot's: the model was trained on human mocap retargeted onto the G1 (SOMA retargeter). On the robot's own skeleton it already leans
  about 12 degrees, bobs the hips 9 cm and has an uneven rhythm. Retargeting cannot remove that, only reshape it.
- Retarget (`tools/g1_retarget.gd`, `HumanoidRetargeter`): the G1 has one bone per axis, so each human joint is a group of G1 joints multiplied together; the frame is
  turned about Y. The G1 neutral pose is NOT the human rest pose: its upper arm hangs down but its forearm points FORWARD at elbow zero (the elbow value then swings it down),
  its thighs angle back about 9 degrees. Fix (in `g1_human_play.gd`, `_build_fix`): per bone, the swing taking the human's rest direction to the robot's neutral
  direction, applied as `G' = G * own`, children `q' = parent^-1 * q * own`. Measured against the robot's own links: thigh 1 to 2 deg, shin 0, upper arm 9.5 deg
  (max 13.7), forearm 5 deg, torso about 3 deg after an empirically tuned extra 26 degrees of spine pitch (the reason is not understood).
- Measured on the MotusMan (walk, 6 s, 60 fps) against the player's Mixamo walk (one stride, 30 fps): with the torso lean removed (20 deg) the torso is upright (0.6 deg
  against about 0), the hip bob is 9.9 cm (Mixamo 7.6), foot lift 18 to 19 cm (Mixamo 13 to 15; it was 19 to 42 before), planted 41 to 48 % of frames (Mixamo 43 to 47).
  The planted slide is 6 mm per 60 fps frame (about twice Mixamo's). The body's travel must be scaled by the leg ratio (1.29) or the feet skate.
- Leg IK from the robot's foot positions (`ik=1`): lift 17 to 18 cm, planted 55 %, but slide about 3 times worse: not better. Off by default.
- Grounding: the retarget keeps the angles, not the proportions, so the person floated; the lowest foot, hand or head is put on the floor each frame (smoothed).

## Verdict so far
Fine for robots and odd characters (zombie, injured, scared NPCs). Not a replacement for the player's Mixamo walk: the rhythm and the stride are the robot's.
A human-skeleton MotionBricks would need training on BONES-SEED (human SOMA mocap, gated, licence: academic non-commercial, or "Qualifying Startup" under
US$1 M revenue with internal use; trained models count as Results; ask licensing@bones.studio before anything shipped), with the skeleton, features
(418 per frame, written for the G1's 34 joints) and loader rewritten, three models trained. Not started. Cheaper options that do not need it: use the model only as a
controller (root path, speed, heading) and play Mixamo clips at the matching speed; author jump, climb and vault as normal clips and switch back to the model.

## Not done
- Separate facing for strafing (the command takes a facing direction separate from the movement; `walk_left` and `walk_right` exist), world targets, batch NPCs.
- Context from the MotusMan's pose (`mb_agent_set_context`) after an authored clip, to hand over from Mixamo to the model.
- A GDExtension instead of the pipe helper (the helper path is hard-coded to the scratchpad build).
- Re-checking NVIDIA's repository for the full release (a human skeleton, jumps, smart objects).

## Decision (2026-10-24): not adopted
The released MotionBricks is a robot-skeleton locomotion model with 15 flat-ground styles. What the project page shows (a game character jumping, vaulting,
sitting, smart objects) is not in the released weights or in the C++ port (its constraint input and style conversion are not implemented). Checked:
- Target height is ignored: a world target at 0, 0.5 and 1.0 m height gave the same walk along the floor (pelvis 0.69 to 0.79 m in all three).
- Nothing in the port's docs about stairs, slopes, obstacles, climbing or jumping.
- The community human-skeleton fork (`Aceared0829/MotionWeaver`, trained on 1,722 UE Mannequin clips on an A800) reports its own result did not pass its
  playtest bar (foot slide 2.15 m/s against 0.60 for motion matching, sideways movement not executed).
- On the MotusMan the retargeted walk is a decent NPC walker but not better than the player's Mixamo walk plus Foot IK, and it still needs Foot IK for stairs.
So: no reason to ship it. Revisit only if NVIDIA releases the human-skeleton model with smart-object/keyframe constraints (check
`NVlabs/GR00T-WholeBodyControl/motionbricks` for commits after 2026-05-01). Jump, climb and vault stay authored clips plus the existing Foot IK.
The temporary scenes (`tests/manual/_tmp/`), `tools/g1_retarget.gd` and the scratchpad builds can be deleted; this file keeps the findings.
