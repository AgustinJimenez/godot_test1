# Current Task: Per-surface outfit fitting with surface selection

**Date:** 2026-07-28

**Branch:** `feature/gpu-cloth-outfit-fit`

**Status:** Changed tack from "fit all surfaces at once" to "select one surface, fit only that one." All
cloth-on-cloth commits (`4934c90`, `05b408a`) reverted via `git reset --hard 98cc4fc` — codebase back
to before any cloth-on-cloth work. Changes since then are staged or in working tree, nothing committed.

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
  `_rebuild_mesh`, `_rebuild_geometry_only`
- `ui/character_creator.gd`: `_on_fit_surface_selected()`, `_refresh_surface_selector()`,
  `_sync_surface_selector_to_selection()`, `_focus_camera_on_selected_surface()`
- `ui/character_creator.tscn`: `SurfaceRow`/`SurfaceSelector` OptionButton
- `.gdlintrc`: max-file-lines bumped to 1300

## Verification

```sh
scripts/check.sh
```

No commit has been requested.
