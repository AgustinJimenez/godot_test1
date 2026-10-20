# 077 - Ground parallax quality (SPOM investigation)

Status (2026-10-20): **active; the speckle is reduced in captures, awaiting a live verdict.** The user explicitly asked for a
commit/push of the whole prior working tree, so the 20-sample checkpoint is in `c9d2964` despite the
usual live-verdict commit rule. The user then explicitly requested a commit/push of the later side-darkness change too.
The user chose quality first: make the close, nearly horizontal ground view look three-dimensional and free of visible bugs, then reduce GPU use. Work and tuning should happen in `tests/manual/ground/ground_lab.tscn` before judging the planet during ordinary play.

## Current handoff

- The shared planet ground shader (`shaders/world/planet_ground.gdshader` plus `planet_mosaic.gdshaderinc`) draws packed fragments with procedural heights. It ray-marches into those heights, refines the hit three times, moves the other ground layers with the hit, and applies plate self-shadowing to direct light. This is the POM core of the linked SPOM example, **not full SPOM**: silhouette clipping and horizon erosion are not implemented. The ground is continuous, so trimming a mesh edge or discarding the horizon could make holes; only try either with a demonstrated ground use case.
- The user liked the general look and saw it in the planet scene, but at a very low, close camera angle reported flat relief, duplicated shapes, stretched plate sides, and later a buggy/speckled view. The earlier "transparent layer over the rocks" was improved by moving all sampled layers to the parallax hit. Smaller, darker real stones and darker plate sides were committed; the side streaks were reduced, not eliminated.
- A committed ground-lab camera readout is copied with **C**. The reproduced troublesome view used `pitch=2.9 yaw=-72.2 dist=2.2 fx=0 fz=-0.5 fov=55 view=far` (about 0.11 m camera height); Claude also rendered it with `chips=0` to isolate the shader. Use the full readout and a matching screenshot for exact A/B comparisons. The last Claude render reported smooth far ground but a bright speckle in the middle distance; its source had not yet been isolated. Images #27/#28 and the exchange are in the Claude TrueLogic session `dad2674f-4c6c-49d2-a3c8-f6fb05411f7c` under the profile's `projects/E--repo-godot-projects-godot-test1/` directory.
- The live ground lab redraws only on changes and is capped at 60 fps. The planet remains a continuously rendered game scene. Claude's earlier claim that the lab was uncapped was corrected: the project already had a 60 fps limit. Its later estimate was about 15 ms GPU for the ground in a planet view, including roughly 4 ms for parallax; remeasure after quality is settled.

## Quality checkpoint in `c9d2964`

- `planet_ground.gdshader`: the march loop allows 32 iterations; `foot_m = length(fwidth(near_anchor))` fades the three fragment scales and fine grain when they become smaller than a pixel.
- `planet_mosaic.gdshaderinc`: the fixed sample count changes from 9 to 20. The shader currently uses `mosaic_pom_max_steps` as its fixed count; `mosaic_pom_min_steps` is still exposed but unused. A varying count previously made a visible ring, so the fixed count is deliberate for now.
- `tests/manual/ground/ground_lab.gd`: default and slider range updated for the 20-sample setting.
- These changes have **not** received a final user live-test verdict. The unrelated texture `.import` change
  was also committed because the user explicitly asked for all then-uncommitted files. Any new visual
  changes wait for live confirmation under the normal `AGENTS.md` rule.

## Current quality result

The 2026-10-20 render A/B used `pitch=2.9 yaw=-72.2 dist=2.2 fx=0 fz=-0.5 fov=55 view=far chips=0 size=1400x600`.
Setting `mosaic_height=0` removes the speckle but loses the depth. Removing scans, plate shadows, grain,
pebbles, or one plate scale does not. More march steps strengthen the artifact; a pixel-footprint fade
and a three-tap height prefilter did not clear it and were reverted. TAA smooths a still or slow turn,
but a 1-degree-per-frame turn still showed the bright speckle. Thus the earlier hypothesis that the
height *sampling alone* caused the visible contrast was incomplete.

The decisive A/B set `mosaic_side_dark=0`: the speckled field almost disappeared without turning
parallax off. The shader had darkened every deep ray hit as if it were a plate side. A deep hit can be
an ordinary gap, so this made most middle-distance ground dark and left isolated bright plate tops.
`mosaic_side_dark` is now a lab slider and a shader uniform, reduced from the hard-coded 0.8 to 0.35.
That keeps nearby plate shapes visible with much less false contrast in both AA-off and fast-turn TAA
captures. This changes the shading decision itself rather than adding another distance/angle guard.
The ground lab accepts layer switches and `sweep=DEGREES` for repeatable captures; PNGs are under
`E:/Temp/codex_spom_*.png` (`side0`, `side02`, `side04`, `reduced_default`, `reduced_fast_taa`).
The fixed lab readout string had an embedded newline that `gdlint` could not parse; it now uses `\n`.
Godot 4.7.2 compiled and rendered the low, macro, brown and sand lab views. The functional checks in
`scripts/planet_check.sh --quick` all passed (including native water, world, walk and swim); its final
status was FAIL solely because repository-wide `gdlint` 4.5.0 reports 294 style violations,
predominantly lines over 100 characters across the project. `git diff --check` passes. The user
authorized committing this visual checkpoint before a live quality verdict.

