# Blender workflow notes

Running notes for making assets (humanoid figure, props) in Blender and bringing them into Godot. Add a
dated line whenever something is learned; keep it short and factual.

## Setup on this machine

- Blender 5.3.0 at `C:\Program Files\Blender Foundation\Blender 5.3\blender.exe` (Python 3.13). The user keeps
  one GUI window open; headless runs are separate processes (`blender -b ... --python script.py -- args`).
- Headless runs always use `--factory-startup` for a clean scene, so the default `Cube`, `Camera` and `Light`
  exist: delete them in any script that saves a `.blend` (the user saw them in the GUI).
- Write scratch scripts and outputs to the session scratchpad, not the repo. Copy only finished assets in.

## MPFB (MakeHuman plugin for Blender), 2026-11-21

- Installed as an extension: `blender -b --factory-startup --online-mode --command extension sync`, then
  `... --online-mode --command extension install --enable mpfb`. The `--online-mode` flag is needed because
  online access is off in the user's preferences (do not change that preference).
  Lives in `%APPDATA%\Blender Foundation\Blender\5.3\extensions\blender_org\mpfb`.
- Enabling it from a headless script fails with "I don't seem to exist" unless the addon entry exists first:
  `e = bpy.context.preferences.addons.new(); e.module = "bl_ext.blender_org.mpfb"`, then
  `addon_utils.enable("bl_ext.blender_org.mpfb")`.
- Then import services as `bl_ext.blender_org.mpfb.services.humanservice` (`HumanService`) and `.targetservice`.
  `HumanService.create_human(macro_detail_dict={...})` (gender, age, muscle, weight, proportions, height,
  cupsize, firmness, race) gives a 19k-vertex basemesh; `HumanService.add_builtin_rig(obj, "game_engine")`
  adds a 53-bone rig (others in the addon's `data/rigs/standard`: default, mixamo, mixamo_unity, cmu_mb,
  openpose). `export_scene.gltf(use_selection=True)` exports a rigged `.glb`.
- The core extension ships no skin photos, hair, eyes or clothes: those are separate MPFB asset packs (not
  installed). Without them the figure is a bald, eyeless, naked base mesh.

## Skin

- First procedural skin (Principled BSDF: subsurface, noise tone variation, Voronoi and noise pore bump,
  roughness variation) is a starting point, not finished: too pale and pink, no lip or nail colour, pores faint.
- Procedural shader nodes do not export to `.glb`; bake to texture maps before the Godot import.

## Making the GUI file useful

- Save the `.blend` with the viewport already set: in a script, for each `VIEW_3D` space set
  `shading.type = "MATERIAL"`, and set `region_3d.view_rotation`, `view_location`, `view_distance`
  (a waist-up front view: rotation `Euler((pi/2, 0, 0))`, location `(0, 0, 1.25)`, distance `2.2`).
- An already-open Blender window never reloads a changed file: open it as a new instance, or use File >
  Revert. Saving from the old window overwrites the script's changes.

## Claude/Blender tooling (researched 2026-11-21, nothing installed)

- Official Blender Lab MCP: needs Blender 5.1+ and a GUI-installed add-on (cannot be set up headless); the
  official page returned 403 to the fetch tool, so its tools and data handling are unread.
- `6xvl/blender-skill`: useful `SKILL.md` and character tools (rig audit, skin lab, walk builder). Its bundled
  MCP bridge has telemetry on by default (Supabase); set `DISABLE_TELEMETRY=1` if used, or copy only the skill.
- `RobLe3/cc-blender-skill`: markdown knowledge only, no network code; needs a separate MCP server.
- Review the source of any Blender MCP add-on before installing: they expose code execution inside Blender.

## Open items

- Add eyes, hair, brows and lashes; tune skin colour; bake textures; import `human.glb` into Godot and check
  rig and weights against `HumanoidRetargeter`.

## Parametric bodies in Godot (spike, 2026-11-21)

- `assets/models/humans/{female,male}_body.glb`: body only (13,380 vertices, helper geometry removed), no rig yet,
  six blend shapes each: `height_short`, `height_tall`, `weight_light`, `weight_heavy`, `muscle_low`, `muscle_high`. Made by creating MPFB humans
  at the macro extremes and storing each vertex position difference from the default as a shape key.
