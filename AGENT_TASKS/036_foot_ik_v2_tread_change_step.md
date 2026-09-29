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
