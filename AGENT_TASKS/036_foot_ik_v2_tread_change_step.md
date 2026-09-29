# 036 - Foot IK v2: a foot that must change tread level needs a real step

Status: OPEN, the hardest remaining v2 bug. Parent: `035_foot_ik_v2.md` (tools, flags, everything
else already fixed). Full history of every attempt: `archive/035_foot_ik_v2_investigation_log_2.md`
items 8-17 (numbers, trace excerpts). Branch `experiment/native-foot-ik`, last commit `7ff496e`.

## The bug in one paragraph

Standing on stairs and turning (or idling while the animation loops), a foot whose animated position
crosses a tread edge has to change level. v2 has only clamp-and-glide pieces for that: a per-frame
floor sample (filtered), a flatten slide, a riser retreat / lift (`_clear_toe`), a sole sink, and a
2.5 cm/frame "step arc" (`foot_ik_v2_stepper.gd`). None of them plans a step. Result, live and in the
fuzz: the foot pops 7-15 cm in one frame, hangs 11 cm (or 37 cm) over a riser, clips 6-9 cm into one,
or keeps re-stepping through a continuous turn ("the foot loop-rotates").

## Evidence and repro (all headless, deterministic)

- Fixed sweeps (in the suite, pass): `scripts/check_foot_ik_v2.sh` runs `--stairs-turn=dz` for
  dz 0, 0.12, -0.12 and the live pose `-1.41:-0.39`.
- Known-open offset (excluded from the suite): `--stairs-turn=0.24` floats ~11 cm for ~10 frames
  (`RISER_MAX_RETREATS` 4 x 1.2 cm gives up, then a 10 cm `toe_lift` onto the next tread).
- Random-pose fuzz: `scripts/fuzz_foot_ik_v2.sh 12 7` (12 poses, seed 7, quick sweep incl. SMOOTH
  turns at 3/8/20 deg/frame). Baseline with the sweep settings FIXED: 12/12 poses fail, ~3 clip
  frames / 6 float frames total, every pose has a one-frame foot move > 0.07 m. A/B rule: compare
  totals with `clip_frames`, `float_frames`, `popped_poses` (awk one-liner in the item 16 run), and never
  change the sweep settings between runs (12-frame holds read 56 float frames on the same code).
- Per-frame tools: `scripts/trace_v2.sh --check --frame N | --track left --from A --to B | --snaps`.
- `TURN_FAULT frame=.. side=.. <reason>` lines name the first fault of each kind per run.

## What was tried (do not retry blindly)

| Idea | Result |
|---|---|
| more riser retreats / bigger retreat step / more clear attempts | moves the failure to other offsets, worse |
| faster (1.5 m/s) flatten-slide glide when unflat | hangs the heel over the riser |
| debounce both sinks 3 frames; rate-limit slide across levels | worse (clip/float frames appear) |
| foot lock (`foot_lock`, world-anchored resting foot) | fixes endless re-stepping but 8x clip / 10x float frames on the fuzz, breaks 2 suite sweeps; left OFF |
| `_clear_toe` re-run after the stepper | swaps float for a 10 cm pop, all 4 suite sweeps fail; reverted |
| shave `ankle_height` 6 mm | the clearance pass just re-adds it |
| stepper trigger 0.10 -> 0.06 m | kept: fixed the live 8-11 cm turn-start pop |

## Round 2 (2026-09-29) - four more attempts, none kept; the failure is broader than the riser

Baseline (sweep settings FIXED, seed 7 x 12, `/tmp`-style awk in item 16): `clip_frames=3
float_frames=6 popped_poses=9-10/12` (the pop metric is now the IK CORRECTION, final foot minus animated
ankle, in the published frame - the body turning/lagging is not counted; it only moved 10 -> 9).

| Idea | Result |
|---|---|
| cap the clearance lift (`MAX_CLIMB` 0.25 per point / total) | per-point cap: clip 3 -> 2, no other change; total cap: clip 16, float 13 (foot left inside the block); reverted |
| riser retreat in the best of 8 directions (a stair edge is SIDEWAYS of the foot) | fixed the 37 cm float at `-0.25:-1.21:26` and clip 3 -> 1, but float 6 -> 32 and the suite turn sweep dz=-0.12 fails; with "old direction unless another clears by 3 cm" the fuzz returns to the baseline and dz=-0.12 STILL fails (19 float frames); reverted |
| hold the clearance lift and release it slowly (1.5 cm/frame) | float 6 -> 109 (the foot hangs on the tread), pops unchanged: the vertical pops are NOT lift flicker; reverted |
| (earlier) clearance after the stepper, foot lock | see the table above |

