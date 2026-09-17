# 030 — Planned stair swings

## Status (2026-09-17)

**Open. The airborne solve path is now proven to change the rendered gait, but the prototype
regressed clipping/smoothness and was removed.** Retained changes improve the stair lab's final-pose
recording and diagnostics. No gameplay change from this attempt remains, and no live acceptance is
claimed. Existing uncommitted 025/028 changes were preserved byte-for-byte.

Goal: choose a real destination tread at takeoff, then move the foot upward and forward in one
smooth swing. This remains paired with 025 (clipping) and 028 (joint discontinuities).

Earlier attempts and their superseded hypotheses are in
[archive/030_stair_swing_arc_attempts_1_to_7.md](archive/030_stair_swing_arc_attempts_1_to_7.md).
In particular, the old closing instruction to override only X/Z is obsolete.

## Reliable measurement now retained

`tests/manual/foot_ik/foot_ik_stair_lab.gd` previously sampled raw skeleton poses from its ordinary
physics callback. Those are not guaranteed to be the modifier's final output. It now records in
`_process()`, requires `has_fresh_final_bone_poses()`, deduplicates physics ticks, and uses the final
cache consistently for recorded bones, ankle/toe positions, trails, clip checks, and joint deltas.
Each JSONL row includes `physics_frame`; per-foot diagnostics include `solve_observed`,
`solve_target`, `owner_name`, and `plan_reason`.

`--lab-check` exits after recording and reports `STAIR_LAB_CAPTURE_CHECK`: sufficient samples,
reaching the top, and no missing physics ticks. This checks capture integrity, **not** whether
the gait is acceptable. Registered in the shared check list and fast suite.

```sh
godot --headless --fixed-fps 60 --path . \
  res://tests/manual/foot_ik/foot_ik_stair_lab.tscn --quit-after 1200 -- --lab-check \
  > /tmp/task030_lab.log 2>&1 || true
python3 scripts/trace_query.py --trace /tmp/task030_lab_baseline.jsonl lab \
  --compare /tmp/task030_arc7.jsonl
```

The new `trace_query.py lab` command reports all-capture versus stair-region metrics, solved versus
released swing counts, and matched-frame toe-path differences. Comparison assumes the same replay
inputs; the stair-region split is specific to this lab (`root.z >= -0.8`).

## What the complete prototype established

A separate optional planner ran after **both** per-leg sampling branches, so missing-contact legs
could no longer skip planning. It populated complete airborne entries, kept destination support
distinct from the in-air waypoint, bypassed the contact-only finalization/release gates, and sent
the planned point through candidate evaluation/commit. The experiment was off by default.

Unlike earlier null attempts, final toe positions changed substantially, and active arc frames
reported actual solves. **Further work does not need to rediscover the target injection point.**

But four coupled requirements remain:

1. **Single swing ownership / stance transfer.** Allowing both low-weight legs to start together
   created two simultaneous swings. Serializing them helped ownership but exposed transfer timing.
2. **Reach at arrival, not only at takeoff.** With a 0.32 s swing and measured root travel about
   2.39 m/s horizontal + 1.39 m/s upward, the body moves about 0.76 m forward and 0.45 m up during
   one swing. The rig's leg length is only about 0.888 m. A supported destination can be unreachable
   by the time the foot is supposed to plant.
3. **Planner coverage.** Extrapolating the hip and rejecting unreachable destinations removed the
   large new clips, but only the first right-foot swing remained active (20 frames). A nearly clean
   capture with one planned swing is not success for the full staircase. Increasing the scan range
   engaged one landing per leg but brought back clips.
4. **Real landing confirmation.** The prototype's `progress == 1` branch fabricated contact to
   request support transfer. That is not a valid final architecture: a constrained/rate-limited foot
   may not actually reach the destination. Transfer must observe the final foot near the supported
   destination, while root travel and the opposite stance remain feasible.

A shorter 0.22 s swing introduced an 11.56 cm clip near the first riser. Merely adjusting duration,
a sine lift, or chain-weight ramp does not resolve the ownership/reach timing problem.

## Measured results

Same live Player, same 0.35 m staircase and input sequence, 179 captured frames. Stair-only metrics
exclude the existing approach-floor startup episode (3.27 cm over nine frames).

