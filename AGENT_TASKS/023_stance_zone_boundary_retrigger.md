# 023: A foot settled right at the stance-zone edge retriggers rehome forever

## Status and scope

**Root-caused via live telemetry, fixed, passing the full `check_foot_ik_fast.sh` suite. Awaiting
live test.** Found live, same-looking symptom as 021/022 ("foot moves constantly on idle") *after*
both of those fixes were already committed and confirmed working for their own mechanisms - this
is a third, distinct cause behind the same visible complaint.

## The concrete symptom

Character standing still (`root` and `velocity` both confirmed constant across the whole window),
left foot `owner=live_contact`. `raw_target` - the real ground-sampler raycast contact - is
essentially fixed: `(15.582, 1.4, 1.908)`, sub-millimeter jitter only. `smoothed_target` cycles on a
clean, regular ~17-19 frame period:

1. **Snap**: `smoothed_target` jumps instantly to exactly match `raw_target` (confirmed to 5
   decimal places - an instant relocate, not a gradual `move_toward` step).
2. **Hold**: stays matching `raw_target` closely for ~5-6 frames.
3. **Drift**: starts moving away from `raw_target` in one `move_toward`-sized step per frame
   (~0.02-0.07m), continuing for ~9 more frames, reaching ~0.3m away.
4. **Snap back** to step 1, repeat forever.

`scripts/trace.sh --anomalies` shows this as a recurring `FOOT_SAFE_ZONE left` line every cycle,
with `lat` oscillating between ~0.56 and ~0.60 - hugging the stance zone's own lateral boundary
(`STANCE_ZONE_MAX_LATERAL = 0.56`).

## Root cause, confirmed by reading `_rehome_idle_stance_target`/`is_target_inside_stance_zone`

Neither 021 (split-safe-root) nor 022 (self-referential rehome destination) is active here -
confirmed directly: `safe_zone_decision` reads `action=keep_common_support surface_y=-inf` the
whole time (021's mechanism fully disengaged, as designed), and the destination computation now
correctly anchors on `raw_target` (022's fix). This cycle is a *different* interaction:

The real ground truth for this foot's natural idle stance sits *right at* the stance zone's
official lateral boundary (0.56) - close enough that ordinary idle-sway animation noise pushes it
just outside on some frames and just inside on others. `_rehome_zone_anchor` clamps to a *tighter*
range than the official zone (`STANCE_ZONE_MAX_LATERAL - 0.04 = 0.52`, an intentional safety
margin), so whenever `raw_target` drifts even slightly outside 0.56:

1. `_rehome_idle_stance_target` fires (current is judged outside zone) and finds `raw_target`
   itself still valid (inside zone check on `raw_target`, not `current`), so it snaps `current`
   directly to `raw_target` - matching the "snap" step.
2. On the next few frames, `raw_target` fluctuates back to just *outside* 0.56 again (same idle
   sway). Since `current` now equals `raw_target`, `current` is *also* judged outside zone, so
   rehome fires *again* - but this time `_rehome_zone_anchor` clamps the destination down to 0.52,
   a real ~4cm-different point from where the foot naturally sits. `move_toward` starts walking
   toward that clamped anchor - the "drift" step.
3. A few frames into that walk, `current` (now away from the real, well-supported natural spot)
   loses `_has_surface_at_height` confirmation at its own new position - real geometry near this
   specific corner doesn't have solid ground exactly at the clamped 0.52 anchor point either.
   `same_height_supported` goes false, falling to the `elif` branch, which snaps `current` straight
   back to `raw_target` - closing the loop.

This is not a coding bug in the sense 021 and 022 were - `_rehome_zone_anchor` is doing exactly
what it's designed to do (pull toward a safety-margined anchor). The problem is that the safety
margin itself doesn't have guaranteed real support at every location, and the rehome trigger has no
hysteresis: a target already essentially at the real, valid ground truth gets *reclassified* as
needing correction on every idle-sway micro-fluctuation across the same few-mm boundary.

## Fix

Added an optional `margin` parameter to `is_target_inside_stance_zone` (default `0.0`, so every
other call site's behavior is unchanged), and pass a new `IDLE_STANCE_REHOME_MARGIN = 0.05`
specifically at `_rehome_idle_stance_target`'s own entry gate. A target within 5cm of the official
zone boundary is now treated as "close enough, leave it alone" - not worth retriggering a rehome
cycle over. Genuine drift (the original 021/022 symptoms, which moved the target by many tens of
centimeters) is far outside this margin and still triggers correction normally.

One function signature change (backward compatible), one new constant, one call-site edit.

## Verification

- `FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=16` - unchanged.
- Full `scripts/check_foot_ik_fast.sh`: bit-for-bit identical to the pre-fix baseline except this
  change, including the one pre-existing, unrelated `FOOT_IK_IDLE_PLANT_STABILITY_CHECK` failure
  (task 019).
- **Not yet live-tested.** Awaiting confirmation at the same stance that exposed this.

## References

- `AGENT_TASKS/021_split_safe_root_target_oscillation.md`, `022_idle_stance_rehome_self_referential_drift.md`
  - the two earlier, structurally different fixes for the same-looking symptom; both confirmed
  still working correctly here (021 fully disengaged, 022's anchor computation correctly
  raw_target-based) - this is a third, independent mechanism.
- `foot_ik_controlled.jsonl` (preserved at `/tmp/foot_ik_controlled_20260913_145252.jsonl`, frames
  350-415 are the clearest single cycle) per AGENTS.md's "preserve before running another harness"
  rule - the live telemetry that found this.
