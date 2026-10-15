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
| `flora_meshes.gd` | pine, oak, birch, dead tree, bush, rock, grass, flower, cactus, reed, stump (variants) |
| `world_scatter.gd` | jittered-grid placement by biome/slope, MultiMesh per kind, colliders for trunks and rocks |
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
