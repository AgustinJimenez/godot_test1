"""Push garment vertices outside a base body with a configurable clearance.

Run this through Blender, not regular Python:

blender --background --python tools/outfit_pipeline/fit_outfit_to_body.py -- \
  --body path/to/body.gltf --body-object BodyMesh \
  --outfit path/to/outfit.gltf --output path/to/fitted.glb

The source assets are never modified. Vertices used only by excluded skin-material primitives are
left untouched. This is a rest-pose fitting pass, not cloth simulation.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--body", required=True)
    parser.add_argument("--body-object", required=True)
    parser.add_argument("--outfit", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--clearance", type=float, default=0.015)
    parser.add_argument("--maximum-distance", type=float, default=0.08)
    # 0.0 (perpendicular) rather than a positive minimum: on Male Peasant, 0.25 left a visible
    # gap at the underarm seam where the garment surface bends sharply relative to the body, and
    # dropping the requirement to "not facing away from the body" closed most of it with no
    # observed silhouette inflation. Still excludes truly backward-facing normals (e.g. a garment's
    # inner lining), just not merely-steep ones.
    parser.add_argument("--minimum-normal-alignment", type=float, default=0.0)
    # 2 rather than 1: seams (e.g. where a boot cuff meets the pant leg) can be sparse enough that
    # a single subdivision still leaves a gap between two individually-corrected vertices.
    parser.add_argument("--subdivision-levels", type=int, default=2)
    parser.add_argument(
        "--exclude-material-patterns",
        default="Regular_Male,Regular_Female",
    )
    # Each moved vertex is pushed along its own normal independently, so without relaxation
    # neighboring vertices can receive different push distances and the surface frays into
    # spikes. These average each moved vertex toward its mesh-adjacent neighbors afterward.
    parser.add_argument("--smoothing-iterations", type=int, default=3)
    parser.add_argument("--smoothing-factor", type=float, default=0.5)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])


def import_gltf(path: str) -> list[bpy.types.Object]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(Path(path).resolve()))
    return [obj for obj in bpy.data.objects if obj not in before]


def build_body_bvh(body: bpy.types.Object) -> BVHTree:
    mesh = body.data
    mesh.calc_loop_triangles()
    vertices = [body.matrix_world @ vertex.co for vertex in mesh.vertices]
    triangles = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
    return BVHTree.FromPolygons(vertices, triangles, all_triangles=True)


def clothing_triangles(
    mesh: bpy.types.Mesh, excluded_material_patterns: list[str]
) -> list[tuple[int, int, int]]:
    mesh.calc_loop_triangles()
    result: list[tuple[int, int, int]] = []
    for triangle in mesh.loop_triangles:
        material = (
            mesh.materials[triangle.material_index]
            if triangle.material_index < len(mesh.materials)
            else None
        )
        material_name = material.name.lower() if material is not None else ""
        if any(pattern in material_name for pattern in excluded_material_patterns):
            continue
        result.append(tuple(triangle.vertices))
    return result


def subdivide_without_smoothing(obj: bpy.types.Object, levels: int) -> None:
    if levels <= 0:
        return
    modifier = obj.modifiers.new(name="OutfitFitSubdivision", type="SUBSURF")
    modifier.subdivision_type = "SIMPLE"
    modifier.levels = levels
    modifier.render_levels = levels
    while obj.modifiers.find(modifier.name) > 0:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def march_until_clear(
    position: Vector,
    world_normal: Vector,
    body_bvh: BVHTree,
    clearance: float,
    maximum_distance: float,
    step: float,
    max_steps: int,
) -> tuple[Vector, float]:
    push = 0.0
    for _ in range(max_steps):
        nearest = body_bvh.find_nearest(position, maximum_distance)
        if nearest[0] is None:
            break
        body_position, body_normal = nearest[0], nearest[1].normalized()
        if (position - body_position).dot(body_normal) >= clearance:
            break
        position += world_normal * step
        push += step
        if push >= maximum_distance:
            break
    return position, push


def vertex_adjacency(mesh: bpy.types.Mesh) -> dict[int, list[int]]:
    # Mesh-edge adjacency alone misses UV seams: garment meshes commonly have duplicate,
    # unwelded vertices at panel boundaries (same 3D position, different vertex index) so the
    # two sides of the seam can have different UVs. Those duplicates aren't edge-connected to
    # each other, so smoothing based on edges alone never blends them - each side of the seam
    # keeps whatever independent push it got, which is exactly what still showed up as spiking
    # at the collar and cuffs after edge-only smoothing fixed the (seamless) torso and underarm.
    # Position-coincidence adjacency below connects those pairs too, purely for smoothing.
    adjacency: dict[int, list[int]] = {}
    for edge in mesh.edges:
        a, b = edge.vertices[0], edge.vertices[1]
        adjacency.setdefault(a, []).append(b)
        adjacency.setdefault(b, []).append(a)

    position_buckets: dict[tuple[int, int, int], list[int]] = {}
    epsilon = 1e-5
    for vertex in mesh.vertices:
        key = (
            round(vertex.co.x / epsilon),
            round(vertex.co.y / epsilon),
            round(vertex.co.z / epsilon),
        )
        position_buckets.setdefault(key, []).append(vertex.index)
    for coincident in position_buckets.values():
        if len(coincident) < 2:
            continue
        for vertex_index in coincident:
            neighbors = adjacency.setdefault(vertex_index, [])
            neighbors.extend(other for other in coincident if other != vertex_index)

    return adjacency


def fit_mesh(
    obj: bpy.types.Object,
    body_bvh: BVHTree,
    excluded_material_patterns: list[str],
    clearance: float,
    maximum_distance: float,
    minimum_normal_alignment: float,
    smoothing_iterations: int,
    smoothing_factor: float,
) -> tuple[int, int, float]:
    # Pushes along the garment vertex's OWN normal, not the nearest body point's normal. At a
    # concave junction (armpit, boot-cuff-to-pant-leg) two body regions curve toward each other,
    # so the nearest body point's normal doesn't reliably point in a direction that clears the
    # body's surrounding curvature - re-running that same correction gave the identical (still
    # insufficient) result every time, since the search kept landing on the same unhelpful normal.
    # The garment's own normal stays a stable "outward from cloth" direction even inside a fold, so
    # this marches the vertex along it in small steps, re-querying the body BVH each step (the
    # nearest point and its normal change as the vertex moves, unlike a single-shot push).
    #
    # Each vertex is still pushed independently, which by itself frays the surface: mesh-adjacent
    # vertices can get different push distances with no coherence between them. A Laplacian-style
    # relaxation pass afterward pulls each moved vertex toward the average of its mesh neighbors
    # (moved and unmoved alike), which restores a coherent surface but can pull a vertex back under
    # the clearance threshold. The fix is a second marching pass, not a closed-form push along the
    # vertex normal by the clearance shortfall: that formula only fully restores clearance when the
    # vertex normal is parallel to the body normal, which is exactly what fails at the concave
    # junctions this whole approach exists to handle.
    mesh = obj.data
    triangles = clothing_triangles(mesh, excluded_material_patterns)
    candidates = {index for triangle in triangles for index in triangle}
    inverse_transform = obj.matrix_world.inverted()
    normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
    world_positions = [obj.matrix_world @ vertex.co for vertex in mesh.vertices]

    step = clearance / 4.0
    max_steps = int(maximum_distance / step) + 1
    moved: set[int] = set()
    maximum_push = 0.0
    for vertex_index in candidates:
        vertex = mesh.vertices[vertex_index]
        world_position = world_positions[vertex_index]
        world_normal = (normal_matrix @ vertex.normal).normalized()
        nearest = body_bvh.find_nearest(world_position, maximum_distance)
        if nearest[0] is None:
            continue
        if world_normal.dot(nearest[1].normalized()) < minimum_normal_alignment:
            continue
        position, push = march_until_clear(
            world_position.copy(), world_normal, body_bvh, clearance, maximum_distance, step, max_steps
        )
        if push <= 0.0:
            continue
        world_positions[vertex_index] = position
        moved.add(vertex_index)
        maximum_push = max(maximum_push, push)

    if moved and smoothing_iterations > 0:
        adjacency = vertex_adjacency(mesh)
        for _ in range(smoothing_iterations):
            relaxed: dict[int, Vector] = {}
            for vertex_index in moved:
                neighbors = adjacency.get(vertex_index)
                if not neighbors:
                    continue
                average = Vector((0.0, 0.0, 0.0))
                for neighbor_index in neighbors:
                    average += world_positions[neighbor_index]
                average /= len(neighbors)
                relaxed[vertex_index] = world_positions[vertex_index].lerp(average, smoothing_factor)
            for vertex_index, position in relaxed.items():
                world_positions[vertex_index] = position

        for vertex_index in moved:
            vertex = mesh.vertices[vertex_index]
            world_normal = (normal_matrix @ vertex.normal).normalized()
            position, _ = march_until_clear(
                world_positions[vertex_index], world_normal, body_bvh, clearance, maximum_distance, step, max_steps
            )
            world_positions[vertex_index] = position

    for vertex_index in moved:
        mesh.vertices[vertex_index].co = inverse_transform @ world_positions[vertex_index]
    mesh.update()
    return len(candidates), len(moved), maximum_push


def select_for_export(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    pending = list(objects)
    selected = set(objects)
    while pending:
        parent = pending.pop().parent
        if parent is not None and parent not in selected:
            selected.add(parent)
            pending.append(parent)
    for obj in selected:
        obj.select_set(True)


def reuse_source_textures(output: Path, outfit: Path) -> None:
    document = json.loads(output.read_text())
    changed = False
    for image in document.get("images", []):
        uri = image.get("uri", "")
        if not uri or uri.startswith("data:"):
            continue
        exported_texture = output.parent / uri
        source_texture = outfit.parent / Path(uri).name
        if not source_texture.is_file():
            continue
        image["uri"] = os.path.relpath(source_texture, output.parent)
        changed = True
        if exported_texture.resolve() != source_texture.resolve() and exported_texture.is_file():
            exported_texture.unlink()
    if changed:
        output.write_text(json.dumps(document, separators=(",", ":")))


def main() -> None:
    args = parse_args()
    if args.clearance <= 0.0:
        raise ValueError("--clearance must be positive")
    if args.maximum_distance < args.clearance:
        raise ValueError("--maximum-distance must be at least --clearance")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    body_objects = import_gltf(args.body)
    body = next((obj for obj in body_objects if obj.name == args.body_object), None)
    if body is None:
        names = ", ".join(obj.name for obj in body_objects if obj.type == "MESH")
        raise RuntimeError(f"Body mesh {args.body_object!r} not found; imported meshes: {names}")
    body_bvh = build_body_bvh(body)

    outfit_objects = import_gltf(args.outfit)
    excluded_material_patterns = [
        pattern.strip().lower()
        for pattern in args.exclude_material_patterns.split(",")
        if pattern.strip()
    ]
    total_candidates = 0
    total_moved = 0
    maximum_push = 0.0
    for obj in outfit_objects:
        if obj.type != "MESH":
            continue
        subdivide_without_smoothing(obj, args.subdivision_levels)
        candidates, moved, mesh_maximum_push = fit_mesh(
            obj,
            body_bvh,
            excluded_material_patterns,
            args.clearance,
            args.maximum_distance,
            args.minimum_normal_alignment,
            args.smoothing_iterations,
            args.smoothing_factor,
        )
        total_candidates += candidates
        total_moved += moved
        maximum_push = max(maximum_push, mesh_maximum_push)

    output = Path(args.output).resolve()
    if output.suffix.lower() != ".gltf":
        raise ValueError("--output must use .gltf so the derived mesh can reuse source textures")
    output.parent.mkdir(parents=True, exist_ok=True)
    select_for_export(outfit_objects)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_animations=False,
        export_keep_originals=True,
    )
    reuse_source_textures(output, Path(args.outfit).resolve())
    print(
        f"FITTED_OUTFIT:{output} candidates={total_candidates} moved={total_moved} "
        f"maximum_push={maximum_push:.6f} clearance={args.clearance:.6f} "
        f"subdivision_levels={args.subdivision_levels}"
    )


if __name__ == "__main__":
    main()