## Next steps

1. In the ground lab, reproduce the saved low-angle view and judge the new 0.35 side darkness during motion. Check nearby relief, the middle-distance field, plate-side streaks, and the transition to flat ground. Captures support improvement but cannot give the final live verdict.
2. If a defect remains, inspect its sampled height, hit depth and final shading separately before altering the ray march. The 0.35 shading change should not be mistaken for a geometry fix.
3. After quality is accepted, benchmark GPU time and tune sample/shadow cost without reintroducing the artifact. The 20-sample march is expected to cost more; no current benchmark establishes that cost as acceptable.

`AGENT_TASKS/076_forests_and_fields.md` records the earlier mosaic design and research, but its parallax sample counts and limits predate this task. This file is the current status for the quality pass.


## Baked height window (prototype, 2026-10-20): the march reads a picture

Opinion that led to it: the march evaluated the procedural plate pattern at every step (about 18 neighbour cells with
trigonometry each, a few hundred evaluations a pixel), for a relief 3 cm deep that fades by 4 m. Now the heights can be drawn
once into a picture round the focus and the march reads that (one texture read a step). **Still procedural**: the picture is made
at run time by `shaders/world/planet_mosaic_bake.gdshader` from the same functions and the same sliders; nothing is authored.

What exists (lab only; off by default, so the planet and every earlier number are unchanged):
- `planet_mosaic.gdshaderinc`: `mosaic_height_map` (the picture: red the large plates, green the medium ones, before the
  distance fade), `mosaic_height_window` (corner x, y, size in the march's own metres; size 0 = no picture), `mosaic_height_terms(p)`
  (what the bake stores) and `mosaic_height_now(p, fade)` (reads the picture where it covers `p`, else works it out). The four
  `mosaic_height_at` calls of the march, the refinement and the shadows in `planet_ground.gdshader` call `mosaic_height_now`.
- `ground_lab`: `bake=PIXELS bakesize=METRES` (a SubViewport with HDR 2D draws the picture once, again when a `mosaic_` slider
  changes or the focus leaves the middle of the window); `ssao=0` switches SSAO and SSIL off.

Measured, the standard low-angle view (`pitch=2.9 yaw=-72.2 dist=2.2 fx=0 fz=-0.5 fov=55 view=far chips=0 size=1400x600 aa=off`),
16 samples, `godot --gpu-profile --disable-vsync` over 400 frames, mean of the last five seconds, RTX 4090 / D3D12:

| Setting | Total GPU | Depth pre-pass | Opaque pass | Picture vs the worked-out one (mean / pixels off by > 24) |
| --- | ---: | ---: | ---: | --- |
| worked out at every step (before) | 14.00 ms | 5.34 | 8.07 | - |
| baked 1024 px over 10 m (10 mm a pixel) | 4.03 ms | 1.36 | 2.01 | 2.3 / 1.8 % |
| baked 2048 px over 10 m (5 mm a pixel) | 5.42 ms | 1.80 | 2.67 | 1.1 / 0.6 % |
| baked 4096 px over 10 m (2.4 mm a pixel) | 5.12 ms | 1.47 | 2.18 | 0.4 / 0.14 % |
| worked out, SSAO and SSIL off | 8.35 ms | 0.00 | 8.10 | - |
| baked 2048, SSAO and SSIL off | 3.29 ms | 0.02 | 2.53 | - |

Macro view (`view=macro`, a hand's breadth from the ground): 2048 differs from the worked-out one by 2.0 / 1.2 %, 4096 by 0.8 / 0.3 %;
the differences are thin lines along plate edges (the picture's pixels), not shape or tone. Picture size hardly changes the cost
(a read is a read); it changes memory (RGBA16F: 8 MB at 1024, 32 MB at 2048, 128 MB at 4096) and how sharp the edges are.

Findings:
- **The march was the cost**: 14.0 -> 5.4 ms (-61 %) with a picture that is nearly the same, about what the shader costs with the
  parallax off (about 5 ms in the table above). With the march this cheap, the step count (16 or 20 or 32) stops being a cost question.
- **The shader runs twice while SSAO or SSIL is on**: the depth pre-pass then also writes the normal and roughness, so Godot runs the
  whole fragment function in it (5.3 ms of the 14.0). With both off the pre-pass costs nothing and the opaque pass is unchanged.
  Any heavy ground shader pays this: keep the expensive part cheap or baked.

Not done (the plan to bring it to the planet):
1. **Scroll it**: the window follows the player (a toroidal picture: only the new strip is drawn as they walk; or a full redraw when they
   leave the middle quarter, split over frames), 2048 px over 10 m is the first size to try; RGBA8 instead of HDR (16 MB, heights in 8 bits
   are 0.1 mm steps) should be tried.
2. **The planet's coordinates**: on the planet the march's coordinates come from `on_planet` along `anchor_up`'s right and forward axes, which
   change when the anchor does (each rebase): rebuild the window then (a few ms of GPU), or keep it in an anchor-local frame. A small node
   (`PlanetGroundBake`) would own the SubViewport and set `mosaic_height_window` and the texture on the ground material.
3. The other per-step costs that remain (the colour layers read once at the hit, the scans, the stones) are about 5 ms in the lab view:
   next candidates after the picture is in.
4. Decide 16 or 20 (or more) samples with the picture on: they cost almost the same.
Run it: `godot --path . res://tests/manual/ground/ground_lab.tscn --gpu-profile --disable-vsync -- out=E:/Temp/x.png frames=400
pitch=2.9 yaw=-72.2 dist=2.2 fx=0 fz=-0.5 fov=55 view=far chips=0 size=1400x600 aa=off bake=2048 bakesize=10`.


## Baked heights in the planet (2026-10-20, second step)

`systems/planet/planet_ground_bake.gd` (`PlanetGroundBake`) is now in the planet, not only in the lab:
- A `SubViewport` (HDR 2D, 2048 px, never cleared) holds the heights of the plates over 12 m (5.9 mm a texel) as a **torus**: the texel of
  the ground at world texel w is w mod 2048, so walking draws only the strip just reached (the window moves 64 texels at a time, with
  hysteresis) and not the picture again. `mosaic_height_now` reads `p / size` with repeat and ignores the outer 8 % of the window (a strip
  is being drawn there, and the bilinear read reaches a texel past the edge); outside the window the heights are worked out as before.
- The picture is in the march's own coordinates (`PlanetGroundBake.flat_of`: the position from the anchor plus the wrapped anchor along the
  anchor's right and forward axes). They change with every rebase, so `PlanetWorld._follow_the_ground` gives `follow` a key (a hash of
  `frame.rot` and the anchor) and a new key draws everything again, from `publish_frame()` (the same frame the shader gets the new
  anchor) and every physics frame for the scrolling. It follows the camera, not the player.
- On when `ground_detail` >= 1 and not headless; `PLANET_NO_BAKE=1` turns it off (A/B). The planet does not change the `mosaic_*`
  numbers, so the picture uses the shader's defaults; the lab's sliders are passed on (`bake=` in the lab).

Checked:
- Scrolling draws what a fresh picture does: lab `bake_scroll=3,2` (start away, scroll back) against a fresh picture, mean difference
  0.00 / 255 (worst 7).
- The picture against the worked-out heights: 1.4 / 255 in the lab view (0.9 % of pixels visibly different, thin lines along plate
  edges), 0.3 / 255 in the planet view looking down (no pixel off by more than 23).
- `planet_check.sh --quick` passes; the windowed walk check (90 s, 5 rebases) passes with no slow frame and a worst frame of 16.7 ms
  (30.6 ms with `PLANET_NO_BAKE=1`).
- **The planet's worst case for this shader** (standing, looking down, so every pixel is near ground, 1920 x 1009,
  `planet_lab -- --hour=12 --fps --climb=0.3`): render GPU time **43.5 ms (23 fps) without the picture, 6.5 ms (145 fps) with it**.

Not done / to look at:
1. The memory is 32 MB (RGBA16F): try RGBA8 (16 MB; heights in 8 bits are 0.1 mm steps).
2. A full redraw (each rebase, about every 80 m of walking; also at the start) draws 4 M texels once: no slow frame showed on this GPU, but
   it was not timed alone, and a weak GPU may want it split over frames (the shader falls back to the slow path meanwhile).
3. Not tried: third-person or a far camera behind the player (the window is 12 m, the march reads within about 4 m of the camera), an
   Earth-size planet, real play. 16 or 20 (or more) samples now cost almost the same: decide by eye.
4. The other near-ground costs (the colour layers once at the hit, the scans, the stones) are what is left of the ground's ~5 ms.


## Third step (2026-10-20): the format, the redraw, the height gate, the samples

All measured with `godot --gpu-profile --disable-vsync` over 400 frames, mean of the last five seconds, RTX 4090, the standard low-angle
view, 2048 px over 12 m unless said. The pictures for judging by eye are in `E:/Temp/claude/ground_eval/` (outside the repo): `sheet_low_angle.png`,
`sheet_macro.png`, `sheet_standing.png`, each the same view worked out / baked 16-bit / baked 8-bit / baked with 32 samples. Live:
`godot --path . res://tests/manual/ground/ground_lab.tscn -- bake=2048 bakesize=12 [bakehdr=0] [mosaic_pom_max_steps=N]`.

| Setting | Total GPU | Depth pre-pass | Opaque pass |
| --- | ---: | ---: | ---: |
| worked out, 16 samples | 13.78 ms | 5.39 | 8.07 |
| worked out, 20 samples | 16.45 ms | 6.41 | 9.35 |
| baked, 16 samples | 5.31 ms | 1.54 | 2.30 |
| baked, 20 samples | 5.42 ms | 1.69 | 2.50 |
| baked, 32 samples | 6.26 ms | 1.48 | 2.30 |
| baked 1024 px, 20 samples | 5.13 ms | 1.46 | 2.14 |

- **8 bits against 16-bit floats**: the same picture to two decimals (against the worked-out heights, mean difference 1.03 / 255 low-angle,
  2.0 macro, 0.23 standing, for both), half the memory (16 MB, not 32). It is the planet's default now (`PLANET_BAKE_16BIT=1` for the other;
  the lab keeps 16-bit unless `bakehdr=0`).
