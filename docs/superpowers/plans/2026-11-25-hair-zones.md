# Hair Zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seven named scalp zones, each able to override the hair shape settings and a hair amount, edited from the Hair tab, with soft borders, a zone tint, and saved custom styles.

**Architecture:**
- A new native module (`hair_zones.h/.cpp`) classifies a scalp point into zones from the head landmarks `build_arrays` already computes. It also blends a per-lock settings struct (`HairLook`).
- Inside the lock loop, `build_arrays` reads the lock's look and shadows the build-wide constants of the same names, so the existing shaping code reads per-lock values unchanged.
- The lab stores zone overrides as `{zone: {key: value}}`, passes them to the builder as `params["zones"]`, and tints the chosen zone through a shader uniform.

**Tech Stack:** C++ GDExtension (`native/planet_crust`), GDScript (Godot 4.7.2 stock), the hair shader.

**Spec:** `docs/superpowers/specs/2026-11-25-hair-zones-design.md`

## Global Constraints

- **Zone keys, in this order (index 0-6):**
  - `front`
  - `top`
  - `crown`
  - `left_side`
  - `right_side`
  - `back`
  - `nape`

  The character faces +Z, so its LEFT side is +X.
- **Per-zone keys:** `length`, `volume`, `curl`, `wave`, `clumping`, `fringe`, `sweep`, `hug`, `quiff`, `swept`, `spike`, `gravity`, `messy`, `gaps`, `wisps`, `tousle`, `amount`. `amount` is zone-only; the whole head is 1.
- **Edges** blend over about 1.5 cm.
- **No zones means no change.** With `params["zones"]` absent or empty, the build's vertices are identical to today's, and no dice draw is added or moved.
- **Simulation limits:** at most 16 guide points (`HairSim::MAX_POINTS`), and at most 4,194,240 vertices per surface.
- **Hair colour:** never changed by a hairstyle or a zone.
- **Build and checks:**
  - Build: `timeout 590 bash scripts/build_native.sh`.
  - Checks: `bash scripts/humans_check.sh --render`, which must print 4 PASS lines.
  - Run one game instance at a time.
  - Windowed runs use override.cfg `no_focus` on screen 1.
- **Commits:**
  - Never commit `project.godot`, `bash.exe.stackdump` or `addons/tressfx/bin/~libtressfx*`.
  - Commit only when the user asks: the commit steps below are local checkpoints, to be run only if the user has said to commit.

## Review Focus

1. **A zone with amount 0 next to a long zone.** Expected: no bare scalp layer showing as a hard patch and no stray hairs; the cap fade follows the amount. Test in Task 2: the cap alpha over the zone is below 0.1.
2. **Per-zone curl or wave when the whole head has none.** Expected: the guide points (`steps`) and the drawn points (`render_steps`) come from the largest value over the zones, so a zone's curl is not drawn with 9 points. Test in Task 2: `hair_render_steps` is greater than `hair_guide_steps` when only one zone has wave.
3. **Left and right swapped.** Expected: "Left side" is the character's left (+X). Test in Task 1.
4. **Picking a hairstyle after editing zones.** Expected: the zone overrides are cleared and the sliders show the style's whole-head values. Test in Task 3 (lab capture).
5. **Saved style with a zone key the current build does not know.** Expected: it loads, unknown keys are ignored, and nothing crashes. Test in Task 4.

---

### Task 1: Zone classification, per-guide zone output, zone in CUSTOM0.z

**Files:**
- Create: `native/planet_crust/src/hair_zones.h`, `native/planet_crust/src/hair_zones.cpp`
- Modify: `native/planet_crust/src/human_hair_native.cpp`:
  - after the landmarks (about lines 484-512), build a `HairZoneFrame`;
  - `add_vertex` (about line 608): store each vertex's zone;
  - the CUSTOM0 fill (about line 2060): `.z` = zone index + 1;
  - the guide output: `built["guide_zones"]` and meta `hair_guide_zones`.
- Test: `tests/manual/humans/human_hair_check.gd`, a new function `_check_zones(gender, body, params)` called from `_check_body`.