What the remaining failures actually are (traced frame by frame, seed 7):
1. Mostly the SMOOTH phase: a foot in state `stretched` (the target is out of reach: stance shift 0.15,
   pelvis drop, floor 0.2 m below) whose position jumps 5-14 cm between frames as the stance shift,
   pelvis drop and reach clamp change together while the body yaws. This is the reach / pelvis /
   stance planner (item "stretched foot"), not the tread-change step. A step planner alone will not fix it.
2. A foot straddling the very edge of the stairs (x = +-1.2 of a 3 m wide flight): the rays at the tip,
   heel and ankle land on different blocks by <1 cm, and the clearance pass lifted the foot 36 cm
   (`toe_lift` summed over 8 attempts). Only the multi-direction retreat fixed it and it broke a sweep.
3. The 11 cm class (heel/tip float at a tread): the riser retreat gives up after 4 tries and lifts 10 cm.
Metric caveat: after every yaw snap the body's turn lags for several frames and the sole points, the
ground sample and the animated pose all move; any IK metric on those frames is contaminated.

Decision needed from the user: v2 is a lab experiment next to a working v1. Either (a) accept v2's
stance/reach planner as it is and treat the smooth-turn + straddled-edge cases as out of scope, keeping
the fixed sweeps as acceptance, or (b) invest in redesigning the reach / pelvis / stance planning as one
coherent model (one decision per foot per frame instead of five passes that each re-decide).

## Why (current understanding)

1. The straight glide of the stepper ignores geometry; the riser logic runs BEFORE it, so a stepping
   foot is never cleared, and clearing it after produces the lift-pop.
2. Nothing chooses WHICH tread a re-seated foot lands on or checks it is reachable; the flatten fit
   and the sole sink each decide independently, from different samples, frame by frame.
3. No foot lock: the animated foot swings with the body across treads (and a lock alone runs the leg
   out of reach), so under a turn the floor level under the foot keeps changing.
4. Measurement caveat: a few frames after a yaw snap the feet move up to 8 cm because the body's own
   turn lags (`LookPose` / balance modifiers); that is not IK.

## Plan (next attempt: a step planner)

1. On a re-seat trigger (`|target - foot| > 6 cm` at rest, or a tread-level change), CHOOSE the
   landing spot once and hold it: floor under the wanted spot, sole flat on ONE tread, reach-checked
   (fall back to the nearest reachable flat spot, or to "do not step yet").
2. Execute it as a two-phase motion: lift straight up past the higher tread edge (`max(from, to)` +
   clearance), then move over and lower - never a straight line across the riser.
3. While a step is in progress the riser/flatten/sink passes must not touch that foot (they fight it).
4. Then reconsider the lock: hold only the planted foot, re-plant through the planner.
5. Every step adds a fuzz row: `clip_frames`, `float_frames`, `popped_poses`, `TURN_FAULT` list.

## Acceptance

- Suite unchanged (sweeps dz 0 / 0.12 / -0.12 / -1.41:-0.39 pass, forward walk pass).
- `--stairs-turn=0.24` passes and joins the suite.
- Fuzz (seed 7, fixed sweep): clip_frames <= 3, float_frames <= 6, and popped_poses < 12 (target 0),
  then more seeds. A 3 cm foot move is the ceiling for a non-step frame.
- Live: turning / idling on stairs with no visible foot pop; user confirms before any commit of
  gameplay-visible behaviour (repo rule).

## Notes for whoever continues

- Files: `tests/manual/foot_ik_v2/foot_ik_v2_modifier.gd` (at the 1000-line lint cap; put new code in
  a helper file like `foot_ik_v2_stepper.gd` / `foot_ik_v2_lock.gd`), `foot_ik_v2_lab.gd` (cap too),
  `foot_ik_v2_turn_check.gd` (sweep + guards), `scripts/fuzz_foot_ik_v2.sh`.
- Helpers must be loaded with `preload` constants, not `class_name` (the editor does not register a new
  `class_name` until it rescans: the user hit "Identifier not declared").
- macOS `sed -i` needs a suffix; do not edit by line number after earlier edits shifted them (it
  clobbered function headers twice). Use the Edit tool with unique strings.
- zsh treats `$p:quick` as a modifier: write `${p}:quick` when a script runs under zsh.
