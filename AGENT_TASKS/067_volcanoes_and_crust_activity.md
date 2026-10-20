# 067 - Volcanoes and crust activity

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `main` (it was `godot-4.7-upgrade` until 2026-10-20).
Read `docs/planet_lessons.md` first (how to measure, the traps).

Decision (user, 2026-10-17): **eruptions are short events (temporary spikes) and stay safe for now**: no damage,
scenery only.

Idea (user, 2026-10-17): volcanoes, if the crust is active. The planet already has plates, so the cause is
there; the activity of the crust becomes a property of the planet.

## Goal

A planet has a measured level of internal activity and its volcanoes, earthquakes, hot springs and the
land they build all follow from it and from the plates, from far (a smoking cone on the horizon, a plume in
orbit) to near (a lava flow, ash, a crater you can stand in).

## Where we are

- `PlanetTectonics`: plates (14 by default) blended smoothly, 4 nearest plates; relief comes from the plate
  boundaries and noise. There are no boundary types (convergent, divergent, transform) stored as data, no
  volcanoes, no hot spots, no earthquakes, no ash or lava, no crust activity setting.
- The map has a Plates layer. The air is Earth's ([065](065_atmosphere_composition.md) plans to vary it).
- Open ideas in [057](057_terrain_realism.md): fold mountains, a volcanic arc, craters; this task takes the
  volcanic part of it.

## What is true (what makes a volcano)

- **Where:** along **subduction zones** (an arc of stratovolcanoes inland of an ocean trench, or an island
  arc in the ocean), at **rifts and mid-ocean ridges** (basalt, fissures, young seafloor), and over **hot
  spots** (a plume under the plate: a chain of shield volcanoes as the plate moves, Hawaii).
- **Shapes:** a stratovolcano is a steep cone (ash and viscous lava, explosive); a shield is wide and
  gentle (runny basalt lava); a caldera is a collapsed crater; a fissure is a crack that pours lava; a
  cinder cone is small and steep.
- **Activity of the crust** comes from the planet's internal heat: bigger and younger planets are hotter and
  more active; a small old planet is dead (the Moon, Mars); a moon squeezed by a giant planet's tides can be
  extremely active (Io). So the setting follows from the planet's size, age and tidal heating.
- **Eruptions** are events in time: long quiet spells and short violent ones. Lava runs downhill (it follows
  the slope like a river, cools to dark basalt); ash goes up and downwind, falls as a grey layer, blocks the
  sun (a **volcanic winter** cools the planet for a year or two), and sulfur gas makes a haze and acid rain.
- **Land and life:** fresh lava is bare black rock; plants return in steps (lichen, moss, grass, shrubs,
  trees) over a long time; volcanic ash makes very fertile soil; hot springs, geysers and fumaroles live
  near the activity; the sea around vents has its own life.
- **Earthquakes** happen on plate boundaries, strongest at subduction zones.

## Plan

1. **Crust activity as data:** a planet setting `crust_activity` (0 dead, 1 Earth-like, 2+ Io-like) derived
   from the radius, the age and tidal heating ([054](054_universe_foundation.md), [064](064_stars_and_life.md));
   a start-menu or lab option to set it by hand for now. At 0 nothing in this task appears.
2. **Boundary types:** from the plates' motion (each plate gets a velocity from the seed) classify each
   boundary as convergent (ocean-ocean, ocean-continent, continent-continent), divergent or transform;
   store it as a function, not a table (so tiles stay independent).
3. **Where the volcanoes are:** a deterministic function giving volcano sites along the arcs, rifts and
   hot-spot chains (a spacing and a probability by activity), each with an id, a type and an age (an old
   one is extinct and eroded), as a list per region found from the direction like the plants are.
4. **The shape in the height function:** add the cone, shield or caldera to `PlanetNoise.height` near a
   site (a smooth profile with noise and gullies), so tiles, colliders, the map and the horizon agree; a
   crater floor and rim you can walk on; lava fields as dark flat ground downslope.
5. **Rocks and colours:** basalt, obsidian, pumice, sulfur yellows, red scoria; the ground shader reads
   the volcanic rock type ([066](066_caves_and_underground.md) has the rock map); no plants on fresh flows,
   recovery by age.
6. **Eruptions as a function of the date** (nothing stored, the clock can run backward): each volcano has an
   activity schedule from a hash of its id and the date: dormant, rumbling (steam, small ash, a glow),
   erupting (a plume, a lava flow, ash fall, earthquakes). Time controls must work: jumping a year may skip
   an eruption but must not break the state.
7. **Lava:** a flow built on the height field from the vent downhill (a path like a river), a lava shader
   (an emissive crust with cracks, bright at night, a heat shimmer), cooling by age; lava reaching the sea
   makes steam; a lava lake in a crater on very active worlds. Keep the cost bounded (a few hundred
   metres of near flow only; far flows are painted into the ground colour).
8. **Ash and smoke:** a plume (particles near, a cloud layer's density far: reuse the cloud march with a
   column), ash fall on the ground (a grey tint and a wetness-like global near the volcano), a darkened and
   reddened sun and sky downwind (feed the air's aerosol amount of [065](065_atmosphere_composition.md)),
   volcanic lightning in big plumes.
9. **Climate effect:** a big eruption adds aerosols that cool the planet for months (the seasons model's
   energy balance gets a forcing as a function of the date); sulfur and CO2 outgassing over geological time
   feed the atmosphere's composition at the planet's creation (065).
10. **Hot springs, geysers, fumaroles:** small features near activity: warm water pools (no ice, steam),
    geysers that erupt on a timer from the date, colourful mineral crusts.
11. **Earthquakes** (optional): a rumble and a camera shake by distance to the boundary and the schedule;
    rockfalls on steep slopes (instances that fall); a tsunami is out of scope.
12. **Sea:** volcanic islands and island arcs from the arcs in the sea, seamounts, vents (a dark smoker
    cluster underwater).
13. **Map and lab:** map layers for boundary types, volcano sites and their state, heat flow; lab
    `--volcanoes` listing sites around the player and their schedule; `--date=` to jump the clock.
14. **Checks:** the sites are the same in two runs, and for tiles built in any order; the cone height
    function is continuous across tile seams; walking up a cone with `--walk-check`-style steps passes.

## Done when

- A planet at activity 1 has volcano arcs at its convergent boundaries and some hot spots; one of each shape
  (stratovolcano, shield, caldera) can be climbed and looked into; an eruption with a plume, a lava flow
  and ash fall plays out over the schedule; a dead planet has none; the map shows them.
- Cost: the near effects stay inside the 044/046 budget; the far cone adds nothing to the horizon cost.

## Risks and open questions

- The height function is shared by tiles, colliders, plants and the map: a volcano's cone must be a smooth
  function with a bounded range so tiles far from it do not pay for it (a spatial index of sites).
- Eruptions are the first *dynamic* terrain: lava can change the ground a player stands on. Keep the ground
  shape fixed and make the lava a surface layer (a decal and a shader) first, not a height change.
- Particles in large numbers are expensive; far plumes must be cloud-like volumes.
- **Decided (user, 2026-10-17):** eruptions are safe for now (scenery); revisit with the player work (063).
