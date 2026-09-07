# 015: Foot IK architecture direction - single authoritative plan, no silent post-plan mutation

## Status and scope

Open, not started. This is a direction-setting task, not a bug fix: it records an outside
architectural assessment of the whole Foot IK system (solicited by the user, reviewed and
largely agreed with), and scopes how to act on it incrementally rather than as a rewrite.
Read this before starting [010](010_foot_ik_target_coordinator_consolidation.md)'s remaining
`STAIR_SUPPORT`/`STAIR_SWING` migration - that task is exactly where this one's central concern
(continuous target mutation with no single authoritative writer) already lives.

## The assessment

> My honest assessment: it has a good foundation, but it is not yet a reliably composed
> system. I would keep the useful pieces and improve their contracts - not rewrite everything.
> The recurring bugs are evidence of architectural problems, not just missing angle limits.

**What's good** (assessment's own words): sampling, gait tracking, landing planning, target
coordination, and bone solving are already separated into modules; the coordinator is the right
direction; preserving authored animation, checking toe/leaf geometry, and testing intermediate
poses are good requirements; the regression scenes and diagnostics are valuable evidence, not a
from-scratch situation. The ~5,100 lines are not inherently the problem - how much hidden
knowledge each module needs about the others is.

**Six concerns, in the assessment's own words** (kept verbatim - each is checked against this
project's actual history below, not taken on faith):

1. **The coordinator is not actually the final authority.** After coordination, the modifier
   can change foot spacing, straighten a target, adjust a slope target, or substitute a cached
   seam target - a "validated target" may not be the target ultimately solved
   (`player_foot_ik_modifier.gd:890` region). Finishing the owner migration alone will not fix
   this unless downstream target changes also follow the contract.
2. **Modules are separated into files but still share too much mutable state.** The coordinator
   reaches into the sampler and gait tracker to erase latches and freezes; the solver reads
   animation names, owner internals, and pelvis state, and retains its own slope-target history.
   This creates ordering conflicts - one feature's decision gets silently changed or invalidated
   by another - producing race-like symptoms without any actual threading.
3. **"Valid" currently means several different things.** Some checks are bypassed but their
   flags still read true (the raw-recovery fallback deliberately skips toe validation, for
   example - `foot_ik_target_coordinator.gd:146`). Needs to distinguish: checked and satisfied;
   not checked/not applicable; temporarily tolerated; degraded fallback. Otherwise both
   debugging and later decisions trust a guarantee that was never actually established.
4. **Time and coordinate-space contracts are too implicit.** The concrete example: solving and
   releasing disagreed about how to inherit pelvis displacement. Animation snapshots, target
   histories, correction histories, and repeated modifier evaluations need a consistent rule -
   advance state once per simulation tick, reapply the corresponding output on refreshes - and
   every pose/target needs an unambiguous coordinate space.
5. **IK is carrying several different responsibilities** (correcting contact, planning steps,
   recovering stance, influencing safe-zone movement, coordinating the pelvis) that all behave
   as foot-target overrides instead of cooperating through one channel. Longer-term: separate
   *where the character intends to step/move* from *how the skeleton reaches that pose*. The
   three locomotion modes also need an explicit production-vs-experimental status.
6. **The tests are extensive, but the feedback system is weaker than the coverage.** Known
   failures stop later checks; large scenes make small transition bugs expensive to isolate.
   Needs cheap contract tests, deterministic transition replays, and a sequential runner that
   reports every result and distinguishes baseline failures from new ones.

**Proposed pipeline**: Animation snapshot -> contact observations -> coordinated feet/pelvis
plan -> pose solve -> final validation -> apply. No silent target replacement after the plan is
finalized; necessary adjustments become part of the plan; solve and release share the same
output contract. Prioritize this over adding more smoothing, thresholds, or joint controls -
those remain useful but can't make conflicting ownership predictable.

## Why this checks out (verified against this project's own recent history, not taken on faith)

- **Point 1 and point 4 are exactly the bug fixed in [013](013_foot_ik_bend_selection_instability.md)
  this same day** (commit `fc2c188`): `release_to_animation()` read the raw animated pose
  without the pelvis lateral-shift/drop offset that `_apply_support_pelvis_and_legs` applies to
  the actual pelvis bone elsewhere - solve and release disagreed about the coordinate space a
  position was in, with no contract forcing them to agree. This was not a one-off: the same
  function also does lateral-shift re-centering, slope-target adjustment, and seam-freeze
  substitution *after* the coordinator has already validated a plan - all named directly in
  point 1.
