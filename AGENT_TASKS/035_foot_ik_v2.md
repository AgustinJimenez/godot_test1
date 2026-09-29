# 035 - Foot IK v2 from scratch (flat / ramp / step / stairs)

Status (paused): v2 is live-tested and "kinda better" than v1 on ramps and stairs. Most defects the
user reported are fixed and covered by headless regressions; four items are open (below). Isolated
work under `tests/manual/foot_ik_v2/` - `actors/player/foot_ik/` (v1) stays intact as the reference.
The full investigation narrative (numbers, dead ends, every trace excerpt) is archived in
`archive/035_foot_ik_v2_session_log.md` - read it only when a specific detail is needed.

**Git state:** one commit (`0ba09c2`, on `experiment/native-foot-ik`) holds everything up to the
floor-height filter. UNCOMMITTED in the working tree: the ledge-safety airborne fix, plant fade,
body-height smoothing (`body_lag`), slower pelvis growth while moving, the stair speed change in
`actors/player/player.gd`, `_flatten_support`, stairs moved to +x, new trace tools/flags. AGENTS.md says
do not commit gameplay/animation changes until the user confirms live - the user said "kinda better",
never an explicit go on the last batch.

## What v2 is

`FootIKV2Modifier` (`foot_ik_v2_modifier.gd`, a `SkeletonModifier3D` added last) + a pure two-bone
`FootIKV2Solver`, driven by the lab scene `foot_ik_v2_lab.tscn`. Per foot per frame: sample the floor
under the animated ankle (filtered), aim the ankle at floor + sole height, solve the leg, lay the sole
on the surface, re-sample under the landed foot, flatten the sole onto one surface, clear the toe /
tip / heel. Around it: a pelvis drop (deep only at rest), stance narrowing at rest, reach clamping,
plant-weight fade (no hard release), body-height smoothing, published final-pose snapshot for tests.
Tunables are `@export`s at the top of the modifier; each new behaviour has a `--foot-ik-v2-no-*` switch
in the lab for A/B.

## Run it

