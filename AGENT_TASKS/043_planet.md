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

## Principle: real features, not fakes (user decision, 2026-10-16)

When the planet needs a behaviour that exists in nature (day and night, seasons, weather, clouds,
tides, climate), build the cause and derive the effect, do not paint the effect. Example: the sun is
not a time-of-day number, it is the direction to a star computed from the planet's orbit, spin and
axial tilt (`PlanetClock`); day length by latitude, the polar day and night, the seasons and the
warm belt moving north and south all come out of that geometry. Temperature by season will come from
the sunlight a latitude receives (`PlanetClock.daily_light`), clouds and weather from the climate and
the winds, moons and tides (later) from orbits. Keep the numbers (day length, year length, tilt,
orbit) in `PlanetSettings` so each planet can differ. Game scale: sizes and distances are not
real, the angles and the ratios are.

## Time, orbit and spin (2026-10-16)

`PlanetClock` (pure geometry, verified by a script: noon sun height at 45 N is 68.4 deg at the
summer solstice and 21.6 deg at the winter one, the day is 12 h at the equator all year, 24 h at 80 N
in midsummer and 0 h in midwinter, an hour of clock time moves the sun by 15 deg, the year closes):
the planet circles the star in a plane once a year (`year_days` solar days), spins once a sidereal
day about an axis tilted `axial_tilt` from the orbit's normal and fixed in space; the star's
direction in the planet's own frame gives the sun anywhere. `PlanetWorld` advances it with play time
(`time_scale` speeds it up) and sets `WorldAtmosphere.sun_direction` (the frame turns planet
space into world space), so the sun, the sky, dusk and the night all follow the real sun. The map
caption shows the local solar time and the season. Lab: `-- --hour=H --year=Y --time-scale=N`.
Seasons (`PlanetSeasons`, the energy balance behind the temperature; not a painted curve): a grid
of 96x48 cells, each warmed by the sunlight its latitude receives that day (`PlanetClock.daily_light`),
cooling by radiating (the balance temperature follows the fourth root of the absorbed light), moving
toward that balance at a rate set by its heat capacity (the sea 0.2 years, the land 0.05), snow and ice
reflecting 30% of the light (a feedback that keeps the caps), evaporation and cloud capping the
hottest values, and heat shared between neighbours (winds and currents, 3 passes of 30%). The planet is
run through its year until the cycle repeats (3-4 years, about 2 s at start) and one year is kept as 48
pictures: the temperature at any moment, forward or backward in time, is read off that cycle (nothing
is simulated while playing). Results: land warmest about 3 weeks after the solstice, the sea about 6
weeks after (it lags), the continental interiors swing 60-70 C a year, the tropics barely at all,
yearly mean 29 C at the equator and -23 at the pole. `PlanetNoise.temperature` is the yearly mean (what
biomes and plants follow, so they stay put); `temperature_now` is the season and the time of day
(land swings 6 C a day, the sea 0.8) minus the lapse rate. Map: layer 3 "Temperature" is the moment now
(it is charted again as time moves), layer 8 "Mean temp" the climate; a Time row moves time: speeds
-1000x to 1000x and pause, a day or an eighth of a year at a time, a slider through the year (the sun
and the temperature follow, backward too). `PlanetWorld.time_rate`, `jump_time`, `set_year_share`.
Weather and clouds (`PlanetWeather`, derived from causes, a function of the date so it runs
backward with time): the cloud a place can make (`readiness`) is its moisture (a warm sea gives off a
lot, wet land some, a frozen place little, from the seasonal temperature and the rain climate) times
the lift: the belt where the trade winds meet (it follows the sun, 0.4 of the declination), the
storm tracks of the middle latitudes (about 50 degrees, shifting with the season) and the wet
windward sides; held down under the subtropical highs (about 28 degrees). The clouds are noise
(two patterns that morph into each other, plus clumps) carried round the planet by the zonal wind
(`zonal_wind`: easterly in the tropics and the polar regions, westerly between, 3.5% of a turn a
day at the strongest), so the pattern drifts and reshapes as time runs. The weather at a place:
cloud over 35% cloudy, thick cloud on lifted moist air rain (snow below 0.5 C, a storm where it is
hot and the lift great), fog on a wet morning (hours 3-8:30), else clear. Measured over the planet:
mean cloud 0.46, clear 51%, cloudy 31%, rain 13-15%, snow 2-4%, storm 1%, fog 1%. `PlanetWorld`
picks the state every 1.5 s for the player's spot and the flat world's `WorldWeather` makes the
effects (clouds, rain, snow, fog, wind, wet ground) and eases between states; the wind blows along
the parallel as the clouds are carried (`WorldWeather.forced_wind`). From orbit a cloud shell
(`PlanetCloudShell`, `planet_clouds.gdshader`) shows the cover, lit by the real sun, from 1.5 km
up (a 256x128 picture charted on a thread every 2.5 s). Map layer 9 "Clouds" (and the caption
shows the weather where the player is). The moon (`PlanetMoon`): a circular orbit tilted 5.1 degrees,
`month_days` 3.5 (game scale), its place in the sky and its phase from the geometry (new to full,
the sky shader draws the lit part, the moonlight scales with it and with the moon being up).
Clouds are height limited (user saw them far from the planet): the flat world's cloud puffs and rain
sit at a height of the WORLD, so when the player flew up they hung in space. `PlanetWorld.
_keep_the_weather_near_the_ground` now rides them at their height above the ground under the player
and hides them and the rain above 1.5 km (where the cloud shell takes over).
Light and sky from physics (user: "disable sky3d for now, make it ourselves, space dark, only light
from the sun"). The planet uses `PlanetAtmosphere extends WorldAtmosphere` and the sky shader
`planet_sky.gdshader`; Sky3D is not used on the planet (the flat world's level still turns it on in
`levels/procedural_world.gd`). `PlanetAir` is the maths (shared with the shader): single scattering
of the star's light through a spherical atmosphere (Rayleigh for the molecules, Mie for haze, density
falling off with height): the sun's light is what the air lets by (`sun_transmittance`: white in space,
yellow at noon, red low down, none where the planet is in the way), the sky is the air scattering it, and
above the air there is nothing: space is black, with the stars, the moon (phase) and the sun disc.
The ambient light is the sky's own (the sky is rendered into the environment, so it is blue by day,
red at dusk, dark at night; only inside the air a trace of starlight is added; in space none), the fog
colour is the air's colour at the horizon seen away from the sun. Small planets get a shrunken
atmosphere (`air_scale` = radius / Earth's radius: lengths times it, scattering per metre divided by
it) so the optical depths are the Earth's and the sunsets are red: with the Earth's air round a 20 km
planet the grazing sun path is 28 times too short to redden. A 20 km planet's air is then about 310 m
thick (`PlanetSettings.air_height` is the Earth-equivalent 100 km). From orbit: black sky, stars, the
planet lit only by the sun, a thin blue rim of air with the sunset colours on the terminator.
Not done: sky clouds in the planet sky shader (the flat world's puffs and the cloud shell are used),
a star of another colour or brightness, aurora, eclipses, eye adaptation (the night is dark; a floor
of ambient keeps it playable), the cost of the realtime sky radiance has not been measured.
Not done: heat carried by the wind along its direction (it is mixed evenly), a moon, clouds, weather, a moon, an
elliptical orbit, other planets in the sky, a star disc and its colour per star.

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

Fourth pass (user feedback): debug menu "Free speed" slider for free mode (2 to 600 m/s on an
exponential slider, `ui/hud.gd`, sprint triples it; `-- --fly-check` flies the planet at 100 m/s,
fast flight faster than ~1,800 m/s made Jolt print shape errors from the tile churn); the red camera
cone was the FOV gizmo of the third-person debug camera, on by default while its button said OFF
(now off by default); tree variety: a planet makes 120 species (`species_count`, was 36: one red
oak-like tree dominated), 6 looks per tree species, wider per-tree tint range.

Fifth pass: the far ground is shaded smooth (colours and normals blend from facets to the smooth
vertex colours between 90 and 320 m, so coarse and fine tiles meet without a seam), the sea shows its
shelf (`depth_fade` 24 m), swimming on the planet (`PlanetSwim extends WorldSwim`, which now has two
hooks `_water_level` / `_flow`; the planet answers with the sea, lake or river at the player's
spot and river currents from `PlanetHydrology.flow_at`; `-- --swim-check` expects `SWIM_CHECK PASS`),
and the underwater fog flag goes to the atmosphere.

Sixth pass (user saw coasts like walls): the cause was a step in `PlanetTectonics.height` where a
continental and an oceanic plate meet: the coastal range (land side) and the trench (sea side) were
two different formulas, so the height jumped by up to 170 m across the boundary. Now one smooth
profile of the signed distance to the boundary, and the plate-interior variety is blended across it
too. Also: the shore easing is an integral (never steeper than the plates; before it multiplied the
height and made the coast steeper than the plates), the ranges start further inland, the plate
base blends over a wider band, tile skirts are at most `relief * 0.15 + 4` m deep (they showed as
walls where a coarse tile misses the hills). Measured with 200,000 shore samples: the largest rise
within 100 m of the shore went from 139 m to 45 m (p99 14 m); an ordinary shore rises ~1 m in 100.

Seventh pass (loading): ground and water first, plants after. A tile is built without plants (4 ground
threads, `PlanetSurface._workers`); plants are a second job (`_queue_plants`, 3 planting threads,
nearest first) grown into a holder node and adopted by the tile on the main thread
(`_adopt_plants`); a tile taken out of the world is freed only when no planting job holds it
(`_retire`). The player is held still (process disabled, "Generating the planet... N %") until the
ground within 2 km is built (colliders included) and the plants within 60 m are in
(`PlanetWorld.loading`, `loaded` signal, `PlanetSurface.progress`); ~3 s for the ground, ~7 s in all
on this machine, the rest of the plants keep coming in around the player. Headless runs have no
threads (tiles and plants are made a few a frame) and no holding. `SpeciesRegistry.mesh` builds
outside its lock now (several threads build different meshes at once).

Eighth pass (a wall on land): the same kind of step as the coast walls, in the plate maths: with only
the two nearest plates counted, the boundary uplift jumped by up to 57 m along every line where the
second nearest plate changes (a triple junction line) near a boundary. `PlanetTectonics.height` now
lets the four nearest plates each have a smooth say (`SOFT`), and every pair of them adds its
boundary effect weighted by both plates' say, so nothing jumps. Land faces steeper than 1 in 10 m: 46
of 300,000 samples before, 3 now (the steepest rise in 10 m 57 m before, 19 m now, the rest are river
gorges). The screen is black with the loading text until the ground is made, then fades.

Ninth pass: the planet map on the M key (`PlanetMap`, an action `planet_map` added at runtime):
640x320 equirectangular, drawn from `PlanetNoise` by 3 background threads once the player is in
(a few seconds, "Charting the planet... N %" meanwhile): depth shading on the sea, biome colours and
hill shading on the land, lakes, rivers (`PlanetHydrology.river_lines`), a lat/long grid, the
player's arrow (which way the camera looks) and the position and altitude under the map. Lab:
`-- --show-map`.

Tenth pass (map): the map fills the screen and opens on the player's region (zoom 6, about 60 degrees
across, the arrow in the middle). Wheel zooms (to the point under the cursor, 1 = the whole planet
fitting the screen, up to 60x), dragging pans, R goes back to the player, M closes; the mouse is
freed while it is open. `PlanetChart` draws one picture of (a part of) the planet on 3 threads: a
coarse whole-planet chart (320x160), then a fine one (1024x512), and when the view has stayed still
on a close region for half a second, a chart of just that region (768 px wide, with a margin to pan
in), so close up it is sharp.

