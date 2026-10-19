# What we learned building the planet

Notes from the planet, plants, sky and performance work (October 2026), kept so the next person
does not pay for them again. The reference for how things work is `planet_generation.md`; this file
is the why, the measurements, the traps and the way to measure. Each section ends with what to do.

## 1. Measure first, in this order

The biggest wins came from measuring, not from guessing. Every performance claim below was measured
with the lab (`tests/manual/planet/planet_lab.tscn`), not assumed.

- `-- --fps` prints, every 300 frames: fps (vsync and `max_fps` are switched off for it), draw calls,
  primitives, tile count and the triangles by kind of node. Draw calls and primitives are the main
  pass only; shadow passes are not in them (test shadows with `--no-shadow`).
- `-- --hide=trees|plants|ground|water|grass|full|light|far` switches one kind off. The difference in
  fps is what that kind costs. This found, in two runs, that trees were most of the frame and that most
  of that was draw calls, not triangles.
- `-- --climb=N` lifts the real player N metres (looking down). The camera-only `--view-alt` mode is
  **not** a faithful test of detail by distance (see 3).
- `-- --fly-check` and `--walk-check` print `HITCH worst_frame=... frames over 33 ms`: the cost of
  streaming (worker threads, adoption on the main thread, mesh uploads). A change can raise the fps and
  still make the game stutter; check both.
- A GPU that is faster than the player's hides problems: 150 fps here can be 40 elsewhere. Compare
  relative numbers, and judge by draw calls and primitives too.
- Do not read a result before the run has finished: tile and plant streaming need about 900 frames
  after the loading screen; look at the last lines.

Do: change one thing, measure with the same arguments, keep the numbers in the doc.

## 2. Where a frame went (ground, then altitude)

- **Altitude.** Tile size, plants and colliders were chosen by distance along the ground, ignoring
  height, so a player 6 km up still had the finest tiles and every tree below drawn: 147 M primitives and
  28 fps. Using the distance in space (height over the ground there, not over the sea) gave 463 fps.
  `PlanetSurface._distance`.
- **Trees.** The trees of a forest are 8 to 10 thousand triangles each; the light version (`lod` 1) was
  built and never used. Levels now: full to 100 m, light to 220 m, the far tree (a cone or a ball)
  beyond. Hide trees: 74 to 219 fps.
- **Draw calls beat triangles.** 120 species x 6 looks make many small multimeshes per tile; the far
  trees alone were 3,000 of 4,900 calls. Merging all the far trees of a tile into one `ArrayMesh`
  (tint in the vertex colours, sway weight kept in the alpha) removed them. Merging is only possible
  for things that do not need their own instance transform at run time.
- **Shrubs and cover** beyond ~220 m and grass beyond ~110 m are invisible at a glance; a
  `visibility_range_end` on the multimesh removes them from the draw for free (it is measured from the
  node, so a tile switches as a whole; tiles are 128 to 256 m wide).
- **Shadows** cost ~1 ms here (146 to 171 fps without). Trees past ~100 m do not cast any.
- **Result**: ground 55 to 152 fps, 4,900 to 1,633 draw calls, 39.6 M to 8.9 M primitives. The clouds
  are almost free (0.4 to 0.9 ms at 1080p, 0.5 ms measured in the worst case).
- **Left**: ~3.8 ms of a 6.8 ms frame is still trees (full ~1.3 ms, light ~1 ms); ground tiles are cheap.

Do: draw calls first (merge, cull by range), triangles second, and measure each cut.

## 3. Streaming: hitches come from uploads

- A mesh made on a worker thread is uploaded on the main thread on first use. 120 species x 6 variants
  x (full, light, far) is hundreds of uploads; flying into new biomes did them constantly. Sharing the
  light mesh between two variants per species took the 24 km fly check from 195 slow frames to 17.
- `add_child` of a tile's plants on the main thread costs per node; two plants adopted per frame is the
  budget. More nodes per tile (the light and far copies) is more spike per adoption.
- `is_instance_valid` before assigning a node that a thread held to a typed variable: a tile can be
  freed while its plants are being grown ("Trying to assign invalid previously freed instance").
- The camera-only lab view (`--view-alt`) never refreshed the tile detail; use the real player.

- **A warm-up did not help (tried, removed).** A thread that built the light and far meshes of every tree
  species ahead of time, 60 ms apart, after the loading screen: slow frames on the fly check were 16,
  16, 19 with it and 11, 38, 4 without. The run-to-run spread (4 to 38) is wider than any effect, and it
  costs CPU and memory, so it was not kept. If the stutter comes back, find the first-use cost with a
  count of meshes created per second before adding machinery.