**Interfaces:**
- Produces, in `hair_zones.h`:
  - `enum HairZone { ZONE_FRONT, ZONE_TOP, ZONE_CROWN, ZONE_LEFT, ZONE_RIGHT, ZONE_BACK, ZONE_NAPE, ZONE_COUNT };`
  - `extern const char *const HAIR_ZONE_KEYS[ZONE_COUNT];` holds the key strings of Global Constraints.
  - `struct HairZoneFrame { Vector3 crown; double centre_z, front_scale, eye_y, top_y; };`
  - `int hair_zone_at(const HairZoneFrame &f, const Vector3 &p);` is the hard class at a point.
  - `std::array<float, ZONE_COUNT> hair_zone_weights(const HairZoneFrame &f, const Vector3 &p);` gives soft weights that sum to 1.
  - `int hair_zone_dominant(const std::array<float, ZONE_COUNT> &w);`
- Produces, in GDScript: mesh meta `hair_guide_zones` (`PackedByteArray`, one dominant zone index per guide, in guide order). CUSTOM0.z per vertex = dominant zone of its root + 1 (0 for beard vertices). Cap vertices use their own position.

- [ ] **Step 1: Write the failing test `_check_zones`.**
  - Build `params` with `{"length": 0.15, "strands": 8}`.
  - Read `hair_guides`, `hair_guide_steps` and `hair_guide_zones`.
  - Assert:
    - `hair_guide_zones.size() == hair_guide_count`;
    - every zone index 0..6 occurs at least 20 times;
    - every guide in zone 3 (left_side) has root x > 0.02, and every guide in zone 4 (right_side) has root x < -0.02;
    - the mean root z of zone 0 (front) > the mean root z of zone 1 (top) > the mean root z of zone 5 (back);
    - the mean root y of zone 6 (nape) < the mean root y of zone 5 (back).
  - Message prefix `"%s: zones: "`.
- [ ] **Step 2: Run** `bash scripts/humans_check.sh`. Expected: `HUMAN_HAIR_CHECK FAIL`, with "zones" lines because the meta is missing.
- [ ] **Step 3: Implement `hair_zone_at`** with these rules, in order. Use `t = clamp((p.y - (eye_y + 0.03)) / max(top_y - eye_y - 0.03, 0.02), 0, 1)`, `fz = (p.z - centre_z) / front_scale` and `cd = hypot(p.x - crown.x, p.z - crown.z)`.
  1. Crown: `cd < 0.045 && t > 0.5`.
  2. Front: `fz > 0.5 && |p.x| < 0.055`.
  3. Top: `t >= 0.62`.
  4. If `fz < -0.35`: Nape when `t < 0.3`, else Back.
  5. Otherwise Left when `p.x >= 0`, else Right.
- [ ] **Step 4: Implement `hair_zone_weights`.** It is the hard class sampled at p and at p ± 0.0075 and ± 0.015 along x, y and z (13 samples, the centre counted twice). Each weight is that zone's share of the samples.
- [ ] **Step 5: Wire it into `build_arrays`.**
  - Build the frame after line 509.
  - In the lock loop, compute the root's weights once, right after `root` (line 753), as `lock_zone_w`.
  - Keep the dominant zone in a variable that `add_vertex` reads into a new `out_zone` vector; cap vertices use `hair_zone_at` of their position.
  - Push the dominant zone per guide where `current_guide = guide_count++`.
  - Add the source files to the native build if `SConstruct` lists sources explicitly.
- [ ] **Step 6: Build and run** `bash scripts/humans_check.sh`. Expected: 3 PASS lines, and the hair vertex checks still pass (positions unchanged).
- [ ] **Step 7: Commit** (only if asked): `native/planet_crust/src/hair_zones.*`, `human_hair_native.cpp`, `human_hair_check.gd`, with the message "Hair zones: classify the scalp into 7 zones (per-guide zone meta, CUSTOM0.z)".

### Task 2: Per-lock settings from zone overrides, hair amount, cap fade, points from the zone maxima

