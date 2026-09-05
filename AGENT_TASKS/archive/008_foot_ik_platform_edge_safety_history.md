# 008: Foot IK platform-edge safety

Historical investigation archive, frozen on 2026-09-05. Entries include superseded experiments
and old results, not current instructions. See the [active task](../008_foot_ik_platform_edge_safety.md).

## Status

Implemented and under live verification as of 2026-08-27. Do not commit gameplay changes until the
user confirms the live result.

## Problem

When the character keeps pushing diagonally near a platform or stair-landing edge, normal walking
velocity stops but the body can still move slightly. After input release, one foot can remain beyond
the authored platform surface with no contact and zero IK weight, visibly floating over the void.

## Confirmed live evidence

Source: `user://foot_ik_controlled.jsonl`, latest user reproduction ending at frame 1265.

- Frames 566–965 retain edge-directed input and report zero horizontal velocity, but the root still
  accumulates 0.079m of horizontal movement.
- When input reaches zero, `_nudge_to_ledge_safe_zone()` moves the root another 0.225m diagonally.
- The final 40 idle frames have left `contact_hit=true`, `ground_weight=1.0`; right
  `contact_hit=false`, `ground_weight=0.0`.
- The right foot remains beyond the authored surface in its animation pose.

This shows two connected defects: blocked motion can still accumulate collision-recovery movement,
and edge recovery proves only a body-center support point rather than support for both stance-foot
areas. Around the stair gym, traversal collision must not be mistaken for authored foot support.

A later live capture ending at frame 625 exposed a separate transient failure hidden by the final
settled pose. Frames 456–504 place the left solved foot outside its colored safe rectangle while a
blocked lateral input is held and the body turns from about 110 to 86 degrees. At frames 499–504 the
left foot crosses the center line, reaching 0.110m onto the right side, loses contact, and fades from
full weight. By the final 40 frames it has recovered, so the trace analyzer's default `--last-n 40`
originally reported no anomaly.

A jump capture ending at frame 1305 exposed a third edge state. The capsule landed at root
`(14.326, 2.080, 4.221)` facing 89 degrees, balanced on the back lip of the top landing. From frame
1130 through the end, the left foot had no authored contact and zero weight; its deep fallback target
settled on the floor about 2.1m below. The left colored zone was entirely beyond the landing, so no
same-side foot-only target existed. The capsule's lip contact reported a tilted floor normal and the
old slope guard disabled body recovery.

## Required regression

Extend the persistent ledge check with a long-held diagonal edge/corner push, then release input and
observe stable idle. It must fail if:

1. the root creeps after the movement request has been blocked;
2. recovery moves farther toward any unsupported edge; or
3. either final foot lacks authored-surface contact or remains below full planted weight.

The existing short 20-frame movement-only cases are insufficient because they finish before slow
collision recovery or the final idle foot state can be observed.

## Work order

1. Add the failing long-hold and post-release regression using the same split authored/traversal
   surfaces as the live stair landing.
2. Make blocked ledge movement preserve the last safe horizontal root position without breaking
   gravity, floor snap, stairs, ramps, or genuine edge-parallel movement.
3. Make idle recovery validate the authored contact surface for both stance zones; do not accept an
   invisible traversal-only hit as proof that a foot is safe.
4. Ensure an unsupported idle foot retracts to reachable support on its own side of the character.
5. Run ledge, randomized edge stance, walk-to-idle stance, ramps including the 360-degree sweep,
   stair repeat/idle-freeze, `scripts/check.sh`, and the full Foot IK runner.

## Implemented

- Blocked ledge input now restores the frame's starting horizontal position after collision recovery,
  while preserving vertical movement and floor state.
- Unsupported-foot recovery checks a small authored-surface patch around a proposed target and aims
  toward a same-side stance point near the body.
- Cached recovery targets are revalidated against the complete body-relative colored rectangle when
  recovery tries to reuse them. A supported world-space target is discarded when rotation moves it
  outside lateral or longitudinal zone bounds.
- Retraction runs only during idle animation; applying the same correction during active stair
  walking pulled a planted foot sideways through a riser.
- The per-foot retraction flag is reset every frame, so an old successful recovery cannot make a later
  unsupported foot look planted.
- The recovery side guard now follows MotusMan's actual skeleton-local convention: left is positive X
  and right is negative X.
- The ledge regression reproduces the exact long diagonal stair-landing push from the live trace and
  observes the released idle state. Its runner timeout was raised so this longer case can finish.
- A second stair-landing regression holds lateral input, rotates from 109.69 to 68.43 degrees in small
  steps, and checks every intermediate solved pose against the colored zones rather than checking only
  the final recovered stance.
- `scripts/trace.sh --anomalies` now reports `FOOT_SAFE_ZONE` events. Use `--last-n 0` to analyze the
  whole current capture rather than its default final 40 frames.
- Grounded idle recovery now runs after every ordinary movement update, including a zero-input jump
  landing. Its slope guard uses a direct center ray instead of the capsule's potentially tilted lip
  normal, allowing the body to move inward from a flat edge without pulling characters up real ramps.
- The ledge harness includes the exact airborne position, downward velocity, yaw, and landing-edge
  geometry from the frame-1305 reproduction. It requires both feet to regain authored contact and
  full weight after landing.
- Follow-up: movement safety and idle recovery used different effective ray depths. Movement accepted
  a lower platform up to `step_height + 0.25m` below the root, but the idle probe forgot to include
  its 0.20m lifted origin and stopped 0.10m too early. A reachable 0.60m lower platform was therefore
  called void after stopping and the capsule was pushed away. Both paths now use
  `_ledge_support_probe_down()`, and the ledge harness keeps an idle split-height stance with one raw
  foot contact on each level while asserting that recovery does not move the root.
- The next live capture showed a separate failure after a short left strafe and stop on that same
  0.60m split: root `(9.260271, 0.600179, 4.126597)`, yaw `-81.2233°`, left upper-foot contact
  confirmed, but its weight stayed exactly `0.208333` for frames 1116–1329. Normal headless timing
  recovered, so the regression includes both the live movement geometry and a deterministic
  zero-delta modifier evaluation initialized to the captured stale weight. Stationary idle contact
  now finishes at full weight independently of delta; moving swings and unsupported feet remain on
  their existing paths. Future JSONL traces include `raw_weight` and `weight_stuck_time` per foot so
  a smoothing deadlock can be distinguished directly from a bad contact classification.
- A later jump-to-edge capture at root `(9.45454, 0.583385, 4.204419)`, yaw `92.72666°`, had full
  raw/smoothed weights but still floated. The left idle ray alternated between the floor and 0.60m
  platform as animation sway crossed the edge, moving the smoothed target through a 0.456m vertical
  range. A tenth ledge case reproduces that exact stance, samples target height for 300 frames, and
  checks final ankle planting error. The sampler now persistently holds the validated lower surface
  at the chosen target XZ until real movement/turning or support loss, and that reachable contact uses
  the shared 0.60m crouch path rather than the smaller 0.35m direct-step/void classification.
- The next live idle capture exposed a regression introduced by that latch. At root
  `(14.30875, 2.101, 3.75454)`, yaw `67.74570°`, both feet reported valid lower-tread contact and
  full weight, but retained targets roughly 1.2m from the body. The left solved foot remained about
  0.79m outside its colored side. The regression now preserves those exact root/target values and
  requires every cached lower target to pass the same body-relative colored-zone bounds used by
  unsupported-foot recovery.

## Regression rule

Every live Foot IK defect that was not identified by the checks already being run is evidence of a
missing regression. Preserve its exact stance or motion sequence and its observable failure where
possible, make that check fail before the runtime fix, then retain it in the smallest relevant
persistent harness. A final-frame contact/weight assertion is not a substitute for checking the
specific escaped symptom (for example target position, safe-zone membership, stability over time,
or post-solve sole clearance).

The next accepted live test exposed a landing handoff gap rather than a final-pose failure. At root
`(9.839911, 0.600516, 4.049873)`, yaw `97.31033°`, the left probe found the lower floor on frame
775, but `unarmed_jump_land` kept its weight at zero and the rendered sole about 0.60m above that
surface through the landing clip. The lower foot only began planting after idle took over around
frame 808. Preserve the exact airborne start and split-height geometry. The regression now requires
the foot to begin descending immediately, reach 0.12m clearance within 12 frames, move neither foot
more than 0.25m in one frame, and move the rendered hip midpoint no more than 0.15m in one frame.

The eleventh ledge case reproduced both the invisible-floor pause and the later snap as red
regressions. The first attempt forced full plant weight and instant correction as soon as lower
support was validated; this removed the pause but teleported a foot 0.767m and the hips 0.575m in a
single frame. The correct handoff validates that lower support is grounded, reachable, and inside
the correct colored zone, carries that latch through `jump_land` into idle, but still uses the normal
landing grace ramp. A penetrating contact must not use the gait tracker's hard 1.0-weight shortcut
during landing grace. The authored landing animation can also briefly raise its ankle beyond the
ordinary short ray; if the previously latched surface still validates beneath its safe-zone XZ, keep
that proven support instead of releasing the IK chain for a frame. `unarmed_jump_land` uses a 0.25s
blend because its 2.5x playback speed made the former 0.10s blend visibly abrupt.

The next live trace ended at root `(13.91262, 2.100216, 3.627019)`, yaw `90.43482°`, facing from the
2.10m top landing toward a known neighboring 1.20m landing. Forward input reached full strength for
46 frames, but ledge safety held horizontal velocity at zero because the 0.90m drop exceeded the old
0.65m stance-support allowance. The twelfth case reproduces the exact start and landing heights. It
first failed after moving only 0.12m without ever becoming airborne; it now requires sustained airborne
frames, the fall animation, landing on the 1.20m surface, final planted feet, and continued blocking
in the existing true-void cases. `Player.ledge_short_fall_height` defaults to 1.0m and affects only
the moving forward probe. Idle safe-zone recovery deliberately retains the stricter 0.65m Foot IK
support depth.

## Verification so far

- Ledge safety: PASS, twelve cases plus the zero-delta assertion, including the held diagonal case,
  gradual blocked turn, exact jump landing, static 0.60m split support, and its live walk-to-idle
  transition.
- Jump-to-landing-edge recovery: PASS; body moved 0.496m inward and both feet finished planted.
- Random edge stance: PASS, 100 positions and rotations.
- Walk-to-idle stance: PASS, 24 cases and 2184 sampled frames.
- Ramp locomotion: PASS, uphill/downhill on 15, 30, and 45 degrees with 360-degree turns.
- Stair repeat and idle-freeze clearance: PASS.
- Project lint, import, and GDScript parsing (`scripts/check.sh`): PASS.
- The post-fix locomotion runner reached the pre-existing `walk_fwd_left` A/B continuity expectation
  after the edge, ramp, stair, planting, penetration, and stance checks.

Latest short-fall fix: the exact airborne/landing regression, all twelve ledge cases, 100 randomized
edge stances, six ramp locomotion cases, stair repeat, idle-freeze clearance,
and project lint/import/parse pass. The separate static ramp penetration matrix is currently red at
several authored ramp-top edge poses; temporarily accepting every cached target produced the same
failure set, so the new colored-zone rejection is not its cause. Keep that existing matrix issue
visible rather than describing the entire battery as green.

Latest jump-snap fix: the eleventh split-height landing case passes its 12-frame settle and per-frame
foot/hip continuity limits. The main Foot IK runner passed airborne release, all twelve ledge cases,
100 randomized edge stances, 24 walk-to-idle cases, six ramp locomotion cases, stair repeat, and idle
freeze before reaching the already-recorded `walk_fwd_left` A/B expectation. `scripts/check.sh` also
passes. The preserved live source trace is `/tmp/foot_ik_live_jump_snap_20260827.jsonl` for this
working session; `/tmp` is not durable project history.

The next live trace at root `(9.160601, 0.597457, 4.157832)`, yaw `78.97567°`, repeatedly landed
with the left foot on the 0.0m lower surface and the right foot on the 0.60m upper surface. During
`unarmed_jump_land`, the right rendered sole reached 0.493m inside the upper slab and stayed more than
2.5cm below it for 41 frames before recovering in idle. Contact, target, and weight were all valid;
the missing regression was rendered upper-sole penetration during the partial landing IK blend.
The thirteenth ledge case recreates the same local stance on an isolated split platform (the original
coordinates overlap the harness stair ramp), computes the post-modifier sole from its final foot basis
and measured sole depth, and rejects penetration deeper than 5cm or lasting more than three frames.
It failed red at 0.493m/41 frames. During a landing grace height split, the upper leg now uses its full
ground target, weight, and joint correction while the lower leg keeps the smooth ramp. This avoids the
nonlinear partial two-bone blend arcing the upper foot through the slab without restoring the lower-foot
snap. The fixed case measures at most 0.045m for three discovery frames (about 50ms), then zero.

The full Foot IK suite is intentionally expensive because it simulates thousands of animation and
physics frames. A later independent task can split fast and exhaustive tiers and run isolated scenes
in two or three parallel Godot processes; trace-writing scenes must remain serial unless each receives
a unique output path.

The next live trace reproduced a split-height turn snap at stationary root
`(9.948931, 0.600523, 4.080213)`. One foot targeted the 0.0m ground and the other the 0.60m platform;
small yaw changes around `127.517° -> 76.959°` produced repeated rendered-foot jumps of about
0.42-0.53m while the root and hips barely moved. The trace is preserved for this working session at
`/tmp/foot_ik_live_split_turn_snap_20260827.jsonl`. The fourteenth ledge case applies the same turn in
small steps with quiet physics frames between updates, then holds the final yaw; it failed red with a
0.553m one-frame foot move and now rejects any move over 0.12m during the turn and immediate pause.

The failure had several competing owners. Pure rotation discarded a valid lower-support latch, a
quiet frame reacquired it, and the next yaw frame discarded it again. When the target left its colored
zone, the safe replacement changed XZ and height together. During the intended height transition,
idle freeze, the generic landing overwrite, void retraction, and retained stair support could each
replace the in-between target. The sampler now retains a valid world contact through pure rotation,
revalidates it against the rotated colored zone, moves a safe replacement vertically at a bounded
rate, and promotes it directly to a latch when it reaches a valid lower tread. This acquisition
temporarily blocks those competing owners and prevents freeze from arming before the foot finishes.
Sloped ramp targets keep their existing immediate slope path; the special transition is restricted
to flat split-height support.