- **The hitch test is noisy: run it three times** and compare the middle values, not one run.

Do: new per-species resources need a budget of how many exist (share between variants); measure with
repeated runs.

## 4. Clouds

- One layer of real volume (700 m, 450 m above the ground), raymarched, shared by two shaders through
  `shaders/world/planet_cloud_march.gdshaderinc`: the **sky shader** only draws where the sky shows, so it
  cannot show clouds from above (terrain fills the view). A **sphere round the planet** with a spatial
  shader marches the same layer from inside it and from above (to orbit), reading the depth texture to
  stop at the ground. Cross-fade between 450 and 700 m above the ground.
- Where there is cloud is the planet's own cover picture (a texture made on a thread from the weather
  model), so the ground, the map and the orbit agree. The noise only shapes it.
- Sky shaders have **no `return`** in `sky()`, no `SKY_COORDS`, no `FRAGCOORD`; use `EYEDIR` for a
  jitter. `AT_QUARTER_RES_PASS` and `QUARTER_RES_COLOR` did not work for us (the pass was not run or
  its output was the full sky): do not rebuild on it without a minimal test.
- **Fog is applied to spatial materials even when they are transparent**, which painted a light band
  across the horizon: `fog_disabled` on the cloud shell.
- Clouds from above looked dim until the haze was made to depend on the air along the way (thin up
  high): `exp(-distance / 9000 * air_there)`.
- Hard edges from a capped march length are visible; fade the density out toward the end of the way.
- Lighting a cloud needs the sun's height over **that cloud**, not over the camera (orbit view, the
  terminator): a Kasten-Young air mass gives white, orange and none.
- Cost levers that worked: skip the march where the cover is ~0 along the way; fewer steps for short
  ways; cheaper noise for the light samples. The shell and the sky share the code so one tweak is both.

## 5. The atmosphere and its levels

- The air shrinks with the planet so that a 20 km planet has an Earth's optical depths. With the whole
  air 314 m deep, the sky was black at cloud level, which is where players noticed it. Least scale 0.25
  (`PlanetAir.MIN_AIR_SCALE`): scale height 2 km, top at 25 km. Bright blue at the clouds, deep blue at
  3 km, dark navy at 8 km, black above 25 km.
- The price is physical and cannot be had back: a small planet has a short sun path at sunset, so
  sunsets are pale and hazy rather than red, and twilight lasts longer. Making the air deep and the
  optical depth big turns the sky white instead. Choose, do not fight it.
- Fog colour must be capped by the light the scene really has (the sun through the air), or sunsets wash
  out. The sun's colour is the air's transmittance, not a fixed colour.
- Stars fade by `exp(-luma * 14)`; at 6 the daytime sky still showed some.

## 6. Ground, weather and surfaces

- Wetness and snow are shader globals set from the weather (`WorldWind.set_surface`); rain needs its own
  global (`rain_fall`) because the ground stays wet after the rain stops while the ripples must stop.
- Puddles collect in low, flat patches (noise in the world position, flat normals); ripples are rings in
  1 m cells, one drop per cell at a time; snow settles unevenly (noise breaks the edge and thins on
  slopes).
- Anisotropic filtering 8x, soft shadow filter 3 and debanding are project settings and are cheap.
  Debanding matters most for a wide dark sky gradient.

## 7. Saves, the start menu and the universe

- A save is a list of planets (their settings; the land is rebuilt from the seed, so it is not stored),
  the current planet and the moment on it (place, heading in the planet's frame, clock, time speed, forced
  weather). `UniverseSave`; first-version saves still load. The player is put on the ground at the saved
  place (their height is not saved).
- Opening reloads the scene with static `PlanetMenu.pending` and `pending_state`; the start menu
  (`UniverseStartMenu`) shows with no arguments, so every scripted check passes arguments.
- A universe will have a seed, planets derived from it and a star system; the plan and the open
  questions are in `AGENT_TASKS/043_planet.md`. Do not add planet-only assumptions to the save format.

## 8. Godot and tooling traps met on the way

- Godot 4.7: `Transform3D * PackedVector3Array` transforms a whole array at once (used for merging).
- `OS.get_cmdline_user_args()` is what the lab reads; a scene started from the editor with no
  arguments now opens the start menu.
