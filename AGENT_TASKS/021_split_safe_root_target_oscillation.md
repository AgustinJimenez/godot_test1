# 021: Split-safe-root search re-picks a different candidate on every arrival, sweeping the foot

## Status and scope

**Root-caused. Fixed (second attempt, first was rejected by automated testing), passing the full
`check_foot_ik_fast.sh` suite including the ledge-safety check the first attempt broke. Awaiting
live test before commit**, per this project's standing rule for gameplay-behavior changes. Found
live by the user standing still on a split-height stance (stairs/overheight platform), reported as
"right foot moves constantly on idle." Confirmed via `foot_ik_controlled.jsonl` telemetry, not just
visual impression.

## The concrete symptom

Character standing perfectly still (`velocity=(0,0,0)`, `root` position and yaw both constant
across the whole window) in a split stance: left foot `owner=idle_lower_latched` (stable,
`target_y=1.400`), right foot `owner=live_contact` (`target_y=1.750`, `plan_solve_validated:
false`, `target_plan_reason: selected_legacy_candidate` - the coordinator never actually validates
this leg's target, same signature as 019/020's "never reaches `_finish_validation`" finding).

The right foot's `smoothed_target` swings horizontally by ~0.55m and back, repeating roughly every
26 frames (~0.43s) forever while idle - e.g. one cycle's X went `14.28 -> 14.03 -> 13.73 -> 13.82 ->
14.05` while the character's root X never moved from `14.18`. `solved_foot_pos` chases this with
rate-limited lag, producing sustained `IK_DIVERGENCE` anomalies (target vs. solved gap up to
0.243m while `ground_weight=1.0`, i.e. "fully planted" by the coordinator's own bookkeeping).

`safe_zone_decision` during this window reads `action=keep_common_support surface_y=-inf
root_distance=-1.000` - the split-safe-zone search is not finding (or not holding) a common
support point at all.

## Root cause, confirmed by reading `_request_overheight_split_safe_zone`

`foot_ik_ground_sampler.gd`'s split-safe-root search re-runs its own **full ~1000-candidate spiral
search from scratch** every time the character's root is within 3cm of the previously-found
`split_safe_root_target` ("arrived"), because the code that decides whether to search treated
"arrived" and "needs a fresh search" as the same condition (`stale := ... or
root.distance_to(split_safe_root_target) <= 0.03`).

A fresh spiral search starting from a position that has just walked to the *previous* result does
not reliably return that same point - it's an expanding-ring scan over many structurally similar
candidate offsets, and which one it returns first is sensitive to tiny position/geometry
differences. So each cycle: character nudges toward candidate A, arrives, re-searches, gets
candidate B nearby, nudges toward B, arrives, re-searches, gets candidate C (possibly back near A),
and so on indefinitely - visible as the foot's target sweeping between several nearby-but-distinct
points, forever, for as long as the character stays in this split stance.

This is the same code finding H (`AGENT_TASKS/018`) instrumented for its *performance* cost
(`split_safe_ring`, 3-11ms/call, run every `SPLIT_SAFE_SETTLED_COOLDOWN_FRAMES`) - and finding H's
own already-designed fix (reconfirm the existing candidate cheaply instead of re-searching)
independently fixes this correctness bug too, since it stops the search from ever picking a
*different* candidate once one has already been found and arrived at. That fix was implemented and
measured earlier this session, but was accidentally discarded by an unrelated `git checkout --`
while reverting a different (020) experiment that touched the same file - see "Note" below.

## Fix

Restored and reframed finding H's fix as a correctness fix, not just a performance one, in
`_request_overheight_split_safe_zone`:

- On arrival (root within 3cm of `split_safe_root_target`), **reconfirm the same candidate** with
  the search's own 3-point check (`FootIKSplitSafeSearch.reconfirm`) at zero motion offset from
  the existing target, instead of running the full spiral search.
- Only fall back to the full `find_nearest_root` spiral search if that reconfirmation actually
  fails (the previously-found spot stopped being valid) or no candidate has ever been found yet.
- The pre-arrival "still walking toward it" path (`continuing_recovery`, unchanged) is unaffected -
  this only changes what happens the moment the character reaches the target.

Files: `actors/player/foot_ik/foot_ik_ground_sampler.gd` (`_request_overheight_split_safe_zone`),
`actors/player/foot_ik/foot_ik_split_safe_search.gd` (new `reconfirm` method).

## Note: how this fix was lost and re-found in the same session

The original finding-H fix (performance framing only, not yet connected to this correctness bug)
was implemented and measured, then held uncommitted pending live test per this project's standing
rule. While investigating and reverting an unrelated `has_support_patch` experiment for task 020
(also touching `foot_ik_ground_sampler.gd`), a blanket `git checkout -- <file>` was used to discard
that experiment - which also discarded finding H's unrelated, still-held fix living in the same
file, since a file-level checkout cannot selectively keep one uncommitted change while discarding
another. This was only noticed because the user's live test of what was believed to be the
finding-H fix actually exercised the unmodified baseline, and reported a bug the fix would have
prevented. When reverting an experiment, check `git diff` against what *should* remain modified in
that file first, not just against a clean HEAD, if the file already carried other held-uncommitted
work before the experiment started.

## Verification, and why the fix above is currently reverted

`scripts/check_foot_ik_fast.sh` after applying the fix caught a real regression before any live
test was requested: `FOOT_IK_LEDGE_SAFETY_CHECK` went from a clean 16/16 pass on unmodified HEAD to
2 failures, both split-height cases, both `retained unsafe target height split 0.600m` -
`walk_to_idle_split_height_live_repro` (a 9-frame walk then 240 idle frames on a split platform -
structurally the same shape as the user's own live repro) and
`jump_land_split_height_commits_safe_support`. Confirmed by isolating with `git stash`: clean HEAD
passes this check outright; the fix alone reproduces both failures.

Working explanation: the "buggy" always-re-search-on-arrival behavior was, by accident, also acting
as a form of continuous re-optimization - each re-search re-evaluates from the character's current
position and can land on a different, sometimes *better* (fully height-converged) candidate than
the first one found. The reconfirm fix locks onto whichever candidate the *first* search happened
to find and never reconsiders it, even when that first candidate leaves the two feet's raw ground
targets at genuinely different heights (up to 0.6m, i.e. still straddling the platform edge rather
than having converged onto one shared level). The reconfirm check only verifies "is there still
ground here," never "did this candidate actually resolve the original unsafe height split" - so it
happily keeps re-confirming a candidate that was never good enough in the first place.

**The first fix (ground-only `reconfirm`) was reverted in full.**

## Second fix attempt: gate the reconfirm on the actually-observed height delta too

Added an `observed_height_delta` parameter to `reconfirm()`, computed by the caller as
`absf(upper_surface.y - lower_surface.y)` - both already fresh per-frame raw per-foot ground
samples passed in by `prepare_overheight_split_safe_zone`'s caller, i.e. exactly the same quantity
`check_safe_level` asserts on. `reconfirm()` now fails immediately if this delta exceeds 0.05m,
forcing a fresh full search instead of re-confirming a candidate that never actually resolved the
split.

This alone reproduced the *exact same* two failures, bit-for-bit identical numbers, which was the
first sign something else was wrong: a second, independent bug in the same new code path. Root
cause: the "arrived" branch reset `split_safe_retry_after_frame` to `current_frame +
SPLIT_SAFE_SETTLED_COOLDOWN_FRAMES` *even when reconfirm failed*, so the very check that was
supposed to trigger a fallback full search (`if needs_full_search and current_frame >=
split_safe_retry_after_frame`) always evaluated false in the same tick - the deadline had just been
pushed 6 frames into the future by the branch that decided a search was needed. Six frames later,
`arrived` was still true, reconfirm still failed, and the deadline got pushed forward *again* -
perpetually rescheduling the fallback search so it never actually ran, while `split_safe_root_target`
stayed pinned to the original bad candidate throughout the entire test.

Fix: only advance the cooldown when reconfirm *succeeds* (extending how long the good candidate can
be trusted without re-checking); on failure, leave `split_safe_retry_after_frame` untouched so the
fallback search's own already-satisfied deadline check fires in the same frame.

**Verified clean:**
- `FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=16` (matches unmodified baseline exactly).
- Full `scripts/check_foot_ik_fast.sh`: every check passes except `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`,
  confirmed via the same git-stash isolation technique to be bit-for-bit identical against
  unmodified HEAD (task 019's already-open toe/riser-clip bug, unrelated to this fix).

**Not yet live-tested.** This is the third time this exact function has needed correction in one
session (finding H's cost measurement, the first rejected correctness fix, this corrected one) -
treat any further change here with the same isolate-with-git-stash discipline used throughout
before trusting a result.

## References

- `AGENT_TASKS/018_ik_implementation_review.md`, finding H - the original performance framing and
  measurement of this exact code path.
- `foot_ik_controlled.jsonl` (preserved at `/tmp/foot_ik_controlled_20260912_231040.jsonl` per
  AGENTS.md's "preserve before running another harness" rule) - the live telemetry that found this.
