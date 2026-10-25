# 089 - Adventure animation pack from generated video (H3 / LTX -> GVHMR -> Godot)

Goal (user, 2026-10-25): a whole locomotion/adventure pack - idle, walk, run, jump, crouch, turn in place, climb, crawl, sword
attack, get injured, move an object - with many variants each, made from generated video, with attention to FINGERS and FEET.
The user wants this worked autonomously with a 4-minute reminder loop (ScheduleWakeup) - keep THIS FILE's "State" current so a
wake-up can continue without the chat.

## Pipeline (all pieces exist unless marked TODO)
1. Video: H3 locally via h3-studio (E:\repo\h3-studio, WanGP) OR LTX-2.3 via E:\repo\unity\unityTest1\Pipeline\wan2gp\
   (generate_video.py, batch_generate.py + manifest json, animation_list.json = the full wanted clip list). One continuous shot,
   static camera, full body in frame, plain background (GVHMR needs it).
2. Motion: GVHMR (E:\repo\gvhmr, runs in WSL; see unity AGENTS.md "GVHMR Video-to-Motion Pipeline") -> outputs/demo/<name>/
   hmr4d_results.pt -> extract_motion.py -> motion.npz (global_orient, body_pose, transl, betas).
3. TODO direct converter (no Blender): tools/gvhmr/smplx_motion_to_json.py (SMPL-X rest joints + parents + per-frame rotations)
   + a Godot script that builds the Skeleton3D/Animation from that json and retargets.
4. Retarget: tests/manual/animation/gvhmr_retarget.gd (+ HumanoidRetargeter direction_chains / hip_axis / twist options),
   verified with tests/manual/animation/gvhmr_debug.gd (limbs within ~1-5 deg, travel follows facing, shoulder twist ~2 deg).
5. TODO feet: GVHMR gives no foot contacts - detect planted feet from the motion (ankle/toe speed + height), pin them
   (foot lock / IK) so they do not slide; check with the foot-IK tooling already in the project.
6. TODO fingers: GVHMR recovers none. Options: prompt2rig hq/hands.py (WiLoR, MediaPipe fallback; E:/Temp/p2r/repo cloned),
   or a few hand-pose presets per clip type (fist for sword/grab, relaxed otherwise). Decide after a pilot.

## Licences
GVHMR, SMPL/SMPL-X (and WiLoR/MANO) are research / non-commercial: fine for prototyping, not for a shipped game without a
licence or a replacement. Kimodo (E:\repo\kimodo, text->motion) is the cleaner fallback.

## Expected hard categories (verify, report honestly)
climb, crawl, move-object, anything with the body not upright or occluded: video models render them badly and GVHMR assumes an
upright body. Report per clip: ok / usable-with-cleanup / failed.

## State (update every wake-up)
- [x] GVHMR clips retargeted onto Brute + MotusMan, limbs/travel/twist verified (see commits).
- [ ] direct converter (step 3)
- [ ] pilot: ONE locomotion clip end to end (video -> motion -> game character), then judge quality
- [ ] feet fix (step 5), fingers decision (step 6)
- [ ] batch generation (use animation_list.json categories; resumable manifests)
- Notes / findings:
