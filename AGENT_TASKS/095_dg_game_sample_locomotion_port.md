# 095 - DG_GAME_SAMPLE locomotion port

> **Status: experimental, deliberately UNCOMMITTED.** None of this tree
> (`tests/manual/dg_game_sample_locomotion/`, `tests/automated/dg_game_sample_locomotion/`,
> `assets/models/dg_game_sample/`, this file) has been committed. It stays out of git until the
> user validates it live. `player_locomotion.glb` in that folder is renamed game content
> (meshes, textures, 547-joint skin, 37 clips) - do not publish it, and do not `git add -A`
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
  degree turns, 180 deg model facing fix, speed scaling, turn counter-rotation, slope blend
  spaces, jump/fall/land and step-down states.
- `tests/manual/dg_game_sample_locomotion/_probe_player_visual.gd` - game-rig probe: clip list,
  idle/move, and the full `Locomotion -> Jump -> Fall -> LandSoft` sequence.
- `tests/manual/dg_game_sample_locomotion/_probe_slope_visual.gd` - game-rig probe on terrain:
  a 20 deg ramp (`SlopeUp`), and 0.35 / 0.50 / 0.60 m descents (floor sweep vs `StepDown`).
- `tests/manual/dg_game_sample_locomotion/_player_view.gd` + `.tscn` - standalone model viewer
  (547 bones, single clip, orbit camera).
- `tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_lab.gd` - course build,
  camera, HUD, input.
- `tests/manual/dg_game_sample_locomotion/inspect_turn_clips.gd` - proves the TurnIP
  clips are in-place.
- `tests/automated/dg_game_sample_locomotion/dg_game_sample_locomotion_test.gd` - 21 headless
  checks (5 predicate-level, 5 body-level, 10 terrain, 3 animation-layer). **The animation checks exercise
  the Y Bot layer**; the game-rig layer is covered by `_probe_player_visual.gd` and
  `_probe_slope_visual.gd`.
- `assets/models/dg_game_sample/player_locomotion.glb` - 63 MB game-derived asset, 5 meshes,
  5 albedo textures, 547-joint skin, 37 clips, loaded as a `PackedScene`.

## Status

### Body / state machine layer

- gdlint clean; 23/23 checks pass on **Godot 4.7.2**
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

- 37 clips in one GLB: `idle`, `walk_F/B/L/R/FL/FR/BL`, `run_F/B`, `sprint_F`,
  `crouch_walk_F/B/L/R`, `turn_L/R_90`, `turn_L/R_180`, `jump_start`, `jump_start_sprint`,
  `jump_fall`, `fall_loop`, `fall_from_walk`, `land_soft`, `land_hard`, `walk_uphill(_fast)`,
  `walk_downhill(_fast)`, `run_uphill`, `run_downhill`, `step_down`, `step_down_land`,
  `edge_drop`, `slide_45`, `slide_65`.
- Wired: Locomotion blend space over local velocity, Crouch blend space over the movement
  direction (F/B/L/R), turn clip selected at 135 deg and above (falls back to the 90 clip),
  playback time-scaled to the procedural turn, 180 deg model yaw so the mesh faces Godot's -Z.
- **Air is wired** (`Jump` / `Fall` / `LandSoft` / `LandHard` states). The body only reports
  `Air`, so the visual infers the sub-state from `is_grounded()` + vertical velocity, and picks
  the landing clip from the deepest fall speed seen (-6 m/s or faster is a hard landing).
  Verified with `_probe_player_visual.gd`: `Locomotion -> Jump -> Fall -> LandSoft -> Locomotion`,
  52 airborne frames (0.87 s, matching the 4.2 m/s jump), and no landing clip at spawn.
