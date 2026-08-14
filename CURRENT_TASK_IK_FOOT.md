# Active Task: Stair Foot IK

**Checkpoint branch:** `experiment/native-foot-ik`

Full chronological history (2026-08-03 through 2026-08-12, idle-freeze/loop-reset/
locomotion-parity debugging) is archived at
`docs/task_history/foot_ik_stairs_and_idle_freeze.md`. This file is the current-state
summary only — update it, don't let it grow back into a full narrative log; put new
blow-by-blow investigation detail in `AGENTS.md` (durable lessons) or a fresh
`docs/task_history/` entry (full trail) instead.

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