**Files:**
- Modify: `native/planet_crust/src/hair_zones.h/.cpp`.
- Modify: `native/planet_crust/src/human_hair_native.cpp`:
  - the parameter block (about lines 403-480);
  - `steps` and `render_target` (about lines 651-662);
  - the lock loop just after `normal` (line 754);
  - the cap fade (line 631).
- Test: `tests/manual/humans/human_hair_check.gd`, in `_check_zones`.

**Interfaces:**
- Consumes the zone functions from Task 1.
- Produces:
  - `struct HairLook { double length, volume, curl, wave, clumping, fringe, sweep, hug, quiff, swept, spike, gravity, messy, gaps, wisps, tousle, amount; };`
  - `HairLook hair_look_from(const Dictionary &p_params, const HairLook &p_base);` reads the keys the dictionary has, with the same clamps as today's `param()` reads.
  - `struct HairZoneLooks { bool any; HairLook head; HairLook zone[ZONE_COUNT]; bool set[ZONE_COUNT][17]; };`
  - `HairZoneLooks hair_zone_looks(const Dictionary &p_params);` reads `p_params["zones"]` (`Dictionary` of zone key to `Dictionary`) and ignores unknown zone names and unknown keys.
  - `HairLook hair_look_at(const HairZoneLooks &z, const std::array<float, ZONE_COUNT> &w);` gives `head + Σ w_z · (zone_value − head_value)` over the overridden keys only.
  - Derived values stay where they are computed today, now from the lock's look: `spike` fades with length, and `volume` and `gravity` take `wetness`.

- [ ] **Step 1: Write the failing tests in `_check_zones`.**
  - **(a) No zones means no change.** Build with no `zones` and with `zones = {}`. Assert the surface-0 vertex arrays are equal.
  - **(b) Amount 0 on one side.**
    - Build with `{"zones": {"left_side": {"amount": 0.0}}}`.
    - Assert there is no guide whose root has x > 0.06 with y below the zone frame's top band. Use: no guide with zone 3 and root x > 0.06.
    - Assert the number of zone-4 guides stays at least 80% of the no-zones count.
    - Assert the cap vertices (COLOR.b > 0.9) with x > 0.06 and y below the eye_y + 0.06 line have mean COLOR.a < 0.1.
  - **(c) Length on top only.**
    - Build with `{"length": 0.06, "zones": {"top": {"length": 0.2}}}`.
    - Assert the mean guide length (sum of segment lengths) of zone-1 guides > 2× that of zone-5 guides.
  - **(d) Wave in one zone.**
    - Build with `{"length": 0.25, "strands": 8, "zones": {"back": {"wave": 0.8}}}`.
    - Assert `hair_render_steps > hair_guide_steps`.
  - **(e) Unknown names are ignored.** Build with `{"zones": {"nowhere": {"curl": 1.0}, "top": {"bogus": 3.0}}}`. Assert it builds and equals the no-zones build.
- [ ] **Step 2: Run** `bash scripts/humans_check.sh`. Expected: FAIL on (b), (c) and (d).
- [ ] **Step 3: Implement the four functions.** In `build_arrays`:
  - read `const HairZoneLooks zone_looks = hair_zone_looks(p_params);`;
  - keep the build-wide `length`, `curl` and `wave` used for `steps`, `render_target` and `lock_width` at the maximum of the head and every zone that sets them.
- [ ] **Step 4: Read the lock's look in the lock loop.**
  - After `normal` (line 754), when `zone_looks.any`, read `const HairLook look = hair_look_at(zone_looks, lock_zone_w);`. Then declare shadowing locals with today's names: `length, volume, curl, wave, clumping, fringe, sweep, hug, quiff, swept, spike, gravity, messy, gaps, wisps, tousle`.
  - When `!zone_looks.any`, the shadows equal the build-wide values. Do not branch the code twice.
  - Before relying on the shadows, grep the lambdas defined before the loop that capture any of these names by reference. Pass such values in explicitly, or the lambda will keep reading the head value.
- [ ] **Step 5: Implement the amount.**
  - When `look.amount < 1`, skip the lock if `fract(sin(lock · 91.3458 + 47.21) · 43758.5453) > look.amount`. Use a hash, not `dice`, so other locks' draws do not move.
  - The cap vertex alpha is multiplied by `smoothstep(0.0, 0.6, amount at the vertex)`, from that vertex's zone weights.