- **Slopes and drops are wired** from the recovered clips:
  - `SlopeUp` / `SlopeDown` are 1D blend spaces over speed, entered at 10 deg and released at
    7 deg (hysteresis). Only while heading forward - the clips are authored forwards, and at one
    angle (45 deg), so sideways movement on a slope keeps the flat ring.
  - `StepDown` / `StepDownLand` cover drops of roughly 0.55-0.6 m, `EdgeDrop` up to 1.2 m, and
    anything deeper uses `fall_loop`. The band is measured, not assumed: a 0.50 m descent is
    absorbed by the floor sweep and never leaves Locomotion, a 0.60 m one plays
    `SlopeDown -> StepDown -> StepDownLand -> Locomotion`.
  - `slide_45` / `slide_65` are baked but **not wired**: the game has no slide in this component
    and there is no slide state to drive them.
- **Turns are counter-rotated.** The turn clips carry the whole turn as skeleton yaw (measured:
  the pelvis ends at +-90 / +-180 deg) *and* the body rotates the capsule, so without the
  counter-rotation in `_sync_turn()` the character visually spins twice.

### Floor and step physics (recovered, implemented, asserted)

`reports/floor-params.txt` in the RE workspace recovered the stock UE4 block at VA `0x14279041E`;
the game's component constructor never touches it, so the runtime is stock UE4. The port now uses:

| UE4 | value | Godot |
| --- | --- | --- |
| `WalkableFloorAngle` | 44.765083 deg | `floor_max_angle = 0.78132` rad |
| `MaxStepHeight` | 45 cm | `max_step_height`, enforced by `_try_step_up()` |
| `PerchAdditionalHeight` | 40 cm | `floor_snap_length = 0.40` + `_stick_to_floor()` |

Two engine gaps had to be filled, both found by failing tests rather than guessed:

1. `CharacterBody3D` has **no auto-step**. `_try_step_up()` runs UE4's pass before the slide: only
   when the blocking normal is steeper than walkable (so ramps keep going to `move_and_slide`),
   the same move succeeds 0.45 m up, there is headroom, and a downward shape probe reports the
   actual rise. 0.35 m climbs exactly; 0.60 m is still a wall.
2. Godot's `floor_snap_length` is a **single-frame** snap, and this capsule's rounded base loses
   floor contact for 2-3 frames while rolling over a stair nose (measured: `is_on_floor()` false
   0.28 m above the ground). Without a fix, a 0.35 m stair was crossed as a *fall*. `_stick_to_floor()`
   sweeps down `floor_snap_length` instead, limited to 150 ms after standing on something so a real
   fall is never shortened. The animation-safe floor test is `body.is_grounded()`.

Asserted in the suite: floor angle (44.7651), snap length (0.40), 20 deg ramp climb (y 2.34 m,
slope 20.0), 50 deg refusal (y 0.07), 0.35 m step climb (y 0.35), 0.60 m step refusal (y 0.00),
0.35 m descent (3 ungrounded frames, ends at y 0.00).
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
  | land_hard / fall_from_walk | **13.8 / 17.2 cm** |
  | jump_fall / land_soft / fall_loop | **21.1 / 21.2 / 24.4 cm** |
  | jump_start / jump_start_sprint | **31.5 / 31.9 cm** (arms overhead) |

  Slope and step clips: `walk_downhill` **7.5 cm** (best in the set), `step_down_land` **12.8**,
  `walk_uphill(F/fast)` **14.1 / 15.3**, `run_downhill` **16.0**, `step_down` **16.9**,
  `run_uphill` **19.5**, `edge_drop` **25.3**, `slide_45/65` **24.4 / 25.1** (arms 32-33 cm).

  Mean of the 37 clip means: **16.83 raw / 16.86 cm yaw-aligned** (worst `jump_start_sprint`
  31.89, best `walk_BL` 6.46). This is the Blender 5.2 bake; the earlier 13.88 cm figure was the
  5.0 bake of the 19 grounded clips - see the note below.