Latest verification: all fourteen ledge cases pass, including the new turn continuity limit; the
main runner passes airborne, stretch, body penetration, pose continuity, stair locomotion/settle,
100 edge stances, 24 walk-idle stances, six ramp locomotion cases, stair repeat, and idle-freeze
clearance. `scripts/check.sh` passes. The locomotion runner still reaches the already-recorded
`walk_fwd_left` A/B expectation. The independent static ramp matrix remains red at existing ramp-top
poses, and the dense sweep currently reports 259/6240 failing samples (worst depth 0.1488m); keep that
separate known issue visible rather than calling the exhaustive ramp battery green.

## Current handoff: lower leg intersects a platform side wall

## Negative rendered-knee guard awaiting live confirmation (2026-08-30)

Follow-up live capture `/tmp/foot_ik_live_20260830_104950.jsonl` showed a separate periodic idle
artifact: at every 2.5s `unarmed_idle` loop, the visible left knee changed
`23.75° -> 28.94° -> 20.70°` and later approached `5°`. Both feet and targets stayed stable and the
negative-knee clamp never ran. The source idle contains a one-shot leg-settling intro that was being
replayed by `LOOP_LINEAR`. Retargeted gameplay idle now makes only the six leg rotation tracks
periodic by easing from the clip-end rotations into the authored first 0.35s; upper-body breathing
tracks are unchanged. A two-loop regression reduced the worst rendered knee change from `8.24°` to
`0.46°` per frame.

Post-fix validation: `scripts/check.sh` and the focused two-loop test pass. The full map retains the
known five ledge failures and the existing `walk_left`/`walk_right` failures. Ramp matrix failures
remain in the existing steep/top-edge set; the dense sweep improved from 259 to 257 failures out of
6240, with unchanged worst depth `0.1488m` and no joint-limit failures. Await live confirmation.

The comparison row then exposed periodic red IK/authored differences in every stationary locomotion
preview (walk, sprint, left/right strafe, both forward diagonals, and crouch walk). These bodies play
locomotion in place on a flat pad; the gait sampler was still treating lifted swing feet as a reason
to solve, although the root never translated. Flat, non-translating walk/sprint clips now explicitly
pass through their authored pose. This does not apply once the body translates or on non-flat
support. `foot_ik_animation_comparison.gd` now has a 360-frame automated check covering all eight
IK-off/on pairs, wired into `scripts/check_foot_ik.sh`; all eight pass.

The 2026-09-03 live trace at root `(14.30828, 2.101, 3.989683)`, yaw `67.7457°`, showed
stationary `unarmed_idle` with fixed ground targets but 0.176m of repeated left-foot drift. The left
freeze streak reached 30 and was cancelled twice: first because the uncorrected animated ankle was
below support even though the final IK foot was valid, then at the 2.5s loop seam because a missed
ankle ray represented the animated foot itself as a distant raw target. Freeze no longer releases
from pre-IK penetration, and target-drift release ignores a missed ray only during the bounded
animation-seam suppression window; validated previous support, void, movement, and turning rules
retain their releases. The exact stair-top pose is covered
by `foot_ik_idle_plant_stability_check`: it failed red with zero left frozen samples and 0.175630m
drift, then passed with both feet frozen for all 120 samples and 0.004147m/0.003706m drift.

Post-fix validation: `scripts/check.sh` passes. The main suite reaches its known 45° ramp spin limits
only after the new idle stability check, 24 walk-to-idle cases, 100 edge stances, 16 ledge cases,
and its earlier focused checks pass. Locomotion retains the known `walk_left`/`walk_right` failures.
The static ramp matrix retains its documented top-edge failures, and the exhaustive sweep is unchanged
at 257 failures out of 6240 with worst depth `0.1488m`.

The next live trace, preserved at `/tmp/foot_ik_live_20260904_002011.jsonl`, rotated in idle across
the overlapping preview stairs near root `(11.69, 0.84, 1.88)`. The selected right-foot support
changed from the 0.60m tread to the 0.80m tread immediately, but the rendered ankle continued toward
it under the standing solver's 45°/s joint correction limit. The standing-only rate is now doubled
to 90°/s; crouch, locomotion, target acquisition, and safe-zone rates are unchanged.

Routine iteration no longer needs the roughly 20-25 minute dense ramp sweep. The new
`scripts/check_foot_ik_fast.sh` runs project parsing plus high-signal core, stair, edge, landing,
split-stance, idle-seam, and planted-idle regressions serially. The existing ramp matrix/sweep and
full entrypoints remain the explicit exhaustive tier for confirmed changes and solver/ramp work.

The next live stair-turn trace is preserved at `/tmp/foot_ik_live_20260904_003830.jsonl`. At a
stationary root near `(11.60, 0.97, 2.20)`, the right leg alternated between `solve_to_support` and
`limit_stance_crossing` while yaw crossed roughly -147 through +162 degrees. The rendered right foot
jumped by 0.22-0.32m on several individual frames even though its support and full weight remained
valid. The stance guard rendered its reduced safe correction but left the rate-limit history holding
the unrestricted rejected correction, so later evaluations repeatedly started from the wrong pose.
The guard now commits its final hip and knee corrections back to that history. The planted-idle
regression includes the captured turn sequence plus a direct cache/render ownership invariant; the
invariant fails before the fix and passes afterward.

The same capture also contains a separate walk-to-idle snap at frame 471: supported idle forced the
left/right weights from `0.347/0.069` directly to `1.0`, moving both rendered feet and knees about
0.14-0.16m in one frame. The immediate supported-idle repair was intended only for Godot's extra
`delta == 0` modifier refresh, where time-based smoothing cannot advance, but it also ran on normal
60 Hz frames. Normal timed evaluations now retain `ground_weight_rise_time`; the zero-delta stale
weight repair remains intact. The planted-idle regression asserts both paths independently.

The next live idle pose is preserved at `/tmp/foot_ik_live_20260904_075825.jsonl`. For all 1,356
retained frames the root stayed still on a 0.20m split support, while the left leg held a roughly
73-degree bend with its knee displaced about 0.28m laterally from its hip. Both legs reported
`clamp_negative_knee` continuously. The negative-knee guard had moved an invalid pole only a 0.001
fraction beyond the sign boundary; on a deeply flexed leg that legal-but-nearly-sideways pole still
looked broken. The clamp now requires a modest 0.5 normalized alignment with the authored bend pole.
This is deliberately short of the previously rejected full pole mirror, which caused platform-corner
calf collisions. The injected-negative regression now fails a boundary-only result and requires the
same authored-direction margin.

The following right-leg pose is preserved at `/tmp/foot_ik_live_20260904_090239.jsonl`. The final
right knee itself was not inverted: it had only about 4.9 degrees of flexion, with the entire nearly
straight leg reaching roughly 0.63m diagonally from hip to foot. Its owner remained
`landing_commitment` throughout hundreds of idle frames. The predicted root was still 0.517m away,
but horizontal airborne correction had necessarily stopped at touchdown, making that commitment
impossible to complete and leaving its distant foot target in permanent control. On the idle
handoff, a commitment whose root remains over 0.05m away is now retired so current physical support
can reacquire both feet. A deterministic regression injects a same-height commitment 0.52m from a
grounded idle root and requires both the planner and per-foot ownership to clear; it is included in
the fast and full Foot IK entrypoints.

The immediate retest is preserved at `/tmp/foot_ik_live_20260904_093352.jsonl`. The stale landing
owner was gone and the right leg had a valid 37-degree forward bend. The visibly extreme leg was now
the left upper-support leg: a valid but strongly lateral 87-degree bend on a mere 0.20m height split.
Higher-foot reposition was enabled but its 112-degree preferred-flexion default classified this pose
as acceptable. The preferred/retained thresholds are now 70/80 degrees, preserving 10 degrees of
hysteresis while repositioning before the knee reaches the escaped pose. A replay of the exact
1.20/1.00m support layout requires the upper knee to remain at or below 80 degrees and validates each
sole against its own split surface. It settles near 70 degrees with both sole errors under 1mm and is
included in both regression tiers.

Final map after the comparison fix: `scripts/check.sh` PASS; animation comparison 8/8 PASS; main
Foot IK runner reaches the same five known ledge failures; locomotion retains the known moving
`walk_left`/`walk_right` failures; ramp matrix retains known steep/top-edge failures; dense sweep is
257/6240 failures (two fewer than before this idle work), worst depth unchanged at `0.1488m`.

The latest live preview reached a signed knee label of `-18°` while both feet had valid flat-floor
support and full IK weight. The closed-form target pole was valid, but independent hip and knee
correction rate limits could leave the final rendered knee on the negative side of the hip-to-foot
line. The solver now validates that final rate-limited pose during upright idle/walk. A negative
result is moved by the minimum amount to the zero-degree boundary with a tiny positive bias; an
earlier full forward mirror was rejected because it introduced two platform-corner calf collisions.

`foot_ik_knee_flex_check.gd` now samples signed knee flexion on every eligible frame and includes a
deterministic injected-negative-pose regression. JSONL foot records now include `target_owner`,
`solver_action`, `decision`, `signed_knee_flexion_deg`, and `negative_knee_clamped`; the top-level
`ik_decision` combines both readable per-foot decisions for compact inspection.

Final validation map after the minimal correction:

- `scripts/check.sh`: PASS.
- Focused injected negative-knee regression: PASS.
- `scripts/check_foot_ik.sh`: reaches the existing ledge suite failures (five: two final contact
  ownership cases and three continuity thresholds); no new corner-volume failures remain.
- `scripts/check_foot_ik_locomotion.sh`: existing `walk_left` and `walk_right` cases remain red,
  although their added rotation spikes decreased materially with the new boundary correction.
- `scripts/check_foot_ik_ramps.sh`: existing steep/top-edge penetration matrix failures remain;
  joint-limit failures are empty.
- `scripts/check_foot_ik_ramp_sweep.sh`: unchanged 259/6240 failures, worst depth `0.1488m`, with
  no joint-limit failures.

Do not commit until the user reproduces the former `-18°` stance in the live preview and confirms
that the knee no longer crosses negative without a new visible snap or obstacle intersection.

The newest live report has a **candidate fix awaiting live confirmation**. The user stopped at an idle split-height pose near the
outer side of the 0.10m staircase in `foot_ik_preview.tscn` and saw a leg clip through the platform's
vertical edge. Preserve the captured trace for this working session at
`/tmp/foot_ik_live_edge_clip_20260827.jsonl` (copied from
`user://foot_ik_controlled.jsonl`, modified `2026-08-27 12:55:52 -0300`). Its last recorded frame is
1245. `scripts/trace.sh --anomalies` does not flag the final pose because both ankle/sole contacts are
valid; this is a leg-segment-versus-solid-volume defect.

Frame 1245 is stationary `moves/unarmed_idle`, root `(8.585059, 0.600102, 3.853755)`, yaw
`41.802564°`. The stair platform occupies `x >= 8.5` and its top is `y = 0.6`. The left foot uses the
lower floor: surface target `(8.480538, 0.0, 3.953255)`, solved ankle
`(8.481530, 0.105135, 3.953629)`, and sole clearance about `+0.0091m`. However, its solved knee is
`(8.530951, 0.560874, 3.972247)`: the knee center is 3.1cm inside the platform and 3.9cm below its top.
The shin therefore crosses the vertical face even though the foot is correctly planted. The right
foot is correctly planted on top at target `y = 0.6` and ankle `y = 0.69601`.

Add a focused red regression before changing runtime behavior. Recreate the exact 0.60m-high side
edge, root-relative placement, and yaw (translate it to isolated harness coordinates if needed), then
measure the post-modifier hip/knee/foot chain against the platform's closed side volume. At minimum,
the lower leg's knee and knee-to-foot segment must remain outside the upper slab while below its top;
allow for visible leg thickness if the harness can reuse the CPU-skinned mesh penetration helpers.
Do not settle for contact, target height, sole clearance, or safe-zone assertions: all four already
pass in the broken frame. This belongs in the persistent ledge/split-height regression set (currently
14 cases), or in a small dedicated closed-volume leg check called by `scripts/check_foot_ik.sh`.

The fifteenth ledge case now recreates the isolated 0.60m side edge at the exact root-relative
placement and yaw. It initially failed because the settled lower knee cleared the slab by only 0.035m
against a 0.040m minimum. The final check also CPU-skins the affected left thigh/shin/foot chain and
tests its vertices against the upper slab's closed box volume every ten frames after warmup, while a
separate per-frame check rejects any lower-foot correction over 0.12m during acquisition. Filter the
mesh sample to the affected leg: an empty filter also counts the correctly planted opposite foot near
the slab top and produces a misleading failure unrelated to the reported lower-leg clip.

The candidate fix is in `FootIKGroundSampler._rehome_lower_surface_from_riser()`. For stationary idle
on flat split-height support only, it checks whether the lower target has a 0.24m same-height support
patch. If not, four neighboring probes identify which direction contains a higher flat surface; the
sampler searches in 0.04m steps away from that neighbor for a same-height patch that remains inside
the affected foot's colored stance rectangle. It feeds that surface through the existing bounded
lower-support acquisition instead of dropping contact or hard-coding the captured world edge. Do not
run this rehome during `jump_land`: an intermediate attempt did so and regressed the existing upper-
foot landing penetration case. Continuous ramps remain excluded by the flat-surface requirements.

Verification on the candidate: all 15 ledge cases pass, including 12 settled CPU-skinned samples with
zero affected-leg vertices inside the slab. `scripts/check.sh` passes. The main Foot IK runner passes
airborne release, stretch, stair body penetration, pose continuity, stair locomotion/settle, 15 ledge
cases, 100 randomized edge stances, 24 walk-idle stances, six ramp locomotion cases, stair repeat, and
idle-freeze clearance before reaching the already-recorded `walk_fwd_left` A/B expectation. The dense
ramp sweep is unchanged at 259/6240 failures with the same 0.1488m worst depth; the independent static
ramp matrix remains its known red diagnostic. Await the user's interactive test before committing.

## Current handoff: two lower legs at the platform corner

The next live test still clipped at the top landing's outer corner. Preserve that source trace for
this working session at `/tmp/foot_ik_live_edge_clip_after_fix_20260827.jsonl` (copied before running
any harness). Its stable last frame is 1977: root `(8.602919, 0.600554, 3.874536)`, yaw
`-23.285968°`, with both soles correctly planted on the 0.0m lower floor. The landing slab occupies
`x=[8.5, 11.5]`, `z=[3.6, 4.1]`, and `y=[0.0, 0.6]`. The earlier side-only fix moved the left target
away from the x face, but the right knee remained at `z=4.039888`, about 6cm inside the back face while
below the slab top. This is a corner stance, not the earlier single-side stance.

