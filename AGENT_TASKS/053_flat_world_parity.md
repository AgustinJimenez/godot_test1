# 053 - Retire the flat world (when the universe replaces it)

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

Decision (user, 2026-10-17): the flat world may be deprecated once the universe exists. Until then it stays
as it is, and nothing is ported to it.

## Goal

Retire the flat streaming world and its levels without breaking what the planet shares with it.

## Where we are

- The flat world: `levels/procedural_world.gd` (uses Sky3D), `ProceduralWorldMenu` (the "World" page),
  `systems/world_gen/` (chunks, `WorldAtmosphere`, `WorldWeather`, `WorldWind`, `WorldClouds`...).
- **Shared with the planet, must stay:** the plants (`systems/world_gen/flora/`, `FloraMeshes`,
  `SpeciesRegistry`), `WorldWeather` (the planet drives its state), `WorldWind` (shader globals),
  `WorldAtmosphere` (`PlanetAtmosphere` extends it), `MeshBuilder`, `WaterSplash` and the flora shader.
  `docs/tree_builder.md` and `species_check` use them.
- The planet's ground shader has puddles, ripples and uneven snow; the flat one has the old even wetness.

## Plan (do this when [054](054_universe_foundation.md) works and the user confirms)

1. List what only the flat world uses (`WorldClouds`, Sky3D plumbing, `ProceduralWorldMenu`, the flat
   ground shader, chunk streaming) and what the planet imports from `systems/world_gen/` (use codegraph
   `codegraph_impact` before deleting anything).
2. Move the shared parts to a neutral folder (`systems/world_common/` or `systems/flora/`) in a pure
   rename commit, so the planet's imports change and nothing else does; checks pass after it.
3. Remove the flat level, its menu, its shaders (`ground_lowpoly`, `river_lowpoly`, `water_lowpoly`,
   `world_sky`) and the Sky3D addon only if nothing else uses it; keep `world_lab` only if it still tests
   something shared (else move its checks to the planet lab).
4. Update `AGENTS.md` ("Procedural world, plants and planet"), the docs and the checks list.
5. Keep a git tag (`flat-world-last`) before the removal so it can be restored.

## Done when

- Planet checks, `species_check` and lint pass; no reference to a removed file; the tag exists.

## Risks and open questions

- Sky3D may be used by other scenes in the project: check before removing the addon.
- Do not delete anything while the user still plays the flat level for comparisons: confirm first.