- Measured: male 1.75 m, female 1.61 m. `height_tall` adds 0.70 m and `height_short` removes 0.36 m at weight 1.0, so the
  lab limits the slider to 0.6. The weight shapes move the waist only about 3 cm; the lab multiplies heavy by 3 (clean up to there) but light only by 1.25: at 3 the female body folds at the waist and hips. Checked at slider -1 and +1 on both bodies, 2026-11-21.
- Godot's mesh bounding box spans every blend shape, so it is not the body height; compute the height from the numbers.
- Lab: `tests/manual/humans/human_body_lab.tscn` (gender buttons, Height and Weight sliders, right-drag to turn,
  `-- --capture=<png>` saves a frame). Next: add a rig that follows the height, and more sliders.

## Underwear (2026-11-21)

- Pipeline scripts live in `tools/blender/` (`make_bodies.py`, then `make_underwear.py`; run each with
  `blender -b --factory-startup --python <script> -- <folder>`; `make_bodies.py` needs MPFB enabled as above).
  The scratchpad is wiped by a crash, so keep generator scripts here, not there.
- `assets/models/humans/{male,female}_underwear.glb`: briefs for both and a bandeau top for the female, cut from the
  body's own faces by slicing along flat planes, pushed 4 mm out along the normals, with the same four blend shapes as
  the body so the same slider weights fit. Hems are straight; the shapes are plain (no straps, waistband or seams).
- The lab always loads it as a child of the body (no toggle).
- Cloth look (2026-11-21): deliberately plain. `shaders/human_underwear_fabric.gdshader` is a single-colour knit cotton (model-space triplanar weave, faint bump, light sheen that fades by pixel footprint); no contrasting waistband or stitch lines (the user did not want them). `make_underwear.py` still bakes waistband/hem masks into the vertex colour if a later style wants them.
  `make_underwear.py`, exported with `export_vertex_color="ACTIVE"`) and is drawn by `shaders/human_underwear_fabric.gdshader`:
- Muscle (2026-11-21): `make_bodies.py` also bakes `muscle_low` / `muscle_high` (MPFB macro muscle 0 and 1; about 2-4 cm
  of movement), and `make_underwear.py` carries them over automatically. The lab uses gains 2.0 (high) and 1.25 (low),
  same reasoning as weight. Checked at slider -1 and +1 on both bodies: clean. At high muscle the female bandeau looks
  slightly rumpled over the chest because the cloth shell copies the body's bumps.

## Eyes (2026-11-21)

- `make_bodies.py` now also writes `{female,male}_landmarks.json` (centres of the helper eye joints in the base shape and in each of the six
  variants; Blender space). `tools/blender/make_eyes.py` turns them into `{female,male}_eyes.glb`: two plain UV spheres (radius 0.9 x the
  helper eye, 14.3 mm) with the same six shape names, each shape just translating the spheres to that variant's eye centres. Do not slice
  `bm.verts[a:]` in bmesh to pick a sphere's vertices (it moved the second eye twice, 3 m up): use the `verts` returned by `create_uvsphere`.
- `shaders/human_eye.gdshader`: no texture; the iris, pupil, limbal ring and sclera (faint veins, shading toward the sides) are drawn from the
  direction on the sphere with the eye looking along +Z, so iris colour, pupil size, iris size and sclera tint are shader parameters. Clearcoat
  gives the wet highlight. The lab has an eye colour picker and a pupil slider (`--eye=rrggbb`, `--face` flags for captures).
- Checked: both bodies, brown/green/blue/amber, height -1 and +1 (the eyes stay in the sockets). The base mesh's eye opening is narrow, so
  little of the eye shows; eyelashes and brows are the next step.
- Eye controls (2026-11-21): shader parameters `iris_color`, `iris_color_other` + `different_eyes` (the -X eye uses the second colour), `iris_radius_deg`
  (lab slider 18-34, default 26), `pupil_size`, `sclera_tint` (yellowing) and `vein_amount`. All have lab controls; capture flags `--eye= --eye2= --iris=
  --pupil= --sclera= --veins=`. Checked: green/blue split eyes work; bigger iris and yellowed sclera show but subtly, and the veins are hardly visible
  because the body's eyelid opening hides most of the eyeball (a face-shape item, not a shader one).

## Eyebrows and eyelashes (2026-11-21)