The sixteenth ledge case, `idle_both_lower_legs_clear_platform_corner_live_repro`, translates that
exact root/yaw to an isolated copy of the same closed slab. After warmup it checks both lower knee
clearances and CPU-skins both complete leg chains against the box every ten frames. Before the new
fix it failed all 12 mesh samples, with 468 penetrating vertices and 5.2cm maximum depth. Merely
widening the lower-foot patch cleared the knee centers but left thigh-skinned vertices inside, proving
that joint positions alone were still insufficient.

The current candidate uses a 0.32m clearance ring for flat lower idle support. Sixteen angular probes
catch a platform corner that four cardinal probes miss. The bounded search explores motion away from
the higher face and along its tangent, keeps candidates inside the affected foot's colored zone, and
selects the smallest total displacement rather than the first nested-loop match. The sampler retains
the detected world-space escape direction while that lower support is owned. During validated idle
only, the two-bone solver uses it as the knee pole, so the thigh and shin bend away from the vertical
wall; moving, airborne, jump-landing, and sloped-ramp legs keep their existing bend behavior.

Current verification:

- All 16 ledge cases pass, including 12/12 settled corner mesh samples with zero vertices inside the
  slab and the earlier single-side mesh/foot-continuity case.
- `scripts/check.sh` passes.
- The broad runner passes stretch, airborne release, body penetration, pose continuity, stair
  locomotion/settle, 100 randomized edge stances, 24 walk-idle stances, all six ramp locomotion cases,
  stair repeat, and idle-freeze clearance. It still stops at the already-recorded `walk_fwd_left` A/B
  continuity expectation.
- The independent static ramp matrix remains its known red diagnostic. The dense ramp sweep is exactly
  unchanged at 259/6240 failed poses with the same 0.1488m worst depth.

This is still awaiting the user's interactive confirmation. Do not commit the unfinished Foot IK
work until the live corner stance is visibly clean.

## Current handoff: upper foot drops after jump landing

The next live trace is preserved at
`/tmp/foot_ik_live_jump_land_right_down_up_20260827.jsonl` (copied from the live JSONL before any
harness ran). The jump begins from stationary root `(8.371093, 0.495433, 4.28113)`, yaw
`82.825107°`. At frames 3204-3205 the animated right foot briefly samples the 0.0m lower floor and
records it as landing support. Frames 3206-3225 then prove the right foot on the 0.60m upper platform
with exact contact and full plant weight. Landing grace masks the old lower claim during those frames.
When grace ends at frame 3226, the stale 0.0m target takes control; the ankle descends from about
0.696m to 0.460m, then returns upward during the idle handoff. Frame 3235 also showed a separate
roughly 0.44m one-frame release to the authored pose while the animated ray temporarily missed.

`foot_ik_landing_stability_check.tscn` now reproduces the complete real jump, including the 0.0m
surrounding floor. Omitting that floor made the first harness falsely pass because idle ledge recovery
moved the root inward before takeoff. The persistent regression waits for airborne travel and four
confirmed upper-support frames, then rejects any later target below 0.55m, ankle below 0.55m, or
right-foot frame step above 0.15m. Before the fix it saw the target fall to 0.0m, the ankle reach about
0.39m, and a later 0.52m one-frame jump.

The current candidate treats four consecutive close, flat upper contacts as stronger evidence than
an older lower landing claim. It retires the lower latch/acquisition, stores the proven upper surface,
and carries that surface through temporary `jump_land` contact misses until normal idle freeze takes
ownership. This preserves the earlier behavior for a genuinely lower foot whose ray disappears, while
preventing both the delayed down/up cycle and the release-to-animation spike for a proven upper foot.

Verification on this candidate:

- The new landing stability check passes with target minimum 0.600m, ankle minimum 0.678m, and maximum
  right-foot frame movement 0.021m.
- All 16 ledge cases pass, including the existing lower-foot landing handoff, upper-foot penetration,
  turn continuity, and both closed-volume leg-edge cases.
- `scripts/check.sh` passes. The broad runner passes through its regular edge, ramp locomotion, stair,
  penetration, and stance checks before the already-known `walk_fwd_left` A/B expectation.
- The static ramp matrix remains its known red diagnostic. The dense ramp sweep remains exactly
  unchanged at 259/6240 failures and 0.1488m worst depth.

Await another interactive jump at this corner before committing the unfinished Foot IK work.

## Current handoff: preview FPS regression from lower-support search

The live trace preserved before profiling is
`/tmp/foot_ik_live_performance_20260827.jsonl`. It contains 307 consecutive physics samples from frames
17-323, averaging about 12KB per JSONL row. It did not measure FPS: `frame` is the physics-frame count
and `time` is the current animation position. The debug overlay now also records `render_fps` in each
row, so the next interactive capture can confirm real render performance rather than inferring it from
physics or animation fields.

The FPS drop was real and mostly came from the new lower-platform corner search, amplified by this
stress scene's roughly 28 live character instances. In a repeatable headless fixed-FPS run of 600
preview frames, the current exhaustive search took about 23.1 seconds. Skipping the complete new lower-
support path took 13.3 seconds. Disabling only the debug overlay did not materially change that result,
so the rolling JSONL and head trail were not the main cause of this particular regression.

The optimized candidate keeps the 0.32m/16-ray clearance proof but removes the nearly 1,000-position
away-by-tangent grid. The four higher-neighbor probes produce a direct escape direction; at a platform
corner their vectors naturally sum into a diagonal. It tests at most 24 positions along that direction,
nearest-first, and caches a cleared static support until its latch or stance becomes invalid. Ordinary
flat ground and ramps also skip the extra deep support validation unless a flat lower direct sample is
actually inside that foot's stance zone. The same 600-frame preview run now takes about 12.1 seconds.

Verification after the performance fix:

- All 16 ledge cases pass, including the exact-corner CPU-skinned mesh check.
- The jump-landing stability check still passes: target minimum 0.600m, ankle minimum 0.678m, and
  maximum right-foot movement 0.021m.
- `scripts/check.sh` and `git diff --check` pass.

This remains uncommitted and still needs the user's interactive FPS and jump/edge confirmation.

## Current handoff: lower foot walks on an invisible upper floor

The next live capture is preserved at
`/tmp/foot_ik_live_lower_foot_invisible_floor_20260827.jsonl` (1,391 rows, frames 317-1707). At the
reported split stance, frame 1481 has the left target on the 0.60m platform and the right target on the
real 0.0m floor. Movement begins at frame 1483. On frame 1484, while `unarmed_idle` is still active,
the right target jumps from 0.0m to 0.671m, `contact_lost=true`, but its smoothed IK weight is still
0.93. The same transition repeats on later movement attempts. Render FPS in this interactive trace is
46-61, so this visual defect is not a low-FPS artifact.

`foot_ik_split_stance_walk_check.tscn` reproduces the exact root `(9.258939, 0.585117, 4.203303)`,
yaw `-88.3°`, 0.60m top-landing bounds, surrounding 0.0m floor, settled split stance, and gradual
forward input. For every early movement frame where the lower right foot still has at least 0.5 IK
weight, it raycasts the real collision beneath the stored target and rejects a height mismatch above
0.12m. It also measures the rendered post-modifier sole and rejects a gap above 0.15m. Before the fix
it fails on movement frame 2 with a 0.665m unsupported target gap at 0.93 weight.

The cause had two layers. The moving void path replaced the last physical target with the animated
ankle before its IK weight faded. On the following walk frames, the ordinary short ray could no longer
reach the 0.0m floor from the rising authored foot, so the modifier's no-contact early exit released
the leg directly to the platform-relative walk pose. The candidate now keeps the last target during a
void fade. On a short-ray miss, the ground sampler also performs a bounded deep probe at the previous
plant X/Z; only if real collision still matches that surface does it route the sample through the
ordinary gait/contact path. Thus weight fades or contact returns against the real lower floor rather
than an invisible animated target. Live traces now include each foot's `raw_target` as well as its
smoothed target for future writer-vs-sampler diagnosis. Retaining the target fixed the stored value but
not the rendered leg: the sole still rose 0.245m at 0.51 weight because the modifier first interpolated
the requested target toward animation and the two-bone solver then faded the correction a second time.
The previous-support release now requests the real ground target directly and lets only the solver's
chain weight perform the visual fade. Ordinary flat-ground locomotion keeps its authored-pose path.

Verification on the candidate:

- The new split-stance walk check passes with a 0.000m maximum weighted unsupported-target gap and a
  0.042m maximum weighted rendered-sole gap (previously 0.245m after the target-only fix).
- All 16 ledge cases and the jump-landing stability check pass.
- The broad suite passes edge stance (100), walk-idle stance (24), all six ramp-locomotion cases,
  stair repeat, idle freeze, and ordinary locomotion/matrix cases through the already-known
  `walk_fwd_left` A/B expectation.
- `scripts/check.sh` and `git diff --check` pass. The dense ramp sweep is exactly unchanged at its
  known 259/6240 failures and 0.1488m worst-depth baseline.

This remains uncommitted pending the user's interactive confirmation.

## Current handoff: 2x split-height reposition speed

The user's next live test rotated in front of the platform repeatedly, making feet move between the
upper and lower surfaces. The behavior was correct but the reposition looked too slow. The live trace
was preserved before running any harness at
`/tmp/foot_ik_live_slow_split_reposition_20260827.jsonl`.

`IDLE_LOWER_ACQUIRE_SPEED` is now 4.0m/s instead of 2.0m/s. A target-only rate increase exposed two
continuity defects in the existing `idle_split_height_turn_pause_no_leg_snap_live_repro` regression.
First, the faster lower target drove the reach-limiting pelvis correction immediately and moved a
rendered foot 0.143m in one frame (over the existing 0.120m limit). Split-height acquisition now uses
the same 2x rate for the bounded idle pelvis engagement. Second, horizontal lower-foot rehoming made
one bounded step, then `_update_idle_lower_transition()` copied the destination X/Z directly and
snapped the remaining distance; removing that axis shortcut makes the complete Vector3 follow the
same 4.0m/s bound.

Verification after the coordinated speed change:

- All 16 ledge cases pass, including split-height turn continuity.
- Split-stance walk support passes with 0.000m target error and 0.041m maximum weighted sole gap.
- Jump-landing stability and all six ramp locomotion cases pass.
- `scripts/check.sh` passes. The broad suite reaches only its known `walk_fwd_left` expectation.
- The dense ramp diagnostic is exactly unchanged: 259/6240 failures, 0.1488m worst depth.

This remains uncommitted pending interactive confirmation that the 2x handoff feels fast enough and
still looks smooth.

## Current handoff: excessive upper-knee bend in a split-height idle

The next live capture is preserved at
`/tmp/foot_ik_live_bent_knee_last_frame_20260828.jsonl`. In its last 40 frames the upper left knee
holds near 131 degrees of flexion while the lower right leg is almost straight (about 10 degrees).
The lower leg is already near its full 0.888m reach, so the shared pelvis cannot rise enough to
straighten the upper leg. This is not a missing hard constraint: the solver already caps knee flexion
at 150 degrees and hip swing at 100 degrees.

Biomechanics references place roughly 110-135 degrees in full/deep-squat territory, while healthy
maximum knee range may reach roughly 150 degrees. The candidate therefore preserves the 150-degree
hard safety cap but uses 110 degrees as a preferred upper-knee limit for a flat, idle split stance.
`FootIKGroundSampler.straighten_compressed_upper_target()` moves only the compressed upper foot to the
nearest real support point at the same height, inside its colored zone, with a support patch and a
predicted hip swing below the existing hard limit. Lowering the hard knee cap alone was tested and
rejected: it reduced the bend only slightly and made the sole miss/enter the platform because the
requested endpoint was no longer reachable.

`foot_ik_knee_flex_check.tscn` recreates the exact root, yaw, 0.60m platform, and lower floor. It
failed before the fix at 136.73 degrees, then passes at 109.09 degrees with both soles on support,
82.40-degree upper hip swing, and effectively zero target error. A shared
`FootIkJointLimitCheck` now checks the modifier's 150-degree knee and 100-degree hip hard limits in
the ledge/stair, randomized edge, ramp-locomotion, dense ramp, landing, split-stance walk, and broad
locomotion regressions. It checks only a leg with a non-trivial Foot IK correction: the authored
crouch reaches 102.17 degrees of hip swing but has zero IK-added rotation, so treating that authored
pose as a solver violation was a false failure.

Verification on the candidate:

- `scripts/check.sh` passes.
- The exact knee check, landing stability, split-stance walk, all 16 ledge/stair cases, all 100 edge
  poses, and all six ramp-locomotion cases pass with the shared joint checks enabled.
- The broad locomotion suite passes idle, crouch, forward/backward walk, and both strafes, then reaches
  only its already-recorded `walk_fwd_left` A/B expectation. No joint-limit check fails.
- The dense 6,240-pose, 360-degree ramp sweep reports no joint-limit failures. Its independent known
  red surface-contact baseline is exactly unchanged at 259 cases and 0.1488m worst depth.

This remains uncommitted and needs the user's interactive confirmation that the upper leg now looks
natural without a visible foot slide during the rehome.

### Follow-up: odd knee direction after rotating around the corner

The next live trace is preserved at
`/tmp/foot_ik_live_odd_knee_angle_20260828.jsonl` (1,272 contiguous frames). Its final upper left knee
is flexed about 137 degrees and the thigh is 86.3 degrees from straight down. The knee pole itself is
mostly forward—only about 11 degrees sideways—so the strange silhouette comes mainly from the thigh
being almost horizontal, not from an inward/outward knee twist.

This pose cannot be reproduced by spawning directly at the last root because it depends on retained
support while rotating. The persistent knee harness now accepts a gradual turn and the canonical
script replays the live transition from root `(8.649, 0.575, 4.231)`, yaw `89.2` degrees, to
`-47.121` degrees. Before the follow-up it retained the deep bend. The compressed-upper search used
only 24 directions; it now samples 36. A temporary 2.5cm support patch made the first turn pass but
allowed too much sole overhang and still could not solve the next yaw. The final candidate keeps the
original 10cm patch. When a candidate satisfies knee, hip, same-height collision, and colored-zone
constraints but fails only that patch, its missing patch rays request a slow inward capsule nudge
from ordinary idle ledge recovery. The root moves only until the candidate has full support.

The investigation also found that `lower_riser_away` could outlive the lower surface that created it.
That wall-escape knee pole is required by the existing both-legs-lower corner clearance case, so it
cannot simply be restricted to a height comparison with the other foot. It now records its owning
surface height, is cleared when the foot reaches a surface that already has wall clearance, and is
used only while the current target remains on that same height. Target hip-angle prediction and the
final solve now share the same pole calculation.

