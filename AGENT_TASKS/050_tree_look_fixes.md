# 050 - Tree and plant look fixes

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Fix the visible flaws of generated plants and finish the open ideas of the tree builder.

## Where we are

- One `TreeGrower` builds every plant except mushrooms from `TreeArchetypes` ([042](042_unified_tree_builder.md)),
  120 species and 6 looks per tree on a planet; lod 1 (lighter) and a far mesh exist.
- Open ideas in 042: bark texture and moss, an "ancient oak vs the Angel Oak" check, more broadleaf species
  per world. Open idea in 043: big flat green "door" leaf shapes on one tree species. In the screenshots
  there is a large dark leaf-like quad near the camera on some trees.
- The light mesh and the far mesh are shared by two variants per species (a mismatch of shape with the full
  tree at the 100 m switch).

## Plan

1. **Door leaves.** Find the species and genome that produce the giant flat leaves (log a genome for any
   leaf larger than a limit in `species_check`), clamp leaf size by the tree's height, and add a check that
   fails on an oversized leaf.
2. **Level switches.** Make the light and far versions match the full tree's silhouette and colour
   (same genome, simpler parameters; take the far tree's colour from the full tree's mean colour) so the
   pop at 100 m and 220 m is invisible; try a short dither fade only if needed.
3. **Bark and moss.** A bark texture by species (a small tiling normal or a procedural pattern in the
   plant shader, which has `planks` and speckle already), moss on the north or wet side by the rule of the
   biome.
4. **More variety.** More archetypes (see [059](059_plant_variety.md)); more broadleaf shapes per planet;
   dead and fallen trees, stumps, logs.
5. **Wind.** Check the sway on the merged far trees (the sway weight is kept in vertex alpha, the amplitude
   uses the node's transform, not each tree's) and on tall trees.
6. **Collisions.** Trunk colliders on the light trees are not needed; check that only near trees have one.

## Done when

- `species_check` reports no oversized leaf over 100 seeds; screenshots of the 10 largest trees look right.
- A walk past a 100 m and a 220 m switch shows no obvious pop.

## Risks and open questions

- More variants cost mesh uploads and memory (see 044); keep the count per species bounded.
