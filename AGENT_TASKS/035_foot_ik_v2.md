# 035 - Foot IK v2 from scratch (flat / ramp / step / stairs)

Status: v2 baseline exists and its own suite runs; the user's live verdict is "no visible
improvement" over v1. The ramp cross-slope case is red. Isolated work under
`tests/manual/foot_ik_v2/` - `actors/player/foot_ik/` (v1) stays intact as the reference.

## Why

v1 grew to 20 runtime modules / ~6.8k lines and could not be tuned into a clean stair walk
(025/028/030/031). v2 restarts the problem with one responsibility per file, one behaviour per
check, and every acceptance test written as the behaviour is added.

## Current handoff

**What works.** v2 drives the real player: per-foot ground ray + analytic two-bone solve +
sole-to-surface alignment. Its own checks pass walking flat / ramps 15-30-45 / stairs
0.10-0.20-0.35 forward (`FOOT_IK_V2_CHECK PASS`, worst ankle-to-target 0.0003 m, sole tilt 0.0).

**What does not.** The user's scenario - stand on the closest ramp, strafe left <-> right - is
red: `FOOT_IK_V2_RAMP_CHECK FAIL  float_max=0.87  toe_clip_max=0.117`. A/B of the worst frames
shows they are on feet v2 **releases to the animation** (`out_of_reach` / `mid_swing`), not on
feet it corrects - so the current corrections are not where the visible defect is.

The user reports no visible improvement over v1 live, and that is the correct reading: the mask,
walkable gate, edge probe, resample and toe-clearance passes added this session did not change
the live result.

## Suite

```sh
scripts/check_foot_ik_v2.sh
#  PASS project checks
#  PASS FOOT_IK_V2_SOLVER_CHECK   pure two-bone maths, 6 assertions, no scene
#  PASS FOOT_IK_V2_CHECK          forward walk over all 7 surfaces
#  FAIL FOOT_IK_V2_RAMP_CHECK     replay of the user's live ramp session (see below)
```

