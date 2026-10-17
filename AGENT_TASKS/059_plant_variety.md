# 059 - Plant variety

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

More kinds of plants and more life in the undergrowth, without breaking the budget.

## Where we are

- `TreeGrower` builds every plant from archetypes: broadleaf and conifer trees, grass kinds (lawn, meadow,
  reed, pampas, tussock), shrubs; mushrooms have their own builder; a planet makes 120 species with 6 looks
  per tree (`SpeciesGenerator`), plants chosen by climate fitness, patch noise and layer
  (canopy, understory, grass, meadow, cover).
- Autumn colours by the `autumn` global; wind sway by `wind_strength`; snow on leaves by `snow_cover`.
- Palms were planned in 042 ("PALM at step 3"); not all kinds exist.

## Plan

1. **New forms:** palms, cacti and succulents, tree ferns, bamboo, vines on trunks, giant reeds, kelp (see
   [049](049_water_and_coasts.md)), lichens and moss on rocks, flowers by season, berries and fruit.
2. **Seasons.** Leaves fall in autumn (instances scaled to zero by a global, or bare variants), buds in
   spring, flowers in a short window; the same rule for the whole forest, per species timing.
3. **Dead things.** Dead standing trees, fallen logs, stumps, leaf litter and needle beds on the ground
   shader (a colour and a roughness), mushrooms on logs.
4. **Ecology rules.** Plants by soil depth and moisture, succession around a lake, treeline by height and
   latitude, krummholz near the treeline (short, bent trees), fire scars (optional).
5. **Budget.** Each new form needs a far version and a light version, and a cap on the number of variants
   (see 044: mesh uploads); share the light and far meshes by species.
6. **Check.** `species_check` extended to the new forms (leaf size, triangle count by lod, no NaN).

## Done when

- Five new forms in a lab screenshot; a forest in autumn and in spring look different; the frame budget
  holds with the new species in the mix.

## Risks and open questions

- More species means more first-use mesh uploads; keep `variant % 2` sharing and measure with the hitch
  test (3 runs).