| Variant | Stair clip max | Joint max | Coverage |
| --- | ---: | ---: | --- |
| Starting working tree / corrected recorder | 0 mm | 50.12°/frame | Legacy; 54 swing-owner frames released |
| Independent simultaneous arcs | 25.14 mm | 79.08°/frame | Both legs driven; rejected |
| One-at-a-time arcs, current-reach destination | 207.30 mm | 62.00°/frame | Stale destination behind body; rejected |
| Future-reach filter, narrow scan | 0.56 mm | 48.55°/frame | Only first right swing; insufficient |
| Future-reach filter, wider scan | 65.33 mm | 56.17°/frame | One landing each; rejected |

Last experiment's stair joint p95 was 25.91° versus baseline 26.81°; the worse maximum and new
penetration still reject it. Final toe-path differences reached 0.75 m left / 0.62 m right:
the route was effective, not inert.

Artifacts: `/tmp/task030_lab_baseline.jsonl`, `/tmp/task030_arc1.jsonl` through
`arc7.jsonl` (selected variants), and `/tmp/task030_experiment_20260917/` (last experimental
source snapshot; temporary evidence, not installed code). Previous user lab log preserved at
`/tmp/task030_prior_lab_20260917.jsonl`.

## Next implementation boundary

Design takeoff, destination, arrival time, opposite stance retention, and touchdown confirmation as
one step transaction. Validate future reach for **both** legs over the entire swing, and distinguish
an unsupported moving foot from a supported planted foot throughout coordinator and pelvis policy.
If the requested root speed cannot fit a feasible step, explicitly handle that condition rather than
declaring the airborne target a contact or silently dropping later steps.

Use the corrected lab to require repeated left/right step coverage, no missed solves while the
planned owner is active, actual supported touchdown before transfer, no new stair clips, and bounded
final joint changes. Keep experiments gated until these pass, then request the user's visual test.

## Verification of retained changes

Pending final capture and fast-suite results for this continuation. No interactive scene autoplayed;
all verification runs are headless and terminate.

## 2026-09-17 continuation: retained changes verified, prototype restored, 2 targeted fixes null

Verified the retained batch (the "pending" part): `scripts/check.sh` green, `STAIR_LAB_CAPTURE_CHECK
PASS samples=179 gaps=0`, `scripts/check_foot_ik_fast.sh` 26 pass (only the known task-019
failure), and `trace_query.py lab` works.

Restored the experimental prototype from `/tmp/task030_experiment_20260917/` (the new
`foot_ik_stair_swing_arc.gd` planner + the modifier/coordinator hooks + the `stair_swing_arc` flag),
gated OFF by default - it is the proven starting point for the redesign, not shipped behaviour.
Reproduced the recorded numbers (flag on): stair clip 65.3 mm / 2 frames, joint p95 25.91 / max
56.17 deg/frame, coverage left 40 solved : 6 released, right 52 : 0.

Then tried two of the four requirements in isolation - both null or worse:

- Requirement 4 (real touchdown: only declare contact once the FINAL solved foot is within 5 cm of
  the destination): clip 65.3 -> 68.4 mm, joint 56 -> 62. Worse, because the foot often never
  arrives (requirement 2), so the transfer never fires at all.
- Requirement 2 (fit the swing duration to the root speed so the stride stays within leg reach):
  identical output - no effect in this capture.

The residual clip sits on the PLANTED foot (`owner = live_contact`) at f154-155 right AFTER a
planned swing contacts - i.e. the planned step's own contact/plant is the regression source. So
requirements 1 (single-swing ownership/stance transfer), 2 (reach at arrival) and 4 (real
touchdown) are genuinely coupled; single-requirement patches do not work. This confirms the doc's
"design it as one step transaction" boundary - no further single-lever attempt was made.

The prototype remains in the tree (gated off); the whole batch is uncommitted.

Also tried narrowing the destination scan (`SCAN_COUNT` 20 -> 6) hoping to reproduce the doc's
0.56 mm "narrow scan" case: instead the planner found **no destination at all** and the run collapsed
to the flag-off baseline (stair clip 0 mm, joint p95 26.81 / max 50.12). So the scan range is a real
tension (too narrow = no coverage, wide = clips), not a free win - another sign the fix must be the
coupled step-transaction design, not a constant. Restored the prototype's original constants.

## 2026-09-17 continuation 2: riser-based landing helps the clip, handoff spikes remain

Took over the redesign. Replaced the prototype's "scan for any higher surface" destination with a
geometry-based one: walk forward until the surface steps up (the riser), then land a fixed 0.18 m
inset onto the new tread (deterministic, well-placed), with reach validated at arrival.

- Result: stair clip **65.3 -> 23.8 mm** (a real improvement), both legs still covered - but joint
  p95 **26.8 -> 43.5** and max **56 -> 80** deg/frame (worse). Net not shippable.
