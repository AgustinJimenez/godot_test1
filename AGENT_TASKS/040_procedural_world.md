# 040 - Procedural low-poly world (Godot only, no imported art)

Built autonomously while the user was away (2026-10-15). Everything is code: terrain, plants, rocks,
water, sky, weather, wind. Open `levels/procedural_world.tscn` and walk (keys on screen), or the lab
`tests/manual/world/world_lab.tscn` (`-- --world-check` headless, `-- --world-shots [--weather=storm]
[--hour=20]` with a window writes /tmp/world_*.png). Uncommitted.

## Pieces (`systems/world_gen/`)
| File | Job |
|---|---|
| `world_settings.gd` | seed, tile size, view radius, density knobs |
| `terrain_noise.gd` | height / moisture / heat / biome as pure functions of (x, z, seed) |
| `terrain_chunk.gd`, `terrain_colors.gd` | one flat-shaded low-poly tile + HeightMap collider, facet colours by biome and slope |
| `mesh_builder.gd` | flat-shaded triangle soup builder with vertex colour (frustums, lumpy blobs) |
| `flora_meshes.gd` | rocks, stumps, logs, rock spires (variants); the plants moved to species, see [041](041_procedural_flora_species.md) (`flora/`) |
| `world_scatter.gd` | jittered-grid placement: plants by species fit ([041](041_procedural_flora_species.md)), rocks and logs by biome/slope; MultiMesh per species and variant, colliders for trunks and rocks |
| `world_water.gd` + `shaders/world/water_lowpoly.gdshader` | faceted sea, depth colour, foam at the shore |
| `world_atmosphere.gd` | sun, sky, fog, day cycle; overcast + lightning inputs |
| `world_weather.gd`, `rain_effect.gd`, `world_clouds.gd`, `world_wind.gd` | clear / cloudy / rain / storm / fog / snow, wind (shader globals in project.godot), wet ground |
| `world_generator.gd`, `procedural_world.gd` | streaming tiles around the player; the whole world as one node |

## Loop log (what each pass added and what is next)
1. Terrain + biomes + water + scatter + sky + weather + wind. Looks like a coherent island.
2. (see below, appended as the loop goes)

## Loop 2 additions
9. Autumn colours (F6 in the level, `autumn` on `ProceduralWorld`; shader global `autumn` turns every
   green gold, orange and brown with a smooth patchwork). Deer and rabbits (`WorldFauna`): idle, walk,
   flee (deer at 25 m, rabbits at 11 m), keep out of water, hidden at deep night. Cabin interiors
   (bed, table, stool, a lit hearth `Campfire`). Mountain lakes (`TerrainNoise.lake_in`: a bowl
   carved into the land with a rim, a round water surface at its own level, swimmable and animals
   and trees keep out of it). Lab flags: `--lakes`, `--fauna`, `--autumn`.
- Lake basins are a bit crater-like on the uphill side (a cut wall); softer transitions would look
  better. World build is ~1.1 s for 325 tiles in the headless check (lake planning in `_init`).

## Loop 3: Terragen-style direction (user asked for erosion + rivers + a realistic style)
10. Eroded terrain (`ErodedNoise`: fractal value noise whose octaves are damped by the slope so far:
    gullies, spurs, clean steep faces; no simulation, so any tile builds alone). Scatter reads the
    tile's own height grid (bilinear), which made the world build faster than before.
11. Rivers (`WorldRivers`): sources in high ground are followed downhill (steepest descent with
    wander, 1.8 km max), water surface never rises, widens downstream, channel and banks carved
    into the land, water strips with a flow shader (`river_lowpoly.gdshader`), a current that
    pushes swimmers, riverbanks classified as beach. `--rivers` lists some; `RIVER_CHECK`.