- **Coverage limit, important when reading the numbers:** the harness reference is the jacket
  PSK (123 bones). It has `LeftUpLeg` and nothing below it, so the legs below the hip and the
  feet are **not measured at all**. A 22 cm change in the foot pose moves the sweep by 0.00 cm.

## How the asset was baked

Blender pipeline, `scripts/build_player_locomotion.py` in the RE workspace (a mirror of the live
script): import the game's 5 meshes + the CUE4Parse skeleton JSON, rig with the GLB bind
rotations and the PSA bone heads, rigidly attach the hands, assign the 5 albedo textures,
bake the PSA clips, export one GLB with one animation per NLA track.

The bake runs **headless on Blender 5.2** (5.0 is no longer installed). The PSK/PSA importer is an
extension, so background mode needs it enabled by its namespaced module name:

```
blender.exe -b -P E:\Temp\opencode\run_blender.py -- D:\GAMES\dg_rea\scripts\build_player_locomotion.py
```

`run_blender.py` does `addon_utils.enable("bl_ext.user_default.io_scene_psk_psa")` and then
`runpy.run_path` on the target. The same wrapper runs `compare_all_clips.py`.

Adding clips is a list edit plus a re-bake, and the sweep then scores every clip on the way in.

Two quirks worth knowing:

- Re-baking the same script on 5.2 shifts the measured numbers slightly against the same
  reference (idle 7.01 -> 7.58, turn_L_180 21.90 -> 23.99), so figures are only comparable within
  one Blender version. Current numbers are the 5.2 ones.
- Godot's glTF importer publishes `fall_loop` as **`fall`**, which silently dropped the Fall state
  until the visual accepted both names (`FALL_CLIP_NAMES`).

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

1. **Transitions.** `walk`/`run` hold `dcn_idle_walk`, `dcn_idle_walk_90/180_L/R`,
   `dcn_walk_stop_L/R_foot`, `dcn_jog_stop_*`, `dcn_sprint_stop_*`, `dcn_loco_pivot_180_*`.
   The port hard-crossfades (0.15 s); these are authored foot-planted transitions and would remove
   the remaining skate at start/stop. All of them are already in
   `extracted/umodel/Game/Animation/player/{walk,run}` - only the bake list needs extending.
2. **Data assets** rather than approximations: `AnimationSets` (95), `Deacon/BlendSpaces` (94),
   `BendStateMachines` (5) + `States` (21), `TransitionGroups` (31), and the `Enumerations`
   behind `GetMoveSpeedForAnimationSelectionAndScaling`. These would replace the slope threshold
   guess (we use 10 deg because only a 45 deg clip exists) with the game's own blend rules.
3. **Arms** remain the largest residual everywhere, and they dominate the air clips
   (jump_start: arms 41 cm). They need a per-bone rest/roll correction rather than the current
   swing offset.
4. Read the pending decompiles, replace the provisional tuning constants, re-run the suite.
5. Decide whether `Turn` should also be entered from `Move` at higher speeds
   (currently only below `move_to_turn_max_speed`).