- Slowing the swing weight ramp (`smoothstep(0.0, 0.25, progress)` -> `0.6`) did **not** change the
  joint spikes, so the ramp/duration is not the cause.
- The worst joint frames are all solved `stair_swing_prediction` legs (f120 80 deg, f134 79 deg):
  the discontinuity is at the **animation <-> solved-arc handoff** (takeoff and touchdown), not
  inside the arc. Replacing the authored swing with a solve changes the knee/hip solution even when
  the foot position matches, so the pose jumps at both ends.

**Next concrete piece:** blend the solved swing with the animation across its boundaries (takeoff
and touchdown) - ramp over the *pose*, not just the target/weight. That is the missing
requirement-1/4 coupling. Reverted to the gated prototype original (clean baseline).

## 2026-09-17 continuation 3: the spike is not the boundary - it is the solve under a moving target

Implemented the target-boundary blend (follow the authored animation early, diverge later) - a
**no-op** on the prototype's numbers (65.33 mm / 56.17 deg; the prototype already starts at the
foot). Then logged the per-frame ankle vs solve target around the worst frame (riser variant):

```
f119 worst=8.1  ankle y=0.837  tgt y=0.835
f120 worst=80.1 ankle y=0.873  tgt y=0.827   <- ankle 4.6cm ABOVE its own target
f121 worst=12.7 ankle y=0.860  tgt y=0.815
```

So mid-arc the **solved leg is above its own target and the solve corrects downward hard in one
frame** - a knee/regime reaction (the same family as 028's planted constraint flip: 028 found the
40-180 deg spikes are the `clamp_negative_knee`/`constrain_knee_direction`/`solve_to_support`
handoff). It is not a takeoff/touchdown boundary artifact and not the weight ramp.

**Conclusion:** the redesigned swing inherits 028's core discontinuity - the solve is not stable
under a moving, airborne target. Fixing 028's regime handoff (make it continuous) is a prerequisite
for the planned swing; the two tasks are coupled. Reverted the blend; prototype restored, gated off.

I've reached the point where further work is the 028 regime-continuity fix, not 030-specific code.

## 2026-09-17 scaffold: the step-transaction prototype is live-iterable

The prototype is restored in the working tree - `actors/player/foot_ik/foot_ik_stair_swing_arc.gd`
plus its modifier/coordinator hooks and `FootIKDebug.settings.stair_swing_arc` - and is gated **OFF**
by default (no behavior change when off). The stair lab's panel now has a
"030 stair step-transaction (experimental)" checkbox bound to that flag, so it can be A/B'd live:

- flag OFF (shipping): lab baseline stair clip 0.0000 m, joint p95 26.81 / max 50.12 deg.
- flag ON (prototype): stair clip 0.0653 m, joint p95 25.91 / max 56.17 deg, both legs solved.

`STAIR_LAB_CAPTURE_CHECK` passes in both states. Usage: launch the lab, tick the box, press
"Rebuild + Record", then scrub/compare; `trace_query.py lab` prints the A/B metrics.

To iterate the design: this is where the step transaction goes (lift-and-plant the support/swing foot
onto the next tread as one motion so its toe never enters the riser, then the 025 retry stops firing
and the 028 jank goes with it). All the dead ends found so far are listed above - do not re-try them.
Uncommitted (part of the WIP batch); commit after live confirmation.

## 2026-09-17 Path A + support-transfer lift: near-solution

- Path A: driving the walk with the retargeted Mixamo stair clip (`--stair-clip`, see 031) improves
  both lab metrics vs the flat clip - stair joint max 50.12 -> 36.14 deg, overall clip 0.0327 ->
  0.0100 m.
- With the 025 retry OFF (`--no-toe-retry`) the joints become flat-walk smooth (**12.00 deg/frame**)
  but the clip is 9.2 cm, on the **support foot once per step** during the support transfer's
  straight lerp onto the next tread.
- Fix (in `_apply_support_contact`): lift the transfer over the step with a sine arc (gated to flat
  treads, only when the target rises > 2 cm). No-retry clip **9.2 -> 1.8 cm**, joints unchanged at
  12.00; with the retry on it is neutral (clip 0.0100, jank ~37.5). Fast suite unchanged (26 pass,
  only task-019).
- So stair clip + no retry + transfer lift = **1.8 cm clip / 12 deg joints** vs the flat-clip
  baseline's 0 stair clip / 50 deg. The residual 1.8 cm is mostly the stair clip running on the
  FLAT approach (the lab uses it everywhere) plus small first-step residuals; in game the flat
  region would use the flat clip.