Eleventh pass (map layers, a debug tool): buttons under the map (and keys 1-7) switch the layer:
Terrain, Elevation (with contour lines), Temperature, Rain, Biome, Plates (boundaries in black),
Slope; each has a colour scale in the corner, and the line under the map gives the exact numbers
under the cursor (height, temperature, rain, biome, plate). A layer's finished charts are kept, so
switching back is instant. `PlanetChart.Layer` / `PlanetTectonics.plate_at`.
What the layers showed straight away: the rain layer has big dry gaps inland (the climate model
lets the air run dry after a few hundred km), and the biome layer is banded by latitude as it
should be; both are the next things to tune in `PlanetClimate`.

Twelfth pass (what the map layers showed): rain no longer runs out inland (`PlanetClimate`: a flat
cell drops 8% of the moisture in the air, half of it is given back by the plants, 0.996 loss a cell,
mountains wring out more), so the continents are green with deserts where they belong. Land share
by biome over four seeds: forest 39-60%, grass 26-43%, desert 2-9%, snow 2-16% (desert if wetness
< 0.2, forest if > 0.5). `find_spawn` now picks green country (mild, wet), with hills and the sea
within a few km, not the foot of a cliff, and not a dead flat plain. Rain tree pads are half the
size (they looked like flat green doors).

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