- GDScript line continuation with a backslash is mangled by Python and shell edits (it turns into tabs
  and a parse error): use `if`/`else` or two statements, and check the file after a scripted edit.
- A scripted `git checkout <old commit> -- .` plus `git stash` to compare versions is dangerous in a dirty
  tree; copy the one file out and back (`git show <commit>:path > file`), then restore it.
- `gdlint` limits: line length 100, 20 public methods per class (make helpers private), files 1000 lines.
- Screenshots of a run: `--shot-frame=N --shot=PATH`; for the menu `--start-menu --shot=PATH`. Stop the
  game after a verification run.
- A run with `--headless` cannot render: fps, shaders and screenshots need a window; the checks that
  only move the player (`--planet-check`, `--walk-check`, `--fly-check`) can run headless.
- Windows Git Bash: `sleep` is blocked; wait for a background run with a `tail -f /dev/null` loop with
  timeouts, and read the log.

## 9. How we decided (process)

- "Do not fake an effect that has a cause" (`AGENT_TASKS/043`): the sun, seasons, weather, the air and
  the clouds follow from the orbit, spin, tilt, moisture and lift. It cost more at first and made every
  later feature (time controls, orbit view, saves) work without special cases.
- Looking at a real game's settings for inspiration is fine; copying its code or assets is not. Rendering
  settings (filtering, shadow quality, debanding) are public knowledge; shader source and art are theirs.
- Ask what the player sees before fixing what the profiler shows: the fps drop near clouds and the
  darkness with height were both real and had different causes (cost of the march, the air's depth).
- Keep every lab tool you wrote for an investigation (`--hide`, `--climb`, `--fps`, the triangle report):
  the next investigation starts with them.

## 10. Going native (what the C++ conversion taught, 2026-10-19)

- **Measure, then convert what costs.** The tile build was already native (grid and heights 10.9 ms, the rest about 4 ms);
  the real costs were plant placement, plant meshes (1-4 s on the first tiles), the quadtree selection (20 ms while loading)
  and a few per-pixel script loops in the map. `PLANET_TIMING=1`, the chart profile (`PLANET_CHART_PROFILE=1`,
  `tests/manual/planet/chart_times.gd`) and the lab's FPS line (it shows the render thread's CPU and GPU time) found them.
- **Godot's `RandomNumberGenerator` is PCG32 with the default increment**, so a native `Rng` with the same constants draws
  the same numbers: a ported builder gives the very same meshes (`PlantMeshNative.scenery`), and the old script is a
  true reference. Do not rely on it for planet shape (see the double build rule in `AGENTS.md`).
- **The frame is GPU-bound when playing** (render thread 4-7 ms CPU, 9-12 ms GPU at High/Ultra on a 4090): spare CPU is not the
  problem, so do not move per-frame work to the GPU. Idle moments (the map open, the game paused) are where the GPU can help:
  the map's cloud cover runs on a compute shader (`PlanetCloudGpu`).
- **A local `RenderingDevice` belongs to the thread that made it** ("can only be called from the render thread"): one
  thread creates it, compiles and does all the GPU work (jobs through a semaphore). The first shader compile took 3.4 s on
  D3D12, so start it on a thread after loading (`PlanetCloudGpu.warm_up`) and use the CPU until `available()`.
- **Native crashes print nothing.** A function that called itself (a refactor that replaced the wrong "first match" of a
  text) killed the headless checks with no message: run the full `planet_check.sh` after every native refactor, and bisect
  with `UtilityFunctions::print` in the C++. A script edit that replaces "the first occurrence" can hit the wrong place.
- **A running editor or game locks the DLL** (`Acceso denegado`): rename `bin/*.dll` to `.dll.old` first (both precisions).
  A new `class_name` script is only known after `godot --headless --path . --import`.
- **Approximations that pay**: half the samples on a cloud row (blend the rest) halved the cost with no visible change;
  a latitude-only quantity (sea ice) needs no trig per pixel; do the picture's smoothing on the last chart thread, not on
  the main one (it was a 60-430 ms hitch when a layer finished).
- **Editing tools on this machine**: write Python edit scripts to a file (a heredoc with an apostrophe confuses the shell
  tool), use `E:/...` paths in Python and `/e/...` in Git Bash, normalise `
` when reading and match the file's real
  indentation (tabs). Keep edits that matter to behaviour in the repo's checks, not in scratch scripts.
- **Keep files under the lint limits as you add**: the lab went past 1000 lines twice; move a check into
  `tests/manual/planet/planet_lab_checks.gd` instead of squeezing.
