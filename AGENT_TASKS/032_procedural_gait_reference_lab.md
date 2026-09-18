# 032 - Procedural gait reference lab

Status: in progress; four flat modes now use full-pose matching, awaiting live review. Stair modes
remain geometry/phase-mismatched and need a separate solution.
No gameplay integration or commit of the new visual/animation changes until the user confirms them.

## Objective

Extend `tests/manual/procedural_walk/procedural_walk_lab.tscn` from one flat walk into an isolated
gait-comparison lab. Provide one-at-a-time walk, sprint, crouch-walk, stair-up, and stair-down modes;
sample this repository's licensed animation clips as whole-body motion references; keep a separate
procedural output; expose per-frame joint and contact metrics. Do not edit gameplay Foot IK while
another agent is working there. Do not auto-launch the visual scene for the user.

## Baseline

Commit `ef12b73` added the in-place/moving flat-walk prototype and
`docs/procedural_walk_experiment.md`. It has world-space planted ankles in moving mode, colored
joint markers, frame stepping, and `--lab-check` / `--moving-check`; both checks pass. The user has
observed that the arms are poor and wants the whole body compared to real clips.

## Source clips confirmed locally

- MotusMan native walk (1.167 s), jog (0.700 s), crouch-walk (1.200 s): imported FBXs all have
  the same 73-bone rig and `Skeleton3D:<bone>` track paths.
- UAL `Walk` (1.333 s) and `Sprint` (0.667 s): source GLB has 65-bone UE naming (`pelvis`, `Head`),
  so use `HumanoidRetargeter` with the existing `PlayerBody.BONE_MAP`, not raw local-copy.
- Mixamo stair-up (1.183 s) / stair-down (0.933 s): retargeted MotusMan `.res` clips under
  `assets/models/stair_clips/`, 53 tracks each.
- `procedural_walk_source_check.gd` is a compact, reproducible asset inventory.

## Current result

- One-at-a-time selector: Original, UAL walk/sprint/crouch, MotusMan aim-walk, Mixamo stair up/down.
  Interactive launch defaults to moving Original walk from a side-on camera; the in-place checkbox
  remains available, and mouse orbit is unchanged.
  The bank retargets UAL onto a private MotusMan rig, samples all 73 bones, and applies the sampled
  whole-body pose. All four **flat** reference modes preserve that full pose and move only Hips
  vertically for floor clearance. Stair modes still apply an independent leg/plant solve. The
  reference actor optionally shows the *raw* source beside it. These are source-dependent hybrids,
  **not** purely generated full-body gaits.
- Stair modes automatically traverse two side-by-side visible stair lanes, each four 0.18 m steps
  with 0.35 m treads. Foot targets use the real tread height; uphill pelvis elevation waits for the
  trailing planted foot to release rather than pulling it beyond leg reach. Geometry has no physics
  collider, so this does not prove shoe-mesh clearance. Stair traversal remains finite; flat moving
  modes no longer stop after eight cycles. Their floor/grid recenter by whole meters around the
  character, keeping the one-meter pattern visually continuous without growing scene geometry.
- Flat reference modes now estimate forward travel from their own near-floor backward foot speed,
  rather than sharing Original's 0.667 m/cycle. At native clip cadence the lab measures roughly
  0.81 m/s for UAL Walk and 5.38 m/s for UAL Sprint; switching modes while moving no longer turns
  travel off. Original retains its planted-foot lock, and stairs retain their geometry-matched path.
  This does not guarantee zero horizontal shoe slide because source clips lack authored root motion.
- Bounded `user://procedural_walk_metrics_<mode>.jsonl` capture records all 73 joints' per-frame pose
  difference and rotation speed versus source, plus knee flex, ankle errors, root travel, and phase;
  the panel shows current worst values. The imported stair-down reference has a ~63° one-frame leg
  jump at mid-cycle; smoothing only the hybrid's derived leg/shoe reference reduces output from
  43.4° to 14.4°/frame. Do not mistake this for improving the underlying source clip.
