# 020: Foot loses ground contact at a ramp corner and clips deeply into the ramp

## Status and scope

**Open, unfixed, root-caused.** Part of the pre-existing `check_foot_ik_ramp_sweep.sh` known
baseline (16/16 failing cases, `worst_depth_m=0.105375`, tracked since before this session).
Investigated the worst case directly rather than leaving it as an unexplained accepted number.

## The concrete symptom

`foot_ik_ramp_matrix_check.gd`'s dense edge/corner sweep on a 45-degree ramp: standing at the
ramp's bottom-left corner (`fraction=0.025` - ~10cm from the bottom edge, `lateral=-half_width` -
at the left edge), facing `yaw=225°`, at animation phase 7/8 of the idle cycle - the left foot
ends up ~10.5cm deep inside the ramp, 236 vertices penetrating across both `foot_l` (84) and
`ball_l` (152, the whole forefoot/toe). This is not a shallow toe-tip graze; the entire foot is
buried.

## Root cause, confirmed by direct investigation

Added temporary debug prints to `_finish_current_case()` gated to this exact case
(`position_name=sweep_bottom_left`, `phase=7`, `yaw≈225°`), then reverted them after capturing:

```
[SWEEPDBG] owner=live_contact valid=false reason=selected_legacy_candidate
           surface=(-1.101755, 0.274994, -0.086483) ankle=(0.0, 0.0, 0.0) normal=(0.0, 1.0, 0.0)
[SWEEPDBG2] hit=false dist=-1.0 raw=(-1.101743, 0.277717, -0.08919)
            smoothed=(-1.101755, 0.274994, -0.086483) final_foot=? anim=unarmed_idle
```

`debug_contact_hit["left"] == false` and `debug_contact_distance["left"] == -1.0` - **the left
foot has lost ground contact entirely** at this frame. The coordinator's plan for this leg never
gets validated (`reason=selected_legacy_candidate`, the untouched pass-through default - same
signature as 019's "`_finish_validation` never ran for this leg" finding) and its `ankle_target`
reads as `(0,0,0)`, an unpopulated value.

Working hypothesis (not yet proven to the same depth as 019's root cause): at this specific
corner + facing + animation phase, the idle animation's own natural sway swings the left foot far
enough past the ramp's actual physical edge (in world space, given the 225° yaw and being already
within ~10cm of both the bottom and left edges) that the downward ground raycast finds nothing -
genuinely open air past the ramp, not a raycast-tolerance issue. Whatever path runs on losing
contact then does not keep the rendered foot in a geometry-safe position; it ends up clipping
deep into the ramp's own body instead of floating above it or holding a last-known-safe pose.

This is the same broad symptom family as the preview-tool spawn-edge over-reach bug fixed
earlier this session (018 follow-up) and 019's toe/riser clip - all three are variations of
"foot swings near a slope/edge and the contact-loss/validation path doesn't keep the result
geometry-safe" - but this one is a full contact loss (not an over-reach or an un-validated
owner), so it likely needs its own fix, not a reuse of either of those two.

## Update 2026-09-12: hypothesis confirmed, no-ground fallback traced, two fix attempts, both rejected

Confirmed the "genuinely no ground nearby" hypothesis directly: a temporary wide (3m), unfiltered
(`require_walkable=false`) raycast from 1m above the failing foot found nothing, consistently,
across every sampled frame of this case. The idle sway really does swing the foot past the ramp's
physical edge into open air at this corner - not a raycast-tolerance gap.

