# 027: Foot IK debug toggles and per-part profiling

## Status

Implemented. Opt-in, off by default; behaviour is unchanged unless switched on. `check.sh` green,
fast suite unchanged (only the pre-existing 019 idle-plant failure), walking harness and ledge check
unaffected.

## What it is

`actors/player/foot_ik/foot_ik_debug.gd` (`class_name FootIKDebug`) provides two things:

1. **One on/off switch per major subsystem** (`master` gates them all; `false` = everything on =
   shipping behaviour):
   - `toe_clearance` - the same-frame clearance retry in `foot_ik_target_coordinator.solve_leg_candidate`;
   - `stair_support` - the stair predictor's `ensure_support` ownership;
   - `swing_lift` - the predicted step-up swing lift;
   - `balance` - the shared-pelvis lateral shift / counter-lean;
   - `idle_stance` - the idle stance rehome.
   They are deliberately **coarse** (whole subsystems, not one per line): they interact, so flip one
   at a time; combinations are not all validated.
2. **Per-part CPU timing** (`profiling`): `FootIKDebug.begin()` / `end(part, start)` accumulate
   `Time.get_ticks_usec` deltas; `frame_tick()` prints a `[FOOT_IK_PERF]` table every `report_every`
   frames. Off = zero cost (`begin()` returns -1 and `end()` early-outs).

Instrumented parts today: `total` (whole `_process_modification_with_delta`, LEGACY path) and
`support` (`_apply_support_pelvis_and_legs`) in `player_foot_ik_modifier.gd`; `clearance`
(the penetration check + retry) in `foot_ik_target_coordinator.solve_leg_candidate`. Add more by
wrapping any block in `begin()`/`end(&"name", ...)`.

## How to use it

Everything is in the existing preview feature panel (`foot_ik_feature_controls.gd`, shown in-scene,
**F6** hides it) under "Debug: subsystem switches + profiler":

- `Master (arms switches below)` - when off, every subsystem is on (shipping behaviour).
- `Toe clearance retry`, `Stair support`, `Swing lift`, `Balance / counter-lean`,
  `Idle stance rehome` - one checkbutton each.
- `Per-part profiler` - checkbutton that turns the timing on; while on it prints a
  `[FOOT_IK_PERF]` table every `report_every` frames.
- `Print profiler report` / `Reset profiler counters` - buttons.

The toggles are static values on `FootIKDebug.settings` (a plain object) so the panel's existing
`_add_toggle` can bind to them - GDScript static vars are not object properties.

Headless, without the panel (write to a file, never print it into chat unbounded): set
`FootIKDebug.settings.profiling = true` from a throwaway script, or temporarily default it true,
then

```sh
godot --headless --path . res://tests/manual/foot_ik/foot_ik_preview.tscn --quit-after 400 \
  > /tmp/perf.log 2>&1
rg -A 4 "FOOT_IK_PERF. frames=300" /tmp/perf.log
```

## First finding

On the default (one-player) preview, `support` (the pelvis/support/leg-solve pipeline) is ~78% of
the IK frame cost - ~557 us/frame of a ~712 us total - while the `toe_clearance` retry is
negligible (~1 us/frame, ~50 calls). So a Windows FPS drop from this feature is dominated by the
support/pelvis/leg pipeline, not the clearance retry. The multi-character preview is a stress case,
not representative one-player FPS (see `scripts/check_foot_ik_fast.sh`'s own note in AGENTS.md).

## Notes / next

- `foot_ik_perf_probe.gd` already prints engine-wide counters via `FOOT_IK_PERF_LOG=1`
  (process_ms/physics_ms/objects/nodes/pipeline compiles). Use that for "is it render or physics",
  and this per-part timing for "which IK step".
- The rig is CPU-only today (matches the user's observation). The profiler does not measure GPU;
  use `FOOT_IK_PERF_LOG` for that side.
- Extending the five toggles to cover more subsystems, or surfacing them as checkboxes in the
  existing F6 feature panel, would need an object-backed settings wrapper (the panel's
  `_add_toggle` reads object properties, and these are static) - not done.
