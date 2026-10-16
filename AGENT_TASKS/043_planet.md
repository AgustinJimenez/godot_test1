# 043 Planet (round world prototype)

Status (2026-10-16): **prototype works**: a walkable round planet with plates, climate biomes, rivers,
lakes, plants and a double precision option. Branch `godot-4.7-upgrade`, code in `systems/planet/`,
lab `tests/manual/planet/planet_lab.tscn`, check `-- --planet-check` (expect `PLANET_CHECK PASS`).
Nothing in the flat world was changed except `TerrainChunk` (collider `map_data` set by `set()` so
it also compiles in the double build). Not play-tested by the user yet.

Run: `godot --path . res://tests/manual/planet/planet_lab.tscn -- --radius=20000 --seed=1337`
(`--dir=x,y,z --view-alt=N --view-pitch=N --shot=PATH --shot-frame=N` for pictures without a player).
Earth size needs the double build (see below).
`-- --walk-check` (with `--fixed-fps 60`, headless ok): the real player holds forward + sprint for 90 s
on the streaming planet; expect `WALK_CHECK PASS` (434 m, 5 rebases, 100% on the floor).

Next (by value): walk it and tune the river look (flat opaque water, steep mouths) and plant
density; birds, butterflies and fireflies; weather and day/night from the planet's rotation; erosion simulation;
planet types without life (craters, ice); star systems above this (see the chat plan: seeds ->
frames -> floating origin per planet).


Goal: a walkable round planet, built next to the flat world (nothing in `systems/world_gen` changed
except that `TerrainChunk.ground_material`, `MeshBuilder` and `TerrainColors` are reused).
Lab: `tests/manual/planet/planet_lab.tscn` (`-- --radius=N --seed=N`); check:
`-- --planet-check` (headless, expect `PLANET_CHECK PASS`).

## Design

- `PlanetTectonics`: ~14 plates (Fibonacci spread, jittered), each continental or oceanic with a spin.
  Height in units of `relief`: plate base height blended across boundaries, plus uplift by boundary
  type (continent/continent collision = high ranges, subduction coast = coastal range + trench,
  ocean/ocean = island arc + trench, divergent = mid-ocean ridge or rift), ridged noise on the ranges,
  plate-interior noise. Plate lookup uses a warped direction so edges wander.
- `PlanetClimate`: 192x96 equirect maps of sea level temperature (latitude) and rain (moisture carried
  along trade winds / westerlies / polar easterlies: picked up over sea, dropped over land and where
  the ground climbs, so rain shadows and dry interiors; wet tropics, dry belt at 28 deg, storm tracks
  at 48 deg).
- `PlanetNoise`: relief from the radius (`clamp(R*0.0014, 150, 9000)` m, Earth 8.9 km, or
  `PlanetSettings.relief`), the sea level found so `ocean_fraction` (0.7) of the area is below it,
  rolling hills (2 km) and hills (450 m) on the land, temperature with the lapse rate (height taken
  as a share of relief), biome and colour from temperature and rain (rain forest, savanna, grass,
  forest, taiga, tundra, desert, ice, rock), and `find_spawn` (mild lowland). Pure functions of the
  direction and the seed. No rivers or lakes yet; no erosion.
- `PlanetHydrology` (rivers, lakes): the ground (macro height, without the small hills) sampled at the
  middle of 96x96 cells per cube face (327 m a cell on a 20 km planet); priority flood from the sea
  gives every cell a downstream neighbour and fills hollows (lakes where deeper than 8 m); rain is
  summed down the drainage; the top 4.5% of land cells by flow are rivers, wider with more water.
  Each river is followed source to mouth, corners rounded (Chaikin x2), each node's water level set
  below the real ground there and never above the node upstream, the river ends where the ground
  falls under the sea. `carve` cuts a channel (bed, banks, valley) into `PlanetNoise.height`;
  tiles draw river ribbons (shared node tangents, no gaps) and lake cells cut to the tile edges.
  `water_at` tells the scatter where water stands: **ground and water come first, plants after**.
- `PlanetScatter`: plants on the finest tiles (all layers near the player, trees only further out),
  species from `SpeciesRegistry` (same generator as the flat world), fitness from the planet's
  moisture (rain), warmth (temperature at the height) and slope; nothing grows in the sea, a river or
  a lake. `Plants` bodies hold trunk colliders (the check ignores them).
- Rocks, logs, stumps, rock spires and driftwood: `PlanetScatter._rocks`, the flat world's kinds and
  chances by biome (`FloraMeshes`), box colliders on the finest tiles.
- Fauna: `PlanetFauna extends WorldFauna` (deer and rabbits, same behaviour) looks the ground up with
  `PlanetWorld.ground_at` (world height, biome, under water?), so animals stay out of the water.
- Water: `shaders/world/planet_water.gdshader` is water_lowpoly with smooth lit normals (the faceted
  low-poly normals made the sun glint a field of squares); sea facets ~5 m near, bigger and flat
  (vertex colour red = wave share) far away.
- Gullies: ridged noise on the high ground in `base_height`.
- `PlanetTile`: one cell of one of the six cube faces bent onto the sphere (tan mapping). The mesh is
  built around the tile's own middle in doubles, so its numbers stay small on any planet. Every tile
  has `tile_cells` quads, so a tile twice as big has quads twice as wide: one code for the near ground
  and the horizon. The finest tiles near the player get a trimesh collider (one-sided: Godot's front
  face is clockwise seen from above; `MeshBuilder.add_tri_smooth` takes counter clockwise corners).