The incremental-turn check passes repeatedly at 107.76 degrees upper-knee flexion, 80.05 degrees hip
swing, zero sole clearance, and effectively zero target error. The earlier captured knee check passes
at 107.70 degrees. All 16 ledge/corner cases, 100 randomized edge poses, six ramp-locomotion cases,
landing stability, and split-stance walking pass. Broad locomotion has no joint failures and reaches
only its known `walk_fwd_left` A/B expectation. The dense ramp diagnostic is exactly unchanged at its
known 259/6240 surface failures, 0.1488m worst depth, with no joint-limit failures.

This remains uncommitted pending live confirmation of both the knee silhouette and the amount of
natural sole overhang at the corner.

### Follow-up retest: another shallow corner yaw

The retest is preserved at `/tmp/foot_ik_live_odd_knee_retest_20260828.jsonl` (1,453 retained rows).
Its final root is `(8.698424, 0.551424, 4.323343)` at yaw `-24.6611` degrees. The upper left sole is
supported and inside its colored zone, but the knee remains at 134.18 degrees and the thigh reaches
91.91 degrees from down—slightly past horizontal. The relevant ownership begins around frame 3181 at
root `(8.769, 0.551, 4.278)`, yaw `89.6` degrees, with left-lower/right-upper support; direct final-
frame spawning does not recreate it.

The canonical knee regression now replays that complete turn. With the supported-root nudge, the
root moves about 10cm inward and the result passes at 108.41 degrees upper-knee flexion, 99.44 degrees
hip swing, zero sole gap, and negligible target error. The earlier two knee cases still pass, as do
all 16 ledge/corner cases, 100 randomized edge poses, six ramp cases, landing stability, and split-
stance walking. This remains uncommitted and needs another live turn/visual confirmation.

### Follow-up: 45-degree upright knee-down limit

The user requested that a standing/walking procedural knee remain generally down instead of allowing
the thigh to approach horizontal. Flat, non-crouched idle/walk Foot IK now uses a 45-degree maximum
thigh swing from `Vector3.DOWN`; crouch, jump/landing, and sloped surfaces retain the existing
100-degree hard safety cap. Authored flat locomotion remains untouched when IK contributes no leg
correction.

A first implementation clamped the final thigh direction. It kept the number below 45 degrees but
made the solved foot miss its target by 0.22-0.34m; trying to move the root from that endpoint error
could walk the capsule off the platform. The final implementation preserves the two-bone endpoint:
when the authored/riser knee pole would produce more than 45 degrees, it binary-searches the smallest
rotation of that bend plane toward down around the hip-to-foot axis. Target prediction and final solve
share this pole, so the thigh limit does not create a floating or penetrating foot.

All three captured knee scenarios pass at approximately 44.94-44.96 degrees thigh swing, 107-109
degrees knee flexion, zero sole gap, and negligible target error. All 16 ledge/corner cases, 100 edge
poses, six ramp-locomotion cases, landing stability, split-stance walking, and ordinary locomotion
through the known `walk_fwd_left` stop pass. Applying the rule to slopes was explicitly rejected after
30/45-degree ramp penetration failures; the final flat-only scope restores those baselines.

### Follow-up: superseded 45-degree rule and raised-leg deformation

The next live pose is preserved at
`/tmp/foot_ik_live_deformed_45_limit_20260828.jsonl` (981 rows, final frame 997). At root
`(8.758182, 0.600149, 4.085211)`, yaw `73.70446` degrees, the right foot was on the 0.60m platform
and the left foot on the floor. The 45-degree thigh rule put the right knee 6.2cm below its ankle, so
the calf folded upward even though the reported thigh angle passed. Lowering that thigh angle farther
would move the knee farther down and worsen the deformation. The 45-degree upright pole constraint is
therefore superseded and removed; the ordinary 100-degree hip safety cone remains.

The standing split-height policy now chooses an upper target aiming for at most 112 degrees of knee
flexion and retains an already verified target through idle sway up to 120 degrees. This two-level
rule avoids discarding/reselecting the plant every time the animated hip moves a few centimetres.
Upper-target acquisition moves across real same-height support at 2m/s. Exact correction is enabled
only once that eased target is within 1cm of the cached point; making it exact immediately produced
0.38-0.49m one-frame joint snaps and was rejected. Automatically moving the capsule until both feet
were upper was also rejected: the captured platform is only 0.50m deep, so some rotated footprints
cannot fit both feet, and the attempted recovery walked the body off the platform.

`foot_ik_knee_flex_check.gd` is now side-independent and includes the mirrored latest pose. It checks
the upper knee at 120 degrees maximum, explicitly requires the upper knee to remain above its ankle,
requires real upper/lower sole contact, and caps one-frame hip/knee/foot movement at 0.25m. The four
canonical cases finish with upper flexion 105.36-116.19 degrees, knee 0.069-0.281m above the ankle,
negligible target error, and 0.145-0.168m worst one-frame joint movement (the older turning case is
0.206m during initial setup). The complete Foot IK script passes ledges, landing, split walking, all
four knee cases, 100 randomized edges, 24 walk-to-idle cases, six ramps, and repeated stairs, then
reaches only the known `walk_fwd_left` A/B stop. `scripts/check.sh` passes. This remains uncommitted
pending interactive visual confirmation.

### Follow-up: over-height split stance moves the body to common support

The newest live trace is preserved at
`/tmp/foot_ik_live_raised_shin_20260828.jsonl`. Its final idle pose held one target on the 0.60m
platform and the other on the floor. The raised thigh was 95.87 degrees from down (slightly above
horizontal), with 109.33 degrees of knee flexion. Although the flex value was below the preferred
limit, the 0.60m surface split exceeds `Player.step_height` (0.40m), so no leg-only target adjustment
can make this a normal relaxed stance.

The candidate now treats such a deformed over-height split as a body-placement request. It searches
outward in 5cm rings for a root position where the capsule center and both raw animated foot probes
all find real support at the same height. It first tries the platform top. When the rotated footprint
cannot fit on that narrow top, it searches the nearest exposed lower-floor stance instead; the lower
ray starts above the upper slab so it cannot accidentally select floor hidden underneath solid
platform geometry. This supersedes the rejected upper-only capsule move described above: the missing
piece was a physically supported lower fallback.

The lower fallback is a small real fall, not a vertical teleport. It keeps the idle body animation
and Foot IK active until the capsule touches down. Disabling Foot IK during that handoff caused a
0.427m joint snap; preserving only the idle animation let the released foot fall 0.31m below the
floor and still snapped on landing. Keeping both active reduced the worst rendered joint step to
0.189–0.223m. A stale descent flag was also found by the ordinary airborne check and is now cleared
when a pending request disappears before the player ever leaves the floor.

The four captured knee cases now finish on common real support. One fits both feet on the 0.60m top
(33.49/42.67-degree knee flexion, 0.133m worst joint step); the other three settle on the exposed
floor (12.97–25.87-degree flexion, 0.189–0.223m worst joint step). Both knees remain above their
ankles and both soles have negligible contact error. The 16-case ledge harness now expects common
support for the affected over-height cases instead of requiring the obsolete permanent 0.60m split.

Verification passes the airborne, stair, ledge, landing, split-walk, four knee, 100 randomized edge,
24 walk-idle, six ramp, repeated-stair, and idle-freeze checks. The broad locomotion run still stops
only at its already-known `walk_fwd_left` A/B expectation. This remains uncommitted pending the
user's interactive confirmation of the actual transition and final silhouette.

### Follow-up: predict the safe stance before jump contact

The next live trace is preserved at
`/tmp/foot_ik_live_prelanding_safe_zone_20260828.jsonl`. It proves that the post-landing recovery was
still visibly late: the capsule contacted the platform edge at frame 1188, the left/right targets
then remained split at 0.60m/0.00m for the complete landing animation, and horizontal safe-zone
movement did not begin until idle at frame 1220. The character therefore showed the unwanted split
stance for roughly half a second before the correct recovery started.

Descending jumps with released movement input now project both current animated foot XZ positions
onto nearby flat collision surfaces. If their predicted height difference exceeds the physical
0.40m step range, the existing radial safe-root search runs before contact, prefers common upper
support, and falls back to common exposed lower support. The result is cached for that descent and
followed at 3m/s, so the expensive support search is not repeated every airborne frame. Active
movement input remains authoritative; prediction starts once the player releases it near landing.

The persistent knee harness now replays the live jump approach from root
`(9.053116, 0.6001, 3.915929)` at yaw `-88.328` degrees. It requires the predictive target to become
active while airborne and rejects more than 8cm of horizontal safe-zone correction after first
contact. The candidate lands directly with both targets on the 0.60m platform, finishes at root
`(9.116593, 0.600468, 3.916342)`, and performs no delayed safe-zone relocation. Ordinary airborne,
landing, ledge, split-walk, four earlier knee, edge, ramp, stair, and idle-freeze checks pass; the
broad run again reaches only the known `walk_fwd_left` stop. Static project checks pass. This remains
uncommitted pending the user's live visual confirmation.

#### Retest: airborne animation spacing was the wrong predictor

The live retest is preserved at `/tmp/foot_ik_live_prelanding_retest_20260828.jsonl`. Its last
relevant jump contacted at frame 1582 with root `(8.866440, 0.600523, 4.006072)`. Movement input was
already zero, but the jump pose placed the right foot at z=4.099, barely over the platform edge, so
the first predictor saw both surfaces as upper and did nothing. `jump_land` widened that foot to
z=4.118 on frame 1584, selected the 0.00m floor, and the old delayed relocation resumed during idle
at frame 1622. This disproved the assumption that the airborne pose's current foot XZ predicts the
landing stance.

The predictor now records each foot's character-local offset from the last stable grounded idle and
carries that spacing through the jump. In the same trace, the pre-jump right foot was z=4.087; after
the root's airborne displacement that predicts z=4.107, correctly beyond the platform edge before
contact. The regression now uses this grounded spacing, sees prediction while airborne, lands at
root `(8.950534, 0.600468, 3.904579)` with both targets on the upper support, and records the exact
same root at first contact and final settle (no delayed relocation). All four older knee cases, the
16 ledge cases, ordinary airborne release, and landing stability remain green. Live confirmation is
still required.

### Follow-up: forward-bent lower leg during safe-zone recovery

The next live trace is preserved at
`/tmp/foot_ik_live_forward_shin_retest_20260828.jsonl` (1,355 rows, frames 3917-5271). During the
right foot's floor-to-platform target rise, the rendered shin moved from 39.86 degrees at frame 5176
to 59.08 at frame 5180 and 63.70 at frame 5184. The knee remained above the ankle, so this was not
the earlier inverted-calf failure; the lower leg itself was approaching horizontal in front of the
body. This clarifies that the requested 45-degree standing limit applies to the shin, not the thigh.

Checking only the ideal two-bone result was insufficient. The desired pole could already produce a
safe final pose while the 120-degree/second joint correction limiter rendered an unsafe intermediate
pose. An initial hard switch to the nearest valid knee plane fixed the angle but caused 0.26-0.43m
one-frame joint jumps. The final solution begins steering the desired knee plane at 30 degrees, then
checks the actual rate-limited shin and projects only any excess beyond 45 degrees back onto the
downward cone. It stores that projected knee correction as the next frame's starting point. A small
temporary foot-target miss is preferable to either a horizontal shin or an abrupt whole-knee switch.
The guard is limited to flat idle/walk Foot IK and does not alter crouch, jump, or slope poses.

The knee regression now records transient rendered shin swing, not only the settled pose. The latest
reproduction peaks at 44.41 degrees; the older incremental corner, mirrored raised-foot, and shallow
corner cases peak at exactly 45.00 degrees, with their worst ordinary one-frame joint movement still
0.223m or less. The predictive jump case remains at 26.66 degrees. `scripts/check.sh`, all 16 ledge
cases, landing stability, and all six 15/30/45-degree ramp cases pass. This remains uncommitted and
needs live visual confirmation.

### Follow-up: do not lower a proven upper foot during upper recovery

The live retest is preserved at
`/tmp/foot_ik_live_shin_guard_lowering_retest_20260828.jsonl` (676 rows, frames 17-692). The relevant
edge push begins from root `(9.219313, 0.600, 3.865484)` at yaw `92.7267` degrees. After four frames
of left input, both targets initially remain on the 0.60m platform. The left target then descends from
0.58m at frame 562 to the floor at frame 571 while upper safe-root movement is already moving the
capsule. At frame 592 it jumps back to 0.60m and the rendered foot rises again. This is the reported
brief leg lowering followed by repositioning.

The upper safe-root recovery now caches both previously proven upper world-space support points. If
the search chooses that same upper surface, both contacts remain held while the capsule moves into
the safe zone; the newly exposed lower ray cannot take ownership first. This is deliberately gated
on having two proven upper contacts. A character that begins already split has no valid upper point
for its lower foot and retains the existing upper/lower fallback behavior.

The knee harness replays the exact four-frame edge push and rejects a target that descends and then
rises more than 0.20m during this recovery. It now reports `target_reversal=0.000`. All other focused
knee cases pass, including the already-split mirrored pose and predictive jump. All 16 ledge cases,
landing stability, six ramp cases, and `scripts/check.sh` pass. This remains uncommitted pending live
confirmation.

### Follow-up: ankle contact hid an unsupported toe at the final pose

The next live trace is preserved at `/tmp/foot_ik_live_upper_hold_last_pose_20260828.jsonl` (1,291
rows, frames 917-2207). At the final root `(9.636244, 0.600522, 3.985670)`, yaw `-101.1646`, both
ankle probes and both IK targets reported the 0.60m platform. The right foot's lowest visible-point
probe still found the floor 0.60m below, however, and `step_down` remained true indefinitely. The
right ankle was only about 1.2cm from the platform edge, leaving the toe/sole over the void. The
skeleton angles themselves were ordinary; the contact classification was the defect.

A rejected first attempt made the common-root search require an 8cm patch around both authored foot
points. This 0.50m-deep platform cannot fit those two points plus both margins because the idle feet
are about 0.43m apart front-to-back. It therefore forced valid upper poses to the lower floor and
regressed predictive landing. Translating the unchanged footprint cannot solve that geometry.

