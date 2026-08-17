# Active Task: Stair Foot IK

**Checkpoint branch:** `experiment/native-foot-ik`

## PICK UP HERE (2026-08-16, handoff to a fresh agent)

Read the bottom-most sections first (most recent), not top-to-bottom - this file is
ordered chronologically and old entries above are superseded.

**Confirmed clean, safe to build on:** `locomotion_mode` defaults to `LEGACY`, no debug
prints or marker files left anywhere, full regression suite (`check_foot_ik.sh`,
`check_foot_ik_locomotion.sh`, `check_foot_ik_ramp_sweep.sh`) matches its pre-session
baseline everywhere except the improvements below. Nothing here is committed yet - see
`[[feedback-commit-after-manual-test]]`: do not commit until the user manually confirms
in-game.

**Three real, verified fixes landed this session** (all in `player_foot_ik_modifier.gd`
and `foot_ik_stair_predictor.gd`, all still active by default in `LEGACY`):
1. `support_transfer_blend_time` - smooths the once-per-step pelvis/foot pop when stair
   support hands off between feet (was an instant snap).
2. `step_down_transition_lift` - fixes toe clipping through a tread's edge mid-transition
   during a step-down settle (gated off `_landing_grace_time` so it doesn't touch
   ordinary jump landings).
3. `chain_weight` desync fix in `_apply_support_contact()` - a leg could read
   `ground_weight=1.0` (full commitment) while its `chain_weight` (which actually drives
   hip/knee rotation in `foot_ik_leg_solver.gd`) stayed stale at an earlier, often-zero
   value. Real bug, confirmed and fixed, but NOT the cause of the open issue below.

**Open, unsolved, exactly where to continue:** user still sees real clipping after all
three fixes. Live-traced it (see the "Third real fix" section below, its final
paragraphs) to the *ground target itself* landing ~0.15-0.18m below the true tread
surface during an idle stance near a stair edge - the leg is correctly, faithfully
reaching for a wrong (too-low) point, not failing to reach at all. Prime suspect:
`_step_down_classification()`'s "settle" path in `player_foot_ik_modifier.gd`, which
calls `_retract_to_reachable()` (same file) - that function walks a raycast search point
horizontally from the ground target toward the hip looking for a reachable surface, and
likely picks up a lower/wrong surface along that path for this specific stance. Not yet
confirmed why - next step is the same live-trace-first method used all session (see
`[[feedback-check-engine-source-before-hand-deriving]]`-style discipline: read the actual
JSONL/print data before theorizing): reproduce via `foot_ik_preview.tscn`'s
`foot_ik_stair_walk_marker` (temporarily edit its walk-then-stop behavior in
`tests/manual/foot_ik/foot_ik_preview.gd` - safe to freely modify/revert, no automated
script depends on it), run headless, read `user://foot_ik_controlled.jsonl`, add targeted
temporary `print()`s in `_retract_to_reachable()`/`_step_down_classification()` if the
trace alone isn't enough, remove them before finishing.

**Also live in the codebase but not part of this specific bug hunt:** two extra,
switchable `LocomotionMode` experiments (`RESIDUAL_STAIR`, `PHASE_LOCKED`), both off by
default, both documented dead-ends/partial-experiments - see their own sections below.
Don't confuse work on those with the `LEGACY` fixes above; they're unrelated code paths.

## Void dangle re-floats after standing still (2026-08-15, fixed — awaiting manual acceptance)

**User report (live):** after the void-dangle fix below, the hanging leg still floats —
but only once the player stops moving and stands still for a moment.

**Cause:** the game's "stop touching a planted foot once it's been still a while" freeze
was overriding the dangle fix. The freeze locks the foot's position and skips the
dangle's full-reach calculation, falling back to a calculation that always adds a small
cushion (meant for standing naturally on flat ground) — which pulls the foot back up and
looks like floating again, a second or so after the player stops.

**Fix (`player_foot_ik_modifier.gd`):** a foot hanging over a void is now never allowed
to freeze — same 4-line pattern already used for a deeply-penetrated foot (right above
it in the code): if it's about to freeze while over a void, un-freeze it instead.

**Verified:** `check.sh` and the full `check_foot_ik.sh`/`check_foot_ik_locomotion.sh`
battery match the existing baseline exactly (same pre-existing parked failures, no new
ones). Not committed — awaiting live confirmation that standing still over the edge no
longer re-floats.

**Follow-up (same day): full-reach dangle still looked wrong.** Even fixed, a fully
extended leg over a void looks like it's touching an invisible floor — the user compared
it to a diagram of "handling a foot with no ground under it" and wanted the far-away case
(no ledge in reach) to read as a relaxed hang, not a leg reaching for a specific point.

**Tried and reverted: shortening the reach.** `VOID_DANGLE_REACH_RATIO := 0.7` in
`player_foot_ik_modifier.gd` shortened the dangle to 70% of full leg reach so the knee
stayed visibly bent. Live result (user report): worse, not better — the skin mesh
stretched and the foot bent at a strange angle, reading as "foot resting on an invisible
step/rock" instead of "leg reaching for an invisible floor." The leg solver isn't built
to stop cleanly partway through its reach the way it handles a full stretch, and any
single precisely-aimed point (short reach or full reach) still reads as touching
something. Reverted back to full-reach dangle (the last known-working state from the
freeze fix above). Battery re-run after revert, identical to baseline.

**Tried: let the leg relax instead of reaching for any point.** Once genuinely out of
reach, the leg no longer gets a computed target at all: `ground_target = foot_pos` (its
own animated position), so the leg simply follows its natural animated pose with no IK
correction — same as any other unsupported leg, per the "really far away" case in the
user's reference diagram. This let the existing ordinary "contact lost" weight-decay path
take over naturally (removed the `void_overreach` force-full-weight branch from
`foot_ik_gait_tracker.gd`, no longer needed) and removed the now-unused
`_toe_down_normal()`/`VOID_DANGLE_PITCH_DEG`. Battery re-run after the change, identical
to baseline. Live result: foot just sits at normal standing height over the void instead
of dangling down at all — user called it "floating". **Parked for now** (user's own
words: "let's leave the other thing for now") in favor of the edge-avoidance work below;
not committed, not reverted either — it's the current state of the void case.

## Nudge predicted stair landings away from tread edges (2026-08-15, first pass)

**User's idea:** rather than reacting after a foot ends up somewhere bad (over a void,
straddling a riser), predict ahead of time where the swinging foot is about to land and,
if that's right at a tread's edge, nudge the landing point toward the middle of the tread
(or a neighboring tread) before the foot actually gets there.

