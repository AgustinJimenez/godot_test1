# 022: Idle stance rehome computes its destination from its own drifting position, feeding back into itself

## Status and scope

**Root-caused via live telemetry. Fixed, passing the full `check_foot_ik_fast.sh` suite. Awaiting
live test before commit**, per this project's standing rule for gameplay-behavior changes. Found
while confirming the 021 fix live: that test confirmed the split-safe-root give-up mechanism worked
correctly (fully disengaged, `action=none`), but the reported symptom - a foot's target sweeping
continuously while the character stands perfectly still - persisted anyway, through an entirely
different, previously undiscovered mechanism.

## The concrete symptom

Same visible shape as 021's bug (a foot's ground target drifting by many centimeters, repeatedly,
while genuinely idle) but with the split-safe search confirmed completely inactive
(`safe_zone_decision: action=none surface_y=-inf`). Left foot, `owner=live_contact`,
`ground_weight=1.0` (fully "planted" by the coordinator's own bookkeeping), `target_y=1.4`
(flat, single-level ground - not a split stance).

Root (`character.global_position`) and yaw are bit-for-bit constant across the entire window
(confirmed from the trace, not assumed). `raw_target` - the actual ground-sampler raycast contact
point - is also essentially constant: `(14.978, 1.4, 1.953)`, sub-millimeter jitter only. But
`smoothed_target` swings by roughly 0.5m (X ranging ~14.7-15.3, Z ~1.95-2.19) in a pattern that
tracks the idle animation's own hip sway (`hip_pos` moves ~0.15m in a correlated pattern), not the
stable raw contact point.

## Root cause, confirmed by reading `_rehome_idle_stance_target`

While a foot is "planted" (`ground_weight >= PLANT_LOCK_WEIGHT`) and not owned by any of the other
latching mechanisms (`idle_lower_latched`, `landing_upper`, etc.), `sample()` calls
`_rehome_idle_stance_target()` every single qualifying frame whenever the current smoothed_target
falls outside the body-relative stance zone. Critically, at that same weight threshold the *normal*
"smooth toward raw_target" branch further down is disabled (it explicitly requires `not
likely_planted`), so once a foot is considered planted, rehome is the *only* thing still allowed to
move `smoothed_target` at all - it isn't a supplementary nudge, it's the sole active driver.

`_rehome_idle_stance_target`'s destination is computed from the *current* (already possibly
drifting) `smoothed_target`'s own projection onto the body's forward/outward axes, clamped into the
stance-zone bounds:

```gdscript
var from_root := current - character.global_position
var lateral := clampf(from_root.dot(outward), IDLE_STANCE_REHOME_LATERAL, STANCE_ZONE_MAX_LATERAL - 0.04)
var longitudinal := clampf(from_root.dot(forward), -STANCE_ZONE_MAX_LONGITUDINAL + 0.04, STANCE_ZONE_MAX_LONGITUDINAL - 0.04)
var destination := character.global_position + outward * lateral + forward * longitudinal
```

Since `character.global_position`/`global_basis` are fixed in this scenario, `destination` is
driven entirely by `current`'s own clamped projection - a **self-referential feedback loop**: the
target this frame moves toward a point derived from where it already is, not from the actual stable
ground contact (`raw_target`). This is compounded by a second instability: the function's own
"same-height-supported" check requires *both* `current` and the newly-computed `destination` to
have real ground beneath them; if `destination` (a distinct point from `current`, walked toward the
zone boundary) happens to land somewhere without confirmable support, the function abruptly
switches to `next = raw_target` instead of the gradual `move_toward`. Whether `destination` has
support can flip from frame to frame as `current` itself moves (each frame's `destination` is a
slightly different point), so the two branches - "creep toward a self-derived destination" and
"jump toward the real raw target" - can alternate, producing exactly the observed back-and-forth
sweep between roughly `raw_target`'s neighborhood and points further out.

The likely trigger for `current` starting outside the stance zone in the first place, in this
specific live session, was the still-being-fixed split-safe-root churn (021) leaving
`smoothed_target` in an off-zone position before finally giving up - but this rehome instability is
independent of that root cause and can be triggered by anything that leaves a planted foot's target
outside the stance zone, not just a split-stance recovery.

## Fix

Changed `_rehome_idle_stance_target`'s destination computation to clamp the real, stable ground
contact's position (`raw_target - character.global_position`) instead of the possibly-already-
drifted `current` (`smoothed_target`) value - removing the feedback loop at its source. When
`raw_target` is already inside the stance zone (the common case), `destination` now resolves to
essentially `raw_target` itself, and the function simply creeps `current` toward real, externally-
grounded ground truth instead of a point derived from wherever it had already wandered to. When
`raw_target` is itself outside the zone (e.g. reaching toward a genuinely distant tread), the clamp
still produces the nearest valid in-zone point in that real direction, same as before - only the
*source* of the projection changed, not the clamping logic itself.

One line changed: `actors/player/foot_ik/foot_ik_ground_sampler.gd`,
`_rehome_idle_stance_target`'s `from_root` assignment.

Deliberately did not also address the second half of the original hypothesis (the
same-height-supported branch potentially flip-flopping frame to frame) - with the feedback loop
removed, `destination` is now derived from a point (`raw_target`) that by definition already has
confirmed support this frame, so the flip-flop condition this was meant to guard against should be
far less likely to occur in practice; adding hysteresis on top without first observing whether it's
still needed would be an unverified, unmotivated extra change.