```sh
scripts/check_foot_ik_v2.sh            # lint + solver + forward walk + ramp strafe + 7 idle/jump regressions
scripts/trace_v2.sh --trace F --segments|--tips|--released|--misses|--snaps|--slide|--vertical|--landing
scripts/trace_v2.sh --trace F --track left --from A --to B   # one foot, frame by frame
scripts/trace_v2.sh --trace F --frame N | --body --step 10   # (add --check for the headless trace)
```
Live trace `user://foot_ik_v2.jsonl`, headless `user://foot_ik_v2_check.jsonl` (never overwrite each
other; every line has `run_id`, `time`, `mode`, animation, heading, reach decision, hips, modifiers).
Lab flags (all after `--`): `--foot-ik-v2-check`, `--foot-ik-v2-ramp-check`, `--foot-ik-v2-idle-check`
with `--ramp-index=0|1|2`, `--start-on-ramp`, `--uphill`, `--stairs`, `--stairs-edge`, `--jump45`,
`--stairs-walk=0|1|2`, `--walk-speed=X`, `--foot-ik-v2-off`. In the live lab: V = camera, F6 = v2 on/off
(the label turns red when off). Orange->green/red spheres on toe tip and heel = touching the real floor.
**Joint angles:** every trace foot has a `pose` block (`foot_ik_v2_pose_dump.gd`): per-joint local Euler
+ delta from rest, knee/hip/shank flexion + abduction, ankle interior, foot pitch/yaw, knee bend-plane
offset, segment lengths vs rest, for the FINAL pose and the pre-IK ANIMATED pose, plus `ik_delta`
(final - animated). Flexion + = knee/ankle FORWARD of the joint above; abduction + = toward the right.
**Perf:** `--foot-ik-v2-perf` (or `FootIKV2Debug.enabled = true`) prints a `[FOOT_IK_V2_PERF]` per-part
usec report every 300 frames (`foot_ik_v2_debug.gd`, v1's begin/end technique). `FOOT_IK_V2_PERF_LOG=1`
adds `[FOOT_IK_V2_ENGINE_PERF]` (fps/process/physics ms, draw calls, node-spawn diff every 60 frames -
`foot_ik_v2_perf_probe.gd`, always attached in the lab, a no-op unless that env var is set).

## Suite state (last run)

PASS: project lint (once the lab is <= 1000 lines - it is at exactly 1000; trim before adding),
solver, forward walk over flat / ramps 15-30-45 / stairs 0.10-0.20, and idle regressions: 15/30/45 deg
across the slope, 45 deg across (`--start-on-ramp`), facing up (`--uphill`), stairs riser (`--stairs`),
stairs edge (`--stairs-edge`), jump on 45 deg (`--jump45`).
**RED: ramp-strafe replay** (`--foot-ik-v2-ramp-check`): tip float 13.5 cm on 20 frames, limit 8 cm.
Cause: the stair speed change (below) also fires on ramps, so the replay (tuned to 1.92 m/s strafe)
now runs at 1.2 m/s with a 1.7x clip; 10 cm / 12 frames even with the ground filter off.

## Open items, in the order to do them

1. **Trailing foot on stairs floats ~10 cm** (56% of planted stair frames "tip up + heel up",
   `--landing`): it stays on the lower tread while the body climbs, the floor is 0.2 m below and
   beyond reach, `reach_when_moving` clamps the leg straight. Try: release a trailing foot that cannot
   reach so it lifts like a real step, instead of clamping it. Check with `--landing` + `--snaps`.
2. **Ramp replay red / stair speed scope**: either re-baseline the replay for 1.2 m/s, or restrict the
   slowdown to real stairs (player.gd cannot tell a ramp from stairs: `has_recent_transition()`).
3. **Riser lift** (`toe_lift` 0.2 m in ONE frame when the tip is in the next riser after 4 retreats of
   1.2 cm) and the retreat/lift flicker - the biggest visible foot snap left on stairs. Rate-limit the
   lift and latch the retreat.
4. **0.35 m stairs are not climbable at stair speed** (the player stops at the first riser below ~2.4
   m/s; `stair035` was dropped from the forward check, terrain kept). Decide whether that matters.
5. **Idle planted foot snap on stairs - FIXED headless, needs the user's live check.** The right foot
   jumped 0.24 m once per idle loop (~150 frames) while reading `at_target`. Cause: `_plan_stance`'s
   stance shift is searched in 5 cm candidates and followed instantly, so it flipped 0.10 <-> 0.15 as
   the idle animation nudged the foot (a 4.5 cm snap; the older 0.24 m one was the same flip at a
   deeper shift). Fix: a shift that still brings the foot within reach is KEPT (hysteresis) instead of
   re-searched. The same hysteresis is in `_flatten_support` (`_support_last`): its 2 cm slide
   candidates flipped every ~150 frames (the "still moves a few cm, many times" report). Idle after
   the spawn settles: worst per-frame foot move 0.24 -> 0.002 m; only the spawn landing (f2, f62)
   still moves (`trace_v2.sh --snaps` after a plain `godot --headless --fixed-fps 60 --quit-after
   1000 ... foot_ik_v2_lab.tscn`). Dead ends: a 2-frame loop-seam hold (removed), rate-limiting the
   final target (broke the walk), rate-limiting the stance shift growth (10 cm floats in the
   uphill/stairs-riser regressions). The trace's `shift` column is the STANCE shift.
Also: ramp-walk reversals rose (9-20 -> ~40) after the body/pelvis changes, unexplained; flat walking
still skates 0.44 m per step (the clip vs 3.2 m/s mismatch that stairs had) - not addressed.

6. **Right foot floats 8-10 cm at rest on stairs (both spheres red) - FIXED headless (reproduced at
   the lab's interactive spawn `(4.61, 0.80, -0.05)` yaw -84.2, plain idle, no sidestep needed).**
   The foot straddles the step-8/9 edge (heel over 0.90, tip over 0.80). `_flatten_support` slid it
   12 cm onto the LOWER tread (nearest fit), but the target stayed at the aimed 0.90 height and the
   ground filter ignores tread-sized re-sample differences, so the foot hung 10 cm up and the leg was
   already at full reach. Fix: (a) the slide search now prefers a fit on the surface the foot was aimed
   at (`aim_y`), falling back to the nearest; (b) `_sink_to_sole_level` (at rest): a sole flat on one
   surface >= `SINK_MIN` 4 cm below the aimed height re-aims straight down from where the foot IS.
   Result: clearance 0.109/0.100 -> 0.027/0.018 (`trace_v2.sh --frame N`).
   (c) FOLLOW-UP at the new spawn `(4.61, 0.80, -0.05)` yaw -84.2 (the user's next log): the slid foot
   was 2.5 cm out of reach (`stretched`, tip 3.2 / heel 2.3 cm up; the pelvis plan samples under the
   ANIMATED ankle, not where the flatten puts the foot). Fix: a resting `stretched` foot adds its
   residual to the pelvis drop, held until the next move (`_stretch_hold`); now 1.5 / 0.6 cm. A
   reach-limited slide search was tried and was WORSE (8.7 cm up: no flat fit left). Sphere
   changes: radius 3 -> 1.5 cm, `TOUCH_ABOVE` 0.04 -> 0.022 (a 3 cm float used to read green).
   Ramp-strafe replay float frames 12 -> 16 (still red), not caused by these.
7. **Whole sole floats a uniform ~6-9mm at rest (user: "small gap between the feet and the floor
   below") - FIXED headless, needs the user's live check.** A live-skin mesh scan (temp probe, same
   technique as below) found EVERY vertex on the sole floating 6-9mm at rest, even though
   `_clear_toe`'s own toe/tip/heel points already read <=2mm clear - those points are RIGID rest-pose
   offsets applied to the current bone pose, and a GPU-blended mesh (foot+toe weights mixed) does not
   exactly follow them. Shaving `ankle_height` by the measured 6mm was tried and made it WORSE
   (heel_clr 0.006 -> 0.021 m at one frame) because `_clear_toe` reacted to the resulting toe
   penetration and over-corrected; reverted. Real fix: `_sink_to_true_sole` in `_clear_toe` - once the
   three rigid points are clear, do a full live-skin scan (`_foot_mesh_points(..., live=true)`, the
   same walk `_measure_sole_depth`/`_measure_heel_local` do at REST, now with `get_bone_global_pose`)
   for the TRUE lowest vertex and sink to `SOLE_GAP_TOLERANCE` (1mm) of it. Gated to AT REST ONLY
   (`not _is_moving`) - ungated it clipped the forward-walk and idle regressions (tip clip 0.10 m on
   ramp45). At rest: idle tip_float_max improved across the board (e.g. 0.020->0.013, 0.015->0.004,
   0.021->0.016 m). No regressions: full `check_foot_ik_v2.sh` suite unchanged (same PASS/FAIL as
   before, ramp-strafe replay's pre-existing float failure only, its clip stayed within limits).
   **PERF (user report) - FIXED, verify live.** `_sink_to_true_sole` cost ~8.5ms/call (measured with
   `Time.get_ticks_usec()`, v1's technique - v1 also has `foot_ik_debug.gd`'s begin/end profiling and
   `tests/manual/foot_ik/foot_ik_perf_probe.gd`'s engine-wide counters, opt-in via `FOOT_IK_PERF_LOG`;
   v2 has neither yet). Cause: it called `find_children` over the whole character + `surface_get_arrays`
   (a full mesh copy) every physics frame at rest, for both feet - ~17ms/frame, over the entire 60fps
   budget alone. Fix: `_cache_sole_vertices` does that walk ONCE per leg in `_build_legs`, storing each
   foot/toe-weighted vertex's per-bone contributions (bone id, weight, bind-local point);
   `_eval_sole_points` replays them cheaply (`_measure_sole_depth`/`_measure_heel_local` now also use
   it, at rest). Verified: 8500us -> 255us/call (33x). Suite re-run identical to before the perf fix.

8. **Turn-in-place regression + fixes (user: right foot popped while standing; "fix it permanently, v1
   had rotate-a-few-cm tests").** `--foot-ik-v2-idle-check --stairs-turn=<dz>` (`foot_ik_v2_turn_check.gd`)
   stands on the stairs and steps the yaw 2 deg / 10 frames through 360 deg at `dz` m along the treads,
   grading tip/heel clip + float against the real surface and the max ONE-FRAME foot move
   (`foot_step_max`). It reproduced the live log exactly (heel_clr -0.084, toe_lift 0.10, float 0.116).
   Root causes found and fixed: (a) `_clear_toe`'s riser retreat always backed the foot up along
   -forward, even when the HEEL was the point in the riser behind it (made it worse) - it now moves
   AWAY from the deepest point; (b) `_sink_to_true_sole` sank to the single lowest vertex against ITS
   floor, but the lowest vertex can be the toe overhanging a lower tread - it now takes the smallest
   gap over the sole-level vertices (each against the floor under it); (c) the 2 cm flatten-slide
   glide (item on idle loop) only glides while the applied slide is still flat AND on the same
   tread level as the wanted one - otherwise it snaps (gliding across a riser hung the heel 11 cm).
   **STEP ARC (done, item 8 follow-up):** the remaining pop (a turn across a riser re-seats the flat fit
   on the other tread: foot 0.28 m in ONE frame, plus dz=0.24 floating 11 cm and dz=-0.12 clipping
   6 cm) is fixed by `FootIKV2Stepper` (`foot_ik_v2_stepper.gd`): a RESTING foot (planted, not moving,
   was planted last frame - a landing is not a step) is re-seated at most 2.5 cm/frame with a 5 cm
   lift arc. Tracked in ROOT-RELATIVE space so a teleport or the body's own travel is never a step.
   `debug_stepping` tells the lab to skip tip/heel grading and the ankle-error check for that foot
   (a stepping foot floats by design). All four `--stairs-turn` offsets (0, 0.12, 0.24, -0.12) now
   PASS with clip 0.000 / float 0.021, and `foot_step_max` fell 0.28 -> 0.059 (limit 0.07 in
   `foot_ik_v2_turn_check.gd`; tighten toward 0.04 if the arc is made smoother). Forward-walk check
   PASS (ankle_err 0.046); the ramp-strafe replay is still red on float, unrelated. Caveat: while a
   step is in progress the foot is graded as skipped, so a step that never finishes would hide a
   float - the sweep would then show large foot travel, not silence. Dead ends before this:
   debouncing both sinks 3 frames (worse), rate-limiting the slide across levels (heel floats).

9. **Foot vibrated on rotate (user) - FIXED; and a masking hole found.** `FootIKV2Stepper` stored the
   lift arc INSIDE its remembered path, so the foot was always >= LIFT (5 cm) from where it was
   heading, never got within a step's distance, and "walked" forever (median foot move 0.024 m/frame,
   1098 reversals) - the vibration. Now the path is kept without the lift. Also: `TRIGGER` 0.10 m -
   only a big re-seat becomes a step; the pelvis-stretch hold ignores a stepping foot (it had
   ratcheted the drop to 0.4 m: legs bent); the stepper's foot-step / stepping-share guard in
   `foot_ik_v2_turn_check.gd` (a foot stepping > 15% of the sweep fails - the tip/heel/ankle grading
   skips stepping feet, which is exactly how the endless stepper passed every check; verified the
   guard FAILS the old stepper). **This un-masked dz=0.24**: at that offset the toe/riser clearance
   gives up after RISER_MAX_RETREATS (4 x 1.2 cm) and lifts the foot 10 cm onto the next tread
   (toe_lift 0.106, heel/tip float ~11 cm for ~10 frames). Tried 8-10 retreats / 0.02 step / 12-14
   attempts: moves the failure to other offsets (heel float 0.116 at dz 0, 0.12, -0.12) - WORSE, so not
   kept. dz=0.24 is excluded from the suite (KNOWN OPEN); 0, 0.12, -0.12 run.

10. **Right knee bent BACKWARD (user: "see the right leg pose?") - FIXED, guarded.** The trace `pose`
    block showed knee_offset_forward -0.17 m (knee behind the hip-foot line), hip flexion -27 deg,
    shank +23: the solver takes the bend direction from the ANIMATED knee projected off the new
    hip->target line, and when the foot moves a long way in (stance shift 0.2 + pelvis drop) that
    projection swings behind the leg. `FootIKV2Solver.solve` now falls back to the rest pole
    whenever the animated bend points against it (a knee never bends backward). The old solver
    fixture (`knee_stays_on_animated_side`) actually asserted the backward fold, so it was changed
    to a consistent knee and a new `knee_never_bends_backward` case was added. Turn sweep now
    guards it too (`KNEE_BACK_LIMIT` 3 cm, `FootIKV2PoseDump.knee_behind`); verified the sweep FAILS
    with the old solver at dz=0 and PASSES with the fix.

11. **Joint limits (user asked how v2 stops unnatural joint motion) - added, v1's approach.** v2 had
    only exact bone lengths + reach clamp + the rest-pole knee; no flexion / swing / speed limits
    (v1: `max_knee_flexion_degrees` 150, `max_hip_swing_degrees` 100 cone, per-joint degrees/sec in
    `_limit_correction`, a negative-knee guard, and `foot_ik_joint_limit_check.gd`). Now
    `FootIKV2Solver.solve` takes optional `max_flexion_deg` (min reach from the interior angle: the
    foot falls short rather than fold) and `max_swing_deg` + `down` (the knee swung back into the
    cone); modifier exports `max_knee_flexion_deg` 150 / `max_hip_swing_deg` 100 (0 = off), `down`
    taken in skeleton space. Solver check has cap cases for both. `FootIKV2PoseDump.pose_fault`
    (knee behind the leg line > 3 cm, flexion or swing over the modifier's own caps + 1 deg) feeds
    the turn sweep as a failing 9.9. **NOT done:** joint angular SPEED limits (v1 has them), an
    ankle/foot angle limit, and enforcing `pose_fault` in the forward-walk / ramp checks (only the
    turn sweep grades it). The stepper is the only rate limit v2 has, and on the foot position only.

12. **Joint speed limit + pose_fault everywhere (follow-up to item 11).** `foot_ik_v2_joint_limiter.gd`:
    v1's `_limit_correction` idea - a joint's correction (rotation away from the animated pose, per
    bone, global space) may change at most `joint_speed_deg` per physics frame, AT REST only (`_aim`
    in the modifier; a bone not corrected last frame restarts unlimited, so a released swing foot or
    a teleport is never dragged). Measured: the sweep legitimately changes a joint up to ~70 deg in
    one frame (riser events), so 12 and 30 deg/frame broke it (clip 0.10 m / float 0.12 m) and 60
    passes: it is a FLIP guard (3600 deg/s), not smoothing - v1's 90-120 deg/s is far tighter and
    would need the stepper/riser handling to slow down first. `pose_fault` is now graded by EVERY
    lab check: the forward walk (`faults=` in its line, must be 0) and all idle/ramp replays (the
    `foot_step_max` limit defaults to 9.0, a fault reads 9.9). Verified it fires: with the solver's
    backward-knee guard removed the forward walk reports faults=2 and FAILS. Still not done: an
    ankle/foot angle limit.

13. **Foot "loop-rotates" on a fast turn (user) - FIXED.** The log: yaw -177 -> 123 deg in ~6 frames,
    right foot walked 41 cm in the world at 2.5 cm/frame then stopped, repeating each turn.
    `FootIKV2Stepper` was fed WORLD-relative positions, so a body turn (the animated foot swings
    with it) read as a big re-seat and the foot was dragged behind the body as a "step". The stepper
    now works in SKELETON space (`_limit_step`), so the body turning/travelling carries the foot
    with it and only a genuine re-seat of the foot against the body is a step. Regression: the turn
    sweep continues with 9 big 40 deg snaps (`idle_snap_*`, 14 frames each); verified it FAILS with
    the old world-space stepper (foot_step_max 0.148 > 0.07) and passes now. Also removed the
    `to_world` parameter from `_limit_step`.

14. **Left foot pops 8-11 cm at the START of a turn (user, live log) - FIXED, reproduced at that pose.**
    Log: yaw 87 -> 83 deg, left foot `support_shift` -0.10 -> 0.00 in ONE frame, foot 0.113 m. It is
    the flatten slide re-seating when the body turns (the applied slide stops being flat), and the
    step arc's `TRIGGER` (0.10 m) let an 8-11 cm re-seat straight through. `TRIGGER` -> 0.06 (0.04
    also passes; the ramp-strafe clip did not change). Tried first: a faster glide for the unflat
    slide (1.5 m/s) - it hung the heel 11 cm over the riser at several offsets, reverted. Repro:
    `--foot-ik-v2-idle-check --stairs-turn=-1.41:-0.39` (dz : x along the stairs, = the live pose
    root (4.61, -0.05)); with the old TRIGGER it FAILS (foot_step_max 0.080 > 0.07), now passes and is
    in the suite. The turn sweep now starts at the live yaw (`START_YAW_DEG` 87.4) and the
    interactive default spawn rotation is 87.4 too (position was already the live one).
    The earlier "could not reproduce a smooth turn" caveat still holds for a MOUSE-continuous turn;
    the sweep uses 2 deg steps every 10 frames and 40 deg snaps.

15. **Random-pose fuzz (user: "drop the character at random spots / rotations headless") - built, it
    FAILS a lot (that is the finding).** `scripts/fuzz_foot_ik_v2.sh [trials] [seed]` drops the
    character at random (x in +-1.3, z along the 0.10 m stairs) with a random yaw and runs the QUICK
    sweep (`--stairs-turn=dz:x:yaw:quick`): fine yaw steps, 40 deg snaps, and SMOOTH turns (3/8/20
    deg per frame, both ways = the mouse-turn case). Deterministic per seed, prints the pose to
    repro. Seed 7, 12 poses: 10 fail. Classes seen: (a) `stepping 41 frames in a row` - during a
    continuous smooth turn the foot re-steps forever (the user's "loop rotates": v2 has no foot lock,
    the animated foot swings with the body across treads, so the floor under it and the flatten fit
    keep changing); (b) `foot moved 7-15 cm against the body in one frame` at smooth-turn start /
    tread crossings (support-shift / sink re-seat under the 6 cm stepper trigger or repeated); (c)
    heel/tip CLIP of 6-9 cm in smooth turns; (d) heel/tip FLOAT 11 cm (riser, same as dz=0.24) and
    once 37 cm at x=-1.21 z=0.63 - a foot hanging over a riser. **Not fixed.** Two measurement bugs
    found on the way: the pose-fault check mixed a NEW skeleton yaw with OLD published poses (fixed:
    `FootIKV2Modifier.final_basis`, the transform the poses were published with) and the one-frame
    foot check used world position (a turning body legitimately carries the foot 14 cm/frame at 20
    deg/frame: now foot-vs-hip in the published frame). Also `pose_fault` now judges the knee
    against the rest bend direction projected off the leg (what the solver promises), not the body
    facing. The stepping guard is now "> 40 frames in a ROW" (was a share of the sweep). The suite
    still runs only the fixed sweeps (no smooth phase), so it stays green; the fuzz is the tool.
    Next: a real FOOT LOCK / step-when-needed model for turns, or accept the animated foot follows.

16. **Foot lock experiment (user: "let's try") - built, MEASURED WORSE, left OFF.**
    `foot_ik_v2_lock.gd` + export `foot_lock` (default false): a resting foot is held at the world
    position where it was planted (the animated ankle's XZ is replaced by the anchor's), and re-plants
    - which the stepper walks as a step - once the animated ankle drifts 0.25 m from it or the anchor
    is > 0.32 m from the hip (out of reach). It did remove the endless re-stepping in smooth turns
    (`stepping N frames in a row` gone), but on the same fuzz (seed 7, 12 poses, quick sweep) the
    totals were OFF: 3 clip frames / 6 float frames vs ON: 25 / 60, and it breaks two suite
    regressions (turn sweep dz=0 clip 0.008, and the live pose -1.41:-0.39 float 0.116). Why: the
    held foot is often out of reach as the body turns (`reach_clamped` floats/clips of 11-37 cm),
    and a stepping foot crosses risers along a straight line and then gets a 10 cm `toe_lift` from
    `_clear_toe` (which runs BEFORE the stepper). Ideas not tried: run the clearance pass after the
    stepper, plan the re-plant target on the floor under the NEW spot with a reach check, a larger
    stance (hold both feet, step the farther one). The turn check now measures the WORLD foot again
    (with a lock a resting foot must hold still) and the stepping-run limit is 120 frames. `--stairs`
    smooth turns remain open (item 15); every fuzz seed still fails 12/12 on the one-frame foot pop.

17. **Clearance pass AFTER the stepper (item 16 idea) - tried, WORSE, reverted.** `_clear_toe` re-run
    on the stepped foot (target set to the stepped spot): fuzz seed 7 clip frames 3 -> 2, float
    frames 6 -> 6 (no change), but ALL FOUR suite turn sweeps fail (`foot_step_max` 0.132 > 0.07: the
    clearance lifts/retreats the stepping foot 10 cm on the frames it crosses a riser, i.e. it
    swaps the float for a pop). Not committed. Also learned: the fuzz's quick sweep undersamples -
    holding each yaw 12 frames with 8 settle frames (instead of 6 / 2) makes the same code read 56
    float frames instead of 6, and the first graded frames after a yaw snap are contaminated by the
    body's own turn lag (feet move up to 8 cm for a few frames after a snap: a measurement effect,
    not IK). Any A/B on the fuzz must keep the sweep settings fixed. What is left is the riser
    problem itself (items 8-9, 15-17): a foot that has to change tread level needs a real step
    (lift, then land on the other tread), which v2's clamp-and-glide pieces do not model.

## Uncommitted in the working tree (2026-09-28, needs the user's live verdict)

- `foot_ik_v2_modifier.gd`: a trailing foot that cannot reach its surface is RELEASED to step instead
  of clamped (`reach_clamp_plant_min` 0.85; 1.0 = old), plus the two idle hysteresis fixes above.
- `foot_ik_v2_lab.gd`: interactive spawn moved to the reported idle pose `(4.47, 0.99, -0.73)` on
  Stair010. The yaw `-57.3` does not stick (the third-person start resets it); position only.

## Findings worth keeping (root causes, each verified with numbers - details in the archive)

- **A one-frame target reposition is invisible to float/clip/slide**: a planted foot that jumps 0.24 m
  in one frame reads `at_target` with zero float and zero planted-slide (it is on its - moving -
  target the whole time). For "the foot moves while idle" reports, grade per-frame MOTION
  (`trace_v2.sh --snaps`: foot m/frame and knee-rot deg), not just contact.
- **Measurement**: bones read from a node's `_process()` / `skeleton_updated` are stale (12 cm+ off);
  read the modifier's published `final_pose` (end of its last pass). Every early number was wrong.
- **v1 turns itself back on** every landing (`set_character_grounded`); use `set_debug_enabled(false)`,
  not `active = false`, or v1 + v2 fight and v1's pelvis drop pulls the hips 0.6 m down on ramps.
- **The player's ledge safety** pushes the root toward a "safe landing" at 3 m/s while falling
  (`landing_correction_speed`, from v1's ground sampler): jumps on a ramp slid the character 1.6 m.
  The lab zeroes only that airborne push (keeps the edge clamp).
- **The game pins the visible body to the capsule** (`_body.position.y = _body_rest_y`); the stair
  "hover" only moves the third-person camera arm (`stair_hover_speed` has no effect on the body). The
  capsule steps up a whole tread in 2-3 frames, so the body popped ~10 cm per step. v2 now lowers the
  pelvis by a first-order body lag (`body_follow_rate` 8/s, `body_max_lag` 0.18).
- **Foot skating on stairs = speed vs step-rate mismatch, not IK**: body 1.92 m/s with the clip at
  0.6x. A foot lock was tried and removed (the near-straight leg reaches only ~0.25 m horizontally).
  Stairs now: speed 1.2 m/s (`stair_walk_speed_scale` 0.375), clip at speed / 0.7 (`STAIR_STEP_SPEED`),
  slide per planted step 0.67 -> ~0.1 m.
- **Floor height flips between treads every frame at a tread edge** (0.20, 0.00, 0.20...) and the foot
  chased each flip = the stair jitter. Filtered per foot: a higher level at once, a lower one after 3
  frames, slopes followed exactly; also applied to the re-sample under the landed foot.
- **A swinging foot must fade out, not release**: the instant release snapped it 0.2-0.3 m.
- **`ankle_height` was the bone rest height (0.0865), the measured sole is 0.096** - every foot sat
  9.5 mm into the ground. The toe's sole point is `toe bone + sole * toe_depth` (1 cm), not 9.6 cm.
- Plan/act must sample the floor from the same height (the plan sampled from the un-lowered ankle, the
  floor flipped "implausible" at 0.45 m, and it chased a tread instead of squatting).
- Idle on steep ramps needs BOTH a stance shift toward the body and a deep pelvis drop (0.23-0.36 m);
  while moving the drop is capped (0.06) and grows slowly (0.25 m/s), releases at 0.6 m/s.
- The toe / tip / heel clearance pass grades three points; a penetration > 4 cm is a riser: retreat
  first, lift only if that fails. The heel is measured from the mesh (`heel_local`).

## Harness traps (do not re-discover)

- Grade only feet meant to be down, but at rest grade EVERY foot (a "mid-swing" excuse hid a 7 cm float).
- A cold spawn at the failing pose can be clean; replay the history (run, jump, walk/stop) instead.
- The headless check teleports between surfaces: skip the frame after a teleport in any per-frame metric.
- The lab file is at the 1000-line lint cap and `player.gd` is at exactly 1000: trim comments first.
- Do not analyse traces with inline Python or edit files with scripts; use `trace_v2.sh` (add a flag
  to `scripts/analyze_v2_trace.gd` if a field is missing) and the Edit tool.
- Copy the live trace out before running anything headless if it matters (separate files now, but the
  next live run overwrites the live one).