- `make_bodies.py` also saves the eyelid helper vertices (`lash_{l,r}_{1,2}`: row 1 = lower lid, row 2 = upper lid) in the landmarks JSON.
  `tools/blender/make_face_hair.py` reads the body glb (it has all six shapes) and the landmarks and writes `{male,female}_brows.glb` and
  `{male,female}_lashes.glb`: flat hair cards. Brows: a Catmull-Rom curve (`BROW_POINTS`, offsets from the eye centre) with each card
  vertex ray-cast onto the skin from the front. Lashes: 30 upper (about 8.5 mm) and 13 lower (about 4 mm) cards per eye along the lid margin.
  Every card vertex is bound to its nearest body vertex plus an offset, and each body shape key moves it with that vertex, so the cards follow
  every slider (checked at height +1).
- `shaders/human_face_hair.gdshader` (`is_lash` switches the mode): brow strands (leaning outward at the inner end, some broken, smooth
  coverage once strands are finer than a pixel) and tapered lash strands; `hair_color`, `lash_darken`, `brow_density`, `strand_count`.
  It uses normal alpha blending (`blend_mix`); alpha-hash dithering gave a speckled brow at this distance. Lab: "Brow and lash colour" picker,
  "Brow thickness" slider, `--brow=rrggbb --density=`.
- Not done: separate lash colour, lash length/curl controls, brow shape controls (arch, thickness, tail) beyond the thickness slider; no head
  hair yet (the head is bald).
- Brows and lashes, second version (2026-11-21, replaces the card/band description above): the first version (flat cards with a drawn strand
  pattern) looked like a striped band and bristles up close. `make_face_hair.py` now builds real hairs: per brow 320 tapered strips (5 mm,
  0.9 mm wide) rooted at random points of the brow curve, leaning up at the inner end, lying on the skin by ray-casting each segment, plus a
  faint base layer; lashes are 24 roots x 3 lashes (upper) and 12 x 2 (lower) per eye, 4 segments, curled and tapered. Vertex colour carries
  red = random brightness, green = random for the density slider (hair drawn when green <= density), blue = 1 on the base layer; the shader
  (`human_face_hair.gdshader`) only draws the taper. Lab: "Face close-up" checkbox (camera follows the eyes), wheel zoom to 0.2 m, "Brow density".
  Known: a few outer-corner lashes are edge-on and show as faint dotted lines; the left brow tail can show one long thin hair toward the temple.

## Head hair (native C++, 2026-11-21)

- Runtime, not Blender: the class `HumanHair` (`native/planet_crust/src/human_hair_native.{h,cpp}`, registered in `register_types.cpp`) builds the hair from the body's
  own `ArrayMesh` (surface 0 plus its blend shapes) and a parameter Dictionary: `seed, length, locks (up to 9000), lock_width, volume, curl, fringe, parting, gravity, side_trim, eye_drop`
  (documented in the header; `HumanHair.default_params()`, or `default_params_for("male"|"female")` for the body's own `eye_drop`, taken from the eye landmarks in `tools/blender/landmarks/`). Three steps so the slow part can leave the main thread: `HumanHair.prepare(body)` reads the ArrayMesh once into plain arrays (kept in the mesh's meta; `surface_get_arrays` stalls the GPU), `HumanHair.build_arrays(data, params)` grows the hair and touches no scene or rendering object (any thread; checked on a `Thread`), `HumanHair.make_mesh(built)` makes the ArrayMesh on the main thread; `build(body, params)` does all three. The dice is a small SplitMix64, one per lock (same hair on every engine build).
- How it works: find the head (top, centre, width) from the body vertices; scalp = vertices above a hairline that is low at the nape, higher at the temples and forehead;
  pick roots on the scalp triangles by area; grow each lock as a polyline (combed away from a crown point shifted by the parting, front hair swept back unless `fringe`,
  gravity grows with `length`, `curl` winds it into a helix, `volume` stands it off a head ellipsoid, and every point is pushed out of the body using a nearest-vertex grid);
  each lock is a flat tapered ribbon (about 2,600 of them, ~58k vertices) plus a dark cap over the scalp that fades toward the hairline (vertex colour alpha).
  The result carries the body's six blend shapes. A hair vertex follows each shape by a fit of the whole scalp (a scale and a move, found by least squares, so the hair grows with the head at Height +-1), plus the residual of the body vertex its lock starts on (fading out along the strand), and hair hanging below the eyes near the neck and shoulders follows the nearest body vertex (Weight and Muscle move the shoulders). The scalp cap and the roots follow the nearest scalp corner plus the head fit.
