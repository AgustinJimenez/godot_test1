# Active Task: Stair Foot IK

**Checkpoint branch:** `experiment/native-foot-ik`

Full chronological history (2026-08-03 through 2026-08-12, idle-freeze/loop-reset/
locomotion-parity debugging) is archived at
`docs/task_history/foot_ik_stairs_and_idle_freeze.md`. This file is the current-state
summary only — update it, don't let it grow back into a full narrative log; put new
blow-by-blow investigation detail in `AGENTS.md` (durable lessons) or a fresh
`docs/task_history/` entry (full trail) instead.

## Current status (2026-08-13)

Committed on this branch (`f79179f`): stair step-up now spreads its vertical rise over
several physics frames (`step_rise_rate` in `player.gd`) instead of an instant
~0.35m single-frame teleport; the stair-support system's release condition was
replaced with a direct "both feet on matching flat ground" signal (was previously
drifting the support target ~20cm during active climbs); `PlayerLookPoseModifier`
now damps Head/LeftShoulder/RightShoulder vertical bob in skeleton-local space. See
`AGENTS.md` for the detailed pitfalls found while building these (three distinct
step-smoothing failure modes, the stair-support drift root cause, a concrete new
instance of the twice-per-tick `SkeletonModifier3D` gotcha).

```sh
scripts/check_foot_ik.sh
```

```text
FOOT_IK_STRETCH_CHECK PASS samples=86 max_error_m=0.0 limit_m=0.005
FOOT_IK_AIRBORNE_CHECK PASS samples=62
FOOT_IK_BODY_PENETRATION_CHECK FAIL samples=86 penetrating_samples=21
penetrating_vertices=4044 max_depth_m=0.356508 tolerance_m=0.005
FOOT_IK_POSE_CONTINUITY_CHECK PASS samples=180 max_jump_m=0.024599 limit_m=0.025
FOOT_IK_STAIR_LOCOMOTION_CHECK FAIL steps=0 samples=0 stalled_frames=0
max_stall_frames=0 vertical_failures=0 max_rendered_dy=0.047
```

Both failures are intentionally still open (see below), not a regression from
tonight's work — `FOOT_IK_STAIR_LOCOMOTION_CHECK` didn't exist before the previous
commit, and `FOOT_IK_BODY_PENETRATION_CHECK` predates tonight's session.

## Open, parked items

- **Swing-phase penetration during active stair climbs** (`FOOT_IK_BODY_PENETRATION_CHECK`,
  currently failing). The walk animation's own swing trajectory, blended in at partial
  `ground_weight` before a foot is recognized as landed, passes through the new tread's
  geometry for a few frames every step — the animation's swing arc was authored assuming
  a flat continuous floor. Foot IK's existing swing-lift prediction reduces but doesn't
  eliminate this. Real fix needs a proper stair-climb blend/IK system (procedural leg
  lift or an authored stepping animation), not another quick IK tweak — scoped as a
  future feature, not a bug fix.
- **`FOOT_IK_STAIR_LOCOMOTION_CHECK`'s step-detection heuristic is stale.** It infers "a
  step happened" from `root_y` rising `>0.05m` in a single frame — exactly what
  `step_rise_rate` now intentionally avoids. The check itself needs updating (e.g.
  cumulative rise over a short window) before it can pass, independent of any further
  game-code fix.
- **65cm idle-float pop** (long-standing, last touched 2026-08-05, never fully
  resolved — see archive). Live-reported as: plants correctly on landing, then pops
  back to floating almost instantly. Never reproduced headlessly. Verify it's still
  reproducible before spending time on it; may be stale given how much of the
  idle/contact-loss machinery has changed since.
