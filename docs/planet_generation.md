# Planet generation (reference)

> The why, the measurements and the traps behind this design are in `planet_lessons.md`.

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
| `PlanetMap`, `PlanetChart` | the M key: a full screen flat map that opens on the player's region, wheel zoom and drag, rivers, lakes, a grid and the player's arrow; the layer buttons / keys 1-7 show the terrain, elevation, temperature, rain, biome, plates and slope with a legend and the numbers under the cursor; `PlanetChart` draws a picture of the whole planet (coarse, then fine) or of the close region on 3 threads once the player is in |
| `PlanetSeasons` | the temperature through the year as an energy balance (sunlight in, heat radiated, heat capacity of land and sea, snow albedo, heat shared by winds): one repeating year kept as 48 pictures, read at any time forward or backward |
| `PlanetWeather`, `PlanetCloudShell`, `PlanetMoon` | the clouds and the weather from moisture, lift (trade belt, storm tracks, mountains) and the zonal winds that carry them, as a function of the date; the cloud shell seen from orbit; the moon's orbit, place and phase |
| `PlanetAtmosphere`, `PlanetAir` | the sun's light, the sky, the ambient light and the fog from the physics of the air: single scattering through a spherical atmosphere (shrunk with the planet), the sun's colour by how much air it crosses, black space and stars above the air; Sky3D is not used |
| `PlanetClock` | the star, the orbit, the spin and the axial tilt as real geometry: the direction to the sun anywhere on the planet, the day length by latitude, the seasons; `PlanetWorld` feeds it to the sky |
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

## The Planet page of the Esc menu

`PlanetMenu` (`systems/planet/planet_menu.gd`) is the planet's counterpart of the flat world's
"World" page; `PlanetWorld.start` adds it through the HUD's `add_menu_page` when the target is a
player. It has the time controls (speed -1000x..1000x and pause, jumps of a day and 1/8 year, sliders
for the hour and the day of the year), the weather (follow the climate or force a state through
`PlanetWorld.weather_override`), seed and radius fields with "Make this planet" / "Random seed"
(`PlanetMenu.pending` carries the settings over the scene reload) and the map. In the lab,
`-- --planet-page` opens it from the start (screenshots).

## Detail follows the distance in space

`PlanetSurface._distance` (what picks the size of a tile, which tiles get plants and which get
colliders) is the distance in space from the player to the tile: along the ground from the point under
them, and their height over the ground there (`_height`, not over the sea: a climber on a mountain
keeps the fine tiles). Before this it was along the ground only, so a player 6 km up still had the
finest tiles and every tree below them drawn: 147 million primitives a frame and 28 fps (now 463).
Measured in the lab with the player lifted by `-- --climb=N --fps` (draw calls, primitives, tiles by
level and the triangles by kind of node are printed). On the ground a frame is still about 40 million
primitives (the trees are 8 to 10 thousand triangles each; shadows draw them again).

### Distance levels of the plants (`PlanetScatter`)

Measured at the ground with `-- --fps` (hide a kind with `--hide=`): trees were nearly all of a frame
(hiding them: 74 to 219 fps), and most of that was draw calls, not triangles (the far trees alone were
3,000 of 4,900 calls). Now a tree is the full mesh to 100 m (`TREE_FULL`, with shadows), its lighter
version (`lod` 1, no shadow) to 220 m (`TREE_LIGHT`), and beyond that the cheap far tree; the far
trees of a tile (and the horizon trees) are merged into one mesh per tile (`_commit_far`: the tint in
the vertex colours, the sway weight kept in alpha), so a tile's far forest is one draw call. Shrubs
and ground cover stop at 220 m, grass at 110 m. Ground frame: 55 fps, 4,900 draw calls, 39.6 M
primitives before; 152 fps, 1,633 calls, 8.9 M after. The trees of the far tiles (beyond 512 m) are
the lighter version, then the far tree.

Streaming cost: a first version of this gave hitches (195 frames over 33 ms on the 24 km fly check,
against 6 before), because every new species and variant also built and uploaded a light mesh and a far
mesh on first use. The light mesh is now shared by two variants per species (`variant % 2`, like the far
tree): 17 slow frames, worst 68 ms. Full-detail plants are only on tiles within 256 m of the player.
`-- --fly-check` and `--walk-check` print `HITCH worst_frame=... frames over 33 ms` (after the loading).

## Clouds

One layer of real volume (700 m thick, 450 m above the ground under the player), marched and lit in
`planet_cloud_march.gdshaderinc`, which two shaders share so they draw the same clouds: the sky
(`planet_sky.gdshader`) from under the layer, and a sphere round the planet
(`planet_clouds.gdshader`, `PlanetCloudShell`) from in the layer and above it, from just over the
ground to orbit, stopping at the ground of the scene (the depth texture). Under 450 m above the
ground the sky has them, over 700 m the shell, with a cross-fade between (`PlanetAtmosphere.cloud_on`).
The star's light at a cloud depends on how high the star stands over that cloud (white high up,
orange low down, none at night), so the day and the night side and the terminator show from orbit.
Where there is cloud comes from the planet's own cover picture (`PlanetCloudShell` keeps it fresh
every few seconds on a thread and gives it to both), so the ground, the map and the orbit agree; the
noise shapes the billows, and the wind that carries the cover (`PlanetWeather.zonal_wind`) carries
the small shapes too (`PlanetWorld._drift_the_clouds`). The old low-poly puffs are no longer used on
the planet. Cost: the march skips clear sky and uses fewer steps on short ways.