12. Realistic style (F9 in the level, `ProceduralWorld.realism` 0..1, shader global `realism`; every
    world shader blends its two looks). Same geometry for both: the terrain mesh carries a flat
    facet colour and smooth normals + smooth per-vertex colours (CUSTOM0); the ground shader uses
    derivative normals for low-poly, and for realistic: smooth normals, soil / grass / rock patches,
    strata on steep faces, fine grain and a bump from noise. Plants: smooth normals (averaged per
    point within ~60 degrees, so a box edge stays sharp), leaf-scale colour variation, light through
    the leaves, finer meshes (320-facet blobs with smooth bulges, rounder trunks) that swap in past
    realism 0.5 (a batch of nodes per frame). Sky: single-scattering atmosphere (blue day, red
    sunset, pale haze at the horizon) and layered noise clouds that follow the weather; the
    low-poly cloud meshes hide. Water and rivers: smooth waves + non-repeating ripples and sky
    reflection. Atmosphere: ACES, volumetric fog and light shafts, 4-split shadows, aerial
    perspective. Lab: `--realistic`.
- Not done for the realistic style: grass is still crossed triangles, trees keep their stylised
  silhouettes (only smoother), no real leaf cards, no rock textures beyond the procedural ones.
13. Waterfalls and rapids: a river segment that drops steeply gets a faster, foamier current (the
    water strip's vertex colour carries the fall) and a `WaterfallMist` spray cloud at its foot
    (drops over 2.2 m per segment). `--rivers` lists some (`WATERFALL --at=x,z`).
14. Realistic grass and leaves: finer tufts (9 curved, tapering blades in two segments) and leaf
    cards over oak and birch canopies (`MeshBuilder.add_leaf_cards`), only in the detailed meshes.
- Next ideas: wading / swimming splashes and ripples, footprints in snow and mud, fog that pools in
  river valleys, real bark and rock textures (procedural) for the realistic style, season blending
  (spring flowers, winter bare trees), seeds that read from the title screen.
15. Water play: `WaterSplash` (a burst of droplets and a spreading ring when you step or jump in,
    rings while wading, a wake while swimming) and a splash sound in `WorldAmbience`.
16. Footprints (`WorldFootprints`): in fresh snow, on beach and marsh ground, and on any wet
    ground in rain, each step leaves a print (a pooled `Decal`, left and right in turn, 70 s, then
    fade). Lab: `--prints-view` (walks through snow, then looks at the trail), `--splash-view`
    (with `--swim`).
17. Realistic bark / wood / stone: in the plant shader, bark gets furrows and ridges, cabins get
    boards (the `planks` parameter, `FloraMeshes.structure_material()`), stone gets grain, veins
    and lichen patches. Detected from the vertex colour (brown or grey, not swaying).
- The shoe-print texture is a plain sole + heel; a proper tread would read better.

## Water and swimming fixes (2026-10-15, after the user's live look)
- Swim speed was `velocity *= 0.6` every frame, which compounds against the player's per-frame
  acceleration (steady state about 0.3 m/s, a tenth of walking). Now a cap: `walk_speed * SWIM_SPEED`
  (0.6) in `world_swim.gd`. Wading (`WADE_SPEED` 0.75) has the same compounding bug and was left as is
  (the user only asked about swimming); fix it the same way if it feels slow.
- River current pushed at 80 percent of the flow (up to 1.5 m/s, almost the new swim cap), so swimming
  upstream stalled. `CURRENT_PUSH` is now 0.4.
- Lakes are 24-44 m discs and rolled like the open sea. `WorldWater.lake_surface` now writes a calm
  factor into the vertex colour red (`POND_ROLL` 0.2 for the smallest .. `BIG_LAKE_ROLL` 0.55), and
  `water_lowpoly.gdshader` scales wave height and ripples by it (`roll`).
- Natural basins below sea level are not lakes, they are sea water, so they still rolled like the
  ocean. `WaterCalmMap` (`water_calm_map.gd`) is a 96 x 96 texel map (10 m texels, rebuilt on a worker
  thread when the player is 120 m off its middle) of how much deep water lies around a spot: wide deep
  sea 1.0, a basin pond or shallow bay down to 0.2. The sea shader samples it (`roll_map`, `roll_area`).
  `ProceduralWorld.rebuild()` re-points it at the new seed's terrain. Lab: `-- --world-check` prints
  `CALM_CHECK` (water texels split between lively and calm).
- Two water layers on the coast: the far sea plane lies 0.4 m under the near one and showed through the
  see-through shallows as a second foam line and second waves. The far plane is now a ring with a
  square hole (`FAR_HOLE` 400 m) inside the near plane's 450 m.
- Two ponds "merged": generated lakes sit at least 160 m apart and cannot touch, so this was most
  likely two sea-level basins joined by a shallow neck (sea water, now calm). Not reproduced; if it shows
  again, note the seed and place (the lab's `--lakes` and `--biomes` print `--at=x,z` spots).

## Foot IK "does not work well on the terrain" (2026-10-15): the ground you see was not the ground you stand on
- Cause found with numbers, not in IK: `TerrainChunk` split every cell along its own diagonal ("the
  steeper pair, so ridges stay crisp") but `HeightMapShape3D` (Jolt) always splits along p10-p01. In
  about half the cells (the ones where the mesh picked p00-p11) the visible ground differed from the
  collider by 7-19 cm on average (p95 17-44 cm, worst 1-2 m on terrace edges) at 2 m cells. The capsule
  and Foot IK stand on the collider, so feet floated or sank against the visible mesh.
- Fix: the mesh always splits p10-p01 (`terrain_chunk.gd`), and `WorldScatter._grid_height` interpolates
  on the same two triangles so plants stand on the visible ground. Cost: ridges are no longer picked out
  by the diagonal choice. Guard: `tests/manual/world/world_surface_check.tscn` (visible mesh vs
  collider at cell centres over four spots, limit 1 cm; after the fix it is 0.00 cm mean, 0.01 worst).
- `tests/manual/world/world_ik_check.tscn` (`-- --v2`, `--off`, `--walk`, `--seed=N`) grades the ankles
  against the real collision ground on spots of growing steepness. Idle: v1 and v2 are both within
  3.2 cm on every slope tried (IK off: 11-15 cm float on the steepest). Walking numbers include the
  natural swing of the leg (a foot far above ground that drops away), so they are not an IK grade yet.
  v1 and v2 gave identical ankle numbers in this metric (v2 differs in sole tilt, knees, pelvis and
  stepping, which it does not measure). The game still runs v1; v2 is opt-in (`FootIKV2Install`,
  only the labs call it). Next, if the user still sees bad IK after this fix: try v2 in the procedural
  world, and add sole tilt / toe clip to the terrain check.

## Blocky clouds in the realistic sky (2026-10-15)

Looking up in the realistic look, the cloud layer broke into hard-edged squares of different
brightness. Cause: `world_sky.gdshader` built its noise from `fract(sin(dot(p, ...)) * 43758.5453)`,
which loses precision on the GPU and turns the value noise into blocks. `hash2` now uses a sine-free
hash (Hoskins style); the clouds are soft again (checked with a camera pitched up at noon, cloudy).
Do not use `sin()`-based hashes in shaders here.

## Sky3D as an optional sky (2026-10-15, uncommitted, waiting for the user's look)

Added the Sky3D add-on (TokisanGames/Sky3D v2.1, MIT, commit 6e151bc of 2026-05-19, source read
first: no network or file access) as `addons/sky_3d/` (demo folder left out; `.gdlintrc` excludes it).
The plugin is NOT enabled in project.godot (not needed, the classes load by `class_name`).

`WorldAtmosphere.use_sky3d(on)` switches the sky: World menu page, "Sky" row (Built-in / Sky3D).
Built-in stays the default. In Sky3D mode: our WorldEnvironment is taken out and Sky3D's own is used
(fog, SSAO, glow are set on it again); our sun and moon are hidden and Sky3D's lights run;
`time_of_day` drives Sky3D's clock (its own clock is off); weather maps to cumulus/cirrus coverage,
cloud intensity and sun energy; `sun_height()` reads Sky3D's sun so night/day numbers (ambience,
fireflies, weather) agree with what is on screen. Both realism looks work with either sky.

Findings: Sky3D's sky shader makes the volumetric-fog pass fail every frame ("Parameter uniform_set
is null", draw_list_bind_uniform_set) so volumetric fog is off while Sky3D is on (found by trying
realism 0 vs 1). Sky3D nights are very dark (matches a review): ambient and moon are lifted by
`_night_amount` in `_apply_sky3d()`. Noon clouds look much better than the built-in sky; dusk is a
deep red and fairly dark; not tuned further. Sky3D's lat/long (16, 108) set when sunrise/sunset
happen, so the clock hours differ a little from the built-in sky.

## Sky3D is the default in the procedural world; steep slopes stop the walk (2026-10-15)

The user found squares/lines left in the built-in sky and none in Sky3D, so `levels/procedural_world.gd`
now starts on Sky3D (World page: Sky -> Built-in switches back). The built-in sky's remaining
squares/lines were NOT chased (suspects: the grid-aligned value noise of its cloud layer, the
star cells at night).

Steep slopes: past `floor_max_angle` (45) the terrain is not floor, the body plays the falling
animation, and `move_and_slide()` slides the remaining horizontal velocity ALONG the slope, which
carried the body uphill (measured: 0.13 m and 0.61 m climbed on frames off the floor).
`actors/player/player_steep_slope.gd` (`PlayerSteepSlope.block_uphill`, called from
`player.gd` right before the stair controller) removes the into-the-slope part of the horizontal
velocity when the next 15 cm hit a surface steeper than floor_max_angle (walls, normal.y < 0.15,
are left to the normal slide). Sideways along the slope still works. New check:
`tests/manual/world/world_steep_check.tscn` (walks uphill into slopes from 10 to 80 deg, fails if the
body gains height while off the floor): FAIL before (2 slopes), PASS after.
NOTE `player.gd` is at exactly 1000 lines (the lint limit); new player logic goes in its own file.

### Sky3D tuning (same day, later)

Sky3D's defaults put the sun on January at 16 N, longitude 108, UTC+7: sunset at about 17:30 on our
clock. `_enter_sky3d()` now sets the equinox (March 21), latitude 30, longitude 0 and `utc = 0`, so
the sun rises at 6, peaks at 12 and sets at 18 like the built-in sky (measured with a sun_height
sweep). Night: ambient `1 + night * 2.6`, moon energy 1.0; checked at 18:30 (dusk, orange clouds) and
21:00 / 23:30 (stars, readable ground) with clear weather. Under cloud the night is much darker.

## Realistic water (2026-10-15)

`shaders/world/water_lowpoly.gdshader` (sea and lakes; the river shader was not touched). Everything
new is scaled by the global `realism`, so the low-poly look is unchanged (checked side by side).
- Refraction: the screen texture seen through the water, bent by the wave normal (`refraction_strength`
  0.05, limited to the first metre of depth, and not dragged across things standing in front of the
  water), tinted by per-colour absorption (`absorption` 0.42/0.11/0.06 per metre: red goes first, so
  deeper water turns blue-green). The bed arrives as EMISSION (it is already lit), the water body
  colour is the lit albedo.
- Shore foam: the edge breathes with a swell and is torn by moving noise instead of a straight band.
- Crest foam: streaks on the wave crests of open water (scaled by roll, so calm bays have none).
- Fresnel: grazing angles let less of the bed through.
- The shader's `sin()` hash (same cause as the blocky sky clouds) is now a sine-free hash.
Costs: the screen texture copy happens for the water in both looks. Not measured in a window yet.
Looked at with shore probes (low-poly, realistic, two shores, looking down): turquoise shallows with the
sand visible, deep blue further out, soft foam line. Not done: rivers, SSR reflections of the shore,
underwater look.

## Could not move in deep water (2026-10-15)

The user went into the water and could not move. Cause: `player.gd` only applies the walk input
when on the floor (or within 0.15 s of leaving it); a swimmer floats with no floor, so from a
standstill in deep water nothing ever accelerated it, and a swimmer that let go of the keys kept
drifting at full speed (no braking, no steering; it only worked by carrying the momentum of the
wade-in). `WorldSwim.update()` now steers the floating body itself: it moves the horizontal velocity
toward the input (`player.debug_movement_input`, in the head's yaw) at the player's acceleration,
capped at walk_speed * SWIM_SPEED. New check `tests/manual/world/world_water_walk_check.tscn`
(`-- --seed=N`): walks from a beach into the sea, lets go of the keys (must stop), swims off again,
then starts from a standstill in deep water. It FAILED before (moved 0.00 m from a standstill),
PASS after (drift 0.17 m, 5.6 m in 3 s). gdlint does not catch a duplicate local name: also run the
headless import after editing a gameplay script.

## Foot IK suite on Godot 4.7.2 vs 4.6.2 (2026-10-15)

Ran `scripts/check_foot_ik_all.sh` on the current tree with 4.7.2 and on the commit before this work
(3ba8839, in a throwaway worktree) with 4.6.2. Needs on Windows: a `godot` wrapper on PATH (the
scripts call `godot`), `python3` and `jq`. Results (36 pass, 6 known baseline failures in both):
- 12 of the 14 "NEW" failures are identical on both engines with identical numbers (e.g.
  locomotion 10.106/13.363 deg): they pre-date the upgrade and this work (the known-failures list in
  the script dates from 2026-09-07). Included: "Foot IK project checks" (compile error: autoload
  `PlayerProfile` not found when a script is checked alone, also what stops `scripts/check.sh` at its
  GDScript parse step on 4.6.2 and 4.7.2 alike) and a test calling `_update_idle_lower_transition`
  with the wrong number of arguments.
- "Foot IK stair lab capture check" fails on 4.6.2 (Condition "!is_inside_tree()" in
  foot_ik_stair_lab._spawn_player) and passes on 4.7.2.
- "Foot IK partial upper-foot support check" PASSES on 4.6.2 and FAILS on 4.7.2, deterministic, same on
  the old commit with 4.7.2, so it is the engine upgrade: `FOOT_IK_KNEE_FLEX_CHECK FAIL right target
  has no complete upper support patch` (right_flex 30.28 vs 30.86 on 4.6.2).
  INVESTIGATED AND FIXED IN THE TEST (same day). Cause: in the spawn frame the landing planner's
  `predict()` commits a landing on 4.7.2 (decision "commit coverage=15/18", committed_surface_y 0.6)
  but finds nothing to commit on 4.6.2 (decision "none": which of the player's physics step and the
  Foot IK's skeleton update runs first in that frame, and so whether the feet's landing probes exist
  yet, differs between the engines). A landing commitment makes the sampler skip the idle upper-foot
  repositioning (`landing_committed_target.has(side)` in `straighten_compressed_upper_target`), so the
  right foot stayed at z=4.0786, 8 cm closer to the tread edge, with no ground 10 cm behind it; on
  4.6.2 it was moved back to z=3.9986. The check is about an idle stand, so
  `foot_ik_knee_flex_check.gd` now drops the planner's commitment after the spawn frame
  (`require_lowest_support` only): PASS on 4.7.2 and on 4.6.2. Not changed: the runtime. Open
  question, not tested: a real jump-landing that ends with a foot half over a tread edge keeps its
  committed target (the repositioning is skipped while a commitment is held) on both engines.
- v2 suite (`check_foot_ik_v2.sh`): "turn in place on the stairs, dz=0" fails once (idle check
  tip_clip_max 0.049 > 0.020) and passes on its repeats; the jq steps could not find
  `foot_ik_v2_check.jsonl` (the scripts look under ~/Library/Application Support, macOS paths).