- **Option B (auto settle-step) can cascade down an entire staircase unprompted**
  instead of resolving just the one foot that needs it (see archive, "Open: Option B
  walks the character down an entire staircase unprompted"). Not yet diagnosed.
- **Ramp terminal-face edge contact**: `scripts/check_foot_ik_ramps.sh` (244-case
  matrix) and `scripts/check_foot_ik_ramp_sweep.sh` (dense spatial sweep) are both
  intentionally red — a toe entering through a ramp's vertical terminal face is
  invisible to a downward-only ray. Needs multipoint/shape-aware contact, not a global
  sole-offset pad (already tried, worsened other cases). See archive for the measured
  failure counts and why a uniform pad was reverted.
- **Leg overreach into empty space near a ramp edge** while turning in place — reported
  once via screenshot, working hypothesis logged in the archive, never investigated.

## Architecture to preserve

- `actors/player/player_foot_ik_modifier.gd`: orchestration, ground-contact sampling,
  shared pelvis application, public/debug state.
- `actors/player/foot_ik/foot_ik_gait_tracker.gd`: animated vertical velocity, contact
  weight, falling streak, landing events.
- `actors/player/foot_ik/foot_ik_stair_predictor.gd`: travel direction, predicted
  tread, swing lift, single-support-foot ownership/transfer.
- `actors/player/foot_ik/foot_ik_leg_solver.gd`: closed-form anatomical leg solve and
  bone angle limits only — no raycasts, no gait-state decisions.
- `actors/player/player.gd`: authoritative `CharacterBody3D` stair ascent/descent and
  collision-root movement (shared gameplay code, not test-only).

Godot evaluates `SkeletonModifier3D` after animation and restores the base pose
afterward — keep recurring IK there, not a direct persistent bone write from an
ordinary node (which would feed a corrected pose into the next frame's animation).

`SkeletonModifier3D._process_modification_with_delta()` runs **twice per physics
tick** (once real, once a phantom `delta=0.0`) — any per-frame "previous value"
reference, streak counter, or cached-output-for-other-systems-to-read must handle
this correctly (see `AGENTS.md` for the general pattern and two concrete examples:
the pelvis-sink baseline cache, and `PlayerLookPoseModifier`'s stabilization).

## Harness and diagnostics

Persistent scene: `tests/manual/foot_ik/foot_ik_preview.tscn` — multiple stair
heights, the 0.35m character is the focused traversable case using the real `Player`
physics callback; 0.50m/0.65m are pose-limit references only (gameplay
`Player.step_height` is 0.40m).

```sh
scripts/check_foot_ik.sh   # stretch/airborne/penetration/pose-continuity/stair-locomotion
scripts/check.sh           # lint + parse
scripts/check_foot_ik_ramps.sh        # 244-case ramp terminal-face matrix (intentionally red)
scripts/check_foot_ik_ramp_sweep.sh   # dense spatial ramp coverage (intentionally red)
```

Live verification loop (see `AGENTS.md`'s "Verification loop for interaction-sensitive
behavior" entry for the full technique): the debug overlay
(`tests/manual/foot_ik/foot_ik_debug_overlay.gd`) writes a rolling per-frame JSONL
trace to `user://foot_ik_controlled.jsonl` (capped at `CONTROLLED_TRACE_MAX_FRAMES`,
~20s) the whole time `foot_ik_preview.tscn` runs, including real skeletal
`Head`/`LeftShoulder`/`RightShoulder` bone transforms under `bones` (distinct from
`head_world_y`, which is the first-person camera anchor, not a bone). A magenta
marker sphere on the Head bone plus a turn-angle-colored trailing tube
(`foot_ik_debug_markers.gd`'s `spawn_trace()`/`update_trace()`) make shake visible
directly in third person, not just in log diffs.

## Manual acceptance checklist

- Walk the controllable player up and down the 0.35m stairs at normal speed.
- Confirm each swing foot clears the vertical riser before crossing it.
- Confirm feet land on tread tops without floating or penetrating.
- Confirm the body doesn't stretch below the steps.
- Jump and land on/near stairs; knees must not invert and airborne IK must release.
- Compare idle and walk poses with IK on/off for unrelated deformation.
- Never commit gameplay/animation changes on automated verification alone — wait for
  explicit live confirmation (see `AGENTS.md`).
