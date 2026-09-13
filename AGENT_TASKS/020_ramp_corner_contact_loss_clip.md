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

## What to try next (not attempted)

- Confirm the hypothesis directly: sample the raycast at the exact foot XZ this frame across a
  wide radius (same technique used for the preview-spawn-edge investigation) to prove there is
  really no ground within reach, not a raycast range/tolerance gap.
- Find what code path actually renders the foot when `contact_hit == false` for an
  otherwise-idle leg, and why it lands 10cm deep in the ramp instead of at the last known
  good position or a raw animated (off-ground) pose.
- Given the resemblance to 019's "coordinator never validates this owner" signature, check
  whether the same `legacy_transition_active`-style gap or a similar "not migrated for this
  owner" gap applies here too, before assuming a new, unrelated mechanism.

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
