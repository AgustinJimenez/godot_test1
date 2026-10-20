# 066 - Caves and the underground

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `main` (it was `godot-4.7-upgrade` until 2026-10-20).
Read `docs/planet_lessons.md` first (how to measure, the traps).

Idea (user, 2026-10-17): cavern systems, and not only holes: a way of going under the ground that comes
from the planet's geology.

Decisions (user, 2026-10-17): **a maze that takes hours to explore, if possible, and realistic**; eruptions
and everything else dangerous stay safe for now.

## Goal

Caves that exist for a reason (the rock, the water, the heat), that can be entered from the surface,
explored, and that look and sound like caves: dark, wet, echoing, with their own rock forms and water.
Stay a pure function of the seed and the position, as the land is.

## Where we are

- The ground is a **height field**: one mesh and one `HeightMapShape3D` collider per tile
  (`PlanetTile`), so there are no overhangs, tunnels or holes. Colliders exist only on the finest tiles
  near the player.
- There is no rock type map: the ground shader makes strata from the slope and the distance to the
  centre; plates give relief but not geology (`PlanetTectonics`); hydrology (`PlanetHydrology`) has rivers
  and lakes on the surface only.
- The earlier terrain task ([057](057_terrain_realism.md)) said caves need volumetric terrain and are out
  of scope there. This task is that work.
- Lighting: the planet's ambient is the sky's light; inside a cave there is none of it.

## What makes a cave (geology, so the rules come from causes)

- **Karst (limestone, soluble rock)** in warm, wet regions where old shallow sea beds are uplifted: a
  network of passages and rooms along water tables, sinkholes at the surface, springs where it exits.
- **Lava tubes** in basaltic volcanic ground ([067](067_volcanoes_and_crust_activity.md)): long, smooth,
  roughly round tunnels downhill from a vent.
- **Sea caves and arches** in coastal cliffs of softer rock, cut by waves ([049](049_water_and_coasts.md)).
- **Ice caves** in the tongue of a glacier ([057](057_terrain_realism.md)): blue light, melt streams.
- **Erosion shelters and canyons' overhangs** in layered sandstone (wide, shallow).
- Cave rooms are bigger and more numerous where there is more water and more soluble rock; none in thin
  soil over hard crystalline rock.

## Research (2026-10-17: what is published, so we copy real methods)

- **Real caves form by a feedback**: water flows through a fracture, dissolves the rock, the passage widens,
  more water flows. A proto-conduit grows slowly for a long time, then *breaks through* and speeds up by orders
  of magnitude; competing paths then stop growing (Dreybrodt and Palmer). The **pattern depends on the
  water**: concentrated recharge (a stream sinking) gives a *branchwork* of tributaries joining downhill
  (vadose); diffuse recharge or rising water under a confining layer (artesian, hypogene, often gypsum or
  limestone with acid water) gives an *angular maze* along the fracture grid, with little selection between
  paths; a changing *water table* gives horizontal, looping levels (base-level conduits); a spongework of
  small connected holes appears in some rocks. A quantitative study of 26 caves separates branchwork from
  angular mazes from water-table/looping caves by their geometry and topology (nodes, loops, lengths).
  So a "maze of hours" is a real thing (Mammoth Cave has over 600 km of passage, Jewel Cave over 300 km) and
  it comes from the angular-maze and looping types.
- **Paris, Guerin, Peytavie, Collon, Galin, "Synthesizing Geologically Coherent Cave Networks"**
  (Computer Graphics Forum 2021, Pacific Graphics): builds the cave *skeleton* from geology: inputs are
  inlets and outlets (where water enters and leaves), faults, fractures, inception horizons (bedding planes
  where dissolution starts) and permeability contrasts; the skeleton is a set of **anisotropic shortest
  paths** between inlets and outlets (paths are cheaper along fractures and horizons), computed gridless; the
  *geometry* is a **signed distance function construction tree** of primitives with blending and warping
  operators, with control over the cross-section shapes and the detail of the conduits. The authors' C++
  re-implementation (MIT licence, no dependencies) makes the skeletons only; the network classification and
  the implicit surface are not in it. Use the paper's method. The project now has a native C++ library (`native/planet_crust`, task [073](073_native_planet_generation.md)): write the skeleton search and the surface meshing there, as the water and plant meshes were, and keep GDScript for the nodes and the streaming.
