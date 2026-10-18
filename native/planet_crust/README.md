# Planet crust, in native code (optional)

`PlanetCrustNative` does the heavy maths of the crust (the plates, the ground height, the rock
colour) in C++. It is an accelerator: the GDScript (`PlanetTectonics`, `PlanetNoise`, `PlanetRock`)
stays the reference and is used when this library is not built or loaded. The numbers come from
GDScript in `setup`, so nothing is copied twice. `PLANET_NO_NATIVE=1` turns it off, and
`planet_lab --native-check` compares the two.

`src/FastNoiseLite.h` is the same file Godot uses (MIT, Auburn/FastNoiseLite).

## Build: one command

```
scripts/setup_native.sh      # once on a machine (Git Bash on Windows, Terminal on a Mac)
```

It fetches godot-cpp and scons into `~/.cache/godot-native` (outside the project), builds the debug
library for this machine, and adds a line to this clone's post-merge and post-checkout git hooks (the
Git LFS ones stay) so that a pull or a checkout builds it again by itself, in the background, when the
C++ changes (`native/planet_crust/build.log` says how it went). `scripts/build_native.sh` does the
build alone and does nothing when the library is up to date (`--force`, `--release`, `--double`).
It needs git, python3 and a C++ compiler: Xcode's command line tools (`xcode-select --install`) on a
Mac, MinGW (`/c/ProgramData/mingw64/mingw64/bin`) on Windows. The first build takes about 15 minutes
(godot-cpp), the next ones seconds. On a Mac it builds a universal library (Intel and Apple).

A library must match the engine's precision, or Godot refuses to load it (or crashes): the standard
editor loads the single library; the double precision build (`E:\Godot\double`) needs the double one:

```
git clone --depth 1 https://github.com/godotengine/godot-cpp E:/Godot/cpp/godot-cpp-double
E:/Godot/double/src/bin/godot.windows.editor.double.x86_64.console.exe --headless --dump-extension-api
# (writes extension_api.json here: keep it as E:/Godot/cpp/dump/extension_api.json)
GODOT_CPP_DOUBLE=E:/Godot/cpp/godot-cpp-double GODOT_API_DOUBLE=E:/Godot/cpp/dump/extension_api.json     scripts/build_native.sh --double
```

(godot-cpp 4.5 with the default API crashed the double engine, and its generator cannot read the 4.7
API dump; master reads it.) The libraries go to `bin/` (not committed).

## What it does (measured, Earth preset, standard build)

- `heights` / `colours`: a ground point 1.8 us instead of 8.9 us, a colour 0.75 us instead of 3.6 us
  (the sea floor is fastest: the layers that are 0 over the sea are not asked for there).
- `tile_dirs`, `local_positions`, `grid_normals`, `ground_colours`, `triangles`: a whole tile's
  grid, normals, colours and triangles (with the collider faces) in a few calls.
- A full-detail tile: 48 ms (GDScript) -> 9.5 ms. The pictures differ by 0.05 of 255 on average.
- Not covered (GDScript is used): a planet with rivers on (the hydrology cuts the ground in
  GDScript), the sea, the water, the plants.

## macOS

The `.gdextension` has the macOS entries and `scripts/setup_native.sh` builds the universal library,
but it has not been run on a Mac yet. Without the library the game runs on the GDScript (about 5
times slower, and without the river valleys) and says so once in the output.