- Esc menu: a "Planet" page (`PlanetMenu`): time speed/jumps/sliders, weather override, new seed/radius, map. Lab: `--planet-page`.

- Saved universes (`UniverseSave`, Planet page: Save here / Open / Delete; lab `--world=`, `--continue`, `--save-as=`, `SAVE_CHECK`).
- Air: least scale 0.25 (`PlanetAir.MIN_AIR_SCALE`), clouds at 450-1150 m inside bright air; sunsets paler on small planets.

## The universe (for later; today there is one planet)

The player will be able to travel between planets, so what exists above a planet is a universe, not a
planet. Decisions so far: saves, the start menu and the Planet page already speak of universes
(`UniverseSave`: a list of planets, the current one, the moment on it; first-version saves still
read). Not done, in the order it would be done:

1. A universe seed; each planet's settings derived from it and a planet number (today the seed typed
   in the start menu is the first planet's own).
2. A star system: the star (colour, brightness, mass), planets on orbits around it (today the one
   planet has its own orbit, spin and tilt in `PlanetClock`, and `PlanetMoon` is its moon). The
   sun's direction and light would come from the planet's place on its orbit and from the star.
3. One planet is built at a time (`PlanetWorld`); the others are far points with a position, radius,
   orbit and a cover picture (so that from afar they are seen as the planet from orbit is today).
   Going to another planet means building it when the player is near and letting the old one go.