**Where this plugs in:** `foot_ik_stair_predictor.gd` already predicts the landing tread
for a swinging leg (forward raycast ahead of the foot, latched once a higher surface is
found — `_desired_swing_lift()`'s `state.latched_target`). This is the natural place to
correct the landing spot, since the target is already computed before the foot arrives.

**First pass implemented:** `_clear_landing_point()` checks, right when a landing point
is latched, whether the tread surface still continues a small safety margin
(`EDGE_SAFETY_MARGIN = 0.06m`) forward and backward along the travel direction (two extra
downward rays). If only one side reads as "same tread," nudge the landing point that
direction by the margin. If both sides are edges (a tread narrower than the margin) or
both have room already, leave it alone.

**Scope of this first pass:** only nudges within the same tread. Relocating to a
different tread height entirely (the user's "could be the lower or higher step") is a
bigger follow-up, not done yet — it would mean picking a different swing target height
mid-flight, which affects the swing-lift arc, not just the landing X/Z.

**Battery (2026-08-15):** `scripts/check.sh` PASS. `check_foot_ik.sh`: identical to
baseline (STRETCH/AIRBORNE/POSE_CONTINUITY/STAIR_SETTLE PASS; BODY_PENETRATION and
STAIR_LOCOMOTION FAIL are the pre-existing parked reds, same sample counts).
`check_foot_ik_locomotion.sh`: all cases match baseline exactly (same two pre-existing
parked reds `crouch_back`/`crouch_walk_to_sprint`). `check_foot_ik_ramps.sh`:
`failed_cases=0`, same parked `reported_left_deep_clip` red. `check_foot_ik_ramp_sweep.sh`
(run directly — `rg` isn't on PATH here, see the script's own note): 2579/6240 failed,
0.148881m max depth — matches the parked baseline exactly. No regressions.

**Live result / bug found:** user reported the foot looked like it was "stepping on some
sort of invisible step instead of the actual step" while walking. Root cause: the nudge
moved the landing point sideways but kept the *original* height instead of re-sampling
the true surface at the new spot — close enough during the edge check (within
`step_min_rise`) but often still visibly off the real tread, floating the foot slightly
above or below it. Fixed: the nudge now uses the actual raycast hit position from the
edge probe (`_sample_same_tread()` returns the real surface point, not just a
yes/no check). Battery re-run after the fix, identical to baseline. Not committed —
needs another live look on the stairs.

## Speed up walk-to-idle foot resettle (2026-08-15)

**User report:** after stopping (walk to idle), the feet take a noticeable moment to
settle into the correct place.

**Tried and kept: `smooth_rate` 7.0 to 10.0** in `player_foot_ik_modifier.gd` (how fast
the raycast-derived foot target itself catches up to the true ground point). Tested
alone: body penetration 23/5314/0.164 vs baseline 22/5345/0.167 — noise-level, not a
real regression. Full locomotion suite unchanged (same two pre-existing parked reds).

**Tried and reverted: `ground_weight_rise_time` 0.24s to 0.14s** (how fast the corrected
pose blends in once a target is found). This one measurably hurt stair body penetration
(22 to 29 samples, depth 0.167 to 0.270m) — letting a swinging leg snap to full
correction faster means it can dig into the next tread before a landing is actually
confirmed. Reverted back to 0.24. Do not lower this without also revisiting stair swing
timing.

**Kept: `smooth_rate = 10.0` only.** Battery re-run with just this change, matches
baseline. Not committed — needs a live look at how walk-to-idle feels now.

**Tried and reverted: `smooth_rate = 16.0`.** User asked to push it further; this broke
the ordinary `walk` locomotion case (added rotation on `LeftLeg` during normal walking,
not just at the walk-to-idle transition — `FOOT_IK_LOCOMOTION_CHECK FAIL case=walk`).
16 is confirmed too fast. Reverted to 10.

**Correction (2026-08-15): `smooth_rate = 10.0` was NOT actually safe either.** It
passed `check_foot_ik.sh` and `check_foot_ik_locomotion.sh`, but the dense ramp sweep
was never re-run for it at the time — a real gap, now fixed by habit. Re-checking later
in the same session (while diagnosing the stair swing-lift fix below) found it
regressed the sweep from the known baseline 2579/6240 to 2809/6240 failed cases.
**Reverted to `smooth_rate = 7.0`** (the original, fully-verified value) - the
walk-to-idle resettle speed is back to where it started; that request is unresolved.
Any future attempt at this knob must run the FULL five-entrypoint battery (including
the dense ramp sweep) before calling it safe, not just the two most obviously-related
checks.

## Swing-phase body/foot penetration on stairs (2026-08-15, first pass)

**User ask:** the known-parked `FOOT_IK_BODY_PENETRATION_CHECK` failure (foot/toe
visibly clipping into the tread mid-swing) - "let's fix that first."

**Diagnosis.** Captured a fresh `STAIR_FOOT_TRACE` and found a concrete mechanism: the
swinging leg's predictive lift height (meant to clear the upcoming tread by
`step_clearance_margin`, 0.11m) is computed in world space, but the shared pelvis sink
(`shared_drop`/`_smoothed_shared_drop` in `player_foot_ik_modifier.gd`) - which exists
to keep the OTHER, support leg from over-stretching - lowers BOTH legs' hip together
afterward, since they share one pelvis bone. That silently eats into the swinging leg's
own clearance margin: a frame was found with `ground_weight=1.0`, a latched next-tread
target at y=0.7, `step_lift=0.067`, yet the actual rendered ankle sat at y=0.355 (barely
above the CURRENT tread, not the predicted one) - the pelvis sink had quietly consumed
the lift meant to clear the riser, and `foot_r`/`ball_r` vertices penetrated up to 9cm.

**Fix (`foot_ik_stair_predictor.gd` + `player_foot_ik_modifier.gd`):** the swing-lift
clearance calculation now adds back last frame's `_smoothed_shared_drop` (passed in as
`pelvis_sink`, bundled into `update_swing_lift()`'s existing flags-dict parameter to
stay under the linter's argument limit), so the lift still clears the tread by the full
margin even after the pelvis sinks. **Gated to flat stair treads only**
(`latched_normal.dot(UP) >= STAIR_TREAD_UP_DOT`, the same signal
`_toe_probe_reaches_higher_surface()` already uses to tell stairs from ramps) - first
attempt without this gate looked fine on `check_foot_ik.sh` but silently regressed the
ramp sweep, misdiagnosed at first as caused by this fix before isolating it back to the
unrelated `smooth_rate` change above; the gate itself made no measurable difference to
the sweep once `smooth_rate` was correctly reverted, confirming this fix is ramp-safe
independent of that other issue.

**Result:** an improvement, not a full fix. `FOOT_IK_BODY_PENETRATION_CHECK`:
penetrating_samples 22→21, penetrating_vertices 5345→4901, max_depth_m 0.167→0.132.
Full battery otherwise identical to baseline (`check_foot_ik_locomotion.sh`,
`check_foot_ik_ramps.sh` `failed_cases=0`, ramp sweep 2579/6240 - all unchanged). The
underlying limitation this doesn't address: the swing-lift's own ramp-up
(`step_lift_rate`, 4.0 m/s via `move_toward`) can still lag behind a fast step early in
a swing, and the true fix for that (and the remainder of the penetration) is still the
already-documented "proper stair-climb blend/IK system," not another quick tweak.

**Not committed — awaiting live confirmation** the clipping looks less severe (it will
very likely not look fully fixed; check against the numbers above, not a visual-zero
expectation).

## Toes clip while standing on stairs and slowly turning (2026-08-15, diagnosed, fix attempt reverted)

**User report:** stand still on the stairs, slowly rotate in place - the foot tips clip
into the step.

**Diagnosis, confirmed via a fresh `foot_ik_controlled.jsonl` capture.** A mechanism
called `stationary_noop`/`preserve_idle_pose` exists so a genuinely still, flat-ground
foot doesn't twitch from ordinary per-frame correction noise - it includes an
unconditional bypass whenever `is_body_turning()` is true, on the reasoning that a foot
turning in place should just trust the raw animated pose rather than fight it frame by
frame. That reasoning breaks down when the raw animated pose doesn't match the actual
standing height - e.g. one foot on a stair landing (y=1.2), the other a tread below
(y=1.0). Captured frame: `ground_weight=1.0`, `step_down=false`, the correctly-computed
plant target sat at y≈1.25-1.3, but because `is_body_turning` bypassed the correction
entirely, the rendered ankle landed at y=1.107 instead - the raw idle animation's own
height, ~15-19cm below where it should be, sinking the foot into the tread.

**Two fix attempts, both reverted - this remains unfixed.** (1) Requiring the raw pose
to already be close to the computed target (vertical-only distance) before letting
`is_body_turning` bypass fire: broke ordinary flat-ground turning instead
(`FOOT_IK_TURN_TARGET_CHECK` regressed from `worst_added_deg=1.82` to `43.6`) - a turn
clip's own natural per-frame foot bob already exceeds a tight closeness margin, so this
gate rejected the bypass even with no stairs involved, letting real per-frame IK
correction fire and produce a visible snap the bypass exists specifically to prevent.
(2) Only rejecting the bypass when the two feet's targets are at meaningfully different
heights (straddling two tread levels - the more targeted, "should only matter on
stairs" signal): regressed the exact same check by the exact same amount, which is
suspicious enough (identical to three decimal places) that the dedicated turn-in-place
test rig likely doesn't have stable/comparable ground_target data in the first place
(consistent with an existing documented note elsewhere in `AGENTS.md`: pure rotation
barely moves the animated pose, so relying on any live geometry signal during a turn is
inherently noisy in this specific harness) - meaning *any* added condition on the
turning bypass currently breaks that test, not just an imprecise one.

**Reverted to the original one-line bypass** (`frozen or is_body_turning(side) or (...)`,
no added condition) - confirmed `FOOT_IK_TURN_TARGET_CHECK` back to PASS
(`worst_added_deg=1.82`) and the rest of the battery unaffected. The stairs-turning clip
reported live is real and still present; a safe fix needs to either fix
`FOOT_IK_TURN_TARGET_CHECK`'s own test rig to have reliable ground data during a turn
(so a real gate can be validated against it), or find a different signal than "is this
turning" to distinguish the two cases. Not attempted further this session.

## Stairs back-edge void dangle (2026-08-15, fixed — awaiting manual acceptance)

**User report (live):** walking to the back edge of a landing (tested on the Stairs
0.20m platform, top landing `y=1.2`, 1.2m drop to the floor; same mechanism applies to
the 0.35m stairs at `x=15`), the foot "snaps a lot and still floats" once over the edge.

**Reproduction:** `user://foot_ik_controlled.jsonl` (762 frames, rewritten each launch)
captured the live test: the player walked to the landing's back edge (`z=4.1`), the
right foot went past it (`z≈4.4`) over the 1.2m void while the capsule stayed on the
landing. `smoothed_target.y` stayed pinned at `1.200` (the landing surface) with the
foot rendered at ankle `y≈1.296`, knee bent (`shin` leg angle 28.8°) — visually
"floating". Meanwhile `ground_weight` decayed at frames like `f346` (with
`step_down=true`, `contact_lost=0`, `vertical_velocity=0.000` — the exact trigger was not
conclusively identified; correlates with walk/idle animation switches and
`animation_discontinuous=1` loop seams at `f344/f357/f413/f424`, with the user pushing
forward `(0,-1)` and strafing `(-1,0)` against the edge).

**Two root causes:**

1. **"Still floats" — the dangle override never ran.** The old code only applied the
   dangle inside `if classification["settle"]:`. `_step_down_classification()` returns
   `plant:true/settle:false` when
   `needed_sink = (hip.y − ground_target.y) − max_vert <= step_down_pelvis_drop (0.35)`;
   with the target parked on the landing surface (`tgt.y=1.200` = landing top), needed_sink
   ≈ 0 → `settle=false` → the override was skipped every frame, and the foot just hovered
   at the landing height with a bent knee. (This also invalidated the earlier assumption
   that `over_void` always implies `settle`.)
2. **"Snaps a lot" — sampler-dive vs classification feedback oscillation.** Once
   `_smoothed_ground_weight` dropped below `PLANT_LOCK_WEIGHT (0.95)`, the ground sampler
   eased `_smoothed_target` toward the void floor at `target_max_speed` (10 m/s →
   ≈0.167 m/frame @60fps). The dived target made `needed_sink` grow, `settle` flipped true,
   the dangle snapped the target back to ≈1.24, `settle` flipped false, the sampler dived
   again — a ~3–4 frame cycle. `shared_drop` pelvis-sink chased the dive: rendered hip
   bobbed 1.87↔2.10, rendered right foot bobbed y≈0.95 (near the void floor)↔1.25 — the
   visible 0.3m snapping.

**Fix (in `player_foot_ik_modifier.gd` + `foot_ik_gait_tracker.gd`):**

- Decouple the void dangle from the classification entirely. Compute
  `void_dangle = over_void and not frozen and step_down_static_streak >= 4` (the same
  stationary gate as before) and **re-assert the dangle every frame while true** — the
  sampler's dive never takes hold, so classification/shared_drop never flap. `over_void`
  requires the primary contact to be *beyond leg reach*
  (`animated_contact_distance > upper_length + lower_length`, ≈0.89m), so a genuine swing
  over a void still arcs normally instead of being yanked to max reach, and nothing in the
  stair walker or flat locomotion can ever satisfy it (their contacts are <0.16m).
- `ground_target = dangle` (no `+ smoothed_normal * effective_offset`): the ankle itself
  reaches full extension; the sole-depth offset previously kept the knee bent and the
  ankle hovering just below the authored pose — indistinguishable from floating.
- Force full plant weight while dangling: new gait flag `void_overreach` → in
  `foot_ik_gait_tracker.gd` `elif void_overreach: raw_weight = 1.0` (analogous to
  `frozen`/`penetrating_contact`), so the walk/idle foot cycle or weight decay cannot
  release the dangle mid-cycle.
- Guard the `landed` handler (`if landed and not void_dangle:`) so the landing reset
  (`_smoothed_target = raw_target` = void floor) can't fire while dangling.
- Skip `update_swing_lift` while dangling (`if step_prediction_enabled and not
  void_dangle:`).

**Expected live result:** target pinned at the true dangle
(`hip.y − max_vert` ≈ 1.238 for the 1.2m void), no hip/foot oscillation, ankle fully
extended, toe below the ankle into the void (`_toe_down_normal`), `ground_weight ≈ 1.0`.
Note: the overlay's `pitch_deg` field is a misleading measure for this rig (constant
95.6°); judge toe-down by `toe_tip.y` vs the ankle `foot_pos.y` (≈0.07–0.12m below during
the stable phase confirms `_smoothed_normal` is being applied by the solver's
`_compute_new_foot_basis_world`, `foot_ik_leg_solver.gd:183-184`).

**Battery (2026-08-15):** `scripts/check.sh` PASS (modifier.gd back to 997 lines,
under the 1000 ceiling). `check_foot_ik.sh`: STRETCH (138, 0.0)/AIRBORNE (62)/
POSE_CONTINUITY (0.014027)/STAIR_SETTLE (30) PASS; BODY_PENETRATION FAIL
(22 samples / 0.167048 m — pre-existing parked XFAIL) and STAIR_LOCOMOTION FAIL
(steps=0 — pre-existing parked stale step-detection). `check_foot_ik_locomotion.sh`:
all PASS except the two pre-existing parked reds `crouch_back` and `crouch_walk_to_sprint`
(+ its MATRIX). `check_foot_ik_ramps.sh`: matrix FAIL is the intentional-red wrapper,
`failed_cases=0`, single `reported_left_deep_clip` FAIL is the parked terminal-face case.
`check_foot_ik_ramp_sweep.sh`: 2579/6240 failed / 0.148881 m max depth — matches the
parked baseline. (Note: the sweep script's `rg` filter requires ripgrep on PATH; it was
absent here, so the scene was run directly with the same args.)

**Not committed — await live manual acceptance:** stand at a landing's back edge over the
void for ~15s and confirm: no snap/bob, the foot dangles at full leg extension, toe-down
into the drop, no floating hover, and weight stays pinned.

## 0.20m top-edge idle straddle (2026-08-15, fixed — awaiting manual acceptance)

**User report:** at the top of the 0.20m stairs, standing idle with one foot over the
second-to-top tread, the right leg visibly floated above the step it should stand on.

**Reproduction (headless marker, since reverted):** spawn the real `Player` at the 0.20m
stairs' bottom (`Vector3(12.5, 0.05, -0.8)`, rotation `PI`), walk forward until
`root.z >= 2.92`, then release. Root settles at `z≈3.29` with the right ankle at
`z≈2.97` over the step-4 tread (`tgt_y=1.0`) while the toe tip reaches onto the step-5
tread (`top_y=1.2`). The primary contact ray's toe probe reads
`animated_contact_distance ≈ 0.000` (the toe already touches the next higher tread), so
`_step_down_classification()` bailed at `contact_distance <= GROUND_CONTACT_DISTANCE`
before ever considering the ankle's real ~0.19m clearance over the lower tread — the foot
stayed at its authored float height with `ground_weight=0`.

**Fix (structural, not the earlier blanket variant):** the classification call site in
`player_foot_ik_modifier.gd` now detects the riser straddle structurally and passes the
correct clearance:

```gdscript
var straddling_riser: bool = animated_contact_hit and (
        animated_contact_position.y - ground_target.y > GROUND_CONTACT_DISTANCE)
```

When the probe's contact point is *above* the ankle's own smoothed ground target by more
than 3cm, it is reading a higher surface (the next tread) while the ankle hovers over a
lower one — pass `foot_pos.y - ground_target.y` (the real ankle clearance) as
`contact_distance`; otherwise keep the original probe gate. This matters because
`ground_target = smoothed_target + smoothed_normal * effective_offset` where
`effective_offset ≈ 0.096` is above the flat floor's contact point, so flat-ground idle
never satisfies the straddle test (`contact_y − target_y ≈ −0.096`) and the probe gate
stays intact; only a genuine tread-overhang reads positive.

**Why not the blanket version:** passing `foot_pos.y - ground_target.y` unconditionally
(previous attempt) broke the locomotion gate — `FOOT_IK_LOCOMOTION_CHECK case=idle` FAIL
(`LeftFoot` +5.6° added) and `FOOT_IK_MOVING_LANDING_CHECK` FAIL
(`added_body_position_peak_m=0.065731 > 0.05`) because idle bob and landing grace push
plain ankle clearance above 0.03 on flat ground too, misclassifying flat idle as a
step-down. The structural gate restores both to PASS.

**Headless A/B:** with the structural fix the right foot plants on step-4
(`foot_pos.y=1.105`, `smoothed_target.y=1.009`, `gap=0.0`, `ground_weight=1.0`,
`step_down=true`, `frozen=true`, sole clearance 0.0) and the left foot is planted on
step-5 — no float. Battery identical to baseline.

**Battery (2026-08-15):** `scripts/check.sh` PASS. `check_foot_ik.sh`: STRETCH/AIRBORNE/
POSE_CONTINUITY (0.014027)/STAIR_SETTLE PASS; BODY_PENETRATION FAIL and STAIR_LOCOMOTION
FAIL are the pre-existing parked reds. `check_foot_ik_locomotion.sh`: every case PASS
except the two pre-existing parked reds `crouch_back` and `crouch_walk_to_sprint` (+ its
MATRIX); `idle` `worst_added_deg=0.0`, `MOVING_LANDING` `added_body_position_peak_m=
0.041716`. `check_foot_ik_ramps.sh`: 184 PASS / 61 FAIL vs stashed-baseline 175/70
(slightly improved, same red classes). Ramp sweep: 3661/20 FAIL vs baseline 3404/20 —
identical FAIL set, no regression. Temporary marker fully reverted; no stray marker files.

**Not committed — await live manual acceptance:** stand idle at the top of the 0.20m
stairs straddling the last two treads and confirm the leg steps down and plants instead of
floating.

Full chronological history (2026-08-03 through 2026-08-12, idle-freeze/loop-reset/
locomotion-parity debugging) is archived at
`docs/task_history/foot_ik_stairs_and_idle_freeze.md`. This file is the current-state
summary only — update it, don't let it grow back into a full narrative log; put new
blow-by-blow investigation detail in `AGENTS.md` (durable lessons) or a fresh
`docs/task_history/` entry (full trail) instead.

## Log review + top-back-edge dangle (2026-08-14, diagnosed)

**What was "off" in the logs — and what wasn't.** A review of `logs/godot.log` from the
user's 20:15 live session found it clean: exactly the expected 18 rig setups × 4 lines
(36 derived sole-down axes + 36 measured planted sole depths). Count verified: 10
`PlayerFootIKModifier` instances in `foot_ik_preview.tscn` (the controllable `$Player`,
the 5 stair walkers, and 4 `_place_character` dummies) + 8 in
`foot_ik_animation_comparison.gd` (6 `PLAYER_BODY.new()` dummies + 2 crouch dummies) =
18. The genuine anomaly is in the live rolling trace `foot_ik_controlled.jsonl`, not
`godot.log`.

**The anomaly:** at the **top-back edge of the 0.35m stairs** (root_y=2.10 = 6×0.35,
x≈13.9–15.5, z≈3.4–3.8), a foot dangles a full stair-height below the tread with
`ground_weight=1.0`, `step_down=true`, `frozen` latched (streak 30), `contact_lost=false`,
`contact_hit=true`, `contact_distance≈2.096–2.100`, and `smoothed_target.y` easing
2.10→0.0 over ~270 frames while the body root never walks down. The leg runs to
anatomical max reach (`foot_hip_dy≈-0.88` vs the ~0.887 limit) so the rendered foot hangs
roughly half a metre below the visible top tread.

**Root cause — a harness geometry gap, not a gameplay-foot-placement bug.** The 0.35m
stair's **top landing past the last authored contact tread (z>3.6)** exists only on the
**traversal-proxy layer** (`CONTINUOUS_TRAVERSAL_LAYER`), which is the capsule's seamless
surface; it has **no geometry on the contact layer** (`1<<5`) that Foot IK probes raycast
against (mask = world 1 | contact `1<<5`, per `foot_ik_ground_sampler.gd`). A foot over
that landing therefore misses every authored tread, the 4 m idle fallback ray
(`idle_settle_search_down`) reads the **floor at y=0, 2.1 m below**, and the settle path
(`_step_down_classification` → "settle" → `_retract_to_reachable`) finds nothing
reachable because the hip is over the same gap. In a real level the top landing would be
ordinary world/contact geometry, so the foot would read ~2.1 and plant normally — this
only manifests in the harness because the split-surface prototype authors the landing on
the traversal layer alone.

**Reproduction status.** Headless marker-driven repros (direct spawn at the edge; walk
up then hold; plant→freeze→nudge past z=3.6) all reproduce the **transient** dive
(`smoothed_target` to ~0.56, rendered foot dropping toward the floor) but **self-recover**
to the correct planted pose within ~30–40 frames: once `_retract_to_reachable` fails, the
intended "genuine ledge/void → stay floating" behavior decays `ground_weight` to 0 and
the foot returns to its authored 2.18 pose. The **permanent ~270-frame live dangle**
additionally required the idle-freeze to latch at weight 1.0 while the target was already
mid-dive (freeze then bypasses `contact_lost` and forces `raw_weight=1.0`), a timing the
headless paths don't hit identically. The live JSONL was overwritten during reproduction
(AGENTS.md's "preserve the live JSONL elsewhere first" warning — acknowledged); the
numbers above are from the pre-overwrite read.

**Fix candidates (see implementation below):** (a) author the top landing on the contact
layer in the harness so foot probes read the real surface (fixes the demonstrated harness
gap), and/or (b) guard the modifier so a frozen foot over an unreachable void releases
instead of pinning the stretch. The harness gap is the clear, demonstrated primary cause.

**Implementing candidate (a).** Added `FootIKStairSurfaces.build_top_landing()` and a call
in `foot_ik_preview.gd`'s `_build_stairs()`: a contact-layer `CSGBox3D` spanning the top
rise and exactly the traversal landing's flat extent past the last authored tread
(`z ∈ [step_count·tread_depth, (step_count−1)·tread_depth + TRANSITION_LENGTH +
LANDING_LENGTH]`, y = full top rise), plus a thin debug tread cap. This matches the
capsule's walkable surface so a foot over the top-back edge reads the real landing at 2.1
instead of the 4 m idle-fallback floor at 0. Headless marker repro (player planted at
root z=3.75 on the 0.35m stairs, facing back) now holds both feet at `tgt_y=2.10`,
`hit=True`, `cd≈0.000`, weight 1.0, freeze latched, for the full 420-frame run — no dive
toward the floor. The landing box is not sampled by `FOOT_IK_BODY_PENETRATION_CHECK`
(that check only tests inside the six authored step volumes), so it adds no new check
surface; walkers' capsule mask excludes the contact layer via `configure_player`, so
movement is unaffected. Candidate (b) was not needed — with real contact geometry the
freeze no longer latches mid-dive.

**Battery after the fix (2026-08-14):** `scripts/check.sh` passes. `check_foot_ik.sh`:
STRETCH PASS (138), AIRBORNE PASS (62), POSE_CONTINUITY PASS (0.024599/0.025),
SETTLE PASS (30), BODY_PENETRATION FAIL (19 samples / 0.167048 max depth — pre-existing
XFAIL unchanged in sample count and depth), STAIR_LOCOMOTION FAIL (steps=0 — pre-existing
parked). `check_foot_ik_locomotion.sh`: all cases PASS except pre-existing `crouch_back`.
`check_foot_ik_ramps.sh`: matrix FAIL is the intentional-red wrapper; `failed_cases=0`.
`check_foot_ik_ramp_sweep.sh`: 2836 records / 0.1498 max depth — matches parked baseline.
One baseline-adjacent observation: BODY_PENETRATION penetrating vertices rose 3976→4862,
entirely at the walker's last-steps frames (107-111, root_z 3.3-3.5) where the foot now
correctly plants on the top tread instead of floating; max depth and sample count are
identical to baseline. This is the known "shallow toe/foot edge contacts inside the
steps" XFAIL taking a slightly different shape, not a new failure class.

**Still open / not addressed:** the permanent-freeze-dangle subclass (freeze latching at
weight 1.0 while the target is already mid-dive) is only reachable when a genuine
unreachable void exists with no contact geometry — the harness no longer produces that
configuration, and candidate (b) would be a defensive guard for real levels with a cliff
edge, left out deliberately to avoid touching the carefully-tuned freeze machinery.

## Current status (2026-08-14 — parked)

Further work on the remaining stair-path snaps is paused. The current uncommitted
continuous-collision prototype measurably improves the automated root path, but the live
visual improvement is small after many procedural smoothing/rate experiments. Do not resume
by adding another generic root, pelvis, Head, or speed offset. The evidence now points toward
an authored/contact-timed stair gait (or a gait-aware pelvis/root trajectory) as the next
meaningful experiment. Preserve the current branch and known-red regression baselines as the
comparison checkpoint; the continuous surface split is still awaiting manual acceptance and
must not be promoted silently.

The separate top-step idle failure from the final live capture is now fixed, pending manual
acceptance. At frame 791 the shared pelvis sank to settle one foot while the opposite
`preserve_idle_pose` leg was released to animation; because the pelvis is a common ancestor, that
nominally untouched foot followed it about `0.534m` through its higher tread. A preserved leg now
remains a no-op only when the shared pelvis does not move; otherwise it is solved back to its
pre-sink authored world target with full weight. The persistent stair-repeat harness now holds the
real player past the 30-frame freeze boundary on split-height support and asserts each rendered sole
that actually enters freeze. Its separate bilateral shared-pelvis invariant measured `0.285060m`
preserved-foot displacement before the fix and `0.000000m` after it (1cm limit); the live-position
replay reports 11 post-freeze samples, no failures, and at most `0.012478m` sole penetration (2cm
guard).

### Residual stair-walk body shake — options (2026-08-14, user-reported)

The physical root is now smooth on the continuous traversal proxy (`root_turn_p95 4.74°`,
`head_turn_p95 7.77°`, `balance_max_m 0.0`). The residual live complaint is a per-step body
shake *while walking over the steps*. The remaining source is almost certainly a per-footfall
vertical pulse: every stride plants the leading foot on a discrete 0.35m-higher tread, the leg
solver extends, and the shared pelvis absorbs a small vertical impulse. Turn-angle metrics are
green; vertical per-stride motion is what still shakes. Do **not** add another generic root,
pelvis, Head, or speed offset (that family is exhausted and documented as rejected above).

Options to try (decided 2026-08-14):

- **A (recommended) — contact-timed gait-aware pelvis trajectory.** Drive a small, smooth
  pelvis vertical curve from the *actual footfall timing* the gait tracker already knows
  (`foot_landed` signal, per-leg `_locomotion_stance_active`): a controlled dip on
  weight-acceptance and rise on push-off, synced to real contacts and gait phase instead of
  reacting to discrete tread heights. Presentation-only — lives in the `SkeletonModifier3D`
  stack, no capsule/collision/target changes, so it cannot feed back into animation or physics.
- **B — authored stair gait clip.** Dedicated stair-walk animation with stride/bob/clearance
  authored for the tread spacing. Cleanest long-term, but no pack ships one and retargeting a
  hand-authored clip between rigs is risky; defer unless A proves insufficient.
- **C — measure first, then choose.** Capture a controlled trace of the real player climbing
  the 0.35m stairs and diff root vs `Hips` vs torso vertical motion per footfall to confirm
  the pulse origin before building A or B.

**2026-08-14 measurement result (Option C, done): the pulse is NOT the walk bob.** An
instrumented probe during the stair-repeat harness's climb logged the animated (pre-IK) pelvis
height and the leg solver's `shared_drop` per frame. The animated pelvis is essentially flat
(`0.904..0.908`, ±3mm) through the whole climb — there is no stride-frequency component in the
pelvis bone to cancel. Yet the rendered (post-IK) Hips still oscillate ~60cm peak-to-peak
relative to root across the up-phase, and `ik_added` (rendered − animated Hips) accounts for
nearly all of it (`~0.62m` pp). Conclusion: the per-step shake is generated entirely by the
Foot IK `shared_drop` reach-limit sink on each 0.35m footfall (oscillating 0→`step_down_max_crouch`
0.6m per step), not by authored bob read on top of the climb. A walk-bob-cancelling pelvis EMA
(the first implementation attempt) therefore measured no improvement and was removed. **Any
effective fix must shape/smooth the reach-limit pelvis sink itself, not compensate an animated
pelvis height that is flat** — but `shared_drop` is deliberately unsmoothed (a lerp trial
reintroduced leg stretch + a body-penetration regression; see archive), so a viable approach
must either change the foot-target timing so the reach limit fires less, or coordinate a
presentation-only pelvis trajectory with the actual `foot_landed` timing while keeping the
solver's reach guarantee intact. Re-measure against rendered `_final_bone_poses` (or
`PlayerFootIKModifier.get_final_bone_global_pose`), never the pre-IK skeleton pose.

**2026-08-14 resolution (Option A variant, implemented): asymmetric rate-limiting of the
reach-limit release edge.** Probe tracing (`_shape_shared_drop`, pelvis-write, and the
walk-marker climb on the real 0.35m stairs) corrected the mechanism: on the continuous
traversal proxy the predictor's `ensure_support` is *not* the shake source — during the
climb the modifier's own reach-limit computation (`hip_pos.y - target.y - max_vertical_diff`)
builds a shared sink that stays high between footfalls (0.17–0.25m), then at each foot
re-plant the leading foot's target latches ~0.28m up a tread, the gap closes, and raw
`shared_drop` falls 0.17→0.05 **in the same frame** the predictor's support transfer
flickers inactive. The rendered pelvis popped 12.7cm that frame; the pre-IK `Hips` bob is
flat, so the pop is entirely IK-added. The chosen fix is `_shape_shared_drop()`: the sink
still engages instantly (a delayed sink stretches the leg — the documented lerp
regression), but the RELEASE back toward the animated pose is rate-limited to
`shared_drop_release_rate = 1.5` m/s (0.025m/frame at 60fps — exactly the pose-continuity
jump limit, so faster would trip the check on its own). The residual is never cleared when
the predictor flickers inactive: it keeps releasing toward raw at the capped rate, which
is precisely what eases the release (a gate that reset it on inactive made the release
instant again and left the 12cm jump). On a continuous slope the predictor is inactive and
the residual stays zero, so the `not active and _smoothed_shared_drop <= 0.0001` guard
returns raw unchanged — the ramp keeps its exact baseline pose-continuity score
(0.024599). Measured on the walk-marker climb (`foot_ik_controlled.jsonl` rendered-hip
probe): max single-frame jump 14.33→6.92cm, p95 7.87→4.86cm, mean 2.83→2.51cm. Release
rate sweep: 1.0→max 6.92 but stair penetration 36/8071; 1.5→max 6.92, penetration
30/7221; 2.0/2.5→max 7.87 but penetration back to ~baseline 29. Rate 1.5 chosen (best
shake reduction at near-baseline penetration; all variants share max_depth 0.18336 on the
known-red penetration check). Await live manual acceptance on the controllable character
before committing.

**2026-08-14 follow-up (idle engage smoothing, implemented):** The user's own live trace
(`foot_ik_controlled.jsonl`, 1423 rows) showed the remaining snaps are all instant ENGAGE
events of the shared sink, not release edges (which the work above fixed): 6 idle settle
engages of 12–26cm in one frame (frames 2605/2678/2679/3055/3065/3086, all on
`moves/unarmed_idle` with both feet planted) and 8 walking engages of 4–13cm per footfall.
The walking engages stay instant by design (the hip is climbing; a lagged sink stretches
the planted leg — the documented lerp regression). The idle settles were rate-limited:
`_shape_shared_drop()` now takes a `stationary` flag (computed from
`anim_player.current_animation` being `moves/unarmed_idle` or `moves/unarmed_crouch_idle`)
and when stationary also rate-limits the ENGAGE to `shared_drop_idle_engage_rate = 1.5` m/s.
This is safe while stationary because the hip does not move, so a gradual sink only bends
the knees more each frame (the "controlled crouch" the riser straddle was meant to read
as) and the preserved-leg compensation holds planted feet at their authored targets —
eliminating both the 12–26cm body snap and the foot sagging 16cm below its target
(overextended past the 0.887m reach). Walking engages are never smoothed. Automated
repro of the exact straddle is luck-of-position (flat-footed stops settle gradually even
in raw), so the fix was verified structurally + full battery (identical to baseline):
POSE_CONTINUITY 0.024599, STRETCH 0.0, SETTLE 0.0, penetration 30/7221, locomotion
suite bit-identical incl. the two pre-existing `crouch_back`/`crouch_walk_to_sprint`
failures, stair-repeat/idle-freeze/ramp-matrix/ramp-sweep unchanged. Not committed —
await live manual acceptance (stop mid-stairs or at the top riser and confirm no 12–26cm
body drop reads as a snap).

**2026-08-14 hover fix (Stairs 0.50m "invisible mesh", implemented + validated):** The
user's live report at the 0.50m reference stairs showed a planted foot held a full
step-height above the visible step beneath its ankle (right foot held a 2.5m target for
~120 frames while its ankle was over the 2.0m step). Root cause: during a step-up the
secondary toe-tip probe (`animated_lowest_surface_point_world`, extrapolated forward by
`toe_tip_margin`) reaches OVER a riser onto the NEXT tread's top while the ankle ray still
reads the current lower tread; `_latch_support_target()` preferred the probe, and
`_apply_support_contact()` pinned `_smoothed_target` at weight 1.0. Both legs are mid-swing
during a climb, so the plain-contact fallback in `_choose_support_side()` also selects the
climbing foot. Fix in `foot_ik_stair_predictor.gd`: `_toe_probe_reaches_higher_surface()`
returns true when the probe reads a surface `step_min_rise` above the ankle's own ray, and
it now guards `_is_contacting()`, `_try_transfer_support()`, and `_latch_support_target()`
(the latter falls back to the ankle's raw ray/normal instead). Headless 0.50m reproduction
(`foot_ik_stair_walk_marker` + `STAIR_WALK_TEST_SPAWN = 7*PLATFORM_SPACING`): 124 planted
hover events before, 0 after. Battery unchanged except an IMPROVEMENT on the known-red
penetration check (30→19 samples, 7221→3976 vertices, 0.18336→0.167048 depth).

**Ramp regression caught by the sweep (second iteration):** the height-only guard was too
broad — a foot planted at the BOTTOM edge of a ramp facing uphill has its toe probe
legitimately read the rising slope above the ankle, dropping it out of contact. The dense
ramp sweep went 2836→2974 failed cases (+138: 126 invalid_contact at frac 0.025-0.125
bottom edge, 12 penetration at frac 0.075 yaw 210). Discriminator: a stair step-up reads a
FLAT next tread (normal near UP), a ramp reads a sloped surface (45deg ≈ 0.71). The guard
now additionally requires `animated_contact_normal.dot(Vector3.UP) >= STAIR_TREAD_UP_DOT`
(0.999, matching the modifier's `flat_contact` threshold — deliberately tighter than
`FLAT_SURFACE_UP_DOT` 0.95 so a shallow 15deg ramp reading 0.966 is not misread as a
tread). After the refinement the sweep failure set is byte-identical to baseline (2836
cases, no new/removed/changed entries), the ramp matrix returns to its baseline
(`reported_left_deep_clip` invalid_contact 15→14), and the 0.50m hover capture still
reports 0 events. Not committed — await live manual acceptance of the 0.50m hover.

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

## Active refactor (2026-08-13)

The next work is deliberately split into behavior-preserving phases before adding
another stair-climb feature. Both `player.gd` and `player_foot_ik_modifier.gd` have
reached the configured 1000-line lint ceiling, and their responsibilities should not
be expanded further.

1. **Complete and live-confirmed: extract gameplay stair traversal from `player.gd` into
   `actors/player/player_stair_controller.gd`.** The helper owns step-up/down probes,
   pending climb/tread state, and stair presentation offsets. `Player` remains the
   authoritative `CharacterBody3D`: the helper operates on that real body and does not
   become a second physics node or test-only movement path. The extraction preserved
   the exact known-red regression baseline and was accepted in live play on 2026-08-13.
2. **Complete and live-confirmed: extract ground-contact
   sampling from `player_foot_ik_modifier.gd` into
   `foot_ik/foot_ik_ground_sampler.gd`.** That helper will own rays, smoothed contact
   target/normal, and rendered sole/toe clearance only; gait policy, stair support,
   pelvis movement, and bone writes remain in their current focused owners. The five
   independent validation entrypoints reproduce the exact pre-extraction baseline,
   and the result was accepted in live play on 2026-08-13.

After phase one is confirmed behavior-equivalent, update the stale stair-locomotion
step detector to use cumulative ascent over a short window. Only then continue with
proper predicted swing-foot clearance above a riser. Run all five validation
entrypoints independently after every phase; intentionally red ramp/stair cases must
remain visible rather than being weakened or silently skipped.

### Active stair-balance experiment

Live head-trace review after the refactor still shows whole-body shake on ascent. A
captured walk measured only 2 red head-path turns on flat ground (angle p95 6.6°), but
47 on stairs (p95 38.2°, peak 72.4°); the root path reports essentially the same
spikes, so this is not primarily a Head-bone defect. `PlayerStairController` now uses
a short trapezoidal acceleration/deceleration profile around the existing physical
ascent instead of starting and stopping a constant vertical velocity abruptly. A full
smoothstep was tested and rejected because its 50% longer ascent worsened penetration
from 21 to 33 samples. The shorter profile preserves `step_rise_rate` as the maximum
rather than hiding the issue with a head-only visual offset. Await live confirmation
before committing.

A synchronized stair-only slowdown was also tested: horizontal root travel and walk
playback eased from 1.0 to 0.65 and back during each rise. It was rejected and reverted.
Although it gave the foot more time, it also kept the swing leg beside the riser for
more frames: penetrating samples increased from 20 to 25 and penetrating vertices from
4,112 to 4,443. Do not retry slowdown by itself. Predict/lift the swing foot before the
riser first; speed modulation can only be reconsidered after that clearance exists.

The subsequent live trace exposed two independent discontinuities and both now have
targeted fixes awaiting live confirmation. `apply_step_down()` used to sweep the entire
remaining drop in one physics frame (captured root/head drop: 25.8/25.5cm); descent now
uses the same `step_rise_rate` per-frame ceiling as ascent and delays floor snap until it
reaches the lower tread. Separately, a top-tread idle held the left foot 33.8cm inside the
floor even though its sampled target was already correct: the unconditional frozen-idle
no-op preserved the authored penetrated pose. Deep ankle penetration (more than 5cm
below the effective IK target) now releases idle freeze and forces planting; using
rendered-sole clearance was explicitly rejected because normal authored foot volume can
extend slightly below its reference plane. Automated checks retain the known-red
baseline (`max_rendered_dy=0.047`, penetration 20 samples / 4,112 vertices; dense ramp
sweep 2,836/6,240); confirm the captured descent and top-tread idle cases live.

The head trace also measured the remaining ascent corner: 37 of 78 upward samples were
red, with a worst turn near 37 degrees, concentrated where the last ~3.5cm root rise
became zero on tread arrival. Extending ascent acceleration/deceleration from one to two
60Hz frames was tested and rejected: body-penetration samples regressed from 20 to 24
and affected vertices from 4,112 to 4,198. Keep the one-frame physical profile. Further
head/body balancing must be presentation-only and must not delay the collision capsule
or the IK contact frame; validate it against real skeleton Head/shoulder transforms and
the complete penetration suite.

A bounded presentation-only balance trial now applies 50% of each frame's stair
displacement (maximum 2.5cm) to `Spine` in `PlayerLookPoseModifier`. Because Spine is
outside the leg chains, hips/legs, collision, and Foot IK targets keep their physical
poses while torso/arms/head inherit a small counter-motion. The head-trace harness
measured 12 red upward turns out of 60 (20%, max 29.6 degrees, mean 8.3 degrees), versus
the preceding live capture's 37/78 (47%, max about 37 degrees). All five regression
entrypoints retained their exact known baselines. Await live visual confirmation; tune
`stair_balance_strength`/`stair_balance_limit` only within the exported bounds and do
not commit this presentation change before that confirmation. Applying a percentage of
the accumulated hover was rejected after the 15% and 25% trials measured about 26% and
25% red: it saturated during a climb and left no margin for the next tread-arrival
corner. Per-frame counter-motion targets the actual impulse and releases when the root
stops. The remaining corners are collision-root timing.

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

- `actors/player/player_foot_ik_modifier.gd`: orchestration, shared pelvis application,
  public/debug state.
- `actors/player/foot_ik/foot_ik_ground_sampler.gd`: downward contact rays, smoothed
  surface targets/normals, and rendered sole/toe clearance sampling.
- `actors/player/foot_ik/foot_ik_gait_tracker.gd`: animated vertical velocity, contact
  weight, falling streak, landing events.
- `actors/player/foot_ik/foot_ik_stair_predictor.gd`: travel direction, predicted
  tread, swing lift, single-support-foot ownership/transfer.
- `actors/player/foot_ik/foot_ik_leg_solver.gd`: closed-form anatomical leg solve and
  bone angle limits only — no raycasts, no gait-state decisions.
- `actors/player/player.gd`: authoritative `CharacterBody3D` and ordinary collision-root
  movement; `player_stair_controller.gd` probes and applies ascent/descent on that same
  body (shared gameplay code, not test-only).

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

**Close-up feet review (2026-08-15):** `tests/manual/foot_ik/foot_ik_stair_feet_review.tscn`
is a hands-off variant for visually inspecting foot placement up close. It auto-walks the
same real `Player` up/down the 0.35m stair loop (reusing `foot_ik_preview.tscn`'s own
`foot_ik_stair_walk_marker` toggle internally — no manual input needed for movement), runs
at 20% time scale, and gives you only a camera: left-drag orbits horizontal/vertical around
the rendered (post-IK) foot midpoint, scroll zooms. No other test platforms are in frame at
the tight default zoom. Launch directly: `godot --path . res://tests/manual/foot_ik/foot_ik_stair_feet_review.tscn`.

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

The headless stair traversal now reproduces the full manual sequence on a real
`Player`: walk from below the 0.35m stairs, release movement at the top, and retain
30 post-release frames in `user://foot_ik_trace.jsonl`. Its independent
`FOOT_IK_STAIR_SETTLE_CHECK` rejects a collision-root drop greater than 5mm in one
settling frame. The first run caught the live-reported terminal rebound automatically
(6 failing frames, 7mm maximum versus roughly 13.7mm in the preceding manual trace),
so future stair-controller changes can exercise this case without a human recording it.

The 2026-08-13 live trace established a concrete balance target. During ordinary
forward walking on flat ground, root-path turn p95 was 5.5 degrees and Head-path p95
was 9.7 degrees; during ascent they rose to 32.7 and 26.0 degrees respectively. A
bounded parameter sweep over that captured trace selected 75% per-frame Spine
counter-motion with a 3cm cap (previously 50% / 2.5cm): the estimated ascent Head p95
drops to 18.7 degrees, maximum to 21.8 degrees, and red segments from 14 to 12 out of
38. This is a presentation improvement, not a claim that stairs now match flat ground;
the remaining difference follows physical root-path corners and needs live acceptance.

Temporary live trial: normal stair walking now uses a synchronized 0.5 physical and
locomotion playback scale while a climb/descent or its presentation tail is active.
This deliberately revisits the previously rejected slowdown only for visual comparison
after the newer swing-clearance work; keep it temporary because the earlier 0.65 trial
increased stair penetration. `PlayerBody.locomotion_playback_scale` also feeds the gait
tracker and predictor, so the experiment does not compare half-speed root motion against
a full-speed animation/IK clock.

A repeated-traversal live trace later stopped exactly against the first riser at
`(11.617, 0.0, -0.367)`: normal 3.2m/s travel became zero and locomotion switched to
idle. The stair repeat guard retained `_last_tread_y`/`_last_contact` indefinitely, so
returning after a descent could reject a legitimate new crossing as the old riser.
`begin_frame()` now expires that guard once the capsule moves at least its 1m locality
radius away. Controlled JSONL frames now include movement input, velocity, and the
controller's climb/pending/last-contact state so future wall stalls distinguish released
input from rejected physical motion directly.

`scripts/check_foot_ik_stair_repeat.sh` now exercises the missing stateful case on a
real Player: ascend, pause, turn and descend, pause, then ascend the same staircase a
second time without calling the stair-controller reset. It fails when held movement
produces more than eight consecutive frames below 2mm horizontal travel. The first
post-fix run passes with two ascents and one maximum stalled frame. Keep this separate
from the one-way settle capture: resetting between trips would erase the exact history
this regression is intended to retain.

The latest 1,200-frame controlled trace still confirms visible stair shake. While
moving off stairs, root/Head path-turn p95 is 5.5°/6.0°; during active/recent stair
transitions it rises to 84.4°/103.7°, with 18/22 turns above the 20° red threshold.
Root vertical displacement also rises from 5.6mm mean absolute per frame off stairs to
12.7mm on stairs. Because root and Head worsen together, treat the remaining shake as
a collision/body-trajectory problem rather than masking it with Head-bone correction.

That trace also found an actual descent-ceiling violation: a root frame dropped nearly
10cm even though `step_rise_rate` limits 60Hz descent to about 4.7cm. The downward
`test_move()` intentionally probes `frame_drop + safe_margin`, but its full returned
travel was mistakenly applied to the root and terminal descent could then floor-snap
again. The controller now caps applied collision travel to `frame_drop`; the terminal
snap remains necessary to keep the capsule grounded on the final tread. The temporary
0.5 stair-speed trial is restored
to normal speed: halving horizontal movement while retaining the same necessary
vertical correction steepens every path corner and did not remove the live shake.

Two further shake experiments were rejected after the repeated traversal made them
quantitative. A 25cm/2cm presentation-only riser anticipation envelope was active, but
changed Head-path p95 from 31.03° to 31.26°; the dominant corner remains the physical
root climb, so its exported defaults are disabled (`0.0`) rather than paying for an
extra probe with no visible metric gain. Halving only `step_rise_rate` was much worse:
collision correction accumulated and released as a 22.35cm frame, raising Head p95 to
88.06°. Keep the authoritative rate at 2.8m/s. The safe improvement in this pass is the
descent probe-travel cap; meaningful further reduction likely requires authored stair
locomotion/root motion or a pelvis trajectory coordinated with actual gait contacts,
not another generic offset or slower capsule solve.

A follow-up verified modifier order before rejecting pelvis-level smoothing too.
`PlayerLookPoseModifier` runs before Foot IK, so shifting `Hips` and allowing the later
leg solver to recover tread contact was structurally valid, but neither the pelvis
low-pass alone nor its 2cm positive anticipation envelope changed the repeated-traverse
Head p95 (`31.03°` baseline; `31.26°` anticipated). The envelope also worsened rendered
penetration from 36 to 45 samples. Revert balance ownership to `Spine` and keep
anticipation disabled. This exhausts the safe generic offset/rate variants tried here;
the next serious path is an authored stair gait (or contact-timed pelvis/root curve),
not a larger procedural correction.

The next live-trace investigation found that the 0.35m reference walker can still record
an exact 35cm root step when the capsule is already touching the riser. In that state the
partial vertical `test_move()` rejects the interpolated climb and ordinary
`move_and_slide()` resolves the whole tread height. Two apparently direct fixes were
tested and rejected: trusting the previously validated full-height pose allowed severe
body/riser penetration (36 samples / 8,300 vertices), while withholding horizontal
travel until the partial pose cleared the riser produced a 10.87cm terminal correction
and raised Head-path p95 to 52.18 degrees. Backing off by one Jolt safe margin produced
the same correction. The stable implementation is restored. This confirms a geometric
limit of the current rigid capsule against a vertical face: further generic incremental
root smoothing alternates between a full-height solve, riser penetration, or a catch-up
correction. The next traversal-level experiment should use continuous/ramp collision
for authored stairs or a dedicated contact-timed stair gait, while keeping the real
stair mesh for foot contact and visual placement.

Godot 4.6.2 API and official-documentation review confirms that the next prototype
should be a separate continuous collision surface, not another capsule offset.
`SeparationRayShape3D` explicitly supports instant stair separation, so it is suitable
for conventional step snapping but not for the smooth root trajectory required here.
`CharacterBody3D` supplies slope handling and floor snap, but no native smooth traversal
of vertical risers. Build an invisible, simplified ramp collision for the player's
capsule while retaining the authored stair mesh/collision on a separate layer queried by
Foot IK. This gives locomotion a continuous physical root path and preserves discrete
tread heights for foot targets. Validate ascent/descent, stair-edge departure, jumping,
and the complete known-red penetration suites before replacing the current controller.
An authored/contact-timed stair gait remains a later presentation layer; it must not own
collision correctness.

### Continuous stair-collision prototype (awaiting manual acceptance)

The Foot IK preview now prototypes that split directly. Authored stair boxes moved to a
contact-only collision layer queried by Foot IK and the rendered-mesh penetration tools,
while player capsules query a separate traversal-only layer. The traversal proxy is one
invisible, two-sided `ConcavePolygonShape3D` surface spanning a flat bottom apron, a smooth
incline, and a flat top apron. Keeping this as one surface matters: separate ramp/landing
boxes exposed hidden vertical end faces that stalled descent. The incline begins one tread
before the visible staircase so its height reaches every tread's leading edge at or above
that tread top rather than carrying the capsule through the visible stair volume. Short
10cm quadratic transition zones remove the flat/slope corner impulse without materially
changing that alignment.

The repeated real-player traversal now passes twice in both directions with no stall:

```text
FOOT_IK_STAIR_REPEAT_CHECK PASS ascents=2 max_stall_frames=1
max_vertical_frame_m=0.0467 vertical_limit_m=0.0500
root_turn_p95_deg=14.93 head_turn_p95_deg=15.62
head_relative_frame_m=0.0182 balance_max_m=0.0300
```

The first manual review rejected the original head-only interpretation: independent
Y damping of Head/LeftShoulder/RightShoulder made the head look disconnected from the
moving body, so a lower Head-path number did not establish a better full-body result.
That damping is now removed. The repeat harness reports physical-root and skeleton-Head
turn separately plus consecutive head-relative-to-root displacement; root and Head p95
now agree instead of one masking the other. Static parsing/lint passes. The other complete gates
retain their pre-existing known-red categories and were not weakened: the focused suite
still reports stair body penetration and its stale one-frame step counter, the fixed ramp
matrix still ends red despite `failed_cases=0`, locomotion still has known transition
failures, and the dense ramp sweep remains 2,836/6,240 failed cases. On this candidate the
focused tread-volume diagnostic reports 28 penetrating samples / 3,909 vertices with
0.222273m maximum depth, so the proxy improves root continuity but does not by itself solve
swing-foot/riser intersections. Do not commit or promote the layer split to gameplay until
the controllable character is manually walked, turned, jumped, and landed on the 0.35m
stairs in both directions.

The rolling controlled trace now captures the connected center chain (`Hips`, all three
spine roles, `Neck`, `Head`) and both complete shoulder-to-hand chains. Each sample includes
world and root-relative position/rotation plus the live/rest parent-segment length ratio.
The legs remain covered by the existing hip/knee/foot/toe joint records and their explicit
upper/lower length ratios, so duplicating them in `bones` would only enlarge the trace. Use
the connected chain to find the first ancestor that diverges: root-relative motion separates
skeletal animation from physical-root travel, while parent-length ratios distinguish actual
stretch from ordinary authored swing. Ignore `Hips -> root` as an anatomical length check;
`root` is the rig's technical ground control, as recorded in `parent_bone`.
`PlayerLookPoseModifier` must cache this complete chain: sampling a cached final `Head` beside
an uncached, Skeleton3D-restored `Neck` initially produced a false 1.32 length ratio despite
the rendered segment remaining rigid. Cache lookup must also pass every canonical role through
`PlayerBody.resolve_bone_name()`; this rig's actual parent is `neck_01`, not literal `Neck`.

The first live manual trace after adding the connected chain showed the remaining visible
corners were physical, not Head-only: frames 209–218 had 35–58 degree Head turns alongside
36–60 degree root turns. Root Y alternated up and down (`0.252 -> 0.246 -> 0.269 -> 0.296
-> 0.278m`) because the discrete stair controller interpreted the seamless proxy's shallow
transition facets as repeated tiny risers, toggling `climbing` every frame. Continuous stair
proxies now use a dedicated controller layer that bypasses discrete `apply_step_up()`; normal
`move_and_slide()` slope motion exclusively owns their root trajectory. This remains part of
the temporary split-surface prototype and still requires live manual acceptance.

The first automated repeat after that separation reduced root-turn p95 from 14.93 to 4.69
degrees and Head-turn p95 from 15.62 to 8.28 degrees. It also exposed a second ownership leak:
a small pre-ramp landing compensation left stair balance active, then the smoothed reference
lagged behind the continuously rising root and saturated at -3cm for the whole ascent. That
compressed `Hips -> Spine` to 0.773x rest length. Continuous-traversal frames now explicitly
clear step-only hover/balance presentation state; those offsets are only for discrete risers.

A walkable slope is not guaranteed to appear in `CharacterBody3D.get_slide_collision()`
every frame, so the first version of that reset still flickered off. A short direct ray against
the traversal-only layer now authoritatively identifies the continuous floor. The repeated
traversal result is:

```text
FOOT_IK_STAIR_REPEAT_CHECK PASS ascents=2 max_stall_frames=1
max_vertical_frame_m=0.0320 root_turn_p95_deg=4.69 head_turn_p95_deg=7.77
head_relative_frame_m=0.0079 balance_max_m=0.0000
```

The connected-chain diagnostic now holds `Hips -> Spine` within
`0.9999994..1.0000006x` rest length. The complete validation map retains the known-red
categories: fixed ramps report no failed matrix cases but retain their wrapper failure,
locomotion retains its existing transition failures, and the dense ramp sweep remains
2,836/6,240. Removing the deforming balance offset changes the focused stair-penetration
distribution from 28 samples / 3,909 vertices / 0.222273m maximum depth to 28 samples /
6,480 vertices / 0.18336m maximum depth. This lowers the worst depth but affects more
vertices, so it is not automatic visual acceptance; manually review the controllable 0.35m
stair traversal before committing.

The next live trace still showed a red corner, but it was a different surface than the
automated case: the player began at `x≈7.7` on the authored 45-degree ramp, while the repeat
harness began directly on the `x=15` staircase. At the sharp ramp-to-flat edge, the live
root path turned 23.5 degrees in one frame. The persistent repeat test now first settles at
the same ramp position, walks downhill across that edge, releases input, and only then runs
the two stair round trips. It initially reproduced an even clearer 35.19-degree corner.
Ordinary ramps now use the same split ownership as stairs: authored geometry remains on the
contact-only Foot IK layer, while the capsule follows a traversal-only slope with a 40cm
quadratic transition at each end. The 45-degree reference also gets five degrees of floor-angle
headroom so numerical equality does not alternate between floor and free-fall. Final result:

```text
FOOT_IK_STAIR_REPEAT_CHECK PASS ascents=2 max_stall_frames=0
root_turn_p95_deg=4.74 head_turn_p95_deg=7.80
surface_turn_max_deg=6.70 surface_turn_limit_deg=12.00
surface_vertical_m=0.0555 surface_vertical_limit_m=0.0600
max_vertical_frame_m=0.0320 balance_max_m=0.0000
```

The surface-specific vertical limit is intentionally 6cm: at 3.2m/s a perfectly smooth
45-degree slope naturally changes Y by about 5.3cm per 60Hz frame, whereas the 5cm staircase
limit remains separate. All five required suites were rerun; their known-red categories and
exact fixed/dense matrix totals remain unchanged.

## Manual acceptance checklist

- Walk the controllable player up and down the 0.35m stairs at normal speed.
- Confirm each swing foot clears the vertical riser before crossing it.
- Confirm feet land on tread tops without floating or penetrating.
- Confirm the body doesn't stretch below the steps.
- Jump and land on/near stairs; knees must not invert and airborne IK must release.
- Compare idle and walk poses with IK on/off for unrelated deformation.
- Never commit gameplay/animation changes on automated verification alone — wait for
  explicit live confirmation (see `AGENTS.md`).

## New switchable "residual" locomotion mode (2026-08-15, first slice)

After `docs/foot_ik_industry_review.md` (research comparing our stair IK to real
implementations — Unity Final IK's leaked source, ozz-animation's reference sample,
Ubisoft's IK Rig GDC talk) found that no real system asks pure IK to carry an entire
staircase climb from one flat-ground walk cycle, the user asked to build a genuinely new,
simpler implementation as a **switchable alternative**, with the existing system left
completely untouched as the default/fallback — not an in-place rewrite.

**Added:** `PlayerFootIKModifier.LocomotionMode` enum (`LEGACY` / `RESIDUAL_STAIR`),
default `LEGACY`, same pattern as the existing `SolverBackend` toggle. When
`RESIDUAL_STAIR` is selected, `_process_modification_with_delta()` early-returns into a
new file, `actors/player/foot_ik/foot_ik_residual_corrector.gd` — modeled directly on
Final IK's actual (much simpler) approach: per-foot raycast, always-on full-weight
two-bone solve (reuses the existing `foot_ik_leg_solver.gd` unmodified), and ONE pelvis
sink (worst-case leg overreach, single symmetric lerp rate) instead of reach-limit trig,
asymmetric rates, swing/stance tracking, predictive swing-lift, or support-leg transfer.
`foot_ik_gait_tracker.gd`/`foot_ik_stair_predictor.gd` are not touched and not called at
all in this mode. `LEGACY` mode's ~1000-line existing path is unmodified except for the
one new branch at the top of the function.

**Verified:** full 5-entrypoint battery in `LEGACY` mode (the default) is byte-identical
to the known baseline — `check_foot_ik.sh` (21/4901/0.132237 penetration, same as
before), `check_foot_ik_locomotion.sh` (same two pre-existing parked reds, `TURN_TARGET_CHECK`
still passing), `check_foot_ik_ramps.sh` (`failed_cases=0`, same parked case), dense ramp
sweep (2579/6240, unchanged). `RESIDUAL_STAIR` mode was smoke-tested headless (temporarily
flipping the default, then reverting) — no script errors, runs stably; as expected for a
system with zero stair-specific prediction, its raw body-penetration numbers under the
full battery are much worse than `LEGACY` (100/32632/0.454 vs 21/4901/0.132) — this isn't
a regression, `RESIDUAL_STAIR` isn't meant to already beat `LEGACY`, it's meant to be
visually compared against it to see how much of the current complexity is actually buying
anything.

**Live A/B tool:** `tests/manual/foot_ik/foot_ik_stair_feet_review.tscn` (the feet-focused
orbit-camera review scene from earlier tonight) now has a **Tab key** toggle to flip
`locomotion_mode` on the live player between `LEGACY` and `RESIDUAL_STAIR` without
restarting, for a direct back-to-back visual comparison on the same stair walk.

**Not committed.** `locomotion_mode` defaults to `LEGACY` (zero behavior change for real
gameplay). Next step is the user doing the live visual A/B comparison via the Tab toggle;
if `RESIDUAL_STAIR` still looks meaningfully worse (likely, given it has no stair-aware
base motion yet — see the industry-review doc's proposed follow-up), the next real step
is generating stair-height-aware base motion (not yet started, `PlayerStairController`
doesn't currently track tread depth, only rise) rather than tuning this minimal corrector
further.

## `RESIDUAL_STAIR` gained root-relative swing detection (2026-08-15)

User reported the turn-in-place-on-stairs toe clip is still there in `LEGACY` mode
(expected — that fix was reverted earlier tonight, see above). Since further GitHub
research (`docs/foot_ik_industry_review.md`, "Follow-up 3") found a real, working Godot
4.6 addon (`blugart-dev/kickback`) using **foot height relative to the character root**
(not velocity, not absolute height) for swing/stance detection, tried adding exactly
that to `RESIDUAL_STAIR` mode — a genuinely different signal than the one that broke
`FOOT_IK_TURN_TARGET_CHECK` earlier, so worth testing independently rather than assuming
it'll hit the same wall.

**Added:** `residual_plant_threshold`/`residual_swing_threshold`/`residual_foot_blend_speed`
exports on `PlayerFootIKModifier` (kickback's own tuned defaults: 0.17/0.25/10.0).
`foot_ik_residual_corrector.gd` now computes `far = animated_foot.y - character_root.y`
per leg each frame and blends correction weight from it (full weight below
`plant_threshold`, zero above `swing_threshold`, linear ramp between), instead of always
correcting at full weight. `LEGACY` mode untouched, confirmed byte-identical to baseline
again (`check_foot_ik.sh` unchanged). `RESIDUAL_STAIR` smoke-tested headless (temporarily
flipping the default, then reverting) - no script errors; full-battery numbers are
similar to before (this alone doesn't add predictive swing-lift, so mid-swing clipping
through a riser during active climbing isn't expected to improve much - matches kickback
and the Perlin patent both explicitly NOT trying to solve that with IK either).

**Added a live toggle to the controllable scene, iterated through three attempts.**
1) A **Tab** keyboard shortcut - discovered live that Tab is already this project's
"inventory" action (`project.godot`) and Godot's own default UI focus-cycle action, both
of which could steal the keypress depending on UI focus; removed. 2) A dropdown added to
`foot_ik_debug_overlay.gd`'s own always-visible corner panel (next to "Solver Backend")
- worked, but the user pointed out they can't easily reach it: the mouse is captured for
first-person look, and freeing it (backtick) mid-test to click a corner widget while
trying to hold a rotation pose is awkward. 3) **User asked to add it to the actual
in-game pause "Debug" menu instead** (`ui/hud.tscn`'s `DebugOverlay` panel, opened via
the normal debug-menu key - that menu already frees the mouse and pauses the tree when
opened, unlike the corner panel). Removed the corner-panel dropdown, added a
**"Foot IK: Residual Stair Mode"** checkbox to `ui/hud.tscn`'s `DebugVBox` (same pattern
as the existing "Follow 0.35m Right Foot"/"Foot IK Joint History Graph" checkboxes right
above it - all three call methods on the `foot_ik_camera_preset` group node, i.e.
`foot_ik_debug_overlay.gd`, and are only visible when that node exists, so this stays
invisible during real gameplay). Added `is_residual_stair_mode()`/
`set_residual_stair_mode()` to `foot_ik_debug_overlay.gd` for the checkbox to call, and
wired the checkbox in `ui/hud.gd` exactly like its two neighbors (`_on_foot_ik_residual_
mode_toggled`, visibility/initial-state block in `_open_debug()`).

**Verified:** lint passes, headless smoke test of both `foot_ik_preview.tscn` and the
real `levels/playground.tscn` (confirming the shared `hud.gd`/`hud.tscn` change doesn't
break normal gameplay) show no errors, and the full `check_foot_ik.sh` battery still
matches the exact baseline. Now: open the pause Debug menu (mouse already freed, tree
already paused) and check the new checkbox near the bottom of the list, right above
"Show Skeleton."

**Not committed — awaiting live test.** Specifically: does `RESIDUAL_STAIR` avoid the
turn-in-place clip that `LEGACY` has (plausible, since `RESIDUAL_STAIR` has no
"trust the raw animated pose while turning" escape hatch at all - it always raycasts and
blends by height, so there's no separate turning-specific code path to have this bug in
the first place), and does the root-relative swing detection make ordinary walking on
`RESIDUAL_STAIR` look less broken than the always-on-full-weight version tested earlier
tonight.

## `RESIDUAL_STAIR` made temporary default (2026-08-15)

After confirming via the trace's new `locomotion_mode` field that a whole test session
never actually left `LEGACY` (the checkbox toggle path wasn't exercised/confirmed
working end-to-end), the user asked to flip the export's default so testing doesn't
depend on remembering to toggle it. **`locomotion_mode` now defaults to
`RESIDUAL_STAIR` everywhere** (`player_foot_ik_modifier.gd`) - this affects real
gameplay scenes too (`playground.tscn`, etc.), not just the test harness, since it's the
modifier's own default. Full battery re-run to confirm it still just runs (no crash),
not to judge it as a regression: `FOOT_IK_BODY_PENETRATION_CHECK` is worse under this
default (91/34411/0.436 vs `LEGACY`'s 21/4901/0.132) - expected, `RESIDUAL_STAIR` still
has no predictive stair-climb lift for actively-swinging feet, only the root-relative
swing/stance and pelvis-sink pieces.

**Must revert before any commit.** This is a live-testing convenience, not a decision
that `RESIDUAL_STAIR` is ready or preferred - flip `locomotion_mode` back to
`LocomotionMode.LEGACY` (the line right after `@export var solver_backend`) once this
round of live testing is done, or before committing anything else on this branch.

## Found and fixed: RESIDUAL_STAIR's raycast was too short-range (2026-08-15)

With the temporary default in place and `locomotion_mode` now recorded in the trace,
confirmed via a genuine `RESIDUAL_STAIR`-mode capture that the visible "clipping" the
user kept seeing was actually the opposite problem: `contact_hit: false` - the ground
raycast was missing the tread entirely at that pose, so the corrector gave up
(`ground_weight: 0.0`) and just showed the raw, uncorrected idle animation, which
naturally doesn't match the real tread height. Root cause: `_sample_leg()` only ever
called the short-range `raycast_ground()` probe, never the longer idle-fallback search
`_ground_sampler.sample()` (the full LEGACY path) already has for a stationary foot.

**Fix:** when the short probe misses AND the leg's root-relative height already reads as
"planted" (not mid-swing), retry with `idle_settle_search_down` (the same deep fallback
distance LEGACY uses). **Second bug caught immediately by the regression battery**: this
alone made `FOOT_IK_BODY_PENETRATION_CHECK` much worse (0.436m -> 0.747m max depth) -
the deep fallback can find a genuinely unreachable surface (several meters below, a real
void) and the corrector would stretch the whole pelvis trying to chase it. Fixed by
reusing the exact same principle already applied to the void-dangle case: check if the
found surface is actually within the leg's reach, and if not, treat it as unreachable
and fall back to the raw animated pose instead of stretching toward it.

**Result: `FOOT_IK_BODY_PENETRATION_CHECK` improved from 88/45077/0.747 to
25/1762/0.077 - now measurably better than `LEGACY`'s own 21/4901/0.132.** Full battery
otherwise unchanged, headless smoke test clean. `locomotion_mode` is still defaulted to
`RESIDUAL_STAIR` for continued live testing (see note above - must revert before commit).

**Correction: the "still floating" diagnosis right after this fix was based on stale
data, not a real symptom.** Checked a fresh `RESIDUAL_STAIR` trace and saw
`contact_hit: false`/`ground_weight: 0.0` for the whole session and concluded the
raycast was still failing. It wasn't - those exact trace fields
(`_ik.debug_contact_hit`, `_ik._smoothed_ground_weight`, `_ik._smoothed_target`) are
written only by the `LEGACY` per-leg loop; `foot_ik_residual_corrector.gd` never touched
them, so the trace was silently showing leftover `LEGACY` bookkeeping (or defaults),
not what the new corrector actually computed. `foot_ik_residual_corrector.gd` now writes
these same shared fields itself (`debug_contact_hit`, `debug_raw_weight`,
`debug_step_down`, `_smoothed_target`, `_smoothed_ground_weight`) purely for
introspection - not consumed by the corrector's own logic - so the live trace and debug
panel report real numbers for either mode. Confirmed diagnostic-only: full battery
re-run identical (25/1762/0.077), headless smoke test clean.

Not committed - awaiting a live look with a genuinely trustworthy trace this time.

## Automated repro built; two more real bugs found and fixed (2026-08-15)

User asked whether I could run this specific test myself instead of relying on manual
play each iteration. Built a temporary automated repro (a scratch edit to
`foot_ik_preview.gd`'s existing `foot_ik_stair_walk_marker` handling: walk to mid-stair,
stop, then continuously rotate in place at 20 deg/s - matching the manual test exactly)
and ran it headless with `--fixed-fps 60`, reading the resulting `foot_ik_controlled.jsonl`
trace directly. This let two real bugs get found and fixed in this session without
needing the user to test each attempt:

1. **A genuine twice-per-tick pelvis-sink bug**, the exact class of mistake this
   project's own `AGENTS.md` warns about (`SkeletonModifier3D` calls the modifier twice
   per physics tick). `_sink_pelvis()` read-and-modified the skeleton's *current* pelvis
   pose every call instead of caching a per-physics-frame baseline first, so on ticks
   where a real sink was active it would compound twice per tick. Fixed by caching the
   baseline pose once per `Engine.get_physics_frames()`, mirroring the identical fix
   already in `player_foot_ik_modifier.gd` for the same bug class. This one turned out to
   have zero measurable effect on the specific symptom being chased (confirmed via a
   temporary debug print: `_smoothed_pelvis_offset` was 0.0 throughout that test), but is
   a real latent bug worth having fixed regardless before it causes a harder-to-diagnose
   problem once the pelvis sink actually engages.
2. **The actual cause: a hard cutoff at the exact reach-limit boundary**, the specific
   "don't gate a noisy signal at exactly the boundary value" mistake `AGENTS.md` already
   documents from an earlier session - and I repeated it. The void-dangle-style
   "unreachable target" check added earlier tonight used `dist > max_reach` with zero
   tolerance; this character's own authored idle stance already sits close to full leg
   extension, so ordinary per-frame noise tipped it over the exact boundary on most
   frames, permanently zeroing correction weight (confirmed via a temporary debug print:
   `dist` was landing right at 0.87-0.91m against a computed `max_reach` of 0.887m).
   Fixed by adding a small margin (`max_reach + 0.08`) before treating a target as
   genuinely unreachable, since the leg solver already clamps and copes fine with
   ordinary minor overreach on its own - the margin only needs to catch real voids.

**Also fixed while doing this: the diagnostic fields themselves were stale.** Before
finding bug #2, initially misdiagnosed the symptom using `contact_hit`/`ground_weight`
trace fields that turned out to be written only by the `LEGACY` code path -
`foot_ik_residual_corrector.gd` never touched them, so they showed leftover `LEGACY`
values, not what `RESIDUAL_STAIR` actually computed. Now writes these shared fields
itself (see the "Correction" note above) so the trace is trustworthy for either mode.

**Result after both fixes** (measured via the automated repro, `RESIDUAL_STAIR` still
temporarily default at the time): `ground_weight` genuinely varies now instead of being
pinned at 0 or 1 (704/898 samples at full weight), worst clip -0.16m, worst float
+0.065m - real improvement, but **not close to solved**: `ground_weight` is still 0.0 for
roughly half of samples, and the full `check_foot_ik_locomotion.sh` battery under
`RESIDUAL_STAIR` fails nearly every case (expected - this mode still has no swing
detection sophistication beyond the basic root-relative height check, no predictive lift,
no hysteresis). This remains a genuinely unfinished experiment, not a near-complete
alternative.

**Reverted before wrapping up:** `locomotion_mode` back to `LocomotionMode.LEGACY`
(default), the temporary `foot_ik_preview.gd` auto-rotate scratch edit removed (restored
to its original full-loop walk behavior - confirmed no automated regression script
depends on `foot_ik_stair_walk_marker`, so this was safe to freely modify and revert).
Confirmed `LEGACY` mode's full battery is byte-identical to the known baseline again
after all reverts (a stale leftover marker file briefly caused a false-looking
airborne/pose-continuity discrepancy on the first re-check - cleaning it up restored the
exact expected numbers). All `RESIDUAL_STAIR`-specific fixes (twice-per-tick pelvis
caching, reach-margin tolerance, shared debug field writes) remain in
`foot_ik_residual_corrector.gd` for whenever this mode gets picked up again.

## Third experimental mode built and rejected: `PHASE_LOCKED`

Built a third switchable mode implementing Ken Perlin's "sample ground only at
touchdown, hold until next touchdown" idea (`foot_ik_phase_locked_corrector.gd`), reusing
`foot_ik_gait_tracker.gd`'s already-proven `landed` event instead of inventing a new
phase detector. Wired in exactly like `RESIDUAL_STAIR` (enum value, debug-panel
checkbox, `is_phase_locked_mode()`/`set_phase_locked_mode()`).

**Rejected after automated testing.** The lock-and-hold mechanism itself works cleanly
(near-zero flicker in the automated stair-rotate repro), but the moment the character
stops generating new footfalls - standing still, turning in place - the stance/release
timers run out and it falls back to **raw, fully uncorrected animation**, since (unlike
`RESIDUAL_STAIR`) there's no continuous fallback path. `check_foot_ik.sh`'s general
locomotion suite (mostly non-walking) confirms this is disqualifying: 79 penetrating
samples / 69900 vertices / 1.223m max depth, vs. `LEGACY`'s 21/4901/0.132 and
`RESIDUAL_STAIR`'s 25/1762/0.077. Left in the codebase, off by default, as a documented
dead end - the touchdown-lock idea itself isn't wrong, it just needs a continuous
fallback for the no-motion case, which is most of what `RESIDUAL_STAIR` already is.

## Real fix found and verified in `LEGACY`: the once-per-step pelvis/foot pop

User reported two persistent, concrete symptoms on stairs: the character bounces once
per step, and feet clip through treads. Traced both to the same mechanism instead of
tuning yet another classifier variant.

**Root cause**: `foot_ik_stair_predictor.gd`'s stair-support-ownership system hands
control of the shared pelvis drop to whichever foot is currently "supporting." When
ownership transfers to the other foot (`_try_transfer_support`, roughly once per step),
`_apply_support_contact()` used to snap that foot's target to its full ground-contact
position and force its weight straight to `1.0` in a single frame - no ramp. Since the
pelvis-drop math (`ensure_support()`) reads directly off that same value, the pelvis
popped in the same instant. This is a genuinely different case from the general
`shared_drop` engage/release smoothing (`_shape_shared_drop`'s doc comment): that's about
a single leg's reach growing continuously (e.g. mid-descent), where delaying it stretches
the leg - a real regression, already found and reverted once. This is a discrete handoff
between two already-latched targets, which doesn't have that failure mode.

**Fix**: blend the newly-support leg's target and weight from its pre-support value up
to the full support target over a short fixed `support_transfer_blend_time` (0.08s, new
export), instead of snapping instantly. Gated on `STAIR_TREAD_UP_DOT` (genuinely flat,
~0.999), not the looser `FLAT_SURFACE_UP_DOT` (0.95) already used elsewhere in this file
- a shallow ramp (15deg reads 0.966) is loose enough to still hold stair-support
ownership, and blending its settle-transfer measurably regressed one static
`FOOT_IK_RAMP_CASE` (0 -> 4 penetrating samples) before this gate was added. With the
gate, the ramp suite is byte-identical to baseline (61/61 same failing cases, zero diff).

**Verified improvement** (`check_foot_ik.sh`, `LEGACY` default, same tree, toggled via
`support_transfer_blend_time = 0.0` for a true instant-snap baseline vs `0.08`):
- `FOOT_IK_BODY_PENETRATION_CHECK`: 21 -> 17 penetrating samples, **4901 -> 2598
  penetrating vertices (~47% reduction)**, max depth unchanged (0.132m - a different,
  deeper case dominates that number, not the transfer pop).
- `FOOT_IK_RAMP_CASE` suite: identical to baseline, 61/61 same failures, zero diff.
- `check_foot_ik_locomotion.sh`: identical failing set both ways (`crouch_back`,
  `crouch_walk_to_sprint`, suite) - pre-existing, unrelated to this fix.
- `check_foot_ik_stair_repeat.sh`, `FOOT_IK_IDLE_FREEZE_CLEARANCE_CHECK`: PASS, unchanged.
- `FOOT_IK_STRETCH_CHECK`/`AIRBORNE_CHECK`/`POSE_CONTINUITY_CHECK`: PASS, unchanged.

Not yet confirmed by eye - `locomotion_mode` stays `LEGACY` (default, unaffected either
way), the fix lives directly in `foot_ik_stair_predictor.gd`/`player_foot_ik_modifier.gd`
so it's live for ordinary play. Needs a live manual playtest (does the bounce actually
read as fixed, does clipping actually look better) before this gets committed.

## Second real fix: toe clipping through the tread during a step-down settle

Live playtest after the fix above confirmed the pop was reduced but toe clipping was
still visible. Checked the trace instead of guessing: `sole` clearance was already clean
(the fix above's pelvis-side effect), but `toe_tip` clearance showed real, repeatable
clips up to -0.1226m, always during a `step_down` classification (a stance foot easing
onto a lower tread), peaking almost exactly at `ground_weight~0.49` and clean at both
ends of the ramp.

**Root cause**: `_step_down_classification`'s "settle" path blends the foot's target as
a straight 3D lerp from the raw animated foot position to a lower, `_retract_to_reachable()`-
picked target. Both endpoints individually clear the tread - `_retract_to_reachable()`
already accounts for toe-forward overhang - but nothing guarantees the straight *path*
between them does, and it doesn't: partway through, the toe swings through the tread's
front edge. `update_swing_lift()` (the mechanism that would normally give a genuinely
swinging foot forward+up clearance) is explicitly disabled for `step_down` by design,
since a settling stance foot isn't a swing.

**Fix**: add a small vertical lift during this transition, `sin(PI * ground_weight) *
step_down_transition_lift` - zero at both ends, peaking exactly where the clip peaked.
Deliberately not `swing_lift`: that mechanism's forward-raycast prediction assumes a
genuinely airborne foot, which this isn't.

**First attempt regressed something else, found and fixed via the same discipline**:
applying this lift unconditionally regressed `FOOT_IK_MOVING_LANDING_CHECK` (added body
position peak 0.042m -> 0.078m, over its 0.05m budget) - traced to `step_down`
classification also firing right after an ordinary *jump landing* (a settling foot right
after impact reads the same "stationary, needs more sink" way a stair descent does),
which has nothing to do with stairs. Gated the lift on `_landing_grace_time <= 0.0`
(already-existing flag, set only on a genuine airborne->grounded transition) to exclude
that case. Re-verified: `MOVING_LANDING_CHECK` back to its exact baseline numbers, full
lift strength intact for real stair descents.

**Verified result** (`check_foot_ik.sh`, cumulative with the fix above, same tree):
- `FOOT_IK_BODY_PENETRATION_CHECK`: baseline 21/4901/0.132m -> **14/1676/0.050m** (33%
  fewer samples, 66% fewer vertices, 62% shallower max depth, from the original baseline).
- Toe clearance in the raw trace: worst clip -0.1226m -> -0.0412m, sample count 14 -> 9.
- `FOOT_IK_MOVING_LANDING_CHECK`: back to PASS, byte-identical numbers to baseline.
- `check_foot_ik_locomotion.sh`'s other cases: identical failing set to baseline
  (`crouch_back`, `crouch_walk_to_sprint`, suite) - pre-existing, unrelated.
- Ramp suite: near-wash, not a concern - 3 tiny pre-existing ramp clips fixed (61+10+1
  vertices, all under 0.009m), one tiny new one introduced (121 vertices, 0.013m) on a
  15deg ramp's near-top settle. All of these are an order of magnitude smaller than the
  actual stair clipping being targeted (up to 0.12m) - noise-level on ramps specifically.

Still not confirmed by eye. `locomotion_mode` stays `LEGACY` (default). Both fixes
(`support_transfer_blend_time`, `step_down_transition_lift`) live directly in the default
code path, so they're active for ordinary play without any mode switch. Needs a live
playtest before committing.

## Third real fix: ground_weight/chain_weight desync during a stair support handoff

User playtest after the two fixes above: still saw real clipping. Checked the actual
`foot_ik_controlled.jsonl` trace from that session instead of guessing - it showed a
foot standing idle right at a stair edge with `sole_clearance` down to -0.187m,
`ground_weight=1.0`, and (misleadingly, see below) `solved_foot_pos` exactly equal to
`foot_pos` for many consecutive frames.

**First (wrong) theory, corrected by live debugging**: initially read that equality as
"the correction isn't being applied at all despite full weight." Added temporary debug
prints and reproduced the exact scenario headless. Found a REAL desync along the way:
`foot_ik_stair_predictor.gd`'s `_apply_support_contact()` (the same function fixed
earlier for the transfer-pop) writes `leg["ground_weight"] = blend` but never touched
`leg["chain_weight"]` - which the per-leg loop had already set earlier, often to `0.0`,
before support ownership took over. Since `foot_ik_leg_solver.gd`'s `solve()` weights the
actual hip/knee ROTATION by `chain_weight` (not `ground_weight`), this let a support leg
read `ground_weight=1.0` (full target commitment) while its `chain_weight` was still
`0.0` (zero rotation applied) - a real bug, confirmed live via debug prints showing
`gw=1.0 chain=0.0` specifically whenever `support_side` matched that leg. **Fixed**: set
`leg["chain_weight"] = blend` alongside `leg["ground_weight"]` in the same function.

**But that fix alone didn't explain the user's specific clip.** Kept debugging with the
same live-print technique instead of assuming the fix was enough. Traced the exact frame
range from the JSONL (`frame=` field) into matching `solve()` calls and found: `chain_weight`
and `ground_weight` were NOT desynced in this specific case (both correctly `1.0`), and the
leg solver's `new_foot_pos.y` really was climbing frame by frame (0.980 -> 0.983 -> 0.987
-> ... -> 1.131), converging toward its target - the correction genuinely IS being
applied. The earlier "solved == foot_pos" observation was a false lead: the trace's
`foot_pos` field is itself sampled post-correction, not the untouched raw animation pose,
so the two will read identical once IK has already engaged - it never meant "no
correction happened."

**The real remaining problem, narrowed but not yet fixed**: the *target* itself is
landing roughly 0.15-0.18m below the true tread surface in this idle-near-stair-edge
case (`shared_drop` reached an unusually large ~0.39m, consistent with the code trying to
reach a target that's genuinely too low, not with a weight bug). This points at
`_step_down_classification`'s "settle" path (`_retract_to_reachable()`, which pulls the
search point horizontally toward the hip looking for a reachable surface) picking the
wrong, too-low surface for this specific stair-edge stance - not yet confirmed exactly
why, next session should pick up there with the same live-trace-first approach rather
than re-guessing.

**Verified so far** (`chain_weight` desync fix only, `check_foot_ik.sh` + full suite, same
tree as the two fixes above): `FOOT_IK_BODY_PENETRATION_CHECK` 14/1676/0.050m ->
15/1728/0.052m (noise-level, not a regression), ramp suite and locomotion suite both
byte-identical to the prior fix's numbers (zero diff), `MOVING_LANDING_CHECK` still PASS
with unchanged numbers. All debug prints and scratch harness edits removed/reverted after
use. `locomotion_mode` stays `LEGACY` (default). Not yet confirmed fixed by eye - the
user's own report is still "still see clippings" as of this writing, and the root cause
of THAT specific report (the too-low settle target) remains open.

## 2026-08-16: Idle-turn foot clip through stair treads — root cause + fix (verified)

**Symptom (user live capture, `foot_ik_controlled.jsonl`, 1338 frames):** player standing
straddling the 0.20m stairs step-3/4 riser (root z 2.274..2.374 straddles riser z=2.4, all
`moves/unarmed_idle`) and turning in place. During the turn the right foot rendered 14.4cm
inside step 4: `foot_y=0.952`, target `1.000` (tread top 1.0), `step_down=false`.

**Root cause:** `stationary_noop`'s turning branch (`_gait_tracker.is_body_turning(side)`)
had no distance requirement. During an idle turn the turning flag is true for both feet, so
the right foot was classified stationary-noop -> `preserve_idle_pose=true` -> `target =
foot_pos` -> the IK solve was skipped entirely, leaving the foot at its authored pose,
buried in the higher tread. The left foot was not misclassified because its authored pose
happened to sit lower (floating only +0.029m).

A previous "solved == foot_pos" trace reading was a false lead: `foot_pos` is itself
sampled post-correction, so equality just means "IK already engaged," not "no correction."

**Fix (in `player_foot_ik_modifier.gd`, `stationary_noop`):** the turning branch now also
requires the foot's vertical gap to its ground target to be within `step_min_rise`:
`absf(foot_pos.y - ground_target.y) <= step_min_rise`. Vertical-only on purpose: the turn
A/B (`foot_ik_locomotion_regression.gd`) allows up to `TURN_TARGET_GAP_LIMIT=0.08`m
*horizontal* lag between the animated foot and the smoothed target during flat-floor turns,
so a full 3D distance gate could false-flip there and re-introduce the documented 12.141deg
thigh-jump regression. On flat ground the vertical gap is ~0, so the turning branch behaves
identically to before; on the stair it is 0.144m -> solve engages. The third (non-turning)
clause is unchanged. `preserve_idle_pose` itself untouched.

**Verification:**
- Headless repro (throwaway capture scene, deleted after use): 0.20m stairs, player at the
  straddle, 180deg turn over 7s. Right foot now renders at 1.096 (= target 1.000 + 0.096
  sole depth) through the whole turn — correctly planted on step 4, `sole_clearance` never
  negative; as the body rotates both feet re-target to the lower tread (0.896 vs 0.800)
  without any burial. Before the fix this exact pose was the 0.952/1.000 clip.
- `scripts/check.sh` PASS (file back at exactly 1000 lines; committed baseline 901).
- `check_foot_ik.sh`: STRETCH/AIRBORNE/POSE_CONTINUITY/STAIR_SETTLE PASS, plus the two
  documented known-red checks (BODY_PENETRATION 15/1728/0.051942m, STAIR_LOCOMOTION steps=0)
  — numbers byte-identical to the pre-fix baseline, so no regression.
- `check_foot_ik_locomotion.sh`: turn A/B `FOOT_IK_TURN_TARGET_CHECK PASS` (max gap 0.0095m
  vs 0.08 limit); the two FAILs (`crouch_back`, `crouch_walk_to_sprint`) are pre-existing —
  byte-identical numbers with the fix surgically reverted.
- `check_foot_ik_ramps.sh` / `check_foot_ik_ramp_sweep.sh`: 59 RAMP_CASE FAILs and
  2579/6240 failures respectively — byte-identical to the pre-fix baseline (both suites
  documented known-red).

Still needs the user's manual in-editor confirmation before commit (the "never commit
gameplay on automated verification alone" rule).

## 2026-08-16: Stair rotation toe-clip under shared pelvis drop & retracted lerp — root cause + fix

**Symptom:** When standing on stairs and rotating the body in place, the uphill/preserved foot's toes were clipping into the step surface (~5.5cm penetration), while the opposite foot planted correctly.

**Root Causes:**
1. **Preserved leg target under shared drop:** When straddling steps, the lower leg's drop sinks the shared pelvis. `_apply_support_pelvis_and_legs()` solved the higher, preserved leg back to its pre-sink position to keep it from following the pelvis down, but passed `leg["target"]` (which was set to raw ungrounded `foot_pos` without the `0.096m` sole clearance offset) together with full `ground_weight = 1.0`. The solver rotated the foot flat and forced the toe to its rest offset below `foot_pos`, pushing the toe ~5.5cm into the higher tread.
2. **Retracted target smoothing across step boundaries:** When `_step_down_classification()` settled onto a lower stair tread via `_retract_to_reachable()`, `_smoothed_target` was lerped toward the new surface at `smooth_rate = 7.0`. On discrete flat stair treads, lerping height slides through non-existent intermediate heights in mid-air/step volume, causing temporary toe clipping during turns.
3. **`stationary_noop` bypassing IK on `frozen` and `is_body_turning`:** `stationary_noop` was set to `true` whenever `frozen` was active or `is_body_turning` was true. This caused `preserve_idle_pose` to trigger, which bypassed IK entirely (`release_to_animation`), dropping the foot from its corrected ground height down into the floor whenever turning or coming to a stop on stairs.
4. **Foot basis yaw snapping during turns:** `_compute_new_foot_basis_world()` previously derived the foot's horizontal facing strictly from the skeleton rest pose (`get_bone_global_rest()`) rather than the animated foot orientation, causing the foot to twist and fight the turn animation during rotations.
5. **False `contact_lost` on uphill/penetrating feet:** In `foot_ik_gait_tracker.gd`, `contact_lost` checked `contact_distance > GROUND_CONTACT_DISTANCE (0.03m)`. Since the probe casts from 0.40m above the foot, `contact_distance` to a ground hit is almost always > 0.03m. On an uphill stair step where `step_down` was false, this declared `contact_lost = true`, which preceded the `penetrating_contact` check and forced `ground_weight = 0.0`, stranding the uphill foot ~20-30cm inside the step.
6. **Knee angular rate-limiter lag during pelvis drop:** In `foot_ik_leg_solver.gd`, `_limit_correction()` capped hip/knee angular speed to 120°/s (2°/frame). When `shared_drop` (pelvis sink) engaged instantly on stairs, the hips dropped immediately while the knee took 15–18 frames to bend, causing the foot to be pushed 10–14cm into the step for ~0.2 seconds before catching up.
7. **Turn raycast sampled only ankle position while toe crossed stair riser:** In `foot_ik_ground_sampler.gd`, ground sampling cast only down from `foot_pos` (ankle). When turning towards the stairs on a lower step (`y = 1.00m`), the ankle remained on the lower step while the extended toe bone rotated across the step riser into the higher step space (`y = 1.20m`), resulting in the toe penetrating the vertical riser / higher tread by 17.5cm. Furthermore, a legacy turn clamp (`if body_turning and raw_target.y > current_target.y: follow_target = current_target`) actively prevented the foot from climbing onto the higher step during in-place rotation.

**Fixes:**
1. In `player_foot_ik_modifier.gd`: For preserved legs when `shared_drop > 0`, pass `leg["ground_target"]` (which includes the proper sole clearance offset) to `_leg_solver.solve()` rather than `leg["target"]` (`foot_pos`).
2. In `player_foot_ik_modifier.gd`: Instant-snap `_smoothed_target[side]` to `retracted["surface"]` when the contact normal is flat (`dot(Vector3.UP) >= 0.999`), preventing the intermediate height lerp on stair treads.
3. In `player_foot_ik_modifier.gd`: Cleaned up `stationary_noop` so it only bypasses IK when the raw animation pose is already resting on flat ground within `flat_idle_noop_distance`, preventing spurious IK releases during idle freeze or turning.
4. In `player_foot_ik_modifier.gd`: Updated `_compute_new_foot_basis_world()` to derive `world_forward` from the animated foot pose projected onto the ground plane, preserving authored turn yaw while aligning pitch and roll to the ground surface.
5. In `foot_ik_gait_tracker.gd`: Removed the probe-distance check from `contact_lost`, relying on vertical clearance above target (`clearance_above_target > GROUND_CONTACT_DISTANCE`), guarded `contact_lost` by `not penetrating_contact`, and promoted `penetrating_contact` to set `raw_weight = 1.0` before any contact-lost evaluation.
6. In `foot_ik_leg_solver.gd`: When `_smoothed_shared_drop > 0` (pelvis sink on stairs), increased angular speed budget to 720°/s so the knee bends instantly with the pelvis drop without lagging into the step.
7. In `foot_ik_ground_sampler.gd`: Added toe surface probing in `sample()` so that when the animated toe reaches across a riser to a higher step, `raw_target` reflects the higher step surface immediately, and removed the turn clamp that previously locked the target to the lower step.

**Verification:**
- Automated headless test with exact player position `(11.506, 1.143, 2.721)` and rotation sweep across the 0.35m stairs confirmed:
  - Foot y solves to `1.296m` on the higher step with toe tip at `1.225m` (+2.5cm clearance above step surface `1.200m`).
  - Zero toe penetration across all frames.
- `scripts/check.sh`: PASS (0 lint/parse errors, file strictly under 1000 lines).
- `check_foot_ik.sh`: PASS for STRETCH, AIRBORNE, POSE_CONTINUITY, STAIR_SETTLE; matching known baseline.
- `check_foot_ik_locomotion.sh`: `FOOT_IK_TURN_TARGET_CHECK` PASS (0.0094m max gap, `worst_added_deg=1.926`).

## 2026-08-16: Precision Foot Placement on Stairs during Diagonal / Side Locomotion (Industry Architecture & Plan)

### 1. The Problem: Floating / Detached Feet on Side/Diagonal Stair Walking
* **Symptom:** When walking across or diagonally on stairs, the player capsule rides smoothly on the invisible continuous traversal ramp (`CONTINUOUS_TRAVERSAL_LAYER`). Between step edges, the ramp surface floats 5–15cm above the recessed step tread underneath. If Foot IK uses forward-only stair prediction or lacks deep downward contact search during non-forward motion, the feet plant onto the invisible ramp plane rather than reaching down to the physical step treads, appearing to walk on thin air above the steps.

### 2. How Modern Engines (Unreal Engine 5 Foot Placement Node / Final IK) Solve This
1. **Separation of Layers:**
   * **Physics Capsule:** Moves on the continuous smooth traversal proxy (`CONTINUOUS_TRAVERSAL_LAYER`) for jitter-free movement and camera control.
   * **IK Raycasts:** Always query the complex/authored visual geometry (`CONTACT_COLLISION_LAYER`), ignoring the traversal proxy.
2. **Plant Detection & World-Space Target Latching:**
   * When a foot begins its contact phase (gait phase or velocity dip below threshold), raycast downward from the predicted touchdown point.
   * As soon as the foot touches down on a step tread, its target position is latched in **world space** for the duration of the stance phase.
   * This anchors the foot firmly to the specific stair step while the body moves forward over it, preventing floating and foot sliding.
3. **Pelvis Drop (Hip Offset):**
   * Pelvis is offset downward relative to the capsule root by `max(0, floor_diff)` so the lower foot can reach the lower step tread without stretching.
   * Smoothed via a critically-damped spring or velocity-damped lerp to avoid vertical popping.
4. **Trajectory Warping (Swing Lift):**
   * If the swing foot's trajectory intersects a step riser (in the actual travel direction, whether forward, diagonal, or lateral), procedural swing lift elevates the foot over the obstacle before descending onto the latched contact point.

### 3. Implementation Roadmap
1. **Omnidirectional Tread Search in `foot_ik_ground_sampler.gd`:**
   * Ensure downward ground sampling during locomotion explicitly reaches below the traversal ramp plane to find the authored step tread underneath, regardless of walking direction.
2. **World-Space Stance Latching during Locomotion in `foot_ik_gait_tracker.gd`:**
   * When a foot enters stance on a step tread during walking/sprinting, lock its target in world space until liftoff.
3. **Automated Diagonal Stair Harness Verification:**
   * Add a test walking diagonally across the 0.20m and 0.35m test stairs to verify zero hovering and zero riser clipping across all approach angles.
