# 044 - Planet performance, round 2

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Update (2026-10-18): the loading starvation is fixed (12 tiles queued per 0.3 s; now all while the player waits, 48 otherwise) and the tile build is mostly native; plants are off by default so the tree numbers below are unchanged. `PLANET_TIMING=1` prints the laps.
Read `docs/planet_lessons.md` first (how to measure, the traps).

## Goal

Keep the ground frame well inside budget on a weaker GPU than ours, and keep streaming smooth. Round 1
(documented in `docs/planet_lessons.md`) took the ground from 55 to ~155 fps (4,900 to 1,590 draw calls,
39.6 M to 8.7 M primitives) and a 6 km altitude frame from 28 to 463 fps. This task takes what is left.

## Where we are (measured in the lab, our GPU, 1080p)

- Of a ~6.8 ms ground frame, trees are ~3.8 ms (full trees < 100 m ~1.3 ms, light trees 100-220 m ~1 ms),
  shadows ~1 ms, ground tiles and water are cheap, grass ~0.2 ms.
- Ranges now: `TREE_FULL` 100 m, `TREE_LIGHT` 220 m, `SMALL_VISIBLE` 220 m, `GRASS_VISIBLE` 110 m
  (`PlanetScatter`); full-detail plants only on tiles within 256 m (`PlanetSurface._plants`).
- Draw calls left ~1,590: ground tiles (~350), near trees (full and light multimeshes per species and
  variant per tile), plants, the merged far trees (one per tile).
- Streaming: the 24 km fly check gives 4-38 slow frames (> 33 ms) per run, worst ~60-100 ms; the cause
  we found was mesh uploads of new species and variants (sharing the light mesh between two variants cut
  it from 195). A warm-up thread did not help (tried and removed).

## Plan

1. **Find the first-use cost.** Count meshes created and uploaded per second during the fly check (a
   counter in `SpeciesRegistry._keep`, printed with `--fps`); see which of lod 0 / light / far / plants
   it is. Decide on that, not on guesses.
2. **Shadows.** Try: shadow distance 120 m instead of 220 m, two cascades instead of four, no shadows
   from plants other than trees, and a shadow-only simpler mesh for trees. Measure each with
   `--no-shadow` as the floor.
3. **Merge more.** Merge the far/light tiers per tile where no per-instance wind is needed (rocks, cover);
   try one multimesh per species per *group of tiles*; check what merged meshes cost in memory.
4. **Tile adoption.** Spread `add_child` of a tile's plants over frames (it is 2 plants per frame now);
   build the multimeshes' buffers fully on the worker thread; measure the main-thread time of `_process`
   in `PlanetSurface` with `Time.get_ticks_usec`.
5. **A third tree level** only if 1-4 are not enough: a billboard or a two-quad tree from 220 to ~600 m
   instead of the far mesh, to cut the primitives at the edge of the forest.
6. **Occlusion.** Godot's occlusion culling needs baked occluders; try `OccluderInstance3D` on hills only
   if the ground view is still heavy (probably not worth it).

## Done when

- The budget numbers (see [046](046_performance_budget_and_checks.md)) hold with margin on the lab at the
  spawn, in a dense forest and at 700 m, 2.5 km, 6 km.
- Three fly-check runs have a median of <= 10 slow frames and a worst frame <= 60 ms.
- `docs/planet_lessons.md` section 2 and 3 are updated with the new numbers and what did not work.

## Risks and open questions

- Our GPU is fast: a card with a quarter of its speed is the real target. Ask the user for a weaker machine
  or lower `render_scale` to emulate it.
- Visibility ranges are measured from the node, so large tiles switch at once (a visible pop); a
  fade (`visibility_range_fade_mode`) costs dither and a second draw during the fade. Test the look.
- Shorter shadow range changes the look of forest floors; compare screenshots.
