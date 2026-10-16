# Planet generation (reference)

A walkable round planet made entirely of code, in `systems/planet/`. This is the stable reference:
how it works, how to run and check it, its limits. The running handoff (status, next steps, what
is rough) is `AGENT_TASKS/043_planet.md`. The flat world it grew next to is `AGENT_TASKS/040`.

## Run it

- Lab: `tests/manual/planet/planet_lab.tscn` (open it and press F6). The real player spawns on the
  planet; `-- --radius=20000 --seed=1337` pick the size and seed.
- Pictures without a player: `-- --dir=x,y,z --view-alt=N --view-pitch=N --view-yaw=N
  --shot=PATH --shot-frame=N` (`--bare` hides the plants).
- Checks (headless): `-- --planet-check` (the player is moved 2.4 km in steps and must stay on the
  ground, expect `PLANET_CHECK PASS`); `-- --walk-check` with `--fixed-fps 60` (the real player
  holds forward and sprint for 90 s on the streaming planet, expect `WALK_CHECK PASS`).
- Lint stays clean: `gdlint .`; the flat world's `--world-check` must still pass.

## How it is built

| Piece | Job |
|---|---|
| `PlanetSettings` | every number: seed, radius, relief, ocean share, plates, tile sizes, hydrology cells, lake depth, densities |
| `PlanetTectonics` | ~14 plates (continental or oceanic) with a spin; height from the plate's base plus uplift by boundary type (collision ranges, coastal range and trench, island arc, mid-ocean ridge, rift) and ridged noise |
| `PlanetClimate` | 192x96 maps of sea level temperature (latitude) and rain (carried by trade winds / westerlies / easterlies, picked up over sea, dropped over land and where the ground climbs) |
| `PlanetHydrology` | flow routing on a cube-face grid: priority flood from the sea (lakes in the hollows), drainage area from the rain, rivers = the top share by flow, smoothed river paths with water levels below the ground, stream power erosion field, carving of channels |
| `PlanetNoise` | the planet as pure functions of a direction: `height` (plates + hills + gullies + erosion + ledges, rivers cut in), `moisture`, `heat`, `temperature`, `biome`, `facet_color` (smooth blend of every biome), `find_spawn` |
| `PlanetTile` | one cell of a cube face bent onto the sphere (tan mapping): mesh, collider, sea, river ribbons, lakes, plants; built around its own middle in doubles |
| `PlanetSurface` | quadtree LOD per face, worker thread, a tile is only dropped once its replacements exist, skirts hide the cracks |
| `PlanetFrame` | the floating origin: the planet is turned under the player so the game's flat-world rules (up = +Y, gravity down) keep holding |
| `PlanetScatter` | plants (the world's species by climate niche), rocks, logs, spires; nothing on water |
| `PlanetFauna` | the flat world's deer and rabbits on the planet |
| `PlanetMap`, `PlanetChart` | the M key: a full screen flat map that opens on the player's region, wheel zoom and drag, rivers, lakes, a grid and the player's arrow; `PlanetChart` draws a picture of the whole planet (coarse, then fine) or of the close region on 3 threads once the player is in |
| `PlanetSwim` | the flat world's swimming and wading (`WorldSwim`) with the planet's sea, lakes, rivers and river currents |
| `PlanetWorld` | ties it together with `WorldAtmosphere`; rebases the frame every 80 m, shifts the world back every 2 km |

Ground shader: `shaders/world/planet_ground.gdshader` is the flat world's low-poly ground with detail
that belongs to the planet: 3D noise read at the point's planet position (the shader globals
`planet_from_world` / `world_from_planet` are set by `PlanetWorld.publish_frame` after every rebase, so
the pattern neither swims nor breaks at tile seams): soil and rock patches, grain, rock layers level
round the planet, bumps on steep faces, fading out with distance. Plants: the two finest tile levels
have real trees, the next three have sparse cheap horizon trees (`Detail.FAR`) out to ~5 km.