- [ ] **Step 6: Build and run** `bash scripts/humans_check.sh --render`. Expected: 4 PASS lines, and `HUMAN_HAIR_CHECK` passes (a)-(e).
- [ ] **Step 7: Commit** (only if asked) with the message "Hair zones: per-zone settings and hair amount (soft borders, cap follows the amount)".

### Task 3: Lab: zone editing on the Hair tab, zone tint, `--hair-zone` flag

**Files:**
- Modify: `tests/manual/humans/human_body_lab.gd`:
  - the Hair tab build (about lines 672-723);
  - `_add_hair_slider` (about line 1045);
  - `_on_hair_preset` and `_on_hair_reset`;
  - the params build (about line 1740);
  - the argument parsing (about line 394).
- Modify: `shaders/human_hair.gdshader`: add the `zone_tint` uniform and a varying from CUSTOM0.z.

**Interfaces:**
- Consumes: `params["zones"]` (Task 2) and CUSTOM0.z (Task 1).
- Produces:
  - lab state `_hair_zones: Dictionary` of zone key (String) to `{StringName: float}`;
  - `_hair_zone_edit: String`, where `""` means the whole head;
  - `const ZONES: Array = [["front", "Front"], ["top", "Top"], ["crown", "Crown"], ["left_side", "Left side"], ["right_side", "Right side"], ["back", "Back"], ["nape", "Nape"]]`;
  - `const ZONE_KEYS: Array[StringName]` holds the per-zone keys;
  - shader `uniform int zone_tint = -1;`.

- [ ] **Step 1: Shader.**
  - Pass `CUSTOM0.z` to a varying `zone_id`.
  - In the fragment, when `zone_tint >= 0 && abs(zone_id - float(zone_tint + 1)) < 0.5`, mix ALBEDO toward `vec3(0.1, 0.75, 1.0)` by 0.45.
- [ ] **Step 2: Panel.**
  - Under the Hairstyle row, add an `OptionButton` labelled "Editing:" with "Whole head" plus the `ZONES` names.
  - Add a **Reset zone** button, disabled while editing the whole head.
  - Add a "Show the zone" CheckBox (on): it sets `zone_tint` to the zone index, or -1.
  - Add a "Hair amount" slider (`amount`, 0..1). It shows only while a zone is chosen.
- [ ] **Step 3: Slider routing.**
  - In the `_add_hair_slider` change handler: when `_hair_zone_edit != ""` and the key is in `ZONE_KEYS`, write to `_hair_zones[_hair_zone_edit][key]`; otherwise write to `_hair_style`.
  - Sliders whose key is not in `ZONE_KEYS` (and the Wet slider) are disabled while a zone is chosen.
  - When the edited zone changes, every zone slider is set without a signal to the zone's value, or else to the head value.
  - The label of a slider that shows a head value ends with `" (head)"`.
- [ ] **Step 4: Params and hairstyles.**
  - The params build adds `params["zones"] = _hair_zones.duplicate(true)` when it is not empty.
  - `_on_hair_preset` and `_on_hair_reset` clear `_hair_zones` and refresh the sliders.
  - Add the flag `--hair-zone=zone:key:value[,zone:key:value...]`, applied after `--hair-preset`.
- [ ] **Step 5: Verify with two captures** (one instance at a time).
  - **Mohawk:** `--gender=Male --face --tab=Hair --nopanel --yaw=160 --hair-preset=Dapper --hair-zone=left_side:amount:0,right_side:amount:0,back:amount:0.15,nape:amount:0.15,top:length:0.16,top:spike:1,front:spike:0.7`. Expected: a ridge of hair on top, near-bare sides and a soft border.
  - **Curly sides:** `--gender=Female --hair-preset="Long waves" --hair-zone=left_side:curl:0.8,right_side:curl:0.8,back:curl:0.8`. Expected: curly lower hair, straight top, and no log errors.
  - **Hairstyle clears the zones:** a panel capture with `--hair-zone=top:curl:1 --switch=Bob`. Expected: the Editing dropdown is on Whole head and the Curl label has no "(head)".
  - Then run `bash scripts/humans_check.sh --render`. Expected: 4 PASS lines.
