# Garment recipes, plan 1 of 5: the recipe builder and outfits (shirt and trousers moved onto it)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any garment is a recipe file and any outfit a list of recipes; one builder makes them and both labs load any outfit; the villager shirt and trousers become the first recipes and come out as good as today.

**Architecture:** Pure-Python modules (no `bpy`) hold the recipe and outfit data, the material defaults and the freedom function, so they are unit-tested with the standard library. A Blender script builds an outfit from the inside out with general rules taken from today's `make_clothes.py` (cut, shell placement, hip rule, layer push, smoothing, unfold, rim, masks). A Blender check measures what made the current pair right (layer gap, inward folds, openings) and gates the refactor before and after. In Godot one `ClothSetup` helper configures a solver from a garment's runtime settings, replacing the shirt/trousers special cases in both labs.

**Tech Stack:** Blender 5.3 Python (bpy, bmesh, mathutils), plain Python 3 `unittest`, Godot 4.7.2 GDScript, the vendored `addons/godot_gpu_cloth` solver.

**Spec:** `docs/superpowers/specs/2026-11-26-garment-recipes-design.md`

**The other plans (written when this one is done, in this order):** 2. task 104's contact fix (`AGENT_TASKS/104_cloth_contact_design.md`, agreed "fix first"); 3. the `drape` shape (skirts, long coats), exact contact generalised to legs and torso, and the near / middle / far cloth distances (collision option C); 4. leather and the first new garments (tunic, vest, jerkin); 5. steel.

## Global Constraints