## Saved universes

`UniverseSave` (`systems/planet/universe_save.gd`) writes `user://universes/<name>.json`: the planets
of the universe (a list; today the one, each with its settings, since the same seed and numbers make
the same planet and the land is not stored), the planet the player is on and the moment on it
(`PlanetWorld.snapshot`: where the player stands, which way they face in the planet's frame, the
clock, the speed of time, a forced weather). The format is made for the day the player can travel
between planets: each planet keeps its settings, the save knows which one is current, and saving
keeps the other planets of the file. First-version saves (`user://planets/`, one planet) are still
read. The Planet page of the Esc menu has "Save here", a list of saves with Open and Delete
(opening reloads the scene with `PlanetMenu.pending` and `pending_state`, and
`PlanetWorld.restored` puts the player back). The player is put on the ground at the saved place,
whatever their height was. Opening still builds the ground from the seed, so the loading screen is
the same; what a save spares is choosing the planet, the place and the time.
The lab (started with no arguments, or with `-- --start-menu`, or from "Main menu" in the Planet
page) shows `UniverseStartMenu` first: the list of saved universes (Open, Delete, double click), a new planet
(seed and radius, a random seed) and a quick start with the default planet; choosing sets
`PlanetMenu.pending` and reloads the scene. Other lab options: `-- --world=NAME` or `-- --continue`
(the newest), `-- --save-as=NAME`; `--planet-check` also runs `SAVE_CHECK`.

## Levels of the air

The air has the Earth's levels, shrunk with the planet but not below a quarter (`PlanetAir.MIN_AIR_SCALE`):
a scale height of 2 km and a top at 25 km on any planet under 1600 km across. The clouds (450 to 1150 m
above the ground) lie in the lowest part, in bright blue air; the sky is deep blue at 3 km, dark
navy at 8 km, black with the stars above the top. Below the least scale (a 20 km planet at full
physical shrink) the whole air would have been 300 m deep and the sky already black at cloud level.
The cost: the sun's path through the air at sunset is shorter than on the Earth, so the sunsets are
pale and hazy rather than red.

## Wet ground and snow

`planet_ground.gdshader` reads three shader globals the weather sets (`WorldWind.set_surface`):
`ground_wetness` (stays after the rain stops), `rain_fall` (how hard it rains now) and `snow_cover`.
Wet ground goes dark and glossy everywhere; water stands in the low level patches (noise in the
world position, only where the ground is almost flat) with rings from the drops while it rains; snow
settles unevenly (more on level ground, broken at the edges). Lab: `-- --weather=rain|snow|storm`.

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

## Universe (task 054)

A universe is a seed (`UniverseSettings`). System N comes from the seed and N (`system_seed`), so nothing is stored:
`StarSystem.generate` makes a `Star` (mass sets luminosity, radius, temperature, lifetime, colour) and its planets on
Kepler orbits (year from distance and star mass; rocky inside the frost line, giants beyond; "habitable" is rocky and
inside the liquid-water zone). `UniverseSettings.planet_settings(system, planet)` turns one planet into the
`PlanetSettings` the planet is built from (game scale: Earth is 20,000 m; the day is the planet's, the year is the true
one in local days clamped to 6..64). The star reaches the planet in two ways, both physical: its colour tints the sun
lamp, the sky scattering and the clouds (`Star.light_tint`; the eye adapts, so only 75% of the colour difference
shows; `star_readability` blends it back to white), and its light at the planet's distance (`insolation` = L / a^2)
multiplies the sunlight the seasons' energy balance receives (half the light: the equator drops from +27 to -16 C
with the ice feedback). The Sun is exactly white and insolation 1, so a plain planet is unchanged. Lab:
`planet_lab -- --universe=SEED [--systems=N] [--any]` prints the table and `UNIVERSE_CHECK`; `-- --home=SEED [--any]`
starts on that universe's home planet; `-- --star-mass=M --star-readability=R` sets the star alone. The start menu
creates a universe (home planet: Sun-like or any; star colours: physical .. readable). Saves are version 3 (a
`universe` block; version 2 still loads). Not done yet: other planet kinds (061), travel (055), the Planet page's star
data, sun disc size.

## Stages (what can be switched off)

A planet is made in this order: tectonics and the height noise, the sea level, the climate (the
seasons, then the yearly temperature and the rain), the weather, hydrology (rivers and lakes), then
in the world the ground tiles, the sky and clouds, the plants and rocks, the animals. Three of them
have a switch, in `PlanetSettings` and in the lab (`planet_lab`):

- `plants_on` / `--no-plants`: no plant or tree is placed (the species are still made, they are cheap).
- `animals_on` / `--no-animals`: no animals.
- `hydrology_cells = 0` / `--no-water`: no rivers or lakes (the sea stays).

The others (terrain, climate) are the base the rest reads, so they stay on. `plant_density` and
`rock_density` still thin the plants and rocks without stopping them.
