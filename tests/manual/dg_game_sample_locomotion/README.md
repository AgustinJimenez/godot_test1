# DG_GAME_SAMPLE locomotion port (lab)

A from-scratch third-person locomotion model built on the reverse-engineered
`UBendCharacterMovementComponent` from `DGGameSample.exe`, kept in its own scene so
it does not touch the game's `player.tscn`.

- Scene: `dg_game_sample_locomotion_lab.tscn`
- Test: `res://tests/automated/dg_game_sample_locomotion/dg_game_sample_locomotion_test.gd`

## Run

Editor: open the lab scene and press F6.

Headless checks with Godot 4.7.2:

```sh
E:/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 \
  --path . --script res://tests/automated/dg_game_sample_locomotion/dg_game_sample_locomotion_test.gd
```

Controls: WASD, Shift sprint, Ctrl crouch, Space jump, mouse look, Esc cursor,
F3 HUD. `-- --demo-walk` on the command line drives forward input without a
keyboard (used for screenshot/movie captures).

The course has two ramps (20 deg and 40 deg, both rising toward -Z), four 0.3 m
stairs, a 1.4 m tunnel that forces a crouch, and pillars for turn-in-place.

## Character and animation

Two visual layers exist. The lab uses the game's own character by default
(`USE_PLAYER_MODEL = true` in the lab script); set it to false for the Y Bot.

### Game rig (`dg_player_visual.gd`)

`assets/models/dg_game_sample/player_locomotion.glb` holds the player's four body
parts, his hands, the 547-bone PSA skeleton and **37 clips** decoded from the game
(see the RE workspace's `notes/animations.md`). It is imported by Godot like any
other scene, so nothing depends on an external path.

| Body state | Animation |
| --- | --- |
| Idle / Move | `Locomotion` 2D blend space over **local** velocity (walk ring at 3.0, run 3.75, sprint 7.5 m/s) |
| Crouch | `Crouch` 2D blend space over the movement direction (F/B/L/R) |
| Turn | `turn_L/R_90` or `turn_L/R_180`, time-scaled to the procedural turn |
| Slope (>= 10 deg) | `SlopeUp` / `SlopeDown` 1D blend spaces: `walk_uphill(_fast)`/`run_uphill`, `walk_downhill(_fast)`/`run_downhill` |
| Jump | `jump_start` (or `jump_start_sprint` above run speed) while rising |
| Fall | `fall_loop` once vertical speed turns over |
| Land | `land_hard` from -6 m/s, else `land_soft` |
| Short drop (0.4-0.65 m) | `step_down`, then `step_down_land` |

`fall_loop` is published by Godot's glTF importer as **`fall`**; the visual accepts
either name. Two quirks worth knowing:

- The turn clips carry the whole turn as skeleton yaw, so the model is
  counter-rotated while a turn plays (otherwise the character spins twice).
- The model is exported facing +Z and is yawed 180 deg to match Godot's -Z forward.

### Y Bot fallback (`dg_game_sample_locomotion_visual.gd`)

The project's retargeted clip set `assets/models/als_retarget_test/*_on_ybot.res`
on the Mixamo Y Bot rig, with the same state mapping. The turn clips were verified
**in-place** (`inspect_turn_clips.gd`: the hips quaternion is identical at both
ends), so they layer on top of the capsule yaw without double-rotating.

```sh
godot --headless --path . \
  --script res://tests/manual/dg_game_sample_locomotion/inspect_turn_clips.gd
```

## Ground and steps

The floor/step block is recovered from the executable (RE workspace
`reports/floor-params.txt`, VA `0x14279041E`) rather than guessed:

| UE4 field | Value | Here |
| --- | --- | --- |
| `WalkableFloorAngle` | 44.765083 deg | `floor_max_angle` |
| `WalkableFloorZ` | 0.71 | implied by the angle |
| `MaxStepHeight` | 45 cm | `max_step_height`; Godot has no auto-step, so `_try_step_up()` implements UE4's pass |
| `PerchAdditionalHeight` | 40 cm | `floor_snap_length` 0.40 m plus the floor sweep in `_stick_to_floor()` |

Godot's `floor_snap_length` alone is not enough: it snaps only on the first frame a
floor is lost, and this capsule's rounded base rolls off a stair nose without a
floor contact on that frame (measured: `is_on_floor()` false at 0.28 m up, then a
free fall). `_stick_to_floor()` runs UE4's downward sweep instead, limited to
150 ms after standing on something so a real fall is never cut short.
`body.is_grounded()` is the animation-safe floor test (it includes the swept frame).

## Mapping to the recovered binary

| UE4 (recovered) | Here |
| --- | --- |
| `OnGroundIdle_Entered/Left`, `OnGroundMove_Entered/Left` | `State.IDLE` / `State.MOVE` in `dg_game_sample_locomotion_state_machine.gd` |
| `WantsToTransitionIdleToMove` | `_wants_to_transition_idle_to_move()` |
| `WantsToTransitionIdleToTurn` | `_wants_to_transition_idle_to_turn()` |
| `WantsToTransitionMoveToIdle_NEW` | `_wants_to_transition_move_to_idle()` |
| `WantsToTransitionMoveToTurn` | `_wants_to_transition_move_to_turn()` |
| `CanEarlyOutAnyTurnInProgress` | `_can_early_out_any_turn_in_progress()` |
| `HasTurnInPlaceTapRequest` / `ConsumeTurnInPlaceTap` | tap window + `_tap_queued` chaining |
| `UpdateTurnStatus`, `OnTurnStart/End`, anchored turns | `_begin_turn()` / `yaw_delta()` (windup, eased rotation, settle) |
| `GetMoveSpeedForAnimationSelectionAndScaling` | `get_speed_ratio()` (0..1 blend parameter) |
| `BendCharacterMovementTurnRateScaleVsStrafeAngleCurve` | `DGGameSampleLocomotionTuning.turn_rate_scale_for_angle()` |
| `SetCollisionShape` / `RevertToDefaultCollisionShape` | `_tick_posture()` capsule swap |

## Honest status

- **The structure is recovered; the speeds are not.** Walk 3.0 / jog 3.75 / sprint
  7.5 m/s and the crouched speed come from the constructor at `0x140833d70`; the
  accelerations, turn rates and state thresholds are still plausible placeholders.
- The **floor and step values are recovered** and asserted in the suite (44.765 deg,
  0.45 m step, 0.40 m snap, 23 checks), together with 20 deg and 40 deg ramp climbs, a 50 deg
  refusal, a 0.35 m step climb, a 0.60 m refusal and a 0.35 m descent.
- Slope clip selection is a threshold, not a blend: the game has one authored angle
  (45 deg) and the bake scores the uphill clips at 14-19 cm against the reference,
  in the same band as the flat walk.
- Only the forward heading uses the slope clips; sideways movement on a slope stays
  on the flat ring.
- Not ported yet: cover, climb/traversal, bike (`UBendMovementComp_VehicleNoDrive`
  is a separate component), weapons, and the game's own transition clips
  (`dcn_idle_walk`, `dcn_walk_stop_*`, `dcn_loco_pivot_180_*`) - the state machine
  still uses plain crossfades.