The final solution detects disagreement between the upper ankle surface and the lower lowest-point
surface, then moves only the affected foot inward in 2cm steps until it finds a 10cm same-height
support patch inside that foot's colored stance zone. The exact captured pose now keeps both targets
at 0.60m; the right target moves inward to `(9.270976, 0.600, 3.990221)`, both knees remain above the
ankles, and the largest joint step is 0.179m. The regression reconstructs this root/yaw and requires
a complete patch under both final targets. All earlier knee cases, the edge-push no-reversal case,
predictive landing, all 16 ledge cases, landing stability, six ramps, and `scripts/check.sh` pass.
This remains uncommitted pending live confirmation.

### Follow-up: released idle foot retained a stale target lock

The next live tail (frames 1958-1997 in `foot_ik_controlled.jsonl`, captured 2026-08-28 23:54)
ended idle at root `(8.805066, 0.600, 3.844814)` and yaw `-75.0354` degrees. The right raw surface
target was `(8.530233, 0.600, 4.093398)`, but its smoothed target remained at
`(8.602680, 0.600, 3.982477)`, about 13cm away. This pulled the rendered right foot toward the body
centre. The right freeze streak reached 30; when animation motion released `_idle_frozen` at frame
1996, `_idle_freeze_yaw[side]` remained. `target_lock_allows_latch()` uses that same side-key as the
plant latch, so it continued reporting the released foot as locked and prevented target smoothing.
The generic trace anomaly summary did not detect this inconsistent state.

`update_idle_freeze()` now erases the side-key whenever a previously frozen foot becomes released.
The walk-to-idle regression asserts the invariant directly: a foot with `_idle_frozen == false` may
not retain the side target latch. It passes 24 travel/yaw cases and 2,184 sampled idle poses. The 16
ledge cases, stair repeat, split-height idle-freeze clearance, and `scripts/check.sh` also pass. This
fix remains part of the broader uncommitted Foot IK work and needs a live visual retest.

### Follow-up: late airborne input cancelled the predicted safe landing

The live reproduction is preserved at
`/tmp/foot_ik_live_delayed_safe_zone_20260829_023325.jsonl` (1,088 rows). The final jump contacts at
frame 891. Its left/right targets then resolve to 0.00m/0.60m while the capsule is already grounded;
idle safe-zone movement begins at frame 907 and moves the root from x=8.432 to x=8.806 through
frame 936. The visible readjustment therefore happened after landing, exactly as reported.

Airborne prediction had already selected a common-support root, but `Player` applied it only while
smoothed movement input was below 0.1. A late nine-frame sideways adjustment stopped following that
cached target and carried the projected stance back across the platform edge. The correction now
continues during every descending frame once a split landing is detected. Its existing 3m/s limit is
unchanged; the fix does not teleport or accelerate the body.

The persistent knee/safe-zone harness now adds a second late input pulse to the known predictive
jump and rejects any grounded frame whose smoothed left/right targets differ by more than
`Player.step_height`. It lands at frame 84 with both targets on the 0.60m platform, records
`post_landing_split=false`, and moves only 0.027m after first contact (below the existing 0.08m
allowance). Landing-grace frames are excluded from the standing shin-cone metric because that guard
applies to settled idle/walk IK rather than the contact transition.

`scripts/check.sh` passes. `scripts/check_foot_ik.sh` passes the new landing case plus all preceding
ledge, landing, knee, edge, ramp-locomotion, stair, and idle-freeze cases, then reaches the existing
`walk_fwd_left` A/B stop; `scripts/check_foot_ik_locomotion.sh` stops at the same known case.
`scripts/check_foot_ik_ramps.sh` reports its existing top-of-ramp penetration cases.
`scripts/check_foot_ik_ramp_sweep.sh` was terminated without a result after more than 87 minutes of
active CPU time. This candidate remains uncommitted and requires the user's live retest.

### Follow-up: landing animation moved the left contact just outside the tread

The next live reproduction is preserved at
`/tmp/foot_ik_live_left_lower_retarget_20260829_074626.jsonl` (1,321 rows). The capsule remains
stationary at `(8.602571, 0.600529, 3.860138)`, yaw `91.1224`. Both projected contacts are on the
0.60m platform through frame 5398, but the landing animation widens the left contact slightly past
the platform edge. Its raw and smoothed target drop to the 0.00m floor at frame 5399. The raw probe
rediscovers the platform at frame 5415, and the smoothed target rises from frame 5422 through 5436.
This is the reported brief left-leg lowering and recovery; it is not late capsule movement.

The airborne probe now preserves the last grounded collision contact rather than the animated foot
bone position. When descending toward equal-height contacts, it requires only 2cm of support around
each projected contact and searches inward in bounded 2cm steps if a landing animation would put a
contact on the edge. This is deliberately much smaller than the rejected whole-foot 8-10cm patch,
which cannot fit both authored contacts on this narrow platform.

The exact root/yaw replay performs a straight jump and rejects both a grounded target-height split
and any down/up target reversal over 0.20m. It shifts the root about 3.4cm while airborne, contacts at
frame 84 with both targets on the 0.60m platform, and reports `post_landing_split=false` and
`target_reversal=0.000`. `scripts/check.sh` passes. The aggregate Foot IK script reaches its existing
split-stance walk case, which now reports that it never enters a split-height stance; the focused
landing-clearance regression itself passes. This candidate remains uncommitted pending live visual
confirmation.

### Follow-up: flat-tread classification preserved a visibly floating pose

The live state is preserved at `/tmp/foot_ik_live_floating_20260829_083351.jsonl`. At root
`(13.58067, 1.611434, 2.017687)`, the left ray found the 1.40m tread and carried full IK weight, but
the rendered sole remained 0.15-0.16m above it. The right ray found the 0.60m lower surface while its
released smoothed target remained near 1.38m. The direct left-leg cause was `is_flat_level_ground`:
it treated every horizontal tread as ordinary flat ground and replaced the solve target with the
animated foot even when that animation was nowhere near contact.

Flat-pose preservation now additionally requires a real animated contact within the existing 3cm
contact band. A horizontal stair tread with visible clearance therefore goes through the IK solve
and shared-pelvis reach handling. `scripts/check.sh` passes; the stretch, airborne, penetration,
pose-continuity, stair-locomotion (zero floating frames), stair-settle, ledge, and landing-stability
checks pass before the aggregate script reaches the separately documented split-stance conflict.
This remains uncommitted pending live confirmation.

### Follow-up: frozen contact over-flexed the standing leg sideways

At live frame 2030, root `(8.537166, 0.600518, 3.977128)`, the left rendered sole was correctly on
the floor but its frozen target was 0.12m from the current raw contact. The chain stayed anatomically
non-inverted, yet the thigh and shin had to splay sideways to retain that stale world point. Euler
values near 180 degrees were equivalent decompositions rather than a quaternion discontinuity.

Idle freeze now releases during current-frame ground sampling when the held target differs from its
new supported contact by more than 8cm. This preserves ordinary flexible knee motion while preventing
a stale plant from demanding the visibly over-flexed pose. The walk-to-idle harness now asserts this
bound for every frozen foot; all 24 cases and 2,184 sampled idle poses pass, as does `scripts/check.sh`.
This remains uncommitted pending live confirmation.

### Follow-up: over-height landing resolves to one common support

The wall-clipping reproduction is preserved at
`/tmp/foot_ik_live_right_platform_to_floor_20260829_133759.jsonl` (753 rows). Frames 565-578 hold
the left target on the 0.00m floor and right target on the 0.60m platform. After the right raw probe
switches to the floor, its smoothed target descends through 0.53, 0.40, 0.27, and 0.13m while the
root remains fixed, visibly blending the leg through the platform wall.

Split-height IK is now limited to 0.35m. A larger supported difference requests the nearer viable
common-support root, upper or lower, and retains the existing landing support until that relocation
clears the edge. This prevents one foot from descending through a vertical wall before the capsule
has moved into the selected safe zone. The selection uses required root travel as the footprint
majority proxy, so it chooses the support needing the smaller body relocation rather than always
preferring the platform.

The ledge harness now requires over-height cases to settle on one safe level. Landing stability
requires the final targets to agree, and split-stance walking first resolves to one common level
before testing locomotion. All three pass, as do the focused landing-clearance, late-input,
floating-foot, knee, edge, stair, idle-freeze, and walk-to-idle regressions.

Validation map for this candidate:

- `scripts/check.sh`: PASS.
- `scripts/check_foot_ik.sh`: new and preceding edge cases PASS, then the existing `walk_left` and
  `walk_right` flat-locomotion target-lock failures make the aggregate exit 1.
- `scripts/check_foot_ik_locomotion.sh`: the same existing `walk_left` and `walk_right` failures.
- `scripts/check_foot_ik_ramps.sh`: existing steep/top-of-ramp penetration failures.
- `scripts/check_foot_ik_ramp_sweep.sh`: completed 6,240 cases with 259 steep-ramp penetration
  failures; worst depth 0.1488m at 45 degrees. No crossed-leg, invalid-contact, or joint-limit
  failure was reported in the displayed failing cases.

This candidate remains uncommitted pending live confirmation in `foot_ik_preview.tscn`.

### Follow-up: blocked safe-zone target caused an endless idle slide

The live runaway is preserved at `/tmp/foot_ik_live_20260829_220622.jsonl`. With input and reported
velocity both zero, the grounded root advances about 0.0125m every frame. The left contact follows
the floor, while the right raw contact is also on the floor but its retained target remains at
`(10.94234, 0.6, 4.00058)`. Right-foot divergence reaches 3.567m as the capsule moves farther from
that obsolete platform target.

The common-support search had validated support beneath candidate feet but not whether the capsule
could move into the candidate root. When the explicit motion toward the platform was wall-blocked,
the generic ledge fallback moved in the opposite direction while leaving the platform target active.
An explicit blocked correction now rejects that support level and returns without running the
fallback. The next sample selects the other common-support level. This bounds the correction and
prevents fallback movement from opposing its retained target.

`scripts/check.sh`, landing stability, resolved split-stance walking, and the late-input predictive
landing regression pass. The latter reports `post_landing_split=false` and finishes with zero root
nudge. This remains uncommitted pending repetition of the exact live landing.

### Follow-up: common-support idle must never use fallback translation

The repeated live escape is preserved at `/tmp/foot_ik_live_20260829_235659.jsonl`. Frames 909-1056
show the root translating 0.0125m per frame with zero input, zero gameplay velocity, and an idle leg
animation. Both raw foot probes are on the 0.00m floor, but the right smoothed target remains owned
at 0.60m and reaches 3.18m horizontal divergence. This is procedural root sliding, not locomotion.

Rejecting a blocked safe root now clears landing confirmation, lower-support acquisition, idle
freeze, and the stale smoothed target for both sides. In addition, when both current foot probes
already agree within the 0.35m split allowance, the generic ledge fallback cannot translate the
root. The fallback therefore cannot outlive the reason for the safe-zone correction or move an idle
character whose feet already share valid support.

`scripts/check.sh`, landing stability, and the late-input predictive landing regression pass. The
live animation-comparison flashes remain a separate final-pose/transition investigation; their
instantaneous errors currently print to Godot output but are not yet part of the controlled trace.
This candidate remains uncommitted pending the exact live jump repetition.

### Follow-up: common-support cancellation must precede explicit relocation

The next capture is preserved at `/tmp/foot_ik_live_20260830_012648.jsonl`. The prior guard does stop
the root at frame 594, but only after roughly 96 idle frames and 1.2m of procedural translation.
Throughout that interval input and gameplay velocity are zero, both raw probes are on the floor,
and the right retained platform target moves farther from the character. At frame 594 ownership
finally releases and both the right target and root settle immediately.

The common-support guard was ordered after explicit safe-root motion, so it could suppress only the
generic fallback. It now runs before either translation path. On the first frame where both live
probes agree, it rejects the obsolete split target, clears its owners, and zeroes the pending pose
nudge before any root motion is applied.

`scripts/check.sh`, landing stability, and the late-input predictive landing regression pass. The
landing-stability reproduction now resolves both targets directly to the 0.60m platform rather than
performing a long post-contact move toward the floor. This remains uncommitted pending live retest.

### Knee-flexion live readout

The controlled preview now places a true flexion label above each rendered knee. `0 degrees` means
the hip-to-knee and knee-to-foot segments are straight; larger values mean more flexion. This
replaces the less useful thigh-to-world-down label while retaining shin, foot, and toe-leaf labels.
It is intended to capture the exact transient value of the subtle backward/lateral right-knee bend
seen at `/tmp/foot_ik_live_20260830_012958.jsonl`. `scripts/check.sh` passes.

### Signed knee flexion and standing forward pole

The knee labels now use signed final-pose flexion. Live inspection established that this rig's normal
anatomical bend follows its positive local Z side; the initial actor-forward assumption reversed the
labels and constraint. The corrected convention displays the normal bend as positive and the
unwanted backward bend as negative. Standing idle/walk solves now use that anatomical side rather
than the rig's nearly straight rest pole, whose tiny offset was ambiguous after rate limiting.

Exact zero-degree lockout is intentionally avoided because a fully extended two-bone chain has no
stable bend plane. The constraint keeps ordinary flexibility but removes negative standing flexion.
`scripts/check.sh` and the focused knee-flexion regression pass. This remains uncommitted pending
live confirmation with the signed labels.

### Follow-up: unreachable lower acquisition oscillated one leg's ownership

The floating/snap capture is preserved at `/tmp/foot_ik_live_20260830_015826.jsonl`. The character
root remains grounded at y=2.10m while both rendered feet stay near y=2.19m, but both probes target
the floor at y=0.00m. The left IK weight repeatedly fades from one to zero and re-engages; the right
remains at one because `idle_lower_acquiring` exempts it from unreachable-drop release. At frame
2778 both probes briefly switch to about y=2.18m before returning to zero, producing the visible
body/pose snap.

Lower-support acquisition now revalidates its vertical drop every frame. If the acquisition target
exceeds the configured crouch/reach depth, it clears ownership immediately instead of continuing to
move the target or keeping that leg fully weighted. A focused injected regression reproduces a
2.1m-below acquisition and asserts that its side-key owner is removed; it passes.

The attempted global standing-knee pole override was removed after the ledge suite exposed large
joint snaps. Signed knee labels remain, but bend-direction enforcement requires a later rate-limited
final-pose solution rather than a global pole replacement.

Validation map:

- `scripts/check.sh`: PASS.
- Focused unreachable-acquisition regression: PASS.
- `scripts/check_foot_ik.sh`: initial stair/pose checks PASS, then the ledge suite fails five current
  transition expectations (two released unsupported contacts and three joint-step limits).