- `shaders/human_hair.gdshader` draws strands, ragged tips, a colour and a tip lightening; vertex colour red = brightness, green = density dice, blue = cap, alpha = cap fade.
  Alpha scissor, no sorting needed. Lab: presets Buzz/Short/Bob/Long/Curly, length, volume, curl, fringe, parting, fall, density, hair colour, "New hair" (other dice);
  capture flags `--hair-preset= --hair-colour= --hair-set=key:value --nohair`. The lab rebuilds the hair in `_process` after a slider moves. Measured (debug build, the check prints them): growing 50-100 ms and making the mesh 20-40 ms per rebuild, the first on any thread.
- Check: `godot --headless --path . -s res://tests/manual/humans/human_hair_check.gd` (PASS: vertices, finite, on the head, same blend shape names as the body,
  deterministic, longer length hangs lower).
- Build state: the single-precision DEBUG library was rebuilt (`scripts/build_native.sh`). The release and double-precision libraries are NOT rebuilt yet (AGENTS.md
  says to rebuild both after a C++ change); do that before the double engine build or an export uses the new class.
- Hair shading and motion (2026-11-21, loop tick 1): `human_hair.gdshader` now lights with Kajiya-Kay plus two shifted highlights (Scheuermann, GDC 2004,
  "Practical Real-Time Hair Rendering and Shading"; the mesh carries a TANGENT along each strand, and the blend shapes carry the base normals and tangents) in `light()`; wind and head inertia
  bend each lock in the vertex stage, weighted `UV.y^1.4` so roots stay put (uniforms `wind`, `wind_speed`, `sway`). The lab has Wind, Hair shine, and a spring
  (`_update_hair_sway`: turning the body or pressing Shake kicks it) that feeds `sway`. First values of the highlights were too hot (white streaks): lowered.
- Hair, loop tick 2 (2026-11-21): `HumanHair` gained `side_trim` (sides and back shorter than the top, by root height) and feathering at the hairline (a share of the roots
  near the hairline is dropped and the survivors are shorter); the shader darkens roots (self-shadow by the hair above). The Short preset now reads as a short back and sides
  with a swept top. Lab: "Sides and back shorter" slider. Still to do: a notch in the middle of the male's forehead hairline, white glare flecks where the highlight
  lines up with the light (clamp them), flyaway strands, release and double libraries.
- Hair, loop tick 3 (2026-11-21; since rewritten in C++, see "Review fixes" below): the sway spring is a reusable component, `HairSway` (native, `hair_sway_native.{h,cpp}`): give it the hair's MeshInstance3D (`hair`) and the moving node
  (`target`), and the character's acceleration and turning kick a damped spring that feeds the shader's `sway` uniform (one spring per character, the per-vertex work is on the
  GPU); `kick(Vector3)` pushes it by hand. The lab uses it (Shake button, `--shake` capture flag, turning the body). Also: back-lit glow (the TT lobe) and clamped highlights in
  the shader, tighter random length/stiffness (fewer flyaways), a lighter scalp cap and a slightly higher front hairline (the forehead notch is much less stark). Checked: a
  shake visibly swings the whole hair mass; no script errors. Not yet wired into a real character (the player/NPC bodies do not use these humans yet).
- Hair, loop tick 4 (2026-11-21): dyed ends (`tip_color`, `tip_mix` in the shader; lab "Dyed ends colour/amount", flags `--tip= --tip-amount=`; pink ombre checked, looks right); side
  hairline lowered (`side_y` eye + 0.014) so the cap covers the temples; scalp triangles with at least 2 of 3 corners above the hairline count (the cap and roots are more complete);
  capture flag `--yaw=<degrees>` turns the body for side/back views. A "bald patch" seen from behind on the Short style turned out to be the ear showing through the short
  back-and-sides (side_trim 0.55), not a hole in the hair. Back and side views look like a believable cut; the edge ahead of the ear is jagged.
- Hair, loop tick 5 (2026-11-21): all presets looked at. Buzz had been a flat swept plate because ribbons 1.8 cm wide are wider than 2.5 cm hair is long; `HumanHair` now narrows the
  locks for short hair (`lock_width = min(requested, 0.002 + length * 0.25)`) and raises the lock count to keep the coverage (cap 9000), so Buzz is a close-cropped cap with a bristly
  edge. Length itself works (hair reaches 3.4 / 7.1 / 17.5 cm from the body at lengths 0.025 / 0.07 / 0.17). Open: the Curly preset is swept and messy rather than curly, and one
  stray lock lands on the face near the mouth on the female Curly; the edge ahead of the ear is jagged; the male Buzz still has longer hair over the ears than the top.
