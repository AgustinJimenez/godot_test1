# Crotch Drop and Sleeve Taper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two general garment-builder rules: every garment covering both thighs bridges the groin `crotch_drop` below the body, every sleeve tapers to `sleeve_taper` of its room at the wrist.

**Architecture:** Optional recipe fields validated in `recipe.py`; defaults in `fit.py`; the sleeve rule scales the limb offset along the arm, the crotch rule reshapes points in the zone between the thighs before the layer pushes; `garment_check.py` gets one check per rule. Every outfit rebuilt.

**Tech Stack:** Python (Blender 5.3 headless, bmesh), JSON recipes, Godot 4.7.2 labs for renders.

**Spec:** `docs/superpowers/specs/2026-11-27-crotch-and-sleeve-taper-design.md`

## Global Constraints

- `crotch_drop`: metres, >= 0, only for garments covering both "thigh" regions' garment (covers "thigh"); default ~0.035.
- `sleeve_taper`: 0..1, only for garments covering "forearm"; default ~0.7; 1 = a straight tube.
- The existing checks keep passing: `python -I tools/blender/garments/test_recipe.py`, `test_freedom.py`, `bash tools/blender/garments/test_build.sh <folder>` (villager PASS; jerkin's known layer-gap points stay open, not worse), `bash scripts/cloth_check.sh` (only the three known elbow motion checks fail).
- One Godot game at a time; windowed runs with `override.cfg` no_focus, screen 1; no commits unless the user asks.

## Review Focus

1. A garment covering the torso only (shirt, jerkin, mail) must not get a crotch bridge — the rule needs both thighs covered.
2. Layered garments: the shirt's hem hangs over the trousers' bridged crotch — the shirt must still stay outside (the bridge runs before the layer pushes; the per-shape pushes still apply).
3. Body sliders (heavy, muscular): the bridge is in the base shape and carried by the shape deltas; the layer check at the extremes must not get worse.
4. Bound cuffs at the wrist keep closing on the skin (taper applies before the cuff rule).
5. Short sleeves (mail, sleeve_end 0.3): the taper is measured along the whole forearm, so a short sleeve is only a little narrower.

---

### Task 1: Recipe fields

**Files:** Modify `tools/blender/garments/recipe.py` (Recipe dataclass, `_OPTIONAL`, validation), `tools/blender/garments/test_recipe.py`.

**Interfaces:** Produces `Recipe.crotch_drop: float = None`, `Recipe.sleeve_taper: float = None`.

- [ ] Step 1: tests `test_fit_fields`: a recipe with `"crotch_drop": 0.05` (trousers) and `"sleeve_taper": 0.6` (shirt) loads with those values; `crotch_drop` on the shirt (no thigh) fails with RecipeError mentioning `crotch_drop`; `sleeve_taper` 1.5 fails; `crotch_drop` -0.01 fails.
- [ ] Step 2: run `python -I tools/blender/garments/test_recipe.py` — FAIL (unknown field).
- [ ] Step 3: add the fields and validation.
- [ ] Step 4: run — OK.

### Task 2: Sleeve taper

**Files:** Modify `tools/blender/garments/fit.py` (offset for `part[0] == "arm"`), `tools/blender/garment_check.py`.

**Interfaces:** Consumes `Recipe.sleeve_taper`. Constant `SLEEVE_TAPER = 0.7` in fit.py.

- [ ] Step 1: check in garment_check: for a garment covering the forearm, the mean gap to the body over points on the forearm beyond 0.6 of it (or the sleeve's last 40%) is smaller than over the upper arm; prints `GARMENT_CHECK <g> <name> sleeve room upper %.1f mm forearm end %.1f mm`.
- [ ] Step 2: run the check on the current build — FAIL (equal rooms).
- [ ] Step 3: limb offset multiplied by `1 - (1 - taper) * s` with s a smoothstep of the share along the arm (0 at the shoulder: upper arm `part[2] < 0` counts as 0..0.5 by its distance along shoulder→elbow, forearm 0.5..1 by `part[2]`), before the cuff rule.
- [ ] Step 4: rebuild villager, run the check — PASS; build test — villager PASS.

### Task 3: Crotch drop

**Files:** Modify `tools/blender/garments/fit.py` (after the layer pushes' first base pass is NOT the place: before `_push_outside`, after the Taubin smoothing), `tools/blender/garment_check.py`.

**Interfaces:** Consumes `Recipe.crotch_drop`. Constant `CROTCH_DROP = 0.035`.

- [ ] Step 1: check: for a garment covering "thigh", the lowest garment point within 3 cm of the middle plane (|x| < 0.03) between the legs lies at least 0.02 m below the body's lowest point there; prints `GARMENT_CHECK <g> <name> crotch %.1f mm below the body`.
- [ ] Step 2: run on the current build — FAIL (~12 mm).
- [ ] Step 3: zone: garment points with |x| below the inner-thigh distance and z within ~0.12 m above the body's crotch; target: x pulled toward the middle plane by the share they face it, z lowered so the bridge's lowest line is `crotch_drop` below the body's crotch; blended out over a few cm (z upward, |x| outward, y toward the seat and the front). Then the usual layer pushes.
- [ ] Step 4: rebuild all outfits; check PASS; build test as in Global Constraints.

### Task 4: Rebuild, renders, docs

**Files:** Modify `docs/blender_workflow.md` (Garments), `AGENTS.md` (pointer near the parametric-humans paragraph), `AGENT_TASKS/103_cloth_simulation.md`.

- [ ] Step 1: copy every outfit's glbs into `assets/models/humans`, `--import`; run `scripts/humans_check.sh` and `scripts/cloth_check.sh` — expected as in Global Constraints.
- [ ] Step 2: before/after renders of the groin and the elbow on both bodies (body lab), shown to the user.
- [ ] Step 3: docs: the two rules, the recipe fields and defaults, the checks; AGENTS.md: "Clothes: read `docs/blender_workflow.md` Garments and the designs in `docs/superpowers/specs/` (garment recipes; crotch drop and sleeve taper) before changing a garment or the builder."