- `--lab-check`, `--moving-check`, `--reference-check`, `--profile-check`, `--stair-check`,
  `--pose-match-check`, `--flat-mesh-check`, `--toe-check`, and `--infinite-check` all pass.
  Profile worst joint rotation is 7.2–18.1°/frame across six modes; upper-body pose difference
  versus source is below 1.1°. Stair traversal reaches 0.72 m up/down, with planted ankle error
  printed as 0.000 m and worst joint step 8.8° up / 15.1° down in the 240-frame checks.
  `scripts/check.sh` passed. The scene was not opened interactively after the change.
  `--infinite-check` verifies Original and all four flat reference modes run beyond 15 cycles at
  their extracted stride, Sprint exceeds twice Walk's speed at native cadence, moving mode survives
  gait selection, and the floor/reference follow. It also holds panel size constant while numeric
  readouts change; before reserving label height, this check caught a 52 px height snap.

## Flat full-pose result

The user observed the procedural UAL walk's toe cutting through the flat floor, then reported
remaining leg/foot pose differences and floating feet. The original independent procedural stride
was the cause: even after matching UAL's shoe rotation and raising the ankle, the lowest shoe mesh
point was at least 0.093 m above the plane for 10% of frames. That is a gait-phase mismatch, not
just a clearance setting. The raw UAL source itself penetrates the lab plane by up to 0.047 m.

The same approach now covers UAL walk, MotusMan aim-walk, UAL sprint, and UAL crouch-walk: copy
**all 73 source bone poses** and shift only Hips by a phase-sampled, rate-limited shoe-mesh
clearance amount. No separate leg solve or planted-ankle target runs in those modes. The
120-frame `--pose-match-check` covers all 73 bones in both in-place and moving paths. UAL walk's
maximum rotation difference is 0.069°; the other flat modes remain under 1.8° (sampling/phase
alignment) with nontechnical joint positions within 0.007 m relative to Hips. The technical Root
bone intentionally remains at ground control. `--flat-mesh-check` skins 1209 foot vertices per
frame: walk, aim-walk, and crouch have a sole within 0.03 m of the plane in all 120 frames; sprint
has 64–66/120 contact frames and retains its authored airborne phase (up to 0.229 m). No flat
mode penetrates the floor; minimum clearance is 0.006 m. The shared clearance envelope bounds a
single sharp sprint sole dip so the added Hips lift does not jump in one sample. `--toe-check` is
the narrower UAL walk toe/rotation regression.

The moving path still translates an **in-place source clip** using foot-derived speed; this full-pose
match does not prove absence of horizontal foot slide. The new flat-mode changes are uncommitted
and await the user's visual review.

## Why stairs are different

`--stair-source-report` evaluates the raw source's skinned shoe against each real-height tread
during the scripted path. On the current 0.18 m rise / 0.35 m tread staircase, the untouched
source stair-up pose enters a higher tread by as much as **0.313 m**; stair-down has up to 0.107 m
penetration and 0.418 m floating, with near-contact in only 6/171 and 11/134 active frames.
Copying those poses exactly would therefore worsen the stair scene. A 0.23 m tread with the
clip's authored 0.467 m/cycle travel reduced up penetration to 0.148 m but worsened down to
0.208 m; that trial was reverted. The missing work is a phase/trajectory/terrain alignment for
each stair clip, likely followed by constrained foot correction. It cannot be achieved safely by
the flat modes' one-number pelvis lift.

An offline animation-to-gait converter is plausible: extract normalized pose curves, feet's
contact intervals/trajectories, pelvis/root path, and terrain metadata, then fit editable gait
profiles. This repo already has source sampling and per-frame mesh/joint measurements. Such a tool
would automate extraction, **not** infer correct contact timing on an unrelated staircase from a
single clip; those semantics need validation and sometimes manual labeling/tuning.

## Pending live feedback / next work

1. User judges the four flat modes' contact, horizontal slide, pelvis bob, and loop seam. Flat
   mesh checks prove sampled clearance, not natural-looking motion or planted feet.
2. Design a terrain/phase-matched stair path or a separate stair profile extraction before
   attempting exact source-pose matching on stairs; keep current IK stairs as experimental.
3. If any mode looks wrong, inspect the bounded metrics around its frame, then fix that mode and
   add a targeted visual/contact regression. Avoid accepting or committing solely on numeric pass.
4. Add mesh-versus-tread clearance and real colliders, heel/toe roll, turning, and editable gait
   profiles only after the current live verdict. The hybrid is not ready for gameplay integration.

## Constraint

The existing Foot IK worktree is dirty and belongs to another agent. Stage/commit only this task's
files. Do not commit this new animation/visual work until the user tests and confirms it live, per
`AGENTS.md`.
