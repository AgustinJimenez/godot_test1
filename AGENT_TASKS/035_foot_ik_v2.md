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
Also: ramp-walk reversals rose (9-20 -> ~40) after the body/pelvis changes, unexplained; flat walking
still skates 0.44 m per step (the clip vs 3.2 m/s mismatch that stairs had) - not addressed.

## Findings worth keeping (root causes, each verified with numbers - details in the archive)

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
