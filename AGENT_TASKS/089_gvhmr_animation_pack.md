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
- BATCH FIX 2026-10-25: the first batch HUNG (0% GPU 15+ min): the LTX-2.3 GGUF model the old template names is NOT on disk and was downloading at ~1 MB/s. Switched to LTX-2.5 distilled int8 which IS in E:/repo/wan2.1gp/ckpts: tools/gvhmr/settings_ltx25.json (model_type ltx2_25_22B_distilled) + tools/gvhmr/batch_generate.py (copy of the unity one using it; output E:/repo/gvhmr_work/videos). One clip = ~2 min incl. model load (49 frames test). Batch restarted ~02:50 from the 38-clip manifest. If a run hangs again: look at the newest xet log in E:/repo/ai_models/huggingface/xet/logs and wan2.1gp/ckpts/.cache/huggingface/download/*.incomplete (= a download in progress).
- [x] HANDS implemented: tests/manual/animation/hand_presets.gd (HandPresets.apply, presets relaxed|fist, curl direction found per bone), gvhmr_retarget.gd hands=relaxed|fist, run_clip.py --hands. Verified on the Brute (fist curls tighter than relaxed). Which preset per clip: Sword_* and Object_* = fist, everything else relaxed (set via run_clip.py --hands).
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

## Results (one line per clip: ok / usable / failed; metrics from assets/animation/gvhmr_pack/metrics, sheets in .../sheets)
Process a clip: `python tools/gvhmr/run_clip.py E:/repo/gvhmr_work/videos/anim_<Name>.mp4 --name <Name> --hands relaxed|fist`
- Idle_Relaxed: ok - 4.0 s, root travel 0.18 m, head 1.60-1.63 m, limb accel median 4 (calm); stands and sways; head slightly bowed on the Brute (check later).
- Idle_Alert: ok - 4.0 s, travel 0.06 m, calm; wide stance, weapon-like prop held up in the right hand on the Brute (the Brute's own held axe, not from the clip).
- Idle_LookAround: usable - source root drifts 1.02 m over 4 s (GVHMR translation drift on a standing person); re-run with --inplace (retargeter's make_clip_in_place removes the net start->end travel; it does not remove wander, fine for loops).
- Idle_Tired: ok - travel 0.30 m, slumped stance, calm.
- DECISION: pass --inplace for Idle*, Turn*, Crouch_Idle, Crouch_Enter/Exit, Jump_InPlace; keep travel for Walk/Run/Crawl/Climb/Object_Carry (root motion is then read from the clip; check drift on those).
- Walk_Forward: usable - 4.0 s, travel 2.41 m (0.6 m/s: slow for a walk), head bob 19 cm, source floor drift -12.8 cm (now fixed by run_clip's ground step). Walks away from the preview camera = along the source's heading. Feet planted detection finds only 2-6% of frames on walks (planted feet are not 'slow' enough in GVHMR's output), so foot slide is NOT verified for walks.
- Walk_Slow: ok - travel 2.57 m (0.64 m/s), calm limb accel 5.7, floor shift -0.6 cm.
- Walk_Confident: usable - travel 3.4 m (0.84 m/s), floor shift -10.9 cm (fixed).
- NEW STEP in run_clip.py: ground_clip (tools/gvhmr/foot_report.py) shifts the translation so the lowest feet (2nd percentile) stand on y=0; GVHMR heights drift up to ~13 cm on walks toward the camera. All clips above were re-run with it.
- TODO speed: walk travel is 0.6-0.85 m/s, a normal walk is ~1.4 m/s and the legs cycle at a walking cadence: GVHMR's static-camera translation under-reads motion toward the camera (depth). Plan: per category target speeds (walk 1.4, run 3.5-5, crouch walk 0.9, crawl 0.5) and rescale the root travel (not the limbs) in run_clip/retarget: scale = target_speed / measured_speed; note that foot slide then gets worse unless the stride matches; verify with gvhmr_feet.tscn.
- Run_Forward: usable - travel 3.36 m (0.83 m/s: far below a run), limb accel median 27.6 with 11% spikes = JITTERY; needs smoothing (TODO: low-pass the rotation tracks, e.g. a small gaussian over 3-5 frames, before/after retarget).
- Walk_Backward: ok - travel 4.7 m (1.2 m/s), walks toward the camera facing it.
- Walk_Left: usable - 4.0 m across the frame, leaves the preview frame (fine); Walk_Right: ok - 2.4 m, calm.
- SPEED NORMALISATION implemented (run_clip.py --speed auto|<m/s>|0; gvhmr_retarget.gd speed=): rescales the hips' horizontal travel to a per-name target (Walk_Slow 0.9, Crouch_Walk 0.9, Crawl 0.5, Walk 1.4, Run 3.6, Run_Fast/Sprint 5.0 m/s); never applied with --inplace. Walk_Forward 0.79 -> 1.40 m/s is x1.77 travel. CAVEAT: limbs keep GVHMR's cadence, so feet will slide more with big factors; the foot-contact detector finds too few planted frames on walks to measure it (retune it: toe speed relative to the ROOT's speed, not the world).
- Batch status 03:0x: 13 videos done, 0 failed (~3 clips / 10 min).
- Run_Fast: ok - leaves the frame (6.9 m, 1.7 m/s before normalisation), mild jitter. Run_Right: ok. Run_Left: usable/doubtful - airborne first frame, floor shift -0.41 m, head 1.17-2.18 m (GVHMR height confusion); consider regenerating. Run_Forward: now ok after smoothing (limb accel 27.6 -> 16.6, spikes 11% -> 0).
- Jump_InPlace: usable - crouch then rise with arms out, head 1.10-1.67 m, no clear airborne phase (the video model barely jumps); regenerate with a stronger prompt if time.
- SMOOTHING added: tools/gvhmr/smooth_clip.py (gaussian over rotations as quaternions + translation, sigma 1 frame, run_clip --smooth 1.0 default); all processed clips re-run with it (walk limb accel halved).
- CONTACTS retuned (foot_report.py): speed limit follows the clip (0.2 x 95th percentile of toe speed, 0.2-0.6 m/s), height floor+5 cm: walks now show 14-57% planted frames per foot, idles ~80%, runs 3-14%. The SOURCE (GVHMR) feet already slide 3-10 cm per stance stretch.
- FOOT LOCK: debug shows the IK holds the ankle within 0-3 cm at most frames, but playback drift per stance stretch only drops ~10% (ankle 3.3/5.8 -> 3.0/5.0 cm, toe 13-15 cm unchanged because the foot keeps the source's pitch). DECISION: accept ~3-6 cm ankle slide per step; the lock stays on whenever contacts are passed (it does no harm), not worth more time now.
- SPEED NORMALISATION now scales the SOURCE pelvis track before the final retarget (so the foot lock sees the final motion); two-pass in gvhmr_retarget.gd.
- Crouch_Enter: ok - stand to deep squat, head 1.55 -> 0.93 m, very smooth (limb accel 0.7).
- Crouch_Idle: usable - the video model starts standing and only half-crouches (head 1.15-1.51); regenerate with 'already in a deep crouch from the first frame' if a true crouch idle is needed.
- Crouch_Walk: usable - travel 1.06 m in 4 s (normalised to 0.9 m/s), head 1.24-1.33 (crouched), calm.
- Jump_Forward: weak - barely leaves the floor (head 1.59-1.79); usable as a hop at best; regenerate.
- Jump_Long: ok - visible airborne frames, 1.9 m travel, head 1.27-1.73.
- Batch status: 20/38 videos done, 0 failed; 25 clips processed.
- Crouch_Exit: ok - deep squat (head 0.73 m) rising to standing, smooth.
- Turn_Around: ok - half turn in place, calm (travel removed by --inplace). Turn_Left / Turn_Right: ok - quarter turn pivots, calm (head height constant 1.55). NOTE these are not exact 90/180 deg: check the yaw change of the pelvis per clip before using them as turn-in-place animations (TODO: measure yaw in run_clip metrics and rescale/trim to the nominal angle).
- Climb_Ledge: FAILED - no climb visible: the person stands and leans/bends with the arms down (head 1.13-1.56, 18% limb-accel spikes = jittery); the video model did not render the wall climb. Needs another approach (start+end image mode, or a prop-free 'pull-up' phrasing, or Kimodo text-to-motion for climbing).
- Batch status: 24/38 done, 0 failed; 30 clips processed.
- Climb_Vault: usable - a run-up and a leap toward the camera (4.25 m, head 1.38-1.83), no wall visible: works as a 'leap / vault over' motion; the Brute's axe swings.
- Crawl_Forward: usable - a hunched low crawl-like move on hands and feet (head 0.76-0.99 m), travel normalised to 0.5 m/s; calm.
- Crawl_Low: usable/doubtful - low posture but the body floats above its shadow in the last frames (GVHMR height drift for a low body: head 0.81-1.66, travel 2.5 m); regenerate or ground per frame.
- Sword_SlashDown: ok - the sword goes up for the overhead wind-up and the fist grip holds it; limb accel calm (2.0); check the downward strike in the full clip later.
- Batch status: 29/38 done, 0 failed; 34 clips processed.
- Sword_Block: ok - arm raised with the weapon held up high and lowered again, calm (accel 1.1). Sword_SlashSide: usable - the weapon sweeps over the head at several angles (reads more like overhead swings than a flat horizontal slash). Sword_Thrust: ok - the weapon is held out level forward/side at shoulder height, small travel (0.66 m). All three use the fist preset. Body stays upright and calm (accel 1-3, no spikes).
- Batch status: 32/38 done, 0 failed; 37 clips processed. Remaining: Hurt_* (3), Object_* (3).
- Hurt_Flinch: ok - a sharp flinch/lean away then straightens, calm (accel 0.6). Hurt_Fall: usable - drops to a kneel and holds, head 0.69-1.29 m; the clip starts already low in the first frames (video model starts mid-fall), floor shift +0.12 m. Hurt_Stagger: usable - steps back with an arm up (travel 0.67 m); fine as a reaction.
- Batch status: 35/38 done, 0 failed; 40 clips processed. Remaining: Object_PickUp, Object_Push, Object_Carry (running).
- Object_PickUp: ok - bends down and straightens with the arm raised holding the prop, head 0.84-1.62, calm. Object_Push: usable - sustained forward lean (head 0.80-1.16 m) reads as a push posture; the video prop is not in the Brute's hands. Object_Carry: weak/usable - a plain walk (2.7 m) with the arms hanging, NOT visibly carrying a box (no two-arm hold); the video model did not hold the box with both arms in front.
- BATCH COMPLETE 2026-10-25 ~04:20: 38/38 videos, 0 failed, all 38 processed (json + Brute/MotusMan .res + sheets + metrics in assets/animation/gvhmr_pack/).

## SUMMARY after the first full pass (38 clips)
ok: Idle_Relaxed/Alert/Tired, Walk_Slow/Backward/Right, Run_Forward/Fast/Right, Crouch_Enter/Exit, Jump_Long, Turn_Left/Right/Around, Sword_SlashDown/Block/Thrust, Hurt_Flinch, Object_PickUp.
usable: Idle_LookAround, Walk_Forward/Confident/Left, Run_Left(doubtful), Jump_InPlace, Crouch_Idle, Crouch_Walk, Crawl_Forward, Crawl_Low(doubtful), Climb_Vault, Sword_SlashSide, Hurt_Fall/Stagger, Object_Push, Object_Carry(weak).
weak/failed: Jump_Forward (barely jumps), Climb_Ledge (no climb).

## NEXT PHASE (plan, in priority order; the loop continues with these)
1. HOOK INTO THE GAME: find how the player/NPC animation libraries load retargeted clips (actors/player/player_directional_locomotion_library.gd, humanoid_actor.gd, CharacterEditor animation package: tools/character_editor/character_animation_package.gd) and add a loader for assets/animation/gvhmr_pack/out/<Name>_<target>.res (per character: Brute / MotusMan / any manifest) so the clips are playable in the character editor and in game. Write a catalog json (name, category, rating, loop, root-motion, in-place flag).
2. TURN ANGLES: measure the pelvis yaw change per Turn_* clip (run_clip metrics) and trim/scale to the nominal 90/180 deg.
3. LOOPS: Idle/Walk/Run/Crouch_Walk/Crawl should loop: find the best loop window (min pose distance between a start and end frame, same foot phase) and crossfade or trim; store loop in/out in the catalog.
4. LOW BODIES / GROUND: crawl and hurt-fall float or sink (GVHMR height drift): ground per frame when the body is low (use the lowest of hands/knees/feet, not only feet).
5. RETRIES with better prompts (generate with tools/gvhmr/batch_generate.py on a new manifest; resumable): Climb_Ledge (use start+end images or a visible wall), Jump_Forward/Jump_InPlace (stronger take-off), Crouch_Idle (starts already in a deep crouch), Object_Carry (both arms hold a large box in front), Run_Left, Crawl_Low. Add more VARIANTS per category (3-6 each): idle (stretch, breathing, check watch), walk (injured limp, sneak, heavy), run (tired, zigzag), sword (combo, parry, kick), hurt (knockback, grab arm), object (drag, throw, open door), climb (ladder up/down), plus get-up and roll. Write them as an extra manifest tools/gvhmr/manifests/pack_v2.json via make_manifest.py CLIPS.
6. H3 OPTION: try h3-studio / WanGP minimax_h3 (weights in wan2.1gp/ckpts, used in August) for the weak categories; compare with LTX-2.5.
7. LICENCE: GVHMR/SMPL-X are non-commercial: document in the pack README; Kimodo (E:/repo/kimodo) as the commercial-friendly fallback for climb/crawl/etc.

## NEXT PHASE progress
- [x] 1a RUNTIME LIBRARY (2026-10-25): systems/animation/gvhmr_pack.gd (class GvhmrPack: catalog(), add_to(library, skeleton, humanoid_map, ratings), retarget(json, skeleton, map, options)); SmplxJsonSource / RetargetSmplx / HandPresets moved to systems/animation/. tests/manual/animation/gvhmr_retarget.gd is now a thin wrapper. assets/animation/gvhmr_pack/catalog.json from tools/gvhmr/make_catalog.py (ratings table inside; update it after retries). tests/manual/animation/gvhmr_library_check.tscn: `GVHMR_LIBRARY_CHECK PASS`: 36 ok/usable clips retargeted at RUN TIME onto Brute (2.8 s) and MotusMan (1.2 s), 0 bad. So the offline .res files are only for previews; games/tools can call GvhmrPack.add_to directly on any catalog character.
- [x] 1b (player half) DONE 2026-10-25: actors/player/player_body.gd adds `GvhmrPack.add_to(lib, skeleton, _target_humanoid_map)` after PlayerStairClips when env PLAYER_GVHMR_PACK is set (OFF by default; names gvhmr_<Name> in library &"moves"). planet_check with PLAYER_GVHMR_PACK=1 ran green (all PASS except the lint step: gdlint not installed). Character editor list: still TODO. Old note: add GvhmrPack.add_to(lib, skeleton, _target_humanoid_map) next to PlayerStairClips.add_to in actors/player/player_body.gd (library &"moves", names gvhmr_<Name>), behind a flag (default off) so gameplay is untouched; then list them in the character editor animation list. NOT DONE: needs care (player_body.gd is gameplay-critical).
- [x] 2 TURN ANGLES DONE: tools/gvhmr/turn_fix.py (measure; crop_to = best window starting facing front, then rescale to the nominal angle). Findings: the videos did NOT turn cleanly: Turn_Left went to -179 and came back (net -1 deg), Turn_Right spun 367 deg, Turn_Around reached only 148. run_clip now crops/rescales: Turn_Left = exactly -90 (1.8 s), Turn_Right +90 (1.6 s), Turn_Around 180 (2.8 s). (Sign: negative = the character's LEFT; verified on the Brute: it turns to its left.)
- [x] 3 LOOPS DONE: tools/gvhmr/loop_fix.py (window with the closest pose + neighbours, last frames blended to the first, in place, vertical bob closed). run_clip applies it to Idle*, Walk*, Run*, Crouch_Idle, Crouch_Walk, Crawl* (min cycle 2.5 s idles, 1.5 s crouch walk/crawl, 1.0 s walk/run; --no-loop to skip) and passes inplace; catalog.json: loops are in_place with `speed` = m/s the CONTROLLER should move at (walk 1.4, run 3.6, ...). GvhmrPack skips speed scaling for in-place clips. library check still PASS (36 clips, 0 bad).

## SECOND BATCH (pack_v2: retries ending in 2 + variants), results
- Jump_Forward2: ok - clearly airborne (frames 3-4: arms up, then tucked), replaces the weak Jump_Forward. Jump_InPlace2: ok - a big vertical jump, arms thrown up, head up to 2.14 m. Crouch_Idle2: ok - stays in a squat for the whole clip (head 1.30-1.39, loop of 2.5 s), replaces Crouch_Idle.
- Climb_Ledge2: usable - now a real climb-up motion (bends low, pulls up and over; the body is above its shadow because the ledge is not modelled), no failure like v1. Object_Carry2: weak - still a plain walk with the arm swinging; the box is not held in front. NEXT: Kimodo or a start-image with the box in the hands for carrying.
- [x] 4 LOW BODIES DONE: foot_report.ground_low (per frame, the lowest of ankles/toes/knees/elbows/wrists on y=0, smoothed 4 frames) applied by run_clip to Crawl*, Hurt_Fall, GetUp (not jumps). Crawl_Low and Crawl_Forward now stay on the floor (mean shift 6-11 cm) -> both rated ok; Hurt_Fall is a grounded kneel.
- [x] CHARACTER EDITOR: tools/character_editor/character_editor_animation_package_handler.gd now lists a built-in group 'GVHMR pack (generated)' (all ok/usable clips from catalog.json, shown as 'Name [rating]'), retargeted on demand onto the editor's current character with GvhmrPack.retarget. Verified only by a headless open of character_editor.tscn (no script errors); the UI itself was not clicked (nobody at the screen): TODO check it by eye.
- catalog.json now 43 clips: 25 ok, 15 usable, 2 weak (Jump_Forward v1, Object_Carry2), 1 failed (Climb_Ledge v1). Library check PASS (40 clips x 2 characters).
- Batch v2 still generating (7/27 done at this point).
- !! GIT MISTAKE 2026-10-25 (commit 8ff65b5): `git add -A tools` also staged tools/bark/bark_downloads (82 Poly Haven files) and tools/bark/fits (106 pictures) and the push uploaded ~86 MB of LFS objects. Fixed in the next commit (git rm --cached; files stay on disk untracked; the two locally-modified fits pictures were un-staged). They REMAIN IN THE HISTORY of that one commit; removing them needs a history rewrite + force push: the user must decide. From now on stage explicit paths only (memory note git-add-specific-paths).
- v2 batch 2: Crawl_Low2 ok (on hands and knees, grounded, 2.1 s loop), Idle_CheckWatch ok (hand to head, then relaxed), Idle_Combat ok (wide stance, weapon raised, calm), Idle_Stretch ok (arms overhead hold, 2.5 s loop), Run_Left2 ok (side run, 1.9 s in-place loop). All five rated ok in make_catalog.py; library check PASS. v2 progress 10/27 videos generated.
- v2 batch 3: Walk_Armed ok (2.3 s in-place cycle, weapon low), Walk_Sneak ok (2.8 s, hunched careful steps), Walk_Heavy usable (a single 1.1 s gait cycle, trudge only mild), Walk_Limp usable (1.2 s cycle; the limp is hardly visible). Speeds for the controller: sneak 0.9, heavy 1.0, limp 1.1 m/s. v2 progress 14/27 videos.
- v2 batch 4: Sword_Combo ok (two sweeping hits from raised guard, calm), Sword_Parry ok (a cross-body swing and return), Run_Armed usable (1.07 s cycle, reads like a brisk walk, not a run), Run_Tired usable (1.27 s cycle, jog-walk, head low). The LTX clips for 'run' toward the camera often come out as fast walks: if a real run is needed use side runs (Run_Left2/Right) or Kimodo. v2 progress 18/27 videos.
- v2 batch 5: Hurt_Knockback ok (arms flung out, stumbles back 0.94 m), Hurt_GrabArm usable (hunches over and straightens; the grab itself is not clear), Object_Drag usable (bends, pulls, straightens, head 0.88-1.39), Sword_Kick WEAK (stands with the sword; no kick visible). v2 progress 22/27 videos.
- v2 batch 6: Roll ok (two running steps, a dive and a landing in a low crouch), GetUp usable (lying on the back, rolls over, ends on hands and knees: the stand-up itself is cut off; grounded per frame, head 0.11-0.73), Object_OpenDoor usable (reaching arm up with the axe, no door), Object_Throw WEAK (stands with arms down; no throw visible). v2 progress 26/27 videos (Climb_Ladder still generating).
- v2 batch 7 (LAST): Climb_Ladder ok - a vertical climb: arms reach up alternately, legs step, the body rises to a head height of 2.19 m along an unmodelled ladder. pack_v2 is complete: 27/27 videos, 0 failed, all processed.

## FINAL SUMMARY (2026-10-25, end of the autonomous session)
WHAT EXISTS
- 65 clips (38 first pass + 27 second pass: retries named *2 and variants), each as GVHMR motion json (assets/animation/gvhmr_pack/json/<Name>.json + _contacts.json), metrics, a 4-frame preview sheet per character, and pre-retargeted .res files for Brute and MotusMan (previews only).
- Ratings (catalog.json): 37 ok, 23 usable, 4 weak (Jump_Forward v1, Object_Carry2, Sword_Kick, Object_Throw), 1 failed (Climb_Ledge v1). By category: Idle 7, Walk 10, Run 7, Crouch 5, Crawl 3, Jump 5, Turn 3, Climb 4, Sword 7, Hurt 5, Object 7, GetUp 1, Roll 1.
- Run time: GvhmrPack (systems/animation/gvhmr_pack.gd) retargets any clip onto any humanoid manifest (60 ok/usable clips on the Brute in 3.5 s, MotusMan 1.4 s); the player gets them behind env PLAYER_GVHMR_PACK=1 (names gvhmr_<Name> in library 'moves'); the character editor lists a group 'GVHMR pack (generated)'.
- Quality work: smoothing, ground fix, per-frame grounding of low bodies, speed normalisation, loops (seamless, in place, speeds in the catalog), exact turn angles (-90/+90/180), hand presets (relaxed/fist), foot contacts + optional ankle lock; limbs match the source within 1-5 degrees, shoulders ~2, travel follows the facing.
HOW TO RUN
- Video: python tools/gvhmr/make_manifest.py out.json [v2]; cp to E:/repo/gvhmr_work/; (cd tools/gvhmr && python batch_generate.py E:/repo/gvhmr_work/<manifest>.json) (LTX-2.5 distilled int8, local weights; resumable; ~2-3 min per clip incl. model load).
- Clip: python tools/gvhmr/run_clip.py <video.mp4> --name <Name> [--hands relaxed|fist] [--inplace] [--no-loop] [--smooth s] [--speed auto|x] [--targets brute,motusman] (native Windows GVHMR: E:/repo/gvhmr_win/.venv; needs GVHMR_CHECKPOINTS pointing at E:/repo/gvhmr/inputs/checkpoints, set inside the script).
- Catalog: edit RATINGS in tools/gvhmr/make_catalog.py, run it. Check: godot --headless --path . res://tests/manual/animation/gvhmr_library_check.tscn -> GVHMR_LIBRARY_CHECK PASS. Debug/preview: gvhmr_debug / gvhmr_preview / gvhmr_feet scenes (tests/manual/animation).
KNOWN WEAKNESSES
- The video model: 'run toward the camera' becomes a fast walk; carry/throw/kick/door are not rendered (weak or generic); no ledge/ladder/door props, so climbs are mimed in the air; turns are not clean angles (we crop+rescale).
- GVHMR: static-camera depth under-reads travel (we rescale speeds), heights drift (we ground), feet slide 3-6 cm per step in the SOURCE already (the ankle lock helps only ~10%), fingers are only presets, no facial/hand detail.
- The player integration is untested in a real play session (planet_check passes with the flag on; nobody looked at the animations in game). The character-editor group was only opened headlessly, not clicked.
LICENCE
- GVHMR, SMPL/SMPL-X (and WiLoR/MANO) are research / non-commercial: fine to prototype, NOT to ship without a licence or a replacement. Kimodo (E:/repo/kimodo, Apache code, NVIDIA open-model weights licence for the SOMA models) is the cleaner alternative; check its model licence before shipping.
NEXT IDEAS (in order)
1. Look at the clips in game: PLAYER_GVHMR_PACK=1, play gvhmr_<Name> from the debug/animation menu; click through the character editor group; fix what looks wrong by eye (this was not possible while the user was away).
2. Weak/failed clips via Kimodo text-to-motion (climb ledge, carry box, throw, kick, door) - same retarget path if its SOMA output is converted to json, or its own retarget.
3. H3 (h3-studio / wan2.1gp minimax_h3 weights exist) for the clips LTX cannot do; compare.
4. More variants per category (the manifests are cheap: ~2.5 min per clip), blends between clips (idle<->walk<->run) and a state-machine/controller that uses catalog loop/in_place/speed.
5. Feet: a proper foot-contact solver (the lock only reduces slide ~10%); fingers: hand tracker if a licence allows.
6. USER DECISION NEEDED: commit 8ff65b5 accidentally pushed tools/bark/bark_downloads (Poly Haven photos) and tools/bark/fits pictures (~86 MB LFS) to main; they are untracked again in the next commit but remain in the history. Purge them (history rewrite + force push) or leave them? I did NOT rewrite history.
