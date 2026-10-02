# 035 - Foot IK v2 from scratch (flat / ramp / step / stairs)

Status: v2 is live-tested and better than v1 on ramps and stairs; everything reported so far is fixed
and guarded by headless regressions EXCEPT one hard bug, now its own task:
**`036_foot_ik_v2_tread_change_step.md`** (a foot that must change tread level needs a real step).
Isolated work under `tests/manual/foot_ik_v2/`; v1 (`actors/player/foot_ik/`) stays as the reference.
Full investigation history (every number, dead end, trace excerpt): `archive/035_foot_ik_v2_session_log.md`
(items 1-4) and `archive/035_foot_ik_v2_investigation_log_2.md` (items 5-17). Read them only for detail.
Branch `experiment/native-foot-ik`, everything committed (last `7ff496e` + this docs commit).

## What v2 is

`FootIKV2Modifier` (a `SkeletonModifier3D`, added last) + a pure two-bone `FootIKV2Solver`, driven by the
lab scene `foot_ik_v2_lab.tscn`. Per foot per frame: sample the floor under the animated ankle
(filtered), aim the ankle at floor + sole height, solve the leg, lay the sole on the surface, re-sample,
flatten the sole onto one tread, clear toe/tip/heel, sink to the true sole. Around it: pelvis drop
(deep only at rest), stance narrowing, reach clamp / release, plant-weight fade, body-height lag, a
step arc for big re-seats (`foot_ik_v2_stepper.gd`), joint limits (knee flexion 150, hip swing 100,
a 60 deg/frame flip guard; `foot_ik_v2_joint_limiter.gd`), an OFF foot-lock experiment
(`foot_ik_v2_lock.gd`, `foot_lock`). Tunables are `@export`s at the top of the modifier.

## Run it

```sh
scripts/check_foot_ik_v2.sh          # lint + solver + forward walk + ramp strafe + idle/jump + 4 turn sweeps
scripts/fuzz_foot_ik_v2.sh 12 7      # random-pose fuzz (fails today: task 036)
scripts/trace_v2.sh --trace F --segments|--tips|--released|--misses|--snaps|--slide|--vertical|--landing
scripts/trace_v2.sh --trace F --track left --from A --to B   # one foot; --frame N | --body (add --check)
```
Live trace `user://foot_ik_v2.jsonl`, headless `user://foot_ik_v2_check.jsonl` (separate files; every
line has `run_id`, animation, heading, reach decision, hips, modifiers, and a `pose` block with joint
angles for the FINAL and pre-IK ANIMATED pose plus `ik_delta`, `foot_ik_v2_pose_dump.gd`).
Lab flags (after `--`): `--foot-ik-v2-check`, `-ramp-check`, `-idle-check` with `--ramp-index=0|1|2`,
`--start-on-ramp`, `--uphill`, `--stairs`, `--stairs-edge`, `--jump45`, `--stairs-walk=0|1|2`,
`--walk-speed=X`, `--stairs-turn=dz[:x[:yaw[:quick]]]`, `--foot-ik-v2-off`, `--foot-ik-v2-perf`
(per-part usec, `foot_ik_v2_debug.gd`), env `FOOT_IK_V2_PERF_LOG=1` (engine counters).
Live lab: V = camera, F6 = v2 on/off, spheres on toe tip / heel green = touching the real floor, a line
joins them. Default spawn = the last live log frame `(4.61, 0.80, -0.05)` yaw 24.8.

## Suite state

PASS: solver (incl. knee never bends backward, flexion/swing caps), forward walk (6 surfaces,
`faults=0`), seven idle/jump regressions, turn sweeps dz 0 / 0.12 / -0.12 / live pose -1.41:-0.39.
RED (known, not caused by recent work): ramp-strafe replay, float 13.5-14 cm on 20-31 frames (limit 8).
Excluded, open: `--stairs-turn=0.24` and the smooth-turn phase of the fuzz (task 036).

## Solved (one line each; details in the archive logs)

- Measurement: read the modifier's published `final_pose` (+ `final_basis`), never a node's `_process`.
- v1 re-enables itself on landing: `set_debug_enabled(false)`. Ledge-safety airborne push zeroed in the lab.
- Idle: stance shift + pelvis drop on steep ramps/stairs; hysteresis on stance shift and flatten slide;
  the 2 cm slide glides; the sole sinks to the TRUE skinned sole (cached mesh walk, 8.5 ms -> 0.25 ms).
- Stairs: floor-height filter, plant fade, body lag, stair speed 1.2 m/s with the clip at speed/0.7,
  toe/tip/heel + riser retreat, flat landing.
- Stepper: skeleton-space, 6 cm trigger, lift kept out of its path (it vibrated forever otherwise).
- Poses: knee never bends backward (solver falls back to the rest pole); only a reach-clamped, non-stepping
  foot adds pelvis drop (the ratchet to 0.4 m bent both legs); joint limits above.
- Tooling: trace with joint angles, perf timers, turn sweep, random-pose fuzz, `pose_fault` in every check.

## Still open besides 036

Ramp-strafe replay red; ramp-walk reversals (9-20 -> ~40, unexplained); flat walking skates 0.44 m/step
(clip vs 3.2 m/s); the 0.35 m stairs cannot be climbed at stair speed; ledge-safety airborne push is a
gameplay decision; no ankle/foot angle limit; joint speed limit is a flip guard only (v1: 90-120 deg/s).

## Rules that bit us

Modifier and lab are at the 1000-line / 100-col lint cap: new code goes in helper files loaded with
`preload` (not `class_name`: the editor needs a rescan). Do not edit by line number after earlier edits
shifted them. macOS `sed -i` needs a suffix; zsh needs `${p}:quick`. Commit gameplay/visual changes only
after the user's live confirmation (AGENTS.md).

## Round 4 (2026-09-30) - stair shake, joint flash, reach blend

Full lessons are in AGENTS.md ("Foot IK v2, stair shake"). Short version: walking UP shook because the
capsule snaps down ~5 cm after each climb and the camera hover ignored it (`camera_snap_y`, camera
only); the pelvis also lurched at each 3-frame velocity stall (`_moving_hold`) and swung 6 cm per step
(slow release while walking). Also new: knee follows the foot (`KNEE_FOLLOWS_FOOT` 0.1) + a sway
regression, reach blend instead of a hard release, `foot_ik_v2_joint_flash.gd` (red spheres), shoulders
in the trace. Open: about 55 joint-flash frames remain on the forward-walk check (toe-off /
surface change), the ramp-strafe replay is still red, and ramp `dz=-0.12` is green only at 0.1.

## Round 5 (2026-10-02) - perf and first refactor

Modifier cost 762 -> 372 us/frame (`--foot-ik-v2-perf`, 900 frames headless). The skinned-sole code moved
to `foot_ik_v2_sole.gd` (cached once, replayed from the foot + toe bone poses, pruned to vertices within
10 cm of the sole, `level_points` transforms only the sole-level ones); `_ray` reuses one
`PhysicsRayQueryParameters3D`. Suite, fuzz (seed 7: clip 1 / float 2 / popped 10) unchanged. The modifier
is 909 lines. Left: the sole-sink pass is still ~220 us (about 130 us rebuilding points, the rest rays;
skipping it for an unmoved foot risks float/clip frames). Next refactor candidates: pelvis/stance planning,
reach/step passes, trace fields, each into a helper with the suite + fuzz run after every move.