- `scripts/check_foot_ik_locomotion.sh`: existing `walk_left` and `walk_right` failures; preceding
  idle, crouch, forward, and backward cases pass.
- `scripts/check_foot_ik_ramps.sh`: existing steep/top-of-ramp penetration failures.
- `scripts/check_foot_ik_ramp_sweep.sh`: 6,240 cases, 259 failures, worst depth 0.1488m.

This candidate remains uncommitted pending live reproduction at the reported high-platform edge.

### Follow-up: lower safe-zone handoff after landing

The latest floating-foot capture is preserved at
`/tmp/foot_ik_live_20260830_142420.jsonl`. It shows a stationary split stance with the left probe at
y=1.05m and the right probe at y=0.40m, beyond the 0.35m split-height limit. The right leg remained
owned by `live_contact`; its weight repeatedly cycled from one to zero and back with the idle loop
because safe-zone recovery only retained the upper surface.

Over-height recovery can now select either validated common surface. For a lower safe zone, it first
moves the capsule horizontally and waits until the body has descended near that surface; only then
does it construct and validate both shifted foot targets. This ordering avoids the rejected version's
immediate 0.62m leg snap while preventing the old one-leg weight oscillation.

The exact 330-frame replay uses the captured root/yaw and a 0.65m split. It finishes with both targets
at y=0.40m, both planted weights at 1.00, maximum settled foot movement of 0.002m per frame, and sole
clearances of -0.011m/-0.009m. The regression also asserts the planted weights across the later idle
loop, where the live defect recurred.

Validation map:

- `scripts/check.sh`: PASS.
- Exact weight-oscillation replay: PASS.
- `scripts/check_foot_ik.sh`: animation comparison and the initial stair/pose checks PASS; the ledge
  suite retains five known failures (two released contacts and three transition snap limits).
- `scripts/check_foot_ik_locomotion.sh`: existing `walk_left` and `walk_right` failures; idle,
  crouch, forward, and backward cases pass.
- `scripts/check_foot_ik_ramps.sh`: existing steep/top-of-ramp penetration failures.
- `scripts/check_foot_ik_ramp_sweep.sh`: 6,240 cases, 257 failures, worst depth 0.1488m.

This candidate remains uncommitted pending live confirmation.

### Follow-up: idle sway reopened a settled upper platform

The delayed post-landing snap is preserved at `/tmp/foot_ik_live_20260830_152105.jsonl`. After the
real landing, both feet remain correctly latched to the floor at y=0.00m. At frame 58803, 0.73s into
idle, the animated right probe briefly reaches the y=0.60m platform. Over-height recovery mistakes
that one-frame probe for a new stance decision, clears both lower latches, and at frame 58804 raises
the root and rendered feet by roughly 0.57m. Lower acquisition immediately reverses the move. The
same defect repeats near the next idle-loop boundary at frame 58880.

An already validated same-height pair of lower latches now owns the stationary stance. While both
latches remain valid and gameplay velocity is zero, over-height recovery clears any pending root
nudge and ignores transient upper probes. Actual movement, loss of support, or either target leaving
its stance rectangle still releases the latches through their existing validation path.

The persistent regression starts at the captured root/yaw and runs 330 frames across multiple idle
cycles. It asserts that neither foot reopens the upper target and that the root cannot rise more than
0.02m after common lower support is established. It passes with `upper_reopened=false` and
`post_latch_root_rise=0.000`.

Validation map:

- `scripts/check.sh`: PASS.
- Exact delayed lower-support snap regression: PASS.
- `scripts/check_foot_ik.sh`: initial animation, pose, and stair checks PASS; the existing ledge
  suite stops the entrypoint at its five known failures.
- `scripts/check_foot_ik_locomotion.sh`: existing `walk_left` and `walk_right` failures.
- `scripts/check_foot_ik_ramps.sh`: existing steep/top-of-ramp penetration failures.
- `scripts/check_foot_ik_ramp_sweep.sh`: 6,240 cases, 257 failures, worst depth 0.1488m.

This candidate remains uncommitted pending live confirmation.

### Follow-up: stationary left-foot jump at the idle loop seam

The latest controlled capture is preserved at `/tmp/foot_ik_live_20260830_171602.jsonl`. The player
is stationary on the 0.35m preview stairs with both contact owners, smoothed targets, IK weights,
root position, and yaw unchanged. At each 150-frame `unarmed_idle` loop boundary, however, the left
rendered foot moved by up to 0.0318m while signed knee flexion jumped from about 5.4 to 29 degrees.
This isolates the visible movement to the solver's correction history rather than contact or stance
ownership.

Idle hip and knee corrections now use the existing conservative 45-degree-per-second correction
rate instead of the generic 120-degree standing rate. This lets the retained support converge
without exposing the animation reset as a one-frame procedural leg jump. Foot orientation remains
immediate, and crouch/jump behavior retains its existing paths.

The persistent preview regression uses the exact controlled scene placement and samples final
post-modifier left-foot positions across two idle-loop seams. With the previous rate it fails at
0.0276m in one frame; with the new rate it passes at 0.0144m against a 0.025m limit. The check lives
in `foot_ik_idle_seam_check.gd` so the preview remains within the 1,000-line ceiling.

Validation map:

- `scripts/check.sh`: PASS.
- Exact controlled-preview idle seam regression: PASS, maximum left-foot step 0.0144m.
- `scripts/check_foot_ik.sh`: animation comparison and initial stair/pose checks PASS; the existing
  ledge suite stops at five known failures (two unsupported-contact expectations and three
  transition joint-step limits).
- `scripts/check_foot_ik_locomotion.sh`: idle, crouch, forward, and backward cases PASS; existing
  `walk_left` and `walk_right` failures remain.
- `scripts/check_foot_ik_ramps.sh`: 42 existing steep/top-transition case failures.
- `scripts/check_foot_ik_ramp_sweep.sh`: unchanged at 6,240 cases, 257 failures, worst depth
  0.1488m.

This candidate remains uncommitted pending live confirmation.

### Follow-up: randomized full-stance edge landings

The next live capture is preserved at `/tmp/foot_ik_live_20260830_205944.jsonl`. On the final jump,
the left probe selected the floor at y=0.00m while the right selected the 1.20m top landing. At
frame 3594 both procedural targets briefly moved to the floor; the following frame restored the
split. From frame 3596 onward the stationary capsule alternated every frame between about y=1.095m
and y=1.200m, while the left leg faded to zero weight and remained floating.

Two related ownership errors caused the reversal. First, `feet_have_common_current_support()`
treated matching deep fallback rays as current support even when both contacts were more than a
metre below the legs. It now requires a real hit on each side within the 0.35m direct-support depth.
Second, making both procedural targets equal cleared the active safe-zone plan before the capsule
reached its selected root. A validated plan with both held targets now remains active until the
horizontal root target is reached; genuine close common contact can still cancel it.

The controlled trace now adds a bounded `safe_zone_decision` string with the selected action,
surface height, remaining root distance, and both contact distances. This distinguishes a real
common plant from a distant fallback or an in-progress upper/lower relocation without expanding
per-foot state ownership.

The new deterministic randomized regression performs 25 independent straight-up jumps over the
exact 1.20m top-edge geometry. It stratifies where the edge crosses the full stance from -0.24m to
+0.24m, randomizes yaw and position with a fixed seed, and includes the exact live yaw. Every case
must settle on either the platform or floor with both targets at one height, both foot weights at
least 0.90, and no root step above 0.05m during its final second. With the production guards
disabled, the finalized sweep fails seven landings with a zero-weight foot. With the guards enabled,
all 25 pass. It runs before the known-failing ledge block in `scripts/check_foot_ik.sh`.

Focused validation map:

- `scripts/check.sh`: PASS.
- Randomized edge-landing sweep: PASS, 25/25 cases across -0.24m..+0.24m.
- Ledge safety: improved from five failures to one existing 0.159m turn-pause foot step against the
  0.150m limit; both unsupported-contact failures and both large landing snaps now pass.
- Landing stability, split-stance walk, lower weight-oscillation, delayed lower-support snap,
  predictive pre-landing, late landing input, and idle-loop seam regressions: PASS.
- Locomotion remains at the existing `walk_left`/`walk_right` failures; static ramps remain at 42
  existing top-transition failures.
- The unrelated 6,240-case ramp penetration sweep was stopped at the user's request in favor of
  bug-related regressions.

This candidate remains uncommitted pending live confirmation.

### Follow-up: delayed upper-landing support restore

The latest live capture is preserved at `/tmp/foot_ik_live_20260830_213506.jsonl`. On the final
jump, both feet initially land on the y=0.60m platform. The right probe briefly records the floor
at y=0.00m early in `jump_land`, then returns to the platform. That stale lower-support latch is
hidden by landing grace until animation time 0.92s, when it becomes the smoothed target and sends
the right foot down. Subsequent platform probes restore it over the following frames.

Upper-support confirmation previously required the animated sole to be within 0.06m of the tread.
At this landing pose the sole remains about 0.64m above it even though the capsule is grounded on
the tread and the raw foot probe repeatedly reads the same surface. Capsule support at the raw
surface height now counts as corroborating upper contact. Four consecutive probes retire the stale
lower latch before landing grace can expose it.

The exact regression starts at the position that predicts the captured landing root and replays the
same yaw and jump. After both targets have remained on the platform for eight frames, it watches the
rest of landing and idle for any departure. With the previous condition it fails with a 0.600m
drop-and-restore; with the fix it passes with zero post-confirmation drift. The randomized edge
landing sweep now applies the same across-time invariant instead of checking only the final second.

Focused validation intentionally omits the unrelated ramp matrix and dense ramp sweep. Those remain
separate terrain-wide entrypoints; this iteration runs only project parsing and landing, edge, and
pose-continuity regressions.

### Follow-up: inverted knee-forward sign

The controlled trace is preserved at `/tmp/foot_ik_live_20260831_002234.jsonl`. In its final idle
frames the right leg reports `negative_knee_clamped=true` and `action=clamp_negative_knee` every
frame, yet both the overlay angle and post-clamp signed trace remain positive near 23 degrees. The
rendered knee pole is on the actor's local +Z side: anatomically backward for a Godot character,
whose actual forward direction is local -Z.

Both the overlay and solver used local +Z as their forward reference. This inverted the diagnostic
sign and made the limiter correct an ordinary forward candidate toward the forbidden backward side.
They now share transformed local -Z as anatomical forward. The injected negative-knee regression
was updated to construct its valid and invalid poles from that same direction, so the old convention
does not satisfy it.

Focused validation passes: `scripts/check.sh`, the injected negative-knee clamp, idle-loop signed
knee continuity, the exact delayed landing restore, the 25-case randomized edge landing sweep,
landing clearance, delayed lower-support retention, and the preview idle-seam check. Ramp matrices
remain intentionally omitted from this bug-specific pass.

### Follow-up: actor-forward knee correction inverted the pose

The immediate live retest is preserved at `/tmp/foot_ik_live_20260831_004027.jsonl`. The attempted
local -Z correction made the leg visibly invert; in the final pose the left solver was now clamping
every frame near 16 degrees. Actor forward is not a sufficient anatomical pole for this rig across
its authored asymmetric animation poses.

The limiter now derives the valid knee half-plane from each frame's untouched animated hip, knee,
and foot chain, then projects that authored pole onto the final hip-to-foot plane. Only a procedural
result crossing to the opposite side is negative and clamped. Actor -Z is retained solely as a
near-straight fallback. The overlay reads the solver's exact signed result, so its label cannot
disagree through an independent world-axis guess.

The injected regression uses a deliberately side-biased authored pole and an invalid candidate on
its opposite side. This requires the animation-relative rule rather than allowing an actor-forward
shortcut to pass. Project checks, the injection, idle-loop continuity, exact delayed landing,
25-case edge landing sweep, and preview seam regression pass; the ramp suites remain omitted.

### Follow-up: commit the final stance before edge contact

The slow two-stage recovery is preserved at `/tmp/foot_ik_live_20260831_005240.jsonl`. The player
first landed in a split stance near the 0.60m platform edge, began the grounded safe-zone descent,
became airborne again, then performed a second landing on the floor. The visible leg adjustment was
therefore a late support decision rather than ordinary landing animation.

`FootIKLandingPlanner` now samples an 18-point footprint spanning the complete area between and just
outside the last stable grounded feet while the character descends. It groups flat support by
height, ranks levels by covered body area and correction distance, rejects a lower candidate whose
capsule ring intersects the upper obstacle, and commits to one reachable root/surface before first
contact. The player moves toward that root at a bounded 3m/s while airborne. The ground sampler
retains the same support through `jump_land`/idle, and the stair predictor is cleared while this
landing commitment owns the solve targets.

Actual solver-target logging exposed a hidden handoff: public ground targets were already on the
floor while the stair predictor still fed the right leg its stale upper target. Trace records now
include `solve_target` plus bounded ownership/action strings such as `landing_commitment` and
`hold_committed_landing_support`, so this inconsistency is directly visible.

The exact replay uses the captured position/yaw and input sequence. It asserts a pre-contact
commitment, no split stance after contact, no second airborne/landing transition, no delayed root
height change, and final solver targets on the committed level. It passes on the floor with
`post_landing_root_dy=0.000`, `committed_solve_error=0.028`, and sole clearances -0.012/-0.010m. A
fixed-seed 25-case sweep covers edge offsets -0.24m..+0.24m and passes every case.

The final remaining ledge failure was a 0.159m opposite-foot jump during idle lower-support
acquisition. Its ground and solve target did not move; the first shared-pelvis sink frame switched
both joints to the 720-degree stair correction rate. Idle edge settling now retains the standing
joint-rate limit unless the stair predictor actually owns the transition. The 16-case ledge suite
then passes, including this 0.150m continuity bound.

Focused validation intentionally omits both ramp entrypoints:

- `scripts/check.sh`: PASS.
- Exact committed landing, landing stability, delayed support restore, delayed lower support,
  negative-knee, idle-loop seam, predictive landing, and late-input landing regressions: PASS.
- Randomized edge landing: PASS, 25/25; ledge safety: PASS, 16/16; edge stance: PASS, 100/100;
  walk/idle stance: PASS, 24 cases; stair repeat and idle-freeze clearance: PASS.
- `scripts/check_foot_ik_locomotion.sh`: retains the documented pre-existing `walk_left` and
  `walk_right` flat-locomotion comparison failures; idle, crouch, forward, and backward pass before
  the script exits.

This candidate remains uncommitted pending live confirmation.

### Follow-up: footprint-safe but capsule-blocked floor commitment