- **A full redraw** is timed alone by the profiler's "Render CanvasItems" pass (the lab's `bake_redraw=1` draws everything every frame):
  1.7 ms at 2048 px (1.85 ms in 8 bits), 0.6 ms at 1024 px. That is what a rebase costs (about every 80 m of walking) and the start;
  splitting it over frames is not needed on this GPU (a slow one may take ten times as long: one slow frame). 1024 px is the way to
  halve it again, with softer plate edges.
- **The height gate**: above 10 m over the ground (`PlanetWorld.BAKE_UP_TO`) the parallax is faded out anyway, so `PlanetGroundBake.pause()`
  stops drawing and the shader goes back to the worked-out path; it is drawn again from scratch when the camera comes down. A flight
  across the gate (the fly check) draws it again a few times; nothing else.
- **The samples**: with the picture, 16, 20 and 32 samples cost 5.3, 5.4 and 6.3 ms. 32 finds thinner features, so it differs more from the
  20-sample picture (macro: 4.5 / 255 and 6.9 % of pixels against 2.0 and 2.1 % for the baked 20): finer, busier detail. The choice is by
  eye now.
- **In the planet** (8 bits, standing, looking down, 1920 x 1009): render GPU 6.6 ms (the worked-out path was 43.5 ms), the picture within
  0.26 / 255 of it; 20 m up (the gate) 3.6 ms; the windowed walk check had no slow frame, the fly check one (worst 50.5 ms).