- **Real-time caves in games** (Mark and Berechet, 2015, GPU pipeline; a hobby SDF project, ProcGrotto): a
  tunnel layout from an L-system or Perlin worms, a signed distance field of it warped by layers of simplex
  and Worley noise, meshed per chunk with marching cubes or surface nets on the GPU or a worker, **skipping
  chunks that are all inside or all outside**; boolean operations on distance fields are min and max, so
  carving and blending are cheap; octrees save memory for big volumes. This is design choice A below.
- Not found: a comparison of surface nets with dual contouring on big cave systems in shipped games; we
  decide by the spike's numbers.

Sources: [Paris et al. 2021, Eurographics DL](https://diglib.eg.org/handle/10.1111/cgf14420),
[the paper's HAL preprint](https://hal.archives-ouvertes.fr/hal-03331697),
[project page](https://perso.liris.cnrs.fr/aparis/public_html/projects/paris2021_Karsts.html),
[code (skeletons)](https://github.com/aparis69/Karst-Synthesis),
[speleogenesis of 3D karst conduits, quantitative study](https://hal.univ-lorraine.fr/hal-01615432),
[coupled reactive-transport karst model, 2023](https://link.springer.com/doi/10.1007/s12665-023-11035-6),
[karst development models (Dreybrodt, Palmer, Klimchouk; EGU abstracts)](https://hess.copernicus.org/preprints/11/6519/2014/hessd-11-6519-2014.pdf),
[Mark and Berechet, caves on the GPU](https://dc2.philarchive.org/rec/MARPGO),
[ProcGrotto (SDF and marching cubes per chunk)](https://quintin-steiner.itch.io/procgrotto).
I read abstracts and the project and repository pages, not the full papers: read the full paper before
implementing the skeleton step.

## Design choices (to confirm with a spike)

A. **Voxel / distance-field chunks near a cave only.** The surface stays a height field everywhere. Where
   the geology says there is a cave, the tiles around the entrance and the cave's volume are made as
   signed-distance-field chunks (surface nets or marching cubes) on worker threads, with a trimesh collider
   per chunk; the terrain tile at the entrance gets a hole (its mesh and collider are made as a mesh with a
   hole, since `HeightMapShape3D` cannot have one). Cheapest in the common case, one more code path.
B. **Placed cave "rooms" as separate generated interiors** (like the procedural rooms of
   `docs/procedural_room_generation_plan.md`) reached through a mouth mesh set into a cliff. Simple and
   safe; not a continuous world; the interior and the exterior must agree at the mouth.
C. **The whole planet volumetric.** Not affordable (memory, build time); rejected.

Recommendation: A for the entrance region and the first rooms, with the cave network a 3D noise field
(worm tunnels plus larger "cheese" rooms) masked by the geology map; B only for decoration scenes.

## Plan

1. **Spike (one day):** one 64 m SDF chunk with a tunnel, surface nets on a thread, a trimesh collider; the
   player walks into it. Measure the build time per chunk (target < 50 ms off the main thread), the memory,
   the collider cost, and the hitch cost of adoption (see 044). Decide A or B on the numbers.
2. **Geology map.** A pure function `rock_at(direction, depth)`: crystalline, volcanic, limestone, sandstone,
   ice, soil; from the plates' ages and boundaries, the climate and the sea history. Add it to the map as a
   layer and use it in the ground shader (rock colours by type, not by noise only: also feeds
   [057](057_terrain_realism.md)).
3. **Cave network (the paper's pipeline, per karst region).** For each region of soluble rock (a cell of
   maybe 5 to 20 km across, found by the geology map, seeded from the region's id so it is the same every time):
   place **inlets** (sinking streams, sinkholes, fed by the surface hydrology) and **outlets** (springs at
   the lowest valley, the water table); lay **fractures** (a few orientation sets with spacing and
   length from noise) and **inception horizons** (bedding planes by depth); compute the skeleton as
   **anisotropic shortest paths** inlet to outlet (a graph on a coarse 3D grid, or gridless as the paper does;
   edge cost low along fractures and horizons), then **classify** it (branchwork when recharge is
   concentrated, angular maze when diffuse or artesian: add many cross-links along the fracture grid and
   loops at a few levels of the water table), subdivide the edges, and add rooms where paths cross and
   at the horizons. Scale target: **tens of kilometres of passage per region**, so a thorough exploration
   takes hours at walking pace (about 5 km/h in a cave is optimistic: allow for climbs and squeezes).
   The skeleton is a *graph per region*, small (thousands of nodes), computed once on a thread and kept in
   memory; the geometry is made from it only near the player (step 4). Entrance candidates are where
   the skeleton meets the surface (a sinkhole, a spring, a cliff face).
4. **Geometry and streaming.** The geometry is an SDF construction tree along the skeleton (tubes of varying
   cross-section: round for phreatic, keyhole or canyon-shaped for vadose, angular along fractures; blends at
   junctions; noise warping for the wall detail; flat ceilings at bedding planes); chunks are meshed from
   it (surface nets), skipping empty and full ones. Cave chunks are built only when the player is within a
   range of an entrance or inside;
   the planet's frame turning and recentring (`PlanetFrame`) must move them; free them when far.
5. **Inside look.** Darkness: ambient light fades with depth and distance from the entrance (a function
   of the cave's openness); fog with a cool tint; no sky; stalactites, stalagmites, columns, flowstone,
   crystals, pools and streams as instances or meshes on the SDF surface; wet shader (the ground shader's
   wetness input); drips.
6. **Underground water.** Rivers that sink and re-appear (a sinkhole and a spring on the hydrology), cave
   lakes at the water table; swimming in a cave uses the existing swim code.
7. **Sound.** Reverb zones (an audio bus effect by how enclosed the position is), drips, wind from the
   entrance, a river's sound.
8. **Life.** Bats and blind cave life, bioluminescent fungi that give light (a few emissive instances);
   no sunlight plants.
9. **Navigation and safety.** The player must not get lost forever or fall out of the world: a recovery
   key (return to the surface), a map layer showing cave entrances, a "depth" readout.
10. **Checks.** A lab mode that walks into a generated cave and reports collider presence, the floor under
    the player, the build times and the hitches; the map layer; `--planet-check` unchanged.

## Done when

- A karst region, a lava tube and a sea cave can be entered, walked through and left; no fall-through,
  no visible seam at the mouth; build and adoption costs measured and inside the 044/046 budget.
- The doc (`planet_generation.md`) has a "Caves" section and `planet_lessons.md` the measurements.

## Risks and open questions

- The biggest change to the terrain design so far (heightfield assumption is everywhere: the surface
  height function, colliders, plant placement, the map). Keep caves a separate layer that only *adds* to the
  heightfield; the surface function must stay valid without it.
- Collision at the mouth and the floating origin; trimesh colliders are slower than height maps.
- Lighting in Godot without baked probes: a dark cave needs a torch or emissive features (the player's
  tools are parked: [063](063_things_to_do_on_the_planet.md)); a cave with no light is unplayable, so a
  simple head lamp may be needed early.
- **Decided (user, 2026-10-17):** a maze that takes hours, realistic. Build it in steps: the spike (one
  tunnel), then one karst region with a branchwork, then the maze pattern, and only then the size.
- A maze of hours needs a map of the cave for the player (a survey drawn as they explore, the way real
  cavers do) and a compass or a way back: add them with the cave, not later.
- Realism limits: we model the pattern and the shapes, not the chemistry (no dissolution simulation over
  geological time; the skeleton comes from the paper's shortest-path method).
