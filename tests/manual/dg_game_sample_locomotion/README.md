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

## Character and animation

No Blender import was needed: the project already carries the retargeted clip
set `assets/models/als_retarget_test/*_on_ybot.res` (built by
`tools/retarget_cli.gd`) on the Mixamo **Y Bot** rig
(`assets/models/mixamo_characters/Y Bot.fbx`). `dg_game_sample_locomotion_visual.gd`
builds an `AnimationTree` at runtime and maps the recovered states onto clips:

| Body state | Animation |
| --- | --- |
| Idle / Move | `Locomotion` 2D blend space keyed by **local** velocity: idle at the origin, 6-direction walk ring at 1.9 m/s, 6-direction run ring at 3.6 m/s |
| Crouch | `Crouch` 2D blend space (4-direction ALS crouch set + crouched idle) |
| Air | Jump clip while rising, Fall clip while dropping |
| Turn | `ALS_N_TurnIP_L/R90` or `L/R180`, time-scaled to the procedural turn duration |

The turn clips were verified **in-place** (`inspect_turn_clips.gd`: the hips
quaternion is identical at both ends), so they layer on top of the capsule yaw
without double-rotating.

Verify the clip property yourself:

```sh
godot --headless --path . \
  --script res://tests/manual/dg_game_sample_locomotion/inspect_turn_clips.gd
```


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

- **The structure is recovered; the numbers are not.** Speeds, accelerations,
  turn rates and thresholds in `dg_game_sample_locomotion_tuning.gd` are plausible
  placeholders. They must be replaced with the CDO/predicate constants read out
  of the binary (see `the RE workspace's notes/locomotion-map.md`).
- No animation: the capsule + wedge visual exists so facing and turn-in-place
  are readable. `get_speed_ratio()` is the hook an `AnimationTree` would use.
- Not ported yet: cover, climb/traversal, bike (`UBendMovementComp_VehicleNoDrive`
  is a separate component), weapons.