- Prior art searched (2026-11-21): no open-source or in-engine generator that grows hair from a scalp mesh with parameters was found. Related: Blender add-ons (Hair Tool, Curve-Bstrands,
  GroomFlow Pro, RapidHair Cards), Houdini Hair Card Generate, Unreal Hair Card Generator, TressFX for Godot 4 (strand simulation fed from Blender grooms). Ideas to borrow: guide
  curves plus interpolated child strands (clumping), and TressFX-style strand physics if the shader sway is not enough.
- Hair, loop tick 6 (2026-11-21): DRAPING REWRITE after the user said the hair "stays straight, does not fall over the head". Strands no longer leave the scalp pointing outward:
  each starts lying along the scalp in the combed direction, gravity bends it a fixed share per step (`pull = clamp(0.26 + 0.2 * gravity_amount)`), the head holds it up (pushed
  out of the surface by the nearest-vertex grid, then the step direction is recomputed from where it actually went, so it slides over the skull) and it falls freely where the head ends.
  Combing is horizontal around the crown (no upward spikes at the crown), the front splits at the parting (sideways push grows toward the front), the front locks are 45% shorter
  (bangs/face-framing), and a neck column (found from the body vertices under the chin) pushes any strand that ended up inside it out the way it came, so back hair no longer
  comes out the front of the neck. Checked: long hair parts and falls over the shoulders, back view is a smooth sheet; bob and short cut lie over the head; no spikes.
- Hair, loop tick 7 (2026-11-21): the "beard" of hair under the chin was traced with throwaway GDScript checks (ribbon tips in front of the neck, then their roots) to scalp detection, not
  growth: (1) the head centre was the average of the head vertices, pulled forward by the face, so the angle round it (used by the hairline) was wrong for cheeks and the jaw; the centre z is now
  the midpoint between the front of the face and the back of the skull; (2) roots with above_hairline <= 0 were still kept with 15% probability; they are skipped now; (3) vertices under the jaw,
  close to the head axis, passed the nape test; below eye level a vertex must be at least 0.6 x the head half width from the axis (the top of the head is exempt, or the crown goes bald).
  Result: scalp-cap vertices on the face 350 -> 44, ribbons ending in front of the neck 116 -> 0, bob has real bangs, long hair parts and frames the face, the short cut looks like a haircut
  from the front, side, top and back. Lesson: when a hair artefact looks like a growth problem, count where the roots are before changing the growth.
- Hair, loop tick 8 (2026-11-21): real curls. The old curl (a few-millimetre wobble added to each step) was invisible, so the Curly preset looked like straight short hair. Now the strand is grown
  as before and then wound into a helix around its spine: `curl_radius = curl * (0.004 + 0.3 * step_length)` (so longer hair gets bigger waves), the helix turns `0.5 + 1.2 * curl (+ up to 0.4)`
  radians per point (slow waves for a little curl, tight coils for a lot), grows over the first three points so the root stays on the scalp, strands with curl get up to 18 points
  (`length / 0.008 + 5`), and the strand rides `0.8 * curl_radius` higher above the skin so a coil does not pass through the head. Presets: Curly curl 0.9 / length 0.12 / volume 1.3, Long curl 0.2.
  Checked: Curly on both bodies is a mass of small coils; a bob at curl 0.4 is wavy; Long stays smooth enough. Buzz re-checked after all the scalp fixes: a short cropped cut.
- Hair, loop tick 9 (2026-11-21): the pale streaks were the highlight term (they vanish with `--shine=0`). The first highlight is now half tinted by the hair colour, the clamp is 0.3 and the default
  shine 0.4 (lab flag `--shine=`). The streaks are gone on long hair and much weaker on the short cut (a little grey remains over the ear, where the scalp cap meets the sparse hair).
  Release and `--double` libraries are being rebuilt with `GODOT_CPP_DOUBLE=E:/Godot/cpp/godot-cpp-double GODOT_API_DOUBLE=E:/Godot/cpp/dump/extension_api.json scripts/build_native.sh --release --double`
  (log in the scratchpad); until that finishes only the single debug DLL has the new class.

## Review fixes and native HairSway (2026-11-21, task 102)