6. Confirm via CUE4Parse that no blueprint CDO overrides `MaxStepHeight` / `WalkableFloorAngle`
   (the executable's defaults are stock UE4; a data asset could still change them at runtime).
7. If the feel is worth keeping, promote the body to `actors/` with the game-rig `AnimationTree`.

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

On the RE side, `scripts/compare_all_clips.py` (Blender, via the MCP client) re-measures all 37
clips and rewrites `reports/clip-sweep.txt`; `scripts/probe_feet.py`, `probe_skin_weights.py` and
`probe_turn_yaw.py` cover the feet, the skinning and the turn yaw. Every report stamps its
generation time - check it, because a crashed run leaves the previous report on disk.

## Slope clips onto our player (tried 2026-11-16, backed out)

Retargeting `walk_uphill` / `walk_downhill` from `player_locomotion.glb` onto the player (Mixamo-style names, empty prefix, the stair-clip retarget path) yields 44 tracks but no real walk: played inside the GLB itself, with no retarget, `walk_F`'s LeftFoot moves 7 cm sideways and 7 cm front to back while the hips stay put (a walk is ~80 cm), `walk_uphill` 13 x 20 cm, `walk_downhill` 6 x 5 cm. All 217 tracks are rotations only (no hips/IK-bone position tracks). So the legs of these exported clips do not carry the stepping (likely an IK-bone or position channel that the export dropped). Do not wire them until the leg motion is recovered in the RE workspace (check the `ik_*` bones and the PSA position tracks). Nothing from this attempt is left in the tree.

Follow-up (same day): the raw PSAs are fine. Forward kinematics straight from the PSA keys (Hips > LeftUpLeg > LeftLeg > LeftFoot, cm, parent-local pos + quat, quaternion xyz NEGATED: UE is left-handed; un-negated gives impossible 125 cm foot excursions) gives the foot a real stride: `dcn_strafe_walk_F` 10 x 17 x 74 cm over the cycle (x lateral, y lift, z forward), `dcn_walk_uphill_45degrees` 12 x 58 x 67 cm, `dcn_walk_downhill_b` 9 x 32 x 76 cm. So the loss is in the Blender bake (`scripts/build_player_locomotion.py`, which keys `rotation_quaternion` only, derived from "target" poses in rest-corrected space), not in the game data. To use the slope clips, convert the PSA straight to our skeleton (parse keys, conjugate, rest-correct per bone, keep the hips position) instead of going through `player_locomotion.glb`.

### Status 2026-11-17: slope clips working on the player (uncommitted, DG material stays out of the repo)

- `tools/dg_slope/psa_joints.py` turns the PSAs into joint JSON (`assets/models/dg_slope/`, game-derived: do not commit). `PlayerSlopeClips` builds
  `unarmed_walk_{uphill,downhill}_{15,30,45}` from them at start-up: the source clips were authored on about +40 / -18 degrees of ground, so each grade is the
  joint data tilted to its slope plus a ground offset (uphill 0.23, downhill -0.09). A clip holds TWO strides (4 steps) in 2.48 s.
- Selection: floor slope (smoothed, hold 0.6 s so stair edges do not count) plus a look-ahead probe (two rays at 0.5 / 0.9 m) so the clip starts before the ramp.
- Pace: ground speed is capped at the clip's own pace (`SLOPE_CLIP_MAX_RATE` 0.85) and the clamp_rate floor is bypassed, so steps follow the movement.
- Blend: 0.4 s crossfade in and out of a slope clip, started at the matching stride phase (all walk clips start left foot forward; slope clips = 2 strides).
  The pose difference to the flat walk is still about 30-35 degrees mean (arms, legs), so the fade does most of the work.
- Foot IK on a ramp (while a slope clip plays): `moving_pelvis_drop` 0.3 (default 0.06), `moving_pelvis_rate` 1.0 (0.25), `ground_filter` off (it lagged the
  planted foot's ground 5-15 cm) and the new native `stretch_when_moving` on (a planted leg that cannot reach lowers the pelvis by its shortfall while walking).
  Planted feet, windowed lab: ramp30 up toe 1.0 cm / heel 1.5 cm (p90 4.7 / 5.2), ramp30 down 1.8 / 2.2, ramp15 up 1.4 / 1.9, ramp15 down 1.6 / 2.1.
  The lab's ramp45 counts as a staircase (stair clips), so the slope clips barely play there.
- Lab: `--log-steps` (STEP / CLIP / CONTACT lines with the IK state per foot), `--spot-down` (walk the ramp downhill), loop backoff 5 m.
- Open: speed drop at the floor -> ramp switch (two quick steps), a feel check of 45 degrees outside the lab, suite lab FAIL (stair020 clip 0.081, foot_step
  0.316 at right_ramp45) is the old one, and whether to keep the feature.