## Fourth step (2026-10-20): a textured look, stones that stand in the soil

The user said some bumps looked stretched and some were too simple. All of it is baked into the same height picture, so the cost stays
the same (lab low-angle view 4.2 ms with 20 samples, no stones).

- **The plates** (`planet_mosaic.gdshaderinc`, `mosaic_plate_height`): each top leans (`mosaic_slab_tilt`), is rough (`mosaic_top_detail`),
  the large plates have cracks (`mosaic_cracks`), each plate has bands of tone across it (`mosaic_veins`) and pale dust on the flat tops
  (`mosaic_dust`). The worked-out fallback uses the same function, so the picture and the fallback agree.
- **The light** follows the real slope of the baked heights at the hit (`mosaic_relief_light`, four extra reads), not only each plate's
  made-up lean. **The steep sides** get bands down them (`mosaic_side_strata`): the colour read at the hit only smears along the ray. The
  first steepness threshold was too high (0.27 / 255 of change in a closeup); 0.15-0.6 gives 1.2.
- Every number has a slider in the ground lab ("mosaic:" rows); all at 0 is the plain plates. A texel is 5.9 mm: nothing finer than
  about 3 cm can be baked.
- **The 3D stones hovered**: the parallax only repaints the ground, so the soil looks up to 3 cm below the mesh and the stones stood on the
  mesh. Sinking them does not help (the mesh hides them). The ground shader now writes `DEPTH` for the point the ray found
  (`pom_push`), which cost 0.3 ms in the lab (4.21 -> 4.52 ms) and about 1 ms in the planet (render GPU 7.3-7.7 ms standing, looking down at
  leaf litter; was 6.5 ms before the textures and the depth). Writing depth turns off early depth rejection for the ground; it cannot be
  limited to the near pixels in one material.
- **The stones**: a dark soft patch under each (`planet_chip_shadow.gdshader`, the same instances, pushed down like the soil), and rounder
  80-face shapes in 8 variants (4 angular, 4 rounded) instead of 20-face gems.
- **Not done**: the plate size and cover following rock type and slope; splitting the bake in a big and a mid picture; a cheaper strata
  noise (one read saved, not worth it).