- Nothing per garment in the builder or the labs: no `if garment == "shirt"`; every rule is general or a recipe / material field.
- Coordinates in the builder are Blender's: Z up, front is -Y. Joints come from `<gender>_rig.json` (`joints_of`).
- Vertex colour channels: R belt, G hem band (1 at an edge, 0 one `HEM_WIDTH` in), B cloth freedom (the solver's `cloth_weight_channel` 2), A draw the inside (1) or not (0).
- Output files: `<gender>_<outfit>_<garment>.glb` in `assets/models/humans/` (outfit = the unit of building, spec "Calls made").
- One Godot run at a time, windowed runs with `override.cfg` `[display] window/size/no_focus=true` on `--screen 1`, the stock `E:/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe`; never touch the user's open editor; kill test runs by PID only.
- Never commit `project.godot`, `bash.exe.stackdump`, `locked_*.dll.bak`, tressfx `~...TMP`. Commit only when the user asks.
- Tests must not save the user's settings, styles or characters (`--styles-dir` / `--characters-dir` scratch folders).
- Parity bar for the shirt and trousers (spec "Calls made"): waist overlap 0 (`--cloth-overlap`), calves 0 inside (`--cloth-legs`, wiggle 15 / 0.15 s, 15 / 0.3 s, `--weight=1`, `--weight=-1`), no inward-facing area under the hem beyond the rolled lip (male <= 12 cm2, female <= 8 cm2 by `garment_check.py`), the neckline as now, `bash scripts/humans_check.sh --render` green apart from the elbow motion checks, those within: male f90 <= 14 faces inside, male f150 <= 8 vertices / 10 faces, female f90 and f150 PASS.
- Shell commands are prefixed with `rtk` where the user's CLAUDE.md asks (git).

## Review Focus

1. An outfit whose lower layer is missing or listed out of order (a shirt alone, or the shirt listed before the trousers): the builder must sort by `layer`, build a garment with nothing under it without the push, and never read a stale lower-layer file from disk. Test: Task 4 Step 1 (`test_shirt_alone`).
2. Body slider extremes (height ±1, weight ±1, muscle ±1, both bodies): the baked garments and the layer gap must hold; the current `human_cloth_check.tscn` covers extremes for the old two-piece wiring only. Test: Task 6 Step 1 (the check iterates outfits at the extremes).
3. Switching outfits and genders repeatedly in the body lab while the cloth restarts (the old ownership bugs: freed solvers still referenced). Test: Task 6 Step 1 (switch villager → underwear → villager, gender twice, no script errors).
4. A recipe with a typo or a missing field: the loader must fail loudly with the field name, not build a half garment. Test: Task 1 Step 1 (`test_unknown_field`, `test_missing_field`).
5. Old file names (`male_shirt.glb`) still referenced somewhere after the rename (a check scene, `rebuild_humans.sh`): every reference moves to the outfit names. Test: Task 7 Step 2 (a grep for `_shirt.glb` / `_pants.glb` outside `docs/` and `AGENT_TASKS/` returns nothing).

---

### Task 1: Recipe, material and outfit data

**Files:**
- Create: `tools/blender/garments/__init__.py` (empty), `tools/blender/garments/recipe.py`, `tools/blender/garments/test_recipe.py`
- Create: `assets/models/humans/garments/shirt.json`, `assets/models/humans/garments/trousers.json`, `assets/models/humans/outfits/villager.json`

**Interfaces:**
- Produces: `Material` (dataclass: `name: str`, `simulated: bool`, `freedom_scale: float`, `stiffness: float`, `bend_stiffness: float`, `rim_depth: float`); `MATERIALS: dict[str, Material]` with `linen`, `wool`, `leather` (steel is plan 5); `Recipe` (dataclass, fields exactly the spec table: `name`, `layer: int`, `shape: str` (`shell` only in this plan), `covers: list[str]` from `torso, upper_arm, forearm, thigh, shin`, `top: dict` (`{"at": "neck"}` or `{"at": "waist", "above_hips": float}`), `neckline: dict | None` (`round_ease`, `v_depth`, `v_width`), `bottom: dict | None` (`below_hips: float`), `sleeve_end: float | None`, `leg_end: float | None`, `ease: dict` (`torso`, `limb`, `flare_torso`, `flare_limb` in metres), `openings: dict[str, str]` (`neck`, `waist`, `hem`, `sleeves`, `cuffs` → `open` | `bound`), `material: str`, `belt: bool`, `overrides: dict`); `Outfit` (dataclass: `name: str`, `garments: list[Recipe]` sorted by `layer`, ties keep file order, `colours: dict[str, dict[str, list[float]]]` garment name → gender → RGB, optional); `load_recipe(path: str) -> Recipe`; `load_outfit(path: str, garments_dir: str) -> Outfit`. Errors: `RecipeError(message)` naming the file and the field.
- Values (today's constants, so parity holds): shirt `layer 1`, `top {"at": "neck"}`, `neckline {"round_ease": 0.01, "v_depth": 0.085, "v_width": 0.07}`, `bottom {"below_hips": 0.0}`, `sleeve_end 0.9`, `ease {"torso": 0.016, "limb": 0.019, "flare_torso": 0.012, "flare_limb": 0.0}`, openings neck bound, sleeves open, hem open, `material linen`; trousers `layer 0`, `top {"at": "waist", "above_hips": 0.035}`, `leg_end 0.9`, `ease {"torso": 0.012, "limb": 0.012, "flare_torso": 0.0, "flare_limb": 0.01}`, openings waist bound, cuffs bound, `material wool`, `belt true`. Outfit `villager.json`: `{"name": "villager", "garments": ["trousers", "shirt"], "colours": {"shirt": {"male": [0.72, 0.66, 0.55], "female": [0.62, 0.55, 0.45]}, "trousers": {"male": [0.33, 0.25, 0.18], "female": [0.3, 0.27, 0.23]}}}` (today's `CLOTHES_COLOURS`).

- [ ] **Step 1: Write the failing tests** in `test_recipe.py` (`unittest`): `test_shirt_values` (loads `shirt.json`, asserts every value above), `test_outfit_sorted` (an outfit listing `["shirt", "trousers"]` comes back trousers first), `test_unknown_field` (a temp recipe with `"colour"` raises `RecipeError` whose message contains `"colour"`), `test_missing_field` (no `layer` raises, message contains `"layer"`), `test_bad_region` (`covers: ["wings"]` raises).
- [ ] **Step 2: Run** `python -I tools/blender/garments/test_recipe.py` — Expected: errors, `recipe` module missing.
- [ ] **Step 3: Implement** `recipe.py` (JSON via the standard library; validate names and types) and the three JSON files.
- [ ] **Step 4: Run** the same command — Expected: `OK`, 5 tests.
- [ ] **Step 5: Commit** (only when the user asks; otherwise leave staged work for the end).

### Task 2: The freedom function

**Files:**
- Create: `tools/blender/garments/freedom.py`, `tools/blender/garments/test_freedom.py`

**Interfaces:**
- Consumes: `Recipe`, `Material` (Task 1).
- Produces: `freedom(region: str, along: float, hang: float, opening: str | None, edge_distance: float, over_layer: float, recipe: Recipe, material: Material) -> float` in `[0, 1]`. `region` from `torso, upper_arm, forearm, thigh, shin`; `along` the share along the limb (0 at its root); `hang` 0 at the chest line to 1 at the hem (torso only); `opening` the nearest opening's kind within its band, else `None`; `edge_distance` metres along the cloth to that opening; `over_layer` 0..1 how far the point lies over a lower layer (the 3 cm ramp used today).
- The rules (today's, made general; parity values in the tests): torso within 0.16 m below the neck joint → 0; torso → `0.6 * hang**2`, capped at `0.3` where `over_layer` is 1 (blended by `over_layer`); arms: `smoothstep((along_upper_arm - 0.05) / 0.3)` (the sleeve is free past 35 % of the upper arm); legs: thigh `knee * thigh_share` with `knee 0.3`, shin `knee + (shin - knee) * min(along / 0.6, 1)` with `shin 0.45`; a `bound` opening multiplies by `1 - closed_edge` (`closed_edge = 1 - clamp((edge_distance - 0.01) / 0.04)`); then `* material.freedom_scale` (linen and wool 1.0, leather 0.35) and recipe `overrides["freedom"]` per region if given.

- [ ] **Step 1: Write the failing tests**: `test_shirt_parity` (shirt + linen: neck band 0; `hang 0.5` → 0.15; `hang 1, over_layer 1` → 0.3; upper arm `along 0.05` → 0, `0.35` → 1.0), `test_trousers_parity` (wool: thigh share 1 → 0.3; shin `along 0.6` → 0.45; at a bound cuff `edge_distance 0.01` → 0), `test_leather_scaled` (leather shirt `hang 1` → `0.6 * 0.35`), `test_override` (`overrides {"freedom": {"shin": 0.2}}` → 0.2 on the shin).
- [ ] **Step 2: Run** `python -I tools/blender/garments/test_freedom.py` — Expected: errors, module missing.
- [ ] **Step 3: Implement** `freedom.py`.
- [ ] **Step 4: Run** — Expected: `OK`, 4 tests.
- [ ] **Step 5: Commit** (when asked).

### Task 3: The garment check (baseline on today's files)

**Files:**
- Create: `tools/blender/garment_check.py`
- Modify: `tools/blender/rebuild_humans.sh` (runs the check after building)

**Interfaces:**
- Produces: `blender -b --factory-startup --python tools/blender/garment_check.py -- <folder> <gender> <outfit json>` prints one line per measure and `GARMENT_CHECK PASS` or `GARMENT_CHECK FAIL <reasons>`, exit code 0 / 1. Measures (from this session's probes `probe_gap.py`, `probe_hemfolds.py`, `probe_loops.py`, `probe_neck.py`): for every pair of layers the signed gap of the upper garment's points over the lower one (BVH nearest, along the lower surface's normal) — FAIL if any point < 0.006 m; the inward-facing area of each torso garment's lower 12 cm — FAIL above 12 cm2 (male) / 8 cm2 (female); the open-edge loops after welding UV seams — shirt exactly 4 (neck, hem, 2 sleeves), trousers exactly 3 (waist, 2 cuffs); the neckline edge mean distance to the skin — FAIL above 6 mm. A flag `--files=<old>` reads today's names (`<gender>_shirt.glb`, `<gender>_pants.glb`) so the baseline runs before the rename.

- [ ] **Step 1: Write the check.**
- [ ] **Step 2: Run on today's files**: `blender ... garment_check.py -- assets/models/humans male assets/models/humans/outfits/villager.json --files=old` and the same for `female` — Expected: `GARMENT_CHECK PASS` both (today: gap min >= 6 mm, inward area male 11.2 / female 7.3 cm2, loops 4 and 3). If FAIL, the thresholds are wrong, not the files: fix the measure until today's files pass, then record the printed values in the task file as the baseline.
- [ ] **Step 3: Commit** (when asked).

### Task 4: The outfit builder

**Files:**
- Create: `tools/blender/build_outfit.py` (entry: `blender -b --factory-startup --python tools/blender/build_outfit.py -- <work folder> <rig folder> <outfit json> [--gender=male|female]`), `tools/blender/garments/fit.py` (the bpy/bmesh rules)
- Delete after parity: `tools/blender/make_clothes.py` (Task 7)

**Interfaces:**
- Consumes: Tasks 1-2. Today's helpers move into `fit.py` unchanged in behaviour: `blender_point`, `joints_of` (with `head`), `segment_t`, `bone_labels`, `part_of`, the Taubin smoothing with its floors, the hip rule (`place_dir`, `hips_axis`), the round-neckline cylinder split (`collar_f`, split points kept), the sleeve refinement (`SLEEVE_EDGE_LENGTH 0.012`), the unfold pass, the rolled rim (`rim_depth` from the material), the layer push spread over 6 rings (generalised from `pants_surface`: any finished lower layer of the same outfit), the inside mask (A = 1 except within 0.09 m of each armpit point `(shoulder.x * 0.85, shoulder.y, shoulder.z - 0.07)` on torso points).
- Produces: `build_garment(gender: str, recipe: Recipe, lower: list[BVHTree], j: dict) -> None` (writes the glb) and `build_outfit(gender: str, outfit: Outfit) -> list[str]` (written paths, inside out). Which rules apply follows the recipe only: the neckline when `top.at == "neck"`; the hip rule and the push wherever a lower layer exists; the belt mask when `belt`; cuffs / neck band closing when the opening is `bound` (`CUFF_OFFSET 0.004`, `CUFF_LENGTH 0.06`, `NECK_BAND 0.03`).

- [ ] **Step 1: Write the failing check runs** (in `tools/blender/garments/test_build.sh`): build `villager` for both genders into a scratch folder and run `garment_check.py` on it; `test_shirt_alone`: an outfit `[shirt]` builds without error and its check reports no layer pair.
- [ ] **Step 2: Run** `bash tools/blender/garments/test_build.sh` — Expected: FAIL, `build_outfit.py` missing.
- [ ] **Step 3: Implement** `fit.py` and `build_outfit.py`.
- [ ] **Step 4: Run** — Expected: `GARMENT_CHECK PASS` for male and female villager, the shirt-alone build passes; the printed measures within 10 % of Task 3's baseline.
- [ ] **Step 5: Commit** (when asked).

### Task 5: ClothSetup — solver settings from the garment

**Files:**
- Create: `tests/manual/humans/cloth_setup.gd` (`class_name ClothSetup`)
- Modify: `tests/manual/humans/human_rig_lab.gd` (`_add_cloth`: per-garment loop calls `ClothSetup.configure`, no `piece == _shirt`), `tests/manual/humans/human_body_lab.gd` (`_restart_cloth`: same, no `i == 0`)

**Interfaces:**
- Produces: `static func configure(solver: GPUClothSolver, garment: Dictionary, collider: MeshInstance3D) -> void` where `garment` is `{"name", "layer", "material", "covers"}` read from the recipe JSON at run time (`static func load_outfit(path: String) -> Array[Dictionary]`, sorted by layer). Material → `solver_iterations 4`, `substeps 2`, `stiffness`, `bend_stiffness`, `damping 0.985`, `max_travel_distance 0.04`, `flip_normals true`; collision: capsules at percentile 0.5 x 0.8, `mixamorig_Hips` and `mixamorig_Spine2` shrunk `(0.0, 0.1)`, full shin capsules `(0.85, 1.0)` on `LeftLeg` / `RightLeg` when `covers` has `shin`; exact arm contact (`HumanRig.prepare_cloth_arms` / `skin_cloth_arms`, voxel 1, thickness 0.004, render offset 0.001) when `covers` has `forearm` (a sleeve hangs loose over the arm; plan 3 adds the near / middle / far switch); else render offset 0.004, thickness 0.006. Every garment is a peer of every other (`peer_cloth_solvers`).

- [ ] **Step 1: Write the failing test**: extend `tests/manual/humans/human_cloth_check.gd` with `outfit_solver_settings`: for `villager`, the shirt's solver has exact contact and render offset 0.001, the trousers' has shin overrides and 0.004, both have `flip_normals` and each other as peers.
- [ ] **Step 2: Run** `bash scripts/cloth_check.sh` — Expected: `HUMAN_CLOTH_CHECK FAIL outfit_solver_settings`.
- [ ] **Step 3: Implement** `cloth_setup.gd` and replace the per-garment code in both labs.
- [ ] **Step 4: Run** — Expected: `HUMAN_CLOTH_CHECK PASS`.
- [ ] **Step 5: Commit** (when asked).

### Task 6: Outfits in the labs

**Files:**
- Modify: `tests/manual/humans/human_body_lab.gd` (`CLOTHES_SCENES`, `CLOTHES`, `CLOTHES_COLOURS`, `_load_clothes`, `_shirt_mesh` / `_pants_mesh` / `_shirt_material` / `_pants_material` become arrays per garment; the Clothes dropdown lists `assets/models/humans/outfits/*.json` plus "Underwear"; colours per garment come from the outfit JSON's `colours` (Task 1); `--clothes=<outfit>`), `tests/manual/humans/human_rig_lab.gd` (the same loading; `--clothes=<outfit>`), `tests/manual/humans/cloth_overlap_probe.gd` (`measure` takes the outfit's layers and reports every adjacent pair; `legs` uses every garment covering `shin`)
- Modify: `tests/manual/humans/human_cloth_check.gd`

**Interfaces:**
- Consumes: Task 5's `ClothSetup.load_outfit`, Task 4's file names.

- [ ] **Step 1: Write the failing test** in `human_cloth_check.gd`: `outfit_cycle` — both bodies; for each outfit in the folder and "Underwear": load it, wait for the solvers, assert every simulated garment's solver initialised; switch villager → underwear → villager and gender twice; body extremes height/weight/muscle ±1 with villager: the overlap probe's inside count is 0 at rest; no `SCRIPT ERROR` (the runner already fails on engine errors).
- [ ] **Step 2: Run** `bash scripts/cloth_check.sh` — Expected: FAIL `outfit_cycle`.
- [ ] **Step 3: Implement** the outfit loading in both labs and the probe changes.
- [ ] **Step 4: Run** — Expected: `HUMAN_CLOTH_CHECK PASS`.
- [ ] **Step 5: Commit** (when asked).

### Task 7: Switch over and parity

**Files:**
- Modify: `tools/blender/rebuild_humans.sh` (`build_outfit.py` for every outfit, then `garment_check.py`), `scripts/humans_check.sh` (runs `python -I tools/blender/garments/test_recipe.py` and `test_freedom.py`), `docs/blender_workflow.md` (how to add a garment: a recipe, an outfit line, rebuild), `AGENT_TASKS/103_cloth_simulation.md` (results)
- Delete: `tools/blender/make_clothes.py`, `assets/models/humans/{male,female}_{shirt,pants}.glb` (+ `.import`)

- [ ] **Step 1: Rebuild** `bash tools/blender/rebuild_humans.sh` (clothes stage) and copy the outfit glbs into `assets/models/humans/`; headless `--import`.
- [ ] **Step 2: Check no old names**: `rtk grep -rn "_shirt.glb\|_pants.glb" --include=*.gd --include=*.sh --include=*.py --include=*.tscn .` — Expected: nothing.
- [ ] **Step 3: Parity runs** (one Godot at a time): body lab `--cloth-overlap` with `--wiggle=15,0.3` and `--osc=0.25` → inside 0 at rest, at most 3 during turns; `--cloth-legs` with `--wiggle=15,0.15`, `--weight=1`, `--weight=-1` → inside 0; `bash scripts/humans_check.sh --render` → all PASS except the elbow checks, those within the Global Constraints bar. Record every number in the task file.
- [ ] **Step 4: Visual check**: the turn, the neckline from four sides, under the hem (renders as in task 103), compared with the last committed captures; send the user the sheet.
- [ ] **Step 5: Commit and push** when the user asks.
