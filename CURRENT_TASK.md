# Current Task: Per-surface outfit fitting with surface selection

**Date:** 2026-07-28

**Branch:** `feature/gpu-cloth-outfit-fit`

**Status:** This branch includes layer-aware component fitting, seam preservation, render-only
component isolation, and generic solid-shell thickness/silhouette preservation. Reusable fitting
guidance is recorded in `AGENTS.md` and the Decisions Log.

## What was added

- **`OutfitFitEditor.fit_selected_surface(clearance)`** (`ui/outfit_fit/editor.gd`): runs the body-projection
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
- **Layer-aware garment cleanup** (`ui/outfit_fit/layers.gd`): measures each pair's imported ordering
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
- **Rigid component shape preservation** snapshots every component accepted by bone-aware distal-limb
  alignment, lets ordinary contact fitting propose its clearance positions, then replaces the
  nonuniform result with one best-fit translation/rotation/uniform-scale transform from the aligned
  baseline. The rule covers the complete position-welded component, including foot shell/sole
  structures and all shaft/cuff islands. Preserving only follower cuff islands restored the upper
  layer but left the shaft rim with more than 5× edge-scale spread; preserving only shaft/cuff left
  each foot with more than 3× spread and produced the catastrophic open rings visible from underneath.
  Combining foot and shaft into one transform closed the mesh but prevented the articulated ankle
  from settling and exposed the foot. Giving each logical component its own similarity transform
  keeps the sole, foot, shaft, and layered cuff structurally intact while retaining their bone-aware
  articulation. Same-side rigid components are connected by a cached nearest-boundary graph. The
  fitted shoe remains the distal anchor and the shaft receives at most 3 cm of horizontal X/Z
  correction; vertical correction is deliberately excluded because a full hard joint exposed the
  toes or dragged the cuff into the pants. Scale uses the 90th percentile of projected requested
  clearance, combined with the least-squares result, and is capped to 1.0–1.12 of the bone-aligned
  baseline so fitting cannot thin an authored rigid shell; higher percentiles still left body
  penetration while enlarging the boot. The final
  constraint runs after seam
  synchronization so later averaging cannot reintroduce distortion. The resulting boot silhouette
  is substantially better and its shells remain closed, but manual underside/rear inspection still
  shows body penetration. Any remaining intersection beneath a
  classified rigid opaque component becomes a fitted body-triangle render mask: normal rendering
  omits those covered body triangles plus one edge-connected triangle guard band to prevent
  low-poly cracks, clipping-debug mode restores the complete source body, and
  `Save` persists the mask in the body/outfit profile so it is regenerated on load without changing
  the imported body mesh.
- **Bone-aware distal-limb alignment** (`ui/outfit_fit/limb_aligner.gd`) runs before contact fitting.
  A topology component qualifies only when at least 85% of its skin weight belongs to one side's
  calf/shin/foot/ankle/ball/toe chain. For every matching body/outfit bone, the pass maps the
  outfit's global rest frame into the body's frame, blends those rigid transforms with the
  garment's existing skin weights, and writes the resulting rest-space offsets before projection.
  This preserves an articulated boot's authored shaft/foot shape instead of asking independent
  contact vertices to absorb a gross skeleton mismatch. The Male Peasant diagnostic selected only
  four boot components (1,878 vertices). Its corresponding leg rotations already match at 0°; the
  real mismatch is a mirrored 23.7 mm lateral rest offset, now corrected before Auto Adjust.
  These aligned rigid components then enforce the requested clearance as a true minimum plus a
  5 mm sub-triangle safety margin. Ordinary layered cloth retains outward-only correction, while
  the extra rigid margin prevents a low-poly boot face from remaining nearly coplanar between
  otherwise-clear corner vertices.
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
- **Compare with original** creates a read-only source-mesh duplicate to the left of the live fitted
  character and labels both views. The duplicate replaces every rebuilt outfit mesh with its captured
  imported `ArrayMesh`, so loaded profiles, manual edits, and Auto Adjust never leak into the original
  side. Both characters share the current body/cosmetics, materials, pose, orbit, and zoom. Comparison
  temporarily disables debug colors and control points for an authored-material inspection, disables
  component isolation, and restores the exact prior toggles and single-character camera framing when
  turned off. It cannot participate in fitting or saving.
- **Free camera** is an optional Edit Fit inspection mode that preserves the current orbit framing,
  captures the mouse for unrestricted look, and uses WASD for movement, Q/E for world-down/up, and
  Shift for faster travel. Selecting another surface does not steal focus while it is active. Escape,
  closing Edit Fit, or leaving the scene releases the cursor and restores the exact orbit view; it can
  remain enabled while comparing original and fitted characters.
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

## Paused / incomplete: rigid boot body coverage

Work is paused here pending a more reliable way to suppress body geometry covered by closed rigid
garments. The current experimental branch state is deliberately **not committed**.

What currently works:

- Bone-aware alignment removes the large left/right rest-frame offset without twisting the boot.
- A separate similarity transform per rigid topology component preserves the authored foot, shaft,
  sole, cuff, and layered borders substantially better than per-vertex fitting.
- Rigid scale is bounded to `1.0–1.12`, so the solver may add modest clearance but cannot shrink and
  thin the authored shell.
- Front and ordinary side silhouettes are broadly acceptable. The remaining failure is easiest to
  see from the rear and underside.

What is still wrong:

- Body calf/foot triangles remain visible through the boot shaft and beneath the sole after
  `Reset All` → `Auto Adjust`.
- Clipping debug correctly restores the complete body and shows these contacts in green. With debug
  disabled, the experimental render mask removes some contacts but still leaves triangular skin
  fragments; a one-edge-connected guard band did not visibly resolve the failure.
- The pants/upper-cuff overlap also remains to be evaluated after body coverage is solved.

Rejected or insufficient approaches:

- Per-vertex projection opened and stretched rigid boot shells.
- One transform for the complete boot prevented ankle articulation.
- Independent components without a tether drifted apart; a full 3D hard joint either exposed the
  foot or pulled the cuff into the pants. The current horizontal-only tether is the best result.
- A permissive `0.5–1.5` similarity-scale range grossly oversized the shoes.
- Restoring the requested-scale percentile from 90% to 98%, even with the tight `1.0–1.12` bounds,
  still left calf/sole penetration while enlarging the garment.
- Masking only directly intersected body triangles under rigid opaque components, followed by one
  shared-edge dilation pass, is incomplete. Do not keep adding blind dilation passes: that risks
  deleting body triangles that should remain visible above an opening.

Recommended resumption:

1. Add temporary diagnostics comparing the complete debug-clipped body-triangle set against the
   rigid-only occlusion set, including per-component and per-body-surface triangle counts. The likely
   issue is that the visible patches are detected through garment pieces not present in
   `rigid_fit_components`, or are fully protruding body triangles that never form the intersection
   configuration used by the current mask.
2. Inspect which of the four aligned Peasant boot components produces each calf/sole patch before
   changing thresholds.
3. Prefer an explicit covered-body classification—such as body skin-weight regions demonstrably
   enclosed by a closed opaque distal garment, or a saved authorable body mask—over further boot
   enlargement or unbounded adjacency dilation.
4. Preserve clipping-debug behavior: it must always restore the complete source body so masking
   cannot disguise unresolved fit contacts during calibration.
5. Validate both normal-material and clipping-color captures from front, rear, side, and underneath
   before keeping the mask, updating the decision log, or committing.

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

- `ui/outfit_fit/editor.gd`: stateful façade with `fit_selected_surface()`,
  `get_clothing_surfaces()`, `select_surface()`,
  `get_selected_surface_center()`, modified `_select_handle`, `_update_dot_visibility`, `_refresh_clipping`,
  `_rebuild_mesh`, `_rebuild_geometry_only`, and layer-cleanup integration
- `ui/outfit_fit/solver.gd`: body-contact, collision, and ordered garment-layer fitting pipeline
- `ui/outfit_fit/limb_aligner.gd`: weighted outfit-rest to body-rest alignment for distal garments
- `ui/outfit_fit/visualization.gd`: body triangle cache and temporary clipping debug meshes
- `ui/outfit_fit/body_occlusion.gd`: experimental rigid-garment body intersection mask,
  profile encoding, and one-edge guard band
- `ui/outfit_fit/presentation.gd`: Character Creator material overrides for normal/debug previews
- `ui/outfit_fit/layers.gd`: authored local order measurement and pairwise garment intersection cleanup
- `ui/outfit_fit/components.gd`: topology component catalog, isolated preview mesh construction, and
  rendered-to-source surface mapping
- `ui/character_creator.gd`: `_on_fit_surface_selected()`, `_refresh_surface_selector()`,
  `_sync_surface_selector_to_selection()`, `_focus_camera_on_selected_surface()`, and isolation control
- `ui/character_creator.tscn`: Surface/Component selectors and `Isolate selected component`
- `.gdlintrc`: the project-wide 1000-line ceiling is restored after splitting the fitting subsystem

## Verification

```sh
scripts/check.sh
```

Temporary acceptance scenes verified that the Leather belt renders exactly its 4,224
triangle indices as the sole outfit surface, hides the body, and restores all five imported outfit
surfaces plus the body when disabled. A second diagnostic measured belt thickness before and after
selected-component fitting, and a full-outfit capture exercised the same topology constraint across
all garments. The temporary scenes were deleted after verification.
The persistent GPU-cloth outfit harness verified that limb alignment identifies 1,878 vertices
across four boot components and produces straighter, more symmetric boot silhouettes. Earlier front
captures suggested that the rigid-only 5 mm interpolation margin eliminated toe patches, but later
rear and underside manual inspection disproved complete coverage: large calf contacts and small sole
fragments remain. `scripts/check.sh` passes for the paused experimental state; visual acceptance does
not.