- [ ] **Step 6: Commit** (only if asked) with the message "Hair lab: per-zone editing (Editing dropdown, Hair amount, Reset zone, zone tint, --hair-zone)".

### Task 4: Saved custom styles

**Files:**
- Create: `tests/manual/humans/hair_style_store.gd` (`class_name HairStyleStore`, static functions only).
- Create: `tests/manual/humans/hair_style_store_check.gd` (a headless check).
- Modify: `scripts/humans_check.sh`, to run the new check (prints `HAIR_STYLE_STORE_CHECK PASS`).
- Modify: `tests/manual/humans/human_body_lab.gd`: the Hairstyle row gets the saved styles, Save as… and Delete.

**Interfaces:**
- Produces:
  - `static func save_style(dir: String, name: String, style: Dictionary, zones: Dictionary, wet: float) -> Error`
  - `static func load_style(dir: String, name: String) -> Dictionary` returns `{"style": Dictionary, "zones": Dictionary, "wet": float}`, or `{}` when missing. Keys arrive as StringName for `style` and inside the `zones` entries. Unknown keys are kept but ignored by the builder (Task 2).
  - `static func list_styles(dir: String) -> PackedStringArray`, sorted by name.
  - `static func delete_style(dir: String, name: String) -> Error`
  - The file format is JSON, `<dir>/<name>.json`, with `{"version": 1, "style": {...}, "zones": {...}, "wet": x}`. The name is sanitised to letters, digits, space, `-` and `_`.
  - Lab `_styles_dir: String = "user://hair_styles"`, overridden by `--styles-dir=` (tests pass a temp dir; tests must not write the user's dir).

- [ ] **Step 1: Write the failing check.**
  - Use the temp dir `user://hair_style_store_check_tmp`, wiped first.
  - Save "My mohawk" with `style = {&"length": 0.07, &"spike": 0.5}`, `zones = {"left_side": {&"amount": 0.0}}` and `wet 0.2`.
  - Assert:
    - `list_styles == ["My mohawk"]`;
    - the loaded values are equal and their keys are StringName;
    - after `delete_style` the list is empty;
    - a hand-written file with `"zones": {"top": {"made_up": 2}}` loads without error.
  - Print `HAIR_STYLE_STORE_CHECK PASS/FAIL` and wipe the dir at the end.
- [ ] **Step 2: Run** `bash scripts/humans_check.sh`. Expected: FAIL, because the store is missing.
- [ ] **Step 3: Implement `HairStyleStore`** and add the check to `humans_check.sh`.
- [ ] **Step 4: Lab.**
  - The Hairstyle dropdown lists the built-in styles, then a separator, then the saved names (`list_styles`).
  - Picking a saved style loads its style, zones and wet value (never colour), rebuilds, and shows it as the current style.
  - A LineEdit and a **Save as…** button save the current whole-head values, zones and wet value under the typed name, then select it.
  - A **Delete** button is enabled only for a saved style.
- [ ] **Step 5: Verify.**
  - Run the lab with `--styles-dir=user://hair_lab_tmp --hair-preset=Bob --hair-zone=top:curl:0.8`, plus a one-off flag `--save-style=Test` that saves and quits.
  - Run again with `--styles-dir=user://hair_lab_tmp --hair-preset=Test` (a saved name is accepted by `--hair-preset`). Expected: the capture shows curly top and the Editing state holds a `top` override.
  - Delete the temp dir afterwards.
  - Run `bash scripts/humans_check.sh --render`. Expected: 5 PASS lines.
- [ ] **Step 6: Notes and commit.**
  - Append a "HAIR ZONES (2026-11-25)" note to `AGENT_TASKS/102_parametric_humans.md`: the zones, keys, flags, files and what is left (painting, brushes, presets as zone styles).
  - Commit only if asked, with the message "Hair lab: save, load and delete custom hairstyles (zones included)".
