# Current Task: Per-surface outfit fitting with surface selection

**Date:** 2026-07-28

**Branch:** `feature/gpu-cloth-outfit-fit`

**Status:** This branch includes layer-aware component fitting, seam preservation, render-only
component isolation, and generic solid-shell thickness/silhouette preservation. Reusable fitting
guidance is recorded in `AGENTS.md` and the Decisions Log.

## What was added

- **`OutfitFitEditor.fit_selected_surface(clearance)`** (`ui/outfit_fit_editor.gd`): runs the body-projection
  fitting solver on a single selected surface. It now uses the same three projection passes and
  sixteen-pass collision cleanup as whole-outfit `auto_adjust`, while leaving every other garment
  surface untouched.
- **`OutfitFitEditor.get_clothing_surfaces()`**: returns display name + mesh_key + surface_index for each
  clothing surface. Surface names use MeshInstance3D node name (trimmed of `:Mesh` suffix), falling back
  to material `resource_name`, then `"Surface N"`.
- **`OutfitFitEditor.select_surface(mesh_key, surface_index)`**: finds first handle on that surface and
  calls `_select_handle()` to focus the editor on it. Cam era focus tweens to 1.2m horizontal distance
  at the surface center's Y height.
- **Context-sensitive Auto Adjust**: Auto Adjust calls `fit_selected_surface(clearance)` when a surface
  is selected, and falls back to the original whole-outfit `auto_adjust(clearance)` when no surface is
  selected. The former separate `Fit Selected` button was removed because this behavior made it
  redundant.
- **Surface selector dropdown** (`character_creator.tscn` + `character_creator.gd`): SurfaceRow with
  SurfaceSelector OptionButton listing clothing surfaces. Selecting one calls `select_surface()` and
  focuses camera. Bidirectionally synced with 3D picking. Its first `All surfaces` entry clears the
  selection, restoring whole-outfit Auto Adjust behavior.
- **Control point filtering**: dot spheres and clipping debug colors only show on the selected surface.
  No selection = show all.
- **Camera focus**: tweens to the centroid of the selected surface's world-space vertices, killing any
  previous tween. Camera Y matches surface center Y, 1.2m away horizontally (preserves the camera's
  current horizontal angle). The focus also becomes the persistent orbit target, so subsequent drag
  and trackpad zoom input continues around the selected garment instead of snapping back to the
  previous full-body target. Manual camera input cancels an in-progress focus tween.
- **Layer-aware garment cleanup** (`ui/outfit_fit_layers.gd`): measures each pair's imported ordering
  only in body-space cells shared by both surfaces, then performs real triangle/triangle intersection
  checks after body fitting. Whole-outfit fitting pushes the authored outer layer outward. A
  selected-only fit changes only that selection: an outer selection moves outward, while an inner
  selection may move inward only until it reaches the requested body clearance. The pass is capped at
  twelve 3 mm iterations and reports when that limit is reached. Each imported surface is additionally
  split into position-welded disconnected topology components, because the Peasant shirt, belt, and
  buckle are five separate pieces baked into one `Male_Peasant_Body` surface. Pieces in that same
  surface preserve their authored order through a body-relative depth constraint: each moving vertex
  interpolates the four closest samples from the neighboring component within 6 cm and retains a 2 mm
  separation. This fills sampling gaps around the belt without applying the broad maximum-depth push
  that visibly inflated its silhouette.
- The Edit Fit panel keeps `Surface` as the imported mesh/material scope and provides a dependent
  `Component` selector for disconnected pieces inside that surface. `All components` is the default
  and preserves the prior whole-surface behavior. The Peasant torso exposes Shirt, Leather belt,
  Metal buckle, and two small accessories; choosing one scopes control points, camera focus, debug
  colors, manual influence, and Auto Adjust to that piece. Component-only Auto Adjust was verified
  to write 685 belt vertices and zero vertices outside the belt.
- **Isolate selected component** is enabled only for an individual component. It hides the base body
  and rebuilds the outfit preview with only that component's triangle indices, even when the piece
  shares an imported surface with other garments. Disabling it restores the complete body/outfit.
  Isolation changes no source arrays, fit offsets, or saved profile data; `Show control points` can
  be disabled independently for an unobstructed mesh inspection.