Loading: the ground and water come first. `PlanetSurface` builds tiles without plants on 2-4 ground
threads; plants are a second job on 2-3 planting threads (nearest tile first) that grows a holder node
which the tile adopts later. The player stands still ("Generating the planet... N %") until the ground
within 2 km (colliders included) and the plants within 60 m exist, about 7 s here; everything else
keeps streaming in around them. `PlanetWorld.loaded` is emitted when they may move.

Water shaders: `shaders/world/planet_water.gdshader` (sea and lakes, smooth lit normals),
`shaders/world/river.gdshader` (flowing ripples, bank foam, UVs along and across the ribbon).

### The key ideas

1. **The frame.** The player never sees a curved world: `world = rot * (planet - anchor) + origin_w`.
   After 80 m of walking the planet is turned about the player's feet by a few tenths of a degree so
   the ground is level again. Foot IK, climbing and the camera needed no change.
2. **Ground and water first, then life.** Terrain, sea, rivers and lakes are built before anything
   grows; plants are chosen from the climate at the spot and never placed in water.
3. **Everything is a pure function of the direction and the seed**, so any tile can be built alone
   and neighbours agree on their shared edge. The only global state is built once at start: the plate
   list, the climate maps and the hydrology grid.
4. **Relief scales with the planet**: `clamp(R * 0.0035, 300, 9000)` m, the sea level is found so
   `ocean_fraction` of the area is under it.

## Limits

| radius | single precision (official Godot) | double precision build |
|---|---|---|
| 20 km (default) | pass | pass |
| 200 km, 1,000 km | pass | not run |
| 6,371 km (Earth) | fails (0.5 m steps in float32) | pass |
| 69,911 km (Jupiter) | not run | pass |

- The tile key allows levels up to 31 and x, y up to 2^20: about 100,000 km radius.
- The horizon of a 20 km planet at eye height is ~260 m; a bigger radius feels more natural.
- The first tiles take about a second to build, then they stream on a worker thread (80 ms each in
  GDScript). A headless run builds a few per frame inline.

### The double precision editor build

Needed for planets above ~1,000 km (or any size that must not jitter). Built here from the 4.7.2
tag with MSVC (14 minutes on 6 cores):

    python misc/scripts/install_d3d12_sdk_windows.py      # this project uses the D3D12 driver
    scons platform=windows target=editor precision=double arch=x86_64 d3d12=yes debug_symbols=no

Output `bin/godot.windows.editor.double.x86_64.exe` (+ `.console.exe`, with `D3D12Core.dll` beside
it). No export templates were built. The project has no native GDExtensions to rebuild, and
Jolt turns on `JPH_DOUBLE_PRECISION` itself. In a double build `Vector3` and the noise inputs are
64-bit and `HeightMapShape3D.map_data` is a `PackedFloat64Array` (`TerrainChunk` sets it with
`set()` so it compiles in both). Binary resources saved by a double build carry a flag: do not
save scenes with it by accident. A ray fired exactly on the seam between two tiles can slip
through in the double build (edges differ by 1e-10 m): physics checks avoid seams.

## Where the ideas come from

- Plates and the cube-sphere quadtree with colour "mods": Kerbal Space Program's PQS; slope and
  altitude blending of the ground: the Parallax terrain shader for KSP.
- Stream power erosion: Cordonnier et al. 2016, "Large Scale Terrain Generation from Tectonic Uplift
  and Fluvial Erosion" (and Tzathas et al. 2024 for the analytical version).
- Rain on the wind, rivers from drainage, biomes from moisture and warmth: Red Blob Games mapgen4.
- The floating origin per planet is the standard way (Kerbal Space Program, Elite Dangerous) to keep
  coordinates small; a universe above this would add seeds -> frames per galaxy, system, planet.

## Not done

Weather and day/night from the planet's rotation, birds and butterflies, underwater look beyond
the fog colour, planets without life (craters, ice), star systems.