The live retest is preserved at `/tmp/foot_ik_live_20260831_064025.jsonl`. The final landing chose
the floor with `coverage=18/18`, but the root stopped at y=0.494m against the nearby platform corner
instead of reaching the committed y=0.00m support. Both foot targets remained on the floor while
animated contact stayed roughly 0.49m above it. Landing grace initially raised both weights to one;
idle contact loss then faded both to zero for the remaining 262 captured frames, leaving both soles
floating around 0.48m.

Footprint rays cannot prove that the player body fits: the 0.35m capsule can overlap a platform
corner between radial samples even when every stance point sees floor. Each landing root candidate
now performs a real physics shape-overlap query using the player's collision shape at the proposed
surface. The older radial guard is also widened to 0.36m and sampled at 16 directions. A candidate
is accepted only when both the complete stance footprint and the landing capsule clear higher
geometry. An `already_safe` result now commits its surface as well, ensuring the stair predictor
cannot retain a stale target during the landing handoff.

The committed-edge replay now directly asserts that the captured floor/root candidate is rejected
by capsule clearance in addition to its existing across-time checks. It passes with both final sole
clearances near -0.01m, weights 1.00/1.00, no second landing, zero post-landing root-height drift,
and maximum committed solver/surface error 0.028m. The 25-case edge sweep, 16-case ledge suite, and
landing-stability replay also pass with the capsule query enabled.

This candidate remains uncommitted pending another live confirmation.

### Follow-up: live feature controls

The preview now has a separate top-left `Foot IK Features` panel so landing policy can be isolated
without expanding the already full pose-debug overlay. It independently toggles airborne safe-zone
landing, grounded split-height recovery, and stair prediction. The panel also exposes landing
correction speed/distance, stance footprint depth, capsule clearance radius, allowed IK height
split, and the main stair/support-settle values. F6 hides the panel; restoring defaults or changing
any control clears transient IK ownership before refreshing the skeleton, so disabled features
cannot leave a stale landing or split-safe target active.

The elevated-foot anti-crouch path is independently exposed as `Higher-foot reposition`. This is
the compressed-upper-target search that slides a foot along its existing upper support to preserve
a straighter knee and adequate riser-edge support. Its acquisition speed, preferred/retained knee
flexion, and support radius are live controls. The exact split-height knee regression passes with
the extracted defaults.

A full pipeline audit added the other independently owned policies: lower-foot support acquisition,
lower-riser escape, idle freeze, locomotion stance-target locks, force-plant mode, and the movement
controller's outer ledge-safety gate. All existing exported Foot IK values are now represented across
the original pose overlay and the feature panel, including stair lift/clearance, lower-foot search
and pelvis limits, target speed, anatomical knee/hip limits, and residual/phase-locked locomotion
mode tuning. Movement `step_height` and short-fall allowance are included because they bound when
the safe-zone/IK system may bridge a height difference.

Runtime policy values now live in `FootIKRuntimeSettings` rather than being attached to the landing
planner. Collision masks, surface tolerances, search sample counts, animation-discontinuity holds,
and hard support/ownership invariants deliberately remain internal. Project checks, 25 edge
landings, 16 ledge cases, the split-height knee replay, and 24 walk-to-idle stance cases pass with
the unchanged defaults.

All runtime defaults remain the same. `scripts/check.sh` passes. The focused Foot IK run passes the
25-case edge landing sweep, 16 ledge cases, landing stability, split stance, 100 edge-stance cases,
stair repeat, and idle-freeze clearance. Its broader flat locomotion tail retains the existing
`walk_left` and `walk_right` comparison failures; the separate ramp entrypoints remain omitted.

This debug tooling and the current IK candidate remain uncommitted pending live confirmation.

### Follow-up: stair support acquisition weight collapse

The stair-walk repro is preserved at `/tmp/foot_ik_live_20260831_142014.jsonl`. During continuous
ascent, rendered knees moved 8-14cm on several frames and a planted stair foot could fall from full
IK weight to about 0.21 in one frame. Stair ownership always began its transfer blend at zero even
when ordinary contact IK already held that same foot near full weight. Repeated acquisition thus
made an otherwise planted leg fold and recover once per tread.

The stair predictor now captures the incoming ground weight and blends from it to full ownership.
It also distinguishes an in-progress vertical traversal from truly leaving the stairs, so the brief
period where both probes share a tread does not by itself release support. Controlled traces now
name `stair_support` and `stair_swing_prediction` ownership and include support side, root vertical
speed, step lifts, predicted targets, and conflicting landing/lower-foot owners.

The stair locomotion regression now asserts the visible temporal invariant: while the body climbs,
a planted foot may release only at the configured weight rate. The focused stair run passes with
186 ascent weight samples, zero excessive drops, maximum drop 0.069, no rendered-body penetration,
and no stretch or pose-continuity failures. `scripts/check.sh` passes. The related locomotion
entrypoint retains only its documented pre-existing `walk_left` and `walk_right` failures; forward
and backward walking pass. Ramp entrypoints remain intentionally omitted.

This candidate remains uncommitted pending live confirmation.

### Follow-up: simultaneous stair swing ownership

The next live stair capture is preserved at `/tmp/foot_ik_live_20260831_145752.jsonl`. The preceding
support-weight collapse is fixed: support now engages 0.21, 0.42, 0.62, 0.83, 1.00 and releases at
the configured gradual rate. A separate defect remained later in the ascent. Frames 430-438 had no
stair support side, both ground weights were zero, and both legs simultaneously reported
`stair_swing_prediction`. The left retained a missed 1.40m landing while the right predicted 1.75m;
both step lifts stayed active and produced 20-33cm rendered knee/foot steps.

When no stair support foot exists, the predictor now permits only one latched swing target. A new
opposite swing remains animation-owned until the older predicted landing clears or a real support
foot is acquired. The stair locomotion regression now rejects any frame with simultaneous left and
right procedural step lift. Archived pre-fix automated traces contain 18-29 such frames; the fixed
run contains zero. It also passes all prior stair assertions: 186 ascent weight samples, maximum
weight drop 0.069, no penetration, no stretch, and no pose-continuity failure. `scripts/check.sh`
passes. Ramp entrypoints remain intentionally omitted.

This candidate remains uncommitted pending live confirmation.

### Follow-up: idle-loop left-leg wakeup

The idle repro is preserved at `/tmp/foot_ik_live_20260901_011218.jsonl`. The player root was
stationary for all 626 captured frames, but the left leg visibly folded once every 150-frame
`unarmed_idle` loop. The raw solve target also jumped about 10cm at the reset in the original live
capture. A solve-target hold removed that input jump, but final-bone inspection showed the deeper
ownership defect: the leg had been animation-owned for roughly 86 frames, then the loop reset
briefly acquired IK and amplified the imported clip seam. Smoothing every idle frame was rejected
because it lagged legitimate authored motion and introduced an 8.5cm foot error.

Stable pre-modifier animation poses are now captured continuously, including while the leg is
released. During the bounded idle-loop reset window, an animation-owned leg reapplies that last
stable pose and cannot acquire a new procedural correction; a correction that was already active
may continue using its held target. This preserves normal idle motion outside the seam and works
across the modifier's real-delta and zero-delta evaluation passes.

`FOOT_IK_IDLE_SEAM_CHECK` now measures the actual final hip/knee/foot geometry instead of the
solver's signed diagnostic. Across two loops it passes with maximum left-foot motion 0.0142m,
maximum seam-window knee motion 0.0073m, and maximum one-frame knee-flex change 0.69 degrees
(limits 0.025m, 0.012m, and 3 degrees). The main Foot IK entrypoint passes all cases. Its stale
upper-support regression reference was updated to read the extracted runtime setting.

Validation map:

- `scripts/check.sh`: pass.
- `scripts/check_foot_ik.sh`: pass, including idle seam, stair locomotion, 25 edge landings, and 16
  ledge cases.
- `scripts/check_foot_ik_locomotion.sh`: idle, crouch idle, forward, and backward pass; the existing
  `walk_left` and `walk_right` comparison failures remain.
- `scripts/check_foot_ik_ramps.sh`: existing top-edge/toe penetration cases remain.
- `scripts/check_foot_ik_ramp_sweep.sh`: 257/6240 existing ramp penetration cases fail; the sweep
  took about 24.5 minutes and produced `user://foot_ik_ramp_sweep_failures.jsonl`.

This candidate remains uncommitted pending live confirmation.

### Follow-up: stale lower commitment after an upper landing

The floating-foot repro is preserved at `/tmp/foot_ik_live_20260901_182653.jsonl`. The airborne
planner committed the stance to the 1.20m lower surface, but collision actually settled the player
root near 2.10m on the upper platform. The lower commitment survived for more than 450 grounded
idle frames. Its deep committed probe kept the left side owned at 1.20m while the unsupported right
side repeatedly acquired and lost a transient target near 2.18m, producing the visible float. The
feature was enabled; stale ownership, not a disabled setting, prevented normal adjustment.

A grounded landing now rejects an airborne commitment when the actual root height differs from the
committed surface by more than `max_split_ik_height`. Rejection clears every per-foot landing target
before ordinary contact sampling continues. Controlled traces expose this transition as
`reject_grounded_height error=<meters>`.

The new `replay_grounded_commit_mismatch` regression injects the escaped sequence on a stable upper
platform: a lower-surface commitment is retained after an upper landing, then the test asserts that
the planner rejects it within two frames, per-foot ownership clears, and both rendered soles remain
on the upper support. It passes along with the neighboring committed-edge and delayed-support
landing replays. `scripts/check.sh` and `scripts/check_foot_ik.sh` pass, including 25 randomized edge
landings, 16 ledge cases, landing stability, and the idle-loop seam regression. The locomotion
entrypoint retains only its documented `walk_left`/`walk_right` failures. The normal ramp matrix
retains its existing top-edge/toe penetrations, and the 1,492-second exhaustive ramp sweep exactly
matches the previous 257/6240 failure baseline. The scene was not launched; this candidate remains
uncommitted pending live confirmation.

### Follow-up: full landing animation after a short safe-zone descent

The animation repro is preserved at `/tmp/foot_ik_live_20260901_203839.jsonl`. Frames 1868-1887
show a controlled, stationary safe-zone descent from root y=1.086m to y=0.612m before touching the
0.60m platform. The descent correctly retained `unarmed_idle`, but the preserved-pose branch still
set the generic airborne flag. Touchdown at frame 1888 therefore started `unarmed_jump_land` and
held it through frame 1918 even though no jump/fall pose preceded it.

`PlayerBody` now remembers whether its airborne state came from a preserved-ground-pose descent.
That state returns directly to idle/locomotion at contact instead of starting the full landing clip.
Any frame that stops requesting preservation clears the marker, so ordinary falls and deliberate
jumps retain their existing fall and landing animations.

`FootIkShortFallAnimationCheck` replays 20 preserved descent updates and asserts that neither the
fall nor landing clip appears, then performs an ordinary fall and asserts that `jump_land` still
does appear. It runs inside the persistent 16-case ledge safety harness. The focused harness and
`scripts/check.sh` pass. The broader Foot IK run passes all edge/landing cases before retaining the
existing steep-ramp spin-step failures (0.060m/0.041m versus 0.040m); the locomotion entrypoint
retains only its documented `walk_left`/`walk_right` failures. No interactive scene was launched.

### Follow-up: retained idle target fighting the stance limiter

The live repro is preserved at `/tmp/foot_ik_live_20260904_094601.jsonl`. At the final stationary
pose, the right foot retained the same `live_contact` surface target while the solver alternated
between `solve_to_support` and `limit_stance_crossing` every few frames. Those transitions moved the
rendered foot roughly 5–7cm even though the root and input were stationary. The retained target was
physically supported but had rotated outside the right foot's body-relative stance rectangle;
planted-target smoothing therefore held it while the solver independently corrected the pose.

Stationary idle targets outside the stance rectangle now move toward a same-height, collision-proven
point inside the rectangle at a bounded 2m/s. This policy does not invent support, change tread
height, or supersede landing/lower-support/higher-foot ownership. The trace exposes active correction
as target owner `idle_stance_rehome` and solver action `move_to_stance_zone`; zero-delta modifier
refreshes retain that diagnostic state instead of erasing it after the actual physics update. The
feature and its speed are available in the F6 tuning panel.

The planted-idle regression injects the captured root, yaw, animation phase, and stale right target.
It asserts that the supported target is rehomed inside the stance zone, the action is observed, the
right foot stays under a 4.5cm one-frame limit, and the stance limiter does not resume cycling. The
focused replay passes with no stance-limited frames and effectively zero visible one-frame movement.
The final reduced Foot IK suite passes all cases in 91 seconds, including the strengthened captured
animation-phase replay. No interactive scene was launched.

### Follow-up: live joint-angle controls

The F6 preview panel now exposes the solver's hard joint constraints and response rates alongside
the existing higher-foot knee preferences. Controls include maximum knee flexion, maximum hip swing,
the upright shin cone, shin-steering threshold, positive knee-pole bias, and general/standing/crouch
joint angular speeds. It also reports current signed knee flexion, hip swing, and shin swing for both
legs so a reproduced pose can be correlated with the chosen values. Defaults preserve the previous
behavior. Joint-limit regressions now read the runtime shin setting rather than a removed solver
constant. The final reduced Foot IK suite passes all cases in 88 seconds. No interactive scene was
launched.

### Follow-up: recurring left-knee correction while planted

The live repro is preserved at `/tmp/foot_ik_live_20260904_102015.jsonl`. In the final stationary
idle pose, both surface targets and the character root were fixed, but the left knee moved roughly
4.5–5.2cm every five or six frames. The trace action changed to `clamp_negative_knee` at each jump.
The post-solve knee guard repaired a wrong-direction intermediate pose only after it crossed zero;
the independent hip/knee angular limiters then moved back toward that unsafe pose and repeated the
same emergency correction indefinitely.

The final-pose guard now retains the configured positive knee-pole alignment continuously instead
of waiting for a sign inversion. The trace distinguishes this stable constraint as
`constrain_knee_direction` and records both `knee_direction_constrained` and
`knee_pole_alignment`. The planted-idle regression injects the captured root, yaw, target, lower
support ownership, and a complete idle-cycle sequence. Across 180 constrained frames its maximum
left-knee movement is 0.004989m against a 0.02m limit; the previous recurring jump exceeded 0.05m.
The reduced Foot IK suite passes all cases in 92 seconds. No interactive scene was launched.

### Follow-up: constrained upper-leg pose at the 0.35m stair split