4. Flying between them: the scale (millions of km) needs the double precision build or a floating
   origin of its own, speed controls, and the cloud shell and the air shaders per planet.
5. The start menu and the Planet page get a list of the universe's planets to travel to.

Open: whether a universe is one star system or many, and how the player travels (a ship, or free
flight at a great speed as in the free mode today).
- Clouds: one raymarched layer drawn by the sky (from under) and by a sphere round the planet (from
  in and above it, to orbit), sharing `planet_cloud_march.gdshaderinc`; they show from above now.
- Fixed: the frame rate fell to 28 fps at 6 km because tile detail ignored altitude (see "Detail follows the
  distance in space" in the doc); now 463. On the ground: tree distance levels and merged far trees took a frame from 55 to 152 fps
  (see "Distance levels of the plants" in the doc).

## Follow-up tasks (planned 2026-10-17, none started)

Read `docs/planet_lessons.md` before any of them. **Focus (user, 2026-10-17): the planet and the star, not the
player; many star systems are wanted; the flat world may be retired once the universe exists.** Suggested
order and what depends on what:

| First | Task | Depends on |
|---|---|---|
| 1 | [044](044_planet_performance_round_2.md) performance round 2 | - |
| 1 | [046](046_performance_budget_and_checks.md) budget and one check script | - (helps all) |
| 1 | [054](054_universe_foundation.md) universe: many star systems, planets, the star as data | - |
| 2 | [064](064_stars_and_life.md) stars and what their light does to life | 054 |
| 2 | [047](047_sky_and_sunsets.md) sky and sunsets (the star's colour feeds it) | 064 |
| 2 | [058](058_climate_and_orbit_depth.md) climate and orbit depth (tidal locking, insolation) | 064 |
| 2 | [065](065_atmosphere_composition.md) atmosphere composition and pressure (sky, greenhouse, weather) | 054, 064; shares work with 047 and 058 |
| 2 | [061](061_other_planet_types.md) other planet types | 054, 064, 065 |
| 2 | [048](048_cloud_polish.md) cloud polish | 047 for the cost budget |
| 2 | [050](050_tree_look_fixes.md) tree look fixes | - |
| 3 | [049](049_water_and_coasts.md) water and coasts | 058 for tides |
| 3 | [068](068_weather_systems_and_storms.md) weather systems and storms (fronts, thunderstorm cells, cyclones) | 058, 065; shows through 048 |
| 3 | [067](067_volcanoes_and_crust_activity.md) volcanoes and crust activity | 057, 054 (activity from size and age), 065 for gases |
| 4 | [066](066_caves_and_underground.md) caves and the underground (starts with a spike) | 057, 067 for lava tubes, 049 for water |
| 3 | [057](057_terrain_realism.md) terrain realism | 049 |
| 3 | [059](059_plant_variety.md) plant variety (star light shapes plant colour) | 044, 050, 064 |
| 3 | [052](052_graphics_options_for_the_planet.md) graphics options | 044, 046 |
| 3 | [051](051_life_and_sound.md) life and sound | - |
| 3 | [062](062_earth_scale_and_double_precision.md) Earth scale and double precision | 044 |
| 4 | [045](045_landing_and_fast_descent.md) landing and fast descent | small, player-adjacent |
| 4 | [053](053_flat_world_parity.md) retire the flat world | 054 working, user confirms |
| 4 | [056](056_saves_v3_and_menus.md) saves v3 (universe part with 054; comfort items later) | 054 |
| 4 | [060](060_map_and_ui.md) map and UI (universe and star map first) | 054, 064 |
| parked | [055](055_space_travel.md) space travel | 054, 064, 062 |
| parked | [063](063_things_to_do_on_the_planet.md) things to do | player focus |

Decisions so far (user, 2026-10-17): many star systems wanted but **start with one star and one planet and
polish it**; start-menu parameters **home planet: sun-like habitable or any** and **star colours: physical or
readable** (both kept, decide after seeing them); flat world to be retired; player parked.

Time (user, 2026-10-17): keep **both** universe/standard (Earth-like) time and each planet's local time, as data,
without building a display for it yet (054). Open (also written in the tasks): how the player will travel and how
far apart things are (055, parked); gravity in the player controller (061).
