# 095 - DG_GAME_SAMPLE locomotion port

> **Status: experimental, deliberately UNCOMMITTED.** None of this tree
> (`tests/manual/dg_game_sample_locomotion/`, `tests/automated/dg_game_sample_locomotion/`,
> `assets/models/dg_game_sample/`, this file) has been committed. It stays out of git until the
> user validates it live. `player_locomotion.glb` in that folder is renamed game content
> (meshes, textures, 547-joint skin, 19 clips) - do not publish it, and do not `git add -A`
> in this repo without expecting it to be swept in.

Written 2026-10-27, updated 2026-10-28. Everything here is an EXPERIMENT: uncommitted, isolated
in its own scene, nothing wired into `player.tscn` or the game.

## What it is

A from-scratch third-person locomotion model rebuilt from the
`UBendCharacterMovementComponent` API recovered out of the game's executable
(Ghidra, 53 native UFunctions), plus a player character baked out of the game's own assets.

Two layers, deliberately separable:

1. **Body + state machine** (original code): speeds, acceleration, facing, turn-in-place, crouch
   capsule swap, air state, and an Idle/Move/Turn/Air machine whose method names are the recovered
   UFunction names.
2. **Visual** (game assets): two interchangeable implementations -
   `dg_game_sample_locomotion_visual.gd` (Y Bot + the project's retargeted clips, the fallback)
   and `dg_player_visual.gd` (the game's own mesh/skeleton/clips). The lab switches with
   `USE_PLAYER_MODEL`.

The RE workspace lives outside this repo. Everything cited below is there:
`notes/animations.md` (the full pipeline history and every measurement),
`notes/locomotion-map.md`, `notes/method-ue4-locomotion-recovery.md`,
`symbols/ubendcharactermovementcomponent-ufunctions.txt`, `reports/`, `scripts/`.

## Files

- `tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_lab.tscn` - playable lab
  (ground, 20 deg ramp, stairs, 1.4 m crouch tunnel, turn-in-place pillars).
- `tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_body.gd` - CharacterBody3D:
  speed selection, acceleration/braking, facing, turn-in-place, crouch capsule
  swap, air state, `get_speed_ratio()` animation hook.
- `tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_state_machine.gd` -
  Idle/Move/Turn/Air machine whose method names are the recovered UFunction names.
- `tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_tuning.gd` - all knobs in
  one Resource.
- `tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_visual.gd` - Y Bot +
  retargeted clips: Locomotion/Crouch blend spaces, jump/fall, turn-in-place
  clips time-scaled to the procedural turn. **Fallback**, works with no game assets.
- `tests/manual/dg_game_sample_locomotion/dg_player_visual.gd` - the game's own rig:
  Locomotion blend space (idle/walk ring/run/sprint), Crouch blend space (F/B/L/R), 90/180
  degree turns, 180 deg model facing fix, speed scaling, turn counter-rotation.
- `tests/manual/dg_game_sample_locomotion/_player_view.gd` + `.tscn` - standalone model viewer
  (547 bones, single clip, orbit camera).
- `tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_lab.gd` - course build,
  camera, HUD, input.
- `tests/manual/dg_game_sample_locomotion/inspect_turn_clips.gd` - proves the TurnIP
  clips are in-place.
- `tests/automated/dg_game_sample_locomotion/dg_game_sample_locomotion_test.gd` - 13 headless
  checks (5 predicate-level, 5 body-level, 3 animation-layer). **These exercise the Y Bot
  layer**; the game-rig layer is covered by the render/lab checks described below.
- `assets/models/dg_game_sample/player_locomotion.glb` - 55 MB game-derived asset, 5 meshes,
  5 albedo textures, 547-joint skin, 19 clips, loaded as a `PackedScene`.

## Status

### Body / state machine layer

- gdlint clean; 13/13 checks pass on **Godot 4.7.2**
  (`E:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe`) with
  `--headless --fixed-fps 60`. The project-wide parse gate
  (`res://scripts/parse_all.tscn`) also passes with these files present.
- Y Bot visuals: the project's own retargeted clips
  (`assets/models/als_retarget_test/*_on_ybot.res`). No Blender step needed for that layer.
- **Tuning values are placeholders.** The structure (states, predicates, turn phases, tap
  chaining, capsule swap) is recovered; the numbers are not. A batch decompile of the transition
  predicates, `UpdateTurnStatus` and `GetMoveSpeedForAnimationSelectionAndScaling` is still
  pending in the RE workspace; replace the Resource values when it lands and cite the evidence id.
- No animation-level fall damage, no cover/climb, no bike (separate component in the game),
  no weapons.

### Player model layer (game assets)

- 19 clips in one GLB: `idle`, `walk_F/B/L/R/FL/FR/BL`, `run_F/B`, `sprint_F`,
  `crouch_walk_F/B/L/R`, `turn_L/R_90`, `turn_L/R_180`.
- Wired: Locomotion blend space over local velocity, Crouch blend space over the movement
  direction (F/B/L/R), turn clip selected at 135 deg and above (falls back to the 90 clip),
  playback time-scaled to the procedural turn, 180 deg model yaw so the mesh faces Godot's -Z.
- **Turns are counter-rotated.** The turn clips carry the whole turn as skeleton yaw (measured:
  the pelvis ends at +-90 / +-180 deg) *and* the body rotates the capsule, so without the
  counter-rotation in `_sync_turn()` the character visually spins twice.
- Measured fidelity vs the game's own PSK/PSA, mean joint error relative to the hips
  (`reports/clip-sweep.txt` in the RE workspace):

  | clip group | error |
  | --- | --- |
  | walk_BL / walk_F / walk_B / idle | **6.4 - 7.4 cm** |
  | walk_L / walk_FL / walk_FR | **8.5 - 10.1 cm** |
  | run_F / walk_R / run_B | **11.1 - 12.6 cm** |
  | crouch_walk_F/B/L/R | **14.4 - 16.0 cm** |
  | sprint_F | **19.0 cm** |
  | turn_L/R_90 | **22.4 / 24.2 cm** |
  | turn_L/R_180 | **21.9 / 22.6 cm** |

  Mean of the 19 clip means: **13.88 cm**. By region (yaw-aligned): spine 0.7-19.6,
  neck/head 0.3-17.1, legs/hips 2.3-10.0, **arms 8.8-32.3**.
- **Coverage limit, important when reading the numbers:** the harness reference is the jacket
  PSK (123 bones). It has `LeftUpLeg` and nothing below it, so the legs below the hip and the
  feet are **not measured at all**. A 22 cm change in the foot pose moves the sweep by 0.00 cm.

## How the asset was baked

Blender pipeline, `scripts/build_player_locomotion.py` in the RE workspace (a mirror of the live
script): import the game's 5 meshes + the CUE4Parse skeleton JSON, rig with the GLB bind
rotations and the PSA bone heads, rigidly attach the hands, assign the 5 albedo textures,
bake 19 PSA clips, export one GLB with one animation per NLA track.

Two formulation details matter and cost the most time to get right:

1. **Frame 0 of the clip is the delta reference.** Using the PSA rest pose tears the mesh.
2. **The motion transfer must be the world-space DELTA, mirror-conjugated:**
   `target = (S . (refWorld . refRest^-1) . S) . ourRest`, with `S = diag(1,-1,1)` because the two
   rigs are mirror images across XZ. The previous form (`ourRest . (refRest^-1 . refWorld)`, and
   its equivalent `REF_CONV . refWorld`) is exact only at rest and *conjugates* the motion,
   so the error grew with the rotation: 8 cm on a forward walk, 34-58 cm on turns, with the head
   ending a metre from where it belonged. Fixing this is what took the mean from 25.09 to
   13.88 cm.

## Rejected experiments (do not retry without new evidence)

- **`Hips` / `cog` driven by the reference pose** (absolute rotation): worse on every lateral
  clip - walk_L 14.3 -> 17.0, turn_L_90 34.0 -> 40.1 (cog); 17.7 / 40.5 with Hips as well.
- **Arms with the delta on the left** (`delta . rest`, the ordering that fixed the spine):
  13.88 -> 14.46 mean; forward clips better, turns worse.
- **Legs with the world-space delta** (both without and with the mirror conjugation): fixes the
  foot twist but makes the SHIN point sideways/upward in `sprint_F` - anatomically impossible.
  The shipped local ordering is the only one with sane shins.
- **Bake-side de-yaw of the turn clips**: the bake mixes absolute (spine) and parent-relative
  (hips/legs) targets, so rotating the `Align` root turns the pelvis but leaves the absolutely
  keyed spine behind (shoulders -86 deg relative to the pelvis).
- **umodel's joint-only glTF export as a position reference**: two independent readers agree with
  each other (47.5 vs 47.6 cm on walk_F) but disagree with the PSK/PSA importer (8.2 cm), and a
  best-fit rigid transform still needs ~90 deg plus a reflection and 24 cm residual - its node
  conventions do not match the PSK bind frames.
- **Mirroring the reference pose and using it directly** (earlier attempt): arms 11.0 -> 45.6 cm.

## Known defects

1. **Arms are the largest residual** (8.8-32.3 cm, worst at the hands). They use the raw
   bind-delta path plus a fixed 35 deg swing offset because their rest pose differs from the
   reference (A-pose vs the PSA T-pose). A swing cannot fix a ROLL difference, and the error
   grows with how far the clip rotates the shoulder - that is the signature.
2. **Feet twist about the shin in `sprint_F`** (foot points sideways while the shin is vertical;
   see `reports/foot-probe.txt`). Reads as the flat/elongated boots in renders. Not skinning:
   every joint with >0.5% weight on any mesh is animated (`reports/skin-weights.txt`).
   A roll difference at the ankle cannot be fixed by choosing where the delta multiplies, and
   there is no reference with feet to measure a correction against - see Next.
3. **Hands are rigid** (no finger articulation); accepted trade-off, the hand mesh is rigidly
   attached to the wrist bones.
4. **Legs below the hip are unvalidated** - not a bug, a measurement gap (see coverage limit).

## Next

1. **Full-body reference via CUE4Parse.** It is already in the pipeline for the meshes and is the
   only decoder that handled the parts umodel rejects with Seek64. Exporting the trousers/boots
   skeleton + skin gives a reference with feet, which (a) makes the ankle roll measurable instead
   of guessed and (b) lets the legs be scored at all. This is the unblock for defect 2.
2. **Arms**: with a full-body reference in place, fit a per-bone rest (roll) correction instead of
   the frontal-plane swing, and judge it with the sweep.
3. **Turns and crouches are the weakest clips** (22-24 cm). With the yaw understood and the
   transfer fixed, the remaining error is arm-dominated, so 1 and 2 should move these too.
4. Read the pending decompiles, replace the provisional tuning constants, re-run the suite.
5. Decide whether `Turn` should also be entered from `Move` at higher speeds
   (currently only below `move_to_turn_max_speed`).
6. If the feel is worth keeping, promote the body to `actors/` with the game-rig `AnimationTree`.

## Verifying a change

```
E:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --headless --import
E:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --headless ^
  -s res://tests/automated/dg_game_sample_locomotion/dg_game_sample_locomotion_test.gd
E:\Temp\opencode\gdlint-venv\Scripts\gdlint.exe tests/manual/dg_game_sample_locomotion/
```

Render the lab (input-driven) or the single clip viewer (no input) when the visual layer changed:

```
... --path . --fixed-fps 30 --write-movie E:\Temp\opencode\lab\frame.png --quit-after 40 ^
  res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_lab.tscn
```

On the RE side, `scripts/compare_all_clips.py` (Blender, via the MCP client) re-measures all 19
clips and rewrites `reports/clip-sweep.txt`; `scripts/probe_feet.py`, `probe_skin_weights.py` and
`probe_turn_yaw.py` cover the feet, the skinning and the turn yaw. Every report stamps its
generation time - check it, because a crashed run leaves the previous report on disk.