The live pose is preserved at `/tmp/foot_ik_live_20260904_103701.jsonl`. The stationary character
had its left foot on y=2.10m and right foot on y=1.75m, which is an allowed 0.35m stair-height split.
The left target remained supported, but the late knee-direction guard owned every frame at its exact
0.5 alignment boundary. Because that guard ran after the upright-shin limiter, it also invalidated
the earlier result: the final shin reached 45.65 degrees against a 45-degree cone, the target error
was about 0.058m, and the sole penetrated roughly 0.037m.

The primary two-bone solve now derives its bend direction from the current authored animation pose.
The post-solve direction guard remains as a safety net, but no longer needs to manufacture a
different knee after the other joint constraints have completed. The planted-idle regression now
injects the exact root, yaw, upper/lower targets, and support ownership from this pose. After bounded
settling, it records zero late knee-direction constraints, 0.000001m maximum target error, and a
24.83-degree maximum shin swing. The reduced Foot IK suite passes all cases in 110 seconds. No
interactive scene was launched.

### Follow-up: stationary rotation over stair treads

The exact split-height pose above is now followed by a deterministic 360-degree stationary rotation
sweep. Before the fix, a lower-foot ownership change moved both legs about 0.12m in one frame. The
shared pelvis had applied a reach sink without retaining it in `_smoothed_shared_drop`; when lower
support acquisition began on the next frame, release shaping restarted from zero and snapped the
pelvis upward. The target path also stopped smoothing on the frame acquisition became a latch, and
an out-of-zone lower support copied the replacement target's horizontal coordinates before its
bounded descent.

Shared pelvis shaping now retains every applied sink, including its no-predictor path, and all
stationary idle sink changes pass through the configured engage/release rates. Lower-foot target
smoothing continues across the acquiring-to-latched boundary, and stair-target rehoming moves the
complete 3D target instead of teleporting X/Z. The sweep validates final post-modifier hip, knee, and
foot geometry at every heading as well as the captured settled pose. It passes with zero hard joint
constraint failures, zero late constraint at the settled pose, zero target error there, a
28.18-degree settled shin angle, and a maximum one-frame joint movement of 0.04036m against a
0.045m limit (down from 0.122m).

The reduced related suite passes all cases in 110 seconds, including core stair locomotion, stair
settle, randomized edge landings, ledge safety, landing stability, split stance, idle seams, and the
new rotation sweep. No interactive scene was launched; live confirmation remains required.

### Follow-up: stationary right-foot stance-limit loop

The live capture is preserved at `/tmp/foot_ik_live_20260904_120650.jsonl`. Frames 1156-1502 show a
stationary root and a right target retained on the 0.8m tread even though the current raw contact was
the supported 0.6m tread. No valid same-height point existed inside the right stance zone, so target
rehoming declined the move but left the stale target active. The solver then alternated between
`solve_to_support` and `limit_stance_crossing`: the foot drifted forward for several frames and
snapped roughly 0.20m backward whenever the stance limiter engaged.

If same-height rehoming is impossible, an out-of-zone idle target now retires to the current flat,
supported, in-zone raw contact when the height difference is within `max_split_ik_height`. The
existing solved-target and joint-rate limits provide the visible transition. The exact root, yaw,
target, and missing lower-owner state are replayed after the 360-degree stair sweep. It passes with
the stale target resolved, only two stance-limit transition frames, a final in-zone target, and a
maximum right-foot step of 0.051278m instead of the repeating 0.20m reset.

`scripts/check.sh` passes. The reduced related Foot IK suite passes every case in 94 seconds. No
interactive scene was launched; live confirmation remains required.

### Follow-up: stationary left-foot stance-limit loop

The mirrored live capture is preserved at `/tmp/foot_ik_live_20260904_121911.jsonl`. Frames
968-1443 retained the left target at `(12.70302, 1.0, 2.477624)` while the supported raw contact was
near `(12.1557, 1.0, 2.458)`. The root and yaw were stationary, but the final foot repeatedly moved
4-6cm toward the stale target and reset through `limit_stance_crossing`. The idle clip's small foot
motion prevented `likely_idle`, so stance rehoming never ran even though the stronger facts already
held: idle animation, stationary body, full plant weight, flat support, and an out-of-zone target.

Idle stance rehoming now uses those explicit plant conditions rather than the animation-speed
heuristic. The idle target-lock side key is also erased on every unfrozen frame, enforcing the
ownership invariant even if cache state becomes inconsistent. The exact left root, yaw, and stale
target now replay after the right-side case. It passes with rehoming observed, zero stance-limit
frames during the sampled recovery, a final in-zone target, and a maximum left-foot step of
0.041485m instead of a repeating cycle.

The reduced related suite passes every case in 96 seconds. No interactive scene was launched; live
confirmation remains required.

### Follow-up: rejected late minimum-knee-bend correction

The locked-straight right-knee capture is preserved at
`/tmp/foot_ik_live_20260904_124609.jsonl`. Its final supported pose had only 5.37 degrees of right-knee
flexion. A first experiment imposed a 12-degree minimum after the existing rate-limited solve and
moved the ankle horizontally just enough to make that geometry possible. Its isolated pose replay
looked safe, requiring only 0.005868m of ankle adjustment, and the reduced suite passed.

Live testing exposed the ownership error that the isolated replay missed. The resulting trace is
preserved at `/tmp/foot_ik_live_20260904_134022.jsonl`: the late correction owned 583 of 1,036 frames,
while the earlier solve continued pursuing the unchanged retained target. During the final idle
window it produced repeated 2-3.8cm right-foot steps and roughly 2.6cm of sole penetration. The
experiment was removed before checkpointing. A future solution must express preferred knee flexion
while choosing the reachable target/pelvis pose, not as another independent post-solve owner.

### Current blocker: target ownership must be centralized

The next left-leg recurrence is preserved at `/tmp/foot_ik_live_20260904_141200.jsonl`. Across frames
896-1318 the character remained in idle while rotating. The left target stayed at approximately
`(12.303, 0.8, 1.900)` even after the current supported raw contact moved to approximately
`(11.918, 0.6, 1.508)`. The retained/raw gap reached 0.584m and the retained target stayed outside
the stance rectangle for all 423 frames. `live_contact` remained the reported owner, while the
downstream stance limiter alternated 248 constrained frames with 173 ordinary solves. Visible foot
steps reached 0.147m and sole penetration remained around 0.035m.

There is also a direct local defect in the rehome fallback: after accepting an in-zone raw target up
to `max_split_ik_height` away, its final ray validation compares the chosen hit height with the stale
current target height. A valid transition from y=0.8m to y=0.6m is therefore rejected by the 0.03m
same-height test. Fixing only that comparison would reproduce the previous patch cycle without
preventing another target cache or late constraint from becoming a second owner.

The next implementation should be an incremental ownership refactor, not another solver guard:

1. Add one typed per-leg plan containing owner, state, surface target/normal, final ankle target,
   weights, transition generation, and decision reason. Persistent target state moves into a single
   coordinator.
2. Make landing, stair prediction, locomotion lock, idle freeze, lower support, and stance rehome
   submit candidates. Resolve their priority once per physics frame; collaborators may no longer
   write `smoothed_target` directly.
3. Validate the selected candidate before smoothing: collision support, stance rectangle, surface
   continuity, anatomical reach, and two-leg pelvis feasibility. An invalid candidate must explicitly
   transition to another candidate or animation; it may not reach the solver.
4. Smooth only the resolved plan. An owner/generation change clears incompatible freeze, latch, and
   solved-target history together.
5. Keep the leg solver pure: consume the immutable plan and emit bone output. Remove the late idle
   stance correction once the coordinator invariant is active. Hard anatomical limits may report an
   infeasible plan but must not silently create a competing foot target.
6. Turn final-pose checks into observation and fallback, not another state owner. Trace both candidate
   rejection and the single selected owner every frame.

Migration should start with the stationary idle/stair path while preserving the existing landing and
locomotion behavior behind adapters. The first regression must replay this complete rotation/contact
sequence and assert that exactly one owner exists, the selected target is valid before solving, the
solver never invokes a stance correction, sole penetration stays below tolerance, and idle foot
motion remains bounded across several animation loops. Only after that slice passes live testing
should the remaining target writers move behind the coordinator.

### Target coordinator migration: stationary live contact

The first architectural slice now introduces a typed `FootIKTargetPlan` and a
`FootIKTargetCoordinator`. Every leg receives one plan with a single owner, transition generation,
surface and ankle targets, support/stance/reach validity, and a decision reason. The coordinator sits
after legacy feature candidate production but before shared-pelvis and leg solving. For migrated
stationary `live_contact` and `idle_freeze` ownership, it validates both the support surface and the
actual ankle target against collision support, the rotated stance rectangle, height continuity, and
reach. An invalid retained target is replaced once by the collision-proven current raw support, or
the leg is released when no valid candidate exists. The replacement updates compatibility caches and
clears incompatible idle/solved-target history together.

A validated plan explicitly tells the leg solver that stance policy is complete, so the solver does
not run its legacy late stance correction as a second owner. Landing, lower-support, stair-swing, and
locomotion ownership remain behind explicit legacy adapters; an early attempt to arbitrate
lower-support state caused a 0.46m landing transition and was rejected by the existing stale-grounded
landing regression before live testing.

The planted-idle harness now replays the captured y=0.8m stale target, y=0.6m raw support, and the
57.34 to -33.19-degree stationary rotation. It observes the coordinator recovery, zero invalid-plan
frames, zero stance-limiter frames, at most three plan generations, a maximum 0.035831m left-foot
step, and -0.009405m worst sole clearance. The earlier static stale cases remain within their existing
bounds. The reduced related suite passes every case in 104 seconds, including the landing adapter,
randomized edges, locomotion, idle seams, and the new captured rotation. Live confirmation is still
required before migrating another owner or committing this slice.

### Target coordinator migration: lower-support latch and knee transition

The next live capture is preserved at `/tmp/foot_ik_live_20260904_193603.jsonl`. Its final idle
window was positionally stable, but both legs remained under the legacy `idle_lower_latched` owner.
The right leg invoked `clamp_negative_knee` every frame, settled at only 3.6 degrees of flexion, and
stayed approximately 0.18m from its selected ankle target. The independent hip/knee rate limiter
kept pursuing the valid solve, while the late anatomical guard wrote its boundary correction back
into that same history every frame. Neither owner could make progress.

Stationary lower-support latches now pass through the coordinator's support, stance, and reach
validation and are reported as `validated_lower_support`. Replacing an invalid lower latch clears
both lower acquisition caches as part of the same plan transition. The solver's wrong-side-knee
fallback no longer overwrites transition history; it may protect intermediate rendered frames while
the bounded primary solve continues toward the selected plan. Positive knees that only need the
configured pole-alignment cone retain constrained history, preserving existing stair-turn
continuity. Primary bend selection now searches for one knee plane satisfying authored-positive,
hip-swing, and upright-shin constraints together before the final safety checks.

The planted-idle harness recreates the exact root, yaw, two retained targets, and lower-latch state.
Before the fix it failed at 3.77 degrees, 0.18132m target error, and 60/60 late constrained frames.
It now settles above 26 degrees with 0.000001m target error, at most 0.022m one-frame foot motion,
and no more than 20 transient safety frames around an animation-loop discontinuity; the guard no longer
owns the final pose or deadlocks its transition.

`scripts/check.sh` and the reduced related suite pass. The latter covers the core solver, stale
landing handoff, shallow split, randomized edge landings, ledge safety, landing stability, locomotion
handoff, idle seam, and planted-idle replay in 104 seconds. No interactive scene was launched; live
confirmation is still required before committing this architectural slice.

### Follow-up: support owners disagree at the exact height limit

Preserved live capture `/tmp/foot_ik_live_20260904_200735.jsonl`, final frame 518, root
`(14.04099, 1.4, 1.753284)`, yaw `-10.2225323948938`. During stationary idle the left
surface alternated between 1.05m and 1.40m while the right stayed on 1.40m. The lower latch
and split recovery repeatedly replaced one another; the last left sole was 0.292m above the
reported support and its solve target still belonged to the upper tread.

The exact geometry reproduces 163 support-level switches in 300 settled samples, maximum
0.318m sole error, and a 0.151m foot step. Restricting landing confirmation to landing grace
did not affect this failure and was reverted. Collision hit noise around the exact 0.35m
split threshold was triggering overheight recovery on alternating frames. Shared runtime
settings now provide one height-difference comparison with 0.001m numerical tolerance for
grounded support admission, split recovery, and coordinator recovery. The configured limit
is unchanged; a 0.36m split remains rejected.

`foot_ik_idle_support_owner_check.tscn` retains the captured stance and samples two idle loops,
asserting no support-level switches, bounded sole error, and bounded rendered-foot steps.
It is included in both fast and main acceptance runners. The first fixed replay records zero
switches, 0.003244m sole error, and 0.000048m maximum foot step. The complete fast suite,
including project lint/import/parse, passes in 117 seconds. Exhaustive ramp matrices were not
rerun for this support-threshold change. Live confirmation remains required; no interactive
scene was launched and no changes were committed.

### Follow-up: lower-tread toe inside the next riser

Capture `/tmp/foot_ik_live_20260905_014001.jsonl`, frames 14483–14522, has the left
ankle supported at y=0.70 while its toe and leaf lie inside the next solid tread
(z starts at 1.20, top y=1.05). Final toe z=1.277106 and leaf z=1.349701, both
at approximately y=0.725. The coordinator reports `validated_lower_support`, but
that does not establish clearance for the extended foot.

The lower-riser candidate filter conflated obstacle clearance with full support:
every point of a radius-0.32m ring had to hit the same tread. A 0.60m-deep tread
cannot contain that 0.64m-wide ring, so escape candidates were all rejected and
the original clipping latch survived. The sampler now rejects higher neighboring
surfaces, not lower or empty neighbors. The separate center-support and stance
checks still apply; no support is fabricated and solver policy is unchanged.

`foot_ik_toe_riser_check.tscn` replays the captured root/yaw and retained left target.
Before the fix, all 600 toe/leaf observations penetrated the next riser. Afterward,
none penetrate during 300 settled frames, sole error rounds to zero, and the
largest rendered-foot step across recovery is 0.026476m (limit 0.035m). The replay
allows 60 recovery frames before requiring clearance, then observes multiple idle
loops. It is registered in both fast and main runners. It checks final toe bones,
not the complete skinned mesh; live confirmation is still required.

## Related history

Earlier Foot IK work is preserved in
[`007_foot_ik_stair_contact_and_locomotion.md`](../007_foot_ik_stair_contact_and_locomotion.md).
