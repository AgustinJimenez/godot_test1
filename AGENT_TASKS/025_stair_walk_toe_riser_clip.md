# 025: Recurring toe clip — startup idle identified, walking scope still open

## Status

**The startup clip is fixed and live-confirmed by the user (2026-09-13): the fixed 16cm clip that
always fired around frame 17-20 at scene load no longer appears in a fresh live session.** Not
yet committed. Task 024 remains live-confirmed and committed separately.

Still open: real clipping during ordinary walking persists, separate from the startup bug this
fix addressed. Same live session that confirmed the startup fix also logged 39 clip events during
genuine walking, most small (5-10mm) but one real: **11.3cm**, right foot toe, mid-walk
(`moves/unarmed_walk`, frame 469). This is a different, still-uninvestigated case - not the
startup bug, not confirmed to be 019 (stationary rotation) or 020 (ramp corner) either. Task 019
and task 020 remain separately open and not declared fixed by this work.

Earlier investigation is preserved in
[the archive](archive/025_walking_hypothesis_investigation.md). Its identification of the recurring
event as walking/turning was incorrect; do not resume target-path patches from that assumption.

## Exact event match (2026-09-13 continuation)

Matched **ankle/toe positions**, not the nearest root, in all three preserved live captures:

- `/tmp/foot_ik_controlled_third.jsonl`
- `/tmp/foot_ik_controlled_livewalk_20260913.jsonl`
- `/tmp/foot_ik_controlled_liveafter.jsonl`

The repeated `(15.37852, 1.117114, 1.958677)` point matches the **left toe tip at frame 17**
within 0.000005 m in all three. Animation is `moves/unarmed_idle`, root yaw is constant
`100.977250312091` degrees; this is startup, before the user walks. The ankle's actual position
is far below its valid 1.496 m solve target. This is not an ankle target crossing a wall.

## Confirmed initialization failures

1. `AnimationPlayer.play()` selected idle but had not applied it before the first zero-delta
   modifier evaluation. At physics frame 1, the imported pose's left foot was
   `(15.17172, 1.618629, 0.211004)`, sampling the wrong tread at y=0.35. The true idle foot is
   around `(15.52421, 1.505602, 1.975434)`, supported at y=1.4. The first real pass reused the
   zero-pass pose cache; later frames smoothed from that unrelated support.
2. `_shape_shared_drop()` could advance pelvis-drop history on a zero-delta refresh.
3. Startup borrowed the animation-loop seam-acquisition bypass: it released the upper leg while
   the shared pelvis lowered to reach the lower tread. The upper leg then rate-limited its way
   back out of the stair. Initial placement is not an already-visible movement to interpolate.
4. Upper-foot extension also needs its destination established in that initial placement;
   initializing only the bones left a brief ~2.4 cm toe clip during delayed upper acquisition.

## Changes

- Gameplay autoplay applies its chosen idle pose with `advance(0.0)` before the first skeleton
  refresh. Character Editor's `autoplay_default_animation=false` path remains untouched.
- Zero-delta pelvis refreshes reapply current drop without advancing history.
- The modifier's spawn-frame-only initialization establishes shared drop and leg corrections
  together and does not take the loop-seam acquisition bypass. Normal later turns, landings,
  runtime resets and idle loops retain their existing interpolation/rate limits.
- Coordinator passes an explicit `initialize_pose` flag to upper-foot placement. Its existing
  support/stance/reach search chooses the initial destination without an acquisition animation;
  normal calls retain their speed-limited motion.
- Clip messages retain episode throttling and now include frame, ankle/toe-tip identity, actor
  path, animation/time, root and yaw. Future reports can match the trace directly.
- Moved the unchanged horizontal target-path hold into `tools/foot_ik/foot_target_motion.gd`
  to keep the sampler below 1000 lines. It is explicitly **not** a swept-foot-volume check.

## Regression and evidence

```sh
godot --headless --fixed-fps 60 --path . \
  res://tests/manual/foot_ik/foot_ik_spawn_contact_check.tscn --quit-after 140
```

Unlike task 024's settled-idle test, this checks the **startup frames**, at fixed spawn/yaw.
Ankle and toe-tip points are sampled every frame 3–120. Final skinned foot/toe/leaf vertices are
also checked against all eight nearby real box colliders during frames 3–40 (304 mesh samples).
Both depth limits are 0.005 m. Registered in shared and fast runners. No expensive live marker
is created or left enabled.

- Fixed: **PASS**, 118 point frames, point depth `0`, mesh depth `0`, 304 mesh samples;
  stationary and moving zero-delta pelvis invariants both pass.
- Mutation, initial-placement path disabled: **FAIL**, point depth `0.239558 m`, mesh depth
  `0.274809 m`. Mutation restored before broader tests.
- A subtle oracle gap: the older precise `sample()` checks only the collider under the root.
  It returned zero while the toe entered a *neighboring higher tread*. The new fixture uses
  `sample_box_transform()` against nearby box colliders; the existing CSG-box method delegates
  to the same mesh oracle. Do not use root-only ray results to certify adjacent-riser clearance.

Evidence: `/tmp/foot-ik-025.bCAdqv/`, including preserved current trace, targeted diagnostics,
intermediate/final startup runs, mutation and fast/full-suite logs. No preview autoplay.

## Pending

1. Finish fast/full verification and compare quantitative failures, not only known labels.
2. ~~User live confirmation~~ - done: startup clip no longer appears in a fresh live session.
   Commit the startup fix once the fast/full verification above is finished.
3. Investigate the still-open real walking clip found in that same confirmation session (11.3cm,
   right toe, `unarmed_walk`, see Status) - a fresh case, not yet traced. Tasks 019/020 and task
   024's previously noted other-stance clearance side effect remain separate work.
