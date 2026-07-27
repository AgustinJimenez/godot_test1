# Current Task: Body-specific outfit fitting and cloth-layer collision

**Date:** 2026-07-27

**Branch:** `feature/gpu-cloth-outfit-fit`

**Status:** BodyRegionMask is implemented in `tools/outfit_pipeline/body_region_mask.gd` and integrated into `ui/character_creator.gd`. The character creator now uses bone-weight-based masking (DEFAULT_HIDDEN_BONES, HAND_BONES, NECK_EXEMPT_BONES) to rebuild the body mesh with covered triangles dropped, replacing the crude discard-shader baseline. The manual fitting overlay uses a direction-aware 4 cm surface grid, one scalar body distance per point, per-row reset, persistent body/outfit profiles, independently hideable control-point spheres, clipping visualization, and vertex-level automatic clearance. Its final collision pass welds coincident positions before identifying real open rims, so UV/hard-normal vertex splits no longer create false holes in collision coverage; triangles merely touching a rim are still checked. Clearance is enforced outward-only rather than used as a shared target shell, preserving authored shirt/pants/boots layer distances for vertices that already clear the body. Leg-dominant surfaces additionally match body triangles by dominant left/right bone region, raycast from outside the matching limb, move at most 3 cm per pass, and smooth the correction over welded mesh adjacency. Only detected intersection vertices and garment vertices inside the body seed corrections; however, this gross mismatch genuinely selects 2,538 vertices versus 2,696 before, taking about 11.4 seconds. The actual Male Peasant front/oblique harness keeps pants and boots smooth with fewer large leg artifacts, but a thin outer-thigh body line remains. GPU Cloth Sim is vendored only for an isolated Male Peasant harness: static fit, gentle spine motion, animated body collision, and shirt/pants peer collision work, but thigh motion destabilizes the procedurally weighted pants and the add-on reports invalid GPU resources during shutdown on Godot 4.6.2/Metal.

## BodyRegionMask implementation

`tools/outfit_pipeline/body_region_mask.gd` (`BodyRegionMask`) replaces the discard-shader baseline in `character_creator.gd` with bone-weight-based body masking:

- `DEFAULT_HIDDEN_BONES` covers torso, arms to the wrist, legs, and feet (pelvis, spine 01-03, clavicle, upperarm, lowerarm, thigh, calf, foot/ball, both sides) - what all four combinations fully cover. Hands/fingers are the deliberate exception (see "Outfit-supplied hand bridges" below) - confirmed by every render this session that both outfit styles leave hands bare.
- `HAND_BONES` is kept separately from `DEFAULT_HIDDEN_BONES`. `outfit_supplies_hand_bridge(outfit_root)` checks whether the *specific* outfit about to be shown has a bridge surface. When a bridge exists, both `DEFAULT_HIDDEN_BONES + HAND_BONES` are passed into `apply()` (hiding the base body's hand/fingers entirely for that combination) and the outfit's bridge is kept visible (not discarded). When no bridge exists, only `DEFAULT_HIDDEN_BONES` applies and the body's hand as always.
- `NECK_EXEMPT_BONES` (`neck_01`, `Head`) and `NECK_EXEMPT_WEIGHT` (`0.15`) prevent the neck/collar boundary from being hidden - a vertex already assigned to a hidden bone is exempted only when it also carries at least that much combined weight on an exempt bone.
- `apply()` rebuilds the body mesh by dropping triangles where all three vertices are hidden. This preserves boundary triangles (authored openings at collar notch, ragged sleeve/boot edges) while removing fully-covered geometry underneath clothing.
- The bridge's own texture (`T_Regular_Male_Dark_BaseColor.png`) is tinted to the selected `SKIN_TONES` value in `character_creator.gd`.

Verified on all four body/outfit combinations (Male Peasant, Female Peasant, Male Ranger, Female Ranger), front and back view each, using the plain unmodified outfit + masked body through the character creator preview.

## Active implementation

- `ui/outfit_fit_editor.gd` owns manual controls, saved offsets, automatic fitting, and diagnostics.
- `ui/outfit_fit_grid_sampler.gd` selects direction-aware garment vertices on the 4 cm grid.
- `assets/outfit_fit_profiles/` stores reusable body/outfit-specific adjustments.
- `tests/manual/outfit_cloth/gpu_cloth_outfit_test.tscn` is the isolated GPU cloth trial.
- `addons/godot_gpu_cloth/` is pinned to upstream commit `bd917afd15a8389370c7e12ec9c074555834cf68`;
  it is deliberately not enabled in `project.godot`.
- Checkpoints: `c6c7b12` (body-specific fitter) and `bf24ff5` (GPU cloth trial).

## Earlier body-masking baseline

The outfit pack's own `Readme.txt` (in the source download, `~/Downloads/Modular Character Outfits -
Fantasy[Standard]/Readme.txt`) says:

> When using the clothing, only the head of the model is required. Using the full body will result in
> clipping. (Removing the unseen parts of the body is better for performance as well.)

This is the actual root cause of every clipping problem chased in this session (see "Superseded work"
below): the outfits were never designed to have the full body rendered underneath them. The base body
(Universal Base Characters) has no separate head mesh, so "only render the head" isn't directly
possible, but the same idea generalizes: **don't render the body regions the outfit already covers.**

`tools/outfit_pipeline/body_region_mask.gd` (`BodyRegionMask`) does this:

- Bone-based first: a vertex is hidden based on which bone it's dominantly skinned to, which is fixed
  at rest pose and independent of the character's current animation pose. On top of that, two
  exemption mechanisms (both computed once at rest pose, not per animation frame) can un-hide a
  vertex the bone rule would otherwise drop: a bone-weight blend-zone signal for the neck/collar
  boundary specifically, and a geometric cloth-coverage measurement for everywhere else - see "Neck/
  collar exemption" and "Geometric cloth-coverage test" below for why both exist and neither alone is
  enough. This is NOT the same as the earlier, explicitly-rejected proximity/UV-baked approach (see
  "Removed approach" below) - that baked a continuous per-pixel visibility field from image-space
  heuristics; this measures actual 3D mesh geometry directly, once, the same way the bone-weight check
  already does.
- `DEFAULT_HIDDEN_BONES` covers torso, arms to the wrist, legs, and feet (pelvis, spine 01-03,
  clavicle, upperarm, lowerarm, thigh, calf, foot/ball, both sides) - what all four combinations fully
  cover. Hands/fingers are the deliberate exception (see "Outfit-supplied hand bridges" below) -
  confirmed by every render this session that both outfit styles leave hands bare.
- A triangle is dropped only if **all three** vertices are dominantly weighted to a hidden bone -
  boundary triangles are kept. Deliberate: authored openings (collar notch, ragged sleeve/boot edges)
  sit exactly at these boundaries, so a stray sliver of body geometry there reads as correct exposed
  skin, not a defect - whereas cutting aggressively risks a visible hole if the garment doesn't reach
  exactly as far as the bone boundary.
- Rebuilds the mesh (drops triangles) rather than using a discard shader - simpler, matches the pack's
  own performance advice, and sidesteps a real Godot rendering quirk hit while debugging the
  now-superseded coverage-overlay tool (see below).

**Verified** on all four combinations (Male Peasant, Female Peasant, Male Ranger, Female Ranger), front
and back view each, using the plain unmodified outfit + masked body: no visible clipping anywhere, only
the already-known-authored collar/hood notch and bare hands. Two real Godot API bugs were found and
fixed while testing Female Peasant (the first female mesh tried) - see "Errors and fixes" in the prior
session transcript, or the code comments in `body_region_mask.gd` - and both fixes are general
correctness requirements for `BodyRegionMask.apply()`, not per-body patches, so Male Ranger and Female
Ranger passed without needing further changes. Dramatically simpler and faster than the superseded
approach too - a masking pass costs under a second, versus the 30-50 seconds the runtime shrinkwrap fit
took per character.

## Outfit-supplied hand bridges (found and fixed after real-materials review, twice)

All this session's masking verification up to this point used flat red/blue debug materials, which
hid a real bug: with debug colors off (real textures), Male Peasant/Male Ranger/Female Ranger showed
a **hole** at the forearm - the sleeve cuff stops short of the wrist and nothing rendered between it
and the hand. Root cause, found by inspecting each `.gltf`'s JSON directly (not guessed): every one of
those three outfits ships an extra mesh primitive with material `MI_Regular_Male`/`MI_Regular_Female`
- a skin "bridge" dominantly weighted (confirmed via its own JOINTS_0/WEIGHTS_0) to `lowerarm_l/r`
plus every finger bone, meant to cover exactly the gap between the sleeve and the fingertips.
`_apply_outfit_materials()` in both `ui/character_creator.gd` and the test harness was unconditionally
discarding any surface matching that material name substring, assuming the base body would supply
that skin - but `BodyRegionMask` had already deleted the base body's forearm there, so neither source
rendered anything. (Female Peasant has no such primitive at all - its sleeve mesh alone reaches the
wrist - which is why it never showed the bug and is why hiding hands/fingers on the base body
unconditionally, tried briefly while fixing this, was wrong: it broke Female Peasant, which has
nothing to fall back on there.)

**First fix attempt (superseded, see why below):** trim the outfit's own skin-bridge surface down to
*only* the portion that bridges a region the base body's mask actually hid (the inverse of `apply()`'s
triangle-drop rule), so it fills the gap without duplicating whatever the base body still shows (the
hand). This looked completely correct in debug-colored renders on all four combinations, and was
believed fixed.

**A user screenshot afterward showed it wasn't** - a real, visible black gap between the sleeve cuff
and the hand, in the same "FULL BODY + CLOTHES" debug view that had looked clean. Root cause, found by
reading each `.gltf`'s own bone rest-pose translations directly (not guessed): the outfit's skeleton
and the base body's skeleton don't always have identical bone lengths. `Male_Peasant.gltf`'s and
`Male_Ranger.gltf`'s `upperarm_l` sits 1.7cm closer to the shoulder than `Superhero_Male_FullBody.gltf`'s
`upperarm_l` (`Female_Peasant.gltf`/`Female_Ranger.gltf`, by contrast, match `Superhero_Female_FullBody.gltf`
exactly, bone-for-bone). The trimmed bridge is skinned to the *outfit's* (shorter) skeleton; the base
body's hand is skinned to the *body's* (longer) skeleton - no amount of triangle-level trimming can
make two independently-posed skeletons meet at the same point in space. This is exactly the kind of
mismatch the project's very first shrinkwrap-fitting effort existed to paper over, just showing up here
in a new spot.

**Actual fix:** never mix the two skeletons for the same visible part. `BodyRegionMask.HAND_BONES` (new,
alongside `DEFAULT_HIDDEN_BONES`) is the hand/finger bone list, kept deliberately separate from
`DEFAULT_HIDDEN_BONES` itself. `BodyRegionMask.outfit_supplies_hand_bridge(outfit_root)` checks whether
the *specific* outfit about to be shown has a bridge surface; if it does, both call sites now pass
`DEFAULT_HIDDEN_BONES + HAND_BONES` into `apply()` (hiding the base body's hand/fingers entirely for
that combination) and use the outfit's bridge **in full, untrimmed** - so sleeve and hand are both
skinned to the outfit's own skeleton and always meet correctly, regardless of any mismatch with the
body's. Female Peasant (no bridge) is unaffected either way - `DEFAULT_HIDDEN_BONES` alone, base body's
hand as always. `trim_outfit_skin_bridge()` is gone; the untrimmed-bridge-or-base-body's-hand choice
replaced it entirely, so there's no more per-vertex trimming logic for hands at all. The bridge's own
texture (`T_Regular_Male_Dark_BaseColor.png`) has no per-skin-tone variant unlike the base body's, so
`character_creator.gd` also tints it to the selected `SKIN_TONES` value - `outfit_coverage_comparison.gd`
doesn't need this (no skin-tone picker there). Re-verified with real materials on all four combinations
after the fix: continuous, correctly-toned, gap-free hand-to-sleeve on the three combinations with a
bridge, Female Peasant unchanged and still correct.

## Neck/collar exemption (found and fixed after real-materials review)

A second real gap, also only visible with debug colors off: a hole between the chin and the shirt
collar, plus small holes at both shoulder tops - neither body skin nor cloth rendered there, just the
background showing through. Root cause, found by reading Superhero_Male_FullBody.gltf's own JOINTS_0/
WEIGHTS_0 directly: a ring of vertices right at the neck-to-torso transition are nearly evenly blended
between `neck_01` (visible) and `clavicle_l/r`/`spine_03` (hidden) - e.g. one vertex is 46%
`clavicle_l`/44% `neck_01`. `apply()`'s single-most-weighted-bone test called that vertex "hidden"
purely because 46 edges out 44, even though nearly half its influence is a bone the outfit leaves bare
- and the whole ring of such vertices got dropped, with nothing (no outfit collar bridge exists for the
neck, unlike the arm case) to fill the result.

First attempt - un-hiding `clavicle_l/r` and `spine_03` outright - was tried and rejected after a live
render showed it reintroduced serious chest clipping: most of the deep chest/back geometry those bones
cover is *not* a thin boundary ring, it's most of the torso, and the shirt's fitted silhouette sits
closer to the body than that geometry in several places. The actual fix: `NECK_EXEMPT_BONES` (`neck_01`,
`Head`) and `NECK_EXEMPT_WEIGHT` (`0.15`) in `body_region_mask.gd` - a vertex already assigned to a
hidden bone is exempted from hiding only when it also carries at least that much combined weight on an
exempt bone. The threshold was chosen by simulating against the actual mesh data (not guessed): it
flips only the triangle ring between world-space y=1.46 and y=1.56 (the neck/shoulder-top height), not
the y=1.37-1.43 range where genuine chest geometry sits, so it doesn't reopen the clipping the first
attempt caused. Re-verified with real materials on all four combinations: the collar/shoulder gaps are
gone (including a visually-correct scalloped back-collar shape on Male Peasant, previously invisible
under the hole), no new clipping anywhere on the torso.

The foot/boot-cuff boundary was also checked at the same time, from front, angled, and side camera
views on all four combinations - found clean at that point. A user screenshot afterward caught a real
problem there anyway (see "Foot clipping" below) - front/angled/side renders in the T-pose just didn't
happen to reveal it; a wider framing showing the full boot at a slight angle did.

## Foot clipping (found and fixed from a user screenshot, opposite failure mode from the neck)

A user screenshot (debug colors on) showed red (body) bulging out past both sides of both boots -
clipping, not a hole: the base body's foot is simply wider than every boot mesh in this pack at that
point. `foot_l`/`foot_r` (and the toe bones, `ball_l`/`ball_r`/`ball_leaf_l`/`ball_leaf_r`) were being
kept visible on the same theory as hands - that boot coverage at the toe might not be guaranteed - but
unlike hands, that theory was never actually verified for feet, and turned out false: every boot in
this pack fully encloses the foot lengthwise (confirmed again after the fact, and no outfit ships a
foot skin primitive the way three of them do for hands, meaning none of them expect the foot to ever be
exposed). Fix: added `foot_l/r`, `ball_l/r`, `ball_leaf_l/r` to `DEFAULT_HIDDEN_BONES` - the opposite
fix from the neck case (hide more, not exempt more), because this was body sticking out past cloth, not
cloth failing to reach across a gap. Re-verified with real materials on all four combinations, front and
back, plus a wider framing matching the angle the original screenshot was taken from: no clipping, no
new toe gap.

## Chest V-notch (a false alarm, but produced a genuinely useful debug tool)

A user screenshot showed a gray void (background) at the top of Male Peasant's chest, below the
collar - not skin, not cloth. Diagnosed at the time as an authored V-neck slit in Male_Peasant's
cloth reaching past the neck/collar boundary the neck-ring fix covers, based on a "hole boundary"
found by scanning `Male_Peasant.gltf`'s own `Body` mesh for edges used by only one triangle. Two
things were built on that diagnosis: a hardcoded per-outfit `AABB` exemption (rejected after
rendering - an untapered box doesn't match a V shape, showed as a red rectangle, not skin), then a
skeleton-anchored, slider-controlled exemption per the user's request (below) - which, when
actually tested at zero exposure, showed **no gap at all**, in either debug colors or real
materials, from a completely fresh render.

That result means the original diagnosis was wrong: the "hole boundary" measurement is a false
positive. Edges "used by only one triangle" also show up at ordinary hard-shading seams - Godot/
glTF represent a sharp edge by duplicating vertices at the same position with different normals, so
the two triangles on either side use different vertex indices even though the mesh is fully closed
there. The scan was vertex-index-based, not position-based, so it flagged the collar's shading seam
as if it were a real opening. The cloth was solid there all along; likely compounded by the same
kind of stale-view issue from earlier in this session (see "Outfit-supplied hand bridges" above) -
the screenshot may not even have reflected the neck-ring fix yet.

The first fix attempt here was a **Chest Skin** debug slider (0.0-1.0) exempting a region anchored
on the live skeleton's own `spine_03` rest position (via `get_bone_global_rest()`, not a hardcoded
coordinate - a hand-summed approximation from the raw `.gltf` node translations was tried first and
was wildly wrong, ~0.41 vs. the ~1.31 Godot's own import actually produces, because Godot's glTF
import re-derives rest transforms rather than just accumulating local translations). This worked (0.0
is correct, matching the false-alarm finding above) but was still fundamentally a manual, per-outfit
guess - the user pushed back on this directly ("patching is not good, it must work with any body,
given any cloth") and asked whether skin-touching-cloth could be detected directly instead. It can -
see "Geometric cloth-coverage test" below, which replaced this slider's exemption logic entirely
(the slider itself is kept, repurposed as a tuning knob for that test - see its own section).

## Geometric cloth-coverage test (replaces the chest-exposure slider's guesswork with a measurement)

`BodyRegionMask.apply()` now takes the outfit's own mesh as an argument and, for any hidden-bone
vertex `NECK_EXEMPT_WEIGHT` doesn't already exempt, measures whether cloth actually covers it there -
instead of guessing via a hardcoded region. Two implementations were tried before landing on the one
that works:

1. **Raycast along the body vertex's own outward normal**, checking for a cloth hit within
   `CLOTH_COVERAGE_DISTANCE`. Looked correct in principle but failed badly in practice - a live render
   showed skin exposed almost everywhere, in a blotchy pattern. Root cause, found by probing specific
   vertices directly (not guessed): body and cloth sit only ~1.1cm apart at this pack's fit, and a ray
   along the body's own normal missed cloth that was unambiguously right there, because a small
   mismatch between the body vertex's local normal direction and the cloth's actual position is
   enough to miss entirely at that range. Confirmed the direction was the problem, not the distance:
   quadrupling the search distance (0.05 to 0.20) produced an *identical* result.
2. **Signed distance from the nearest cloth point, using the cloth's own normal** (not the body's):
   `find_nearest()` already existed in `RuntimeClothFitter.SpatialGrid` (left over from the earlier
   shrinkwrap-fitting effort) and returns the closest cloth point plus its normal; a vertex is exempted
   if nothing is within `CLOTH_COVERAGE_DISTANCE` at all, or if it measures on/past the outward side of
   that nearest surface (`(body_point - cloth_point).dot(cloth_normal) >= CLOTH_COVERAGE_CLEARANCE_MARGIN`).
   This is more robust than the raycast: it asks "which side of the cloth am I on" rather than "does a
   ray in one specific direction happen to hit it," so a slightly-off local normal doesn't cause a miss.
   Verified correct on three known cases before rolling out - a chest vertex (should stay hidden,
   measured covered), a hand vertex (should be exempt, no cloth within range at all) - both correct
   immediately, but a **neck-ring vertex measured as covered when it should be exempt**: the collar's
   own rim geometry sits about as close (~1.1-1.3cm) as genuinely-covering cloth does elsewhere, and its
   local normal near an opening's edge doesn't reliably signal "opening" the way `NECK_EXEMPT_WEIGHT`'s
   bone-weight blend does. Conclusion: proximity (even with a normal) can't always tell "the edge of an
   opening is nearby" from "a covering surface is nearby," because both really are just as close - so
   at the time, `NECK_EXEMPT_WEIGHT` became the first check for the neck ring specifically, with the
   geometric test as a second, independent fallback for everywhere else. That priority order was later
   found to be wrong once an exact hole test existed (see "Exact collar-hole detection" below) -
   `NECK_EXEMPT_WEIGHT` is now only a fallback for outfits with no detected hole at all.

Also needed a margin, not a bare `>= 0` cutoff: at `>= 0.0` exactly, thin streaks of falsely-exposed
skin appeared tracing the cloth's own fold/seam lines (sleeve creases, pant seams) - at a sharp fold
the geometrically nearest point can land on a slightly different local facet than the one actually
facing the body vertex, making the signed distance noisy right around zero. `CLOTH_COVERAGE_CLEARANCE_MARGIN`
requires a vertex to be clearly past the cloth surface, not just barely so.

Scoping: only vertices dominantly weighted to `DEFAULT_HIDDEN_BONES` are eligible for either
exemption - `HAND_BONES` vertices never are, since the geometric test would otherwise immediately
re-expose the base body's now-redundant hand (correctly, by its own logic - it really is far from any
cloth, since the outfit's bridge is a separate mesh) and silently undo the hand-bridge fix above.

This is a rest-pose measurement done once per mask rebuild, not a per-frame/per-pose runtime test -
consistent with the project's earlier rejection of proximity-based masking (see "Removed approach"
below), which failed for a different reason: that system baked UV-space visibility masks from
image-space proximity/ray heuristics, inconsistent across viewing angles and eroding/dilating in ways
that ate real detail. This measures actual 3D geometry directly, once, the same way `NECK_EXEMPT_WEIGHT`
already measures bone weight once - not a continuous per-pixel field.

### The margin couldn't be a single perfect constant (superseded - see "Exact collar-hole detection" below)

A user screenshot at the default margin (then 0.02) showed a small but real gap still open at the very
base of the collar, on Male Peasant specifically - visible only at a close zoom (the character
creator's own default face-focused framing), which is why the wider-framed verification render above
missed it. Measured directly (not guessed): this gap's own vertices have a signed distance of only
~0.0003-0.0013 past the cloth - genuinely smaller than any margin that also silences the fold/seam
noise elsewhere on the same mesh (0.006 was the lowest value that fully silenced it, tried by
sweeping 0.0001/0.001/0.003/0.006/0.02 and rendering each). The two cases produce distances in
overlapping ranges, so no single margin value can have both a closed notch and zero streaking.

A connected-component filter was tried next - the theory being that a real opening is a sizeable
*connected* patch while fold noise is small and scattered - but raising the minimum island size from
8 up to 80 vertices made no visible difference at all: fold-line noise turned out to be just as
"connected" as the real notch, because both are elongated features (a crease traces a continuous
line; the notch is a continuous narrow slit), not blobs a vertex-count threshold can tell apart.
Reverted - added complexity for no measurable benefit.

At this point a tunable `clearance_margin` slider was added as an honest, live tradeoff (closing the
gap versus reopening streaking elsewhere) rather than a single guessed constant - since superseded and
removed entirely, see below.

### Exact collar-hole detection (replaces the margin/slider tradeoff above)

The real fix: instead of inferring the hole's location indirectly through a distance/margin threshold
that's provably confusable with fold noise, read the outfit's own mesh boundary directly.
`_cloth_boundary_loops()` merges the outfit's cloth vertices by POSITION first (not index - matching
by index was exactly the bug behind the earlier "Chest V-notch" false alarm below, since a hard-shading
seam duplicates a vertex at the same position with a different normal, and looks identical to a real
hole if only raw indices are compared), then traces every edge used by exactly one triangle into closed
loops. Verified directly against Male_Peasant.gltf: position-dedup gives a clean 2/1 edge-count split
(13246 shared edges, 400 boundary edges, zero ambiguous ones), tracing 19 distinct loops - the
neckline, both cuffs, the waist hem, and various strap/buckle/pauldron boundaries.
`_collar_hole_polygons()` narrows those 19 down to the collar specifically: a loop's bounding-box
diagonal must be small (`COLLAR_HOLE_MAX_DIAGONAL` - excludes the waist hem) and its centroid must sit
near a `NECK_EXEMPT_BONES` rest position (`COLLAR_HOLE_SEARCH_RADIUS` - excludes sleeve cuffs and
shoulder-strap/pauldron boundaries). `_point_in_hole()` then does an exact membership test: a best-fit
plane via Newell's method, a 2D basis in that plane, and `Geometry2D.is_point_in_polygon()` on the
projected point. `_vertex_hidden_flags()` checks this exact test FIRST whenever an outfit has a
detected hole, falling back to `NECK_EXEMPT_WEIGHT`'s cruder bone-weight blend only when it doesn't
(see "Geometric cloth-coverage test" above for why that reordering itself was a bug fix, not just a
priority tweak). `coverage_distance` is still a live slider (`ui/character_creator.gd`'s "Cloth
Coverage Distance") for the separate no-cloth-nearby fallback; the old `clearance_margin` slider and
`CLOTH_COVERAGE_CLEARANCE_MARGIN` constant are gone entirely - superseded, not tuned away.

Two real bugs in this exact test were found and fixed after it looked correct in initial renders (front
collar clean on all four combinations), both surfacing only once the *back* of Male Peasant specifically
was reviewed at a real-materials zoom - real base-body skin rendering through the shirt, not a masking
void, in a shoulder-blade-crescent + lower-back-triangle pattern initially misdiagnosed as an intentional
texture design before the user corrected that read:

1. **`_point_in_hole()` had no notion of distance along the hole's own plane normal** - a 2D
   point-in-polygon test only sees the two in-plane axes, so a point anywhere along a line
   perpendicular to that plane can share the same (u, v) projection as a point genuinely inside the
   hole. The collar hole's plane normal points roughly vertically (up through the neck opening), so
   its (u, v) basis spans mostly horizontal directions - meaning points on the back, and even the
   thighs, at the same horizontal position as the neck hole tested "inside" it. Measured directly (not
   guessed) via an instrumented probe: a genuine collar-adjacent vertex sits only ~0.044 off the hole's
   plane, while the nearest false match (mid-upper-back) sits ~0.24 off it - a wide, clean gap, not a
   razor-thin tuning call. Fixed by rejecting on plane-distance (`COLLAR_HOLE_NORMAL_TOLERANCE := 0.06`)
   before running the 2D polygon test at all - see the constant's own comment in `body_region_mask.gd`.
2. **`NECK_EXEMPT_WEIGHT` running unconditionally, ahead of the exact test, exposed a second, unrelated
   region** even after bug 1 was fixed: this blend zone is anatomically about neck-vs-shoulder
   proximity only, not about where the collar's cloth actually stops, so on Male Peasant it also flipped
   a crescent-shaped patch of `spine_03` at each shoulder blade - well below the shirt's true back
   neckline. Unlike bug 1, there was no clean gap to tighten a threshold against (genuine collar-adjacent
   vertices and the false shoulder-blade ones interleave continuously in plane-distance, confirmed by
   sorting an instrumented probe's full output), so this couldn't be fixed by tuning; it had to be
   reordered instead. Fixed by making the exact hole test authoritative whenever a hole was detected for
   this outfit, and demoting `NECK_EXEMPT_WEIGHT` to a fallback for the (currently untested-in-practice)
   case of an outfit with no detectable hole loop at all - see "Geometric cloth-coverage test" above and
   `NECK_EXEMPT_WEIGHT`'s own comment in `body_region_mask.gd`.

Re-verified after both fixes: all four combinations clean front and back, including a real-materials
zoom on Male Peasant's back specifically (the view that caught both bugs) - only a couple of stray
sub-centimeter slivers remain right at the nape of the neck, matching the outfit's own real mesh
boundary loop dipping slightly into the back there, not a masking defect.

## Collar wedge trim (a manual, generic control for what no automatic test can safely resolve)

The user pushed back on leaving the nape sliver as-is ("is really visible, can we try something?").
Investigated whether a connected-component size filter could remove it automatically (the same idea
tried and rejected earlier in "The margin couldn't be a single perfect constant", but scoped narrowly
this time to just the exact-hole-exempted vertex set instead of the whole coverage-distance domain) -
measured directly (not guessed) by building the real visibility graph (which visible vertices actually
touch, including bridging through always-visible ones like the neck bone) and checking which
hole-exempted vertices *don't* connect to the main head/neck mass: Male Peasant has two small
disconnected pockets (9 and 11 vertices - the real defect) and Female Ranger has one (1 vertex), but
**Female Peasant has a 30-vertex disconnected pocket that renders completely correctly** - it's just
the bottom tip of her front V-neck, topologically disconnected from the neck bone's own vertices for
mesh-specific weight-painting reasons, not a defect. A same-or-bigger legitimate fragment on one outfit
means no size threshold can safely distinguish "real defect" from "real opening" across outfits - the
same failure mode as the earlier fold-noise filter, confirmed again rather than assumed.

Given no automatic signal can make this call, `BodyRegionMask` gained a manual one instead:
`_apply_wedge_trim()` divides the collar fringe into `WEDGE_COUNT` (18) angular wedges around the neck
bone's own rest position (20° each, wedge 0 at world +Z, counter-clockwise from above), and for each
wedge, `wedge_trim[i]` (0.0-1.0) keeps only the top fraction of THAT WEDGE's own currently-exposed
vertices, measured from that wedge's own min/max Y - not a fixed world-Y range, so `1.0` (the default,
every wedge) is a true no-op regardless of an outfit's actual proportions. Only vertices already
exempted by the automatic tests are eligible (dominantly weighted to a hidden, exemptable bone AND
already visible) - this can never touch the permanently-visible head/face or any other body region,
only the collar fringe, and it's strictly a further restriction on top of the automatic tests, never an
additional exemption. Wired to `ui/character_creator.gd` as 18 live `VSlider`s under "Collar Wedge Trim
(Debug)" (`_build_wedge_sliders()`, built at runtime rather than hand-authored in the `.tscn` since
it's a repeated pattern), each with a tooltip showing its degree range so a specific defect spotted in
a render can be matched to the slider that covers it - the same trial-and-look workflow the coverage-
distance slider already uses. `BodyRegionMask.apply()`'s new `wedge_trim` parameter defaults to an
empty array (skips the whole step, same as passing all-`1.0`), so every existing call site is unaffected
unless it opts in.

Verified on Male Peasant: the nape sliver's own two known vertices both land in wedge 9 (straight
back) by direct computation, but trimming wedge 9 alone to 0.0 did *not* fully remove the sliver in a
real-materials render - its actual disconnected patch (9-11 vertices, not just the 2 sampled) spans a
wider height range than assumed and bleeds slightly into wedges 8 and 10 too. Trimming wedges 8-10 to
0.0 together removed it completely, confirmed with the front V-neck and every other wedge re-rendered
unaffected. Left at the default (`1.0`, no-op) in the shipped UI rather than baking Male Peasant's
specific working values in as new defaults - that would silently reintroduce per-outfit hardcoding
through the back door; the slider is there for the user to dial in live, per outfit, same as
`coverage_distance` already is.

### Slider lag, its real cause, and per-wedge debug markers

The user noticed the wedge sliders felt slow (~1-2s) while dragging. Measured before guessing: a
single `BodyRegionMask.apply()` call on Male Peasant costs ~740ms, and profiling each internal step
showed `_collar_hole_polygons()` (boundary-loop tracing) at ~9ms and `_build_cloth_grid()` at ~7ms -
both fast - against `_vertex_hidden_flags()` at ~722ms, almost all of it `cloth_grid.find_nearest()`
spatial queries, called once per hidden-bone-dominant body vertex (thousands, for a fully-covering
outfit) to answer a question that's always "yes, cloth is nearby, stay hidden" for the vast majority
of them. The user's own first idea was to replace the outfit's cloth mesh with a coarse sphere proxy
for cheaper queries - a reasonable instinct, but the real fix needed no geometry approximation at
all: none of that per-vertex work depends on `wedge_trim`, so a wedge-only change never needed to
redo it in the first place.

`BodyRegionMask.apply()` is now `compute_mask_state()` (the expensive, wedge-independent part -
bone weights, collar-hole polygons, cloth grid, the full per-vertex exemption pass) followed by
`rebuild_mesh()` (wedge trim + triangle-dropping + mesh rebuild - a linear pass with no spatial
queries at all). `apply()` itself is now a two-line wrapper composing both, unchanged for every
existing call site. `ui/character_creator.gd` caches `compute_mask_state()`'s result in
`_mask_state` on every real rebuild (outfit/body/coverage-distance change) and `_on_wedge_trim_changed()`
calls `rebuild_mesh()` directly against the cached state - confirmed by profiling: `rebuild_mesh()`
plus the new `wedge_marker_positions()` call together cost ~2.5ms, down from ~740ms per slider tick.

Separately, the user asked for a visual aid: one small sphere per wedge, positioned at that wedge's
current trim boundary, so the effect can be seen directly in 3D instead of inferred from the
rendered skin alone. `BodyRegionMask.wedge_marker_positions()` computes this from the same cached
`mask_state` (equally cheap, no spatial queries), and `ui/character_creator.gd` builds 18
`MeshInstance3D` spheres once (`_build_wedge_sliders()`) and repositions/shows-or-hides them every
tick (`_update_wedge_markers()`). Verified live: markers appear at the collar boundary on both
shoulders at the default (`1.0`, no-op) trim, and simulating a wedge-8/9/10 trim through the actual
`_on_wedge_trim_changed()` code path (not just `rebuild_mesh()` directly) removes the nape sliver
exactly as the earlier full-rebuild test did, confirming the cheap and full paths agree.

### Extending wedge trim to the neck column, and a sphere-size rendering gotcha

Looking at the markers, the user pointed out the real problem: only 3 of 18 wedges had any marker
at all (one at the back-center sliver, two near the shoulders), with a big gap between them - and
that gap was exactly "the parts I actually wanted to reduce." The reason: wedge trim was scoped only
to DEFAULT_HIDDEN_BONES-dominant vertices (the small collar-fringe sliver), never to the neck itself
(`neck_01`/`Head`-dominant, deliberately always-visible per `NECK_EXEMPT_BONES` - see that constant's
own comment) - so most of what's visually "the neck" in a Hide-Clothes render was structurally
untouchable by any wedge slider, regardless of value.

Widened eligibility to include the neck column too, via a new `WEDGE_NECK_BONES` constant -
deliberately `["neck_01"]` only, NOT `"Head"` even though `NECK_EXEMPT_BONES` includes both: measured
directly (not guessed) that `Head` is the single most-dominant bone for 1375 vertices spanning
y=1.58-1.81 on the male body (the entire face/skull), while `neck_01` dominates only 195 vertices in
a tight y=1.52-1.62 band (just the neck column). Including `Head` would let a wedge slider erase the
face - confirmed as a real risk worth guarding against explicitly, not a theoretical one, given the
user's own stated scope ("not the arms yet" - the same caution applies even more to the face).
`compute_mask_state()` now also computes `wedge_neck_bone_indices` and stores it in `mask_state`;
`_apply_wedge_trim()`/`wedge_marker_positions()` treat a vertex as eligible if it's either the
existing collar-fringe candidate OR neck-column-dominant, merged into the same per-wedge min/max Y
range (so a wedge with both gets one continuous trimmable extent, not two disjoint ones).

Verified via `wedge_marker_positions()` directly: all 18 wedges now report `has_data: true` (except
two - wedges 4 and 13 - which turned out to pick up the bare forearm instead, sitting at that exact
~90°/270° angle in T-pose; a known, pre-existing quirk of the simple angular-bucketing scheme, not
something this change introduced, and out of scope per "not the arms yet").

Re-verifying in an actual render turned up a second, unrelated bug: after the neck-column change,
**zero markers rendered at all**, anywhere, despite `wedge_marker_positions()` returning correct data.
Instrumented the live scene directly rather than guessing further: `visible`, `global_position`,
`parent`, `is_inside_tree()`, `mesh`, and `material_override` all checked out exactly as expected on
the invisible marker - it just never rasterized a single pixel. Bisected by radius: `0.008` (the
original size) rendered nothing at all, `0.05` rendered an obvious giant blob, `0.016` reads clearly
as a small marker - so this was a real minimum-screen-size rendering floor for a `SphereMesh` at this
scene's camera distances, not a logic bug (and not something the earlier, pre-neck-column marker
tests happened to hit, since they only exercised 2-3 markers at a slightly closer camera distance
where the same tiny radius happened to still clear whatever floor this is). `_build_wedge_sliders()`
now uses `radius = 0.016`, `height = 0.032`.

### Marker color: does this wedge's trim boundary touch cloth right now?

Requested as a further visual aid: color each marker by whether cloth is actually nearby at its
current position, reusing the same `cloth_grid.find_nearest()`/`coverage_distance` signal
`CLOTH_COVERAGE_DISTANCE`'s own fallback exemption already relies on, rather than inventing a new
threshold. `compute_mask_state()` now also stores `cloth_grid` and `coverage_distance` in
`mask_state`; `wedge_marker_positions()` adds one `find_nearest()` call per wedge with data (at most
`WEDGE_COUNT` calls total, not per-vertex - still cheap) and returns `touches_cloth` per entry.
`ui/character_creator.gd` swaps each marker's `material_override` between two shared materials
(green/red) rather than coloring per-instance.

Deliberately documented as purely informational, not a correctness signal either way - trimming
into cloth isn't inherently wrong (the cloth covers whatever's hidden underneath) any more than
trimming short of it is.

Verified via `wedge_marker_positions()` directly (not just eyeballing a render): on Male Peasant,
every collar/neck wedge (0 and 8 checked explicitly) stayed `touches_cloth: true` across the entire
trim range from the collar line up to the very top of the neck (`neck_01`'s own max y=1.615) -
technically correct given the 8cm `coverage_distance` (the collar's own highest back point, y=1.564,
sits only ~5cm below that), and confirmed the mechanism itself does produce both colors correctly by
checking wedge 4 (the bare-forearm wedge) instead. But reusing `coverage_distance` (0.08) for this at
all was itself the actual mistake, caught by the user from a real screenshot: markers positioned with
a real, visible gap above the cloth line still read red, because 0.08 is nearly half the neck's own
visible height at typical zoom - "structurally impossible to read green" isn't a defense when the
threshold making it impossible is the wrong threshold for what a human would call "touching."
`coverage_distance` answers "is there any cloth within a generous search radius" for a completely
different purpose (never leave a body part with nothing covering it); "touches" needed its own,
much tighter one. Added `WEDGE_MARKER_TOUCH_DISTANCE := 0.015` (this project's own measurements
elsewhere put a properly-fitted garment's real skin-to-cloth gap around 0.011-0.013, so 0.015
comfortably covers a real touch without reaching far enough to falsely flag a visible gap) and
switched `wedge_marker_positions()`'s `touches_cloth` check to use it instead. Re-verified: wedge
0 and 8 both now show a real mix of `true`/`false` across their trim range, matching visible
distance to the eye - confirmed live too, and incidentally the green marker landed exactly on the
known small nape gap in Male Peasant's collar mesh (see "Exact collar-hole detection" above) -
correctly flagging a real, if tiny, gap in the garment.

### Spheres to pins: markers going invisible as they moved down

The user reported markers sometimes going invisible as the wedge trim boundary moved down toward
the collar. A sphere sitting flush on the trim-boundary point itself can end up mostly embedded in
nearby geometry as that point moves closer to the cloth surface - a pin perpendicular to the surface
doesn't have this problem, since it pokes outward past whatever's around it regardless of how deep
its base point is. Replaced the `SphereMesh` with a thin `CylinderMesh` (radius `0.01`, comfortably
above the same minimum-rasterization floor found earlier - see "Extending wedge trim to the neck
column" above), oriented so it stands radially outward from `BodyRegionMask`'s own `wedge_center`
axis - a good approximation of the true surface normal given the neck is close enough to
cylindrical, and reuses a value already computed rather than adding real per-vertex normal lookups.
`WEDGE_MARKER_PIN_LENGTH := 0.04` controls how far it pokes out.

Verified live from two angles: a straight-on back view mostly foreshortens the pins into discs
(expected - looking straight down a pin's own axis will always do that, for any perpendicular
marker, not a defect in this approach), but a side/three-quarter view clearly shows them as short
lines poking out from the shoulder and collar, confirming the orientation math is correct.

### Thinner/taller pins, and a real arm-eligibility bug the pin shape exposed

Two follow-ups from a user screenshot. First, cosmetic: thinner, taller pins read more clearly as
lines - `WEDGE_MARKER_PIN_RADIUS := 0.006` (`ui/character_creator.gd`, down from the cylinder's
original `0.01`, still comfortably above the rasterization floor) and `WEDGE_MARKER_PIN_LENGTH`
raised to `0.07` (from `0.04`).

Second, a real bug the screenshot caught: a green marker rendering well below and disconnected from
the rest of the collar/neck row. Traced via `wedge_marker_positions()` directly: wedges 4 and 13
(near 90°/270°, the T-pose arm's own outstretched direction) were picking up a bare-forearm vertex
at x=±0.594, y=1.400 - correct per the eligibility test as written (collar-fringe eligibility is
DEFAULT_HIDDEN_BONES-dominant AND already-exempted, which on a full-sleeve outfit also legitimately
covers upperarm_l/r and lowerarm_l/r wherever the CLOTH_COVERAGE_DISTANCE fallback exposes them,
e.g. the real bare-forearm gap fixed earlier this session), but out of scope for what the wedge
system is actually for - the neck/collar, not the arms, explicitly per the user's own earlier "not
the arms yet." Added `WEDGE_EXCLUDED_BONES := ["upperarm_l", "upperarm_r", "lowerarm_l",
"lowerarm_r"]`, checked first (before collar-fringe/neck-column eligibility) in both
`_apply_wedge_trim()` and `wedge_marker_positions()`, threaded through `compute_mask_state()`'s
`mask_state` like the other bone-index sets. Re-verified via `wedge_marker_positions()`: wedges 4
and 13 now land at x=±0.078, y=1.55 - back on the neck, in line with their neighbors - and live,
confirming the far-away marker is gone.

### More wedges, and their own wider panel

Same screenshot prompted a follow-up: two pins near 90°/270° rendered as long horizontal bars while
the rest looked like dots. Checked the underlying data first (not assumed to be the same bug):
wedges 4 and 13 were already correctly clustered on the neck, so this wasn't a detection bug at
all - it's viewing-angle foreshortening, inherent to any surface-perpendicular 3D marker. A pin
pointing straight at/away from the camera (wedges near 0°/180° from this back-view camera) reads as
a small dot; a pin pointing sideways (perpendicular to the camera, wedges near 90°/270°) reads at
its full un-foreshortened length - same real length everywhere, just very different apparent size
depending on which way each one happens to point relative to the viewer. Not fixed yet (the user
moved on to other requests instead - more wedges and a dedicated panel - before choosing between
the two mitigation options discussed: shortening the pins back down, or switching to camera-facing
billboards).

Two follow-up requests, both straightforward data/layout changes:
- `BodyRegionMask.WEDGE_COUNT` raised from 18 to 36 (10° per wedge instead of 20°) - confirmed
  nothing else hardcodes a wedge count anywhere (angle step, array sizing, bucket index all read
  the constant), so this was a pure data change, no logic changes needed.
- The wedge sliders moved out of the main control panel into their own new `WedgePanel`
  (`ui/character_creator.tscn`, positioned below the main panel) - needed room for 36 sliders side
  by side, which the original panel's ~340px width was never going to fit well. Main `Panel`'s
  height reverted back down to its pre-wedge-row size (`734`) now that the wedge row moved out.
  `ui/character_creator.gd`'s `wedge_sliders_row` path updated to match.

Verified live at 1280x960: all 36 sliders fit comfortably in the new panel with room to spare, and
the finer wedge resolution gives visibly denser coverage around the front collar in a debug-colors
render - confirms both changes work together correctly, not just individually.

### Hover-to-highlight: matching a slider to its physical spot

With 36 sliders, matching one to its actual location on the neck by eye got harder, not easier.
Added a third shared marker material (orange, `_wedge_marker_material_hovered`) and wired each
slider's `mouse_entered`/`mouse_exited` signals (`_on_wedge_slider_mouse_entered()`/
`_on_wedge_slider_mouse_exited()`) to set/clear `_hovered_wedge_index` and call
`_update_wedge_markers()` - cheap (no `compute_mask_state()` work, just the cached `_mask_state`),
safe on every hover. The hovered wedge's pin takes the orange material ahead of its normal
green/red touches_cloth color in `_update_wedge_markers()`'s own material selection.

Verified by simulating a hover (calling `_on_wedge_slider_mouse_entered()` directly, since a
headless `--write-movie` render can't drive real mouse input) on wedge 18 (180°, back-center under
the new 36-wedge numbering) - its pin renders clearly orange, distinct from every other wedge's
green/red.

### A real bug in the collar-hole test itself, caught by the user pushing back twice

The user kept flagging the isolated marker below the collar row as wrong, and I kept defending it
as the known real nape sliver - twice, with measurements each time (the true nearest-cloth distance
at 2.55cm, correctly above `WEDGE_MARKER_TOUCH_DISTANCE`). Both of those measurements were
individually correct but answering the wrong question. The user's actual objection - "this is the
back, there's no shape or opening here like the front V" - was right, and the way to settle it
wasn't another distance measurement, it was looking at the outfit's own mesh directly: rendered
Male Peasant's shirt ALONE (no body) from behind, zoomed on that exact spot, against a bright green
background so any hole would be unmistakable. Result: completely continuous, unbroken fabric - no
hole there at all. `_point_in_hole()` really was misclassifying this vertex as inside the collar
hole.

Root cause: the collar hole loop genuinely isn't flat (Male Peasant's collar dips to y=1.49 at the
front V and rises to y=1.56 at the back), so `_build_hole_polygon()`'s single best-fit plane (via
Newell's method) was itself only an approximation - one that broke down for a loop with this much
real 3D curvature. A point could satisfy the plane's own normal-distance tolerance
(`COLLAR_HOLE_NORMAL_TOLERANCE`) and the flattened 2D polygon test while sitting nowhere near the
loop's true 3D shape. This is a *different* bug from the one `COLLAR_HOLE_NORMAL_TOLERANCE` itself
fixed earlier (a 2D test with no notion of depth at all) - that fix was real and still necessary,
it just wasn't sufficient once the loop stopped being reasonably flat.

Fix: replaced the plane-projection approach with fan-triangulating the loop's own real 3D vertices
directly (`_build_hole_cap()` - loop[0] as a shared apex, connecting each consecutive pair) into
true 3D triangles that follow whatever shape the loop actually has, flat or not, then measuring
distance to that surface with the same closest-point-on-triangle math already used elsewhere
(`RuntimeClothFitter._closest_point_on_triangle`) - a point is "in the hole" if it's within
`COLLAR_HOLE_CAP_DISTANCE` of this real surface, not an averaged approximation of it.

Verified by measurement before touching the real code, not guessed: computed this new cap-distance
for every vertex the OLD test called `in_hole=true` on Male Peasant. The confirmed-false-positive
vertex (proven above to have continuous fabric) measured 0.039 - a clean margin above every
genuinely correct match, which topped out at 0.018. A second, more marginal false positive (also
confirmed by the same render, ~2cm from the first) measured 0.019 - only 0.001 above the single
closest legitimate match, an inherently noisy margin for that one specific vertex pair rather than
a sign the method is unreliable elsewhere. Set `COLLAR_HOLE_CAP_DISTANCE := 0.015`, below both
confirmed false positives; the one borderline legitimate vertex it also excludes has several other
clavicle vertices within a centimeter of it, and `rebuild_mesh()`'s triangle-drop rule (only drops
a triangle if all three vertices end up hidden) means losing one vertex from a dense cluster doesn't
open a visible gap.

Re-verified end to end: both known false positives now correctly test `in_hole=false`, the known
front-V point still correctly tests `in_hole=true`, live renders confirm the stray marker is gone
with the rest of the collar row unaffected, the front V-neck still renders clean with real
materials, and - since this changes core masking behavior for every outfit, not just the debug
wedge tool - re-checked all four body/outfit combinations from behind: all clean, no regressions.

### Slider step size, and thinner pins

Two more polish requests. `WEDGE_MARKER_PIN_RADIUS` reduced from `0.006` to `0.004` (verified live
it's still clearly visible - the minimum-rasterization floor found earlier was between `0.008`
(invisible) and `0.05` (an obvious blob), so `0.004` has real margin).

The "mesh doesn't move evenly" report was mostly the slider's own `step := 0.05` - Godot's `Range`
only fires `value_changed` (and therefore only rebuilds the mesh and repositions the pin) when the
*snapped* value changes, so most of a drag across a 0.05 step did nothing at all, then jumped.
Lowered to `0.01`. This doesn't remove all steppiness by design, not oversight: the mesh itself can
only visibly change at an actual vertex row (triangles are dropped or kept whole, `rebuild_mesh()`
never interpolates), so there's a hard floor set by how many candidate vertices a given wedge has,
independent of slider granularity - the fix removes the slider from making that floor artificially
worse, not the floor itself.

### Marker color redefined: proximity was the wrong question

The user asked why markers still showed red at un-adjusted (default) wedge positions, expecting the
tool to auto-stop before ever reaching a red state. Clarified first: red never meant "something's
wrong" - it meant "cloth happens to be within `WEDGE_MARKER_TOUCH_DISTANCE`," which at a normal,
correctly-fitted collar edge is the ordinary, unremarkable case (skin sitting close to where cloth
begins is what "fitted" means) - there was no bad state to auto-avoid. The user then reframed what
they actually wanted: red should mean the skin is genuinely poking THROUGH cloth that's right
there, not merely near it - a real geometric overlap check, not a proximity one.

Implemented properly this time: `SpatialGrid.find_nearest()` already returns the nearest cloth
point's own surface normal (used elsewhere for the shrinkwrap-fitting pipeline, unused here until
now). `wedge_marker_positions()`'s field renamed `touches_cloth` -> `clips_cloth`, and its logic
changed from "is any cloth within range" to "is cloth within range AND does the skin point sit on
the OUTWARD side of that cloth's surface" (`(position - cloth_position).dot(cloth_normal) > 0.0`) -
skin behind/at the cloth from the outward view (negative signed distance) reads clean, only skin
actually past cloth's outward face reads as clipping.

Verified by measurement before wiring into the live scene: computed this for all 36 wedges on Male
Peasant at the default (no-op) trim. Of 20 wedges with cloth within range, only 2 came back
positive (clipping) - a plausible rate for genuine, minor low-poly overlap, not proximity noise;
the other 18 correctly read as covered, not flagged. Re-verified live: the render now shows mostly
green with only two small red segments, matching the computed data exactly (rather than the
previous version, where roughly half the collar row read red simply for being near cloth at all).
`character_creator.gd`'s two shared marker materials renamed to match
(`_wedge_marker_material_clean`/`_wedge_marker_material_clips_cloth`).

### Averaging hid a real clip: checking every vertex, not just the marker's own position

The user then pointed at visible dark clipping triangles sitting right where a marker read green.
Checked directly (not assumed to be the same averaging/proximity issue already fixed): dumped
every currently-exposed vertex near that spot and clip-tested each one individually - a mirrored
pair at x=±0.097 genuinely clips (signed distance +0.00107), confirming the visible triangles were
real, but the wedge's own marker (at `Vector3(sum_x / count, boundary_y, sum_z / count)`) landed
somewhere else entirely, averaged together with a neighboring non-clipping vertex (-0.00115) close
enough in position that the average masked the clip completely.

Root cause: `wedge_marker_positions()` only ever clip-tested the ONE averaged display position per
wedge, never the individual candidate vertices that make it up. A wedge with a genuinely mixed
population (some vertices clipping, some not) could average out to a clean-looking position while
the actual mesh still visibly clipped.

Fixed by keeping each wedge's own candidate vertex positions (`wedge_vertex_positions`, alongside
the existing aggregate min/max/sum stats used for the marker's own display position) and clip-
testing every one that's actually visible at the current trim (`vertex_position.y >= boundary_y`),
not just the averaged point - `clips_cloth` is true if ANY of them clip. More `find_nearest()` calls
per wedge (up to a handful of vertices instead of one), but each wedge only ever has a small
candidate count, so still cheap in absolute terms.

Verified: re-ran the same measurement on Male Peasant at the default trim - 12 wedges now correctly
flag `clips_cloth` (up from 2 under the averaged-only version), including the specific x=±0.097
pair found manually. Live render confirms the red markers now sit directly on top of the visible
dark clipping triangles, rather than near but disconnected from them.

### Auto-fixing clipping at load, now that detection is per-vertex and accurate

The user asked directly: since detection now measures real clipping, can't it just fix itself
automatically instead of requiring 36 sliders to be checked by hand? Yes - and unlike every other
threshold in this file, there's no tradeoff to weigh here: a clipping vertex, by definition, has
cloth right there covering that exact spot already, so hiding it can't open a new visible gap the
way trimming a non-clipping vertex could (the collar-hole/coverage-distance exemptions all had to
stay manual-or-carefully-tuned precisely because getting them wrong risks a new hole; this one has
no such risk in either direction).

Refactored `wedge_marker_positions()`'s per-vertex work into a shared `_wedge_vertex_data()`
(returns each wedge's own candidate positions and per-vertex clip status) so both the marker
display and the new fix use identical data and `cloth_grid.find_nearest()` only runs once per
vertex, not once per caller. Added `compute_auto_wedge_trim()`: for each wedge with any clipping
vertex, sets trim so the boundary sits just above the HIGHEST clipping one - hiding it and
everything below (this system can only trim contiguous top-down ranges, not pick out individual
vertices), a small amount of collateral non-clipping skin traded for guaranteed correctness. A
wedge with no clipping stays at the default `1.0`.

`ui/character_creator.gd`'s `_rebuild_outfit()` now calls the new `_apply_auto_wedge_trim()`
immediately after computing a fresh `_mask_state`, pushing the result onto both `_wedge_trim` and
each slider's own displayed value (`set_value_no_signal()`, so it doesn't retrigger the change
handler for a value already applied) - added a `_wedge_sliders` array (parallel to the existing
`_wedge_markers`) to make the sliders addressable for this. Trade-off: a manual slider adjustment
no longer survives the next `_rebuild_outfit()` call (skin-tone changes go through it too, not
just an actual outfit swap) - acceptable for a debug tool that reacts to whatever the current
geometry needs rather than remembering unrelated past adjustments.

`body_region_mask.gd` crossed 1000 lines during this refactor (the project's own lint limit) -
trimmed several of the session's more verbose historical comment blocks (the superseded
`COLLAR_HOLE_NORMAL_TOLERANCE` writeup, `COLLAR_HOLE_CAP_DISTANCE`'s measurement log,
`WEDGE_MARKER_TOUCH_DISTANCE`, `WEDGE_EXCLUDED_BONES`) down to their essential facts rather than
cutting anything substantive, to get back under the limit with room to spare.

Verified live: both the front V-neck and back-of-neck views that previously needed 12+ wedges
manually pulled down now render fully green/clean with every slider left completely untouched -
the fix applies itself the moment the character loads. Re-checked Female Peasant too (a different
body/outfit combination, since this changes default rendering behavior for every combination, not
just a debug visualization) - clean, no regressions, no crashes.

**Correction: that "verified live, fully green" result above was itself a false pass**, caused by a
real bug introduced by the `_wedge_vertex_data()` refactor, found from a user screenshot showing a
jagged/notched V-neck silhouette despite every marker reading green. Root cause: `_wedge_vertex_data()`
built each per-vertex append as `(entry["positions"] as PackedVector3Array).append(...)` /
`(entry["clips"] as PackedByteArray).append(...)`. Fetching a packed array out of a `Dictionary` and
casting it produces a temporary copy in GDScript - appending to that temporary never writes back into
the dictionary, so `entry["positions"]`/`entry["clips"]` stayed permanently empty for every wedge (only
`entry["count"]`, assigned directly, actually persisted). Confirmed in isolation with a throwaway
`SceneTree` script before touching the real file: `(d["arr"] as PackedVector3Array).append(x)` leaves
`d["arr"].size()` at 0, while `var a = d["arr"]; a.append(x); d["arr"] = a` correctly leaves it at 1.

Effect of the bug: `compute_auto_wedge_trim()` always saw zero clipping vertices (empty arrays) and
returned `1.0` (no-op) for all 36 wedges, so the auto-fix never actually ran - the "fix applies itself
the moment the character loads" claim above was never true. `wedge_marker_positions()`'s clip check
had the same empty-array blind spot, so every marker read green regardless of the mesh's real state -
explaining how a jagged, still-clipping V-neck could coexist with an all-green marker row.

Fixed by assigning through a local variable and writing it back (`var positions_arr: PackedVector3Array
= entry["positions"]; positions_arr.append(world_position); entry["positions"] = positions_arr`, same
pattern for `clips`). Verified via a real probe against Male Peasant (`ui/character_creator.tscn`
instantiated headless, not a synthetic dictionary): `compute_auto_wedge_trim()` now returns non-default
trim for 11 of 36 wedges (previously 0), and re-running `wedge_marker_positions()` after applying that
trim shows 0 wedges still clipping (previously would have read 0 too, but falsely). Live-rendered the
front V-neck after the fix: smooth, clean edge, no notches, all markers genuinely green. Female
Peasant re-checked too: `compute_auto_wedge_trim()` returns non-default trim for 10 of 36 wedges
(previously 0), 0 wedges still clipping afterward - same pattern as Male Peasant, fix holds for both.

## Collar tip bridge patch (the one case per-wedge trimming can't resolve alone)

Even after the append-bug fix above, a user screenshot showed two small red slivers surviving right
at the V-neck's lowest point, and manually pulling the nearest sliders further down made them
disappear into a black void instead of clean cloth - "no value in between." Root cause, confirmed by
dumping `_wedge_vertex_data()` for the wedges around that point: the V's lowest vertex sits exactly
on the angular boundary between two wedges, and its own fan of triangles reaches into both. Hiding
that one vertex satisfies `compute_auto_wedge_trim()`'s safety guarantee (a clipping vertex always
has cloth right there), but `rebuild_mesh()`'s triangle-drop rule only drops a triangle once ALL
THREE of its vertices are hidden - the other two corners of each fan triangle sit in wedges with no
clipping evidence of their own, so those triangles are kept, rendering as a thin skin sliver. Cutting
further to fully drop them has no such safety guarantee (there's no clip signal on the *neighbor*
wedge to justify it), and empirically opens a real gap - `CLOTH_COVERAGE_DISTANCE`'s own reach didn't
extend that far in this specific spot.

Fix has two parts, both in `tools/outfit_pipeline/body_region_mask.gd`:

1. **`build_collar_bridge_mesh(mask_state) -> ArrayMesh`**: renders the outfit's own collar-hole
   loop (`collar_holes`, already computed for the point-in-hole test) as an actual visible surface,
   fan-triangulated the same way `_point_in_hole()` tests against it, in the outfit's own cloth
   material. Ordinarily invisible - occluded by the neck skin poking up through the hole, or
   coincident with the garment's own rim - it only becomes visible exactly where hidden skin leaves
   a sliver or a gap the triangle-drop rule can't close, giving both cases a cloth-colored backstop
   instead of stray skin or true background.
2. **`WEDGE_AUTO_TRIM_MARGIN`** (0.02, replacing a bare `0.0001` epsilon) and
   **`_nudge_untouched_neighbors()`** (`WEDGE_AUTO_TRIM_NEIGHBOR_NUDGE := 0.85`): now that any
   over-cut is backstopped by the bridge, `compute_auto_wedge_trim()` can afford to cut a bit deeper
   than the bare minimum, and to nudge an adjacent wedge with no clipping evidence of its own a
   fixed, modest amount when its neighbor does clip - exactly the shared-apex case above.

Two real implementation dead ends along the way, both confirmed by rendering, not guessed:
- First tried appending this as an extra surface directly onto the skinned body mesh
  (`masked_mesh.add_surface_from_arrays()` inside `rebuild_mesh()`). Built correctly (verified vertex
  counts, material, no script errors) but rendered as large, wildly-misplaced black triangles
  smeared across the whole torso. Root cause: `body_mesh_instance` is skinned, and every surface on
  it needs its own BONES/WEIGHTS arrays or GPU skinning reads garbage attribute data for the
  mismatched one. Rebinding rigidly to the neck bone fixed the corruption, but the patch still never
  showed through anywhere a gap existed - the base surface's own format flags carry Godot's
  vertex-compression metadata (a packed vertex count in the high bits, not a boolean flag), and a
  differently-sized surface sharing that format silently failed to render. Abandoned in favor of a
  separate, unskinned `MeshInstance3D` in world space (`_collar_bridge` in `character_creator.gd`,
  parented under `preview_root` at identity transform) - doesn't follow animation, an acceptable
  simplification for this still-debug-only outfit system.
- Even as a standalone mesh it initially rendered solid black: the outfit's cloth material's albedo
  comes from a texture, not `albedo_color` (confirmed: `albedo_color` read back as plain white), so
  the fan needed placeholder UVs even though texture detail doesn't matter here - without them the
  shader sampled undefined/black. Fixing the UVs alone still left it rendering near-black from most
  angles: the fan's per-triangle normals (a simple cross product per triangle, not guaranteed
  outward-facing for every loop found this way) aren't flipped for the back-facing side even with
  culling disabled, so per-pixel lighting shaded it as if facing away from every light. Setting the
  material `SHADING_MODE_UNSHADED` sidesteps the question entirely - the patch doesn't need dynamic
  lighting response, just to blend in, and it does.

Verified live on both bodies: Male Peasant's tip sliver is gone (clean cloth-colored fill, no red, no
void, confirmed with real materials AND with debug colors, where the bridge - a separate node,
unaffected by the skin mesh's `material_override` - correctly shows its own true color instead of the
debug red/blue), Female Peasant is clean with no regressions, and Male Ranger (a differently-shaped
collar with no V-tip) renders unaffected - the bridge only ever appears where something would
otherwise be missing.

## Hide Clothes toggle

Also added at the user's request: a checkbox in `ui/character_creator.gd` next to "Debug colors" that
hides the outfit mesh entirely (`_preview_outfit.visible = false`), leaving just the masked base body
- useful for checking mask boundaries directly against skin without clothing occluding anything. Does
not force a mesh rebuild (just toggles `Node3D.visible`), and correctly re-applies its own state
whenever `_rebuild_outfit()` does run for another reason (changing outfit/body/skin tone).

## Test harness

`tests/manual/outfits/outfit_coverage_comparison.tscn`: three columns (FULL BODY masked / CLOTHES ONLY
/ FULL BODY + CLOTHES masked), `P` cycles which one is shown full-screen, left-drag orbits, mouse
wheel zooms. `OUTFIT_SCENE`/body swapped by editing the top-of-file consts.

## Next work

1. Inspect the remaining thin outer-thigh body line; it is not marked as an intersecting triangle,
   so the next check must sample body coverage rather than repeat garment-edge intersection tests.
2. Visually confirm that the 4 cm grid remains usable and responsive in Character Creator.
3. Exercise saved profiles after the density change; handle identity is vertex-based, so existing
   edits should load unchanged.
4. Author proper cloth-weight vertex colors in Blender instead of deriving them from vertex height.
5. Retest shirt/pants collision through representative spine, hip, and leg animations.
6. Diagnose or patch the upstream RenderingDevice teardown errors before enabling the solver in
   Character Creator or gameplay.
7. Keep body masking as the stable fallback until the animated fitting/cloth path passes those tests.

## Superseded work: shrinkwrap-conform fitting (do not resume without a reason)

An earlier, much longer effort tried to solve body/cloth clipping by deforming the *clothing* mesh to
clear the body, first as an offline Blender pipeline (`tools/outfit_pipeline/fit_outfit_to_body.py`),
then ported to run live in Godot (`tools/outfit_pipeline/runtime_cloth_fitter.gd`,
`debug_compare_distances.py`). Both are left on disk, unused, not deleted - there's real, working
technical content in them (a spatial-hash nearest-point search, closest-point-on-triangle math, mesh
subdivision with correct bone-weight merging) that might be useful again someday, but neither is
wired into anything and neither should be revisited unless bone-region masking turns out to be
insufficient for some future outfit that doesn't cleanly cover whole limbs.

The short version of why this took so long and is being set aside: the underlying shrinkwrap-conform
algorithm was eventually verified correct (matched Blender's own distance statistics almost exactly),
and a real algorithmic bug in the corrective pass was found and fixed (marching along a fixed
direction couldn't always escape a concave fold; direct repositioning toward whatever's currently
nearest fixed it, cutting clipping from ~40% to 0-10% per mesh) - but the whole pursuit was solving a
problem that didn't need to exist. The full history of dead ends, root-cause analyses, and fixes along
the way (including two genuine Godot rendering bugs found in the verification harness itself - a
discard shader on one surface suppressing a sibling surface's rendering in a specific SubViewport
setup, and an unreliable alpha channel on a transparent-background viewport's output texture) is not
reproduced here; read prior git history / session transcripts if picking this back up.

**Re-verified, still broken, in a later session** (prompted by wanting a truly generic fix instead of
the collar-specific bridge/wedge system below): rendered the already-generated offline output
(`assets/models/modular_outfits_fantasy/fitted/Male_Peasant_Fitted.gltf`) directly - a torn, holed
collar and blotchy shoulder shading, confirming this is a real, unresolved defect in the algorithm's
output, not just a stale claim. Separately live-tested the GDScript port
(`runtime_cloth_fitter.gd`) on the same outfit: an even more severe, different bug - the fitted shirt
renders almost entirely invisible (a couple of stray triangles) even with smoothing fully disabled,
isolated down to the core per-vertex push step itself (subdivision alone renders correctly; stripping
all bone/skinning data made no difference either, ruling out a skinning cause). Root cause not found -
each sampled vertex's own push computation looks individually reasonable, so the bug likely lives in
how neighboring pushed vertices interact at scale, not in any single vertex's math. Also confirmed
impractically slow as currently written: ~30 seconds to fit one 4-piece outfit (dominated by
`_subdivide_arrays()`'s 2 levels, ~6k vertices to ~115k). Given a working, verified alternative
already exists (the boundary bridge + wider auto-trim margin above, and the generic cloth-inflate
slider below), this path is being left alone again - if picked up a third time, the push-step bug
needs to be found first (try a synthetic case - a subdivided plane over a sphere - to isolate it from
this asset's own topology).

## Cloth push-out (generic alternative to per-outfit tuning)

A simpler, fully generic alternative to shrinkwrap-conform fitting, added directly to
`ui/character_creator.gd`: `_apply_cloth_inflate()` pushes every vertex of the outfit's own mesh
outward along its own already-authored vertex normal by a single tunable amount (new "Cloth
Push-Out (Debug)" slider, 0.0-0.03, next to "Cloth Coverage Distance"). Unlike shrinkwrap-conform,
it has no nearest-point search, no subdivision, no smoothing pass - it doesn't know the body's shape
at all, so it needs zero per-outfit tuning and is effectively instant. Applied in `_rebuild_outfit()`
right after the outfit instance is added to the tree, before `BodyRegionMask.compute_mask_state()`
runs, so the collar-hole/coverage-distance detection sees the already-inflated cloth boundary.
Reuses each surface's own original `format_flags` when rebuilding - passing a mismatched format for
a surface's actual vertex layout is what silently broke rendering the first two times a new surface
was built this session (see `build_boundary_bridge_mesh()`'s own history above), so this was
deliberately handled correctly from the start rather than rediscovered the hard way again.

First version pushed every vertex equally regardless of position - verified live at 0.01 (1cm) with
zero red slivers on the collar, but a user screenshot caught the real problem: sleeves, sides, the
whole torso got visibly bulkier too, not just the collar fringe that actually needed it. Fixed by
weighting the push with `_boundary_proximity_weights()`: 1.0 right at one of the surface's own open
edges (an edge used by only one triangle - collar, cuffs, hems), tapering to 0.0 by
`CLOTH_INFLATE_FALLOFF_DISTANCE` (0.06) away from the nearest one - still fully generic, since
boundary edges are the garment's own topology, nothing here looks at the body. Needed the same
position-based edge dedup as `BodyRegionMask.BOUNDARY_POSITION_EPSILON` (a hard-shading seam looks
identical to a real boundary edge if matched by raw vertex index), though that alone didn't explain
everything found next.

Verified live on Male Peasant at 0.015: torso/sleeves/waist back to their original, un-inflated
shape, only the collar fringe visibly thicker - but a closer look at the collar found a *new*, small
defect: two tiny red slivers right where the collar meets a separate shoulder-trim/strap piece,
absent at 0.0 and unaffected by the position-dedup fix, so not a boundary-detection bug. Most likely
cause: the collar and the trim piece are meant to sit exactly coincident at that seam, but each
surface's own vertices there get pushed along that surface's *own* normal - if the collar's normal
and the trim's normal point in different directions at the same seam point (very plausible for two
differently-oriented pieces meeting edge-to-edge), inflating both pulls them apart instead of moving
them together, opening a hairline gap. Not chased further given the tool is deliberately a manual,
tunable slider, not an automatic fix: at 0.006 the same collar fringe still visibly thickens with no
red anywhere, so the practical answer is to dial in the amount that clears a given outfit's actual
gaps without reaching whatever amount opens a new one at that outfit's own trim seams - exactly the
manual, per-outfit judgment call the slider exists for.

Rejected by the user after this verification: even at the smaller amounts that avoid the trim-seam
slivers, the cloth is visibly thicker - "the cloth looks thinker, maybe we need to try another
strategy." The core objection is that pushing the *cloth* outward always changes the garment's own
silhouette, which is visible by definition. The slider (`InflateRow`/`InflateSlider` in
`character_creator.tscn`) is left in place as a debug control, not wired into the real per-outfit
pipeline. See "Skin pull-in" below for the approach adopted instead.

## Skin pull-in (adopted - corrects clipping without changing the garment's silhouette)

Rather than pushing the outfit's cloth outward (always visible - see "Cloth push-out" above), this
pulls the *skin* inward: `BodyRegionMask._pull_clipping_vertices_inward()` (in
`tools/outfit_pipeline/body_region_mask.gd`) finds body vertices that poke outward past the nearest
cloth surface (same signed-distance-past-nearest-surface test as `_wedge_vertex_data()`'s own `clips`
computation) and moves them straight back along that cloth's own normal, just enough to sit
`CLIP_CORRECTION_MARGIN` (3mm) behind it. A few iterations run since moving a vertex can change which
cloth triangle is nearest to it afterward. Invisible by construction: this fringe of skin is already
thin and hidden by default, with no independent silhouette of its own to distort, unlike the cloth.

Restricted to the same eligibility `_apply_wedge_trim()` already uses (`collar_fringe` bone or
`wedge_neck` bone) - an early version checked every visible vertex with no restriction and wrongly
"corrected" 217 face/hand/forearm vertices near the collar trim that were never clipping in the first
place (a face poking out above a collar is normal, not a defect; only vertices in the collar-fringe/
neck column are ever eligible). Also only considers vertices where `vertex_hidden[v] == 0`, since a
hidden vertex's position doesn't render (except through the long-standing "a triangle survives if not
all three corners are hidden" boundary-keep rule, which is a pre-existing, separate concern this
correction doesn't need to solve).

**Verified working alongside the real (not forced) wedge-trim system**, on both Male and Female
Peasant: rendered with debug colors on and off, comparing wedge-trim disabled (forced to 1.0, i.e. no
trim - used only for isolating this correction during development) against wedge-trim at its real,
auto-computed values. With wedge-trim forced off, a large red V of exposed chest skin appeared (wedge
trim's own job, not this correction's) plus scattered red patches - none of that is this correction's
concern. With wedge-trim at its real values *and* this correction active, the collar comes back
almost entirely clean on both bodies. **This does not replace wedge-trim** - the two solve different
problems (wedge-trim decides how much skin the opening *should* show; this corrects genuine clipping
within whatever ends up visible) and both remain in the pipeline.

**Known remaining defect, not fixed**: two small red slivers persist right at the bottom tip of the
collar V, caught by the user from a live screenshot after the above was reported as clean - a real
miss on my part, not a placket design detail as first (wrongly) claimed. Root-caused via a probe
script: the two slivers come from vertices wedge-trim marks HIDDEN (they genuinely clip) whose
triangles still render anyway because each shares its other two corners with a VISIBLE vertex - the
same "a triangle survives unless all three corners are hidden" rule documented throughout this file.
`_pull_clipping_vertices_inward()` skips hidden vertices by design, so it never touches these.

Tried the direct fix - correcting hidden vertices too, not just visible ones - and confirmed via a
pixel diff between renders that it made the slivers WORSE, not gone: a cloth cut edge's (a raw
boundary triangle, not interior fabric) own normal doesn't reliably point "away from camera" the way
mid-garment fabric does, so nudging a hidden collar-edge vertex along it can swing it further into
view instead of further behind the fabric. Reverted that change - confirmed via a zero-diff render
that the code is back to exactly the prior (known, documented-here) state. Left open for now; the
next attempt should probably use the SKIN's own normal (not the nearest cloth triangle's) to decide
which direction is "further into the body," or restrict correction to hidden vertices whose nearest
cloth point is on an interior triangle, not a boundary/cut-edge one.

## Removed approach (do not restore without a materially different model)

An even earlier automatic body-coverage mask system (UV-space proximity/ray mask baking,
per-body/per-outfit PNG visibility masks, a runtime body-mask shader, Head/Neck ownership exceptions,
runtime UV erosion/dilation) was removed at the user's request: broad masks hid the body but erased
visible skin near open collars, narrow masks preserved junctions but exposed body through clothing,
dilation suppressed pinholes by eating more junction skin, and results were inconsistent between
viewing angles. Bone-region masking (this file's current approach) is a materially different model -
discrete, named skeletal regions instead of continuous UV/proximity fields - so it doesn't carry the
same failure modes, but keep this history in mind if it ever seems to be drifting back toward
per-pixel/per-vertex proximity logic.

## Verification

Run:

```sh
scripts/check.sh
git diff --check
```

No commit has been requested.
