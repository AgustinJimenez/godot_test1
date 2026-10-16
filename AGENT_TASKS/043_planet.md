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

Plants and rocks, water shader tuned for tiles (it uses the flat world's water shader on bent
patches), rivers and lakes, fauna, weather, planet rotation / day-night from the planet, other
planets, space.
