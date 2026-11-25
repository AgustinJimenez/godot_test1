# Hair zones: per-zone hairstyle settings (approach A)

Date: 2026-11-25. Task 102 (parametric humans). Lab: `tests/manual/humans/human_body_lab.tscn`. Builder: `native/planet_crust/src/human_hair_native.cpp`.

## Intent

A user should be able to make any hairstyle in detail, not just pick one from the list. The hairstyles stay as quick starting points. Detail comes from splitting the scalp into named zones, each with its own settings. Examples the user gave: a mohawk, and curly lower sides with straight hair on top.

Today every Hair-tab setting applies to the whole head. A few sliders fake regions in code: Fringe, Sides and back shorter, Longer behind, Fringe strips, Quiff and Tousle.

## Approaches considered

- **A. Fixed named zones, each with the full slider set and a hair amount (chosen by the user).** Easiest to use and quickest to build. Limit: a shape is only as fine as the zones, so a mohawk is as wide as the Top zone.
- **B. Painted layers.** Brush any patch on the head, and each patch overrides the settings you touch. Any shape is possible, but it needs 3D painting and a layer list, so it is the most work.
- **C. Layers whose area is a zone or painted.** B, but a layer can start from a zone. This was recommended. A was picked to try first. A's zone lookup and per-lock settings are what B and C would build on, so A is not wasted if they come later.

## Goals

1. **Zones on the scalp.**
   - The zones: **Front** (fringe and hairline), **Top**, **Crown**, **Left side**, **Right side**, **Back**, **Nape**.
   - Sides are separate so asymmetric styles (one side shaved) are possible.
   - Sideburns belong to the sides.
2. **Per-zone settings.** Each zone can override:
   - every shape setting: Length, Volume, Curl, Wave, Clumping, Fringe (falls forward), Combed back, Hugs the head, Quiff, Swept, Spikes, Fall, Messy, Gaps, Wisps, Tousle;
   - **Hair amount** (0 = bald zone, 1 = normal density).

   A setting a zone does not override uses the whole-head value.
3. **Soft edges.** Neighbouring zones blend over about 1.5 cm, so there is no hard line of changed hair. A shaved side next to a long top keeps a short transition, as a real fade does.
4. **Panel.**
   - At the top of the Hair tab, under Hairstyle, an **"Editing: Whole head / Front / Top / ..."** dropdown.
   - The sliders below edit the chosen zone.
   - A slider the zone has not changed shows the inherited whole-head value, marked as inherited. Moving the slider makes it the zone's own.
   - A **"Reset zone"** button clears the zone's overrides.
5. **Show the zone.** While a zone is chosen, the scalp area it covers is tinted, using the existing scalp debug overlay idea. Turn the tint off with a checkbox.
6. **Hairstyles keep working.** Picking a hairstyle sets the whole-head values and clears all zone overrides. It never changes hair colour.
7. **Save and load custom styles.**
   - "Save as..." stores the whole-head values plus the zone overrides as a named style in `user://hair_styles/`.
   - Saved styles appear in the Hairstyle dropdown after the built-in ones.
   - The ability to delete saved styles is in scope.

## Non-goals (this round)

- Painting or brushing zones, and strand brushes (comb, cut, add, delete). That is approach B or C, later.
- Rewriting the built-in hairstyles as zone styles. They stay whole-head styles, and their fixed-region sliders keep working.
- Removing the old fixed-region sliders (Fringe strips, Sides and back shorter, Longer behind). They stay until zones have proven they cover the same looks.
- Per-zone colour (streaks or dyed tips). Colour stays whole-head.
- Beard changes. The beard has its own region system.

## Anti-goals (a failure even if it works)

- Visible seams or steps of hair at zone borders.
- A zone with amount 0 that leaves stray hairs or a scalp-coloured layer showing as a patch. The scalp layer must follow the amount.
- Slower rebuilds while dragging a slider, or a changed hair count, when no zone is overridden. The whole-head path must cost the same as today.
- Hair that the simulation drops, from too many points or vertices.

## Constraints and facts about the current code

- The builder grows each lock from one root on the scalp. Most settings are read as `const double` near the top of `build_arrays` (about lines 400-480) and used inside the lock loop. Per-zone settings mean the lock loop must read a per-lock value: the whole-head value blended with zone overrides by the root's zone weights.
- **Landmarks to define zones from** (already computed): `crown`, `centre_z`, `z_front`, `z_back`, `top_y`, `eye_y`, `head_centre`, the `hairline()` function, and the ear positions used by the beard and hairline code.
- **Guide points** (`steps`) are chosen once for the whole build, from length and curl. With zones, use the largest length and curl over the zones in use. The simulation still holds at most 16 points per guide.
- **Drawn points** (`render_steps`, for waves) are also whole-build. Use the largest wave over the zones in use.
- Some steps look at neighbours, not only the root: clumping, depth shade, the coverage pass and the crown whorl. They must keep working when lengths differ by zone.
- **Hair amount** acts where roots are accepted (follicle placement), not by hiding hairs later. That keeps hair LOD (`lock_share`) and the hair-count target honest. The lab's hair-count retry already learns from the real count.
- **Parameter passing:** the lab passes a Dictionary of params to `HumanHair.build_arrays` on a worker thread. Zone overrides travel in it as `zones: {zone_name: {param: value}}`. Each zone has only the keys it overrides.
- Lab conventions:
  - Runs by Play Scene with no flags, so defaults must be right.
  - Tests must not save user settings.
  - Add a test flag `--hair-zone=zone:key:value,...` for captures and checks.
- Checks: `bash scripts/humans_check.sh [--render]`. `human_hair_check.gd` gains zone tests.

## Decided (by the user)

- Approach A first.
- Users must be able to customise in every detail. Hairstyles are quick starting points.

## My calls (correct me)

- The zone list in goal 1, with sides split left and right.
- Edges blend over about 1.5 cm.
- Inherited values show in the sliders. "Reset zone" clears the overrides.
- Saving custom styles is in this round. Without it, detailed editing is lost on the next run.
- Picking a built-in hairstyle clears zone overrides.

## Left to the builder

- Exact zone shapes from the landmarks: they must cover the scalp with no holes, and Front must follow the hairline.
- How to make the per-lock settings cheap (for example a small struct per lock).
- How inherited values look in the slider label, for example "Curl: 0.40 (head)".
- The save file format (JSON or Godot resource).
- The tests:
  - a zone with amount 0 grows no roots inside it;
  - a zone's curl reaches only hairs rooted in it;
  - the build with no zones is identical to today's;
  - left and right are not swapped.