- `HairSway` is C++ now (`native/planet_crust/src/hair_sway_native.{h,cpp}`, the GDScript `components/hair_sway.gd` is gone). It takes the hair's mesh instance (`hair`), not a material: the swing goes to the shader's
  `instance uniform vec3 sway` through `set_instance_shader_parameter`, so characters that share the hair material swing on their own. The character's movement is sampled in `_physics_process` (true positions, not
  the interpolated ones) and converted into the hair mesh's own space (the humans' glb files face +Z, actors face -Z; `forward` says which way the mesh faces), the spring runs in `_process`.
- Hair shader: no highlight on the scalp cap (its tangent is arbitrary: the grey patch over the ear), `return` is not allowed in `light()` (a compile error made the hair render white).
- `HumanHair` changes: body read once (`prepare`), blend shapes by head fit (above), the combing direction no longer collapses where it is parallel to the surface normal, dead code removed.
- Landmarks: `tools/blender/landmarks/{male,female}_landmarks.json` (the eye centres, lid vertices; `make_eyes.py` and `make_face_hair.py` need them, pass that folder). The default `eye_drop` of each body is checked
  against them by `tests/manual/humans/human_hair_check.gd` (male 0.108, female 0.107 m).
- Check: `scripts/humans_check.sh` (the hair check on the double engine; needs the double library built).
- Not done: B7 (patterns in model space slide once the body is skinned: store rest-pose coordinates in a custom vertex channel when the rig exists), scalp constants in absolute metres, ear-rim vertices count as scalp,
  collision against clothing beyond the nearest-vertex push, LOD.

## Rig (2026-11-21, task 102)

- `tools/blender/make_rig.py` rigs the same two bodies with MPFB's Mixamo skeleton (`add_builtin_rig(body, "mixamo")`: 52 bones named `mixamorig:Hips` ..., the family the game's retargeting
  (`HumanoidRetargeter`, `player_body.gd`) already knows; Godot's importer turns the colon into an underscore: `mixamorig_Hips`). Outputs `{male,female}_rigged.glb` (the body of `make_bodies.py`,
  the same vertex order and six shape keys, plus skeleton and skin weights: all 13,380 vertices skinned) and `{male,female}_rig.json` into `assets/models/humans/`. `blender -b --factory-startup --python
  tools/blender/make_rig.py -- <folder>`. The rig is fitted again to each of the six macro extremes (the same humans `make_bodies.py` bakes) and the JSON stores the move of every joint per shape
  (Godot space, y up). Joint moves: height_short -0.33 m, height_tall +0.65 m at the largest; weight and muscle at most 1.7 cm.
- Why the JSON: shape keys move the vertices but a skeleton has none. `HumanRig` (native, `human_rig_native.{h,cpp}`) applies the same slider weights to the bones: every bone's rest origin moves by the
  weighted sum of its stored moves (its orientation stays the base one), the local rests are rebuilt, and the skin's bind poses are set to the inverse of the new global rests (checked: at rest they equal
  the inverse of the global rests to 1e-6, so this is what keeps the mesh unchanged at rest while the bones move). The skin resource is copied per rig. `HumanRig.shape_weights(height, weight, muscle)` is the
  one slider mapping (the old lab constants). Use: `rig.setup(skeleton, [mesh_instance], HumanRig.load_data("res://assets/models/humans/male_rig.json")); rig.apply(weights)`.
- Checks: `tests/manual/humans/human_rig_check.gd` (in `scripts/humans_check.sh`): data matches the skeleton, bind poses are the inverse global rests after every shape, every joint is inside the shaped body at
  every extreme (largest joint-to-surface distance 0.11 m, the same as at rest), a turned arm bone moves the vertices skinned to it. Lab: `tests/manual/humans/human_rig_lab.tscn` (keys 1 rest, 2 arms up,
  3 squat, B bones, G gender, Up/Down height; capture flags in the script header). Seen: bones lie in the body at height -1 and +1; arms raised and a squat deform naturally on both bodies.
- Engine quirk met while checking: reading a bone's global pose before setting a pose, outside the frame loop, returns the old pose until the next frame; read poses after `await process_frame`.
- Not done: the other meshes (underwear, eyes, brows, lashes, hair) are not skinned yet (underwear: copy the body weights; eyes, brows, lashes, hair: attach to the head bone); no animation retargeting
  tested on this skeleton (the Mixamo names should match `HumanoidRetargeter`); the JSON has to be in the export's non-resource filter (`*.json`) for an exported game; finger and toe bones follow only by
  translation; orientation does not change with the shapes.

