# Task History: Character Editor Import Feature

Status: **feature working, verified live**. "Import Character..." and "Import
Animation..." buttons added to `tools/character_editor/character_editor.tscn`,
using a native macOS file picker, plus a loading spinner during the
(multi-second) import round trip. Eight unrelated bugs surfaced during
verification, all fixed - Bug 8 predates this feature entirely, only ever
became reachable once non-Player characters existed to test against, and
turned out to have three separate occurrences of the same underlying
mistake across three different functions before it was fully resolved.
Notes below exist so a future session doesn't have to re-diagnose the same
symptoms from scratch.

## Background

The character editor tool (a played scene, not the editor itself) needed a
way to import a new character/animation FBX directly from the UI, instead of
requiring the assistant to manually copy files and trigger a reimport every
time. Only the actual Godot editor process can run the FBX importer, so the
played scene asks the editor to do it via the existing `addons/mcp_bridge`
debugger-message channel (the same mechanism already used for live character
switching) - see `pose_debugger_plugin.gd`'s `_on_message_received` /
`_import_asset` and `character_editor.gd`'s `_request_import_asset`.

## Bug 1: native file picker never actually appeared - FIXED

First attempt used `FileDialog.use_native_dialog = true` on the dialog node.
Never opened Finder - always fell back to Godot's own drawn dialog UI.
`use_native_dialog` has a documented bug where it has no effect unless the
dialog is shown via `popup()`-family calls specifically
([godotengine/godot#82531](https://github.com/godotengine/godot/issues/82531)).
Fixed by calling `DisplayServer.file_dialog_show()` directly instead of
relying on the `FileDialog` node's wrapper, with a fallback to the drawn
`FileDialog` on any platform that doesn't report
`DisplayServer.FEATURE_NATIVE_DIALOG_FILE` support at all.

That alone still didn't fix it - see Bug 2.

## Bug 2: `game_embed_mode` silently blocking native dialogs - FIXED (env, not code)

Even after switching to `DisplayServer.file_dialog_show()`, the picker still
didn't appear. Root cause: this editor's `run/window_placement/
game_embed_mode` EditorSetting was `0` ("Use Per-Project Configuration"),
and this project has no override - Godot's default under that combination
runs "Play Scene" **embedded inside the editor's own window** (a `Game`
panel sub-view, launched with a `--embedded` CLI flag, confirmed by
inspecting the played-scene process's actual argv). A native OS file dialog
has no independent OS window to parent to in that mode, so
`file_dialog_show()` was silently failing every time - no error, just no
dialog. Confirmed by checking `DisplayServer.has_feature(...)` (all `true` -
this build DOES support native dialogs).

Fixed by setting `EditorSettings` `run/window_placement/game_embed_mode` to
`-1` ("Disabled") via the live editor bridge. **This change did not take
effect for the currently-running editor process** - a full editor restart
(quit + relaunch) was required before new Play sessions actually launched
without `--embedded`. Once they did, the native Finder picker started
working immediately, no other code changes needed.

This is a per-developer editor preference, not something the project's own
files control - if a future session (or a different machine/user) sees the
native dialog silently not appear again, check this setting first, and
remember an editor restart is required after changing it.

## Bug 3: fallback dialog opened in "Save" mode - FIXED

While diagnosing Bug 2, the fallback `FileDialog` node was visible (native
wasn't working yet) and showed a "Save" button instead of "Open" -
`FileDialog.file_mode` defaults to `4` (`FILE_MODE_SAVE_FILE`) when not set
explicitly, confirmed via local `--doctool` docs. Every other `FileDialog` in
this scene (`OpenPresetDialog`, `SavePresetDialog`) has the identical latent
bug - `OpenPresetDialog` also never sets `file_mode` and has been running in
Save mode by accident the whole time, working only because its handler just
reads the picked path rather than actually saving anything. Only
`ImportDialog` was fixed (`file_mode = 0`); `OpenPresetDialog` was flagged to
the user and deliberately left alone as out of scope.

## Bug 4: stray tab indentation - parser error, unrelated to the above - FIXED

An edit to `_open_import_dialog`'s error-handling branch introduced one
extra tab of indentation on a single line
(`import_dialog.popup_centered_ratio(0.82)` inside the `if err != OK:`
block), breaking the whole script's parse. **This was verified as "clean" by
`godot --headless --path . --import` multiple times before the user actually
hit it** - `--import` mainly drives the asset importer (fbx/png/etc.), not a
full project-wide GDScript compile check, so it does not reliably catch
syntax errors in scripts that aren't touched by the asset-import pass.

**Lesson for future edits to this file**: verify GDScript changes by
actually loading the scene (parses the root script fully), not just
`--import`:
```
godot --headless --path . tools/character_editor/character_editor.tscn -- character=player dump_bones=__no_match__
```
`--import` is still useful for forcing new/renamed `class_name` files to be
picked up (see the retargeting adapter rename earlier this session), but
it's not a substitute for an actual load/compile check.

## Bug 5 (unrelated, found via the same import test): transparent imported materials - FIXED

Not part of the file-picker saga, but found while verifying the import
feature end-to-end with a real file (`Ch28_nonPBR.fbx`): every material on
the imported character had `transparency = TRANSPARENCY_ALPHA_DEPTH_PRE_PASS`
and `albedo_color.a = 0.8`, making the whole character semi-transparent
(eyeballs visible through skin/clothes). Almost certainly Godot's FBX
importer auto-detecting an alpha channel in the source texture and assuming
it means the surface should be translucent. Fixed in
`character_editor.gd`'s `_disable_mesh_transparency()`, applied only to the
import pipeline (`_create_custom_character_adapter`) - the curated
characters already render correctly without this, so it isn't applied
universally.

## Bug 6 (also found via the same import test): normal/roughness maps never wired up - FIXED

Also found on `Ch28_nonPBR.fbx`: the user noticed the imported character's
texture "seems so plain." Inspecting the material showed only
`albedo_texture` set - `Ch28_nonPBR_1/2/3.png` existed as extracted files
but weren't referenced by any material property at all. Direct visual
inspection of each file confirmed `_2.png` is a real roughness/AO map
(grayscale, follows the same UV layout as albedo, with real per-material
tonal variation - skin vs. fabric vs. rubber sole) and `_3.png` is a real
tangent-space normal map (dominant blue channel, visible wrinkle/seam
detail). Ruled out the import pipeline as the cause by diffing
`Ch28_nonPBR.fbx.import` against the already-correctly-imported
`Ch08_nonPBR.fbx.import` (from earlier in this session, imported the normal
way, not through this feature) - byte-identical import settings aside from
the auto-generated UID/cache path, and ­Ch08 DOES get its normal map
auto-wired. The difference is in what each source FBX's own material graph
references; Godot's importer can only follow that, not infer it when it's
missing or uses a slot layout the importer doesn't recognize.

Fixed with a post-import pass (`_fix_unwired_textures` +
`_classify_texture_role` in `character_editor.gd`) that scans sibling
`<basename>_N.png` files next to the albedo texture and classifies each by
actual pixel content (not assumed slot order, which isn't consistent across
sources) before wiring it in as a normal or roughness map. Two real bugs
surfaced building the classifier itself, both worth remembering for any
similar future pixel-inspection code:

- **Large near-black regions read as "grayscale" regardless of true hue.**
  Ch28's own *albedo* texture (clearly colorful - skin tones, a red eye
  texture) was misclassified as "roughness" on the first attempt, because
  the image is dominated by large areas of near-black fabric, which are
  trivially `r≈g≈b≈0` no matter what the real color content elsewhere is.
  Fixed by excluding near-black/near-white pixels from the grayscale
  judgment entirely (only pixels with `0.12 < value < 0.95` get judged),
  and requiring a low fraction of genuinely *saturated* pixels (HSV
  saturation, not raw channel-equality) before calling something
  grayscale - a real color texture with large black regions must still
  show real saturated pixels somewhere, and does.
- **GPU-compressed texture data distorts normal maps enough to break blue-
  channel detection.** First working version loaded textures via
  `load(path)` (ResourceLoader) + `get_image()` + `decompress()`, to avoid
  a Godot warning that `Image.load_from_file()` is the wrong tool for an
  already-imported resource. That warning is specifically about
  *exported/packed* builds not including raw source files - doesn't apply
  to this editor-only tool reading project source assets directly - but
  switching to it anyway broke normal-map detection: Godot GPU-compresses
  a newly-imported texture using a generic color preset when it doesn't
  know the texture is a normal map (exactly the case here), and
  decompressing that lossy data measurably shifted the blue-channel
  signal enough to misclassify a real normal map as "unknown." Reverted to
  `Image.load_from_file()` reading the raw source PNG bytes directly - no
  such distortion.

## Bug 7 (found after Bug 6 shipped): wired-in roughness map made everything look wet - FIXED

The user reported the imported character's texture now "looks all wet,
brillant" after Bug 6's fix. Wiring the maps in was correct; the *values*
reaching the shader weren't, for two independent reasons stacked on top of
each other:

1. **Color-space mismatch.** Normal/roughness maps encode literal numeric
   values, not perceptual color, and must reach the shader as linear data.
   Loading via `load(tex_path)` (ResourceLoader) uses the imported/
   compressed resource, which Godot stores in an sRGB-flagged GPU format by
   default for any texture it doesn't recognize as non-color data (exactly
   this case - the whole reason Bug 6 exists). Sampling an sRGB-stored
   texture applies a gamma decode in hardware before the shader sees it,
   silently brightening the roughness values. Confirmed via research (see
   sources below), not guessed. Fixed by building the material's texture
   directly from the already-loaded raw `Image` (`_linear_texture_from_image`
   via `ImageTexture.create_from_image()`) instead of going through
   `load()` a second time - raw bytes uploaded as a plain non-sRGB texture,
   sampled literally.
   - [Fix 3D Model Textures & Lighting in Godot](https://www.arsturn.com/blog/why-your-3d-models-look-wrong-in-godot-how-to-fix-them)
   - [Imported .fbx model do not have anything set on metallic and roughness - Godot Forum](https://forum.godotengine.org/t/imported-fbx-model-do-not-have-anything-set-on-metallic-and-roughness/129697)
   - [Importing .blend file results in Roughness texture being used as Metallic texture · Issue #82455](https://github.com/godotengine/godot/issues/82455)
2. **Wrong channel semantics - the real fix.** The color-space fix alone
   made things *worse*, not better (brighter shine, not less). Sampled
   actual pixel values at known fabric/shoe coordinates in `_2.png` before
   guessing again: fabric read 0.04-0.20, shoes read literal `0.0`. Under
   Godot's `roughness_texture` convention (`0` = mirror-smooth, `1` =
   fully matte), that means shoes were being rendered as a perfect mirror -
   exactly the "wet latex" look reported. This "nonPBR"-family source file
   (name is literal - see Bug 6) turns out to encode an old-style
   gloss/specular map (bright = shiny), not a modern roughness map (bright
   = matte) - the same physical concept on an inverted scale. Fixed by
   inverting each color channel (`_invert_image_values`, `1.0 - value`)
   before assigning it as `roughness_texture` - normal maps are unaffected,
   only the roughness assignment goes through the inversion. Implemented as
   raw `PackedByteArray` arithmetic rather than a `get_pixel()`/
   `set_pixel()` loop - the source texture here is 4096x4096 (16.7M
   pixels), and per-pixel `Color` round trips at that scale are slow enough
   to matter even with the import spinner (see below) giving cover for it.

Both fixes were necessary together; neither alone produced a correct
result. Verified by sampling real pixel values before each attempt, then
confirming visually via the live editor bridge - guessing twice in a row on
appearance alone before finally measuring the data directly is the mistake
worth remembering here.

## Spinner during import - built, then found to be structurally unfixable, replaced with a static message

The multi-second gap between picking a file and the character/animation
appearing had no feedback at all. Added an indeterminate spinner (animated
Unicode braille frames prefixing `status_label.text`, driven from
`_process()` via `_update_import_spinner()`) rather than a percentage bar -
the editor round-trip (file copy + Godot's importer + skeleton inspection,
plus retargeting for animations) has no well-defined progress fraction to
report, since duration depends on file size and importer behavior neither
of which this tool can predict. Also disables both Import buttons for the
duration to prevent a re-entrant double-import.

**The user reported never seeing it ("i don't see the spinner"), repeatedly,
across several rounds.** Each round ruled out a different wrong guess:

1. First guess: stale Play session predating the spinner code (plausible,
   since script changes never hot-reload into an already-playing scene -
   a real recurring gotcha in this tool, see this doc's other bugs). A
   temporary `print()` inside `_update_import_spinner()` showed 156 correct
   updates during one real import, which read as confirmation this was
   just a stale-session issue. It wasn't re-tested after that.
2. User reported it again after a confirmed fresh session, plus "it gets
   freeze a few seconds" - a stronger symptom than "just not visible."
   Brought the played window to the foreground on the native dialog's
   callback (`DisplayServer.window_move_to_foreground`), reasoning the
   native macOS file picker might close without returning the window to
   the front. Verified via a temporary file-based log (bypassing the MCP
   bridge entirely, since a bridge screenshot request routes through the
   editor process and was separately confirmed to be an unreliable way to
   observe timing during an import - see below) that `_process()` ticks
   continuously with no gaps and `DisplayServer.window_is_focused()`/
   `window_can_draw()` both report `true` for the entire import. This
   fix did not resolve it either.
3. User reported "still don't see the spinner, only the import buttons get
   disabled while all freezes." That's the key clue: SOME rendering
   happens (the disabled button state becomes visible), then nothing else
   updates on screen until the character suddenly appears - despite the
   script-level proof from step 2 that the underlying logic keeps running
   correctly the whole time. Tested whether this scales with file size
   using a 340KB test animation clip instead of the 50MB Ch28 FBX: same
   exact pattern (buttons disable, no spinner), but with no perceptible
   freeze, since the whole import completed in ~1.4s - too fast to notice
   the same frame-skipping that's obvious over several seconds. This
   confirms the issue isn't proportional to import cost (ruling out a GPU/
   CPU contention theory); the window simply never presents a new frame
   between "import started" and "import finished," for ANY duration.

**Root cause (best available explanation, not fully instrumentable further
with tools on hand)**: the actual reimport work (`EditorFileSystem.
reimport_files()`, see `pose_debugger_plugin.gd`'s `_import_asset()`) runs
synchronously on the *editor* process's own main thread, and this scene
plays under `--remote-debug` inside that same editor. The played process's
own script execution keeps ticking normally throughout (proven twice, by
two different diagnostics), but its window does not appear to actually
present a new frame to the screen until the editor process becomes
responsive again - most likely because frame presentation for a remote-
debugged played window is gated on some sync point with the editor that a
fully synchronous, blocking editor-side call starves. This is a structural
characteristic of playing a scene inside the editor during heavy synchronous
editor-side work, not a simple logic bug in this tool's own code - there
was no one-line fix available for it.

**Fix**: removed the animated spinner infrastructure entirely
(`_IMPORT_SPINNER_FRAMES`, `_import_status_message`, `_update_import_spinner()`
and its `_process()` call) and replaced it with one static status message
set synchronously in `_on_import_file_selected()`, before the first
`await` - the one point in the whole import path proven to actually render,
since it runs in the same frame as the button-disable that the user could
already see. Also removed two now-pointless mid-import status updates
(a "Retargeting..." message inside `_import_animation`) that could never
have been visible for the same reason.

**Diagnostic methodology note**: MCP bridge commands (`capture_live_pose`,
etc.) route through the editor process, not directly to the played scene -
a screenshot request issued while the editor is synchronously blocked
reimporting will itself stall, for up to its own hardcoded timeout,
independent of how long the actual import takes. A background small-file
import that completed in 1.4 seconds still caused four separate screenshot
attempts to time out at their ~8-second ceiling - this is a bridge queuing
artifact (only one command appears to be reliably in flight through the
debugger session at a time), not evidence about the played window's actual
render timing. The file-based log (writing straight from the played
process's own script to a local file, bypassing the bridge) is what
actually characterized this bug correctly; screenshot-based bridge timing
during an in-progress import cannot be trusted.

**Lesson**: "the logic is provably correct" and "the user can see it working"
are different claims, and proving the first doesn't establish the second -
this took three full rounds because each fix targeted a plausible cause for
invisibility (staleness, window ordering) without confirming those were
actually what was happening, rather than first establishing what category
of problem it even was (logic bug vs. rendering/presentation bug). The
turning point was a controlled A/B test (small file vs. large file) the
user ran on request, which is the same "ask for a precise repro instead of
guessing a third variation" lesson from Bug 9, applied one more time.

## Bug 8 (pre-existing, unrelated to the import feature itself): "Reset All" crashed on any non-Player character - FIXED

Not caused by anything in this feature - `_on_reset_all_pressed()` has
unconditionally written to `_held_object.position/rotation/scale` since
before this session, and `_held_object` is only ever non-null for Player
(`supports_held_object == true`). This just had no way to surface until
non-Player characters were actually selectable and something prompted
someone to click "Reset All" while one was loaded - both of which only
became possible once the character-selector and import features existed.
User reported "the skin mesh disappears" after loading a character and
clicking Reset. Confirmed the exact mechanism via the live bridge (a
temporary `test_reset_all` debug hook, since removed) rather than guessing
from the symptom:

```
SCRIPT ERROR: Invalid assignment of property or key 'position' with value
of type 'Vector3' on a base object of type 'Nil'.
   at: _on_reset_all_pressed (character_editor.gd:1967)
```

The crash aborts the function immediately - `_sync_bone_controls()`,
`_sync_object_controls()`, and critically `_refresh_skeleton()` never run.
`_modifier.reset_all()` (the line *before* the crash) had already partially
applied, with no follow-up skeleton refresh to correctly reflect it - the
most likely explanation for the mesh visually breaking rather than just the
reset silently failing. Fixed by guarding the whole held-object block with
`if body.supports_held_object:`, matching the pattern already used
elsewhere in this file (see `_run_automation_args`) - `_on_reset_bone_pressed`
was checked too and never touched `_held_object` in the first place, so it
was already safe.

**Side lesson, not specific to this bug**: a GDScript *parse* error (not a
runtime one) in a headless scene-load verification command
(`godot --headless --path . tools/character_editor/character_editor.tscn -- ...`)
does not exit promptly with an error - it hangs indefinitely, since there's
no valid `_ready()` to ever reach the automation args' `quit()` call. Where
earlier bugs in this doc showed up as fast, clean `SCRIPT ERROR` output,
this one instead looked like the verification command was simply stuck.
Worth checking for a fresh typo/type-error before assuming a real infinite
loop when a verification run that's normally instant suddenly hangs.

### Bug 8 continued: the crash fix alone did NOT resolve the reported symptom

User reported "reset makes the skin disappear still" after the crash fix
above shipped, clean and confirmed. This was a real, important signal, not
noise: the crash fix was correct and necessary, but it was never the
*actual* cause of "the skin disappearing" - that phrase was a description
of a second, independent bug in the exact same function, on Player
specifically (where `_held_object` is never null, so the crash fix changes
nothing about this code path at all).

`_on_reset_all_pressed()` unconditionally sets `_held_object.scale =
Vector3.ONE` (100%). The flashlight's actual default size is
`DEFAULT_OBJECT_SCALE` (12%) - resetting to 100% balloons it to roughly
8x its normal size, engulfing the character's head and torso. That reads
exactly like "the skin disappearing" (it's still there, just completely
hidden behind an oversized flashlight model) without looking like the
literal words would suggest.

Caught by trusting the report over the first fix's own verification: the
first fix's `test_reset_all` diagnostic only checked `mesh.visible` (stayed
`true`) and that the function completed without erroring (it did) - both
correct, neither sufficient. Rebuilt the diagnostic
(`test_reset_all_visual`, since removed) to capture a real screenshot
before/after instead of trusting a boolean flag, which showed the actual
oversized-flashlight render immediately. Fixed by using
`Vector3.ONE * DEFAULT_OBJECT_SCALE` instead of `Vector3.ONE`.

**Lesson**: "still happening" after a confirmed, verified fix means the
verification missed the real symptom, not that the user is wrong or the
fix didn't apply. Re-diagnose from the report again rather than assuming a
stale test session explains it away a second time - that explanation was
correct for the spinner report earlier in this same conversation, which
made it tempting to reach for again here, and would have been wrong.

### Bug 8, third occurrence: "New Preset" had the identical bug, in a different function

User reported "still happening" a *third* time, after explicitly confirming
(asked directly, not assumed) that this was a genuinely fresh Play session
with the scale fix in place - and a live re-test of `_on_reset_all_pressed`
on that fresh session showed it working correctly. That combination meant a
third, distinct code path with the same symptom, not a verification gap in
the same one.

Searched for every other call site sharing the same `_modifier.reset_all()`
marker (the one line common to every "reset everything" button) rather than
guessing which button the user meant a third time. Found `_on_new_preset_
pressed()` ("New" button, `PresetRow`) with the exact same two bugs as
`_on_reset_all_pressed` - unconditional `_held_object` access, and `Vector3.
ONE` instead of `DEFAULT_OBJECT_SCALE`. Its crash path specifically was
never reachable in practice (`preset_row.visible = body.supports_held_
object` hides this button entirely for non-Player characters), but the
scale bug was fully reachable on Player, which is exactly the character
this button is visible for - explaining why the first two fixes (one
gated behind a character type that couldn't even see this button, one
fixing a *different* function) never touched what the user was actually
clicking.

Also hardened `_load_pose_from_path()` itself (shared by the "Open" preset
button, `_run_automation_args`' `pose=` CLI option, and the default pose
load on character switch) with the same guard, since it has the identical
unconditional pattern and multiple callers - fixing it once at the source
rather than patching each call site. Its own crash path isn't reachable via
UI today (load/save is also hidden for non-held-object characters) but the
CLI path (`character=ch08 pose=some_preset.json`) had no such protection.

**Lesson**: once the same bug shape has been found twice in one file,
search for every structurally similar call site before declaring victory a
third time, rather than fixing one instance and hoping it was the only one.

## Bug 9: "Reset Camera View" nulled the face mesh entirely on any non-Player character - FIXED

While re-verifying Bug 8's fixes, the user pushed back on testing methodology
directly ("how are you testing it? is still happening, check what i see")
and asked me to check the actual state of their currently-running session
instead of running another isolated repro. A screenshot of that live session
(`current_state.png`) showed Ch28's face rendering nearly solid black with
faint highlight lines - a third, previously undiagnosed visual defect
distinct from Bug 8's giant-flashlight and missing-mesh symptoms. This took
three rounds of investigation and two wrong conclusions before landing on
the real cause - recorded in full below because the wrong turns are exactly
the kind of thing worth not repeating.

**Wrong conclusion #1 - "it's lighting, not a bug".** A temporary
`dump_current_state` diagnostic showed the loaded character's material
properties all looked normal (`albedo_texture`, `normal_texture`,
`roughness_texture` all correctly wired, confirmed against the source PNGs
directly too - the face region of the albedo atlas is genuinely
skin-toned). A fresh reimport into a clean session rendered correctly.
Comparing screenshots, `current_state.png` showed the *entire* character
looking uniformly dark, which read as a backlit-silhouette lighting problem
rather than a broken material. Reported this to the user as "likely
lighting, not a bug" and asked them to try to reproduce it.

**Wrong conclusion #2 - "Ch28_Body has no material".** The user reproduced
it immediately on the very next attempt ("i just did it and happened").
Re-ran the diagnostic against their actual live session this time instead
of a fresh one of my own, and found `Ch28_Body` (the mesh carrying the
face, neck, and hands) reporting `material_class: null` on its only
surface, while every other mesh part had a normal material. Built a fix
(`_fix_missing_materials`) that reused a sibling mesh's material for any
surface missing one, verified it against several fresh reimports (all
came back correctly), and reported it fixed.

**Still wrong.** The user tested it themselves and reported "no progress" -
still black, and asked directly whether I was actually verifying each time.
I wasn't reproducing their actual sequence: 10 further automated attempts
(5 fresh imports, 5 character switches via `set_live_character`) all came
back completely clean - `_fix_missing_materials` never found anything to
fix. That mismatch was the real signal that my test procedure differed from
the user's, so I asked them directly for their exact click sequence rather
than guessing a third time. Answer: "import, then click reset camera."

That pointed straight at `_on_view_selected()` (called by both the view
picker and `_on_reset_camera_view_pressed`, i.e. "Reset Camera View"):

```gdscript
body.mesh.mesh = (_isolated_attachment_mesh
        if index == 2 and _isolated_attachment_mesh != null else _full_body_mesh)
```

`_full_body_mesh` is only ever populated in `_load_character` when `body.
supports_held_object` is true (Player only, for the flashlight close-up/
isolated-attachment views) - every other character leaves it explicitly
`null`. `body.mesh` is `adapter.meshes[0]`, which for Ch28 is `Ch28_Body` -
the exact face mesh. Selecting the "Full body" view (index 0, what "Reset
Camera View" always selects) unconditionally executed this line and
assigned `null` to `Ch28_Body`'s actual mesh *resource* - not its material.
A `MeshInstance3D` with `.mesh == null` renders nothing at all, leaving a
face-shaped hole that shows the black scene background straight through it,
with `Ch28_Hair`/`Ch28_Eyelashes` (separate meshes) still rendering around
the edges - exactly the "black face with faint highlight lines" the user
described. Confirmed directly: calling `set_live_view mode=full` on a
working Ch28 instantly reproduced it, and a diagnostic reporting `mesh.
get_surface_count()` per mesh (not just material state) showed `Ch28_Body`
at `-1` (no mesh at all) immediately after, `1` (correct) before.

This also explains wrong conclusion #2's `material_class: null` reading -
`get_active_material()` on a `MeshInstance3D` with a null `.mesh` also
resolves to null, so that diagnostic was seeing a symptom of the same mesh-
nulling bug, not a separate FBX-importer material-synthesis failure. There
never was an importer flakiness issue.

**Real fix**: guarded the mesh swap in `_on_view_selected()` with `if body.
supports_held_object:` - the swap is only ever meaningful for the character
that actually has `_full_body_mesh`/`_isolated_attachment_mesh` populated.
Every other character now leaves `body.mesh.mesh` untouched when switching
views, which is correct since they have no isolated-attachment feature to
begin with. Removed `_fix_missing_materials` entirely (dead code addressing
a misdiagnosed cause) along with its call site and tracking var. Verified
by reimporting Ch28, calling the exact `set_live_view mode=full` action
that used to break it, confirming `Ch28_Body`'s mesh surface count stayed
at `1`, and screenshotting a correctly-rendered face.

**Lesson**: when repeated automated repro attempts don't reproduce a bug the
user hits reliably, that mismatch is itself the most important signal -
don't paper over it with a plausible-sounding fix for whatever *did* show up
in testing (Bug 9's `material_class: null` reading was real, but was a
downstream symptom, not the cause). Ask the user for their exact action
sequence instead of guessing a third time; five minutes of a precise
question saved another wrong-fix round trip. Also: a `null` value can mean
two very different things depending on which property is null (a
`Material` vs. a `Mesh` resource) - "the face is black" is consistent with
several different underlying nulls, and screenshots alone can't
disambiguate them from each other.

## Diagnostic technique used throughout

Several of the above were confirmed via temporary one-off commands added to
`addons/mcp_bridge/commands.gd` (e.g. `check_display_features`,
`check_embed_settings`, `dump_material_info`), called directly over the raw
TCP bridge protocol with a `python3 -c` one-liner rather than guessing from
symptoms - `commands.gd` reloads fresh from disk on every request, so this
requires no editor restart to iterate on. Each diagnostic was removed again
once its answer was found; only `rescan_filesystem` was kept as genuinely
reusable. This is faster and more reliable than reasoning from screenshots
alone when the live editor is available - see `AGENTS.md`'s "check engine
source before hand-deriving" guidance for the same principle applied to
engine internals specifically.
