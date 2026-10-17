# Planet crust, in native code (optional)

`PlanetCrustNative` does the heavy maths of the crust (the plates, the ground height, the rock
colour) in C++. It is an accelerator: the GDScript (`PlanetTectonics`, `PlanetNoise`, `PlanetRock`)
stays the reference and is used when this library is not built or loaded. The numbers come from
GDScript in `setup`, so nothing is copied twice. `PLANET_NO_NATIVE=1` turns it off, and
`planet_lab --native-check` compares the two.

`src/FastNoiseLite.h` is the same file Godot uses (MIT, Auburn/FastNoiseLite).

## Build (Windows, MinGW, outside the repo: `E:\Godot\cpp`)

```
git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp E:/Godot/cpp/godot-cpp
python -m venv E:/Godot/cpp/venv && E:/Godot/cpp/venv/Scripts/pip install scons
```

Then `native/planet_crust/build.sh` builds the single precision (standard editor) and the double
precision (E:\Godot\double) libraries into `bin/` (not committed). A library must match the engine's
precision, or Godot refuses to load it.

## What it does (measured, Earth preset, standard build)

- `heights` / `colours`: a ground point 1.8 us instead of 8.9 us, a colour 0.75 us instead of 3.6 us
  (the sea floor is fastest: the layers that are 0 over the sea are not asked for there).
- `tile_dirs`, `local_positions`, `grid_normals`, `ground_colours`, `triangles`: a whole tile's
  grid, normals, colours and triangles (with the collider faces) in a few calls.
- A full-detail tile: 48 ms (GDScript) -> 9.5 ms. The pictures differ by 0.05 of 255 on average.
- Not covered (GDScript is used): a planet with rivers on (the hydrology cuts the ground in
  GDScript), the sea, the water, the plants.
