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
- [x] direct converter (step 3): tools/gvhmr/smplx_motion_to_json.py + tests/manual/animation/smplx_json_source.gd; gvhmr_retarget.gd takes source_json=; verified against the FBX route (limbs 1-5 deg, travel matches). clip fps is 30 (the old FBXs were exported at 24).
- [ ] pilot: ONE locomotion clip end to end (video -> motion -> game character), then judge quality
- [x] FEET (2026-10-25): tools/gvhmr/foot_report.py <clip.json> [contacts.json] = planted-foot detection + source slide; tests/manual/animation/gvhmr_feet.tscn = slide of the retargeted character while the source says planted; HumanoidRetargeter foot_lock (optional, gvhmr_retarget.gd contacts=) pins planted ankles with two-bone IK. FINDING: with tight contact thresholds (toe/ankle < floor+4 cm and < 0.2 m/s) the retargeted slide is only ~1-3 cm per planted stretch (pilot walk) and ~9 cm on the noisy walking_man_test; the lock changed it by <1 cm, so it stays OFF by default. Planted toes sit 1-4 cm above the clip's lowest point: acceptable. Re-check on the batch clips (run/crouch walk have more travel); if slide matters there, tune the lock (it has no reach-loss release yet).
- [x] FINGERS DECISION: no WiLoR/MANO (non-commercial + heavy). GVHMR leaves all 30 finger joints static. Plan: per-clip-type hand PRESETS written into the retargeted clip's finger tracks (relaxed half-curl by default, tight fist for Sword/Object grips). TODO implement in gvhmr_retarget.gd (Mixamo finger bones LeftHandIndex1..3 etc. from humanoid_map if present, else skip).
- [ ] batch generation: STARTED 2026-10-25 ~02:25. Manifest tools/gvhmr/make_manifest.py -> tools/gvhmr/manifests/pack_v1.json (38 clips, 97 frames @ ~24 fps, 832x448, LTX-2.3 distilled). Working copy with live statuses: E:/repo/gvhmr_work/pack_v1.json, videos in E:/repo/gvhmr_work/videos/anim_<Name>.mp4, log E:/repo/gvhmr_work/batch.log. Run: `cd E:/repo/unity/unityTest1/Pipeline/wan2gp && python batch_generate.py E:/repo/gvhmr_work/pack_v1.json --output-dir E:/repo/gvhmr_work/videos` (resumable). ~100 s per clip. Do NOT start GVHMR while it runs if the GPU is short on VRAM (try; GVHMR is small).
- [ ] per finished video: gvhmr.exe demo -s (gvhmr_win) -> extract_motion -> json (fps 30) -> foot_report -> retarget (Brute + MotusMan) -> judge ok/usable/failed in a table below. Script it as tools/gvhmr/run_clip.ps1 or .py so one command does a clip.
- [ ] native Windows GVHMR: venv E:
epo\gvhmr_win\.venv (uv, python 3.11, torch 2.7.1 cu126, `gvhmr[preproc]==1.6.1` = the repackaging that vendors pytorch3d's maths, no WSL needed). Install runs in the background (install_*.log, install_done.log). Checkpoints: point GVHMR_CHECKPOINTS / GVHMR_BODY_MODELS at E:
epo\gvhmr\inputs\checkpoints (and its body_models). Test on E:
epo\gvhmr\inputs\walking_man_test.mp4.
- [x] PILOT DONE 2026-10-25 (end to end, all native Windows except the video which was an existing LTX clip): video -> `gvhmr.exe demo -s` (gvhmr_win) -> extract_motion.py (run with gvhmr_win python) -> tools/gvhmr/smplx_motion_to_json.py <smplx.npz> <motion.npz> <out.json> 30 -> gvhmr_retarget.gd source_json= -> grounded walking Brute (json/pilot_walk_win.json, out/pilot_walk_win_brute.res; preview: gvhmr_preview.tscn target_model= clip= at= shot=). Bug fixed: the pelvis track must not get the rest lift. Old line: pilot (running 2026-10-25 01:52): existing LTX walk video (unity Pipeline/wan2gp/generated/videos/Walk_Forward_ToCamera_v3_fixed.mp4) -> copied to gvhmr/inputs/demo/pilot_walk.mp4 -> WSL `bash wsl_run.sh` (log E:/Temp/obj/pilot_walk.log, output gvhmr/outputs/demo/pilot_walk/hmr4d_results.pt) -> extract_motion.py -> smplx_motion_to_json.py -> gvhmr_retarget.gd source_json= -> preview.
- DECISION: video source for now = the proven LTX-2.3 headless pipeline (unity Pipeline/wan2gp/generate_video.py, ~30-90 s/clip, many clips already in generated/videos). H3 via h3-studio stays an upgrade option (needs its backend server running).
- Notes / findings:
  - 2026-10-25 native Windows GVHMR WORKS: E:epo\gvhmr_win\.venv, `gvhmr.exe demo <video> -s -o <dir>` with env GVHMR_CHECKPOINTS=E:/repo/gvhmr/inputs/checkpoints GVHMR_BODY_MODELS=E:/repo/gvhmr/inputs/checkpoints/body_models (torch 2.7.1+cu126, 4090 visible). It also offers --camera simplevo/dust3r/vggt for moving cameras (no DPVO). No WSL needed.
  - FPS TRAP: the old WSL run treats a 24 fps LTX video as 30 fps (62 frames = '2.1 s'), so motion plays 25% too fast; the old FBXs only looked right because they were exported at 24. The Windows package resamples 24 -> 30 fps (62 -> 78 frames) = correct real time. Prefer the Windows outputs; if a WSL motion.npz is used, give smplx_motion_to_json.py the video's real fps (24).
  - pilot (WSL run): 62 frames, retargeted OK onto Brute and MotusMan (assets/animation/gvhmr_test/out/pilot_walk_*.res, json/pilot_walk.json made at 30 fps = too fast; redo from the Windows output).
  - prior art: unity project Pipeline/wan2gp has animation_list.json (the wanted clip list), batch_generate.py, manifests.
  - SMPL-X rest origin is not on the floor: the json loader lifts the rest pose so the feet stand on y=0.
