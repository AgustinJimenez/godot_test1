# Open-Source Autorigger Code Investigation

**Date:** 2026-07-19; updated 2026-07-20
**Status:** Active reference; deterministic findings are being implemented incrementally.

## Purpose

Identify implementation ideas from open-source automatic-rigging projects that
can improve Character Editor's native humanoid rig generator. The goal of this
pass was to inspect source code for reusable algorithms and boundaries, not to
replace the editor with an external service or machine-learning runtime.

## Current Project Baseline

`tools/character_editor/character_editor_autorigger.gd` currently:

- creates a fixed MotusMan-compatible humanoid hierarchy from normalized body
  bounds;
- allows generated joint positions to be adjusted and saved;
- weights vertices against the final edited parent-child bone segments;
- retains up to four normalized influences for Godot export; and
- smooths candidate weights across indexed triangle neighbors before pruning;
- emits a Godot `Skeleton3D`, `Skin`, and weighted `ArrayMesh`.

The remaining limitations are landmark inference from coarse cross-sections,
the lack of an interior/geodesic distance field, and limited inspection of the
resulting weights. Euclidean segment distance can still leak between nearby
anatomical regions within one connected surface, especially around the armpits,
hips, layered clothing, or fingers.

### Vertical landmark failure found on Zombie1

The first geometry-fitting pass was incomplete in one important way: arm,
center, and leg fitting sampled mesh cross-sections but preserved the original
fixed Y coordinate. Zombie1 therefore kept `Hips` and both upper-leg origins at
37% of total height even though their X/Z centers followed the mesh. The
side-by-side rig reference made the discrepancy visible to a person but was not
registered to the character and supplied no numeric validation.

The generator now builds a horizontal silhouette profile through the lower
torso. The fifth-percentile distance from the center plane detects where two leg
regions merge at the crotch; the ninetieth-percentile half-width finds the
narrow waist above it. Their midpoint is blended with a conservative humanoid
prior because layered clothing can introduce false center-plane geometry. The
detector is accepted only when crotch, waist, and separation fall inside broad
humanoid bounds; otherwise generation reports a fallback result.

For Zombie1 this measures crotch at 42%, waist at 62%, and places the pelvis at
51.75% instead of 37%. Checks against UAL1, UAL2, MotusMan, and a clothed Mixamo
zombie established the fallback range; these known rigged assets should become
a persistent landmark-error benchmark before expanding inference to every
joint. Generation returns the measurements in `landmarks`, and Character Editor
stores them with the character profile and identifies geometry/fallback status.

## 2026-07-20 Follow-up: Project Classification

The additional projects are not interchangeable. They solve two distinct
problems:

- **Rigify, GameRig, CloudRig, and mGear** construct animator-facing control
  rigs from an already placed guide/metarig. They are useful references for
  modular rig definitions, symmetry, IK/FK controls, validation, and export
  cleanup, but they do not infer reliable joints and skin weights from an
  arbitrary mesh.
- **UniRig and RigAnything** infer skeletons and skinning from geometry. Their
  quality comes primarily from learned PyTorch models and trained checkpoints,
  not from a small deterministic algorithm that can be translated directly to
  GDScript.

UniRig is MIT licensed, but its published inference stack requires Python,
PyTorch, sparse-convolution dependencies, and a CUDA GPU. It is a plausible
future optional external provider, not an appropriate mandatory runtime for the
Godot editor. RigAnything's released code is under Adobe's noncommercial
research license, so its implementation must not be copied into this project.
Its general post-processing sequence can still be independently reproduced:
keep several candidate influences, blend weights over mesh neighbors, discard
weak values, then normalize.

The Maya-oriented entries (autoRigger, Riggery, GT Tools, Skinner) are likewise
host-application tooling rather than mesh-to-game-rig solvers. They do not
remove the need for landmark inference and skin binding in Character Editor.

Primary references checked in this follow-up:

- UniRig source and MIT license: https://github.com/VAST-AI-Research/UniRig
- RigAnything project description: https://research.adobe.com/publication/riganything-template-free-autoregressive-rigging-for-diverse-3d-assets/
- Rigify manual: https://docs.blender.org/manual/en/4.1/addons/rigging/rigify/index.html
- CloudRig source: https://gitlab.com/blender/CloudRig
- mGear source: https://github.com/mgear-dev/mgear

## Projects Inspected

### SkinTokens / TokenRig

- Repository: https://github.com/VAST-AI-Research/SkinTokens
- License: MIT
- Relevant source:
  `src/data/vertex_group.py`, `src/rig_package/info/voxel.py`, and
  `src/rig_package/utils.py`

The learned model is not useful as native Godot code, but its deterministic
voxel-skinning stage is directly relevant. It:

1. samples several points along every parent-child bone segment;
2. constructs a graph containing triangle edges, nearby surface vertices, and
   occupied interior voxels;
3. calculates shortest-path distances from bone samples to mesh vertices;
4. converts those distances into smooth influence values; and
5. normalizes all influences per vertex.

This avoids a major weakness of Euclidean weighting: influence cannot jump
straight through empty space between nearby but anatomically separate parts.

### UniRig