Traced the fallback path (`player_foot_ik_modifier.gd`'s per-leg loop, around line 526): when
`_ground_sampler.sample()` returns `hit: false`, the idle-only `_retract_to_reachable()` helper
tries to find a nearby reachable spot to stand on instead. If it also fails, the leg's IK is
skipped entirely for that frame (`per_leg[side]["hit"] = false; continue`) and the character's raw,
un-corrected animated pose is left standing - which was authored for flat ground, so on a 45-degree
ramp corner it clips deep into the incline. This confirms the "what renders it" question from the
prior update: nothing renders it; it's the *absence* of any IK correction that leaves the raw
animation pose in place.

Root-caused *why* `_retract_to_reachable()` itself fails here, with two real defects found:

1. **Its "quick path" (reuse the previous frame's smoothed target) always fails at this corner**,
   because the previous smoothed target is itself already past the ramp's edge (same "no ground
   nearby" fact as above) - expected, not a bug on its own.
2. **Its fallback candidate-direction search also fails**, but for two compounding reasons:
   - The 4 candidate directions it tries (`toward_stance`, `backward`, `lateral`,
     `backward+lateral`, all body-relative) do not include a plain "straight back toward the
     body/hip" direction. Adding one (tested in isolation) changed nothing at radius 0.12 - it
     found the ramp surface a couple of raycast steps in, but got rejected anyway (see next point) -
     confirming this addition alone is a no-op, not a fix, but not harmful either.
   - The real gate is `has_support_patch()` (used generically across ground_sampler for stairs and
     here): it requires a full 0.12m-radius patch of matching, coplanar ground on all 4 world-axis
     sides of a candidate point. Near a ramp corner, at least one of those 4 offset points falls
     past the ramp's physical boundary into open air, so the check correctly reports "not a full
     patch" and rejects an otherwise-reasonable, if edge-adjacent, foothold. This is a real
     architectural mismatch: `has_support_patch`'s uniform radius assumes there's always room for a
     symmetric patch, which is untrue by definition within centimeters of any corner.

**Fix attempt 1** (kept, harmless): add a `toward_root` candidate direction to
`_retract_to_reachable`'s search list. Verified in isolation to be a no-op at the existing 0.12m
patch radius - it finds ground but `has_support_patch` still rejects it. Reverted along with attempt
2 for cleanliness, but safe to re-add if a real patch-radius fix lands.

**Fix attempt 2** (reverted, causes a regression): shrink `has_support_patch`'s radius from 0.12m to
0.04m for this one call site only. This did fix the target case dramatically (yaw 225,
`max_depth_m` 0.105375 -> 0.017988, `penetrating_vertices` 236 -> 27, whole-foot burial -> a small
toe graze). However, re-running the same position across all yaws exposed a **new regression**: two
previously-clean yaws at the same corner (270, 285) started failing on the *other* foot
(`max_depth_m` 0.076-0.078, ~350 penetrating vertices each) - the looser check now accepts a
foothold there that used to be correctly rejected, and that foothold turns out to be a worse fit.
Isolated cleanly: the `toward_root` direction change alone (radius left at 0.12) reproduces the
*original* baseline exactly (only yaw 225 fails, same 0.105375 depth) - the regression is caused
specifically by the radius shrink, not the added search direction.

**Conclusion: no safe fix found this session.** Per this project's own debugging discipline (3+
fix attempts / new symptoms in a different place -> stop and reconsider the architecture rather
than keep tweaking), stopping here rather than trying a fourth variant blind. All experimental code
was reverted; nothing was committed.

## What to try next

- A properly slope-aware version of `has_support_patch`: instead of 4 fixed-radius world-axis
  offsets, sample offsets tangent to the candidate surface's own plane (perpendicular to its
  normal), and/or shrink the radius adaptively as remaining verified-flat area shrinks, rather than
  a single global radius constant used both for generous stair-tread checks and this tighter
  edge-of-a-ramp case. This is a shared helper (also used for stair tread validation) - any change
  needs the full `check_foot_ik_ramp_sweep.sh`/`check_foot_ik_stairs*.sh` suites re-run, not just
  this one case.
- Alternatively, accept that some ramp corners are genuinely too small for a full stance and design
  a graceful "no reachable foothold" fallback distinct from silently freezing the raw animated pose
  (e.g., a small controlled retreat toward the body's own footprint, using the confirmed-solid
  `settled` root position as the target rather than searching outward from the lost foot).
- Given the resemblance to 019's "coordinator never validates this owner" signature, still worth a
  final check on whether the same `legacy_transition_active`-style gap applies to this fallback
  path too, though the fallback tracing done this session did not surface one directly.

## References

- `tests/manual/foot_ik/foot_ik_ramp_matrix_check.gd::_build_dense_sweep`/`_finish_current_case` -
  the reproducing scene; already supports `-- case=<position_name>` to isolate one position (see
  `_filter_requested_case`), though the failing case also needs the specific yaw/phase combination
  from `foot_ik_ramp_sweep_failures.jsonl` (written under `user://` by a real sweep run) to
  reproduce exactly.
- `scripts/check_foot_ik_ramp_sweep.sh` - the runner; its `rg` filter only surfaces
  `FOOT_IK_RAMP_CASE FAIL`/`FOOT_IK_RAMP_MATRIX_CHECK` lines, so any new debug print during
  investigation must be read from the full godot invocation directly, not through this wrapper.
- `AGENT_TASKS/019_foot_ik_toe_riser_clip_during_rotation.md` - the closely related, still-open
  toe/riser clip; check there first before assuming a new mechanism.