**Verified clean:**
- `FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=16` - unchanged.
- Full `scripts/check_foot_ik_fast.sh`: identical to the pre-fix baseline, including the one
  pre-existing, unrelated `FOOT_IK_IDLE_PLANT_STABILITY_CHECK` failure (task 019) - every field
  matches to 5+ decimal places except one unrelated float that differs in the 5th decimal (noise,
  not a regression).

**Not yet live-tested.** The precondition (a planted foot whose target has already drifted outside
the stance zone) is state-dependent and may not trivially reproduce from a cold spawn - the
concrete next step is a live test on the same kind of stance that originally exposed this, ideally
one where the target starts outside the zone (e.g. right after a 021-style split-safe give-up, or
any other path that can leave a planted foot's target off-zone).

## What to try next if the fix above doesn't fully hold

- Reconsider whether the "jump straight to `raw_target`" fallback branch and the "creep toward
  `destination`" branch should be able to alternate frame-to-frame at all, if flip-flopping is still
  observed live despite the above.
- Consider whether this function and the still-open `wobbly-painting-flask.md` idle-reposition plan
  (a collision-aware hold instead of the current lift-arc/rehome approach) should be addressed
  together rather than patched independently again.

## Attempted a regression test for this fix - abandoned, did not discriminate

Tried adding a synthetic test (`_run_rehome_convergence_regression` in
`foot_ik_idle_plant_stability_check.gd`) that started `smoothed_target` well outside the stance
zone with a fixed, stable `raw_target`, then asserted the settled position ended up meaningfully
closer to `raw_target` than it started. After several corrections (the body-relative offset math,
raycasting real ground height instead of assuming a flat Y, avoiding offsets large enough to step
onto a different platform level), the test finally ran cleanly - but produced nearly identical
"got closer" ratios with and without the fix applied (0.8114 with, 0.8331 without, both well under
the 0.9 pass threshold). It didn't discriminate.

Root cause of the non-discrimination: both the buggy and fixed code correctly pull an out-of-zone
point back into *some* valid zone position on the very first correction (clamping is clamping,
whether it clamps `current`'s own drift or `raw_target`'s position) - a single "did it re-enter the
zone" or "did it get closer" check can't distinguish "converged toward real ground truth" from
"converged toward an arbitrary self-referential point that happens to also be in-zone." The bug's
real signature is *sustained* drift over many cycles in a live setting with continuous animation
sway perturbing the input every frame, not a single static correction - a property this kind of
short, static, single-shot function test doesn't exercise.

A test that would actually discriminate would need to compare the destination *computed* from two
different starting `current` values against the same `raw_target` (the property that changed), not
the eventual settled position after "stop once inside the zone" masks the difference - `destination`
is a local variable, not returned or otherwise observable without either extracting it into a
separately-testable pure function or inferring it from partial movement vectors. Both are real,
reasonable options but are a bigger change than a quick regression-test addition, and this was
already the third distinct attempt at making the test meaningful. Reverted the test file back to
clean HEAD rather than ship a test that looks like coverage but doesn't actually catch the bug -
the live user report plus the code-level root-cause analysis remain the only verification for this
fix, same as before.

## Second attempt: extract the destination into a pure, directly-testable function - this worked

Extracted the clamp-onto-stance-zone computation out of `_rehome_idle_stance_target` into
`_rehome_zone_anchor(character, side, raw_target)` - a pure function that deliberately does not
accept a "current" position at all. The bug was clamping the target's own drifting value instead of
`raw_target`'s; this signature makes that mistake structurally impossible to reintroduce silently,
since there is no current position in scope to reach for.

Added a real regression test (`_check_rehome_zone_anchor` in
`foot_ik_idle_plant_stability_check.gd`, run once from `_ready()`) using a throwaway `Node3D` and
pure vector math - no physics or raycasts needed, since the extracted function has no other
dependencies. It checks known clamp cases (in-zone passthrough, lateral floor/ceiling, longitudinal
clamp) and the actual regression property: calling the function twice with the same `raw_target`
but wildly different `smoothed_target` values must return the identical result.

Verified this test actually discriminates (unlike the first attempt above): temporarily
reintroduced the old self-referential read (`smoothed_target.get(side, raw_target)` instead of
`raw_target` directly) and confirmed the test failed with a clear diagnostic ("anchor depends on
smoothed_target: ... vs ..."), then reverted. `FOOT_IK_LEDGE_SAFETY_CHECK` stayed a clean 16/16 and
the full fast suite was unchanged except the new `rehome_anchor_ok=true` field and the pre-existing,
unrelated task 019 failure.

**Note:** this and the 021 fix ended up committed together as `2af14e2` when they should have been
committed separately - both files were staged together without checking that `foot_ik_ground_sampler.gd`
also carried the still-untested 021 changes. Left as-is per the user's direction rather than
rewriting history; see `023` for what live-testing this combined commit surfaced next.

## References

- `foot_ik_ground_sampler.gd::_rehome_idle_stance_target`/`_rehome_zone_anchor`/`sample()` (the
  `idle_rehome_planted` gate) - the mechanism itself.
- `AGENT_TASKS/023_stance_zone_boundary_retrigger.md` - a third, independent mechanism found live
  after this fix, on the same-looking symptom.
- `AGENT_TASKS/021_split_safe_root_target_oscillation.md` - the investigation that surfaced this
  while confirming 021's own fix was working correctly.
- `foot_ik_controlled.jsonl` (preserved at `/tmp/foot_ik_controlled_20260913_124717.jsonl` per
  AGENTS.md's "preserve before running another harness" rule) - the live telemetry that found this.
