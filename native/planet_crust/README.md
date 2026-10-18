# Planet crust, in native code (optional)

`PlanetCrustNative` does the heavy maths of the crust (the plates, the ground height, the rock
colour) in C++. It is an accelerator: the GDScript (`PlanetTectonics`, `PlanetNoise`, `PlanetRock`)
stays the reference and is used when this library is not built or loaded. The numbers come from
GDScript in `setup`, so nothing is copied twice. `PLANET_NO_NATIVE=1` turns it off, and
`planet_lab --native-check` compares the two.

`src/FastNoiseLite.h` is the same file Godot uses (MIT, Auburn/FastNoiseLite).

## Build (Windows, MinGW, outside the repo: `E:\Godot\cpp`)

A library must match the engine's precision, or Godot refuses to load it (or crashes).

```
python -m venv E:/Godot/cpp/venv && E:/Godot/cpp/venv/Scripts/pip install scons

# standard (single precision) editor: godot-cpp 4.5 is enough
git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp E:/Godot/cpp/godot-cpp
scons platform=windows use_mingw=yes arch=x86_64 target=template_debug precision=single

# the double precision build (E:\Godot\double): godot-cpp master and the engine's own API dump
git clone --depth 1 https://github.com/godotengine/godot-cpp E:/Godot/cpp/godot-cpp-double
E:/Godot/double/src/bin/godot.windows.editor.double.x86_64.console.exe --headless --dump-extension-api
# (writes extension_api.json in the current folder: keep it as E:/Godot/cpp/dump/extension_api.json)
GODOT_CPP=E:/Godot/cpp/godot-cpp-double scons platform=windows use_mingw=yes arch=x86_64     target=template_debug precision=double custom_api_file=E:/Godot/cpp/dump/extension_api.json
```

(Run `scons` in this folder. godot-cpp itself takes about 15 minutes the first time, the library a few
seconds. godot-cpp 4.5 with the default API crashed the double engine, and its generator cannot read
the 4.7 API dump; master reads it.) The libraries go to `bin/` (not committed).

## What it does (measured, Earth preset, standard build)

- `heights` / `colours`: a ground point 1.8 us instead of 8.9 us, a colour 0.75 us instead of 3.6 us
  (the sea floor is fastest: the layers that are 0 over the sea are not asked for there).
- `tile_dirs`, `local_positions`, `grid_normals`, `ground_colours`, `triangles`: a whole tile's
  grid, normals, colours and triangles (with the collider faces) in a few calls.
- A full-detail tile: 48 ms (GDScript) -> 9.5 ms. The pictures differ by 0.05 of 255 on average.
- Not covered (GDScript is used): a planet with rivers on (the hydrology cuts the ground in
  GDScript), the sea, the water, the plants.

## macOS (not built or tried yet)

The libraries in `bin/` are Windows ones; on a Mac the game runs on the GDScript (about 5 times
slower, and without the river valleys) until the library is built there. The `.gdextension` has the
macOS entries. Build on the Mac with Xcode's command line tools, godot-cpp 4.5 and scons:

```
git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp ~/godot-cpp
python3 -m venv ~/scons-venv && ~/scons-venv/bin/pip install scons
GODOT_CPP=~/godot-cpp ~/scons-venv/bin/scons platform=macos arch=universal target=template_debug
```