The ramp check is a scripted replay of the user's real live session (trace-derived): body turned
~99 deg across ramp15, strafing DOWNhill (left) / UPhill (right) in four passes plus a final idle,
graded per segment by the orange toe-tip sphere (toe bone + 3.5 cm forward, v1's definition)
against the real ramp: pass = tip clip <= 2 cm and float <= 8 cm on a foot meant to be down.
Baseline with v1 truly off: `tip_clip_max=0.013 tip_float_max=0.191` (5 clip / 150 float frames of 473); hips stay 0.85-0.93 above the root. Remaining: floats of ~18 cm around the downhill->pause->uphill switches (frames ~308-325) and a 4-5 cm clip on the uphill swing (`out_of_reach`). Live trace fields (`animation`, `move_angle_deg`,
`v2_enabled`, `tip_*`, `surface`) are in `user://foot_ik_v2.jsonl`; headless runs write
`user://foot_ik_v2_check.jsonl` so they never overwrite a live trace. V toggles the camera,
F6 toggles v2. Older text below describing the check as cross-slope strafing is superseded.

The ramp check is independent of the modifier: the harness casts its own ray from above the body
so it finds the **real ramp** (not the floor beneath it) and compares the sole/toe points against
that surface. Trace: `user://foot_ik_v2.jsonl` (v1's writer and schema, readable by
`scripts/trace_query.py`).

## Live "left foot floats at idle across the ramp" - reproduced headless, fixed by pelvis drop

Live last frame: idle at mid-ramp, body across the slope, left (downhill) foot `released`/
`out_of_reach` with its tip 4-8 cm above the ramp for 400+ frames, right foot planted. Cause: the
downhill foot's floor is 0.944 m from the hip against a 0.887 m leg, so v2 gave the foot back to
the flat-ground animation. `--foot-ik-v2-idle-check` replays the session (run, jump onto the ramp
side, walk/stop/walk/stop, 450 idle frames): with `--foot-ik-v2-no-pelvis-drop` it FAILS (455 float
frames, up to 7.5 cm); with the pelvis drop (`max_pelvis_drop`, lowers the pelvis by the shortfall
for feet the animation plants) it PASSES (0 float frames). It is in `check_foot_ik_v2.sh`.
Trap that hid it for a while: the grader skipped any foot more than 5 cm off the surface as
"mid-swing"; idle segments now grade every foot. Known side effects still open: a 38 cm float on
the leading foot at the start of a downhill walk, and a few clip frames on the uphill swing.
Steeper ramps: on 30 deg the downhill foot's ankle sits >25 cm over the slope, which the old
`mid_swing` test (`animated ankle - ground > max_lift`) called a swing foot - never corrected, pelvis
drop blocked (live log: 21 cm float, 190 idle frames). `_is_swinging` now also requires the ankle
to be lifted above the character's own floor level. On 45 deg the drop needs ~0.36 m
(`max_pelvis_drop` 0.40); that squat is only allowed at rest: while moving faster than
`still_speed` the drop is capped at `moving_pelvis_drop` (0.06) and grows at `pelvis_attack_speed`
(before this the body sank 0.2-0.4 m during ramp strafes). Idle checks: 15/30 deg via the jump
replay, 45 deg via `--start-on-ramp` (the jump cannot reach it); all in `check_foot_ik_v2.sh`, all
PASS. Ramp-strafe replay: 31 float frames (was 150), hips 0.72-0.79 above root while walking.
Facing UP the 45 deg ramp (live log): the rear foot's floor was 1.16 m from the hip even after a
0.29 m drop -> released, toe 14 cm / heel 28 cm above the ramp (headless: 28.8 cm float). Fixes:
(1) at rest a planted foot is brought in toward the body (`max_stance_shift` 0.30, `_plan_stance`),
which raises the ground under it, and the pelvis drops only for what is left (idle squat 0.36 ->
0.23 m); the plan uses the re-sampled target `_resample_and_correct` will chase (on a steep slope
that second floor is ~7 cm further), which is why the first version still floated 7 cm;
(2) `ankle_height` is now the MEASURED sole depth (0.096), not the bone rest height (0.0865): every
foot used to sit 9.5 mm into the ground (heel read -1 cm on flat); (3) the toe clearance pass grades
the toe, the shoe's tip and the heel (`heel_local`, measured from the mesh). The lab grades the heel
too (`HEEL_CLIP_TOLERANCE`), and idle checks now: 15/30 deg across, 45 deg across, 45 deg facing up
(`--uphill`) - all PASS (float <= 1.5 cm). Ramp-strafe replay: clip 5 frames <= 1.7 cm (limit 2),
float 44 frames up to 20 cm (limit 8) - still red, the leading foot when walking DOWNhill is
released (`out_of_reach`) and hangs; forward check still red (stair035), but tip clip frames
119 -> 38 and float frames 346 -> 31.

Live last frame on the 0.10 m stairs (`--stairs`): the shoe tip poked 2.5 cm into the next riser and
the clearance pass, which raycasts from above, read it as "the toe is under a tread 10 cm higher" and
lifted the WHOLE foot 10.6 cm (`toe_lift`), leaving the heel 10.6 cm above its own tread. Now a
penetration over `RISER_PENETRATION` (4 cm) first slides the foot back off the riser (4 x 1.2 cm),
and only lifts if that does not clear it (tall steps, as before). The lab no longer grades a heel
that overhangs an edge (surface under the heel/toe > 7 cm below the foot's) as a float.

Foot off the SIDE of the stairs over the floor 0.38 m below (`--stairs-edge`, live last frame): it
hung 30 cm up. Cause was a flip-flop, not reach: the pelvis-drop plan sampled the floor from the
UNlowered ankle (0.454 m up -> floor "implausible", `max_surface_drop` 0.45) and found the stair
tread via the edge probe (drop 0.03), while `_place_foot` sampled from the lowered ankle (0.41) and
found the floor. The plan now samples from the same lowered height. It then squats 0.32 m and both
feet touch. Also new: a planted foot that is still out of reach reaches as far as the leg goes
(`reach_when_still`, `reach_when_moving`) instead of being released for a frame or two to the
animation's height - that alone turned the ramp-strafe replay green (clip 0, float 5.6 cm) and cut
forward-check tip clip frames 38 -> 0. The forward check stays red on `ankle_err` (0.36 @ stair035),
which grades the solver residual and is large by design for a clamped reach - a stale metric to
rework, not a visible defect. Idle regressions (all in `check_foot_ik_v2.sh`): ramp 15/30/45 deg
across, 45 deg across (`--start-on-ramp`), 15..45 deg facing up (`--uphill`), stairs tip against a
riser (`--stairs`), stairs edge with one foot on the floor (`--stairs-edge`).

Jumping on a steep ramp (live log: "what is moving the character while jumping?" - v2's own pelvis
drop): `moving` was horizontal speed only, so a jump from standing counted as "at rest" and the deep
squat re-fired in the air and on landing (drop 0.10 -> 0.40 m and back frame to frame, hips 0.24-0.64
above the root). Jumping now counts as moving (airborne, |vy| > 0.5, or a `jump` clip playing), which
caps the drop at `moving_pelvis_drop`. `--jump45` fails without it (`--foot-ik-v2-jump-not-moving`,
excess 0.20) and passes with it. Needs a live look.

Forward check reworked (now green): its `ankle_err` graded the foot against the FIRST target, so every
resample / riser retreat / toe-heel lift read as a miss (0.36 @ stair035); the modifier now measures
against the final target and flags `clamped` feet, which the lab skips (0.058 worst, limit 0.06 - the
45 deg uphill leg is at full extension). It also now gates on tip clip (<= 2 cm) and tip / heel float
(<= 8 cm), and walks 90 frames per surface instead of 150 (past ~96 the character walks off the top of
the ramp and falls, which is not graded). Result: clip 0, float 5.7 cm. `--foot-ik-v2-off` shows what
the gate catches. `trace_v2.sh --misses` lists corrected feet > 3 cm from their target.

## Harness traps found this session (do not re-discover)

- **v1 Foot IK turns itself back on every landing** (`PlayerFootIKModifier.set_character_grounded`
  sets `active = grounded`), so `active = false` in the lab left v1 AND v2 running together; v1's
  pelvis drop pulled the hips 0.6 m down on every uphill pass (the user's "hip does not go up
  anymore, broken pose"). Use `set_debug_enabled(false)`, which sticks. The trace records
  `body.modifiers_active` and `body.hips_above_root` (normal ~0.9) so this is visible.

- **Reading `Skeleton3D.get_bone_global_pose()` from a node's `_process()` returns the WRONG pose
  (not the modifier's output): 12 cm median / 68 cm max off for the foot.** Every earlier lab/trace
  number was measured on that stale pose (ramp replay: 247 tip-clip + 153 tip-float frames, v2 looked
  worse than v2-off). The lab now snapshots poses in the `skeleton_updated` signal (fires after every
  modifier) and reads `_pub(bone)`; with that, the same replay is 6 clip + 28 float frames (v2 off:
  38/39). Never sample bones outside that signal / a modifier-published snapshot.
- The toe's sole point is `toe_bone + sole * toe_depth` (toe bone rest height, ~1 cm), NOT
  `ankle_height` (9.6 cm): the wrong value made the toe-clearance pass lift every foot ~7 cm.

Each of these produced a confident, wrong number before being found:

- `Skeleton3D.get_bone_global_pose()` is **relative to the skeleton, not the world** - convert with
  `skeleton.global_transform` for every ray/target/measurement. Casting a ray at the raw pose
  samples the wrong place as soon as the character is off the origin.
- A `SkeletonModifier3D` publishes in the skeleton's **deferred** update, after a node's
  `_physics_process`. Sample the pose in `_process` (or after publication), or you measure the
  pre-correction pose.
- A harness that **recomputes** world-space values can disagree with the modifier's skeleton-space
  result and report a perfectly aligned foot as 60-127 deg off. Grade the modifier's own
  authoritative values (`residual`, `align.after_deg`) instead of restating the logic.
- The sole contact point is `bone_origin + sole_dir * ankle_height` (the sole is **below** the
  bone). Subtracting puts it above and inflates every "float" by `2 * ankle_height`.
- Grade only **grounded** feet (either the animation or the result is near the surface). Grading a
  swing foot's distance-to-ground is meaningless and produced false floats.
- `ankle_height` is the **measured sole depth** from the skinned foot mesh in the rest pose
  (0.0960), not the foot bone's rest height (0.0865). The mesh read needs the
  `find_bone(skin.get_bind_name(bind))` fallback because the bind bone index comes back -1.

## Next steps

1. **A/B v1 through the identical ramp-strafe scenario** and diff the two runs - v1 works on ramps
   in its own preview, so the difference is the answer, not more reasoning.
2. **Fix the released-foot path**: a foot v2 leaves to the animation (`out_of_reach`/`mid_swing`)
   is where the remaining toe clip and float live. Decide whether v2 should correct it, or why the
   animation clips there.
3. The ground ray can still sample the floor instead of the ramp near edges; an inward edge probe
   (v1's) was added but is unverified.

## Known-kept in v2

mask `1 | (1<<5)` + walkable-normal gate (v1's), out-of-reach release, per-frame pose snapshot,
`round`-free per-foot state (`released`/`at_target`/`stretched`), the pure solver split, and the
v1-format trace.
