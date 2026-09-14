# 024 archive: rejected latch investigation before the 2026-09-13 feedback-loop fix

Historical handoff below; final status is in `024_idle_lower_latch_multi_evaluation_flicker.md`.

## Status and scope

**Still unsolved after five rejected fix attempts. Not a quick-margin bug like 021/022/023 - likely
needs an architecture-level look rather than another one-line patch.** Fourth distinct mechanism
investigated behind the same visible complaint ("foot moves constantly while standing still, on a
split-height/stair stance"), after 021 (split-safe-root oscillation), 022 (self-referential rehome
destination), and 023 (stance-zone boundary retrigger) were all found, fixed, and confirmed inactive
here.

## Repro

`tests/manual/foot_ik/foot_ik_preview.gd`'s default (non-automated) spawn point is now set to the
exact reported live-repro spot: `Vector3(15.52282, 1.422718, 1.734463)`, yaw
`deg_to_rad(100.977250312091)`. Running the scene **headlessly** reproduces the bug deterministically
without any live input:

```
godot --headless --fixed-fps 60 --path . res://tests/manual/foot_ik/foot_ik_preview.tscn --quit-after 600
```

This writes a real `user://foot_ik_controlled.jsonl` trace identical in shape to a live-captured
one; `scripts/trace.sh --anomalies --last-n 0` on it shows the same recurring `FOOT_SAFE_ZONE
left`/`IK_DIVERGENCE` cycle the user reports live, roughly every 20 frames, indefinitely. This
headless workflow is a major speedup for this whole bug family - no more waiting on the user to
walk to the spot and test live for each hypothesis.

## The concrete symptom

Right foot (lower stair tread, y=1.05) cycles `idle_lower_latched` -> `idle_lower_acquiring` ->
`idle_lower_latched` roughly every 21 frames, always the same shape: while latched, its
`smoothed_target` suddenly jumps from its settled x (~15.66) to ~15.80, then over the next few
frames the state machine drops the latch, re-acquires, and settles back to ~15.66. This right-foot
flicker is what upstream drives the *left* foot's visible drift (left foot's target is computed
relative to the right foot's state via `straighten_compressed_upper_target`, called unconditionally
every frame from `finalize_leg_targets`).

## Five rejected fix attempts (in order)

All five were implemented and verified with the headless repro above. The first four produced
**byte-for-byte identical** oscillation before and after; the fifth changed some internal detail
(transition count 72 -> 64) but the *visible* drift - magnitude and ~20-frame period of the
`FOOT_SAFE_ZONE`/`IK_DIVERGENCE` anomalies - was unchanged. None fixed the bug:

1. Added `IDLE_STANCE_REHOME_MARGIN` hysteresis to `_update_idle_lower_transition`'s "is the
   currently-latched target still inside the stance zone" check (the `previous` check). No effect.
2. Same margin added to the neighboring "is the in-progress acquire target still valid" check
   (`acquire_target`). No effect.
3. Added a Schmitt-trigger margin (`LOWER_RISER_CLEARANCE_MARGIN`) to `_has_lower_riser_clearance`,
   requiring more clearance to re-enter "clear" than to leave it, on the theory that the
   riser-avoidance search's binary clearance test was flip-flopping right at its own boundary. No
   effect.
4. Required the riser-avoidance candidate search to land with an inward safety margin inside the
   stance zone (`is_target_inside_stance_zone(side, candidate, -IDLE_STANCE_REHOME_MARGIN)`) rather
   than just barely inside it. No effect.
5. Gated `_latch_idle_lower_support`'s state-changing decision (zone checks, latch/acquire
   dictionary writes) to run at most once per physics tick, reusing the cached answer for any
   additional calls within the same tick (see "multi-evaluation" finding below). Changed the
   right-foot latch/acquire transition count slightly but left the visible drift pattern unchanged -
   the multi-call-per-tick behavior is real (confirmed by instrumentation) but is not, by itself,
   what's causing the visible symptom.

All five were reverted; none are in the working tree.

## A real but insufficient finding: multi-evaluation per physics tick

Per the systematic-debugging rule ("3+ failed fixes -> stop guessing, add instrumentation"), added
temporary `print()` calls at every write site of `idle_lower_latched_target[side]` and at
`_latch_idle_lower_support`'s entry, tagged with `Engine.get_physics_frames()`.

**Finding:** `_latch_idle_lower_support` (and therefore the whole idle-lower latch/acquire state
machine) is called **multiple times per single physics tick** - up to 6 times observed for the same
`Engine.get_physics_frames()` value. This is expected Godot behavior: `sample()` is driven from
`player_foot_ik_modifier.gd`'s `_process_modification_with_delta`, a `SkeletonModifier3D` callback
that runs once per **rendered** frame, not once per physics tick. At any render rate above the
physics rate (60 by default, easily true on any real monitor and unthrottled in headless mode),
this function gets invoked several times for what is logically "the same instant," each call with a
tiny `delta`.

This is real (confirmed by the print instrumentation) and worth knowing, but attempt 5 above proved
it is **not the cause of the visible drift**: gating the decision to run once per tick changed some
internal bookkeeping (transition count) without changing the drift's magnitude or period at all. The
actual trigger is still unidentified - it produces the same ~20-frame cycle whether the underlying
decision is re-evaluated once or several times per tick, which rules out "asked too often" as the
mechanism and points at something that genuinely changes once per physics tick, tick after tick, at
this specific stance.

## Where this stands

Five attempts, five different specific hypotheses, all tested via the fast headless repro, none
fixed it. Per the project's debugging discipline, this is the point to stop making one-line guesses
and either add much more targeted instrumentation on the *left* foot's own code path directly (since
that's the foot that's actually visibly drifting - all five attempts so far targeted the *right*
foot's latch state on the theory that it drives the left foot upstream, which was never itself
re-verified after 023) or step back and reconsider this stance-boundary-hugging design more broadly,
as discussed with the user. Not yet decided which; nothing has been rebuilt since the revert.

## Verification (once the fix is built)

- Headless repro above must show a flat/stable `FOOT_SAFE_ZONE`/`IK_DIVERGENCE`-free trace for the
  full 600-frame run at the exact reported spot.
- `scripts/check_foot_ik_fast.sh` / `check_foot_ik_all.sh` - confirm no new regressions.
- Live-tested by the user at the same stance - the real acceptance bar, per standing project rule.

## References

- `AGENT_TASKS/021_split_safe_root_target_oscillation.md`,
  `022_idle_stance_rehome_self_referential_drift.md`,
  `023_stance_zone_boundary_retrigger.md` - the three earlier, structurally different fixes for the
  same-looking symptom, all confirmed still working/inactive here.
- `tests/manual/foot_ik/foot_ik_preview.gd` - default spawn point now set to this bug's exact repro
  position/rotation, enabling headless reproduction.
- `foot_ik_controlled.jsonl` traces preserved at `/tmp/foot_ik_controlled_headless_20260913_*.jsonl`
  (several, across the four rejected attempts - all show the identical ~21-frame cycle).
