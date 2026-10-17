# 066 - Caves and the underground

Status: **planned (2026-10-17)**. Follows [043](043_planet.md). Branch: `godot-4.7-upgrade`.
Read `docs/planet_lessons.md` first (how to measure, the traps).

Idea (user, 2026-10-17): cavern systems, and not only holes: a way of going under the ground that comes
from the planet's geology.

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
3. **Cave field.** A 3D function (worm tunnels along the water table, rooms where soluble rock and water
   meet; lava tubes down the slope of a volcano; sea caves along coastal cliffs) giving density; the
   entrance candidates are where the field meets the surface on a steep face or a sinkhole.
4. **Streaming.** Cave chunks are built only when the player is within a range of an entrance or inside;
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
- **Open (user):** how deep and how large should a cave system be (a few rooms, or a maze of hours)? Start
  with one cave of a few rooms per geological region.