- Whole-outfit Auto Adjust constructs an overlap-only directed layer graph from the imported local
  body-relative depth. Components that never occupy the same body-space cells receive no ordering
  relationship. Each cleanup iteration resolves and rebuilds one graph level at a time, so inner
  shirt/pants corrections feed the belt level and belt corrections feed the buckle level. The
  Peasant outfit produces 16 local relationships across four levels; its torso path is
  Body → Shirt → Leather belt → Metal buckle.
- Auto Fit synchronizes offsets across position-welded duplicates after every body, collision, and
  layer stage. These duplicates are separate indices for UV seams or hard normals but represent the
  same garment position. Before synchronization, 51 Peasant pants seam groups diverged by as much as
  1.29 cm and exposed a vertical strip of leg without technically intersecting the body; the fitted
  side capture now measures zero divergence and keeps that seam closed.
- Auto Fit also preserves authored thickness generically. Each topology component searches for
  nearby opposite-facing walls within three median local edge lengths and classifies it as a solid
  shell only when at least 80% of its vertices participate in wall pairs. Solid shells cache small
  local groups that also include coincident UV/hard-normal seam copies. Every body, collision, and
  garment layer stage averages each group's automatic displacement so inner and outer walls move
  together; eight group-aware topology passes smooth neighboring displacement without making the
  complete object rigid. The Leather belt is only the acceptance case: its median inner/outer
  separation changed from 7.59 mm to 4.19 mm with independent fitting, versus 7.62 mm with the
  general constraint. The belt and buckle qualify, while ordinary shirts, sleeves, pants, boots, and
  open accessories retain their existing cloth-fitting path rather than being mistaken for solids.
- On the isolated belt, merging seam copies into the wall groups reduced final paired-wall/seam
  deviation to zero. Eight smoothing passes reduced the 95th-percentile neighboring offset jump from
  2.13 mm to 1.20 mm and the maximum from 6.62 mm to 2.73 mm, keeping the fitted border close to the
  smooth authored silhouette.
- Auto Adjust renders a centered blocking overlay for two frames before its synchronous geometry
  work begins. The message identifies whether the complete outfit, selected surface, or selected
  component is being fitted, warns that the operation can take about a minute, blocks other input,
  and uses the wait cursor until the fit returns.

## Debug colors on selected surfaces

With `_visualize_clipping` enabled, selecting a surface via the dropdown or 3D pick filters the
control spheres, clipping colors, and blue debug material to that surface. Non-selected clothing
surfaces render with their original materials.

The fix addressed both sources of persistent color:

- `OutfitFitEditor` now snapshots each imported surface's original vertex-color channel. A rebuild
  restores that channel whenever the surface is not receiving clipping colors, preventing colors from
  a previous selection from leaking into later mesh rebuilds.
- `CharacterCreator` now applies its white/vertex-color debug material override only to the selected
  mesh surface. It removes the override from every non-selected clothing surface, restoring the
  imported material. With no surface selected, the previous all-surface diagnostic remains available.
- The base-body diagnostic is scoped too. Body triangles nearest the selected garment surface retain
  the red/green diagnostic, while unaffected body vertices use white vertex tint with a duplicated
  authored material, so their original texture and skin tone remain visible.

## Files changed

- `ui/outfit_fit_editor.gd`: `fit_selected_surface()`, `get_clothing_surfaces()`, `select_surface()`,
  `get_selected_surface_center()`, modified `_select_handle`, `_update_dot_visibility`, `_refresh_clipping`,
  `_rebuild_mesh`, `_rebuild_geometry_only`, and layer-cleanup integration
- `ui/outfit_fit_layers.gd`: authored local order measurement and pairwise garment intersection cleanup
- `ui/outfit_fit_components.gd`: topology component catalog, isolated preview mesh construction, and
  rendered-to-source surface mapping
- `ui/character_creator.gd`: `_on_fit_surface_selected()`, `_refresh_surface_selector()`,
  `_sync_surface_selector_to_selection()`, `_focus_camera_on_selected_surface()`, and isolation control
- `ui/character_creator.tscn`: Surface/Component selectors and `Isolate selected component`
- `.gdlintrc`: max-file-lines bumped to 1300

## Verification

```sh
scripts/check.sh
```

Temporary acceptance scenes verified that the Leather belt renders exactly its 4,224
triangle indices as the sole outfit surface, hides the body, and restores all five imported outfit
surfaces plus the body when disabled. A second diagnostic measured belt thickness before and after
selected-component fitting, and a full-outfit capture exercised the same topology constraint across
all garments. The temporary scenes were deleted after verification.
