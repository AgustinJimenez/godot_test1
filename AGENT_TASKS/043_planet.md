# 043 Planet (round world prototype)

Goal: a walkable round planet, built next to the flat world (nothing in `systems/world_gen` changed
except that `TerrainChunk.ground_material`, `MeshBuilder` and `TerrainColors` are reused).
Lab: `tests/manual/planet/planet_lab.tscn` (`-- --radius=N --seed=N`); check:
`-- --planet-check` (headless, expect `PLANET_CHECK PASS`).

## Design

- `PlanetNoise`: 3D noise sampled on the sphere (height, moisture, heat by latitude, biome, colour).
  No rivers or lakes yet.
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

## Limits (measured with `-- --planet-check --radius=N`, 2.4 km walked in 60 m steps)

| radius | max level | result |
|---|---|---|
| 20 km (default) | 8 | PASS, worst gap to the true ground 0.8 m |
| 200 km | 12 | PASS |
| 1,000 km | 14 | PASS (0.7 m) |
| 6,371 km (Earth) | 17 | FAIL: the tile directions and the noise inputs are float32, 0.5 m steps |

Up to ~1,000 km the single precision build is fine (vertex positions are done in doubles around each
tile's middle; only the unit directions and the noise inputs are float32, 6-12 cm at 1,000 km).
Earth size needs the directions and the noise sampled in doubles (own noise, or a double precision
engine build). The horizon of a 20 km planet at eye height is ~260 m.

## Not done

Plants and rocks, water shader tuned for tiles (it uses the flat world's water shader on bent
patches), rivers and lakes, fauna, weather, planet rotation / day-night from the planet, other
planets, space.
