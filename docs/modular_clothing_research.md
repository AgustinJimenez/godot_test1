# Modular Clothing Body Coverage

## Problem

The Quaternius outfit pack expects a separate character head, but the free Universal Base
Characters pack supplies a single full-body skin surface. Drawing both complete meshes causes skin
to intersect clothing; reducing the body to only its dominant Head/Neck skinning region can leave
open necklines without enough chest skin.

## Established Workflows

- Epic's modular-character workflow splits a skeletal character into authored sections such as
  head, torso, and legs, then drives those parts from one skeleton.
- Blender's Mask modifier hides geometry using an authored vertex group or texture, including a
  smooth weight boundary.
- MakeHuman clothing assets carry a `Delete` vertex group for body vertices covered by a garment.
  Its authoring guide warns that a vertex should be deleted only when all faces containing it are
  hidden; deleting nearest vertices independently creates triangle-sized islands and holes.
- Godot spatial shaders support fragment discard and skinned-mesh inputs, so an imported coverage
  mask can be applied at runtime. Stencil masking exists but is experimental and cannot replace
  garment-authored body coverage in the opaque pass.

## Project Direction

1. Start from a diagnostic baseline that renders the complete base body plus clothes and discards
   only duplicate outfit-authored skin primitives.
2. Inspect intersections from front, rear, sides, top, and while deforming before defining any body
   removal boundary.
3. Prefer explicit garment-defined body-part replacement, authored modular body sections, or
   topology-aware triangle groups. These approaches make junction ownership stable under
   animation.
4. Do not restore the tested proximity/UV-mask system as-is. Broad coverage erased visible body at
   collars and cuffs; narrow coverage exposed body through clothes; dilation suppressed pinholes
   by consuming more junction skin; Neck exceptions alternated between black gaps and upper-back
   wedges.

## Sources

- Godot spatial shaders: https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/spatial_shader.html
- Epic modular characters: https://dev.epicgames.com/documentation/unreal-engine/working-with-modular-characters?application_version=4.27
- Blender Mask modifier: https://docs.blender.org/manual/en/4.1/modeling/modifiers/generate/mask.html
- MakeHuman clothing authoring: https://static.makehumancommunity.org/assets/creatingassets/makeclothes/clothes.html