## Skinning the other meshes and a Mixamo walk (2026-11-21, task 102)

- `HumanRig` has four more statics so every mesh of a human follows the skeleton without re-exporting anything from Blender: `transfer_skin(cloth, body)` (each cloth vertex takes the bones and weights of the nearest body
  vertex, both in the base pose: the underwear, later any clothing cut from the body), `skin_to_bone(mesh)` (every vertex on one bone), `attach_skinned(cloth, body, skeleton)` and `attach_rigid(mesh, skeleton, bone)`
  (the above plus the instance moved under the skeleton with the right skin). Blend shapes and material are kept. Order: attach first, then pass the mesh instances to `setup()` so the skins follow the sliders.
  The lab: underwear skinned with the body's weights, eyes, brows, lashes and the native hair rigidly on `mixamorig_Head`.
- Walk: `HumanoidRetargeter.retarget_clip` (the project's own retargeting) turns the Mixamo `walking.fbx` of the action pack into a clip for this skeleton, `make_clip_in_place`, played by an AnimationPlayer on the
  skeleton's parent (`human_rig_lab` key 4, `--pose=walk --time=`). The skeleton's names carry the `mixamorig_` prefix, so `prefix_role_map` and `full_map_from_prefix` work unchanged. The clip is made for the skeleton
  as it is when it is made: proportions follow Height, so make it again when a slider moves (the lab does, on every change). Captured on both bodies at height -1, 0, +1: strides, arm swing, underwear and hair follow.
- Known: transferring by the nearest vertex leaves a few small slits in the underwear in extreme poses at heavy weight (under the arms, at the crotch), where neighbouring cloth vertices pick different bones: interpolate
  the weights of the three nearest vertices or smooth them. The shader patterns of eyes, underwear and hair cap are still model space (B7): they slide a little in a pose.

## Second hair review (Opus 5.5, high effort, 2026-11-21) and what was done

Fixed (checked by `scripts/humans_check.sh`; `--render` also draws the rig lab and fails on a shader error):
- Skinned hair, eyes, brows and lashes were culled at some heights: Godot sizes a skinned mesh from the base vertices and ignores blend shapes (head 0.42 m higher at Height +1). `attach_rigid` / `attach_skinned` now set a `custom_aabb` with the base and every shape plus 0.4 m.
- A hair attached after `HumanRig.setup` moved twice (its bind pose never followed `apply`): `HumanRig.adopt(mesh)` joins it to the rig; `setup` may be called again on a skeleton `apply` has moved (the base rest is kept in the skeleton's meta `human_rig_base_rest`).
- Curly locks flipped their ribbon side every coil (crossed quads): the side is carried from point to point. The check counts normals of consecutive points that face opposite ways.
- Below the eyes the follow of the nearest body vertex searched 4 cm but faded out at 9 cm: a second grid with 9 cm cells finds the nearest vertex within the reach.
- HairSway kicked the hair in proportion to the turning SPEED (pinned at max_swing above 1.4 rad/s) and let the velocity pile up at the limit: the kick follows the CHANGE of the turning speed (`turn_gain` is now m/s per rad/s of change, 0.3), the outward velocity is dropped at the limit; `human_sway_check.gd` covers acceleration, a turn starting, a steady turn, coming back to rest, a huge kick and the instance uniform. HairSway is a runtime class (no spring running in the editor).
- Seeds: the dice mixes the seed first (seed + 1 used to be seed shifted by one number; "New hair" re-rolled by one number). All hair changes with this (seed 1 gives other locks than before).
- `side_trim` 1 wrote zero-length locks with zero normals: locks under 4 mm are skipped. `locks` is clamped to 9000 (the real cap). The determinism claim is now "same on the same build" (float precision and maths libraries differ across platforms).
- The scalp cap has plain wrapped diffuse (no strand diffuse from an arbitrary tangent, no highlight); the cap's noise and the wind phase use the rest place in UV2 (x + y, z + y) and no longer swim when the head moves. A light blond hair looks cream instead of neon yellow (the cap was very bright).
- `prepare`'s cached read is dropped when the mesh's vertex or shape count differs (the meta survives `duplicate()`).
Open: B7 for the other shaders (eyes, underwear), nothing yet compiles the shaders in a headless run (use `--render`).