- **Point 3 matches the raw-recovery fallback's `check_toe=false` bypass** and the
  `TOE_INVALID_HOLD_FRAMES` streak-tolerance in `_finish_validation` - both blur "actually
  checked" with "tolerated anyway" behind the same `plan.valid = true`.
- **Point 6 was felt firsthand, repeatedly, across this entire multi-session Foot IK effort**:
  `scripts/check_foot_ik.sh` is fail-fast, which is why an ad hoc continue-past-failures copy
  (regenerated more than once as the real script changed) had to be hand-rolled every time a
  fix needed verifying against the *complete* failure picture rather than whichever known
  failure happened to sit first in the script.

Given every point checks out against concrete, already-documented incidents rather than
abstract concern, the assessment is treated as accurate and worth acting on - incrementally,
not as a rewrite (see next section).

## What to actually do (scoped, incremental - not a rewrite)

A full pipeline formalization (point 1-5) is large and cross-cutting - it would touch every
post-coordinator mutation point at once, in code this project's own history shows is fragile
(009's ownership review flagged `foot_ik_stair_predictor.gd` as explicitly self-documented
"TEMPORARY / EXPERIMENTAL"). Today's session needed hours of careful evidence-gathering to
trust even a single-line, narrowly-scoped fix in this area. Treat this as a lens to apply
incrementally, not a project to start outright:

1. **Use it to shape [010](010_foot_ik_target_coordinator_consolidation.md)'s remaining
   `STAIR_SUPPORT`/`STAIR_SWING` migration**, rather than opening a separate rewrite effort.
   That task is already exactly where points 1 and 2 live: a continuously-transferring target
   with no single authoritative writer, mutated by `foot_ik_stair_predictor.gd` outside the
   plan system entirely. Any gate designed for it should produce a real plan the modifier
   cannot then silently override, not just another validation check bolted onto the existing
   pattern.
2. **Point 6: done.** `scripts/check_foot_ik_all.sh` runs every entrypoint `check_foot_ik.sh`
   covers plus every sibling script (including `check_foot_ik_ramps.sh`/
   `check_foot_ik_ramp_sweep.sh`, which `check_foot_ik.sh` never calls at all), continuing past
   failures, and separates a hand-maintained `KNOWN_BASELINE_FAILURES` list from new/unexpected
   ones (only the latter make it exit non-zero) - replacing the repeated ad hoc `/tmp`
   continue-past-failures scripts this session kept regenerating. Running it for the first time
   immediately paid for itself: it surfaced that `check_foot_ik_ramps.sh`/
   `check_foot_ik_ramp_sweep.sh` were failing (43/245 and 22/168 cases - the already-known
   012 ramp-edge residual) despite never having been run standalone earlier this session,
   exactly the blind spot `AGENTS.md` already warned about.
3. **Point 3's validity taxonomy** (checked-and-satisfied / not-checked-or-applicable /
   temporarily-tolerated / degraded-fallback) is a good target shape for `FootIKTargetPlan`'s
   `valid`/`stance_valid`/`support_valid`/`reach_valid`/`toe_valid` fields, which currently
   collapse all four states into a single boolean per check. Worth adopting the next time any
   of those fields is touched, rather than as its own separate pass.
4. **Points 1, 2, 4, 5 (the full pipeline formalization)** remain a longer-term direction, not
   scoped into concrete steps here - do that scoping only once 010's remaining migration is
   done and provides a second, independent data point on what "one authoritative writer" needs
   to look like in this codebase specifically.

## References

- [009](009_foot_ik_architecture_review.md) - the existing ownership-matrix review this
  assessment largely corroborates from an outside angle.
- [010](010_foot_ik_target_coordinator_consolidation.md) - the coordinator consolidation this
  assessment's point 1/2 concerns should shape, especially its still-open
  `STAIR_SUPPORT`/`STAIR_SWING` piece.
- [013](013_foot_ik_bend_selection_instability.md) - the `release_to_animation()` fix
  (commit `fc2c188`) that concretely demonstrates points 1 and 4.
- `actors/player/foot_ik/foot_ik_target_coordinator.gd`, `actors/player/player_foot_ik_modifier.gd`
  - the files point 1's "coordinator is not the final authority" concern is about.
