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
