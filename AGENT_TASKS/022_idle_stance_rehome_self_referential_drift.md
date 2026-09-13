# 022: Idle stance rehome computes its destination from its own drifting position, feeding back into itself

## Status and scope

**Root-caused via live telemetry, no fix attempted yet.** Found while confirming the 021 fix live:
that test confirmed the split-safe-root give-up mechanism worked correctly (fully disengaged,
`action=none`), but the reported symptom - a foot's target sweeping continuously while the
character stands perfectly still - persisted anyway, through an entirely different, previously
undiscovered mechanism.

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

## What to try next (not attempted)

- Do not patch this the same way 021 was patched (three attempts, each revealing a new failure
  mode in the same function) without first deciding on a design, given this is now the *second*
  self-referential/flip-flopping idle-stabilization bug found in one session.
- Most direct fix: stop deriving `destination` from `current`'s own position. Derive it from
  `raw_target` (or the body's actual stance-zone anchor) instead, so the destination is a stable,
  externally-grounded point rather than dependent on wherever the target already drifted to -
  removing the feedback loop at its source.
- Separately, decide whether the "jump straight to `raw_target`" fallback branch and the "creep
  toward `destination`" branch should really be able to alternate frame-to-frame at all - if
  `destination` intermittently lacks support, retrying next frame with the *last* stable choice
  (hysteresis) rather than switching behavior every frame would remove the second half of the
  instability even if the first isn't fixed.
- Confirm with a live A/B (matching this project's own established debugging pattern - see
  AGENTS.md's `013`/`014` references) rather than trusting a single headless run, since this bug's
  precondition (a planted foot whose target has already drifted outside the stance zone) is
  state-dependent and may not trivially reproduce from a cold spawn.
- Consider whether this function and the still-open `wobbly-painting-flask.md` idle-reposition plan
  (a collision-aware hold instead of the current lift-arc/rehome approach) should be addressed
  together rather than patched independently again.

## References

- `foot_ik_ground_sampler.gd::_rehome_idle_stance_target`/`sample()` (the `idle_rehome_planted`
  gate) - the mechanism itself.
- `AGENT_TASKS/021_split_safe_root_target_oscillation.md` - the investigation that surfaced this
  while confirming 021's own fix was working correctly.
- `foot_ik_controlled.jsonl` (preserved at `/tmp/foot_ik_controlled_20260913_124717.jsonl` per
  AGENTS.md's "preserve before running another harness" rule) - the live telemetry that found this.
