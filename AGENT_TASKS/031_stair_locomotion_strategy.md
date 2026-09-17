# 031 - Stair locomotion strategy: authored stair clip vs procedural gait

Status: decision pending. 025/028/030 have shown the current hybrid - a flat walk clip corrected by
reactive IK - cannot be tuned into a clean stair walk.

## Why the hybrid is the wrong base (retrospective)

- 025 (the toe clip) and 028 (the joint jank) are **one mechanism** (see AGENTS.md): the step-up
  target moves a full tread in one frame, the planted toe enters the riser, the 025 retry fires, and
  its re-solve spikes the joints 40-180 deg.
- So every single lever trades clip against jank or is null/worse (full list in 028/030). The
  clip-worthy pose comes from the *base pose/target*, not from the correction.
- Deeper cause: a flat-ground walk clip plus bolt-on stair corrections means the corrections fight
  the clip. Two ways out.

## Path A - authored stair-walk animation(s)

The standard fix. The base pose becomes stair-correct, so the IK returns to being *refinement*
(slopes, exact contact) and the retry/jank corrections likely stop being needed.

- Need: an in-place, looping stair-walk cycle (up; down optional), retargeted to the character.
- Candidate sources (must have explicit Godot-compatible terms - Epic's GASP/UE assets are UE-Only
  per [027](027_gasp_animation_assets_and_architecture_reference.md), do not import them):
  - **Mixamo** (mixamo.com, Adobe, free) - has "Climbing Stairs" / "Walk Up Stairs" style clips;
    FBX download; ubiquitous in Godot; re-check Adobe's terms.
  - The project's existing source library (UAL / MotusMan) - `player_body.gd`'s `BONE_MAP` already
    retargets UAL clips; check whether that library has stair clips.
  - CC0 packs (Quaternius, Kenney, KayKit) - may or may not include stairs.
  - Blender / the user's own tooling - a 4-step cycle is small.
- Import path exists: `tools/retarget_cli.gd` + `HumanoidRetargeter` retarget an arbitrary source
  clip onto a catalog character headlessly.
- Acceptance: the clip swapped in, measured in `foot_ik_stair_lab.tscn`; clip/joint metrics better
  than baseline with the 025 retry disabled (proving the base pose no longer needs it).

## Path B - procedural leg gait

No authored base; the terrain drives the feet, so the retry/regime-flip class of bugs disappears -
this was the user's original direction.

- Existing material: `docs/PROCEDURAL_ANIMATION_RESEARCH.md` (modules, math, Godot built-ins) and the
  reference repo reviewed this session (jegor377/ProceduralWalk) - a legs-only stepper (step-when-
  drift). Caveat: `SkeletonIK3D` is a dead end in Godot 4 (AGENTS.md); solve bones directly, and the
  repo leaves the upper body static (looks robotic).
- Research/design needed before building:
  1. A gait/phase model (step timing, stride, speed) and foot placement (where to plant per step).
  2. Whole-body: pelvis/COM and upper-body counter-motion (not just legs).
  3. Integration: the project already has a strong two-bone leg solver + ground sampler - drive its
     *targets* from the procedural gait and let it place the feet (reuse, not replace).
  4. Composition with idle/landing/turning, and with the released-swing finding (`STAIR_SWING`).
- Acceptance: a plausible walk cycle at several speeds, flat and stairs, measured in the lab.

## Recommendation

- Cheapest unblock: **Path A** (one stair-walk clip) - likely hours of asset work vs the months of
  correction tuning the hybrid has cost.
- The user's stated preference and the original goal: **Path B** (procedural) - bigger, but removes
  the whole bug class. If a licensed stair clip can't be sourced, Path B is the fallback.
- Next step: (1) try to source a stair clip (Mixamo/UAL) and test it in the lab; or (2) a focused
  procedural research spike covering the four items above, then a gated prototype A/B'd in the lab.

## Do not

- Do not re-try the single-lever stair corrections (028/030 lists) - they are proven trades.
- Do not import UE/GASP assets (UE-Only; 027).

## 2026-09-17 result: Path A works (with the transfer lift + no retry), selection needs a transition

Measured in the lab (`trace_query.py lab`, stair region), same walk, only the base clip changed:

| setup | joint p95 / max | clip |
| --- | ---: | ---: |
| flat clip + retry (baseline) | 26.81 / 50.12 deg | 0.0000 m |
| stair clip + retry | 25.27 / 36.14 | 0.0100 m |
| stair clip + no retry | 12.00 / 12.00 | 0.0922 m |
| stair clip + no retry + **support-transfer lift** | **12.00 / 12.00** | **0.0180 m** |

So the stair clip + the transfer lift + the 025 retry OFF gives flat-walk-smooth joints and a 1.8 cm
clip (mostly the stair clip running on the flat approach). The retry is confirmed as the jank; the
authored base pose plus the lift is what lets it be turned off.

Retargeted clips: `assets/models/stair_clips/stair_walk_{up,up_2,down,down_2}.res`, produced by
`tools/retarget_cli.gd` (now Mixamo-aware). Added to the player's `moves` library via
`PlayerStairClips.add_to()`.

**Selection needs a transition.** A naive per-frame swap of the walk clip to the stair clip when the
predictor becomes active regressed the lab clip to 12.4 cm - the two clips have different gait
phases, so the switch snaps the feet. `PlayerStairClips.select_walk()` exists but is not wired; a
proper phase-matched crossfade (cf. `player_locomotion_transition.gd`'s `GAIT_PHASE_GROUPS`) at the
flat<->stair boundary is required. Do not hard-swap.

Lab A/B: `-- --lab-check --stair-clip [--no-toe-retry]` (see 030's scaffold section).

### Phase-aligned switch attempted - still not enough

`player_locomotion_transition.gd`'s `GAIT_PHASE_GROUPS` was defined but unused; implemented it and
grouped the stair clips with the walk (start the new clip at the same normalized phase). A
phase-aligned flat<->stair swap still regressed the lab clip to 12.1 cm - the two clips' stride/cycle
do not line the planted foot up with the terrain the way the phase fraction implies, so normalized
phase is not the right alignment. Auto-wiring `PlayerStairClips.select_walk()` is reverted; the lab
panel now has manual checkboxes ("use retargeted stair clip", "disable 025 toe retry") to A/B by eye.
Next: a terrain-matched enter/exit for the stair clip (e.g. switch on the first riser at a
planted-foot moment, or a dedicated blend), not a per-frame clip swap.

### Game wiring attempted - no clean switch signal exists

Wired `PlayerStairClips.select_walk_gated()` into `update_motion`, gated to the current clip's loop
seam (both clips restart there). Every signal tried is unusable and/or the switch regresses the lab:

- Predictor `is_active()` (Foot IK ownership): active only ~14 of 163 walk frames on the climb.
- Stair controller `recent_transition`: true for ~2 frames.
- A seam-gated switch with either: the stair clip plays a partial cycle (1.18s clip vs the short
  window), the terrain placement mismatches, and the lab regressed (jank 50 -> 59 deg, or clip
  14.6cm with the retry off).

So the stair clip cannot be wired as a per-frame swap. It needs (a) a continuous "on the staircase"
signal (e.g. a trigger volume or the stair surfaces themselves, not the transition flags) and (b) a
dedicated stair-locomotion mode whose enter/exit is designed as one motion, not a clip swap
mid-stride. Reverted the wiring; the lab keeps its manual checkboxes to show the improvement.