- Repository: https://github.com/VAST-AI-Research/UniRig
- License: MIT
- Relevant source: `src/data/vertex_group.py`, `src/data/exporter.py`, and
  `src/tokenizer/spec.py`

UniRig uses a similar mesh/voxel graph for geometric skinning features. Its
exporter supplies two useful finalization rules: retain a bounded number of the
strongest vertex groups and normalize the retained weights before export. Its
skeleton representation also treats hierarchy construction and leaf-tail
generation as explicit cleanup stages rather than assuming predicted joints
already form an exportable armature.

### RigNet

- Repository: https://github.com/zhan-xu/RigNet
- License: GPLv3 or separate commercial license
- Relevant source: `quick_start.py`, `utils/mst_utils.py`, and
  `run_skinning.py`

Useful concepts from RigNet include:

- rejecting predicted joints outside a voxelized mesh;
- sampling along a proposed bone and increasing its hierarchy cost when much of
  the segment lies outside the mesh;
- explicitly reflecting candidates and constructing symmetric left/right
  relationships;
- smoothing weights across one-ring mesh neighbors;
- removing weak influences relative to the strongest influence; and
- renormalizing after filtering.

The GPL implementation must not be copied into this project without a license
compatibility decision. The general algorithms can still guide an independent
implementation.

### Puppeteer

- Repository: https://github.com/Seed3D/Puppeteer
- License: Apache-2.0
- Relevant source: `skeleton/`, `skinning/`, and `export.py`

Puppeteer's skeleton and skin predictions are primarily learned-model code, so
there is less suitable for a small native GDScript implementation. Its useful
architectural lesson is to keep skeleton generation, skinning, and export as
separate pipeline stages with inspectable intermediate results.

## Ideas Worth Adopting

### 1. Weight Against Bone Segments

For every parent-child pair, compute the closest point on the segment for each
vertex and derive an influence from that distance. Use the actual edited joint
positions. This is the smallest improvement with the highest immediate value.

Retain anatomical eligibility masks so, for example, a vertex in the head does
not become eligible for a hand merely because of an unusual pose or topology.

### 2. Normalize the Export Contract

For each vertex:

1. discard negligible influences;
2. keep the strongest four influences supported by Godot's mesh format;
3. ensure at least one fallback influence remains; and
4. normalize the retained values so their sum is one.

This should be a dedicated finalization function independent of how candidate
weights were produced.

### 3. Smooth Across Mesh Adjacency (implemented)

Build vertex adjacency from triangle indices and blend each vertex's candidate
weights with its one-ring neighbors. Two conservative passes at 25% neighbor
influence reduce abrupt deformation boundaries without requiring a full voxel
solver.

Smoothing must run before top-four pruning and normalization. It should not
cross disconnected mesh surfaces unless that behavior is explicitly enabled.

### 4. Add Symmetric Joint Editing

Provide an optional **Mirror joints** mode. Moving a named left/right joint
updates its counterpart across the model's center plane. Center-chain joints
remain constrained to that plane when symmetry is enabled.

This is both an authoring convenience and a way to keep the initial skinning
input coherent.

### 5. Validate Bone Containment

Sample points along each bone and test them against an approximate mesh
interior. Initially this can be a warning rather than an automatic correction:

- normal bone: current cyan visualization;
- partly outside: amber;
- mostly outside: red.

A coarse voxel occupancy grid or ray parity test can supply the containment
query. This validation is also useful before a more expensive skinning pass.

### 6. Add Weight Inspection

The editor needs a way to inspect generated results before more sophisticated
weighting is worthwhile. Selecting a bone should optionally color the mesh by
that bone's weight and report the number of influenced vertices. This makes
weight leakage and hard boundaries visible without playing many animations.

### 7. Consider Voxel-Geodesic Weighting Later

A SkinTokens-style interior graph is the strongest non-ML algorithm found in
this investigation. A native version could:

- voxelize the mesh at a configurable coarse resolution;
- flood-fill or otherwise identify interior cells;
- connect mesh vertices, interior cells, and bone samples;
- run bounded multi-source Dijkstra searches; and
- convert path distances into weights.

This is more expensive in CPU time and memory than segment weighting. It should
be a later optional quality mode, ideally executed off the main thread with
progress and cancellation.

## Suggested Implementation Order

1. Make weights depend on edited bone segments. **Done.**
2. Add top-four pruning, fallback handling, and normalization. **Done.**
3. Add mesh-adjacency smoothing per connected surface/component. **Done.**
4. Add weight heat-map inspection.
5. Add a persistent known-rig landmark benchmark and viewport diagnostic bands.
6. Add mirrored joint editing and bone-containment warnings.
7. Prototype optional voxel-geodesic weighting only if the earlier stages still
   produce unacceptable deformation around close limbs or layered geometry.

## Non-Goals From This Investigation

- Embedding PyTorch, CUDA, UniRig, SkinTokens, or Puppeteer into Godot.
- Claiming production-quality automatic rigging for arbitrary creatures.
- Copying GPL RigNet code into the project.
- Removing Blender or other external tools as fallback options for difficult
  meshes and final weight cleanup.

The immediate target remains a transparent, editable first-pass humanoid rig
whose generated weights actually follow the joints authored in Character
Editor.