- `PlanetSurface`: quadtree LOD per face (split when the player is within `split_factor` tile
  widths), worker thread, a tile is only dropped once the tiles that replace it are built; skirts
  hide the cracks between tiles of different sizes.
- `PlanetFrame`: the key idea. The player always stands in a flat-looking world (up = +Y, gravity
  down, so the player, foot IK, climbing, camera need no change); the PLANET is moved around them.
  `world = rot * (planet - anchor) + origin_w`. After walking `REBASE_DISTANCE` (80 m) the planet is
  turned about the player's feet so the ground there is level again (a few tenths of a degree), and
  after `RECENTER_DISTANCE` the whole world is shifted back (this one teleports the player, which
  may glitch foot IK; rare). Tile transforms are recomputed from doubles each time, so the world
  coordinates stay small however far the player walks.
- `PlanetWorld`: ties them together with the existing `WorldAtmosphere`.

## Surface polish (2026-10-16, second pass) and the work it was inspired by

Ideas taken from existing work (read only the abstracts / pages, not the full papers):
- Cordonnier et al. 2016, "Large Scale Terrain Generation from Tectonic Uplift and Fluvial Erosion"
  (stream power law over a drainage graph) -> `PlanetHydrology._erode`: slope allowed = f(water
  through the cell), so big rivers sit in wide low valleys and trickles barely cut. Tzathas et al.
  2024 (analytical stream power) is the next step if it must be faster or finer.
- Red Blob Games mapgen4/mapgen2: rain from the sea on the wind, rivers from drainage, biomes from
  moisture and temperature; cheap and good looking -> `PlanetClimate`, `PlanetHydrology`.
- Kerbal Space Program's PQS and the Parallax terrain shader: a cube-sphere quadtree with height and
  colour "mods", and slope / altitude based blending of low, mid, high and steep ground (rock on
  steep faces, triplanar for cliffs) -> `PlanetNoise.facet_color` blends every ingredient with
  smooth weights. Triplanar detail textures on a sphere are a later step (needs a ground shader
  change; the planet reuses the flat world's low-poly ground shader).
- Inigo Quilez's derivative-damped eroded fbm (already `ErodedNoise` for the flat world): the
  planet uses ridged gully noise on the high ground instead (cheaper, no derivatives).

Done: beaches and shallows (`_macro` shore profile), rock ledges (`base_height` layers), mountain
belts inside the continents (`_ranges`), rolling hills scaled with the relief, stream power
erosion field, blended biome colours (no hard edges, rock on steep or high ground, snow by
temperature), river shader (`shaders/world/river.gdshader`: UVs along/across the ribbon, flowing
ripples, bank foam, clear shallows), lakes built from each tile's own grid (shore follows the ground),
fewer lakes (`lake_depth_share`, 8% of the relief, about 2% of the land), clear spawn.
Relief is now `clamp(R * 0.0035, 300, 9000)` m.

Third pass: planet ground shader with planet-anchored 3D detail noise (globals `planet_from_world`,
`world_from_planet` in project.godot), horizon trees on the next three tile sizes.

Still rough / ideas: tile LOD edge colour mismatch and popping, sea depth
colours, swimming / underwater, river mouths into steep coasts, lakes' outflow carving, river banks
(mud, reeds), erosion by simulation on a finer grid, thermal erosion (talus), performance (tile
build ~80 ms, startup).

## Limits (measured with `-- --planet-check --radius=N`, 2.4 km walked in 60 m steps)

| radius | single precision (official 4.7.2) | double precision build |
|---|---|---|
| 20 km (default) | PASS | PASS |
| 200 km, 1,000 km | PASS (worst gap 0.7 m) | not run |
| 6,371 km (Earth) | FAIL (float32 directions and noise inputs, 0.5 m steps) | PASS (0.86 m) |
| 69,911 km (Jupiter) | not run | PASS (0.76 m) |

Tile keys hold levels up to 31 and x, y up to 2^20, so about 100,000 km radius is the ceiling of the
current key packing (level 20); widen `PlanetTile.key_of` for more.
The horizon of a 20 km planet at eye height is ~260 m.

## The double precision editor build

Built from the 4.7.2-stable tag (shallow clone) in `E:\Godot\double\src`, SCons in
`E:\Godot\doubleenv`, MSVC 2022, 6 cores, 14 minutes:

    python misc/scripts/install_d3d12_sdk_windows.py        # the project uses the D3D12 driver
    scons platform=windows target=editor precision=double arch=x86_64 d3d12=yes debug_symbols=no -j6

Output `bin/godot.windows.editor.double.x86_64.exe` (+ `.console.exe`, `D3D12Core.dll`, keep them
together). No export templates were built (they need `target=template_release precision=double`).
The project has no native GDExtensions, so nothing else needs a rebuild. Jolt switches on
`JPH_DOUBLE_PRECISION` itself. Things a double build changes for GDScript: `Vector3`, `Transform3D`
and noise coordinates are 64-bit, and `HeightMapShape3D.map_data` is a `PackedFloat64Array`
(`TerrainChunk` sets it with `set()` so it works in both builds). Do not save scenes with the double
build you also open in the single one unless you mean to: binary resources get a flag.
A ray cast onto the exact seam between two tiles can slip through in the double build (the tiles'
edges differ by 1e-10 m); the planet check avoids seams.

## Not done

Birds and butterflies (WorldLife), weather, planet rotation / day-night from the planet, other
planets, space.
